import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import 'windows_system_environment.dart';

enum WindowsInstallImageFormat { wim, esd, swm }

/// CPU architectures that can be loaded through the removable-media UEFI
/// fallback path. The file name alone is not trusted: the inspector also
/// checks the PE/COFF machine value before reporting an architecture here.
enum WindowsEfiBootArchitecture { x64, arm64, ia32 }

class WindowsIsoFileInfo {
  final String relativePath;
  final int sizeBytes;

  const WindowsIsoFileInfo({
    required this.relativePath,
    required this.sizeBytes,
  });
}

/// The structural result of inspecting a mounted ISO root.
///
/// The result is deliberately based on installer files rather than an ISO file
/// name. This lets creator paths reject Linux and arbitrary data ISO files
/// before they can reach a destructive disk operation.
class WindowsIsoLayoutInspection {
  final bool isValid;
  final String? error;
  final WindowsInstallImageFormat? imageFormat;
  final String? imagePath;
  final bool hasBiosBootManager;
  final bool hasBiosBcd;
  final bool hasEfiBcd;
  final Set<WindowsEfiBootArchitecture> efiBootArchitectures;
  final WindowsEfiBootArchitecture? efiBootManagerArchitecture;
  final int installImageBytes;
  final int totalFileBytes;
  final List<WindowsIsoFileInfo> fat32OversizedFiles;

  const WindowsIsoLayoutInspection._({
    required this.isValid,
    this.error,
    this.imageFormat,
    this.imagePath,
    this.hasBiosBootManager = false,
    this.hasBiosBcd = false,
    this.hasEfiBcd = false,
    this.efiBootArchitectures = const <WindowsEfiBootArchitecture>{},
    this.efiBootManagerArchitecture,
    this.installImageBytes = 0,
    this.totalFileBytes = 0,
    this.fat32OversizedFiles = const <WindowsIsoFileInfo>[],
  });

  const WindowsIsoLayoutInspection.valid({
    required WindowsInstallImageFormat imageFormat,
    required String imagePath,
    bool hasBiosBootManager = false,
    bool hasBiosBcd = false,
    bool hasEfiBcd = false,
    Set<WindowsEfiBootArchitecture> efiBootArchitectures =
        const <WindowsEfiBootArchitecture>{},
    WindowsEfiBootArchitecture? efiBootManagerArchitecture,
    int installImageBytes = 0,
    int totalFileBytes = 0,
    List<WindowsIsoFileInfo> fat32OversizedFiles = const <WindowsIsoFileInfo>[],
  }) : this._(
         isValid: true,
         imageFormat: imageFormat,
         imagePath: imagePath,
         hasBiosBootManager: hasBiosBootManager,
         hasBiosBcd: hasBiosBcd,
         hasEfiBcd: hasEfiBcd,
         efiBootArchitectures: efiBootArchitectures,
         efiBootManagerArchitecture: efiBootManagerArchitecture,
         installImageBytes: installImageBytes,
         totalFileBytes: totalFileBytes,
         fat32OversizedFiles: fat32OversizedFiles,
       );

  const WindowsIsoLayoutInspection.invalid(String error)
    : this._(isValid: false, error: error);
}

/// Reads the Windows setup layout from a mounted ISO root.
///
/// A valid image must have a real Windows PE boot WIM, a real install WIM/ESD
/// (or split WIM), and a Windows boot manager marker. The WIM header check
/// prevents arbitrary files named `install.wim` from satisfying the preflight.
class WindowsIsoLayoutInspector {
  const WindowsIsoLayoutInspector._();

  static const _wimHeaderBytes = 0xD0;
  static const _wimMagic = <int>[0x4d, 0x53, 0x57, 0x49, 0x4d, 0, 0, 0];
  static const int fat32MaximumFileBytes = 0xFFFFFFFF;

