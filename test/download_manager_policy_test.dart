import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:win_deploy_studio/shared/webview/download_manager.dart';

void main() {
  test('refuses a plaintext initial download URL', () {
    expect(
      DownloadManager.isAllowedDownloadUri(Uri.parse('http://example.com/a.iso')),
      isFalse,
    );
  });

  test('refuses loopback, link-local and RFC1918 targets', () {
    for (final host in <String>[
      '127.0.0.1',
      'localhost',
      '10.1.2.3',
      '172.16.0.9',
      '192.168.1.10',
      '169.254.1.1',
    ]) {
      expect(
        DownloadManager.isAllowedDownloadUri(Uri.parse('https://$host/a.iso')),
        isFalse,
        reason: host,
      );
    }
  });

  test('allows a public HTTPS target', () {
    expect(
      DownloadManager.isAllowedDownloadUri(
        Uri.parse('https://mirror.example.org/a.iso'),
      ),
      isTrue,
    );
  });

  test('refuses a redirect that downgrades a public download to plaintext', () async {
    var calls = 0;
    final client = MockClient((request) async {
      calls++;
      return http.Response('', 302, headers: {
        'location': 'http://mirror.example.org/a.iso',
      });
    });

    final response = await DownloadManager.sendWithValidatedRedirects(
      client,
      Uri.parse('https://mirror.example.org/a.iso'),
      headers: const {'Accept-Encoding': 'identity'},
    );

    expect(response, isNull);
    expect(calls, 1);
  });

  test('refuses a redirect into the local network', () async {
    var calls = 0;
    final client = MockClient((request) async {
      calls++;
      return http.Response('', 302, headers: {
        'location': 'https://169.254.169.254/latest/meta-data/',
      });
    });

    final response = await DownloadManager.sendWithValidatedRedirects(
      client,
      Uri.parse('https://mirror.example.org/a.iso'),
      headers: const {'Accept-Encoding': 'identity'},
    );

    expect(response, isNull);
    expect(calls, 1);
  });

  test('follows a public cross-origin HTTPS redirect', () async {
    var calls = 0;
    final client = MockClient((request) async {
      calls++;
      if (calls == 1) {
        return http.Response('', 302, headers: {
          'location': 'https://cdn.example.net/a.iso',
        });
      }
      return http.Response.bytes(
        const [0x4d, 0x5a],
        200,
        headers: {'content-type': 'application/octet-stream'},
      );
    });

    final response = await DownloadManager.sendWithValidatedRedirects(
      client,
      Uri.parse('https://mirror.example.org/a.iso'),
      headers: const {'Accept-Encoding': 'identity'},
    );

    expect(response, isNotNull);
    expect(response!.statusCode, 200);
    expect(calls, 2);
    await response.stream.drain<void>();
  });
}
