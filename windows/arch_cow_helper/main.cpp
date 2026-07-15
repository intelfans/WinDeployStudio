#include <windows.h>
#include <bcrypt.h>
#include <ntddstor.h>
#include <winioctl.h>

#include <algorithm>
#include <array>
#include <chrono>
#include <cstddef>
#include <cstdint>
#include <cstring>
#include <iomanip>
#include <iostream>
#include <iterator>
#include <limits>
#include <optional>
#include <sstream>
#include <string>
#include <string_view>
#include <utility>
#include <vector>

#pragma comment(lib, "bcrypt.lib")

namespace {

// This helper has one deliberately narrow responsibility: format the exact
// third GPT partition created for an Arch Linux To Go device. It never opens a
// PhysicalDrive for writing; every filesystem write goes through the bounded
// \\.\HarddiskNPartitionM handle after the physical-drive layout has been
// checked twice.
constexpr std::uint64_t kMiB = 1024ull * 1024ull;
constexpr std::uint64_t kGiB = 1024ull * kMiB;
constexpr std::uint64_t kMinimumPartitionBytes = 4ull * kMiB;
constexpr std::uint64_t kMaximumPartitionBytes = 16ull * kGiB;
constexpr std::uint32_t kBlockSize = 4096;
constexpr std::uint32_t kBlocksPerGroup = 32768;
constexpr std::uint32_t kInodesPerGroup = 8192;
constexpr std::uint32_t kInodeSize = 256;
constexpr std::uint32_t kInodeTableBlocks =
    (kInodesPerGroup * kInodeSize) / kBlockSize;
constexpr std::uint32_t kMaximumGroupCount = 128;
constexpr std::uint16_t kExt4Magic = 0xEF53;
constexpr std::uint16_t kExt4StateClean = 1;
constexpr std::uint16_t kExt4ErrorsContinue = 1;
constexpr std::uint32_t kExt4CompatExtAttr = 0x0008;
constexpr std::uint32_t kExt4IncompatFileType = 0x0002;
constexpr std::uint32_t kExt4IncompatExtents = 0x0040;
constexpr std::uint32_t kExt4RoCompatSparseSuper = 0x0001;
constexpr std::uint32_t kExt4RoCompatLargeFile = 0x0002;
constexpr std::uint32_t kExt4RoCompatExtraIsize = 0x0040;
constexpr std::uint32_t kInodeFlagExtents = 0x00080000;
constexpr std::uint16_t kExtentMagic = 0xF30A;
constexpr std::uint32_t kFirstNonReservedInode = 11;
constexpr std::uint32_t kRootInode = 2;
constexpr std::uint32_t kLostFoundInode = 11;
constexpr std::uint32_t kCowDirectoryInode = 12;
constexpr DWORD kMaximumDiskNumber = 9999;
constexpr std::size_t kMaximumLayoutBytes = 1024 * 1024;
constexpr std::size_t kZeroBufferBytes = 1024 * 1024;

// EFI GPT Linux filesystem data partition type.
const GUID kLinuxFilesystemPartitionType = {
    0x0FC63DAF,
    0x8483,
    0x4772,
    {0x8E, 0x79, 0x3D, 0x69, 0xD8, 0x47, 0x7D, 0xE4},
};

class ScopedHandle {
 public:
  explicit ScopedHandle(HANDLE handle = INVALID_HANDLE_VALUE) : handle_(handle) {}

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
    handle_ = INVALID_HANDLE_VALUE;
    return handle;
  }

  void Reset(HANDLE handle = INVALID_HANDLE_VALUE) {
    if (valid()) {
      CloseHandle(handle_);
    }
    handle_ = handle;
  }

 private:
  HANDLE handle_;
};

class VolumeLock {
 public:
  VolumeLock() = default;
  ~VolumeLock() {
    if (locked_ && handle_ != INVALID_HANDLE_VALUE) {
      DWORD ignored = 0;
      DeviceIoControl(handle_, FSCTL_UNLOCK_VOLUME, nullptr, 0, nullptr, 0,
                      &ignored, nullptr);
    }
  }

  VolumeLock(const VolumeLock&) = delete;
  VolumeLock& operator=(const VolumeLock&) = delete;

  bool Lock(HANDLE handle, std::string* error) {
    DWORD bytes_returned = 0;
    if (!DeviceIoControl(handle, FSCTL_LOCK_VOLUME, nullptr, 0, nullptr, 0,
                         &bytes_returned, nullptr)) {
      const DWORD code = GetLastError();
      // A fresh Linux GPT partition normally has no Windows volume object.
      // The exclusive partition handle remains the required ownership guard in
      // this case. Any other failure means a mounted or busy target is refused.
      if (code == ERROR_INVALID_FUNCTION) {
        return true;
      }
      *error = "lock target partition (Win32=" + std::to_string(code) + ")";
      return false;
    }
    handle_ = handle;
    locked_ = true;
    if (!DeviceIoControl(handle, FSCTL_DISMOUNT_VOLUME, nullptr, 0, nullptr,
                         0, &bytes_returned, nullptr)) {
      const DWORD code = GetLastError();
      *error = "dismount target partition (Win32=" + std::to_string(code) +
               ")";
      return false;
    }
    return true;
  }

 private:
  HANDLE handle_ = INVALID_HANDLE_VALUE;
  bool locked_ = false;
};

struct Arguments {
  DWORD disk_number = 0;
  GUID disk_guid{};
  DWORD partition_number = 0;
  GUID partition_guid{};
  std::uint64_t partition_offset_bytes = 0;
  std::uint64_t partition_size_bytes = 0;
  DWORD parent_pid = 0;
};

struct GroupLayout {
  std::uint32_t index = 0;
  std::uint32_t start_block = 0;
  std::uint32_t block_count = 0;
  std::uint32_t superblock_block = 0;
  std::uint32_t gdt_start_block = 0;
  std::uint32_t block_bitmap_block = 0;
  std::uint32_t inode_bitmap_block = 0;
  std::uint32_t inode_table_start_block = 0;
  std::uint32_t first_data_block = 0;
  std::uint32_t overhead_blocks = 0;
  bool has_backup_superblock = false;
};

struct FilesystemLayout {
  std::uint32_t total_blocks = 0;
  std::uint32_t group_count = 0;
  std::uint32_t group_descriptor_blocks = 0;
  std::uint32_t total_inodes = 0;
  std::uint32_t free_blocks = 0;
  std::uint32_t free_inodes = 0;
  std::uint32_t root_data_block = 0;
  std::uint32_t lost_found_data_block = 0;
  std::uint32_t cow_directory_data_block = 0;
  std::vector<GroupLayout> groups;
};

struct DriveLayoutBuffer {
  std::vector<std::uint8_t> bytes;

  DRIVE_LAYOUT_INFORMATION_EX* get() {
    return reinterpret_cast<DRIVE_LAYOUT_INFORMATION_EX*>(bytes.data());
  }

  const DRIVE_LAYOUT_INFORMATION_EX* get() const {
    return reinterpret_cast<const DRIVE_LAYOUT_INFORMATION_EX*>(bytes.data());
  }
};

