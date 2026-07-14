import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../../core/services/sourceforge_download_resolver.dart';
import '../../features/logs/services/log_center_service.dart';

enum DownloadStatus { downloading, paused, completed, cancelled, error }

class DownloadItem {
  final String id;
  final String url;
  final String fileName;
  final String savePath;
  DownloadStatus status;
  double progress;
  int receivedBytes;
  int totalBytes;
  String speed;
  String? error;
  DateTime startTime;
  String? eTag;
  String? lastModified;
  IOSink? _sink;
  StreamSubscription<List<int>>? _subscription;
  http.Client? _client;
  int _transferId = 0;

  DownloadItem({
    required this.id,
    required this.url,
    required this.fileName,
    required this.savePath,
    this.status = DownloadStatus.downloading,
    this.progress = 0,
    this.receivedBytes = 0,
    this.totalBytes = 0,
    this.speed = '',
    this.error,
    DateTime? startTime,
  }) : startTime = startTime ?? DateTime.now();
}

class DownloadManager extends ChangeNotifier {
  static final DownloadManager _instance = DownloadManager._();
  factory DownloadManager() => _instance;
  DownloadManager._();

  final List<DownloadItem> _items = [];

  List<DownloadItem> get items => List.unmodifiable(_items);
  bool get hasActiveDownloads =>
      _items.any((i) => i.status == DownloadStatus.downloading);

  Future<void> startDownload({
    required String url,
    required String fileName,
    required String savePath,
  }) async {
    final id = DateTime.now().millisecondsSinceEpoch.toString();
    final item = DownloadItem(
      id: id,
      url: url,
      fileName: fileName,
      savePath: savePath,
    );
    _items.insert(0, item);
    notifyListeners();
    await _doDownload(item);
  }

