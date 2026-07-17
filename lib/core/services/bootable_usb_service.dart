import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'bootable_media_validation.dart';
import 'background_file_hash_service.dart';
import 'file_logger_service.dart';
import 'disk_safety_service.dart';
import 'in_memory_powershell.dart';
import 'linux_driver_staging_service.dart';
import 'linux_media_preflight.dart';
import 'linux_togo_image_preflight.dart';
import 'windows_iso_preflight.dart';
import 'windows_system_environment.dart';
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
  static const String _linuxToGoIconFileName = '.wds-drive.ico';
  static const String _casperPersistenceFileName = 'writable';
  static const String _casperPersistenceVolumeLabel = 'writable';
  static const String _debianPersistenceFileName = 'persistence';
  static const String _debianPersistenceVolumeLabel = 'persistence';
  static const String _debianPersistenceConfiguration = '/ union\n';
  static const String _ext4BuilderExecutableName = 'wds_ext4_builder.exe';
  static const int _fat32NativeFormatLimitBytes = 32 * 1024 * 1024 * 1024;
  static const int _fat32BootPartitionSizeMb = 32760;
  static const int _installMediaCapacityReserveBytes = 64 * 1024 * 1024;
  static const int _wimSplitCapacityReserveBytes = 64 * 1024 * 1024;
  static const String _ext4BuilderSha256 =
      '85f4c3e74f6e005ecf94e0d688e1de6d35b715af21716151c4a23e9f52ab6184';

  /// The bundled helper is a narrow MIT-licensed ext4 image writer with its
  /// pinned source and notices in tools/ext4-builder. This is intentionally
  /// unrelated to the excluded GPL e2fsprogs distribution.
  static const bool linuxPersistenceToolDistributionApproved = true;

  @visibleForTesting
  static String linuxToGoPersistenceFileNameForFamily(
    LinuxToGoImageFamily family,
  ) => switch (family) {
    LinuxToGoImageFamily.casper => _casperPersistenceFileName,
    LinuxToGoImageFamily.debianLive => _debianPersistenceFileName,
    LinuxToGoImageFamily.deepinLive => _debianPersistenceFileName,
  };

  @visibleForTesting
  static String linuxToGoPersistenceArgumentForFamily(
    LinuxToGoImageFamily family,
  ) => switch (family) {
    LinuxToGoImageFamily.casper => 'persistent',
    LinuxToGoImageFamily.debianLive => 'persistence',
    LinuxToGoImageFamily.deepinLive => 'persistence',
  };

  final Ref ref;
  final List<String> _log = [];
  bool _cancelRequested = false;
  Process? _activeLinuxRawWriteProcess;
  Process? _activeLinuxUtilityProcess;

  BootableUsbService(this.ref);

  Future<ProcessResult> _runPowerShell(
    List<String> arguments, {
    Map<String, String>? environment,
    Duration? timeout,
  }) {
    final resolvedEnvironment = WindowsSystemEnvironment.withSystemRoot(
      environment,
    );
    // `Future.timeout` only stops waiting for Process.run; it leaves a stuck
    // Storage cmdlet alive. The bounded paths below use the existing managed
    // process runner so a timeout also terminates the direct PowerShell tree.
    if (timeout != null) {
      return _runLinuxUtility(
        WindowsSystemEnvironment.powerShellExecutable,
        arguments,
        timeout: timeout,
        environment: resolvedEnvironment,
        trackForCancellation: false,
      );
    }
    return Process.run(
      WindowsSystemEnvironment.powerShellExecutable,
      arguments,
      environment: resolvedEnvironment,
    );
  }

  void cancel() {
    _cancelRequested = true;
    final processes = {
      ?_activeLinuxRawWriteProcess,
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

  // The previous standalone verifier is no longer used at runtime: raw
  // verification now stays in the writer process. Keep it available to the
  // parser contract until the compatibility script can be removed entirely.
  @visibleForTesting
  static String get linuxRawVerifyScriptForTesting => _linuxRawVerifyScript;

  @visibleForTesting
  static String get linuxRawFinalizeScriptForTesting => _linuxRawFinalizeScript;

  @visibleForTesting
  static String summarizePowerShellFailureForTesting(String raw) =>
      _summarizePowerShellFailure(raw, fallback: 'PowerShell command failed.');

  @visibleForTesting
  static String linuxToGoVolumeLabelForTesting(String value) =>
      _sanitizeLinuxToGoVolumeLabel(value);

  @visibleForTesting
  static String linuxToGoLiveMediaArgumentForTesting(String ntfsUuid) =>
      _linuxToGoLiveMediaArgument(ntfsUuid);

  @visibleForTesting
  static String linuxToGoAutorunForTesting({required bool hasCustomIcon}) =>
      _linuxToGoAutorunText(hasCustomIcon: hasCustomIcon);

  @visibleForTesting
  static String linuxToGoDiskpartScriptForTesting({
    required int diskNumber,
    required int bootPartitionSizeMb,
    required String bootLetter,
    required String liveLetter,
    required String liveVolumeLabel,
    String currentPartitionStyle = 'Unknown',
  }) => _buildLinuxToGoDiskpartScript(
    diskNumber: diskNumber,
    bootPartitionSizeMb: bootPartitionSizeMb,
    bootLetter: bootLetter,
    liveLetter: liveLetter,
    liveVolumeLabel: liveVolumeLabel,
    currentPartitionStyle: currentPartitionStyle,
  );

  @visibleForTesting
  static String installMediaDiskpartScriptForTesting({
    required int diskNumber,
    required String currentPartitionStyle,
    required DeploymentBootMode deploymentBootMode,
    required String volumeLabel,
    String preferredDriveLetter = '',
    int? diskSizeBytes,
  }) => _buildInstallMediaDiskpartScript(
    diskNumber: diskNumber,
    currentPartitionStyle: currentPartitionStyle,
    deploymentBootMode: deploymentBootMode,
    preferredDriveLetter: preferredDriveLetter,
    volumeLabel: volumeLabel,
    diskSizeBytes: diskSizeBytes,
  );

  @visibleForTesting
  static bool installMediaPartitionMatchesForTesting({
    required Map<String, Object?> actual,
    required int expectedDiskNumber,
    required String expectedPartitionStyle,
    required String expectedLabel,
    bool? expectedEfiSystemPartition,
    bool? expectedActive,
  }) => _installMediaPartitionMatches(
    actual,
    expectedDiskNumber: expectedDiskNumber,
    expectedPartitionStyle: expectedPartitionStyle,
    expectedLabel: expectedLabel,
    expectedEfiSystemPartition: expectedEfiSystemPartition,
    expectedActive: expectedActive,
  );

  @visibleForTesting
  static bool linuxToGoCustomIconMatchesForTesting({
    required String actualDigest,
    required String expectedDigest,
    required String autorunText,
  }) => _matchesLinuxToGoCustomIcon(
    actualDigest: actualDigest,
    expectedDigest: expectedDigest,
    autorunText: autorunText,
  );

  @visibleForTesting
  static String? linuxToGoNtfsUuidFromFsutilForTesting(String output) =>
      _extractLinuxToGoNtfsUuid(output);

  @visibleForTesting
  static bool isRemoteInstallMediaUncPathForTesting(String path) =>
      _isRemoteInstallMediaUncPath(path);

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
    var windowsInstallIsoMounted = false;

    Future<void> unmountWindowsInstallIsoIfNeeded() async {
      if (!windowsInstallIsoMounted) return;
      windowsInstallIsoMounted = false;
      await _unmountWindowsInstallIso(isoPath);
    }

    late final DeploymentBootMode deploymentBootMode;
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
      deploymentBootMode = plan.bootMode;
      bootMode = switch (plan.bootMode) {
        DeploymentBootMode.uefiGpt => BootMode.uefi,
        // UEFI + MBR is still UEFI-only. Treating it as a dual-boot target
        // made the creator require a BIOS chain without marking the MBR
        // partition active, so it could report a misleading success.
        DeploymentBootMode.uefiMbr => BootMode.uefi,
        DeploymentBootMode.legacyBios => BootMode.bios,
      };
    } else {
      deploymentBootMode = switch (bootMode) {
        BootMode.uefi => DeploymentBootMode.uefiMbr,
        BootMode.bios || BootMode.both => DeploymentBootMode.legacyBios,
      };
    }
    final diskNumber = disk.diskNumber;
    _log.clear();
    _logLine('=== Create Windows Installation Media Start ===');
    _logLine('Disk: $diskNumber, ISO: $isoPath, Mode: $bootMode');

    final sourceInspection = await ref
        .read(windowsIsoPreflightProvider)
        .inspect(isoPath);
    if (!sourceInspection.isValid) {
      _logLine(
        'Windows ISO preflight failed before erase: '
        '${sourceInspection.error ?? "unknown layout error"}',
      );
      _notify(
        onProgress,
        const CreateProgress(
          step: CreateStep.failed,
          message: 'creator_invalid_windows_iso',
        ),
      );
      return false;
    }

    final mediaPreflight = await _preflightWindowsInstallMediaBeforeErase(
      isoPath: isoPath,
      disk: disk,
      bootMode: bootMode,
      sourceInspection: sourceInspection,
    );
    if (!mediaPreflight.success) {
      final error =
          mediaPreflight.error ??
          'Windows installation media preflight did not complete.';
      _logLine(
        'Windows installation-media preflight failed before erase: $error',
      );
      _notify(
        onProgress,
        CreateProgress(
          step: CreateStep.failed,
          message: 'boot_preflight_failed',
          error: 'i18n:${mediaPreflight.messageKey ?? 'boot_preflight_failed'}',
        ),
      );
      return false;
    }

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
      if (!volumeIcon.success) {
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

      final effectiveVolumeLabel = _sanitizeVolumeLabel(
        plan?.customVolumeLabel ?? '',
        fallback: 'WDS_BOOT',
      );
      if (volumeIcon.payload == null) {
        _logLine(
          'No custom volume icon selected; Windows will use its default drive icon.',
        );
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
        deploymentBootMode: deploymentBootMode,
        preferredDriveLetter: plan?.preferredSystemLetter ?? '',
        volumeLabel: effectiveVolumeLabel,
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

      final mountPoint = await _mountWindowsInstallIso(isoPath);
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
      windowsInstallIsoMounted = true;

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
        if (wimSize > WindowsIsoLayoutInspector.fat32MaximumFileBytes) {
          needSplit = true;
          _logLine('install.wim > 4GB, will split');
        }
      } else if (hasEsd) {
        wimSource = installEsd;
        final esdSize = await File(installEsd).length();
        if (esdSize > WindowsIsoLayoutInspector.fat32MaximumFileBytes) {
          _logLine('install.esd exceeds FAT32 and cannot be split safely.');
          await unmountWindowsInstallIsoIfNeeded();
          _notify(
            onProgress,
            const CreateProgress(
              step: CreateStep.failed,
              message: 'boot_split_failed',
            ),
          );
          return false;
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
        await unmountWindowsInstallIsoIfNeeded();
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
          dismExecutable: mediaPreflight.dismExecutable,
        );

        if (!splitResult) {
          _logLine('WIM split FAILED');
          await unmountWindowsInstallIsoIfNeeded();
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
        targetDrive: driveLetter,
        bootMode: bootMode,
        sourceEfiBootArchitectures: mediaPreflight.efiBootArchitectures,
        sourceEfiBootManagerArchitecture:
            mediaPreflight.efiBootManagerArchitecture,
        legacyBootsectExecutable: mediaPreflight.legacyBootsectExecutable,
      );

      await unmountWindowsInstallIsoIfNeeded();

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

      // Step 8.5: Apply a user-supplied icon only. A blank selection means
      // the removable drive should retain the normal Windows Explorer icon.
      if (volumeIcon.payload != null) {
        _notify(
          onProgress,
          const CreateProgress(
            step: CreateStep.writingBootFiles,
            message: 'boot_setting_icon',
            progress: 0.85,
          ),
        );
      }
      final iconSet = volumeIcon.payload == null
          ? await _clearCustomVolumeIdentity(driveLetter)
          : await _setVolumeIcon(
              driveLetter,
              icon: volumeIcon.payload!,
              volumeLabel: effectiveVolumeLabel,
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
        expectedEfiBootArchitectures: mediaPreflight.efiBootArchitectures,
        expectedIcon: volumeIcon.payload,
        expectedVolumeLabel: effectiveVolumeLabel,
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
      await unmountWindowsInstallIsoIfNeeded();
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

  /// Performs the media-specific checks that must finish before the selected
  /// disk is initialized. The generic ISO inspector proves that this is a
  /// Windows layout; this method proves that the requested boot mode can be
  /// written to a single FAT32 removable-media volume.
  Future<_WindowsInstallMediaPreflightResult>
  _preflightWindowsInstallMediaBeforeErase({
    required String isoPath,
    required DiskInfo disk,
    required BootMode bootMode,
    required WindowsIsoLayoutInspection sourceInspection,
  }) async {
    try {
      final isRemoteUncSource = _isRemoteInstallMediaUncPath(isoPath);
      final source = File(
        isRemoteUncSource ? isoPath : p.normalize(p.absolute(isoPath)),
      );
      if (await FileSystemEntity.type(source.path, followLinks: false) !=
          FileSystemEntityType.file) {
        return const _WindowsInstallMediaPreflightResult.failure(
          'The Windows ISO source must be a regular file, not a link or directory.',
          messageKey: 'boot_preflight_source_invalid',
        );
      }
      if (isRemoteUncSource) {
        _logLine(
          'Windows ISO source is a non-loopback UNC path; it cannot reside on '
          'the selected local physical target disk.',
        );
      } else {
        final resolvedSourcePath = await source.resolveSymbolicLinks();
        final sourceOnTarget = await _isWindowsInstallMediaPathOnTargetDisk(
          resolvedSourcePath,
          disk.diskNumber,
        );
        if (sourceOnTarget == null) {
          return const _WindowsInstallMediaPreflightResult.failure(
            'The physical disk containing the Windows ISO could not be verified.',
            messageKey: 'boot_preflight_source_location',
          );
        }
        if (sourceOnTarget) {
          return const _WindowsInstallMediaPreflightResult.failure(
            'The Windows ISO is stored on the target disk and would be erased.',
            messageKey: 'boot_preflight_source_target',
          );
        }
      }

      final fat32Check = await _validateWindowsInstallMediaFat32Capacity(
        sourceInspection: sourceInspection,
        diskSizeBytes: disk.sizeBytes,
      );
      if (!fat32Check.success) {
        return _WindowsInstallMediaPreflightResult.failure(
          fat32Check.error!,
          messageKey: fat32Check.messageKey ?? 'boot_preflight_failed',
        );
      }

      final availableEfiArchitectures = <WindowsEfiBootArchitecture>{
        ...sourceInspection.efiBootArchitectures,
      };
      final efiBootManagerArchitecture =
          sourceInspection.efiBootManagerArchitecture;
      if (bootMode != BootMode.bios && !sourceInspection.hasEfiBcd) {
        return const _WindowsInstallMediaPreflightResult.failure(
          'UEFI mode requires EFI\\Microsoft\\Boot\\BCD in the Windows ISO.',
          messageKey: 'boot_preflight_uefi_layout',
        );
      }
      if (bootMode != BootMode.bios &&
          availableEfiArchitectures.isEmpty &&
          efiBootManagerArchitecture == null) {
        return const _WindowsInstallMediaPreflightResult.failure(
          'This Windows ISO has no valid x64, ARM64, or IA32 UEFI fallback boot file.',
          messageKey: 'boot_preflight_uefi',
        );
      }
      if (bootMode != BootMode.bios &&
          availableEfiArchitectures.isEmpty &&
          efiBootManagerArchitecture != null) {
        // The source has no removable-media fallback file, but its Microsoft
        // boot manager has a verified architecture and can be copied once to
        // the correctly named fallback path after the ISO content is copied.
        availableEfiArchitectures.add(efiBootManagerArchitecture);
      }

      String? bootsectExecutable;
      if (bootMode != BootMode.uefi) {
        if (!sourceInspection.hasBiosBootManager ||
            !sourceInspection.hasBiosBcd) {
          return const _WindowsInstallMediaPreflightResult.failure(
            'Legacy BIOS mode requires both bootmgr and boot\\BCD in the Windows ISO.',
            messageKey: 'boot_preflight_legacy_layout',
          );
        }
        bootsectExecutable = await _findWindowsSystemTool('bootsect.exe');
        if (bootsectExecutable == null) {
          return const _WindowsInstallMediaPreflightResult.failure(
            'Legacy BIOS mode requires bootsect.exe, but it is unavailable on this computer.',
            messageKey: 'boot_preflight_bootsect',
          );
        }
      }

      String? dismExecutable;
      if (fat32Check.needsWimSplit) {
        if (sourceInspection.imageFormat != WindowsInstallImageFormat.wim) {
          return const _WindowsInstallMediaPreflightResult.failure(
            'An install.esd or install.swm larger than FAT32 supports cannot be split safely. Use a Windows ISO with install.wim or a smaller image.',
            messageKey: 'boot_preflight_fat32_file',
          );
        }
        dismExecutable = await _findWindowsSystemTool('dism.exe');
        if (dismExecutable == null) {
          return const _WindowsInstallMediaPreflightResult.failure(
            'install.wim must be split for FAT32, but DISM is unavailable on this computer.',
            messageKey: 'boot_preflight_dism',
          );
        }
      }

      _logLine(
        'Windows install-media preflight passed: source disk differs from '
        'target, payload=${sourceInspection.totalFileBytes} bytes, '
        'UEFI=${availableEfiArchitectures.map((value) => value.name).join(',')}.',
      );
      return _WindowsInstallMediaPreflightResult.success(
        efiBootArchitectures: availableEfiArchitectures,
        efiBootManagerArchitecture: efiBootManagerArchitecture,
        legacyBootsectExecutable: bootsectExecutable,
        dismExecutable: dismExecutable,
        needsWimSplit: fat32Check.needsWimSplit,
      );
    } catch (error) {
      return _WindowsInstallMediaPreflightResult.failure(
        'Windows installation-media preflight failed: $error',
        messageKey: 'boot_preflight_failed',
      );
    }
  }

  Future<_WindowsInstallMediaFat32Check>
  _validateWindowsInstallMediaFat32Capacity({
    required WindowsIsoLayoutInspection sourceInspection,
    required int diskSizeBytes,
  }) async {
    if (sourceInspection.totalFileBytes <= 0 || diskSizeBytes <= 0) {
      return const _WindowsInstallMediaFat32Check.failure(
        'The Windows ISO payload size or target disk capacity could not be verified.',
        messageKey: 'boot_preflight_capacity',
      );
    }

    var needsWimSplit = false;
    for (final file in sourceInspection.fat32OversizedFiles) {
      final normalizedPath = file.relativePath
          .replaceAll('/', r'\\')
          .toLowerCase();
      if (normalizedPath == r'sources\install.wim' &&
          sourceInspection.imageFormat == WindowsInstallImageFormat.wim) {
        needsWimSplit = true;
        continue;
      }
      return _WindowsInstallMediaFat32Check.failure(
        '${file.relativePath} is larger than the FAT32 single-file limit and cannot be copied to UEFI-compatible installation media.',
        messageKey: 'boot_preflight_fat32_file',
      );
    }

    if (sourceInspection.installImageBytes >
            WindowsIsoLayoutInspector.fat32MaximumFileBytes &&
        sourceInspection.imageFormat != WindowsInstallImageFormat.wim) {
      return const _WindowsInstallMediaFat32Check.failure(
        'The Windows install image is larger than FAT32 supports and is not an install.wim that DISM can split.',
        messageKey: 'boot_preflight_fat32_file',
      );
    }

    final fat32CapacityBytes = _installMediaFat32CapacityBytes(diskSizeBytes);
    final requiredBytes =
        sourceInspection.totalFileBytes +
        (needsWimSplit ? _wimSplitCapacityReserveBytes : 0);
    if (requiredBytes + _installMediaCapacityReserveBytes >
        fat32CapacityBytes) {
      return _WindowsInstallMediaFat32Check.failure(
        'The target FAT32 installation-media partition is too small '
        '(needs at least ${requiredBytes + _installMediaCapacityReserveBytes} bytes; '
        'has $fat32CapacityBytes bytes).',
        messageKey: 'boot_preflight_capacity',
      );
    }
    return _WindowsInstallMediaFat32Check.success(needsWimSplit: needsWimSplit);
  }

  static int _installMediaFat32CapacityBytes(int diskSizeBytes) {
    if (diskSizeBytes <= 0) return 0;
    final cappedSizeMb = _fat32PartitionSizeMbForDisk(diskSizeBytes);
    return cappedSizeMb == null ? diskSizeBytes : cappedSizeMb * 1024 * 1024;
  }

  static bool _isRemoteInstallMediaUncPath(String path) {
    final normalized = path.trim().replaceAll('/', r'\');
    if (!normalized.startsWith(r'\\')) return false;
    final components = normalized.substring(2).split(r'\');
    if (components.length < 2 || components.first.trim().isEmpty) return false;
    final host = components.first.trim().toLowerCase();
    final localNames = <String>{
      'localhost',
      '127.0.0.1',
      '[::1]',
      '::1',
      Platform.localHostname.toLowerCase(),
      (Platform.environment['COMPUTERNAME'] ?? '').trim().toLowerCase(),
    }..remove('');
    return !localNames.contains(host);
  }

  /// Resolves the source only for the Windows install-media preflight.  It is
  /// deliberately separate from the Linux raw-write resolver so hardening a
  /// Windows installer does not alter the Linux To Go creation path.
  Future<bool?> _isWindowsInstallMediaPathOnTargetDisk(
    String path,
    int targetDiskNumber,
  ) async {
    try {
      final result = await _runPowerShell(
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
        timeout: const Duration(seconds: 10),
      );
      if (result.exitCode != 0) {
        _logLine('Windows ISO source disk resolution failed: ${result.stderr}');
        return null;
      }
      final sourceDiskNumber = int.tryParse(result.stdout.toString().trim());
      return sourceDiskNumber == null
          ? null
          : sourceDiskNumber == targetDiskNumber;
    } catch (error) {
      _logLine('Windows ISO source disk resolution error: $error');
      return null;
    }
  }

  Future<String?> _findWindowsSystemTool(String executableName) async {
    final inboxPath = p.join(
      WindowsSystemEnvironment.systemRoot,
      'System32',
      executableName,
    );
    if (await File(inboxPath).exists()) return inboxPath;

    try {
      final wherePath = p.join(
        WindowsSystemEnvironment.systemRoot,
        'System32',
        'where.exe',
      );
      final result = await _runLinuxUtility(
        wherePath,
        [executableName],
        timeout: const Duration(seconds: 8),
        environment: WindowsSystemEnvironment.withSystemRoot(),
        trackForCancellation: false,
      );
      if (result.exitCode != 0) return null;
      for (final line
          in result.stdout
              .toString()
              .split(RegExp(r'\r?\n'))
              .map((value) => value.trim())) {
        if (line.isNotEmpty && await File(line).exists()) return line;
      }
    } catch (error) {
      _logLine('System tool lookup failed for $executableName: $error');
    }
    return null;
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

    final windowsSourceInspection = await ref
        .read(windowsIsoPreflightProvider)
        .inspect(isoPath);
    if (windowsSourceInspection.isValid) {
      _logLine(
        'Linux ISO preflight rejected a Windows installation layout before erase.',
      );
      _notify(
        onProgress,
        const CreateProgress(
          step: CreateStep.failed,
          message: 'creator_windows_iso_in_linux_mode',
        ),
      );
      return false;
    }

    if (kind == LinuxUsbKind.toGo) {
      final imageInspection = await ref
          .read(linuxToGoImagePreflightProvider)
          .inspectForDeployment(isoPath);
      if (!imageInspection.canCreate) {
        final messageKey =
            imageInspection.messageKey ?? 'linux_togo_unsupported_iso';
        _logLine(
          'Linux To Go image preflight rejected the source before disk access: '
          '$messageKey${imageInspection.diagnostic == null ? '' : ' (${imageInspection.diagnostic})'}',
        );
        _notify(
          onProgress,
          CreateProgress(
            step: CreateStep.failed,
            message: messageKey,
            error: imageInspection.diagnostic,
          ),
        );
        return false;
      }

      // Validate the bundled persistence tool before doing any target-disk
      // work. Source compatibility and local tool availability are separate.
      if (await _findExt4Builder() == null) {
        _notify(
          onProgress,
          const CreateProgress(
            step: CreateStep.failed,
            message: 'linux_togo_mke2fs_missing',
          ),
        );
        return false;
      }
    }

    final logCenter = LogCenterService();
    await logCenter.logUsb('$modeName 创建开始 | 磁盘: $diskNumber | ISO: $isoPath');

    final logger = ref.read(fileLoggerServiceProvider);
    await logger.log(
      action: 'Create $modeName',
      target: 'Disk $diskNumber',
      result: 'Starting - ISO: $isoPath',
    );

    var rawDiskMayNeedRestore = false;
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
        final volumeIdentity = await _prepareLinuxToGoVolumeIdentity(
          deploymentPlan,
        );
        if (!volumeIdentity.success || volumeIdentity.identity == null) {
          final error =
              volumeIdentity.error ?? 'Linux To Go volume identity is invalid.';
          _logLine('Linux To Go volume identity preflight failed: $error');
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
        final result = await _createPersistentLinuxToGo(
          disk: disk,
          isoPath: isoPath,
          volumeIdentity: volumeIdentity.identity!,
          stagingBundle: stagingPreparation.bundle,
          onProgress: onProgress,
        );

        _notify(
          onProgress,
          CreateProgress(
            step: result.success ? CreateStep.complete : CreateStep.failed,
            message: result.success
                ? 'linux_complete'
                : result.failureMessageKey ??
                      'linux_write_failed\n${result.error ?? "Unknown error"}',
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

      // Keep the raw device open through the full byte-for-byte verification.
      // Some USB bridges cannot be taken offline, so the writer falls back to
      // an exclusive raw handle instead of allowing Windows a gap in which it
      // could inspect or alter the hybrid GPT/EFI metadata.
      rawDiskMayNeedRestore = true;
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
        onVerifyProgress: (verifyProgress) {
          _notify(
            onProgress,
            CreateProgress(
              step: CreateStep.verifying,
              message: 'linux_finalizing',
              progress: 0.96 + verifyProgress * 0.04,
            ),
          );
        },
      );

      if (!result.success) {
        var errorDetail = result.error ?? 'Unknown error';
        final restoreResult = result.diskOnline
            ? const _LinuxRawWriteResult(success: true)
            : await _restoreLinuxRawDiskOnline(disk: disk);
        if (restoreResult.success) {
          rawDiskMayNeedRestore = false;
        } else {
          errorDetail =
              '$errorDetail\n\n'
              'The target disk could not be returned online: '
              '${restoreResult.error ?? 'Unknown error'}';
        }
        final errorKey =
            result.failureMessageKey ??
            (result.cancelled
                ? 'deploy_cancel_requested'
                : result.verificationFailed
                ? 'linux_verify_failed'
                : errorDetail.contains('Access is denied') ||
                      errorDetail.contains('拒绝访问') ||
                      errorDetail.contains('UnauthorizedAccess')
                ? 'linux_access_denied'
                : 'linux_write_failed');
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

      // The raw writer returns the disk online before emitting WDS_DONE. Do
      // not start a second PowerShell process after successful verification.
      rawDiskMayNeedRestore = false;
      final finalResult = result;
      _logLine('Linux verify: ${finalResult.success ? "OK" : "FAILED"}');

      _notify(
        onProgress,
        CreateProgress(
          step: finalResult.success ? CreateStep.complete : CreateStep.failed,
          message: finalResult.success
              ? 'linux_complete'
              : '${finalResult.cancelled ? 'deploy_cancel_requested' : 'linux_verify_failed'}\n${finalResult.error ?? ''}',
          progress: finalResult.success ? 1.0 : 0.0,
          error: finalResult.error,
        ),
      );

      await logger.log(
        action: 'Create $modeName',
        target: 'Disk $diskNumber',
        result: finalResult.success
            ? 'Success - Raw ISOHybrid write'
            : 'Failed: ${finalResult.error ?? "Unknown error"}',
        level: finalResult.success ? LogLevel.success : LogLevel.error,
      );

      if (finalResult.success) {
        await logCenter.logUsb('$modeName 创建成功 | 磁盘: $diskNumber');
      } else {
        await logCenter.logError(
          '$modeName 验证失败 | 磁盘: $diskNumber | ${finalResult.error ?? "Unknown"}',
        );
      }

      final logPath = await saveLogToFile();
      _logLine('Log saved to: $logPath');
      return finalResult.success;
    } catch (e) {
      String? restoreError;
      if (rawDiskMayNeedRestore) {
        final restoreResult = await _restoreLinuxRawDiskOnline(disk: disk);
        if (restoreResult.success) {
          rawDiskMayNeedRestore = false;
        } else {
          restoreError = restoreResult.error ?? 'Unknown error';
          _logLine('Linux raw disk recovery FAILED: $restoreError');
        }
      }
      final errorDetail = restoreError == null
          ? '$e'
          : '$e\n\nThe target disk could not be returned online: $restoreError';
      _logLine('Linux creation EXCEPTION: $errorDetail');
      final logPath = await saveLogToFile();
      await logCenter.logError(
        '$modeName 创建异常 | 磁盘: $diskNumber | 错误: $errorDetail',
      );
      _notify(
        onProgress,
        CreateProgress(
          step: CreateStep.failed,
          message: 'creator_error\n$errorDetail\n\nLog: $logPath',
        ),
      );
      await logger.log(
        action: 'Create $modeName',
        target: 'Disk $diskNumber',
        result: 'Exception: $errorDetail',
        level: LogLevel.error,
      );
      return false;
    }
  }

  Future<_LinuxRawWriteResult> _createPersistentLinuxToGo({
    required DiskInfo disk,
    required String isoPath,
    required _LinuxToGoVolumeIdentity volumeIdentity,
    LinuxDriverStagingBundle? stagingBundle,
    ProgressCallback? onProgress,
  }) async {
    final diskNumber = disk.diskNumber;
    const int mib = 1024 * 1024;

    try {
      // The source can change while driver staging runs. Refresh both source
      // classifications here, before this method can clean the target disk.
      final freshInspection = await _refreshLinuxToGoImageBeforeErase(isoPath);
      final freshImage = freshInspection.image;
      if (!freshInspection.canCreate || freshImage == null) {
        _logLine(
          'Linux To Go preflight failed immediately before erase: '
          '${freshInspection.messageKey ?? freshInspection.diagnostic}',
        );
        return _LinuxRawWriteResult(
          success: false,
          error: freshInspection.diagnostic,
          failureMessageKey:
              freshInspection.messageKey ?? 'linux_togo_unsupported_iso',
        );
      }

      if (!freshImage.hasCompleteContentManifest) {
        _logLine(
          'Linux To Go preflight did not produce a complete source manifest.',
        );
        return const _LinuxRawWriteResult(
          success: false,
          error:
              'Linux To Go source verification did not complete before disk preparation.',
        );
      }

      if (stagingBundle != null && !freshImage.supportsDriverStaging) {
        _logLine(
          'Linux To Go image family ${freshImage.family.name} does not '
          'support the casper first-boot staging contract.',
        );
        return const _LinuxRawWriteResult(
          success: false,
          error:
              'The selected Linux To Go image does not support first-boot driver staging.',
          failureMessageKey: 'linux_togo_driver_staging_unsupported',
        );
      }

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
          ((freshImage.totalContentBytes + mib - 1) ~/ mib) +
          stagingContentMb +
          256;
      final bootContentMb =
          ((freshImage.bootContentBytes + mib - 1) ~/ mib) + 128;
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
        liveVolumeLabel: volumeIdentity.label,
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
        expectedLabel: volumeIdentity.label,
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

      final liveNtfsUuid = await _readLinuxToGoNtfsUuid(liveDrive);
      if (liveNtfsUuid == null) {
        return const _LinuxRawWriteResult(
          success: false,
          error:
              'Could not read the NTFS UUID for the Linux To Go data partition.',
        );
      }
      final liveMediaArgument = _linuxToGoLiveMediaArgument(liveNtfsUuid);
      _logLine(
        'Linux To Go data identity: label=${volumeIdentity.label}, '
        'live-media=$liveMediaArgument',
      );

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
          expectedTotalBytes: freshImage.totalContentBytes,
          deferContentVerification: true,
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
          excludedExtensions: freshImage.livePayloadExtensions,
          expectedTotalBytes: freshImage.bootContentBytes,
          deferContentVerification: true,
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
          image: freshImage,
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
        image: freshImage,
        liveMediaArgument: liveMediaArgument,
        enableFirstBootStaging: stagingBundle != null,
      );
      final livePatched = await _patchLinuxPersistenceBootConfigs(
        liveDrive,
        image: freshImage,
        liveMediaArgument: liveMediaArgument,
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
        image: freshImage,
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

      final explorerIdentitySet = await _setLinuxToGoExplorerIdentity(
        liveDrive,
        icon: volumeIdentity.icon,
      );
      if (!explorerIdentitySet) {
        return const _LinuxRawWriteResult(
          success: false,
          error: 'Failed to apply the Linux To Go drive icon.',
        );
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
        liveVolumeLabel: volumeIdentity.label,
        liveMediaArgument: liveMediaArgument,
        expectedIcon: volumeIdentity.icon,
        image: freshImage,
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

  Future<LinuxToGoImageInspection> _refreshLinuxToGoImageBeforeErase(
    String isoPath,
  ) async {
    final windowsSourceInspection = await ref
        .read(windowsIsoPreflightProvider)
        .inspect(isoPath);
    if (windowsSourceInspection.isValid) {
      _logLine(
        'Linux To Go preflight rejected a Windows installation layout '
        'immediately before erase.',
      );
      return const LinuxToGoImageInspection.unsupported(
        LinuxToGoImageIssue.windowsInstaller,
      );
    }
    final inspection = await ref
        .read(linuxToGoImagePreflightProvider)
        .inspectForDeployment(isoPath);
    if (inspection.canCreate && inspection.image != null) {
      final image = inspection.image!;
      _logLine(
        'Linux To Go image preflight: family=${image.family.name}, '
        'content=${image.totalContentBytes}, boot=${image.bootContentBytes}, '
        'live payloads=${image.livePayloads.length}',
      );
    }
    return inspection;
  }

  Future<bool> _isIsoHybridImage(String isoPath) async {
    final inspection = await LinuxIsoHybridInspector.inspect(isoPath);
    if (!inspection.isValid) {
      _logLine('ISOHybrid preflight failed: ${inspection.error}');
      return false;
    }
    final efiArchitectures = inspection.efiArchitectures
        .map((value) => value.name)
        .join(', ');
    _logLine(
      'ISOHybrid preflight: ISO9660/El Torito valid, '
      'catalog LBA=${inspection.bootCatalogLba}, '
      'legacy=${inspection.hasLegacyBiosBoot}, '
      'uefi=${inspection.hasUefiBoot}, '
      'EFI image LBA=${inspection.efiImageLba}, '
      'EFI architectures=${efiArchitectures.isEmpty ? 'not advertised' : efiArchitectures}',
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
      if (imageBytes <= 0 || imageBytes > targetBytes) {
        return _LinuxRawWriteResult(
          success: false,
          error:
              'The Linux image must not be larger than the target disk '
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
      final result = await _runPowerShell(
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
      final result = await _runPowerShell([
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
    required String liveVolumeLabel,
  }) async {
    final letters = await _reserveLinuxToGoDriveLetters();
    if (letters == null) {
      return const _LinuxToGoPartitionResult(
        success: false,
        error: 'Could not reserve two drive letters for Linux To Go.',
      );
    }

    final currentDisk = await ref
        .read(diskSafetyServiceProvider)
        .refreshDisk(disk);
    if (currentDisk == null) {
      return const _LinuxToGoPartitionResult(
        success: false,
        error: 'Target disk identity changed before partitioning.',
      );
    }
    final diskSafety = ref.read(diskSafetyServiceProvider);
    final initialization = await diskSafety.initializeDiskPartitionStyle(
      currentDisk,
      partitionStyle: 'GPT',
    );
    if (initialization.exitCode != 0) {
      final stderr = initialization.stderr.toString();
      final stdout = initialization.stdout.toString();
      final detail = _summarizePowerShellFailure(
        stderr.trim().isNotEmpty ? stderr : stdout,
        fallback: 'Disk initialization failed.',
      );
      return _LinuxToGoPartitionResult(success: false, error: detail);
    }
    final initializedDisk = await diskSafety.refreshDisk(currentDisk);
    if (initializedDisk == null ||
        initializedDisk.partitionStyle.toUpperCase() != 'GPT') {
      return const _LinuxToGoPartitionResult(
        success: false,
        error: 'Target disk initialization could not be verified.',
      );
    }

    final script = _buildLinuxToGoDiskpartScript(
      diskNumber: initializedDisk.diskNumber,
      bootPartitionSizeMb: bootPartitionSizeMb,
      bootLetter: letters.bootLetter,
      liveLetter: letters.liveLetter,
      liveVolumeLabel: liveVolumeLabel,
      currentPartitionStyle: initializedDisk.partitionStyle,
    );
    _logLine('Linux To Go DiskPart script:\n$script');

    final result = await diskSafety.runGuardedDiskpart(initializedDisk, script);
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

  static String _buildLinuxToGoDiskpartScript({
    required int diskNumber,
    required int bootPartitionSizeMb,
    required String bootLetter,
    required String liveLetter,
    required String liveVolumeLabel,
    required String currentPartitionStyle,
  }) {
    final commands = <String>[
      'select disk $diskNumber',
      'create partition efi size=$bootPartitionSizeMb',
      'select partition 1',
      'format fs=fat32 label="WDS_LTG" quick',
      'assign letter=$bootLetter',
      'select disk $diskNumber',
      'create partition primary',
      'select partition 2',
      'format fs=ntfs label="$liveVolumeLabel" quick',
      'assign letter=$liveLetter',
      'exit',
    ];
    return '${commands.join('\n')}\n';
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
      'there is no volume selected',
      'no volume selected',
      'diskpart 遇到错误',
      '虚拟磁盘服务错误',
      '参数错误',
      '拒绝访问',
      '卷大小太大',
      '没有选择卷',
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
      final result = await _runPowerShell([
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
        final result = await _runPowerShell(
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

  Future<String?> _readLinuxToGoNtfsUuid(String drive) async {
    final letter = drive.replaceAll(RegExp(r'[:\\]'), '').toUpperCase();
    try {
      final result = await Process.run('fsutil', [
        'fsinfo',
        'ntfsinfo',
        '$letter:',
      ]).timeout(const Duration(seconds: 10));
      final output = '${result.stdout}\n${result.stderr}';
      final uuid = _extractLinuxToGoNtfsUuid(output);
      if (result.exitCode == 0 && uuid != null) {
        return uuid;
      }
      _logLine(
        'Linux To Go NTFS UUID lookup failed: '
        '${output.trim()}',
      );
    } catch (error) {
      _logLine('Linux To Go NTFS UUID lookup error: $error');
    }
    return null;
  }

  Future<bool> _patchLinuxPersistenceBootConfigs(
    String targetDrive, {
    required LinuxToGoSupportedImage image,
    required String liveMediaArgument,
    required bool enableFirstBootStaging,
  }) async {
    if (!_isSupportedLinuxToGoPersistenceStrategy(image)) {
      _logLine('Unsupported Linux To Go persistence strategy.');
      return false;
    }
    if (enableFirstBootStaging && !image.supportsDriverStaging) {
      _logLine(
        'This Linux To Go image family does not support driver staging.',
      );
      return false;
    }

    final root = targetDrive.endsWith(r'\') ? targetDrive : '$targetDrive\\';
    var foundPatchableEntry = false;
    final escapedKernelPath = RegExp.escape('/${image.kernelRelativePath}');
    final kernelPattern = RegExp(
      '$escapedKernelPath(?:\\s|\$)',
      caseSensitive: false,
    );
    final requiresLiveBoot =
        image.family == LinuxToGoImageFamily.debianLive ||
        image.family == LinuxToGoImageFamily.deepinLive;
    final liveBootPattern = RegExp(
      r'(^|\s)boot=live(?:\s|$)',
      caseSensitive: false,
    );
    final persistenceArgument = _linuxToGoPersistenceArgument(image);

    for (final config in image.patchableBootConfigs) {
      if (config.syntax != LinuxToGoBootConfigSyntax.grub) continue;
      final file = File(p.join(root, config.relativePath));
      if (!await file.exists()) {
        _logLine('Approved boot config is missing after copy: ${file.path}');
        return false;
      }

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
                !kernelPattern.hasMatch(line) ||
                (requiresLiveBoot && !liveBootPattern.hasMatch(line))) {
              return line;
            }

            foundPatchableEntry = true;
            var updated = line;
            final persistencePattern = RegExp(
              '(^|\\s)${RegExp.escape(persistenceArgument)}(\\s|\$)',
              caseSensitive: false,
            );
            if (!persistencePattern.hasMatch(updated)) {
              updated = _insertGrubKernelArgument(updated, persistenceArgument);
            }

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

    return foundPatchableEntry;
  }

  String _insertGrubKernelArgument(String line, String argument) {
    final markerIndex = line.indexOf(' ---');
    if (markerIndex >= 0) {
      return '${line.substring(0, markerIndex)} $argument${line.substring(markerIndex)}';
    }
    return '$line $argument';
  }

  static bool _isSupportedLinuxToGoPersistenceStrategy(
    LinuxToGoSupportedImage image,
  ) =>
      (image.family == LinuxToGoImageFamily.casper &&
          image.persistenceStrategy ==
              LinuxToGoPersistenceStrategy.casperWritableImage) ||
      (image.family == LinuxToGoImageFamily.debianLive &&
          image.persistenceStrategy ==
              LinuxToGoPersistenceStrategy.debianPersistenceImage) ||
      (image.family == LinuxToGoImageFamily.deepinLive &&
          image.persistenceStrategy ==
              LinuxToGoPersistenceStrategy.debianPersistenceImage);

  static String _linuxToGoPersistenceFileName(LinuxToGoSupportedImage image) =>
      switch (image.persistenceStrategy) {
        LinuxToGoPersistenceStrategy.casperWritableImage =>
          _casperPersistenceFileName,
        LinuxToGoPersistenceStrategy.debianPersistenceImage =>
          _debianPersistenceFileName,
      };

  static String _linuxToGoPersistenceVolumeLabel(
    LinuxToGoSupportedImage image,
  ) => switch (image.persistenceStrategy) {
    LinuxToGoPersistenceStrategy.casperWritableImage =>
      _casperPersistenceVolumeLabel,
    LinuxToGoPersistenceStrategy.debianPersistenceImage =>
      _debianPersistenceVolumeLabel,
  };

  static String _linuxToGoPersistenceArgument(LinuxToGoSupportedImage image) =>
      switch (image.persistenceStrategy) {
        LinuxToGoPersistenceStrategy.casperWritableImage => 'persistent',
        LinuxToGoPersistenceStrategy.debianPersistenceImage => 'persistence',
      };

  static String? _linuxToGoPersistenceConfiguration(
    LinuxToGoSupportedImage image,
  ) => switch (image.persistenceStrategy) {
    LinuxToGoPersistenceStrategy.casperWritableImage => null,
    LinuxToGoPersistenceStrategy.debianPersistenceImage =>
      _debianPersistenceConfiguration,
  };

  Future<_LinuxRawWriteResult> _createPersistenceImage({
    required String targetDrive,
    required int sizeMb,
    required LinuxToGoSupportedImage image,
  }) async {
    if (!_isSupportedLinuxToGoPersistenceStrategy(image)) {
      return const _LinuxRawWriteResult(
        success: false,
        error: 'Unsupported Linux To Go persistence strategy.',
      );
    }
    final ext4Builder = await _findExt4Builder();
    if (ext4Builder == null) {
      return const _LinuxRawWriteResult(
        success: false,
        error:
            'The bundled Linux persistence component is missing or did not pass integrity verification.',
      );
    }

    final root = targetDrive.endsWith(r'\') ? targetDrive : '$targetDrive\\';
    final fileName = _linuxToGoPersistenceFileName(image);
    final volumeLabel = _linuxToGoPersistenceVolumeLabel(image);
    final configuration = _linuxToGoPersistenceConfiguration(image);
    final persistenceImage = File(p.join(root, fileName));
    _logLine(
      'Creating Linux persistence image: ${persistenceImage.path}, '
      '${sizeMb}MB, label=$volumeLabel',
    );

    if (await persistenceImage.exists()) {
      await persistenceImage.delete();
    }
    final arguments = <String>[
      '--output',
      persistenceImage.path,
      '--size-mb',
      '$sizeMb',
      '--label',
      volumeLabel,
      if (configuration != null) '--debian-persistence',
    ];
    final result = await _runLinuxUtility(
      ext4Builder,
      arguments,
      timeout: const Duration(minutes: 5),
    );

    _logLine('ext4 builder exit: ${result.exitCode}');
    if (result.stdout.toString().trim().isNotEmpty) {
      _logLine('ext4 builder stdout: ${result.stdout}');
    }
    if (result.stderr.toString().trim().isNotEmpty) {
      _logLine('ext4 builder stderr: ${result.stderr}');
    }

    if (result.exitCode != 0) {
      return _LinuxRawWriteResult(
        success: false,
        error: result.stderr.toString().trim().isNotEmpty
            ? result.stderr.toString().trim()
            : 'The Linux persistence component failed with exit code ${result.exitCode}.',
      );
    }

    final verified = await _verifyExt4PersistenceImage(
      persistenceImage,
      expectedVolumeLabel: volumeLabel,
      expectedConfiguration: configuration,
    );
    if (!verified) {
      return _LinuxRawWriteResult(
        success: false,
        error:
            'The ext4 $fileName persistence image did not pass post-create verification.',
      );
    }
    return const _LinuxRawWriteResult(success: true);
  }

  Future<String?> _findExt4Builder() async {
    if (!linuxPersistenceToolDistributionApproved || !Platform.isWindows) {
      return null;
    }
    final helper = File(
      p.join(
        p.dirname(Platform.resolvedExecutable),
        'tools',
        'ext4-builder',
        _ext4BuilderExecutableName,
      ),
    );
    if (!await helper.exists()) {
      _logLine('Linux persistence helper is missing: ${helper.path}');
      return null;
    }
    final digest = await BackgroundFileHashService.sha256File(helper);
    if (digest.toLowerCase() != _ext4BuilderSha256) {
      _logLine('Linux persistence helper integrity check failed.');
      return null;
    }
    return helper.path;
  }

  Future<_LinuxRawWriteResult> _verifyLinuxToGoCopies({
    required String mountPoint,
    required String bootDrive,
    required String liveDrive,
    required LinuxToGoSupportedImage image,
  }) async {
    try {
      if (!image.hasCompleteContentManifest) {
        return const _LinuxRawWriteResult(
          success: false,
          error: 'Linux To Go source manifest is incomplete.',
        );
      }
      final sourceRoot = mountPoint.endsWith(r'\')
          ? mountPoint
          : '$mountPoint\\';
      final bootRoot = bootDrive.endsWith(r'\') ? bootDrive : '$bootDrive\\';
      final liveRoot = liveDrive.endsWith(r'\') ? liveDrive : '$liveDrive\\';
      var verifiedLiveBytes = 0;
      var verifiedBootBytes = 0;

      for (final contentFile in image.contentFiles) {
        final relativePath = contentFile.relativePath;
        final source = File(p.join(sourceRoot, relativePath));
        if (!await source.exists() ||
            await source.length() != contentFile.sizeBytes) {
          return _LinuxRawWriteResult(
            success: false,
            error:
                'Linux source changed during copy verification: $relativePath',
          );
        }
        final sourceDigest = await BackgroundFileHashService.sha256File(source);
        verifiedLiveBytes += contentFile.sizeBytes;
        final liveFile = File(p.join(liveRoot, relativePath));
        if (!await liveFile.exists() ||
            await liveFile.length() != contentFile.sizeBytes) {
          return _LinuxRawWriteResult(
            success: false,
            error: 'Linux Live copy verification failed: $relativePath',
          );
        }
        final liveDigest = await BackgroundFileHashService.sha256File(liveFile);
        if (liveDigest != sourceDigest) {
          return _LinuxRawWriteResult(
            success: false,
            error:
                'Linux Live copy SHA-256 mismatch: $relativePath '
                '(source=$sourceDigest, copy=$liveDigest)',
          );
        }

        final isLivePayload = image.isLivePayloadPath(relativePath);
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
            await bootFile.length() != contentFile.sizeBytes) {
          return _LinuxRawWriteResult(
            success: false,
            error: 'Linux boot copy verification failed: $relativePath',
          );
        } else {
          final bootDigest = await BackgroundFileHashService.sha256File(
            bootFile,
          );
          if (bootDigest != sourceDigest) {
            return _LinuxRawWriteResult(
              success: false,
              error:
                  'Linux boot copy SHA-256 mismatch: $relativePath '
                  '(source=$sourceDigest, copy=$bootDigest)',
            );
          }
          verifiedBootBytes += contentFile.sizeBytes;
        }
      }

      if (verifiedLiveBytes != image.totalContentBytes ||
          verifiedBootBytes != image.bootContentBytes) {
        return _LinuxRawWriteResult(
          success: false,
          error:
              'Linux To Go copy size verification failed: '
              'live=$verifiedLiveBytes/${image.totalContentBytes}, '
              'boot=$verifiedBootBytes/${image.bootContentBytes}.',
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
    required String liveVolumeLabel,
    required String liveMediaArgument,
    required _VolumeIconPayload? expectedIcon,
    required LinuxToGoSupportedImage image,
    LinuxDriverStagingBundle? stagingBundle,
  }) async {
    try {
      if (!_isSupportedLinuxToGoPersistenceStrategy(image)) {
        _logLine('Linux To Go verify failed: unsupported persistence strategy');
        return false;
      }
      if (stagingBundle != null && !image.supportsDriverStaging) {
        _logLine('Linux To Go verify failed: unsupported driver staging');
        return false;
      }

      final bootMatches = await _partitionMatchesLinuxToGoLayout(
        drive: bootDrive,
        expectedLabel: 'WDS_LTG',
        expectedFileSystem: 'FAT32',
        expectedPartitionNumber: 1,
        diskNumber: diskNumber,
      );
      final liveMatches = await _partitionMatchesLinuxToGoLayout(
        drive: liveDrive,
        expectedLabel: liveVolumeLabel,
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
      final bootx64 = File(p.join(bootRoot, image.efiBootRelativePath));
      final liveBootx64 = File(p.join(liveRoot, image.efiBootRelativePath));
      final bootKernel = File(p.join(bootRoot, image.kernelRelativePath));
      final bootInitrd = File(p.join(bootRoot, image.initrdRelativePath));
      final persistenceImage = File(
        p.join(bootRoot, _linuxToGoPersistenceFileName(image)),
      );
      final persistenceArgument = _linuxToGoPersistenceArgument(image);
      final persistenceConfiguration = _linuxToGoPersistenceConfiguration(
        image,
      );

      if (!await bootx64.exists() || !await liveBootx64.exists()) {
        _logLine('Linux To Go verify failed: BOOTx64.EFI missing');
        return false;
      }
      if (!await bootKernel.exists() || !await bootInitrd.exists()) {
        _logLine('Linux To Go verify failed: Live kernel or initrd missing');
        return false;
      }
      final bootConfigTexts = <String>[];
      final liveConfigTexts = <String>[];
      for (final config in image.patchableBootConfigs) {
        if (config.syntax != LinuxToGoBootConfigSyntax.grub) {
          _logLine('Linux To Go verify failed: unsupported boot config syntax');
          return false;
        }
        final bootConfig = File(p.join(bootRoot, config.relativePath));
        final liveConfig = File(p.join(liveRoot, config.relativePath));
        if (!await bootConfig.exists() || !await liveConfig.exists()) {
          _logLine(
            'Linux To Go verify failed: approved GRUB config missing: '
            '${config.relativePath}',
          );
          return false;
        }
        final bootText = await bootConfig.readAsString();
        final liveText = await liveConfig.readAsString();
        if (!_hasPatchedLinuxToGoBootEntry(
              bootText,
              image: image,
              persistenceArgument: persistenceArgument,
              liveMediaArgument: liveMediaArgument,
            ) ||
            !_hasPatchedLinuxToGoBootEntry(
              liveText,
              image: image,
              persistenceArgument: persistenceArgument,
              liveMediaArgument: liveMediaArgument,
            )) {
          _logLine(
            'Linux To Go verify failed: required boot args missing from '
            '${config.relativePath}',
          );
          return false;
        }
        bootConfigTexts.add(bootText);
        liveConfigTexts.add(liveText);
      }

      if (stagingBundle != null) {
        for (final argument in const [
          LinuxDriverStagingService.bootMarkerArgument,
          LinuxDriverStagingService.systemdWantsArgument,
        ]) {
          if (bootConfigTexts.any((text) => !text.contains(argument)) ||
              liveConfigTexts.any((text) => !text.contains(argument))) {
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

      if (!await _verifyLinuxToGoExplorerIdentity(
        liveDrive,
        expectedIcon: expectedIcon,
      )) {
        _logLine('Linux To Go verify failed: drive icon identity mismatch');
        return false;
      }

      for (final payload in image.livePayloads) {
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

      if (!await _verifyExt4PersistenceImage(
        persistenceImage,
        expectedVolumeLabel: _linuxToGoPersistenceVolumeLabel(image),
        expectedConfiguration: persistenceConfiguration,
      )) {
        _logLine('Linux To Go verify failed: persistence image invalid');
        return false;
      }

      return true;
    } catch (e) {
      _logLine('Linux To Go verify error: $e');
      return false;
    }
  }

  static bool _hasPatchedLinuxToGoBootEntry(
    String content, {
    required LinuxToGoSupportedImage image,
    required String persistenceArgument,
    required String liveMediaArgument,
  }) {
    final kernelPattern = RegExp(
      '${RegExp.escape('/${image.kernelRelativePath}')}(?:\\s|\$)',
      caseSensitive: false,
    );
    final persistencePattern = RegExp(
      '(^|\\s)${RegExp.escape(persistenceArgument)}(\\s|\$)',
      caseSensitive: false,
    );
    final liveMediaPattern = RegExp(
      '(^|\\s)${RegExp.escape(liveMediaArgument)}(\\s|\$)',
      caseSensitive: false,
    );
    final liveBootPattern = RegExp(
      r'(^|\s)boot=live(?:\s|$)',
      caseSensitive: false,
    );
    return content.replaceAll('\r\n', '\n').split('\n').any((line) {
      final isLinuxLine = RegExp(
        r'^\s*linux(efi)?\s+',
        caseSensitive: false,
      ).hasMatch(line);
      return isLinuxLine &&
          kernelPattern.hasMatch(line) &&
          ((image.family != LinuxToGoImageFamily.debianLive &&
                  image.family != LinuxToGoImageFamily.deepinLive) ||
              liveBootPattern.hasMatch(line)) &&
          persistencePattern.hasMatch(line) &&
          liveMediaPattern.hasMatch(line);
    });
  }

  Future<bool> _verifyExt4PersistenceImage(
    File image, {
    required String expectedVolumeLabel,
    required String? expectedConfiguration,
  }) async {
    RandomAccessFile? handle;
    try {
      if (!await image.exists() || await image.length() < 16 * 1024 * 1024) {
        return false;
      }
      handle = await image.open(mode: FileMode.read);
      final superblock = await _readExact(handle, 1024, 1024);
      if (superblock == null || _littleEndian16(superblock, 0x38) != 0xef53) {
        return false;
      }

      final labelBytes = superblock.sublist(0x78, 0x78 + 16);
      final labelEnd = labelBytes.indexOf(0);
      final actualLabel = ascii.decode(
        labelEnd < 0 ? labelBytes : labelBytes.sublist(0, labelEnd),
        allowInvalid: true,
      );
      if (actualLabel != expectedVolumeLabel) return false;
      if (expectedConfiguration == null) return true;

      final layout = _Ext4Layout.fromSuperblock(superblock);
      if (layout == null) return false;
      final root = await _readExt4Inode(handle, layout, 2);
      if (root == null || !root.isDirectory) return false;
      final configurationInode = await _findExt4DirectoryEntry(
        handle,
        layout,
        root,
        'persistence.conf',
      );
      if (configurationInode == null) return false;
      final configuration = await _readExt4File(
        handle,
        layout,
        configurationInode,
      );
      return configuration != null &&
          utf8.decode(configuration, allowMalformed: true) ==
              expectedConfiguration;
    } catch (error) {
      _logLine('ext4 persistence verification failed: $error');
      return false;
    } finally {
      await handle?.close();
    }
  }

  static Future<List<int>?> _readExact(
    RandomAccessFile handle,
    int offset,
    int length,
  ) async {
    await handle.setPosition(offset);
    final bytes = await handle.read(length);
    return bytes.length == length ? bytes : null;
  }

  static int _littleEndian16(List<int> bytes, int offset) =>
      bytes[offset] | (bytes[offset + 1] << 8);

  static int _littleEndian32(List<int> bytes, int offset) =>
      bytes[offset] |
      (bytes[offset + 1] << 8) |
      (bytes[offset + 2] << 16) |
      (bytes[offset + 3] << 24);

  static Future<_Ext4Inode?> _readExt4Inode(
    RandomAccessFile handle,
    _Ext4Layout layout,
    int inodeNumber,
  ) async {
    if (inodeNumber <= 0) return null;
    final inodeIndex = inodeNumber - 1;
    final group = inodeIndex ~/ layout.inodesPerGroup;
    final groupDescriptor = await _readExact(
      handle,
      layout.groupDescriptorOffset + group * layout.groupDescriptorSize,
      layout.groupDescriptorSize,
    );
    if (groupDescriptor == null) return null;
    final inodeTableBlock = _littleEndian32(groupDescriptor, 8);
    if (inodeTableBlock <= 0) return null;
    final indexInGroup = inodeIndex % layout.inodesPerGroup;
    final inodeOffset =
        inodeTableBlock * layout.blockSize + indexInGroup * layout.inodeSize;
    final bytes = await _readExact(handle, inodeOffset, layout.inodeSize);
    if (bytes == null) return null;
    return _Ext4Inode.fromBytes(bytes);
  }

  static Future<_Ext4Inode?> _findExt4DirectoryEntry(
    RandomAccessFile handle,
    _Ext4Layout layout,
    _Ext4Inode directory,
    String expectedName,
  ) async {
    final content = await _readExt4File(handle, layout, directory);
    if (content == null) return null;
    var offset = 0;
    while (offset + 8 <= content.length) {
      final inodeNumber = _littleEndian32(content, offset);
      final recordLength = _littleEndian16(content, offset + 4);
      final nameLength = content[offset + 6];
      if (recordLength < 8 ||
          recordLength % 4 != 0 ||
          offset + recordLength > content.length ||
          nameLength > recordLength - 8) {
        return null;
      }
      if (inodeNumber != 0) {
        final name = ascii.decode(
          content.sublist(offset + 8, offset + 8 + nameLength),
          allowInvalid: true,
        );
        if (name == expectedName) {
          return _readExt4Inode(handle, layout, inodeNumber);
        }
      }
      offset += recordLength;
    }
    return null;
  }

  static Future<List<int>?> _readExt4File(
    RandomAccessFile handle,
    _Ext4Layout layout,
    _Ext4Inode inode,
  ) async {
    if (inode.size < 0 || inode.size > 16 * 1024 * 1024) return null;
    final blocks = inode.dataBlocks(layout.blockSize);
    if (blocks == null) return null;
    final remaining = inode.size;
    final result = <int>[];
    for (final block in blocks) {
      if (result.length >= remaining) break;
      final bytes = await _readExact(
        handle,
        block * layout.blockSize,
        layout.blockSize,
      );
      if (bytes == null) return null;
      final bytesNeeded = remaining - result.length;
      result.addAll(bytes.take(bytesNeeded));
    }
    return result.length == remaining ? result : null;
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
      final result = await _runPowerShell(
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
    required void Function(double progress) onVerifyProgress,
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
    var verificationStarted = false;
    var imageVerified = false;
    var diskOnline = false;
    var completed = false;
    String? restoreFailureDetail;
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
              final fields = cleanLine
                  .substring('WDS_PROGRESS:'.length)
                  .split(':');
              final percent = int.tryParse(fields.first);
              if (percent != null) {
                onProgress(percent.clamp(0, 100) / 100.0);
              }
            }
            if (cleanLine == 'WDS_VERIFY_STARTED') {
              verificationStarted = true;
            }
            if (cleanLine.startsWith('WDS_VERIFY_PROGRESS:')) {
              verificationStarted = true;
              final percent = int.tryParse(
                cleanLine.substring('WDS_VERIFY_PROGRESS:'.length),
              );
              if (percent != null) {
                onVerifyProgress(percent.clamp(0, 100) / 100.0);
              }
            }
            if (cleanLine == 'WDS_VERIFY_COMPLETE') {
              if (!verificationStarted) {
                _logLine(
                  'Linux raw writer emitted verification completion before verification started.',
                );
              }
              imageVerified = true;
            }
            if (cleanLine == 'WDS_DISK_ONLINE') {
              if (!imageVerified) {
                _logLine(
                  'Linux raw writer emitted disk-online before verification completed.',
                );
              }
              diskOnline = true;
            }
            if (cleanLine == 'WDS_DONE') {
              if (!imageVerified || !diskOnline) {
                _logLine(
                  'Linux raw writer emitted completion before required recovery markers.',
                );
              }
              completed = true;
            }
            if (cleanLine.startsWith('WDS_RESTORE_FAILED:')) {
              restoreFailureDetail = cleanLine
                  .substring('WDS_RESTORE_FAILED:'.length)
                  .trim();
            }
          })
          .asFuture<void>();
      final stderrDone = process.stderr
          .transform(const SystemEncoding().decoder)
          .listen(stderrText.write)
          .asFuture<void>();
      final timeout = linuxRawWriteAndVerifyTimeoutForBytes(imageBytes);
      _logLine(
        'Linux raw write and verification timeout: ${timeout.inSeconds}s '
        'for $imageBytes bytes.',
      );
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
          verificationFailed: verificationStarted && !imageVerified,
          imageVerified: imageVerified,
          diskOnline: diskOnline,
        );
      }
      await Future.wait([
        stdoutDone.catchError((_) {}),
        stderrDone.catchError((_) {}),
      ]);
      if (_cancelRequested) {
        return _LinuxRawWriteResult(
          success: false,
          cancelled: true,
          error: 'Linux raw writing was cancelled.',
          verificationFailed: verificationStarted && !imageVerified,
          imageVerified: imageVerified,
          diskOnline: diskOnline,
        );
      }
      if (exitCode != 0) {
        final rawDetail = stderrText.toString().trim().isNotEmpty
            ? stderrText.toString().trim()
            : restoreFailureDetail ?? stdoutText.toString().trim();
        final detail = _summarizePowerShellFailure(
          rawDetail,
          fallback: 'PowerShell exited with code $exitCode.',
        );
        return _LinuxRawWriteResult(
          success: false,
          error: detail,
          failureMessageKey: imageVerified && !diskOnline
              ? 'linux_write_failed'
              : null,
          verificationFailed: verificationStarted && !imageVerified,
          imageVerified: imageVerified,
          diskOnline: diskOnline,
        );
      }
      if (!imageVerified || !diskOnline || !completed) {
        return _LinuxRawWriteResult(
          success: false,
          error: imageVerified
              ? 'Image verification finished, but the target disk was not returned online.'
              : 'Linux raw verification did not complete.',
          failureMessageKey: imageVerified ? 'linux_write_failed' : null,
          verificationFailed: !imageVerified,
          imageVerified: imageVerified,
          diskOnline: diskOnline,
        );
      }
      return const _LinuxRawWriteResult(
        success: true,
        imageVerified: true,
        diskOnline: true,
      );
    } catch (error) {
      if (process != null) {
        await _terminateProcessTree(process, reason: 'Linux write failed');
      }
      return _LinuxRawWriteResult(
        success: false,
        error: 'Linux raw writing failed: $error',
        verificationFailed: verificationStarted && !imageVerified,
        imageVerified: imageVerified,
        diskOnline: diskOnline,
      );
    } finally {
      if (identical(_activeLinuxRawWriteProcess, process)) {
        _activeLinuxRawWriteProcess = null;
      }
    }
  }

  Future<_LinuxRawWriteResult> _restoreLinuxRawDiskOnline({
    required DiskInfo disk,
  }) async {
    try {
      final command = InMemoryPowerShell.build(
        script: _linuxRawFinalizeScript,
        parameters: {
          'DiskNumber': '${disk.diskNumber}',
          'ExpectedSize': '${disk.sizeBytes}',
          'ExpectedModel': disk.model,
          'ExpectedBus': disk.busType,
          'ExpectedSerial': disk.reliableSerialNumber,
          'ExpectedDevicePath': disk.reliableDevicePath,
          'ExpectedUniqueId': disk.reliableUniqueId,
        },
      );
      final result = await _runLinuxUtility(
        command.executable,
        command.arguments,
        timeout: const Duration(seconds: 30),
        environment: command.environment,
        trackForCancellation: false,
      );
      if (result.exitCode != 0 ||
          !result.stdout.toString().contains('WDS_DISK_ONLINE')) {
        final rawDetail = result.stderr.toString().trim().isNotEmpty
            ? result.stderr.toString().trim()
            : result.stdout.toString().trim();
        final detail = _summarizePowerShellFailure(
          rawDetail,
          fallback: 'Unable to return target disk ${disk.diskNumber} online.',
        );
        _logLine('Linux raw disk recovery failed: $detail');
        return _LinuxRawWriteResult(success: false, error: detail);
      }
      _logLine('Linux raw disk returned online and refreshed.');
      return const _LinuxRawWriteResult(success: true);
    } catch (error) {
      final detail =
          'Unable to return target disk ${disk.diskNumber} online: '
          '$error';
      _logLine('Linux raw disk recovery exception: $detail');
      return _LinuxRawWriteResult(success: false, error: detail);
    }
  }

  static String _summarizePowerShellFailure(
    String raw, {
    required String fallback,
  }) {
    for (var line in raw.replaceAll('\r\n', '\n').split('\n')) {
      line = line.trim();
      if (line.isEmpty ||
          line.startsWith('#< CLIXML') ||
          line.startsWith('<') ||
          line.startsWith('---') ||
          line.startsWith('WDS_') ||
          line.startsWith('at ') ||
          line.startsWith('At ') ||
          line.startsWith('在 ') ||
          line.contains('System.Management.Automation.Interpreter') ||
          line.contains('System.Management.Automation.ExceptionHandlingOps')) {
        continue;
      }

      final exceptionPrefix = RegExp(
        r'^(?:System\.[^:]+|[A-Za-z0-9_.]+(?:Exception|Error)):\s*',
      ).firstMatch(line);
      if (exceptionPrefix != null) {
        line = line.substring(exceptionPrefix.end).trim();
      }
      line = line.replaceFirst(RegExp(r'\s*--->.*$'), '').trim();
      if (line.isEmpty) continue;
      return line.length <= 480 ? line : '${line.substring(0, 477)}...';
    }
    return fallback;
  }

  Future<void> _terminateProcessTree(
    Process process, {
    required String reason,
  }) async {
    _logLine('$reason; terminating process tree PID ${process.pid}');
    if (Platform.isWindows) {
      try {
        final result = await Process.run(
          WindowsSystemEnvironment.taskkillExecutable,
          ['/PID', '${process.pid}', '/T', '/F'],
          environment: WindowsSystemEnvironment.withSystemRoot(),
        ).timeout(const Duration(seconds: 15));
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
    Map<String, String>? environment,
    bool trackForCancellation = true,
  }) async {
    Process? process;
    try {
      process = await Process.start(
        executable,
        arguments,
        environment: environment,
      );
      if (trackForCancellation) {
        _activeLinuxUtilityProcess = process;
      }
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
      if (trackForCancellation &&
          identical(_activeLinuxUtilityProcess, process)) {
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

function Test-OfflineIsolationUnsupported([object]$Failure) {
  if ($Failure.Exception -and
      [int]$Failure.Exception.HResult -eq -2147024846) {
    # HRESULT 0x80070032: ERROR_NOT_SUPPORTED.
    return $true
  }

  $details = @(
    [string]$Failure.Exception.Message,
    [string]$Failure.FullyQualifiedErrorId,
    [string]$Failure.CategoryInfo,
    [string]$Failure
  ) -join [Environment]::NewLine
  return $details -match '(?i)\b(not supported|not implemented)\b' -or
    $details -match '不支持|未实现'
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

if ($ExpectedIsoLength -gt [int64]$disk.Size) {
  throw "ISO image is larger than the target disk."
}
$sourceVolume = Get-Volume -FilePath $IsoPath -ErrorAction Stop
$sourcePartitions = @(Get-Partition -Volume $sourceVolume -ErrorAction Stop)
if ($sourcePartitions.Count -ne 1) {
  throw "ISO source did not resolve to exactly one physical partition."
}
if ([int]$sourcePartitions[0].DiskNumber -eq $DiskNumber) {
  throw "ISO source is stored on the target disk."
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
$offlineIsolation = $false
try {
  Set-Disk -Number $DiskNumber -IsOffline $true -ErrorAction Stop
  $offlineIsolation = $true
  Write-Output 'WDS_ISOLATION:OFFLINE'
} catch {
  # Some removable-media bridges reject the Storage cmdlet with
  # ERROR_NOT_SUPPORTED. The exclusive raw handle below is then held over
  # both the write and the full verification, with no Update-Disk in between.
  if (-not (Test-OfflineIsolationUnsupported $_)) {
    throw
  }
  Write-Output 'WDS_ISOLATION:EXCLUSIVE'
}

if ($offlineIsolation) {
  Start-Sleep -Milliseconds 700
}

$source = $null
$target = $null
$sourceHash = $null
$targetHash = $null
$operationFailure = $null
$restoreFailure = $null
try {
  $source = [System.IO.File]::Open(
    $IsoPath,
    [System.IO.FileMode]::Open,
    [System.IO.FileAccess]::Read,
    [System.IO.FileShare]::Read
  )
  if ([int64]$source.Length -ne $ExpectedIsoLength) {
    throw "ISO file changed before raw writing."
  }

  $targetPath = "\\.\PhysicalDrive$DiskNumber"
  $target = [System.IO.File]::Open(
    $targetPath,
    [System.IO.FileMode]::Open,
    [System.IO.FileAccess]::ReadWrite,
    [System.IO.FileShare]::None
  )

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

  # Do not release the target handle before this verification finishes. This
  # keeps the fallback safe for bridges that do not implement Set-Disk
  # offline, and also avoids a separate process observing a newly-written
  # hybrid partition layout.
  Write-Output 'WDS_VERIFY_STARTED'
  Write-Output 'WDS_VERIFY_PROGRESS:0'
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
  $firstMismatchOffset = [int64]-1
  $firstSourceByte = $null
  $firstTargetByte = $null
  $lastVerifyPercent = -1

  while ($verified -lt $total) {
    # Keep arithmetic in Int64 until the bounded chunk length is known.  Calling
    # Math.Min here can select an Int32 overload in PowerShell and overflow when
    # the remaining ISO size is larger than 2 GiB.
    $remaining = [int64]($total - $verified)
    $requested = if ($remaining -lt [int64]$bufferLength) {
      [int]$remaining
    } else {
      [int]$bufferLength
    }
    $sourceRead = $source.Read($sourceBuffer, 0, $requested)
    $targetRead = $target.Read($targetBuffer, 0, $requested)
    if ($sourceRead -ne $requested -or $targetRead -ne $requested) {
      throw "Short read while verifying at offset $verified."
    }

    $sourceHash.AppendData($sourceBuffer, 0, $requested)
    $targetHash.AppendData($targetBuffer, 0, $requested)
    # Most blocks match.  Use the CLR's byte-array enumeration for the fast
    # path and only walk a block byte-by-byte after a mismatch is detected.
    # A PowerShell loop over every byte of a multi-gigabyte image would make
    # a successful verification impractically slow.
    $blockMatches = if ($requested -eq $bufferLength) {
      [System.Linq.Enumerable]::SequenceEqual(
        [byte[]]$sourceBuffer,
        [byte[]]$targetBuffer
      )
    } else {
      $matches = $true
      for ($index = 0; $index -lt $requested; $index++) {
        if ($sourceBuffer[$index] -ne $targetBuffer[$index]) {
          $matches = $false
          break
        }
      }
      $matches
    }
    if ($firstMismatchOffset -lt 0 -and -not $blockMatches) {
      for ($index = 0; $index -lt $requested; $index++) {
        if ($sourceBuffer[$index] -ne $targetBuffer[$index]) {
          $firstMismatchOffset = $verified + $index
          $firstSourceByte = $sourceBuffer[$index]
          $firstTargetByte = $targetBuffer[$index]
          break
        }
      }
    }

    $verified += $requested
    $verifyPercent = [int][Math]::Floor(($verified * 100.0) / $total)
    if ($verifyPercent -ne $lastVerifyPercent) {
      Write-Output ("WDS_VERIFY_PROGRESS:{0}" -f $verifyPercent)
      $lastVerifyPercent = $verifyPercent
    }
  }

  $sourceDigest = $sourceHash.GetHashAndReset()
  $targetDigest = $targetHash.GetHashAndReset()
  if ($firstMismatchOffset -ge 0) {
    throw (
      "Full-stream SHA-256 verification mismatch at offset {0} " +
      "(source 0x{1:X2}, target 0x{2:X2})." -f
        $firstMismatchOffset, $firstSourceByte, $firstTargetByte
    )
  }
  if (-not [System.Linq.Enumerable]::SequenceEqual(
      [byte[]]$sourceDigest,
      [byte[]]$targetDigest
    )) {
    throw "Full-stream SHA-256 verification mismatch."
  }

  Write-Output "WDS_VERIFY_COMPLETE"
} catch {
  # Always release the exclusive raw handle before asking the Storage module
  # to rediscover the newly-written hybrid layout.  Retaining the original
  # error lets the caller distinguish write/verification failures from the
  # recovery step below.
  $operationFailure = $_
} finally {
  if ($null -ne $targetHash) { $targetHash.Dispose() }
  if ($null -ne $sourceHash) { $sourceHash.Dispose() }
  if ($null -ne $target) { $target.Dispose() }
  if ($null -ne $source) { $source.Dispose() }
}

# Do this in the same elevated PowerShell process that performed the raw
# write. Starting a second process after verification can be denied by a
# security product or by a transient device state, even though the image is
# already correct. The separate finalizer remains only as a timeout/cancel
# fallback in Dart.
try {
  $restoredDisk = Get-Disk -Number $DiskNumber -ErrorAction Stop
  $restoredBus = $restoredDisk.BusType.ToString().ToUpperInvariant()
  $restoredIsExternal = $restoredBus -in @('USB', 'SD', 'MMC') -or [bool]$restoredDisk.IsRemovable
  if (-not $restoredIsExternal -or $restoredDisk.IsSystem -or $restoredDisk.IsBoot) {
    throw "Refusing to return a non-external disk online."
  }
  if ([int64]$restoredDisk.Size -ne $ExpectedSize -or
      $restoredDisk.FriendlyName.ToString().Trim().ToUpperInvariant() -ne $ExpectedModel.Trim().ToUpperInvariant() -or
      $restoredBus -ne $ExpectedBus.Trim().ToUpperInvariant()) {
    throw "Target disk identity changed before it could be returned online."
  }
  if ($ExpectedSerial -and $ExpectedSerial.Trim().ToUpperInvariant() -notin @('N/A', 'UNKNOWN')) {
    $physical = Get-PhysicalDisk -ErrorAction Stop |
      Where-Object { $_.DeviceId -eq $restoredDisk.Number.ToString() } |
      Select-Object -First 1
    $currentSerial = if ($physical -and $physical.SerialNumber) {
      $physical.SerialNumber.ToString().Trim().ToUpperInvariant()
    } else { '' }
    if ($currentSerial -ne $ExpectedSerial.Trim().ToUpperInvariant()) {
      throw "Target disk serial number changed before it could be returned online."
    }
  } elseif ($ExpectedUniqueId) {
    $currentUniqueId = if ($restoredDisk.UniqueId) { $restoredDisk.UniqueId.ToString().Trim().ToUpperInvariant() } else { '' }
    if ($currentUniqueId -ne $ExpectedUniqueId.Trim().ToUpperInvariant()) {
      throw "Target disk unique identity changed before it could be returned online."
    }
  } elseif ($ExpectedDevicePath) {
    $currentPath = if ($restoredDisk.Path) { $restoredDisk.Path.ToString().Trim().ToUpperInvariant() } else { '' }
    if ($currentPath -ne $ExpectedDevicePath.Trim().ToUpperInvariant()) {
      throw "Target disk device path changed before it could be returned online."
    }
  } else {
    throw "Target disk has no reliable physical identity."
  }

  if ($restoredDisk.IsOffline) {
    Set-Disk -Number $DiskNumber -IsOffline $false -ErrorAction Stop
  }
  Update-Disk -Number $DiskNumber -ErrorAction Stop | Out-Null
  $onlineDisk = Get-Disk -Number $DiskNumber -ErrorAction Stop
  if ([bool]$onlineDisk.IsOffline) {
    throw "Target disk is still offline after recovery."
  }
  Write-Output "WDS_DISK_ONLINE"
} catch {
  $restoreFailure = $_
  Write-Output ("WDS_RESTORE_FAILED:{0}" -f $_.Exception.Message)
}

if ($null -ne $operationFailure) {
  if ($null -ne $restoreFailure) {
    throw (
      "Linux raw operation failed: {0}`nDisk recovery also failed: {1}" -f
        $operationFailure.Exception.Message, $restoreFailure.Exception.Message
    )
  }
  throw $operationFailure
}
if ($null -ne $restoreFailure) {
  throw (
    "Image verification completed, but the target disk could not be returned online: {0}" -f
      $restoreFailure.Exception.Message
  )
}

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
if (-not $isExternal -or $targetDisk.IsSystem -or $targetDisk.IsBoot -or -not $targetDisk.IsOffline) {
  throw "The verification target is no longer isolated from Windows."
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
  [System.IO.FileShare]::None
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
  $firstMismatchOffset = [int64]-1
  $firstSourceByte = $null
  $firstTargetByte = $null
  $lastPercent = -1
  Write-Output "WDS_VERIFY_PROGRESS:0"
  while ($verified -lt $isoLength) {
    # Keep arithmetic in Int64 until the bounded chunk length is known.  Calling
    # Math.Min here can select an Int32 overload in PowerShell and overflow when
    # the remaining ISO size is larger than 2 GiB.
    $remaining = [int64]($isoLength - $verified)
    $requested = if ($remaining -lt [int64]$bufferLength) {
      [int]$remaining
    } else {
      [int]$bufferLength
    }
    if ($requested -lt $bufferLength) {
      [System.Array]::Clear($sourceBuffer, 0, $bufferLength)
      [System.Array]::Clear($targetBuffer, 0, $bufferLength)
    }
    $sourceRead = $source.Read($sourceBuffer, 0, $requested)
    $targetRead = $target.Read($targetBuffer, 0, $requested)
    if ($sourceRead -ne $requested -or $targetRead -ne $requested) {
      throw "Short read while verifying at offset $verified."
    }
    $sourceHash.AppendData($sourceBuffer, 0, $requested)
    $targetHash.AppendData($targetBuffer, 0, $requested)
    if ($firstMismatchOffset -lt 0 -and -not [System.Linq.Enumerable]::SequenceEqual(
        [byte[]]$sourceBuffer,
        [byte[]]$targetBuffer
      )) {
      for ($index = 0; $index -lt $requested; $index++) {
        if ($sourceBuffer[$index] -ne $targetBuffer[$index]) {
          $firstMismatchOffset = $verified + $index
          $firstSourceByte = $sourceBuffer[$index]
          $firstTargetByte = $targetBuffer[$index]
          break
        }
      }
    }
    $verified += $requested
    $percent = [int][Math]::Floor(($verified * 100.0) / $isoLength)
    if ($percent -ne $lastPercent) {
      Write-Output ("WDS_VERIFY_PROGRESS:{0}" -f $percent)
      $lastPercent = $percent
    }
  }

  $sourceDigest = $sourceHash.GetHashAndReset()
  $targetDigest = $targetHash.GetHashAndReset()
  if ($firstMismatchOffset -ge 0) {
    throw (
      "Full-stream SHA-256 verification mismatch at offset {0} " +
      "(source 0x{1:X2}, target 0x{2:X2})." -f
        $firstMismatchOffset, $firstSourceByte, $firstTargetByte
    )
  }
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

  static const String _linuxRawFinalizeScript = r'''
param(
  [Parameter(Mandatory = $true)][int]$DiskNumber,
  [Parameter(Mandatory = $true)][int64]$ExpectedSize,
  [Parameter(Mandatory = $true)][string]$ExpectedModel,
  [Parameter(Mandatory = $true)][string]$ExpectedBus,
  [string]$ExpectedSerial = '',
  [string]$ExpectedDevicePath = '',
  [string]$ExpectedUniqueId = ''
)

$ErrorActionPreference = 'Stop'

$disk = Get-Disk -Number $DiskNumber -ErrorAction Stop
$bus = $disk.BusType.ToString().ToUpperInvariant()
$isExternal = $bus -in @('USB', 'SD', 'MMC') -or [bool]$disk.IsRemovable
if (-not $isExternal -or $disk.IsSystem -or $disk.IsBoot) {
  throw "Refusing to return a non-external disk online."
}
if ([int64]$disk.Size -ne $ExpectedSize -or
    $disk.FriendlyName.ToString().Trim().ToUpperInvariant() -ne $ExpectedModel.Trim().ToUpperInvariant() -or
    $bus -ne $ExpectedBus.Trim().ToUpperInvariant()) {
  throw "Target disk identity changed before it could be returned online."
}
if ($ExpectedSerial -and $ExpectedSerial.Trim().ToUpperInvariant() -notin @('N/A', 'UNKNOWN')) {
  $physical = Get-PhysicalDisk -ErrorAction Stop |
    Where-Object { $_.DeviceId -eq $disk.Number.ToString() } |
    Select-Object -First 1
  $currentSerial = if ($physical -and $physical.SerialNumber) {
    $physical.SerialNumber.ToString().Trim().ToUpperInvariant()
  } else { '' }
  if ($currentSerial -ne $ExpectedSerial.Trim().ToUpperInvariant()) {
    throw "Target disk serial number changed before it could be returned online."
  }
} elseif ($ExpectedUniqueId) {
  $currentUniqueId = if ($disk.UniqueId) { $disk.UniqueId.ToString().Trim().ToUpperInvariant() } else { '' }
  if ($currentUniqueId -ne $ExpectedUniqueId.Trim().ToUpperInvariant()) {
    throw "Target disk unique identity changed before it could be returned online."
  }
} elseif ($ExpectedDevicePath) {
  $currentPath = if ($disk.Path) { $disk.Path.ToString().Trim().ToUpperInvariant() } else { '' }
  if ($currentPath -ne $ExpectedDevicePath.Trim().ToUpperInvariant()) {
    throw "Target disk device path changed before it could be returned online."
  }
} else {
  throw "Target disk has no reliable physical identity."
}

if ($disk.IsOffline) {
  Set-Disk -Number $DiskNumber -IsOffline $false -ErrorAction Stop
}
Update-Disk -Number $DiskNumber -ErrorAction Stop | Out-Null
Write-Output "WDS_DISK_ONLINE"
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
    final currentDisk = await ref
        .read(diskSafetyServiceProvider)
        .refreshDisk(disk);
    if (currentDisk == null) {
      return const _DiskPartResult(
        success: false,
        error: 'Target disk identity changed before partitioning.',
      );
    }
    final label = _sanitizeVolumeLabel(volumeLabel, fallback: 'WDS_BOOT');
    final useGpt = deploymentBootMode == DeploymentBootMode.uefiGpt;
    final targetStyle = useGpt ? 'GPT' : 'MBR';
    final diskSafety = ref.read(diskSafetyServiceProvider);
    _logLine('Initializing target disk as $targetStyle before partitioning.');
    final initialization = await diskSafety.initializeDiskPartitionStyle(
      currentDisk,
      partitionStyle: targetStyle,
    );
    if (initialization.exitCode != 0) {
      final stderr = initialization.stderr.toString();
      final stdout = initialization.stdout.toString();
      final detail = _summarizePowerShellFailure(
        stderr.trim().isNotEmpty ? stderr : stdout,
        fallback: 'Disk initialization failed.',
      );
      _logLine('Disk initialization failed: $detail');
      return _DiskPartResult(success: false, error: detail);
    }
    final initializedDisk = await diskSafety.refreshDisk(currentDisk);
    if (initializedDisk == null ||
        initializedDisk.partitionStyle.toUpperCase() != targetStyle) {
      return const _DiskPartResult(
        success: false,
        error: 'Target disk initialization could not be verified.',
      );
    }
    final script = _buildInstallMediaDiskpartScript(
      diskNumber: diskNumber,
      currentPartitionStyle: initializedDisk.partitionStyle,
      deploymentBootMode: deploymentBootMode,
      preferredDriveLetter: requestedLetter ?? '',
      volumeLabel: label,
      diskSizeBytes: initializedDisk.sizeBytes,
    );
    _logLine('DiskPart script:\n$script');

    final result = await diskSafety.runGuardedDiskpart(initializedDisk, script);
    _logLine('DiskPart exit: ${result.exitCode}');

    if (!_diskpartSucceeded(result)) {
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
      expectedEfiSystemPartition: useGpt,
      expectedActive: deploymentBootMode == DeploymentBootMode.legacyBios,
    )) {
      _logLine('Install media partition postcondition check failed');
      return const _DiskPartResult(
        success: false,
        error: 'i18n:boot_partition_layout_not_ready',
      );
    }

    return _DiskPartResult(success: true, driveLetter: driveLetter);
  }

  static String _buildInstallMediaDiskpartScript({
    required int diskNumber,
    required String currentPartitionStyle,
    required DeploymentBootMode deploymentBootMode,
    required String preferredDriveLetter,
    required String volumeLabel,
    required int? diskSizeBytes,
  }) {
    final normalizedLetter = _normalizePreferredLetter(preferredDriveLetter);
    final fat32PartitionSizeMb = _fat32PartitionSizeMbForDisk(diskSizeBytes);
    final useGpt = deploymentBootMode == DeploymentBootMode.uefiGpt;
    final partitionKind = useGpt ? 'efi' : 'primary';
    final partitionCommand = fat32PartitionSizeMb == null
        ? 'create partition $partitionKind'
        : 'create partition $partitionKind size=$fat32PartitionSizeMb';
    final commands = <String>[
      'select disk $diskNumber',
      // A UEFI + GPT installation disk uses one full-size ESP. This keeps the
      // normal removable-media fallback path while retaining a mountable FAT32
      // volume for the installation files.
      partitionCommand,
      // Some DiskPart builds do not select the corresponding volume after
      // creating a partition. Select it explicitly before formatting.
      'select partition 1',
      'format fs=fat32 label="$volumeLabel" quick',
      normalizedLetter == null ? 'assign' : 'assign letter=$normalizedLetter',
      if (deploymentBootMode == DeploymentBootMode.legacyBios)
        'select partition 1',
      if (deploymentBootMode == DeploymentBootMode.legacyBios) 'active',
      'exit',
    ];
    return '${commands.join('\n')}\n';
  }

  static int? _fat32PartitionSizeMbForDisk(int? diskSizeBytes) {
    if (diskSizeBytes == null ||
        diskSizeBytes <= _fat32NativeFormatLimitBytes) {
      return null;
    }
    return _fat32BootPartitionSizeMb;
  }

  Future<bool> _verifyInstallMediaPartition({
    required int diskNumber,
    required String driveLetter,
    required String expectedPartitionStyle,
    required String expectedLabel,
    required bool expectedEfiSystemPartition,
    required bool expectedActive,
  }) async {
    try {
      final letter = driveLetter.replaceAll(RegExp(r'[:\\]'), '').toUpperCase();
      final result = await _runPowerShell(
        [
          '-NoProfile',
          '-NonInteractive',
          '-ExecutionPolicy',
          'Bypass',
          '-Command',
          r'''$deadline = (Get-Date).AddSeconds(25)
$lastError = ''
while ((Get-Date) -lt $deadline) {
  try {
    $partition = Get-Partition -DriveLetter $env:WDS_DRIVE_LETTER -ErrorAction Stop
    $volume = Get-Volume -DriveLetter $env:WDS_DRIVE_LETTER -ErrorAction Stop
    $disk = Get-Disk -Number $partition.DiskNumber -ErrorAction Stop
    $label = if ($volume.FileSystemLabel) { $volume.FileSystemLabel.ToString() } else { '' }
    $fileSystem = if ($volume.FileSystem) { $volume.FileSystem.ToString() } else { '' }
    $gptType = if ($partition.GptType) { $partition.GptType.ToString() } else { '' }
    $isEfiSystemPartition = $gptType -eq 'C12A7328-F81F-11D2-BA4B-00A0C93EC93B'
    $actual = [PSCustomObject]@{
      DiskNumber = $partition.DiskNumber
      PartitionStyle = $disk.PartitionStyle.ToString()
      Label = $label
      FileSystem = $fileSystem
      EfiSystemPartition = [bool]$isEfiSystemPartition
      IsActive = [bool]$partition.IsActive
    }
    if ($actual.DiskNumber -eq [int]$env:WDS_EXPECTED_DISK_NUMBER -and
        $actual.PartitionStyle.ToUpperInvariant() -eq $env:WDS_EXPECTED_PARTITION_STYLE.ToUpperInvariant() -and
        $actual.Label.ToUpperInvariant() -eq $env:WDS_EXPECTED_LABEL.ToUpperInvariant() -and
        $actual.FileSystem.ToUpperInvariant() -eq 'FAT32' -and
        $actual.EfiSystemPartition -eq [bool]::Parse($env:WDS_EXPECTED_EFI_SYSTEM_PARTITION) -and
        $actual.IsActive -eq [bool]::Parse($env:WDS_EXPECTED_ACTIVE)) {
      $actual | ConvertTo-Json -Compress
      exit 0
    }
    $lastError = "Observed disk=$($actual.DiskNumber), style=$($actual.PartitionStyle), label=$($actual.Label), filesystem=$($actual.FileSystem)."
  } catch {
    $lastError = $_.Exception.Message
  }
  Start-Sleep -Milliseconds 500
}
if ($lastError) { Write-Error $lastError }
exit 1''',
        ],
        environment: {
          ...Platform.environment,
          'WDS_DRIVE_LETTER': letter,
          'WDS_EXPECTED_DISK_NUMBER': '$diskNumber',
          'WDS_EXPECTED_PARTITION_STYLE': expectedPartitionStyle,
          'WDS_EXPECTED_LABEL': expectedLabel,
          'WDS_EXPECTED_EFI_SYSTEM_PARTITION': '$expectedEfiSystemPartition',
          'WDS_EXPECTED_ACTIVE': '$expectedActive',
        },
        timeout: const Duration(seconds: 35),
      );
      final stdout = result.stdout.toString().trim();
      final stderr = result.stderr.toString().trim();
      if (result.exitCode != 0 || stdout.isEmpty) {
        _logLine(
          'Install media partition verification output: '
          '${stderr.isNotEmpty ? stderr : stdout}',
        );
        return false;
      }
      final data = jsonDecode(stdout);
      return data is Map &&
          _installMediaPartitionMatches(
            data,
            expectedDiskNumber: diskNumber,
            expectedPartitionStyle: expectedPartitionStyle,
            expectedLabel: expectedLabel,
            expectedEfiSystemPartition: expectedEfiSystemPartition,
            expectedActive: expectedActive,
          );
    } catch (error) {
      _logLine('Install media partition verification error: $error');
      return false;
    }
  }

  static bool _installMediaPartitionMatches(
    Map<dynamic, dynamic> actual, {
    required int expectedDiskNumber,
    required String expectedPartitionStyle,
    required String expectedLabel,
    bool? expectedEfiSystemPartition,
    bool? expectedActive,
  }) {
    final efiMatches =
        expectedEfiSystemPartition == null ||
        actual['EfiSystemPartition'].toString().toLowerCase() ==
            expectedEfiSystemPartition.toString().toLowerCase();
    final activeMatches =
        expectedActive == null ||
        actual['IsActive'].toString().toLowerCase() ==
            expectedActive.toString().toLowerCase();
    return actual['DiskNumber'].toString() == expectedDiskNumber.toString() &&
        actual['PartitionStyle'].toString().toUpperCase() ==
            expectedPartitionStyle.toUpperCase() &&
        actual['Label'].toString().toUpperCase() ==
            expectedLabel.toUpperCase() &&
        actual['FileSystem'].toString().toUpperCase() == 'FAT32' &&
        efiMatches &&
        activeMatches;
  }

  static String? _normalizePreferredLetter(String value) {
    final normalized = value
        .trim()
        .replaceAll(RegExp(r'[:\\]'), '')
        .toUpperCase();
    if (normalized.isEmpty) return null;
    return RegExp(r'^[D-Z]$').hasMatch(normalized) ? normalized : null;
  }

  Future<bool> _isDriveLetterAvailable(String letter, int diskNumber) async {
    try {
      final result = await _runPowerShell(
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
        timeout: const Duration(seconds: 8),
      );
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
      final result = await _runPowerShell(
        const [
          '-NoProfile',
          '-NonInteractive',
          '-ExecutionPolicy',
          'Bypass',
          '-Command',
          r'''$deadline = (Get-Date).AddSeconds(25)
$lastError = ''
while ((Get-Date) -lt $deadline) {
  try {
    $letter = Get-Partition -DiskNumber ([int]$env:WDS_DISK_NUMBER) -ErrorAction Stop |
      Where-Object { $_.DriveLetter } |
      Sort-Object PartitionNumber |
      Select-Object -First 1 -ExpandProperty DriveLetter
    if ($letter) {
      Write-Output $letter
      exit 0
    }
    $lastError = 'The new volume does not have a drive letter yet.'
  } catch {
    $lastError = $_.Exception.Message
  }
  Start-Sleep -Milliseconds 500
}
if ($lastError) { Write-Error $lastError }
exit 1''',
        ],
        environment: {
          ...Platform.environment,
          'WDS_DISK_NUMBER': '$diskNumber',
        },
        timeout: const Duration(seconds: 35),
      );
      if (result.exitCode == 0) {
        final letter = _normalizePreferredLetter(result.stdout.toString());
        if (letter != null) return '$letter:';
      } else {
        _logLine(
          'Drive-letter discovery output: '
          '${result.stderr.toString().trim()}',
        );
      }
    } catch (error) {
      _logLine('Drive-letter discovery error: $error');
    }

    return null;
  }

  // --- Formatting ---

  Future<bool> _formatPartition({
    required String driveLetter,
    required String fileSystem,
  }) async {
    try {
      final result = await _runPowerShell([
        '-NoProfile',
        '-NonInteractive',
        '-ExecutionPolicy',
        'Bypass',
        '-Command',
        'Get-Volume -DriveLetter ${driveLetter.replaceAll(":", "")} | Select-Object -ExpandProperty FileSystem',
      ], timeout: const Duration(seconds: 10));
      return result.exitCode == 0 &&
          result.stdout.toString().trim().toUpperCase() ==
              fileSystem.toUpperCase();
    } catch (_) {
      return false;
    }
  }

  // --- ISO Mounting ---

  // Windows installation-media creation needs bounded mount operations because
  // this path has already repartitioned the selected USB drive when the second
  // mount occurs. Keep it separate from the Linux To Go mount helper below so
  // its behavior remains unchanged.
  Future<String?> _mountWindowsInstallIso(String isoPath) async {
    var mounted = false;
    // The cleanup path must also run if the stale-mount probe itself fails.
    // Dismount-DiskImage can time out while an existing image remains mounted.
    var mountMayExist = true;
    try {
      final escapedPath = isoPath.replaceAll("'", "''");
      _logLine('Mounting Windows installation ISO: $isoPath');
      await _runPowerShell([
        '-NoProfile',
        '-NonInteractive',
        '-ExecutionPolicy',
        'Bypass',
        '-Command',
        "Dismount-DiskImage -ImagePath '$escapedPath' -ErrorAction SilentlyContinue | Out-Null",
      ], timeout: const Duration(seconds: 10));
      final mountResult = await _runPowerShell([
        '-NoProfile',
        '-NonInteractive',
        '-ExecutionPolicy',
        'Bypass',
        '-Command',
        "Mount-DiskImage -ImagePath '$escapedPath' -PassThru -ErrorAction Stop | Out-Null",
      ], timeout: const Duration(seconds: 30));
      if (mountResult.exitCode != 0) {
        _logLine(
          'Windows installation ISO mount failed: ${mountResult.stderr}',
        );
      } else {
        mounted = true;
        final deadline = DateTime.now().add(const Duration(seconds: 20));
        while (DateTime.now().isBefore(deadline)) {
          await Future<void>.delayed(const Duration(milliseconds: 400));
          final remaining = deadline.difference(DateTime.now());
          if (remaining <= Duration.zero) break;
          final volumeResult = await _runPowerShell(
            [
              '-NoProfile',
              '-NonInteractive',
              '-ExecutionPolicy',
              'Bypass',
              '-Command',
              "Get-DiskImage -ImagePath '$escapedPath' | Get-Volume | Select-Object -ExpandProperty DriveLetter",
            ],
            timeout: remaining > const Duration(seconds: 4)
                ? const Duration(seconds: 4)
                : remaining,
          );
          final letter = volumeResult.stdout.toString().trim();
          if (volumeResult.exitCode == 0 &&
              RegExp(r'^[A-Za-z]$').hasMatch(letter)) {
            return '${letter.toUpperCase()}:\\';
          }
        }
        _logLine(
          'Windows installation ISO mount did not receive a drive letter.',
        );
      }
    } catch (error) {
      _logLine('Windows installation ISO mount error: $error');
    }
    if (mounted || mountMayExist) await _unmountWindowsInstallIso(isoPath);
    return null;
  }

  Future<void> _unmountWindowsInstallIso(String isoPath) async {
    try {
      final escapedPath = isoPath.replaceAll("'", "''");
      final result = await _runPowerShell([
        '-NoProfile',
        '-NonInteractive',
        '-ExecutionPolicy',
        'Bypass',
        '-Command',
        "Dismount-DiskImage -ImagePath '$escapedPath' -ErrorAction SilentlyContinue | Out-Null",
      ], timeout: const Duration(seconds: 15));
      if (result.exitCode != 0) {
        _logLine('Windows installation ISO unmount warning: ${result.stderr}');
      }
    } catch (error) {
      _logLine('Windows installation ISO unmount error: $error');
    }
  }

  Future<String?> _mountIso(String isoPath) async {
    try {
      final escapedPath = isoPath.replaceAll("'", "''");
      _logLine('Mounting ISO: $isoPath');

      // Clean up any stale mount
      await _runPowerShell([
        '-NoProfile',
        '-ExecutionPolicy',
        'Bypass',
        '-Command',
        "Dismount-DiskImage -ImagePath '$escapedPath' -ErrorAction SilentlyContinue | Out-Null",
      ]).timeout(const Duration(seconds: 10));

      // Mount
      final mountResult = await _runPowerShell([
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
        final letterResult = await _runPowerShell([
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
      await _runPowerShell([
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
    int? expectedTotalBytes,
    bool deferContentVerification = false,
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

      // Linux To Go supplies a manifest captured in a worker isolate during
      // preflight. Re-crawling a mounted 6+ GB ISO every second while robocopy
      // runs can monopolize the UI isolate and make the entire window appear
      // frozen. Other callers retain the legacy live-size progress path.
      final totalBytes =
          expectedTotalBytes ??
          await _directorySize(
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

      if (expectedTotalBytes != null) {
        // Keep the known copy stage visible without periodically walking the
        // destination tree. Exact file and SHA-256 verification follows the
        // copy using the same manifest.
        await exitFuture;
      } else {
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

      if (deferContentVerification) {
        _logLine(
          'robocopy content verification deferred to Linux To Go manifest',
        );
      } else {
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
        final sourceDigest = await BackgroundFileHashService.sha256File(entity);
        final targetDigest = await BackgroundFileHashService.sha256File(target);
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
    required String? dismExecutable,
  }) async {
    try {
      if (dismExecutable == null || dismExecutable.isEmpty) return false;
      final targetPath = p.join(targetDir, 'install.swm');
      final result = await _runLinuxUtility(
        dismExecutable,
        [
          '/Split-Image',
          '/ImageFile:$sourcePath',
          '/SWMFile:$targetPath',
          '/FileSize:3800',
        ],
        timeout: const Duration(minutes: 30),
        environment: WindowsSystemEnvironment.withSystemRoot(),
        trackForCancellation: false,
      );
      if (result.exitCode != 0) return false;
      final fragments = <File>[];
      await for (final entity in Directory(
        targetDir,
      ).list(followLinks: false)) {
        if (entity is! File) continue;
        final fileName = p.basename(entity.path).toLowerCase();
        if (RegExp(r'^install\d*\.swm$').hasMatch(fileName)) {
          fragments.add(entity);
        }
      }
      if (fragments.isEmpty) return false;
      for (final fragment in fragments) {
        final sizeBytes = await fragment.length();
        if (sizeBytes <= 0 ||
            sizeBytes > WindowsIsoLayoutInspector.fat32MaximumFileBytes) {
          _logLine(
            'Invalid split WIM fragment: ${fragment.path} ($sizeBytes bytes)',
          );
          return false;
        }
      }
      _logLine(
        'WIM split verification OK: ${fragments.length} SWM fragment(s).',
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  // --- Boot Files ---

  Future<bool> _writeBootFiles({
    required String targetDrive,
    required BootMode bootMode,
    required Set<WindowsEfiBootArchitecture> sourceEfiBootArchitectures,
    required WindowsEfiBootArchitecture? sourceEfiBootManagerArchitecture,
    required String? legacyBootsectExecutable,
  }) async {
    try {
      _logLine('Writing boot files: target=$targetDrive');

      // The copied setup BCD is the authoritative installer BCD. Do not create
      // an empty replacement store: it can make the volume look complete while
      // leaving it unable to boot Windows Setup.
      if (bootMode != BootMode.uefi) {
        if (legacyBootsectExecutable == null ||
            legacyBootsectExecutable.isEmpty) {
          _logLine(
            'Legacy boot chain requested but bootsect.exe was not preflighted.',
          );
          return false;
        }
        _logLine('Step 1: bootsect /nt60 $targetDrive /mbr');
        final bootsectResult = await _runLinuxUtility(
          legacyBootsectExecutable,
          ['/nt60', targetDrive, '/mbr'],
          timeout: const Duration(seconds: 30),
          environment: WindowsSystemEnvironment.withSystemRoot(),
          trackForCancellation: false,
        );
        _logLine('bootsect exit: ${bootsectResult.exitCode}');
        _logLine('bootsect stdout: ${bootsectResult.stdout}');
        if (bootsectResult.exitCode != 0) {
          _logLine('bootsect stderr: ${bootsectResult.stderr}');
          return false;
        }
      } else {
        _logLine('Step 1: skipped bootsect for UEFI-only mode');
      }

      // A Legacy installer needs the copied boot manager and BCD in addition
      // to a successful bootsect call above.
      final hasBootmgr = await File('$targetDrive\\bootmgr').exists();
      final bcd = File('$targetDrive\\boot\\BCD');
      final hasBiosBcd = await bcd.exists() && await bcd.length() > 0;
      if (bootMode != BootMode.uefi && (!hasBootmgr || !hasBiosBcd)) {
        _logLine(
          'Legacy boot files missing: bootmgr=$hasBootmgr, bcd=$hasBiosBcd',
        );
        return false;
      }

      final efiBcd = File('$targetDrive\\efi\\microsoft\\boot\\BCD');
      final hasEfiBcd = await efiBcd.exists() && await efiBcd.length() > 0;
      if (bootMode != BootMode.bios && !hasEfiBcd) {
        _logLine('UEFI boot configuration is missing: $efiBcd');
        return false;
      }

      var efiBootArchitectures = await _targetEfiBootArchitectures(targetDrive);
      if (bootMode != BootMode.bios && efiBootArchitectures.isEmpty) {
        final managerArchitecture = sourceEfiBootManagerArchitecture;
        final manager = File(
          '$targetDrive\\efi\\microsoft\\boot\\bootmgfw.efi',
        );
        if (managerArchitecture == null || !await manager.exists()) {
          _logLine(
            'UEFI fallback is missing and no architecture-verified boot manager is available.',
          );
          return false;
        }
        final efiBootDirectory = Directory('$targetDrive\\efi\\boot');
        await efiBootDirectory.create(recursive: true);
        final fallback = File(
          p.join(
            efiBootDirectory.path,
            _efiFallbackFileName(managerArchitecture),
          ),
        );
        await manager.copy(fallback.path);
        efiBootArchitectures = await _targetEfiBootArchitectures(targetDrive);
      }

      final expectedEfiArchitectures = <WindowsEfiBootArchitecture>{
        ...sourceEfiBootArchitectures,
      };
      if (expectedEfiArchitectures.isEmpty &&
          sourceEfiBootManagerArchitecture != null) {
        expectedEfiArchitectures.add(sourceEfiBootManagerArchitecture);
      }
      final hasExpectedEfiBoot =
          expectedEfiArchitectures.isNotEmpty &&
          efiBootArchitectures.containsAll(expectedEfiArchitectures);
      _logLine(
        'Final boot files: bootmgr=$hasBootmgr, bcd=$hasBiosBcd, '
        'efiBcd=$hasEfiBcd, '
        'efi=${efiBootArchitectures.map((value) => value.name).join(',')}.',
      );
      return (bootMode == BootMode.uefi || (hasBootmgr && hasBiosBcd)) &&
          (bootMode == BootMode.bios || hasExpectedEfiBoot);
    } catch (e) {
      _logLine('Boot file exception: $e');
      return false;
    }
  }

  static String _efiFallbackFileName(WindowsEfiBootArchitecture architecture) =>
      switch (architecture) {
        WindowsEfiBootArchitecture.x64 => 'bootx64.efi',
        WindowsEfiBootArchitecture.arm64 => 'bootaa64.efi',
        WindowsEfiBootArchitecture.ia32 => 'bootia32.efi',
      };

  Future<Set<WindowsEfiBootArchitecture>> _targetEfiBootArchitectures(
    String targetDrive,
  ) async {
    final found = <WindowsEfiBootArchitecture>{};
    for (final architecture in WindowsEfiBootArchitecture.values) {
      final path = p.join(
        targetDrive,
        'efi',
        'boot',
        _efiFallbackFileName(architecture),
      );
      if (await WindowsIsoLayoutInspector.readEfiArchitecture(path) ==
          architecture) {
        found.add(architecture);
      }
    }
    return found;
  }

  // --- Verification ---

  Future<bool> _verifyBootableUsb({
    required String driveLetter,
    required BootMode bootMode,
    required Set<WindowsEfiBootArchitecture> expectedEfiBootArchitectures,
    required _VolumeIconPayload? expectedIcon,
    required String expectedVolumeLabel,
  }) async {
    final errors = <String>[];

    // Legacy boot media must retain the setup boot manager and the BCD copied
    // from the ISO. A file-only bootmgr check can otherwise report success for
    // a disk with an empty or missing BCD store.
    final hasBootmgr = await File('$driveLetter\\bootmgr').exists();
    final bcd = File('$driveLetter\\boot\\BCD');
    final hasBiosBcd = await bcd.exists() && await bcd.length() > 0;
    if (bootMode != BootMode.uefi && (!hasBootmgr || !hasBiosBcd)) {
      errors.add(
        'Legacy boot chain incomplete (bootmgr=$hasBootmgr, bcd=$hasBiosBcd)',
      );
    }

    final efiBcd = File('$driveLetter\\efi\\microsoft\\boot\\BCD');
    final hasEfiBcd = await efiBcd.exists() && await efiBcd.length() > 0;
    if (bootMode != BootMode.bios && !hasEfiBcd) {
      errors.add('UEFI boot configuration missing (efi\\microsoft\\boot\\BCD)');
    }

    // Verify each architecture advertised by the source inspection. This
    // includes IA32, which was previously ignored, and avoids accepting an
    // ARM64 boot manager incorrectly copied under the x64 fallback name.
    final actualEfiArchitectures = await _targetEfiBootArchitectures(
      driveLetter,
    );
    if (bootMode != BootMode.bios &&
        (expectedEfiBootArchitectures.isEmpty ||
            !actualEfiArchitectures.containsAll(
              expectedEfiBootArchitectures,
            ))) {
      errors.add(
        'EFI fallback missing for ${expectedEfiBootArchitectures.map((value) => value.name).join(', ')}',
      );
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

    final autorunFile = File('$driveLetter\\autorun.inf');
    final iconFile = File('$driveLetter\\intel.ico');
    if (expectedIcon == null) {
      if (await iconFile.exists()) {
        errors.add('custom volume icon remains despite no icon selection');
      }
      if (await autorunFile.exists()) {
        errors.add('custom autorun.inf remains despite no icon selection');
      }
    } else {
      if (!await iconFile.exists()) {
        errors.add('volume icon missing');
      } else {
        final actualIconDigest = await BackgroundFileHashService.sha256File(
          iconFile,
        );
        if (actualIconDigest != expectedIcon.sha256Digest) {
          errors.add('volume icon content mismatch');
        }
      }
      if (!await autorunFile.exists()) {
        errors.add('autorun.inf missing');
      } else {
        final autorun = (await autorunFile.readAsString())
            .replaceAll('\r\n', '\n')
            .trim();
        final label = _sanitizeVolumeLabel(
          expectedVolumeLabel,
          fallback: 'WDS_BOOT',
        );
        final expectedAutorun = '[autorun]\nicon=intel.ico\nlabel=$label';
        if (autorun != expectedAutorun) {
          errors.add('autorun.inf content mismatch');
        }
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

  Future<_LinuxToGoVolumeIdentityPreparation> _prepareLinuxToGoVolumeIdentity(
    DeploymentPlan? plan,
  ) async {
    final iconPreparation = await _prepareVolumeIcon(
      plan?.customIconPath ?? '',
    );
    if (!iconPreparation.success) {
      return _LinuxToGoVolumeIdentityPreparation.failure(
        iconPreparation.error ?? 'Custom drive icon validation failed.',
      );
    }
    return _LinuxToGoVolumeIdentityPreparation.success(
      _LinuxToGoVolumeIdentity(
        label: _sanitizeLinuxToGoVolumeLabel(plan?.customVolumeLabel ?? ''),
        icon: iconPreparation.payload,
      ),
    );
  }

  static String _sanitizeLinuxToGoVolumeLabel(String value) {
    final sanitized = value
        .trim()
        .replaceAll(RegExp(r'["*/:<>?\\|\x00-\x1F]'), '')
        .trim();
    if (sanitized.isEmpty) return 'WINDEPLOY';
    return sanitized.length > 32 ? sanitized.substring(0, 32) : sanitized;
  }

  static String _linuxToGoLiveMediaArgument(String ntfsUuid) {
    final normalized = ntfsUuid.trim().toUpperCase();
    if (!RegExp(r'^[0-9A-F]{16}$').hasMatch(normalized)) {
      throw ArgumentError.value(ntfsUuid, 'ntfsUuid', 'Invalid NTFS UUID.');
    }
    return 'live-media=/dev/disk/by-uuid/$normalized';
  }

  static String? _extractLinuxToGoNtfsUuid(String output) => RegExp(
    r'0x([0-9A-Fa-f]{16})',
  ).firstMatch(output)?.group(1)?.toUpperCase();

  static String _linuxToGoAutorunText({bool hasCustomIcon = true}) =>
      hasCustomIcon ? '[autorun]\r\nicon=$_linuxToGoIconFileName\r\n' : '';

  static bool _matchesLinuxToGoCustomIcon({
    required String actualDigest,
    required String expectedDigest,
    required String autorunText,
  }) =>
      actualDigest == expectedDigest &&
      autorunText.replaceAll('\r\n', '\n').trim() ==
          _linuxToGoAutorunText().replaceAll('\r\n', '\n').trim();

  Future<bool> _setLinuxToGoExplorerIdentity(
    String liveDrive, {
    required _VolumeIconPayload? icon,
  }) async {
    final root = liveDrive.endsWith(r'\') ? liveDrive : '$liveDrive\\';
    final autorun = File(p.join(root, 'autorun.inf'));
    final iconFile = File(p.join(root, _linuxToGoIconFileName));
    try {
      for (final file in [autorun, iconFile]) {
        if (!await file.exists()) continue;
        await Process.run('attrib', [
          '-h',
          '-s',
          '-r',
          file.path,
        ]).timeout(const Duration(seconds: 5));
        await file.delete();
      }

      // A Linux ISO can carry autorun metadata. Remove it so an absent custom
      // icon always leaves Windows Explorer on its normal drive icon.
      if (icon == null) {
        _logLine(
          'Linux To Go custom icon not selected; using the Windows default drive icon.',
        );
        return true;
      }

      await iconFile.writeAsBytes(icon.bytes, flush: true);
      await autorun.writeAsString(_linuxToGoAutorunText(), flush: true);
      await Process.run('attrib', [
        '+h',
        '+s',
        autorun.path,
      ]).timeout(const Duration(seconds: 5));
      await Process.run('attrib', [
        '+h',
        iconFile.path,
      ]).timeout(const Duration(seconds: 5));

      final writtenDigest = await BackgroundFileHashService.sha256File(
        iconFile,
      );
      final autorunText = (await autorun.readAsString())
          .replaceAll('\r\n', '\n')
          .trim();
      if (!_matchesLinuxToGoCustomIcon(
        actualDigest: writtenDigest,
        expectedDigest: icon.sha256Digest,
        autorunText: autorunText,
      )) {
        throw StateError('Linux To Go drive icon verification failed.');
      }
      _logLine('Linux To Go custom drive icon applied to $liveDrive');
      return true;
    } catch (error) {
      _logLine('Linux To Go drive icon error: $error');
      return false;
    }
  }

  Future<bool> _verifyLinuxToGoExplorerIdentity(
    String liveDrive, {
    required _VolumeIconPayload? expectedIcon,
  }) async {
    try {
      final root = liveDrive.endsWith(r'\') ? liveDrive : '$liveDrive\\';
      final autorun = File(p.join(root, 'autorun.inf'));
      final iconFile = File(p.join(root, _linuxToGoIconFileName));
      if (expectedIcon == null) {
        return !await autorun.exists() && !await iconFile.exists();
      }
      if (!await autorun.exists() || !await iconFile.exists()) return false;
      final actualDigest = await BackgroundFileHashService.sha256File(iconFile);
      final autorunText = (await autorun.readAsString())
          .replaceAll('\r\n', '\n')
          .trim();
      return _matchesLinuxToGoCustomIcon(
        actualDigest: actualDigest,
        expectedDigest: expectedIcon.sha256Digest,
        autorunText: autorunText,
      );
    } catch (error) {
      _logLine('Linux To Go drive icon verification error: $error');
      return false;
    }
  }

  // --- Volume Icon ---

  Future<_VolumeIconPreparation> _prepareVolumeIcon(
    String customIconPath,
  ) async {
    try {
      final requestedPath = customIconPath.trim();
      if (requestedPath.isEmpty) {
        return const _VolumeIconPreparation.none();
      }
      final Uint8List iconData;
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

      final label = _sanitizeVolumeLabel(volumeLabel, fallback: 'WDS_BOOT');
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

      final writtenDigest = await BackgroundFileHashService.sha256File(
        iconDest,
      );
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

  Future<bool> _clearCustomVolumeIdentity(String driveLetter) async {
    try {
      final files = [
        File('$driveLetter\\intel.ico'),
        File('$driveLetter\\autorun.inf'),
      ];
      for (final file in files) {
        if (!await file.exists()) continue;
        await Process.run('attrib', [
          '-h',
          '-s',
          '-r',
          file.path,
        ]).timeout(const Duration(seconds: 5));
        await file.delete();
        if (await file.exists()) {
          throw StateError('Could not remove ${file.path}.');
        }
      }
      _logLine(
        'Custom volume identity removed; Windows default drive icon will be used.',
      );
      return true;
    } catch (error) {
      _logLine('Could not restore the Windows default drive icon: $error');
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

class _WindowsInstallMediaPreflightResult {
  final String? error;
  final String? messageKey;
  final Set<WindowsEfiBootArchitecture> efiBootArchitectures;
  final WindowsEfiBootArchitecture? efiBootManagerArchitecture;
  final String? legacyBootsectExecutable;
  final String? dismExecutable;
  final bool needsWimSplit;

  const _WindowsInstallMediaPreflightResult._({
    this.error,
    this.messageKey,
    this.efiBootArchitectures = const <WindowsEfiBootArchitecture>{},
    this.efiBootManagerArchitecture,
    this.legacyBootsectExecutable,
    this.dismExecutable,
    this.needsWimSplit = false,
  });

  const _WindowsInstallMediaPreflightResult.success({
    required Set<WindowsEfiBootArchitecture> efiBootArchitectures,
    required WindowsEfiBootArchitecture? efiBootManagerArchitecture,
    required String? legacyBootsectExecutable,
    required String? dismExecutable,
    required bool needsWimSplit,
  }) : this._(
         efiBootArchitectures: efiBootArchitectures,
         efiBootManagerArchitecture: efiBootManagerArchitecture,
         legacyBootsectExecutable: legacyBootsectExecutable,
         dismExecutable: dismExecutable,
         needsWimSplit: needsWimSplit,
       );

  const _WindowsInstallMediaPreflightResult.failure(
    String error, {
    required String messageKey,
  }) : this._(error: error, messageKey: messageKey);

  bool get success => error == null;
}

class _WindowsInstallMediaFat32Check {
  final String? error;
  final String? messageKey;
  final bool needsWimSplit;

  const _WindowsInstallMediaFat32Check._({
    this.error,
    this.messageKey,
    this.needsWimSplit = false,
  });

  const _WindowsInstallMediaFat32Check.success({required bool needsWimSplit})
    : this._(needsWimSplit: needsWimSplit);

  const _WindowsInstallMediaFat32Check.failure(
    String error, {
    required String messageKey,
  }) : this._(error: error, messageKey: messageKey);

  bool get success => error == null;
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

  const _VolumeIconPreparation.none() : this._();

  const _VolumeIconPreparation.failure(String error) : this._(error: error);

  bool get success => error == null;
}

class _LinuxToGoVolumeIdentity {
  final String label;
  final _VolumeIconPayload? icon;

  const _LinuxToGoVolumeIdentity({required this.label, this.icon});
}

class _LinuxToGoVolumeIdentityPreparation {
  final _LinuxToGoVolumeIdentity? identity;
  final String? error;

  const _LinuxToGoVolumeIdentityPreparation._({this.identity, this.error});

  const _LinuxToGoVolumeIdentityPreparation.success(
    _LinuxToGoVolumeIdentity identity,
  ) : this._(identity: identity);

  const _LinuxToGoVolumeIdentityPreparation.failure(String error)
    : this._(error: error);

  bool get success => error == null;
}

class _LinuxRawWriteResult {
  final bool success;
  final String? error;
  final String? failureMessageKey;
  final bool cancelled;
  final bool verificationFailed;
  final bool imageVerified;
  final bool diskOnline;

  const _LinuxRawWriteResult({
    required this.success,
    this.error,
    this.failureMessageKey,
    this.cancelled = false,
    this.verificationFailed = false,
    this.imageVerified = false,
    this.diskOnline = false,
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

class _Ext4Layout {
  final int blockSize;
  final int inodeSize;
  final int inodesPerGroup;
  final int groupDescriptorOffset;
  final int groupDescriptorSize;

  const _Ext4Layout({
    required this.blockSize,
    required this.inodeSize,
    required this.inodesPerGroup,
    required this.groupDescriptorOffset,
    required this.groupDescriptorSize,
  });

  static _Ext4Layout? fromSuperblock(List<int> superblock) {
    if (superblock.length < 1024) return null;
    final logBlockSize = _BootableUsbExt4Codec.littleEndian32(superblock, 0x18);
    if (logBlockSize > 2) return null;
    final blockSize = 1024 << logBlockSize;
    final inodeSize = _BootableUsbExt4Codec.littleEndian16(superblock, 0x58);
    final inodesPerGroup = _BootableUsbExt4Codec.littleEndian32(
      superblock,
      0x28,
    );
    final descriptorSize = _BootableUsbExt4Codec.littleEndian16(
      superblock,
      0xfe,
    );
    if (inodeSize < 128 ||
        inodeSize > blockSize ||
        inodesPerGroup <= 0 ||
        descriptorSize < 32 ||
        descriptorSize > blockSize) {
      return null;
    }
    return _Ext4Layout(
      blockSize: blockSize,
      inodeSize: inodeSize,
      inodesPerGroup: inodesPerGroup,
      groupDescriptorOffset: (blockSize == 1024 ? 2 : 1) * blockSize,
      groupDescriptorSize: descriptorSize,
    );
  }
}

class _Ext4Inode {
  static const int _extentFlag = 0x00080000;
  final int mode;
  final int size;
  final int flags;
  final List<int> blockData;

  const _Ext4Inode({
    required this.mode,
    required this.size,
    required this.flags,
    required this.blockData,
  });

  bool get isDirectory => (mode & 0xf000) == 0x4000;

  static _Ext4Inode? fromBytes(List<int> bytes) {
    if (bytes.length < 100) return null;
    return _Ext4Inode(
      mode: _BootableUsbExt4Codec.littleEndian16(bytes, 0),
      size: _BootableUsbExt4Codec.littleEndian32(bytes, 4),
      flags: _BootableUsbExt4Codec.littleEndian32(bytes, 0x20),
      blockData: bytes.sublist(0x28, 0x28 + 60),
    );
  }

  List<int>? dataBlocks(int blockSize) {
    if (size == 0) return const [];
    if ((flags & _extentFlag) == 0) {
      final blocks = <int>[];
      for (var index = 0; index < 12; index++) {
        final block = _BootableUsbExt4Codec.littleEndian32(
          blockData,
          index * 4,
        );
        if (block == 0) break;
        blocks.add(block);
      }
      return _hasEnoughBlocks(blocks, blockSize) ? blocks : null;
    }

    if (_BootableUsbExt4Codec.littleEndian16(blockData, 0) != 0xf30a ||
        _BootableUsbExt4Codec.littleEndian16(blockData, 6) != 0) {
      return null;
    }
    final entries = _BootableUsbExt4Codec.littleEndian16(blockData, 2);
    final maximumEntries = _BootableUsbExt4Codec.littleEndian16(blockData, 4);
    if (entries <= 0 || entries > maximumEntries || 12 + entries * 12 > 60) {
      return null;
    }

    final blocks = <int>[];
    for (var entry = 0; entry < entries; entry++) {
      final offset = 12 + entry * 12;
      final rawLength = _BootableUsbExt4Codec.littleEndian16(
        blockData,
        offset + 4,
      );
      final length = rawLength & 0x7fff;
      final startHigh = _BootableUsbExt4Codec.littleEndian16(
        blockData,
        offset + 6,
      );
      final startLow = _BootableUsbExt4Codec.littleEndian32(
        blockData,
        offset + 8,
      );
      final start = (startHigh << 32) | startLow;
      if (length <= 0 || rawLength != length || start <= 0) return null;
      for (var block = 0; block < length; block++) {
        blocks.add(start + block);
      }
    }
    return _hasEnoughBlocks(blocks, blockSize) ? blocks : null;
  }

  bool _hasEnoughBlocks(List<int> blocks, int blockSize) =>
      blocks.length * blockSize >= size;
}

class _BootableUsbExt4Codec {
  const _BootableUsbExt4Codec._();

  static int littleEndian16(List<int> bytes, int offset) =>
      bytes[offset] | (bytes[offset + 1] << 8);

  static int littleEndian32(List<int> bytes, int offset) =>
      bytes[offset] |
      (bytes[offset + 1] << 8) |
      (bytes[offset + 2] << 16) |
      (bytes[offset + 3] << 24);
}
