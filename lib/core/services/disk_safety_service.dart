import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'windows_system_environment.dart';

class DiskInfo {
  final int diskNumber;
  final String model;
  final String friendlyName;
  final int sizeBytes;
  final String sizeFormatted;
  final String serialNumber;
  final String uniqueId;
  final String devicePath;
  final String busType;
  final String partitionStyle;
  final bool isSystem;
  final bool isBoot;
  final bool isOffline;
  final bool isRemovable;
  final List<String> driveLetters;
  final List<DiskPartition> partitions;

  const DiskInfo({
    required this.diskNumber,
    required this.model,
    required this.friendlyName,
    required this.sizeBytes,
    required this.sizeFormatted,
    this.serialNumber = '',
    this.uniqueId = '',
    this.devicePath = '',
    this.busType = 'Unknown',
    this.partitionStyle = 'Unknown',
    this.isSystem = false,
    this.isBoot = false,
    this.isOffline = false,
    this.isRemovable = false,
    this.driveLetters = const [],
    this.partitions = const [],
  });

  /// Returns the volume that is most appropriate for a user-facing operation.
  ///
  /// A removable disk can expose a small EFI/recovery partition before its
  /// actual data volume.  The old callers used `driveLetters.first`, which
  /// made a benchmark write to that small partition (or fail immediately when
  /// it had no free space).  Prefer a mounted, non-system partition with the
  /// largest reported capacity and retain the legacy ordering only when
  /// partition metadata is unavailable.
  String? get preferredDriveLetter {
    final mounted = partitions
        .where(
          (partition) =>
              partition.driveLetter != null &&
              partition.driveLetter!.trim().isNotEmpty,
        )
        .toList(growable: false);
    if (mounted.isNotEmpty) {
      final ranked = [...mounted]
        ..sort((left, right) {
          final systemOrder = (_isBootOrReservedPartition(left) ? 1 : 0)
              .compareTo(_isBootOrReservedPartition(right) ? 1 : 0);
          if (systemOrder != 0) return systemOrder;
          final sizeOrder = right.sizeBytes.compareTo(left.sizeBytes);
          if (sizeOrder != 0) return sizeOrder;
          return (left.driveLetter ?? '').compareTo(right.driveLetter ?? '');
        });
      return ranked.first.driveLetter!.trim().toUpperCase();
    }

    for (final letter in driveLetters) {
      final normalized = letter
          .trim()
          .replaceAll(RegExp(r'[:\\]'), '')
          .toUpperCase();
      if (normalized.length == 1) return normalized;
    }
    return null;
  }

  static bool _isBootOrReservedPartition(DiskPartition partition) {
    if (partition.isSystem) return true;
    final type = partition.type.trim().toLowerCase();
    return type.contains('system') ||
        type.contains('efi') ||
        type.contains('recovery') ||
        type.contains('reserved');
  }

  @override
  String toString() =>
      'Disk $diskNumber: $model ($sizeFormatted) S/N: $serialNumber';

  bool hasSamePhysicalIdentity(DiskInfo other) {
    if (sizeBytes <= 0 ||
        other.sizeBytes <= 0 ||
        sizeBytes != other.sizeBytes) {
      return false;
    }

    if (!_hasMatchingModelAndBus(other)) return false;

    // A selected-disk refresh can expose a different subset of Windows
    // Storage properties (for example, Get-Disk may omit a bridge serial
    // that was present during the initial inventory). Compare every identity
    // that is available on both snapshots, while rejecting conflicting
    // values. This preserves the physical-disk guard without turning a
    // missing optional property into a false rejection.
    final thisSerial = _normalizedIdentityValue(serialNumber);
    final otherSerial = _normalizedIdentityValue(other.serialNumber);
    if (_isReliableIdentityValue(thisSerial) &&
        _isReliableIdentityValue(otherSerial)) {
      return thisSerial == otherSerial;
    }

    final thisUniqueId = _normalizedIdentityValue(uniqueId);
    final otherUniqueId = _normalizedIdentityValue(other.uniqueId);
    if (_isReliableIdentityValue(thisUniqueId) &&
        _isReliableIdentityValue(otherUniqueId)) {
      return thisUniqueId == otherUniqueId;
    }

    final thisPath = _normalizedIdentityValue(devicePath);
    final otherPath = _normalizedIdentityValue(other.devicePath);
    if (_isReliableDevicePath(thisPath) && _isReliableDevicePath(otherPath)) {
      return thisPath == otherPath;
    }

    return false;
  }

  bool _hasMatchingModelAndBus(DiskInfo other) {
    final thisModel = model.trim().toUpperCase();
    final otherModel = other.model.trim().toUpperCase();
    final thisBus = busType.trim().toUpperCase();
    final otherBus = other.busType.trim().toUpperCase();
    return thisModel.isNotEmpty &&
        thisModel == otherModel &&
        thisBus.isNotEmpty &&
        thisBus == otherBus;
  }

  Map<String, dynamic> toJson() => {
    'diskNumber': diskNumber,
    'model': model,
    'friendlyName': friendlyName,
    'sizeBytes': sizeBytes,
    'sizeFormatted': sizeFormatted,
    'serialNumber': serialNumber,
    'uniqueId': uniqueId,
    'devicePath': devicePath,
    'busType': busType,
    'partitionStyle': partitionStyle,
    'isSystem': isSystem,
    'isBoot': isBoot,
    'isOffline': isOffline,
    'isRemovable': isRemovable,
    'driveLetters': driveLetters,
    'partitions': partitions
        .map(
          (partition) => {
            'type': partition.type,
            'sizeBytes': partition.sizeBytes,
            'driveLetter': partition.driveLetter,
            'isSystem': partition.isSystem,
            'isActive': partition.isActive,
          },
        )
        .toList(),
  };

  factory DiskInfo.fromJson(Map<String, dynamic> json) {
    final rawPartitions = json['partitions'];
    return DiskInfo(
      diskNumber: json['diskNumber'] as int,
      model: json['model'] as String,
      friendlyName: json['friendlyName'] as String,
      sizeBytes: json['sizeBytes'] as int,
      sizeFormatted: json['sizeFormatted'] as String,
      serialNumber: json['serialNumber'] as String? ?? '',
      uniqueId: json['uniqueId'] as String? ?? '',
      devicePath: json['devicePath'] as String? ?? '',
      busType: json['busType'] as String? ?? 'Unknown',
      partitionStyle: json['partitionStyle'] as String? ?? 'Unknown',
      isSystem: json['isSystem'] as bool? ?? false,
      isBoot: json['isBoot'] as bool? ?? false,
      isOffline: json['isOffline'] as bool? ?? false,
      isRemovable: json['isRemovable'] as bool? ?? false,
      driveLetters: (json['driveLetters'] as List<dynamic>? ?? const [])
          .map((value) => value.toString())
          .toList(),
      partitions: rawPartitions is List
          ? rawPartitions
                .whereType<Map>()
                .map(
                  (value) => DiskPartition(
                    type: value['type']?.toString() ?? '',
                    sizeBytes: (value['sizeBytes'] as num?)?.toInt() ?? 0,
                    driveLetter: value['driveLetter']?.toString(),
                    isSystem: value['isSystem'] as bool? ?? false,
                    isActive: value['isActive'] as bool? ?? false,
                  ),
                )
                .toList()
          : const [],
    );
  }

  static String _normalizedIdentityValue(String value) =>
      value.trim().replaceAll(RegExp(r'\s+'), '').toUpperCase();

  static bool _isReliableIdentityValue(String value) {
    if (value.isEmpty || value == 'N/A' || value == 'UNKNOWN') return false;
    final compact = value.replaceAll(RegExp(r'[^A-Z0-9]'), '');
    if (compact.length < 4) return false;
    return !RegExp(r'^(0+|F+)$').hasMatch(compact);
  }

