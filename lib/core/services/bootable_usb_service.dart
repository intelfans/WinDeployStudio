import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'file_logger_service.dart';
import '../utils/file_utils.dart';
import '../../features/logs/services/log_center_service.dart';

enum BootMode { uefi, bios, both }

enum LinuxUsbKind { installMedia, toGo }

enum CreateStep {
  preparing,
  cleaningDisk,
  creatingPartitions,
  formatting,
  mountingIso,
  copyingFiles,
  splittingWim,
  writingBootFiles,
  verifying,
  complete,
  failed,
}

class CreateProgress {
  final CreateStep step;
  final double progress;
  final String message;
  final String? error;

  const CreateProgress({
    required this.step,
    this.progress = 0.0,
    this.message = '',
    this.error,
  });
}

typedef ProgressCallback = void Function(CreateProgress progress);

final bootableUsbServiceProvider = Provider<BootableUsbService>((ref) {
  return BootableUsbService(ref);
});

class BootableUsbService {
  final Ref ref;
  final List<String> _log = [];

  BootableUsbService(this.ref);

  void _logLine(String msg) {
    final line = '[${DateTime.now().toIso8601String()}] $msg';
    _log.add(line);
    debugPrint(line);
  }

  String get logText => _log.join('\n');

  Future<String> saveLogToFile() async {
    try {
      final dir = await getApplicationSupportDirectory();
      final logFile = File(p.join(dir.path, 'logs', 'last_creation_log.txt'));
      await logFile.parent.create(recursive: true);
      await logFile.writeAsString(logText);
      return logFile.path;
    } catch (e) {
      return 'Failed to save log: $e';
    }
  }

  Future<bool> createBootableUsb({
    required int diskNumber,
    required String isoPath,
    BootMode bootMode = BootMode.both,
    ProgressCallback? onProgress,
  }) async {
    _log.clear();
    _logLine('=== Create Windows Installation Media Start ===');
    _logLine('Disk: $diskNumber, ISO: $isoPath, Mode: $bootMode');

    final logCenter = LogCenterService();
    await logCenter.logUsb(
      'Windows 安装盘创建开始 | 磁盘: $diskNumber | ISO: $isoPath | 模式: $bootMode',
    );

    final logger = ref.read(fileLoggerServiceProvider);
    await logger.log(
      action: 'Create Install Media',
      target: 'Disk $diskNumber',
      result: 'Starting - ISO: $isoPath',
    );

    try {
      // Step 1: Prepare
      _notify(
        onProgress,
        const CreateProgress(
          step: CreateStep.preparing,
          message: 'boot_preparing',
          progress: 0.0,
        ),
      );

      _logLine('Using FAT32 boot media layout for $bootMode');

      // Step 2: Clean and partition disk
      _notify(
        onProgress,
        const CreateProgress(
          step: CreateStep.cleaningDisk,
          message: 'boot_cleaning',
          progress: 0.05,
        ),
      );

      final partitionResult = await _partitionDisk(
        diskNumber: diskNumber,
        bootMode: bootMode,
      );

      if (!partitionResult.success) {
        final errorDetail = partitionResult.error ?? '';
        _logLine('Partition FAILED: $errorDetail');
        final errorKey =
            errorDetail.contains('Access is denied') ||
                errorDetail.contains('denied') ||
                errorDetail.contains('0x80070005')
            ? 'boot_access_denied'
            : 'boot_partition_failed';
        final logPath = await saveLogToFile();
        _notify(
          onProgress,
          CreateProgress(
            step: CreateStep.failed,
            message: '$errorKey\n\nLog: $logPath',
            error: errorDetail,
          ),
        );
        return false;
      }

      final driveLetter = partitionResult.driveLetter;
      if (driveLetter == null) {
        _logLine('Partition succeeded but no drive letter assigned');
        return false;
      }
      _logLine('Partition OK, drive: $driveLetter');

      // Step 3: Format (already done by diskpart, just verify)
      _notify(
        onProgress,
        const CreateProgress(
          step: CreateStep.formatting,
          message: 'boot_format_verifying',
          progress: 0.15,
        ),
      );

      final formatResult = await _formatPartition(
        driveLetter: driveLetter,
        fileSystem: 'FAT32',
      );

      if (!formatResult) {
        _logLine('Format verification FAILED');
        final logPath = await saveLogToFile();
        _notify(
          onProgress,
          CreateProgress(
            step: CreateStep.failed,
            message: 'boot_format_failed\n\nLog: $logPath',
          ),
        );
        return false;
      }
      _logLine('Format verified');

      // Step 4: Mount ISO
      _notify(
        onProgress,
        const CreateProgress(
          step: CreateStep.mountingIso,
          message: 'boot_mounting',
          progress: 0.20,
        ),
      );

      final mountPoint = await _mountIso(isoPath);
      if (mountPoint == null) {
        _logLine('Mount ISO FAILED');
        final logPath = await saveLogToFile();
        _notify(
          onProgress,
          CreateProgress(
            step: CreateStep.failed,
            message: 'boot_mount_failed\n$isoPath\n\nLog: $logPath',
          ),
        );
        return false;
      }
      _logLine('Mounted at: $mountPoint');

      // Step 5: Check if we need to split install.wim (>4GB FAT32 limit)
      final installWim = p.join(mountPoint, 'sources', 'install.wim');
      final installEsd = p.join(mountPoint, 'sources', 'install.esd');
      final hasWim = await File(installWim).exists();
      final hasEsd = await File(installEsd).exists();

      bool needSplit = false;
      String wimSource = '';

      if (hasWim) {
        wimSource = installWim;
        final wimSize = await File(installWim).length();
        if (wimSize > 4 * 1024 * 1024 * 1024) {
          needSplit = true;
          _logLine('install.wim > 4GB, will split');
        }
      } else if (hasEsd) {
        wimSource = installEsd;
        final esdSize = await File(installEsd).length();
        if (esdSize > 4 * 1024 * 1024 * 1024) {
          needSplit = true;
          _logLine('install.esd > 4GB, will split');
        }
      }

      // Step 6: Copy files with robocopy (fast)
      _notify(
        onProgress,
        const CreateProgress(
          step: CreateStep.copyingFiles,
          message: 'boot_copying_fast',
          progress: 0.25,
        ),
      );

      final copyResult = await _copyIsoContents(
        mountPoint: mountPoint,
        targetDrive: driveLetter,
        excludeWim: needSplit,
        onProgress: (progress) {
          _notify(
            onProgress,
            CreateProgress(
              step: CreateStep.copyingFiles,
              message: progress < 1.0
                  ? 'boot_copying_fast'
                  : 'boot_copy_complete',
              progress: 0.25 + progress * 0.45,
            ),
          );
        },
      );

      if (!copyResult) {
        _logLine('File copy FAILED');
        await _unmountIso(isoPath);
        final logPath = await saveLogToFile();
        _notify(
          onProgress,
          CreateProgress(
            step: CreateStep.failed,
            message: 'boot_copy_failed\n\nLog: $logPath',
          ),
        );
        return false;
      }
      _logLine('File copy OK');

      // Step 7: Split WIM if needed
      if (needSplit && wimSource.isNotEmpty) {
        _notify(
          onProgress,
          const CreateProgress(
            step: CreateStep.splittingWim,
            message: 'boot_splitting_wim',
            progress: 0.70,
          ),
        );

        final splitResult = await _splitWim(
          sourcePath: wimSource,
          targetDir: '$driveLetter\\sources',
        );

        if (!splitResult) {
          _logLine('WIM split FAILED');
          await _unmountIso(isoPath);
          final logPath = await saveLogToFile();
          _notify(
            onProgress,
            CreateProgress(
              step: CreateStep.failed,
              message: 'boot_split_failed\n\nLog: $logPath',
            ),
          );
          return false;
        }
        _logLine('WIM split OK');
      }

      // Step 8: Write boot files
      _notify(
        onProgress,
        const CreateProgress(
          step: CreateStep.writingBootFiles,
          message: 'boot_writing_boot',
          progress: 0.80,
        ),
      );

      final bootResult = await _writeBootFiles(
        windowsDrive: mountPoint.endsWith('\\') ? mountPoint : '$mountPoint\\',
        targetDrive: driveLetter,
        bootMode: bootMode,
      );

      await _unmountIso(isoPath);

      if (!bootResult) {
        _logLine('Boot file write FAILED');
        final logPath = await saveLogToFile();
        _notify(
          onProgress,
          CreateProgress(
            step: CreateStep.failed,
            message: 'boot_write_failed\n\nLog: $logPath',
          ),
        );
        return false;
      }
      _logLine('Boot files OK');

      // Step 8.5: Set volume icon
      _notify(
        onProgress,
        const CreateProgress(
          step: CreateStep.writingBootFiles,
          message: 'boot_setting_icon',
          progress: 0.85,
        ),
      );
      await _setVolumeIcon(driveLetter);

      // Step 9: Verify
      _notify(
        onProgress,
        const CreateProgress(
          step: CreateStep.verifying,
          message: 'boot_verifying',
          progress: 0.90,
        ),
      );

      final verifyResult = await _verifyBootableUsb(
        driveLetter: driveLetter,
        bootMode: bootMode,
      );
      _logLine('Verify: ${verifyResult ? "OK" : "FAILED"}');

      _notify(
        onProgress,
        CreateProgress(
          step: verifyResult ? CreateStep.complete : CreateStep.failed,
          message: verifyResult ? 'boot_complete' : 'boot_verify_failed',
          progress: verifyResult ? 1.0 : 0.0,
        ),
      );

      await logger.log(
        action: 'Create Install Media',
        target: 'Disk $diskNumber',
        result: verifyResult ? 'Success - Verified' : 'Failed - Verification',
        level: verifyResult ? LogLevel.success : LogLevel.error,
      );

      final logPath = await saveLogToFile();
      _logLine('Log saved to: $logPath');

      if (verifyResult) {
        await logCenter.logUsb('Windows 安装盘创建成功 | 磁盘: $diskNumber');
      } else {
        await logCenter.logError('Windows 安装盘验证失败 | 磁盘: $diskNumber');
      }

      return verifyResult;
    } catch (e) {
      _logLine('EXCEPTION: $e');
      final logPath = await saveLogToFile();
      await logCenter.logError('Windows 安装盘创建异常 | 磁盘: $diskNumber | 错误: $e');
      _notify(
        onProgress,
        CreateProgress(
          step: CreateStep.failed,
          message: 'creator_error\n$e\n\nLog: $logPath',
        ),
      );
      await logger.log(
        action: 'Create Install Media',
        target: 'Disk $diskNumber',
        result: 'Exception: $e',
        level: LogLevel.error,
      );
      return false;
    }
  }