  static Future<WindowsIsoLayoutInspection> inspectMountedRoot(
    String mountedRoot, {
    bool Function()? isCancelled,
  }) async {
    if (_isCancelled(isCancelled)) return _cancelledInspection;
    final root = Directory(mountedRoot);
    if (!await root.exists()) {
      return const WindowsIsoLayoutInspection.invalid(
        'The mounted ISO root is not available.',
      );
    }
    if (_isCancelled(isCancelled)) return _cancelledInspection;

    final bootWimPath = p.join(mountedRoot, 'sources', 'boot.wim');
    if (!await _isRegularWimFile(bootWimPath)) {
      return const WindowsIsoLayoutInspection.invalid(
        'Windows setup boot.wim is missing or invalid.',
      );
    }
    if (_isCancelled(isCancelled)) return _cancelledInspection;

    const candidates = <(WindowsInstallImageFormat, String)>[
      (WindowsInstallImageFormat.wim, 'install.wim'),
      (WindowsInstallImageFormat.esd, 'install.esd'),
      (WindowsInstallImageFormat.swm, 'install.swm'),
    ];
    WindowsInstallImageFormat? imageFormat;
    String? imagePath;
    for (final candidate in candidates) {
      if (_isCancelled(isCancelled)) return _cancelledInspection;
      final path = p.join(mountedRoot, 'sources', candidate.$2);
      if (await _isRegularWimFile(path)) {
        imageFormat = candidate.$1;
        imagePath = path;
        break;
      }
    }
    if (_isCancelled(isCancelled)) return _cancelledInspection;
    if (imageFormat == null || imagePath == null) {
      return const WindowsIsoLayoutInspection.invalid(
        'Windows install.wim, install.esd, or install.swm is missing or invalid.',
      );
    }

    final hasBootmgr = await _isRegularFile(p.join(mountedRoot, 'bootmgr'));
    final hasBiosBcd = await _isNonEmptyRegularFile(
      p.join(mountedRoot, 'boot', 'bcd'),
    );
    final hasEfiBcd = await _isNonEmptyRegularFile(
      p.join(mountedRoot, 'efi', 'microsoft', 'boot', 'bcd'),
    );
    final hasEfiBootManager = await _isRegularFile(
      p.join(mountedRoot, 'efi', 'microsoft', 'boot', 'bootmgfw.efi'),
    );
    if (_isCancelled(isCancelled)) return _cancelledInspection;
    if (!hasBootmgr && !hasEfiBootManager) {
      return const WindowsIsoLayoutInspection.invalid(
        'Windows boot manager files are missing.',
      );
    }

    final efiBootArchitectures = <WindowsEfiBootArchitecture>{};
    for (final entry in const <(WindowsEfiBootArchitecture, String)>[
      (WindowsEfiBootArchitecture.x64, 'bootx64.efi'),
      (WindowsEfiBootArchitecture.arm64, 'bootaa64.efi'),
      (WindowsEfiBootArchitecture.ia32, 'bootia32.efi'),
    ]) {
      if (_isCancelled(isCancelled)) return _cancelledInspection;
      final architecture = await _readEfiArchitecture(
        p.join(mountedRoot, 'efi', 'boot', entry.$2),
      );
      if (architecture == entry.$1) efiBootArchitectures.add(architecture!);
    }
    final efiBootManagerArchitecture = await _readEfiArchitecture(
      p.join(mountedRoot, 'efi', 'microsoft', 'boot', 'bootmgfw.efi'),
    );
    if (_isCancelled(isCancelled)) return _cancelledInspection;

    final scan = await _scanFiles(mountedRoot, isCancelled: isCancelled);
    if (_isCancelled(isCancelled)) return _cancelledInspection;
    if (scan == null) {
      return const WindowsIsoLayoutInspection.invalid(
        'Windows setup files could not be inspected for FAT32 compatibility.',
      );
    }

    final installImageBytes = await File(imagePath).length();
    if (_isCancelled(isCancelled)) return _cancelledInspection;
    return WindowsIsoLayoutInspection.valid(
      imageFormat: imageFormat,
      imagePath: imagePath,
      hasBiosBootManager: hasBootmgr,
      hasBiosBcd: hasBiosBcd,
      hasEfiBcd: hasEfiBcd,
      efiBootArchitectures: efiBootArchitectures,
      efiBootManagerArchitecture: efiBootManagerArchitecture,
      installImageBytes: installImageBytes,
      totalFileBytes: scan.totalFileBytes,
      fat32OversizedFiles: scan.fat32OversizedFiles,
    );
  }

  static bool _isCancelled(bool Function()? isCancelled) =>
      isCancelled?.call() ?? false;

  static const WindowsIsoLayoutInspection _cancelledInspection =
      WindowsIsoLayoutInspection.invalid(
        'ISO layout inspection was cancelled.',
      );

  static Future<bool> _isRegularFile(String path) async {
    return await FileSystemEntity.type(path, followLinks: false) ==
        FileSystemEntityType.file;
  }

