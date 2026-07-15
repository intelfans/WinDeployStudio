import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import 'windows_system_environment.dart';
import 'windows_iso_preflight.dart';

/// The result of determining whether an ISO can create a persistent Linux To
/// Go workspace without relying on its filename.
enum LinuxToGoImageStatus { supported, unsupported, inspectionFailed }

/// A supported Live image layout. More layouts can be added without making
/// callers infer behavior from individual files.
enum LinuxToGoImageFamily { casper, debianLive, deepinLive }

/// The persistence layout required by an image family.
enum LinuxToGoPersistenceStrategy {
  casperWritableImage,
  debianPersistenceImage,
}

/// The boot configuration syntax that a creator can safely modify.
enum LinuxToGoBootConfigSyntax { grub }

/// A typed reason for an image that cannot be used for Linux To Go.
enum LinuxToGoImageIssue {
  sourceNotRegularFile,
  mountFailed,
  windowsInstaller,
  missingX64Efi,
  missingKernel,
  missingInitrd,
  missingLivePayload,
  noPatchableBootConfig,
  bootFileTooLarge,
  debianLiveMissingNtfsSupport,
  unknownLayout,
}

extension LinuxToGoImageIssueLocalization on LinuxToGoImageIssue {
  /// The localization key a UI or progress service should show for this
  /// rejection. The caller can choose a more context-specific Windows key.
  String get localizationKey => switch (this) {
    LinuxToGoImageIssue.sourceNotRegularFile =>
      'linux_togo_source_not_regular_file',
    LinuxToGoImageIssue.mountFailed => 'linux_togo_mount_preflight_failed',
    LinuxToGoImageIssue.windowsInstaller => 'creator_windows_iso_in_linux_mode',
    LinuxToGoImageIssue.missingX64Efi => 'linux_togo_missing_x64_efi',
    LinuxToGoImageIssue.missingKernel => 'linux_togo_missing_live_kernel',
    LinuxToGoImageIssue.missingInitrd => 'linux_togo_missing_live_initrd',
    LinuxToGoImageIssue.missingLivePayload => 'linux_togo_missing_live_payload',
    LinuxToGoImageIssue.noPatchableBootConfig =>
      'linux_togo_boot_config_unsupported',
    LinuxToGoImageIssue.bootFileTooLarge => 'linux_togo_boot_file_too_large',
    LinuxToGoImageIssue.debianLiveMissingNtfsSupport =>
      'linux_togo_debian_live_missing_ntfs_support',
    LinuxToGoImageIssue.unknownLayout => 'linux_togo_unsupported_iso',
  };
}

/// A boot configuration that was both found and structurally accepted by the
/// inspector. The creator must patch only these approved files.
class LinuxToGoBootConfig {
  final String relativePath;
  final LinuxToGoBootConfigSyntax syntax;

  const LinuxToGoBootConfig({required this.relativePath, required this.syntax});
}

/// A Live filesystem payload copied only to the writable data partition.
class LinuxToGoPayload {
  final String relativePath;
  final int sizeBytes;

  const LinuxToGoPayload({required this.relativePath, required this.sizeBytes});
}

/// A source file captured by the destructive-operation preflight.
///
/// Keeping the manifest lets the copy path use fixed source sizes and avoids
/// repeatedly crawling a mounted ISO on Flutter's UI isolate.
class LinuxToGoContentFile {
  final String relativePath;
  final int sizeBytes;

  const LinuxToGoContentFile({
    required this.relativePath,
    required this.sizeBytes,
  });
}

/// The immutable contract a Linux To Go creator needs after an image has
/// passed structural inspection.
class LinuxToGoSupportedImage {
  final LinuxToGoImageFamily family;
  final LinuxToGoPersistenceStrategy persistenceStrategy;
  final String efiBootRelativePath;
  final String kernelRelativePath;
  final String initrdRelativePath;
  final List<LinuxToGoBootConfig> patchableBootConfigs;
  final List<LinuxToGoPayload> livePayloads;
  final List<LinuxToGoContentFile> contentFiles;
  final bool hasCompleteContentManifest;
  final int totalContentBytes;
  final int bootContentBytes;
  final bool supportsDriverStaging;

