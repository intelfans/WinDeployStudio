import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:win_deploy_studio/app/theme.dart';
import 'package:win_deploy_studio/shared/widgets/app_navigation_shell.dart';
import 'package:win_deploy_studio/shared/widgets/app_page.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('page header renders each resolved style token set', (
    tester,
  ) async {
    for (final style in [
      VisualStyle.win11,
      VisualStyle.win10,
      VisualStyle.win7,
    ]) {
      await tester.pumpWidget(
        _ThemedSurface(
          style: style,
          child: const AppPageHeader(
            icon: Icons.settings_outlined,
            title: 'Appearance',
            subtitle: 'A standard page header',
          ),
        ),
      );

      final marker = find.byKey(ValueKey('app-page-header-${style.name}'));
      expect(marker, findsOneWidget);
      final container = tester.widget<Container>(marker);
      final decoration = container.decoration! as BoxDecoration;
      final title = tester.widget<Text>(find.text('Appearance'));
      expect(title.style?.fontSize, 28);
      expect(decoration.borderRadius, isNotNull);
      if (style == VisualStyle.win7) {
        expect(decoration.border, isNotNull);
        expect(decoration.boxShadow, isNotEmpty);
      } else {
        expect(decoration.border, isNull);
      }
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('navigation shell collapses without changing style source', (
    tester,
  ) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.binding.setSurfaceSize(const Size(520, 640));

    for (final style in [
      VisualStyle.win11,
      VisualStyle.win10,
      VisualStyle.win7,
    ]) {
      await tester.pumpWidget(
        _ThemedSurface(
          style: style,
          child: AppNavigationShell(
            selectedIndex: 0,
            destinations: const [
              AppNavigationDestination(
                icon: Icons.home_outlined,
                selectedIcon: Icons.home,
                label: 'Home',
              ),
              AppNavigationDestination(
                icon: Icons.settings_outlined,
                selectedIcon: Icons.settings,
                label: 'Settings',
              ),
            ],
            onDestinationSelected: (_) {},
            child: const SizedBox.expand(),
          ),
        ),
      );

      final compact = tester.widget<SizedBox>(
        find.byKey(ValueKey('app-navigation-${style.name}-compact')),
      );
      expect(compact.width, 68);
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('responsive page primitives stack in a narrow RTL surface', (
    tester,
  ) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.binding.setSurfaceSize(const Size(320, 700));

    await tester.pumpWidget(
      _ThemedSurface(
        style: VisualStyle.win11,
        child: Directionality(
          textDirection: TextDirection.rtl,
          child: SingleChildScrollView(
            child: Column(
              children: [
                AppInfoBox(
                  icon: Icons.info_outline,
                  actions: [
                    FilledButton(onPressed: () {}, child: const Text('متابعة')),
                    TextButton(onPressed: () {}, child: const Text('إلغاء')),
                  ],
                  child: const Text(
                    'معلومات طويلة لاختبار التفاف النص في نافذة ضيقة.',
                  ),
                ),
                const SizedBox(height: 12),
                const AdaptiveTwoPane(
                  primary: SizedBox(key: Key('primary-pane'), height: 40),
                  secondary: SizedBox(key: Key('secondary-pane'), height: 40),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    expect(
      tester.getTopLeft(find.byKey(const Key('secondary-pane'))).dy,
      greaterThan(tester.getTopLeft(find.byKey(const Key('primary-pane'))).dy),
    );
    expect(tester.takeException(), isNull);
  });
}

class _ThemedSurface extends StatelessWidget {
  const _ThemedSurface({required this.style, required this.child});

  final VisualStyle style;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      key: ValueKey(style),
      themeAnimationDuration: Duration.zero,
      theme: AppTheme.light(
        const Color(0xFF0071C5),
        'HarmonyOSSans',
        style: style,
      ),
      home: Scaffold(body: child),
    );
  }
}
