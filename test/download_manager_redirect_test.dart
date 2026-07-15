import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:win_deploy_studio/shared/webview/download_manager.dart';

void main() {
  const sourceForgeUrl =
      'https://sourceforge.net/projects/windeploystudio/files/v1.1.2/WinDeployStudio_Setup_1.1.2.exe/download';

  test('blocks an off-domain redirect from a SourceForge download', () async {
    final requests = <http.Request>[];
    final client = MockClient((request) async {
      requests.add(request);
      return http.Response(
        '',
        302,
        headers: {'location': 'https://example.invalid/installer.exe'},
      );
    });

    final response = await DownloadManager.sendWithValidatedRedirects(
      client,
      Uri.parse(sourceForgeUrl),
      headers: const {'Accept-Encoding': 'identity'},
    );

    expect(response, isNull);
    expect(requests, hasLength(1));
    expect(requests.single.followRedirects, isFalse);
  });

  test('follows an HTTPS SourceForge mirror redirect', () async {
    final requests = <http.Request>[];
    final client = MockClient((request) async {
      requests.add(request);
      if (requests.length == 1) {
        return http.Response(
          '',
          302,
          headers: {
            'location':
                'https://master.dl.sourceforge.net/project/windeploystudio/v1.1.2/WinDeployStudio_Setup_1.1.2.exe?fid=test',
          },
        );
      }
      return http.Response.bytes(
        const [0x4d, 0x5a],
        200,
        headers: {'content-type': 'application/octet-stream'},
      );
    });

    final response = await DownloadManager.sendWithValidatedRedirects(
      client,
      Uri.parse(sourceForgeUrl),
      headers: const {'Accept-Encoding': 'identity', 'Range': 'bytes=42-'},
    );

    expect(response, isNotNull);
    expect(response!.statusCode, 200);
    expect(requests, hasLength(2));
    expect(requests[1].url.host, 'master.dl.sourceforge.net');
    expect(requests[1].headers['range'], 'bytes=42-');
    await response.stream.drain<void>();
  });

  test(
    'accepts a direct file response from the HTTPS SourceForge root',
    () async {
      final client = MockClient(
        (_) async => http.Response.bytes(
          const [0x4d, 0x5a],
          200,
          headers: {'content-type': 'application/octet-stream'},
        ),
      );

      final response = await DownloadManager.sendWithValidatedRedirects(
        client,
        Uri.parse(sourceForgeUrl),
        headers: const {'Accept-Encoding': 'identity'},
      );

      expect(response, isNotNull);
      expect(response!.statusCode, 200);
      await response.stream.drain<void>();
    },
  );

  test('rejects an insecure SourceForge initial URL', () async {
    final client = MockClient((_) async {
      fail('The HTTP URL must be rejected before sending a request');
    });

    final response = await DownloadManager.sendWithValidatedRedirects(
      client,
      Uri.parse(sourceForgeUrl.replaceFirst('https://', 'http://')),
      headers: const {'Accept-Encoding': 'identity'},
    );

    expect(response, isNull);
  });
}