  LinuxToGoSupportedImage({
    required this.family,
    required this.persistenceStrategy,
    required this.efiBootRelativePath,
    required this.kernelRelativePath,
    required this.initrdRelativePath,
    required List<LinuxToGoBootConfig> patchableBootConfigs,
    required List<LinuxToGoPayload> livePayloads,
    List<LinuxToGoContentFile> contentFiles = const [],
    this.hasCompleteContentManifest = false,
    required this.totalContentBytes,
    required this.bootContentBytes,
    required this.supportsDriverStaging,
  }) : patchableBootConfigs = List.unmodifiable(patchableBootConfigs),
       livePayloads = List.unmodifiable(livePayloads),
       contentFiles = List.unmodifiable(contentFiles);

  List<String> get patchableBootConfigPaths => List.unmodifiable(
    patchableBootConfigs.map((config) => config.relativePath),
  );

  Set<String> get livePayloadExtensions => Set.unmodifiable(
    livePayloads
        .map((payload) => p.extension(payload.relativePath).toLowerCase())
        .where((extension) => extension.isNotEmpty)
        .map((extension) => extension.substring(1)),
  );

  bool isLivePayloadPath(String relativePath) {
    final normalized = _normalizeRelativePath(relativePath);
    return livePayloads.any(
      (payload) => _normalizeRelativePath(payload.relativePath) == normalized,
    );
  }
}

/// An immutable classification of one selected ISO.
class LinuxToGoImageInspection {
  final LinuxToGoImageStatus status;
  final LinuxToGoImageIssue? issue;
  final String? diagnostic;
  final LinuxToGoSupportedImage? image;

  const LinuxToGoImageInspection._({
    required this.status,
    this.issue,
    this.diagnostic,
    this.image,
  });

  factory LinuxToGoImageInspection.supported(LinuxToGoSupportedImage image) =>
      LinuxToGoImageInspection._(
        status: LinuxToGoImageStatus.supported,
        image: image,
      );

  const LinuxToGoImageInspection.unsupported(
    LinuxToGoImageIssue issue, {
    String? diagnostic,
  }) : this._(
         status: LinuxToGoImageStatus.unsupported,
         issue: issue,
         diagnostic: diagnostic,
       );

  const LinuxToGoImageInspection.inspectionFailed(
    LinuxToGoImageIssue issue, {
    String? diagnostic,
  }) : this._(
         status: LinuxToGoImageStatus.inspectionFailed,
         issue: issue,
         diagnostic: diagnostic,
       );

  bool get canCreate =>
      status == LinuxToGoImageStatus.supported && image != null;

  bool get canCreateLinuxToGo => canCreate;

  String? get messageKey => issue?.localizationKey;
}

/// Read-only ISO inspection used at selection time and immediately before a
/// destructive Linux To Go operation.
abstract interface class LinuxToGoImagePreflight {
  Future<LinuxToGoImageInspection> inspect(String isoPath);
}

/// Allows the real implementation to build a complete source manifest before
/// erasing a disk, while test and alternate implementations keep the compact
/// [LinuxToGoImagePreflight] contract.
extension LinuxToGoImagePreflightDeployment on LinuxToGoImagePreflight {
  Future<LinuxToGoImageInspection> inspectForDeployment(String isoPath) {
    final service = this;
    if (service is LinuxToGoImagePreflightService) {
      return service.inspectForDeployment(isoPath);
    }
    return inspect(isoPath);
  }
}

/// Windows implementation which mounts an ISO, inspects its root, and always
/// attempts to unmount it afterwards.
class LinuxToGoImagePreflightService implements LinuxToGoImagePreflight {
  static const int _fat32MaxFileBytes = 0xffffffff;
  static const String _efiBootRelativePath = 'EFI/BOOT/BOOTX64.EFI';
  static const String _casperKernelRelativePath = 'casper/vmlinuz';
  static const String _casperInitrdRelativePath = 'casper/initrd';
  static const String _debianKernelRelativePath = 'live/vmlinuz';
  static const String _debianInitrdRelativePath = 'live/initrd.img';
  static const String _deepinKernelRelativePath = 'live/vmlinuz.efi';
  static const String _deepinInitrdRelativePath = 'live/initrd';
  static const List<String> _deepinMarkerRelativePaths = [
    'live/filesyst.lin',
    'live/filesystem.linglong-manifest',
  ];
  static const List<String> _grubConfigPaths = [
    'boot/grub/grub.cfg',
    'boot/grub/loopback.cfg',
  ];

