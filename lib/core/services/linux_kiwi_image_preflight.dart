import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import 'linux_initrd_entry_lister.dart';
import 'linux_media_preflight.dart';
import 'windows_iso_preflight.dart';

/// The non-destructive result of checking an ISO for KIWI's raw ISOHybrid
/// persistence contract.
enum LinuxKiwiImageStatus { supported, unsupported, inspectionFailed }

/// Reasons a KIWI ISO is not eligible for the raw persistent-write profile.
///
/// The raw profile deliberately accepts a narrow subset: it preserves the ISO
/// byte-for-byte and relies on KIWI's already-present initrd code to create its
/// COW partition on first boot. It never rewrites GRUB inside the ISO.
enum LinuxKiwiImageIssue {
  sourceNotRegularFile,
  isoHybridInvalid,
  mountFailed,
  windowsInstaller,
  missingX64Efi,
  missingLivePayload,
  noEligibleLiveBootEntry,
  missingKernel,
  missingInitrd,
  initrdUnreadable,
  initrdCapabilitiesMissing,
}

extension LinuxKiwiImageIssueDetails on LinuxKiwiImageIssue {
  /// Stable, non-localized reason code for logs and a later UI integration.
  String get code => switch (this) {
    LinuxKiwiImageIssue.sourceNotRegularFile => 'kiwi_source_not_regular_file',
    LinuxKiwiImageIssue.isoHybridInvalid => 'kiwi_iso_hybrid_invalid',
    LinuxKiwiImageIssue.mountFailed => 'kiwi_mount_preflight_failed',
    LinuxKiwiImageIssue.windowsInstaller => 'kiwi_windows_installer',
    LinuxKiwiImageIssue.missingX64Efi => 'kiwi_missing_x64_efi',
    LinuxKiwiImageIssue.missingLivePayload => 'kiwi_missing_live_payload',
    LinuxKiwiImageIssue.noEligibleLiveBootEntry =>
      'kiwi_no_eligible_live_boot_entry',
    LinuxKiwiImageIssue.missingKernel => 'kiwi_missing_live_kernel',
    LinuxKiwiImageIssue.missingInitrd => 'kiwi_missing_live_initrd',
    LinuxKiwiImageIssue.initrdUnreadable => 'kiwi_initrd_unreadable',
    LinuxKiwiImageIssue.initrdCapabilitiesMissing =>
      'kiwi_initrd_capabilities_missing',
  };
}

/// A statically verified normal KIWI Live boot entry.
class LinuxKiwiBootEntry {
  final String bootConfigRelativePath;
  final String kernelRelativePath;
  final String initrdRelativePath;
  final String liveCdLabel;

  const LinuxKiwiBootEntry({
    required this.bootConfigRelativePath,
    required this.kernelRelativePath,
    required this.initrdRelativePath,
    required this.liveCdLabel,
  });
}

/// The initrd capabilities that KIWI's disk-boot persistence path needs.
///
/// Values are derived only from parsed CPIO entry names. The service never
/// approves an initrd based on arbitrary bytes in compressed or malformed data.
class LinuxKiwiInitrdCapabilities {
  final bool hasKiwiLiveRoot;
  final bool hasKiwiLiveLibrary;
  final bool hasKiwiLiveParser;
  final bool hasFdisk;
  final bool hasPartx;
  final bool hasMkfsExt4;
  final bool hasMount;
  final bool hasBlkid;
  final bool hasOverlaySupport;
  final bool hasExt4Support;
  final bool hasIso9660Support;

  const LinuxKiwiInitrdCapabilities({
    required this.hasKiwiLiveRoot,
    required this.hasKiwiLiveLibrary,
    required this.hasKiwiLiveParser,
    required this.hasFdisk,
    required this.hasPartx,
    required this.hasMkfsExt4,
    required this.hasMount,
    required this.hasBlkid,
    required this.hasOverlaySupport,
    required this.hasExt4Support,
    required this.hasIso9660Support,
  });

  bool get isComplete => missingCapabilities.isEmpty;

