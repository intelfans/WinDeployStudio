import 'dart:io';

import 'package:path/path.dart' as p;

import 'linux_initrd_entry_lister.dart';
import 'windows_iso_preflight.dart';

/// Result of inspecting an ArchISO layout for the dedicated three-partition
/// Linux To Go writer.
enum LinuxArchImageStatus { supported, unsupported, inspectionFailed }

enum LinuxArchImageIssue {
  sourceNotRegularFile,
  mountFailed,
  windowsInstaller,
  unknownLayout,
  missingX64Efi,
  missingKernel,
  missingInitrd,
  missingLivePayload,
  bootFileTooLarge,
  noEligibleBootEntry,
  initrdUnreadable,
  initrdCapabilitiesMissing,
}

extension LinuxArchImageIssueDetails on LinuxArchImageIssue {
  String get code => switch (this) {
    LinuxArchImageIssue.sourceNotRegularFile => 'arch_source_not_regular_file',
    LinuxArchImageIssue.mountFailed => 'arch_mount_preflight_failed',
    LinuxArchImageIssue.windowsInstaller => 'arch_windows_installer',
    LinuxArchImageIssue.unknownLayout => 'arch_unsupported_iso',
    LinuxArchImageIssue.missingX64Efi => 'arch_missing_x64_efi',
    LinuxArchImageIssue.missingKernel => 'arch_missing_live_kernel',
    LinuxArchImageIssue.missingInitrd => 'arch_missing_live_initrd',
    LinuxArchImageIssue.missingLivePayload => 'arch_missing_live_payload',
    LinuxArchImageIssue.bootFileTooLarge => 'arch_boot_file_too_large',
    LinuxArchImageIssue.noEligibleBootEntry => 'arch_boot_config_unsupported',
    LinuxArchImageIssue.initrdUnreadable => 'arch_initrd_unreadable',
    LinuxArchImageIssue.initrdCapabilitiesMissing =>
      'arch_initrd_capabilities_missing',
  };
}

class LinuxArchBootEntry {
  final String relativePath;
  final String kernelRelativePath;
  final String initrdRelativePath;

  const LinuxArchBootEntry({
    required this.relativePath,
    required this.kernelRelativePath,
    required this.initrdRelativePath,
  });
}

class LinuxArchInitrdCapabilities {
  final bool hasArchisoHook;
  final bool hasNtfsSupport;
  final bool hasExt4Support;
  final bool hasOverlaySupport;

  const LinuxArchInitrdCapabilities({
    required this.hasArchisoHook,
    required this.hasNtfsSupport,
    required this.hasExt4Support,
    required this.hasOverlaySupport,
  });

  bool get isComplete => missingCapabilities.isEmpty;

  List<String> get missingCapabilities => [
    if (!hasArchisoHook) 'archiso hook',
    if (!hasNtfsSupport) 'NTFS',
    if (!hasExt4Support) 'ext4',
    if (!hasOverlaySupport) 'OverlayFS',
  ];
}

class LinuxArchSupportedImage {
  final LinuxArchBootEntry bootEntry;
  final String efiBootRelativePath;
  final String livePayloadRelativePath;
  final int livePayloadBytes;
  final int totalContentBytes;
  final int bootContentBytes;
  final LinuxArchInitrdCapabilities initrdCapabilities;

  const LinuxArchSupportedImage({
    required this.bootEntry,
    required this.efiBootRelativePath,
    required this.livePayloadRelativePath,
    required this.livePayloadBytes,
    required this.totalContentBytes,
    required this.bootContentBytes,
    required this.initrdCapabilities,
  });
}

class LinuxArchImageInspection {
  final LinuxArchImageStatus status;
  final LinuxArchImageIssue? issue;
  final String? diagnostic;
  final LinuxArchSupportedImage? image;

  const LinuxArchImageInspection._({
    required this.status,
    this.issue,
    this.diagnostic,
    this.image,
  });

  factory LinuxArchImageInspection.supported(LinuxArchSupportedImage image) =>
      LinuxArchImageInspection._(
        status: LinuxArchImageStatus.supported,
        image: image,
      );

