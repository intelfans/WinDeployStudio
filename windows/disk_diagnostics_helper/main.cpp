#include <windows.h>
#include <ntddscsi.h>
#include <winioctl.h>

#include <algorithm>
#include <array>
#include <cstddef>
#include <cstdint>
#include <cstring>
#include <cwchar>
#include <cwctype>
#include <iostream>
#include <optional>
#include <sstream>
#include <string>
#include <string_view>
#include <utility>
#include <vector>

namespace {

constexpr DWORD kNvmeHealthLogPage = 0x02;
constexpr std::size_t kNvmeHealthLogSize = 512;
constexpr DWORD kDiskWorkerTimeoutMilliseconds = 3500;
constexpr DWORD kWorkerTerminationGraceMilliseconds = 250;
constexpr DWORD kInventoryTimeoutMilliseconds = 18000;
constexpr DWORD kMaximumPhysicalDriveNumber = 63;
constexpr unsigned long kMaximumDiskNumber = 9999;
constexpr DWORD kMaximumDescriptorSize = 64 * 1024;
constexpr std::size_t kMaximumDescriptorTextLength = 512;
constexpr std::size_t kMaximumIdentifierLength = 256;
constexpr std::size_t kMaximumWorkerOutputLength = 64 * 1024;
constexpr std::size_t kMaximumStorageCountersSize = 64 * 1024;
constexpr int kDiskNotPresentExitCode = 3;
constexpr DWORD kIntelRstNvmeControlCode = static_cast<DWORD>(
    CTL_CODE(0xf000u, 0xA02u, METHOD_BUFFERED, FILE_ANY_ACCESS));
constexpr DWORD kIntelVrocNvmeControlCode = static_cast<DWORD>(
    CTL_CODE(0xe000u, 0x800u, METHOD_BUFFERED, FILE_ANY_ACCESS));

#pragma pack(push, 1)
// Intel RST exposes NVMe health data through a documented-by-driver miniport
// envelope rather than the standard Storage Protocol query. The request below
// is copied from the public Intel RST wire layout used by storage diagnostic
// tools; only the read-only NVMe Get Log Page command is issued.
struct IntelRstNvmePayload {
  std::uint8_t version;
  std::uint8_t path_id;
  std::uint8_t target_id;
  std::uint8_t lun;
  std::array<DWORD, 16> command;
  std::array<DWORD, 4> completion;
  DWORD queue_id;
  DWORD parameter_buffer_length;
  DWORD return_buffer_length;
  std::array<std::uint8_t, 0x28> reserved;
};

struct IntelRstNvmePassThrough {
  SRB_IO_CONTROL srb;
  IntelRstNvmePayload payload;
  std::array<std::uint8_t, 0x1000> data;
};

struct IntelVrocNvmePassThrough {
  SRB_IO_CONTROL srb;
  std::array<DWORD, 6> vendor_specific;
  std::array<DWORD, 16> command;
  std::array<DWORD, 4> completion;
  DWORD direction;
  DWORD queue_id;
  DWORD data_buffer_length;
  DWORD metadata_length;
  DWORD return_buffer_length;
  std::array<std::uint8_t, 0x1000> data;
};
#pragma pack(pop)

static_assert(sizeof(SRB_IO_CONTROL) == 0x1c,
              "Unexpected SRB_IO_CONTROL ABI.");
static_assert(sizeof(IntelRstNvmePayload) == 0x88,
              "Unexpected Intel RST NVMe payload ABI.");

class ScopedHandle {
 public:
  explicit ScopedHandle(HANDLE handle = nullptr) : handle_(handle) {}

  ~ScopedHandle() { Reset(); }

  ScopedHandle(const ScopedHandle&) = delete;
  ScopedHandle& operator=(const ScopedHandle&) = delete;

  ScopedHandle(ScopedHandle&& other) noexcept : handle_(other.Release()) {}

  ScopedHandle& operator=(ScopedHandle&& other) noexcept {
    if (this != &other) {
      Reset(other.Release());
    }
    return *this;
  }

  HANDLE get() const { return handle_; }

  bool valid() const {
    return handle_ != nullptr && handle_ != INVALID_HANDLE_VALUE;
  }

  HANDLE Release() {
    const HANDLE handle = handle_;
    handle_ = nullptr;
    return handle;
  }

  void Reset(HANDLE handle = nullptr) {
    if (valid()) {
      CloseHandle(handle_);
    }
    handle_ = handle;
  }

