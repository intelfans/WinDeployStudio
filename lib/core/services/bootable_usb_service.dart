import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'bootable_media_validation.dart';
import 'file_logger_service.dart';
import 'disk_safety_service.dart';
import 'in_memory_powershell.dart';
import 'linux_driver_staging_service.dart';
import 'linux_media_preflight.dart';
import '../../features/deployment/models/deployment_plan.dart';
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
  static const int _fat32MaxFileBytes = 0xFFFFFFFF;
  static const String _trustedMke2fsSha256 =
      'BE42ABB5D1651C8766E230E7AF834BD8E0F2085857CCB483463F58BA5AD65E1A';
  static const String _trustedMke2fsVersion = 'mke2fs 1.47.2 (1-Jan-2025)';
  static const String _trustedMke2fsLibraryVersion =
      'android-platform-15.0.0_r5-314-ga1f793f6b';

  @visibleForTesting
  static String trustedMke2fsPathForResolvedExecutable(
    String resolvedExecutable,
  ) => p.join(
    File(resolvedExecutable).parent.path,
    'tools',
    'e2fsprogs',
    'mke2fs.exe',
  );

  @visibleForTesting
  static bool isTrustedMke2fsVersionOutput(String output) =>
      output.contains(_trustedMke2fsVersion) &&
      output.contains(_trustedMke2fsLibraryVersion);

  final Ref ref;
  final List<String> _log = [];
  bool _cancelRequested = false;
  Process? _activeLinuxRawWriteProcess;
  Process? _activeLinuxVerificationProcess;
  Process? _activeLinuxUtilityProcess;

  BootableUsbService(this.ref);

  void cancel() {
    _cancelRequested = true;
    final processes = {
      ?_activeLinuxRawWriteProcess,
      ?_activeLinuxVerificationProcess,
      ?_activeLinuxUtilityProcess,
    };
    for (final process in processes) {
      unawaited(
        _terminateProcessTree(process, reason: 'Linux operation cancelled'),
      );
    }
  }

  void _logLine(String msg) {
    final line = '[${DateTime.now().toIso8601String()}] $msg';
    _log.add(line);
    debugPrint(line);
  }

  String get logText => _log.join('\n');
  bool get isCancelled => _cancelRequested;

  @visibleForTesting
  static String get linuxRawWriteScriptForTesting => _linuxRawWriteScript;

  @visibleForTesting
  static String get linuxRawVerifyScriptForTesting => _linuxRawVerifyScript;

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
    required DiskInfo disk,
    required String isoPath,
    BootMode bootMode = BootMode.both,
    DeploymentPlan? deploymentPlan,
    ProgressCallback? onProgress,
  }) async {
    final plan = deploymentPlan;
    if (plan != null) {
      final compatibility = DeploymentCompatibility.evaluate(plan);
      if (!compatibility.canDeploy ||
          plan.platform != DeploymentPlatform.windows ||
          plan.purpose != DeploymentPurpose.installMedia) {
        _logLine('Installation media deployment plan is not compatible.');
        _notify(
          onProgress,
          CreateProgress(
            step: CreateStep.failed,
            message: compatibility.errors.isEmpty
                ? 'deploy_compat_install_direct_only'
                : compatibility.errors.first.messageKey,
          ),
        );
        return false;
      }
      bootMode = switch (plan.bootMode) {
        DeploymentBootMode.uefiGpt => BootMode.uefi,
        DeploymentBootMode.uefiMbr => BootMode.both,
        DeploymentBootMode.legacyBios => BootMode.bios,
      };
    }
    final diskNumber = disk.diskNumber;
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

      final safetyResult = await ref
          .read(diskSafetyServiceProvider)
          .checkDiskSafety(disk);
      if (!safetyResult.isSafe) {
        _logLine('Target disk safety check failed: ${safetyResult.reason}');
        _notify(
          onProgress,
          CreateProgress(step: CreateStep.failed, message: safetyResult.reason),
        );
        return false;
      }

      final volumeIcon = await _prepareVolumeIcon(plan?.customIconPath ?? '');
      if (!volumeIcon.success || volumeIcon.payload == null) {
        final error = volumeIcon.error ?? 'Volume icon validation failed.';
        _logLine('Volume icon preflight failed: $error');
        _notify(
          onProgress,
          CreateProgress(
            step: CreateStep.failed,
            message: 'deploy_compat_invalid_icon\n$error',
            error: error,
          ),
        );
        return false;
      }

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
        disk: disk,
        bootMode: bootMode,
        deploymentBootMode: plan?.bootMode ?? DeploymentBootMode.uefiMbr,
        preferredDriveLetter: plan?.preferredSystemLetter ?? '',
        volumeLabel: plan?.customVolumeLabel ?? '',
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

      final partitionedDiskSafety = await ref
          .read(diskSafetyServiceProvider)
          .checkDiskSafety(disk);
      if (!partitionedDiskSafety.isSafe) {
        _logLine(
          'Target disk changed after partitioning: '
          '${partitionedDiskSafety.reason}',
        );
        _notify(
          onProgress,
          CreateProgress(
            step: CreateStep.failed,
            message: partitionedDiskSafety.reason,
          ),
        );
        return false;
      }

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
      final iconSet = await _setVolumeIcon(
        driveLetter,
        icon: volumeIcon.payload!,
        volumeLabel: plan?.customVolumeLabel ?? '',
      );
      if (!iconSet) {
        _notify(
          onProgress,
          const CreateProgress(
            step: CreateStep.failed,
            message: 'deploy_compat_invalid_icon',
          ),
        );
        return false;
      }

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
        expectedIconSha256: volumeIcon.payload!.sha256Digest,
        expectedVolumeLabel: plan?.customVolumeLabel ?? '',
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
    required DiskInfo disk,
    required String isoPath,
    required LinuxUsbKind kind,
    DeploymentPlan? deploymentPlan,
    ProgressCallback? onProgress,
  }) async {
    final diskNumber = disk.diskNumber;
    _cancelRequested = false;
    _log.clear();
    final modeName = kind == LinuxUsbKind.toGo
        ? 'Linux To Go'
        : 'Linux Installation Media';
    _logLine('=== Create $modeName Start ===');
    _logLine('Disk: $diskNumber, ISO: $isoPath');

    if (deploymentPlan != null &&
        (deploymentPlan.platform != DeploymentPlatform.linux ||
            deploymentPlan.purpose !=
                (kind == LinuxUsbKind.toGo
                    ? DeploymentPurpose.toGo
                    : DeploymentPurpose.installMedia))) {
      _logLine('Linux deployment plan does not match the requested operation.');
      _notify(
        onProgress,
        const CreateProgress(step: CreateStep.failed, message: 'creator_error'),
      );
      return false;
    }

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

      final safetyResult = await ref
          .read(diskSafetyServiceProvider)
          .checkDiskSafety(disk);
      if (!safetyResult.isSafe) {
        _logLine('Target disk safety check failed: ${safetyResult.reason}');
        _notify(
          onProgress,
          CreateProgress(step: CreateStep.failed, message: safetyResult.reason),
        );
        return false;
      }

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

      final sourcePreflight = await _validateLinuxSourceBeforeErase(
        disk: disk,
        isoPath: isoPath,
      );
      if (!sourcePreflight.success) {
        final error = sourcePreflight.error ?? 'Linux source preflight failed.';
        _logLine(error);
        _notify(
          onProgress,
          CreateProgress(
            step: CreateStep.failed,
            message: 'linux_write_failed\n$error',
            error: error,
          ),
        );
        return false;
      }

      final stagingService = LinuxDriverStagingService(log: _logLine);
      final stagingPreparation = kind == LinuxUsbKind.toGo
          ? await stagingService.prepare(
              sourceDirectory: deploymentPlan?.driverDirectory ?? '',
              targetDiskNumber: diskNumber,
            )
          : const LinuxDriverStagingPreparation.disabled();
      if (!stagingPreparation.success) {
        final error =
            stagingPreparation.error ??
            'Linux first-boot staging validation failed.';
        _logLine(error);
        _notify(
          onProgress,
          CreateProgress(
            step: CreateStep.failed,
            message: 'creator_error\n$error',
            error: error,
          ),
        );
        return false;
      }

      if (kind == LinuxUsbKind.toGo) {
        final preflight = await _validateLinuxToGoIso(isoPath);
        if (!preflight.success) {
          _logLine('Linux To Go preflight failed: ${preflight.error}');
          _notify(
            onProgress,
            CreateProgress(
              step: CreateStep.failed,
              message: preflight.error ?? 'linux_togo_unsupported_iso',
              error: preflight.error,
            ),
          );
          return false;
        }
        final result = await _createPersistentLinuxToGo(
          disk: disk,
          isoPath: isoPath,
          preflight: preflight,
          stagingBundle: stagingPreparation.bundle,
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

      if (!await _isIsoHybridImage(isoPath)) {
        _logLine('Linux image is not an ISOHybrid image');
        _notify(
          onProgress,
          const CreateProgress(
            step: CreateStep.failed,
            message: 'linux_not_isohybrid',
          ),
        );
        return false;
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
        disk: disk,
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
        final errorKey = result.cancelled
            ? 'deploy_cancel_requested'
            : errorDetail.contains('Access is denied') ||
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
        disk: disk,
        isoPath: isoPath,
        onProgress: (progress) {
          _notify(
            onProgress,
            CreateProgress(
              step: CreateStep.verifying,
              message: 'linux_finalizing',
              progress: 0.96 + progress * 0.04,
            ),
          );
        },
      );
      _logLine('Linux verify: ${verifyResult.success ? "OK" : "FAILED"}');

      _notify(
        onProgress,
        CreateProgress(
          step: verifyResult.success ? CreateStep.complete : CreateStep.failed,
          message: verifyResult.success
              ? 'linux_complete'
              : '${verifyResult.cancelled ? 'deploy_cancel_requested' : 'linux_verify_failed'}\n${verifyResult.error ?? ''}',
          progress: verifyResult.success ? 1.0 : 0.0,
          error: verifyResult.error,
        ),
      );

      await logger.log(
        action: 'Create $modeName',
        target: 'Disk $diskNumber',
        result: verifyResult.success
            ? 'Success - Raw ISOHybrid write'
            : 'Failed: ${verifyResult.error ?? "Unknown error"}',
        level: verifyResult.success ? LogLevel.success : LogLevel.error,
      );

      if (verifyResult.success) {
        await logCenter.logUsb('$modeName 创建成功 | 磁盘: $diskNumber');
      } else {
        await logCenter.logError(
          '$modeName 验证失败 | 磁盘: $diskNumber | ${verifyResult.error ?? "Unknown"}',
        );
      }

      final logPath = await saveLogToFile();
      _logLine('Log saved to: $logPath');
      return verifyResult.success;
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
    required DiskInfo disk,
    required String isoPath,
    required _LinuxToGoPreflight preflight,
    LinuxDriverStagingBundle? stagingBundle,
    ProgressCallback? onProgress,
  }) async {
    final diskNumber = disk.diskNumber;
    const int mib = 1024 * 1024;

    try {
      final diskBytes = await _getDiskSizeBytes(diskNumber);
      if (diskBytes == null) {
        return const _LinuxRawWriteResult(
          success: false,
          error: 'Unable to read target disk size.',
        );
      }

      final diskSizeMb = diskBytes ~/ mib;
      final stagingContentMb = stagingBundle == null
          ? 0
          : ((stagingBundle.totalBytes + mib - 1) ~/ mib) + 16;
      final dataRequiredMb =
          ((preflight.totalContentBytes + mib - 1) ~/ mib) +
          stagingContentMb +
          256;
      final bootContentMb =
          ((preflight.bootContentBytes + mib - 1) ~/ mib) + 128;
      final minimumPersistenceMb = stagingBundle == null
          ? 512
          : _maxInt(
              512,
              (stagingBundle.estimatedPersistenceBytes + mib - 1) ~/ mib,
            );
      final persistenceSizeMb = _minInt(
        4095,
        diskSizeMb - dataRequiredMb - bootContentMb - 32,
      );
      final bootPartitionSizeMb = bootContentMb + persistenceSizeMb;

      if (persistenceSizeMb < minimumPersistenceMb ||
          bootPartitionSizeMb > 32760) {
        return _LinuxRawWriteResult(
          success: false,
          error:
              'The target disk is too small for this Linux To Go image. '
              'It needs space for the complete Live image, boot files, '
              '${stagingBundle == null ? 'and at least 512 MB of persistence.' : 'the verified Linux staging seed, and at least $minimumPersistenceMb MB of persistence for first-boot installation.'}',
        );
      }

      _logLine(
        'Linux To Go layout: disk=${diskSizeMb}MB, '
        'boot=${bootPartitionSizeMb}MB FAT32, '
        'live>=${dataRequiredMb}MB NTFS, persistence=${persistenceSizeMb}MB, '
        'staging=${stagingBundle?.totalBytes ?? 0} bytes',
      );

      final destructivePreflight = await _validateLinuxSourceBeforeErase(
        disk: disk,
        isoPath: isoPath,
      );
      if (!destructivePreflight.success) return destructivePreflight;

      _notify(
        onProgress,
        const CreateProgress(
          step: CreateStep.cleaningDisk,
          message: 'linux_locking_disk',
          progress: 0.05,
        ),
      );

      final partitionResult = await _partitionLinuxToGoDisk(
        disk: disk,
        bootPartitionSizeMb: bootPartitionSizeMb,
      );
      if (!partitionResult.success ||
          partitionResult.bootDrive == null ||
          partitionResult.liveDrive == null) {
        return _LinuxRawWriteResult(
          success: false,
          error: partitionResult.error ?? 'Failed to partition target disk.',
        );
      }

      final bootDrive = partitionResult.bootDrive!;
      final liveDrive = partitionResult.liveDrive!;
      _logLine('Linux To Go partitions: boot=$bootDrive, live=$liveDrive');

      _notify(
        onProgress,
        const CreateProgress(
          step: CreateStep.formatting,
          message: 'boot_format_verifying',
          progress: 0.12,
        ),
      );

      final bootReady = await _waitForLinuxToGoPartition(
        drive: bootDrive,
        expectedLabel: 'WDS_LTG',
        expectedFileSystem: 'FAT32',
        expectedPartitionNumber: 1,
        diskNumber: diskNumber,
      );
      final liveReady = await _waitForLinuxToGoPartition(
        drive: liveDrive,
        expectedLabel: 'WDS_LIVE',
        expectedFileSystem: 'NTFS',
        expectedPartitionNumber: 2,
        diskNumber: diskNumber,
      );
      if (!bootReady || !liveReady) {
        return const _LinuxRawWriteResult(
          success: false,
          error:
              'Linux To Go partitions did not pass the post-format identity check.',
        );
      }

      final partitionedDiskSafety = await ref
          .read(diskSafetyServiceProvider)
          .checkDiskSafety(disk);
      if (!partitionedDiskSafety.isSafe) {
        return _LinuxRawWriteResult(
          success: false,
          error: partitionedDiskSafety.reason,
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

        final liveCopyOk = await _copyIsoContents(
          mountPoint: mountPoint,
          targetDrive: liveDrive,
          excludeWim: false,
          excludeAutoUnattend: false,
          onProgress: (progress) {
            _notify(
              onProgress,
              CreateProgress(
                step: CreateStep.copyingFiles,
                message: 'step_copying',
                progress: 0.24 + progress * 0.34,
              ),
            );
          },
        );

        if (!liveCopyOk) {
          return const _LinuxRawWriteResult(
            success: false,
            error: 'Failed to copy Linux Live files to the NTFS partition.',
          );
        }

        final bootCopyOk = await _copyIsoContents(
          mountPoint: mountPoint,
          targetDrive: bootDrive,
          excludeWim: false,
          excludeAutoUnattend: false,
          excludedExtensions: const {'squashfs', 'ext2'},
          onProgress: (progress) {
            _notify(
              onProgress,
              CreateProgress(
                step: CreateStep.copyingFiles,
                message: 'step_copying',
                progress: 0.58 + progress * 0.12,
              ),
            );
          },
        );

        if (!bootCopyOk) {
          return const _LinuxRawWriteResult(
            success: false,
            error: 'Failed to copy Linux boot files to the FAT32 partition.',
          );
        }

        final copied = await _verifyLinuxToGoCopies(
          mountPoint: mountPoint,
          bootDrive: bootDrive,
          liveDrive: liveDrive,
          preflight: preflight,
        );
        if (!copied.success) return copied;
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

      final bootPatched = await _patchLinuxPersistenceBootConfigs(
        bootDrive,
        enableFirstBootStaging: stagingBundle != null,
      );
      final livePatched = await _patchLinuxPersistenceBootConfigs(
        liveDrive,
        enableFirstBootStaging: stagingBundle != null,
      );
      if (!bootPatched || !livePatched) {
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
        targetDrive: bootDrive,
        sizeMb: persistenceSizeMb,
      );
      if (!persistenceResult.success) {
        return persistenceResult;
      }

      if (stagingBundle != null) {
        final stagingResult = await LinuxDriverStagingService(log: _logLine)
            .deploy(
              bundle: stagingBundle,
              liveDrive: liveDrive,
              bootDrive: bootDrive,
            );
        if (!stagingResult.success) {
          return _LinuxRawWriteResult(
            success: false,
            error: stagingResult.error,
          );
        }
      }

      _notify(
        onProgress,
        const CreateProgress(
          step: CreateStep.verifying,
          message: 'linux_finalizing',
          progress: 0.96,
        ),
      );

      final verified = await _verifyLinuxToGoLayout(
        diskNumber: diskNumber,
        bootDrive: bootDrive,
        liveDrive: liveDrive,
        preflight: preflight,
        stagingBundle: stagingBundle,
      );
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

  Future<_LinuxToGoPreflight> _validateLinuxToGoIso(String isoPath) async {
    final mke2fs = await _findMke2fs();
    if (mke2fs == null) {
      return const _LinuxToGoPreflight(
        success: false,
        error: 'linux_togo_mke2fs_missing',
      );
    }

    final mountPoint = await _mountIso(isoPath);
    if (mountPoint == null) {
      return const _LinuxToGoPreflight(
        success: false,
        error: 'linux_togo_mount_preflight_failed',
      );
    }

    try {
      final root = mountPoint.endsWith(r'\') ? mountPoint : '$mountPoint\\';
      final hasCasperKernel = await File(
        p.join(root, 'casper', 'vmlinuz'),
      ).exists();
      final hasCasperInitrd = await File(
        p.join(root, 'casper', 'initrd'),
      ).exists();
      final grubConfigs = <File>[
        File(p.join(root, 'boot', 'grub', 'grub.cfg')),
        File(p.join(root, 'boot', 'grub', 'loopback.cfg')),
      ];
      var hasGrub = false;
      for (final file in grubConfigs) {
        if (await file.exists()) {
          hasGrub = true;
          break;
        }
      }
      final hasEfi = await File(
        p.join(root, 'EFI', 'BOOT', 'BOOTX64.EFI'),
      ).exists();
      if (!hasCasperKernel || !hasCasperInitrd || !hasGrub || !hasEfi) {
        return const _LinuxToGoPreflight(
          success: false,
          error: 'linux_togo_unsupported_iso',
        );
      }

      var hasPatchableCasperEntry = false;
      for (final file in grubConfigs) {
        if (!await file.exists()) continue;
        final text = await file.readAsString();
        if (RegExp(
          r'^\s*linux(efi)?\s+.*\/casper\/vmlinuz(?:\s|$)',
          caseSensitive: false,
          multiLine: true,
        ).hasMatch(text)) {
          hasPatchableCasperEntry = true;
          break;
        }
      }
      if (!hasPatchableCasperEntry) {
        return const _LinuxToGoPreflight(
          success: false,
          error: 'linux_togo_boot_config_unsupported',
        );
      }

      var totalContentBytes = 0;
      var bootContentBytes = 0;
      var largestBootFileBytes = 0;
      final livePayloads = <_LinuxToGoPayload>[];
      await for (final entity in Directory(
        root,
      ).list(recursive: true, followLinks: false)) {
        if (entity is! File) continue;
        final length = await entity.length();
        totalContentBytes += length;
        final relativePath = p.relative(entity.path, from: root);
        final extension = p.extension(relativePath).toLowerCase();
        final isLivePayload = extension == '.squashfs' || extension == '.ext2';
        if (isLivePayload) {
          livePayloads.add(
            _LinuxToGoPayload(relativePath: relativePath, sizeBytes: length),
          );
          continue;
        }

        bootContentBytes += length;
        if (length > largestBootFileBytes) largestBootFileBytes = length;
      }

      if (livePayloads.isEmpty) {
        return const _LinuxToGoPreflight(
          success: false,
          error: 'linux_togo_unsupported_iso',
        );
      }
      if (largestBootFileBytes > _fat32MaxFileBytes) {
        return const _LinuxToGoPreflight(
          success: false,
          error: 'linux_togo_boot_file_too_large',
        );
      }

      _logLine(
        'Linux To Go preflight: content=$totalContentBytes, '
        'boot=$bootContentBytes, live payloads=${livePayloads.length}, '
        'largest live=${livePayloads.map((item) => item.sizeBytes).fold<int>(0, _maxInt)}',
      );
      return _LinuxToGoPreflight(
        success: true,
        totalContentBytes: totalContentBytes,
        bootContentBytes: bootContentBytes,
        livePayloads: livePayloads,
      );
    } finally {
      await _unmountIso(isoPath);
    }
  }

  Future<bool> _isIsoHybridImage(String isoPath) async {
    final inspection = await LinuxIsoHybridInspector.inspect(isoPath);
    if (!inspection.isValid) {
      _logLine('ISOHybrid preflight failed: ${inspection.error}');
      return false;
    }
    _logLine(
      'ISOHybrid preflight: ISO9660/El Torito/EFI valid, '
      'catalog LBA=${inspection.bootCatalogLba}, '
      'EFI image LBA=${inspection.efiImageLba}',
    );
    return true;
  }

  Future<_LinuxRawWriteResult> _validateLinuxSourceBeforeErase({
    required DiskInfo disk,
    required String isoPath,
  }) async {
    try {
      final source = File(isoPath);
      final sourceType = await FileSystemEntity.type(
        source.path,
        followLinks: false,
      );
      if (sourceType != FileSystemEntityType.file) {
        return const _LinuxRawWriteResult(
          success: false,
          error: 'The Linux image source must be a regular file.',
        );
      }
      final imageBytes = await source.length();
      final targetBytes = await _getDiskSizeBytes(disk.diskNumber);
      if (targetBytes == null ||
          targetBytes <= 0 ||
          targetBytes != disk.sizeBytes) {
        return const _LinuxRawWriteResult(
          success: false,
          error: 'The target disk size or identity changed before writing.',
        );
      }
      if (imageBytes <= 0 || imageBytes >= targetBytes) {
        return _LinuxRawWriteResult(
          success: false,
          error:
              'The Linux image must be smaller than the target disk '
              '(image=$imageBytes bytes, target=$targetBytes bytes).',
        );
      }

      final sourceOnTarget = await _isPathOnTargetDisk(
        source.path,
        disk.diskNumber,
      );
      if (sourceOnTarget == null) {
        return const _LinuxRawWriteResult(
          success: false,
          error:
              'The physical disk containing the Linux image could not be verified.',
        );
      }
      if (sourceOnTarget) {
        return const _LinuxRawWriteResult(
          success: false,
          error:
              'The Linux image is stored on the target disk and would be erased.',
        );
      }

      _logLine(
        'Linux source preflight: image=$imageBytes bytes, '
        'target=$targetBytes bytes, source disk differs from target',
      );
      return const _LinuxRawWriteResult(success: true);
    } catch (error) {
      return _LinuxRawWriteResult(
        success: false,
        error: 'Linux source preflight failed: $error',
      );
    }
  }

  Future<bool?> _isPathOnTargetDisk(String path, int targetDiskNumber) async {
    try {
      final result = await Process.run(
        'powershell',
        const [
          '-NoProfile',
          '-NonInteractive',
          '-ExecutionPolicy',
          'Bypass',
          '-Command',
          r'''$volume = Get-Volume -FilePath $env:WDS_SOURCE_PATH -ErrorAction Stop
$partitions = @(Get-Partition -Volume $volume -ErrorAction Stop)
if ($partitions.Count -ne 1) {
  throw "Source path did not resolve to exactly one physical partition."
}
[int]$partitions[0].DiskNumber''',
        ],
        environment: {...Platform.environment, 'WDS_SOURCE_PATH': path},
      ).timeout(const Duration(seconds: 10));
      if (result.exitCode != 0) {
        _logLine('Linux source disk resolution failed: ${result.stderr}');
        return null;
      }
      final sourceDiskNumber = int.tryParse(result.stdout.toString().trim());
      return sourceDiskNumber == null
          ? null
          : sourceDiskNumber == targetDiskNumber;
    } catch (error) {
      _logLine('Linux source disk resolution error: $error');
      return null;
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
  int _maxInt(int a, int b) => a > b ? a : b;

  Future<_LinuxToGoPartitionResult> _partitionLinuxToGoDisk({
    required DiskInfo disk,
    required int bootPartitionSizeMb,
  }) async {
    final diskNumber = disk.diskNumber;
    final letters = await _reserveLinuxToGoDriveLetters();
    if (letters == null) {
      return const _LinuxToGoPartitionResult(
        success: false,
        error: 'Could not reserve two drive letters for Linux To Go.',
      );
    }

    final script =
        '''
select disk $diskNumber
clean
convert gpt
create partition efi size=$bootPartitionSizeMb
format fs=fat32 label="WDS_LTG" quick
assign letter=${letters.bootLetter}
create partition primary
format fs=ntfs label="WDS_LIVE" quick
assign letter=${letters.liveLetter}
exit
''';
    _logLine('Linux To Go DiskPart script:\n$script');

    final result = await ref
        .read(diskSafetyServiceProvider)
        .runGuardedDiskpart(disk, script);
    _logLine('Linux To Go DiskPart exit: ${result.exitCode}');

    if (!_diskpartSucceeded(result)) {
      final stderr = result.stderr.toString();
      final stdout = result.stdout.toString();
      _logLine('Linux To Go DiskPart stderr: $stderr');
      _logLine('Linux To Go DiskPart stdout: $stdout');
      return _LinuxToGoPartitionResult(
        success: false,
        error: stderr.isNotEmpty ? stderr : stdout,
      );
    }

    return _LinuxToGoPartitionResult(
      success: true,
      bootDrive: '${letters.bootLetter}:',
      liveDrive: '${letters.liveLetter}:',
    );
  }

  bool _diskpartSucceeded(ProcessResult result) {
    if (result.exitCode != 0) return false;
    final combined = '${result.stdout}\n${result.stderr}'.toLowerCase();
    const errors = [
      'diskpart has encountered an error',
      'virtual disk service error',
      'the parameter is incorrect',
      'access is denied',
      'the volume size is too big',
      'diskpart 遇到错误',
      '虚拟磁盘服务错误',
      '参数错误',
      '拒绝访问',
      '卷大小太大',
    ];
    return !errors.any(combined.contains);
  }

  Future<_LinuxToGoDriveLetters?> _reserveLinuxToGoDriveLetters() async {
    final usedLetters = await _getUsedDriveLetters();
    if (usedLetters == null) return null;
    String? pick(List<String> preferred, Set<String> blocked) {
      for (final letter in preferred) {
        final normalized = letter.toUpperCase();
        if (!usedLetters.contains(normalized) &&
            !blocked.contains(normalized)) {
          return normalized;
        }
      }
      return null;
    }

    final boot = pick(const ['S', 'R', 'T', 'U', 'V', 'X', 'Y', 'Z'], const {});
    if (boot == null) return null;
    final live = pick(const ['W', 'V', 'U', 'T', 'R', 'X', 'Y', 'Z'], {boot});
    if (live == null) return null;
    _logLine('Reserved Linux To Go drive letters: boot=$boot, live=$live');
    return _LinuxToGoDriveLetters(bootLetter: boot, liveLetter: live);
  }

  Future<Set<String>?> _getUsedDriveLetters() async {
    try {
      final result = await Process.run('powershell', [
        '-NoProfile',
        '-ExecutionPolicy',
        'Bypass',
        '-Command',
        r'''
$letters = @()
try {
  $letters += Get-Volume -ErrorAction SilentlyContinue |
    Where-Object { $_.DriveLetter } |
    ForEach-Object { $_.DriveLetter.ToString() }
} catch {}
try {
  $letters += Get-PSDrive -PSProvider FileSystem -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -match '^[A-Za-z]$' } |
    ForEach-Object { $_.Name }
} catch {}
$letters |
  Where-Object { $_ } |
  ForEach-Object { $_.ToString().TrimEnd(':').ToUpperInvariant() } |
  Sort-Object -Unique
''',
      ]).timeout(const Duration(seconds: 10));
      if (result.exitCode == 0) {
        return result.stdout
            .toString()
            .split(RegExp(r'\s+'))
            .map((item) => item.trim().replaceAll(':', '').toUpperCase())
            .where((item) => item.length == 1)
            .toSet();
      }
      _logLine('Drive letter scan failed: ${result.stderr}');
    } catch (e) {
      _logLine('Drive letter scan error: $e');
    }
    return null;
  }

  Future<bool> _waitForLinuxToGoPartition({
    required String drive,
    required String expectedLabel,
    required String expectedFileSystem,
    required int expectedPartitionNumber,
    required int diskNumber,
  }) async {
    final root = drive.endsWith(r'\') ? drive : '$drive\\';
    final letter = drive.replaceAll(RegExp(r'[:\\]'), '').toUpperCase();
    for (var attempt = 1; attempt <= 30; attempt++) {
      try {
        final result = await Process.run(
          'powershell',
          [
            '-NoProfile',
            '-ExecutionPolicy',
            'Bypass',
            '-Command',
            r'''$partition = Get-Partition -DriveLetter $env:WDS_DRIVE_LETTER -ErrorAction Stop
$volume = Get-Volume -DriveLetter $env:WDS_DRIVE_LETTER -ErrorAction Stop
[PSCustomObject]@{
  DiskNumber = $partition.DiskNumber
  PartitionNumber = $partition.PartitionNumber
  Label = $volume.FileSystemLabel
  FileSystem = $volume.FileSystem
} | ConvertTo-Json -Compress''',
          ],
          environment: {...Platform.environment, 'WDS_DRIVE_LETTER': letter},
        ).timeout(const Duration(seconds: 5));
        if (result.exitCode == 0) {
          final decoded = jsonDecode(result.stdout.toString());
          final matches =
              decoded is Map &&
              decoded['DiskNumber'].toString() == diskNumber.toString() &&
              decoded['PartitionNumber'].toString() ==
                  expectedPartitionNumber.toString() &&
              decoded['Label'].toString().toUpperCase() ==
                  expectedLabel.toUpperCase() &&
              decoded['FileSystem'].toString().toUpperCase() ==
                  expectedFileSystem.toUpperCase();
          if (matches && await Directory(root).exists()) {
            final probe = File(p.join(root, '.wds_ltg_probe'));
            await probe.writeAsString('ok');
            await probe.delete();
            _logLine('$expectedLabel ready at $root (attempt $attempt)');
            return true;
          }
        }
      } catch (e) {
        _logLine('$expectedLabel readiness attempt $attempt failed: $e');
      }
      await Future.delayed(const Duration(seconds: 1));
    }
    return false;
  }

  Future<bool> _patchLinuxPersistenceBootConfigs(
    String targetDrive, {
    required bool enableFirstBootStaging,
  }) async {
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
            if (!isLinuxLine ||
                !RegExp(
                  r'\/casper\/vmlinuz(?:\s|$)',
                  caseSensitive: false,
                ).hasMatch(line)) {
              return line;
            }

            foundCasperEntry = true;
            var updated = line;
            final persistentPattern = RegExp(
              r'(^|\s)persistent(\s|$)',
              caseSensitive: false,
            );
            if (!persistentPattern.hasMatch(updated)) {
              updated = _insertGrubKernelArgument(updated, 'persistent');
            }

            const liveMediaArgument = 'live-media=/dev/disk/by-label/WDS_LIVE';
            final liveMediaPattern = RegExp(
              r'(^|\s)live-media=\S+',
              caseSensitive: false,
            );
            if (liveMediaPattern.hasMatch(updated)) {
              updated = updated.replaceFirstMapped(
                liveMediaPattern,
                (match) => '${match.group(1)}$liveMediaArgument',
              );
            } else {
              updated = _insertGrubKernelArgument(updated, liveMediaArgument);
            }

            if (enableFirstBootStaging) {
              for (final argument in const [
                LinuxDriverStagingService.bootMarkerArgument,
                LinuxDriverStagingService.systemdWantsArgument,
              ]) {
                final argumentPattern = RegExp(
                  '(^|\\s)${RegExp.escape(argument)}(\\s|\$)',
                  caseSensitive: false,
                );
                if (!argumentPattern.hasMatch(updated)) {
                  updated = _insertGrubKernelArgument(updated, argument);
                }
              }
            }

            if (updated != line) changed = true;
            return updated;
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

  String _insertGrubKernelArgument(String line, String argument) {
    final markerIndex = line.indexOf(' ---');
    if (markerIndex >= 0) {
      return '${line.substring(0, markerIndex)} $argument${line.substring(markerIndex)}';
    }
    return '$line $argument';
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

    final result = await _runLinuxUtility(mke2fs, [
      '-t',
      'ext4',
      '-F',
      '-L',
      'writable',
      image.path,
    ], timeout: const Duration(minutes: 5));

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
    final candidate = trustedMke2fsPathForResolvedExecutable(
      Platform.resolvedExecutable,
    );
    try {
      final file = File(candidate);
      if (await FileSystemEntity.type(candidate, followLinks: false) !=
          FileSystemEntityType.file) {
        _logLine('Trusted mke2fs not found at: $candidate');
        return null;
      }
      final resolved = await file.resolveSymbolicLinks();
      if (p.normalize(resolved).toLowerCase() !=
          p.normalize(candidate).toLowerCase()) {
        _logLine('Trusted mke2fs path resolves through a link: $candidate');
        return null;
      }

      final digest = (await sha256.bind(file.openRead()).first)
          .toString()
          .toUpperCase();
      if (digest != _trustedMke2fsSha256) {
        _logLine(
          'Trusted mke2fs SHA-256 mismatch: expected '
          '$_trustedMke2fsSha256, actual $digest',
        );
        return null;
      }

      final versionResult = await Process.run(candidate, const [
        '-V',
      ]).timeout(const Duration(seconds: 10));
      final versionOutput = '${versionResult.stdout}\n${versionResult.stderr}'
          .trim();
      if (versionResult.exitCode != 0 ||
          !isTrustedMke2fsVersionOutput(versionOutput)) {
        _logLine(
          'Trusted mke2fs version check failed '
          '(exit ${versionResult.exitCode}): $versionOutput',
        );
        return null;
      }

      _logLine(
        'Using trusted mke2fs: $candidate '
        '(SHA-256 $digest; $_trustedMke2fsVersion)',
      );
      return candidate;
    } catch (error) {
      _logLine('Trusted mke2fs validation failed: $error');
      return null;
    }
  }

  Future<_LinuxRawWriteResult> _verifyLinuxToGoCopies({
    required String mountPoint,
    required String bootDrive,
    required String liveDrive,
    required _LinuxToGoPreflight preflight,
  }) async {
    try {
      final sourceRoot = mountPoint.endsWith(r'\')
          ? mountPoint
          : '$mountPoint\\';
      final bootRoot = bootDrive.endsWith(r'\') ? bootDrive : '$bootDrive\\';
      final liveRoot = liveDrive.endsWith(r'\') ? liveDrive : '$liveDrive\\';
      var verifiedLiveBytes = 0;
      var verifiedBootBytes = 0;

      await for (final entity in Directory(
        sourceRoot,
      ).list(recursive: true, followLinks: false)) {
        if (entity is! File) continue;
        final relativePath = p.relative(entity.path, from: sourceRoot);
        final sourceLength = await entity.length();
        final sourceDigest = (await sha256.bind(entity.openRead()).first)
            .toString();
        verifiedLiveBytes += sourceLength;
        final liveFile = File(p.join(liveRoot, relativePath));
        if (!await liveFile.exists() ||
            await liveFile.length() != sourceLength) {
          return _LinuxRawWriteResult(
            success: false,
            error: 'Linux Live copy verification failed: $relativePath',
          );
        }
        final liveDigest = (await sha256.bind(liveFile.openRead()).first)
            .toString();
        if (liveDigest != sourceDigest) {
          return _LinuxRawWriteResult(
            success: false,
            error:
                'Linux Live copy SHA-256 mismatch: $relativePath '
                '(source=$sourceDigest, copy=$liveDigest)',
          );
        }

        final extension = p.extension(relativePath).toLowerCase();
        final isLivePayload = extension == '.squashfs' || extension == '.ext2';
        final bootFile = File(p.join(bootRoot, relativePath));
        if (isLivePayload) {
          if (await bootFile.exists()) {
            return _LinuxRawWriteResult(
              success: false,
              error:
                  'Linux boot partition contains an unexpected Live payload: $relativePath',
            );
          }
        } else if (!await bootFile.exists() ||
            await bootFile.length() != sourceLength) {
          return _LinuxRawWriteResult(
            success: false,
            error: 'Linux boot copy verification failed: $relativePath',
          );
        } else {
          final bootDigest = (await sha256.bind(bootFile.openRead()).first)
              .toString();
          if (bootDigest != sourceDigest) {
            return _LinuxRawWriteResult(
              success: false,
              error:
                  'Linux boot copy SHA-256 mismatch: $relativePath '
                  '(source=$sourceDigest, copy=$bootDigest)',
            );
          }
          verifiedBootBytes += sourceLength;
        }
      }

      if (verifiedLiveBytes != preflight.totalContentBytes ||
          verifiedBootBytes != preflight.bootContentBytes) {
        return _LinuxRawWriteResult(
          success: false,
          error:
              'Linux To Go copy size verification failed: '
              'live=$verifiedLiveBytes/${preflight.totalContentBytes}, '
              'boot=$verifiedBootBytes/${preflight.bootContentBytes}.',
        );
      }

      _logLine('Linux To Go copy verification: OK');
      return const _LinuxRawWriteResult(success: true);
    } catch (e) {
      return _LinuxRawWriteResult(
        success: false,
        error: 'Linux To Go copy verification failed: $e',
      );
    }
  }

  Future<bool> _verifyLinuxToGoLayout({
    required int diskNumber,
    required String bootDrive,
    required String liveDrive,
    required _LinuxToGoPreflight preflight,
    LinuxDriverStagingBundle? stagingBundle,
  }) async {
    try {
      final bootMatches = await _partitionMatchesLinuxToGoLayout(
        drive: bootDrive,
        expectedLabel: 'WDS_LTG',
        expectedFileSystem: 'FAT32',
        expectedPartitionNumber: 1,
        diskNumber: diskNumber,
      );
      final liveMatches = await _partitionMatchesLinuxToGoLayout(
        drive: liveDrive,
        expectedLabel: 'WDS_LIVE',
        expectedFileSystem: 'NTFS',
        expectedPartitionNumber: 2,
        diskNumber: diskNumber,
      );
      if (!bootMatches || !liveMatches) {
        _logLine('Linux To Go verify failed: partition identity mismatch');
        return false;
      }

      final bootRoot = bootDrive.endsWith(r'\') ? bootDrive : '$bootDrive\\';
      final liveRoot = liveDrive.endsWith(r'\') ? liveDrive : '$liveDrive\\';
      final bootx64 = File(p.join(bootRoot, 'EFI', 'BOOT', 'BOOTx64.EFI'));
      final liveBootx64 = File(p.join(liveRoot, 'EFI', 'BOOT', 'BOOTx64.EFI'));
      final bootGrub = File(p.join(bootRoot, 'boot', 'grub', 'grub.cfg'));
      final liveGrub = File(p.join(liveRoot, 'boot', 'grub', 'grub.cfg'));
      final bootKernel = File(p.join(bootRoot, 'casper', 'vmlinuz'));
      final bootInitrd = File(p.join(bootRoot, 'casper', 'initrd'));
      final writable = File(p.join(bootRoot, 'writable'));

      if (!await bootx64.exists() || !await liveBootx64.exists()) {
        _logLine('Linux To Go verify failed: BOOTx64.EFI missing');
        return false;
      }
      if (!await bootKernel.exists() || !await bootInitrd.exists()) {
        _logLine('Linux To Go verify failed: casper kernel or initrd missing');
        return false;
      }
      if (!await bootGrub.exists() || !await liveGrub.exists()) {
        _logLine('Linux To Go verify failed: GRUB config missing');
        return false;
      }

      final bootGrubText = await bootGrub.readAsString();
      final liveGrubText = await liveGrub.readAsString();
      final persistentPattern = RegExp(r'(^|\s)persistent(\s|$)');
      final liveMediaPattern = RegExp(
        r'(^|\s)live-media=\/dev\/disk\/by-label\/WDS_LIVE(\s|$)',
        caseSensitive: false,
      );
      if (!persistentPattern.hasMatch(bootGrubText) ||
          !persistentPattern.hasMatch(liveGrubText) ||
          !liveMediaPattern.hasMatch(bootGrubText) ||
          !liveMediaPattern.hasMatch(liveGrubText)) {
        _logLine('Linux To Go verify failed: required boot args missing');
        return false;
      }

      if (stagingBundle != null) {
        for (final argument in const [
          LinuxDriverStagingService.bootMarkerArgument,
          LinuxDriverStagingService.systemdWantsArgument,
        ]) {
          if (!bootGrubText.contains(argument) ||
              !liveGrubText.contains(argument)) {
            _logLine(
              'Linux To Go verify failed: staging boot argument missing: '
              '$argument',
            );
            return false;
          }
        }
        final stagingVerified = await LinuxDriverStagingService(log: _logLine)
            .verifyDeployment(
              bundle: stagingBundle,
              liveDrive: liveDrive,
              bootDrive: bootDrive,
            );
        if (!stagingVerified) return false;
      }

      for (final payload in preflight.livePayloads) {
        final liveFile = File(p.join(liveRoot, payload.relativePath));
        if (!await liveFile.exists() ||
            await liveFile.length() != payload.sizeBytes) {
          _logLine(
            'Linux To Go verify failed: Live payload missing or truncated: '
            '${payload.relativePath}',
          );
          return false;
        }
        if (await File(p.join(bootRoot, payload.relativePath)).exists()) {
          _logLine(
            'Linux To Go verify failed: Live payload leaked onto FAT32: '
            '${payload.relativePath}',
          );
          return false;
        }
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

  Future<bool> _partitionMatchesLinuxToGoLayout({
    required String drive,
    required String expectedLabel,
    required String expectedFileSystem,
    required int expectedPartitionNumber,
    required int diskNumber,
  }) async {
    try {
      final letter = drive.replaceAll(RegExp(r'[:\\]'), '').toUpperCase();
      final result = await Process.run(
        'powershell',
        [
          '-NoProfile',
          '-ExecutionPolicy',
          'Bypass',
          '-Command',
          r'''$partition = Get-Partition -DriveLetter $env:WDS_DRIVE_LETTER -ErrorAction Stop
$volume = Get-Volume -DriveLetter $env:WDS_DRIVE_LETTER -ErrorAction Stop
[PSCustomObject]@{
  DiskNumber = $partition.DiskNumber
  PartitionNumber = $partition.PartitionNumber
  Label = $volume.FileSystemLabel
  FileSystem = $volume.FileSystem
} | ConvertTo-Json -Compress''',
        ],
        environment: {...Platform.environment, 'WDS_DRIVE_LETTER': letter},
      ).timeout(const Duration(seconds: 5));
      if (result.exitCode != 0) return false;
      final decoded = jsonDecode(result.stdout.toString());
      return decoded is Map &&
          decoded['DiskNumber'].toString() == diskNumber.toString() &&
          decoded['PartitionNumber'].toString() ==
              expectedPartitionNumber.toString() &&
          decoded['Label'].toString().toUpperCase() ==
              expectedLabel.toUpperCase() &&
          decoded['FileSystem'].toString().toUpperCase() ==
              expectedFileSystem.toUpperCase();
    } catch (_) {
      return false;
    }
  }

  Future<_LinuxRawWriteResult> _writeIsoHybridRaw({
    required DiskInfo disk,
    required int diskNumber,
    required String isoPath,
    required void Function(double progress) onProgress,
  }) async {
    final imageBytes = await File(isoPath).length();
    final command = InMemoryPowerShell.build(
      script: _linuxRawWriteScript,
      parameters: {
        'DiskNumber': '$diskNumber',
        'IsoPath': isoPath,
        'ExpectedIsoLength': '$imageBytes',
        'ExpectedSize': '${disk.sizeBytes}',
        'ExpectedModel': disk.model,
        'ExpectedBus': disk.busType,
        'ExpectedUniqueId': disk.reliableUniqueId,
        'ExpectedSerial': disk.reliableSerialNumber,
        'ExpectedDevicePath': disk.reliableDevicePath,
      },
    );
    Process? process;
    try {
      process = await Process.start(
        command.executable,
        command.arguments,
        environment: command.environment,
      );
      _activeLinuxRawWriteProcess = process;
      if (_cancelRequested) {
        await _terminateProcessTree(process, reason: 'Linux write cancelled');
        return const _LinuxRawWriteResult(
          success: false,
          cancelled: true,
          error: 'Linux raw writing was cancelled.',
        );
      }

      final stdoutText = StringBuffer();
      final stderrText = StringBuffer();
      final stdoutDone = process.stdout
          .transform(const SystemEncoding().decoder)
          .transform(const LineSplitter())
          .listen((line) {
            final cleanLine = line.trim();
            if (cleanLine.isEmpty) return;
            stdoutText.writeln(cleanLine);
            _logLine('Linux raw stdout: $cleanLine');
            if (cleanLine.startsWith('WDS_PROGRESS:')) {
              final percent = int.tryParse(
                cleanLine.substring('WDS_PROGRESS:'.length),
              );
              if (percent != null) {
                onProgress(percent.clamp(0, 100) / 100.0);
              }
            }
          })
          .asFuture<void>();
      final stderrDone = process.stderr
          .transform(const SystemEncoding().decoder)
          .listen(stderrText.write)
          .asFuture<void>();
      final timeout = linuxRawWriteTimeoutForBytes(imageBytes);
      int exitCode;
      try {
        exitCode = await process.exitCode.timeout(timeout);
      } on TimeoutException {
        await _terminateProcessTree(process, reason: 'Linux write timed out');
        await Future.wait([
          stdoutDone.catchError((_) {}),
          stderrDone.catchError((_) {}),
        ]);
        return _LinuxRawWriteResult(
          success: false,
          error:
              'Linux raw writing timed out after ${timeout.inSeconds} seconds.',
        );
      }
      await Future.wait([
        stdoutDone.catchError((_) {}),
        stderrDone.catchError((_) {}),
      ]);
      if (_cancelRequested) {
        return const _LinuxRawWriteResult(
          success: false,
          cancelled: true,
          error: 'Linux raw writing was cancelled.',
        );
      }
      if (exitCode != 0) {
        final detail = stderrText.toString().trim().isNotEmpty
            ? stderrText.toString().trim()
            : stdoutText.toString().trim();
        return _LinuxRawWriteResult(
          success: false,
          error: detail.isEmpty
              ? 'PowerShell exited with code $exitCode'
              : detail,
        );
      }
      return const _LinuxRawWriteResult(success: true);
    } catch (error) {
      if (process != null) {
        await _terminateProcessTree(process, reason: 'Linux write failed');
      }
      return _LinuxRawWriteResult(
        success: false,
        error: 'Linux raw writing failed: $error',
      );
    } finally {
      if (identical(_activeLinuxRawWriteProcess, process)) {
        _activeLinuxRawWriteProcess = null;
      }
    }
  }

  Future<_LinuxRawWriteResult> _verifyLinuxRawWrite({
    required DiskInfo disk,
    required String isoPath,
    required void Function(double progress) onProgress,
  }) async {
    Process? process;
    try {
      final imageBytes = await File(isoPath).length();
      final timeout = linuxRawVerificationTimeoutForBytes(imageBytes);
      _logLine(
        'Linux full verification timeout: ${timeout.inSeconds}s for '
        '$imageBytes bytes at minimum '
        '$linuxRawVerificationMinimumBytesPerSecond B/s',
      );

      final command = InMemoryPowerShell.build(
        script: _linuxRawVerifyScript,
        parameters: {
          'DiskNumber': '${disk.diskNumber}',
          'IsoPath': isoPath,
          'ExpectedSize': '${disk.sizeBytes}',
          'ExpectedModel': disk.model,
          'ExpectedBus': disk.busType,
          'ExpectedSerial': disk.reliableSerialNumber,
          'ExpectedDevicePath': disk.reliableDevicePath,
          'ExpectedUniqueId': disk.reliableUniqueId,
        },
      );
      process = await Process.start(
        command.executable,
        command.arguments,
        environment: command.environment,
      );
      _activeLinuxVerificationProcess = process;

      final stdoutText = StringBuffer();
      final stderrText = StringBuffer();
      var verified = false;
      final stdoutDone = process.stdout
          .transform(const SystemEncoding().decoder)
          .transform(const LineSplitter())
          .listen((line) {
            final cleanLine = line.trim();
            if (cleanLine.isEmpty) return;
            stdoutText.writeln(cleanLine);
            if (cleanLine == 'OK') verified = true;
            if (cleanLine.startsWith('WDS_VERIFY_PROGRESS:')) {
              final percent = int.tryParse(
                cleanLine.substring('WDS_VERIFY_PROGRESS:'.length),
              );
              if (percent != null) {
                onProgress(percent.clamp(0, 100) / 100.0);
              }
            }
          })
          .asFuture<void>();
      final stderrDone = process.stderr
          .transform(const SystemEncoding().decoder)
          .listen(stderrText.write)
          .asFuture<void>();
      final exitFuture = process.exitCode;
      final deadline = DateTime.now().add(timeout);

      int? exitCode;
      while (exitCode == null) {
        if (_cancelRequested) {
          await _terminateProcessTree(
            process,
            reason: 'Linux verification cancelled',
          );
          await Future.wait([
            stdoutDone.catchError((_) {}),
            stderrDone.catchError((_) {}),
          ]);
          return const _LinuxRawWriteResult(
            success: false,
            cancelled: true,
            error: 'Linux byte-for-byte verification was cancelled.',
          );
        }

        final remaining = deadline.difference(DateTime.now());
        if (remaining <= Duration.zero) {
          await _terminateProcessTree(
            process,
            reason: 'Linux verification timed out',
          );
          await Future.wait([
            stdoutDone.catchError((_) {}),
            stderrDone.catchError((_) {}),
          ]);
          return _LinuxRawWriteResult(
            success: false,
            error:
                'Linux byte-for-byte verification timed out after '
                '${timeout.inSeconds} seconds.',
          );
        }

        final pollDelay = remaining < const Duration(milliseconds: 250)
            ? remaining
            : const Duration(milliseconds: 250);
        exitCode = await Future.any<int?>([
          exitFuture.then<int?>((value) => value),
          Future<int?>.delayed(pollDelay, () => null),
        ]);
      }

      await Future.wait([
        stdoutDone.catchError((_) {}),
        stderrDone.catchError((_) {}),
      ]);
      if (_cancelRequested) {
        return const _LinuxRawWriteResult(
          success: false,
          cancelled: true,
          error: 'Linux byte-for-byte verification was cancelled.',
        );
      }
      if (exitCode != 0 || !verified) {
        final detail = stderrText.toString().trim().isNotEmpty
            ? stderrText.toString().trim()
            : stdoutText.toString().trim();
        _logLine('Verify command failed (exit $exitCode): $detail');
        return _LinuxRawWriteResult(
          success: false,
          error: detail.isEmpty
              ? 'PowerShell verification exited with code $exitCode.'
              : detail,
        );
      }

      onProgress(1.0);
      return const _LinuxRawWriteResult(success: true);
    } catch (error) {
      _logLine('Verify command exception: $error');
      if (process != null) {
        await _terminateProcessTree(
          process,
          reason: 'Linux verification failed',
        );
      }
      return _LinuxRawWriteResult(
        success: false,
        error: 'Linux byte-for-byte verification failed: $error',
      );
    } finally {
      if (identical(_activeLinuxVerificationProcess, process)) {
        _activeLinuxVerificationProcess = null;
      }
    }
  }

  Future<void> _terminateProcessTree(
    Process process, {
    required String reason,
  }) async {
    _logLine('$reason; terminating process tree PID ${process.pid}');
    if (Platform.isWindows) {
      try {
        final result = await Process.run('taskkill', [
          '/PID',
          '${process.pid}',
          '/T',
          '/F',
        ]).timeout(const Duration(seconds: 15));
        _logLine('taskkill PID ${process.pid} exit: ${result.exitCode}');
      } catch (error) {
        _logLine('taskkill PID ${process.pid} failed: $error');
      }
    }
    process.kill(ProcessSignal.sigkill);
    try {
      await process.exitCode.timeout(const Duration(seconds: 10));
    } catch (error) {
      _logLine('Process PID ${process.pid} did not confirm exit: $error');
    }
  }

  Future<ProcessResult> _runLinuxUtility(
    String executable,
    List<String> arguments, {
    required Duration timeout,
  }) async {
    Process? process;
    try {
      process = await Process.start(executable, arguments);
      _activeLinuxUtilityProcess = process;
      final stdoutFuture = process.stdout
          .transform(const SystemEncoding().decoder)
          .join();
      final stderrFuture = process.stderr
          .transform(const SystemEncoding().decoder)
          .join();
      int exitCode;
      try {
        exitCode = await process.exitCode.timeout(timeout);
      } on TimeoutException {
        await _terminateProcessTree(process, reason: '$executable timed out');
        return ProcessResult(
          process.pid,
          -1,
          await stdoutFuture,
          '${await stderrFuture}\nProcess timed out after ${timeout.inSeconds} seconds.',
        );
      }
      return ProcessResult(
        process.pid,
        exitCode,
        await stdoutFuture,
        await stderrFuture,
      );
    } finally {
      if (identical(_activeLinuxUtilityProcess, process)) {
        _activeLinuxUtilityProcess = null;
      }
    }
  }

  static const String _linuxRawWriteScript = r'''
param(
  [Parameter(Mandatory = $true)][int]$DiskNumber,
  [Parameter(Mandatory = $true)][string]$IsoPath,
  [Parameter(Mandatory = $true)][int64]$ExpectedIsoLength,
  [Parameter(Mandatory = $true)][int64]$ExpectedSize,
  [Parameter(Mandatory = $true)][string]$ExpectedModel,
  [Parameter(Mandatory = $true)][string]$ExpectedBus,
  [string]$ExpectedUniqueId = '',
  [string]$ExpectedSerial = '',
  [string]$ExpectedDevicePath = ''
)

$ErrorActionPreference = 'Stop'

function Emit-Progress([int]$Percent, [int64]$Written, [int64]$Total) {
  Write-Output ("WDS_PROGRESS:{0}:{1}:{2}" -f $Percent, $Written, $Total)
}

if (-not (Test-Path -LiteralPath $IsoPath -PathType Leaf)) {
  throw "ISO file not found: $IsoPath"
}

$isoItem = Get-Item -LiteralPath $IsoPath -ErrorAction Stop
if ([int64]$isoItem.Length -ne $ExpectedIsoLength -or $ExpectedIsoLength -le 0) {
  throw "ISO file changed after preflight."
}

$disk = Get-Disk -Number $DiskNumber -ErrorAction Stop
$bus = $disk.BusType.ToString().ToUpperInvariant()
$isExternal = $bus -in @('USB', 'SD', 'MMC') -or [bool]$disk.IsRemovable
if (-not $isExternal -or $disk.IsSystem -or $disk.IsBoot -or $disk.IsOffline) {
  throw "Refusing to write to a disk that is not a safe external target."
}
if ([int64]$disk.Size -ne $ExpectedSize -or
    $disk.FriendlyName.ToString().Trim().ToUpperInvariant() -ne $ExpectedModel.Trim().ToUpperInvariant() -or
    $bus -ne $ExpectedBus.Trim().ToUpperInvariant()) {
  throw "Target disk identity changed after selection."
}
if ($ExpectedSerial -and $ExpectedSerial.Trim().ToUpperInvariant() -notin @('N/A', 'UNKNOWN')) {
  $physical = Get-PhysicalDisk -ErrorAction Stop |
    Where-Object { $_.DeviceId -eq $disk.Number.ToString() } |
    Select-Object -First 1
  $currentSerial = if ($physical -and $physical.SerialNumber) {
    $physical.SerialNumber.ToString().Trim().ToUpperInvariant()
  } else { '' }
  if ($currentSerial -ne $ExpectedSerial.Trim().ToUpperInvariant()) {
    throw "Target disk serial number changed after selection."
  }
} elseif ($ExpectedUniqueId) {
  $currentUniqueId = if ($disk.UniqueId) { $disk.UniqueId.ToString().Trim().ToUpperInvariant() } else { '' }
  if ($currentUniqueId -ne $ExpectedUniqueId.Trim().ToUpperInvariant()) {
    throw "Target disk unique identity changed after selection."
  }
} elseif ($ExpectedDevicePath) {
  $currentPath = if ($disk.Path) { $disk.Path.ToString().Trim().ToUpperInvariant() } else { '' }
  if ($currentPath -ne $ExpectedDevicePath.Trim().ToUpperInvariant()) {
    throw "Target disk device path changed after selection."
  }
} else {
  throw "Target disk has no reliable physical identity."
}

if ($ExpectedIsoLength -ge [int64]$disk.Size) {
  throw "ISO image must be smaller than the target disk."
}
$sourceVolume = Get-Volume -FilePath $IsoPath -ErrorAction Stop
$sourcePartitions = @(Get-Partition -Volume $sourceVolume -ErrorAction Stop)
if ($sourcePartitions.Count -ne 1) {
  throw "ISO source did not resolve to exactly one physical partition."
}
if ([int]$sourcePartitions[0].DiskNumber -eq $DiskNumber) {
  throw "ISO source is stored on the target disk."
}

$source = [System.IO.File]::Open(
  $IsoPath,
  [System.IO.FileMode]::Open,
  [System.IO.FileAccess]::Read,
  [System.IO.FileShare]::Read
)

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
  [Parameter(Mandatory = $true)][string]$IsoPath,
  [Parameter(Mandatory = $true)][int64]$ExpectedSize,
  [Parameter(Mandatory = $true)][string]$ExpectedModel,
  [Parameter(Mandatory = $true)][string]$ExpectedBus,
  [string]$ExpectedSerial = '',
  [string]$ExpectedDevicePath = '',
  [string]$ExpectedUniqueId = ''
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
$targetBus = $targetDisk.BusType.ToString().ToUpperInvariant()
$isExternal = $targetBus -in @('USB', 'SD', 'MMC') -or [bool]$targetDisk.IsRemovable
if (-not $isExternal -or $targetDisk.IsSystem -or $targetDisk.IsBoot -or $targetDisk.IsOffline) {
  throw "The verification target is no longer a safe external disk."
}
if ([int64]$targetDisk.Size -ne $ExpectedSize -or
    $targetDisk.FriendlyName.ToString().Trim().ToUpperInvariant() -ne $ExpectedModel.Trim().ToUpperInvariant() -or
    $targetBus -ne $ExpectedBus.Trim().ToUpperInvariant()) {
  throw "The verification target changed after writing."
}
if ($ExpectedSerial -and $ExpectedSerial.Trim().ToUpperInvariant() -notin @('N/A', 'UNKNOWN')) {
  $physical = Get-PhysicalDisk -ErrorAction Stop |
    Where-Object { $_.DeviceId -eq $targetDisk.Number.ToString() } |
    Select-Object -First 1
  $currentSerial = if ($physical -and $physical.SerialNumber) {
    $physical.SerialNumber.ToString().Trim().ToUpperInvariant()
  } else { '' }
  if ($currentSerial -ne $ExpectedSerial.Trim().ToUpperInvariant()) {
    throw "The verification target serial number changed after writing."
  }
} elseif ($ExpectedUniqueId) {
  $currentUniqueId = if ($targetDisk.UniqueId) { $targetDisk.UniqueId.ToString().Trim().ToUpperInvariant() } else { '' }
  if ($currentUniqueId -ne $ExpectedUniqueId.Trim().ToUpperInvariant()) {
    throw "The verification target unique ID changed after writing."
  }
} elseif ($ExpectedDevicePath) {
  $currentPath = if ($targetDisk.Path) { $targetDisk.Path.ToString().Trim().ToUpperInvariant() } else { '' }
  if ($currentPath -ne $ExpectedDevicePath.Trim().ToUpperInvariant()) {
    throw "The verification target device path changed after writing."
  }
} else {
  throw "The verification target has no reliable physical identity."
}
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

  $bufferLength = 8388608
  $sourceBuffer = New-Object byte[] $bufferLength
  $targetBuffer = New-Object byte[] $bufferLength
  $source.Seek(0, [System.IO.SeekOrigin]::Begin) | Out-Null
  $target.Seek(0, [System.IO.SeekOrigin]::Begin) | Out-Null
  $sourceHash = [System.Security.Cryptography.IncrementalHash]::CreateHash(
    [System.Security.Cryptography.HashAlgorithmName]::SHA256
  )
  $targetHash = [System.Security.Cryptography.IncrementalHash]::CreateHash(
    [System.Security.Cryptography.HashAlgorithmName]::SHA256
  )
  $verified = [int64]0
  $lastPercent = -1
  Write-Output "WDS_VERIFY_PROGRESS:0"
  while ($verified -lt $isoLength) {
    $requested = [int][Math]::Min($bufferLength, $isoLength - $verified)
    $sourceRead = $source.Read($sourceBuffer, 0, $requested)
    $targetRead = $target.Read($targetBuffer, 0, $requested)
    if ($sourceRead -ne $requested -or $targetRead -ne $requested) {
      throw "Short read while verifying at offset $verified."
    }
    $sourceHash.AppendData($sourceBuffer, 0, $requested)
    $targetHash.AppendData($targetBuffer, 0, $requested)
    $verified += $requested
    $percent = [int][Math]::Floor(($verified * 100.0) / $isoLength)
    if ($percent -ne $lastPercent) {
      Write-Output ("WDS_VERIFY_PROGRESS:{0}" -f $percent)
      $lastPercent = $percent
    }
  }

  $sourceDigest = $sourceHash.GetHashAndReset()
  $targetDigest = $targetHash.GetHashAndReset()
  if (-not [System.Linq.Enumerable]::SequenceEqual(
      [byte[]]$sourceDigest,
      [byte[]]$targetDigest
    )) {
    throw "Full-stream SHA-256 verification mismatch."
  }

  Write-Output "OK"
} finally {
  if ($null -ne $targetHash) { $targetHash.Dispose() }
  if ($null -ne $sourceHash) { $sourceHash.Dispose() }
  $target.Dispose()
  $source.Dispose()
}
''';

  // --- Disk Partitioning ---

  Future<_DiskPartResult> _partitionDisk({
    required DiskInfo disk,
    required BootMode bootMode,
    required DeploymentBootMode deploymentBootMode,
    required String preferredDriveLetter,
    required String volumeLabel,
  }) async {
    final diskNumber = disk.diskNumber;
    final requestedLetter = _normalizePreferredLetter(preferredDriveLetter);
    if (preferredDriveLetter.isNotEmpty && requestedLetter == null) {
      return const _DiskPartResult(
        success: false,
        error: 'The requested drive letter is invalid.',
      );
    }
    if (requestedLetter != null &&
        !await _isDriveLetterAvailable(requestedLetter, diskNumber)) {
      return const _DiskPartResult(
        success: false,
        error: 'The requested drive letter is already in use.',
      );
    }
    final label = _sanitizeVolumeLabel(volumeLabel, fallback: 'WDS_BOOT');
    final useGpt = deploymentBootMode == DeploymentBootMode.uefiGpt;
    final activeLine = deploymentBootMode == DeploymentBootMode.legacyBios
        ? 'active'
        : '';
    final assignLine = requestedLetter == null
        ? 'assign'
        : 'assign letter=$requestedLetter';
    final script =
        '''
select disk $diskNumber
clean
convert ${useGpt ? 'gpt' : 'mbr'}
create partition primary
$activeLine
format fs=fat32 label="$label" quick
$assignLine
exit
''';
    _logLine('DiskPart script:\n$script');

    final result = await ref
        .read(diskSafetyServiceProvider)
        .runGuardedDiskpart(disk, script);
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

    final driveLetter = requestedLetter == null
        ? await _findDriveLetterForDisk(diskNumber)
        : '$requestedLetter:';
    if (driveLetter == null) {
      _logLine('Could not find drive letter');
      return _DiskPartResult(
        success: false,
        error: 'Could not find assigned drive letter',
      );
    }

    if (!await _verifyInstallMediaPartition(
      diskNumber: diskNumber,
      driveLetter: driveLetter,
      expectedPartitionStyle: useGpt ? 'GPT' : 'MBR',
      expectedLabel: label,
    )) {
      _logLine('Install media partition postcondition check failed');
      return const _DiskPartResult(
        success: false,
        error: 'Created partition does not match the requested layout.',
      );
    }

    return _DiskPartResult(success: true, driveLetter: driveLetter);
  }

  Future<bool> _verifyInstallMediaPartition({
    required int diskNumber,
    required String driveLetter,
    required String expectedPartitionStyle,
    required String expectedLabel,
  }) async {
    try {
      final letter = driveLetter.replaceAll(RegExp(r'[:\\]'), '').toUpperCase();
      final result = await Process.run(
        'powershell',
        [
          '-NoProfile',
          '-ExecutionPolicy',
          'Bypass',
          '-Command',
          r'''$partition = Get-Partition -DriveLetter $env:WDS_DRIVE_LETTER -ErrorAction Stop
$volume = Get-Volume -DriveLetter $env:WDS_DRIVE_LETTER -ErrorAction Stop
$disk = Get-Disk -Number $partition.DiskNumber -ErrorAction Stop
[PSCustomObject]@{
  DiskNumber = $partition.DiskNumber
  PartitionStyle = $disk.PartitionStyle.ToString()
  Label = $volume.FileSystemLabel
  FileSystem = $volume.FileSystem
} | ConvertTo-Json -Compress''',
        ],
        environment: {...Platform.environment, 'WDS_DRIVE_LETTER': letter},
      ).timeout(const Duration(seconds: 8));
      if (result.exitCode != 0) return false;
      final data = jsonDecode(result.stdout.toString());
      return data is Map &&
          data['DiskNumber'].toString() == diskNumber.toString() &&
          data['PartitionStyle'].toString().toUpperCase() ==
              expectedPartitionStyle.toUpperCase() &&
          data['Label'].toString().toUpperCase() ==
              expectedLabel.toUpperCase() &&
          data['FileSystem'].toString().toUpperCase() == 'FAT32';
    } catch (error) {
      _logLine('Install media partition verification error: $error');
      return false;
    }
  }

  String? _normalizePreferredLetter(String value) {
    final normalized = value
        .trim()
        .replaceAll(RegExp(r'[:\\]'), '')
        .toUpperCase();
    if (normalized.isEmpty) return null;
    return RegExp(r'^[D-Z]$').hasMatch(normalized) ? normalized : null;
  }

  Future<bool> _isDriveLetterAvailable(String letter, int diskNumber) async {
    try {
      final result = await Process.run(
        'powershell',
        const [
          '-NoProfile',
          '-ExecutionPolicy',
          'Bypass',
          '-Command',
          r'''$partition = Get-Partition -DriveLetter $env:WDS_LETTER -ErrorAction SilentlyContinue
if (-not $partition) { exit 0 }
if ($partition.DiskNumber -eq [int]$env:WDS_DISK_NUMBER) { exit 0 }
exit 1''',
        ],
        environment: {
          ...Platform.environment,
          'WDS_LETTER': letter,
          'WDS_DISK_NUMBER': '$diskNumber',
        },
      ).timeout(const Duration(seconds: 8));
      return result.exitCode == 0;
    } catch (_) {
      return false;
    }
  }

  String _sanitizeVolumeLabel(String value, {required String fallback}) {
    final sanitized = value
        .trim()
        .replaceAll(RegExp(r'["*/:<>?\\|+,;=\[\]]'), '')
        .trim();
    if (sanitized.isEmpty) return fallback;
    return sanitized.length > 11 ? sanitized.substring(0, 11) : sanitized;
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
    bool excludeAutoUnattend = true,
    Set<String> excludedExtensions = const {},
    void Function(double progress)? onProgress,
  }) async {
    try {
      final srcDir = mountPoint.endsWith('\\') ? mountPoint : '$mountPoint\\';
      final dstDir = targetDrive.endsWith('\\')
          ? targetDrive
          : '$targetDrive\\';
      _logLine('robocopy: $srcDir -> $dstDir');

      final excludedNames = <String>{
        if (excludeWim) ...['install.wim', 'install.esd'],
        if (excludeAutoUnattend) ...['AutoUnattend.xml', 'autounattend.xml'],
      };
      final normalizedExtensions = excludedExtensions
          .map(
            (extension) =>
                extension.replaceFirst(RegExp(r'^\.'), '').toLowerCase(),
          )
          .where((extension) => extension.isNotEmpty)
          .toSet();

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

      final excludedPatterns = <String>[
        if (excludeWim) ...['install.wim', 'install.esd'],
        if (excludeAutoUnattend) ...['AutoUnattend.xml', 'autounattend.xml'],
        ...normalizedExtensions.map((extension) => '*.$extension'),
      ];
      if (excludedPatterns.isNotEmpty) {
        args.addAll(['/XF', ...excludedPatterns]);
      }

      _logLine('robocopy args: ${args.join(" ")}');

      final totalBytes = await _directorySize(
        srcDir,
        excludedNames: excludedNames,
        excludedExtensions: normalizedExtensions,
      );
      _logLine('robocopy total bytes: $totalBytes');

      onProgress?.call(0.0);

      final process = await Process.start('robocopy', args);
      final stdoutBuffer = StringBuffer();
      final stderrBuffer = StringBuffer();
      final stdoutSub = process.stdout
          .transform(const Utf8Decoder(allowMalformed: true))
          .listen(stdoutBuffer.write);
      final stderrSub = process.stderr
          .transform(const Utf8Decoder(allowMalformed: true))
          .listen(stderrBuffer.write);

      var completed = false;
      final exitFuture = process.exitCode.then((code) {
        completed = true;
        return code;
      });

      var lastLoggedPercent = -1;
      while (!completed) {
        await Future.any([
          exitFuture,
          Future<void>.delayed(const Duration(seconds: 1)),
        ]);

        if (totalBytes <= 0) continue;

        final copiedBytes = await _directorySize(
          dstDir,
          excludedNames: excludedNames,
          excludedExtensions: normalizedExtensions,
        );
        final progress = (copiedBytes / totalBytes).clamp(0.0, 0.99);
        onProgress?.call(progress);

        final percent = (progress * 100).floor();
        if (percent >= lastLoggedPercent + 10) {
          lastLoggedPercent = percent;
          _logLine(
            'robocopy progress: $percent% ($copiedBytes / $totalBytes bytes)',
          );
        }
      }

      final exitCode = await exitFuture;
      await stdoutSub.cancel();
      await stderrSub.cancel();

      // Only 0-3 are accepted. Codes 4-7 report mismatched files and must fail
      // before any later boot or content verification is trusted.
      // 0 = no files copied (already up to date)
      // 1 = files copied successfully
      // 2 = extra files in destination
      // 3 = files copied + extra files
      _logLine('robocopy exit: $exitCode');

      if (!isAcceptedRobocopyExitCode(exitCode)) {
        _logLine('robocopy FAILED: ${stderrBuffer.toString().trim()}');
        _logLine('robocopy stdout: ${stdoutBuffer.toString().trim()}');
        return false;
      }

      final contentVerified = await _verifyCopiedTree(
        sourceRoot: srcDir,
        targetRoot: dstDir,
        excludedNames: excludedNames,
        excludedExtensions: normalizedExtensions,
      );
      if (!contentVerified) {
        _logLine('robocopy content verification FAILED');
        return false;
      }

      onProgress?.call(1.0);
      _logLine('robocopy OK');
      return true;
    } catch (e) {
      _logLine('robocopy error: $e');
      return false;
    }
  }

  Future<bool> _verifyCopiedTree({
    required String sourceRoot,
    required String targetRoot,
    required Set<String> excludedNames,
    required Set<String> excludedExtensions,
  }) async {
    final excluded = excludedNames.map((name) => name.toLowerCase()).toSet();
    var verifiedFiles = 0;
    var verifiedBytes = 0;
    try {
      await for (final entity in Directory(
        sourceRoot,
      ).list(recursive: true, followLinks: false)) {
        if (entity is! File) continue;
        if (excluded.contains(p.basename(entity.path).toLowerCase())) continue;
        final extension = p
            .extension(entity.path)
            .replaceFirst('.', '')
            .toLowerCase();
        if (excludedExtensions.contains(extension)) continue;

        final relativePath = p.relative(entity.path, from: sourceRoot);
        final target = File(p.join(targetRoot, relativePath));
        final sourceBytes = await entity.length();
        if (!await target.exists() || await target.length() != sourceBytes) {
          _logLine('Copy verification missing/truncated: $relativePath');
          return false;
        }
        final sourceDigest = (await sha256.bind(entity.openRead()).first)
            .toString();
        final targetDigest = (await sha256.bind(target.openRead()).first)
            .toString();
        if (sourceDigest != targetDigest) {
          _logLine(
            'Copy verification SHA-256 mismatch: $relativePath '
            '(source=$sourceDigest, target=$targetDigest)',
          );
          return false;
        }
        verifiedFiles++;
        verifiedBytes += sourceBytes;
      }
      _logLine(
        'Copy content verification OK: $verifiedFiles files, '
        '$verifiedBytes bytes',
      );
      return true;
    } catch (error) {
      _logLine('Copy content verification error: $error');
      return false;
    }
  }

  Future<int> _directorySize(
    String rootPath, {
    Set<String> excludedNames = const {},
    Set<String> excludedExtensions = const {},
  }) async {
    final root = Directory(rootPath);
    if (!await root.exists()) return 0;

    final excluded = excludedNames.map((name) => name.toLowerCase()).toSet();
    final excludedSuffixes = excludedExtensions
        .map(
          (extension) =>
              extension.replaceFirst(RegExp(r'^\.'), '').toLowerCase(),
        )
        .where((extension) => extension.isNotEmpty)
        .toSet();
    var total = 0;

    try {
      await for (final entity in root.list(
        recursive: true,
        followLinks: false,
      )) {
        if (entity is! File) continue;
        if (excluded.contains(p.basename(entity.path).toLowerCase())) continue;
        final extension = p
            .extension(entity.path)
            .replaceFirst('.', '')
            .toLowerCase();
        if (excludedSuffixes.contains(extension)) continue;

        try {
          total += await entity.length();
        } catch (_) {
          // Files can appear or disappear while robocopy is still working.
        }
      }
    } catch (e) {
      _logLine('directory size scan skipped: $rootPath ($e)');
    }

    return total;
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
    required String expectedIconSha256,
    required String expectedVolumeLabel,
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

    final iconFile = File('$driveLetter\\intel.ico');
    if (!await iconFile.exists()) {
      errors.add('volume icon missing');
    } else {
      final actualIconDigest = (await sha256.bind(iconFile.openRead()).first)
          .toString();
      if (actualIconDigest != expectedIconSha256) {
        errors.add('volume icon content mismatch');
      }
    }
    final autorunFile = File('$driveLetter\\autorun.inf');
    if (!await autorunFile.exists()) {
      errors.add('autorun.inf missing');
    } else {
      final autorun = (await autorunFile.readAsString())
          .replaceAll('\r\n', '\n')
          .trim();
      final label = _sanitizeVolumeLabel(
        expectedVolumeLabel,
        fallback: 'WINDEPLOY',
      );
      final expectedAutorun = '[autorun]\nicon=intel.ico\nlabel=$label';
      if (autorun != expectedAutorun) {
        errors.add('autorun.inf content mismatch');
      }
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

  Future<_VolumeIconPreparation> _prepareVolumeIcon(
    String customIconPath,
  ) async {
    try {
      final requestedPath = customIconPath.trim();
      final Uint8List iconData;
      if (requestedPath.isNotEmpty) {
        if (p.extension(requestedPath).toLowerCase() != '.ico') {
          return const _VolumeIconPreparation.failure(
            'Custom volume icon must be an ICO file.',
          );
        }
        if (await FileSystemEntity.type(requestedPath, followLinks: false) !=
            FileSystemEntityType.file) {
          return const _VolumeIconPreparation.failure(
            'The requested custom volume icon does not exist or is not a regular file.',
          );
        }
        final file = File(requestedPath);
        if (await file.length() > 16 * 1024 * 1024) {
          return const _VolumeIconPreparation.failure(
            'Custom volume icon exceeds the 16 MiB safety limit.',
          );
        }
        iconData = await file.readAsBytes();
        _logLine('Custom volume icon validated before erase: $requestedPath');
      } else {
        final iconBytes = await rootBundle.load('assets/intel.ico');
        iconData = iconBytes.buffer.asUint8List(
          iconBytes.offsetInBytes,
          iconBytes.lengthInBytes,
        );
      }

      final validationError = validateIcoBytes(iconData);
      if (validationError != null) {
        return _VolumeIconPreparation.failure(validationError);
      }
      return _VolumeIconPreparation.success(
        _VolumeIconPayload(
          bytes: Uint8List.fromList(iconData),
          sha256Digest: sha256.convert(iconData).toString(),
        ),
      );
    } catch (error) {
      return _VolumeIconPreparation.failure(
        'Volume icon validation failed: $error',
      );
    }
  }

  Future<bool> _setVolumeIcon(
    String driveLetter, {
    required _VolumeIconPayload icon,
    required String volumeLabel,
  }) async {
    try {
      // Copy icon to USB root
      final iconDest = File('$driveLetter\\intel.ico');
      await iconDest.writeAsBytes(icon.bytes, flush: true);
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

      final label = _sanitizeVolumeLabel(volumeLabel, fallback: 'WINDEPLOY');
      await autorunFile.writeAsString(
        '[autorun]\nicon=intel.ico\nlabel=$label\n',
        flush: true,
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

      final writtenDigest = (await sha256.bind(iconDest.openRead()).first)
          .toString();
      final autorun = (await autorunFile.readAsString())
          .replaceAll('\r\n', '\n')
          .trim();
      if (writtenDigest != icon.sha256Digest ||
          autorun != '[autorun]\nicon=intel.ico\nlabel=$label') {
        throw StateError(
          'Volume icon or autorun.inf content verification failed.',
        );
      }
      _logLine('Volume icon set OK');
      return true;
    } catch (e) {
      _logLine('Volume icon error: $e');
      return false;
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

class _VolumeIconPayload {
  final Uint8List bytes;
  final String sha256Digest;

  const _VolumeIconPayload({required this.bytes, required this.sha256Digest});
}

class _VolumeIconPreparation {
  final _VolumeIconPayload? payload;
  final String? error;

  const _VolumeIconPreparation._({this.payload, this.error});

  const _VolumeIconPreparation.success(_VolumeIconPayload payload)
    : this._(payload: payload);

  const _VolumeIconPreparation.failure(String error) : this._(error: error);

  bool get success => error == null;
}

class _LinuxRawWriteResult {
  final bool success;
  final String? error;
  final bool cancelled;

  const _LinuxRawWriteResult({
    required this.success,
    this.error,
    this.cancelled = false,
  });
}

class _LinuxToGoPreflight {
  final bool success;
  final String? error;
  final int totalContentBytes;
  final int bootContentBytes;
  final List<_LinuxToGoPayload> livePayloads;

  const _LinuxToGoPreflight({
    required this.success,
    this.error,
    this.totalContentBytes = 0,
    this.bootContentBytes = 0,
    this.livePayloads = const [],
  });
}

class _LinuxToGoPayload {
  final String relativePath;
  final int sizeBytes;

  const _LinuxToGoPayload({
    required this.relativePath,
    required this.sizeBytes,
  });
}

class _LinuxToGoPartitionResult {
  final bool success;
  final String? bootDrive;
  final String? liveDrive;
  final String? error;

  const _LinuxToGoPartitionResult({
    required this.success,
    this.bootDrive,
    this.liveDrive,
    this.error,
  });
}

class _LinuxToGoDriveLetters {
  final String bootLetter;
  final String liveLetter;

  const _LinuxToGoDriveLetters({
    required this.bootLetter,
    required this.liveLetter,
  });
}
