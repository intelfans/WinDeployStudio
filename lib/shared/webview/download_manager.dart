import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../../core/services/background_file_hash_service.dart';
import '../../core/services/global_mirror_download_resolver.dart';
import '../../features/logs/services/log_center_service.dart';

enum DownloadStatus { downloading, paused, completed, cancelled, error }

/// User-facing download failures are stored as localization keys instead of
/// transport exceptions. Network and HTTP exception text can vary by platform
/// and should never leak into the managed download page.
enum DownloadError {
  redirectBlocked,
  responseTimeout,
  invalidResponse,
  incomplete,
  integrityMismatch,
  network,
}

extension DownloadErrorLocalization on DownloadError {
  String get localizationKey {
    return switch (this) {
      DownloadError.redirectBlocked => 'download_error_redirect_blocked',
      DownloadError.responseTimeout => 'download_error_response_timeout',
      DownloadError.invalidResponse => 'webview_download_failed',
      DownloadError.incomplete => 'download_error_incomplete',
      DownloadError.integrityMismatch => 'download_error_integrity_failed',
      DownloadError.network => 'webview_download_failed',
    };
  }
}

/// Thrown only when a redirect hop did not provide response headers in time.
/// The UI maps it to [DownloadError.responseTimeout].
class DownloadResponseTimeoutException implements Exception {
  const DownloadResponseTimeoutException();

  @override
  String toString() => 'Download response header timeout';
}

class DownloadItem {
  final String id;
  final String url;
  final String fileName;
  final String savePath;
  final String? expectedSha256;
  final bool requiresSha256Verification;
  DownloadStatus status;
  double progress;
  int receivedBytes;
  int totalBytes;
  String speed;
  DownloadError? error;
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
    this.expectedSha256,
    this.requiresSha256Verification = false,
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
  static const _responseHeaderTimeout = Duration(seconds: 20);
  static final DownloadManager _instance = DownloadManager._();
  factory DownloadManager() => _instance;
  DownloadManager._()
    : _clientFactory = http.Client.new,
      _responseHeaderTimeoutForRequest = _responseHeaderTimeout;

  @visibleForTesting
  DownloadManager.forTesting({
    required http.Client Function() clientFactory,
    Duration responseHeaderTimeout = _responseHeaderTimeout,
  }) : this._testing(
         clientFactory: clientFactory,
         responseHeaderTimeout: responseHeaderTimeout,
       );

  DownloadManager._testing({
    required this._clientFactory,
    required Duration responseHeaderTimeout,
  }) : _responseHeaderTimeoutForRequest = responseHeaderTimeout;

  final List<DownloadItem> _items = [];
  final http.Client Function() _clientFactory;
  final Duration _responseHeaderTimeoutForRequest;

  List<DownloadItem> get items => List.unmodifiable(_items);
  bool get hasActiveDownloads =>
      _items.any((i) => i.status == DownloadStatus.downloading);

  Future<DownloadItem> startDownload({
    required String url,
    required String fileName,
    required String savePath,
    String? expectedSha256,
  }) async {
    final rawExpectedSha256 = expectedSha256?.trim();
    final normalizedExpectedSha256 = _normalizeSha256(rawExpectedSha256);
    final id = DateTime.now().millisecondsSinceEpoch.toString();
    final item = DownloadItem(
      id: id,
      url: url,
      fileName: fileName,
      savePath: savePath,
      expectedSha256: normalizedExpectedSha256,
      requiresSha256Verification:
          rawExpectedSha256 != null && rawExpectedSha256.isNotEmpty,
    );
    _items.insert(0, item);
    notifyListeners();
    // Starting a download must return immediately so callers can expose the
    // progress panel while the mirror resolution and transfer continue.
    unawaited(_doDownload(item));
    return item;
  }

