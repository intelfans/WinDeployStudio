import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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

  @override
  String toString() =>
      'Disk $diskNumber: $model ($sizeFormatted) S/N: $serialNumber';

  bool hasSamePhysicalIdentity(DiskInfo other) {
    if (sizeBytes <= 0 ||
        other.sizeBytes <= 0 ||
        sizeBytes != other.sizeBytes) {
      return false;
    }

    final thisSerial = _normalizedIdentityValue(serialNumber);
    final otherSerial = _normalizedIdentityValue(other.serialNumber);
    if (_isReliableIdentityValue(thisSerial)) {
      return _isReliableIdentityValue(otherSerial) &&
          thisSerial == otherSerial &&
          _hasMatchingModelAndBus(other);
    }

    final thisUniqueId = _normalizedIdentityValue(uniqueId);
    final otherUniqueId = _normalizedIdentityValue(other.uniqueId);
    if (_isReliableIdentityValue(thisUniqueId)) {
      return _isReliableIdentityValue(otherUniqueId) &&
          thisUniqueId == otherUniqueId &&
          _hasMatchingModelAndBus(other);
    }

    final thisPath = _normalizedIdentityValue(devicePath);
    final otherPath = _normalizedIdentityValue(other.devicePath);
    if (_isReliableDevicePath(thisPath)) {
      return _isReliableDevicePath(otherPath) &&
          thisPath == otherPath &&
          _hasMatchingModelAndBus(other);
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
    pointer.asTypedList(codeUnits.length + 1).setRange(
      0,
      codeUnits.length,
      codeUnits,
    );
    return pointer;
  }
}

typedef _CreateMutexWNative = Pointer<Void> Function(
  Pointer<Void> mutexAttributes,
  Int32 initialOwner,
  Pointer<Uint16> name,
);
typedef _CreateMutexWDart = Pointer<Void> Function(
  Pointer<Void> mutexAttributes,
  int initialOwner,
  Pointer<Uint16> name,
);
typedef _WaitForSingleObjectNative = Uint32 Function(
  Pointer<Void> handle,
  Uint32 milliseconds,
);
typedef _WaitForSingleObjectDart = int Function(
  Pointer<Void> handle,
  int milliseconds,
);
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

  Future<List<DiskInfo>> getAllDisks() async {
    try {
      return await _queryAllDisks();
    } catch (_) {
      return [];
    }
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

  Future<SafetyCheckResult> checkDiskSafety(DiskInfo disk) async {
    try {
      final disks = await _queryAllDisks();
      final current = disks.where((item) => item.diskNumber == disk.diskNumber);
      if (current.isEmpty) {
        return const SafetyCheckResult(
          isSafe: false,
          reason: 'safety_disk_missing',
        );
      }

      final currentDisk = current.single;
      if (!disk.hasSamePhysicalIdentity(currentDisk)) {
        return const SafetyCheckResult(
          isSafe: false,
          reason: 'safety_disk_changed',
        );
      }

      return await _checkCurrentDiskSafety(currentDisk);
    } catch (_) {
      return const SafetyCheckResult(
        isSafe: false,
        reason: 'safety_detection_failed',
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
      final acl = await Process.run(
        'powershell',
        const [
          '-NoProfile',
          '-NonInteractive',
          '-ExecutionPolicy',
          'Bypass',
          '-Command',
          _secureDirectoryAclScript,
        ],
        environment: {
          ...Platform.environment,
          'WDS_SECURE_PATH': secureDirectory.path,
        },
      ).timeout(const Duration(seconds: 30));
      if (acl.exitCode != 0) {
        return ProcessResult(0, -1, '', 'Secure script ACL setup failed.');
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
    final environment = <String, String>{
      ...Platform.environment,
      'WDS_DISK_NUMBER': '${disk.diskNumber}',
      'WDS_DISK_SIZE': '${disk.sizeBytes}',
      'WDS_DISK_MODEL': disk.model.trim().toUpperCase(),
      'WDS_DISK_BUS': disk.busType.trim().toUpperCase(),
      'WDS_DISK_UNIQUE_ID': disk.reliableUniqueId,
      'WDS_DISK_SERIAL': disk.reliableSerialNumber,
      'WDS_DISK_PATH': disk.reliableDevicePath,
      'WDS_DISKPART_SCRIPT': diskpartFile.path,
      'WDS_DISKPART_SHA256': scriptHash,
    };

    Process? process;
    try {
      process = await Process.start('powershell', const [
        '-NoProfile',
        '-ExecutionPolicy',
        'Bypass',
        '-Command',
        _guardedDiskpartScript,
      ], environment: environment);
      final stdoutFuture = process.stdout
          .transform(const SystemEncoding().decoder)
          .join();
      final stderrFuture = process.stderr
          .transform(const SystemEncoding().decoder)
          .join();
      final exitCode = await process.exitCode.timeout(timeout);
      return ProcessResult(
        process.pid,
        exitCode,
        await stdoutFuture,
        await stderrFuture,
      );
    } on TimeoutException {
      if (process != null) {
        await Process.run('taskkill', ['/F', '/T', '/PID', '${process.pid}']);
      }
      return ProcessResult(process?.pid ?? 0, -1, '', 'DiskPart timed out.');
    } catch (error) {
      return ProcessResult(process?.pid ?? 0, -1, '', error.toString());
    } finally {
      try {
        if (await diskpartFile.exists()) await diskpartFile.delete();
      } catch (_) {}
    }
  }

  Future<SafetyCheckResult> _checkCurrentDiskSafety(DiskInfo disk) async {
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

    final windowsDrive = await _getWindowsDriveLetter();
    if (windowsDrive == null) {
      return const SafetyCheckResult(
        isSafe: false,
        reason: 'safety_detection_failed',
      );
    }
    if (disk.driveLetters.contains(windowsDrive)) {
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

  Future<String?> _getWindowsDriveLetter() async {
    try {
      final result = await Process.run('powershell', [
        '-NoProfile',
        '-Command',
        r'$env:SystemDrive',
      ]).timeout(const Duration(seconds: 5));
      if (result.exitCode == 0) {
        return result.stdout.toString().trim().replaceAll(':', '');
      }
    } catch (_) {}
    return null;
  }

  Future<List<DiskInfo>> _queryAllDisks() async {
    final result = await Process.run('powershell', [
      '-NoProfile',
      '-ExecutionPolicy',
      'Bypass',
      '-Command',
      _getAllDisksScript,
    ]).timeout(const Duration(seconds: 10));

    if (result.exitCode != 0) {
      throw StateError('Disk enumeration failed: ${result.stderr}');
    }
    final output = result.stdout.toString().trim();
    if (output.isEmpty) throw StateError('Disk enumeration returned no data');
    final disks = _parseDisks(output);
    if (disks.isEmpty) throw StateError('Disk enumeration could not be parsed');
    return disks;
  }

  static const String _getAllDisksScript = r'''
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
    $serial = ''
    try {
      $phys = Get-PhysicalDisk | Where-Object { $_.DeviceId -eq $disk.Number.ToString() }
      if ($phys) { $serial = $phys.SerialNumber }
    } catch {}
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
      final letter = item.trim().replaceAll(':', '').toUpperCase();
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

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(0)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(0)} GB';
  }
}
