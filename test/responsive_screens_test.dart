import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:win_deploy_studio/app/theme.dart';
import 'package:win_deploy_studio/core/config/ai_config.dart';
import 'package:win_deploy_studio/core/localization/strings.dart';
import 'package:win_deploy_studio/features/ai_assistant/screens/ai_assistant_screen.dart';
import 'package:win_deploy_studio/features/logs/screens/logs_screen.dart';
import 'package:win_deploy_studio/features/mirror/screens/mirror_screen.dart';
import 'package:win_deploy_studio/features/settings/settings_screen.dart';
import 'package:win_deploy_studio/features/tools/screens/tools_screen.dart';
import 'package:win_deploy_studio/features/tools/models/tool_models.dart';
import 'package:win_deploy_studio/features/update/models/update_models.dart';
import 'package:win_deploy_studio/features/update/providers/update_provider.dart';
import 'package:win_deploy_studio/features/update/screens/update_dialog.dart';
import 'package:win_deploy_studio/features/update/services/update_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'language_code': 'en',
      'ai_assistant_notice_hidden': true,
      'update_auto_check': false,
    });
    L.currentLocale = 'en';
  });

  testWidgets('settings and mirror screens remain usable at narrow width', (
    tester,
  ) async {
    await _setNarrowSurface(tester);

    await _pumpScreen(tester, const SettingsScreen());
    expect(find.text(trCurrent('settings_title')), findsOneWidget);
    expect(find.text(trCurrent('update_channel')), findsNothing);
    _expectNoFlutterExceptions(tester);

    await _pumpScreen(tester, const MirrorScreen());
    expect(find.text(trCurrent('images_title')), findsOneWidget);
    _expectNoFlutterExceptions(tester);
  });

  testWidgets('default AI service locks credential and model editing', (
    tester,
  ) async {
    await _pumpScreen(tester, const SettingsScreen());

    final endpointEdit = tester.widget<FilledButton>(
      find.byKey(const Key('settings-ai-endpoint-edit')),
    );
    final apiKeyEdit = tester.widget<FilledButton>(
      find.byKey(const Key('settings-ai-api-key-edit')),
    );
    final modelEdit = tester.widget<FilledButton>(
      find.byKey(const Key('settings-ai-model-edit')),
    );

    expect(endpointEdit.onPressed, isNotNull);
    expect(apiKeyEdit.onPressed, isNull);
    expect(modelEdit.onPressed, isNull);
    expect(find.text(trCurrent('ai_default')), findsNWidgets(2));

    await AiConfig.setEndpointUrl('https://example.com/v1/');
    await _pumpScreen(
      tester,
      const SettingsScreen(key: ValueKey('custom-ai-settings')),
    );

    final customApiKeyEdit = tester.widget<FilledButton>(
      find.byKey(const Key('settings-ai-api-key-edit')),
    );
    final customModelEdit = tester.widget<FilledButton>(
      find.byKey(const Key('settings-ai-model-edit')),
    );
    expect(customApiKeyEdit.onPressed, isNotNull);
    expect(customModelEdit.onPressed, isNotNull);
    expect(find.text(trCurrent('ai_default')), findsNothing);
    _expectNoFlutterExceptions(tester);
  });

  testWidgets('mirror category labels stay intact at desktop width', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1100, 760));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await _pumpScreen(tester, const MirrorScreen());

    final communityCategory = find.text('Community Editions');
    expect(communityCategory, findsOneWidget);
    final communityTitle = tester.widget<Text>(communityCategory);
    expect(communityTitle.maxLines, 1);
    expect(communityTitle.softWrap, isFalse);
    _expectNoFlutterExceptions(tester);
  });

  testWidgets('AI, logs, and tools screens do not overflow at narrow width', (
    tester,
  ) async {
    await _setNarrowSurface(tester);

    await _pumpScreen(tester, const AiAssistantScreen());
    final openSidebar = find.byTooltip(trCurrent('ai_show_sidebar'));
    expect(openSidebar, findsOneWidget);
    await tester.tap(openSidebar);
    await tester.pumpAndSettle();
    expect(find.byType(Drawer), findsOneWidget);
    _expectNoFlutterExceptions(tester);

    await _pumpScreen(tester, const LogsScreen());
    expect(find.text(trCurrent('logs_title')), findsOneWidget);
    _expectNoFlutterExceptions(tester);

    await _pumpScreen(
      tester,
      ToolsScreen(dataLoader: () async => _testToolsData),
    );
    final toolsTitle = find.text(trCurrent('tools_title'));
    await _pumpUntilFound(tester, toolsTitle);
    _expectNoFlutterExceptions(tester);
    expect(toolsTitle, findsWidgets);
  });

  testWidgets('available update dialog wraps content and actions narrowly', (
    tester,
  ) async {
    await _setNarrowSurface(tester);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          updateProvider.overrideWith((ref) => _AvailableUpdateNotifier()),
        ],
        child: _TestApp(home: const UpdateDialog()),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.text(trCurrent('update_now')), findsOneWidget);
    _expectNoFlutterExceptions(tester);
  });
}

Future<void> _setNarrowSurface(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(420, 760));
  addTearDown(() => tester.binding.setSurfaceSize(null));
}

Future<void> _pumpScreen(WidgetTester tester, Widget screen) async {
  await tester.pumpWidget(ProviderScope(child: _TestApp(home: screen)));
  for (var index = 0; index < 10; index++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _pumpUntilFound(WidgetTester tester, Finder finder) async {
  for (var index = 0; index < 50 && finder.evaluate().isEmpty; index++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void _expectNoFlutterExceptions(WidgetTester tester) {
  final exceptions = <Object>[];
  Object? exception;
  while ((exception = tester.takeException()) != null) {
    exceptions.add(exception!);
  }
  expect(exceptions, isEmpty, reason: exceptions.join('\n\n'));
}

class _TestApp extends StatelessWidget {
  const _TestApp({required this.home});

  final Widget home;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      theme: AppTheme.light(
        const Color(0xFF0071C5),
        'HarmonyOSSans',
        style: VisualStyle.win11,
      ),
      home: home,
    );
  }
}

class _AvailableUpdateNotifier extends UpdateNotifier {
  _AvailableUpdateNotifier() : super(UpdateService()) {
    state = UpdateState(
      status: UpdateStatus.available,
      info: UpdateInfo(
        version: const AppVersion(2, 0, 0),
        tagName: 'v2.0.0',
        name: 'Responsive update',
        body: List.filled(
          8,
          '- A deliberately long release note for narrow-window testing.',
        ).join('\n'),
        publishedAt: DateTime.utc(2026, 7, 12),
        assets: const <UpdateAsset>[],
      ),
    );
  }
}

const _testToolsData = ToolsData(
  categories: [
    ToolCategory(
      nameKey: 'tools_cat_system',
      color: '#0071C5',
      tools: [
        ToolItem(
          name: 'Test Utility',
          desc: 'A long utility description used to exercise the narrow card.',
          icon: 'system',
          url: 'https://example.com',
          downloadUrl: 'https://example.com/download',
          developer: 'WinDeploy Studio',
          version: '1.0.0',
          featured: true,
          tags: ['diagnostics', 'system', 'portable', 'recovery'],
        ),
      ],
    ),
  ],
);