  static bool _isReliableDevicePath(String value) {
    if (!_isReliableIdentityValue(value)) return false;
    return !RegExp(r'^(?:\\\\[.?]\\)?PHYSICALDRIVE\d+$').hasMatch(value);
  }

  String get reliableSerialNumber {
    final value = _normalizedIdentityValue(serialNumber);
    return _isReliableIdentityValue(value) ? value : '';
  }

  String get reliableUniqueId {
    final value = _normalizedIdentityValue(uniqueId);
    return _isReliableIdentityValue(value) ? value : '';
  }

  String get reliableDevicePath {
    final value = _normalizedIdentityValue(devicePath);
    return _isReliableDevicePath(value) ? value : '';
  }
}

class DiskPartition {
  final String type;
  final int sizeBytes;
  final String? driveLetter;
  final bool isSystem;
  final bool isActive;

  const DiskPartition({
    required this.type,
    required this.sizeBytes,
    this.driveLetter,
    this.isSystem = false,
    this.isActive = false,
  });
}

class SafetyCheckResult {
  final bool isSafe;
  final String reason;
  final Map<String, String>? params;

  const SafetyCheckResult({
    required this.isSafe,
    this.reason = '',
    this.params,
  });
}

class DiskOperationLock {
  static const _mutexNamePrefix = r'Global\WinDeployStudio.DiskOperation.';
  static const _waitObject0 = 0x00000000;
  static const _waitAbandoned = 0x00000080;

  final Pointer<Void> _handle;
  bool _released = false;

  DiskOperationLock._(this._handle);

  static Future<DiskOperationLock?> tryAcquire(int diskNumber) async {
    if (!Platform.isWindows) return null;

    Pointer<Uint16>? name;
    Pointer<Void>? handle;
    try {
      name = _allocateWideString('$_mutexNamePrefix$diskNumber');
      final mutex = _createMutex(nullptr.cast<Void>(), 0, name);
      handle = mutex;
      if (mutex.address == 0) return null;

      final waitResult = _waitForSingleObject(mutex, 0);
      if (waitResult != _waitObject0 && waitResult != _waitAbandoned) {
        _closeHandle(mutex);
        handle = null;
        return null;
      }

      return DiskOperationLock._(mutex);
    } catch (_) {
      if (handle != null && handle.address != 0) {
        _closeHandle(handle);
      }
      return null;
    } finally {
      if (name != null && name.address != 0) {
        _localFree(name.cast<Void>());
      }
    }
  }

  Future<void> release() async {
    if (_released) return;
    _released = true;
    _releaseMutex(_handle);
    _closeHandle(_handle);
  }

  static final _kernel32 = DynamicLibrary.open('kernel32.dll');
  static final _createMutex = _kernel32
      .lookupFunction<_CreateMutexWNative, _CreateMutexWDart>('CreateMutexW');
  static final _waitForSingleObject = _kernel32
      .lookupFunction<_WaitForSingleObjectNative, _WaitForSingleObjectDart>(
        'WaitForSingleObject',
      );
  static final _releaseMutex = _kernel32
      .lookupFunction<_ReleaseMutexNative, _ReleaseMutexDart>('ReleaseMutex');
  static final _closeHandle = _kernel32
      .lookupFunction<_CloseHandleNative, _CloseHandleDart>('CloseHandle');
  static final _localAlloc = _kernel32
      .lookupFunction<_LocalAllocNative, _LocalAllocDart>('LocalAlloc');
  static final _localFree = _kernel32
      .lookupFunction<_LocalFreeNative, _LocalFreeDart>('LocalFree');

  static Pointer<Uint16> _allocateWideString(String value) {
    final codeUnits = value.codeUnits;
    final pointer = _localAlloc(
      _localAllocZeroInitialized,
      (codeUnits.length + 1) * sizeOf<Uint16>(),
    ).cast<Uint16>();
    if (pointer.address == 0) {
      throw StateError('Unable to allocate the disk operation mutex name.');
    }
    pointer
        .asTypedList(codeUnits.length + 1)
        .setRange(0, codeUnits.length, codeUnits);
    return pointer;
  }
}

typedef _CreateMutexWNative =
    Pointer<Void> Function(
      Pointer<Void> mutexAttributes,
      Int32 initialOwner,
      Pointer<Uint16> name,
    );
typedef _CreateMutexWDart =
    Pointer<Void> Function(
      Pointer<Void> mutexAttributes,
      int initialOwner,
      Pointer<Uint16> name,
    );
typedef _WaitForSingleObjectNative =
    Uint32 Function(Pointer<Void> handle, Uint32 milliseconds);
typedef _WaitForSingleObjectDart =
    int Function(Pointer<Void> handle, int milliseconds);
typedef _ReleaseMutexNative = Int32 Function(Pointer<Void> handle);
typedef _ReleaseMutexDart = int Function(Pointer<Void> handle);
typedef _CloseHandleNative = Int32 Function(Pointer<Void> handle);
typedef _CloseHandleDart = int Function(Pointer<Void> handle);
typedef _LocalAllocNative = Pointer<Void> Function(Uint32 flags, IntPtr size);
typedef _LocalAllocDart = Pointer<Void> Function(int flags, int size);
typedef _LocalFreeNative = Pointer<Void> Function(Pointer<Void> memory);
typedef _LocalFreeDart = Pointer<Void> Function(Pointer<Void> memory);

const _localAllocZeroInitialized = 0x40;

final diskSafetyServiceProvider = Provider<DiskSafetyService>((ref) {
  return DiskSafetyService();
});

class DiskSafetyService {
  static const _nativeDiskHelperName = 'wds_disk_diagnostics_helper.exe';
  Process? _driveLetterEnumerationProcess;
  Timer? _driveLetterEnumerationTimeout;
  Completer<ProcessResult>? _driveLetterEnumerationCompleter;
  Future<Set<String>>? _driveLetterEnumerationFuture;

  static const _processCleanupTimeout = Duration(seconds: 3);
  static const _processOutputTimeout = Duration(seconds: 2);

  static const _secureDirectoryAclScript = r'''
$ErrorActionPreference = 'Stop'
$path = $env:WDS_SECURE_PATH
$acl = [System.Security.AccessControl.DirectorySecurity]::new()
$acl.SetAccessRuleProtection($true, $false)
$inherit = [System.Security.AccessControl.InheritanceFlags]::ContainerInherit -bor [System.Security.AccessControl.InheritanceFlags]::ObjectInherit
$propagation = [System.Security.AccessControl.PropagationFlags]::None
$allow = [System.Security.AccessControl.AccessControlType]::Allow
$system = [System.Security.Principal.SecurityIdentifier]::new('S-1-5-18')
$administrators = [System.Security.Principal.SecurityIdentifier]::new('S-1-5-32-544')
$acl.SetOwner($administrators)
$acl.AddAccessRule([System.Security.AccessControl.FileSystemAccessRule]::new($system, 'FullControl', $inherit, $propagation, $allow))
$acl.AddAccessRule([System.Security.AccessControl.FileSystemAccessRule]::new($administrators, 'FullControl', $inherit, $propagation, $allow))
Set-Acl -LiteralPath $path -AclObject $acl
$allowed = @('S-1-5-18', 'S-1-5-32-544')
$actual = @((Get-Acl -LiteralPath $path).Access | Where-Object AccessControlType -eq Allow | ForEach-Object { $_.IdentityReference.Translate([System.Security.Principal.SecurityIdentifier]).Value } | Sort-Object -Unique)
if ($actual.Count -ne 2 -or @($actual | Where-Object { $_ -notin $allowed }).Count -ne 0) { throw 'Secure script ACL verification failed.' }
''';