  static Future<bool> _isNonEmptyRegularFile(String path) async {
    if (!await _isRegularFile(path)) return false;
    try {
      return await File(path).length() > 0;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> _isRegularWimFile(String path) async {
    if (!await _isRegularFile(path)) return false;
    final file = File(path);
    if (await file.length() < _wimHeaderBytes) return false;

    RandomAccessFile? handle;
    try {
      handle = await file.open();
      final header = await handle.read(_wimHeaderBytes);
      if (header.length != _wimHeaderBytes) return false;
      for (var index = 0; index < _wimMagic.length; index++) {
        if (header[index] != _wimMagic[index]) return false;
      }
      final headerSize = _uint32(header, 8);
      return headerSize >= _wimHeaderBytes && headerSize <= await file.length();
    } catch (_) {
      return false;
    } finally {
      await handle?.close();
    }
  }

  static int _uint32(Uint8List bytes, int offset) =>
      bytes[offset] |
      (bytes[offset + 1] << 8) |
      (bytes[offset + 2] << 16) |
      (bytes[offset + 3] << 24);

  static Future<WindowsEfiBootArchitecture?> _readEfiArchitecture(
    String path,
  ) async {
    if (!await _isRegularFile(path)) return null;
    RandomAccessFile? handle;
    try {
      handle = await File(path).open();
      final dosHeader = await handle.read(0x40);
      if (dosHeader.length < 0x40 ||
          dosHeader[0] != 0x4d ||
          dosHeader[1] != 0x5a) {
        return null;
      }
      final peOffset = _uint32(dosHeader, 0x3c);
      final fileLength = await handle.length();
      if (peOffset < 0x40 || peOffset > fileLength - 6) return null;
      await handle.setPosition(peOffset);
      final signatureAndMachine = await handle.read(6);
      if (signatureAndMachine.length != 6 ||
          signatureAndMachine[0] != 0x50 ||
          signatureAndMachine[1] != 0x45 ||
          signatureAndMachine[2] != 0 ||
          signatureAndMachine[3] != 0) {
        return null;
      }
      final machine = signatureAndMachine[4] | (signatureAndMachine[5] << 8);
      return switch (machine) {
        0x8664 => WindowsEfiBootArchitecture.x64,
        0xaa64 => WindowsEfiBootArchitecture.arm64,
        0x014c => WindowsEfiBootArchitecture.ia32,
        _ => null,
      };
    } catch (_) {
      return null;
    } finally {
      await handle?.close();
    }
  }

  /// Returns the PE/COFF architecture of an EFI executable.  Callers use
  /// this after copying the installation files so a correctly named but
  /// wrong-architecture (or corrupt) fallback file cannot pass verification.
  static Future<WindowsEfiBootArchitecture?> readEfiArchitecture(String path) =>
      _readEfiArchitecture(path);

  static Future<_WindowsIsoFileScan?> _scanFiles(
    String mountedRoot, {
    bool Function()? isCancelled,
  }) async {
    var totalFileBytes = 0;
    final fat32OversizedFiles = <WindowsIsoFileInfo>[];
    try {
      await for (final entity in Directory(
        mountedRoot,
      ).list(recursive: true, followLinks: false)) {
        if (_isCancelled(isCancelled)) return null;
        if (entity is! File) continue;
        final sizeBytes = await entity.length();
        if (_isCancelled(isCancelled)) return null;
        totalFileBytes += sizeBytes;
        if (sizeBytes > fat32MaximumFileBytes) {
          fat32OversizedFiles.add(
            WindowsIsoFileInfo(
              relativePath: p
                  .relative(entity.path, from: mountedRoot)
                  .replaceAll('/', r'\'),
              sizeBytes: sizeBytes,
            ),
          );
        }
      }
      return _WindowsIsoFileScan(
        totalFileBytes: totalFileBytes,
        fat32OversizedFiles: List.unmodifiable(fat32OversizedFiles),
      );
    } catch (_) {
      return null;
    }
  }
}

class _WindowsIsoFileScan {
  final int totalFileBytes;
  final List<WindowsIsoFileInfo> fat32OversizedFiles;

  const _WindowsIsoFileScan({
    required this.totalFileBytes,
    required this.fat32OversizedFiles,
  });
}

/// Read-only ISO preflight used immediately before destructive media creation.
abstract class WindowsIsoPreflight {
  Future<WindowsIsoLayoutInspection> inspect(String isoPath);
}

class WindowsIsoPreflightService implements WindowsIsoPreflight {
  const WindowsIsoPreflightService();

  @override
  Future<WindowsIsoLayoutInspection> inspect(String isoPath) async {
    final source = File(isoPath);
    if (await FileSystemEntity.type(source.path, followLinks: false) !=
        FileSystemEntityType.file) {
      return const WindowsIsoLayoutInspection.invalid(
        'The ISO source is not a regular file.',
      );
    }

    final mountPoint = await _mountIso(isoPath);
    if (mountPoint == null) {
      return const WindowsIsoLayoutInspection.invalid(
        'The ISO could not be mounted for Windows setup validation.',
      );
    }
    try {
      return WindowsIsoLayoutInspector.inspectMountedRoot(mountPoint);
    } finally {
      await _unmountIso(isoPath);
    }
  }

  String _psQuote(String value) => "'${value.replaceAll("'", "''")}'";

  Future<String?> _mountIso(String isoPath) async {
    var mounted = false;
    var mountMayExist = false;
    try {
      final quotedPath = _psQuote(isoPath);
      mountMayExist = true;
      final mount = await _runPowerShell([
        '-NoProfile',
        '-NonInteractive',
        '-ExecutionPolicy',
        'Bypass',
        '-Command',
        'Mount-DiskImage -ImagePath $quotedPath -ErrorAction Stop',
      ], timeout: const Duration(seconds: 15));
      if (mount.exitCode == 0) {
        mounted = true;

        final deadline = DateTime.now().add(const Duration(seconds: 20));
        while (DateTime.now().isBefore(deadline)) {
          await Future<void>.delayed(const Duration(milliseconds: 400));
          final remaining = deadline.difference(DateTime.now());
          if (remaining <= Duration.zero) break;
          final volume = await _runPowerShell(
            [
              '-NoProfile',
              '-NonInteractive',
              '-ExecutionPolicy',
              'Bypass',
              '-Command',
              'Get-DiskImage -ImagePath $quotedPath | Get-Volume | '
                  'Select-Object -ExpandProperty DriveLetter',
            ],
            timeout: remaining > const Duration(seconds: 4)
                ? const Duration(seconds: 4)
                : remaining,
          );
          final letter = volume.stdout.toString().trim();
          if (volume.exitCode == 0 && letter.isNotEmpty) return '$letter:\\';
        }
      }
    } catch (_) {
      // The caller turns a failed inspection into a non-destructive rejection.
    }
    if (mounted || mountMayExist) await _unmountIso(isoPath);
    return null;
  }

  Future<void> _unmountIso(String isoPath) async {
    try {
      final quotedPath = _psQuote(isoPath);
      await _runPowerShell([
        '-NoProfile',
        '-NonInteractive',
        '-ExecutionPolicy',
        'Bypass',
        '-Command',
        'Dismount-DiskImage -ImagePath $quotedPath -ErrorAction SilentlyContinue',
      ], timeout: const Duration(seconds: 10));
    } catch (_) {
      // An unmount failure is diagnostic only; the ISO was never written to.
    }
  }

  Future<ProcessResult> _runPowerShell(
    List<String> arguments, {
    required Duration timeout,
  }) async {
    try {
      final process = await Process.start(
        WindowsSystemEnvironment.powerShellExecutable,
        arguments,
        environment: WindowsSystemEnvironment.withSystemRoot(),
      );
      final stdout = process.stdout
          .transform(const SystemEncoding().decoder)
          .join();
      final stderr = process.stderr
          .transform(const SystemEncoding().decoder)
          .join();
      try {
        final exitCode = await process.exitCode.timeout(timeout);
        return ProcessResult(process.pid, exitCode, await stdout, await stderr);
      } on TimeoutException {
        process.kill(ProcessSignal.sigkill);
        try {
          await process.exitCode.timeout(const Duration(seconds: 5));
        } catch (_) {
          // The caller receives a non-zero result, and no disk was modified.
        }
        return ProcessResult(
          process.pid,
          -1,
          await stdout,
          '${await stderr}\nPowerShell timed out after ${timeout.inSeconds} seconds.',
        );
      }
    } catch (error) {
      return ProcessResult(-1, -1, '', error.toString());
    }
  }
}

final windowsIsoPreflightProvider = Provider<WindowsIsoPreflight>(
  (ref) => const WindowsIsoPreflightService(),
);