struct TargetPartition {
  PARTITION_INFORMATION_EX partition{};
  std::uint32_t logical_sector_size = 0;
};

int HexDigit(wchar_t value) {
  if (value >= L'0' && value <= L'9') {
    return value - L'0';
  }
  if (value >= L'a' && value <= L'f') {
    return value - L'a' + 10;
  }
  if (value >= L'A' && value <= L'F') {
    return value - L'A' + 10;
  }
  return -1;
}

bool ParseUnsigned(std::wstring_view value, std::uint64_t* output) {
  if (value.empty()) {
    return false;
  }
  std::uint64_t result = 0;
  for (const wchar_t character : value) {
    if (character < L'0' || character > L'9') {
      return false;
    }
    const std::uint64_t digit = static_cast<std::uint64_t>(character - L'0');
    if (result > (std::numeric_limits<std::uint64_t>::max() - digit) / 10) {
      return false;
    }
    result = result * 10 + digit;
  }
  *output = result;
  return true;
}

bool ParseHex(std::wstring_view value, std::uint64_t* output) {
  if (value.empty() || value.size() > 16) {
    return false;
  }
  std::uint64_t result = 0;
  for (const wchar_t character : value) {
    const int digit = HexDigit(character);
    if (digit < 0 || result > (std::numeric_limits<std::uint64_t>::max() >> 4)) {
      return false;
    }
    result = (result << 4) | static_cast<std::uint64_t>(digit);
  }
  *output = result;
  return true;
}

bool ParseGuid(std::wstring_view value, GUID* guid) {
  if (value.size() != 36 || value[8] != L'-' || value[13] != L'-' ||
      value[18] != L'-' || value[23] != L'-') {
    return false;
  }
  std::uint64_t parsed = 0;
  if (!ParseHex(value.substr(0, 8), &parsed)) {
    return false;
  }
  guid->Data1 = static_cast<unsigned long>(parsed);
  if (!ParseHex(value.substr(9, 4), &parsed)) {
    return false;
  }
  guid->Data2 = static_cast<unsigned short>(parsed);
  if (!ParseHex(value.substr(14, 4), &parsed)) {
    return false;
  }
  guid->Data3 = static_cast<unsigned short>(parsed);
  for (std::size_t index = 0; index < 2; ++index) {
    if (!ParseHex(value.substr(19 + index * 2, 2), &parsed)) {
      return false;
    }
    guid->Data4[index] = static_cast<unsigned char>(parsed);
  }
  for (std::size_t index = 0; index < 6; ++index) {
    if (!ParseHex(value.substr(24 + index * 2, 2), &parsed)) {
      return false;
    }
    guid->Data4[index + 2] = static_cast<unsigned char>(parsed);
  }
  return true;
}

bool GuidEqual(const GUID& first, const GUID& second) {
  return std::memcmp(&first, &second, sizeof(GUID)) == 0;
}

bool GuidIsZero(const GUID& value) {
  const GUID zero{};
  return GuidEqual(value, zero);
}

std::string Ext4UuidToString(const std::array<std::uint8_t, 16>& uuid) {
  std::ostringstream output;
  output << std::hex << std::nouppercase << std::setfill('0');
  for (std::size_t index = 0; index < uuid.size(); ++index) {
    output << std::setw(2) << static_cast<unsigned int>(uuid[index]);
    if (index == 3 || index == 5 || index == 7 || index == 9) {
      output << '-';
    }
  }
  return output.str();
}

void PrintUsage() {
  std::cout
      << "Usage: wds_arch_cow_helper.exe "
      << "--disk-number N --disk-guid GUID --partition-number N "
      << "--partition-guid GUID --partition-offset-bytes N "
      << "--partition-size-bytes N --parent-pid N\n";
}

bool ParseArguments(int argc, wchar_t* argv[], Arguments* arguments,
                    std::string* error) {
  bool has_disk_number = false;
  bool has_disk_guid = false;
  bool has_partition_number = false;
  bool has_partition_guid = false;
  bool has_partition_offset = false;
  bool has_partition_size = false;
  bool has_parent_pid = false;

  for (int index = 1; index < argc; index += 2) {
    if (index + 1 >= argc) {
      *error = "each option requires one value";
      return false;
    }
    const std::wstring_view option(argv[index]);
    const std::wstring_view value(argv[index + 1]);
    std::uint64_t numeric_value = 0;

    if (option == L"--disk-number") {
      if (has_disk_number || !ParseUnsigned(value, &numeric_value) ||
          numeric_value > kMaximumDiskNumber) {
        *error = "invalid --disk-number";
        return false;
      }
      arguments->disk_number = static_cast<DWORD>(numeric_value);
      has_disk_number = true;
    } else if (option == L"--disk-guid") {
      if (has_disk_guid || !ParseGuid(value, &arguments->disk_guid) ||
          GuidIsZero(arguments->disk_guid)) {
        *error = "invalid --disk-guid";
        return false;
      }
      has_disk_guid = true;
    } else if (option == L"--partition-number") {
      if (has_partition_number || !ParseUnsigned(value, &numeric_value) ||
          numeric_value == 0 ||
          numeric_value > std::numeric_limits<DWORD>::max()) {
        *error = "invalid --partition-number";
        return false;
      }
      arguments->partition_number = static_cast<DWORD>(numeric_value);
      has_partition_number = true;
    } else if (option == L"--partition-guid") {
      if (has_partition_guid || !ParseGuid(value, &arguments->partition_guid) ||
          GuidIsZero(arguments->partition_guid)) {
        *error = "invalid --partition-guid";
        return false;
      }
      has_partition_guid = true;
    } else if (option == L"--partition-offset-bytes") {
      if (has_partition_offset || !ParseUnsigned(value, &numeric_value)) {
        *error = "invalid --partition-offset-bytes";
        return false;
      }
      arguments->partition_offset_bytes = numeric_value;
      has_partition_offset = true;
    } else if (option == L"--partition-size-bytes") {
      if (has_partition_size || !ParseUnsigned(value, &numeric_value)) {
        *error = "invalid --partition-size-bytes";
        return false;
      }
      arguments->partition_size_bytes = numeric_value;
      has_partition_size = true;
    } else if (option == L"--parent-pid") {
      if (has_parent_pid || !ParseUnsigned(value, &numeric_value) ||
          numeric_value == 0 ||
          numeric_value > std::numeric_limits<DWORD>::max()) {
        *error = "invalid --parent-pid";
        return false;
      }
      arguments->parent_pid = static_cast<DWORD>(numeric_value);
      has_parent_pid = true;
    } else {
      *error = "unknown option";
      return false;
    }
  }

  if (!has_disk_number || !has_disk_guid || !has_partition_number ||
      !has_partition_guid || !has_partition_offset || !has_partition_size ||
      !has_parent_pid) {
    *error = "all target identity options are required";
    return false;
  }
  if (arguments->partition_offset_bytes < kMiB ||
      arguments->partition_offset_bytes % kBlockSize != 0 ||
      arguments->partition_size_bytes < kMinimumPartitionBytes ||
      arguments->partition_size_bytes > kMaximumPartitionBytes ||
      arguments->partition_size_bytes % kBlockSize != 0) {
    *error = "target partition offset or size is outside the allowed geometry";
    return false;
  }
  return true;
}

