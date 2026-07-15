import 'package:flutter_test/flutter_test.dart';
import 'package:win_deploy_studio/features/update/models/update_models.dart';
import 'package:win_deploy_studio/features/update/services/update_service.dart';

void main() {
  test('builds a SourceForge landing URL from tag and asset name', () {
    final info = UpdateInfo(
      version: const AppVersion(1, 1, 2),
      tagName: 'v1.1.2',
      name: 'WinDeploy Studio',
      body: '',
      publishedAt: DateTime.utc(2026, 7, 1),
      assets: const [
        UpdateAsset(
          name: 'WinDeployStudio_Setup_1.1.2.exe',
          url: 'https://github.com/example/update.exe',
          sizeBytes: 42,
          contentType: 'application/octet-stream',
          digest: '',
        ),
      ],
    );

    expect(
      info.generateSourceForgeLandingUrl(),
      'https://sourceforge.net/projects/windeploystudio/files/v1.1.2/WinDeployStudio_Setup_1.1.2.exe/download',
    );
  });

  test('accepts GitHub assets without a digest for legacy releases', () {
    final info = UpdateInfo.fromJson({
      'tag_name': 'v1.1.2',
      'name': 'Legacy release',
      'body': 'notes',
      'published_at': '2026-07-01T00:00:00Z',
      'assets': [
        {
          'name': 'WinDeployStudio_Setup_1.1.2.exe',
          'browser_download_url':
              'https://github.com/intelfans/WinDeployStudio/releases/download/v1.1.2/WinDeployStudio_Setup_1.1.2.exe',
          'size': 42,
          'content_type': 'application/octet-stream',
        },
      ],
    });

    expect(info.bestAsset, isNotNull);
    expect(info.bestAsset!.sha256, isNull);
  });

  test('selects the Chinese or English release-note section', () {
    final info = UpdateInfo(
      version: const AppVersion(1, 1, 2),
      tagName: 'v1.1.2',
      name: 'Bilingual release',
      body: '## English\n\nImproved updates.\n\n---\n\n## 中文\n\n改进更新。',
      publishedAt: DateTime.utc(2026, 7, 1),
      assets: const <UpdateAsset>[],
    );

    expect(info.bodyForLocale('en'), contains('Improved updates'));
    expect(info.bodyForLocale('zh'), contains('改进更新'));
    expect(info.bodyForLocale('zh'), isNot(contains('Improved updates')));
  });

  test('parses a GitHub Releases Atom entry without API metadata', () {
    const feed = '''
      <feed xmlns="http://www.w3.org/2005/Atom">
        <entry>
          <title>WinDeploy Studio v2.0.7</title>
          <updated>2026-07-15T00:00:00Z</updated>
          <link rel="alternate" href="https://github.com/intelfans/WinDeployStudio/releases/tag/v2.0.7" />
          <content type="html">&lt;h2&gt;WinDeploy Studio v2.0.7&lt;/h2&gt;&lt;p&gt;Improved updates.&lt;/p&gt;&lt;hr&gt;&lt;h2&gt;中文&lt;/h2&gt;&lt;p&gt;改进更新。&lt;/p&gt;</content>
        </entry>
      </feed>
    ''';

    final releases = parseAtomReleaseMetadata(feed);
    expect(releases, hasLength(1));
    final info = UpdateInfo.fromJson(releases.single);
    expect(info.tagName, 'v2.0.7');
    expect(info.bestAsset?.name, 'WinDeployStudio_Setup_2.0.7.exe');
    expect(info.bestAsset?.sizeBytes, 0);
    expect(info.bodyForLocale('en'), contains('Improved updates'));
    expect(info.bodyForLocale('zh'), contains('改进更新'));
  });
}