  /// The deployment flow invokes preflight twice: once before its early
  /// checks and again immediately before erasing. Cache only the complete
  /// manifest for the same immutable source snapshot so the second check does
  /// not crawl a multi-gigabyte ISO again.
  static final Map<String, LinuxToGoImageInspection> _deploymentCache = {};

  const LinuxToGoImagePreflightService();

  @override
  Future<LinuxToGoImageInspection> inspect(String isoPath) =>
      _inspect(isoPath, includeContentManifest: false);

  Future<LinuxToGoImageInspection> inspectForDeployment(String isoPath) =>
      _inspect(isoPath, includeContentManifest: true);

  Future<LinuxToGoImageInspection> _inspect(
    String isoPath, {
    required bool includeContentManifest,
  }) async {
    final source = File(isoPath);
    if (await FileSystemEntity.type(source.path, followLinks: false) !=
        FileSystemEntityType.file) {
      return const LinuxToGoImageInspection.unsupported(
        LinuxToGoImageIssue.sourceNotRegularFile,
      );
    }

    FileStat stat;
    try {
      stat = await source.stat();
    } catch (error) {
      return LinuxToGoImageInspection.inspectionFailed(
        LinuxToGoImageIssue.sourceNotRegularFile,
        diagnostic: 'Could not read the ISO source: $error',
      );
    }
    final cacheKey = _cacheKey(source.path, stat);
    if (includeContentManifest) {
      final cached = _deploymentCache[cacheKey];
      if (cached != null) return cached;
    }

    final mountPoint = await _mountIso(isoPath);
    if (mountPoint == null) {
      return const LinuxToGoImageInspection.inspectionFailed(
        LinuxToGoImageIssue.mountFailed,
        diagnostic:
            'Windows did not expose a drive letter for the mounted ISO.',
      );
    }

    try {
      final inspection = includeContentManifest
          ? await Isolate.run(
              () => _inspectMountedRootInWorker(mountPoint, stat.size),
            )
          : await inspectMountedRoot(mountPoint, sourceSizeBytes: stat.size);
      if (includeContentManifest && inspection.canCreate) {
        _deploymentCache[cacheKey] = inspection;
        while (_deploymentCache.length > 4) {
          _deploymentCache.remove(_deploymentCache.keys.first);
        }
      }
      return inspection;
    } catch (error) {
      return LinuxToGoImageInspection.inspectionFailed(
        LinuxToGoImageIssue.mountFailed,
        diagnostic: '$error',
      );
    } finally {
      await _unmountIso(isoPath);
    }
  }