  Future<bool> createLinuxIsoUsb({
    required int diskNumber,
    required String isoPath,
    required LinuxUsbKind kind,
    ProgressCallback? onProgress,
  }) async {
    _log.clear();
    final modeName = kind == LinuxUsbKind.toGo
        ? 'Linux To Go'
        : 'Linux Installation Media';
    _logLine('=== Create $modeName Start ===');
    _logLine('Disk: $diskNumber, ISO: $isoPath');

    final logCenter = LogCenterService();
    await logCenter.logUsb('$modeName 创建开始 | 磁盘: $diskNumber | ISO: $isoPath');

    final logger = ref.read(fileLoggerServiceProvider);
    await logger.log(
      action: 'Create $modeName',
      target: 'Disk $diskNumber',
      result: 'Starting - ISO: $isoPath',
    );

    try {
      _notify(
        onProgress,
        const CreateProgress(
          step: CreateStep.preparing,
          message: 'linux_preparing',
          progress: 0.0,
        ),
      );

      if (!await File(isoPath).exists()) {
        _logLine('ISO not found: $isoPath');
        final logPath = await saveLogToFile();
        _notify(
          onProgress,
          CreateProgress(
            step: CreateStep.failed,
            message: 'linux_iso_not_found\n$isoPath\n\nLog: $logPath',
          ),
        );
        return false;
      }

      if (kind == LinuxUsbKind.toGo) {
        final result = await _createPersistentLinuxToGo(
          diskNumber: diskNumber,
          isoPath: isoPath,
          onProgress: onProgress,
        );

        _notify(
          onProgress,
          CreateProgress(
            step: result.success ? CreateStep.complete : CreateStep.failed,
            message: result.success
                ? 'linux_complete'
                : 'linux_write_failed\n${result.error ?? "Unknown error"}',
            progress: result.success ? 1.0 : 0.0,
            error: result.error,
          ),
        );

        await logger.log(
          action: 'Create $modeName',
          target: 'Disk $diskNumber',
          result: result.success
              ? 'Success - Persistent Linux To Go'
              : 'Failed: ${result.error ?? "Unknown error"}',
          level: result.success ? LogLevel.success : LogLevel.error,
        );

        if (result.success) {
          await logCenter.logUsb('$modeName 创建成功 | 磁盘: $diskNumber');
        } else {
          await logCenter.logError(
            '$modeName 创建失败 | 磁盘: $diskNumber | 错误: ${result.error ?? "Unknown"}',
          );
        }

        final logPath = await saveLogToFile();
        _logLine('Log saved to: $logPath');
        return result.success;
      }

      _notify(
        onProgress,
        const CreateProgress(
          step: CreateStep.cleaningDisk,
          message: 'linux_locking_disk',
          progress: 0.05,
        ),
      );

      final result = await _writeIsoHybridRaw(
        diskNumber: diskNumber,
        isoPath: isoPath,
        onProgress: (rawProgress) {
          _notify(
            onProgress,
            CreateProgress(
              step: CreateStep.copyingFiles,
              message: 'linux_writing_image',
              progress: 0.08 + rawProgress * 0.87,
            ),
          );
        },
      );

      if (!result.success) {
        final errorDetail = result.error ?? 'Unknown error';
        final errorKey =
            errorDetail.contains('Access is denied') ||
                errorDetail.contains('拒绝访问') ||
                errorDetail.contains('UnauthorizedAccess')
            ? 'linux_access_denied'
            : 'linux_write_failed';
        _logLine('Linux raw write FAILED: $errorDetail');
        final logPath = await saveLogToFile();
        _notify(
          onProgress,
          CreateProgress(
            step: CreateStep.failed,
            message: '$errorKey\n$errorDetail\n\nLog: $logPath',
            error: errorDetail,
          ),
        );
        await logger.log(
          action: 'Create $modeName',
          target: 'Disk $diskNumber',
          result: 'Failed: $errorDetail',
          level: LogLevel.error,
        );
        await logCenter.logError(
          '$modeName 创建失败 | 磁盘: $diskNumber | 错误: $errorDetail',
        );
        return false;
      }

      _notify(
        onProgress,
        const CreateProgress(
          step: CreateStep.verifying,
          message: 'linux_finalizing',
          progress: 0.96,
        ),
      );

      final verifyResult = await _verifyLinuxRawWrite(
        diskNumber: diskNumber,
        isoPath: isoPath,
      );
      _logLine('Linux verify: ${verifyResult ? "OK" : "FAILED"}');

      _notify(
        onProgress,
        CreateProgress(
          step: verifyResult ? CreateStep.complete : CreateStep.failed,
          message: verifyResult ? 'linux_complete' : 'linux_verify_failed',
          progress: verifyResult ? 1.0 : 0.0,
        ),
      );

      await logger.log(
        action: 'Create $modeName',
        target: 'Disk $diskNumber',
        result: verifyResult ? 'Success - Raw ISOHybrid write' : 'Failed',
        level: verifyResult ? LogLevel.success : LogLevel.error,
      );

      if (verifyResult) {
        await logCenter.logUsb('$modeName 创建成功 | 磁盘: $diskNumber');
      } else {
        await logCenter.logError('$modeName 验证失败 | 磁盘: $diskNumber');
      }

      final logPath = await saveLogToFile();
      _logLine('Log saved to: $logPath');
      return verifyResult;
    } catch (e) {
      _logLine('Linux creation EXCEPTION: $e');
      final logPath = await saveLogToFile();
      await logCenter.logError('$modeName 创建异常 | 磁盘: $diskNumber | 错误: $e');
      _notify(
        onProgress,
        CreateProgress(
          step: CreateStep.failed,
          message: 'creator_error\n$e\n\nLog: $logPath',
        ),
      );
      await logger.log(
        action: 'Create $modeName',
        target: 'Disk $diskNumber',
        result: 'Exception: $e',
        level: LogLevel.error,
      );
      return false;
    }
  }