  Future<void> _doDownload(DownloadItem item) async {
    final transferId = ++item._transferId;
    final client = http.Client();
    IOSink? sink;

    void failBeforeStreaming(String message) {
      client.close();
      if (item._transferId != transferId) return;
      if (identical(item._client, client)) item._client = null;
      if (item.status == DownloadStatus.downloading) {
        item.status = DownloadStatus.error;
        item.error = message;
        item.speed = '';
        notifyListeners();
      }
    }

    try {
      item._client = client;

      final existingFile = File(item.savePath);
      final localLength = await existingFile.exists()
          ? await existingFile.length()
          : 0;
      final previousTotal = item.totalBytes;
      final resumeValidator = _resumeValidator(item);
      final canResume =
          localLength > 0 &&
          previousTotal > localLength &&
          resumeValidator != null;
      final resumeFrom = canResume ? localLength : 0;
      final resolvedUrl = await SourceForgeDownloadResolver.resolve(item.url);
      if (item._transferId != transferId) {
        client.close();
        return;
      }
      final request = http.Request('GET', Uri.parse(resolvedUrl))
        ..headers['Accept-Encoding'] = 'identity';
      if (canResume) {
        request.headers['Range'] = 'bytes=$resumeFrom-';
        request.headers['If-Range'] = resumeValidator.value;
      }
      final response = await client.send(request);

      if (item._transferId != transferId) {
        client.close();
        return;
      }

      final isPartial = canResume && response.statusCode == 206;
      final isFullResponse = response.statusCode == 200;
      if (!isPartial && !isFullResponse) {
        failBeforeStreaming('HTTP ${response.statusCode}');
        return;
      }

      final contentEncoding = response.headers['content-encoding']?.trim();
      if (contentEncoding != null &&
          contentEncoding.isNotEmpty &&
          contentEncoding.toLowerCase() != 'identity') {
        failBeforeStreaming('Unsupported Content-Encoding');
        return;
      }

      final responseETag = response.headers['etag'];
      final responseLastModified = response.headers['last-modified'];
      late final int expectedTotal;
      if (isPartial) {
        final contentRange = _parseContentRange(
          response.headers['content-range'],
        );
        final expectedRemaining = previousTotal - resumeFrom;
        if (contentRange == null ||
            contentRange.start != resumeFrom ||
            contentRange.end != contentRange.total - 1 ||
            contentRange.total != previousTotal ||
            (response.contentLength != null &&
                response.contentLength != expectedRemaining) ||
            !_validatorMatches(
              resumeValidator,
              responseETag,
              responseLastModified,
            )) {
          failBeforeStreaming('Invalid resume response');
          return;
        }
        expectedTotal = contentRange.total;
      } else {
        final fullLength = response.contentLength;
        if (fullLength == null || fullLength <= 0) {
          failBeforeStreaming('Missing Content-Length');
          return;
        }
        expectedTotal = fullLength;
        item.eTag = responseETag?.trim();
        item.lastModified = responseLastModified?.trim();
      }

      item.totalBytes = expectedTotal;
      item.receivedBytes = isPartial ? resumeFrom : 0;
      item.progress = item.receivedBytes / item.totalBytes;
      item.error = null;

      final file = File(item.savePath);
      sink = file.openWrite(mode: isPartial ? FileMode.append : FileMode.write);
      item._sink = sink;

      int lastBytes = item.receivedBytes;
      DateTime lastTime = DateTime.now();
      var finished = false;

      Future<void> finish({Object? failure}) async {
        if (finished) return;
        finished = true;
        try {
          await sink?.flush();
        } catch (error) {
          failure ??= error;
        }
        try {
          await sink?.close();
        } catch (error) {
          failure ??= error;
        }
        sink = null;
        client.close();

        if (item._transferId != transferId) return;
        item._sink = null;
        item._subscription = null;
        if (identical(item._client, client)) item._client = null;

        if (item.status == DownloadStatus.cancelled) {
          try {
            if (await file.exists()) await file.delete();
          } catch (_) {}
        } else if (item.status == DownloadStatus.downloading) {
          final finalLength = await file.length();
          item.receivedBytes = finalLength;
          item.progress = finalLength / item.totalBytes;
          if (failure != null) {
            item.status = DownloadStatus.error;
            item.error = failure.toString();
          } else if (finalLength != item.totalBytes) {
            item.status = DownloadStatus.error;
            item.error = 'Incomplete download';
            notifyListeners();
            unawaited(
              LogCenterService().logDownload(
                '[Download]\nURL=${item.url}\nStatus=Failed\nReason=LengthMismatch\nExpected=${item.totalBytes}\nActual=$finalLength',
              ),
            );
          } else {
            _markCompleted(item, finalLength);
          }
        }
      }

      final sub = response.stream
          .timeout(const Duration(seconds: 60))
          .listen(
            (chunk) {
              if (finished ||
                  item._transferId != transferId ||
                  item.status != DownloadStatus.downloading) {
                return;
              }
              if (item.receivedBytes + chunk.length > item.totalBytes) {
                unawaited(finish(failure: 'Response exceeded expected length'));
                return;
              }

              sink?.add(chunk);
              item.receivedBytes += chunk.length;
              item.progress = item.receivedBytes / item.totalBytes;

              final now = DateTime.now();
              final elapsed = now.difference(lastTime).inMilliseconds;
              if (elapsed >= 500) {
                final bytesInPeriod = item.receivedBytes - lastBytes;
                final bytesPerSec = bytesInPeriod * 1000 / elapsed;
                item.speed = _formatSpeed(bytesPerSec);
                lastBytes = item.receivedBytes;
                lastTime = now;
              }

              notifyListeners();
            },
            onDone: () => unawaited(finish()),
            onError: (Object error) => unawaited(finish(failure: error)),
            cancelOnError: true,
          );

      item._subscription = sub;
    } catch (e) {
      try {
        await sink?.close();
      } catch (_) {}
      client.close();
      if (item._transferId == transferId) {
        item._sink = null;
        item._subscription = null;
        if (identical(item._client, client)) item._client = null;
        if (item.status == DownloadStatus.downloading) {
          item.status = DownloadStatus.error;
          item.error = e.toString();
          item.speed = '';
          notifyListeners();
        }
      }
    }
  }