  /// Inspects an already mounted ISO root. This is public so tests and other
  /// read-only callers can validate a directory fixture without PowerShell.
  ///
  /// Supplying [sourceSizeBytes] uses a fast structural scan suitable for the
  /// picker UI. The destructive path requests [includeContentManifest], which
  /// records every file in a worker isolate for exact space and copy checks.
  static Future<LinuxToGoImageInspection> inspectMountedRoot(
    String mountedRoot, {
    int? sourceSizeBytes,
    bool includeContentManifest = false,
  }) async {
    try {
      final root = Directory(mountedRoot);
      if (!await root.exists()) {
        return const LinuxToGoImageInspection.inspectionFailed(
          LinuxToGoImageIssue.mountFailed,
          diagnostic: 'The mounted ISO root is not available.',
        );
      }

      final windowsLayout = await WindowsIsoLayoutInspector.inspectMountedRoot(
        mountedRoot,
      );
      if (windowsLayout.isValid) {
        return const LinuxToGoImageInspection.unsupported(
          LinuxToGoImageIssue.windowsInstaller,
        );
      }

      final hasDeepinMarker = await Future.wait(
        _deepinMarkerRelativePaths.map(
          (relativePath) => _isRegularFile(p.join(mountedRoot, relativePath)),
        ),
      ).then((matches) => matches.any((matches) => matches));
      if (hasDeepinMarker) {
        return _inspectDeepinLive(
          mountedRoot: mountedRoot,
          sourceSizeBytes: sourceSizeBytes,
          includeContentManifest: includeContentManifest,
        );
      }

      final livePayloads = await _collectPayloads(
        mountedRoot,
        directory: 'live',
        extensions: const {'.squashfs', '.ext2'},
      );
      if (livePayloads.isNotEmpty) {
        return _inspectDebianLive(
          mountedRoot: mountedRoot,
          sourceSizeBytes: sourceSizeBytes,
          includeContentManifest: includeContentManifest,
          livePayloads: livePayloads,
        );
      }

      final casperDirectory = Directory(p.join(mountedRoot, 'casper'));
      final hasCasperDirectory = await casperDirectory.exists();
      final kernel = File(p.join(mountedRoot, _casperKernelRelativePath));
      final initrd = File(p.join(mountedRoot, _casperInitrdRelativePath));
      final hasCasperKernel = await _isRegularFile(kernel.path);
      final hasCasperInitrd = await _isRegularFile(initrd.path);
      if (!hasCasperDirectory && !hasCasperKernel && !hasCasperInitrd) {
        return const LinuxToGoImageInspection.unsupported(
          LinuxToGoImageIssue.unknownLayout,
        );
      }
      if (!hasCasperKernel) {
        return const LinuxToGoImageInspection.unsupported(
          LinuxToGoImageIssue.missingKernel,
        );
      }
      if (!hasCasperInitrd) {
        return const LinuxToGoImageInspection.unsupported(
          LinuxToGoImageIssue.missingInitrd,
        );
      }

      final casperPayloads = await _collectPayloads(
        mountedRoot,
        directory: 'casper',
        extensions: const {'.squashfs', '.ext2'},
      );
      if (casperPayloads.isEmpty) {
        return const LinuxToGoImageInspection.unsupported(
          LinuxToGoImageIssue.missingLivePayload,
        );
      }
      if (!await _isRegularFile(p.join(mountedRoot, _efiBootRelativePath))) {
        return const LinuxToGoImageInspection.unsupported(
          LinuxToGoImageIssue.missingX64Efi,
        );
      }

      final patchableConfigs = await _findPatchableGrubConfigs(
        mountedRoot,
        kernelRelativePath: _casperKernelRelativePath,
        requiresLiveBoot: false,
      );
      if (patchableConfigs.isEmpty) {
        return const LinuxToGoImageInspection.unsupported(
          LinuxToGoImageIssue.noPatchableBootConfig,
        );
      }

      final scan = await _buildFileScan(
        mountedRoot,
        livePayloads: casperPayloads,
        criticalBootPaths: [
          _efiBootRelativePath,
          _casperKernelRelativePath,
          _casperInitrdRelativePath,
          ...patchableConfigs.map((config) => config.relativePath),
        ],
        sourceSizeBytes: sourceSizeBytes,
        includeContentManifest: includeContentManifest,
      );
      if (scan.largestBootFileBytes > _fat32MaxFileBytes) {
        return const LinuxToGoImageInspection.unsupported(
          LinuxToGoImageIssue.bootFileTooLarge,
        );
      }

      return LinuxToGoImageInspection.supported(
        _supportedImage(
          family: LinuxToGoImageFamily.casper,
          persistenceStrategy: LinuxToGoPersistenceStrategy.casperWritableImage,
          kernelRelativePath: _casperKernelRelativePath,
          initrdRelativePath: _casperInitrdRelativePath,
          patchableConfigs: patchableConfigs,
          livePayloads: casperPayloads,
          scan: scan,
          supportsDriverStaging: true,
        ),
      );
    } catch (error) {
      return LinuxToGoImageInspection.inspectionFailed(
        LinuxToGoImageIssue.mountFailed,
        diagnostic: '$error',
      );
    }
  }

