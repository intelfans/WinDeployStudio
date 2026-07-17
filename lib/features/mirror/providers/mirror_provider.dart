import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/legacy.dart';
import '../models/mirror_models.dart';

enum MirrorLoadStatus { initial, loading, loaded, error }

class MirrorState {
  final MirrorLoadStatus status;
  final MirrorListData? data;
  final String? error;
  final List<LocalIsoInfo> localIsos;

  const MirrorState({
    this.status = MirrorLoadStatus.initial,
    this.data,
    this.error,
    this.localIsos = const [],
  });

  MirrorState copyWith({
    MirrorLoadStatus? status,
    MirrorListData? data,
    String? error,
    List<LocalIsoInfo>? localIsos,
  }) {
    return MirrorState(
      status: status ?? this.status,
      data: data ?? this.data,
      error: error ?? this.error,
      localIsos: localIsos ?? this.localIsos,
    );
  }
}

final mirrorProvider = StateNotifierProvider<MirrorNotifier, MirrorState>(
  (ref) => MirrorNotifier(),
);

class MirrorNotifier extends StateNotifier<MirrorState> {
  /// The local-library view is intentionally bounded.  It is a convenience
  /// index, not a full disk crawler, so an accidentally selected drive root or
  /// network share must not keep the UI waiting indefinitely.
  static const int maxLocalDirectoryEntries = 20000;
  static const int maxLocalIsoResults = 500;
  static const Duration maxLocalScanDuration = Duration(seconds: 20);
  static const Duration _rootProbeTimeout = Duration(seconds: 5);
  static const Duration _fileMetadataTimeout = Duration(seconds: 2);

  MirrorNotifier() : _beforeLocalIsoScan = null, super(const MirrorState());

  @visibleForTesting
  MirrorNotifier.withLocalIsoScanHook(
    Future<void> Function(String path) beforeLocalIsoScan,
  ) : _beforeLocalIsoScan = beforeLocalIsoScan,
      super(const MirrorState());

  final Future<void> Function(String path)? _beforeLocalIsoScan;
  int _localIsoScanGeneration = 0;
  bool _isDisposed = false;

  Future<void> loadBuiltInMirrors({bool force = false}) async {
    if (!force && state.status == MirrorLoadStatus.loaded) return;

    state = state.copyWith(status: MirrorLoadStatus.loading);

    try {
      final asset = await rootBundle.load('data/mirrors.json');
      final jsonStr = utf8.decode(asset.buffer.asUint8List());
      final json = jsonDecode(jsonStr) as Map<String, dynamic>;
      final data = MirrorListData.fromJson(json);

      debugPrint('Built-in mirrors loaded: ${data.items.length} items');
      state = state.copyWith(status: MirrorLoadStatus.loaded, data: data);
    } catch (e) {
      debugPrint('Failed to load built-in mirrors: $e');
      state = state.copyWith(
        status: MirrorLoadStatus.error,
        error: e.toString(),
      );
    }
  }

  /// Index ISO files under [dirPath] for the local image library.
  ///
  /// Starting another scan, calling [clearLocalIsos], or disposing this
  /// notifier cancels the current scan cooperatively.  The method deliberately
  /// keeps its original public signature so existing callers can continue to
  /// await it unchanged.
  Future<void> scanLocalDirectory(String dirPath) async {
    final generation = ++_localIsoScanGeneration;
    final normalizedPath = dirPath.trim();

    if (normalizedPath.isEmpty) {
      _commitLocalIsos(generation, const []);
      return;
    }

    try {
      final beforeScan = _beforeLocalIsoScan;
      if (beforeScan != null) {
        await beforeScan(normalizedPath);
      }
      if (!_isCurrentLocalIsoScan(generation)) return;

      // An unreachable UNC root can block at the filesystem boundary before a
      // directory stream has a chance to yield.  The image library only
      // indexes local folders; mapped drives remain bounded by the scan limits
      // below.
      if (_isUncPath(normalizedPath)) {
        debugPrint('Skipped local ISO scan for network path: $normalizedPath');
        _commitLocalIsos(generation, const []);
        return;
      }

      final directory = Directory(normalizedPath);
      final rootType = await FileSystemEntity.type(
        directory.path,
        followLinks: false,
      ).timeout(_rootProbeTimeout);
      if (!_isCurrentLocalIsoScan(generation)) return;

      // Do not treat a symlink/junction as a library root.  Scanning through a
      // link can unexpectedly crawl another volume or a network location.
      if (rootType != FileSystemEntityType.directory) {
        debugPrint('Skipped local ISO scan for non-directory: $normalizedPath');
        _commitLocalIsos(generation, const []);
        return;
      }

      final isos = await _collectLocalIsos(directory, generation);
      if (!_isCurrentLocalIsoScan(generation)) return;

      isos.sort((left, right) {
        final byName = left.fileName.toLowerCase().compareTo(
          right.fileName.toLowerCase(),
        );
        return byName != 0
            ? byName
            : left.filePath.toLowerCase().compareTo(
                right.filePath.toLowerCase(),
              );
      });
      debugPrint('Local ISOs found: ${isos.length} in $normalizedPath');
      _commitLocalIsos(generation, isos);
    } on TimeoutException catch (error) {
      debugPrint('Timed out while scanning local ISO directory: $error');
      _commitLocalIsos(generation, const []);
    } on FileSystemException catch (error) {
      debugPrint('Failed to scan local ISO directory: $error');
      _commitLocalIsos(generation, const []);
    } catch (error, stackTrace) {
      debugPrint('Failed to scan local ISO directory: $error\n$stackTrace');
      _commitLocalIsos(generation, const []);
    }
  }