  List<String> get missingCapabilities => [
    if (!hasKiwiLiveRoot) 'kiwi-live-root',
    if (!hasKiwiLiveLibrary) 'kiwi-live-lib',
    if (!hasKiwiLiveParser) 'parse-kiwi-live',
    if (!hasFdisk) 'fdisk',
    if (!hasPartx) 'partx',
    if (!hasMkfsExt4) 'mkfs.ext4',
    if (!hasMount) 'mount',
    if (!hasBlkid) 'blkid',
    if (!hasOverlaySupport) 'overlayfs',
    if (!hasExt4Support) 'ext4',
    if (!hasIso9660Support) 'iso9660',
  ];
}

/// Immutable data required by a later raw KIWI writer integration.
class LinuxKiwiSupportedImage {
  final LinuxKiwiBootEntry bootEntry;
  final String livePayloadRelativePath;
  final int livePayloadBytes;
  final LinuxKiwiInitrdCapabilities initrdCapabilities;

  const LinuxKiwiSupportedImage({
    required this.bootEntry,
    required this.livePayloadRelativePath,
    required this.livePayloadBytes,
    required this.initrdCapabilities,
  });
}

class LinuxKiwiImageInspection {
  final LinuxKiwiImageStatus status;
  final LinuxKiwiImageIssue? issue;
  final String? diagnostic;
  final LinuxKiwiSupportedImage? image;

  const LinuxKiwiImageInspection._({
    required this.status,
    this.issue,
    this.diagnostic,
    this.image,
  });

  factory LinuxKiwiImageInspection.supported(LinuxKiwiSupportedImage image) =>
      LinuxKiwiImageInspection._(
        status: LinuxKiwiImageStatus.supported,
        image: image,
      );

  const LinuxKiwiImageInspection.unsupported(
    LinuxKiwiImageIssue issue, {
    String? diagnostic,
  }) : this._(
         status: LinuxKiwiImageStatus.unsupported,
         issue: issue,
         diagnostic: diagnostic,
       );

  const LinuxKiwiImageInspection.inspectionFailed(
    LinuxKiwiImageIssue issue, {
    String? diagnostic,
  }) : this._(
         status: LinuxKiwiImageStatus.inspectionFailed,
         issue: issue,
         diagnostic: diagnostic,
       );

  bool get canCreate =>
      status == LinuxKiwiImageStatus.supported && image != null;
}

abstract interface class LinuxKiwiImagePreflight {
  Future<LinuxKiwiImageInspection> inspect(String isoPath);
}

/// Read-only inspector for KIWI ISOHybrid images that already declare KIWI's
/// persistent OverlayFS mode in their normal Live boot entry.
class LinuxKiwiImagePreflightService implements LinuxKiwiImagePreflight {
  static const String _efiBootRelativePath = 'EFI/BOOT/BOOTX64.EFI';
  static const String _livePayloadRelativePath = 'LiveOS/squashfs.img';
  static const List<String> _grubConfigPaths = [
    'boot/grub2/grub.cfg',
    'boot/grub/grub.cfg',
    'boot/grub/loopback.cfg',
    'EFI/BOOT/grub.cfg',
  ];
  static const int _maxCpioEntryNameBytes = 16 * 1024;

  final LinuxInitrdEntryLister initrdEntryLister;

  const LinuxKiwiImagePreflightService({
    this.initrdEntryLister = const LinuxInitrdEntryListerService(),
  });

  @override
  Future<LinuxKiwiImageInspection> inspect(String isoPath) async {
    final source = File(isoPath);
    if (await FileSystemEntity.type(source.path, followLinks: false) !=
        FileSystemEntityType.file) {
      return const LinuxKiwiImageInspection.unsupported(
        LinuxKiwiImageIssue.sourceNotRegularFile,
      );
    }

    final hybrid = await LinuxIsoHybridInspector.inspect(isoPath);
    if (!hybrid.isValid) {
      return LinuxKiwiImageInspection.unsupported(
        LinuxKiwiImageIssue.isoHybridInvalid,
        diagnostic: hybrid.error,
      );
    }

    final mountPoint = await _mountIso(isoPath);
    if (mountPoint == null) {
      return const LinuxKiwiImageInspection.inspectionFailed(
        LinuxKiwiImageIssue.mountFailed,
      );
    }

    try {
      return await inspectMountedRoot(
        mountPoint,
        initrdEntryLister: initrdEntryLister,
      );
    } catch (error) {
      return LinuxKiwiImageInspection.inspectionFailed(
        LinuxKiwiImageIssue.mountFailed,
        diagnostic: '$error',
      );
    } finally {
      await _unmountIso(isoPath);
    }
  }