  static Future<LinuxToGoImageInspection> _inspectDebianLive({
    required String mountedRoot,
    required int? sourceSizeBytes,
    required bool includeContentManifest,
    required List<LinuxToGoPayload> livePayloads,
  }) async {
    final kernel = File(p.join(mountedRoot, _debianKernelRelativePath));
    final initrd = File(p.join(mountedRoot, _debianInitrdRelativePath));
    if (!await _isRegularFile(kernel.path)) {
      return const LinuxToGoImageInspection.unsupported(
        LinuxToGoImageIssue.missingKernel,
      );
    }
    if (!await _isRegularFile(initrd.path)) {
      return const LinuxToGoImageInspection.unsupported(
        LinuxToGoImageIssue.missingInitrd,
      );
    }
    if (!await _isRegularFile(p.join(mountedRoot, _efiBootRelativePath))) {
      return const LinuxToGoImageInspection.unsupported(
        LinuxToGoImageIssue.missingX64Efi,
      );
    }

    final patchableConfigs = await _findPatchableGrubConfigs(
      mountedRoot,
      kernelRelativePath: _debianKernelRelativePath,
      requiresLiveBoot: true,
    );
    if (patchableConfigs.isEmpty) {
      return const LinuxToGoImageInspection.unsupported(
        LinuxToGoImageIssue.noPatchableBootConfig,
      );
    }
    if (!await _debianInitrdProvidesNtfsSupport(initrd)) {
      return const LinuxToGoImageInspection.unsupported(
        LinuxToGoImageIssue.debianLiveMissingNtfsSupport,
      );
    }

    final scan = await _buildFileScan(
      mountedRoot,
      livePayloads: livePayloads,
      criticalBootPaths: [
        _efiBootRelativePath,
        _debianKernelRelativePath,
        _debianInitrdRelativePath,
        ...patchableConfigs.map((config) => config.relativePath),
      ],
      sourceSizeBytes: sourceSizeBytes,
      includeContentManifest: includeContentManifest,
    );
    if (scan.largestBootFileBytes > _fat32MaxFileBytes) {
      return const LinuxToGoImageInspection.unsupported(
        LinuxToGoImageIssue.bootFileTooLarge,
      );
    }

    return LinuxToGoImageInspection.supported(
      _supportedImage(
        family: LinuxToGoImageFamily.debianLive,
        persistenceStrategy:
            LinuxToGoPersistenceStrategy.debianPersistenceImage,
        kernelRelativePath: _debianKernelRelativePath,
        initrdRelativePath: _debianInitrdRelativePath,
        patchableConfigs: patchableConfigs,
        livePayloads: livePayloads,
        scan: scan,
        supportsDriverStaging: false,
      ),
    );
  }

  static Future<LinuxToGoImageInspection> _inspectDeepinLive({
    required String mountedRoot,
    required int? sourceSizeBytes,
    required bool includeContentManifest,
  }) async {
    final kernel = File(p.join(mountedRoot, _deepinKernelRelativePath));
    final initrd = File(p.join(mountedRoot, _deepinInitrdRelativePath));
    if (!await _isRegularFile(kernel.path)) {
      return const LinuxToGoImageInspection.unsupported(
        LinuxToGoImageIssue.missingKernel,
      );
    }
    if (!await _isRegularFile(initrd.path)) {
      return const LinuxToGoImageInspection.unsupported(
        LinuxToGoImageIssue.missingInitrd,
      );
    }
    if (!await _isRegularFile(p.join(mountedRoot, _efiBootRelativePath))) {
      return const LinuxToGoImageInspection.unsupported(
        LinuxToGoImageIssue.missingX64Efi,
      );
    }

    final livePayloads = await _collectPayloads(
      mountedRoot,
      directory: 'live',
      extensions: const {'.squ'},
      fileNamePredicate: (name) => name.startsWith('filesys'),
    );
    if (livePayloads.isEmpty) {
      return const LinuxToGoImageInspection.unsupported(
        LinuxToGoImageIssue.missingLivePayload,
      );
    }

    final patchableConfigs = await _findPatchableGrubConfigs(
      mountedRoot,
      kernelRelativePath: _deepinKernelRelativePath,
      requiresLiveBoot: true,
    );
    if (patchableConfigs.isEmpty) {
      return const LinuxToGoImageInspection.unsupported(
        LinuxToGoImageIssue.noPatchableBootConfig,
      );
    }

    // Deepin 25 stores a microcode archive followed by its opaque Live initrd,
    // so the Debian newc-only NTFS probe cannot safely inspect it. Its own
    // `filesyst.lin` marker, split Live payloads, and `boot=live` GRUB entry
    // form the bounded Deepin profile accepted here.
    final scan = await _buildFileScan(
      mountedRoot,
      livePayloads: livePayloads,
      criticalBootPaths: [
        _efiBootRelativePath,
        _deepinKernelRelativePath,
        _deepinInitrdRelativePath,
        ...patchableConfigs.map((config) => config.relativePath),
      ],
      sourceSizeBytes: sourceSizeBytes,
      includeContentManifest: includeContentManifest,
    );
    if (scan.largestBootFileBytes > _fat32MaxFileBytes) {
      return const LinuxToGoImageInspection.unsupported(
        LinuxToGoImageIssue.bootFileTooLarge,
      );
    }

    return LinuxToGoImageInspection.supported(
      _supportedImage(
        family: LinuxToGoImageFamily.deepinLive,
        persistenceStrategy:
            LinuxToGoPersistenceStrategy.debianPersistenceImage,
        kernelRelativePath: _deepinKernelRelativePath,
        initrdRelativePath: _deepinInitrdRelativePath,
        patchableConfigs: patchableConfigs,
        livePayloads: livePayloads,
        scan: scan,
        supportsDriverStaging: false,
      ),
    );
  }

