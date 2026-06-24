import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

enum WtgCompatibilityGrade {
  a,
  b,
  c,
  d,
  f,
  unknown,
}

class WtgCompatibilityResult {
  final WtgCompatibilityGrade grade;
  final String driveLetter;
  final String model;
  final String friendlyName;
  final int diskNumber;
  final int sizeBytes;
  final String sizeFormatted;
  final String busType;
  final String usbVersion;
  final int readSpeedMBps;
  final int writeSpeedMBps;
  final bool isRemovable;
  final bool isUsb;
  final bool speedTestSuccess;
  final String? speedTestError;
  final List<String> warnings;
  final List<String> recommendations;
  final List<String> debugLogs;

  const WtgCompatibilityResult({
    required this.grade,
    required this.driveLetter,
    required this.model,
    required this.friendlyName,
    required this.diskNumber,
    required this.sizeBytes,
    required this.sizeFormatted,
    required this.busType,
    required this.usbVersion,
    required this.readSpeedMBps,
    required this.writeSpeedMBps,
    required this.isRemovable,
    required this.isUsb,
    required this.speedTestSuccess,
    this.speedTestError,
    required this.warnings,
    required this.recommendations,
    required this.debugLogs,
  });

  String get gradeText {
    switch (grade) {
      case WtgCompatibilityGrade.a:
        return 'A';
      case WtgCompatibilityGrade.b:
        return 'B';
      case WtgCompatibilityGrade.c:
        return 'C';
      case WtgCompatibilityGrade.d:
        return 'D';
      case WtgCompatibilityGrade.f:
        return 'F';
      case WtgCompatibilityGrade.unknown:
        return 'N/A';
    }
  }

  String get gradeDescription {
    switch (grade) {
      case WtgCompatibilityGrade.a:
        return 'wtg_grade_a';
      case WtgCompatibilityGrade.b:
        return 'wtg_grade_b';
      case WtgCompatibilityGrade.c:
        return 'wtg_grade_c';
      case WtgCompatibilityGrade.d:
        return 'wtg_grade_d';
      case WtgCompatibilityGrade.f:
        return 'wtg_grade_f';
      case WtgCompatibilityGrade.unknown:
        return 'wtg_grade_unknown';
    }
  }

  bool get isRecommended => grade == WtgCompatibilityGrade.a || 
                            grade == WtgCompatibilityGrade.b;
}

final wtgCompatibilityServiceProvider = Provider<WtgCompatibilityService>((ref) {
  return WtgCompatibilityService();
});

class WtgCompatibilityService {
  final List<String> _debugLogs = [];
  
  List<String> get debugLogs => List.unmodifiable(_debugLogs);
  
  void _addDebug(String message) {
    final line = '[${DateTime.now().toIso8601String()}] $message';
    _debugLogs.add(line);
    debugPrint('[WTG-COMPAT] $message');
  }