  static const _guardedDiskpartScript = r'''
$ErrorActionPreference = 'Stop'
$disk = Get-Disk -Number ([int]$env:WDS_DISK_NUMBER) -ErrorAction Stop
$bus = $disk.BusType.ToString().ToUpperInvariant()
$isExternal = $bus -in @('USB', 'SD', 'MMC') -or [bool]$disk.IsRemovable
if (-not $isExternal -or $disk.IsSystem -or $disk.IsBoot -or $disk.IsOffline) {
  throw 'Target disk is no longer a safe external disk.'
}
if ([int64]$disk.Size -ne [int64]$env:WDS_DISK_SIZE) {
  throw 'Target disk size changed after selection.'
}
if ($disk.FriendlyName.ToString().Trim().ToUpperInvariant() -ne $env:WDS_DISK_MODEL) {
  throw 'Target disk model changed after selection.'
}
if ($bus -ne $env:WDS_DISK_BUS) {
  throw 'Target disk bus changed after selection.'
}
if ($env:WDS_DISK_SERIAL) {
  $physical = Get-PhysicalDisk -ErrorAction Stop |
    Where-Object { $_.DeviceId -eq $disk.Number.ToString() } |
    Select-Object -First 1
  $currentSerial = if ($physical -and $physical.SerialNumber) {
    $physical.SerialNumber.ToString().Trim().ToUpperInvariant()
  } else { '' }
  if ($currentSerial -ne $env:WDS_DISK_SERIAL) {
    throw 'Target disk serial number changed after selection.'
  }
} elseif ($env:WDS_DISK_UNIQUE_ID) {
  $currentId = if ($disk.UniqueId) { $disk.UniqueId.ToString().Trim().ToUpperInvariant() } else { '' }
  if ($currentId -ne $env:WDS_DISK_UNIQUE_ID) {
    throw 'Target disk identity changed after selection.'
  }
} elseif ($env:WDS_DISK_PATH) {
  $currentPath = if ($disk.Path) { $disk.Path.ToString().Trim().ToUpperInvariant() } else { '' }
  if ($currentPath -ne $env:WDS_DISK_PATH) {
    throw 'Target disk device path changed after selection.'
  }
} else {
  throw 'Target disk has no reliable physical identity.'
}
$actualHash = (Get-FileHash -LiteralPath $env:WDS_DISKPART_SCRIPT -Algorithm SHA256 -ErrorAction Stop).Hash
if ($actualHash -ne $env:WDS_DISKPART_SHA256) {
  throw 'The guarded DiskPart script changed after validation.'
}
& "$env:SystemRoot\System32\diskpart.exe" /s $env:WDS_DISKPART_SCRIPT
exit $LASTEXITCODE
''';

  static const _guardedDiskInitializationScript = r'''
$ErrorActionPreference = 'Stop'
$targetStyle = $env:WDS_PARTITION_STYLE.Trim().ToUpperInvariant()
if ($targetStyle -notin @('GPT', 'MBR')) {
  throw 'Requested partition style is invalid.'
}

function Normalize-IdentityValue([object]$Value) {
  if ($null -eq $Value) { return '' }
  return ($Value.ToString() -replace '\s+', '').ToUpperInvariant()
}

function Assert-TargetDisk([bool]$CheckIdentity, [bool]$RequireOnline) {
  $disk = Get-Disk -Number ([int]$env:WDS_DISK_NUMBER) -ErrorAction Stop
  $bus = $disk.BusType.ToString().ToUpperInvariant()
  $isExternal = $bus -in @('USB', 'SD', 'MMC') -or [bool]$disk.IsRemovable
  if (-not $isExternal -or $disk.IsSystem -or $disk.IsBoot) {
    throw 'Target disk is no longer a safe external disk.'
  }
  if ($RequireOnline -and $disk.IsOffline) {
    throw 'Target disk is offline.'
  }
  if ([int64]$disk.Size -ne [int64]$env:WDS_DISK_SIZE) {
    throw 'Target disk size changed after selection.'
  }
  if ($disk.FriendlyName.ToString().Trim().ToUpperInvariant() -ne $env:WDS_DISK_MODEL) {
    throw 'Target disk model changed after selection.'
  }
  if ($bus -ne $env:WDS_DISK_BUS) {
    throw 'Target disk bus changed after selection.'
  }
  if ($CheckIdentity) {
    if ($env:WDS_DISK_SERIAL) {
      $physical = Get-PhysicalDisk -ErrorAction Stop |
        Where-Object { $_.DeviceId -eq $disk.Number.ToString() } |
        Select-Object -First 1
      $diskSerial = if ($disk.SerialNumber) {
        Normalize-IdentityValue $disk.SerialNumber
      } else { '' }
      $physicalSerial = if ($physical -and $physical.SerialNumber) {
        Normalize-IdentityValue $physical.SerialNumber
      } else { '' }
      if ($diskSerial -ne $env:WDS_DISK_SERIAL -and
          $physicalSerial -ne $env:WDS_DISK_SERIAL) {
        throw 'Target disk serial number changed after selection.'
      }
    } elseif ($env:WDS_DISK_UNIQUE_ID) {
      $currentId = if ($disk.UniqueId) { Normalize-IdentityValue $disk.UniqueId } else { '' }
      if ($currentId -ne $env:WDS_DISK_UNIQUE_ID) {
        throw 'Target disk identity changed after selection.'
      }
    } elseif ($env:WDS_DISK_PATH) {
      $currentPath = if ($disk.Path) { Normalize-IdentityValue $disk.Path } else { '' }
      if ($currentPath -ne $env:WDS_DISK_PATH) {
        throw 'Target disk device path changed after selection.'
      }
    } else {
      throw 'Target disk has no reliable physical identity.'
    }
  }
  return $disk
}

function Assert-PersistentIdentity([object]$Disk) {
  if ($env:WDS_DISK_SERIAL) {
    $physical = Get-PhysicalDisk -ErrorAction Stop |
      Where-Object { $_.DeviceId -eq $Disk.Number.ToString() } |
      Select-Object -First 1
    $diskSerial = if ($Disk.SerialNumber) {
      Normalize-IdentityValue $Disk.SerialNumber
    } else { '' }
    $physicalSerial = if ($physical -and $physical.SerialNumber) {
      Normalize-IdentityValue $physical.SerialNumber
    } else { '' }
    if ($diskSerial -ne $env:WDS_DISK_SERIAL -and
        $physicalSerial -ne $env:WDS_DISK_SERIAL) {
      throw 'Target disk serial number changed while initializing.'
    }
    return
  }
  if ($env:WDS_DISK_PATH) {
    $currentPath = if ($Disk.Path) { Normalize-IdentityValue $Disk.Path } else { '' }
    if ($currentPath -ne $env:WDS_DISK_PATH) {
      throw 'Target disk device path changed while initializing.'
    }
    return
  }
  throw 'Target disk has no persistent identity after it was cleared.'
}

$disk = Assert-TargetDisk $true $true
if ($disk.IsReadOnly) {
  Set-Disk -Number $disk.Number -IsReadOnly $false -ErrorAction Stop | Out-Null
}
Clear-Disk -Number $disk.Number -RemoveData -RemoveOEM -Confirm:$false -ErrorAction Stop | Out-Null
$deadline = [DateTime]::UtcNow.AddSeconds(5)
do {
  Update-Disk -Number $disk.Number -ErrorAction Stop | Out-Null
  Start-Sleep -Milliseconds 150
  $disk = Assert-TargetDisk $false $false
  $partitions = @(Get-Partition -DiskNumber $disk.Number -ErrorAction SilentlyContinue)
  if ($partitions.Count -eq 0) {
    break
  }
} while ([DateTime]::UtcNow -lt $deadline)
if (@(Get-Partition -DiskNumber $disk.Number -ErrorAction SilentlyContinue).Count -ne 0) {
  throw 'Target disk still has partitions after it was cleared.'
}

# The disk signature/unique ID can legitimately change after Clear-Disk.
# Require a persistent serial number or device path before reinitializing it.
Assert-PersistentIdentity $disk
if ($disk.IsOffline) {
  Set-Disk -Number $disk.Number -IsOffline $false -ErrorAction Stop | Out-Null
}
$clearedStyle = $disk.PartitionStyle.ToString().ToUpperInvariant()
if ($clearedStyle -eq 'RAW') {
  Initialize-Disk -Number $disk.Number -PartitionStyle $targetStyle -ErrorAction Stop | Out-Null
} elseif ($clearedStyle -ne $targetStyle -and $clearedStyle -in @('GPT', 'MBR')) {
  # Some USB bridges report an empty MBR/GPT disk instead of RAW after
  # Clear-Disk. Convert only this known, empty state; final style and zero
  # partition checks below remain authoritative.
  $diskpartInput = @(
    "select disk $($disk.Number)",
    "convert $($targetStyle.ToLowerInvariant())",
    'exit'
  ) -join [Environment]::NewLine
  $diskpartInput | & "$env:SystemRoot\System32\diskpart.exe"
  if ($LASTEXITCODE -ne 0) {
    throw "DiskPart could not convert empty $clearedStyle disk to $targetStyle."
  }
} elseif ($clearedStyle -ne $targetStyle) {
  throw "Target disk has unsupported cleared style $clearedStyle."
}
Update-Disk -Number $disk.Number -ErrorAction Stop | Out-Null
$initialized = Get-Disk -Number $disk.Number -ErrorAction Stop
if ($initialized.PartitionStyle.ToString().ToUpperInvariant() -ne $targetStyle) {
  throw "Target disk did not initialize as $targetStyle."
}
if (@(Get-Partition -DiskNumber $initialized.Number -ErrorAction SilentlyContinue).Count -ne 0) {
  throw 'Target disk has partitions immediately after initialization.'
}
Assert-PersistentIdentity $initialized
Write-Output 'WDS_DISK_INITIALIZED'
''';