  static LinuxToGoSupportedImage _supportedImage({
    required LinuxToGoImageFamily family,
    required LinuxToGoPersistenceStrategy persistenceStrategy,
    required String kernelRelativePath,
    required String initrdRelativePath,
    required List<LinuxToGoBootConfig> patchableConfigs,
    required List<LinuxToGoPayload> livePayloads,
    required _LinuxToGoFileScan scan,
    required bool supportsDriverStaging,
  }) => LinuxToGoSupportedImage(
    family: family,
    persistenceStrategy: persistenceStrategy,
    efiBootRelativePath: _efiBootRelativePath,
    kernelRelativePath: kernelRelativePath,
    initrdRelativePath: initrdRelativePath,
    patchableBootConfigs: patchableConfigs,
    livePayloads: livePayloads,
    contentFiles: scan.contentFiles,
    hasCompleteContentManifest: scan.hasCompleteContentManifest,
    totalContentBytes: scan.totalContentBytes,
    bootContentBytes: scan.bootContentBytes,
    supportsDriverStaging: supportsDriverStaging,
  );

  static Future<List<LinuxToGoPayload>> _collectPayloads(
    String mountedRoot, {
    required String directory,
    required Set<String> extensions,
    bool Function(String fileName)? fileNamePredicate,
  }) async {
    final payloadRoot = Directory(p.join(mountedRoot, directory));
    if (!await payloadRoot.exists()) return const [];

    final payloads = <LinuxToGoPayload>[];
    await for (final entity in payloadRoot.list(
      recursive: true,
      followLinks: false,
    )) {
      if (entity is! File) continue;
      final relativePath = p
          .relative(entity.path, from: mountedRoot)
          .replaceAll('\\', '/');
      final extension = p.extension(relativePath).toLowerCase();
      final fileName = p.basename(relativePath).toLowerCase();
      if (!extensions.contains(extension) ||
          (fileNamePredicate != null && !fileNamePredicate(fileName))) {
        continue;
      }
      payloads.add(
        LinuxToGoPayload(
          relativePath: relativePath,
          sizeBytes: await entity.length(),
        ),
      );
    }
    return payloads;
  }

  static Future<_LinuxToGoFileScan> _buildFileScan(
    String mountedRoot, {
    required List<LinuxToGoPayload> livePayloads,
    required List<String> criticalBootPaths,
    required int? sourceSizeBytes,
    required bool includeContentManifest,
  }) async {
    final needsFullManifest = includeContentManifest || sourceSizeBytes == null;
    final payloadPaths = livePayloads
        .map((payload) => _normalizeRelativePath(payload.relativePath))
        .toSet();
    if (needsFullManifest) {
      var totalContentBytes = 0;
      var bootContentBytes = 0;
      var largestBootFileBytes = 0;
      final contentFiles = <LinuxToGoContentFile>[];
      await for (final entity in Directory(
        mountedRoot,
      ).list(recursive: true, followLinks: false)) {
        // ISO mounts are read-only. Directory.list with followLinks disabled
        // yields Link rather than File for a link, so no extra per-file type
        // syscall is needed while walking thousands of package files.
        if (entity is! File) continue;
        final relativePath = p
            .relative(entity.path, from: mountedRoot)
            .replaceAll('\\', '/');
        final sizeBytes = await entity.length();
        contentFiles.add(
          LinuxToGoContentFile(
            relativePath: relativePath,
            sizeBytes: sizeBytes,
          ),
        );
        totalContentBytes += sizeBytes;
        if (payloadPaths.contains(_normalizeRelativePath(relativePath))) {
          continue;
        }
        bootContentBytes += sizeBytes;
        if (sizeBytes > largestBootFileBytes) {
          largestBootFileBytes = sizeBytes;
        }
      }
      return _LinuxToGoFileScan(
        totalContentBytes: totalContentBytes,
        bootContentBytes: bootContentBytes,
        largestBootFileBytes: largestBootFileBytes,
        contentFiles: contentFiles,
        hasCompleteContentManifest: true,
      );
    }

    var largestBootFileBytes = 0;
    for (final relativePath in criticalBootPaths) {
      final file = File(p.join(mountedRoot, relativePath));
      if (!await _isRegularFile(file.path)) continue;
      final sizeBytes = await file.length();
      if (sizeBytes > largestBootFileBytes) largestBootFileBytes = sizeBytes;
    }
    final payloadBytes = livePayloads.fold<int>(
      0,
      (total, payload) => total + payload.sizeBytes,
    );
    // The null case above always builds the complete manifest.
    final estimatedTotalBytes = sourceSizeBytes;
    var estimatedBootBytes = estimatedTotalBytes - payloadBytes;
    if (estimatedBootBytes < largestBootFileBytes) {
      estimatedBootBytes = largestBootFileBytes;
    }
    return _LinuxToGoFileScan(
      totalContentBytes: estimatedTotalBytes,
      bootContentBytes: estimatedBootBytes,
      largestBootFileBytes: largestBootFileBytes,
      contentFiles: const [],
      hasCompleteContentManifest: false,
    );
  }

