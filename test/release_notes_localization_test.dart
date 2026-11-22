import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:win_deploy_studio/features/update/models/update_models.dart';

UpdateInfo _info(String body) => UpdateInfo.fromJson(<String, dynamic>{
  'tag_name': 'v3.0.0',
  'name': 'v3.0.0',
  'body': body,
  'published_at': '2026-11-22T00:00:00Z',
  'html_url': 'https://github.com/intelfans/WinDeployStudio/releases/tag/v3.0.0',
  'assets': const [],
});

void main() {
  late String releaseBody;

  setUpAll(() {
    releaseBody = File('RELEASE_v3.0.0.md').readAsStringSync();
  });

  test('the release notes carry both language markers', () {
    expect(releaseBody.contains('<!-- wds:lang=en -->'), isTrue);
    expect(releaseBody.contains('<!-- wds:lang=zh -->'), isTrue);
  });

  test('an English locale receives the English section without markers', () {
    final body = _info(releaseBody).bodyForLocale('en');
    expect(body.contains('wds:lang'), isFalse, reason: 'markers must be stripped');
    expect(body.contains('Major update'), isTrue);
    expect(body.contains('重大更新'), isFalse);
  });

  test('a Chinese locale receives the Chinese section', () {
    for (final code in <String>['zh', 'zh_TW', 'zh-CN']) {
      final body = _info(releaseBody).bodyForLocale(code);
      expect(body.contains('重大更新'), isTrue, reason: code);
      expect(body.contains('Major update'), isFalse, reason: code);
      expect(body.contains('wds:lang'), isFalse, reason: code);
    }
  });

  test('other locales fall back to English', () {
    for (final code in <String>['fr', 'de', 'ja', 'ru', 'ar']) {
      final body = _info(releaseBody).bodyForLocale(code);
      expect(body.contains('Major update'), isTrue, reason: code);
    }
  });

  test('unmarked notes still fall back to the character heuristic', () {
    const legacy = '# v2.1.0 Major update\n\n---\n\n# v2.1.0 重大更新\n';
    expect(_info(legacy).bodyForLocale('en').contains('Major update'), isTrue);
    expect(_info(legacy).bodyForLocale('zh').contains('重大更新'), isTrue);
  });
}
