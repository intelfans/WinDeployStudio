#include <windows.h>

#include <imapi2.h>
#include <imapi2fs.h>
#include <oleauto.h>
#include <shlwapi.h>
#include <wrl/client.h>

#include <algorithm>
#include <cstdint>
#include <cwchar>
#include <iostream>
#include <string>
#include <thread>
#include <utility>
#include <vector>

using Microsoft::WRL::ComPtr;

namespace {

constexpr int kProtocolVersion = 1;
constexpr ULONG kTransferBufferSize = 4 * 1024 * 1024;

struct ReplacementFile {
  std::wstring source;
  std::wstring target_name;
};

struct Options {
  DWORD parent_pid = 0;
  std::wstring source_root;
  std::wstring output_path;
  std::wstring volume_label;
  std::wstring cancel_path;
  std::vector<ReplacementFile> replacements;
};

class ParentLifetimeGuard {
 public:
  ParentLifetimeGuard() = default;
  ParentLifetimeGuard(const ParentLifetimeGuard&) = delete;
  ParentLifetimeGuard& operator=(const ParentLifetimeGuard&) = delete;

  ~ParentLifetimeGuard() {
    if (stop_event_ != nullptr) {
      SetEvent(stop_event_);
    }
    if (monitor_.joinable()) {
      monitor_.join();
    }
    if (parent_ != nullptr) {
      CloseHandle(parent_);
    }
    if (stop_event_ != nullptr) {
      CloseHandle(stop_event_);
    }
  }

  bool Start(DWORD parent_pid) {
    if (parent_pid == 0 || parent_pid == GetCurrentProcessId()) {
      return false;
    }
    parent_ = OpenProcess(SYNCHRONIZE | PROCESS_QUERY_LIMITED_INFORMATION,
                          FALSE, parent_pid);
    if (parent_ == nullptr || WaitForSingleObject(parent_, 0) != WAIT_TIMEOUT) {
      return false;
    }
    stop_event_ = CreateEventW(nullptr, TRUE, FALSE, nullptr);
    if (stop_event_ == nullptr) {
      return false;
    }
    monitor_ = std::thread([this]() {
      HANDLE handles[] = {parent_, stop_event_};
      if (WaitForMultipleObjects(2, handles, FALSE, INFINITE) ==
          WAIT_OBJECT_0) {
        TerminateProcess(GetCurrentProcess(), ERROR_PROCESS_ABORTED);
      }
    });
    return true;
  }

 private:
  HANDLE parent_ = nullptr;
  HANDLE stop_event_ = nullptr;
  std::thread monitor_;
};

class ScopedBstr {
 public:
  explicit ScopedBstr(const std::wstring& value)
      : value_(SysAllocStringLen(value.data(),
                                 static_cast<UINT>(value.size()))) {}
  ~ScopedBstr() { SysFreeString(value_); }
  ScopedBstr(const ScopedBstr&) = delete;
  ScopedBstr& operator=(const ScopedBstr&) = delete;
  BSTR get() const { return value_; }
  bool valid() const { return value_ != nullptr; }