  static Future<List<LinuxToGoBootConfig>> _findPatchableGrubConfigs(
    String mountedRoot, {
    required String kernelRelativePath,
    required bool requiresLiveBoot,
  }) async {
    final configs = <LinuxToGoBootConfig>[];
    final kernelEntry = RegExp(
      r'^\s*linux(efi)?\s+.*' +
          RegExp.escape('/$kernelRelativePath') +
          r'(?:\s|$)',
      caseSensitive: false,
    );
    final liveBootArgument = RegExp(
      r'(^|\s)boot=live(?:\s|$)',
      caseSensitive: false,
    );
    for (final relativePath in _grubConfigPaths) {
      final file = File(p.join(mountedRoot, relativePath));
      if (!await _isRegularFile(file.path)) continue;
      final text = await file.readAsString();
      final hasPatchableEntry = text
          .replaceAll('\r\n', '\n')
          .split('\n')
          .any(
            (line) =>
                kernelEntry.hasMatch(line) &&
                (!requiresLiveBoot || liveBootArgument.hasMatch(line)),
          );
      if (!hasPatchableEntry) continue;
      configs.add(
        LinuxToGoBootConfig(
          relativePath: relativePath,
          syntax: LinuxToGoBootConfigSyntax.grub,
        ),
      );
    }
    return configs;
  }

  static Future<bool> _debianInitrdProvidesNtfsSupport(File initrd) async {
    // Debian live-build uses an uncompressed newc archive for the supported
    // profile. Parse entries instead of searching arbitrary bytes so a string
    // in compressed data cannot mistakenly approve a destructive write.
    RandomAccessFile? handle;
    try {
      handle = await initrd.open(mode: FileMode.read);
      final length = await handle.length();
      var offset = 0;
      var hasNtfsSupport = false;
      var hasLiveBoot = false;
      while (offset + 110 <= length) {
        await handle.setPosition(offset);
        final header = await handle.read(110);
        if (header.length != 110 ||
            ascii.decode(header.sublist(0, 6)) != '070701') {
          return false;
        }
        final fileSize = _parseNewcHex(header, 54);
        final nameSize = _parseNewcHex(header, 94);
        if (fileSize == null || nameSize == null || nameSize <= 1) {
          return false;
        }
        final nameOffset = offset + 110;
        if (nameOffset + nameSize > length) return false;
        await handle.setPosition(nameOffset);
        final nameBytes = await handle.read(nameSize);
        if (nameBytes.length != nameSize || nameBytes.last != 0) return false;
        final name = ascii
            .decode(
              nameBytes.sublist(0, nameBytes.length - 1),
              allowInvalid: true,
            )
            .toLowerCase();
        if (name == 'trailer!!!') return hasNtfsSupport && hasLiveBoot;

        hasNtfsSupport =
            hasNtfsSupport ||
            name.contains('ntfs3.ko') ||
            name.contains('ntfs.ko') ||
            name.contains('ntfs-3g') ||
            name.contains('mount.ntfs');
        hasLiveBoot =
            hasLiveBoot ||
            name.contains('live-boot') ||
            name.contains('scripts/live') ||
            name.contains('/live/boot');

        final dataOffset = _alignNewc(nameOffset + nameSize);
        final nextOffset = _alignNewc(dataOffset + fileSize);
        if (nextOffset <= offset || nextOffset > length) return false;
        offset = nextOffset;
      }
      return false;
    } catch (_) {
      return false;
    } finally {
      await handle?.close();
    }
  }