  Future<WtgCompatibilityResult> checkCompatibility({
    required int diskNumber,
    required String driveLetter,
  }) async {
    _debugLogs.clear();
    _addDebug('=== WTG Compatibility Check ===');
    _addDebug('Disk Number: $diskNumber');
    _addDebug('Drive Letter: $driveLetter');

    String model = 'Unknown';
    String friendlyName = 'Unknown';
    int sizeBytes = 0;
    String sizeFormatted = '0 GB';
    String busType = 'Unknown';
    String usbVersion = 'Unknown';
    bool isRemovable = false;
    bool isUsb = false;
    int readSpeedMBps = 0;
    int writeSpeedMBps = 0;
    bool speedTestSuccess = false;
    String? speedTestError;
    final warnings = <String>[];
    final recommendations = <String>[];

    // Get disk info using PowerShell
    try {
      final diskInfo = await _getDiskInfo(diskNumber);
      _addDebug('Disk Info Response:');
      diskInfo.forEach((key, value) {
        _addDebug('  $key: $value');
      });
      
      model = diskInfo['Model']?.toString() ?? 'Unknown';
      friendlyName = diskInfo['FriendlyName']?.toString() ?? 'Unknown';
      sizeBytes = diskInfo['SizeBytes'] is int ? diskInfo['SizeBytes'] : 0;
      sizeFormatted = _formatSize(sizeBytes);
      busType = diskInfo['BusType']?.toString() ?? 'Unknown';
      isRemovable = diskInfo['IsRemovable'] == true;
      
      // Improved USB detection
      final busTypeUpper = busType.toUpperCase();
      isUsb = busTypeUpper == 'USB' || 
              (busTypeUpper == 'SCSI' && isRemovable) ||
              (busTypeUpper == 'UNKNOWN' && isRemovable);
      
      _addDebug('Calculated Values:');
      _addDebug('  sizeFormatted: $sizeFormatted');
      _addDebug('  sizeBytes: $sizeBytes');
      _addDebug('  sizeGB: ${(sizeBytes / (1024 * 1024 * 1024)).toStringAsFixed(2)}');
      _addDebug('  busType: $busType');
      _addDebug('  isRemovable: $isRemovable');
      _addDebug('  isUsb (calculated): $isUsb');
      
    } catch (e) {
      _addDebug('Error getting disk info: $e');
      warnings.add('wtg_warn_disk_info_failed');
    }

    // Get USB version
    usbVersion = _detectUsbVersion(busType);
    _addDebug('USB Version: $usbVersion');

    // Check size requirements
    final sizeGB = sizeBytes / (1024 * 1024 * 1024);
    _addDebug('Size check: ${sizeGB.toStringAsFixed(2)} GB');
    
    if (sizeGB < 32) {
      warnings.add('wtg_warn_size_small');
    }

    // Check if it's a USB drive
    if (!isUsb) {
      warnings.add('wtg_warn_not_usb');
    }

    // Run speed test
    _addDebug('');
    _addDebug('Start Speed Test...');
    
    if (driveLetter.isNotEmpty) {
      // Normalize drive letter format
      String driveRoot;
      if (driveLetter.length == 1) {
        driveRoot = '$driveLetter:\\';
      } else if (driveLetter.length == 2 && driveLetter.endsWith(':')) {
        driveRoot = '$driveLetter\\';
      } else if (driveLetter.endsWith('\\')) {
        driveRoot = driveLetter;
      } else {
        driveRoot = '$driveLetter\\';
      }
      
      _addDebug('Drive Letter Raw: $driveLetter');
      _addDebug('Drive Root: $driveRoot');
      
      // Check if drive exists
      final driveDir = Directory(driveRoot);
      final driveExists = driveDir.existsSync();
      _addDebug('Drive Exists: $driveExists');
      
      if (!driveExists) {
        _addDebug('ERROR: Drive root not found');
        speedTestSuccess = false;
        speedTestError = 'wtg_err_drive_not_found';
      } else {
        try {
          final speedResult = await _runSpeedTest(driveRoot);
          readSpeedMBps = speedResult['read'] ?? 0;
          writeSpeedMBps = speedResult['write'] ?? 0;
          speedTestSuccess = speedResult['success'] == true;
          speedTestError = speedResult['error']?.toString();
          
          _addDebug('');
          _addDebug('Speed Test Result:');
          _addDebug('  Success: $speedTestSuccess');
          _addDebug('  Read Speed: ${readSpeedMBps} MB/s');
          _addDebug('  Write Speed: ${writeSpeedMBps} MB/s');
          if (speedTestError != null) {
            _addDebug('  Error: $speedTestError');
          }
        } catch (e) {
          _addDebug('Speed test exception: $e');
          speedTestSuccess = false;
          speedTestError = e.toString();
        }
      }
    } else {
      _addDebug('Skipping speed test - empty drive letter');
      speedTestError = 'wtg_err_empty_drive_letter';
    }
    
    _addDebug('Speed Test Completed.');

    // Calculate grade
    final grade = _calculateGrade(
      sizeBytes: sizeBytes,
      readSpeedMBps: readSpeedMBps,
      writeSpeedMBps: writeSpeedMBps,
      speedTestSuccess: speedTestSuccess,
    );
    _addDebug('');
    _addDebug('Final grade: ${grade.name}');

    // Add warnings based on speed test
    if (speedTestSuccess) {
      // Microsoft WTG requires ~80MB/s sequential read/write
      if (readSpeedMBps < 80 || writeSpeedMBps < 80) {
        warnings.add('wtg_warn_performance_low');
      }
    } else {
      warnings.add('wtg_warn_speed_test_failed');
      recommendations.add('wtg_rec_retry_speed_test');
    }

    return WtgCompatibilityResult(
      grade: grade,
      driveLetter: driveLetter,
      model: model,
      friendlyName: friendlyName,
      diskNumber: diskNumber,
      sizeBytes: sizeBytes,
      sizeFormatted: sizeFormatted,
      busType: busType,
      usbVersion: usbVersion,
      readSpeedMBps: readSpeedMBps,
      writeSpeedMBps: writeSpeedMBps,
      isRemovable: isRemovable,
      isUsb: isUsb,
      speedTestSuccess: speedTestSuccess,
      speedTestError: speedTestError,
      warnings: warnings,
      recommendations: recommendations,
      debugLogs: List.from(_debugLogs),
    );
  }

