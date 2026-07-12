import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:win_deploy_studio/app/theme.dart';
import 'package:win_deploy_studio/core/localization/strings.dart';
import 'package:win_deploy_studio/features/settings/settings_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'language_code': 'en',
      'update_auto_check': false,
    });
    L.currentLocale = 'en';
  });

  testWidgets('five rapid taps on the About version reveal the artwork egg', (
    tester,
  ) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.binding.setSurfaceSize(const Size(800, 1600));
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: AppTheme.light(
            const Color(0xFF0071C5),
            'HarmonyOSSans',
            style: VisualStyle.win11,
          ),
          home: const SettingsScreen(),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));

    final versionTile = find.byKey(const Key('settings-version-easter-egg'));
    expect(versionTile, findsOneWidget);
    for (var tap = 0; tap < 5; tap++) {
      await tester.tap(versionTile);
      await tester.pump();
    }

    expect(find.byType(Dialog), findsOneWidget);
    expect(find.byTooltip(trCurrent('close')), findsOneWidget);
  });

  testWidgets('Intel museum dialog adapts without a scroll view', (
    tester,
  ) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.binding.setSurfaceSize(const Size(1280, 900));
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(
          const Color(0xFF0071C5),
          'HarmonyOSSans',
          style: VisualStyle.win11,
        ),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: FilledButton(
                key: const Key('open-intel-museum'),
                onPressed: () => showDialog<void>(
                  context: context,
                  builder: (context) =>
                      const IntelMuseumDialog(loadSystemInfo: false),
                ),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const Key('open-intel-museum')));
    await tester.pump();

    final dialog = find.byType(Dialog);
    expect(dialog, findsOneWidget);
    expect(
      find.descendant(of: dialog, matching: find.byType(SingleChildScrollView)),
      findsNothing,
    );

    await tester.binding.setSurfaceSize(const Size(420, 760));
    await tester.pump();

    final dialogRect = tester.getRect(dialog);
    expect(dialogRect.left, greaterThanOrEqualTo(0));
    expect(dialogRect.right, lessThanOrEqualTo(420));
    expect(dialogRect.top, greaterThanOrEqualTo(0));
    expect(dialogRect.bottom, lessThanOrEqualTo(760));
    _expectNoFlutterExceptions(tester);
  });

  testWidgets('settings controls remain end aligned on wide layouts', (
    tester,
  ) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.binding.setSurfaceSize(const Size(1000, 900));
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: AppTheme.light(
            const Color(0xFF0071C5),
            'HarmonyOSSans',
            style: VisualStyle.win11,
          ),
          home: const SettingsScreen(),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));

    final themeMenu = find.byWidgetPredicate(
      (widget) => widget is DropdownButton<ThemeMode>,
    );
    expect(themeMenu, findsOneWidget);
    expect(tester.getRect(themeMenu).right, greaterThan(900));
    _expectNoFlutterExceptions(tester);
  });
}

void _expectNoFlutterExceptions(WidgetTester tester) {
  final exceptions = <Object>[];
  Object? exception;
  while ((exception = tester.takeException()) != null) {
    exceptions.add(exception!);
  }
  expect(exceptions, isEmpty, reason: exceptions.join('\n\n'));
}