  Future<List<DiskInfo>> getAllDisks() async {
    try {
      return await _queryAllDisks();
    } catch (_) {
      // Storage PowerShell can be unavailable during the first seconds after
      // a USB device is attached, or when a bridge blocks one of its cmdlets.
      // The native helper only uses bounded read-only IOCTLs for inventory and
      // is a reliable fallback instead of presenting a false empty list.
      try {
        return await _queryAllDisksWithNativeHelper();
      } catch (_) {
        // Keep the existing non-throwing contract for callers that render an
        // empty state when both inventory providers are unavailable.
        return [];
      }
    }
  }

  Future<DiskInfo?> getDiskByNumber(int diskNumber) async {
    final disks = await getAllDisks();
    final matches = disks.where((disk) => disk.diskNumber == diskNumber);
    return matches.length == 1 ? matches.single : null;
  }

  Future<List<DiskInfo>> getRemovableDisks() async {
    final allDisks = await getAllDisks();
    return allDisks.where((d) {
      final busType = d.busType.toUpperCase();
      final isExternalMedia =
          busType == 'USB' ||
          busType == 'SD' ||
          busType == 'MMC' ||
          d.isRemovable;
      return isExternalMedia && !d.isSystem && !d.isBoot && !d.isOffline;
    }).toList();
  }

  /// Returns drive letters currently exposed by local, virtual, and network
  /// file-system providers. The creator uses this to avoid offering a letter
  /// that Windows would reject during DiskPart assignment.
  Future<Set<String>> getUsedDriveLetters() {
    final active = _driveLetterEnumerationFuture;
    if (active != null) return active;
    final future = _enumerateUsedDriveLetters();
    _driveLetterEnumerationFuture = future;
    unawaited(
      future.whenComplete(() {
        if (identical(_driveLetterEnumerationFuture, future)) {
          _driveLetterEnumerationFuture = null;
        }
      }),
    );
    return future;
  }

  Future<Set<String>> _enumerateUsedDriveLetters() async {
    try {
      final process = await Process.start(
        WindowsSystemEnvironment.powerShellExecutable,
        const [
          '-NoProfile',
          '-NonInteractive',
          '-ExecutionPolicy',
          'Bypass',
          '-Command',
          r'''@(
  Get-Volume -ErrorAction SilentlyContinue | Where-Object DriveLetter | ForEach-Object { $_.DriveLetter }
  Get-PSDrive -PSProvider FileSystem -ErrorAction SilentlyContinue | ForEach-Object { $_.Name }
) | ForEach-Object { $_.ToString().ToUpperInvariant() } | Sort-Object -Unique''',
        ],
        environment: WindowsSystemEnvironment.withSystemRoot(),
      );
      _driveLetterEnumerationProcess = process;
      final stdoutFuture = process.stdout
          .transform(const SystemEncoding().decoder)
          .join();
      final stderrFuture = process.stderr
          .transform(const SystemEncoding().decoder)
          .join();
      final completer = Completer<ProcessResult>();
      _driveLetterEnumerationCompleter = completer;
      process.exitCode.then((exitCode) async {
        final result = ProcessResult(
          process.pid,
          exitCode,
          await stdoutFuture,
          await stderrFuture,
        );
        if (!completer.isCompleted) completer.complete(result);
      });
      _driveLetterEnumerationTimeout = Timer(const Duration(seconds: 15), () {
        unawaited(_terminateProcessTree(process));
        if (!completer.isCompleted) {
          completer.complete(
            ProcessResult(process.pid, -1, '', 'Drive-letter query timed out.'),
          );
        }
      });
      final result = await completer.future;
      if (result.exitCode != 0) return const <String>{};
      return result.stdout
          .toString()
          .split(RegExp(r'\r?\n'))
          .map((value) => value.replaceAll(':', '').trim().toUpperCase())
          .where((value) => RegExp(r'^[D-Z]$').hasMatch(value))
          .toSet();
    } catch (_) {
      // An unavailable enumeration must not block the creator. DiskPart still
      // validates the selected letter under the target-disk safety guard.
      return const <String>{};
    } finally {
      _driveLetterEnumerationTimeout?.cancel();
      _driveLetterEnumerationTimeout = null;
      _driveLetterEnumerationProcess = null;
      _driveLetterEnumerationCompleter = null;
    }
  }

  void cancelUsedDriveLetters() {
    _driveLetterEnumerationTimeout?.cancel();
    _driveLetterEnumerationTimeout = null;
    final process = _driveLetterEnumerationProcess;
    // Cancellation is normally triggered while a widget is being disposed.
    // Kill the short-lived query synchronously here so disposal does not leave
    // a background taskkill process or timer behind.  Timeout paths still use
    // _terminateProcessTree to clean up descendants.
    if (process != null) {
      try {
        process.kill(ProcessSignal.sigkill);
      } catch (_) {}
    }
    final completer = _driveLetterEnumerationCompleter;
    if (completer != null && !completer.isCompleted) {
      completer.complete(ProcessResult(0, -1, '', 'Enumeration cancelled.'));
    }
  }