  static int? _parseNewcHex(List<int> header, int offset) {
    if (offset + 8 > header.length) return null;
    final value = int.tryParse(
      ascii.decode(header.sublist(offset, offset + 8), allowInvalid: true),
      radix: 16,
    );
    return value == null || value < 0 ? null : value;
  }

  static int _alignNewc(int value) => (value + 3) & ~3;

  static Future<bool> _isRegularFile(String path) async =>
      await FileSystemEntity.type(path, followLinks: false) ==
      FileSystemEntityType.file;

  String _psQuote(String value) => "'${value.replaceAll("'", "''")}'";

  Future<String?> _mountIso(String isoPath) async {
    var mounted = false;
    try {
      final quotedPath = _psQuote(isoPath);
      final mount = await Process.run(
        WindowsSystemEnvironment.powerShellExecutable,
        [
          '-NoProfile',
          '-NonInteractive',
          '-ExecutionPolicy',
          'Bypass',
          '-Command',
          'Mount-DiskImage -ImagePath $quotedPath -ErrorAction Stop',
        ],
        environment: WindowsSystemEnvironment.withSystemRoot(),
      ).timeout(const Duration(seconds: 15));
      if (mount.exitCode != 0) return null;
      mounted = true;

      // Larger modern ISO files can take longer than the previous 2.5-second
      // window before Windows assigns their volume letter.
      for (var attempt = 0; attempt < 20; attempt++) {
        await Future<void>.delayed(const Duration(milliseconds: 500));
        final volume = await Process.run(
          WindowsSystemEnvironment.powerShellExecutable,
          [
            '-NoProfile',
            '-NonInteractive',
            '-ExecutionPolicy',
            'Bypass',
            '-Command',
            'Get-DiskImage -ImagePath $quotedPath | Get-Volume | '
                'Select-Object -ExpandProperty DriveLetter',
          ],
          environment: WindowsSystemEnvironment.withSystemRoot(),
        ).timeout(const Duration(seconds: 5));
        final letter = volume.stdout.toString().trim();
        if (volume.exitCode == 0 && RegExp(r'^[A-Za-z]$').hasMatch(letter)) {
          return '$letter:\\';
        }
      }
    } catch (_) {
      // A failed mount is a non-destructive inspection failure.
    }
    if (mounted) await _unmountIso(isoPath);
    return null;
  }

  Future<void> _unmountIso(String isoPath) async {
    try {
      final quotedPath = _psQuote(isoPath);
      await Process.run(
        WindowsSystemEnvironment.powerShellExecutable,
        [
          '-NoProfile',
          '-NonInteractive',
          '-ExecutionPolicy',
          'Bypass',
          '-Command',
          'Dismount-DiskImage -ImagePath $quotedPath -ErrorAction SilentlyContinue',
        ],
        environment: WindowsSystemEnvironment.withSystemRoot(),
      ).timeout(const Duration(seconds: 10));
    } catch (_) {
      // The source image was only read, so an unmount failure is diagnostic.
    }
  }

  static String _cacheKey(String path, FileStat stat) =>
      '${p.normalize(p.absolute(path))}|${stat.size}|${stat.modified.microsecondsSinceEpoch}';
}

Future<LinuxToGoImageInspection> _inspectMountedRootInWorker(
  String mountedRoot,
  int sourceSizeBytes,
) => LinuxToGoImagePreflightService.inspectMountedRoot(
  mountedRoot,
  sourceSizeBytes: sourceSizeBytes,
  includeContentManifest: true,
);

String _normalizeRelativePath(String value) =>
    value.replaceAll('\\', '/').toLowerCase();

class _LinuxToGoFileScan {
  final int totalContentBytes;
  final int bootContentBytes;
  final int largestBootFileBytes;
  final List<LinuxToGoContentFile> contentFiles;
  final bool hasCompleteContentManifest;

  _LinuxToGoFileScan({
    required this.totalContentBytes,
    required this.bootContentBytes,
    required this.largestBootFileBytes,
    required List<LinuxToGoContentFile> contentFiles,
    required this.hasCompleteContentManifest,
  }) : contentFiles = List.unmodifiable(contentFiles);
}

final linuxToGoImagePreflightProvider = Provider<LinuxToGoImagePreflight>(
  (ref) => const LinuxToGoImagePreflightService(),
);
