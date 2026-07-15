import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import 'windows_system_environment.dart';

enum WindowsInstallImageFormat { wim, esd, swm }

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

  const WindowsIsoLayoutInspection._({
    required this.isValid,
    this.error,
    this.imageFormat,
    this.imagePath,
  });

  const WindowsIsoLayoutInspection.valid({
    required WindowsInstallImageFormat imageFormat,
    required String imagePath,
  }) : this._(isValid: true, imageFormat: imageFormat, imagePath: imagePath);

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

  static Future<WindowsIsoLayoutInspection> inspectMountedRoot(
    String mountedRoot,
  ) async {
    final root = Directory(mountedRoot);
    if (!await root.exists()) {
      return const WindowsIsoLayoutInspection.invalid(
        'The mounted ISO root is not available.',
      );
    }

    final bootWimPath = p.join(mountedRoot, 'sources', 'boot.wim');
    if (!await _isRegularWimFile(bootWimPath)) {
      return const WindowsIsoLayoutInspection.invalid(
        'Windows setup boot.wim is missing or invalid.',
      );
    }

    const candidates = <(WindowsInstallImageFormat, String)>[
      (WindowsInstallImageFormat.wim, 'install.wim'),
      (WindowsInstallImageFormat.esd, 'install.esd'),
      (WindowsInstallImageFormat.swm, 'install.swm'),
    ];
    WindowsInstallImageFormat? imageFormat;
    String? imagePath;
    for (final candidate in candidates) {
      final path = p.join(mountedRoot, 'sources', candidate.$2);
      if (await _isRegularWimFile(path)) {
        imageFormat = candidate.$1;
        imagePath = path;
        break;
      }
    }
    if (imageFormat == null || imagePath == null) {
      return const WindowsIsoLayoutInspection.invalid(
        'Windows install.wim, install.esd, or install.swm is missing or invalid.',
      );
    }

    final hasBootmgr = await _isRegularFile(p.join(mountedRoot, 'bootmgr'));
    final hasEfiBootManager = await _isRegularFile(
      p.join(mountedRoot, 'efi', 'microsoft', 'boot', 'bootmgfw.efi'),
    );
    if (!hasBootmgr && !hasEfiBootManager) {
      return const WindowsIsoLayoutInspection.invalid(
        'Windows boot manager files are missing.',
      );
    }

    return WindowsIsoLayoutInspection.valid(
      imageFormat: imageFormat,
      imagePath: imagePath,
    );
  }

  static Future<bool> _isRegularFile(String path) async {
    return await FileSystemEntity.type(path, followLinks: false) ==
        FileSystemEntityType.file;
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
        if (volume.exitCode == 0 && letter.isNotEmpty) return '$letter:\\';
      }
    } catch (_) {
      // The caller turns a failed inspection into a non-destructive rejection.
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
      // An unmount failure is diagnostic only; the ISO was never written to.
    }
  }
}

final windowsIsoPreflightProvider = Provider<WindowsIsoPreflight>(
  (ref) => const WindowsIsoPreflightService(),
);