  Future<_LinuxRawWriteResult> _createPersistentLinuxToGo({
    required int diskNumber,
    required String isoPath,
    ProgressCallback? onProgress,
  }) async {
    const int mib = 1024 * 1024;

    try {
      final isoBytes = await File(isoPath).length();
      final diskBytes = await _getDiskSizeBytes(diskNumber);
      if (diskBytes == null) {
        return const _LinuxRawWriteResult(
          success: false,
          error: 'Unable to read target disk size.',
        );
      }

      final diskSizeMb = diskBytes ~/ mib;
      final isoSizeMb = (isoBytes + mib - 1) ~/ mib;
      final partitionSizeMb = _minInt(diskSizeMb - 16, 32760);
      final persistenceSizeMb = _minInt(
        4095,
        partitionSizeMb - isoSizeMb - 512,
      );

      if (partitionSizeMb <= isoSizeMb + 512 || persistenceSizeMb < 512) {
        return _LinuxRawWriteResult(
          success: false,
          error:
              'The target disk is too small for Linux To Go persistence. Need ISO size plus at least 512 MB free space.',
        );
      }

      _logLine(
        'Linux To Go layout: disk=${diskSizeMb}MB, boot=${partitionSizeMb}MB, persistence=${persistenceSizeMb}MB',
      );

      _notify(
        onProgress,
        const CreateProgress(
          step: CreateStep.cleaningDisk,
          message: 'linux_locking_disk',
          progress: 0.05,
        ),
      );

      final partitionResult = await _partitionLinuxToGoDisk(
        diskNumber: diskNumber,
        partitionSizeMb: partitionSizeMb,
      );
      if (!partitionResult.success || partitionResult.driveLetter == null) {
        return _LinuxRawWriteResult(
          success: false,
          error: partitionResult.error ?? 'Failed to partition target disk.',
        );
      }

      final targetDrive = partitionResult.driveLetter!;
      _logLine('Linux To Go boot partition: $targetDrive');

      _notify(
        onProgress,
        const CreateProgress(
          step: CreateStep.formatting,
          message: 'boot_format_verifying',
          progress: 0.12,
        ),
      );

      final formatOk = await _formatPartition(
        driveLetter: targetDrive,
        fileSystem: 'FAT32',
      );
      if (!formatOk) {
        return const _LinuxRawWriteResult(
          success: false,
          error: 'Linux To Go boot partition was not formatted as FAT32.',
        );
      }

      _notify(
        onProgress,
        const CreateProgress(
          step: CreateStep.mountingIso,
          message: 'boot_mounting',
          progress: 0.18,
        ),
      );

      final mountPoint = await _mountIso(isoPath);
      if (mountPoint == null) {
        return _LinuxRawWriteResult(
          success: false,
          error: 'Failed to mount Linux ISO: $isoPath',
        );
      }

      try {
        _notify(
          onProgress,
          const CreateProgress(
            step: CreateStep.copyingFiles,
            message: 'step_copying',
            progress: 0.24,
          ),
        );

        final copyOk = await _copyIsoContents(
          mountPoint: mountPoint,
          targetDrive: targetDrive,
          excludeWim: false,
          onProgress: (progress) {
            _notify(
              onProgress,
              CreateProgress(
                step: CreateStep.copyingFiles,
                message: 'step_copying',
                progress: 0.24 + progress * 0.44,
              ),
            );
          },
        );

        if (!copyOk) {
          return const _LinuxRawWriteResult(
            success: false,
            error: 'Failed to copy Linux ISO files to the target disk.',
          );
        }
      } finally {
        await _unmountIso(isoPath);
      }

      _notify(
        onProgress,
        const CreateProgress(
          step: CreateStep.writingBootFiles,
          message: 'linux_finalizing',
          progress: 0.72,
        ),
      );

      final bootPatched = await _patchLinuxPersistenceBootConfigs(targetDrive);
      if (!bootPatched) {
        return const _LinuxRawWriteResult(
          success: false,
          error:
              'Failed to enable Linux persistence in GRUB boot configuration.',
        );
      }

      _notify(
        onProgress,
        const CreateProgress(
          step: CreateStep.copyingFiles,
          message: 'linux_finalizing',
          progress: 0.78,
        ),
      );

      final persistenceResult = await _createPersistenceImage(
        targetDrive: targetDrive,
        sizeMb: persistenceSizeMb,
      );
      if (!persistenceResult.success) {
        return persistenceResult;
      }

      _notify(
        onProgress,
        const CreateProgress(
          step: CreateStep.verifying,
          message: 'linux_finalizing',
          progress: 0.96,
        ),
      );

      final verified = await _verifyLinuxToGoLayout(targetDrive);
      if (!verified) {
        return const _LinuxRawWriteResult(
          success: false,
          error: 'Linux To Go persistence layout verification failed.',
        );
      }

      _logLine('Linux To Go verify: OK');
      return const _LinuxRawWriteResult(success: true);
    } catch (e) {
      _logLine('Linux To Go creation error: $e');
      return _LinuxRawWriteResult(success: false, error: e.toString());
    }
  }

  Future<int?> _getDiskSizeBytes(int diskNumber) async {
    try {
      final result = await Process.run('powershell', [
        '-NoProfile',
        '-ExecutionPolicy',
        'Bypass',
        '-Command',
        '(Get-Disk -Number $diskNumber -ErrorAction Stop).Size',
      ]).timeout(const Duration(seconds: 10));

      if (result.exitCode != 0) {
        _logLine('Get-Disk size failed: ${result.stderr}');
        return null;
      }

      return int.tryParse(result.stdout.toString().trim());
    } catch (e) {
      _logLine('Get-Disk size error: $e');
      return null;
    }
  }

  int _minInt(int a, int b) => a < b ? a : b;

  Future<_DiskPartResult> _partitionLinuxToGoDisk({
    required int diskNumber,
    required int partitionSizeMb,
  }) async {
    final script =
        '''
select disk $diskNumber
clean
convert mbr
create partition primary size=$partitionSizeMb
active
format fs=fat32 label="WDS_LTG" quick
assign
exit
''';
    _logLine('Linux To Go DiskPart script:\n$script');

    final result = await _runDiskpart(script);
    _logLine('Linux To Go DiskPart exit: ${result.exitCode}');

    if (result.exitCode != 0) {
      final stderr = result.stderr.toString();
      final stdout = result.stdout.toString();
      _logLine('Linux To Go DiskPart stderr: $stderr');
      _logLine('Linux To Go DiskPart stdout: $stdout');
      return _DiskPartResult(
        success: false,
        error: stderr.isNotEmpty ? stderr : stdout,
      );
    }

    final driveLetter = await _findDriveLetterForDisk(diskNumber);
    if (driveLetter == null) {
      return const _DiskPartResult(
        success: false,
        error: 'Could not find Linux To Go boot partition drive letter.',
      );
    }

    return _DiskPartResult(success: true, driveLetter: driveLetter);
  }

