import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'file_logger_service.dart';
import '../../features/logs/services/log_center_service.dart';

enum WtgStep {
  preparing,
  partitioningDisk,
  mountingIso,
  applyingImage,
  writingBootFiles,
  verifying,
  complete,
  failed,
}

enum WtgBootLayout { gptUefi, mbrHybrid }

class _WtgDriveLetters {
  final String efiLetter;
  final String windowsLetter;

  const _WtgDriveLetters({
    required this.efiLetter,
    required this.windowsLetter,
  });
}

class _WtgPartitionLayout {
  final WtgBootLayout bootLayout;
  final String efiDrive;
  final String windowsDrive;

  const _WtgPartitionLayout({
    required this.bootLayout,
    required this.efiDrive,
    required this.windowsDrive,
  });
}

class WtgProgress {
  final WtgStep step;
  final double progress;
  final String message;
  final String? error;
  final String? currentFile;
  final int writtenBytes;
  final int totalBytes;
  final int currentSpeedBytes;
  final Duration? elapsedTime;

  const WtgProgress({
    required this.step,
    this.progress = 0.0,
    this.message = '',
    this.error,
    this.currentFile,
    this.writtenBytes = 0,
    this.totalBytes = 0,
    this.currentSpeedBytes = 0,
    this.elapsedTime,
  });

  int get remainingBytes =>
      totalBytes > writtenBytes ? totalBytes - writtenBytes : 0;