  /// Checks the ISO filesystem tree after ISOHybrid validation has happened.
  ///
  /// This is intentionally public for fixture-based tests. Production callers
  /// must call [inspect] so the raw ISOHybrid structure is checked first.
  static Future<LinuxKiwiImageInspection> inspectMountedRoot(
    String mountedRoot, {
    LinuxInitrdEntryLister initrdEntryLister =
        const LinuxInitrdEntryListerService(),
  }) async {
    final root = Directory(mountedRoot);
    if (!await root.exists()) {
      return const LinuxKiwiImageInspection.inspectionFailed(
        LinuxKiwiImageIssue.mountFailed,
        diagnostic: 'The mounted ISO root is not available.',
      );
    }

    final windowsLayout = await WindowsIsoLayoutInspector.inspectMountedRoot(
      mountedRoot,
    );
    if (windowsLayout.isValid) {
      return const LinuxKiwiImageInspection.unsupported(
        LinuxKiwiImageIssue.windowsInstaller,
      );
    }

    if (!await _isRegularFile(p.join(mountedRoot, _efiBootRelativePath))) {
      return const LinuxKiwiImageInspection.unsupported(
        LinuxKiwiImageIssue.missingX64Efi,
      );
    }

    final livePayload = File(p.join(mountedRoot, _livePayloadRelativePath));
    if (!await _isRegularFile(livePayload.path)) {
      return const LinuxKiwiImageInspection.unsupported(
        LinuxKiwiImageIssue.missingLivePayload,
      );
    }

    final candidates = await _findEligibleBootEntries(mountedRoot);
    if (candidates.isEmpty) {
      return const LinuxKiwiImageInspection.unsupported(
        LinuxKiwiImageIssue.noEligibleLiveBootEntry,
      );
    }

    LinuxKiwiImageInspection? firstFailure;
    for (final candidate in candidates) {
      final kernel = File(p.join(mountedRoot, candidate.kernelRelativePath));
      if (!await _isRegularFile(kernel.path)) {
        firstFailure ??= LinuxKiwiImageInspection.unsupported(
          LinuxKiwiImageIssue.missingKernel,
          diagnostic: candidate.kernelRelativePath,
        );
        continue;
      }

      final initrd = File(p.join(mountedRoot, candidate.initrdRelativePath));
      if (!await _isRegularFile(initrd.path)) {
        firstFailure ??= LinuxKiwiImageInspection.unsupported(
          LinuxKiwiImageIssue.missingInitrd,
          diagnostic: candidate.initrdRelativePath,
        );
        continue;
      }

      final initrdResult = await _readInitrdCapabilities(
        initrd,
        initrdEntryLister,
      );
      final capabilities = initrdResult.capabilities;
      if (capabilities == null) {
        firstFailure ??= LinuxKiwiImageInspection.unsupported(
          LinuxKiwiImageIssue.initrdUnreadable,
          diagnostic: initrdResult.diagnostic,
        );
        continue;
      }
      if (!capabilities.isComplete) {
        firstFailure ??= LinuxKiwiImageInspection.unsupported(
          LinuxKiwiImageIssue.initrdCapabilitiesMissing,
          diagnostic: capabilities.missingCapabilities.join(', '),
        );
        continue;
      }

      return LinuxKiwiImageInspection.supported(
        LinuxKiwiSupportedImage(
          bootEntry: candidate,
          livePayloadRelativePath: _livePayloadRelativePath,
          livePayloadBytes: await livePayload.length(),
          initrdCapabilities: capabilities,
        ),
      );
    }

    return firstFailure ??
        const LinuxKiwiImageInspection.unsupported(
          LinuxKiwiImageIssue.noEligibleLiveBootEntry,
        );
  }

