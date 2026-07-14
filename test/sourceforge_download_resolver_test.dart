import 'package:flutter_test/flutter_test.dart';
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