  String get formattedWritten {
    if (writtenBytes <= 0) {
      return '0 B';
    }
    if (writtenBytes < 1024 * 1024) {
      return '${(writtenBytes / 1024).toStringAsFixed(1)} KB';
    }
    if (writtenBytes < 1024 * 1024 * 1024) {
      return '${(writtenBytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(writtenBytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }

  String get formattedTotal {
    if (totalBytes <= 0) {
      return '--';
    }
    if (totalBytes < 1024 * 1024) {
      return '${(totalBytes / 1024).toStringAsFixed(1)} KB';
    }
    if (totalBytes < 1024 * 1024 * 1024) {
      return '${(totalBytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(totalBytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }

  String get formattedRemaining {
    final rem = remainingBytes;
    if (rem <= 0) {
      return '0 B';
    }
    if (rem < 1024 * 1024) {
      return '${(rem / 1024).toStringAsFixed(1)} KB';
    }
    if (rem < 1024 * 1024 * 1024) {
      return '${(rem / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(rem / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }

  String get formattedSpeed {
    if (currentSpeedBytes <= 0) {
      return '--';
    }
    if (currentSpeedBytes < 1024 * 1024) {
      return '${(currentSpeedBytes / 1024).toStringAsFixed(1)} KB/s';
    }
    if (currentSpeedBytes < 1024 * 1024 * 1024) {
      return '${(currentSpeedBytes / (1024 * 1024)).toStringAsFixed(1)} MB/s';
    }
    return '${(currentSpeedBytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB/s';
  }

  String get formattedElapsed {
    if (elapsedTime == null) {
      return '00:00:00';
    }
    final h = elapsedTime!.inHours.toString().padLeft(2, '0');
    final m = (elapsedTime!.inMinutes % 60).toString().padLeft(2, '0');
    final s = (elapsedTime!.inSeconds % 60).toString().padLeft(2, '0');
    return '$h:$m:$s';
  }
}

typedef WtgProgressCallback = void Function(WtgProgress progress);

final wtgServiceProvider = Provider<WtgService>((ref) {
  return WtgService(ref);
});

class WtgService {
  final Ref ref;
  final List<String> _log = [];
  bool _cancelled = false;
  Process? _currentProcess;
  String? _currentIsoPath;

  WtgService(this.ref) {
    // Kill process and eject ISO when provider is disposed (app exit)
    ref.onDispose(() {
      _killCurrentProcess();
      // Eject ISO synchronously
      if (_currentIsoPath != null) {
        try {
          final escapedPath = _currentIsoPath!.replaceAll("'", "''");
          Process.run('powershell', [
            '-NoProfile',
            '-ExecutionPolicy',
            'Bypass',
            '-Command',
            "Dismount-DiskImage -ImagePath '$escapedPath' -ErrorAction SilentlyContinue",
          ]);
        } catch (_) {}
      }
    });
  }

  void _logLine(String msg) {
    final line = '[${DateTime.now().toIso8601String()}] $msg';
    _log.add(line);
    debugPrint(line);

    // 实时写入文件 - 同步执行确保日志不丢失
    _writeLogToFileSync(line);
  }

  void _writeLogToFileSync(String line) {
    try {
      final dir = Directory(
        'C:\\Users\\${Platform.environment['USERNAME']}\\AppData\\Roaming\\WinDeployStudio\\logs',
      );
      if (!dir.existsSync()) {
        dir.createSync(recursive: true);
      }
      final logFile = File('${dir.path}\\wtg_detail.log');
      logFile.writeAsStringSync('$line\n', mode: FileMode.append);
    } catch (e) {
      debugPrint('Log write error: $e');
    }
  }

  String get logText => _log.join('\n');

  String _driveRoot(String drive) {
    final value = drive.trim();
    if (value.endsWith('\\')) return value;
    if (value.endsWith(':')) return '$value\\';
    if (value.length == 1) return '$value:\\';
    return value;
  }

  String _driveSpec(String drive) {
    final value = drive.trim().replaceAll('\\', '');
    if (value.endsWith(':')) return value;
    if (value.length == 1) return '$value:';
    return value;
  }

  String _drivePath(String drive, String relativePath) {
    final cleanRelative = relativePath.replaceFirst(RegExp(r'^\\+'), '');
    return '${_driveRoot(drive)}$cleanRelative';
  }

  String _driveFromLetter(String letter) {
    return '${letter.toUpperCase()}:\\';
  }

  void _killCurrentProcess() {
    if (_currentProcess == null) return;
    try {
      // Kill the process tree (including child processes like DISM)
      Process.run('taskkill', ['/F', '/T', '/PID', '${_currentProcess!.pid}']);
      _currentProcess?.kill(ProcessSignal.sigkill);
      _currentProcess = null;
      debugPrint('[WTG] Killed DISM process tree');
    } catch (e) {
      debugPrint('[WTG] Failed to kill process: $e');
    }
  }

  Future<void> _ejectIso(String isoPath) async {
    try {
      _logLine('Ejecting ISO: $isoPath');
      final escapedPath = isoPath.replaceAll("'", "''");
      await Process.run('powershell', [
        '-NoProfile',
        '-ExecutionPolicy',
        'Bypass',
        '-Command',
        "Dismount-DiskImage -ImagePath '$escapedPath' -ErrorAction SilentlyContinue",
      ]).timeout(const Duration(seconds: 15));
      _logLine('ISO ejected OK');
    } catch (e) {
      _logLine('ISO eject error (non-fatal): $e');
    }
  }

  void cancel() {
    _cancelled = true;
    _logLine('=== WTG Creation Cancelled ===');
    _killCurrentProcess();
    if (_currentIsoPath != null) {
      _ejectIso(_currentIsoPath!);
    }
    _logLine('Killed DISM process and ejected ISO');
  }

  Future<String> saveLogToFile() async {
    try {
      final dir = await getApplicationSupportDirectory();
      final logFile = File(
        p.join(dir.path, 'logs', 'last_wtg_creation_log.txt'),
      );
      await logFile.parent.create(recursive: true);
      await logFile.writeAsString(logText);
      return logFile.path;
    } catch (e) {
      return 'Failed to save log: $e';
    }
  }

  void _notify(WtgProgressCallback? callback, WtgProgress progress) {
    if (!_cancelled) {
      callback?.call(progress);
    }
  }

  Future<List<Map<String, dynamic>>> getWimImages(String isoPath) async {
    _logLine('Getting WIM images from: $isoPath');
    _debugLogs.clear();
    _addDebug('ISO Path: $isoPath');

    // Mount ISO
    _addDebug('Mounting ISO...');
    final mountPoint = await _mountIso(isoPath);
    if (mountPoint == null) {
      _addDebug('ERROR: Failed to mount ISO');
      _logLine('Failed to mount ISO');
      return [];
    }
    _addDebug('Mounted Drive: $mountPoint');
    _logLine('ISO mounted at: $mountPoint');

    try {
      // Check sources directory
      final sourcesDir = '${mountPoint}sources';
      _addDebug('Checking directory: $sourcesDir');

      final sourcesDirEntity = Directory(sourcesDir);
      if (!await sourcesDirEntity.exists()) {
        _addDebug('ERROR: sources directory does not exist');
        _logLine('Sources directory does not exist');
        return [];
      }
      _addDebug('sources directory exists: YES');

      // List all files in sources directory
      _addDebug('Files in $sourcesDir:');
      try {
        final files = await sourcesDirEntity.list().toList();
        for (final file in files) {
          final name = file.path.split('\\').last;
          _addDebug('  - $name');
        }
      } catch (e) {
        _addDebug('Error listing directory: $e');
      }

      // Find install.wim or install.esd
      final wimPath = '${mountPoint}sources\\install.wim';
      final esdPath = '${mountPoint}sources\\install.esd';

      final hasWim = await File(wimPath).exists();
      final hasEsd = await File(esdPath).exists();

      _addDebug('Found install.wim = $hasWim');
      _addDebug('Found install.esd = $hasEsd');

      String? sourcePath;
      if (hasWim) {
        sourcePath = wimPath;
        _addDebug('Using install.wim');
      } else if (hasEsd) {
        sourcePath = esdPath;
        _addDebug('Using install.esd');
      }

      if (sourcePath == null) {
        _addDebug('ERROR: No install.wim or install.esd found');
        _logLine('No install.wim or install.esd found');
        return [];
      }

      // Get image info using DISM
      _addDebug('Running DISM /Get-ImageInfo...');
      _logLine('Running DISM on: $sourcePath');
      final result = await Process.run('dism', [
        '/Get-ImageInfo',
        '/ImageFile:$sourcePath',
      ]).timeout(const Duration(seconds: 60));

      _addDebug('DISM exit code: ${result.exitCode}');
      _logLine('DISM exit code: ${result.exitCode}');

      if (result.exitCode != 0) {
        final stderr = result.stderr.toString();
        final stdout = result.stdout.toString();
        _addDebug('DISM stderr: $stderr');
        _addDebug('DISM stdout: $stdout');
        _logLine('DISM stderr: $stderr');
        _logLine('DISM stdout: $stdout');
        return [];
      }

      final output = result.stdout.toString();
      _addDebug('DISM output length: ${output.length} characters');
      _logLine('DISM output length: ${output.length} characters');

      if (output.isEmpty) {
        _addDebug('ERROR: DISM output is empty');
        _logLine('DISM output is empty');
        return [];
      }

      // Show first 500 chars of output for debugging
      final preview = output.length > 500 ? output.substring(0, 500) : output;
      _addDebug('DISM output preview:\n$preview');

      final images = _parseDismImageInfo(output);
      _addDebug('Parsed ${images.length} images');

      return images;
    } catch (e) {
      _addDebug('EXCEPTION: $e');
      _logLine('Error getting WIM images: $e');
      return [];
    } finally {
      await _unmountIso(isoPath);
    }
  }

  final List<String> _debugLogs = [];

  List<String> get debugLogs => List.unmodifiable(_debugLogs);

  void _addDebug(String message) {
    _debugLogs.add(message);
    debugPrint('[WTG-DEBUG] $message');
  }

  List<Map<String, dynamic>> _parseDismImageInfo(String output) {
    final images = <Map<String, dynamic>>[];
    final lines = output.split('\n');
    _addDebug('Total lines in DISM output: ${lines.length}');

    // Regular expressions for matching DISM fields
    // Support both English and Chinese, with flexible spacing around colon
    final indexRegex = RegExp(r'^(Index|索引)\s*:\s*(\d+)$');
    final nameRegex = RegExp(r'^(Name|名称)\s*:\s*(.+)$');
    final descRegex = RegExp(r'^(Description|描述|说明)\s*:\s*(.+)$');
    final sizeRegex = RegExp(r'^(Size|大小)\s*:\s*(.+)$');
    final archRegex = RegExp(r'^(Architecture|体系结构)\s*:\s*(.+)$');
    final editionRegex = RegExp(r'^(Edition|版本)\s*:\s*(.+)$');
    final versionRegex = RegExp(r'^(Version|版本号)\s*:\s*(.+)$');
    final installTypeRegex = RegExp(r'^(Installation Type|安装类型)\s*:\s*(.+)$');

    Map<String, dynamic>? currentImage;
    int matchedLines = 0;

    for (int i = 0; i < lines.length; i++) {
      final trimmed = lines[i].trim();
      if (trimmed.isEmpty) continue;

      // Try to match index (start of new image)
      var match = indexRegex.firstMatch(trimmed);
      if (match != null) {
        // Save previous image if exists
        if (currentImage != null) {
          images.add(currentImage);
        }
        currentImage = {'index': int.tryParse(match.group(2)!) ?? 0};
        matchedLines++;
        _addDebug('Line $i: Found index ${currentImage['index']}');
        continue;
      }

      // If we have a current image, try to match other fields
      if (currentImage != null) {
        match = nameRegex.firstMatch(trimmed);
        if (match != null) {
          currentImage['name'] = match.group(2)!.trim();
          matchedLines++;
          _addDebug('Line $i: Found name "${currentImage['name']}"');
          continue;
        }

        match = descRegex.firstMatch(trimmed);
        if (match != null) {
          currentImage['description'] = match.group(2)!.trim();
          matchedLines++;
          continue;
        }

        match = sizeRegex.firstMatch(trimmed);
        if (match != null) {
          currentImage['size'] = match.group(2)!.trim();
          matchedLines++;
          continue;
        }

        match = archRegex.firstMatch(trimmed);
        if (match != null) {
          currentImage['architecture'] = match.group(2)!.trim();
          matchedLines++;
          continue;
        }

        match = editionRegex.firstMatch(trimmed);
        if (match != null) {
          currentImage['edition'] = match.group(2)!.trim();
          matchedLines++;
          continue;
        }

        match = versionRegex.firstMatch(trimmed);
        if (match != null) {
          currentImage['version'] = match.group(2)!.trim();
          matchedLines++;
          continue;
        }

        match = installTypeRegex.firstMatch(trimmed);
        if (match != null) {
          currentImage['installationType'] = match.group(2)!.trim();
          matchedLines++;
          continue;
        }
      }
    }

    // Add the last image
    if (currentImage != null) {
      images.add(currentImage);
    }

    _addDebug('Matched $matchedLines field lines');
    _addDebug('Parsed ${images.length} images from DISM output');
    for (final img in images) {
      _addDebug('  Image ${img['index']}: ${img['name'] ?? 'Unknown'}');
    }

    // If no images found, show sample lines for debugging
    if (images.isEmpty && lines.isNotEmpty) {
      _addDebug('Sample lines from DISM output:');
      for (int i = 0; i < lines.length && i < 30; i++) {
        _addDebug('  [$i]: "${lines[i].trim()}"');
      }
    }

    return images;
  }

  Future<bool> createWtg({
    required String isoPath,
    required int imageIndex,
    required int diskNumber,
    required String driveLetter,
    WtgProgressCallback? onProgress,
  }) async {
    _log.clear();
    _cancelled = false;
    _currentIsoPath = isoPath;
    _logLine('=== WTG Creation Start ===');
    _logLine('ISO: $isoPath');
    _logLine('Image Index: $imageIndex');
    _logLine('Disk: $diskNumber');
    _logLine('Drive: $driveLetter');

    final logCenter = LogCenterService();
    await logCenter.logWTG(
      'WTG 创建开始 | 磁盘: $diskNumber | ISO: $isoPath | 镜像索引: $imageIndex',
    );

    final logger = ref.read(fileLoggerServiceProvider);
    await logger.log(
      action: 'Create WTG',
      target: 'Disk $diskNumber',
      result: 'Starting - ISO: $isoPath, Index: $imageIndex',
    );

    try {
      // Step 1: Prepare
      _notify(
        onProgress,
        const WtgProgress(
          step: WtgStep.preparing,
          message: 'wtg_svc_preparing',
          progress: 0.0,
        ),
      );

      if (_cancelled) return false;

      // Step 2: Partition disk
      _notify(
        onProgress,
        const WtgProgress(
          step: WtgStep.partitioningDisk,
          message: 'wtg_svc_partitioning',
          progress: 0.05,
        ),
      );

      final partitionLayout = await _partitionDisk(diskNumber: diskNumber);
      if (partitionLayout == null) {
        _logLine('Partition FAILED');
        final logPath = await saveLogToFile();
        _notify(
          onProgress,
          WtgProgress(
            step: WtgStep.failed,
            message: 'wtg_svc_partition_failed\n\nLog: $logPath',
          ),
        );
        return false;
      }
      _logLine('Partition OK');
      final bootLayout = partitionLayout.bootLayout;
      final efiDrive = partitionLayout.efiDrive;
      final windowsDrive = partitionLayout.windowsDrive;
      _logLine('Prepared EFI partition: $efiDrive');
      _logLine('Prepared Windows partition: $windowsDrive');

      if (_cancelled) return false;

      // Step 3: Mount ISO
      _notify(
        onProgress,
        const WtgProgress(
          step: WtgStep.mountingIso,
          message: 'wtg_svc_mounting',
          progress: 0.15,
        ),
      );

      final mountPoint = await _mountIso(isoPath);
      if (mountPoint == null) {
        _logLine('Mount ISO FAILED');
        final logPath = await saveLogToFile();
        _notify(
          onProgress,
          WtgProgress(
            step: WtgStep.failed,
            message: 'wtg_svc_mount_failed\n\nLog: $logPath',
          ),
        );
        return false;
      }
      _logLine('Mounted at: $mountPoint');

      if (_cancelled) {
        await _unmountIso(isoPath);
        return false;
      }

      // Step 4: Apply image using DISM
      _notify(
        onProgress,
        const WtgProgress(
          step: WtgStep.applyingImage,
          message: 'wtg_svc_applying',
          progress: 0.20,
        ),
      );

      // Find install.wim or install.esd
      final wimPath = '${mountPoint}sources\\install.wim';
      final esdPath = '${mountPoint}sources\\install.esd';

      String? sourcePath;
      if (await File(wimPath).exists()) {
        sourcePath = wimPath;
      } else if (await File(esdPath).exists()) {
        sourcePath = esdPath;
      }

      if (sourcePath == null) {
        _logLine('No install.wim or install.esd found');
        await _unmountIso(isoPath);
        final logPath = await saveLogToFile();
        _notify(
          onProgress,
          WtgProgress(
            step: WtgStep.failed,
            message: 'wtg_svc_no_wim\n\nLog: $logPath',
          ),
        );
        return false;
      }

      final windowsDriveReady = await _waitForPartitionRoot(
        drive: windowsDrive,
        expectedLabel: 'WDS_WTG',
      );
      if (!windowsDriveReady) {
        _logLine('Windows partition is not accessible: $windowsDrive');
        await _unmountIso(isoPath);
        final logPath = await saveLogToFile();
        _notify(
          onProgress,
          WtgProgress(
            step: WtgStep.failed,
            message: 'wtg_svc_no_partition\n\nLog: $logPath',
          ),
        );
        return false;
      }

      final applyResult = await _applyImage(
        sourcePath: sourcePath,
        imageIndex: imageIndex,
        targetDrive: windowsDrive,
        onProgress: onProgress,
      );

      if (!applyResult) {
        _logLine('Apply image FAILED');
        await _unmountIso(isoPath);
        final logPath = await saveLogToFile();
        _notify(
          onProgress,
          WtgProgress(
            step: WtgStep.failed,
            message: 'wtg_svc_apply_failed\n\nLog: $logPath',
          ),
        );
        return false;
      }
      _logLine('Apply image OK');

      if (_cancelled) {
        await _unmountIso(isoPath);
        return false;
      }

      final configResult = await _configureWtgImage(windowsDrive: windowsDrive);
      if (!configResult) {
        _logLine('WTG offline configuration FAILED');
        await _unmountIso(isoPath);
        final logPath = await saveLogToFile();
        _notify(
          onProgress,
          WtgProgress(
            step: WtgStep.failed,
            message: 'wtg_svc_boot_failed\n\nLog: $logPath',
          ),
        );
        return false;
      }
      _logLine('WTG offline configuration OK');

      if (_cancelled) {
        await _unmountIso(isoPath);
        return false;
      }

      // Step 5: Write boot files
      _notify(
        onProgress,
        const WtgProgress(
          step: WtgStep.writingBootFiles,
          message: 'wtg_svc_writing_boot',
          progress: 0.70,
        ),
      );

      final efiDriveReady = await _waitForPartitionRoot(
        drive: efiDrive,
        expectedLabel: 'WDS_EFI',
      );
      if (!efiDriveReady) {
        _logLine('EFI partition is not accessible: $efiDrive');
        await _unmountIso(isoPath);
        final logPath = await saveLogToFile();
        _notify(
          onProgress,
          WtgProgress(
            step: WtgStep.failed,
            message: 'wtg_svc_boot_failed\n\nLog: $logPath',
          ),
        );
        return false;
      }
      _logLine('Using independent EFI partition: $efiDrive');

      final bootResult = await _writeBootFiles(
        windowsDrive: windowsDrive,
        efiDrive: efiDrive,
        bootLayout: bootLayout,
      );

      await _unmountIso(isoPath);

      if (!bootResult) {
        _logLine('Boot file write FAILED');
        final logPath = await saveLogToFile();
        _notify(
          onProgress,
          WtgProgress(
            step: WtgStep.failed,
            message: 'wtg_svc_boot_failed\n\nLog: $logPath',
          ),
        );
        return false;
      }
      _logLine('Boot files OK');

      if (_cancelled) return false;

      // Step 6: Verify
      _notify(
        onProgress,
        const WtgProgress(
          step: WtgStep.verifying,
          message: 'wtg_svc_verifying',
          progress: 0.90,
        ),
      );

      final verifyResult = await _verifyWtg(
        windowsDrive: windowsDrive,
        efiDrive: efiDrive,
        bootLayout: bootLayout,
      );
      _logLine('Verify: ${verifyResult ? "OK" : "FAILED"}');

      _notify(
        onProgress,
        WtgProgress(
          step: verifyResult ? WtgStep.complete : WtgStep.failed,
          message: verifyResult ? 'wtg_svc_complete' : 'wtg_svc_verify_failed',
          progress: verifyResult ? 1.0 : 0.0,
        ),
      );

      await logger.log(
        action: 'Create WTG',
        target: 'Disk $diskNumber',
        result: verifyResult ? 'Success - Verified' : 'Failed - Verification',
        level: verifyResult ? LogLevel.success : LogLevel.error,
      );

      final logPath = await saveLogToFile();
      _logLine('Log saved to: $logPath');

      if (verifyResult) {
        await logCenter.logWTG('WTG 创建成功 | 磁盘: $diskNumber');
      } else {
        await logCenter.logError('WTG 验证失败 | 磁盘: $diskNumber');
      }

      return verifyResult;
    } on TimeoutException catch (e) {
      _logLine('TIMEOUT: $e');
      final logPath = await saveLogToFile();
      await logCenter.logError('WTG 创建超时 | 磁盘: $diskNumber | 错误: $e');
      _notify(
        onProgress,
        WtgProgress(
          step: WtgStep.failed,
          message: 'wtg_svc_timeout\n\nLog: $logPath',
        ),
      );
      await logger.log(
        action: 'Create WTG',
        target: 'Disk $diskNumber',
        result: 'Timeout: $e',
        level: LogLevel.error,
      );
      return false;
    } catch (e) {
      _logLine('EXCEPTION: $e');
      final logPath = await saveLogToFile();
      await logCenter.logError('WTG 创建异常 | 磁盘: $diskNumber | 错误: $e');
      _notify(
        onProgress,
        WtgProgress(
          step: WtgStep.failed,
          message: 'creator_error\n$e\n\nLog: $logPath',
        ),
      );
      await logger.log(
        action: 'Create WTG',
        target: 'Disk $diskNumber',
        result: 'Exception: $e',
        level: LogLevel.error,
      );
      return false;
    }
  }

  Future<_WtgPartitionLayout?> _partitionDisk({required int diskNumber}) async {
    final letters = await _reserveWtgDriveLetters();
    if (letters == null) {
      _logLine('Unable to reserve drive letters for WTG partitions');
      return null;
    }

    _logLine('Creating GPT/UEFI WTG partition scheme...');
    final gptResult = await _partitionDiskGpt(diskNumber, letters);

    if (gptResult) {
      _logLine('GPT/UEFI partition scheme succeeded');
      return _WtgPartitionLayout(
        bootLayout: WtgBootLayout.gptUefi,
        efiDrive: _driveFromLetter(letters.efiLetter),
        windowsDrive: _driveFromLetter(letters.windowsLetter),
      );
    }

    _logLine('GPT/UEFI failed, trying MBR hybrid two-partition layout...');
    final retryLetters = await _reserveWtgDriveLetters();
    if (retryLetters == null) {
      _logLine('Unable to reserve drive letters for MBR fallback');
      return null;
    }

    final mbrResult = await _partitionDiskMbrHybrid(diskNumber, retryLetters);
    if (mbrResult) {
      _logLine('MBR hybrid partition scheme succeeded');
      return _WtgPartitionLayout(
        bootLayout: WtgBootLayout.mbrHybrid,
        efiDrive: _driveFromLetter(retryLetters.efiLetter),
        windowsDrive: _driveFromLetter(retryLetters.windowsLetter),
      );
    }

    _logLine('All WTG partition schemes failed');
    return null;
  }

  Future<bool> _partitionDiskGpt(
    int diskNumber,
    _WtgDriveLetters letters,
  ) async {
    final script =
        '''
select disk $diskNumber
clean
exit
''';
    _logLine('GPT DiskPart - Step 1: Clean disk');
    _logLine('DiskPart script:\n$script');

    // Step 1: Clean the disk first
    final cleanResult = await _runDiskpart(script);
    _logLine('Clean exit: ${cleanResult.exitCode}');

    if (!_diskpartSucceeded(cleanResult)) {
      _logLine('Clean failed');
      _logLine('Clean stderr: ${cleanResult.stderr}');
      _logLine('Clean stdout: ${cleanResult.stdout}');
      return false;
    }

    // Wait for system to recognize the cleaned disk
    _logLine('Waiting 3 seconds for disk recognition...');
    await Future.delayed(const Duration(seconds: 3));

    // Step 2: Convert to GPT and create partitions
    final script2 =
        '''
select disk $diskNumber
convert gpt
create partition efi size=300
format fs=fat32 label="WDS_EFI" quick
assign letter=${letters.efiLetter}
create partition msr size=16
create partition primary
format fs=ntfs label="WDS_WTG" quick
assign letter=${letters.windowsLetter}
exit
''';
    _logLine('GPT DiskPart - Step 2: Create partitions');
    _logLine('DiskPart script:\n$script2');

    final result = await _runDiskpart(script2);
    _logLine('GPT DiskPart exit: ${result.exitCode}');

    if (!_diskpartSucceeded(result)) {
      _logLine('GPT DiskPart stderr: ${result.stderr}');
      _logLine('GPT DiskPart stdout: ${result.stdout}');
      return false;
    }

    return true;
  }

  Future<bool> _partitionDiskMbrHybrid(
    int diskNumber,
    _WtgDriveLetters letters,
  ) async {
    final cleanScript =
        '''
select disk $diskNumber
clean
exit
''';
    _logLine('MBR Hybrid DiskPart - Step 1: Clean disk');

    final cleanResult = await _runDiskpart(cleanScript);
    _logLine('Clean exit: ${cleanResult.exitCode}');

    if (!_diskpartSucceeded(cleanResult)) {
      _logLine('Clean failed');
      _logLine('Clean stderr: ${cleanResult.stderr}');
      _logLine('Clean stdout: ${cleanResult.stdout}');
      return false;
    }

    _logLine('Waiting 3 seconds for disk recognition...');
    await Future.delayed(const Duration(seconds: 3));

    final script =
        '''
select disk $diskNumber
convert mbr
create partition primary size=350
format fs=fat32 label="WDS_EFI" quick
active
assign letter=${letters.efiLetter}
create partition primary
format fs=ntfs label="WDS_WTG" quick
assign letter=${letters.windowsLetter}
exit
''';
    _logLine(
      'MBR Hybrid DiskPart - Step 2: Create system and Windows partitions',
    );
    _logLine('DiskPart script:\n$script');

    final result = await _runDiskpart(script);
    _logLine('MBR Hybrid DiskPart exit: ${result.exitCode}');

    if (!_diskpartSucceeded(result)) {
      _logLine('MBR Hybrid DiskPart stderr: ${result.stderr}');
      _logLine('MBR Hybrid DiskPart stdout: ${result.stdout}');
      return false;
    }

    return true;
  }

  bool _diskpartSucceeded(ProcessResult result) {
    if (result.exitCode != 0) return false;

    final combined = '${result.stdout}\n${result.stderr}'.toLowerCase();
    const errors = [
      'diskpart has encountered an error',
      'virtual disk service error',
      'the parameter is incorrect',
      'access is denied',
      'diskpart 遇到错误',
      '虚拟磁盘服务错误',
      '参数错误',
      '拒绝访问',
    ];

    return !errors.any(combined.contains);
  }

  Future<_WtgDriveLetters?> _reserveWtgDriveLetters() async {
    const preferredEfi = 'S';
    const preferredWindows = 'W';

    String? pick(List<String> preferred, Set<String> blocked) {
      for (final letter in preferred) {
        final value = letter.toUpperCase();
        final root = Directory(_driveFromLetter(value));
        if (!root.existsSync() && !blocked.contains(value)) {
          return value;
        }
      }
      return null;
    }

    final efi = pick([
      preferredEfi,
      'R',
      'T',
      'U',
      'V',
      'X',
      'Y',
      'Z',
    ], const {});
    if (efi == null) return null;

    final windows = pick(
      [preferredWindows, 'V', 'U', 'T', 'R', 'X', 'Y', 'Z'],
      {efi},
    );
    if (windows == null) return null;

    _logLine('Reserved WTG drive letters: EFI=$efi Windows=$windows');
    return _WtgDriveLetters(efiLetter: efi, windowsLetter: windows);
  }

  Future<bool> _waitForPartitionRoot({
    required String drive,
    required String expectedLabel,
  }) async {
    final root = _driveRoot(drive);
    _logLine('Waiting for $expectedLabel partition at $root');

    for (var attempt = 1; attempt <= 30; attempt++) {
      if (_cancelled) return false;

      final directory = Directory(root);
      if (await directory.exists()) {
        final probe = File(_drivePath(root, '.wds_probe'));
        try {
          await probe.writeAsString('ok');
          await probe.delete().catchError((_) => probe);
          _logLine(
            '$expectedLabel partition ready at $root (attempt $attempt)',
          );
          return true;
        } catch (e) {
          _logLine(
            '$expectedLabel partition exists but is not writable yet '
            '(attempt $attempt): $e',
          );
        }
      }

      await Future.delayed(const Duration(seconds: 1));
    }

    _logLine('$expectedLabel partition did not become ready at $root');
    return false;
  }

  Future<ProcessResult> _runDiskpart(String script) async {
    final tempDir = await getTemporaryDirectory();
    final scriptFile = File(p.join(tempDir.path, 'wtg_diskpart.txt'));
    await scriptFile.writeAsString(script);

    try {
      final result = await Process.run('diskpart', [
        '/s',
        scriptFile.path,
      ]).timeout(const Duration(seconds: 120));
      return result;
    } on TimeoutException {
      _logLine('DiskPart timeout (120s) - disk may be locked or busy');
      rethrow;
    } finally {
      await scriptFile.delete().catchError((_) => scriptFile);
    }
  }

  Future<String?> _mountIso(String isoPath) async {
    try {
      _logLine('Mounting ISO: $isoPath');

      // Check if file exists
      final isoFile = File(isoPath);
      if (!await isoFile.exists()) {
        _logLine('ERROR: ISO file not found: $isoPath');
        return null;
      }
      _logLine('ISO file exists: YES');
      _logLine('ISO file size: ${await isoFile.length()} bytes');

      final escapedPath = isoPath.replaceAll("'", "''");

      // Clean up any stale mount
      _logLine('Cleaning up stale mounts...');
      try {
        await Process.run('powershell', [
          '-NoProfile',
          '-ExecutionPolicy',
          'Bypass',
          '-Command',
          "Dismount-DiskImage -ImagePath '$escapedPath' -ErrorAction SilentlyContinue | Out-Null",
        ]).timeout(const Duration(seconds: 15));
      } catch (e) {
        _logLine('Cleanup warning (non-fatal): $e');
      }

      // Mount ISO with longer timeout
      _logLine('Mounting disk image...');
      ProcessResult mountResult;
      try {
        mountResult = await Process.run('powershell', [
          '-NoProfile',
          '-ExecutionPolicy',
          'Bypass',
          '-Command',
          "Mount-DiskImage -ImagePath '$escapedPath' -PassThru",
        ]).timeout(const Duration(seconds: 120));
      } on TimeoutException {
        _logLine('ERROR: Mount timed out after 120 seconds');
        return null;
      }

      _logLine('Mount exit code: ${mountResult.exitCode}');
      if (mountResult.exitCode != 0) {
        _logLine('Mount stderr: ${mountResult.stderr}');
        _logLine('Mount stdout: ${mountResult.stdout}');
        return null;
      }

      // Get drive letter with retries
      _logLine('Getting drive letter...');
      for (int i = 0; i < 15; i++) {
        if (_cancelled) {
          _logLine('Cancelled during drive letter detection');
          return null;
        }

        await Future.delayed(const Duration(milliseconds: 300));

        try {
          final letterResult = await Process.run('powershell', [
            '-NoProfile',
            '-ExecutionPolicy',
            'Bypass',
            '-Command',
            "Get-DiskImage -ImagePath '$escapedPath' | Get-Volume | Select-Object -ExpandProperty DriveLetter",
          ]).timeout(const Duration(seconds: 5));

          _logLine(
            'Drive letter attempt ${i + 1}: exit=${letterResult.exitCode}, stdout="${letterResult.stdout.toString().trim()}"',
          );

          if (letterResult.exitCode == 0) {
            final letter = letterResult.stdout.toString().trim();
            if (letter.isNotEmpty && letter.length == 1 && letter != '0') {
              final mountPoint = '$letter:\\';
              _logLine('Mounted at: $mountPoint');
              return mountPoint;
            }
          }
        } catch (e) {
          _logLine('Drive letter attempt ${i + 1} error: $e');
        }
      }

      _logLine('Failed to get drive letter after 15 attempts');

      // Try alternative method to get drive letter
      _logLine('Trying alternative drive letter detection...');
      try {
        final altResult = await Process.run('powershell', [
          '-NoProfile',
          '-ExecutionPolicy',
          'Bypass',
          '-Command',
          "(Get-DiskImage -ImagePath '$escapedPath' | Get-Volume).DriveLetter",
        ]).timeout(const Duration(seconds: 10));

        if (altResult.exitCode == 0) {
          final letter = altResult.stdout.toString().trim();
          if (letter.isNotEmpty && letter.length == 1 && letter != '0') {
            final mountPoint = '$letter:\\';
            _logLine('Mounted at (alt method): $mountPoint');
            return mountPoint;
          }
        }
      } catch (e) {
        _logLine('Alternative method failed: $e');
      }
    } catch (e) {
      _logLine('Mount exception: $e');
    }
    return null;
  }

  Future<void> _unmountIso(String isoPath) async {
    try {
      _logLine('Unmounting ISO: $isoPath');
      final escapedPath = isoPath.replaceAll("'", "''");
      await Process.run('powershell', [
        '-NoProfile',
        '-ExecutionPolicy',
        'Bypass',
        '-Command',
        "Dismount-DiskImage -ImagePath '$escapedPath' -ErrorAction SilentlyContinue",
      ]).timeout(const Duration(seconds: 30));
      _logLine('Unmounted OK');
    } catch (e) {
      _logLine('Unmount error (non-fatal): $e');
    }
  }

  Future<bool> _configureWtgImage({required String windowsDrive}) async {
    const hiveName = 'WDS_WTG_SYSTEM';
    final systemHive = _drivePath(
      windowsDrive,
      'Windows\\System32\\config\\SYSTEM',
    );

    try {
      _logLine('Configuring offline WTG image: $windowsDrive');
      if (!await File(systemHive).exists()) {
        _logLine('SYSTEM hive not found: $systemHive');
        return false;
      }

      final sanPolicyResult = await _applySanPolicyUnattend(windowsDrive);
      if (!sanPolicyResult) {
        return false;
      }

      final winReResult = await _writeWinReUnattend(windowsDrive);
      if (!winReResult) {
        return false;
      }

      await _unloadRegistryHive(hiveName);

      final loadResult = await Process.run('reg', [
        'load',
        'HKLM\\$hiveName',
        systemHive,
      ]).timeout(const Duration(seconds: 30));
      _logLine('reg load exit: ${loadResult.exitCode}');
      _logLine('reg load stdout: ${loadResult.stdout}');
      if (loadResult.exitCode != 0) {
        _logLine('reg load stderr: ${loadResult.stderr}');
        return false;
      }

      final commands = <List<String>>[
        [
          'add',
          'HKLM\\$hiveName\\ControlSet001\\Control',
          '/v',
          'PortableOperatingSystem',
          '/t',
          'REG_DWORD',
          '/d',
          '1',
          '/f',
        ],
        [
          'add',
          'HKLM\\$hiveName\\ControlSet001\\Services\\partmgr\\Parameters',
          '/v',
          'SanPolicy',
          '/t',
          'REG_DWORD',
          '/d',
          '4',
          '/f',
        ],
      ];

      for (final args in commands) {
        final result = await Process.run(
          'reg',
          args,
        ).timeout(const Duration(seconds: 30));
        _logLine('reg ${args.join(' ')} exit: ${result.exitCode}');
        if (result.exitCode != 0) {
          _logLine('reg stderr: ${result.stderr}');
          return false;
        }
      }

      return true;
    } catch (e) {
      _logLine('WTG offline configuration error: $e');
      return false;
    } finally {
      await _unloadRegistryHive(hiveName);
    }
  }

  Future<bool> _applySanPolicyUnattend(String windowsDrive) async {
    final imageRoot = _driveRoot(windowsDrive);
    final policyPath = _drivePath(windowsDrive, 'san_policy.xml');
    const policyXml = '''
<?xml version="1.0" encoding="utf-8" standalone="yes"?>
<unattend xmlns="urn:schemas-microsoft-com:unattend">
  <settings pass="offlineServicing">
    <component name="Microsoft-Windows-PartitionManager" processorArchitecture="x86" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS" xmlns:wcm="http://schemas.microsoft.com/WMIConfig/2002/State" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
      <SanPolicy>4</SanPolicy>
    </component>
    <component name="Microsoft-Windows-PartitionManager" processorArchitecture="amd64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS" xmlns:wcm="http://schemas.microsoft.com/WMIConfig/2002/State" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
      <SanPolicy>4</SanPolicy>
    </component>
    <component name="Microsoft-Windows-PartitionManager" processorArchitecture="arm64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS" xmlns:wcm="http://schemas.microsoft.com/WMIConfig/2002/State" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
      <SanPolicy>4</SanPolicy>
    </component>
  </settings>
</unattend>
''';

    try {
      await File(policyPath).writeAsString(policyXml);
      _logLine('Applying SAN policy unattend: $policyPath');
      final result = await Process.run('dism', [
        '/Image:$imageRoot',
        '/Apply-Unattend:$policyPath',
      ]).timeout(const Duration(minutes: 5));

      _logLine('DISM SAN policy exit: ${result.exitCode}');
      _logLine('DISM SAN policy stdout: ${result.stdout}');
      if (result.exitCode != 0) {
        _logLine('DISM SAN policy stderr: ${result.stderr}');
        return false;
      }

      return true;
    } catch (e) {
      _logLine('SAN policy unattend error: $e');
      return false;
    } finally {
      try {
        await File(policyPath).delete();
      } catch (_) {}
    }
  }

  Future<bool> _writeWinReUnattend(String windowsDrive) async {
    final sysprepDir = Directory(
      _drivePath(windowsDrive, 'Windows\\System32\\Sysprep'),
    );
    final unattendPath = p.join(sysprepDir.path, 'unattend.xml');
    const unattendXml = '''
<?xml version="1.0" encoding="utf-8"?>
<unattend xmlns="urn:schemas-microsoft-com:unattend">
  <settings pass="oobeSystem">
    <component name="Microsoft-Windows-WinRE-RecoveryAgent" processorArchitecture="x86" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS" xmlns:wcm="http://schemas.microsoft.com/WMIConfig/2002/State" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
      <UninstallWindowsRE>true</UninstallWindowsRE>
    </component>
    <component name="Microsoft-Windows-WinRE-RecoveryAgent" processorArchitecture="amd64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS" xmlns:wcm="http://schemas.microsoft.com/WMIConfig/2002/State" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
      <UninstallWindowsRE>true</UninstallWindowsRE>
    </component>
    <component name="Microsoft-Windows-WinRE-RecoveryAgent" processorArchitecture="arm64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS" xmlns:wcm="http://schemas.microsoft.com/WMIConfig/2002/State" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
      <UninstallWindowsRE>true</UninstallWindowsRE>
    </component>
  </settings>
</unattend>
''';

    try {
      if (!await sysprepDir.exists()) {
        await sysprepDir.create(recursive: true);
      }
      await File(unattendPath).writeAsString(unattendXml);
      _logLine('Wrote WTG WinRE unattend: $unattendPath');
      return true;
    } catch (e) {
      _logLine('Write WinRE unattend error: $e');
      return false;
    }
  }

  Future<void> _unloadRegistryHive(String hiveName) async {
    for (int attempt = 0; attempt < 3; attempt++) {
      try {
        final result = await Process.run('reg', [
          'unload',
          'HKLM\\$hiveName',
        ]).timeout(const Duration(seconds: 15));
        _logLine('reg unload HKLM\\$hiveName exit: ${result.exitCode}');
        if (result.exitCode == 0) return;
      } catch (e) {
        _logLine('reg unload warning: $e');
      }
      await Future.delayed(const Duration(milliseconds: 500));
    }
  }

  Future<bool> _applyImage({
    required String sourcePath,
    required int imageIndex,
    required String targetDrive,
    WtgProgressCallback? onProgress,
  }) async {
    try {
      _logLine('=== Apply Image ===');
      _logLine('Source: $sourcePath');
      _logLine('Index: $imageIndex');
      final targetRoot = _driveRoot(targetDrive);
      _logLine('Target: $targetRoot');

      // Get total image size from source file
      final sourceFile = File(sourcePath);
      final totalImageSize = await sourceFile.length();
      _logLine(
        'Total image size: $totalImageSize bytes (${(totalImageSize / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB)',
      );

      final stopwatch = Stopwatch()..start();

      // Use Process.start for DISM
      _logLine('Starting DISM...');
      final process = await Process.start('dism', [
        '/Apply-Image',
        '/ImageFile:$sourcePath',
        '/Index:$imageIndex',
        '/ApplyDir:$targetRoot',
      ]);

      // Save process reference for cancellation
      _currentProcess = process;
      _logLine('DISM PID: ${process.pid}');

      // Track progress from DISM output
      int lastPercent = 0;
      int lastWrittenBytes = 0;
      int lastElapsedMs = 0;

      // Listen to stdout
      process.stdout.transform(const SystemEncoding().decoder).listen((data) {
        final match = RegExp(r'(\d+)\s*%').firstMatch(data);
        if (match != null) {
          final percent = int.parse(match.group(1)!);
          if (percent > lastPercent) {
            lastPercent = percent;
            final elapsed = stopwatch.elapsed;
            final elapsedMs = elapsed.inMilliseconds;
            final writtenBytes = (totalImageSize * percent / 100).round();

            // Calculate speed: bytes per second
            final elapsedDelta = elapsedMs - lastElapsedMs;
            final writtenDelta = writtenBytes - lastWrittenBytes;
            final speedBytes = elapsedDelta > 0
                ? (writtenDelta * 1000 / elapsedDelta).round()
                : 0;

            lastWrittenBytes = writtenBytes;
            lastElapsedMs = elapsedMs;

            _logLine(
              'DISM: $percent% | Written: ${(writtenBytes / (1024 * 1024)).toStringAsFixed(0)} MB | Speed: ${(speedBytes / (1024 * 1024)).toStringAsFixed(1)} MB/s',
            );

            _notify(
              onProgress,
              WtgProgress(
                step: WtgStep.applyingImage,
                message: 'wtg_svc_applying_percent',
                progress: percent / 100.0,
                writtenBytes: writtenBytes,
                totalBytes: totalImageSize,
                currentSpeedBytes: speedBytes,
                elapsedTime: elapsed,
              ),
            );
          }
        }
      });

      // Listen to stderr
      process.stderr.transform(const SystemEncoding().decoder).listen((data) {
        if (data.trim().isNotEmpty) {
          _logLine('DISM stderr: ${data.trim()}');
          final match = RegExp(r'(\d+)\s*%').firstMatch(data);
          if (match != null) {
            final percent = int.parse(match.group(1)!);
            if (percent > lastPercent) {
              lastPercent = percent;
              final elapsed = stopwatch.elapsed;
              final writtenBytes = (totalImageSize * percent / 100).round();

              _notify(
                onProgress,
                WtgProgress(
                  step: WtgStep.applyingImage,
                  message: 'wtg_svc_applying_percent',
                  progress: percent / 100.0,
                  writtenBytes: writtenBytes,
                  totalBytes: totalImageSize,
                  currentSpeedBytes: 0,
                  elapsedTime: elapsed,
                ),
              );
            }
          }
        }
      });

      // Wait for DISM to complete
      int exitCode;
      try {
        exitCode = await process.exitCode.timeout(
          const Duration(minutes: 30),
          onTimeout: () {
            _logLine('DISM timeout!');
            _killCurrentProcess();
            return -1;
          },
        );
      } finally {
        _currentProcess = null;
      }

      stopwatch.stop();
      _logLine('DISM exit: $exitCode');
      _logLine(
        'Total: ${stopwatch.elapsed.inMinutes}m ${stopwatch.elapsed.inSeconds % 60}s',
      );

      if (exitCode != 0) {
        _logLine('DISM FAILED');
        return false;
      }

      _notify(
        onProgress,
        WtgProgress(
          step: WtgStep.applyingImage,
          message: 'wtg_svc_image_applied',
          progress: 1.0,
          writtenBytes: totalImageSize,
          totalBytes: totalImageSize,
          currentSpeedBytes: 0,
          elapsedTime: stopwatch.elapsed,
        ),
      );

      return true;
    } catch (e) {
      _logLine('ERROR: $e');
      return false;
    }
  }

  Future<bool> _writeBootFiles({
    required String windowsDrive,
    required String efiDrive,
    required WtgBootLayout bootLayout,
  }) async {
    try {
      _logLine('Writing boot files: windows=$windowsDrive efi=$efiDrive');

      // Check admin rights first
      final isAdmin = await _checkAdminRights();
      if (!isAdmin) {
        _logLine('ERROR: bcdboot requires administrator privileges');
        _logLine('Please run the application as administrator');
        return false;
      }

      // Run bcdboot against the independent FAT32 system partition. Never use
      // the Windows NTFS partition as the boot target.
      final windowsPath = _drivePath(windowsDrive, 'Windows');
      final efiRoot = _driveRoot(efiDrive);
      final targetBcdboot = _drivePath(
        windowsDrive,
        'Windows\\System32\\bcdboot.exe',
      );
      final bcdbootExe = await File(targetBcdboot).exists()
          ? targetBcdboot
          : 'bcdboot';
      final firmware = bootLayout == WtgBootLayout.gptUefi ? 'UEFI' : 'ALL';
      _logLine('Running $bcdbootExe $windowsPath /s $efiRoot /f $firmware');
      final result = await Process.run(bcdbootExe, [
        windowsPath,
        '/s',
        efiRoot,
        '/f',
        firmware,
      ]).timeout(const Duration(seconds: 120));

      _logLine('bcdboot exit: ${result.exitCode}');
      _logLine('bcdboot stdout: ${result.stdout}');

      if (result.exitCode != 0) {
        _logLine('bcdboot stderr: ${result.stderr}');
        _logLine('bcdboot FAILED with exit code ${result.exitCode}');
        return false;
      }

      _logLine('bcdboot completed successfully');
      final fallbackOk = await _ensureFallbackUefiBootFile(efiDrive: efiDrive);
      if (!fallbackOk) return false;

      return _hardenBcdStore(windowsDrive: windowsDrive, efiDrive: efiDrive);
    } on TimeoutException {
      _logLine('bcdboot timed out after 120 seconds');
      return false;
    } catch (e) {
      _logLine('Boot file error: $e');
      return false;
    }
  }

  Future<bool> _hardenBcdStore({
    required String windowsDrive,
    required String efiDrive,
  }) async {
    final bcdPath = _drivePath(efiDrive, 'EFI\\Microsoft\\Boot\\BCD');
    if (!await File(bcdPath).exists()) {
      _logLine('BCD store not found for hardening: $bcdPath');
      return false;
    }

    final osDevice = 'partition=${_driveSpec(windowsDrive)}';
    final commands = <List<String>>[
      ['/store', bcdPath, '/set', '{default}', 'device', osDevice],
      ['/store', bcdPath, '/set', '{default}', 'osdevice', osDevice],
      ['/store', bcdPath, '/set', '{default}', 'detecthal', 'yes'],
    ];

    for (final args in commands) {
      try {
        final result = await Process.run(
          'bcdedit',
          args,
        ).timeout(const Duration(seconds: 30));
        _logLine('bcdedit ${args.join(' ')} exit: ${result.exitCode}');
        if (result.exitCode != 0) {
          _logLine('bcdedit stderr: ${result.stderr}');
          return false;
        }
      } catch (e) {
        _logLine('bcdedit error: $e');
        return false;
      }
    }

    return true;
  }

  Future<bool> _ensureFallbackUefiBootFile({required String efiDrive}) async {
    try {
      final bootDir = Directory(_drivePath(efiDrive, 'EFI\\Boot'));
      if (!await bootDir.exists()) {
        await bootDir.create(recursive: true);
      }

      final fallback = File(_drivePath(efiDrive, 'EFI\\Boot\\bootx64.efi'));
      if (await fallback.exists()) {
        _logLine('UEFI fallback boot file exists: ${fallback.path}');
        return true;
      }

      final candidates = <String>[
        _drivePath(efiDrive, 'EFI\\Microsoft\\Boot\\bootmgfw.efi'),
        _drivePath(efiDrive, 'EFI\\Microsoft\\Boot\\bootx64.efi'),
      ];

      for (final candidate in candidates) {
        final source = File(candidate);
        if (await source.exists()) {
          await source.copy(fallback.path);
          _logLine('Copied UEFI fallback boot file from $candidate');
          return true;
        }
      }

      _logLine('Unable to create UEFI fallback boot file');
      return false;
    } catch (e) {
      _logLine('UEFI fallback boot file error: $e');
      return false;
    }
  }

  Future<bool> _checkAdminRights() async {
    try {
      final result = await Process.run('net', ['session']);
      return result.exitCode == 0;
    } catch (e) {
      _logLine('Admin check failed: $e');
      return false;
    }
  }

  Future<bool> _verifyWtg({
    required String windowsDrive,
    required String efiDrive,
    required WtgBootLayout bootLayout,
  }) async {
    final errors = <String>[];

    _logLine('Verification mode: ${bootLayout.name}');

    // Check Windows partition
    if (!await Directory(_drivePath(windowsDrive, 'Windows')).exists()) {
      errors.add('Windows directory missing');
    }

    if (_driveRoot(windowsDrive).toUpperCase() ==
        _driveRoot(efiDrive).toUpperCase()) {
      errors.add('EFI partition must be separate from Windows partition');
    }

    // GPT mode: check independent EFI partition
    if (!await Directory(_drivePath(efiDrive, 'EFI')).exists()) {
      errors.add('EFI directory missing');
    }

    // Check BCD
    final hasBcd = await File(
      _drivePath(efiDrive, 'EFI\\Microsoft\\Boot\\BCD'),
    ).exists();
    if (!hasBcd) {
      errors.add('BCD missing');
    }

    if (bootLayout == WtgBootLayout.mbrHybrid) {
      final hasBootmgr = await File(_drivePath(efiDrive, 'bootmgr')).exists();
      if (!hasBootmgr) {
        errors.add('BIOS bootmgr missing on system partition');
      }
    }

    final hasFallbackEfi =
        await File(_drivePath(efiDrive, 'EFI\\Boot\\bootx64.efi')).exists() ||
        await File(_drivePath(efiDrive, 'EFI\\Boot\\bootaa64.efi')).exists();
    if (!hasFallbackEfi) {
      errors.add('UEFI fallback boot file missing');
    }

    if (errors.isNotEmpty) {
      _logLine('Verify issues: ${errors.join(', ')}');
      return false;
    }

    _logLine('Verification passed');
    return true;
  }
}
