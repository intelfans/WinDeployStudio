import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import '../../features/logs/services/log_center_service.dart';
import 'wim_info_service.dart';
import 'windows_iso_preflight.dart';

class IsoMetadata {
  final String filePath;
  final String fileName;
  final int fileSize;
  final String? windowsVersion;
  final String? buildNumber;
  final String? architecture;
  final String? language;
  final String? edition;
  final bool isValidWindowsIso;

  const IsoMetadata({
    required this.filePath,
    required this.fileName,
    required this.fileSize,
    this.windowsVersion,
    this.buildNumber,
    this.architecture,
    this.language,
    this.edition,
    this.isValidWindowsIso = false,
  });

  String get displaySize {
    if (fileSize < 1024 * 1024) {
      return '${(fileSize / 1024).toStringAsFixed(0)} KB';
    }
    if (fileSize < 1024 * 1024 * 1024) {
      return '${(fileSize / (1024 * 1024)).toStringAsFixed(0)} MB';
    }
    return '${(fileSize / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }
}

final isoParseServiceProvider = Provider<IsoParseService>((ref) {
  return IsoParseService();
});

typedef ProgressCallback = void Function(String step, int percent);

class IsoParseService {
  bool _cancelled = false;

  Future<IsoMetadata?> parseIso(
    String isoPath, {
    ProgressCallback? onProgress,
  }) async {
    _cancelled = false;
    final file = File(isoPath);
    if (!await file.exists()) return null;

    final fileSize = await file.length();
    final fileName = p.basename(isoPath);

    debugPrint('=== ISO Parse Start ===');
    debugPrint('File: $isoPath');
    debugPrint('Size: $fileSize bytes');

    final logCenter = LogCenterService();
    await logCenter.logIso(
      'ISO 解析开始 | 文件: $fileName | 大小: ${_formatSize(fileSize)}',
    );

    // Step 1: Filename detection (instant)
    _report(onProgress, 'detect', 50);
    final fastResult = _detectFromFileName(fileName, isoPath, fileSize);
    debugPrint('Filename detection: ${fastResult.windowsVersion}');

    if (_cancelled) return null;
    _report(onProgress, 'detect', 100);

    // Step 2: Mount ISO
    _report(onProgress, 'mount', 0);
    final mountPoint = await _mountIso(isoPath);
    if (mountPoint == null) {
      debugPrint('Mount failed or cancelled');
      return fastResult;
    }
    Map<String, String>? dismInfo;
    try {
      if (_cancelled) return null;
      _report(onProgress, 'mount', 100);
      debugPrint('Mounted at: $mountPoint');
      _report(onProgress, 'detect', 0);

      final layout = await WindowsIsoLayoutInspector.inspectMountedRoot(
        mountPoint,
      );
      if (!layout.isValid || layout.imagePath == null) {
        debugPrint('Windows setup layout not found: ${layout.error}');
        return fastResult;
      }
      _report(onProgress, 'detect', 100);
      if (_cancelled) return null;

      if (layout.imageFormat != WindowsInstallImageFormat.swm) {
        _report(onProgress, 'info', 30);
        final images = await WimInfoService.readImages(layout.imagePath!);
        final image = images.first;
        dismInfo = {
          'build': image.build,
          'architecture': image.architecture,
          'language': image.language,
          'edition': image.name.isEmpty ? image.edition : image.name,
        };
        final buildNumber = int.tryParse(image.build) ?? 0;
        if (buildNumber >= 22000) {
          dismInfo['version'] = 'Windows 11 (Build ${image.build})';
        } else if (buildNumber >= 10240) {
          dismInfo['version'] = 'Windows 10 (Build ${image.build})';
        } else if (image.version.isNotEmpty) {
          dismInfo['version'] = image.version;
        }
      } else {
        debugPrint(
          'Split WIM layout detected; skipping optional WIM metadata.',
        );
      }
      _report(onProgress, 'info', 100);
    } catch (error) {
      debugPrint('WIM metadata read failed: $error');
      _report(onProgress, 'info', 100);
    } finally {
      onProgress?.call('cleanup', 0);
      await _unmount(isoPath);
      onProgress?.call('cleanup', 100);
    }

    if (_cancelled) return null;

    // Build result
    if (dismInfo != null && dismInfo.isNotEmpty) {
      final version = dismInfo['version'] ?? fastResult.windowsVersion;
      final build = dismInfo['build'] ?? fastResult.buildNumber;
      final arch = dismInfo['architecture'];
      await logCenter.logIso(
        'ISO 解析成功 | 文件: $fileName | 版本: $version | 构建: $build | 架构: $arch',
      );
      return IsoMetadata(
        filePath: isoPath,
        fileName: fileName,
        fileSize: fileSize,
        windowsVersion: dismInfo['version'] ?? fastResult.windowsVersion,
        buildNumber: dismInfo['build'] ?? fastResult.buildNumber,
        architecture: dismInfo['architecture'],
        language: dismInfo['language'],
        edition: dismInfo['edition'],
        isValidWindowsIso: true,
      );
    }

    return IsoMetadata(
      filePath: isoPath,
      fileName: fileName,
      fileSize: fileSize,
      windowsVersion: fastResult.windowsVersion,
      buildNumber: fastResult.buildNumber,
      isValidWindowsIso: true,
    );
  }