bool CheckParentAlive(DWORD parent_pid, ScopedHandle* parent,
                      std::string* error) {
  if (parent_pid == GetCurrentProcessId()) {
    *error = "parent PID must refer to the caller, not this helper";
    return false;
  }
  HANDLE handle = OpenProcess(SYNCHRONIZE | PROCESS_QUERY_LIMITED_INFORMATION,
                              FALSE, parent_pid);
  if (handle == nullptr) {
    *error = "open parent process (Win32=" + std::to_string(GetLastError()) +
             ")";
    return false;
  }
  parent->Reset(handle);
  if (WaitForSingleObject(parent->get(), 0) != WAIT_TIMEOUT) {
    *error = "parent process is not running";
    return false;
  }
  return true;
}

bool IsParentAlive(HANDLE parent) {
  return parent != INVALID_HANDLE_VALUE &&
         WaitForSingleObject(parent, 0) == WAIT_TIMEOUT;
}

std::wstring PhysicalDrivePath(DWORD disk_number) {
  return L"\\\\.\\PhysicalDrive" + std::to_wstring(disk_number);
}

std::wstring PartitionPath(DWORD disk_number, DWORD partition_number) {
  return L"\\\\.\\Harddisk" + std::to_wstring(disk_number) + L"Partition" +
         std::to_wstring(partition_number);
}

bool QueryStorageDeviceNumber(HANDLE handle, STORAGE_DEVICE_NUMBER* value,
                              std::string* error) {
  DWORD bytes_returned = 0;
  if (!DeviceIoControl(handle, IOCTL_STORAGE_GET_DEVICE_NUMBER, nullptr, 0,
                       value, sizeof(*value), &bytes_returned, nullptr) ||
      bytes_returned < sizeof(*value)) {
    const DWORD code = GetLastError();
    *error = "query storage device number (Win32=" + std::to_string(code) +
             ")";
    return false;
  }
  if (value->DeviceType != FILE_DEVICE_DISK) {
    *error = "target is not a disk device";
    return false;
  }
  return true;
}

bool QueryPartitionLength(HANDLE handle, std::uint64_t* length,
                          std::string* error) {
  GET_LENGTH_INFORMATION information{};
  DWORD bytes_returned = 0;
  if (!DeviceIoControl(handle, IOCTL_DISK_GET_LENGTH_INFO, nullptr, 0,
                       &information, sizeof(information), &bytes_returned,
                       nullptr) ||
      bytes_returned < sizeof(information) || information.Length.QuadPart <= 0) {
    const DWORD code = GetLastError();
    *error = "query target partition length (Win32=" + std::to_string(code) +
             ")";
    return false;
  }
  *length = static_cast<std::uint64_t>(information.Length.QuadPart);
  return true;
}

bool QueryLogicalSectorSize(HANDLE handle, std::uint32_t* size,
                            std::string* error) {
  STORAGE_PROPERTY_QUERY query{};
  query.PropertyId = StorageAccessAlignmentProperty;
  query.QueryType = PropertyStandardQuery;
  STORAGE_ACCESS_ALIGNMENT_DESCRIPTOR descriptor{};
  DWORD bytes_returned = 0;
  if (!DeviceIoControl(handle, IOCTL_STORAGE_QUERY_PROPERTY, &query,
                       sizeof(query), &descriptor, sizeof(descriptor),
                       &bytes_returned, nullptr) ||
      bytes_returned < sizeof(descriptor) ||
      descriptor.BytesPerLogicalSector == 0) {
    const DWORD code = GetLastError();
    *error = "query target sector alignment (Win32=" + std::to_string(code) +
             ")";
    return false;
  }
  *size = descriptor.BytesPerLogicalSector;
  return true;
}

bool QueryDriveLayout(HANDLE handle, DriveLayoutBuffer* output,
                      std::string* error) {
  std::size_t capacity =
      offsetof(DRIVE_LAYOUT_INFORMATION_EX, PartitionEntry) +
      16 * sizeof(PARTITION_INFORMATION_EX);
  while (capacity <= kMaximumLayoutBytes) {
    std::vector<std::uint8_t> buffer(capacity);
    DWORD bytes_returned = 0;
    if (DeviceIoControl(handle, IOCTL_DISK_GET_DRIVE_LAYOUT_EX, nullptr, 0,
                        buffer.data(), static_cast<DWORD>(buffer.size()),
                        &bytes_returned, nullptr)) {
      if (bytes_returned <
          offsetof(DRIVE_LAYOUT_INFORMATION_EX, PartitionEntry)) {
        *error = "drive layout response is truncated";
        return false;
      }
      const auto* layout = reinterpret_cast<const DRIVE_LAYOUT_INFORMATION_EX*>(
          buffer.data());
      const std::uint64_t required =
          static_cast<std::uint64_t>(offsetof(DRIVE_LAYOUT_INFORMATION_EX,
                                               PartitionEntry)) +
          static_cast<std::uint64_t>(layout->PartitionCount) *
              sizeof(PARTITION_INFORMATION_EX);
      if (required > buffer.size() ||
          (bytes_returned != 0 && required > bytes_returned)) {
        *error = "drive layout partition table is truncated";
        return false;
      }
      buffer.resize(static_cast<std::size_t>(required));
      output->bytes = std::move(buffer);
      return true;
    }
    const DWORD code = GetLastError();
    if (code != ERROR_INSUFFICIENT_BUFFER && code != ERROR_MORE_DATA) {
      *error = "query drive layout (Win32=" + std::to_string(code) + ")";
      return false;
    }
    capacity *= 2;
  }
  *error = "drive layout exceeds the bounded response size";
  return false;
}

bool VerifyPhysicalDriveIdentity(HANDLE physical_drive,
                                 const Arguments& arguments,
                                 TargetPartition* target,
                                 std::string* error) {
  STORAGE_DEVICE_NUMBER device_number{};
  if (!QueryStorageDeviceNumber(physical_drive, &device_number, error)) {
    return false;
  }
  if (device_number.DeviceNumber != arguments.disk_number ||
      device_number.PartitionNumber != 0) {
    *error = "physical drive number no longer matches the requested disk";
    return false;
  }

  DriveLayoutBuffer layout_buffer;
  if (!QueryDriveLayout(physical_drive, &layout_buffer, error)) {
    return false;
  }
  const DRIVE_LAYOUT_INFORMATION_EX* layout = layout_buffer.get();
  if (layout->PartitionStyle != PARTITION_STYLE_GPT) {
    *error = "target disk is not GPT";
    return false;
  }
  if (!GuidEqual(layout->Gpt.DiskId, arguments.disk_guid)) {
    *error = "GPT disk identity no longer matches the selection";
    return false;
  }

  const PARTITION_INFORMATION_EX* found = nullptr;
  for (DWORD index = 0; index < layout->PartitionCount; ++index) {
    const PARTITION_INFORMATION_EX& partition = layout->PartitionEntry[index];
    if (partition.PartitionNumber != arguments.partition_number) {
      continue;
    }
    if (found != nullptr) {
      *error = "GPT layout contains duplicate target partition numbers";
      return false;
    }
    found = &partition;
  }
  if (found == nullptr) {
    *error = "target partition no longer exists";
    return false;
  }
  if (found->PartitionStyle != PARTITION_STYLE_GPT ||
      found->RewritePartition ||
      !GuidEqual(found->Gpt.PartitionType, kLinuxFilesystemPartitionType) ||
      !GuidEqual(found->Gpt.PartitionId, arguments.partition_guid) ||
      found->StartingOffset.QuadPart < 0 ||
      found->PartitionLength.QuadPart <= 0 ||
      static_cast<std::uint64_t>(found->StartingOffset.QuadPart) !=
          arguments.partition_offset_bytes ||
      static_cast<std::uint64_t>(found->PartitionLength.QuadPart) !=
          arguments.partition_size_bytes) {
    *error = "target partition identity, type, offset, or size changed";
    return false;
  }
  target->partition = *found;
  return true;
}

