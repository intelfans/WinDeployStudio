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
    $partitions = Get-Partition -DiskNumber $disk.Number -ErrorAction SilentlyContinue
    $letters = $partitions | Where-Object { $_.DriveLetter } | ForEach-Object { $_.DriveLetter.ToString() }
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
      DriveLetters  = ($letters -join ',')
    }
  } | ConvertTo-Json -Compress
  ''';

  List<DiskInfo> _parseDisks(String json) {
    try {
      if (json.startsWith('[')) {
        final items = _parseJsonArray(json);
        return items
            .map((e) => _parseDiskInfo(e as Map<String, dynamic>))
            .toList();
      } else if (json.startsWith('{')) {
        return [_parseDiskInfo(_parseJsonObject(json))];
      }
    } catch (_) {}
    return [];
  }

  DiskInfo _parseDiskInfo(Map<String, dynamic> data) {
    final sizeBytes = data['SizeBytes'] as int? ?? 0;
    final lettersStr = data['DriveLetters']?.toString() ?? '';
    final letters = lettersStr.isEmpty
        ? <String>[]
        : lettersStr.split(',').map((e) => e.trim()).toList();

    return DiskInfo(
      diskNumber: data['DiskNumber'] as int? ?? 0,
      model: data['Model']?.toString() ?? 'Unknown Disk',
      friendlyName: data['FriendlyName']?.toString() ?? 'Unknown Disk',
      sizeBytes: sizeBytes,
      sizeFormatted: _formatSize(sizeBytes),
      serialNumber: data['SerialNumber']?.toString() ?? 'N/A',
      busType: data['BusType']?.toString() ?? 'Unknown',
      partitionStyle: data['PartitionStyle']?.toString() ?? 'Unknown',
      isSystem: data['IsSystem'] as bool? ?? false,
      isBoot: data['IsBoot'] as bool? ?? false,
      isOffline: data['IsOffline'] as bool? ?? false,
      isRemovable: data['IsRemovable'] as bool? ?? false,
      driveLetters: letters,
    );
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(0)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(0)} GB';
  }

  List<dynamic> _parseJsonArray(String json) {
    final content = json.substring(1, json.length - 1).trim();
    if (content.isEmpty) return [];
    final items = <dynamic>[];
    int depth = 0;
    int start = 0;
    for (int i = 0; i < content.length; i++) {
      if (content[i] == '{') depth++;
      if (content[i] == '}') depth--;
      if (content[i] == ',' && depth == 0) {
        items.add(_parseJsonObject(content.substring(start, i).trim()));
        start = i + 1;
      }
    }
    items.add(_parseJsonObject(content.substring(start).trim()));
    return items;
  }

  Map<String, dynamic> _parseJsonObject(String json) {
    final map = <String, dynamic>{};
    final content = json.substring(1, json.length - 1).trim();
    if (content.isEmpty) return map;
    int i = 0;
    while (i < content.length) {
      while (i < content.length && content[i] == ' ') {
        i++;
      }
      if (i >= content.length || content[i] != '"') break;
      i++;
      final keyStart = i;
      while (i < content.length && content[i] != '"') {
        i++;
      }
      final key = content.substring(keyStart, i);
      i++;
      while (i < content.length && (content[i] == ':' || content[i] == ' ')) {
        i++;
      }
      if (i >= content.length) break;
      dynamic value;
      if (content[i] == '"') {
        i++;
        final valueStart = i;
        while (i < content.length && content[i] != '"') {
          i++;
        }
        value = content.substring(valueStart, i);
        i++;
      } else if (content[i] == 't') {
        value = true;
        i += 4;
      } else if (content[i] == 'f') {
        value = false;
        i += 5;
      } else if (content[i] == 'n') {
        value = null;
        i += 4;
      } else {
        final numStart = i;
        while (i < content.length && content[i] != ',' && content[i] != '}') {
          i++;
        }
        value =
            int.tryParse(content.substring(numStart, i).trim()) ??
            double.tryParse(content.substring(numStart, i).trim());
      }
      map[key] = value;
      while (i < content.length && (content[i] == ',' || content[i] == ' ')) {
        i++;
      }
    }
    return map;
  }
}