  static Future<List<LinuxKiwiBootEntry>> _findEligibleBootEntries(
    String mountedRoot,
  ) async {
    final entries = <LinuxKiwiBootEntry>[];
    for (final configPath in _grubConfigPaths) {
      final file = File(p.join(mountedRoot, configPath));
      if (!await _isRegularFile(file.path)) continue;

      String content;
      try {
        content = await file.readAsString();
      } catch (_) {
        continue;
      }
      entries.addAll(_parseEligibleBootEntries(content, configPath));
    }
    return entries;
  }

  static List<LinuxKiwiBootEntry> _parseEligibleBootEntries(
    String content,
    String configPath,
  ) {
    final lines = content.replaceAll('\r\n', '\n').split('\n');
    final entries = <LinuxKiwiBootEntry>[];
    for (var index = 0; index < lines.length; index++) {
      final linuxMatch = _linuxLine.firstMatch(lines[index]);
      if (linuxMatch == null) continue;

      final kernelPath = _normalizeStaticPath(linuxMatch.group(1));
      final options = linuxMatch.group(2)?.trim() ?? '';
      if (kernelPath == null || !_hasSafePersistentKiwiOptions(options)) {
        continue;
      }

      final initrdPath = _findFollowingInitrd(lines, index);
      if (initrdPath == null || _containsRejectedEntryMarker(lines, index)) {
        continue;
      }

      final rootLabel = _liveCdLabel(options);
      if (rootLabel == null) continue;
      entries.add(
        LinuxKiwiBootEntry(
          bootConfigRelativePath: configPath,
          kernelRelativePath: kernelPath,
          initrdRelativePath: initrdPath,
          liveCdLabel: rootLabel,
        ),
      );
    }
    return entries;
  }

  static final RegExp _linuxLine = RegExp(
    r'^\s*linux(?:efi)?\s+(\S+)(?:\s+(.*))?$',
    caseSensitive: false,
  );
  static final RegExp _initrdLine = RegExp(
    r'^\s*initrd(?:efi)?\s+(\S+)(?:\s+.*)?$',
    caseSensitive: false,
  );
  static final RegExp _menuEntry = RegExp(
    r'^\s*menuentry\b',
    caseSensitive: false,
  );
  static final RegExp _safePath = RegExp(r'^/[A-Za-z0-9._/+\-]+$');
  static final RegExp _rejectedEntryMarker = RegExp(
    r'\b(?:install(?:er|ation)?|check(?:sum)?|mediacheck|media\s+check|rescue|recovery|safe(?:\s|-)?mode|failsafe)\b',
    caseSensitive: false,
  );

  static String? _findFollowingInitrd(List<String> lines, int linuxIndex) {
    final lastIndex = (linuxIndex + 32 < lines.length)
        ? linuxIndex + 32
        : lines.length - 1;
    for (var index = linuxIndex + 1; index <= lastIndex; index++) {
      if (_menuEntry.hasMatch(lines[index]) ||
          _linuxLine.hasMatch(lines[index])) {
        return null;
      }
      if (lines[index].trim() == '}') return null;
      final initrdMatch = _initrdLine.firstMatch(lines[index]);
      if (initrdMatch == null) continue;
      return _normalizeStaticPath(initrdMatch.group(1));
    }
    return null;
  }

  static bool _containsRejectedEntryMarker(List<String> lines, int linuxIndex) {
    final start = _nearestMenuEntry(lines, linuxIndex);
    final end = _nextMenuEntry(lines, linuxIndex);
    return _rejectedEntryMarker.hasMatch(lines.sublist(start, end).join('\n'));
  }

  static int _nearestMenuEntry(List<String> lines, int from) {
    for (var index = from; index >= 0; index--) {
      if (_menuEntry.hasMatch(lines[index])) return index;
    }
    return from;
  }