  Future<List<LocalIsoInfo>> _collectLocalIsos(
    Directory directory,
    int generation,
  ) async {
    final isos = <LocalIsoInfo>[];
    final stopwatch = Stopwatch()..start();
    var entriesSeen = 0;

    try {
      final entries = directory
          .list(recursive: true, followLinks: false)
          .timeout(
            maxLocalScanDuration,
            onTimeout: (sink) {
              sink.addError(
                TimeoutException(
                  'No directory entry arrived within '
                  '${maxLocalScanDuration.inSeconds} seconds.',
                ),
              );
              sink.close();
            },
          )
          .handleError((Object error, StackTrace stackTrace) {
            if (error is TimeoutException) {
              debugPrint('Local ISO directory stream timed out: $error');
            } else {
              debugPrint('Skipped inaccessible local ISO scan entry: $error');
            }
          });

      await for (final entity in entries) {
        if (!_isCurrentLocalIsoScan(generation)) return isos;
        if (stopwatch.elapsed >= maxLocalScanDuration) {
          debugPrint(
            'Stopped local ISO scan after ${maxLocalScanDuration.inSeconds}s: '
            '${directory.path}',
          );
          return isos;
        }
        if (++entriesSeen > maxLocalDirectoryEntries) {
          debugPrint(
            'Stopped local ISO scan after $maxLocalDirectoryEntries entries: '
            '${directory.path}',
          );
          return isos;
        }
        if (entity is! File || !entity.path.toLowerCase().endsWith('.iso')) {
          continue;
        }

        // Directory.list(..., followLinks: false) yields links as Link
        // entities. Recheck the type before obtaining file metadata and skip
        // links encountered during the scan.
        try {
          final entityType = await FileSystemEntity.type(
            entity.path,
            followLinks: false,
          ).timeout(_fileMetadataTimeout);
          if (!_isCurrentLocalIsoScan(generation)) return isos;
          if (entityType != FileSystemEntityType.file) continue;

          final fileSize = await entity.length().timeout(_fileMetadataTimeout);
          if (!_isCurrentLocalIsoScan(generation)) return isos;
          isos.add(
            LocalIsoInfo(
              filePath: entity.path,
              fileName: entity.path.split(Platform.pathSeparator).last,
              fileSize: fileSize,
            ),
          );
          if (isos.length >= maxLocalIsoResults) {
            debugPrint(
              'Stopped local ISO scan after $maxLocalIsoResults ISO files: '
              '${directory.path}',
            );
            return isos;
          }
        } on FileSystemException catch (error) {
          debugPrint('Skipped unreadable ISO candidate ${entity.path}: $error');
        } on TimeoutException catch (error) {
          debugPrint('Skipped slow ISO candidate ${entity.path}: $error');
        }
      }
    } on FileSystemException catch (error) {
      // Keep already indexed files when a single protected subtree ends the
      // underlying directory stream.
      debugPrint('Local ISO directory stream stopped: $error');
    } on TimeoutException catch (error) {
      debugPrint('Local ISO directory stream timed out: $error');
    }

    return isos;
  }

  bool _isCurrentLocalIsoScan(int generation) =>
      !_isDisposed && generation == _localIsoScanGeneration;

  void _commitLocalIsos(int generation, List<LocalIsoInfo> isos) {
    if (_isCurrentLocalIsoScan(generation)) {
      state = state.copyWith(localIsos: List.unmodifiable(isos));
    }
  }

  bool _isUncPath(String path) {
    if (!Platform.isWindows) return false;
    final normalized = path.replaceAll('/', '\\');
    if (!normalized.startsWith(r'\\')) return false;
    // \\?\ and \\.\ are local Windows device namespace prefixes, not UNC
    // shares. Treat ordinary \\server\share paths as network roots.
    return !(normalized.startsWith('\\\\?\\') ||
        normalized.startsWith('\\\\.\\'));
  }

  /// Cooperatively stops an active local-library scan.
  void cancelLocalDirectoryScan({bool clearResults = false}) {
    _localIsoScanGeneration++;
    if (clearResults && !_isDisposed) {
      state = state.copyWith(localIsos: const []);
    }
  }

  void clearLocalIsos() {
    cancelLocalDirectoryScan(clearResults: true);
  }

  @override
  void dispose() {
    _isDisposed = true;
    _localIsoScanGeneration++;
    super.dispose();
  }
}