bool VerifyTargetPartitionBinding(HANDLE target_partition,
                                  const Arguments& arguments,
                                  TargetPartition* target,
                                  std::string* error) {
  STORAGE_DEVICE_NUMBER device_number{};
  if (!QueryStorageDeviceNumber(target_partition, &device_number, error)) {
    return false;
  }
  if (device_number.DeviceNumber != arguments.disk_number ||
      device_number.PartitionNumber != arguments.partition_number) {
    *error = "partition device path does not map to the selected GPT partition";
    return false;
  }
  std::uint64_t partition_length = 0;
  if (!QueryPartitionLength(target_partition, &partition_length, error)) {
    return false;
  }
  if (partition_length != arguments.partition_size_bytes) {
    *error = "partition device length does not match the selected GPT partition";
    return false;
  }
  if (!QueryLogicalSectorSize(target_partition, &target->logical_sector_size,
                              error)) {
    return false;
  }
  if (arguments.partition_offset_bytes % target->logical_sector_size != 0 ||
      arguments.partition_size_bytes % target->logical_sector_size != 0) {
    *error = "target partition is not aligned to its logical sector size";
    return false;
  }
  DWORD bytes_returned = 0;
  if (!DeviceIoControl(target_partition, IOCTL_DISK_IS_WRITABLE, nullptr, 0,
                       nullptr, 0, &bytes_returned, nullptr)) {
    *error = "target partition is not writable (Win32=" +
             std::to_string(GetLastError()) + ")";
    return false;
  }
  return true;
}

bool IsPowerOf(std::uint32_t value, std::uint32_t base) {
  if (value == 0) {
    return false;
  }
  while (value % base == 0) {
    value /= base;
  }
  return value == 1;
}

bool HasSparseSuperblock(std::uint32_t group) {
  return group == 0 || group == 1 || IsPowerOf(group, 3) ||
         IsPowerOf(group, 5) || IsPowerOf(group, 7);
}

bool BuildFilesystemLayout(std::uint64_t partition_size,
                           FilesystemLayout* output, std::string* error) {
  if (partition_size < kMinimumPartitionBytes ||
      partition_size > kMaximumPartitionBytes ||
      partition_size % kBlockSize != 0) {
    *error = "unsupported ext4 partition size";
    return false;
  }
  const std::uint64_t total_blocks64 = partition_size / kBlockSize;
  if (total_blocks64 == 0 ||
      total_blocks64 > std::numeric_limits<std::uint32_t>::max()) {
    *error = "ext4 block count is outside the supported range";
    return false;
  }
  const std::uint32_t total_blocks =
      static_cast<std::uint32_t>(total_blocks64);
  const std::uint32_t group_count =
      (total_blocks + kBlocksPerGroup - 1) / kBlocksPerGroup;
  if (group_count == 0 || group_count > kMaximumGroupCount) {
    *error = "ext4 group count is outside the supported range";
    return false;
  }
  const std::uint32_t gdt_blocks =
      (group_count * 32 + kBlockSize - 1) / kBlockSize;

  FilesystemLayout layout;
  layout.total_blocks = total_blocks;
  layout.group_count = group_count;
  layout.group_descriptor_blocks = gdt_blocks;
  layout.total_inodes = group_count * kInodesPerGroup;
  layout.free_inodes = layout.total_inodes - kCowDirectoryInode;
  layout.groups.reserve(group_count);

  std::uint64_t total_free_blocks = 0;
  for (std::uint32_t group = 0; group < group_count; ++group) {
    GroupLayout group_layout;
    group_layout.index = group;
    group_layout.start_block = group * kBlocksPerGroup;
    const std::uint64_t remaining =
        static_cast<std::uint64_t>(total_blocks) - group_layout.start_block;
    group_layout.block_count = static_cast<std::uint32_t>(
        std::min<std::uint64_t>(remaining, kBlocksPerGroup));
    group_layout.has_backup_superblock = HasSparseSuperblock(group);

    std::uint64_t next_block = group_layout.start_block;
    if (group_layout.has_backup_superblock) {
      group_layout.superblock_block = static_cast<std::uint32_t>(next_block++);
      group_layout.gdt_start_block = static_cast<std::uint32_t>(next_block);
      next_block += gdt_blocks;
    }
    group_layout.block_bitmap_block = static_cast<std::uint32_t>(next_block++);
    group_layout.inode_bitmap_block = static_cast<std::uint32_t>(next_block++);
    group_layout.inode_table_start_block =
        static_cast<std::uint32_t>(next_block);
    next_block += kInodeTableBlocks;
    if (next_block > static_cast<std::uint64_t>(group_layout.start_block) +
                         group_layout.block_count) {
      *error = "target partition is too small for the ext4 metadata layout";
      return false;
    }
    group_layout.first_data_block = static_cast<std::uint32_t>(next_block);
    group_layout.overhead_blocks = static_cast<std::uint32_t>(
        next_block - group_layout.start_block);
    total_free_blocks += group_layout.block_count - group_layout.overhead_blocks;
    layout.groups.push_back(group_layout);
  }

  const GroupLayout& first_group = layout.groups.front();
  if (first_group.first_data_block + 2 >=
      first_group.start_block + first_group.block_count || total_free_blocks < 3) {
    *error = "target partition has no room for the ext4 root directories";
    return false;
  }
  layout.root_data_block = first_group.first_data_block;
  layout.lost_found_data_block = first_group.first_data_block + 1;
  layout.cow_directory_data_block = first_group.first_data_block + 2;
  total_free_blocks -= 3;
  if (total_free_blocks > std::numeric_limits<std::uint32_t>::max()) {
    *error = "ext4 free block count is outside the supported range";
    return false;
  }
  layout.free_blocks = static_cast<std::uint32_t>(total_free_blocks);
  *output = std::move(layout);
  return true;
}

void PutU16(std::uint8_t* buffer, std::size_t offset, std::uint16_t value) {
  buffer[offset] = static_cast<std::uint8_t>(value);
  buffer[offset + 1] = static_cast<std::uint8_t>(value >> 8);
}