  static int _nextMenuEntry(List<String> lines, int from) {
    for (var index = from + 1; index < lines.length; index++) {
      if (_menuEntry.hasMatch(lines[index])) return index;
    }
    return lines.length;
  }

  static String? _normalizeStaticPath(String? rawPath) {
    if (rawPath == null || !_safePath.hasMatch(rawPath)) return null;
    final normalized = rawPath.substring(1);
    if (normalized.split('/').any((segment) => segment == '..')) return null;
    return normalized;
  }

  static bool _hasSafePersistentKiwiOptions(String options) {
    if (options.isEmpty || options.contains(RegExp(r'''["'`$]'''))) {
      return false;
    }
    final tokens = options
        .split(RegExp(r'\s+'))
        .where((token) => token.isNotEmpty)
        .map((token) => token.toLowerCase())
        .toList(growable: false);
    final rootTokens = tokens
        .where((token) => token.startsWith('root='))
        .toList();
    if (rootTokens.length != 1 ||
        !rootTokens.single.startsWith('root=live:cdlabel=') ||
        rootTokens.single.length == 'root=live:cdlabel='.length) {
      return false;
    }
    if (!_hasEnabledFlag(tokens, 'rd.live.image') ||
        !_hasEnabledFlag(tokens, 'rd.live.overlay.persistent')) {
      return false;
    }

    final cowFileSystems = tokens
        .where((token) => token.startsWith('rd.live.overlay.cowfs'))
        .toList(growable: false);
    if (cowFileSystems.any((token) => token != 'rd.live.overlay.cowfs=ext4')) {
      return false;
    }

    return !tokens.any((token) {
      return token.startsWith('rd.live.overlay.temporary') ||
          token.startsWith('rd.root.overlay.') ||
          token == 'rd.live.overlay' ||
          token.startsWith('rd.live.overlay=') ||
          token.startsWith('rd.live.cowfile.') ||
          token.startsWith('root=overlay:');
    });
  }

  static bool _hasEnabledFlag(List<String> tokens, String flag) => tokens.any(
    (token) =>
        token == flag ||
        token == '$flag=1' ||
        token == '$flag=yes' ||
        token == '$flag=true',
  );

  static String? _liveCdLabel(String options) {
    for (final token in options.split(RegExp(r'\s+'))) {
      if (!token.toLowerCase().startsWith('root=live:cdlabel=')) continue;
      final label = token.substring('root=live:CDLABEL='.length);
      return label.isEmpty || label.contains(RegExp(r'''["'`$\\]'''))
          ? null
          : label;
    }
    return null;
  }

  static Future<LinuxKiwiInitrdCapabilities?> _readNewcInitrdCapabilities(
    File initrd,
  ) async {
    RandomAccessFile? handle;
    try {
      handle = await initrd.open(mode: FileMode.read);
      final length = await handle.length();
      var offset = 0;
      final entryNames = <String>[];

      while (offset + 110 <= length) {
        await handle.setPosition(offset);
        final header = await handle.read(110);
        if (header.length != 110) return null;
        final magic = ascii.decode(header.sublist(0, 6), allowInvalid: true);
        if (magic != '070701' && magic != '070702') return null;
        final fileSize = _parseNewcHex(header, 54);
        final nameSize = _parseNewcHex(header, 94);
        if (fileSize == null ||
            nameSize == null ||
            nameSize <= 1 ||
            nameSize > _maxCpioEntryNameBytes) {
          return null;
        }
        final nameOffset = offset + 110;
        if (nameOffset + nameSize > length) return null;
        await handle.setPosition(nameOffset);
        final nameBytes = await handle.read(nameSize);
        if (nameBytes.length != nameSize || nameBytes.last != 0) return null;
        final name = ascii
            .decode(
              nameBytes.sublist(0, nameBytes.length - 1),
              allowInvalid: true,
            )
            .toLowerCase();
        if (name == 'trailer!!!') {
          return _capabilitiesFromEntryNames(entryNames);
        }
        entryNames.add(name);

        final dataOffset = _alignNewc(nameOffset + nameSize);
        final nextOffset = _alignNewc(dataOffset + fileSize);
        if (nextOffset <= offset || nextOffset > length) return null;
        offset = nextOffset;
      }
      return null;
    } catch (_) {
      return null;
    } finally {
      await handle?.close();
    }
  }