  const LinuxArchImageInspection.unsupported(
    LinuxArchImageIssue issue, {
    String? diagnostic,
  }) : this._(
         status: LinuxArchImageStatus.unsupported,
         issue: issue,
         diagnostic: diagnostic,
       );

  const LinuxArchImageInspection.inspectionFailed(
    LinuxArchImageIssue issue, {
    String? diagnostic,
  }) : this._(
         status: LinuxArchImageStatus.inspectionFailed,
         issue: issue,
         diagnostic: diagnostic,
       );

  bool get canCreate =>
      status == LinuxArchImageStatus.supported && image != null;
}

abstract interface class LinuxArchImagePreflight {
  Future<LinuxArchImageInspection> inspect(String isoPath);
}

/// Strict structural checker for the supported ArchISO profile.
///
/// It is intentionally mounted-root only. The owning Linux To Go preflight
/// already controls ISO mounting and does the same check again immediately
/// before a destructive disk operation.
class LinuxArchImagePreflightService implements LinuxArchImagePreflight {
  static const _fat32MaxFileBytes = 0xffffffff;
  static const _efiBootRelativePath = 'EFI/BOOT/BOOTX64.EFI';
  static const _kernelRelativePath = 'arch/boot/x86_64/vmlinuz-linux';
  static const _initrdRelativePath = 'arch/boot/x86_64/initramfs-linux.img';
  static const _livePayloadRelativePath = 'arch/x86_64/airootfs.sfs';
  static const _loaderEntriesRelativePath = 'loader/entries';
  static const _maximumBootConfigBytes = 1024 * 1024;
  static const _maximumBootConfigFiles = 64;

  final LinuxInitrdEntryLister initrdEntryLister;

  const LinuxArchImagePreflightService({
    this.initrdEntryLister = const LinuxInitrdEntryListerService(),
  });

  @override
  Future<LinuxArchImageInspection> inspect(String isoPath) async {
    if (await FileSystemEntity.type(isoPath, followLinks: false) !=
        FileSystemEntityType.file) {
      return const LinuxArchImageInspection.unsupported(
        LinuxArchImageIssue.sourceNotRegularFile,
      );
    }
    final mountPoint = await _mountIso(isoPath);
    if (mountPoint == null) {
      return const LinuxArchImageInspection.inspectionFailed(
        LinuxArchImageIssue.mountFailed,
      );
    }
    try {
      return await inspectMountedRoot(
        mountPoint,
        initrdEntryLister: initrdEntryLister,
      );
    } catch (error) {
      return LinuxArchImageInspection.inspectionFailed(
        LinuxArchImageIssue.mountFailed,
        diagnostic: '$error',
      );
    } finally {
      await _unmountIso(isoPath);
    }
  }

