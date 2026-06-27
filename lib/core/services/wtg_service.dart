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

  int get remainingBytes => totalBytes > writtenBytes ? totalBytes - writtenBytes : 0;

  String get formattedWritten {
    if (writtenBytes <= 0) return '0 B';
    if (writtenBytes < 1024 * 1024) return '${(writtenBytes / 1024).toStringAsFixed(1)} KB';
    if (writtenBytes < 1024 * 1024 * 1024) return '${(writtenBytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(writtenBytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }

  String get formattedTotal {
    if (totalBytes <= 0) return '--';
    if (totalBytes < 1024 * 1024) return '${(totalBytes / 1024).toStringAsFixed(1)} KB';
    if (totalBytes < 1024 * 1024 * 1024) return '${(totalBytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(totalBytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }

  String get formattedRemaining {
    final rem = remainingBytes;
    if (rem <= 0) return '0 B';
    if (rem < 1024 * 1024) return '${(rem / 1024).toStringAsFixed(1)} KB';
    if (rem < 1024 * 1024 * 1024) return '${(rem / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(rem / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }

  String get formattedSpeed {
    if (currentSpeedBytes <= 0) return '--';
    if (currentSpeedBytes < 1024 * 1024) return '${(currentSpeedBytes / 1024).toStringAsFixed(1)} KB/s';
    if (currentSpeedBytes < 1024 * 1024 * 1024) return '${(currentSpeedBytes / (1024 * 1024)).toStringAsFixed(1)} MB/s';
    return '${(currentSpeedBytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB/s';
  }

  String get formattedElapsed {
    if (elapsedTime == null) return '00:00:00';
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

  WtgService(this.ref);

  void _logLine(String msg) {
    final line = '[${DateTime.now().toIso8601String()}] $msg';
    _log.add(line);
    debugPrint(line);
    
    // 实时写入文件 - 同步执行确保日志不丢失
    _writeLogToFileSync(line);
  }
  
  void _writeLogToFileSync(String line) {
    try {
      final dir = Directory('C:\\Users\\${Platform.environment['USERNAME']}\\AppData\\Roaming\\WinDeployStudio\\logs');
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

  void cancel() {
    _cancelled = true;
    _logLine('=== WTG Creation Cancelled ===');
  }

  Future<String> saveLogToFile() async {
    try {
      final dir = await getApplicationSupportDirectory();
      final logFile = File(p.join(dir.path, 'logs', 'last_wtg_creation_log.txt'));
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

  List<String> _debugLogs = [];
  
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
        currentImage = {
          'index': int.tryParse(match.group(2)!) ?? 0,
        };
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
    _logLine('=== WTG Creation Start ===');
    _logLine('ISO: $isoPath');
    _logLine('Image Index: $imageIndex');
    _logLine('Disk: $diskNumber');
    _logLine('Drive: $driveLetter');

    final logCenter = LogCenterService();
    await logCenter.logWTG('WTG 创建开始 | 磁盘: $diskNumber | ISO: $isoPath | 镜像索引: $imageIndex');

    final logger = ref.read(fileLoggerServiceProvider);
    await logger.log(
      action: 'Create WTG',
      target: 'Disk $diskNumber',
      result: 'Starting - ISO: $isoPath, Index: $imageIndex',
    );

    try {
      // Step 1: Prepare
      _notify(onProgress, const WtgProgress(
        step: WtgStep.preparing,
        message: 'wtg_svc_preparing',
        progress: 0.0,
      ));

      if (_cancelled) return false;

      // Step 2: Partition disk
      _notify(onProgress, const WtgProgress(
        step: WtgStep.partitioningDisk,
        message: 'wtg_svc_partitioning',
        progress: 0.05,
      ));

      final partitionResult = await _partitionDisk(diskNumber: diskNumber);
      if (!partitionResult) {
        _logLine('Partition FAILED');
        final logPath = await saveLogToFile();
        _notify(onProgress, WtgProgress(
          step: WtgStep.failed,
          message: 'wtg_svc_partition_failed\n\nLog: $logPath',
        ));
        return false;
      }
      _logLine('Partition OK');

      if (_cancelled) return false;

      // Step 3: Mount ISO
      _notify(onProgress, const WtgProgress(
        step: WtgStep.mountingIso,
        message: 'wtg_svc_mounting',
        progress: 0.15,
      ));

      final mountPoint = await _mountIso(isoPath);
      if (mountPoint == null) {
        _logLine('Mount ISO FAILED');
        final logPath = await saveLogToFile();
        _notify(onProgress, WtgProgress(
          step: WtgStep.failed,
          message: 'wtg_svc_mount_failed\n\nLog: $logPath',
        ));
        return false;
      }
      _logLine('Mounted at: $mountPoint');

      if (_cancelled) {
        await _unmountIso(isoPath);
        return false;
      }

      // Step 4: Apply image using DISM
      _notify(onProgress, const WtgProgress(
        step: WtgStep.applyingImage,
        message: 'wtg_svc_applying',
        progress: 0.20,
      ));

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
        _notify(onProgress, WtgProgress(
          step: WtgStep.failed,
          message: 'wtg_svc_no_wim\n\nLog: $logPath',
        ));
        return false;
      }

      // Get Windows drive letter (the larger partition)
      final windowsDrive = await _getWindowsPartitionDrive(diskNumber);
      if (windowsDrive == null) {
        _logLine('Could not find Windows partition drive');
        await _unmountIso(isoPath);
        final logPath = await saveLogToFile();
        _notify(onProgress, WtgProgress(
          step: WtgStep.failed,
          message: 'wtg_svc_no_partition\n\nLog: $logPath',
        ));
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
        _notify(onProgress, WtgProgress(
          step: WtgStep.failed,
          message: 'wtg_svc_apply_failed\n\nLog: $logPath',
        ));
        return false;
      }
      _logLine('Apply image OK');

      if (_cancelled) {
        await _unmountIso(isoPath);
        return false;
      }

      // Step 5: Write boot files
      _notify(onProgress, const WtgProgress(
        step: WtgStep.writingBootFiles,
        message: 'wtg_svc_writing_boot',
        progress: 0.70,
      ));

      // For GPT, get EFI partition; for MBR, use Windows partition
      String efiDrive;
      final efiPartition = await _getEfiPartitionDrive(diskNumber);
      if (efiPartition != null) {
        efiDrive = efiPartition;
        _logLine('Using separate EFI partition: $efiDrive');
      } else {
        // MBR mode - use Windows partition for boot files
        efiDrive = windowsDrive;
        _logLine('Using Windows partition for boot files (MBR mode)');
      }

      final bootResult = await _writeBootFiles(
        windowsDrive: windowsDrive,
        efiDrive: efiDrive,
      );

      await _unmountIso(isoPath);

      if (!bootResult) {
        _logLine('Boot file write FAILED');
        final logPath = await saveLogToFile();
        _notify(onProgress, WtgProgress(
          step: WtgStep.failed,
          message: 'wtg_svc_boot_failed\n\nLog: $logPath',
        ));
        return false;
      }
      _logLine('Boot files OK');

      if (_cancelled) return false;

      // Step 6: Verify
      _notify(onProgress, const WtgProgress(
        step: WtgStep.verifying,
        message: 'wtg_svc_verifying',
        progress: 0.90,
      ));

      final verifyResult = await _verifyWtg(
        windowsDrive: windowsDrive,
        efiDrive: efiDrive,
      );
      _logLine('Verify: ${verifyResult ? "OK" : "FAILED"}');

      _notify(onProgress, WtgProgress(
        step: verifyResult ? WtgStep.complete : WtgStep.failed,
        message: verifyResult ? 'wtg_svc_complete' : 'wtg_svc_verify_failed',
        progress: verifyResult ? 1.0 : 0.0,
      ));

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
      _notify(onProgress, WtgProgress(
        step: WtgStep.failed,
        message: 'wtg_svc_timeout\n\nLog: $logPath',
      ));
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
      _notify(onProgress, WtgProgress(
        step: WtgStep.failed,
        message: 'Error: $e\n\nLog: $logPath',
      ));
      await logger.log(
        action: 'Create WTG',
        target: 'Disk $diskNumber',
        result: 'Exception: $e',
        level: LogLevel.error,
      );
      return false;
    }
  }

  Future<bool> _partitionDisk({required int diskNumber}) async {
    // First try GPT + EFI partition (for fixed disks)
    _logLine('Attempting GPT partition scheme...');
    final gptResult = await _partitionDiskGpt(diskNumber);
    
    if (gptResult) {
      _logLine('GPT partition scheme succeeded');
      return true;
    }
    
    // If GPT fails (e.g., removable media), try MBR
    _logLine('GPT failed, falling back to MBR partition scheme...');
    final mbrResult = await _partitionDiskMbr(diskNumber);
    
    if (mbrResult) {
      _logLine('MBR partition scheme succeeded');
      return true;
    }
    
    _logLine('Both GPT and MBR partition schemes failed');
    return false;
  }

  Future<bool> _partitionDiskGpt(int diskNumber) async {
    final script = '''
select disk $diskNumber
clean
exit
''';
    _logLine('GPT DiskPart - Step 1: Clean disk');
    _logLine('DiskPart script:\n$script');

    // Step 1: Clean the disk first
    final cleanResult = await _runDiskpart(script);
    _logLine('Clean exit: ${cleanResult.exitCode}');
    
    if (cleanResult.exitCode != 0) {
      _logLine('Clean failed');
      return false;
    }
    
    // Wait for system to recognize the cleaned disk
    _logLine('Waiting 3 seconds for disk recognition...');
    await Future.delayed(const Duration(seconds: 3));
    
    // Step 2: Convert to GPT and create partitions
    final script2 = '''
select disk $diskNumber
convert gpt
create partition efi size=260
format fs=fat32 label="EFI" quick
assign letter=S
create partition primary
format fs=ntfs label="Windows" quick
assign letter=W
exit
''';
    _logLine('GPT DiskPart - Step 2: Create partitions');
    _logLine('DiskPart script:\n$script2');

    final result = await _runDiskpart(script2);
    _logLine('GPT DiskPart exit: ${result.exitCode}');

    if (result.exitCode != 0) {
      _logLine('GPT DiskPart stdout: ${result.stdout}');
      return false;
    }

    return true;
  }

  Future<bool> _partitionDiskMbr(int diskNumber) async {
    // Step 1: Clean the disk
    final cleanScript = '''
select disk $diskNumber
clean
exit
''';
    _logLine('MBR DiskPart - Step 1: Clean disk');
    
    final cleanResult = await _runDiskpart(cleanScript);
    _logLine('Clean exit: ${cleanResult.exitCode}');
    
    if (cleanResult.exitCode != 0) {
      _logLine('Clean failed');
      return false;
    }
    
    // Wait for system to recognize the cleaned disk
    _logLine('Waiting 3 seconds for disk recognition...');
    await Future.delayed(const Duration(seconds: 3));
    
    // Step 2: Convert to MBR and create partition
    final script = '''
select disk $diskNumber
convert mbr
create partition primary
active
format fs=ntfs label="WIN_TO_GO" quick
assign letter=W
exit
''';
    _logLine('MBR DiskPart - Step 2: Create partition');
    _logLine('DiskPart script:\n$script');

    final result = await _runDiskpart(script);
    _logLine('MBR DiskPart exit: ${result.exitCode}');

    if (result.exitCode != 0) {
      _logLine('MBR DiskPart stderr: ${result.stderr}');
      _logLine('MBR DiskPart stdout: ${result.stdout}');
      return false;
    }

    return true;
  }

  Future<ProcessResult> _runDiskpart(String script) async {
    final tempDir = await getTemporaryDirectory();
    final scriptFile = File(p.join(tempDir.path, 'wtg_diskpart.txt'));
    await scriptFile.writeAsString(script);

    try {
      final result = await Process.run('diskpart', ['/s', scriptFile.path])
          .timeout(const Duration(seconds: 120));
      return result;
    } on TimeoutException {
      _logLine('DiskPart timeout (120s) - disk may be locked or busy');
      rethrow;
    } finally {
      await scriptFile.delete().catchError((_) => scriptFile);
    }
  }

  Future<String?> _getWindowsPartitionDrive(int diskNumber) async {
    try {
      _logLine('Getting Windows partition drive for disk $diskNumber');
      
      // Try multiple approaches to find the drive letter
      final result = await Process.run('powershell', [
        '-NoProfile',
        '-ExecutionPolicy', 'Bypass',
        '-Command',
        'Get-Partition -DiskNumber $diskNumber -ErrorAction SilentlyContinue | Where-Object { \$_.DriveLetter -and \$_.DriveLetter -ne " " } | Select-Object -First 1 -ExpandProperty DriveLetter',
      ]).timeout(const Duration(seconds: 10));

      _logLine('Get-Partition exit: ${result.exitCode}');
      _logLine('Get-Partition stdout: "${result.stdout}"');
      _logLine('Get-Partition stderr: "${result.stderr}"');

      if (result.exitCode == 0) {
        final letter = result.stdout.toString().trim();
        if (letter.isNotEmpty && letter.length == 1) {
          _logLine('Found Windows partition drive: $letter:');
          return '$letter:';
        }
      }
      
      // Fallback: try to get the drive we just assigned (W:)
      _logLine('Trying fallback: checking if W: exists');
      final wDrive = Directory('W:\\');
      if (wDrive.existsSync()) {
        _logLine('W: drive exists');
        return 'W:';
      }
      
    } catch (e) {
      _logLine('Get partition drive error: $e');
    }
    return null;
  }

  Future<String?> _getEfiPartitionDrive(int diskNumber) async {
    try {
      final result = await Process.run('powershell', [
        '-NoProfile',
        '-Command',
        'Get-Partition -DiskNumber $diskNumber | Where-Object { \$_.Type -eq "EFI" -or \$_.GptType -eq "{c12a7328-f81f-11d2-ba4b-00a0c93ec93b}" } | Select-Object -First 1 -ExpandProperty DriveLetter',
      ]).timeout(const Duration(seconds: 5));

      if (result.exitCode == 0) {
        final letter = result.stdout.toString().trim();
        if (letter.isNotEmpty) return '$letter:';
      }
    } catch (_) {}
    return null;
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
          '-NoProfile', '-ExecutionPolicy', 'Bypass',
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
          '-NoProfile', '-ExecutionPolicy', 'Bypass',
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
            '-NoProfile', '-ExecutionPolicy', 'Bypass',
            '-Command',
            "Get-DiskImage -ImagePath '$escapedPath' | Get-Volume | Select-Object -ExpandProperty DriveLetter",
          ]).timeout(const Duration(seconds: 5));
          
          _logLine('Drive letter attempt ${i + 1}: exit=${letterResult.exitCode}, stdout="${letterResult.stdout.toString().trim()}"');
          
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
          '-NoProfile', '-ExecutionPolicy', 'Bypass',
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
        '-NoProfile', '-ExecutionPolicy', 'Bypass',
        '-Command',
        "Dismount-DiskImage -ImagePath '$escapedPath' -ErrorAction SilentlyContinue",
      ]).timeout(const Duration(seconds: 30));
      _logLine('Unmounted OK');
    } catch (e) {
      _logLine('Unmount error (non-fatal): $e');
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
      _logLine('Target: $targetDrive');

      // Check target drive
      final targetDir = Directory(targetDrive);
      _logLine('Target drive exists: ${targetDir.existsSync()}');

      // Get total image size from source file
      final sourceFile = File(sourcePath);
      final totalImageSize = await sourceFile.length();
      _logLine('Total image size: ${totalImageSize} bytes (${(totalImageSize / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB)');

      final stopwatch = Stopwatch()..start();

      // Use Process.start for DISM
      _logLine('Starting DISM...');
      final process = await Process.start('dism', [
        '/Apply-Image',
        '/ImageFile:$sourcePath',
        '/Index:$imageIndex',
        '/ApplyDir:$targetDrive',
      ]);

      _logLine('DISM PID: ${process.pid}');

      // Monitor DISM output
      int lastPercent = 0;
      bool dismDone = false;

      process.stdout.transform(const SystemEncoding().decoder).listen((data) {
        // Parse progress
        final match = RegExp(r'(\d+)%').firstMatch(data);
        if (match != null) {
          final percent = int.parse(match.group(1)!);
          if (percent > lastPercent) {
            lastPercent = percent;
            final elapsed = stopwatch.elapsed;
            final writtenBytes = (totalImageSize * percent / 100).round();
            final speedBytes = elapsed.inSeconds > 0 ? (writtenBytes / elapsed.inSeconds).round() : 0;

            _logLine('DISM: $percent% (${elapsed.inSeconds}s)');

            _notify(onProgress, WtgProgress(
              step: WtgStep.applyingImage,
              message: 'wtg_svc_applying_percent',
              progress: percent / 100.0,
              writtenBytes: writtenBytes,
              totalBytes: totalImageSize,
              currentSpeedBytes: speedBytes,
              elapsedTime: elapsed,
            ));
          }
        }

        // Log important messages
        if (data.contains('Error') || data.contains('error') || data.contains('failed')) {
          _logLine('DISM: ${data.trim()}');
        }
      });

      process.stderr.transform(const SystemEncoding().decoder).listen((data) {
        if (data.trim().isNotEmpty) {
          _logLine('DISM stderr: ${data.trim()}');
          // DISM sometimes outputs progress to stderr
          final match = RegExp(r'(\d+)%').firstMatch(data);
          if (match != null) {
            final percent = int.parse(match.group(1)!);
            if (percent > lastPercent) {
              lastPercent = percent;
              final elapsed = stopwatch.elapsed;
              final writtenBytes = (totalImageSize * percent / 100).round();
              final speedBytes = elapsed.inSeconds > 0 ? (writtenBytes / elapsed.inSeconds).round() : 0;

              _notify(onProgress, WtgProgress(
                step: WtgStep.applyingImage,
                message: 'wtg_svc_applying_percent',
                progress: percent / 100.0,
                writtenBytes: writtenBytes,
                totalBytes: totalImageSize,
                currentSpeedBytes: speedBytes,
                elapsedTime: elapsed,
              ));
            }
          }
        }
      });

      // Monitor target directory size - update every 750ms
      int monitorErrorCount = 0;
      int previousSize = 0;
      int previousElapsedMs = 0;
      final monitorTimer = Timer.periodic(const Duration(milliseconds: 750), (timer) {
        if (dismDone || _cancelled) {
          timer.cancel();
          return;
        }

        try {
          int totalSize = 0;
          int fileCount = 0;
          for (final f in targetDir.listSync(recursive: true)) {
            if (f is File) {
              totalSize += f.lengthSync();
              fileCount++;
            }
          }
          monitorErrorCount = 0; // Reset on success
          final elapsed = stopwatch.elapsed;
          final elapsedMs = elapsed.inMilliseconds;
          final elapsedDeltaMs = elapsedMs - previousElapsedMs;

          if (elapsedDeltaMs > 0) {
            final sizeDelta = totalSize - previousSize;
            final currentSpeed = (sizeDelta * 1000 / elapsedDeltaMs).round();

            _notify(onProgress, WtgProgress(
              step: WtgStep.applyingImage,
              message: 'wtg_svc_applying_percent',
              progress: lastPercent / 100.0,
              writtenBytes: totalSize,
              totalBytes: totalImageSize,
              currentSpeedBytes: currentSpeed,
              elapsedTime: elapsed,
            ));
          }

          previousSize = totalSize;
          previousElapsedMs = elapsedMs;
        } catch (e) {
          monitorErrorCount++;
          if (monitorErrorCount <= 3) {
            _logLine('Monitor error: $e');
          }
          // Stop monitoring after repeated errors
          if (monitorErrorCount > 3) {
            _logLine('Monitor: too many errors, stopping directory scan');
            timer.cancel();
          }
        }
      });

      // Wait for DISM
      int exitCode;
      try {
        exitCode = await process.exitCode.timeout(
          const Duration(minutes: 30),
          onTimeout: () {
            _logLine('DISM timeout!');
            process.kill(ProcessSignal.sigkill);
            return -1;
          },
        );
      } finally {
        dismDone = true;
        monitorTimer.cancel();
      }

      stopwatch.stop();
      _logLine('DISM exit: $exitCode');
      _logLine('Total: ${stopwatch.elapsed.inMinutes}m ${stopwatch.elapsed.inSeconds % 60}s');

      if (exitCode != 0) {
        _logLine('DISM FAILED');
        return false;
      }

      _notify(onProgress, WtgProgress(
        step: WtgStep.applyingImage,
        message: 'wtg_svc_image_applied',
        progress: 1.0,
        writtenBytes: totalImageSize,
        totalBytes: totalImageSize,
        elapsedTime: stopwatch.elapsed,
      ));

      return true;
    } catch (e) {
      _logLine('ERROR: $e');
      return false;
    }
  }

  Future<bool> _writeBootFiles({
    required String windowsDrive,
    required String efiDrive,
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

      // Run bcdboot
      _logLine('Running bcdboot ${windowsDrive}\\Windows /s $efiDrive /f ALL');
      final result = await Process.run('bcdboot', [
        '${windowsDrive}\\Windows',
        '/s', efiDrive,
        '/f', 'ALL',
      ]).timeout(const Duration(seconds: 120));

      _logLine('bcdboot exit: ${result.exitCode}');
      _logLine('bcdboot stdout: ${result.stdout}');

      if (result.exitCode != 0) {
        _logLine('bcdboot stderr: ${result.stderr}');
        _logLine('bcdboot FAILED with exit code ${result.exitCode}');
        return false;
      }

      _logLine('bcdboot completed successfully');
      return true;
    } on TimeoutException {
      _logLine('bcdboot timed out after 120 seconds');
      return false;
    } catch (e) {
      _logLine('Boot file error: $e');
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
  }) async {
    final errors = <String>[];
    final isMbrMode = windowsDrive == efiDrive;
    
    _logLine('Verification mode: ${isMbrMode ? "MBR" : "GPT"}');

    // Check Windows partition
    if (!await Directory('${windowsDrive}Windows').exists()) {
      errors.add('Windows directory missing');
    }

    // Check boot files
    final hasBootmgr = await File('${windowsDrive}bootmgr').exists();
    if (!hasBootmgr) {
      errors.add('bootmgr missing');
    }

    if (isMbrMode) {
      // MBR mode: check boot folder on Windows partition
      final hasBootDir = await Directory('${windowsDrive}Boot').exists() ||
                         await Directory('${windowsDrive}boot').exists();
      if (!hasBootDir) {
        _logLine('Note: Boot directory not found (may be created by bcdboot)');
      }
    } else {
      // GPT mode: check EFI partition
      if (!await Directory('${efiDrive}EFI').exists()) {
        errors.add('EFI directory missing');
      }
      
      // Check BCD
      final hasBcd = await File('${efiDrive}EFI\\Microsoft\\Boot\\BCD').exists();
      if (!hasBcd) {
        errors.add('BCD missing');
      }
    }

    if (errors.isNotEmpty) {
      _logLine('Verify issues: ${errors.join(', ')}');
      return false;
    }

    _logLine('Verification passed');
    return true;
  }
}
