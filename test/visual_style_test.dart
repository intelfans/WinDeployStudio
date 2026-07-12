import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:win_deploy_studio/app/theme.dart';
import 'package:win_deploy_studio/core/localization/strings.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('VisualStyleHost.detect', () {
    test('detects Windows 11 from a modern build string', () {
      expect(
        VisualStyleHost.detect('Windows 10 Pro 10.0.26100 Build 26100'),
        VisualStyle.win11,
      );
      expect(VisualStyleHost.detect('Windows 10.0.22631'), VisualStyle.win11);
    });

    test('detects Windows 10 before build 22000', () {
      expect(
        VisualStyleHost.detect('Windows 10 Pro 10.0.19045 Build 19045'),
        VisualStyle.win10,
      );
      expect(VisualStyleHost.detect('Windows 10.0.17763'), VisualStyle.win10);
    });

    test('uses the classic style for pre-Windows 10 hosts', () {
      expect(
        VisualStyleHost.detect('Windows 6.1.7601 Service Pack 1'),
        VisualStyle.win7,
      );
    });
  });

  test('all visual styles expose localized labels and descriptions', () {
    final languages = <Map<String, String>>[
      L.zh,
      L.zhTW,
      L.en,
      L.fr,
      L.de,
      L.es,
      L.pt,
      L.ru,
      L.ar,
      L.ko,
      L.ja,
    ];

    for (final language in languages) {
      for (final key in VisualStyleLocalizationKeys.all) {
        expect(language[key], isNotNull);
        expect(language[key]!.trim(), isNotEmpty);
      }
    }
  });

  test('styles expose distinct structural tokens with shared type scale', () {
    const seed = Color(0xFF0071C5);
    final themes = <VisualStyle, ThemeData>{
      for (final style in VisualStyle.values.where(
        (style) => style != VisualStyle.auto,
      ))
        style: AppTheme.light(seed, 'HarmonyOSSans', style: style),
    };
    final tokens = themes.map(
      (style, theme) => MapEntry(style, theme.extension<AppVisualTokens>()!),
    );

    for (final token in tokens.values) {
      expect(token.pageTitleSize, 28);
      expect(token.sectionTitleSize, 20);
      expect(token.bodyTextSize, 14);
      expect(token.surfaceRadius, inInclusiveRange(8, 12));
    }
    expect(tokens[VisualStyle.win11]!.pagePadding, 24);
    expect(tokens[VisualStyle.win10]!.controlHeight, 38);
    expect(tokens[VisualStyle.win7]!.controlHeight, 36);
    expect(
      tokens.values.map((token) => token.motionDuration).toSet(),
      hasLength(3),
    );
  });

  test('startup appearance preloads all persisted values', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      AppAppearanceSettings.themeModePreferenceKey: ThemeMode.dark.name,
      AppAppearanceSettings.visualStylePreferenceKey: VisualStyle.win7.name,
      AppAppearanceSettings.accentPreferenceKey: 0xFF008272,
      AppAppearanceSettings.fontFamilyPreferenceKey: 'Microsoft YaHei UI',
    });
    final preferences = await SharedPreferences.getInstance();
    final appearance = AppAppearanceSettings.fromPreferences(preferences);
    final container = ProviderContainer(
      overrides: [initialAppearanceProvider.overrideWithValue(appearance)],
    );
    addTearDown(container.dispose);

    expect(container.read(themeModeProvider), ThemeMode.dark);
    expect(container.read(visualStyleProvider), VisualStyle.win7);
    expect(container.read(seedColorProvider), const Color(0xFF008272));
    expect(container.read(fontFamilyProvider), 'Microsoft YaHei UI');
  });

  test(
    'selection persists and sends the native window style payload',
    () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final calls = <MethodCall>[];
      const channel = MethodChannel('wds/window_style');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      if (Platform.isWindows) {
        messenger.setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          return null;
        });
      }

      final notifier = VisualStyleNotifier();
      await notifier.setStyle(VisualStyle.win10);

      expect(notifier.state, VisualStyle.win10);
      final preferences = await SharedPreferences.getInstance();
      expect(
        preferences.getString(VisualStyleNotifier.preferenceKey),
        VisualStyle.win10.name,
      );
      if (Platform.isWindows) {
        final update = calls.lastWhere((call) => call.method == 'update');
        expect(update.arguments, isA<Map<Object?, Object?>>());
        final arguments = update.arguments as Map<Object?, Object?>;
        expect(arguments['style'], VisualStyle.win10.name);
        expect(arguments['brightness'], anyOf('light', 'dark'));
        expect(arguments['accent'], isA<int>());
        expect(arguments['surface'], isA<int>());
        expect(arguments['style'], isNot(VisualStyle.auto.name));
        messenger.setMockMethodCallHandler(channel, null);
      }
      notifier.dispose();
    },
  );
}