void PutU32(std::uint8_t* buffer, std::size_t offset, std::uint32_t value) {
  for (std::size_t index = 0; index < 4; ++index) {
    buffer[offset + index] = static_cast<std::uint8_t>(value >> (index * 8));
  }
}

std::uint16_t GetU16(const std::uint8_t* buffer, std::size_t offset) {
  return static_cast<std::uint16_t>(buffer[offset]) |
         (static_cast<std::uint16_t>(buffer[offset + 1]) << 8);
}

std::uint32_t GetU32(const std::uint8_t* buffer, std::size_t offset) {
  std::uint32_t value = 0;
  for (std::size_t index = 0; index < 4; ++index) {
    value |= static_cast<std::uint32_t>(buffer[offset + index]) <<
             (index * 8);
  }
  return value;
}

bool BlockOffset(std::uint32_t block, std::uint64_t* offset) {
  if (block > std::numeric_limits<std::uint64_t>::max() / kBlockSize) {
    return false;
  }
  *offset = static_cast<std::uint64_t>(block) * kBlockSize;
  return true;
}

bool CheckRange(std::uint64_t offset, std::uint64_t length,
                std::uint64_t capacity) {
  return offset <= capacity && length <= capacity - offset;
}

bool WriteExactAt(HANDLE handle, std::uint64_t capacity, std::uint64_t offset,
                  const std::uint8_t* data, std::size_t length,
                  std::string* error) {
  if (!CheckRange(offset, length, capacity)) {
    *error = "attempted write is outside the selected partition";
    return false;
  }
  LARGE_INTEGER position{};
  position.QuadPart = static_cast<LONGLONG>(offset);
  if (!SetFilePointerEx(handle, position, nullptr, FILE_BEGIN)) {
    *error = "seek target partition for write (Win32=" +
             std::to_string(GetLastError()) + ")";
    return false;
  }
  std::size_t written_total = 0;
  while (written_total < length) {
    const DWORD chunk = static_cast<DWORD>(std::min<std::size_t>(
        length - written_total, std::numeric_limits<DWORD>::max()));
    DWORD written = 0;
    if (!WriteFile(handle, data + written_total, chunk, &written, nullptr) ||
        written != chunk) {
      *error = "write target partition (Win32=" +
               std::to_string(GetLastError()) + ")";
      return false;
    }
    written_total += written;
  }
  return true;
}

bool ReadExactAt(HANDLE handle, std::uint64_t capacity, std::uint64_t offset,
                 std::uint8_t* data, std::size_t length, std::string* error) {
  if (!CheckRange(offset, length, capacity)) {
    *error = "attempted read is outside the selected partition";
    return false;
  }
  LARGE_INTEGER position{};
  position.QuadPart = static_cast<LONGLONG>(offset);
  if (!SetFilePointerEx(handle, position, nullptr, FILE_BEGIN)) {
    *error = "seek target partition for read (Win32=" +
             std::to_string(GetLastError()) + ")";
    return false;
  }
  std::size_t read_total = 0;
  while (read_total < length) {
    const DWORD chunk = static_cast<DWORD>(std::min<std::size_t>(
        length - read_total, std::numeric_limits<DWORD>::max()));
    DWORD read = 0;
    if (!ReadFile(handle, data + read_total, chunk, &read, nullptr) ||
        read != chunk) {
      *error = "read target partition (Win32=" +
               std::to_string(GetLastError()) + ")";
      return false;
    }
    read_total += read;
  }
  return true;
}

bool WriteZeroes(HANDLE handle, std::uint64_t capacity, std::uint64_t offset,
                 std::uint64_t length, std::string* error) {
  if (!CheckRange(offset, length, capacity)) {
    *error = "attempted zero operation is outside the selected partition";
    return false;
  }
  const std::vector<std::uint8_t> zeroes(kZeroBufferBytes, 0);
  std::uint64_t cursor = offset;
  std::uint64_t remaining = length;
  while (remaining != 0) {
    const std::size_t chunk = static_cast<std::size_t>(
        std::min<std::uint64_t>(remaining, zeroes.size()));
    if (!WriteExactAt(handle, capacity, cursor, zeroes.data(), chunk, error)) {
      return false;
    }
    cursor += chunk;
    remaining -= chunk;
  }
  return true;
}

void SetBit(std::vector<std::uint8_t>* bitmap, std::uint32_t bit) {
  (*bitmap)[bit / 8] |= static_cast<std::uint8_t>(1u << (bit % 8));
}

std::uint32_t GroupFreeBlocks(const GroupLayout& group) {
  const std::uint32_t root_blocks = group.index == 0 ? 3 : 0;
  return group.block_count - group.overhead_blocks - root_blocks;
}

std::array<std::uint8_t, 1024> BuildSuperblock(
    const FilesystemLayout& layout, const std::array<std::uint8_t, 16>& uuid,
    std::uint32_t unix_time, std::uint16_t group_number) {
  std::array<std::uint8_t, 1024> superblock{};
  PutU32(superblock.data(), 0x00, layout.total_inodes);
  PutU32(superblock.data(), 0x04, layout.total_blocks);
  PutU32(superblock.data(), 0x08, 0);
  PutU32(superblock.data(), 0x0C, layout.free_blocks);
  PutU32(superblock.data(), 0x10, layout.free_inodes);
  PutU32(superblock.data(), 0x14, 0);
  PutU32(superblock.data(), 0x18, 2);
  PutU32(superblock.data(), 0x1C, 2);
  PutU32(superblock.data(), 0x20, kBlocksPerGroup);
  PutU32(superblock.data(), 0x24, kBlocksPerGroup);
  PutU32(superblock.data(), 0x28, kInodesPerGroup);
  PutU32(superblock.data(), 0x30, unix_time);
  PutU16(superblock.data(), 0x36, 0xFFFF);
  PutU16(superblock.data(), 0x38, kExt4Magic);
  PutU16(superblock.data(), 0x3A, kExt4StateClean);
  PutU16(superblock.data(), 0x3C, kExt4ErrorsContinue);
  PutU32(superblock.data(), 0x40, unix_time);
  PutU32(superblock.data(), 0x4C, 1);
  PutU32(superblock.data(), 0x54, kFirstNonReservedInode);
  PutU16(superblock.data(), 0x58, kInodeSize);
  PutU16(superblock.data(), 0x5A, group_number);
  PutU32(superblock.data(), 0x5C, kExt4CompatExtAttr);
  PutU32(superblock.data(), 0x60,
          kExt4IncompatFileType | kExt4IncompatExtents);
  PutU32(superblock.data(), 0x64,
          kExt4RoCompatSparseSuper | kExt4RoCompatLargeFile |
              kExt4RoCompatExtraIsize);
  std::copy(uuid.begin(), uuid.end(), superblock.begin() + 0x68);
  constexpr char kVolumeLabel[] = "WDS_ARCH_COW";
  std::copy(std::begin(kVolumeLabel), std::end(kVolumeLabel) - 1,
            superblock.begin() + 0x78);
  PutU16(superblock.data(), 0xFE, 32);
  PutU32(superblock.data(), 0x108, unix_time);
  PutU16(superblock.data(), 0x15C, 32);
  PutU16(superblock.data(), 0x15E, 32);
  return superblock;
}

