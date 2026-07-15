import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:win_deploy_studio/core/localization/strings.dart';
import 'package:win_deploy_studio/features/mirror/models/mirror_models.dart';

void main() {
  test('uses locale-specific official links and Enterprise image sizes', () {
    final officialWindows10 = MirrorItem.fromJson(<String, dynamic>{
      'id': 'official-win10',
      'name': <String, String>{'en': 'Official Windows 10'},
      'category': 'Official Microsoft Images',
      'downloadUrl':
          'https://www.microsoft.com/en-us/software-download/windows10',
      'chinaUrl': 'https://www.microsoft.com/zh-cn/software-download/windows10',
      'globalUrl':
          'https://www.microsoft.com/en-us/software-download/windows10',
    });
    final officialWindows11 = MirrorItem.fromJson(<String, dynamic>{
      'id': 'official-win11',
      'name': <String, String>{'en': 'Official Windows 11'},
      'category': 'Official Microsoft Images',
      'downloadUrl':
          'https://www.microsoft.com/en-us/software-download/windows11',
      'chinaUrl': 'https://www.microsoft.com/zh-cn/software-download/windows11',
      'globalUrl':
          'https://www.microsoft.com/en-us/software-download/windows11',
    });
    final enterpriseWindows10 = MirrorItem.fromJson(<String, dynamic>{
      'id': 'ltsc-win10-enterprise',
      'name': <String, String>{'en': 'Windows 10 Enterprise LTSC'},
      'category': 'Enterprise & LTSC Builds',
      'downloadUrl': 'https://example.invalid/windows-10-enterprise',
      'size': <String, String>{
        'zh': '4.70 GB',
        'zh_TW': '4.70 GB',
        'en': '4.56 GB',
      },
    });

    expect(
      officialWindows11.downloadUrlFor(const Locale('zh')),
      'https://www.microsoft.com/zh-cn/software-download/windows11',
    );
    expect(
      officialWindows11.downloadUrlFor(const Locale('en')),
      'https://www.microsoft.com/en-us/software-download/windows11',
    );
    expect(
      officialWindows10.downloadUrlFor(const Locale('zh')),
      'https://www.microsoft.com/zh-cn/software-download/windows10',
    );
    expect(
      officialWindows10.downloadUrlFor(const Locale('fr')),
      'https://www.microsoft.com/en-us/software-download/windows10',
    );
    expect(officialWindows11.getSize(const Locale('en')), isNull);
    expect(enterpriseWindows10.getSize(const Locale('zh')), '4.70 GB');
    expect(enterpriseWindows10.getSize(const Locale('zh', 'TW')), '4.70 GB');
    expect(enterpriseWindows10.getSize(const Locale('fr')), '4.56 GB');
  });

  test(
    'catalog routes official Windows 10 to the international site outside Chinese locales',
    () async {
      final json =
          jsonDecode(await File('data/mirrors.json').readAsString())
              as Map<String, dynamic>;
      final catalog = MirrorListData.fromJson(json);
      final windows10 = catalog.items.singleWhere(
        (item) => item.id == 'official-win10',
      );

      expect(
        windows10.downloadUrlFor(const Locale('zh')),
        'https://www.microsoft.com/zh-cn/software-download/windows10',
      );
      for (final locale in const <Locale>[
        Locale('en'),
        Locale('fr'),
        Locale('de'),
        Locale('ja'),
      ]) {
        expect(
          windows10.downloadUrlFor(locale),
          'https://www.microsoft.com/en-us/software-download/windows10',
        );
      }
    },
  );

  test('recognizes image entries with a China-only download mirror', () {
    final chineseOnlyResource = MirrorItem.fromJson(<String, dynamic>{
      'id': 'font-pack',
      'name': <String, String>{'zh': 'CJK 字体包'},
      'category': 'Tools',
      'downloadUrl': 'https://example.invalid/font-pack',
      'chinaUrl': 'https://example.invalid/font-pack',
    });

    expect(chineseOnlyResource.hasChinaMirror, isTrue);
    expect(chineseOnlyResource.hasGlobalMirror, isFalse);
  });

  test(
    'catalog publishes nine checksums with the Enterprise locale policy',
    () async {
      final json =
          jsonDecode(await File('data/mirrors.json').readAsString())
              as Map<String, dynamic>;
      final catalog = MirrorListData.fromJson(json);

      expect(catalog.knownImages, hasLength(9));
      for (final image in catalog.knownImages) {
        expect(image.sha256, matches(RegExp(r'^[a-f0-9]{64}$')));
        expect(image.md5, matches(RegExp(r'^[a-f0-9]{32}$')));
      }

      const enterpriseIds = <String>{
        'ltsc-win10-enterprise',
        'ltsc-win11-enterprise',
      };
      const universallyVisibleIds = <String>{
        'tiny10',
        'tiny11',
        'xlite10',
        'xlite11',
        'starvalleyx',
        'ltsc-win10-iot',
        'ltsc-win11-iot',
      };

      for (final code in supportedLocaleCodes) {
        final visibleIds = catalog
            .knownImagesForLocale(localeFromCode(code))
            .map((image) => image.id)
            .toSet();
        final isChineseLocale = code == 'zh' || code == 'zh_TW';

        expect(
          visibleIds.containsAll(universallyVisibleIds),
          isTrue,
          reason: 'All universally published checksums must work in $code.',
        );
        if (isChineseLocale) {
          expect(visibleIds.intersection(enterpriseIds), isEmpty);
        } else {
          expect(
            visibleIds.containsAll(enterpriseIds),
            isTrue,
            reason:
                'Both Enterprise checksums must work outside Chinese locales.',
          );
        }
        expect(visibleIds, hasLength(isChineseLocale ? 7 : 9));
      }
    },
  );

  test(
    'catalog uses direct Global Mirror files and keeps excluded resources local',
    () async {
      final json =
          jsonDecode(await File('data/mirrors.json').readAsString())
              as Map<String, dynamic>;
      final catalog = MirrorListData.fromJson(json);
      final byId = <String, MirrorItem>{
        for (final item in catalog.items) item.id: item,
      };
      const directIds = <String>{
        'tiny10',
        'tiny11',
        'xlite10',
        'xlite11',
        'ltsc-win10-enterprise',
        'ltsc-win11-enterprise',
        'ltsc-win10-iot',
        'ltsc-win11-iot',
      };

      for (final id in directIds) {
        final url = byId[id]!.globalUrl;
        expect(url, isNotNull, reason: '$id must have a global direct link');
        final uri = Uri.parse(url!);
        expect(uri.host, 'downloads.sourceforge.net');
        expect(url, contains('/project/windeploystudio/Extended%20Files/'));
        expect(url.toLowerCase(), isNot(contains('gofile')));
      }

      expect(byId['starvalleyx']!.hasGlobalMirror, isFalse);
      expect(byId['font-pack']!.hasGlobalMirror, isFalse);
    },
  );

  test(
    'English-only images expose language, time-zone, and font guidance',
    () async {
      final json =
          jsonDecode(await File('data/mirrors.json').readAsString())
              as Map<String, dynamic>;
      final catalog = MirrorListData.fromJson(json);
      final byId = <String, MirrorItem>{
        for (final item in catalog.items) item.id: item,
      };
      const ids = <String>{
        'tiny10',
        'tiny11',
        'xlite10',
        'xlite11',
        'ltsc-win10-iot',
        'ltsc-win11-iot',
      };

      for (final id in ids) {
        final item = byId[id]!;
        expect(item.needsFontPack, isTrue);
        expect(item.fontPackUrl, contains('share.123pan.cn'));
        for (final code in supportedLocaleCodes) {
          final parts = code.split('_');
          final locale = Locale(
            parts.first,
            parts.length > 1 ? parts[1] : null,
          );
          expect(
            item.getNotes(locale).join(' '),
            isNotEmpty,
            reason: '$id must explain the post-install setup in every locale',
          );
        }
      }
      expect(
        byId['tiny10']!.getNotes(const Locale('zh')).join(' '),
        allOf(contains('英文'), contains('语言'), contains('时区'), contains('字体')),
      );
      expect(
        byId['tiny10']!.getNotes(const Locale('en')).join(' ').toLowerCase(),
        allOf(
          contains('english'),
          contains('language'),
          contains('time zone'),
          contains('font'),
        ),
      );
    },
  );
}