  void cancel() {
    _cancelled = true;
    debugPrint('=== ISO Parse Cancelled ===');
  }

  String _formatSize(int bytes) {
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(0)} KB';
    }
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(0)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  void _report(ProgressCallback? cb, String step, int percent) {
    if (!_cancelled) {
      cb?.call(step, percent);
    }
  }

  // --- Mount ---

  String _psQuote(String value) => "'${value.replaceAll("'", "''")}'";

  Future<String?> _mountIso(String isoPath) async {
    try {
      final quotedPath = _psQuote(isoPath);
      final result = await Process.run('powershell', [
        '-NoProfile',
        '-ExecutionPolicy',
        'Bypass',
        '-Command',
        "Mount-DiskImage -ImagePath $quotedPath",
      ]).timeout(const Duration(seconds: 15));

      if (result.exitCode != 0) return null;
      if (_cancelled) {
        await _unmount(isoPath);
        return null;
      }

      // Retry getting drive letter
      for (int i = 0; i < 5; i++) {
        if (_cancelled) {
          await _unmount(isoPath);
          return null;
        }
        await Future.delayed(const Duration(milliseconds: 500));
        final r = await Process.run('powershell', [
          '-NoProfile',
          '-ExecutionPolicy',
          'Bypass',
          '-Command',
          "Get-DiskImage -ImagePath $quotedPath | Get-Volume | Select-Object -ExpandProperty DriveLetter",
        ]);
        if (r.exitCode == 0) {
          final letter = r.stdout.toString().trim();
          if (letter.isNotEmpty) return '$letter:\\';
        }
      }
      await _unmount(isoPath);
      return null;
    } catch (e) {
      debugPrint('Mount error: $e');
      return null;
    }
  }

  Future<void> _unmount(String isoPath) async {
    try {
      final quotedPath = _psQuote(isoPath);
      final process = await Process.start('powershell', [
        '-NoProfile',
        '-ExecutionPolicy',
        'Bypass',
        '-Command',
        "Dismount-DiskImage -ImagePath $quotedPath -ErrorAction SilentlyContinue",
      ]);
      final exited = await process.exitCode.timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          debugPrint('Unmount timed out, killing PID ${process.pid}');
          process.kill(ProcessSignal.sigterm);
          return -1;
        },
      );
      debugPrint('Unmount exited: $exited');
    } catch (e) {
      debugPrint('Unmount error: $e');
    }
  }

  // --- Filename detection ---

  IsoMetadata _detectFromFileName(
    String fileName,
    String filePath,
    int fileSize,
  ) {
    String? windowsVersion;
    String? buildNumber;
    final lower = fileName.toLowerCase();

    if (lower.contains('win11') ||
        lower.contains('windows11') ||
        lower.contains('26100') ||
        lower.contains('22621') ||
        lower.contains('22000')) {
      windowsVersion = 'Windows 11';
    } else if (lower.contains('win10') ||
        lower.contains('windows10') ||
        lower.contains('19045') ||
        lower.contains('19044') ||
        lower.contains('19043')) {
      windowsVersion = 'Windows 10';
    } else if (lower.contains('server')) {
      windowsVersion = 'Windows Server';
    }

    final buildMatch = RegExp(r'(\d{5})').firstMatch(lower);
    if (buildMatch != null) buildNumber = buildMatch.group(1);

    return IsoMetadata(
      filePath: filePath,
      fileName: fileName,
      fileSize: fileSize,
      windowsVersion: windowsVersion,
      buildNumber: buildNumber,
    );
  }
}
