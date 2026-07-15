import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../features/deployment/models/deployment_plan.dart';
import '../../features/deployment/services/windows_deployment_service.dart';
import '../../features/logs/services/log_center_service.dart';
import '../constants/app_constants.dart';
import 'background_file_hash_service.dart';
import 'disk_safety_service.dart';
import 'file_logger_service.dart';
import 'wim_info_service.dart';
import 'windows_iso_preflight.dart';
import 'windows_system_environment.dart';

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

enum WtgBootLayout { uefiGpt, uefiMbr, legacyBios }

class WtgBootContract {
  const WtgBootContract._();

  static String expectedDevice({
    required String windowsDrive,
    required String storageDrive,
    String virtualDiskFileName = '',
  }) {
    final windows = _driveSpec(windowsDrive);
    if (virtualDiskFileName.isEmpty) return 'partition=$windows';
    return 'vhd=[${_driveSpec(storageDrive)}]\\$virtualDiskFileName';
  }

  static bool listingMatches(String listing, String expectedDevice) {
    final expected = expectedDevice.toLowerCase().replaceAll('/', r'\');
    final deviceLines = const LineSplitter()
        .convert(listing)
        .map((line) => line.trim().toLowerCase().replaceAll('/', r'\'))
        .where((line) => line.contains('partition=') || line.contains('vhd=['))
        .toList(growable: false);
    final exactLines = deviceLines
        .where((line) => line.endsWith(expected))
        .toList(growable: false);
    if (deviceLines.length != 2 || exactLines.length != 2) return false;
    final labels = exactLines
        .map((line) => line.substring(0, line.length - expected.length).trim())
        .where((label) => label.isNotEmpty)
        .toSet();
    return labels.length == 2 &&
        labels.contains('device') &&
        labels.contains('osdevice');
  }

  static String _driveSpec(String value) {
    final match = RegExp(r'[A-Za-z]').firstMatch(value.trim());
    return '${match?.group(0)?.toUpperCase() ?? ''}:';
  }
}

/// Files written to the target volume only when the user explicitly supplies
/// an ICO file. A blank icon path intentionally leaves File Explorer's
/// standard drive icon in place.
@immutable
class WtgVolumeIdentity {
  static const iconFileName = '.wds-drive.ico';

  final String volumeLabel;
  final String customIconPath;

  const WtgVolumeIdentity({
    required this.volumeLabel,
    required this.customIconPath,
  });

  factory WtgVolumeIdentity.fromPlan(DeploymentPlan plan) => WtgVolumeIdentity(
    volumeLabel: plan.customVolumeLabel.trim(),
    customIconPath: plan.customIconPath.trim(),
  );

  bool get usesCustomIcon => customIconPath.trim().isNotEmpty;

  /// Null means no autorun file or icon file is written to the volume.
  String? get autorunContents {
    if (!usesCustomIcon) return null;
    final label = volumeLabel.trim();
    final labelLine = label.isEmpty ? '' : 'label=$label\r\n';
    return '[autorun]\r\nicon=$iconFileName\r\n$labelLine';
  }
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
    this.progress = 0,
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

  String get formattedWritten => _formatBytes(writtenBytes, zero: '0 B');
  String get formattedTotal => _formatBytes(totalBytes);
  String get formattedRemaining => _formatBytes(remainingBytes, zero: '0 B');

  String get formattedSpeed {
    if (currentSpeedBytes <= 0) return '--';
    return '${_formatBytes(currentSpeedBytes)}/s';
  }

  String get formattedElapsed {
    final elapsed = elapsedTime ?? Duration.zero;
    final hours = elapsed.inHours.toString().padLeft(2, '0');
    final minutes = elapsed.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = elapsed.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$hours:$minutes:$seconds';
  }

  static String _formatBytes(int bytes, {String zero = '--'}) {
    if (bytes <= 0) return zero;
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }
}

typedef WtgProgressCallback = void Function(WtgProgress progress);

final wtgServiceProvider = Provider<WtgService>(WtgService.new);

class _WtgFailure implements Exception {
  final String messageKey;
  final String detail;

  const _WtgFailure(this.messageKey, this.detail);

  @override
  String toString() => detail;
}

class _WtgImageSource {
  final String imagePath;
  final WimImageInfo image;
  final DeploymentPlan plan;
  final String architecture;
  final String? netFx3Source;

  const _WtgImageSource({
    required this.imagePath,
    required this.image,
    required this.plan,
    required this.architecture,
    required this.netFx3Source,
  });
}

class _WtgDriveLetters {
  final String boot;
  final String storage;
  final String image;

  const _WtgDriveLetters({
    required this.boot,
    required this.storage,
    required this.image,
  });
}

class _WtgPartitionLayout {
  final WtgBootLayout bootLayout;
  final String bootDrive;
  final String storageDrive;
  final String bootLabel;
  final String storageLabel;

  const _WtgPartitionLayout({
    required this.bootLayout,
    required this.bootDrive,
    required this.storageDrive,
    required this.bootLabel,
    required this.storageLabel,
  });
}

class _WtgVirtualDisk {
  final String filePath;
  final String fileName;
  final String imageDrive;
  final int diskNumber;

  const _WtgVirtualDisk({
    required this.filePath,
    required this.fileName,
    required this.imageDrive,
    required this.diskNumber,
  });
}

class _DriverManifestEntry {
  final String path;
  final String resolvedPath;
  final int size;
  final DateTime modified;
  final String digest;
  final bool isInf;

  const _DriverManifestEntry({
    required this.path,
    required this.resolvedPath,
    required this.size,
    required this.modified,
    required this.digest,
    required this.isInf,
  });
}

class _DriverManifest {
  final String rootPath;
  final String resolvedRootPath;
  final int sourceDiskNumber;
  final List<_DriverManifestEntry> entries;

  const _DriverManifest({
    required this.rootPath,
    required this.resolvedRootPath,
    required this.sourceDiskNumber,
    required this.entries,
  });

  static const empty = _DriverManifest(
    rootPath: '',
    resolvedRootPath: '',
    sourceDiskNumber: -1,
    entries: [],
  );

  List<String> get infPaths => entries
      .where((entry) => entry.isInf)
      .map((entry) => entry.path)
      .toList(growable: false);
}

class WtgService {
  @visibleForTesting
  static String diskpartScriptForTesting({
    required int diskNumber,
    required WtgBootLayout bootLayout,
    required String currentPartitionStyle,
    required String bootLetter,
    required String storageLetter,
    String bootLabel = 'WDS_EFI',
    String storageLabel = 'WDS_TOGO',
  }) => _buildWtgDiskpartScript(
    diskNumber: diskNumber,
    bootLayout: bootLayout,
    currentPartitionStyle: currentPartitionStyle,
    bootLetter: bootLetter,
    storageLetter: storageLetter,
    bootLabel: bootLabel,
    storageLabel: storageLabel,
  );

  final Ref ref;
  final List<String> _log = [];
  final List<String> _debugLogs = [];
  Future<void> _detailLogWriteQueue = Future.value();
  bool _cancelled = false;
  Process? _currentProcess;
  String? _currentIsoPath;

  WtgService(this.ref) {
    ref.onDispose(() {
      final isoPath = _currentIsoPath;
      unawaited(() async {
        await _stopCurrentProcess();
        if (isoPath != null) await _unmountIso(isoPath);
      }());
    });
  }

  List<String> get debugLogs => List.unmodifiable(_debugLogs);
  String get logText => _log.join('\n');
  bool get isCancelled => _cancelled;

  void cancel() {
    _cancelled = true;
    _logLine('Cancellation requested.');
    _killCurrentProcess();
  }

  Future<List<Map<String, dynamic>>> getWimImages(String isoPath) async {
    _debugLogs.clear();
    _cancelled = false;
    String? mountPoint;
    try {
      mountPoint = await _mountIso(isoPath);
      if (mountPoint == null) return const [];
      final layout = await WindowsIsoLayoutInspector.inspectMountedRoot(
        mountPoint,
      );
      if (!layout.isValid ||
          layout.imagePath == null ||
          layout.imageFormat == WindowsInstallImageFormat.swm) {
        _logLine('Windows To Go image selection rejected: ${layout.error}');
        return const [];
      }
      final images = await WimInfoService.readImages(layout.imagePath!);
      return images.map((image) => image.toMap()).toList(growable: false);
    } catch (error) {
      _debugLogs.add(error.toString());
      _logLine('WIM metadata query failed: $error');
      return const [];
    } finally {
      if (mountPoint != null) await _unmountIso(isoPath);
    }
  }

  Future<bool> createWtg({
    required String isoPath,
    required int imageIndex,
    required DiskInfo disk,
    required String driveLetter,
    DeploymentPlan? deploymentPlan,
    WtgProgressCallback? onProgress,
  }) async {
    final plan =
        deploymentPlan ??
        DeploymentPlan(
          platform: DeploymentPlatform.windows,
          purpose: DeploymentPurpose.toGo,
          imagePath: isoPath,
          imageIndex: imageIndex,
          bootMode: DeploymentBootMode.uefiGpt,
          deploymentMode: DeploymentMode.direct,
          preferredSystemLetter: _letterOnly(driveLetter),
          blockLocalDisks: true,
          disableWinRe: true,
        );
    final diskNumber = disk.diskNumber;
    final logger = ref.read(fileLoggerServiceProvider);
    final logCenter = LogCenterService();
    String? mountPoint;
    _WtgVirtualDisk? virtualDisk;
    var driverManifest = _DriverManifest.empty;
    String? driverStagingPath;
    Uint8List? preparedIcon;

    _log.clear();
    _debugLogs.clear();
    _cancelled = false;
    _currentIsoPath = isoPath;
    _logLine('=== Windows To Go deployment start ===');
    _logLine('Disk=$diskNumber Plan=${jsonEncode(plan.toJson())}');

    try {
      _notify(
        onProgress,
        const WtgProgress(
          step: WtgStep.preparing,
          message: 'wtg_svc_preparing',
        ),
      );
      _validateTaskPlan(plan, isoPath, imageIndex);
      await _validateWindowsIsoLayoutBeforeErase(isoPath);
      await _requireSafeDisk(disk);
      // Reject an ISO on the target before mounting it or preparing any target work.
      await _validateIsoSourceBeforeErase(isoPath, diskNumber);
      final sourceDriverManifest = await _prepareDriverManifest(
        plan.driverDirectory,
        diskNumber,
      );
      driverManifest = await _stageDriverManifest(
        sourceDriverManifest,
        diskNumber,
      );
      if (driverManifest.entries.isNotEmpty) {
        driverStagingPath = driverManifest.rootPath;
      }
      preparedIcon = await _prepareCustomIcon(plan.customIconPath);

      mountPoint = await _mountIso(isoPath);
      if (mountPoint == null) {
        throw const _WtgFailure('wtg_svc_mount_failed', 'ISO mount failed.');
      }
      final source = await _inspectImage(mountPoint, plan, imageIndex);
      _throwIfCancelled();
      _validateCapacity(disk, source);
      await _validateIsoSourceBeforeErase(isoPath, diskNumber);

      final letters = await _reserveDriveLetters(plan);
      _notify(
        onProgress,
        const WtgProgress(
          step: WtgStep.partitioningDisk,
          message: 'wtg_svc_partitioning',
          progress: 0.08,
        ),
      );
      final layout = await _partitionDisk(
        disk: disk,
        plan: source.plan,
        letters: letters,
      );
      await _requireSafeDisk(disk);
      _throwIfCancelled();

      String windowsDrive = layout.storageDrive;
      if (source.plan.usesVirtualDisk) {
        virtualDisk = await _createVirtualDisk(
          layout: layout,
          plan: source.plan,
          imageLetter: letters.image,
          physicalDiskNumber: diskNumber,
        );
        windowsDrive = virtualDisk.imageDrive;
      }

      String applySource = source.imagePath;
      if (source.plan.wimBoot) {
        applySource = await _stageWimBootSource(
          source.imagePath,
          layout.storageDrive,
        );
      }
      _throwIfCancelled();

      final applied = await _applyImage(
        sourcePath: applySource,
        imageIndex: imageIndex,
        targetDrive: windowsDrive,
        compact: source.plan.compactOs,
        wimBoot: source.plan.wimBoot,
        onProgress: onProgress,
      );
      if (!applied) {
        throw const _WtgFailure(
          'wtg_svc_apply_failed',
          'DISM image application failed.',
        );
      }

      await _verifyDriverManifest(driverManifest);
      _throwIfCancelled();
      final configuredPlan = driverManifest.entries.isEmpty
          ? source.plan
          : source.plan.copyWith(driverDirectory: driverManifest.rootPath);
      final deploymentService = WindowsDeploymentService(
        _logLine,
        processRunner: _runTracked,
      );
      final configured = await deploymentService.configureOfflineImage(
        windowsDrive: windowsDrive,
        plan: configuredPlan,
        architecture: source.architecture,
        driverInfPaths: driverManifest.infPaths,
        netFx3Source: source.netFx3Source,
        compactApplied: source.plan.compactOs,
        wimBootApplied: source.plan.wimBoot,
      );
      if (!configured) {
        throw const _WtgFailure(
          'wtg_svc_apply_failed',
          'Offline Windows configuration failed verification.',
        );
      }
      if (!await deploymentService.disableAndVerifyWinRe(
        windowsDrive: windowsDrive,
        requested: source.plan.disableWinRe,
      )) {
        throw const _WtgFailure(
          'wtg_svc_apply_failed',
          'WinRE configuration failed verification.',
        );
      }
      await _writeVolumeIdentity(
        layout.storageDrive,
        WtgVolumeIdentity.fromPlan(source.plan),
        preparedIcon,
      );
      _throwIfCancelled();

      _notify(
        onProgress,
        const WtgProgress(
          step: WtgStep.writingBootFiles,
          message: 'wtg_svc_writing_boot',
          progress: 0.78,
        ),
      );
      await _revalidateTargetDisk(disk, layout);
      if (!await _writeBootFiles(
        disk: disk,
        windowsDrive: windowsDrive,
        layout: layout,
        virtualDisk: virtualDisk,
        architecture: source.image.architecture,
        legacyBootsectPath: p.join(mountPoint, 'boot', 'bootsect.exe'),
      )) {
        throw const _WtgFailure(
          'wtg_svc_boot_failed',
          'Boot-file creation failed verification.',
        );
      }
      _throwIfCancelled();

      _notify(
        onProgress,
        const WtgProgress(
          step: WtgStep.verifying,
          message: 'wtg_svc_verifying',
          progress: 0.9,
        ),
      );
      if (!await _verifyDeployment(
        disk: disk,
        layout: layout,
        plan: source.plan,
        windowsDrive: windowsDrive,
        virtualDisk: virtualDisk,
        architecture: source.image.architecture,
        preparedIcon: preparedIcon,
      )) {
        throw const _WtgFailure(
          'wtg_svc_verify_failed',
          'Final deployment postconditions failed.',
        );
      }
      _throwIfCancelled();

      _notify(
        onProgress,
        const WtgProgress(
          step: WtgStep.complete,
          message: 'wtg_svc_complete',
          progress: 1,
        ),
      );
      _throwIfCancelled();
      await logger.log(
        action: 'Create Windows To Go',
        target: 'Disk $diskNumber',
        result:
            'Success - ${source.plan.deploymentMode.name}/${source.plan.bootMode.name}',
        level: LogLevel.success,
      );
      _throwIfCancelled();
      await logCenter.logToGo(
        '[Deployment] Product=WindowsToGo Disk=$diskNumber Status=Success',
      );
      _throwIfCancelled();
      return true;
    } on _WtgFailure catch (error) {
      _logLine('${error.messageKey}: ${error.detail}');
      _notify(
        onProgress,
        WtgProgress(
          step: WtgStep.failed,
          message: '${error.messageKey}\n${error.detail}',
          error: error.detail,
        ),
      );
      await logger.log(
        action: 'Create Windows To Go',
        target: 'Disk $diskNumber',
        result: 'Failed: ${error.detail}',
        level: LogLevel.error,
      );
      await logCenter.logError(
        '[Deployment] Product=WindowsToGo Disk=$diskNumber Status=Failed '
        'Reason=${error.detail}',
      );
      return false;
    } on TimeoutException catch (error) {
      _logLine('Deployment timeout: $error');
      _notify(
        onProgress,
        const WtgProgress(step: WtgStep.failed, message: 'wtg_svc_timeout'),
      );
      return false;
    } catch (error, stackTrace) {
      _logLine('Unexpected deployment error: $error\n$stackTrace');
      _notify(
        onProgress,
        WtgProgress(
          step: WtgStep.failed,
          message: 'creator_error\n$error',
          error: error.toString(),
        ),
      );
      return false;
    } finally {
      await _stopCurrentProcess();
      if (virtualDisk != null) await _detachVirtualDisk(virtualDisk.filePath);
      if (mountPoint != null) await _unmountIso(isoPath);
      if (driverStagingPath != null) {
        await _deleteDriverStaging(driverStagingPath);
      }
      _currentIsoPath = null;
      final logPath = await saveLogToFile();
      _logLine('Detailed log: $logPath');
    }
  }

  void _validateTaskPlan(DeploymentPlan plan, String isoPath, int imageIndex) {
    if (!plan.isWindows || !plan.isToGo) {
      throw const _WtgFailure(
        'deploy_compat_task_mismatch',
        'The deployment plan is not a Windows To Go plan.',
      );
    }
    if (_normalizedPath(plan.imagePath) != _normalizedPath(isoPath)) {
      throw const _WtgFailure(
        'deploy_compat_image_mismatch',
        'The ISO path changed across elevation.',
      );
    }
    if (plan.imageIndex != imageIndex) {
      throw const _WtgFailure(
        'deploy_compat_index_mismatch',
        'The selected image index changed across elevation.',
      );
    }
    final compatibility = DeploymentCompatibility.evaluate(plan);
    if (!compatibility.canDeploy) {
      throw _WtgFailure(
        compatibility.errors.first.messageKey,
        compatibility.errors.map((issue) => issue.code).join(', '),
      );
    }
  }

  Future<_WtgImageSource> _inspectImage(
    String mountPoint,
    DeploymentPlan requestedPlan,
    int imageIndex,
  ) async {
    final layout = await WindowsIsoLayoutInspector.inspectMountedRoot(
      mountPoint,
    );
    if (!layout.isValid || layout.imagePath == null) {
      throw _WtgFailure(
        'wtg_invalid_windows_iso',
        layout.error ??
            'The ISO does not contain a valid Windows setup layout.',
      );
    }
    if (layout.imageFormat == WindowsInstallImageFormat.swm) {
      throw const _WtgFailure(
        'wtg_svc_no_wim',
        'Windows To Go does not yet support split install.swm images.',
      );
    }
    final imagePath = layout.imagePath!;
    final images = await WimInfoService.readImages(imagePath);
    final matches = images.where((image) => image.index == imageIndex);
    if (matches.length != 1) {
      throw const _WtgFailure(
        'wtg_svc_no_wim',
        'The selected Windows edition is not present in the image.',
      );
    }
    final image = matches.single;
    final generation = DeploymentPlan.detectWindowsGeneration(
      build: image.build,
      version: '${image.name} ${image.version}',
    );
    final effectivePlan = requestedPlan.copyWith(
      imageBuild: image.build,
      imageName: image.name,
      imageEdition: image.edition,
      imageArchitecture: image.architecture,
      windowsGeneration: generation,
    );
    final compatibility = DeploymentCompatibility.evaluate(effectivePlan);
    if (!compatibility.canDeploy) {
      throw _WtgFailure(
        compatibility.errors.first.messageKey,
        'Image metadata changed compatibility: '
        '${compatibility.errors.map((issue) => issue.code).join(', ')}',
      );
    }
    if (effectivePlan.wimBoot &&
        p.extension(imagePath).toLowerCase() != '.wim') {
      throw const _WtgFailure(
        'deploy_compat_wimboot_scope',
        'WIMBoot requires install.wim; install.esd is not supported.',
      );
    }
    if (effectivePlan.usesVirtualDisk &&
        effectivePlan.virtualDiskSizeGb * 1024 * 1024 * 1024 <
            image.sizeBytes + 4 * 1024 * 1024 * 1024) {
      throw const _WtgFailure(
        'deploy_compat_vhd_too_small',
        'The virtual disk is too small for the selected Windows image.',
      );
    }
    final sourceArchitecture = switch (image.architecture.toLowerCase()) {
      'x64' || 'amd64' => 'amd64',
      'arm64' => 'arm64',
      _ => 'x86',
    };
    final sxs = p.join(mountPoint, 'sources', 'sxs');
    final netFx3Source =
        effectivePlan.enableNetFx3 && await Directory(sxs).exists()
        ? sxs
        : null;
    if (effectivePlan.enableNetFx3 && netFx3Source == null) {
      throw const _WtgFailure(
        'wtg_svc_apply_failed',
        'The selected ISO does not contain a sources\\sxs payload for .NET Framework 3.5.',
      );
    }
    _logLine(
      'Selected image: index=${image.index} name=${image.name} '
      'build=${image.build} arch=${image.architecture}',
    );
    return _WtgImageSource(
      imagePath: imagePath,
      image: image,
      plan: effectivePlan,
      architecture: sourceArchitecture,
      netFx3Source: netFx3Source,
    );
  }

  void _validateCapacity(DiskInfo disk, _WtgImageSource source) {
    final reserve = source.plan.usesVirtualDisk
        ? source.plan.virtualDiskSizeGb * 1024 * 1024 * 1024
        : source.image.sizeBytes + 6 * 1024 * 1024 * 1024;
    if (disk.sizeBytes <= reserve + 512 * 1024 * 1024) {
      throw const _WtgFailure(
        'deploy_compat_vhd_too_small',
        'The target disk does not have enough capacity for this deployment.',
      );
    }
  }

  Future<void> _validateIsoSourceBeforeErase(
    String isoPath,
    int targetDiskNumber,
  ) async {
    final source = File(p.normalize(p.absolute(isoPath)));
    if (await FileSystemEntity.type(source.path, followLinks: false) !=
        FileSystemEntityType.file) {
      throw const _WtgFailure(
        'wtg_svc_apply_failed',
        'The Windows ISO source must be a regular file, not a link or directory.',
      );
    }
    final resolvedPath = await source.resolveSymbolicLinks();
    final sourceDiskNumber = await _pathDiskNumber(resolvedPath);
    if (sourceDiskNumber == null) {
      throw const _WtgFailure(
        'wtg_svc_apply_failed',
        'The physical disk containing the Windows ISO could not be verified.',
      );
    }
    if (sourceDiskNumber == targetDiskNumber) {
      throw const _WtgFailure(
        'wtg_svc_apply_failed',
        'The Windows ISO is stored on the target disk and would be erased.',
      );
    }
    _logLine(
      'ISO source preflight passed: source disk $sourceDiskNumber differs '
      'from target disk $targetDiskNumber.',
    );
  }

  Future<void> _validateWindowsIsoLayoutBeforeErase(String isoPath) async {
    final layout = await ref.read(windowsIsoPreflightProvider).inspect(isoPath);
    if (!layout.isValid) {
      throw _WtgFailure(
        'wtg_invalid_windows_iso',
        layout.error ??
            'The ISO does not contain a valid Windows setup layout.',
      );
    }
    _logLine(
      'Windows To Go ISO layout preflight passed: '
      '${layout.imageFormat?.name ?? 'unknown'} image.',
    );
  }

  Future<_DriverManifest> _prepareDriverManifest(
    String directoryPath,
    int targetDiskNumber,
  ) async {
    if (directoryPath.trim().isEmpty) return _DriverManifest.empty;
    final directory = Directory(p.normalize(p.absolute(directoryPath)));
    if (!await directory.exists()) {
      throw const _WtgFailure(
        'wtg_svc_apply_failed',
        'The selected Windows driver directory does not exist.',
      );
    }
    if (await FileSystemEntity.type(directory.path, followLinks: false) ==
        FileSystemEntityType.link) {
      throw const _WtgFailure(
        'wtg_svc_apply_failed',
        'The Windows driver directory cannot be a symbolic link or junction.',
      );
    }
    final sourceDiskNumber = await _pathDiskNumber(directory.path);
    if (sourceDiskNumber == null || sourceDiskNumber == targetDiskNumber) {
      throw const _WtgFailure(
        'wtg_svc_apply_failed',
        'The driver source disk could not be verified or is the target disk.',
      );
    }
    final root = await directory.resolveSymbolicLinks();
    final manifest = <_DriverManifestEntry>[];
    await for (final entity in directory.list(
      recursive: true,
      followLinks: false,
    )) {
      final type = await FileSystemEntity.type(entity.path, followLinks: false);
      if (type == FileSystemEntityType.link) {
        throw const _WtgFailure(
          'wtg_svc_apply_failed',
          'Driver staging cannot contain symbolic links or junctions.',
        );
      }
      if (entity is! File) continue;
      final resolved = await entity.resolveSymbolicLinks();
      if (!p.isWithin(root, resolved)) {
        throw const _WtgFailure(
          'wtg_svc_apply_failed',
          'A driver file resolves outside the selected directory.',
        );
      }
      final file = File(entity.path);
      manifest.add(
        _DriverManifestEntry(
          path: file.path,
          resolvedPath: resolved,
          size: await file.length(),
          modified: await file.lastModified(),
          digest: await _sha256File(file),
          isInf: p.extension(file.path).toLowerCase() == '.inf',
        ),
      );
    }
    final infCount = manifest.where((entry) => entry.isInf).length;
    if (infCount == 0) {
      throw const _WtgFailure(
        'wtg_svc_apply_failed',
        'The selected Windows driver directory contains no INF files.',
      );
    }
    _logLine(
      'Driver preflight hashed ${manifest.length} file(s), including '
      '$infCount INF file(s).',
    );
    return _DriverManifest(
      rootPath: directory.path,
      resolvedRootPath: root,
      sourceDiskNumber: sourceDiskNumber,
      entries: List.unmodifiable(manifest),
    );
  }

  Future<void> _verifyDriverManifest(_DriverManifest manifest) async {
    if (manifest.entries.isEmpty) return;
    final directory = Directory(manifest.rootPath);
    if (!await directory.exists() ||
        await FileSystemEntity.type(directory.path, followLinks: false) ==
            FileSystemEntityType.link ||
        await directory.resolveSymbolicLinks() != manifest.resolvedRootPath ||
        await _pathDiskNumber(directory.path) != manifest.sourceDiskNumber) {
      throw const _WtgFailure(
        'wtg_svc_apply_failed',
        'The Windows driver source location changed after preflight.',
      );
    }

    final currentPaths = <String>{};
    await for (final entity in directory.list(
      recursive: true,
      followLinks: false,
    )) {
      final type = await FileSystemEntity.type(entity.path, followLinks: false);
      if (type == FileSystemEntityType.link) {
        throw const _WtgFailure(
          'wtg_svc_apply_failed',
          'The Windows driver source gained a symbolic link after preflight.',
        );
      }
      if (type == FileSystemEntityType.file) {
        currentPaths.add(_normalizedPath(entity.path));
      }
    }
    final expectedPaths = manifest.entries
        .map((entry) => _normalizedPath(entry.path))
        .toSet();
    if (currentPaths.length != expectedPaths.length ||
        !currentPaths.containsAll(expectedPaths)) {
      throw const _WtgFailure(
        'wtg_svc_apply_failed',
        'The Windows driver source file set changed after preflight.',
      );
    }

    for (final entry in manifest.entries) {
      final file = File(entry.path);
      if (await FileSystemEntity.type(file.path, followLinks: false) !=
              FileSystemEntityType.file ||
          await file.resolveSymbolicLinks() != entry.resolvedPath ||
          await file.length() != entry.size ||
          await file.lastModified() != entry.modified ||
          await _sha256File(file) != entry.digest) {
        throw const _WtgFailure(
          'wtg_svc_apply_failed',
          'The Windows driver source changed after preflight.',
        );
      }
    }
    _logLine('Driver source content digest verification passed.');
  }

  Future<String> _sha256File(File file) =>
      BackgroundFileHashService.sha256File(file);

  Future<_DriverManifest> _stageDriverManifest(
    _DriverManifest source,
    int targetDiskNumber,
  ) async {
    if (source.entries.isEmpty) return _DriverManifest.empty;
    await _verifyDriverManifest(source);

    final programData = Platform.environment['ProgramData'];
    if (programData == null || programData.trim().isEmpty) {
      throw const _WtgFailure(
        'wtg_svc_apply_failed',
        'A secure local driver staging location is unavailable.',
      );
    }
    final secureRoot = Directory(
      p.join(programData, 'WinDeployStudioSecureStaging'),
    );
    await secureRoot.create(recursive: true);
    if (await FileSystemEntity.type(secureRoot.path, followLinks: false) ==
        FileSystemEntityType.link) {
      throw const _WtgFailure(
        'wtg_svc_apply_failed',
        'The secure driver staging root cannot be a link or junction.',
      );
    }
    await _lockDownDirectory(secureRoot.path);
    await _cleanupStaleDriverStaging(secureRoot);

    final token = '${pid}_${DateTime.now().microsecondsSinceEpoch}';
    final staging = Directory(p.join(secureRoot.path, 'wds_drivers_$token'));
    await staging.create();
    await _lockDownDirectory(staging.path);

    try {
      for (final entry in source.entries) {
        _throwIfCancelled();
        final relative = p.relative(entry.path, from: source.rootPath);
        if (relative == '..' || relative.startsWith('..${p.separator}')) {
          throw const _WtgFailure(
            'wtg_svc_apply_failed',
            'A driver staging path escaped the selected directory.',
          );
        }
        final target = File(p.join(staging.path, relative));
        await target.parent.create(recursive: true);
        await File(entry.path).copy(target.path);
        if (await _sha256File(target) != entry.digest) {
          throw const _WtgFailure(
            'wtg_svc_apply_failed',
            'A driver file changed while it was copied to secure staging.',
          );
        }
      }

      final staged = await _prepareDriverManifest(
        staging.path,
        targetDiskNumber,
      );
      final sourceDigests = <String, String>{
        for (final entry in source.entries)
          _normalizedRelativePath(entry.path, source.rootPath): entry.digest,
      };
      final stagedDigests = <String, String>{
        for (final entry in staged.entries)
          _normalizedRelativePath(entry.path, staged.rootPath): entry.digest,
      };
      if (sourceDigests.length != stagedDigests.length ||
          sourceDigests.entries.any(
            (entry) => stagedDigests[entry.key] != entry.value,
          )) {
        throw const _WtgFailure(
          'wtg_svc_apply_failed',
          'Secure driver staging failed its content verification.',
        );
      }
      _logLine(
        'Driver files copied to ACL-restricted staging: ${staging.path}',
      );
      return staged;
    } catch (_) {
      await _deleteDriverStaging(staging.path);
      rethrow;
    }
  }

  Future<void> _lockDownDirectory(
    String path, {
    bool allowWhenCancelled = false,
  }) async {
    final result = await _runTracked(
      'powershell',
      const [
        '-NoProfile',
        '-NonInteractive',
        '-ExecutionPolicy',
        'Bypass',
        '-Command',
        r'''$ErrorActionPreference = 'Stop'
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
if ($actual.Count -ne 2 -or @($actual | Where-Object { $_ -notin $allowed }).Count -ne 0) { throw 'Secure staging ACL verification failed.' }''',
      ],
      timeout: const Duration(seconds: 30),
      allowWhenCancelled: allowWhenCancelled,
      environment: {...Platform.environment, 'WDS_SECURE_PATH': path},
    );
    if (result.exitCode != 0) {
      throw _WtgFailure(
        'wtg_svc_apply_failed',
        'Could not secure the driver staging directory: '
            '${_trimOutput(result.stderr)}',
      );
    }
  }

  Future<void> _deleteDriverStaging(String path) async {
    final programData = Platform.environment['ProgramData'];
    if (programData == null || programData.trim().isEmpty) return;
    final secureRoot = p.join(programData, 'WinDeployStudioSecureStaging');
    final normalized = p.normalize(p.absolute(path));
    if (!p.isWithin(secureRoot, normalized) ||
        !p.basename(normalized).startsWith('wds_drivers_')) {
      _logLine('Refused to delete an unexpected driver staging path: $path');
      return;
    }
    try {
      final directory = Directory(normalized);
      if (await directory.exists()) await directory.delete(recursive: true);
    } catch (error) {
      _logLine('Driver staging cleanup warning: $error');
    }
  }

  Future<void> _cleanupStaleDriverStaging(Directory secureRoot) async {
    final cutoff = DateTime.now().subtract(const Duration(days: 1));
    try {
      await for (final entity in secureRoot.list(followLinks: false)) {
        if (entity is! Directory ||
            !p.basename(entity.path).startsWith('wds_drivers_')) {
          continue;
        }
        final modified = (await FileStat.stat(entity.path)).modified;
        if (modified.isBefore(cutoff)) {
          await _deleteDriverStaging(entity.path);
        }
      }
    } catch (error) {
      _logLine('Stale driver staging cleanup warning: $error');
    }
  }

  String _normalizedRelativePath(String path, String root) =>
      p.relative(path, from: root).replaceAll('/', r'\').toUpperCase();

  Future<Uint8List?> _prepareCustomIcon(String iconPath) async {
    if (iconPath.trim().isEmpty) return null;
    final file = File(p.normalize(p.absolute(iconPath)));
    if (p.extension(file.path).toLowerCase() != '.ico' ||
        !await file.exists()) {
      throw const _WtgFailure(
        'deploy_compat_invalid_icon',
        'The selected custom ICO file is unavailable.',
      );
    }
    final length = await file.length();
    if (length < 6 || length > 10 * 1024 * 1024) {
      throw const _WtgFailure(
        'deploy_compat_invalid_icon',
        'The selected ICO file has an invalid size.',
      );
    }
    final bytes = await file.readAsBytes();
    if (bytes[0] != 0 || bytes[1] != 0 || bytes[2] != 1 || bytes[3] != 0) {
      throw const _WtgFailure(
        'deploy_compat_invalid_icon',
        'The selected file does not have a valid ICO header.',
      );
    }
    _logLine('Custom drive icon staged in memory before disk erasure.');
    return bytes;
  }

  Future<int?> _pathDiskNumber(String path) async {
    try {
      final result = await _runTracked(
        'powershell',
        const [
          '-NoProfile',
          '-NonInteractive',
          '-ExecutionPolicy',
          'Bypass',
          '-Command',
          r'''$item = Get-Item -LiteralPath $env:WDS_SOURCE_PATH -Force -ErrorAction Stop
$volume = Get-Volume -FilePath $item.FullName -ErrorAction Stop
$partitions = @(Get-Partition -Volume $volume -ErrorAction Stop)
if ($partitions.Count -ne 1) {
  throw "Source path did not resolve to exactly one physical partition."
}
[int]$partitions[0].DiskNumber''',
        ],
        environment: {
          ...Platform.environment,
          'WDS_SOURCE_PATH': p.normalize(p.absolute(path)),
        },
        timeout: const Duration(seconds: 10),
      );
      return result.exitCode == 0
          ? int.tryParse(result.stdout.toString().trim())
          : null;
    } on _WtgFailure {
      rethrow;
    } catch (_) {
      return null;
    }
  }

  Future<_WtgDriveLetters> _reserveDriveLetters(DeploymentPlan plan) async {
    final used = await _usedDriveLetters();
    final boot = _pickDriveLetter(
      requested: plan.preferredBootLetter,
      preferences: const ['S', 'T', 'U', 'V', 'X', 'Y', 'Z'],
      used: used,
    );
    used.add(boot);
    final storage = _pickDriveLetter(
      requested: plan.preferredSystemLetter,
      preferences: const ['W', 'V', 'U', 'T', 'R', 'X', 'Y', 'Z'],
      used: used,
    );
    used.add(storage);
    final image = _pickDriveLetter(
      requested: '',
      preferences: const ['I', 'J', 'K', 'L', 'M', 'N', 'O', 'P', 'Q'],
      used: used,
    );
    return _WtgDriveLetters(boot: boot, storage: storage, image: image);
  }

  String _pickDriveLetter({
    required String requested,
    required List<String> preferences,
    required Set<String> used,
  }) {
    final normalized = _letterOnly(requested);
    if (normalized.isNotEmpty) {
      if (used.contains(normalized)) {
        throw const _WtgFailure(
          'deploy_compat_invalid_letter',
          'A requested drive letter is already in use.',
        );
      }
      return normalized;
    }
    for (final candidate in preferences) {
      if (!used.contains(candidate)) return candidate;
    }
    for (var code = 90; code >= 68; code--) {
      final candidate = String.fromCharCode(code);
      if (!used.contains(candidate)) return candidate;
    }
    throw const _WtgFailure(
      'deploy_compat_invalid_letter',
      'No unused drive letter is available.',
    );
  }

  Future<Set<String>> _usedDriveLetters() async {
    try {
      final result = await _runTracked('powershell', const [
        '-NoProfile',
        '-NonInteractive',
        '-ExecutionPolicy',
        'Bypass',
        '-Command',
        r'''@(
  Get-Volume -ErrorAction SilentlyContinue | Where-Object DriveLetter | ForEach-Object { $_.DriveLetter }
  Get-PSDrive -PSProvider FileSystem -ErrorAction SilentlyContinue | ForEach-Object { $_.Name }
) | ForEach-Object { $_.ToString().ToUpperInvariant() } | Sort-Object -Unique''',
      ], timeout: const Duration(seconds: 10));
      if (result.exitCode != 0) throw StateError('${result.stderr}');
      return const LineSplitter()
          .convert(result.stdout.toString())
          .map((value) => _letterOnly(value))
          .where((value) => value.isNotEmpty)
          .toSet();
    } on _WtgFailure {
      rethrow;
    } catch (error) {
      throw _WtgFailure(
        'deploy_compat_invalid_letter',
        'Drive-letter enumeration failed: $error',
      );
    }
  }

  Future<_WtgPartitionLayout> _partitionDisk({
    required DiskInfo disk,
    required DeploymentPlan plan,
    required _WtgDriveLetters letters,
  }) async {
    final bootLayout = switch (plan.bootMode) {
      DeploymentBootMode.uefiGpt => WtgBootLayout.uefiGpt,
      DeploymentBootMode.uefiMbr => WtgBootLayout.uefiMbr,
      DeploymentBootMode.legacyBios => WtgBootLayout.legacyBios,
    };
    final bootLabel = bootLayout == WtgBootLayout.legacyBios
        ? 'WDS_BOOT'
        : 'WDS_EFI';
    final storageLabel = plan.customVolumeLabel.trim().isEmpty
        ? 'WDS_TOGO'
        : plan.customVolumeLabel.trim();
    final script = _buildWtgDiskpartScript(
      diskNumber: disk.diskNumber,
      bootLayout: bootLayout,
      currentPartitionStyle: disk.partitionStyle,
      bootLetter: letters.boot,
      storageLetter: letters.storage,
      bootLabel: bootLabel,
      storageLabel: storageLabel,
    );
    final result = await ref
        .read(diskSafetyServiceProvider)
        .runGuardedDiskpart(disk, script, timeout: const Duration(minutes: 3));
    if (!_diskpartSucceeded(result)) {
      throw _WtgFailure(
        'wtg_svc_partition_failed',
        'DiskPart failed: ${_trimOutput(result.stderr)} '
            '${_trimOutput(result.stdout)}',
      );
    }
    final layout = _WtgPartitionLayout(
      bootLayout: bootLayout,
      bootDrive: '${letters.boot}:\\',
      storageDrive: '${letters.storage}:\\',
      bootLabel: bootLabel,
      storageLabel: storageLabel,
    );
    if (!await _verifyPartitionLayout(disk.diskNumber, layout)) {
      throw const _WtgFailure(
        'wtg_svc_partition_failed',
        'The target partition layout failed its postcondition check.',
      );
    }
    return layout;
  }

  static String _buildWtgDiskpartScript({
    required int diskNumber,
    required WtgBootLayout bootLayout,
    required String currentPartitionStyle,
    required String bootLetter,
    required String storageLetter,
    required String bootLabel,
    required String storageLabel,
  }) {
    final usesGpt = bootLayout == WtgBootLayout.uefiGpt;
    final targetStyle = usesGpt ? 'GPT' : 'MBR';
    final currentStyle = currentPartitionStyle.trim().toUpperCase();
    // DiskPart `clean` retains GPT/MBR metadata. Avoid a matching conversion,
    // which DiskPart rejects after the target has already been erased.
    final conversion = currentStyle == targetStyle
        ? null
        : 'convert ${targetStyle.toLowerCase()}';
    final commands = <String>[
      'select disk $diskNumber',
      'clean',
      ?conversion,
      usesGpt
          ? 'create partition efi size=300'
          : 'create partition primary size=350',
      'format fs=${bootLayout == WtgBootLayout.legacyBios ? 'ntfs' : 'fat32'} label="$bootLabel" quick',
      if (!usesGpt) 'active',
      'assign letter=$bootLetter',
      if (usesGpt) 'create partition msr size=16',
      'create partition primary',
      'format fs=ntfs label="$storageLabel" quick',
      'assign letter=$storageLetter',
      'exit',
    ];
    return '${commands.join('\n')}\n';
  }

  Future<bool> _verifyPartitionLayout(
    int diskNumber,
    _WtgPartitionLayout layout,
  ) async {
    final bootLetter = _letterOnly(layout.bootDrive);
    final storageLetter = _letterOnly(layout.storageDrive);
    try {
      final result = await _runTracked(
        'powershell',
        const [
          '-NoProfile',
          '-NonInteractive',
          '-ExecutionPolicy',
          'Bypass',
          '-Command',
          r'''$boot = Get-Partition -DriveLetter $env:WDS_BOOT -ErrorAction Stop
$storage = Get-Partition -DriveLetter $env:WDS_STORAGE -ErrorAction Stop
$bootVolume = Get-Volume -DriveLetter $env:WDS_BOOT -ErrorAction Stop
$storageVolume = Get-Volume -DriveLetter $env:WDS_STORAGE -ErrorAction Stop
$disk = Get-Disk -Number $boot.DiskNumber -ErrorAction Stop
[PSCustomObject]@{
  BootDisk = $boot.DiskNumber
  StorageDisk = $storage.DiskNumber
  BootPartition = $boot.PartitionNumber
  StoragePartition = $storage.PartitionNumber
  Style = $disk.PartitionStyle.ToString()
  BootFs = $bootVolume.FileSystem
  StorageFs = $storageVolume.FileSystem
  BootLabel = $bootVolume.FileSystemLabel
  StorageLabel = $storageVolume.FileSystemLabel
  BootGptType = if ($boot.GptType) { $boot.GptType.ToString() } else { '' }
  BootActive = [bool]$boot.IsActive
} | ConvertTo-Json -Compress''',
        ],
        environment: {
          ...Platform.environment,
          'WDS_BOOT': bootLetter,
          'WDS_STORAGE': storageLetter,
        },
        timeout: const Duration(seconds: 20),
      );
      if (result.exitCode != 0) return false;
      final decoded = jsonDecode(result.stdout.toString());
      if (decoded is! Map) return false;
      final style = decoded['Style'].toString().toUpperCase();
      final bootFs = decoded['BootFs'].toString().toUpperCase();
      final storageFs = decoded['StorageFs'].toString().toUpperCase();
      final expectedStyle = layout.bootLayout == WtgBootLayout.uefiGpt
          ? 'GPT'
          : 'MBR';
      final expectedBootFs = layout.bootLayout == WtgBootLayout.legacyBios
          ? 'NTFS'
          : 'FAT32';
      final baseValid =
          decoded['BootDisk'].toString() == '$diskNumber' &&
          decoded['StorageDisk'].toString() == '$diskNumber' &&
          decoded['BootPartition'].toString() !=
              decoded['StoragePartition'].toString() &&
          style == expectedStyle &&
          bootFs == expectedBootFs &&
          storageFs == 'NTFS' &&
          decoded['BootLabel'].toString().toUpperCase() ==
              layout.bootLabel.toUpperCase() &&
          decoded['StorageLabel'].toString().toUpperCase() ==
              layout.storageLabel.toUpperCase();
      if (!baseValid) return false;
      if (layout.bootLayout == WtgBootLayout.uefiGpt) {
        return decoded['BootGptType'].toString().toUpperCase() ==
            '{C12A7328-F81F-11D2-BA4B-00A0C93EC93B}';
      }
      return decoded['BootActive'] == true;
    } on _WtgFailure {
      rethrow;
    } catch (error) {
      _logLine('Partition verification error: $error');
      return false;
    }
  }

  Future<_WtgVirtualDisk> _createVirtualDisk({
    required _WtgPartitionLayout layout,
    required DeploymentPlan plan,
    required String imageLetter,
    required int physicalDiskNumber,
  }) async {
    final filePath = p.join(
      _driveRoot(layout.storageDrive),
      plan.virtualDiskFileName,
    );
    final maximumMb = plan.virtualDiskSizeGb * 1024;
    final type = plan.virtualDiskType == VirtualDiskType.fixed
        ? 'fixed'
        : 'expandable';
    final script =
        '''
create vdisk file="$filePath" maximum=$maximumMb type=$type
select vdisk file="$filePath"
attach vdisk
convert mbr
create partition primary
format fs=ntfs label="WDS_OS" quick
assign letter=$imageLetter
exit
''';
    final result = await _runDiskpartFile(script);
    if (!_diskpartSucceeded(result)) {
      throw _WtgFailure(
        'wtg_svc_partition_failed',
        'Virtual disk creation failed: ${_trimOutput(result.stderr)} '
            '${_trimOutput(result.stdout)}',
      );
    }
    final diskNumber = await _verifyVirtualDisk(
      filePath: filePath,
      imageLetter: imageLetter,
      physicalDiskNumber: physicalDiskNumber,
    );
    if (diskNumber == null) {
      await _detachVirtualDisk(filePath);
      throw const _WtgFailure(
        'wtg_svc_partition_failed',
        'The virtual disk failed its identity postcondition check.',
      );
    }
    _logLine('Virtual disk ready: $filePath at $imageLetter:');
    return _WtgVirtualDisk(
      filePath: filePath,
      fileName: plan.virtualDiskFileName,
      imageDrive: '$imageLetter:\\',
      diskNumber: diskNumber,
    );
  }

  Future<int?> _verifyVirtualDisk({
    required String filePath,
    required String imageLetter,
    required int physicalDiskNumber,
  }) async {
    try {
      final result = await _runTracked(
        'powershell',
        const [
          '-NoProfile',
          '-NonInteractive',
          '-ExecutionPolicy',
          'Bypass',
          '-Command',
          r'''$ErrorActionPreference = 'Stop'
$image = Get-DiskImage -ImagePath $env:WDS_VHD_PATH -ErrorAction Stop
if (-not $image.Attached) { throw 'The selected virtual disk is not attached.' }
$imageDisk = $image | Get-Disk -ErrorAction Stop
$partition = Get-Partition -DriveLetter $env:WDS_IMAGE -ErrorAction Stop
$disk = Get-Disk -Number $partition.DiskNumber -ErrorAction Stop
$backingLetter = [System.IO.Path]::GetPathRoot($env:WDS_VHD_PATH).Substring(0, 1)
$backingPartition = Get-Partition -DriveLetter $backingLetter -ErrorAction Stop
$volume = Get-Volume -DriveLetter $env:WDS_IMAGE -ErrorAction Stop
[PSCustomObject]@{
  DiskNumber = $disk.Number
  ImageDiskNumber = $imageDisk.Number
  BackingDiskNumber = $backingPartition.DiskNumber
  ImagePath = $image.ImagePath
  Attached = [bool]$image.Attached
  BusType = $disk.BusType.ToString()
  Style = $disk.PartitionStyle.ToString()
  Fs = $volume.FileSystem
  Label = $volume.FileSystemLabel
} | ConvertTo-Json -Compress''',
        ],
        environment: {
          ...Platform.environment,
          'WDS_IMAGE': imageLetter,
          'WDS_VHD_PATH': filePath,
          'WDS_PHYSICAL_DISK': '$physicalDiskNumber',
        },
        timeout: const Duration(seconds: 20),
      );
      if (result.exitCode != 0) return null;
      final decoded = jsonDecode(result.stdout.toString());
      if (decoded is! Map) return null;
      final diskNumber = int.tryParse(decoded['DiskNumber'].toString());
      final imageDiskNumber = int.tryParse(
        decoded['ImageDiskNumber'].toString(),
      );
      final backingDiskNumber = int.tryParse(
        decoded['BackingDiskNumber'].toString(),
      );
      final valid =
          diskNumber != null &&
          diskNumber != physicalDiskNumber &&
          imageDiskNumber == diskNumber &&
          backingDiskNumber == physicalDiskNumber &&
          decoded['Attached'] == true &&
          _normalizedPath(decoded['ImagePath'].toString()) ==
              _normalizedPath(filePath) &&
          decoded['BusType'].toString().toUpperCase().contains('FILE') &&
          decoded['Style'].toString().toUpperCase() == 'MBR' &&
          decoded['Fs'].toString().toUpperCase() == 'NTFS' &&
          decoded['Label'].toString().toUpperCase() == 'WDS_OS';
      return valid ? diskNumber : null;
    } on _WtgFailure {
      rethrow;
    } catch (_) {
      return null;
    }
  }

  Future<ProcessResult> _runDiskpartFile(
    String script, {
    bool allowWhenCancelled = false,
  }) async {
    final programData = Platform.environment['ProgramData'];
    if (programData == null || programData.trim().isEmpty) {
      throw const _WtgFailure(
        'wtg_svc_partition_failed',
        'A secure DiskPart script location is unavailable.',
      );
    }
    final root = Directory(p.join(programData, 'WinDeployStudioSecureScripts'));
    await root.create(recursive: true);
    if (await FileSystemEntity.type(root.path, followLinks: false) ==
        FileSystemEntityType.link) {
      throw const _WtgFailure(
        'wtg_svc_partition_failed',
        'The secure DiskPart script location is not trustworthy.',
      );
    }
    await _lockDownDirectory(root.path, allowWhenCancelled: allowWhenCancelled);
    final token = '${pid}_${DateTime.now().microsecondsSinceEpoch}';
    final file = File(p.join(root.path, 'wds_vdisk_$token.txt'));
    try {
      await file.writeAsString(script, flush: true);
      return await _runTracked(
        'diskpart',
        ['/s', file.path],
        timeout: const Duration(minutes: 10),
        allowWhenCancelled: allowWhenCancelled,
      );
    } finally {
      try {
        if (await file.exists()) await file.delete();
      } catch (_) {}
    }
  }

  Future<void> _detachVirtualDisk(String filePath) async {
    final script =
        '''
select vdisk file="$filePath"
detach vdisk
exit
''';
    try {
      final result = await _runDiskpartFile(script, allowWhenCancelled: true);
      _logLine('Virtual disk detach exit=${result.exitCode}: $filePath');
    } catch (error) {
      _logLine('Virtual disk detach warning: $error');
    }
  }

  Future<String> _stageWimBootSource(
    String sourcePath,
    String storageDrive,
  ) async {
    final directory = Directory(p.join(_driveRoot(storageDrive), 'WIMBoot'));
    await directory.create(recursive: true);
    final target = File(p.join(directory.path, 'install.wim'));
    final source = File(sourcePath);
    RandomAccessFile? input;
    RandomAccessFile? output;
    try {
      input = await source.open(mode: FileMode.read);
      output = await target.open(mode: FileMode.write);
      while (true) {
        _throwIfCancelled();
        final chunk = await input.read(4 * 1024 * 1024);
        if (chunk.isEmpty) break;
        await output.writeFrom(chunk);
      }
      await output.flush();
      await input.close();
      input = null;
      await output.close();
      output = null;
      if (!await target.exists() ||
          await target.length() != await source.length() ||
          await _sha256File(target) != await _sha256File(source)) {
        throw const _WtgFailure(
          'wtg_svc_apply_failed',
          'The persistent WIMBoot source copy failed verification.',
        );
      }
    } catch (_) {
      try {
        if (await target.exists()) await target.delete();
      } catch (_) {}
      rethrow;
    } finally {
      await input?.close();
      await output?.close();
    }
    final attrib = await _runTracked('attrib', [
      '+H',
      '+S',
      directory.path,
    ], timeout: const Duration(seconds: 30));
    if (attrib.exitCode != 0) {
      throw const _WtgFailure(
        'wtg_svc_apply_failed',
        'The persistent WIMBoot source could not be protected.',
      );
    }
    _logLine('WIMBoot source staged persistently at ${target.path}.');
    return target.path;
  }

  Future<bool> _applyImage({
    required String sourcePath,
    required int imageIndex,
    required String targetDrive,
    required bool compact,
    required bool wimBoot,
    WtgProgressCallback? onProgress,
  }) async {
    final sourceLength = await File(sourcePath).length();
    final stopwatch = Stopwatch()..start();
    final arguments = <String>[
      '/English',
      '/Apply-Image',
      '/ImageFile:$sourcePath',
      '/Index:$imageIndex',
      '/ApplyDir:${_driveRoot(targetDrive)}',
      if (compact) '/Compact',
      if (wimBoot) '/WIMBoot',
    ];
    _logLine('Starting DISM ${arguments.join(' ')}');
    final process = await Process.start(
      'dism',
      arguments,
      environment: WindowsSystemEnvironment.withSystemRoot(),
    );
    _currentProcess = process;
    if (_cancelled) {
      await _terminateProcess(process);
      _throwIfCancelled();
    }
    var lastPercent = 0;
    var lastBytes = 0;
    var lastElapsedMs = 0;

    void parse(String data) {
      final matches = RegExp(r'(\d{1,3})(?:\.\d+)?\s*%').allMatches(data);
      if (matches.isEmpty) return;
      final percent = int.tryParse(matches.last.group(1) ?? '') ?? 0;
      if (percent <= lastPercent || percent > 100) return;
      lastPercent = percent;
      final elapsedMs = stopwatch.elapsedMilliseconds;
      final bytes = (sourceLength * percent / 100).round();
      final deltaMs = elapsedMs - lastElapsedMs;
      final speed = deltaMs > 0
          ? ((bytes - lastBytes) * 1000 / deltaMs).round()
          : 0;
      lastBytes = bytes;
      lastElapsedMs = elapsedMs;
      _notify(
        onProgress,
        WtgProgress(
          step: WtgStep.applyingImage,
          message: 'wtg_svc_applying_percent',
          progress: 0.22 + percent / 100 * 0.48,
          writtenBytes: bytes,
          totalBytes: sourceLength,
          currentSpeedBytes: speed,
          elapsedTime: stopwatch.elapsed,
        ),
      );
    }

    final stdoutDone = process.stdout
        .transform(const SystemEncoding().decoder)
        .listen((data) {
          _logLine('DISM: ${_trimOutput(data)}');
          parse(data);
        })
        .asFuture<void>();
    final stderrDone = process.stderr
        .transform(const SystemEncoding().decoder)
        .listen((data) {
          if (data.trim().isNotEmpty) {
            _logLine('DISM stderr: ${_trimOutput(data)}');
          }
          parse(data);
        })
        .asFuture<void>();
    try {
      final exitCode = await process.exitCode.timeout(const Duration(hours: 2));
      await stdoutDone;
      await stderrDone;
      stopwatch.stop();
      _logLine('DISM exit=$exitCode elapsed=${stopwatch.elapsed}.');
      _throwIfCancelled();
      return exitCode == 0 &&
          await Directory(p.join(_driveRoot(targetDrive), 'Windows')).exists();
    } on TimeoutException {
      await _terminateProcess(process);
      rethrow;
    } finally {
      if (identical(_currentProcess, process)) _currentProcess = null;
    }
  }

  Future<bool> _writeBootFiles({
    required DiskInfo disk,
    required String windowsDrive,
    required _WtgPartitionLayout layout,
    required _WtgVirtualDisk? virtualDisk,
    required String architecture,
    required String legacyBootsectPath,
  }) async {
    final windowsPath = p.join(_driveRoot(windowsDrive), 'Windows');
    final systemRoot = Platform.environment['SystemRoot'] ?? r'C:\Windows';
    final bcdboot = File(p.join(systemRoot, 'System32', 'bcdboot.exe'));
    if (!await bcdboot.exists()) {
      _logLine('Host BCDBoot is missing: ${bcdboot.path}');
      return false;
    }
    final firmware = layout.bootLayout == WtgBootLayout.legacyBios
        ? 'BIOS'
        : 'UEFI';
    final result = await _runTracked(bcdboot.path, [
      windowsPath,
      '/s',
      _driveRoot(layout.bootDrive),
      '/f',
      firmware,
      '/v',
    ], timeout: const Duration(minutes: 3));
    _logLine('bcdboot exit=${result.exitCode}: ${_trimOutput(result.stdout)}');
    if (result.exitCode != 0) {
      _logLine('bcdboot stderr: ${_trimOutput(result.stderr)}');
      return false;
    }
    if (layout.bootLayout == WtgBootLayout.legacyBios &&
        !await _writeLegacyBootCode(
          disk: disk,
          layout: layout,
          bootDrive: layout.bootDrive,
          bootsectPath: legacyBootsectPath,
        )) {
      return false;
    }
    if (layout.bootLayout != WtgBootLayout.legacyBios &&
        !await _ensureFallbackUefiBootFile(
          bootDrive: layout.bootDrive,
          architecture: architecture,
        )) {
      return false;
    }
    await _revalidateTargetDisk(disk, layout);
    return _configureBcd(
      layout: layout,
      windowsDrive: windowsDrive,
      virtualDisk: virtualDisk,
    );
  }

  Future<bool> _writeLegacyBootCode({
    required DiskInfo disk,
    required _WtgPartitionLayout layout,
    required String bootDrive,
    required String bootsectPath,
  }) async {
    final executable = File(bootsectPath);
    if (!await executable.exists()) {
      _logLine('Legacy boot code failed: ISO bootsect.exe is missing.');
      return false;
    }
    await _revalidateTargetDisk(disk, layout);
    final result = await _runTracked(executable.path, [
      '/nt60',
      _driveSpec(bootDrive),
      '/mbr',
      '/force',
    ], timeout: const Duration(minutes: 2));
    _logLine('bootsect exit=${result.exitCode}: ${_trimOutput(result.stdout)}');
    if (result.exitCode != 0) {
      _logLine('bootsect stderr: ${_trimOutput(result.stderr)}');
      return false;
    }
    return true;
  }

  Future<bool> _configureBcd({
    required _WtgPartitionLayout layout,
    required String windowsDrive,
    required _WtgVirtualDisk? virtualDisk,
  }) async {
    final bcdPath = _bcdPath(layout);
    if (!await File(bcdPath).exists()) return false;
    final device = _expectedBcdDevice(layout, windowsDrive, virtualDisk);
    final commands = <List<String>>[
      ['/store', bcdPath, '/set', '{default}', 'device', device],
      ['/store', bcdPath, '/set', '{default}', 'osdevice', device],
      ['/store', bcdPath, '/set', '{default}', 'detecthal', 'yes'],
    ];
    for (final arguments in commands) {
      final result = await _runTracked(
        'bcdedit',
        arguments,
        timeout: const Duration(seconds: 45),
      );
      _logLine('bcdedit ${arguments.join(' ')} exit=${result.exitCode}');
      if (result.exitCode != 0) return false;
    }
    return _verifyBcdDevice(bcdPath, layout, virtualDisk, windowsDrive);
  }

  Future<bool> _verifyBcdDevice(
    String bcdPath,
    _WtgPartitionLayout layout,
    _WtgVirtualDisk? virtualDisk,
    String windowsDrive,
  ) async {
    final result = await _runTracked('bcdedit', [
      '/store',
      bcdPath,
      '/enum',
      '{default}',
      '/v',
    ], timeout: const Duration(seconds: 45));
    if (result.exitCode != 0) return false;
    final expected = _expectedBcdDevice(layout, windowsDrive, virtualDisk);
    return WtgBootContract.listingMatches(result.stdout.toString(), expected);
  }

  String _expectedBcdDevice(
    _WtgPartitionLayout layout,
    String windowsDrive,
    _WtgVirtualDisk? virtualDisk,
  ) => WtgBootContract.expectedDevice(
    windowsDrive: windowsDrive,
    storageDrive: layout.storageDrive,
    virtualDiskFileName: virtualDisk?.fileName ?? '',
  );

  Future<bool> _ensureFallbackUefiBootFile({
    required String bootDrive,
    required String architecture,
  }) async {
    final suffix = switch (architecture.toLowerCase()) {
      'arm64' => 'aa64',
      'x86' => 'ia32',
      _ => 'x64',
    };
    final targetDirectory = Directory(
      p.join(_driveRoot(bootDrive), 'EFI', 'Boot'),
    );
    await targetDirectory.create(recursive: true);
    final target = File(p.join(targetDirectory.path, 'boot$suffix.efi'));
    final source = File(
      p.join(_driveRoot(bootDrive), 'EFI', 'Microsoft', 'Boot', 'bootmgfw.efi'),
    );
    if (!await source.exists()) return false;
    if (!await target.exists() ||
        await _sha256File(target) != await _sha256File(source)) {
      await source.copy(target.path);
    }
    return await target.exists() &&
        await _sha256File(target) == await _sha256File(source);
  }

  Future<bool> _verifyDeployment({
    required DiskInfo disk,
    required _WtgPartitionLayout layout,
    required DeploymentPlan plan,
    required String windowsDrive,
    required _WtgVirtualDisk? virtualDisk,
    required String architecture,
    required Uint8List? preparedIcon,
  }) async {
    await _revalidateTargetDisk(disk, layout);
    final diskNumber = disk.diskNumber;
    if (!await Directory(
      p.join(_driveRoot(windowsDrive), 'Windows'),
    ).exists()) {
      return false;
    }
    final bcdPath = _bcdPath(layout);
    if (!await File(bcdPath).exists() ||
        !await _verifyBcdDevice(bcdPath, layout, virtualDisk, windowsDrive)) {
      return false;
    }
    if (layout.bootLayout == WtgBootLayout.legacyBios) {
      if (!await File(
        p.join(_driveRoot(layout.bootDrive), 'bootmgr'),
      ).exists()) {
        return false;
      }
    } else {
      final suffix = switch (architecture.toLowerCase()) {
        'arm64' => 'aa64',
        'x86' => 'ia32',
        _ => 'x64',
      };
      final fallback = File(
        p.join(_driveRoot(layout.bootDrive), 'EFI', 'Boot', 'boot$suffix.efi'),
      );
      final microsoftBootManager = File(
        p.join(
          _driveRoot(layout.bootDrive),
          'EFI',
          'Microsoft',
          'Boot',
          'bootmgfw.efi',
        ),
      );
      if (!await fallback.exists() ||
          !await microsoftBootManager.exists() ||
          await _sha256File(fallback) !=
              await _sha256File(microsoftBootManager)) {
        return false;
      }
    }
    if (virtualDisk != null) {
      if (!await File(virtualDisk.filePath).exists() ||
          await _verifyVirtualDisk(
                filePath: virtualDisk.filePath,
                imageLetter: _letterOnly(virtualDisk.imageDrive),
                physicalDiskNumber: diskNumber,
              ) !=
              virtualDisk.diskNumber) {
        return false;
      }
    }
    if (plan.usesNtfsUefiLayout) {
      final uefiSafe =
          layout.bootLayout != WtgBootLayout.legacyBios &&
          layout.bootLabel == 'WDS_EFI';
      if (!uefiSafe) return false;
      _logLine(
        'NTFS UEFI layout VERIFIED: NTFS system storage uses a separate FAT32 EFI partition.',
      );
    }
    final volumeIdentity = WtgVolumeIdentity.fromPlan(plan);
    if (volumeIdentity.usesCustomIcon) {
      final icon = File(
        p.join(_driveRoot(layout.storageDrive), WtgVolumeIdentity.iconFileName),
      );
      final autorun = File(
        p.join(_driveRoot(layout.storageDrive), 'autorun.inf'),
      );
      if (preparedIcon == null ||
          !await icon.exists() ||
          !await autorun.exists() ||
          await _sha256File(icon) != sha256.convert(preparedIcon).toString()) {
        return false;
      }
      final autorunText = (await autorun.readAsString()).toLowerCase();
      if (!autorunText.contains('icon=${WtgVolumeIdentity.iconFileName}')) {
        return false;
      }
      final expectedLabel = volumeIdentity.volumeLabel.toLowerCase();
      if (expectedLabel.isNotEmpty &&
          !autorunText.contains('label=$expectedLabel')) {
        return false;
      }
    }
    _logLine('All deployment postconditions passed.');
    return true;
  }

  Future<void> _writeVolumeIdentity(
    String storageDrive,
    WtgVolumeIdentity identity,
    Uint8List? preparedIcon,
  ) async {
    final autorunContents = identity.autorunContents;
    if (autorunContents == null) {
      _logLine(
        'No custom volume icon requested; leaving the Windows default drive icon.',
      );
      return;
    }
    if (preparedIcon == null) {
      throw const _WtgFailure(
        'deploy_compat_invalid_icon',
        'The custom ICO file was not staged before disk erasure.',
      );
    }
    final root = _driveRoot(storageDrive);
    final target = File(p.join(root, WtgVolumeIdentity.iconFileName));
    await target.writeAsBytes(preparedIcon, flush: true);
    if (await _sha256File(target) != sha256.convert(preparedIcon).toString()) {
      throw const _WtgFailure(
        'deploy_compat_invalid_icon',
        'The custom drive icon failed verification.',
      );
    }
    await File(
      p.join(root, 'autorun.inf'),
    ).writeAsString(autorunContents, flush: true);
    final attrib = await _runTracked('attrib', [
      '+H',
      '+S',
      target.path,
      p.join(root, 'autorun.inf'),
    ], timeout: const Duration(seconds: 30));
    if (attrib.exitCode != 0) {
      throw const _WtgFailure(
        'deploy_compat_invalid_icon',
        'The custom drive icon attributes could not be applied.',
      );
    }
  }

  String _bcdPath(_WtgPartitionLayout layout) {
    return layout.bootLayout == WtgBootLayout.legacyBios
        ? p.join(_driveRoot(layout.bootDrive), 'Boot', 'BCD')
        : p.join(
            _driveRoot(layout.bootDrive),
            'EFI',
            'Microsoft',
            'Boot',
            'BCD',
          );
  }

  Future<String?> _mountIso(String isoPath) async {
    if (!await File(isoPath).exists()) return null;
    _notifyInternalMount();
    try {
      await _runTracked(
        'powershell',
        const [
          '-NoProfile',
          '-NonInteractive',
          '-ExecutionPolicy',
          'Bypass',
          '-Command',
          r'Dismount-DiskImage -ImagePath $env:WDS_ISO -ErrorAction SilentlyContinue | Out-Null',
        ],
        environment: {...Platform.environment, 'WDS_ISO': isoPath},
        timeout: const Duration(seconds: 20),
      );
      final mount = await _runTracked(
        'powershell',
        const [
          '-NoProfile',
          '-NonInteractive',
          '-ExecutionPolicy',
          'Bypass',
          '-Command',
          r'Mount-DiskImage -ImagePath $env:WDS_ISO -ErrorAction Stop | Out-Null',
        ],
        environment: {...Platform.environment, 'WDS_ISO': isoPath},
        timeout: const Duration(minutes: 2),
      );
      if (mount.exitCode != 0) return null;
      for (var attempt = 0; attempt < 30; attempt++) {
        _throwIfCancelled();
        final result = await _runTracked(
          'powershell',
          const [
            '-NoProfile',
            '-NonInteractive',
            '-ExecutionPolicy',
            'Bypass',
            '-Command',
            r'(Get-DiskImage -ImagePath $env:WDS_ISO -ErrorAction Stop | Get-Volume -ErrorAction Stop).DriveLetter',
          ],
          environment: {...Platform.environment, 'WDS_ISO': isoPath},
          timeout: const Duration(seconds: 10),
        );
        final letter = _letterOnly(result.stdout.toString());
        if (result.exitCode == 0 && letter.isNotEmpty) {
          _currentIsoPath = isoPath;
          return '$letter:\\';
        }
        await Future<void>.delayed(const Duration(milliseconds: 350));
      }
    } on _WtgFailure {
      rethrow;
    } catch (error) {
      _logLine('ISO mount error: $error');
    }
    return null;
  }

  void _notifyInternalMount() {
    _logLine('Mounting ISO image.');
  }

  Future<void> _unmountIso(String isoPath) async {
    try {
      await _runTracked(
        'powershell',
        const [
          '-NoProfile',
          '-NonInteractive',
          '-ExecutionPolicy',
          'Bypass',
          '-Command',
          r'Dismount-DiskImage -ImagePath $env:WDS_ISO -ErrorAction SilentlyContinue | Out-Null',
        ],
        environment: {...Platform.environment, 'WDS_ISO': isoPath},
        timeout: const Duration(seconds: 30),
        allowWhenCancelled: true,
      );
    } catch (error) {
      _logLine('ISO unmount warning: $error');
    }
    if (_currentIsoPath == isoPath) _currentIsoPath = null;
  }

  Future<void> _requireSafeDisk(DiskInfo disk) async {
    final result = await ref
        .read(diskSafetyServiceProvider)
        .checkDiskSafety(disk);
    if (!result.isSafe) {
      throw _WtgFailure(result.reason, 'Target disk safety validation failed.');
    }
  }

  Future<void> _revalidateTargetDisk(
    DiskInfo disk,
    _WtgPartitionLayout layout,
  ) async {
    await _requireSafeDisk(disk);
    if (!await _verifyPartitionLayout(disk.diskNumber, layout)) {
      throw const _WtgFailure(
        'safety_disk_changed',
        'The target disk partition binding changed during deployment.',
      );
    }
  }

  bool _diskpartSucceeded(ProcessResult result) {
    if (result.exitCode != 0) return false;
    final output = '${result.stdout}\n${result.stderr}'.toLowerCase();
    const knownErrors = [
      'diskpart has encountered an error',
      'virtual disk service error',
      'access is denied',
      'the parameter is incorrect',
      'diskpart 遇到错误',
      '虚拟磁盘服务错误',
      '拒绝访问',
      '参数错误',
    ];
    return !knownErrors.any(output.contains);
  }

  void _throwIfCancelled() {
    if (_cancelled) {
      throw const _WtgFailure(
        'deploy_cancel_requested',
        'The deployment was cancelled.',
      );
    }
  }

  Future<ProcessResult> _runTracked(
    String executable,
    List<String> arguments, {
    required Duration timeout,
    Map<String, String>? environment,
    bool allowWhenCancelled = false,
  }) async {
    if (!allowWhenCancelled) _throwIfCancelled();
    if (_currentProcess != null) {
      throw const _WtgFailure(
        'creator_error',
        'A deployment subprocess is already running.',
      );
    }
    final resolvedExecutable = executable.toLowerCase() == 'powershell'
        ? WindowsSystemEnvironment.powerShellExecutable
        : executable;
    final process = await Process.start(
      resolvedExecutable,
      arguments,
      environment: WindowsSystemEnvironment.withSystemRoot(environment),
    );
    _currentProcess = process;
    if (_cancelled && !allowWhenCancelled) {
      await _terminateProcess(process);
      _throwIfCancelled();
    }
    final stdoutFuture = process.stdout
        .transform(const SystemEncoding().decoder)
        .join();
    final stderrFuture = process.stderr
        .transform(const SystemEncoding().decoder)
        .join();
    try {
      final exitCode = await process.exitCode.timeout(timeout);
      final stdout = await stdoutFuture;
      final stderr = await stderrFuture;
      if (!allowWhenCancelled) _throwIfCancelled();
      return ProcessResult(process.pid, exitCode, stdout, stderr);
    } on TimeoutException {
      _logLine(
        '$executable timed out after ${timeout.inSeconds}s; terminating process tree.',
      );
      await _terminateProcess(process);
      rethrow;
    } finally {
      if (identical(_currentProcess, process)) _currentProcess = null;
    }
  }

  Future<void> _terminateProcess(Process process) async {
    try {
      await Process.run(
        WindowsSystemEnvironment.taskkillExecutable,
        ['/F', '/T', '/PID', '${process.pid}'],
        environment: WindowsSystemEnvironment.withSystemRoot(),
      ).timeout(const Duration(seconds: 15));
    } catch (_) {
      process.kill(ProcessSignal.sigkill);
    }
    try {
      await process.exitCode.timeout(const Duration(seconds: 10));
    } catch (_) {
      process.kill(ProcessSignal.sigkill);
    }
  }

  Future<void> _stopCurrentProcess() async {
    final process = _currentProcess;
    if (process == null) return;
    await _terminateProcess(process);
    if (identical(_currentProcess, process)) _currentProcess = null;
  }

  void _killCurrentProcess() {
    final process = _currentProcess;
    if (process != null) unawaited(_terminateProcess(process));
  }

  void _notify(WtgProgressCallback? callback, WtgProgress progress) {
    if (!_cancelled || progress.step == WtgStep.failed) {
      callback?.call(progress);
    }
  }

  void _logLine(String message) {
    final line = '[${DateTime.now().toIso8601String()}] $message';
    _log.add(line);
    debugPrint(line);
    _detailLogWriteQueue = _detailLogWriteQueue.then(
      (_) => _appendDetailLogLine(line),
    );
  }

  Future<void> _appendDetailLogLine(String line) async {
    try {
      final directory = Directory(
        p.join(AppConstants.appDataPath, 'WinDeployStudio', 'logs'),
      );
      await directory.create(recursive: true);
      await File(
        p.join(directory.path, 'wtg_detail.log'),
      ).writeAsString('$line\n', mode: FileMode.append);
    } catch (_) {
      // Detailed diagnostics must not interfere with deployment progress.
    }
  }

  Future<String> saveLogToFile() async {
    try {
      final support = await getApplicationSupportDirectory();
      final file = File(
        p.join(support.path, 'logs', 'last_wtg_creation_log.txt'),
      );
      await file.parent.create(recursive: true);
      await file.writeAsString(logText, flush: true);
      return file.path;
    } catch (error) {
      return 'Log save failed: $error';
    }
  }

  static String _normalizedPath(String value) =>
      p.normalize(p.absolute(value.trim())).replaceAll('/', '\\').toUpperCase();

  static String _letterOnly(String value) {
    final match = RegExp(r'[A-Za-z]').firstMatch(value.trim());
    return match?.group(0)?.toUpperCase() ?? '';
  }

  static String _driveRoot(String drive) {
    final letter = _letterOnly(drive);
    return letter.isEmpty ? drive : '$letter:\\';
  }

  static String _driveSpec(String drive) => '${_letterOnly(drive)}:';

  static String _trimOutput(Object? value) {
    final text = value?.toString().trim().replaceAll(RegExp(r'\s+'), ' ') ?? '';
    return text.length <= 1200 ? text : '${text.substring(0, 1200)}...';
  }
}
