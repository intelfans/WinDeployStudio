import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

enum DownloadStatus { downloading, paused, completed, cancelled, error }

class DownloadItem {
  final String id;
  final String url;
  String fileName;
  String savePath;
  DownloadStatus status;
  double progress;
  int receivedBytes;
  int totalBytes;
  String speed;
  String? error;
  DateTime startTime;
  IOSink? _sink;
  StreamSubscription<List<int>>? _subscription;
  http.Client? _client;

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
  bool get hasActiveDownloads => _items.any((i) => i.status == DownloadStatus.downloading);

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
    try {
      final client = http.Client();
      item._client = client;

      final request = http.Request('GET', Uri.parse(item.url));
      final response = await client.send(request);

      if (response.statusCode != 200) {
        item.status = DownloadStatus.error;
        item.error = 'HTTP ${response.statusCode}';
        notifyListeners();
        return;
      }

      // Try Content-Disposition for real filename
      final disposition = response.headers['content-disposition'];
      if (disposition != null) {
        final realName = _parseContentDisposition(disposition);
        if (realName != null && realName.isNotEmpty) {
          item.fileName = realName;
          item.savePath = p.join(p.dirname(item.savePath), realName);
        }
      }

      item.totalBytes = response.contentLength ?? 0;
      item.receivedBytes = 0;
      item.progress = 0;

      final file = File(item.savePath);
      final sink = file.openWrite();
      item._sink = sink;

      int lastBytes = 0;
      DateTime lastTime = DateTime.now();

      final sub = response.stream.listen(
        (chunk) {
          if (item.status == DownloadStatus.cancelled) return;
          if (item.status == DownloadStatus.paused) return;

          sink.add(chunk);
          item.receivedBytes += chunk.length;

          if (item.totalBytes > 0) {
            item.progress = item.receivedBytes / item.totalBytes;
          }

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
        onDone: () async {
          await sink.close();
          item._sink = null;
          if (item.status == DownloadStatus.cancelled) {
            try { await file.delete(); } catch (_) {}
          } else if (item.status != DownloadStatus.paused) {
            item.status = DownloadStatus.completed;
            item.progress = 1.0;
            item.speed = '';
            notifyListeners();
          }
          item._subscription = null;
          item._client = null;
        },
        onError: (e) async {
          await sink.close();
          item._sink = null;
          item.status = DownloadStatus.error;
          item.error = e.toString();
          notifyListeners();
          item._subscription = null;
          item._client = null;
        },
        cancelOnError: true,
      );

      item._subscription = sub;
    } catch (e) {
      item.status = DownloadStatus.error;
      item.error = e.toString();
      notifyListeners();
    }
  }

  void pauseDownload(String id) {
    final item = _items.firstWhere((i) => i.id == id);
    if (item.status != DownloadStatus.downloading) return;
    item.status = DownloadStatus.paused;
    item.speed = '';
    item._subscription?.cancel();
    item._client?.close();
    item._sink?.close();
    item._subscription = null;
    item._client = null;
    item._sink = null;
    notifyListeners();
  }

  void resumeDownload(String id) {
    final item = _items.firstWhere((i) => i.id == id);
    if (item.status != DownloadStatus.paused) return;
    item.status = DownloadStatus.downloading;
    item.speed = '';
    notifyListeners();
    _doDownload(item);
  }

  void cancelDownload(String id) {
    final item = _items.firstWhere((i) => i.id == id);
    item.status = DownloadStatus.cancelled;
    item._subscription?.cancel();
    item._client?.close();
    item._sink?.close();
    item._subscription = null;
    item._client = null;
    item._sink = null;
    notifyListeners();
  }

  void removeItem(String id) {
    _items.removeWhere((i) => i.id == id);
    notifyListeners();
  }

  void clearCompleted() {
    _items.removeWhere((i) =>
        i.status == DownloadStatus.completed ||
        i.status == DownloadStatus.cancelled ||
        i.status == DownloadStatus.error);
    notifyListeners();
  }

  String? _parseContentDisposition(String disposition) {
    final rfc5987 = RegExp(r"filename\*\s*=\s*UTF-8''(.+)", caseSensitive: false);
    final m1 = rfc5987.firstMatch(disposition);
    if (m1 != null) return Uri.decodeComponent(m1.group(1)!.trim());

    final rfc5987any = RegExp(r"filename\*\s*=\s*[^']+'[^']*'(.+)", caseSensitive: false);
    final m2 = rfc5987any.firstMatch(disposition);
    if (m2 != null) return Uri.decodeComponent(m2.group(1)!.trim());

    final plain = RegExp(r'filename\s*=\s*("?)([^";\r\n]*)\1', caseSensitive: false);
    final m3 = plain.firstMatch(disposition);
    if (m3 != null) {
      var name = m3.group(2)!.trim();
      if (name.contains('%')) {
        try { name = Uri.decodeComponent(name); } catch (_) {}
      }
      return name;
    }
    return null;
  }

  String _formatSpeed(double bytesPerSec) {
    if (bytesPerSec < 1024) return '${bytesPerSec.toStringAsFixed(0)} B/s';
    if (bytesPerSec < 1024 * 1024) return '${(bytesPerSec / 1024).toStringAsFixed(1)} KB/s';
    return '${(bytesPerSec / (1024 * 1024)).toStringAsFixed(1)} MB/s';
  }
}
