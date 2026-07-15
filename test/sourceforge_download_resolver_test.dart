import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:win_deploy_studio/core/services/global_mirror_download_resolver.dart';

void main() {
  final landingPage = Uri(
    scheme: 'https',
    host: 'downloads.sourceforge.net',
    path: '/project/windeploystudio/Extended%20Files/TinyOS/Tiny10_22H2.iso',
  );

  test('extracts a signed Global Mirror URL from a meta refresh', () {
    const html = '''
      <meta http-equiv="refresh" content="0; url=https://onboardcloud.dl.sourceforge.net/project/windeploystudio/Extended%20Files/TinyOS/Tiny10_22H2.iso?viasf=1&amp;fid=abc&amp;e=123&amp;st=signature">
    ''';

    final result = GlobalMirrorDownloadResolver.extractDirectUrl(
      html,
      baseUri: landingPage,
    );

    expect(result, isNotNull);
    expect(result!.host, 'onboardcloud.dl.sourceforge.net');
    expect(result.queryParameters['fid'], 'abc');
    expect(result.queryParameters['st'], 'signature');
  });

  test('extracts an escaped JavaScript mirror URL', () {
    const html = r'''
      <script>
        const directUrl = "https:\/\/netix.dl.sourceforge.net\/project\/windeploystudio\/file.iso?viasf=1\u0026fid=def";
      </script>
    ''';

    final result = GlobalMirrorDownloadResolver.extractDirectUrl(
      html,
      baseUri: landingPage,
    );

    expect(result, isNotNull);
    expect(result!.host, 'netix.dl.sourceforge.net');
    expect(result.queryParameters['fid'], 'def');
  });

  test('extracts a protocol-relative Global Mirror mirror link', () {
    const html = '''
      <a href="//pilotfiber.dl.sourceforge.net/project/windeploystudio/file.iso?viasf=1">Download</a>
    ''';

    final result = GlobalMirrorDownloadResolver.extractDirectUrl(
      html,
      baseUri: landingPage,
    );

    expect(result, isNotNull);
    expect(result!.scheme, 'https');
    expect(result.host, 'pilotfiber.dl.sourceforge.net');
  });

  test('keeps SourceForge download endpoint for a second resolution pass', () {
    const html = '''
      <meta http-equiv="refresh" content="5; url=https://downloads.sourceforge.net/project/windeploystudio/v1.1.2/WinDeployStudio_Setup_1.1.2.exe?use_mirror=master">
    ''';

    final result = GlobalMirrorDownloadResolver.extractDirectUrl(
      html,
      baseUri: landingPage,
    );

    expect(result, isNotNull);
    expect(result!.host, 'downloads.sourceforge.net');
    expect(GlobalMirrorDownloadResolver.isDownloadEndpoint(result), isTrue);
  });

  test('accepts an HTTPS root-host download endpoint', () {
    const html = '''
      <a href="https://sourceforge.net/projects/windeploystudio/files/v1.1.2/WinDeployStudio_Setup_1.1.2.exe/download?direct=1">Download</a>
    ''';

    final result = GlobalMirrorDownloadResolver.extractDirectUrl(
      html,
      baseUri: landingPage,
    );

    expect(result, isNotNull);
    expect(result!.host, 'sourceforge.net');
    expect(GlobalMirrorDownloadResolver.isDownloadEndpoint(result), isTrue);
  });

  test('returns a direct file response from the trusted root host', () async {
    const directUrl =
        'https://sourceforge.net/projects/windeploystudio/files/v1.1.2/WinDeployStudio_Setup_1.1.2.exe/download?direct=1';
    final client = MockClient(
      (_) async => http.Response.bytes(
        const [0x4d, 0x5a],
        200,
        headers: {'content-type': 'application/octet-stream'},
      ),
    );

    final resolved = await GlobalMirrorDownloadResolver.resolve(
      directUrl,
      client: client,
    );

    expect(resolved, directUrl);
  });

  test('does not treat an HTTP SourceForge endpoint as trusted', () {
    expect(
      GlobalMirrorDownloadResolver.isDownloadEndpoint(
        Uri.parse('http://downloads.sourceforge.net/project/file.iso'),
      ),
      isFalse,
    );
    expect(
      GlobalMirrorDownloadResolver.isDownloadEndpoint(
        Uri.parse(
          'http://sourceforge.net/projects/windeploystudio/files/file.iso/download',
        ),
      ),
      isFalse,
    );
  });

  test('does not accept a non-Global Mirror download URL', () {
    const html = '''
      <meta http-equiv="refresh" content="0; url=https://example.invalid/file.iso">
      <a href="https://sourceforge.net/projects/windeploystudio/files/">Files</a>
    ''';

    expect(
      GlobalMirrorDownloadResolver.extractDirectUrl(html, baseUri: landingPage),
      isNull,
    );
  });

  test('follows the SourceForge endpoint to a signed mirror URL', () async {
    final requests = <Uri>[];
    final directUrl = Uri.parse(
      'https://master.dl.sourceforge.net/project/windeploystudio/v1.1.2/WinDeployStudio_Setup_1.1.2.exe?viasf=1&fid=abc',
    );
    final client = MockClient((request) async {
      requests.add(request.url);
      if (requests.length == 1) {
        return http.Response(
          '<meta http-equiv="refresh" content="0; url=https://downloads.sourceforge.net/project/windeploystudio/v1.1.2/WinDeployStudio_Setup_1.1.2.exe?use_mirror=master">',
          200,
          headers: {'content-type': 'text/html'},
        );
      }
      return http.Response(
        '',
        302,
        headers: {'location': directUrl.toString()},
      );
    });

    final resolved = await GlobalMirrorDownloadResolver.resolve(
      'https://sourceforge.net/projects/windeploystudio/files/v1.1.2/WinDeployStudio_Setup_1.1.2.exe/download',
      client: client,
    );

    expect(resolved, directUrl.toString());
    expect(requests, hasLength(2));
    expect(requests[1].host, 'downloads.sourceforge.net');
  });

  test('recognizes only HTTPS Global Mirror URLs as trusted', () {
    expect(
      GlobalMirrorDownloadResolver.isGlobalMirrorUrl(
        Uri.parse('https://sourceforge.net/projects/windeploystudio/files/'),
      ),
      isTrue,
    );
    expect(
      GlobalMirrorDownloadResolver.isGlobalMirrorUrl(
        Uri.parse('https://onboardcloud.dl.sourceforge.net/project/file.iso'),
      ),
      isTrue,
    );
    expect(
      GlobalMirrorDownloadResolver.isGlobalMirrorUrl(
        Uri.parse('http://downloads.sourceforge.net/project/file.iso'),
      ),
      isFalse,
    );
    expect(
      GlobalMirrorDownloadResolver.isGlobalMirrorUrl(
        Uri.parse('https://example.invalid/file.iso'),
      ),
      isFalse,
    );
  });
}