  static Future<LinuxArchImageInspection> inspectMountedRoot(
    String mountedRoot, {
    LinuxInitrdEntryLister initrdEntryLister =
        const LinuxInitrdEntryListerService(),
  }) async {
    try {
      if (!await Directory(mountedRoot).exists()) {
        return const LinuxArchImageInspection.inspectionFailed(
          LinuxArchImageIssue.mountFailed,
          diagnostic: 'The mounted ISO root is not available.',
        );
      }
      final windowsLayout = await WindowsIsoLayoutInspector.inspectMountedRoot(
        mountedRoot,
      );
      if (windowsLayout.isValid) {
        return const LinuxArchImageInspection.unsupported(
          LinuxArchImageIssue.windowsInstaller,
        );
      }

      final archRoot = Directory(p.join(mountedRoot, 'arch'));
      if (!await archRoot.exists()) {
        return const LinuxArchImageInspection.unsupported(
          LinuxArchImageIssue.unknownLayout,
        );
      }
      if (!await _isRegularFile(p.join(mountedRoot, _efiBootRelativePath))) {
        return const LinuxArchImageInspection.unsupported(
          LinuxArchImageIssue.missingX64Efi,
        );
      }
      if (!await _isRegularFile(p.join(mountedRoot, _kernelRelativePath))) {
        return const LinuxArchImageInspection.unsupported(
          LinuxArchImageIssue.missingKernel,
        );
      }
      final initrd = File(p.join(mountedRoot, _initrdRelativePath));
      if (!await _isRegularFile(initrd.path)) {
        return const LinuxArchImageInspection.unsupported(
          LinuxArchImageIssue.missingInitrd,
        );
      }
      final livePayload = File(p.join(mountedRoot, _livePayloadRelativePath));
      if (!await _isRegularFile(livePayload.path)) {
        return const LinuxArchImageInspection.unsupported(
          LinuxArchImageIssue.missingLivePayload,
        );
      }

      final bootEntry = await _findEligibleBootEntry(mountedRoot);
      if (bootEntry == null) {
        return const LinuxArchImageInspection.unsupported(
          LinuxArchImageIssue.noEligibleBootEntry,
        );
      }

      final listing = await initrdEntryLister.list(initrd);
      if (!listing.success) {
        return LinuxArchImageInspection.unsupported(
          LinuxArchImageIssue.initrdUnreadable,
          diagnostic: listing.diagnostic,
        );
      }
      final capabilities = _capabilitiesFromEntries(listing.entries);
      if (!capabilities.isComplete) {
        return LinuxArchImageInspection.unsupported(
          LinuxArchImageIssue.initrdCapabilitiesMissing,
          diagnostic: capabilities.missingCapabilities.join(', '),
        );
      }

      final scan = await _scanFiles(mountedRoot);
      if (scan.largestBootFileBytes > _fat32MaxFileBytes) {
        return const LinuxArchImageInspection.unsupported(
          LinuxArchImageIssue.bootFileTooLarge,
        );
      }

      return LinuxArchImageInspection.supported(
        LinuxArchSupportedImage(
          bootEntry: bootEntry,
          efiBootRelativePath: _efiBootRelativePath,
          livePayloadRelativePath: _livePayloadRelativePath,
          livePayloadBytes: await livePayload.length(),
          totalContentBytes: scan.totalContentBytes,
          bootContentBytes: scan.bootContentBytes,
          initrdCapabilities: capabilities,
        ),
      );
    } catch (error) {
      return LinuxArchImageInspection.inspectionFailed(
        LinuxArchImageIssue.mountFailed,
        diagnostic: '$error',
      );
    }
  }

  static Future<_ArchFileScan> _scanFiles(String mountedRoot) async {
    var totalContentBytes = 0;
    var bootContentBytes = 0;
    var largestBootFileBytes = 0;
    await for (final entity in Directory(
      mountedRoot,
    ).list(recursive: true, followLinks: false)) {
      if (entity is! File || !await _isRegularFile(entity.path)) continue;
      final size = await entity.length();
      totalContentBytes += size;
      final relative = p
          .relative(entity.path, from: mountedRoot)
          .replaceAll('\\', '/')
          .toLowerCase();
      if (relative == _livePayloadRelativePath) continue;
      bootContentBytes += size;
      if (size > largestBootFileBytes) largestBootFileBytes = size;
    }
    return _ArchFileScan(
      totalContentBytes: totalContentBytes,
      bootContentBytes: bootContentBytes,
      largestBootFileBytes: largestBootFileBytes,
    );
  }

  static Future<LinuxArchBootEntry?> _findEligibleBootEntry(
    String mountedRoot,
  ) async {
    final directory = Directory(
      p.join(mountedRoot, _loaderEntriesRelativePath),
    );
    if (!await directory.exists()) return null;
    var inspected = 0;
    await for (final entity in directory.list(followLinks: false)) {
      if (entity is! File ||
          ++inspected > _maximumBootConfigFiles ||
          !entity.path.toLowerCase().endsWith('.conf') ||
          !await _isRegularFile(entity.path)) {
        continue;
      }
      if (await entity.length() > _maximumBootConfigBytes) continue;
      String content;
      try {
        content = await entity.readAsString();
      } catch (_) {
        continue;
      }
      final relative = p
          .relative(entity.path, from: mountedRoot)
          .replaceAll('\\', '/');
      final candidate = _parseEligibleBootEntry(content, relative);
      if (candidate != null) return candidate;
    }
    return null;
  }