  Future<SafetyCheckResult> checkDiskSafety(DiskInfo disk) async {
    try {
      // A complete Storage inventory can block on an unrelated USB bridge.
      // Once the user has selected a disk, query only that disk so a slow
      // sibling cannot prevent a safe target from being selected.
      final currentDisk = await _queryDiskByNumber(disk);
      if (!disk.hasSamePhysicalIdentity(currentDisk)) {
        return const SafetyCheckResult(
          isSafe: false,
          reason: 'safety_disk_changed',
        );
      }

      return await _checkCurrentDiskSafety(
        currentDisk,
        fallbackDriveLetters: disk.driveLetters,
      );
    } catch (error) {
      final detail = _formatSafetyDiagnostic(error);
      if (detail.isEmpty) {
        return const SafetyCheckResult(
          isSafe: false,
          reason: 'safety_detection_failed',
        );
      }
      return SafetyCheckResult(
        isSafe: false,
        reason: 'safety_detection_failed_detail',
        params: {'detail': _safetyDiagnosticToken(detail)},
      );
    }
  }

  Future<DiskInfo?> refreshDisk(DiskInfo snapshot) async {
    try {
      final disks = await _queryAllDisks();
      final matches = disks.where(
        (item) => item.diskNumber == snapshot.diskNumber,
      );
      if (matches.length != 1) return null;
      final current = matches.single;
      return snapshot.hasSamePhysicalIdentity(current) ? current : null;
    } catch (_) {
      return null;
    }
  }

  /// Refreshes only the selected physical disk.
  ///
  /// A full Storage inventory is useful for the disk picker, but it is a poor
  /// post-operation probe: an unrelated USB bridge can block enumeration while
  /// the selected disk is already healthy. Keep the identity guard while
  /// avoiding that unrelated I/O.
  Future<DiskInfo?> refreshSelectedDisk(DiskInfo snapshot) async {
    try {
      final current = await _queryDiskByNumber(snapshot);
      return snapshot.hasSamePhysicalIdentity(current) ? current : null;
    } catch (_) {
      return null;
    }
  }

  /// Waits for Windows Storage to publish the requested partition style.
  ///
  /// Clear-Disk/Initialize-Disk can complete before Get-Disk reflects the new
  /// style. This bounded poll treats a missing or stale observation as
  /// transient, but still fails closed when the target never reaches the
  /// requested style or its identity no longer matches.
  Future<DiskInfo?> waitForPartitionStyle(
    DiskInfo snapshot, {
    required String expectedPartitionStyle,
    int maxAttempts = 12,
    Duration retryDelay = const Duration(milliseconds: 750),
    void Function(int attempt, String observedStyle)? onAttempt,
  }) {
    return waitForPartitionStyleWith(
      snapshot: snapshot,
      expectedPartitionStyle: expectedPartitionStyle,
      refresh: refreshSelectedDisk,
      maxAttempts: maxAttempts,
      retryDelay: retryDelay,
      onAttempt: onAttempt,
    );
  }

  @visibleForTesting
  static Future<DiskInfo?> waitForPartitionStyleWith({
    required DiskInfo snapshot,
    required String expectedPartitionStyle,
    required Future<DiskInfo?> Function(DiskInfo) refresh,
    int maxAttempts = 12,
    Duration retryDelay = const Duration(milliseconds: 750),
    void Function(int attempt, String observedStyle)? onAttempt,
    Future<void> Function(Duration duration)? delay,
  }) async {
    final expected = expectedPartitionStyle.trim().toUpperCase();
    final attempts = maxAttempts < 1 ? 1 : maxAttempts;
    final wait = delay ?? (duration) => Future<void>.delayed(duration);
    DiskInfo? latest;

    for (var attempt = 1; attempt <= attempts; attempt++) {
      latest = await refresh(snapshot);
      final observed =
          latest?.partitionStyle.trim().toUpperCase() ?? 'UNAVAILABLE';
      onAttempt?.call(attempt, observed);
      if (latest != null && observed == expected) return latest;
      if (attempt < attempts) await wait(retryDelay);
    }
    return null;
  }

  Future<ProcessResult> runGuardedDiskpart(
    DiskInfo disk,
    String diskpartScript, {
    Duration timeout = const Duration(seconds: 120),
  }) async {
    final safety = await checkDiskSafety(disk);
    if (!safety.isSafe) {
      return ProcessResult(0, -1, '', safety.reason);
    }

    final programData = Platform.environment['ProgramData'];
    if (programData == null || programData.trim().isEmpty) {
      return ProcessResult(0, -1, '', 'Secure script storage is unavailable.');
    }
    final secureDirectory = Directory(
      '$programData\\WinDeployStudioSecureScripts',
    );
    try {
      await secureDirectory.create(recursive: true);
      if (await FileSystemEntity.type(
            secureDirectory.path,
            followLinks: false,
          ) ==
          FileSystemEntityType.link) {
        return ProcessResult(0, -1, '', 'Secure script storage is a link.');
      }
      final acl = await _runProcessWithTimeout(
        WindowsSystemEnvironment.powerShellExecutable,
        const [
          '-NoProfile',
          '-NonInteractive',
          '-ExecutionPolicy',
          'Bypass',
          '-Command',
          _secureDirectoryAclScript,
        ],
        environment: WindowsSystemEnvironment.withSystemRoot({
          'WDS_SECURE_PATH': secureDirectory.path,
        }),
        timeout: const Duration(seconds: 30),
        timeoutMessage: 'Secure script ACL setup timed out after 30 seconds.',
      );
      if (acl.exitCode != 0) {
        final detail = _firstProcessDetail(acl);
        return ProcessResult(
          acl.pid,
          -1,
          acl.stdout.toString(),
          detail.isEmpty ? 'Secure script ACL setup failed.' : detail,
        );
      }
    } catch (error) {
      return ProcessResult(0, -1, '', 'Secure script setup failed: $error');
    }

    final token = '${pid}_${DateTime.now().microsecondsSinceEpoch}';
    final diskpartFile = File(
      '${secureDirectory.path}\\wds_diskpart_$token.txt',
    );
    final scriptBytes = utf8.encode(diskpartScript);
    final scriptHash = sha256.convert(scriptBytes).toString().toUpperCase();
    RandomAccessFile? scriptHandle;
    try {
      await diskpartFile.create(exclusive: true);
      scriptHandle = await diskpartFile.open(mode: FileMode.writeOnly);
      await scriptHandle.writeFrom(scriptBytes);
      await scriptHandle.flush();
    } catch (error) {
      try {
        if (await diskpartFile.exists()) await diskpartFile.delete();
      } catch (_) {}
      return ProcessResult(0, -1, '', 'Secure script write failed: $error');
    } finally {
      await scriptHandle?.close();
    }
    final environment = WindowsSystemEnvironment.withSystemRoot({
      'WDS_DISK_NUMBER': '${disk.diskNumber}',
      'WDS_DISK_SIZE': '${disk.sizeBytes}',
      'WDS_DISK_MODEL': disk.model.trim().toUpperCase(),
      'WDS_DISK_BUS': disk.busType.trim().toUpperCase(),
      'WDS_DISK_UNIQUE_ID': disk.reliableUniqueId,
      'WDS_DISK_SERIAL': disk.reliableSerialNumber,
      'WDS_DISK_PATH': disk.reliableDevicePath,
      'WDS_DISKPART_SCRIPT': diskpartFile.path,
      'WDS_DISKPART_SHA256': scriptHash,
    });

    try {
      return await _runProcessWithTimeout(
        WindowsSystemEnvironment.powerShellExecutable,
        const [
          '-NoProfile',
          '-ExecutionPolicy',
          'Bypass',
          '-Command',
          _guardedDiskpartScript,
        ],
        environment: environment,
        timeout: timeout,
        timeoutMessage: 'DiskPart timed out.',
      );
    } catch (error) {
      return ProcessResult(0, -1, '', error.toString());
    } finally {
      try {
        if (await diskpartFile.exists()) await diskpartFile.delete();
      } catch (_) {}
    }
  }