  WtgCompatibilityGrade _calculateGrade({
    required int sizeBytes,
    required int readSpeedMBps,
    required int writeSpeedMBps,
    required bool speedTestSuccess,
  }) {
    // If speed test failed, return unknown
    if (!speedTestSuccess) {
      _addDebug('Grade: Unknown (speed test failed)');
      return WtgCompatibilityGrade.unknown;
    }

    int score = 0;
    final scoreDetails = <String>[];

    // Size scoring
    final sizeGB = sizeBytes / (1024 * 1024 * 1024);
    if (sizeGB >= 256) {
      score += 40;
      scoreDetails.add('Size ${sizeGB.toStringAsFixed(0)}GB: +40');
    } else if (sizeGB >= 128) {
      score += 30;
      scoreDetails.add('Size ${sizeGB.toStringAsFixed(0)}GB: +30');
    } else if (sizeGB >= 64) {
      score += 20;
      scoreDetails.add('Size ${sizeGB.toStringAsFixed(0)}GB: +20');
    } else {
      score += 0;
      scoreDetails.add('Size ${sizeGB.toStringAsFixed(0)}GB: +0');
    }

    // Read speed scoring
    if (readSpeedMBps >= 300) {
      score += 30;
      scoreDetails.add('Read $readSpeedMBps MB/s: +30');
    } else if (readSpeedMBps >= 150) {
      score += 20;
      scoreDetails.add('Read $readSpeedMBps MB/s: +20');
    } else if (readSpeedMBps >= 80) {
      score += 10;
      scoreDetails.add('Read $readSpeedMBps MB/s: +10');
    } else {
      score += 0;
      scoreDetails.add('Read $readSpeedMBps MB/s: +0');
    }

    // Write speed scoring
    if (writeSpeedMBps >= 300) {
      score += 30;
      scoreDetails.add('Write $writeSpeedMBps MB/s: +30');
    } else if (writeSpeedMBps >= 150) {
      score += 20;
      scoreDetails.add('Write $writeSpeedMBps MB/s: +20');
    } else if (writeSpeedMBps >= 80) {
      score += 10;
      scoreDetails.add('Write $writeSpeedMBps MB/s: +10');
    } else {
      score += 0;
      scoreDetails.add('Write $writeSpeedMBps MB/s: +0');
    }

    _addDebug('Score calculation:');
    for (final detail in scoreDetails) {
      _addDebug('  $detail');
    }
    _addDebug('Total score: $score');

    // Convert score to grade
    if (score >= 90) {
      return WtgCompatibilityGrade.a;
    } else if (score >= 75) {
      return WtgCompatibilityGrade.b;
    } else if (score >= 60) {
      return WtgCompatibilityGrade.c;
    } else if (score >= 40) {
      return WtgCompatibilityGrade.d;
    } else {
      return WtgCompatibilityGrade.f;
    }
  }

  String _detectUsbVersion(String busType) {
    if (busType.toUpperCase().contains('USB')) {
      if (busType.contains('3.2')) {
        return 'USB 3.2';
      } else if (busType.contains('3.1')) {
        return 'USB 3.1';
      } else if (busType.contains('3.0')) {
        return 'USB 3.0';
      } else if (busType.contains('2.0')) {
        return 'USB 2.0';
      }
      return 'USB 3.0'; // Default assumption for USB devices
    }
    return 'N/A';
  }

  Future<Map<String, dynamic>> _getDiskInfo(int diskNumber) async {
    try {
      final result = await Process.run('powershell', [
        '-NoProfile',
        '-ExecutionPolicy', 'Bypass',
        '-Command',
        '''
        \$disk = Get-Disk -Number $diskNumber -ErrorAction Stop
        \$result = [PSCustomObject]@{
          DiskNumber = \$disk.Number
          Model = \$disk.Model
          FriendlyName = \$disk.FriendlyName
          SizeBytes = \$disk.Size
          BusType = \$disk.BusType.ToString()
          IsRemovable = \$disk.IsRemovable
          IsSystem = \$disk.IsSystem
          IsBoot = \$disk.IsBoot
        }
        \$result | ConvertTo-Json -Compress
        ''',
      ]).timeout(const Duration(seconds: 10));

      _addDebug('PowerShell Get-Disk exit code: ${result.exitCode}');
      
      if (result.exitCode == 0) {
        final output = result.stdout.toString().trim();
        if (output.isNotEmpty) {
          return _parseJson(output);
        }
      } else {
        _addDebug('PowerShell stderr: ${result.stderr}');
      }
    } catch (e) {
      _addDebug('Error getting disk info: $e');
    }
    return {};
  }