  Future<void> _doDownload(DownloadItem item) async {
    final transferId = ++item._transferId;
    final client = _clientFactory();
    IOSink? sink;

    bool isCurrentTransfer() =>
        item._transferId == transferId &&
        item.status == DownloadStatus.downloading;

    void failBeforeStreaming(DownloadError error) {
      client.close();
      if (item._transferId != transferId) return;
      if (identical(item._client, client)) item._client = null;
      if (item.status == DownloadStatus.downloading) {
        item.status = DownloadStatus.error;
        item.error = error;
        item.speed = '';
        notifyListeners();
      }
    }

    try {
      if (!isCurrentTransfer()) {
        client.close();
        return;
      }
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
      final resolvedUrl = await GlobalMirrorDownloadResolver.resolve(
        item.url,
        client: client,
      );
      if (item._transferId != transferId) {
        client.close();
        return;
      }
      final requestHeaders = <String, String>{'Accept-Encoding': 'identity'};
      if (canResume) {
        requestHeaders['Range'] = 'bytes=$resumeFrom-';
        requestHeaders['If-Range'] = resumeValidator.value;
      }
      final response = await sendWithValidatedRedirects(
        client,
        Uri.parse(resolvedUrl),
        headers: requestHeaders,
        responseHeaderTimeout: _responseHeaderTimeoutForRequest,
      );

      if (response == null) {
        failBeforeStreaming(DownloadError.redirectBlocked);
        return;
      }

      if (item._transferId != transferId) {
        client.close();
        return;
      }

      final isPartial = canResume && response.statusCode == 206;
      final isFullResponse = response.statusCode == 200;
      if (!isPartial && !isFullResponse) {
        failBeforeStreaming(DownloadError.invalidResponse);
        return;
      }

      final contentEncoding = response.headers['content-encoding']?.trim();
      if (contentEncoding != null &&
          contentEncoding.isNotEmpty &&
          contentEncoding.toLowerCase() != 'identity') {
        failBeforeStreaming(DownloadError.invalidResponse);
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
          failBeforeStreaming(DownloadError.invalidResponse);
          return;
        }
        expectedTotal = contentRange.total;
      } else {
        final fullLength = response.contentLength;
        if (fullLength == null || fullLength <= 0) {
          failBeforeStreaming(DownloadError.invalidResponse);
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
      // Cancellation can happen while mirror resolution or response headers
      // are pending. Check immediately before and after opening the sink so a
      // cancelled transfer cannot create a new file after cleanup has run.
      if (!isCurrentTransfer()) {
        client.close();
        return;
      }
      sink = file.openWrite(mode: isPartial ? FileMode.append : FileMode.write);
      item._sink = sink;
      if (!isCurrentTransfer()) {
        try {
          await sink.close();
        } catch (_) {}
        sink = null;
        await _deleteFileBestEffort(file);
        client.close();
        return;
      }

      int lastBytes = item.receivedBytes;
      DateTime lastTime = DateTime.now();
      var finished = false;

      Future<void> finish({Object? failure}) async {
        if (finished) return;
        finished = true;
        final currentSink = sink;
        try {
          await currentSink?.flush();
        } catch (error) {
          failure ??= error;
        }
        try {
          await currentSink?.close();
        } catch (error) {
          failure ??= error;
        }
        sink = null;
        client.close();

        if (identical(item._sink, currentSink)) item._sink = null;
        if (item._transferId != transferId) {
          if (item.status == DownloadStatus.cancelled) {
            await _deleteFileBestEffort(file);
          }
          return;
        }
        item._sink = null;
        item._subscription = null;
        if (identical(item._client, client)) item._client = null;

        if (item.status == DownloadStatus.cancelled) {
          await _deleteFileBestEffort(file);
        } else if (item.status == DownloadStatus.downloading) {
          final int finalLength;
          try {
            finalLength = await file.length();
          } catch (_) {
            _markDownloadError(item, DownloadError.network);
            return;
          }
          item.receivedBytes = finalLength;
          item.progress = (finalLength / item.totalBytes)
              .clamp(0.0, 1.0)
              .toDouble();
          if (failure != null) {
            _markDownloadError(item, _downloadErrorFor(failure));
          } else if (finalLength != item.totalBytes) {
            _markDownloadError(item, DownloadError.incomplete);
            unawaited(
              LogCenterService().logDownload(
                '[Download]\nURL=${item.url}\nStatus=Failed\nReason=LengthMismatch\nExpected=${item.totalBytes}\nActual=$finalLength',
              ),
            );
          } else if (item.requiresSha256Verification) {
            final expectedSha256 = item.expectedSha256;
            if (expectedSha256 == null) {
              await _deleteFileBestEffort(file);
              _markDownloadError(item, DownloadError.integrityMismatch);
              return;
            }

            String? actualSha256;
            try {
              actualSha256 = await BackgroundFileHashService.sha256File(file);
            } catch (_) {
              actualSha256 = null;
            }
            if (item._transferId != transferId ||
                item.status != DownloadStatus.downloading) {
              if (item.status == DownloadStatus.cancelled) {
                await _deleteFileBestEffort(file);
              }
              return;
            }
            if (actualSha256 == null ||
                !matchesExpectedSha256(actualSha256, expectedSha256)) {
              await _deleteFileBestEffort(file);
              _markDownloadError(item, DownloadError.integrityMismatch);
              unawaited(
                LogCenterService().logDownload(
                  '[Download]\nURL=${item.url}\nStatus=Failed\nReason=IntegrityMismatch',
                ),
              );
              return;
            }
            _markCompleted(item, finalLength);
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
                unawaited(finish(failure: DownloadError.invalidResponse));
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
          _markDownloadError(item, _downloadErrorFor(e));
        }
      } else if (item.status == DownloadStatus.cancelled) {
        await _deleteFileBestEffort(File(item.savePath));
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
    await _deleteFileBestEffort(File(item.savePath));
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

  /// Sends a download request while retaining SourceForge's HTTPS/domain
  /// boundary after mirror resolution. For other download origins, redirects
  /// retain the previous unrestricted behavior.
  @visibleForTesting
  static Future<http.StreamedResponse?> sendWithValidatedRedirects(
    http.Client client,
    Uri initial, {
    required Map<String, String> headers,
    Duration responseHeaderTimeout = _responseHeaderTimeout,
  }) async {
    final initialHost = initial.host.toLowerCase();
    final isSourceForgeOrigin =
        initialHost == 'sourceforge.net' ||
        initialHost.endsWith('.sourceforge.net');
    if (isSourceForgeOrigin &&
        !GlobalMirrorDownloadResolver.isGlobalMirrorUrl(initial)) {
      return null;
    }

    var current = initial;
    for (var redirectCount = 0; redirectCount <= 5; redirectCount++) {
      if (isSourceForgeOrigin &&
          !GlobalMirrorDownloadResolver.isGlobalMirrorUrl(current)) {
        return null;
      }

      final request = http.Request('GET', current)
        ..followRedirects = false
        ..headers.addAll(headers);
      late final http.StreamedResponse response;
      try {
        response = await client.send(request).timeout(responseHeaderTimeout);
      } on TimeoutException {
        throw const DownloadResponseTimeoutException();
      }
      if (!_isRedirectStatus(response.statusCode)) return response;

      final location = response.headers['location'];
      // A redirect body is irrelevant. Cancel it with a bound so a slow or
      // malformed mirror cannot hold the next hop indefinitely.
      try {
        await response.stream
            .listen((_) {})
            .cancel()
            .timeout(responseHeaderTimeout);
      } catch (_) {}
      if (location == null || location.isEmpty) return null;

      final next = current.resolve(location);
      if (isSourceForgeOrigin &&
          !GlobalMirrorDownloadResolver.isGlobalMirrorUrl(next)) {
        return null;
      }
      current = next;
    }
    return null;
  }

  static bool _isRedirectStatus(int statusCode) =>
      statusCode == 301 ||
      statusCode == 302 ||
      statusCode == 303 ||
      statusCode == 307 ||
      statusCode == 308;

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

  void _markDownloadError(DownloadItem item, DownloadError error) {
    item.status = DownloadStatus.error;
    item.error = error;
    item.speed = '';
    notifyListeners();
  }

  DownloadError _downloadErrorFor(Object error) {
    if (error is DownloadError) return error;
    if (error is DownloadResponseTimeoutException) {
      return DownloadError.responseTimeout;
    }
    if (error is GlobalMirrorDownloadResolutionException &&
        error.message.toLowerCase().contains('untrusted')) {
      return DownloadError.redirectBlocked;
    }
    return DownloadError.network;
  }

  Future<void> _deleteFileBestEffort(File file) async {
    // File closure and cancellation can cross on Windows. A few short retries
    // cover the close/delete race without leaving a partial image behind.
    for (var attempt = 0; attempt < 6; attempt++) {
      try {
        if (!await file.exists()) return;
        await file.delete();
        if (!await file.exists()) return;
      } catch (_) {
        // The next retry gives the asynchronously closed sink time to release
        // its file handle.
      }
      if (attempt < 5) {
        await Future<void>.delayed(Duration(milliseconds: 50 * (attempt + 1)));
      }
    }
  }

  static String? _normalizeSha256(String? value) {
    final normalized = value?.trim();
    if (normalized == null ||
        !RegExp(r'^[0-9a-f]{64}$', caseSensitive: false).hasMatch(normalized)) {
      return null;
    }
    return normalized.toUpperCase();
  }

  @visibleForTesting
  static bool matchesExpectedSha256(String actual, String expected) {
    final actualNormalized = _normalizeSha256(actual);
    final expectedNormalized = _normalizeSha256(expected);
    return actualNormalized != null && actualNormalized == expectedNormalized;
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
