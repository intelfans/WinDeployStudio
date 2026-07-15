#include <windows.h>

#include <cstdint>
#include <iostream>
#include <string>

namespace {

class WimApi {
 public:
  using CreateFileFn = HANDLE(WINAPI*)(LPCWSTR, DWORD, DWORD, DWORD, DWORD,
                                       LPDWORD);
  using GetImageCountFn = DWORD(WINAPI*)(HANDLE);
  using LoadImageFn = HANDLE(WINAPI*)(HANDLE, DWORD);
  using GetImageInformationFn = BOOL(WINAPI*)(HANDLE, PVOID*, PDWORD);
  using SetTemporaryPathFn = BOOL(WINAPI*)(HANDLE, PWSTR);
  using CloseHandleFn = BOOL(WINAPI*)(HANDLE);

  WimApi() {
    module_ = LoadLibraryW(L"wimgapi.dll");
    if (module_ == nullptr) {
      error_ = GetLastError();
      return;
    }

    create_file = LoadFunction<CreateFileFn>("WIMCreateFile");
    get_image_count = LoadFunction<GetImageCountFn>("WIMGetImageCount");
    load_image = LoadFunction<LoadImageFn>("WIMLoadImage");
    get_image_information =
        LoadFunction<GetImageInformationFn>("WIMGetImageInformation");
    set_temporary_path =
        LoadFunction<SetTemporaryPathFn>("WIMSetTemporaryPath");
    close_handle = LoadFunction<CloseHandleFn>("WIMCloseHandle");
    if (create_file == nullptr || get_image_count == nullptr ||
        load_image == nullptr || get_image_information == nullptr ||
        set_temporary_path == nullptr || close_handle == nullptr) {
      error_ = ERROR_PROC_NOT_FOUND;
      FreeLibrary(module_);
      module_ = nullptr;
    }
  }

  ~WimApi() {
    if (module_ != nullptr) {
      FreeLibrary(module_);
    }
  }

  WimApi(const WimApi&) = delete;
  WimApi& operator=(const WimApi&) = delete;

  bool IsAvailable() const { return module_ != nullptr; }

  DWORD error() const { return error_; }

  CreateFileFn create_file = nullptr;
  GetImageCountFn get_image_count = nullptr;
  LoadImageFn load_image = nullptr;
  GetImageInformationFn get_image_information = nullptr;
  SetTemporaryPathFn set_temporary_path = nullptr;
  CloseHandleFn close_handle = nullptr;

 private:
  template <typename Function>
  Function LoadFunction(const char* name) const {
    return reinterpret_cast<Function>(GetProcAddress(module_, name));
  }

  HMODULE module_ = nullptr;
  DWORD error_ = ERROR_MOD_NOT_FOUND;
};

std::string ToUtf8(const wchar_t* text, std::size_t character_count) {
  if (text == nullptr || character_count == 0) {
    return {};
  }
  if (character_count > 0 && text[character_count - 1] == L'\0') {
    --character_count;
  }
  const int byte_count = WideCharToMultiByte(
      CP_UTF8, 0, text, static_cast<int>(character_count), nullptr, 0, nullptr,
      nullptr);
  if (byte_count <= 0) {
    return {};
  }
  std::string output(static_cast<std::size_t>(byte_count), '\0');
  WideCharToMultiByte(CP_UTF8, 0, text, static_cast<int>(character_count),
                      output.data(), byte_count, nullptr, nullptr);
  return output;
}

std::string Base64Encode(const std::string& input) {
  static constexpr char alphabet[] =
      "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
  std::string output;
  output.reserve(((input.size() + 2) / 3) * 4);
  std::uint32_t accumulator = 0;
  int bits = 0;
  for (const unsigned char value : input) {
    accumulator = (accumulator << 8) | value;
    bits += 8;
    while (bits >= 6) {
      bits -= 6;
      output.push_back(alphabet[(accumulator >> bits) & 0x3F]);
    }
  }
  if (bits > 0) {
    accumulator <<= (6 - bits);
    output.push_back(alphabet[accumulator & 0x3F]);
  }
  while (output.size() % 4 != 0) {
    output.push_back('=');
  }
  return output;
}

}  // namespace

int wmain(int argc, wchar_t* argv[]) {
  if (argc != 2) {
    std::cerr << "A WIM or ESD path is required." << std::endl;
    return 1;
  }

  const WimApi wim_api;
  if (!wim_api.IsAvailable()) {
    std::cerr << "Unable to load Windows Imaging API (Win32="
              << wim_api.error() << ")." << std::endl;
    return 2;
  }

  DWORD creation_result = 0;
  HANDLE wim = wim_api.create_file(argv[1], GENERIC_READ, OPEN_EXISTING, 0, 0,
                                   &creation_result);
  if (wim == nullptr) {
    std::cerr << "WIMCreateFile failed: " << GetLastError() << std::endl;
    return 2;
  }

  // WIMLoadImage requires a writable scratch directory even when the caller
  // only reads image metadata. Without this, ESD-backed installers such as
  // Tiny10 fail with ERROR_INSTALL_TEMP_UNWRITABLE (1632).
  wchar_t temporary_path[MAX_PATH] = {};
  const DWORD temporary_path_length =
      GetTempPathW(MAX_PATH, temporary_path);
  if (temporary_path_length == 0 || temporary_path_length >= MAX_PATH ||
      !wim_api.set_temporary_path(wim, temporary_path)) {
    std::cerr << "WIMSetTemporaryPath failed: " << GetLastError() << std::endl;
    wim_api.close_handle(wim);
    return 2;
  }

  const DWORD image_count = wim_api.get_image_count(wim);
  if (image_count == 0) {
    std::cerr << "The image contains no entries." << std::endl;
    wim_api.close_handle(wim);
    return 3;
  }

  for (DWORD index = 1; index <= image_count; ++index) {
    HANDLE image = wim_api.load_image(wim, index);
    if (image == nullptr) {
      std::cerr << "WIMLoadImage failed for index " << index << ": "
                << GetLastError() << std::endl;
      wim_api.close_handle(wim);
      return 4;
    }

    void* image_information = nullptr;
    DWORD information_size = 0;
    const bool information_ok =
        wim_api.get_image_information(image, &image_information,
                                      &information_size) != FALSE;
    if (!information_ok || image_information == nullptr ||
        information_size < sizeof(wchar_t)) {
      std::cerr << "WIMGetImageInformation failed for index " << index << ": "
                << GetLastError() << std::endl;
      if (image_information != nullptr) {
        LocalFree(image_information);
      }
      wim_api.close_handle(image);
      wim_api.close_handle(wim);
      return 5;
    }

    const auto* xml = static_cast<const wchar_t*>(image_information);
    const std::size_t character_count = information_size / sizeof(wchar_t);
    const std::string utf8 = ToUtf8(xml, character_count);
    // WIMGetImageInformation returns a LocalAlloc buffer. WIMFreeMemory is
    // not exported by the system WIMGAPI DLL on supported Windows releases.
    LocalFree(image_information);
    wim_api.close_handle(image);

    if (utf8.empty()) {
      std::cerr << "Image metadata conversion failed for index " << index
                << std::endl;
      wim_api.close_handle(wim);
      return 6;
    }
    std::cout << "IMAGE|" << index << "|" << Base64Encode(utf8)
              << std::endl;
  }

  wim_api.close_handle(wim);
  return 0;
}
