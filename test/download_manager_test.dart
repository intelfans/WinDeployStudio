import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:win_deploy_studio/shared/webview/download_manager.dart';

void main() {
  late Directory tempDirectory;

  setUp(() async {
    tempDirectory = await Directory.systemTemp.createTemp('wds-download-test-');
  });

  tearDown(() async {
    if (await tempDirectory.exists()) {
      await tempDirectory.delete(recursive: true);
    }
  });

  test('times out while waiting for the first response headers', () async {
    final pendingResponse = Completer<http.Response>();
    final client = MockClient((_) => pendingResponse.future);

    await expectLater(
      DownloadManager.sendWithValidatedRedirects(
        client,
        Uri.parse('https://downloads.example/first.iso'),
        headers: const {'Accept-Encoding': 'identity'},
        responseHeaderTimeout: const Duration(milliseconds: 10),
      ),
      throwsA(isA<DownloadResponseTimeoutException>()),
    );
  });

  test('times out while waiting for a later redirect response', () async {
    final pendingResponse = Completer<http.Response>();
    var requestCount = 0;
    final client = MockClient((_) {
      requestCount++;
      if (requestCount == 1) {
        return Future.value(
          http.Response('', 302, headers: {'location': '/next.iso'}),
        );
      }
      return pendingResponse.future;
    });

    await expectLater(
      DownloadManager.sendWithValidatedRedirects(
        client,
        Uri.parse('https://downloads.example/start.iso'),
        headers: const {'Accept-Encoding': 'identity'},
        responseHeaderTimeout: const Duration(milliseconds: 10),
      ),
      throwsA(isA<DownloadResponseTimeoutException>()),
    );
    expect(requestCount, 2);
  });

  test('completes a known image only after its SHA-256 matches', () async {
    const bytes = <int>[0x57, 0x44, 0x53, 0x21];
    final expectedSha256 = sha256.convert(bytes).toString();
    final manager = DownloadManager.forTesting(
      clientFactory: () => _bytesClient(bytes),
    );
    final target = File(
      '${tempDirectory.path}${Platform.pathSeparator}known.iso',
    );

    final item = await manager.startDownload(
      url: 'https://downloads.example/known.iso',
      fileName: 'known.iso',
      savePath: target.path,
      expectedSha256: expectedSha256,
    );
    await _waitForTerminalState(item);

    expect(item.status, DownloadStatus.completed);
    expect(item.error, isNull);
    expect(await target.readAsBytes(), bytes);
  });

  test('deletes a known image when its SHA-256 does not match', () async {
    const bytes = <int>[0x57, 0x44, 0x53, 0x21];
    final manager = DownloadManager.forTesting(
      clientFactory: () => _bytesClient(bytes),
    );
    final target = File(
      '${tempDirectory.path}${Platform.pathSeparator}mismatch.iso',
    );

    final item = await manager.startDownload(
      url: 'https://downloads.example/mismatch.iso',
      fileName: 'mismatch.iso',
      savePath: target.path,
      expectedSha256: '0' * 64,
    );
    await _waitForTerminalState(item);

    expect(item.status, DownloadStatus.error);
    expect(item.error, DownloadError.integrityMismatch);
    expect(await target.exists(), isFalse);
  });

  test('allows generic downloads without a known SHA-256', () async {
    const bytes = <int>[0x47, 0x45, 0x4e, 0x45, 0x52, 0x49, 0x43];
    final manager = DownloadManager.forTesting(
      clientFactory: () => _bytesClient(bytes),
    );
    final target = File(
      '${tempDirectory.path}${Platform.pathSeparator}generic.iso',
    );

    final item = await manager.startDownload(
      url: 'https://downloads.example/generic.iso',
      fileName: 'generic.iso',
      savePath: target.path,
    );
    await _waitForTerminalState(item);

    expect(item.status, DownloadStatus.completed);
    expect(item.error, isNull);
    expect(await target.readAsBytes(), bytes);
  });

  test(
    'cancellation removes a target that was still waiting for headers',
    () async {
      final client = _HeaderBlockingClient();
      final manager = DownloadManager.forTesting(clientFactory: () => client);
      final target = File(
        '${tempDirectory.path}${Platform.pathSeparator}cancelled.iso',
      );

      final item = await manager.startDownload(
        url: 'https://downloads.example/cancelled.iso',
        fileName: 'cancelled.iso',
        savePath: target.path,
      );
      await client.requestSeen.future;
      await manager.cancelDownload(item.id);
      client.respond(
        http.StreamedResponse(
          Stream<List<int>>.fromIterable(const [
            <int>[0x01, 0x02],
          ]),
          200,
          contentLength: 2,
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 80));

      expect(item.status, DownloadStatus.cancelled);
      expect(await target.exists(), isFalse);
    },
  );

  test('cancellation deletes a target that was opened for streaming', () async {
    final client = _StreamingClient();
    final manager = DownloadManager.forTesting(clientFactory: () => client);
    final target = File(
      '${tempDirectory.path}${Platform.pathSeparator}stream-cancelled.iso',
    );

    final item = await manager.startDownload(
      url: 'https://downloads.example/stream-cancelled.iso',
      fileName: 'stream-cancelled.iso',
      savePath: target.path,
    );
    await client.requestSeen.future;
    client.add(const [0x01, 0x02]);
    await _waitForFile(target);

    await manager.cancelDownload(item.id);
    await client.closeStream();
    await Future<void>.delayed(const Duration(milliseconds: 80));

    expect(item.status, DownloadStatus.cancelled);
    expect(await target.exists(), isFalse);
  });
}

http.Client _bytesClient(List<int> bytes) {
  return MockClient(
    (_) async => http.Response.bytes(
      bytes,
      200,
      headers: {'content-length': '${bytes.length}'},
    ),
  );
}

Future<void> _waitForTerminalState(DownloadItem item) async {
  for (var attempt = 0; attempt < 100; attempt++) {
    if (item.status != DownloadStatus.downloading) return;
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  fail('Download did not reach a terminal state.');
}

Future<void> _waitForFile(File file) async {
  for (var attempt = 0; attempt < 100; attempt++) {
    if (await file.exists()) return;
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  fail('Download target was not opened.');
}

class _HeaderBlockingClient extends http.BaseClient {
  final Completer<void> requestSeen = Completer<void>();
  final Completer<http.StreamedResponse> _response =
      Completer<http.StreamedResponse>();

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    if (!requestSeen.isCompleted) requestSeen.complete();
    return _response.future;
  }

  void respond(http.StreamedResponse response) {
    if (!_response.isCompleted) _response.complete(response);
  }
}

class _StreamingClient extends http.BaseClient {
  final Completer<void> requestSeen = Completer<void>();
  final StreamController<List<int>> _chunks = StreamController<List<int>>();

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (!requestSeen.isCompleted) requestSeen.complete();
    return http.StreamedResponse(_chunks.stream, 200, contentLength: 4);
  }

  void add(List<int> bytes) => _chunks.add(bytes);

  Future<void> closeStream() => _chunks.close();
}