std::vector<std::uint8_t> BuildGroupDescriptors(
    const FilesystemLayout& layout) {
  std::vector<std::uint8_t> descriptors(layout.group_count * 32, 0);
  for (const GroupLayout& group : layout.groups) {
    const std::size_t offset = static_cast<std::size_t>(group.index) * 32;
    PutU32(descriptors.data() + offset, 0, group.block_bitmap_block);
    PutU32(descriptors.data() + offset, 4, group.inode_bitmap_block);
    PutU32(descriptors.data() + offset, 8, group.inode_table_start_block);
    PutU16(descriptors.data() + offset, 12,
           static_cast<std::uint16_t>(GroupFreeBlocks(group)));
    const std::uint16_t free_inodes = static_cast<std::uint16_t>(
        kInodesPerGroup - (group.index == 0 ? kCowDirectoryInode : 0));
    PutU16(descriptors.data() + offset, 14, free_inodes);
    PutU16(descriptors.data() + offset, 16, group.index == 0 ? 3 : 0);
    PutU16(descriptors.data() + offset, 28, free_inodes);
  }
  return descriptors;
}

std::array<std::uint8_t, kInodeSize> BuildDirectoryInode(
    std::uint32_t data_block, std::uint16_t mode, std::uint16_t links,
    std::uint32_t unix_time) {
  std::array<std::uint8_t, kInodeSize> inode{};
  PutU16(inode.data(), 0x00, mode);
  PutU32(inode.data(), 0x04, kBlockSize);
  PutU32(inode.data(), 0x08, unix_time);
  PutU32(inode.data(), 0x0C, unix_time);
  PutU32(inode.data(), 0x10, unix_time);
  PutU16(inode.data(), 0x1A, links);
  PutU32(inode.data(), 0x1C, kBlockSize / 512);
  PutU32(inode.data(), 0x20, kInodeFlagExtents);
  PutU16(inode.data(), 0x28, kExtentMagic);
  PutU16(inode.data(), 0x2A, 1);
  PutU16(inode.data(), 0x2C, 4);
  PutU16(inode.data(), 0x2E, 0);
  PutU32(inode.data(), 0x34, 0);
  PutU16(inode.data(), 0x38, 1);
  PutU16(inode.data(), 0x3A, 0);
  PutU32(inode.data(), 0x3C, data_block);
  PutU16(inode.data(), 0x80, 32);
  PutU32(inode.data(), 0x90, unix_time);
  return inode;
}

void WriteDirectoryEntry(std::array<std::uint8_t, kBlockSize>* block,
                         std::size_t offset, std::uint32_t inode,
                         std::uint16_t record_length, std::string_view name) {
  PutU32(block->data(), offset, inode);
  PutU16(block->data(), offset + 4, record_length);
  (*block)[offset + 6] = static_cast<std::uint8_t>(name.size());
  (*block)[offset + 7] = 2;
  std::copy(name.begin(), name.end(), block->begin() + offset + 8);
}

std::array<std::uint8_t, kBlockSize> BuildRootDirectory() {
  std::array<std::uint8_t, kBlockSize> block{};
  WriteDirectoryEntry(&block, 0, kRootInode, 12, ".");
  WriteDirectoryEntry(&block, 12, kRootInode, 12, "..");
  WriteDirectoryEntry(&block, 24, kLostFoundInode, 20, "lost+found");
  WriteDirectoryEntry(&block, 44, kCowDirectoryInode,
                      static_cast<std::uint16_t>(kBlockSize - 44),
                      "wds-arch");
  return block;
}

std::array<std::uint8_t, kBlockSize> BuildLostFoundDirectory() {
  std::array<std::uint8_t, kBlockSize> block{};
  WriteDirectoryEntry(&block, 0, kLostFoundInode, 12, ".");
  WriteDirectoryEntry(&block, 12, kRootInode,
                      static_cast<std::uint16_t>(kBlockSize - 12), "..");
  return block;
}

std::array<std::uint8_t, kBlockSize> BuildCowDirectory() {
  std::array<std::uint8_t, kBlockSize> block{};
  WriteDirectoryEntry(&block, 0, kCowDirectoryInode, 12, ".");
  WriteDirectoryEntry(&block, 12, kRootInode,
                      static_cast<std::uint16_t>(kBlockSize - 12), "..");
  return block;
}

bool WriteBlock(HANDLE handle, std::uint64_t capacity, std::uint32_t block,
                const std::uint8_t* data, std::size_t length,
                std::string* error) {
  std::uint64_t offset = 0;
  if (!BlockOffset(block, &offset)) {
    *error = "ext4 block offset overflow";
    return false;
  }
  return WriteExactAt(handle, capacity, offset, data, length, error);
}

bool ZeroBlocks(HANDLE handle, std::uint64_t capacity, std::uint32_t block,
                std::uint32_t count, std::string* error) {
  std::uint64_t offset = 0;
  if (!BlockOffset(block, &offset)) {
    *error = "ext4 zero range offset overflow";
    return false;
  }
  return WriteZeroes(handle, capacity, offset,
                     static_cast<std::uint64_t>(count) * kBlockSize, error);
}