 private:
  HANDLE handle_;
};

struct NvmeHealthData {
  bool available = false;
  std::string reason =
      "The device or storage driver does not expose NVMe health data.";
  std::string source = "Windows NVMe protocol query";
  DWORD windows_error = ERROR_SUCCESS;
  std::optional<int> temperature_celsius;
  std::optional<int> percentage_used;
  std::optional<std::string> host_read_bytes;
  std::optional<std::string> host_written_bytes;
  std::optional<std::string> host_read_commands;
  std::optional<std::string> host_write_commands;
  std::optional<std::string> power_on_hours;
  std::optional<std::string> media_and_data_integrity_errors;
  std::uint8_t critical_warning = 0;
};

struct DiskTopology {
  std::optional<DWORD> device_type;
  std::optional<DWORD> device_number;
  std::optional<DWORD> partition_number;
  std::optional<bool> media_removable;
  std::optional<bool> media_hotplug;
  std::optional<bool> device_hotplug;
};

struct DiskReport {
  DWORD disk_number = 0;
  bool present = true;
  std::optional<std::string> model;
  std::optional<std::string> size_bytes;
  std::optional<std::string> serial_number;
  std::optional<std::string> unique_id;
  std::optional<std::string> bus_type;
  std::optional<std::string> vendor_id;
  std::optional<std::string> product_id;
  std::optional<std::string> health;
  std::optional<std::string> health_source;
  std::optional<int> temperature_celsius;
  std::optional<int> wear_percent;
  std::optional<std::string> read_errors_corrected;
  std::optional<std::string> read_errors_uncorrected;
  std::optional<std::string> read_errors_total;
  std::optional<std::string> write_errors_corrected;
  std::optional<std::string> write_errors_uncorrected;
  std::optional<std::string> write_errors_total;
  std::optional<std::string> power_on_hours;
  std::optional<std::string> firmware_version;
  std::optional<std::string> media_type;
  std::optional<std::string> partition_style;
  std::optional<std::string> operational_status;
  std::optional<std::string> pnp_device_id;
  std::string device_path;
  std::vector<std::string> drive_letters;
  std::optional<bool> is_system;
  std::optional<bool> is_boot;
  std::optional<bool> is_offline;
  std::optional<bool> is_read_only;
  std::optional<bool> is_removable;
  std::string reliability_unavailable_reason =
      "The storage driver did not expose supported reliability counters.";
  NvmeHealthData nvme;
  DiskTopology topology;
  std::vector<std::string> warnings;
};

struct ChildWorkerResult {
  bool started = false;
  bool timed_out = false;
  bool output_truncated = false;
  DWORD error_code = ERROR_SUCCESS;
  DWORD exit_code = ERROR_GEN_FAILURE;
  std::string output;
};

std::string TrimAscii(std::string value) {
  const auto first = value.find_first_not_of(" \t\r\n");
  if (first == std::string::npos) {
    return {};
  }
  const auto last = value.find_last_not_of(" \t\r\n");
  return value.substr(first, last - first + 1);
}

std::string JsonEscape(std::string_view value) {
  static constexpr char kHex[] = "0123456789ABCDEF";
  std::string escaped;
  escaped.reserve(value.size() + 16);
  for (const unsigned char character : value) {
    switch (character) {
      case '\\':
        escaped += "\\\\";
        break;
      case '"':
        escaped += "\\\"";
        break;
      case '\b':
        escaped += "\\b";
        break;
      case '\f':
        escaped += "\\f";
        break;
      case '\n':
        escaped += "\\n";
        break;
      case '\r':
        escaped += "\\r";
        break;
      case '\t':
        escaped += "\\t";
        break;
      default:
        if (character < 0x20U) {
          escaped += "\\u00";
          escaped += kHex[(character >> 4U) & 0x0FU];
          escaped += kHex[character & 0x0FU];
        } else {
          escaped += static_cast<char>(character);
        }
        break;
    }
  }
  return escaped;
}

void AppendJsonString(std::ostream& stream, std::string_view value) {
  stream << '"' << JsonEscape(value) << '"';
}

void AppendOptionalString(std::ostream& stream,
                          const std::optional<std::string>& value) {
  if (value.has_value()) {
    AppendJsonString(stream, *value);
  } else {
    stream << "null";
  }
}

void AppendOptionalInt(std::ostream& stream, const std::optional<int>& value) {
  if (value.has_value()) {
    stream << *value;
  } else {
    stream << "null";
  }
}

void AppendOptionalDword(std::ostream& stream,
                         const std::optional<DWORD>& value) {
  if (value.has_value()) {
    stream << *value;
  } else {
    stream << "null";
  }
}

void AppendOptionalBool(std::ostream& stream,
                        const std::optional<bool>& value) {
  if (!value.has_value()) {
    stream << "null";
  } else {
    stream << (*value ? "true" : "false");
  }
}

void AppendJsonStringArray(std::ostream& stream,
                           const std::vector<std::string>& values) {
  stream << '[';
  for (std::size_t index = 0; index < values.size(); ++index) {
    if (index > 0) {
      stream << ',';
    }
    AppendJsonString(stream, values[index]);
  }
  stream << ']';
}

void AppendDiagnosticWarningArray(std::ostream& stream,
                                  const std::vector<std::string>& warnings) {
  // Keep diagnostic transport details out of the UI. They are useful to a
  // developer but are not localized and can vary between storage drivers.
  // The Dart client maps this stable code to the current application locale.
  stream << '[';
  if (!warnings.empty()) {
    stream << "{\"code\":\"disk_diag_warning_partial\"}";
  }
  stream << ']';
}

std::string DecimalFromLittleEndian(const std::uint8_t* bytes,
                                    std::size_t length) {
  std::string decimal = "0";
  for (std::size_t byte_index = length; byte_index > 0; --byte_index) {
    unsigned int carry = bytes[byte_index - 1];
    for (std::size_t digit_index = decimal.size(); digit_index > 0;
         --digit_index) {
      const unsigned int value =
          static_cast<unsigned int>(decimal[digit_index - 1] - '0') * 256U +
          carry;
      decimal[digit_index - 1] = static_cast<char>('0' + (value % 10U));
      carry = value / 10U;
    }
    while (carry > 0U) {
      decimal.insert(decimal.begin(), static_cast<char>('0' + (carry % 10U)));
      carry /= 10U;
    }
  }
  return decimal;
}

std::string MultiplyDecimal(const std::string& decimal,
                            std::uint32_t multiplier) {
  std::string result = decimal;
  std::uint64_t carry = 0;
  for (std::size_t index = result.size(); index > 0; --index) {
    const std::uint64_t value =
        static_cast<std::uint64_t>(result[index - 1] - '0') * multiplier +
        carry;
    result[index - 1] = static_cast<char>('0' + (value % 10U));
    carry = value / 10U;
  }
  while (carry > 0U) {
    result.insert(result.begin(), static_cast<char>('0' + (carry % 10U)));
    carry /= 10U;
  }
  return result;
}

std::uint16_t ReadUint16(const std::uint8_t* data) {
  return static_cast<std::uint16_t>(data[0]) |
         (static_cast<std::uint16_t>(data[1]) << 8U);
}

std::string AnsiBytesToUtf8(const char* bytes, std::size_t length) {
  if (bytes == nullptr || length == 0) {
    return {};
  }
  const auto terminator =
      static_cast<const char*>(std::memchr(bytes, '\0', length));
  if (terminator != nullptr) {
    length = static_cast<std::size_t>(terminator - bytes);
  }
  length = std::min(length, kMaximumDescriptorTextLength);
  if (length == 0) {
    return {};
  }

  const int wide_length = MultiByteToWideChar(
      CP_ACP, 0, bytes, static_cast<int>(length), nullptr, 0);
  if (wide_length <= 0) {
    std::string ascii;
    ascii.reserve(length);
    for (std::size_t index = 0; index < length; ++index) {
      const unsigned char character =
          static_cast<unsigned char>(bytes[index]);
      ascii.push_back(character >= 0x20U && character <= 0x7EU
                          ? static_cast<char>(character)
                          : '?');
    }
    return TrimAscii(std::move(ascii));
  }

  std::wstring wide(static_cast<std::size_t>(wide_length), L'\0');
  if (MultiByteToWideChar(CP_ACP, 0, bytes, static_cast<int>(length),
                          wide.data(), wide_length) != wide_length) {
    return {};
  }
  const int utf8_length = WideCharToMultiByte(
      CP_UTF8, 0, wide.data(), wide_length, nullptr, 0, nullptr, nullptr);
  if (utf8_length <= 0) {
    return {};
  }
  std::string utf8(static_cast<std::size_t>(utf8_length), '\0');
  if (WideCharToMultiByte(CP_UTF8, 0, wide.data(), wide_length, utf8.data(),
                          utf8_length, nullptr, nullptr) != utf8_length) {
    return {};
  }
  return TrimAscii(std::move(utf8));
}

std::optional<std::string> DescriptorText(const std::vector<std::uint8_t>& data,
                                          DWORD offset) {
  if (offset == 0 || offset >= data.size()) {
    return std::nullopt;
  }
  const std::string text = AnsiBytesToUtf8(
      reinterpret_cast<const char*>(data.data() + offset), data.size() - offset);
  if (text.empty()) {
    return std::nullopt;
  }
  return text;
}

std::string HexEncode(const std::uint8_t* bytes, std::size_t length) {
  static constexpr char kHex[] = "0123456789ABCDEF";
  length = std::min(length, kMaximumIdentifierLength);
  std::string encoded;
  encoded.reserve(length * 2);
  for (std::size_t index = 0; index < length; ++index) {
    encoded.push_back(kHex[(bytes[index] >> 4U) & 0x0FU]);
    encoded.push_back(kHex[bytes[index] & 0x0FU]);
  }
  return encoded;
}

std::string BusTypeName(STORAGE_BUS_TYPE bus_type) {
  switch (static_cast<DWORD>(bus_type)) {
    case 1:
      return "SCSI";
    case 2:
      return "ATAPI";
    case 3:
      return "ATA";
    case 4:
      return "1394";
    case 5:
      return "SSA";
    case 6:
      return "Fibre";
    case 7:
      return "USB";
    case 8:
      return "RAID";
    case 9:
      return "iSCSI";
    case 10:
      return "SAS";
    case 11:
      return "SATA";
    case 12:
      return "SD";
    case 13:
      return "MMC";
    case 14:
      return "Virtual";
    case 15:
      return "File-backed virtual";
    case 16:
      return "Storage Spaces";
    case 17:
      return "NVMe";
    case 18:
      return "SCM";
    case 19:
      return "UFS";
    default:
      return "Unknown";
  }
}

std::string PartitionStyleName(DWORD style) {
  switch (style) {
    case PARTITION_STYLE_MBR:
      return "MBR";
    case PARTITION_STYLE_GPT:
      return "GPT";
    case PARTITION_STYLE_RAW:
      return "RAW";
    default:
      return "Unknown";
  }
}

bool IsAdministrator() {
  SID_IDENTIFIER_AUTHORITY authority = SECURITY_NT_AUTHORITY;
  PSID administrators = nullptr;
  if (!AllocateAndInitializeSid(&authority, 2, SECURITY_BUILTIN_DOMAIN_RID,
                                DOMAIN_ALIAS_RID_ADMINS, 0, 0, 0, 0, 0, 0,
                                &administrators)) {
    return false;
  }
  BOOL is_member = FALSE;
  const BOOL checked = CheckTokenMembership(nullptr, administrators, &is_member);
  FreeSid(administrators);
  return checked != FALSE && is_member != FALSE;
}

bool DeviceIoControlQuery(HANDLE disk, DWORD control_code, void* input_buffer,
                          DWORD input_size, void* output_buffer,
                          DWORD output_size, DWORD* returned,
                          DWORD* error_code) {
  *returned = 0;
  if (DeviceIoControl(disk, control_code, input_buffer, input_size,
                      output_buffer, output_size, returned, nullptr) != FALSE) {
    *error_code = ERROR_SUCCESS;
    return true;
  }
  *error_code = GetLastError();
  return false;
}

HANDLE OpenPhysicalDiskForReadOnlyQuery(const std::wstring& path,
                                        DWORD* error_code) {
  HANDLE zero_access =
      CreateFileW(path.c_str(), 0, FILE_SHARE_READ | FILE_SHARE_WRITE, nullptr,
                  OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, nullptr);
  const DWORD zero_access_error =
      zero_access == INVALID_HANDLE_VALUE ? GetLastError() : ERROR_SUCCESS;

  // Some drivers accept the least-privileged handle but reject individual
  // read-only storage IOCTLs on it. Prefer GENERIC_READ when it is available;
  // retain the zero-access handle when a caller lacks read permission.
  HANDLE read_access = CreateFileW(path.c_str(), GENERIC_READ,
                                   FILE_SHARE_READ | FILE_SHARE_WRITE, nullptr,
                                   OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, nullptr);
  if (read_access != INVALID_HANDLE_VALUE) {
    if (zero_access != INVALID_HANDLE_VALUE) {
      CloseHandle(zero_access);
    }
    *error_code = ERROR_SUCCESS;
    return read_access;
  }

  if (zero_access != INVALID_HANDLE_VALUE) {
    *error_code = ERROR_SUCCESS;
    return zero_access;
  }
  *error_code = zero_access_error;
  return INVALID_HANDLE_VALUE;
}

bool IsMissingPhysicalDriveError(DWORD error_code) {
  return error_code == ERROR_FILE_NOT_FOUND || error_code == ERROR_PATH_NOT_FOUND ||
         error_code == ERROR_INVALID_NAME;
}

bool HasPhysicalDriveAlias(DWORD disk_number) {
  const std::wstring name = L"PhysicalDrive" + std::to_wstring(disk_number);
  std::array<wchar_t, 1024> target{};
  if (QueryDosDeviceW(name.c_str(), target.data(),
                      static_cast<DWORD>(target.size())) != 0) {
    return true;
  }
  // Only a definitive not-found result is used as a skip hint. Any other
  // namespace failure still goes through the isolated worker for a bounded
  // physical-drive query.
  return GetLastError() != ERROR_FILE_NOT_FOUND;
}

bool QueryStorageDescriptor(HANDLE disk, STORAGE_PROPERTY_ID property_id,
                            std::vector<std::uint8_t>* descriptor,
                            DWORD* error_code) {
  STORAGE_PROPERTY_QUERY query{};
  query.PropertyId = property_id;
  query.QueryType = PropertyStandardQuery;

  STORAGE_DESCRIPTOR_HEADER header{};
  DWORD returned = 0;
  if (!DeviceIoControlQuery(disk, IOCTL_STORAGE_QUERY_PROPERTY, &query,
                            static_cast<DWORD>(sizeof(query)), &header,
                            static_cast<DWORD>(sizeof(header)), &returned,
                            error_code)) {
    return false;
  }
  if (returned < sizeof(header) || header.Size < sizeof(header) ||
      header.Size > kMaximumDescriptorSize) {
    *error_code = ERROR_INVALID_DATA;
    return false;
  }

  descriptor->assign(header.Size, 0);
  returned = 0;
  if (!DeviceIoControlQuery(disk, IOCTL_STORAGE_QUERY_PROPERTY, &query,
                            static_cast<DWORD>(sizeof(query)), descriptor->data(),
                            static_cast<DWORD>(descriptor->size()), &returned,
                            error_code)) {
    return false;
  }
  if (returned < sizeof(header) || returned > descriptor->size()) {
    *error_code = ERROR_INVALID_DATA;
    return false;
  }
  descriptor->resize(returned);
  return true;
}

std::optional<std::string> QueryStorageIdentifier(HANDLE disk,
                                                  DWORD* error_code) {
  std::vector<std::uint8_t> descriptor;
  if (!QueryStorageDescriptor(disk, StorageDeviceIdProperty, &descriptor,
                              error_code)) {
    return std::nullopt;
  }
  constexpr std::size_t kIdentifiersOffset =
      offsetof(STORAGE_DEVICE_ID_DESCRIPTOR, Identifiers);
  constexpr std::size_t kIdentifierDataOffset =
      offsetof(STORAGE_IDENTIFIER, Identifier);
  if (descriptor.size() < kIdentifiersOffset) {
    *error_code = ERROR_INVALID_DATA;
    return std::nullopt;
  }

  const auto* id_descriptor =
      reinterpret_cast<const STORAGE_DEVICE_ID_DESCRIPTOR*>(descriptor.data());
  const std::size_t descriptor_size =
      std::min<std::size_t>(descriptor.size(), id_descriptor->Size);
  if (id_descriptor->Size < kIdentifiersOffset ||
      descriptor_size < kIdentifiersOffset) {
    *error_code = ERROR_INVALID_DATA;
    return std::nullopt;
  }

  std::size_t identifier_offset = kIdentifiersOffset;
  const DWORD identifier_count = std::min<DWORD>(id_descriptor->NumberOfIdentifiers,
                                                  1024);
  for (DWORD index = 0; index < identifier_count; ++index) {
    if (identifier_offset > descriptor_size ||
        kIdentifierDataOffset > descriptor_size - identifier_offset) {
      break;
    }
    const auto* identifier = reinterpret_cast<const STORAGE_IDENTIFIER*>(
        descriptor.data() + identifier_offset);
    const std::size_t value_offset = identifier_offset + kIdentifierDataOffset;
    const std::size_t value_size = identifier->IdentifierSize;
    if (value_size > 0 && value_offset <= descriptor_size &&
        value_size <= descriptor_size - value_offset) {
      const std::string encoded =
          HexEncode(descriptor.data() + value_offset, value_size);
      if (!encoded.empty()) {
        return encoded;
      }
    }
    if (identifier->NextOffset == 0 ||
        identifier->NextOffset > descriptor_size - identifier_offset) {
      break;
    }
    identifier_offset += identifier->NextOffset;
  }

  *error_code = ERROR_NOT_FOUND;
  return std::nullopt;
}

void AddQueryWarning(DiskReport* report, std::string_view query,
                     DWORD error_code) {
  std::ostringstream warning;
  warning << query << " unavailable (Win32=" << error_code << ").";
  report->warnings.push_back(warning.str());
}

void PopulateDeviceDescriptor(HANDLE disk, DiskReport* report) {
  DWORD error_code = ERROR_SUCCESS;
  std::vector<std::uint8_t> descriptor;
  if (!QueryStorageDescriptor(disk, StorageDeviceProperty, &descriptor,
                              &error_code)) {
    AddQueryWarning(report, "Storage device descriptor", error_code);
    return;
  }
  if (descriptor.size() < sizeof(STORAGE_DEVICE_DESCRIPTOR)) {
    AddQueryWarning(report, "Storage device descriptor", ERROR_INVALID_DATA);
    return;
  }
  const auto* device =
      reinterpret_cast<const STORAGE_DEVICE_DESCRIPTOR*>(descriptor.data());
  const std::size_t descriptor_size =
      std::min<std::size_t>(descriptor.size(), device->Size);
  if (device->Size < sizeof(STORAGE_DEVICE_DESCRIPTOR) ||
      descriptor_size < sizeof(STORAGE_DEVICE_DESCRIPTOR)) {
    AddQueryWarning(report, "Storage device descriptor", ERROR_INVALID_DATA);
    return;
  }

  const auto vendor = DescriptorText(descriptor, device->VendorIdOffset);
  const auto product = DescriptorText(descriptor, device->ProductIdOffset);
  const auto revision = DescriptorText(descriptor, device->ProductRevisionOffset);
  const auto serial = DescriptorText(descriptor, device->SerialNumberOffset);

  report->vendor_id = vendor;
  report->product_id = product;
  report->firmware_version = revision;
  report->serial_number = serial;
  const std::string bus = BusTypeName(device->BusType);
  if (bus != "Unknown") {
    report->bus_type = bus;
  }
  report->is_removable = device->RemovableMedia != FALSE;

  if (vendor.has_value() && product.has_value()) {
    report->model = *vendor + " " + *product;
  } else if (product.has_value()) {
    report->model = product;
  } else if (vendor.has_value()) {
    report->model = vendor;
  }
}

void PopulateLength(HANDLE disk, DiskReport* report) {
  GET_LENGTH_INFORMATION length{};
  DWORD returned = 0;
  DWORD error_code = ERROR_SUCCESS;
  if (DeviceIoControlQuery(disk, IOCTL_DISK_GET_LENGTH_INFO, nullptr, 0,
                           &length, static_cast<DWORD>(sizeof(length)),
                           &returned, &error_code) &&
      returned >= sizeof(length) && length.Length.QuadPart >= 0) {
    report->size_bytes = std::to_string(
        static_cast<std::uint64_t>(length.Length.QuadPart));
    return;
  }

  // Some lower storage filters deny the length-specific IOCTL while allowing
  // the geometry query. Both are metadata-only requests.
  std::array<std::uint8_t, sizeof(DISK_GEOMETRY_EX)> geometry_buffer{};
  returned = 0;
  DWORD geometry_error = ERROR_SUCCESS;
  if (DeviceIoControlQuery(disk, IOCTL_DISK_GET_DRIVE_GEOMETRY_EX, nullptr, 0,
                           geometry_buffer.data(),
                           static_cast<DWORD>(geometry_buffer.size()),
                           &returned, &geometry_error) &&
      returned >= offsetof(DISK_GEOMETRY_EX, Data)) {
    const auto* geometry =
        reinterpret_cast<const DISK_GEOMETRY_EX*>(geometry_buffer.data());
    if (geometry->DiskSize.QuadPart >= 0) {
      report->size_bytes = std::to_string(
          static_cast<std::uint64_t>(geometry->DiskSize.QuadPart));
      return;
    }
  }

  AddQueryWarning(report, "Disk length", geometry_error == ERROR_SUCCESS
                                          ? (error_code == ERROR_SUCCESS
                                                 ? ERROR_INVALID_DATA
                                                 : error_code)
                                          : geometry_error);
}

void PopulateTopology(HANDLE disk, DiskReport* report) {
  STORAGE_DEVICE_NUMBER device_number{};
  DWORD returned = 0;
  DWORD error_code = ERROR_SUCCESS;
  if (DeviceIoControlQuery(disk, IOCTL_STORAGE_GET_DEVICE_NUMBER, nullptr, 0,
                           &device_number,
                           static_cast<DWORD>(sizeof(device_number)), &returned,
                           &error_code) &&
      returned >= sizeof(device_number)) {
    report->topology.device_type = device_number.DeviceType;
    report->topology.device_number = device_number.DeviceNumber;
    report->topology.partition_number = device_number.PartitionNumber;
  } else {
    AddQueryWarning(report, "Storage device topology", error_code == ERROR_SUCCESS
                                                     ? ERROR_INVALID_DATA
                                                     : error_code);
  }

  STORAGE_HOTPLUG_INFO hotplug{};
  returned = 0;
  error_code = ERROR_SUCCESS;
  if (DeviceIoControlQuery(disk, IOCTL_STORAGE_GET_HOTPLUG_INFO, nullptr, 0,
                           &hotplug, static_cast<DWORD>(sizeof(hotplug)),
                           &returned, &error_code) &&
      returned >= sizeof(hotplug)) {
    report->topology.media_removable = hotplug.MediaRemovable != FALSE;
    report->topology.media_hotplug = hotplug.MediaHotplug != FALSE;
    report->topology.device_hotplug = hotplug.DeviceHotplug != FALSE;
    if (!report->is_removable.has_value()) {
      report->is_removable =
          hotplug.MediaRemovable != FALSE || hotplug.MediaHotplug != FALSE ||
          hotplug.DeviceHotplug != FALSE;
    }
  } else {
    AddQueryWarning(report, "Storage hotplug topology",
                    error_code == ERROR_SUCCESS ? ERROR_INVALID_DATA
                                                : error_code);
  }
}

void PopulatePartitionStyle(HANDLE disk, DiskReport* report) {
  std::vector<std::uint8_t> layout_buffer(64 * 1024, 0);
  DWORD returned = 0;
  DWORD error_code = ERROR_SUCCESS;
  if (!DeviceIoControlQuery(disk, IOCTL_DISK_GET_DRIVE_LAYOUT_EX, nullptr, 0,
                            layout_buffer.data(),
                            static_cast<DWORD>(layout_buffer.size()), &returned,
                            &error_code) ||
      returned < offsetof(DRIVE_LAYOUT_INFORMATION_EX, PartitionEntry)) {
    AddQueryWarning(report, "Disk partition layout", error_code == ERROR_SUCCESS
                                                   ? ERROR_INVALID_DATA
                                                   : error_code);
    return;
  }
  const auto* layout =
      reinterpret_cast<const DRIVE_LAYOUT_INFORMATION_EX*>(layout_buffer.data());
  report->partition_style = PartitionStyleName(layout->PartitionStyle);
}

void PopulateReadOnlyFlag(HANDLE disk, DiskReport* report) {
  GET_DISK_ATTRIBUTES attributes{};
  attributes.Version = sizeof(attributes);
  DWORD returned = 0;
  DWORD error_code = ERROR_SUCCESS;
  if (DeviceIoControlQuery(disk, IOCTL_DISK_GET_DISK_ATTRIBUTES, &attributes,
                           static_cast<DWORD>(sizeof(attributes)), &attributes,
                           static_cast<DWORD>(sizeof(attributes)), &returned,
                           &error_code) &&
      returned >= sizeof(attributes)) {
    report->is_read_only =
        (attributes.Attributes & DISK_ATTRIBUTE_READ_ONLY) != 0;
  } else {
    AddQueryWarning(report, "Disk attributes", error_code == ERROR_SUCCESS
                                           ? ERROR_INVALID_DATA
                                           : error_code);
  }
}

bool HasNonZeroBytes(const std::uint8_t* data, std::size_t length) {
  return std::any_of(data, data + length,
                     [](std::uint8_t value) { return value != 0; });
}

void PopulateNvmeHealthFromLog(const std::uint8_t* data,
                               std::string source,
                               NvmeHealthData* health) {
  health->source = std::move(source);
  if (!HasNonZeroBytes(data, kNvmeHealthLogSize)) {
    health->reason =
        "The storage driver returned an empty NVMe health log.";
    health->windows_error = ERROR_INVALID_DATA;
    return;
  }

  const std::uint16_t temperature_kelvin = ReadUint16(data + 1);
  health->critical_warning = data[0];
  if (temperature_kelvin >= 200U && temperature_kelvin <= 500U) {
    health->temperature_celsius =
        static_cast<int>(temperature_kelvin) - 273;
  }
  health->percentage_used = static_cast<int>(data[5]);

  const std::string data_units_read = DecimalFromLittleEndian(data + 32, 16);
  const std::string data_units_written =
      DecimalFromLittleEndian(data + 48, 16);
  health->host_read_bytes = MultiplyDecimal(data_units_read, 512000U);
  health->host_written_bytes = MultiplyDecimal(data_units_written, 512000U);
  health->host_read_commands = DecimalFromLittleEndian(data + 64, 16);
  health->host_write_commands = DecimalFromLittleEndian(data + 80, 16);
  health->power_on_hours = DecimalFromLittleEndian(data + 128, 16);
  health->media_and_data_integrity_errors =
      DecimalFromLittleEndian(data + 160, 16);
  health->available = true;
  health->reason.clear();
  health->windows_error = ERROR_SUCCESS;
}

bool QueryNvmeHealthLog(HANDLE disk, STORAGE_PROPERTY_ID property,
                        DWORD namespace_id, DWORD* error_code,
                        NvmeHealthData* health) {
  constexpr std::size_t kQueryHeaderSize =
      offsetof(STORAGE_PROPERTY_QUERY, AdditionalParameters);
  constexpr std::size_t kQueryBufferSize =
      kQueryHeaderSize + sizeof(STORAGE_PROTOCOL_SPECIFIC_DATA) +
      kNvmeHealthLogSize;
  std::array<std::uint8_t, kQueryBufferSize> buffer{};
  auto* query = reinterpret_cast<STORAGE_PROPERTY_QUERY*>(buffer.data());
  query->PropertyId = property;
  query->QueryType = PropertyStandardQuery;

  auto* protocol = reinterpret_cast<STORAGE_PROTOCOL_SPECIFIC_DATA*>(
      query->AdditionalParameters);
  protocol->ProtocolType = ProtocolTypeNvme;
  protocol->DataType = NVMeDataTypeLogPage;
  protocol->ProtocolDataRequestValue = kNvmeHealthLogPage;
  protocol->ProtocolDataRequestSubValue = namespace_id;
  protocol->ProtocolDataOffset = sizeof(STORAGE_PROTOCOL_SPECIFIC_DATA);
  protocol->ProtocolDataLength = kNvmeHealthLogSize;

  DWORD returned = 0;
  *error_code = ERROR_SUCCESS;
  if (!DeviceIoControlQuery(disk, IOCTL_STORAGE_QUERY_PROPERTY, buffer.data(),
                            static_cast<DWORD>(buffer.size()), buffer.data(),
                            static_cast<DWORD>(buffer.size()), &returned,
                            error_code)) {
    return false;
  }

  constexpr std::size_t kProtocolOffset =
      offsetof(STORAGE_PROTOCOL_DATA_DESCRIPTOR, ProtocolSpecificData);
  if (returned < sizeof(STORAGE_PROTOCOL_DATA_DESCRIPTOR)) {
    *error_code = ERROR_INVALID_DATA;
    return false;
  }

  const auto* descriptor =
      reinterpret_cast<const STORAGE_PROTOCOL_DATA_DESCRIPTOR*>(buffer.data());
  const auto& result = descriptor->ProtocolSpecificData;
  const std::size_t descriptor_size =
      std::min<std::size_t>(returned, descriptor->Size);
  if (descriptor->Version < sizeof(STORAGE_PROTOCOL_DATA_DESCRIPTOR) ||
      descriptor->Size < sizeof(STORAGE_PROTOCOL_DATA_DESCRIPTOR) ||
      descriptor_size < sizeof(STORAGE_PROTOCOL_DATA_DESCRIPTOR) ||
      result.ProtocolDataOffset < sizeof(STORAGE_PROTOCOL_SPECIFIC_DATA) ||
      result.ProtocolDataOffset > descriptor_size - kProtocolOffset) {
    *error_code = ERROR_INVALID_DATA;
    return false;
  }

  const std::size_t health_offset =
      kProtocolOffset + static_cast<std::size_t>(result.ProtocolDataOffset);
  if (result.ProtocolType != ProtocolTypeNvme ||
      result.DataType != NVMeDataTypeLogPage ||
      result.ProtocolDataLength < kNvmeHealthLogSize ||
      health_offset < kProtocolOffset || health_offset > descriptor_size ||
      kNvmeHealthLogSize > descriptor_size - health_offset) {
    *error_code = ERROR_INVALID_DATA;
    return false;
  }

  const auto* data = buffer.data() + health_offset;
  PopulateNvmeHealthFromLog(data, "Windows NVMe protocol query", health);
  *error_code = health->windows_error;
  return health->available;
}

void PopulateNvmeHealth(HANDLE disk, NvmeHealthData* health) {
  DWORD device_error = ERROR_SUCCESS;
  if (QueryNvmeHealthLog(disk, StorageDeviceProtocolSpecificProperty, 0,
                         &device_error, health)) {
    return;
  }

  DWORD adapter_error = ERROR_SUCCESS;
  if (QueryNvmeHealthLog(disk, StorageAdapterProtocolSpecificProperty, 0,
                         &adapter_error, health)) {
    return;
  }

  // Some adapter drivers require the all-namespaces request even for the
  // controller health log. This mirrors the compatibility fallback used by
  // mature SMART tools while remaining a read-only protocol query.
  DWORD all_namespaces_error = ERROR_SUCCESS;
  if (QueryNvmeHealthLog(disk, StorageAdapterProtocolSpecificProperty,
                         0xffffffff, &all_namespaces_error, health)) {
    return;
  }

  health->available = false;
  health->source = "Windows NVMe protocol query";
  health->reason =
      "The storage driver does not expose the NVMe health log for this disk.";
  health->windows_error = all_namespaces_error != ERROR_SUCCESS
      ? all_namespaces_error
      : (adapter_error == ERROR_SUCCESS ? device_error : adapter_error);
}

void PopulateStorageCounters(HANDLE disk, DiskReport* report) {
  STORAGE_COUNTERS probe{};
  probe.Version = STORAGE_COUNTERS_VERSION_V1;
  probe.Size = sizeof(probe);
  DWORD returned = 0;
  DWORD error_code = ERROR_SUCCESS;
  const bool probe_succeeded = DeviceIoControlQuery(
      disk, IOCTL_STORAGE_GET_COUNTERS, &probe, static_cast<DWORD>(sizeof(probe)),
      &probe, static_cast<DWORD>(sizeof(probe)), &returned, &error_code);
  const DWORD probe_returned = returned;

  DWORD requested_size = probe.Size;
  if (requested_size < sizeof(STORAGE_COUNTERS)) {
    requested_size = sizeof(STORAGE_COUNTERS);
  }
  if (requested_size > kMaximumStorageCountersSize) {
    report->reliability_unavailable_reason =
        "Windows reported an invalid reliability counter size.";
    return;
  }

  std::vector<std::uint8_t> buffer(requested_size, 0);
  auto* request = reinterpret_cast<STORAGE_COUNTERS*>(buffer.data());
  request->Version = STORAGE_COUNTERS_VERSION_V1;
  request->Size = sizeof(STORAGE_COUNTERS);
  returned = 0;
  error_code = ERROR_SUCCESS;
  if (!DeviceIoControlQuery(
          disk, IOCTL_STORAGE_GET_COUNTERS, request,
          static_cast<DWORD>(buffer.size()), request,
          static_cast<DWORD>(buffer.size()), &returned, &error_code)) {
    if (probe_succeeded &&
        probe_returned >= offsetof(STORAGE_COUNTERS, Counters)) {
      // A compact result was already returned by the probe. It still belongs
      // to the same ABI and can be parsed from the probe buffer below.
      buffer.assign(reinterpret_cast<std::uint8_t*>(&probe),
                    reinterpret_cast<std::uint8_t*>(&probe) + sizeof(probe));
      returned = sizeof(probe);
    } else {
      report->reliability_unavailable_reason =
          "The storage driver did not expose supported reliability counters.";
      return;
    }
  }

  constexpr std::size_t kCountersOffset = offsetof(STORAGE_COUNTERS, Counters);
  if (returned < kCountersOffset || buffer.size() < kCountersOffset) {
    report->reliability_unavailable_reason =
        "Windows returned invalid reliability counter metadata.";
    return;
  }
  const auto* counters =
      reinterpret_cast<const STORAGE_COUNTERS*>(buffer.data());
  const std::size_t declared_size = std::min<std::size_t>(
      std::min<std::size_t>(counters->Size, returned), buffer.size());
  if (counters->Version < STORAGE_COUNTERS_VERSION_V1 ||
      declared_size < kCountersOffset) {
    report->reliability_unavailable_reason =
        "Windows returned invalid reliability counter metadata.";
    return;
  }

  const std::size_t capacity =
      (declared_size - kCountersOffset) / sizeof(STORAGE_COUNTER);
  const DWORD count = std::min<DWORD>(
      counters->NumberOfCounters,
      static_cast<DWORD>(std::min<std::size_t>(capacity, 128)));
  bool found = false;
  for (DWORD index = 0; index < count; ++index) {
    const STORAGE_COUNTER& counter = counters->Counters[index];
    const std::uint64_t value = static_cast<std::uint64_t>(counter.Value.AsUlonglong);
    switch (counter.Type) {
      case StorageCounterTypeTemperatureCelsius:
        if (value <= 200) {
          report->temperature_celsius = static_cast<int>(value);
          found = true;
        }
        break;
      case StorageCounterTypeWearPercentage:
        if (value <= 100) {
          report->wear_percent = static_cast<int>(value);
          found = true;
        }
        break;
      case StorageCounterTypeReadErrorsCorrected:
        report->read_errors_corrected = std::to_string(value);
        found = true;
        break;
      case StorageCounterTypeReadErrorsUncorrected:
        report->read_errors_uncorrected = std::to_string(value);
        found = true;
        break;
      case StorageCounterTypeReadErrorsTotal:
        report->read_errors_total = std::to_string(value);
        found = true;
        break;
      case StorageCounterTypeWriteErrorsCorrected:
        report->write_errors_corrected = std::to_string(value);
        found = true;
        break;
      case StorageCounterTypeWriteErrorsUncorrected:
        report->write_errors_uncorrected = std::to_string(value);
        found = true;
        break;
      case StorageCounterTypeWriteErrorsTotal:
        report->write_errors_total = std::to_string(value);
        found = true;
        break;
      case StorageCounterTypePowerOnHours:
        report->power_on_hours = std::to_string(value);
        found = true;
        break;
      default:
        break;
    }
  }
  if (!found) {
    report->reliability_unavailable_reason =
        "The storage driver returned no supported reliability counters.";
  }
}

void PopulatePredictFailure(HANDLE disk, DiskReport* report) {
  STORAGE_PREDICT_FAILURE prediction{};
  DWORD returned = 0;
  DWORD error_code = ERROR_SUCCESS;
  if (!DeviceIoControlQuery(disk, IOCTL_STORAGE_PREDICT_FAILURE, nullptr, 0,
                            &prediction,
                            static_cast<DWORD>(sizeof(prediction)), &returned,
                            &error_code) ||
      returned < sizeof(prediction)) {
    return;
  }
  report->health = prediction.PredictFailure == 0
      ? "no_failure_predicted"
      : "failure_predicted";
  report->health_source = "Windows SMART failure prediction";
}

bool QueryScsiAddress(HANDLE disk, SCSI_ADDRESS* address, DWORD* error_code) {
  DWORD returned = 0;
  return DeviceIoControlQuery(disk, IOCTL_SCSI_GET_ADDRESS, nullptr, 0, address,
                              static_cast<DWORD>(sizeof(*address)), &returned,
                              error_code) &&
         returned >= sizeof(*address);
}

void PopulateIntelRstNvmeHealth(HANDLE disk, NvmeHealthData* health) {
  SCSI_ADDRESS address{};
  DWORD error_code = ERROR_SUCCESS;
  if (!QueryScsiAddress(disk, &address, &error_code)) {
    health->reason = "Intel RST did not expose a SCSI address for this disk.";
    health->source = "Intel RST NVMe miniport protocol";
    health->windows_error = error_code == ERROR_SUCCESS ? ERROR_INVALID_DATA
                                                         : error_code;
    return;
  }

  const std::wstring controller =
      L"\\\\.\\Scsi" + std::to_wstring(address.PortNumber) + L":";
  ScopedHandle miniport(CreateFileW(
      controller.c_str(), GENERIC_READ | GENERIC_WRITE,
      FILE_SHARE_READ | FILE_SHARE_WRITE, nullptr, OPEN_EXISTING,
      FILE_ATTRIBUTE_NORMAL, nullptr));
  if (!miniport.valid()) {
    health->reason =
        "Intel RST denied the read-only NVMe health-log miniport request.";
    health->source = "Intel RST NVMe miniport protocol";
    health->windows_error = GetLastError();
    return;
  }

  IntelRstNvmePassThrough request{};
  request.srb.HeaderLength = sizeof(SRB_IO_CONTROL);
  std::memcpy(request.srb.Signature, "IntelNvm", sizeof(request.srb.Signature));
  request.srb.Timeout = 10;
  request.srb.ControlCode = kIntelRstNvmeControlCode;
  request.srb.Length =
      static_cast<ULONG>(sizeof(request) - sizeof(SRB_IO_CONTROL));
  request.payload.version = 1;
  request.payload.path_id = address.PathId;
  request.payload.command[0] = 0x02;  // NVMe Admin Get Log Page.
  request.payload.command[1] = 0xffffffff;  // All namespaces.
  request.payload.command[10] = 0x007f0002;  // SMART / Health log, 512 bytes.
  request.payload.parameter_buffer_length =
      static_cast<DWORD>(sizeof(IntelRstNvmePayload) + sizeof(SRB_IO_CONTROL));
  request.payload.return_buffer_length = static_cast<DWORD>(request.data.size());

  DWORD returned = 0;
  if (DeviceIoControl(miniport.get(), IOCTL_SCSI_MINIPORT, &request,
                      static_cast<DWORD>(sizeof(request)), &request,
                      static_cast<DWORD>(sizeof(request)), &returned,
                      nullptr) == FALSE) {
    health->reason =
        "Intel RST did not expose the NVMe health log for this disk.";
    health->source = "Intel RST NVMe miniport protocol";
    health->windows_error = GetLastError();
    return;
  }
  PopulateNvmeHealthFromLog(request.data.data(),
                            "Intel RST NVMe miniport protocol", health);
}

void PopulateIntelVrocNvmeHealth(HANDLE disk, NvmeHealthData* health) {
  SCSI_ADDRESS address{};
  DWORD error_code = ERROR_SUCCESS;
  if (!QueryScsiAddress(disk, &address, &error_code)) {
    health->reason = "Intel VROC did not expose a SCSI address for this disk.";
    health->source = "Intel VROC NVMe miniport protocol";
    health->windows_error = error_code == ERROR_SUCCESS ? ERROR_INVALID_DATA
                                                         : error_code;
    return;
  }

  const std::wstring controller =
      L"\\\\.\\Scsi" + std::to_wstring(address.PortNumber) + L":";
  ScopedHandle miniport(CreateFileW(
      controller.c_str(), GENERIC_READ | GENERIC_WRITE,
      FILE_SHARE_READ | FILE_SHARE_WRITE, nullptr, OPEN_EXISTING,
      FILE_ATTRIBUTE_NORMAL, nullptr));
  if (!miniport.valid()) {
    health->reason =
        "Intel VROC denied the read-only NVMe health-log miniport request.";
    health->source = "Intel VROC NVMe miniport protocol";
    health->windows_error = GetLastError();
    return;
  }

  IntelVrocNvmePassThrough request{};
  request.srb.HeaderLength = sizeof(SRB_IO_CONTROL);
  std::memcpy(request.srb.Signature, "NvmeRAID", sizeof(request.srb.Signature));
  request.srb.Timeout = 10;
  request.srb.ControlCode = kIntelVrocNvmeControlCode;
  request.srb.Length =
      static_cast<ULONG>(sizeof(request) - sizeof(SRB_IO_CONTROL));
  request.srb.ReturnCode = 0x86000000u +
      (static_cast<DWORD>(address.PathId) << 16u) +
      (static_cast<DWORD>(address.TargetId) << 8u) + address.Lun;
  request.direction = 2;  // Device to host.
  request.queue_id = 0;
  request.data_buffer_length = static_cast<DWORD>(request.data.size());
  request.metadata_length = 0;
  request.return_buffer_length = static_cast<DWORD>(sizeof(request));
  request.command[0] = 0x02;  // NVMe Admin Get Log Page.
  request.command[1] = 0xffffffff;  // All namespaces.
  request.command[10] = 0x007f0002;  // SMART / Health log, 512 bytes.

  DWORD returned = 0;
  if (DeviceIoControl(miniport.get(), IOCTL_SCSI_MINIPORT, &request,
                      static_cast<DWORD>(sizeof(request)), &request,
                      static_cast<DWORD>(sizeof(request)), &returned,
                      nullptr) == FALSE) {
    health->reason =
        "Intel VROC did not expose the NVMe health log for this disk.";
    health->source = "Intel VROC NVMe miniport protocol";
    health->windows_error = GetLastError();
    return;
  }
  PopulateNvmeHealthFromLog(request.data.data(),
                            "Intel VROC NVMe miniport protocol", health);
}

std::vector<std::string> FindDriveLettersForDisk(DWORD disk_number) {
  std::vector<std::string> letters;
  const DWORD logical_drives = GetLogicalDrives();
  for (unsigned int index = 0; index < 26; ++index) {
    if ((logical_drives & (1UL << index)) == 0) {
      continue;
    }
    const wchar_t letter = static_cast<wchar_t>(L'A' + index);
    const std::wstring root = std::wstring(1, letter) + L":\\";
    const UINT drive_type = GetDriveTypeW(root.c_str());
    if (drive_type != DRIVE_FIXED && drive_type != DRIVE_REMOVABLE) {
      continue;
    }
    const std::wstring volume_path = L"\\\\.\\" + std::wstring(1, letter) + L":";
    HANDLE volume = CreateFileW(volume_path.c_str(), 0,
                                FILE_SHARE_READ | FILE_SHARE_WRITE, nullptr,
                                OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, nullptr);
    if (volume == INVALID_HANDLE_VALUE) {
      continue;
    }
    STORAGE_DEVICE_NUMBER number{};
    DWORD returned = 0;
    const BOOL succeeded = DeviceIoControl(
        volume, IOCTL_STORAGE_GET_DEVICE_NUMBER, nullptr, 0, &number,
        static_cast<DWORD>(sizeof(number)), &returned, nullptr);
    CloseHandle(volume);
    if (succeeded != FALSE && returned >= sizeof(number) &&
        number.DeviceNumber == disk_number) {
      letters.push_back(std::string(1, static_cast<char>('A' + index)) + ":\\");
    }
  }
  return letters;
}

bool IsWindowsSystemDrive(const std::vector<std::string>& drive_letters) {
  std::array<wchar_t, MAX_PATH> windows_directory{};
  const UINT length = GetWindowsDirectoryW(
      windows_directory.data(), static_cast<UINT>(windows_directory.size()));
  if (length < 2 || length >= static_cast<UINT>(windows_directory.size()) ||
      windows_directory[1] != L':') {
    return false;
  }
  const char drive_letter = static_cast<char>(
      std::towupper(static_cast<wint_t>(windows_directory[0])));
  const std::string root = std::string(1, drive_letter) + ":\\";
  return std::find(drive_letters.begin(), drive_letters.end(), root) !=
         drive_letters.end();
}

std::string BuildDiskReportJson(const DiskReport& report) {
  std::ostringstream output;
  output << '{';
  output << "\"present\":" << (report.present ? "true" : "false");
  output << ",\"diskNumber\":" << report.disk_number;
  output << ",\"model\":";
  AppendOptionalString(output, report.model);
  output << ",\"sizeBytes\":";
  AppendOptionalString(output, report.size_bytes);
  output << ",\"serialNumber\":";
  AppendOptionalString(output, report.serial_number);
  output << ",\"uniqueId\":";
  AppendOptionalString(output, report.unique_id);
  output << ",\"busType\":";
  AppendOptionalString(output, report.bus_type);
  output << ",\"vendorId\":";
  AppendOptionalString(output, report.vendor_id);
  output << ",\"productId\":";
  AppendOptionalString(output, report.product_id);
  output << ",\"health\":";
  AppendOptionalString(output, report.health);
  output << ",\"healthSource\":";
  AppendOptionalString(output, report.health_source);
  output << ",\"temperatureCelsius\":";
  AppendOptionalInt(output, report.temperature_celsius);
  output << ",\"wearPercent\":";
  AppendOptionalInt(output, report.wear_percent);
  output << ",\"readErrorsCorrected\":";
  AppendOptionalString(output, report.read_errors_corrected);
  output << ",\"readErrorsUncorrected\":";
  AppendOptionalString(output, report.read_errors_uncorrected);
  output << ",\"readErrorsTotal\":";
  AppendOptionalString(output, report.read_errors_total);
  output << ",\"writeErrorsCorrected\":";
  AppendOptionalString(output, report.write_errors_corrected);
  output << ",\"writeErrorsUncorrected\":";
  AppendOptionalString(output, report.write_errors_uncorrected);
  output << ",\"writeErrorsTotal\":";
  AppendOptionalString(output, report.write_errors_total);
  output << ",\"powerOnHours\":";
  AppendOptionalString(output, report.power_on_hours);
  output << ",\"firmwareVersion\":";
  AppendOptionalString(output, report.firmware_version);
  output << ",\"mediaType\":";
  AppendOptionalString(output, report.media_type);
  output << ",\"partitionStyle\":";
  AppendOptionalString(output, report.partition_style);
  output << ",\"operationalStatus\":";
  AppendOptionalString(output, report.operational_status);
  output << ",\"pnpDeviceId\":";
  AppendOptionalString(output, report.pnp_device_id);
  output << ",\"devicePath\":";
  AppendJsonString(output, report.device_path);
  output << ",\"driveLetters\":";
  AppendJsonStringArray(output, report.drive_letters);
  output << ",\"isSystem\":";
  AppendOptionalBool(output, report.is_system);
  output << ",\"isBoot\":";
  AppendOptionalBool(output, report.is_boot);
  output << ",\"isOffline\":";
  AppendOptionalBool(output, report.is_offline);
  output << ",\"isReadOnly\":";
  AppendOptionalBool(output, report.is_read_only);
  output << ",\"isRemovable\":";
  AppendOptionalBool(output, report.is_removable);
  output << ",\"reliabilityUnavailableReason\":";
  AppendJsonString(output, report.reliability_unavailable_reason);
  output << ",\"topology\":{";
  output << "\"deviceType\":";
  AppendOptionalDword(output, report.topology.device_type);
  output << ",\"deviceNumber\":";
  AppendOptionalDword(output, report.topology.device_number);
  output << ",\"partitionNumber\":";
  AppendOptionalDword(output, report.topology.partition_number);
  output << ",\"mediaRemovable\":";
  AppendOptionalBool(output, report.topology.media_removable);
  output << ",\"mediaHotplug\":";
  AppendOptionalBool(output, report.topology.media_hotplug);
  output << ",\"deviceHotplug\":";
  AppendOptionalBool(output, report.topology.device_hotplug);
  output << '}';
  output << ",\"nvme\":{";
  output << "\"available\":" << (report.nvme.available ? "true" : "false");
  output << ",\"source\":";
  AppendJsonString(output, report.nvme.source);
  output << ",\"reason\":";
  if (report.nvme.available) {
    output << "null";
  } else {
    AppendJsonString(output, report.nvme.reason);
  }
  output << ",\"windowsError\":";
  if (report.nvme.windows_error == ERROR_SUCCESS) {
    output << "null";
  } else {
    output << report.nvme.windows_error;
  }
  output << ",\"temperatureCelsius\":";
  AppendOptionalInt(output, report.nvme.temperature_celsius);
  output << ",\"percentageUsed\":";
  AppendOptionalInt(output, report.nvme.percentage_used);
  output << ",\"hostReadBytes\":";
  AppendOptionalString(output, report.nvme.host_read_bytes);
  output << ",\"hostWrittenBytes\":";
  AppendOptionalString(output, report.nvme.host_written_bytes);
  output << ",\"hostReadCommands\":";
  AppendOptionalString(output, report.nvme.host_read_commands);
  output << ",\"hostWriteCommands\":";
  AppendOptionalString(output, report.nvme.host_write_commands);
  output << ",\"powerOnHours\":";
  AppendOptionalString(output, report.nvme.power_on_hours);
  output << ",\"mediaAndDataIntegrityErrors\":";
  AppendOptionalString(output, report.nvme.media_and_data_integrity_errors);
  output << '}';
  output << ",\"warnings\":";
  AppendJsonStringArray(output, report.warnings);
  output << '}';
  return output.str();
}

DiskReport MakeUnavailableReport(DWORD disk_number, std::string reason,
                                 DWORD error_code) {
  DiskReport report;
  report.disk_number = disk_number;
  report.device_path = "\\\\.\\PhysicalDrive" + std::to_string(disk_number);
  report.nvme.reason = std::move(reason);
  report.nvme.windows_error = error_code;
  return report;
}

DiskReport CollectDiskReport(DWORD disk_number, bool* present) {
  DiskReport report;
  report.disk_number = disk_number;
  report.device_path = "\\\\.\\PhysicalDrive" + std::to_string(disk_number);

  DWORD open_error = ERROR_SUCCESS;
  const HANDLE disk = OpenPhysicalDiskForReadOnlyQuery(
      L"\\\\.\\PhysicalDrive" + std::to_wstring(disk_number), &open_error);
  if (disk == INVALID_HANDLE_VALUE) {
    if (IsMissingPhysicalDriveError(open_error)) {
      report.present = false;
      *present = false;
      report.nvme.reason = "The physical disk is not present.";
      report.nvme.windows_error = open_error;
      return report;
    }
    *present = true;
    report.nvme.reason =
        "Windows could not open the physical disk for a read-only query.";
    report.nvme.windows_error = open_error;
    AddQueryWarning(&report, "Physical disk open", open_error);
    return report;
  }

  *present = true;
  PopulateDeviceDescriptor(disk, &report);
  PopulateLength(disk, &report);
  PopulateTopology(disk, &report);
  PopulatePartitionStyle(disk, &report);
  PopulateReadOnlyFlag(disk, &report);
  PopulateStorageCounters(disk, &report);
  PopulatePredictFailure(disk, &report);

  DWORD identifier_error = ERROR_SUCCESS;
  report.unique_id = QueryStorageIdentifier(disk, &identifier_error);
  if (!report.unique_id.has_value() && identifier_error != ERROR_NOT_FOUND) {
    AddQueryWarning(&report, "Storage unique identifier", identifier_error);
  }

  PopulateNvmeHealth(disk, &report.nvme);
  if (!report.nvme.available && report.bus_type.has_value() &&
      *report.bus_type == "RAID") {
    PopulateIntelRstNvmeHealth(disk, &report.nvme);
    if (!report.nvme.available) {
      PopulateIntelVrocNvmeHealth(disk, &report.nvme);
    }
  }
  if (report.nvme.available) {
    report.health = report.nvme.critical_warning == 0 ? "healthy" : "warning";
    report.health_source = report.nvme.source;
  }
  CloseHandle(disk);

  report.drive_letters = FindDriveLettersForDisk(disk_number);
  report.is_system = IsWindowsSystemDrive(report.drive_letters);
  return report;
}

bool GetExecutablePath(std::wstring* path, DWORD* error_code) {
  std::vector<wchar_t> buffer(32768, L'\0');
  const DWORD length = GetModuleFileNameW(nullptr, buffer.data(),
                                           static_cast<DWORD>(buffer.size()));
  if (length == 0 || length >= buffer.size()) {
    *error_code = length == 0 ? GetLastError() : ERROR_INSUFFICIENT_BUFFER;
    return false;
  }
  path->assign(buffer.data(), length);
  *error_code = ERROR_SUCCESS;
  return true;
}

void DrainPipe(HANDLE pipe, std::string* output, bool* output_truncated) {
  std::array<char, 4096> buffer{};
  for (;;) {
    DWORD available = 0;
    if (PeekNamedPipe(pipe, nullptr, 0, nullptr, &available, nullptr) == FALSE ||
        available == 0) {
      return;
    }
    const DWORD to_read = static_cast<DWORD>(
        std::min<std::size_t>(buffer.size(), static_cast<std::size_t>(available)));
    DWORD read = 0;
    if (ReadFile(pipe, buffer.data(), to_read, &read, nullptr) == FALSE ||
        read == 0) {
      return;
    }
    const std::size_t remaining =
        output->size() < kMaximumWorkerOutputLength
            ? kMaximumWorkerOutputLength - output->size()
            : 0;
    const std::size_t copied = std::min<std::size_t>(remaining, read);
    output->append(buffer.data(), copied);
    if (copied < read) {
      *output_truncated = true;
    }
  }
}

ChildWorkerResult RunDiskWorker(DWORD disk_number, DWORD timeout_milliseconds) {
  ChildWorkerResult result;
  DWORD path_error = ERROR_SUCCESS;
  std::wstring executable;
  if (!GetExecutablePath(&executable, &path_error)) {
    result.error_code = path_error;
    return result;
  }

  SECURITY_ATTRIBUTES inheritable{};
  inheritable.nLength = sizeof(inheritable);
  inheritable.bInheritHandle = TRUE;

  HANDLE stdout_read_raw = nullptr;
  HANDLE stdout_write_raw = nullptr;
  if (CreatePipe(&stdout_read_raw, &stdout_write_raw, &inheritable, 16 * 1024) ==
      FALSE) {
    result.error_code = GetLastError();
    return result;
  }
  ScopedHandle stdout_read(stdout_read_raw);
  ScopedHandle stdout_write(stdout_write_raw);
  if (SetHandleInformation(stdout_read.get(), HANDLE_FLAG_INHERIT, 0) == FALSE) {
    result.error_code = GetLastError();
    return result;
  }

  ScopedHandle null_input(CreateFileW(
      L"NUL", GENERIC_READ, FILE_SHARE_READ | FILE_SHARE_WRITE, &inheritable,
      OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, nullptr));
  ScopedHandle null_error(CreateFileW(
      L"NUL", GENERIC_WRITE, FILE_SHARE_READ | FILE_SHARE_WRITE, &inheritable,
      OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, nullptr));
  if (!null_input.valid() || !null_error.valid()) {
    result.error_code = GetLastError();
    return result;
  }

  const std::wstring command_line =
      L"\"" + executable + L"\" --disk " + std::to_wstring(disk_number);
  std::vector<wchar_t> mutable_command(command_line.begin(), command_line.end());
  mutable_command.push_back(L'\0');

  STARTUPINFOW startup{};
  startup.cb = sizeof(startup);
  startup.dwFlags = STARTF_USESTDHANDLES;
  startup.hStdInput = null_input.get();
  startup.hStdOutput = stdout_write.get();
  startup.hStdError = null_error.get();

  PROCESS_INFORMATION process{};
  if (CreateProcessW(executable.c_str(), mutable_command.data(), nullptr, nullptr,
                     TRUE, CREATE_NO_WINDOW | CREATE_SUSPENDED, nullptr,
                     nullptr, &startup, &process) == FALSE) {
    result.error_code = GetLastError();
    return result;
  }
  result.started = true;
  ScopedHandle process_handle(process.hProcess);
  ScopedHandle thread_handle(process.hThread);
  stdout_write.Reset();
  null_input.Reset();
  null_error.Reset();

  ScopedHandle job(CreateJobObjectW(nullptr, nullptr));
  if (!job.valid()) {
    result.error_code = GetLastError();
    TerminateProcess(process_handle.get(), result.error_code);
    return result;
  }
  JOBOBJECT_EXTENDED_LIMIT_INFORMATION limits{};
  limits.BasicLimitInformation.LimitFlags = JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE;
  if (SetInformationJobObject(job.get(), JobObjectExtendedLimitInformation,
                              &limits, sizeof(limits)) == FALSE ||
      AssignProcessToJobObject(job.get(), process_handle.get()) == FALSE) {
    result.error_code = GetLastError();
    TerminateProcess(process_handle.get(), result.error_code);
    return result;
  }
  if (ResumeThread(thread_handle.get()) == static_cast<DWORD>(-1)) {
    result.error_code = GetLastError();
    TerminateProcess(process_handle.get(), result.error_code);
    return result;
  }

  const ULONGLONG deadline = GetTickCount64() +
                             std::min(kDiskWorkerTimeoutMilliseconds,
                                      timeout_milliseconds);
  for (;;) {
    DrainPipe(stdout_read.get(), &result.output, &result.output_truncated);
    const ULONGLONG now = GetTickCount64();
    if (now >= deadline) {
      result.timed_out = true;
      result.error_code = ERROR_TIMEOUT;
      TerminateProcess(process_handle.get(), ERROR_TIMEOUT);
      WaitForSingleObject(process_handle.get(), kWorkerTerminationGraceMilliseconds);
      DrainPipe(stdout_read.get(), &result.output, &result.output_truncated);
      return result;
    }
    const DWORD remaining = static_cast<DWORD>(deadline - now);
    const DWORD wait = WaitForSingleObject(process_handle.get(),
                                           std::min<DWORD>(remaining, 25));
    if (wait == WAIT_OBJECT_0) {
      break;
    }
    if (wait == WAIT_FAILED) {
      result.error_code = GetLastError();
      TerminateProcess(process_handle.get(), result.error_code);
      WaitForSingleObject(process_handle.get(), kWorkerTerminationGraceMilliseconds);
      return result;
    }
  }

  DrainPipe(stdout_read.get(), &result.output, &result.output_truncated);
  if (GetExitCodeProcess(process_handle.get(), &result.exit_code) == FALSE) {
    result.error_code = GetLastError();
  }
  return result;
}

bool IsExpectedWorkerReport(const std::string& text, DWORD disk_number) {
  const std::string report = TrimAscii(text);
  if (report.size() < 2 || report.front() != '{' || report.back() != '}') {
    return false;
  }
  const std::string expected_number =
      "\"diskNumber\":" + std::to_string(disk_number);
  return report.find(expected_number) != std::string::npos &&
         report.find("\"nvme\":{") != std::string::npos;
}

std::string BuildInventoryJson(bool ok, const std::vector<std::string>& reports,
                               const std::vector<std::string>& warnings) {
  std::ostringstream output;
  output << "{\"ok\":" << (ok ? "true" : "false")
         << ",\"isAdministrator\":" << (IsAdministrator() ? "true" : "false")
         << ",\"reports\":[";
  for (std::size_t index = 0; index < reports.size(); ++index) {
    if (index > 0) {
      output << ',';
    }
    output << TrimAscii(reports[index]);
  }
  output << "],\"warnings\":";
  AppendDiagnosticWarningArray(output, warnings);
  output << '}';
  return output.str();
}

int RunDiskMode(DWORD disk_number) {
  bool present = false;
  const DiskReport report = CollectDiskReport(disk_number, &present);
  std::cout << BuildDiskReportJson(report) << std::endl;
  return present ? 0 : kDiskNotPresentExitCode;
}

int RunInventoryMode() {
  std::vector<std::string> reports;
  std::vector<std::string> warnings;
  const ULONGLONG started = GetTickCount64();
  for (DWORD disk_number = 0; disk_number <= kMaximumPhysicalDriveNumber;
       ++disk_number) {
    const ULONGLONG elapsed = GetTickCount64() - started;
    if (elapsed >= kInventoryTimeoutMilliseconds) {
      warnings.push_back(
          "The read-only inventory deadline was reached before PhysicalDrive" +
          std::to_string(disk_number) + " could be queried.");
      break;
    }
    if (!HasPhysicalDriveAlias(disk_number)) {
      continue;
    }
    const DWORD remaining =
        kInventoryTimeoutMilliseconds - static_cast<DWORD>(elapsed);
    ChildWorkerResult worker = RunDiskWorker(disk_number, remaining);
    if (!worker.started) {
      const std::string reason =
          "The isolated read-only disk worker could not be started.";
      reports.push_back(BuildDiskReportJson(
          MakeUnavailableReport(disk_number, reason, worker.error_code)));
      warnings.push_back("PhysicalDrive" + std::to_string(disk_number) +
                         " worker launch failed (Win32=" +
                         std::to_string(worker.error_code) + ").");
      continue;
    }
    if (worker.timed_out) {
      const std::string reason =
          "The isolated read-only disk query timed out and was terminated.";
      reports.push_back(
          BuildDiskReportJson(MakeUnavailableReport(disk_number, reason,
                                                     ERROR_TIMEOUT)));
      warnings.push_back("PhysicalDrive" + std::to_string(disk_number) +
                         " exceeded the read-only query deadline.");
      continue;
    }
    if (worker.exit_code == kDiskNotPresentExitCode) {
      continue;
    }
    if (worker.exit_code != 0 || worker.output_truncated ||
        !IsExpectedWorkerReport(worker.output, disk_number)) {
      const DWORD error_code = worker.error_code == ERROR_SUCCESS
                                   ? ERROR_INVALID_DATA
                                   : worker.error_code;
      reports.push_back(BuildDiskReportJson(MakeUnavailableReport(
          disk_number, "The isolated read-only disk worker returned no valid "
                       "inventory response.",
          error_code)));
      warnings.push_back("PhysicalDrive" + std::to_string(disk_number) +
                         " worker response was invalid.");
      continue;
    }
    reports.push_back(TrimAscii(worker.output));
  }

  std::cout << BuildInventoryJson(true, reports, warnings) << std::endl;
  return 0;
}

bool ParseDiskNumber(const wchar_t* value, DWORD* disk_number) {
  if (value == nullptr || *value == L'\0') {
    return false;
  }
  for (const wchar_t* character = value; *character != L'\0'; ++character) {
    if (*character < L'0' || *character > L'9') {
      return false;
    }
  }
  wchar_t* end = nullptr;
  const unsigned long parsed = wcstoul(value, &end, 10);
  if (end == value || *end != L'\0' || parsed > kMaximumDiskNumber) {
    return false;
  }
  *disk_number = static_cast<DWORD>(parsed);
  return true;
}

void PrintUsageError() {
  std::cout << "{\"ok\":false,\"isAdministrator\":"
            << (IsAdministrator() ? "true" : "false")
            << ",\"reports\":[],\"warnings\":[\"Expected --inventory or "
               "--disk <physical-disk-number>.\"]}"
            << std::endl;
}

}  // namespace

int wmain(int argc, wchar_t* argv[]) {
  if (argc == 2 && std::wstring(argv[1]) == L"--inventory") {
    return RunInventoryMode();
  }

  DWORD disk_number = 0;
  if (argc == 3 && std::wstring(argv[1]) == L"--disk" &&
      ParseDiskNumber(argv[2], &disk_number)) {
    return RunDiskMode(disk_number);
  }

  // Preserve the previous single-number form for manual diagnostics. The
  // inventory coordinator always invokes the explicit --disk worker mode.
  if (argc == 2 && ParseDiskNumber(argv[1], &disk_number)) {
    return RunDiskMode(disk_number);
  }

  PrintUsageError();
  return 2;
}