  Future<ProcessResult> initializeDiskPartitionStyle(
    DiskInfo disk, {
    required String partitionStyle,
    Duration timeout = const Duration(seconds: 90),
  }) async {
    final targetStyle = partitionStyle.trim().toUpperCase();
    if (targetStyle != 'GPT' && targetStyle != 'MBR') {
      return ProcessResult(
        0,
        -1,
        '',
        'Unsupported partition style: $partitionStyle',
      );
    }
    final safety = await checkDiskSafety(disk);
    if (!safety.isSafe) {
      return ProcessResult(0, -1, '', safety.reason);
    }

    final environment = WindowsSystemEnvironment.withSystemRoot({
      'WDS_DISK_NUMBER': '${disk.diskNumber}',
      'WDS_DISK_SIZE': '${disk.sizeBytes}',
      'WDS_DISK_MODEL': disk.model.trim().toUpperCase(),
      'WDS_DISK_BUS': disk.busType.trim().toUpperCase(),
      'WDS_DISK_UNIQUE_ID': disk.reliableUniqueId,
      'WDS_DISK_SERIAL': disk.reliableSerialNumber,
      'WDS_DISK_PATH': disk.reliableDevicePath,
      'WDS_PARTITION_STYLE': targetStyle,
    });
    try {
      final result = await _runProcessWithTimeout(
        WindowsSystemEnvironment.powerShellExecutable,
        const [
          '-NoProfile',
          '-ExecutionPolicy',
          'Bypass',
          '-Command',
          _guardedDiskInitializationScript,
        ],
        environment: environment,
        timeout: timeout,
        timeoutMessage: 'Disk initialization timed out.',
      );
      final stdout = result.stdout.toString();
      final stderr = result.stderr.toString();
      if (result.exitCode == 0 && !stdout.contains('WDS_DISK_INITIALIZED')) {
        return ProcessResult(
          result.pid,
          -1,
          stdout,
          '$stderr\nDisk initialization did not confirm completion.',
        );
      }
      return result;
    } catch (error) {
      return ProcessResult(0, -1, '', error.toString());
    }
  }

  Future<SafetyCheckResult> _checkCurrentDiskSafety(
    DiskInfo disk, {
    List<String> fallbackDriveLetters = const [],
  }) async {
    if (!_isExternalMedia(disk)) {
      return const SafetyCheckResult(
        isSafe: false,
        reason: 'safety_not_external',
      );
    }

    if (disk.isOffline) {
      return const SafetyCheckResult(
        isSafe: false,
        reason: 'safety_disk_offline',
      );
    }

    if (disk.isSystem) {
      return const SafetyCheckResult(
        isSafe: false,
        reason: 'safety_system_disk',
      );
    }

    if (disk.isBoot) {
      return const SafetyCheckResult(isSafe: false, reason: 'safety_boot_disk');
    }

    final knownDriveLetters = {...disk.driveLetters, ...fallbackDriveLetters}
        .map(
          (letter) =>
              letter.trim().replaceAll(RegExp(r'[:\\]'), '').toUpperCase(),
        )
        .where((letter) => letter.length == 1)
        .toSet();
    final windowsDrive = _getWindowsDriveLetter();
    if (knownDriveLetters.contains(windowsDrive)) {
      return SafetyCheckResult(
        isSafe: false,
        reason: 'safety_windows_install',
        params: {'drive': '$windowsDrive:\\'},
      );
    }

    return const SafetyCheckResult(isSafe: true);
  }

  bool _isExternalMedia(DiskInfo disk) {
    final busType = disk.busType.toUpperCase();
    return busType == 'USB' ||
        busType == 'SD' ||
        busType == 'MMC' ||
        disk.isRemovable;
  }

  String _getWindowsDriveLetter() {
    final candidates = <String?>[
      Platform.environment['SystemDrive'],
      Platform.environment['SystemRoot'],
      Platform.environment['WINDIR'],
      WindowsSystemEnvironment.systemRoot,
    ];
    for (final candidate in candidates) {
      final normalized = candidate?.trim().replaceAll('/', '\\') ?? '';
      final match = RegExp(r'^([A-Za-z]):(?:\\|$)').firstMatch(normalized);
      if (match != null) return match.group(1)!.toUpperCase();
    }
    throw StateError('Windows system drive is unavailable.');
  }

  static String _firstProcessDetail(ProcessResult result) {
    final stderr = result.stderr.toString().trim();
    if (stderr.isNotEmpty) return stderr;
    return result.stdout.toString().trim();
  }

  static String _formatSafetyDiagnostic(Object error) {
    var detail = error.toString().trim();
    detail = detail.replaceFirst(
      RegExp(r'^(Bad state: |StateError: |TimeoutException: )'),
      '',
    );
    detail = detail.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (detail.length > 260) {
      detail = '${detail.substring(0, 257)}...';
    }
    return detail;
  }

  Future<List<DiskInfo>> _queryAllDisks() async {
    late final ProcessResult result;
    try {
      result = await _runProcessWithTimeout(
        WindowsSystemEnvironment.powerShellExecutable,
        const [
          '-NoProfile',
          '-NonInteractive',
          '-ExecutionPolicy',
          'Bypass',
          '-Command',
          _getAllDisksScript,
        ],
        environment: WindowsSystemEnvironment.withSystemRoot(),
        timeout: const Duration(seconds: 10),
        timeoutMessage: 'Disk inventory query timed out after 10 seconds.',
      );
    } on ProcessException catch (error) {
      throw StateError('Disk inventory query could not start: $error');
    }

    if (result.exitCode != 0) {
      throw StateError('Disk enumeration failed: ${result.stderr}');
    }
    final output = result.stdout.toString().trim();
    if (output.isEmpty) throw StateError('Disk enumeration returned no data');
    final disks = _parseDisks(output);
    if (disks.isEmpty) throw StateError('Disk enumeration could not be parsed');
    return disks;
  }

  Future<DiskInfo> _queryDiskByNumber(DiskInfo snapshot) async {
    final nativeHelper = _nativeHelperFile();
    if (await nativeHelper.exists()) {
      return _queryDiskWithNativeHelper(nativeHelper.path, snapshot);
    }
    return _queryDiskByNumberWithPowerShell(snapshot.diskNumber);
  }

  File _nativeHelperFile() => File(
    '${File(Platform.resolvedExecutable).parent.path}${Platform.pathSeparator}$_nativeDiskHelperName',
  );

  Future<List<DiskInfo>> _queryAllDisksWithNativeHelper() async {
    final nativeHelper = _nativeHelperFile();
    if (!await nativeHelper.exists()) {
      throw StateError('Native disk inventory helper is unavailable.');
    }

    late final ProcessResult result;
    try {
      result = await _runProcessWithTimeout(
        nativeHelper.path,
        const ['--inventory'],
        environment: WindowsSystemEnvironment.withSystemRoot(),
        timeout: const Duration(seconds: 18),
        timeoutMessage:
            'Native disk inventory query timed out after 18 seconds.',
      );
    } on ProcessException catch (error) {
      throw StateError('Native disk inventory query could not start: $error');
    }
    if (result.exitCode != 0) {
      throw StateError('Native disk inventory query failed: ${result.stderr}');
    }

    final output = result.stdout.toString().trim();
    if (output.isEmpty) {
      throw StateError('Native disk inventory returned no data.');
    }
    final decoded = jsonDecode(output);
    if (decoded is! Map) {
      throw StateError('Native disk inventory returned invalid data.');
    }
    final reports = decoded['reports'];
    if (reports is! List) {
      throw StateError('Native disk inventory returned no reports.');
    }

    final disks = <DiskInfo>[];
    for (final report in reports) {
      final disk = _parseNativeInventoryDisk(report);
      if (disk != null) disks.add(disk);
    }
    if (disks.isEmpty) {
      throw StateError('Native disk inventory returned no usable disks.');
    }
    return disks;
  }

