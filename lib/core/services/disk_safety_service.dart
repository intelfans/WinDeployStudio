import 'dart:convert';
import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class DiskInfo {
  final int diskNumber;
  final String model;
  final String friendlyName;
  final int sizeBytes;
  final String sizeFormatted;
  final String serialNumber;
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

final diskSafetyServiceProvider = Provider<DiskSafetyService>((ref) {
  return DiskSafetyService();
});

class DiskSafetyService {
  Future<List<DiskInfo>> getAllDisks() async {
    try {
      final result = await Process.run('powershell', [
        '-NoProfile',
        '-ExecutionPolicy',
        'Bypass',
        '-Command',
        _getAllDisksScript,
      ]);

      if (result.exitCode != 0) return [];
      final output = result.stdout.toString().trim();
      if (output.isEmpty) return [];

      return _parseDisks(output);
    } catch (e) {
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
    if (disk.isSystem) {
      return const SafetyCheckResult(
        isSafe: false,
        reason: 'safety_system_disk',
      );
    }

    if (disk.isBoot) {
      return const SafetyCheckResult(isSafe: false, reason: 'safety_boot_disk');
    }

    final hasEfi = await _hasEfiPartition(disk.diskNumber);
    if (hasEfi) {
      return const SafetyCheckResult(
        isSafe: false,
        reason: 'safety_efi_partition',
      );
    }

    final hasRecovery = await _hasRecoveryPartition(disk.diskNumber);
    if (hasRecovery) {
      return const SafetyCheckResult(
        isSafe: false,
        reason: 'safety_recovery_partition',
      );
    }

    final windowsDrive = await _getWindowsDriveLetter();
    if (windowsDrive != null && disk.driveLetters.contains(windowsDrive)) {
      return SafetyCheckResult(
        isSafe: false,
        reason: 'safety_windows_install',
        params: {'drive': '$windowsDrive:\\'},
      );
    }

    return const SafetyCheckResult(isSafe: true);
  }

  Future<bool> _hasEfiPartition(int diskNumber) async {
    try {
      final result = await Process.run('powershell', [
        '-NoProfile',
        '-ExecutionPolicy',
        'Bypass',
        '-Command',
        'Get-Partition -DiskNumber $diskNumber | Where-Object { \$_.Type -eq "EFI" -or \$_.GptType -eq "{c12a7328-f81f-11d2-ba4b-00a0c93ec93b}" } | Measure-Object | Select-Object -ExpandProperty Count',
      ]).timeout(const Duration(seconds: 5));
      if (result.exitCode == 0) {
        final count = int.tryParse(result.stdout.toString().trim()) ?? 0;
        return count > 0;
      }
    } catch (_) {}
    return false;
  }

  Future<bool> _hasRecoveryPartition(int diskNumber) async {
    try {
      final result = await Process.run('powershell', [
        '-NoProfile',
        '-ExecutionPolicy',
        'Bypass',
        '-Command',
        'Get-Partition -DiskNumber $diskNumber | Where-Object { \$_.Type -eq "Recovery" -or \$_.GptType -eq "{de94bba4-06d1-4d40-a16a-bfd50179d6ac}" } | Measure-Object | Select-Object -ExpandProperty Count',
      ]).timeout(const Duration(seconds: 5));
      if (result.exitCode == 0) {
        final count = int.tryParse(result.stdout.toString().trim()) ?? 0;
        return count > 0;
      }
    } catch (_) {}
    return false;
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