  Future<bool> _patchLinuxPersistenceBootConfigs(String targetDrive) async {
    final root = targetDrive.endsWith(r'\') ? targetDrive : '$targetDrive\\';
    final configFiles = <File>[
      File(p.join(root, 'boot', 'grub', 'grub.cfg')),
      File(p.join(root, 'boot', 'grub', 'loopback.cfg')),
    ];

    var foundBootConfig = false;
    var foundCasperEntry = false;

    for (final file in configFiles) {
      if (!await file.exists()) continue;
      foundBootConfig = true;

      await Process.run('attrib', ['-R', file.path]).timeout(
        const Duration(seconds: 10),
        onTimeout: () => ProcessResult(0, -1, '', 'attrib timeout'),
      );

      final original = await file.readAsString();
      final newline = original.contains('\r\n') ? '\r\n' : '\n';
      final lines = original.replaceAll('\r\n', '\n').split('\n');
      var changed = false;

      final updatedLines = lines
          .map((line) {
            final isLinuxLine = RegExp(
              r'^\s*linux(efi)?\s+',
              caseSensitive: false,
            ).hasMatch(line);
            if (!isLinuxLine || !line.contains('/casper/vmlinuz')) {
              return line;
            }

            foundCasperEntry = true;
            if (RegExp(r'(^|\s)persistent(\s|$)').hasMatch(line)) {
              return line;
            }

            changed = true;
            final markerIndex = line.indexOf(' ---');
            if (markerIndex >= 0) {
              return '${line.substring(0, markerIndex)} persistent${line.substring(markerIndex)}';
            }
            return '$line persistent';
          })
          .join('\n');

      if (changed) {
        await file.writeAsString(updatedLines.replaceAll('\n', newline));
        _logLine('Patched persistence boot config: ${file.path}');
      } else {
        _logLine('Persistence boot config already patched: ${file.path}');
      }
    }

    return foundBootConfig && foundCasperEntry;
  }

  Future<_LinuxRawWriteResult> _createPersistenceImage({
    required String targetDrive,
    required int sizeMb,
  }) async {
    final mke2fs = await _findMke2fs();
    if (mke2fs == null) {
      return const _LinuxRawWriteResult(
        success: false,
        error:
            'Bundled mke2fs.exe was not found. Linux To Go persistence requires mke2fs to create an ext4 writable image.',
      );
    }

    final root = targetDrive.endsWith(r'\') ? targetDrive : '$targetDrive\\';
    final image = File(p.join(root, 'writable'));
    _logLine('Creating Linux persistence image: ${image.path}, ${sizeMb}MB');

    if (await image.exists()) {
      await image.delete();
    }

    final raf = await image.open(mode: FileMode.write);
    try {
      await raf.truncate(sizeMb * 1024 * 1024);
    } finally {
      await raf.close();
    }

    final result = await Process.run(mke2fs, [
      '-t',
      'ext4',
      '-F',
      '-L',
      'writable',
      image.path,
    ]).timeout(const Duration(minutes: 5));

    _logLine('mke2fs exit: ${result.exitCode}');
    if (result.stdout.toString().trim().isNotEmpty) {
      _logLine('mke2fs stdout: ${result.stdout}');
    }
    if (result.stderr.toString().trim().isNotEmpty) {
      _logLine('mke2fs stderr: ${result.stderr}');
    }

    if (result.exitCode != 0) {
      return _LinuxRawWriteResult(
        success: false,
        error: result.stderr.toString().trim().isNotEmpty
            ? result.stderr.toString().trim()
            : 'mke2fs failed with exit code ${result.exitCode}.',
      );
    }

    return const _LinuxRawWriteResult(success: true);
  }

  Future<String?> _findMke2fs() async {
    final candidates = <String>[];

    final executableDir = File(Platform.resolvedExecutable).parent.path;
    final currentDir = Directory.current.path;
    candidates.addAll([
      p.join(executableDir, 'tools', 'e2fsprogs', 'mke2fs.exe'),
      p.join(executableDir, 'tools', 'mke2fs.exe'),
      p.join(executableDir, 'data', 'tools', 'e2fsprogs', 'mke2fs.exe'),
      p.join(executableDir, 'data', 'tools', 'mke2fs.exe'),
      p.join(currentDir, 'tools', 'e2fsprogs', 'mke2fs.exe'),
      p.join(currentDir, 'tools', 'mke2fs.exe'),
    ]);

    for (final name in const ['mke2fs.exe', 'mke2fs']) {
      try {
        final result = await Process.run('where.exe', [
          name,
        ]).timeout(const Duration(seconds: 5));
        if (result.exitCode == 0) {
          candidates.addAll(
            result.stdout
                .toString()
                .split(RegExp(r'\r?\n'))
                .map((line) => line.trim())
                .where((line) => line.isNotEmpty),
          );
        }
      } catch (_) {}
    }

    for (final candidate in candidates) {
      if (candidate.isEmpty) continue;
      if (await File(candidate).exists()) {
        _logLine('Using mke2fs: $candidate');
        return candidate;
      }
    }

    _logLine('mke2fs not found');
    return null;
  }

  Future<bool> _verifyLinuxToGoLayout(String targetDrive) async {
    try {
      final root = targetDrive.endsWith(r'\') ? targetDrive : '$targetDrive\\';
      final bootx64 = File(p.join(root, 'EFI', 'BOOT', 'BOOTx64.EFI'));
      final grub = File(p.join(root, 'boot', 'grub', 'grub.cfg'));
      final writable = File(p.join(root, 'writable'));

      if (!await bootx64.exists()) {
        _logLine('Linux To Go verify failed: BOOTx64.EFI missing');
        return false;
      }
      if (!await grub.exists()) {
        _logLine('Linux To Go verify failed: grub.cfg missing');
        return false;
      }

      final grubText = await grub.readAsString();
      if (!RegExp(r'(^|\s)persistent(\s|$)').hasMatch(grubText)) {
        _logLine('Linux To Go verify failed: persistent boot arg missing');
        return false;
      }

      if (!await writable.exists() ||
          await writable.length() < 16 * 1024 * 1024) {
        _logLine('Linux To Go verify failed: writable image missing');
        return false;
      }

      final raf = await writable.open();
      try {
        await raf.setPosition(1080);
        final magic = await raf.read(2);
        if (magic.length != 2 || magic[0] != 0x53 || magic[1] != 0xEF) {
          _logLine('Linux To Go verify failed: ext4 magic missing');
          return false;
        }
      } finally {
        await raf.close();
      }

      return true;
    } catch (e) {
      _logLine('Linux To Go verify error: $e');
      return false;
    }
  }

  Future<_LinuxRawWriteResult> _writeIsoHybridRaw({
    required int diskNumber,
    required String isoPath,
    required void Function(double progress) onProgress,
  }) async {
    final tempDir = await FileUtils.getTempDirectory();
    final scriptFile = File(p.join(tempDir, 'wds_linux_raw_write.ps1'));
    await scriptFile.writeAsString(_linuxRawWriteScript);

    final process = await Process.start('powershell', [
      '-NoProfile',
      '-ExecutionPolicy',
      'Bypass',
      '-File',
      scriptFile.path,
      '-DiskNumber',
      '$diskNumber',
      '-IsoPath',
      isoPath,
    ]);

    final stdoutLines = process.stdout
        .transform(const SystemEncoding().decoder)
        .transform(const LineSplitter());
    final stderrText = StringBuffer();

    final stderrFuture = process.stderr
        .transform(const SystemEncoding().decoder)
        .listen((chunk) {
          stderrText.write(chunk);
          if (chunk.trim().isNotEmpty) {
            _logLine('Linux raw stderr: ${chunk.trim()}');
          }
        })
        .asFuture<void>();

    await for (final line in stdoutLines) {
      final cleanLine = line.trim();
      if (cleanLine.isEmpty) continue;
      _logLine('Linux raw stdout: $cleanLine');
      if (cleanLine.startsWith('WDS_PROGRESS:')) {
        final parts = cleanLine.split(':');
        if (parts.length >= 2) {
          final percent = int.tryParse(parts[1]) ?? 0;
          onProgress((percent.clamp(0, 100)) / 100.0);
        }
      }
    }

    final exitCode = await process.exitCode;
    await stderrFuture.catchError((_) {});
    await scriptFile.delete().catchError((_) => scriptFile);

    if (exitCode != 0) {
      return _LinuxRawWriteResult(
        success: false,
        error: stderrText.toString().trim().isNotEmpty
            ? stderrText.toString().trim()
            : 'PowerShell exited with code $exitCode',
      );
    }

    return const _LinuxRawWriteResult(success: true);
  }

  Future<bool> _verifyLinuxRawWrite({
    required int diskNumber,
    required String isoPath,
  }) async {
    final tempDir = await FileUtils.getTempDirectory();
    final scriptFile = File(p.join(tempDir, 'wds_linux_verify_raw_write.ps1'));

    try {
      await scriptFile.writeAsString(_linuxRawVerifyScript);

      final result = await Process.run('powershell', [
        '-NoProfile',
        '-ExecutionPolicy',
        'Bypass',
        '-File',
        scriptFile.path,
        '-DiskNumber',
        '$diskNumber',
        '-IsoPath',
        isoPath,
      ]).timeout(const Duration(seconds: 15));
      if (result.exitCode != 0) {
        _logLine('Verify command failed: ${result.stderr}');
        return false;
      }
      return result.stdout.toString().contains('OK');
    } catch (e) {
      _logLine('Verify command exception: $e');
      return false;
    } finally {
      await scriptFile.delete().catchError((_) => scriptFile);
    }
  }

  static const String _linuxRawWriteScript = r'''
param(
  [Parameter(Mandatory = $true)][int]$DiskNumber,
  [Parameter(Mandatory = $true)][string]$IsoPath
)

$ErrorActionPreference = 'Stop'

function Emit-Progress([int]$Percent, [int64]$Written, [int64]$Total) {
  Write-Output ("WDS_PROGRESS:{0}:{1}:{2}" -f $Percent, $Written, $Total)
}

if (-not (Test-Path -LiteralPath $IsoPath -PathType Leaf)) {
  throw "ISO file not found: $IsoPath"
}

$disk = Get-Disk -Number $DiskNumber -ErrorAction Stop
if ($disk.IsSystem -or $disk.IsBoot) {
  throw "Refusing to write to a system or boot disk."
}

if ($disk.IsOffline) {
  Set-Disk -Number $DiskNumber -IsOffline $false -ErrorAction SilentlyContinue
}
if ($disk.IsReadOnly) {
  Set-Disk -Number $DiskNumber -IsReadOnly $false -ErrorAction SilentlyContinue
}

$driveLetters = @(
  Get-Partition -DiskNumber $DiskNumber -ErrorAction SilentlyContinue |
    Where-Object { $_.DriveLetter } |
    Select-Object -ExpandProperty DriveLetter
)

foreach ($letter in $driveLetters) {
  if ($null -ne $letter -and "$letter".Length -gt 0) {
    $drive = ("{0}:" -f $letter)
    & "$env:SystemRoot\System32\mountvol.exe" $drive /D 2>$null | Out-Null
  }
}

Clear-Disk -Number $DiskNumber -RemoveData -RemoveOEM -Confirm:$false -ErrorAction Stop
Start-Sleep -Milliseconds 700

$source = [System.IO.File]::Open(
  $IsoPath,
  [System.IO.FileMode]::Open,
  [System.IO.FileAccess]::Read,
  [System.IO.FileShare]::Read
)

$targetPath = "\\.\PhysicalDrive$DiskNumber"
$target = [System.IO.File]::Open(
  $targetPath,
  [System.IO.FileMode]::Open,
  [System.IO.FileAccess]::ReadWrite,
  [System.IO.FileShare]::ReadWrite
)

try {
  $buffer = New-Object byte[] 4194304
  $total = $source.Length
  $written = [int64]0
  $lastPercent = -1
  Emit-Progress 0 0 $total

  while (($read = $source.Read($buffer, 0, $buffer.Length)) -gt 0) {
    $target.Write($buffer, 0, $read)
    $written += $read
    $percent = [int][Math]::Floor(($written * 100.0) / $total)
    if ($percent -ne $lastPercent) {
      Emit-Progress $percent $written $total
      $lastPercent = $percent
    }
  }

  $target.Flush($true)
  Emit-Progress 100 $written $total
} finally {
  $target.Dispose()
  $source.Dispose()
}

Update-Disk -Number $DiskNumber -ErrorAction SilentlyContinue | Out-Null
Write-Output "WDS_DONE"
''';

  static const String _linuxRawVerifyScript = r'''
param(
  [Parameter(Mandatory = $true)][int]$DiskNumber,
  [Parameter(Mandatory = $true)][string]$IsoPath
)

$ErrorActionPreference = 'Stop'

function Read-Bytes([System.IO.Stream]$Stream, [int64]$Offset, [int]$Length) {
  $buffer = New-Object byte[] $Length
  $Stream.Seek($Offset, [System.IO.SeekOrigin]::Begin) | Out-Null
  $read = $Stream.Read($buffer, 0, $Length)
  if ($read -ne $Length) {
    throw "Short read at offset $Offset."
  }
  return $buffer
}

function Get-HexRange([byte[]]$Bytes, [int]$Offset, [int]$Length) {
  $builder = New-Object System.Text.StringBuilder
  for ($i = 0; $i -lt $Length; $i++) {
    [void]$builder.AppendFormat("{0:X2}", $Bytes[$Offset + $i])
  }
  return $builder.ToString()
}

function Test-ZeroEntry([byte[]]$Entry) {
  foreach ($byte in $Entry) {
    if ($byte -ne 0) {
      return $false
    }
  }
  return $true
}

function Read-GptLayout([System.IO.Stream]$Stream) {
  $header = Read-Bytes $Stream 512 92
  $magic = [System.Text.Encoding]::ASCII.GetString($header, 0, 8)
  if ($magic -ne 'EFI PART') {
    return @()
  }

  $entryLba = [BitConverter]::ToUInt64($header, 72)
  $entryCount = [BitConverter]::ToUInt32($header, 80)
  $entrySize = [BitConverter]::ToUInt32($header, 84)

  if ($entrySize -lt 56 -or $entrySize -gt 4096 -or $entryCount -gt 1024) {
    throw "Invalid GPT entry table."
  }

  $entries = @()
  for ($index = 0; $index -lt $entryCount; $index++) {
    $entryOffset = ([int64]$entryLba * 512) + ([int64]$index * $entrySize)
    $entry = Read-Bytes $Stream $entryOffset $entrySize
    if (Test-ZeroEntry $entry) {
      continue
    }

    $entries += [PSCustomObject]@{
      TypeHex = Get-HexRange $entry 0 16
      FirstLba = [BitConverter]::ToUInt64($entry, 32)
      LastLba = [BitConverter]::ToUInt64($entry, 40)
    }
  }

  return $entries
}

function Compare-Block(
  [System.IO.Stream]$Source,
  [System.IO.Stream]$Target,
  [int64]$Offset,
  [int]$Length
) {
  $sourceBytes = Read-Bytes $Source $Offset $Length
  $targetBytes = Read-Bytes $Target $Offset $Length
  for ($i = 0; $i -lt $Length; $i++) {
    if ($sourceBytes[$i] -ne $targetBytes[$i]) {
      throw "Verification mismatch at offset $($Offset + $i)."
    }
  }
}

if (-not (Test-Path -LiteralPath $IsoPath -PathType Leaf)) {
  throw "ISO file not found: $IsoPath"
}

$isoItem = Get-Item -LiteralPath $IsoPath -ErrorAction Stop
$isoLength = [int64]$isoItem.Length
if ($isoLength -le 0) {
  throw "ISO file is empty."
}

$targetDisk = Get-Disk -Number $DiskNumber -ErrorAction Stop
if ([int64]$targetDisk.Size -lt $isoLength) {
  throw "Target disk is smaller than the ISO image."
}

$source = [System.IO.File]::Open(
  $IsoPath,
  [System.IO.FileMode]::Open,
  [System.IO.FileAccess]::Read,
  [System.IO.FileShare]::Read
)

$targetPath = "\\.\PhysicalDrive$DiskNumber"
$target = [System.IO.File]::Open(
  $targetPath,
  [System.IO.FileMode]::Open,
  [System.IO.FileAccess]::Read,
  [System.IO.FileShare]::ReadWrite
)

try {
  $diskMbr = Read-Bytes $target 0 512
  if ($diskMbr[510] -ne 0x55 -or $diskMbr[511] -ne 0xAA) {
    throw "Target disk has no valid boot signature."
  }

  $isoLayout = @(Read-GptLayout $source)
  $diskLayout = @(Read-GptLayout $target)
  if ($isoLayout.Count -gt 0) {
    if ($diskLayout.Count -lt $isoLayout.Count) {
      throw "Target GPT partition count does not match the ISO image."
    }

    for ($i = 0; $i -lt $isoLayout.Count; $i++) {
      if (
        $isoLayout[$i].TypeHex -ne $diskLayout[$i].TypeHex -or
        $isoLayout[$i].FirstLba -ne $diskLayout[$i].FirstLba -or
        $isoLayout[$i].LastLba -ne $diskLayout[$i].LastLba
      ) {
        throw "Target GPT partition layout does not match the ISO image."
      }
    }
  }

  $sourcePvd = Read-Bytes $source 32768 6
  $sourcePvdMagic = [System.Text.Encoding]::ASCII.GetString($sourcePvd, 1, 5)
  if ($sourcePvdMagic -eq 'CD001') {
    $targetPvd = Read-Bytes $target 32768 6
    $targetPvdMagic = [System.Text.Encoding]::ASCII.GetString($targetPvd, 1, 5)
    if ($targetPvdMagic -ne 'CD001') {
      throw "Target disk is missing the ISO9660 signature."
    }
  }

  $blockLength = 4096
  $sampleOffsets = New-Object System.Collections.Generic.List[Int64]
  $sampleOffsets.Add([int64]1048576) | Out-Null
  $sampleOffsets.Add([int64][Math]::Floor($isoLength * 0.25)) | Out-Null
  $sampleOffsets.Add([int64][Math]::Floor($isoLength * 0.50)) | Out-Null
  $sampleOffsets.Add([int64][Math]::Floor($isoLength * 0.75)) | Out-Null

  $checked = New-Object System.Collections.Generic.HashSet[Int64]
  foreach ($offset in $sampleOffsets) {
    $alignedOffset = [int64]([Math]::Floor($offset / 4096) * 4096)
    if (
      $alignedOffset -ge 1048576 -and
      ($alignedOffset + $blockLength) -lt ($isoLength - 16777216) -and
      $checked.Add($alignedOffset)
    ) {
      Compare-Block $source $target $alignedOffset $blockLength
    }
  }

  Write-Output "OK"
} finally {
  $target.Dispose()
  $source.Dispose()
}
''';

  // --- Disk Partitioning ---

  Future<_DiskPartResult> _partitionDisk({
    required int diskNumber,
    required BootMode bootMode,
  }) async {
    final activeLine = bootMode == BootMode.uefi ? '' : 'active';
    final script =
        '''
select disk $diskNumber
clean
convert mbr
create partition primary
$activeLine
format fs=fat32 label="WDS_BOOT" quick
assign
exit
''';
    _logLine('DiskPart script:\n$script');

    final result = await _runDiskpart(script);
    _logLine('DiskPart exit: ${result.exitCode}');

    if (result.exitCode != 0) {
      final stderr = result.stderr.toString();
      final stdout = result.stdout.toString();
      _logLine('DiskPart stderr: $stderr');
      _logLine('DiskPart stdout: $stdout');
      return _DiskPartResult(
        success: false,
        error: stderr.isNotEmpty ? stderr : stdout,
      );
    }

    final driveLetter = await _findDriveLetterForDisk(diskNumber);
    if (driveLetter == null) {
      _logLine('Could not find drive letter');
      return _DiskPartResult(
        success: false,
        error: 'Could not find assigned drive letter',
      );
    }

    return _DiskPartResult(success: true, driveLetter: driveLetter);
  }

  Future<String?> _findDriveLetterForDisk(int diskNumber) async {
    try {
      final result = await Process.run('powershell', [
        '-NoProfile',
        '-ExecutionPolicy',
        'Bypass',
        '-Command',
        'Get-Partition -DiskNumber $diskNumber -ErrorAction Stop | '
            'Where-Object { \$_.DriveLetter } | '
            'Sort-Object PartitionNumber | '
            'Select-Object -First 1 -ExpandProperty DriveLetter',
      ]);
      if (result.exitCode == 0) {
        final letter = result.stdout.toString().trim();
        if (letter.isNotEmpty) return '$letter:';
      }
    } catch (_) {}

    return null;
  }

  // --- Formatting ---

  Future<bool> _formatPartition({
    required String driveLetter,
    required String fileSystem,
  }) async {
    try {
      final result = await Process.run('powershell', [
        '-NoProfile',
        '-ExecutionPolicy',
        'Bypass',
        '-Command',
        'Get-Volume -DriveLetter ${driveLetter.replaceAll(":", "")} | Select-Object -ExpandProperty FileSystem',
      ]);
      return result.exitCode == 0 &&
          result.stdout.toString().trim().toUpperCase() ==
              fileSystem.toUpperCase();
    } catch (_) {
      return false;
    }
  }

  // --- ISO Mounting ---

  Future<String?> _mountIso(String isoPath) async {
    try {
      final escapedPath = isoPath.replaceAll("'", "''");
      _logLine('Mounting ISO: $isoPath');

      // Clean up any stale mount
      await Process.run('powershell', [
        '-NoProfile',
        '-ExecutionPolicy',
        'Bypass',
        '-Command',
        "Dismount-DiskImage -ImagePath '$escapedPath' -ErrorAction SilentlyContinue | Out-Null",
      ]).timeout(const Duration(seconds: 10));

      // Mount
      final mountResult = await Process.run('powershell', [
        '-NoProfile',
        '-ExecutionPolicy',
        'Bypass',
        '-Command',
        "Mount-DiskImage -ImagePath '$escapedPath' -PassThru | Out-Null",
      ]).timeout(const Duration(seconds: 30));
      _logLine(
        'Mount exit: ${mountResult.exitCode}, stderr: ${mountResult.stderr}',
      );

      if (mountResult.exitCode != 0) return null;

      // Get drive letter with retries
      for (int i = 0; i < 5; i++) {
        await Future.delayed(const Duration(milliseconds: 500));
        final letterResult = await Process.run('powershell', [
          '-NoProfile',
          '-ExecutionPolicy',
          'Bypass',
          '-Command',
          "Get-DiskImage -ImagePath '$escapedPath' | Get-Volume | Select-Object -ExpandProperty DriveLetter",
        ]).timeout(const Duration(seconds: 10));
        _logLine(
          'Drive letter attempt $i: exit=${letterResult.exitCode}, out="${letterResult.stdout}"',
        );
        if (letterResult.exitCode == 0) {
          final letter = letterResult.stdout.toString().trim();
          if (letter.isNotEmpty) {
            _logLine('Mounted at: $letter:\\');
            return '$letter:\\';
          }
        }
      }
    } catch (e) {
      _logLine('Mount error: $e');
    }
    return null;
  }

  Future<void> _unmountIso(String isoPath) async {
    try {
      final escapedPath = isoPath.replaceAll("'", "''");
      await Process.run('powershell', [
        '-NoProfile',
        '-ExecutionPolicy',
        'Bypass',
        '-Command',
        "Dismount-DiskImage -ImagePath '$escapedPath' -ErrorAction SilentlyContinue",
      ]).timeout(const Duration(seconds: 15));
      _logLine('Unmounted OK');
    } catch (e) {
      _logLine('Unmount error: $e');
    }
  }

  // --- File Copying ---

  Future<bool> _copyIsoContents({
    required String mountPoint,
    required String targetDrive,
    required bool excludeWim,
    void Function(double progress)? onProgress,
  }) async {
    try {
      final srcDir = mountPoint.endsWith('\\') ? mountPoint : '$mountPoint\\';
      final dstDir = targetDrive.endsWith('\\')
          ? targetDrive
          : '$targetDrive\\';
      _logLine('robocopy: $srcDir -> $dstDir');

      // robocopy args
      final args = <String>[
        srcDir,
        dstDir,
        '/E', // recursive including empty dirs
        '/R:1', // 1 retry
        '/W:1', // 1 second wait between retries
        '/NP', // no progress percentage (clean output)
        '/NDL', // don't log directory names
        '/NJH', // no job header
        '/NJS', // no job summary
        '/MT:8', // 8 threads
      ];

      if (excludeWim) {
        args.addAll(['/XF', 'install.wim', 'install.esd']);
      }

      // Always exclude AutoUnattend.xml from ISO (may contain invalid keys
      // that break Windows Setup on USB drives)
      args.addAll(['/XF', 'AutoUnattend.xml', 'autounattend.xml']);

      _logLine('robocopy args: ${args.join(" ")}');

      // Report indeterminate progress while copying
      if (onProgress != null) {
        onProgress(0.0);
      }

      final result = await Process.run(
        'robocopy',
        args,
      ).timeout(const Duration(minutes: 15));

      // robocopy exit codes: 0-7 are success, 8+ are failures
      // 0 = no files copied (already up to date)
      // 1 = files copied successfully
      // 2 = extra files in destination
      // 3 = files copied + extra files
      // 4 = mismatched files
      // 5 = files copied + mismatched
      // 6 = extra + mismatched
      // 7 = all of the above
      final exitCode = result.exitCode;
      _logLine('robocopy exit: $exitCode');

      if (onProgress != null) {
        onProgress(1.0);
      }

      if (exitCode >= 8) {
        _logLine('robocopy FAILED: ${result.stderr}');
        _logLine('robocopy stdout: ${result.stdout}');
        return false;
      }

      _logLine('robocopy OK');
      return true;
    } catch (e) {
      _logLine('robocopy error: $e');
      return false;
    }
  }

  // --- WIM Splitting ---

  Future<bool> _splitWim({
    required String sourcePath,
    required String targetDir,
  }) async {
    try {
      final targetPath = p.join(targetDir, 'install.swm');
      final result = await Process.run('dism', [
        '/Split-Image',
        '/ImageFile:$sourcePath',
        '/SWMFile:$targetPath',
        '/FileSize:3800',
      ]);
      return result.exitCode == 0;
    } catch (_) {
      return false;
    }
  }

  // --- Boot Files ---

  Future<bool> _writeBootFiles({
    required String windowsDrive,
    required String targetDrive,
    required BootMode bootMode,
  }) async {
    try {
      _logLine('Writing boot files: target=$targetDrive');

      // Step 1: Write MBR boot code with bootsect
      if (bootMode != BootMode.uefi) {
        _logLine('Step 1: bootsect /nt60 $targetDrive /mbr');
        final bootsectResult = await Process.run('bootsect', [
          '/nt60',
          targetDrive,
          '/mbr',
        ]).timeout(const Duration(seconds: 30));
        _logLine('bootsect exit: ${bootsectResult.exitCode}');
        _logLine('bootsect stdout: ${bootsectResult.stdout}');
        if (bootsectResult.exitCode != 0) {
          _logLine('bootsect stderr: ${bootsectResult.stderr}');
        }
      } else {
        _logLine('Step 1: skipped bootsect for UEFI-only mode');
      }

      // Step 2: Try bcdboot (fast if \Windows exists on ISO)
      final windowsDir = '${windowsDrive}Windows';
      if (await Directory(windowsDir).exists()) {
        _logLine('Step 2: bcdboot (standard path)');
        final result = await Process.run('bcdboot', [
          windowsDir,
          '/s',
          targetDrive,
          '/f',
          'ALL',
        ]).timeout(const Duration(seconds: 60));
        _logLine('bcdboot exit: ${result.exitCode}');
        _logLine('bcdboot stdout: ${result.stdout}');
        if (result.exitCode != 0) {
          _logLine('bcdboot failed, falling back to bootsect-only');
        }
        // Don't return yet — need to verify EFI files exist below
      }

      // Step 3: For slim ISOs (Tiny10 etc) - bcdboot needs DISM mount which is slow
      // Instead, try bcdboot with /s pointing to the ISO's boot directory
      // The bootmgr + BCD from ISO should be enough for BIOS boot
      _logLine('Step 3: Trying bcdboot with boot dir');
      final bootDir = '${targetDrive}boot';
      if (await Directory(bootDir).exists()) {
        // Try creating BCD store manually if missing
        final bcdPath = '$targetDrive\\boot\\BCD';
        if (!await File(bcdPath).exists()) {
          _logLine('BCD not found, creating with bcdedit...');
          await _createBcdStore(targetDrive);
        }
      }

      // Verify: bootsect + bootmgr from ISO = bootable for BIOS
      // UEFI boot needs \efi\boot\bootx64.efi which was copied from ISO
      final hasBootmgr = await File('$targetDrive\\bootmgr').exists();
      var hasEfiBoot =
          await File('$targetDrive\\efi\\boot\\bootx64.efi').exists() ||
          await File('$targetDrive\\efi\\boot\\bootaa64.efi').exists();
      _logLine('Boot files: bootmgr=$hasBootmgr, efi=$hasEfiBoot');

      // If EFI boot file missing, try to fix it
      if (!hasEfiBoot) {
        _logLine('EFI boot file missing, attempting repair...');

        // Try 1: Copy bootmgfw.efi from efi\microsoft\boot to efi\boot\bootx64.efi
        final bootmgfwPath = '$targetDrive\\efi\\microsoft\\boot\\bootmgfw.efi';
        if (await File(bootmgfwPath).exists()) {
          _logLine('Found bootmgfw.efi, copying to efi\\boot');
          final efiBootDir = '$targetDrive\\efi\\boot';
          await Directory(efiBootDir).create(recursive: true);
          await File(bootmgfwPath).copy('$efiBootDir\\bootx64.efi');
          hasEfiBoot = true;
        }

        // Try 1b: Copy bootmgfw.efi as bootaa64.efi for ARM64
        if (!hasEfiBoot) {
          final bootmgfwPath2 =
              '$targetDrive\\efi\\microsoft\\boot\\bootmgfw.efi';
          if (await File(bootmgfwPath2).exists()) {
            final efiBootDir = '$targetDrive\\efi\\boot';
            await Directory(efiBootDir).create(recursive: true);
            await File(bootmgfwPath2).copy('$efiBootDir\\bootaa64.efi');
            hasEfiBoot = true;
          }
        }

        // Try 2: bcdboot with /f UEFI specifically
        if (!hasEfiBoot) {
          final windowsDir2 = '${windowsDrive}Windows';
          if (await Directory(windowsDir2).exists()) {
            _logLine('Trying bcdboot /f UEFI...');
            final uefiResult = await Process.run('bcdboot', [
              windowsDir2,
              '/s',
              targetDrive,
              '/f',
              'UEFI',
            ]).timeout(const Duration(seconds: 60));
            _logLine('bcdboot UEFI exit: ${uefiResult.exitCode}');
            hasEfiBoot =
                await File('$targetDrive\\efi\\boot\\bootx64.efi').exists() ||
                await File('$targetDrive\\efi\\boot\\bootaa64.efi').exists();
          }
        }

        // Try 3: Check if ISO had efi\boot and re-copy it
        if (!hasEfiBoot) {
          _logLine('EFI still missing after repair attempts');
        }
      }

      _logLine('Final: bootmgr=$hasBootmgr, efi=$hasEfiBoot');
      return _bootFilesMatchMode(
        bootMode: bootMode,
        hasBootmgr: hasBootmgr,
        hasEfiBoot: hasEfiBoot,
      );
    } catch (e) {
      _logLine('Boot file exception: $e');
      return false;
    }
  }

  Future<void> _createBcdStore(String targetDrive) async {
    try {
      final bcdPath = '$targetDrive\\boot\\BCD';
      // bcdedit /createstore creates an empty BCD store
      await Process.run('bcdedit', [
        '/createstore',
        bcdPath,
      ]).timeout(const Duration(seconds: 10));

      // Create boot manager entry
      await Process.run('bcdedit', [
        '/store',
        bcdPath,
        '/create',
        '{bootmgr}',
        '/d',
        'Windows Boot Manager',
      ]).timeout(const Duration(seconds: 10));

      _logLine('BCD store created');
    } catch (e) {
      _logLine('BCD create error: $e');
    }
  }

  // --- Verification ---

  Future<bool> _verifyBootableUsb({
    required String driveLetter,
    required BootMode bootMode,
  }) async {
    final errors = <String>[];

    // Core boot files (required for BIOS/both)
    final hasBootmgr = await File('$driveLetter\\bootmgr').exists();
    if (bootMode != BootMode.uefi && !hasBootmgr) {
      errors.add('bootmgr missing');
    }

    // EFI boot (required for UEFI/both)
    final hasEfiBoot =
        await File('$driveLetter\\EFI\\Boot\\bootx64.efi').exists() ||
        await File('$driveLetter\\EFI\\Boot\\bootaa64.efi').exists();
    if (bootMode != BootMode.bios && !hasEfiBoot) {
      errors.add('EFI boot file missing');
    }

    // Install image (required)
    final hasWim = await File('$driveLetter\\sources\\install.wim').exists();
    final hasEsd = await File('$driveLetter\\sources\\install.esd').exists();
    final hasSwm = await File('$driveLetter\\sources\\install.swm').exists();
    if (!hasWim && !hasEsd && !hasSwm) {
      errors.add('install image missing (wim/esd/swm)');
    }

    // setup.exe is optional (slim ISOs like Tiny10/X-Lite may not have it)
    if (!await File('$driveLetter\\setup.exe').exists()) {
      _logLine('Note: setup.exe not found (OK for slim ISOs)');
    }

    if (errors.isNotEmpty) {
      _logLine('Verify issues: ${errors.join(', ')}');
      final logger = ref.read(fileLoggerServiceProvider);
      await logger.log(
        action: 'Verify Install Media',
        target: driveLetter,
        result: 'Issues: ${errors.join(', ')}',
        level: LogLevel.warning,
      );
    }

    return errors.isEmpty;
  }

  bool _bootFilesMatchMode({
    required BootMode bootMode,
    required bool hasBootmgr,
    required bool hasEfiBoot,
  }) {
    switch (bootMode) {
      case BootMode.bios:
        return hasBootmgr;
      case BootMode.uefi:
        return hasEfiBoot;
      case BootMode.both:
        return hasBootmgr && hasEfiBoot;
    }
  }

  // --- Volume Icon ---

  Future<void> _setVolumeIcon(String driveLetter) async {
    try {
      _logLine('Loading intel.ico from app assets...');

      // Load icon from Flutter asset bundle
      final iconBytes = await rootBundle.load('assets/intel.ico');
      final iconData = iconBytes.buffer.asUint8List();

      // Copy icon to USB root
      final iconDest = File('$driveLetter\\intel.ico');
      await iconDest.writeAsBytes(iconData);
      _logLine('Icon written to: ${iconDest.path}');

      // Create autorun.inf — remove existing first (Windows may block it)
      final autorunFile = File('$driveLetter\\autorun.inf');
      try {
        // Remove hidden/system/read-only attributes if file exists
        await Process.run('attrib', [
          '-h',
          '-s',
          '-r',
          autorunFile.path,
        ]).timeout(const Duration(seconds: 5));
        await autorunFile.delete().catchError((_) => autorunFile);
      } catch (_) {}

      await autorunFile.writeAsString(
        '[autorun]\nicon=intel.ico\nlabel=INTEL\n',
      );
      _logLine('autorun.inf created');

      // Set autorun.inf as hidden+system (suppresses some Windows warnings)
      await Process.run('attrib', [
        '+h',
        '+s',
        autorunFile.path,
      ]).timeout(const Duration(seconds: 5));

      // Set icon as hidden
      await Process.run('attrib', [
        '+h',
        iconDest.path,
      ]).timeout(const Duration(seconds: 5));

      _logLine('Volume icon set OK');
    } catch (e) {
      _logLine('Volume icon error: $e (non-fatal, continuing)');
    }
  }

  // --- Utility ---

  Future<ProcessResult> _runDiskpart(String script) async {
    final tempDir = await FileUtils.getTempDirectory();
    final scriptFile = File(p.join(tempDir, 'winddeploy_diskpart.txt'));
    await scriptFile.writeAsString(script);

    try {
      final result = await Process.run('diskpart', ['/s', scriptFile.path])
          .timeout(
            const Duration(seconds: 30),
            onTimeout: () {
              return ProcessResult(0, -1, '', 'diskpart timed out after 30s');
            },
          );
      return result;
    } finally {
      await scriptFile.delete().catchError((_) => scriptFile);
    }
  }

  void _notify(ProgressCallback? callback, CreateProgress progress) {
    callback?.call(progress);
  }
}

class _DiskPartResult {
  final bool success;
  final String? driveLetter;
  final String? error;

  const _DiskPartResult({required this.success, this.driveLetter, this.error});
}

class _LinuxRawWriteResult {
  final bool success;
  final String? error;

  const _LinuxRawWriteResult({required this.success, this.error});
}
