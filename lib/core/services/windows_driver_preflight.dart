import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import 'background_file_hash_service.dart';

/// Resolves the physical disk number containing a local source path.
///
/// A null result is deliberately treated as unsafe. The caller cannot safely
/// erase a target disk while it does not know where the driver source lives.
typedef WindowsDriverSourceDiskResolver =
    Future<int?> Function(String sourcePath);

/// A single regular file accepted into a Windows driver package manifest.
class WindowsDriverManifestEntry {
  final String path;
  final String resolvedPath;
  final int size;
  final DateTime modified;
  final String digest;
  final bool isInf;

  const WindowsDriverManifestEntry({
    required this.path,
    required this.resolvedPath,
    required this.size,
    required this.modified,
    required this.digest,
    required this.isInf,
  });
}

/// Immutable inventory of a driver source directory.
///
/// The hashes make it possible to detect source changes between selection,
/// secure staging, and DISM injection without writing to the source directory.
class WindowsDriverManifest {
  final String rootPath;
  final String resolvedRootPath;
  final int sourceDiskNumber;
  final List<WindowsDriverManifestEntry> entries;

  const WindowsDriverManifest({
    required this.rootPath,
    required this.resolvedRootPath,
    required this.sourceDiskNumber,
    required this.entries,
  });

  static const empty = WindowsDriverManifest(
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

enum WindowsDriverPreflightError {
  invalidSource,
  sourceOnTargetDisk,
  infRequired,
  sourceChanged,
  unavailable,
}

/// Result of a non-destructive Windows driver source inspection.
class WindowsDriverPreflightResult {
  final WindowsDriverManifest? manifest;
  final String? error;
  final WindowsDriverPreflightError? errorCode;

  const WindowsDriverPreflightResult._({
    this.manifest,
    this.error,
    this.errorCode,
  });

  const WindowsDriverPreflightResult.disabled() : this._();

  const WindowsDriverPreflightResult.success(WindowsDriverManifest manifest)
    : this._(manifest: manifest);

  const WindowsDriverPreflightResult.failure(
    String error, {
    WindowsDriverPreflightError errorCode =
        WindowsDriverPreflightError.unavailable,
  }) : this._(error: error, errorCode: errorCode);

  bool get success => error == null;
  bool get enabled => manifest != null;
  int get fileCount => manifest?.entries.length ?? 0;
  int get infCount => manifest?.infPaths.length ?? 0;
}

/// Read-only validation for a Windows To Go driver source.
///
/// It accepts only a normal local directory which is not located on the target
/// disk. The directory tree may contain only normal files and directories: all
/// symbolic links, junctions, network paths, device paths, volume roots, and
/// unusual file-system entries are rejected. EXE/MSI installers are not INF
/// packages and are rejected even when placed beside a valid driver. At least
/// one non-empty, textual INF with a `[Version]` section is required. DISM
/// remains the authoritative compatibility check when the validated manifest
/// is later injected.
abstract interface class WindowsDriverPreflight {
  Future<WindowsDriverPreflightResult> prepare({
    required String sourceDirectory,
    required int targetDiskNumber,
  });

  /// Rechecks a prior manifest before source data is copied or consumed.
  Future<WindowsDriverPreflightResult> verify({
    required WindowsDriverManifest manifest,
    required int targetDiskNumber,
  });
}

class WindowsDriverPreflightService implements WindowsDriverPreflight {
  static const int _maxEntries = 8192;
  static const int _maxTotalBytes = 4 * 1024 * 1024 * 1024;
  static const int _maxInfHeaderBytes = 1024 * 1024;
  static const _unsupportedInstallerExtensions = {'.exe', '.msi'};

  final WindowsDriverSourceDiskResolver _sourceDiskResolver;
  final void Function(String message)? log;

  WindowsDriverPreflightService({
    WindowsDriverSourceDiskResolver? sourceDiskResolver,
    this.log,
  }) : _sourceDiskResolver = sourceDiskResolver ?? _resolveSourceDisk;

  @override
  Future<WindowsDriverPreflightResult> prepare({
    required String sourceDirectory,
    required int targetDiskNumber,
  }) async {
    if (sourceDirectory.trim().isEmpty) {
      return const WindowsDriverPreflightResult.disabled();
    }

    try {
      final manifest = await _buildManifest(
        sourceDirectory: sourceDirectory,
        targetDiskNumber: targetDiskNumber,
      );
      log?.call(
        'Windows driver preflight hashed ${manifest.entries.length} file(s), '
        'including ${manifest.infPaths.length} validated INF file(s).',
      );
      return WindowsDriverPreflightResult.success(manifest);
    } on _WindowsDriverPreflightFailure catch (error) {
      return WindowsDriverPreflightResult.failure(
        error.message,
        errorCode: error.code,
      );
    } catch (_) {
      return const WindowsDriverPreflightResult.failure(
        'The selected Windows driver directory could not be inspected safely.',
      );
    }
  }

  @override
  Future<WindowsDriverPreflightResult> verify({
    required WindowsDriverManifest manifest,
    required int targetDiskNumber,
  }) async {
    try {
      final root = Directory(manifest.rootPath);
      if (!await root.exists() ||
          await FileSystemEntity.type(root.path, followLinks: false) !=
              FileSystemEntityType.directory ||
          await root.resolveSymbolicLinks() != manifest.resolvedRootPath ||
          await _sourceDiskResolver(root.path) != manifest.sourceDiskNumber ||
          manifest.sourceDiskNumber == targetDiskNumber) {
        throw const _WindowsDriverPreflightFailure(
          'The Windows driver source location changed after preflight.',
          code: WindowsDriverPreflightError.sourceChanged,
        );
      }

      final currentPaths = <String>{};
      await for (final entity in root.list(
        recursive: true,
        followLinks: false,
      )) {
        final type = await FileSystemEntity.type(
          entity.path,
          followLinks: false,
        );
        if (type == FileSystemEntityType.link) {
          throw const _WindowsDriverPreflightFailure(
            'The Windows driver source gained a symbolic link or junction after preflight.',
            code: WindowsDriverPreflightError.sourceChanged,
          );
        }
        if (type == FileSystemEntityType.directory) continue;
        if (type != FileSystemEntityType.file || entity is! File) {
          throw _WindowsDriverPreflightFailure(
            'The Windows driver source contains an unsupported file-system entry: ${entity.path}',
            code: WindowsDriverPreflightError.sourceChanged,
          );
        }
        currentPaths.add(_normalizedPath(entity.path));
      }
      final expectedPaths = manifest.entries
          .map((entry) => _normalizedPath(entry.path))
          .toSet();
      if (currentPaths.length != expectedPaths.length ||
          !currentPaths.containsAll(expectedPaths)) {
        throw const _WindowsDriverPreflightFailure(
          'The Windows driver source file set changed after preflight.',
          code: WindowsDriverPreflightError.sourceChanged,
        );
      }

      for (final entry in manifest.entries) {
        final file = File(entry.path);
        if (await FileSystemEntity.type(file.path, followLinks: false) !=
                FileSystemEntityType.file ||
            await file.resolveSymbolicLinks() != entry.resolvedPath ||
            !_isWithinRoot(manifest.resolvedRootPath, entry.resolvedPath) ||
            await file.length() != entry.size ||
            await file.lastModified() != entry.modified ||
            await _sha256File(file) != entry.digest) {
          throw const _WindowsDriverPreflightFailure(
            'The Windows driver source changed after preflight.',
            code: WindowsDriverPreflightError.sourceChanged,
          );
        }
        if (entry.isInf) {
          final infError = await _validateInf(file, entry.path);
          if (infError != null) {
            throw _WindowsDriverPreflightFailure(
              infError,
              code: WindowsDriverPreflightError.sourceChanged,
            );
          }
        }
      }
      if (manifest.infPaths.isEmpty) {
        throw const _WindowsDriverPreflightFailure(
          'The selected Windows driver directory contains no INF files.',
          code: WindowsDriverPreflightError.infRequired,
        );
      }
      log?.call('Windows driver source content digest verification passed.');
      return WindowsDriverPreflightResult.success(manifest);
    } on _WindowsDriverPreflightFailure catch (error) {
      return WindowsDriverPreflightResult.failure(
        error.message,
        errorCode: error.code,
      );
    } catch (_) {
      return const WindowsDriverPreflightResult.failure(
        'The Windows driver source could not be revalidated safely.',
      );
    }
  }

  Future<WindowsDriverManifest> _buildManifest({
    required String sourceDirectory,
    required int targetDiskNumber,
  }) async {
    final requestedPath = sourceDirectory.trim();
    if (!_isLocalDirectoryPath(requestedPath)) {
      throw const _WindowsDriverPreflightFailure(
        'The Windows driver source must be an absolute local directory, not a network or device path.',
        code: WindowsDriverPreflightError.invalidSource,
      );
    }
    final directory = Directory(p.normalize(p.absolute(requestedPath)));
    if (_isVolumeRoot(directory.path)) {
      throw const _WindowsDriverPreflightFailure(
        'The root of a volume cannot be used as a Windows driver source.',
        code: WindowsDriverPreflightError.invalidSource,
      );
    }
    if (!await directory.exists() ||
        await FileSystemEntity.type(directory.path, followLinks: false) !=
            FileSystemEntityType.directory) {
      throw const _WindowsDriverPreflightFailure(
        'The selected Windows driver directory does not exist or is not a normal directory.',
        code: WindowsDriverPreflightError.invalidSource,
      );
    }

    final sourceDiskNumber = await _sourceDiskResolver(directory.path);
    if (sourceDiskNumber == null) {
      throw const _WindowsDriverPreflightFailure(
        'The physical disk containing the Windows driver directory could not be verified.',
        code: WindowsDriverPreflightError.invalidSource,
      );
    }
    if (sourceDiskNumber == targetDiskNumber) {
      throw const _WindowsDriverPreflightFailure(
        'The Windows driver directory is stored on the target disk and would be erased.',
        code: WindowsDriverPreflightError.sourceOnTargetDisk,
      );
    }

    final root = await directory.resolveSymbolicLinks();
    if (!_isWithinOrEqualRoot(directory.path, root)) {
      throw const _WindowsDriverPreflightFailure(
        'The Windows driver directory resolves outside its selected local path.',
        code: WindowsDriverPreflightError.invalidSource,
      );
    }
    final manifest = <WindowsDriverManifestEntry>[];
    var totalBytes = 0;
    await for (final entity in directory.list(
      recursive: true,
      followLinks: false,
    )) {
      if (manifest.length >= _maxEntries) {
        throw const _WindowsDriverPreflightFailure(
          'The Windows driver directory contains more than 8192 files.',
        );
      }
      final type = await FileSystemEntity.type(entity.path, followLinks: false);
      if (type == FileSystemEntityType.link) {
        throw const _WindowsDriverPreflightFailure(
          'Windows driver directories cannot contain symbolic links or junctions.',
          code: WindowsDriverPreflightError.invalidSource,
        );
      }
      if (type == FileSystemEntityType.directory) continue;
      if (type != FileSystemEntityType.file || entity is! File) {
        throw _WindowsDriverPreflightFailure(
          'Windows driver directories may contain only regular files: ${entity.path}',
          code: WindowsDriverPreflightError.invalidSource,
        );
      }
      final resolved = await entity.resolveSymbolicLinks();
      if (!_isWithinRoot(root, resolved)) {
        throw const _WindowsDriverPreflightFailure(
          'A Windows driver file resolves outside the selected directory.',
          code: WindowsDriverPreflightError.invalidSource,
        );
      }
      final size = await entity.length();
      final extension = p.extension(entity.path).toLowerCase();
      if (_unsupportedInstallerExtensions.contains(extension)) {
        throw _WindowsDriverPreflightFailure(
          'Windows driver packages cannot include EXE/MSI installers: '
          '${entity.path}',
          code: WindowsDriverPreflightError.invalidSource,
        );
      }
      final isInf = extension == '.inf';
      if (isInf && size <= 0) {
        throw _WindowsDriverPreflightFailure(
          'Windows driver INF files cannot be empty: ${entity.path}',
          code: WindowsDriverPreflightError.infRequired,
        );
      }
      totalBytes += size;
      if (totalBytes > _maxTotalBytes) {
        throw const _WindowsDriverPreflightFailure(
          'The Windows driver directory exceeds the 4 GB safety limit.',
        );
      }
      if (isInf) {
        final infError = await _validateInf(entity, entity.path);
        if (infError != null) {
          throw _WindowsDriverPreflightFailure(
            infError,
            code: WindowsDriverPreflightError.infRequired,
          );
        }
      }
      manifest.add(
        WindowsDriverManifestEntry(
          path: entity.path,
          resolvedPath: resolved,
          size: size,
          modified: await entity.lastModified(),
          digest: await _sha256File(entity),
          isInf: isInf,
        ),
      );
    }
    if (!manifest.any((entry) => entry.isInf)) {
      throw const _WindowsDriverPreflightFailure(
        'The selected Windows driver directory contains no INF files.',
        code: WindowsDriverPreflightError.infRequired,
      );
    }
    return WindowsDriverManifest(
      rootPath: directory.path,
      resolvedRootPath: root,
      sourceDiskNumber: sourceDiskNumber,
      entries: List.unmodifiable(manifest),
    );
  }

  static Future<String?> _validateInf(File file, String path) async {
    final bytesToRead = (await file.length()).clamp(0, _maxInfHeaderBytes);
    RandomAccessFile? handle;
    try {
      handle = await file.open();
      final bytes = await handle.read(bytesToRead);
      if (bytes.isEmpty) {
        return 'Windows driver INF files cannot be empty: $path';
      }
      // Removing UTF-16 NUL bytes leaves the ASCII section labels intact and
      // also supports legacy ANSI INF files without guessing their code page.
      final text = String.fromCharCodes(bytes).replaceAll('\u0000', '');
      if (!RegExp(r'\[\s*version\s*\]', caseSensitive: false).hasMatch(text)) {
        return 'A Windows driver INF is missing its required [Version] section: $path';
      }
      return null;
    } on FileSystemException {
      return 'A Windows driver INF could not be read safely: $path';
    } finally {
      await handle?.close();
    }
  }

  static Future<String> _sha256File(File file) =>
      BackgroundFileHashService.sha256File(file);

  static bool _isLocalDirectoryPath(String path) {
    final normalized = path.trim();
    if (normalized.startsWith(r'\\') || normalized.startsWith('//')) {
      return false;
    }
    if (Platform.isWindows) {
      return RegExp(r'^[A-Za-z]:[\\/]').hasMatch(normalized);
    }
    return p.isAbsolute(normalized);
  }

  static bool _isVolumeRoot(String path) {
    final normalized = p.normalize(p.absolute(path));
    final root = p.rootPrefix(normalized);
    return root.isNotEmpty &&
        _normalizedPath(normalized) == _normalizedPath(root);
  }

  static bool _isWithinRoot(String root, String candidate) =>
      _isWithinOrEqualRoot(root, candidate);

  static bool _isWithinOrEqualRoot(String root, String candidate) {
    final normalizedRoot = _normalizedPath(root);
    final normalizedCandidate = _normalizedPath(candidate);
    return normalizedRoot == normalizedCandidate ||
        p.isWithin(normalizedRoot, normalizedCandidate);
  }

  static String _normalizedPath(String path) =>
      p.normalize(p.absolute(path.trim())).replaceAll('/', '\\').toUpperCase();

  static Future<int?> _resolveSourceDisk(String path) async {
    try {
      final result = await Process.run(
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
      ).timeout(const Duration(seconds: 10));
      return result.exitCode == 0
          ? int.tryParse(result.stdout.toString().trim())
          : null;
    } catch (_) {
      return null;
    }
  }
}

class _WindowsDriverPreflightFailure implements Exception {
  final String message;
  final WindowsDriverPreflightError code;

  const _WindowsDriverPreflightFailure(
    this.message, {
    this.code = WindowsDriverPreflightError.unavailable,
  });
}

final windowsDriverPreflightProvider = Provider<WindowsDriverPreflight>(
  (ref) => WindowsDriverPreflightService(),
);