  Future<void> pauseDownload(String id) async {
    final item = _items.firstWhere((i) => i.id == id);
    if (item.status != DownloadStatus.downloading) return;
    item.status = DownloadStatus.paused;
    item._transferId++;
    item.speed = '';
    final subscription = item._subscription;
    final client = item._client;
    final sink = item._sink;
    item._subscription = null;
    item._client = null;
    item._sink = null;
    await subscription?.cancel();
    client?.close();
    try {
      await sink?.flush();
    } catch (_) {}
    try {
      await sink?.close();
    } catch (_) {}
    final file = File(item.savePath);
    if (await file.exists()) {
      item.receivedBytes = await file.length();
      item.progress = item.totalBytes > 0
          ? (item.receivedBytes / item.totalBytes).clamp(0.0, 1.0)
          : 0;
    }
    notifyListeners();
  }

  Future<void> resumeDownload(String id) async {
    final item = _items.firstWhere((i) => i.id == id);
    if (item.status != DownloadStatus.paused) return;
    item.status = DownloadStatus.downloading;
    item.speed = '';
    item.error = null;
    notifyListeners();
    await _doDownload(item);
  }

  Future<void> cancelDownload(String id) async {
    final item = _items.firstWhere((i) => i.id == id);
    item.status = DownloadStatus.cancelled;
    item._transferId++;
    final subscription = item._subscription;
    final client = item._client;
    final sink = item._sink;
    item._subscription = null;
    item._client = null;
    item._sink = null;
    await subscription?.cancel();
    client?.close();
    try {
      await sink?.close();
    } catch (_) {}
    try {
      final file = File(item.savePath);
      if (await file.exists()) await file.delete();
    } catch (_) {}
    notifyListeners();
  }

  void removeItem(String id) {
    _items.removeWhere((i) => i.id == id);
    notifyListeners();
  }

  void clearCompleted() {
    _items.removeWhere(
      (i) =>
          i.status == DownloadStatus.completed ||
          i.status == DownloadStatus.cancelled ||
          i.status == DownloadStatus.error,
    );
    notifyListeners();
  }

  _ContentRange? _parseContentRange(String? contentRange) {
    if (contentRange == null) return null;
    final match = RegExp(
      r'^bytes\s+(\d+)-(\d+)/(\d+)$',
      caseSensitive: false,
    ).firstMatch(contentRange.trim());
    if (match == null) return null;
    final start = int.tryParse(match.group(1)!);
    final end = int.tryParse(match.group(2)!);
    final total = int.tryParse(match.group(3)!);
    if (start == null ||
        end == null ||
        total == null ||
        start < 0 ||
        end < start ||
        total <= end) {
      return null;
    }
    return _ContentRange(start, end, total);
  }

  _ResumeValidator? _resumeValidator(DownloadItem item) {
    final eTag = item.eTag?.trim();
    if (eTag != null &&
        eTag.length >= 2 &&
        eTag.startsWith('"') &&
        eTag.endsWith('"') &&
        !eTag.toLowerCase().startsWith('w/')) {
      return _ResumeValidator(eTag, isETag: true);
    }
    final lastModified = item.lastModified?.trim();
    if (lastModified != null && lastModified.isNotEmpty) {
      return _ResumeValidator(lastModified, isETag: false);
    }
    return null;
  }

  bool _validatorMatches(
    _ResumeValidator validator,
    String? responseETag,
    String? responseLastModified,
  ) {
    final responseValue = validator.isETag
        ? responseETag?.trim()
        : responseLastModified?.trim();
    return responseValue == validator.value;
  }

  void _markCompleted(DownloadItem item, int finalLength) {
    item.status = DownloadStatus.completed;
    item.progress = 1.0;
    item.speed = '';
    notifyListeners();
    unawaited(
      LogCenterService().logDownload(
        '[Download]\nURL=${item.url}\nPath=${item.savePath}\nStatus=Success\nBytes=$finalLength',
      ),
    );
  }

  String _formatSpeed(double bytesPerSec) {
    if (bytesPerSec < 1024) {
      return '${bytesPerSec.toStringAsFixed(0)} B/s';
    }
    if (bytesPerSec < 1024 * 1024) {
      return '${(bytesPerSec / 1024).toStringAsFixed(1)} KB/s';
    }
    return '${(bytesPerSec / (1024 * 1024)).toStringAsFixed(1)} MB/s';
  }
}

class _ContentRange {
  final int start;
  final int end;
  final int total;

  const _ContentRange(this.start, this.end, this.total);
}

class _ResumeValidator {
  final String value;
  final bool isETag;

  const _ResumeValidator(this.value, {required this.isETag});
}