  static Future<_LinuxKiwiInitrdReadResult> _readInitrdCapabilities(
    File initrd,
    LinuxInitrdEntryLister entryLister,
  ) async {
    final uncompressed = await _readNewcInitrdCapabilities(initrd);
    if (uncompressed != null) {
      return _LinuxKiwiInitrdReadResult(capabilities: uncompressed);
    }

    final listing = await entryLister.list(initrd);
    if (!listing.success) {
      return _LinuxKiwiInitrdReadResult(diagnostic: listing.diagnostic);
    }
    return _LinuxKiwiInitrdReadResult(
      capabilities: _capabilitiesFromEntryNames(listing.entries),
    );
  }

  static LinuxKiwiInitrdCapabilities _capabilitiesFromEntryNames(
    Iterable<String> names,
  ) {
    var hasKiwiLiveRoot = false;
    var hasKiwiLiveLibrary = false;
    var hasKiwiLiveParser = false;
    var hasFdisk = false;
    var hasPartx = false;
    var hasMkfsExt4 = false;
    var hasMount = false;
    var hasBlkid = false;
    var hasOverlaySupport = false;
    var hasExt4Support = false;
    var hasIso9660Support = false;

    for (final rawName in names) {
      final name = rawName.replaceAll('\\', '/').toLowerCase();
      hasKiwiLiveRoot =
          hasKiwiLiveRoot || _pathEndsWith(name, 'kiwi-live-root');
      hasKiwiLiveLibrary =
          hasKiwiLiveLibrary || _pathEndsWith(name, 'kiwi-live-lib.sh');
      hasKiwiLiveParser =
          hasKiwiLiveParser || _pathEndsWith(name, 'parse-kiwi-live.sh');
      hasFdisk = hasFdisk || _pathEndsWith(name, 'fdisk');
      hasPartx = hasPartx || _pathEndsWith(name, 'partx');
      hasMkfsExt4 = hasMkfsExt4 || _pathEndsWith(name, 'mkfs.ext4');
      hasMount = hasMount || _pathEndsWith(name, 'mount');
      hasBlkid = hasBlkid || _pathEndsWith(name, 'blkid');
      hasOverlaySupport =
          hasOverlaySupport ||
          name.contains('/overlay.ko') ||
          name.endsWith('/overlay');
      hasExt4Support =
          hasExt4Support || name.contains('/ext4.ko') || name.endsWith('/ext4');
      hasIso9660Support =
          hasIso9660Support ||
          name.contains('/isofs.ko') ||
          name.contains('/iso9660.ko') ||
          name.endsWith('/isofs') ||
          name.endsWith('/iso9660');
    }

    return LinuxKiwiInitrdCapabilities(
      hasKiwiLiveRoot: hasKiwiLiveRoot,
      hasKiwiLiveLibrary: hasKiwiLiveLibrary,
      hasKiwiLiveParser: hasKiwiLiveParser,
      hasFdisk: hasFdisk,
      hasPartx: hasPartx,
      hasMkfsExt4: hasMkfsExt4,
      hasMount: hasMount,
      hasBlkid: hasBlkid,
      hasOverlaySupport: hasOverlaySupport,
      hasExt4Support: hasExt4Support,
      hasIso9660Support: hasIso9660Support,
    );
  }

  static bool _pathEndsWith(String path, String basename) =>
      path == basename || path.endsWith('/$basename');

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

class _LinuxKiwiInitrdReadResult {
  final LinuxKiwiInitrdCapabilities? capabilities;
  final String? diagnostic;

  const _LinuxKiwiInitrdReadResult({this.capabilities, this.diagnostic});
}

final linuxKiwiImagePreflightProvider = Provider<LinuxKiwiImagePreflight>(
  (ref) => const LinuxKiwiImagePreflightService(),
);