bool FormatExt4(HANDLE target_partition, const FilesystemLayout& layout,
                const std::array<std::uint8_t, 16>& uuid,
                std::string* error) {
  const auto now = std::chrono::duration_cast<std::chrono::seconds>(
                       std::chrono::system_clock::now().time_since_epoch())
                       .count();
  if (now <= 0 || now > std::numeric_limits<std::uint32_t>::max()) {
    *error = "current system time cannot be represented by ext4";
    return false;
  }
  const std::uint32_t unix_time = static_cast<std::uint32_t>(now);
  const std::uint64_t capacity =
      static_cast<std::uint64_t>(layout.total_blocks) * kBlockSize;

  // Clear the unused boot-sector bytes so no stale boot signature remains.
  if (!WriteZeroes(target_partition, capacity, 0, 1024, error)) {
    return false;
  }
  const auto primary_superblock = BuildSuperblock(layout, uuid, unix_time, 0);
  if (!WriteExactAt(target_partition, capacity, 1024, primary_superblock.data(),
                    primary_superblock.size(), error)) {
    return false;
  }

  const std::vector<std::uint8_t> descriptors = BuildGroupDescriptors(layout);
  for (const GroupLayout& group : layout.groups) {
    if (!group.has_backup_superblock) {
      continue;
    }
    if (!ZeroBlocks(target_partition, capacity, group.gdt_start_block,
                    layout.group_descriptor_blocks, error)) {
      return false;
    }
    if (!WriteBlock(target_partition, capacity, group.gdt_start_block,
                    descriptors.data(), descriptors.size(), error)) {
      return false;
    }
    if (group.index != 0) {
      const auto backup_superblock =
          BuildSuperblock(layout, uuid, unix_time,
                          static_cast<std::uint16_t>(group.index));
      if (!WriteBlock(target_partition, capacity, group.superblock_block,
                      backup_superblock.data(), backup_superblock.size(),
                      error)) {
        return false;
      }
    }
  }

  for (const GroupLayout& group : layout.groups) {
    std::vector<std::uint8_t> block_bitmap(kBlockSize, 0);
    for (std::uint32_t bit = 0; bit < group.overhead_blocks; ++bit) {
      SetBit(&block_bitmap, bit);
    }
    for (std::uint32_t bit = group.block_count; bit < kBlocksPerGroup; ++bit) {
      SetBit(&block_bitmap, bit);
    }
    if (group.index == 0) {
      SetBit(&block_bitmap, layout.root_data_block - group.start_block);
      SetBit(&block_bitmap, layout.lost_found_data_block - group.start_block);
      SetBit(&block_bitmap, layout.cow_directory_data_block - group.start_block);
    }
    if (!WriteBlock(target_partition, capacity, group.block_bitmap_block,
                    block_bitmap.data(), block_bitmap.size(), error)) {
      return false;
    }

    std::vector<std::uint8_t> inode_bitmap(kBlockSize, 0);
    if (group.index == 0) {
      for (std::uint32_t inode = 1; inode <= kCowDirectoryInode; ++inode) {
        SetBit(&inode_bitmap, inode - 1);
      }
    }
    for (std::size_t byte = kInodesPerGroup / 8; byte < inode_bitmap.size();
         ++byte) {
      inode_bitmap[byte] = 0xFF;
    }
    if (!WriteBlock(target_partition, capacity, group.inode_bitmap_block,
                    inode_bitmap.data(), inode_bitmap.size(), error)) {
      return false;
    }
    if (!ZeroBlocks(target_partition, capacity, group.inode_table_start_block,
                    kInodeTableBlocks, error)) {
      return false;
    }
  }

  const GroupLayout& first_group = layout.groups.front();
  const auto root_inode = BuildDirectoryInode(
      layout.root_data_block, static_cast<std::uint16_t>(0x4000 | 0755), 4,
      unix_time);
  const auto lost_found_inode = BuildDirectoryInode(
      layout.lost_found_data_block, static_cast<std::uint16_t>(0x4000 | 0700),
      2, unix_time);
  const auto cow_directory_inode = BuildDirectoryInode(
      layout.cow_directory_data_block,
      static_cast<std::uint16_t>(0x4000 | 0755), 2, unix_time);
  std::uint64_t inode_table_offset = 0;
  if (!BlockOffset(first_group.inode_table_start_block, &inode_table_offset)) {
    *error = "root inode table offset overflow";
    return false;
  }
  if (!WriteExactAt(target_partition, capacity,
                    inode_table_offset + (kRootInode - 1) * kInodeSize,
                    root_inode.data(), root_inode.size(), error) ||
      !WriteExactAt(target_partition, capacity,
                    inode_table_offset + (kLostFoundInode - 1) * kInodeSize,
                    lost_found_inode.data(), lost_found_inode.size(), error) ||
      !WriteExactAt(target_partition, capacity,
                    inode_table_offset +
                        (kCowDirectoryInode - 1) * kInodeSize,
                    cow_directory_inode.data(), cow_directory_inode.size(),
                    error)) {
    return false;
  }
  const auto root_directory = BuildRootDirectory();
  const auto lost_found_directory = BuildLostFoundDirectory();
  const auto cow_directory = BuildCowDirectory();
  if (!WriteBlock(target_partition, capacity, layout.root_data_block,
                  root_directory.data(), root_directory.size(), error) ||
      !WriteBlock(target_partition, capacity, layout.lost_found_data_block,
                  lost_found_directory.data(), lost_found_directory.size(),
                  error) ||
      !WriteBlock(target_partition, capacity, layout.cow_directory_data_block,
                  cow_directory.data(), cow_directory.size(),
                  error)) {
    return false;
  }
  if (!FlushFileBuffers(target_partition)) {
    *error = "flush target partition (Win32=" + std::to_string(GetLastError()) +
             ")";
    return false;
  }
  return true;
}

bool VerifyExt4(HANDLE target_partition, const FilesystemLayout& layout,
                const std::array<std::uint8_t, 16>& uuid,
                std::string* error) {
  const std::uint64_t capacity =
      static_cast<std::uint64_t>(layout.total_blocks) * kBlockSize;
  std::array<std::uint8_t, 1024> superblock{};
  if (!ReadExactAt(target_partition, capacity, 1024, superblock.data(),
                   superblock.size(), error)) {
    return false;
  }
  constexpr char kVolumeLabel[] = "WDS_ARCH_COW";
  if (GetU16(superblock.data(), 0x38) != kExt4Magic ||
      GetU32(superblock.data(), 0x04) != layout.total_blocks ||
      GetU32(superblock.data(), 0x0C) != layout.free_blocks ||
      GetU16(superblock.data(), 0x58) != kInodeSize ||
      (GetU32(superblock.data(), 0x60) &
           (kExt4IncompatFileType | kExt4IncompatExtents)) !=
          (kExt4IncompatFileType | kExt4IncompatExtents) ||
      !std::equal(uuid.begin(), uuid.end(), superblock.begin() + 0x68) ||
      !std::equal(std::begin(kVolumeLabel), std::end(kVolumeLabel) - 1,
                  superblock.begin() + 0x78)) {
    *error = "ext4 superblock verification failed";
    return false;
  }

  std::array<std::uint8_t, kInodeSize> root_inode{};
  std::uint64_t inode_table_offset = 0;
  if (!BlockOffset(layout.groups.front().inode_table_start_block,
                   &inode_table_offset) ||
      !ReadExactAt(target_partition, capacity,
                   inode_table_offset + (kRootInode - 1) * kInodeSize,
                   root_inode.data(), root_inode.size(), error)) {
    if (error->empty()) {
      *error = "root inode verification offset overflow";
    }
    return false;
  }
  if (GetU16(root_inode.data(), 0x00) != (0x4000 | 0755) ||
      GetU16(root_inode.data(), 0x28) != kExtentMagic ||
      GetU32(root_inode.data(), 0x3C) != layout.root_data_block) {
    *error = "ext4 root inode verification failed";
    return false;
  }
  std::array<std::uint8_t, kInodeSize> cow_inode{};
  if (!ReadExactAt(target_partition, capacity,
                   inode_table_offset +
                       (kCowDirectoryInode - 1) * kInodeSize,
                   cow_inode.data(), cow_inode.size(), error) ||
      GetU16(cow_inode.data(), 0x00) != (0x4000 | 0755) ||
      GetU16(cow_inode.data(), 0x28) != kExtentMagic ||
      GetU32(cow_inode.data(), 0x3C) != layout.cow_directory_data_block) {
    if (error->empty()) {
      *error = "ext4 COW directory inode verification failed";
    }
    return false;
  }
  std::uint64_t root_directory_offset = 0;
  std::array<std::uint8_t, kBlockSize> root_directory{};
  if (!BlockOffset(layout.root_data_block, &root_directory_offset) ||
      !ReadExactAt(target_partition, capacity, root_directory_offset,
                   root_directory.data(), root_directory.size(), error) ||
      GetU32(root_directory.data(), 44) != kCowDirectoryInode ||
      root_directory[50] != 8 ||
      !std::equal(std::begin("wds-arch"), std::end("wds-arch") - 1,
                  root_directory.begin() + 52)) {
    if (error->empty()) {
      *error = "ext4 COW directory verification failed";
    }
    return false;
  }
  return true;
}

