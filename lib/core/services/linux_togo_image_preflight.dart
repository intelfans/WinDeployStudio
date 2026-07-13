import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import 'windows_iso_preflight.dart';

/// The result of determining whether an ISO can create a persistent Linux To
/// Go workspace without relying on its filename.
enum LinuxToGoImageStatus { supported, unsupported, inspectionFailed }

/// A supported Live image layout. More layouts can be added without making
/// callers infer behavior from individual files.
enum LinuxToGoImageFamily { casper, debianLive }

/// The persistence layout required by an image family.
enum LinuxToGoPersistenceStrategy {
  casperWritableImage,
  debianPersistencePartition,
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
  debianLiveUnsupported,
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
    LinuxToGoImageIssue.debianLiveUnsupported =>
      'linux_togo_debian_live_unsupported',
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

/// A live filesystem payload copied only to the writable data partition.
class LinuxToGoPayload {
  final String relativePath;
  final int sizeBytes;

  const LinuxToGoPayload({required this.relativePath, required this.sizeBytes});
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
    required this.totalContentBytes,
    required this.bootContentBytes,
    required this.supportsDriverStaging,
  }) : patchableBootConfigs = List.unmodifiable(patchableBootConfigs),
       livePayloads = List.unmodifiable(livePayloads);

  List<String> get patchableBootConfigPaths => List.unmodifiable(
    patchableBootConfigs.map((config) => config.relativePath),
  );
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

/// Windows implementation which mounts an ISO, inspects its root, and always
/// attempts to unmount it afterwards.
class LinuxToGoImagePreflightService implements LinuxToGoImagePreflight {
  static const int _fat32MaxFileBytes = 0xffffffff;
  static const String _efiBootRelativePath = 'EFI/BOOT/BOOTX64.EFI';
  static const String _casperKernelRelativePath = 'casper/vmlinuz';
  static const String _casperInitrdRelativePath = 'casper/initrd';
  static const List<String> _grubConfigPaths = [
    'boot/grub/grub.cfg',
    'boot/grub/loopback.cfg',
  ];

  const LinuxToGoImagePreflightService();