 private:
  BSTR value_ = nullptr;
};

void EmitState(const char* state, int percent) {
  std::cout << "STATE|" << state << "|" << percent << std::endl;
}

void EmitProgress(const char* state, int percent, std::uint64_t written,
                  std::uint64_t total) {
  std::cout << "PROGRESS|" << state << "|" << percent << "|" << written
            << "|" << total << std::endl;
}

void EmitError(const char* message, HRESULT result = S_OK) {
  std::cerr << message;
  if (FAILED(result)) {
    std::cerr << " (HRESULT=0x" << std::hex
              << static_cast<unsigned long>(result) << std::dec << ")";
  }
  std::cerr << std::endl;
}

bool IsCancelled(const std::wstring& cancel_path) {
  return !cancel_path.empty() &&
         GetFileAttributesW(cancel_path.c_str()) != INVALID_FILE_ATTRIBUTES;
}

bool IsRegularFile(const std::wstring& path) {
  const DWORD attributes = GetFileAttributesW(path.c_str());
  return attributes != INVALID_FILE_ATTRIBUTES &&
         (attributes & FILE_ATTRIBUTE_DIRECTORY) == 0 &&
         (attributes & FILE_ATTRIBUTE_REPARSE_POINT) == 0;
}

bool IsDirectory(const std::wstring& path) {
  const DWORD attributes = GetFileAttributesW(path.c_str());
  return attributes != INVALID_FILE_ATTRIBUTES &&
         (attributes & FILE_ATTRIBUTE_DIRECTORY) != 0 &&
         (attributes & FILE_ATTRIBUTE_REPARSE_POINT) == 0;
}

std::wstring JoinPath(const std::wstring& left, const std::wstring& right) {
  if (left.empty()) {
    return right;
  }
  if (left.back() == L'\\' || left.back() == L'/') {
    return left + right;
  }
  return left + L"\\" + right;
}

std::wstring FullPath(const std::wstring& value) {
  const DWORD length = GetFullPathNameW(value.c_str(), 0, nullptr, nullptr);
  if (length == 0) {
    return {};
  }
  std::vector<wchar_t> buffer(length + 1, L'\0');
  if (GetFullPathNameW(value.c_str(), static_cast<DWORD>(buffer.size()),
                       buffer.data(), nullptr) == 0) {
    return {};
  }
  std::wstring result(buffer.data());
  while (result.size() > 3 &&
         (result.back() == L'\\' || result.back() == L'/')) {
    result.pop_back();
  }
  return result;
}

std::wstring Lower(std::wstring value) {
  std::transform(value.begin(), value.end(), value.begin(),
                 [](wchar_t character) {
                   return static_cast<wchar_t>(towlower(character));
                 });
  return value;
}

bool IsPathInside(const std::wstring& child, const std::wstring& parent) {
  const std::wstring normalized_child = Lower(FullPath(child));
  std::wstring normalized_parent = Lower(FullPath(parent));
  if (normalized_child.empty() || normalized_parent.empty()) {
    return true;
  }
  normalized_parent.push_back(L'\\');
  return normalized_child.rfind(normalized_parent, 0) == 0;
}

bool IsSafeTargetName(const std::wstring& value) {
  if (value.empty() || value.size() > 64) {
    return false;
  }
  for (const wchar_t character : value) {
    const bool valid = (character >= L'a' && character <= L'z') ||
                       (character >= L'A' && character <= L'Z') ||
                       (character >= L'0' && character <= L'9') ||
                       character == L'.' || character == L'_' ||
                       character == L'-';
    if (!valid) {
      return false;
    }
  }
  return value != L"." && value != L"..";
}

bool ParseUnsigned(const wchar_t* value, DWORD* output) {
  if (value == nullptr || output == nullptr) {
    return false;
  }
  wchar_t* end = nullptr;
  const unsigned long parsed = std::wcstoul(value, &end, 10);
  if (end == value || *end != L'\0' || parsed == 0) {
    return false;
  }
  *output = static_cast<DWORD>(parsed);
  return true;
}

bool ParseOptions(int argc, wchar_t* argv[], Options* options) {
  if (options == nullptr) {
    return false;
  }
  for (int index = 1; index < argc; ++index) {
    const std::wstring argument = argv[index];
    if (argument == L"--parent-pid" && index + 1 < argc) {
      if (!ParseUnsigned(argv[++index], &options->parent_pid)) {
        return false;
      }
    } else if (argument == L"--source-root" && index + 1 < argc) {
      options->source_root = argv[++index];
    } else if (argument == L"--output" && index + 1 < argc) {
      options->output_path = argv[++index];
    } else if (argument == L"--volume-label" && index + 1 < argc) {
      options->volume_label = argv[++index];
    } else if (argument == L"--cancel" && index + 1 < argc) {
      options->cancel_path = argv[++index];
    } else if (argument == L"--replace-file" && index + 2 < argc) {
      options->replacements.push_back({argv[++index], argv[++index]});
    } else {
      return false;
    }
  }
  return options->parent_pid != 0 && !options->source_root.empty() &&
         !options->output_path.empty() && !options->volume_label.empty();
}

HRESULT OpenReadStream(const std::wstring& path, IStream** stream) {
  if (stream == nullptr) {
    return E_POINTER;
  }
  *stream = nullptr;
  return SHCreateStreamOnFileEx(path.c_str(), STGM_READ | STGM_SHARE_DENY_WRITE,
                                FILE_ATTRIBUTE_NORMAL, FALSE, nullptr, stream);
}

HRESULT CreateBootOption(const std::wstring& path, PlatformId platform,
                         IBootOptions** option, IStream** retained_stream) {
  if (option == nullptr || retained_stream == nullptr) {
    return E_POINTER;
  }
  *option = nullptr;
  *retained_stream = nullptr;
  ComPtr<IStream> stream;
  HRESULT result = OpenReadStream(path, &stream);
  if (FAILED(result)) {
    return result;
  }
  ComPtr<IBootOptions> boot;
  result = CoCreateInstance(CLSID_BootOptions, nullptr, CLSCTX_INPROC_SERVER,
                            IID_PPV_ARGS(&boot));
  if (FAILED(result)) {
    return result;
  }
  result = boot->AssignBootImage(stream.Get());
  if (FAILED(result)) {
    return result;
  }
  if (FAILED(result = boot->put_Emulation(EmulationNone)) ||
      FAILED(result = boot->put_PlatformId(platform))) {
    return result;
  }
  ScopedBstr manufacturer(L"WinDeploy Studio");
  if (!manufacturer.valid()) {
    return E_OUTOFMEMORY;
  }
  result = boot->put_Manufacturer(manufacturer.get());
  if (FAILED(result)) {
    return result;
  }
  *option = boot.Detach();
  *retained_stream = stream.Detach();
  return S_OK;
}

HRESULT ConfigureBootOptions(IFileSystemImage2* image,
                             const std::wstring& source_root,
                             bool* has_bios, bool* has_uefi,
                             std::vector<ComPtr<IStream>>* retained_streams) {
  if (image == nullptr || has_bios == nullptr || has_uefi == nullptr ||
      retained_streams == nullptr) {
    return E_POINTER;
  }
  std::wstring bios_path = JoinPath(source_root, L"boot\\etfsboot.com");
  std::wstring uefi_path =
      JoinPath(source_root, L"efi\\microsoft\\boot\\efisys.bin");
  if (!IsRegularFile(uefi_path)) {
    uefi_path = JoinPath(
        source_root, L"efi\\microsoft\\boot\\efisys_noprompt.bin");
  }

  std::vector<ComPtr<IBootOptions>> boot_options;
  for (const auto& entry :
       std::vector<std::pair<std::wstring, PlatformId>>{
           {bios_path, PlatformX86}, {uefi_path, PlatformEFI}}) {
    if (!IsRegularFile(entry.first)) {
      continue;
    }
    ComPtr<IBootOptions> option;
    ComPtr<IStream> stream;
    HRESULT result = CreateBootOption(entry.first, entry.second, &option,
                                      &stream);
    if (FAILED(result)) {
      return result;
    }
    if (entry.second == PlatformEFI) {
      *has_uefi = true;
    } else {
      *has_bios = true;
    }
    boot_options.push_back(std::move(option));
    retained_streams->push_back(std::move(stream));
  }
  if (boot_options.empty()) {
    return HRESULT_FROM_WIN32(ERROR_FILE_NOT_FOUND);
  }

  SAFEARRAY* array = SafeArrayCreateVector(
      VT_VARIANT, 0, static_cast<ULONG>(boot_options.size()));
  if (array == nullptr) {
    return E_OUTOFMEMORY;
  }
  HRESULT result = S_OK;
  for (LONG index = 0; index < static_cast<LONG>(boot_options.size()); ++index) {
    VARIANT value;
    VariantInit(&value);
    value.vt = VT_DISPATCH;
    result = boot_options[static_cast<std::size_t>(index)]->QueryInterface(
        IID_IDispatch, reinterpret_cast<void**>(&value.pdispVal));
    if (SUCCEEDED(result)) {
      result = SafeArrayPutElement(array, &index, &value);
    }
    VariantClear(&value);
    if (FAILED(result)) {
      break;
    }
  }
  if (SUCCEEDED(result)) {
    result = image->put_BootImageOptionsArray(array);
  }
  SafeArrayDestroy(array);
  return result;
}

void RemoveExistingInstallImages(IFsiDirectoryItem* root,
                                 const std::wstring& source_root) {
  if (root == nullptr) {
    return;
  }
  ScopedBstr sources_name(L"sources");
  ComPtr<IFsiItem> sources_item;
  if (!sources_name.valid() ||
      FAILED(root->get_Item(sources_name.get(), &sources_item))) {
    return;
  }
  ComPtr<IFsiDirectoryItem> sources;
  if (FAILED(sources_item.As(&sources))) {
    return;
  }
  for (const wchar_t* name : {L"install.wim", L"install.esd"}) {
    ScopedBstr target(name);
    if (target.valid()) {
      sources->Remove(target.get());
    }
  }

  const std::wstring pattern =
      JoinPath(source_root, L"sources\\install*.swm");
  WIN32_FIND_DATAW data{};
  HANDLE search = FindFirstFileW(pattern.c_str(), &data);
  if (search == INVALID_HANDLE_VALUE) {
    return;
  }
  do {
    if ((data.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY) == 0) {
      ScopedBstr target(data.cFileName);
      if (target.valid()) {
        sources->Remove(target.get());
      }
    }
  } while (FindNextFileW(search, &data) != FALSE);
  FindClose(search);
}

HRESULT AddReplacementFiles(IFsiDirectoryItem* root,
                            const std::vector<ReplacementFile>& replacements,
                            std::vector<ComPtr<IStream>>* retained_streams) {
  if (root == nullptr || retained_streams == nullptr) {
    return E_POINTER;
  }
  if (replacements.empty()) {
    return S_OK;
  }
  ScopedBstr sources_name(L"sources");
  ComPtr<IFsiItem> sources_item;
  HRESULT result = sources_name.valid()
                       ? root->get_Item(sources_name.get(), &sources_item)
                       : E_OUTOFMEMORY;
  if (FAILED(result)) {
    return result;
  }
  ComPtr<IFsiDirectoryItem> sources;
  if (FAILED(result = sources_item.As(&sources))) {
    return result;
  }

  for (const ReplacementFile& replacement : replacements) {
    ComPtr<IStream> stream;
    if (FAILED(result = OpenReadStream(replacement.source, &stream))) {
      return result;
    }
    ScopedBstr target(replacement.target_name);
    if (!target.valid()) {
      return E_OUTOFMEMORY;
    }
    if (FAILED(result = sources->AddFile(target.get(), stream.Get()))) {
      return result;
    }
    retained_streams->push_back(std::move(stream));
  }
  return S_OK;
}

bool WriteImage(IStream* stream, LONG total_blocks,
                const std::wstring& output_path,
                const std::wstring& cancel_path) {
  if (stream == nullptr || total_blocks <= 0) {
    return false;
  }
  const std::wstring temporary_path = output_path + L".wds-part";
  DeleteFileW(temporary_path.c_str());
  HANDLE output = CreateFileW(temporary_path.c_str(), GENERIC_WRITE, 0, nullptr,
                              CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, nullptr);
  if (output == INVALID_HANDLE_VALUE) {
    EmitError("Unable to create the temporary ISO output",
              HRESULT_FROM_WIN32(GetLastError()));
    return false;
  }

  const std::uint64_t total_bytes =
      static_cast<std::uint64_t>(total_blocks) * 2048ULL;
  std::vector<unsigned char> buffer(kTransferBufferSize);
  std::uint64_t written_total = 0;
  int last_percent = -1;
  bool success = true;
  while (written_total < total_bytes) {
    if (IsCancelled(cancel_path)) {
      success = false;
      SetLastError(ERROR_CANCELLED);
      break;
    }
    const ULONG requested = static_cast<ULONG>(std::min<std::uint64_t>(
        buffer.size(), total_bytes - written_total));
    ULONG read = 0;
    const HRESULT read_result = stream->Read(buffer.data(), requested, &read);
    if (FAILED(read_result) || read == 0) {
      EmitError("The IMAPI image stream ended unexpectedly", read_result);
      success = false;
      break;
    }
    DWORD written = 0;
    if (WriteFile(output, buffer.data(), read, &written, nullptr) == FALSE ||
        written != read) {
      EmitError("Writing the ISO output failed",
                HRESULT_FROM_WIN32(GetLastError()));
      success = false;
      break;
    }
    written_total += written;
    const int percent = static_cast<int>(
        std::min<std::uint64_t>(100, written_total * 100 / total_bytes));
    if (percent != last_percent) {
      last_percent = percent;
      EmitProgress("writing", 45 + percent * 50 / 100, written_total,
                   total_bytes);
    }
  }
  if (success && FlushFileBuffers(output) == FALSE) {
    EmitError("Flushing the ISO output failed",
              HRESULT_FROM_WIN32(GetLastError()));
    success = false;
  }
  CloseHandle(output);

  if (!success) {
    DeleteFileW(temporary_path.c_str());
    return false;
  }
  if (MoveFileExW(temporary_path.c_str(), output_path.c_str(),
                  MOVEFILE_REPLACE_EXISTING | MOVEFILE_WRITE_THROUGH) ==
      FALSE) {
    EmitError("Publishing the ISO output failed",
              HRESULT_FROM_WIN32(GetLastError()));
    DeleteFileW(temporary_path.c_str());
    return false;
  }
  return true;
}

}  // namespace