bool CreateRandomUuid(std::array<std::uint8_t, 16>* uuid, std::string* error) {
  const NTSTATUS status = BCryptGenRandom(
      nullptr, reinterpret_cast<PUCHAR>(uuid->data()),
      static_cast<ULONG>(uuid->size()), BCRYPT_USE_SYSTEM_PREFERRED_RNG);
  if (status < 0) {
    *error = "generate ext4 UUID (NTSTATUS=" +
             std::to_string(static_cast<long>(status)) + ")";
    return false;
  }
  (*uuid)[6] = static_cast<std::uint8_t>(((*uuid)[6] & 0x0F) | 0x40);
  (*uuid)[8] = static_cast<std::uint8_t>(((*uuid)[8] & 0x3F) | 0x80);
  return true;
}

bool RunSelfTest(std::string* error) {
  FilesystemLayout minimum;
  FilesystemLayout maximum;
  if (!BuildFilesystemLayout(kMinimumPartitionBytes, &minimum, error) ||
      !BuildFilesystemLayout(kMaximumPartitionBytes, &maximum, error)) {
    return false;
  }
  if (minimum.groups.size() != 1 || minimum.root_data_block >=
                                        minimum.total_blocks ||
      maximum.group_count != kMaximumGroupCount ||
      maximum.free_blocks >= maximum.total_blocks ||
      maximum.free_inodes >= maximum.total_inodes) {
    *error = "ext4 layout self-test assertions failed";
    return false;
  }
  std::uint64_t counted_free_blocks = 0;
  for (const GroupLayout& group : maximum.groups) {
    counted_free_blocks += GroupFreeBlocks(group);
  }
  if (counted_free_blocks != maximum.free_blocks) {
    *error = "ext4 group free-block accounting self-test failed";
    return false;
  }
  std::array<std::uint8_t, 16> uuid{};
  uuid[0] = 1;
  const auto superblock = BuildSuperblock(minimum, uuid, 1, 0);
  if (GetU16(superblock.data(), 0x38) != kExt4Magic ||
      GetU32(superblock.data(), 0x04) != minimum.total_blocks ||
      !std::equal(uuid.begin(), uuid.end(), superblock.begin() + 0x68)) {
    *error = "ext4 superblock self-test assertions failed";
    return false;
  }
  const auto root_inode = BuildDirectoryInode(
      minimum.root_data_block, static_cast<std::uint16_t>(0x4000 | 0755), 4,
      1);
  const auto root_directory = BuildRootDirectory();
  if (GetU16(root_inode.data(), 0x28) != kExtentMagic ||
      GetU32(root_inode.data(), 0x3C) != minimum.root_data_block ||
      GetU32(root_directory.data(), 44) != kCowDirectoryInode ||
      root_directory[50] != 8 ||
      !std::equal(std::begin("wds-arch"), std::end("wds-arch") - 1,
                  root_directory.begin() + 52)) {
    *error = "ext4 COW directory self-test assertions failed";
    return false;
  }
  return true;
}

bool RunFormatter(const Arguments& arguments, std::string* ext4_uuid,
                  std::string* error) {
  ScopedHandle parent;
  if (!CheckParentAlive(arguments.parent_pid, &parent, error)) {
    return false;
  }

  ScopedHandle physical_drive(CreateFileW(
      PhysicalDrivePath(arguments.disk_number).c_str(), GENERIC_READ,
      FILE_SHARE_READ | FILE_SHARE_WRITE, nullptr, OPEN_EXISTING,
      FILE_ATTRIBUTE_NORMAL, nullptr));
  if (!physical_drive.valid()) {
    *error = "open physical drive for validation (Win32=" +
             std::to_string(GetLastError()) + ")";
    return false;
  }
  TargetPartition target;
  if (!VerifyPhysicalDriveIdentity(physical_drive.get(), arguments, &target,
                                   error)) {
    return false;
  }

  ScopedHandle target_partition(CreateFileW(
      PartitionPath(arguments.disk_number, arguments.partition_number).c_str(),
      GENERIC_READ | GENERIC_WRITE, 0, nullptr, OPEN_EXISTING,
      FILE_ATTRIBUTE_NORMAL | FILE_FLAG_WRITE_THROUGH, nullptr));
  if (!target_partition.valid()) {
    *error = "open selected partition exclusively (Win32=" +
             std::to_string(GetLastError()) + ")";
    return false;
  }
  if (!VerifyTargetPartitionBinding(target_partition.get(), arguments, &target,
                                    error) ||
      !VerifyPhysicalDriveIdentity(physical_drive.get(), arguments, &target,
                                   error)) {
    return false;
  }

  VolumeLock volume_lock;
  if (!volume_lock.Lock(target_partition.get(), error)) {
    return false;
  }
  if (!IsParentAlive(parent.get())) {
    *error = "parent process exited before target formatting began";
    return false;
  }

  FilesystemLayout filesystem_layout;
  if (!BuildFilesystemLayout(arguments.partition_size_bytes, &filesystem_layout,
                             error)) {
    return false;
  }
  std::array<std::uint8_t, 16> uuid{};
  if (!CreateRandomUuid(&uuid, error) ||
      !FormatExt4(target_partition.get(), filesystem_layout, uuid, error)) {
    return false;
  }
  if (!VerifyExt4(target_partition.get(), filesystem_layout, uuid, error)) {
    return false;
  }
  if (!VerifyPhysicalDriveIdentity(physical_drive.get(), arguments, &target,
                                   error)) {
    return false;
  }
  *ext4_uuid = Ext4UuidToString(uuid);
  return true;
}

}  // namespace

int wmain(int argc, wchar_t* argv[]) {
  if (argc == 2 && std::wstring_view(argv[1]) == L"--help") {
    PrintUsage();
    return 0;
  }
  if (argc == 2 && std::wstring_view(argv[1]) == L"--self-test") {
    std::string error;
    if (!RunSelfTest(&error)) {
      std::cerr << "wds-arch-cow-helper: " << error << '\n';
      return 1;
    }
    std::cout << "RESULT|self-test|ok\n";
    return 0;
  }

  Arguments arguments;
  std::string error;
  if (!ParseArguments(argc, argv, &arguments, &error)) {
    std::cerr << "wds-arch-cow-helper: " << error << '\n';
    PrintUsage();
    return 2;
  }
  std::string ext4_uuid;
  if (!RunFormatter(arguments, &ext4_uuid, &error)) {
    std::cerr << "wds-arch-cow-helper: " << error << '\n';
    return 1;
  }
  std::cout << "RESULT|ok|" << ext4_uuid << "|WDS_ARCH_COW\n";
  return 0;
}