  @override
  Future<LinuxToGoImageInspection> inspect(String isoPath) async {
    final source = File(isoPath);
    if (await FileSystemEntity.type(source.path, followLinks: false) !=
        FileSystemEntityType.file) {
      return const LinuxToGoImageInspection.unsupported(
        LinuxToGoImageIssue.sourceNotRegularFile,
      );
    }

    final mountPoint = await _mountIso(isoPath);
    if (mountPoint == null) {
      return const LinuxToGoImageInspection.inspectionFailed(
        LinuxToGoImageIssue.mountFailed,
      );
    }

    try {
      return inspectMountedRoot(mountPoint);
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
  static Future<LinuxToGoImageInspection> inspectMountedRoot(
    String mountedRoot,
  ) async {
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

      final scan = await _scanFiles(mountedRoot);
      if (await _looksLikeDebianLive(mountedRoot, scan)) {
        return const LinuxToGoImageInspection.unsupported(
          LinuxToGoImageIssue.debianLiveUnsupported,
        );
      }

      final kernel = File(p.join(mountedRoot, _casperKernelRelativePath));
      final initrd = File(p.join(mountedRoot, _casperInitrdRelativePath));
      final hasCasperKernel = await _isRegularFile(kernel.path);
      final hasCasperInitrd = await _isRegularFile(initrd.path);
      final hasCasperDirectory = await Directory(
        p.join(mountedRoot, 'casper'),
      ).exists();

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

      if (!await _isRegularFile(p.join(mountedRoot, _efiBootRelativePath))) {
        return const LinuxToGoImageInspection.unsupported(
          LinuxToGoImageIssue.missingX64Efi,
        );
      }
      if (scan.livePayloads.isEmpty) {
        return const LinuxToGoImageInspection.unsupported(
          LinuxToGoImageIssue.missingLivePayload,
        );
      }
      if (scan.largestBootFileBytes > _fat32MaxFileBytes) {
        return const LinuxToGoImageInspection.unsupported(
          LinuxToGoImageIssue.bootFileTooLarge,
        );
      }

      final patchableConfigs = await _findPatchableCasperGrubConfigs(
        mountedRoot,
      );
      if (patchableConfigs.isEmpty) {
        return const LinuxToGoImageInspection.unsupported(
          LinuxToGoImageIssue.noPatchableBootConfig,
        );
      }

      return LinuxToGoImageInspection.supported(
        LinuxToGoSupportedImage(
          family: LinuxToGoImageFamily.casper,
          persistenceStrategy: LinuxToGoPersistenceStrategy.casperWritableImage,
          efiBootRelativePath: _efiBootRelativePath,
          kernelRelativePath: _casperKernelRelativePath,
          initrdRelativePath: _casperInitrdRelativePath,
          patchableBootConfigs: patchableConfigs,
          livePayloads: scan.livePayloads,
          totalContentBytes: scan.totalContentBytes,
          bootContentBytes: scan.bootContentBytes,
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

  static Future<_LinuxToGoFileScan> _scanFiles(String mountedRoot) async {
    var totalContentBytes = 0;
    var bootContentBytes = 0;
    var largestBootFileBytes = 0;
    final livePayloads = <LinuxToGoPayload>[];

    await for (final entity in Directory(
      mountedRoot,
    ).list(recursive: true, followLinks: false)) {
      if (entity is! File) continue;
      if (!await _isRegularFile(entity.path)) continue;

      final sizeBytes = await entity.length();
      totalContentBytes += sizeBytes;
      final relativePath = p
          .relative(entity.path, from: mountedRoot)
          .replaceAll('\\', '/');
      final extension = p.extension(relativePath).toLowerCase();
      if (extension == '.squashfs' || extension == '.ext2') {
        livePayloads.add(
          LinuxToGoPayload(relativePath: relativePath, sizeBytes: sizeBytes),
        );
        continue;
      }

      bootContentBytes += sizeBytes;
      if (sizeBytes > largestBootFileBytes) largestBootFileBytes = sizeBytes;
    }

    return _LinuxToGoFileScan(
      totalContentBytes: totalContentBytes,
      bootContentBytes: bootContentBytes,
      largestBootFileBytes: largestBootFileBytes,
      livePayloads: livePayloads,
    );
  }

  static Future<bool> _looksLikeDebianLive(
    String mountedRoot,
    _LinuxToGoFileScan scan,
  ) async {
    final liveRoot = Directory(p.join(mountedRoot, 'live'));
    if (!await liveRoot.exists()) return false;

    final hasPayload = scan.livePayloads.any(
      (payload) => payload.relativePath.toLowerCase().startsWith('live/'),
    );
    if (!hasPayload) return false;

    final hasKernel = await _isRegularFile(
      p.join(mountedRoot, 'live', 'vmlinuz'),
    );
    final hasInitrd = await _isRegularFile(
      p.join(mountedRoot, 'live', 'initrd.img'),
    );
    return hasKernel || hasInitrd;
  }

  static Future<List<LinuxToGoBootConfig>> _findPatchableCasperGrubConfigs(
    String mountedRoot,
  ) async {
    final configs = <LinuxToGoBootConfig>[];
    final casperEntry = RegExp(
      r'^\s*linux(efi)?\s+.*\/casper\/vmlinuz(?:\s|$)',
      caseSensitive: false,
      multiLine: true,
    );
    for (final relativePath in _grubConfigPaths) {
      final file = File(p.join(mountedRoot, relativePath));
      if (!await _isRegularFile(file.path)) continue;
      final text = await file.readAsString();
      if (!casperEntry.hasMatch(text)) continue;
      configs.add(
        LinuxToGoBootConfig(
          relativePath: relativePath,
          syntax: LinuxToGoBootConfigSyntax.grub,
        ),
      );
    }
    return configs;
  }

  static Future<bool> _isRegularFile(String path) async =>
      await FileSystemEntity.type(path, followLinks: false) ==
      FileSystemEntityType.file;

  String _psQuote(String value) => "'${value.replaceAll("'", "''")}'";

  Future<String?> _mountIso(String isoPath) async {
    try {
      final quotedPath = _psQuote(isoPath);
      final mount = await Process.run('powershell', [
        '-NoProfile',
        '-NonInteractive',
        '-ExecutionPolicy',
        'Bypass',
        '-Command',
        'Mount-DiskImage -ImagePath $quotedPath -ErrorAction Stop',
      ]).timeout(const Duration(seconds: 15));
      if (mount.exitCode != 0) return null;

      for (var attempt = 0; attempt < 5; attempt++) {
        await Future<void>.delayed(const Duration(milliseconds: 500));
        final volume = await Process.run('powershell', [
          '-NoProfile',
          '-NonInteractive',
          '-ExecutionPolicy',
          'Bypass',
          '-Command',
          'Get-DiskImage -ImagePath $quotedPath | Get-Volume | '
              'Select-Object -ExpandProperty DriveLetter',
        ]);
        final letter = volume.stdout.toString().trim();
        if (volume.exitCode == 0 && letter.isNotEmpty) return '$letter:\\';
      }
    } catch (_) {
      // A failed mount is a non-destructive inspection failure.
    }
    return null;
  }

  Future<void> _unmountIso(String isoPath) async {
    try {
      final quotedPath = _psQuote(isoPath);
      await Process.run('powershell', [
        '-NoProfile',
        '-NonInteractive',
        '-ExecutionPolicy',
        'Bypass',
        '-Command',
        'Dismount-DiskImage -ImagePath $quotedPath -ErrorAction SilentlyContinue',
      ]).timeout(const Duration(seconds: 10));
    } catch (_) {
      // The source image was only read, so an unmount failure is diagnostic.
    }
  }
}

class _LinuxToGoFileScan {
  final int totalContentBytes;
  final int bootContentBytes;
  final int largestBootFileBytes;
  final List<LinuxToGoPayload> livePayloads;

  _LinuxToGoFileScan({
    required this.totalContentBytes,
    required this.bootContentBytes,
    required this.largestBootFileBytes,
    required List<LinuxToGoPayload> livePayloads,
  }) : livePayloads = List.unmodifiable(livePayloads);
}

final linuxToGoImagePreflightProvider = Provider<LinuxToGoImagePreflight>(
  (ref) => const LinuxToGoImagePreflightService(),
);