  Future<Map<String, dynamic>> _runSpeedTest(String driveRoot) async {
    final testFile = '${driveRoot}WinDeployStudio_Test.bin';
    final testSize = 512 * 1024 * 1024; // 512MB
    final chunkSize = 1024 * 1024; // 1MB chunks
    
    _addDebug('Test File Path: $testFile');
    _addDebug('Test File Size: ${testSize ~/ (1024 * 1024)} MB');
    
    try {
      final file = File(testFile);
      
      // Delete existing test file if any
      if (await file.exists()) {
        _addDebug('Deleting existing test file...');
        await file.delete();
      }
      
      // Prepare test data (1MB chunk)
      final testData = List<int>.filled(chunkSize, 0);
      
      // Write speed test - sequential write 512MB
      _addDebug('');
      _addDebug('Write Test Start: ${DateTime.now().toIso8601String()}');
      final writeStopwatch = Stopwatch()..start();
      
      final sink = file.openWrite();
      for (int i = 0; i < testSize ~/ chunkSize; i++) {
        sink.add(testData);
      }
      await sink.flush();
      await sink.close();
      
      writeStopwatch.stop();
      final writeDuration = writeStopwatch.elapsedMilliseconds;
      _addDebug('Write Test End: ${DateTime.now().toIso8601String()}');
      _addDebug('Write Duration: ${writeDuration}ms');
      
      final writeSpeed = writeDuration > 0 
          ? ((testSize / (1024 * 1024)) * 1000 / writeDuration).round()
          : 0;
      _addDebug('Write Speed: ${writeSpeed} MB/s');
      
      // Read speed test - sequential read 512MB
      _addDebug('');
      _addDebug('Read Test Start: ${DateTime.now().toIso8601String()}');
      final readStopwatch = Stopwatch()..start();
      
      await file.readAsBytes();
      
      readStopwatch.stop();
      final readDuration = readStopwatch.elapsedMilliseconds;
      _addDebug('Read Test End: ${DateTime.now().toIso8601String()}');
      _addDebug('Read Duration: ${readDuration}ms');
      
      final readSpeed = readDuration > 0
          ? ((testSize / (1024 * 1024)) * 1000 / readDuration).round()
          : 0;
      _addDebug('Read Speed: ${readSpeed} MB/s');
      
      // Cleanup
      _addDebug('');
      _addDebug('Cleaning up test file...');
      await file.delete();
      
      _addDebug('Speed Test Completed Successfully.');
      
      return {
        'success': true,
        'read': readSpeed,
        'write': writeSpeed,
      };
    } catch (e) {
      _addDebug('');
      _addDebug('Exception: $e');
      _addDebug('Speed Test Failed.');
      
      // Try to cleanup on error
      try {
        final file = File(testFile);
        if (await file.exists()) {
          await file.delete();
        }
      } catch (_) {}
      
      return {
        'success': false,
        'read': 0,
        'write': 0,
        'error': e.toString(),
      };
    }
  }

  String _formatSize(int bytes) {
    if (bytes <= 0) return '0 B';
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(0)} MB';
    }
    final gb = bytes / (1024 * 1024 * 1024);
    return '${gb.toStringAsFixed(1)} GB';
  }

  Map<String, dynamic> _parseJson(String json) {
    final map = <String, dynamic>{};
    try {
      final content = json.substring(1, json.length - 1).trim();
      if (content.isEmpty) return map;
      int i = 0;
      while (i < content.length) {
        while (i < content.length && content[i] == ' ') { i++; }
        if (i >= content.length || content[i] != '"') break;
        i++;
        final keyStart = i;
        while (i < content.length && content[i] != '"') { i++; }
        final key = content.substring(keyStart, i);
        i++;
        while (i < content.length && (content[i] == ':' || content[i] == ' ')) { i++; }
        if (i >= content.length) break;
        dynamic value;
        if (content[i] == '"') {
          i++;
          final valueStart = i;
          while (i < content.length && content[i] != '"') { i++; }
          value = content.substring(valueStart, i);
          i++;
        } else if (content[i] == 't') {
          value = true; i += 4;
        } else if (content[i] == 'f') {
          value = false; i += 5;
        } else if (content[i] == 'n') {
          value = null; i += 4;
        } else {
          final numStart = i;
          while (i < content.length && content[i] != ',' && content[i] != '}') { i++; }
          final numStr = content.substring(numStart, i).trim();
          value = int.tryParse(numStr) ?? double.tryParse(numStr);
        }
        map[key] = value;
        while (i < content.length && (content[i] == ',' || content[i] == ' ')) { i++; }
      }
    } catch (e) {
      _addDebug('JSON parse error: $e');
    }
    return map;
  }
}