int wmain(int argc, wchar_t* argv[]) {
  Options options;
  if (!ParseOptions(argc, argv, &options)) {
    std::cerr << "Required arguments: --parent-pid PID --source-root DIR "
                 "--output FILE --volume-label LABEL [--cancel FILE] "
                 "[--replace-file SOURCE TARGET]"
              << std::endl;
    return 1;
  }
  options.source_root = FullPath(options.source_root);
  options.output_path = FullPath(options.output_path);
  options.cancel_path = FullPath(options.cancel_path);
  for (ReplacementFile& replacement : options.replacements) {
    replacement.source = FullPath(replacement.source);
  }
  if (!IsDirectory(options.source_root) || options.output_path.empty() ||
      options.volume_label.size() > 32 ||
      IsPathInside(options.output_path, options.source_root)) {
    std::cerr << "The source root, output path, or volume label is invalid."
              << std::endl;
    return 1;
  }
  for (const ReplacementFile& replacement : options.replacements) {
    if (!IsRegularFile(replacement.source) ||
        !IsSafeTargetName(replacement.target_name)) {
      std::cerr << "A replacement image path or target name is invalid."
                << std::endl;
      return 1;
    }
  }

  ParentLifetimeGuard parent_guard;
  if (!parent_guard.Start(options.parent_pid)) {
    std::cerr << "Unable to bind the ISO builder to the application process."
              << std::endl;
    return 1;
  }
  if (IsCancelled(options.cancel_path)) {
    return ERROR_CANCELLED;
  }

  const HRESULT com_result = CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);
  if (FAILED(com_result)) {
    EmitError("Unable to initialize Windows image mastering", com_result);
    return 2;
  }
  std::cout << "PROTO|" << kProtocolVersion << std::endl;
  int exit_code = 2;
  {
    ComPtr<IFileSystemImage2> image;
    HRESULT result = CoCreateInstance(CLSID_MsftFileSystemImage, nullptr,
                                      CLSCTX_INPROC_SERVER,
                                      IID_PPV_ARGS(&image));
    if (FAILED(result)) {
      EmitError("Windows IMAPI2 is unavailable", result);
    } else {
      EmitState("preparing", 5);
      result = image->ChooseImageDefaultsForMediaType(IMAPI_MEDIA_TYPE_DISK);
      if (SUCCEEDED(result)) {
        result = image->put_FileSystemsToCreate(static_cast<FsiFileSystems>(
            FsiFileSystemISO9660 | FsiFileSystemJoliet | FsiFileSystemUDF));
      }
      if (SUCCEEDED(result)) {
        result = image->put_ISO9660InterchangeLevel(2);
      }
      if (SUCCEEDED(result)) {
        result = image->put_UDFRevision(0x102);
      }
      if (SUCCEEDED(result)) {
        result = image->put_StageFiles(VARIANT_FALSE);
      }
      ScopedBstr label(options.volume_label);
      if (SUCCEEDED(result)) {
        result = label.valid() ? image->put_VolumeName(label.get())
                               : E_OUTOFMEMORY;
      }

      ComPtr<IFsiDirectoryItem> root;
      if (SUCCEEDED(result)) {
        result = image->get_Root(&root);
      }
      ScopedBstr source(options.source_root);
      if (SUCCEEDED(result)) {
        result = source.valid()
                     ? root->AddTree(source.get(), VARIANT_FALSE)
                     : E_OUTOFMEMORY;
      }
      std::vector<ComPtr<IStream>> retained_streams;
      if (SUCCEEDED(result) && !options.replacements.empty()) {
        RemoveExistingInstallImages(root.Get(), options.source_root);
        result = AddReplacementFiles(root.Get(), options.replacements,
                                     &retained_streams);
      }

      bool has_bios = false;
      bool has_uefi = false;
      if (SUCCEEDED(result)) {
        result = ConfigureBootOptions(image.Get(), options.source_root,
                                      &has_bios, &has_uefi,
                                      &retained_streams);
      }
      if (FAILED(result)) {
        EmitError("The Windows source could not be prepared as bootable media",
                  result);
      } else if (IsCancelled(options.cancel_path)) {
        exit_code = ERROR_CANCELLED;
      } else {
        EmitState("building", 25);
        ComPtr<IFileSystemImageResult> image_result;
        result = image->CreateResultImage(&image_result);
        if (FAILED(result)) {
          EmitError("Windows IMAPI2 could not build the ISO file system",
                    result);
        } else if (IsCancelled(options.cancel_path)) {
          exit_code = ERROR_CANCELLED;
        } else {
          LONG total_blocks = 0;
          ComPtr<IStream> image_stream;
          result = image_result->get_TotalBlocks(&total_blocks);
          if (SUCCEEDED(result)) {
            result = image_result->get_ImageStream(&image_stream);
          }
          if (FAILED(result)) {
            EmitError("Windows IMAPI2 returned an invalid image stream",
                      result);
          } else if (WriteImage(image_stream.Get(), total_blocks,
                                options.output_path, options.cancel_path)) {
            WIN32_FILE_ATTRIBUTE_DATA attributes{};
            GetFileAttributesExW(options.output_path.c_str(),
                                 GetFileExInfoStandard, &attributes);
            const std::uint64_t size =
                (static_cast<std::uint64_t>(attributes.nFileSizeHigh) << 32) |
                attributes.nFileSizeLow;
            EmitState("complete", 100);
            std::cout << "RESULT|" << size << "|" << (has_bios ? 1 : 0)
                      << "|" << (has_uefi ? 1 : 0) << std::endl;
            exit_code = 0;
          } else if (IsCancelled(options.cancel_path)) {
            exit_code = ERROR_CANCELLED;
          }
        }
      }
    }
  }
  CoUninitialize();
  return exit_code;
}