  static LinuxArchBootEntry? _parseEligibleBootEntry(
    String content,
    String relativePath,
  ) {
    String? kernel;
    String? initrd;
    String? options;
    for (final rawLine in content.replaceAll('\r\n', '\n').split('\n')) {
      final line = rawLine.trim();
      if (line.isEmpty || line.startsWith('#')) continue;
      final match = RegExp(
        r'^(linux|initrd|options)\s+(\S(?:.*\S)?)$',
      ).firstMatch(line);
      if (match == null) continue;
      final key = match.group(1)!;
      final value = match.group(2)!;
      switch (key) {
        case 'linux':
          if (kernel != null) return null;
          kernel = _normalizeStaticPath(value);
        case 'initrd':
          if (initrd != null) return null;
          initrd = _normalizeStaticPath(value);
        case 'options':
          if (options != null) return null;
          options = value;
      }
    }
    if (kernel != _kernelRelativePath || initrd != _initrdRelativePath) {
      return null;
    }
    if (!_hasSafeArchisoOptions(options)) return null;
    return LinuxArchBootEntry(
      relativePath: relativePath,
      kernelRelativePath: kernel!,
      initrdRelativePath: initrd!,
    );
  }

  static bool _hasSafeArchisoOptions(String? options) {
    if (options == null ||
        options.isEmpty ||
        options.contains(RegExp(r'''["'`$\\]'''))) {
      return false;
    }
    final tokens = options
        .split(RegExp(r'\s+'))
        .where((token) => token.isNotEmpty)
        .toList(growable: false);
    final baseDirs = tokens
        .where((token) => token.toLowerCase().startsWith('archisobasedir='))
        .toList(growable: false);
    final devices = tokens
        .where((token) => token.toLowerCase().startsWith('archisodevice='))
        .toList(growable: false);
    if (baseDirs.length != 1 ||
        baseDirs.single.toLowerCase() != 'archisobasedir=arch' ||
        devices.length != 1 ||
        devices.single.length == 'archisodevice='.length) {
      return false;
    }
    return !tokens.any((token) {
      final normalized = token.toLowerCase();
      return normalized.startsWith('cow_device=') ||
          normalized.startsWith('cow_label=') ||
          normalized.startsWith('cow_directory=') ||
          normalized == 'copytoram' ||
          normalized.startsWith('copytoram=');
    });
  }

  static String? _normalizeStaticPath(String value) {
    if (!RegExp(r'^/[A-Za-z0-9._/+\-]+$').hasMatch(value)) return null;
    final normalized = value.substring(1);
    if (normalized.isEmpty ||
        normalized.split('/').any((segment) => segment == '..')) {
      return null;
    }
    return normalized;
  }

  static LinuxArchInitrdCapabilities _capabilitiesFromEntries(
    Iterable<String> entries,
  ) {
    var hasArchisoHook = false;
    var hasNtfsSupport = false;
    var hasExt4Support = false;
    var hasOverlaySupport = false;
    for (final rawEntry in entries) {
      final entry = rawEntry.replaceAll('\\', '/').toLowerCase();
      hasArchisoHook =
          hasArchisoHook ||
          entry == 'hooks/archiso' ||
          entry.endsWith('/hooks/archiso');
      hasNtfsSupport =
          hasNtfsSupport ||
          entry.contains('/ntfs3.ko') ||
          entry.contains('/ntfs.ko');
      hasExt4Support = hasExt4Support || entry.contains('/ext4.ko');
      hasOverlaySupport = hasOverlaySupport || entry.contains('/overlay.ko');
    }
    return LinuxArchInitrdCapabilities(
      hasArchisoHook: hasArchisoHook,
      hasNtfsSupport: hasNtfsSupport,
      hasExt4Support: hasExt4Support,
      hasOverlaySupport: hasOverlaySupport,
    );
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
      // The source image is only inspected, never changed.
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
      // A failed read-only mount cleanup is non-destructive.
    }
  }
}

class _ArchFileScan {
  final int totalContentBytes;
  final int bootContentBytes;
  final int largestBootFileBytes;

  const _ArchFileScan({
    required this.totalContentBytes,
    required this.bootContentBytes,
    required this.largestBootFileBytes,
  });
}