  DiskInfo? _parseNativeInventoryDisk(dynamic value) {
    if (value is! Map) return null;
    final data = Map<String, dynamic>.from(value);
    if (_readNullableBool(data['present']) == false) return null;

    final diskNumber = _readInt(data['diskNumber']);
    final sizeBytes = _readInt(data['sizeBytes']);
    final model = data['model']?.toString().trim() ?? '';
    final busType = data['busType']?.toString().trim() ?? '';
    if (diskNumber < 0 || sizeBytes <= 0 || model.isEmpty || busType.isEmpty) {
      return null;
    }

    final driveLetters = _parseDriveLetters(data['driveLetters']);
    return DiskInfo(
      diskNumber: diskNumber,
      model: model,
      friendlyName: model,
      sizeBytes: sizeBytes,
      sizeFormatted: _formatSize(sizeBytes),
      serialNumber: data['serialNumber']?.toString() ?? '',
      uniqueId: data['uniqueId']?.toString() ?? '',
      devicePath: data['devicePath']?.toString() ?? '',
      busType: busType,
      partitionStyle: data['partitionStyle']?.toString() ?? 'Unknown',
      isSystem: _readNullableBool(data['isSystem']) ?? false,
      isBoot: _readNullableBool(data['isBoot']) ?? false,
      isOffline: _readNullableBool(data['isOffline']) ?? false,
      isRemovable:
          _readNullableBool(data['isRemovable']) ??
          const {'USB', 'SD', 'MMC'}.contains(busType.toUpperCase()),
      driveLetters: driveLetters,
    );
  }

  Future<DiskInfo> _queryDiskWithNativeHelper(
    String helperPath,
    DiskInfo snapshot,
  ) async {
    late final ProcessResult result;
    try {
      result = await _runProcessWithTimeout(
        helperPath,
        ['--identity', '${snapshot.diskNumber}'],
        environment: WindowsSystemEnvironment.withSystemRoot({
          'WDS_DISK_NUMBER': '${snapshot.diskNumber}',
        }),
        timeout: const Duration(seconds: 20),
        timeoutMessage:
            'Native selected disk query timed out after 20 seconds.',
      );
    } on ProcessException catch (error) {
      throw StateError('Native selected disk query could not start: $error');
    }

    if (result.exitCode != 0) {
      throw StateError('Native selected disk query failed: ${result.stderr}');
    }
    final output = result.stdout.toString().trim();
    if (output.isEmpty) {
      throw StateError('Native selected disk query returned no data');
    }
    try {
      final decoded = jsonDecode(output);
      if (decoded is! Map) throw const FormatException();
      return _parseNativeDiskInfo(Map<String, dynamic>.from(decoded), snapshot);
    } on FormatException {
      throw StateError('Native selected disk query returned invalid data');
    }
  }

  DiskInfo _parseNativeDiskInfo(Map<String, dynamic> data, DiskInfo snapshot) {
    final diskNumber = _readInt(data['diskNumber']);
    final sizeBytes = _readInt(data['sizeBytes']);
    final model = data['model']?.toString().trim() ?? '';
    final busType = data['busType']?.toString().trim() ?? '';
    if (diskNumber != snapshot.diskNumber ||
        sizeBytes <= 0 ||
        model.isEmpty ||
        busType.isEmpty) {
      throw StateError(
        'Native selected disk query returned incomplete identity',
      );
    }

    final nativeDriveLetters = _parseDriveLetters(data['driveLetters']);
    return DiskInfo(
      diskNumber: diskNumber,
      model: model,
      friendlyName: model,
      sizeBytes: sizeBytes,
      sizeFormatted: _formatSize(sizeBytes),
      serialNumber: data['serialNumber']?.toString() ?? '',
      uniqueId: data['uniqueId']?.toString() ?? '',
      devicePath: data['devicePath']?.toString() ?? '',
      busType: busType,
      partitionStyle:
          data['partitionStyle']?.toString() ?? snapshot.partitionStyle,
      isSystem: _readNullableBool(data['isSystem']) ?? snapshot.isSystem,
      isBoot: _readNullableBool(data['isBoot']) ?? snapshot.isBoot,
      isOffline: _readNullableBool(data['isOffline']) ?? snapshot.isOffline,
      isRemovable:
          _readNullableBool(data['isRemovable']) ?? snapshot.isRemovable,
      driveLetters: nativeDriveLetters.isEmpty
          ? snapshot.driveLetters
          : nativeDriveLetters,
      partitions: snapshot.partitions,
    );
  }

  Future<DiskInfo> _queryDiskByNumberWithPowerShell(int diskNumber) async {
    late final ProcessResult result;
    try {
      result = await _runProcessWithTimeout(
        WindowsSystemEnvironment.powerShellExecutable,
        const [
          '-NoProfile',
          '-NonInteractive',
          '-ExecutionPolicy',
          'Bypass',
          '-Command',
          _getDiskByNumberScript,
        ],
        environment: WindowsSystemEnvironment.withSystemRoot({
          'WDS_DISK_NUMBER': '$diskNumber',
        }),
        timeout: const Duration(seconds: 10),
        timeoutMessage: 'Selected disk query timed out after 10 seconds.',
      );
    } on ProcessException catch (error) {
      throw StateError('Selected disk query could not start: $error');
    }

    if (result.exitCode != 0) {
      throw StateError('Selected disk query failed: ${result.stderr}');
    }
    final output = result.stdout.toString().trim();
    if (output.isEmpty) {
      throw StateError('Selected disk query returned no data');
    }
    final disks = _parseDisks(output);
    if (disks.length != 1) {
      throw StateError('Selected disk query returned an invalid result');
    }
    return disks.single;
  }

  static String _safetyDiagnosticToken(String detail) {
    final normalized = detail.toLowerCase();
    if (normalized.contains('timed out')) {
      return 'i18n:safety_detail_storage_timeout';
    }
    return 'i18n:safety_detail_storage_unavailable';
  }

  Future<ProcessResult> _runProcessWithTimeout(
    String executable,
    List<String> arguments, {
    required Map<String, String> environment,
    required Duration timeout,
    required String timeoutMessage,
  }) async {
    final process = await Process.start(
      executable,
      arguments,
      environment: environment,
    );
    final stdoutFuture = process.stdout
        .transform(const SystemEncoding().decoder)
        .join();
    final stderrFuture = process.stderr
        .transform(const SystemEncoding().decoder)
        .join();

    try {
      final exitCode = await process.exitCode.timeout(timeout);
      return ProcessResult(
        process.pid,
        exitCode,
        await _readProcessOutput(stdoutFuture),
        await _readProcessOutput(stderrFuture),
      );
    } on TimeoutException {
      await _terminateProcessTree(process);
      final stdout = await _readProcessOutput(stdoutFuture);
      final stderr = await _readProcessOutput(stderrFuture);
      final detail = stderr.trim();
      return ProcessResult(
        process.pid,
        -1,
        stdout,
        detail.isEmpty ? timeoutMessage : '$detail\n$timeoutMessage',
      );
    }
  }

  Future<String> _readProcessOutput(Future<String> output) async {
    try {
      return await output.timeout(_processOutputTimeout, onTimeout: () => '');
    } catch (_) {
      return '';
    }
  }

  Future<void> _terminateProcessTree(Process process) async {
    try {
      final killer = await Process.start(
        WindowsSystemEnvironment.taskkillExecutable,
        ['/F', '/T', '/PID', '${process.pid}'],
        environment: WindowsSystemEnvironment.withSystemRoot(),
      );
      final killerOutput = Future.wait<void>([
        killer.stdout.drain<void>(),
        killer.stderr.drain<void>(),
      ]);
      try {
        await killer.exitCode.timeout(
          _processCleanupTimeout,
          onTimeout: () {
            try {
              killer.kill(ProcessSignal.sigkill);
            } catch (_) {}
            return -1;
          },
        );
      } finally {
        try {
          await killerOutput.timeout(
            _processCleanupTimeout,
            onTimeout: () => <void>[],
          );
        } catch (_) {}
      }
    } catch (_) {
      // The direct kill below still handles a PowerShell process when taskkill
      // is unavailable or itself cannot finish within the cleanup window.
    }
    try {
      process.kill(ProcessSignal.sigkill);
    } catch (_) {}
    try {
      await process.exitCode.timeout(
        _processCleanupTimeout,
        onTimeout: () => -1,
      );
    } catch (_) {}
  }

  static const String _getAllDisksScript = r'''
$physicalByDevice = @{}
try {
  Get-PhysicalDisk -ErrorAction Stop | ForEach-Object {
    $physicalByDevice[$_.DeviceId.ToString()] = $_
  }
} catch {}

  Get-Disk | ForEach-Object {
    $disk = $_
    $partitions = @(Get-Partition -DiskNumber $disk.Number -ErrorAction SilentlyContinue)
    $letters = @($partitions | Where-Object { $_.DriveLetter } | ForEach-Object { $_.DriveLetter.ToString().ToUpperInvariant() })
    $partitionData = @($partitions | ForEach-Object {
      [PSCustomObject]@{
        Type        = if ($_.Type) { $_.Type.ToString() } else { '' }
        SizeBytes   = if ($_.Size) { [int64]$_.Size } else { 0 }
        DriveLetter = if ($_.DriveLetter) { $_.DriveLetter.ToString().ToUpperInvariant() } else { '' }
        IsSystem    = [bool]$_.IsSystem
        IsActive    = [bool]$_.IsActive
      }
    })
    $serial = if ($disk.SerialNumber) { $disk.SerialNumber.ToString() } else { '' }
    if (-not $serial -and $physicalByDevice.ContainsKey($disk.Number.ToString())) {
      $serial = $physicalByDevice[$disk.Number.ToString()].SerialNumber
    }
    [PSCustomObject]@{
      DiskNumber    = $disk.Number
      Model         = $disk.FriendlyName
      FriendlyName  = $disk.FriendlyName
      SizeBytes     = $disk.Size
      SerialNumber  = $serial
      UniqueId      = if ($disk.UniqueId) { $disk.UniqueId.ToString() } else { '' }
      DevicePath    = if ($disk.Path) { $disk.Path.ToString() } else { '' }
      BusType       = $disk.BusType.ToString()
      PartitionStyle = $disk.PartitionStyle.ToString()
      IsSystem      = $disk.IsSystem
      IsBoot        = $disk.IsBoot
      IsOffline     = $disk.IsOffline
      IsRemovable   = $disk.IsRemovable
      DriveLetters  = $letters
      Partitions    = $partitionData
    }
  } | ConvertTo-Json -Depth 5 -Compress
  ''';

  static const String _getDiskByNumberScript = r'''
$targetNumber = [int]$env:WDS_DISK_NUMBER
$disk = Get-Disk -Number $targetNumber -ErrorAction Stop
$serial = if ($disk.SerialNumber) { $disk.SerialNumber.ToString() } else { '' }
[PSCustomObject]@{
  DiskNumber     = $disk.Number
  Model          = $disk.FriendlyName
  FriendlyName   = $disk.FriendlyName
  SizeBytes      = $disk.Size
  SerialNumber   = $serial
  UniqueId       = if ($disk.UniqueId) { $disk.UniqueId.ToString() } else { '' }
  DevicePath     = if ($disk.Path) { $disk.Path.ToString() } else { '' }
  BusType        = $disk.BusType.ToString()
  PartitionStyle = $disk.PartitionStyle.ToString()
  IsSystem       = $disk.IsSystem
  IsBoot         = $disk.IsBoot
  IsOffline      = $disk.IsOffline
  IsRemovable    = $disk.IsRemovable
  # Partition enumeration is deliberately excluded from the safety refresh:
  # some USB bridges block partition enumeration even when Get-Disk is responsive.
  DriveLetters   = @()
  Partitions     = @()
} | ConvertTo-Json -Depth 5 -Compress
''';

  List<DiskInfo> _parseDisks(String json) {
    try {
      final decoded = jsonDecode(json);
      final items = decoded is List ? decoded : [decoded];
      final disks = <DiskInfo>[];
      for (final item in items) {
        if (item is Map) {
          disks.add(_parseDiskInfo(Map<String, dynamic>.from(item)));
        }
      }
      return disks;
    } catch (_) {}
    return [];
  }

  DiskInfo _parseDiskInfo(Map<String, dynamic> data) {
    final sizeBytes = _readInt(data['SizeBytes']);
    final partitions = _parsePartitions(data['Partitions']);
    final letters = _parseDriveLetters(data['DriveLetters']);
    final derivedLetters = partitions
        .map((p) => p.driveLetter)
        .whereType<String>()
        .where((letter) => letter.isNotEmpty)
        .toList();

    return DiskInfo(
      diskNumber: _readInt(data['DiskNumber']),
      model: data['Model']?.toString() ?? 'Unknown Disk',
      friendlyName: data['FriendlyName']?.toString() ?? 'Unknown Disk',
      sizeBytes: sizeBytes,
      sizeFormatted: _formatSize(sizeBytes),
      serialNumber: data['SerialNumber']?.toString() ?? 'N/A',
      uniqueId: data['UniqueId']?.toString() ?? '',
      devicePath: data['DevicePath']?.toString() ?? '',
      busType: data['BusType']?.toString() ?? 'Unknown',
      partitionStyle: data['PartitionStyle']?.toString() ?? 'Unknown',
      isSystem: _readBool(data['IsSystem']),
      isBoot: _readBool(data['IsBoot']),
      isOffline: _readBool(data['IsOffline']),
      isRemovable: _readBool(data['IsRemovable']),
      driveLetters: letters.isEmpty ? derivedLetters : letters,
      partitions: partitions,
    );
  }

  List<String> _parseDriveLetters(dynamic value) {
    final raw = value is List
        ? value.map((e) => e.toString())
        : (value?.toString() ?? '').split(',');
    final seen = <String>{};
    final letters = <String>[];
    for (final item in raw) {
      final letter = item.trim().replaceAll(RegExp(r'[:\\]'), '').toUpperCase();
      if (letter.length == 1 && seen.add(letter)) {
        letters.add(letter);
      }
    }
    return letters;
  }

  List<DiskPartition> _parsePartitions(dynamic value) {
    final items = value is List ? value : (value is Map ? [value] : const []);
    final partitions = <DiskPartition>[];
    for (final item in items) {
      if (item is! Map) continue;
      final data = Map<String, dynamic>.from(item);
      final driveLetter = data['DriveLetter']?.toString().trim();
      partitions.add(
        DiskPartition(
          type: data['Type']?.toString() ?? '',
          sizeBytes: _readInt(data['SizeBytes']),
          driveLetter: driveLetter == null || driveLetter.isEmpty
              ? null
              : driveLetter.replaceAll(':', '').toUpperCase(),
          isSystem: _readBool(data['IsSystem']),
          isActive: _readBool(data['IsActive']),
        ),
      );
    }
    return partitions;
  }

  int _readInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.round();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  bool _readBool(dynamic value) {
    if (value is bool) return value;
    final text = value?.toString().toLowerCase();
    return text == 'true' || text == '1';
  }

  bool? _readNullableBool(dynamic value) {
    if (value is bool) return value;
    final text = value?.toString().trim().toLowerCase();
    if (text == 'true' || text == '1') return true;
    if (text == 'false' || text == '0') return false;
    return null;
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(0)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(0)} GB';
  }
}
