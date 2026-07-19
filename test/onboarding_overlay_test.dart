import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:win_deploy_studio/app/theme.dart';
import 'package:win_deploy_studio/core/constants/app_constants.dart';
import 'package:win_deploy_studio/core/localization/strings.dart';
import 'package:win_deploy_studio/features/onboarding/onboarding_overlay.dart';
import 'package:win_deploy_studio/shared/widgets/app_navigation_shell.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'language_code': 'en',
    });
    L.currentLocale = 'en';
  });

  Widget host() {
    return MaterialApp(
      theme: AppTheme.light(
        const Color(0xFF0071C5),
        'HarmonyOSSans',
        style: VisualStyle.win11,
      ),
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: FilledButton(
              key: const Key('open-onboarding'),
              onPressed: () => OnboardingOverlay.show(context),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('renders the first tour step and exposes close action', (
    tester,
  ) async {
    await tester.pumpWidget(host());
    await tester.tap(find.byKey(const Key('open-onboarding')));
    await tester.pump(const Duration(milliseconds: 80));

    expect(find.text('Quick tour'), findsOneWidget);
    expect(find.byKey(const Key('onboarding-close-all')), findsOneWidget);
    expect(find.byKey(const Key('onboarding-skip-section')), findsOneWidget);

    await tester.tap(find.byKey(const Key('onboarding-close-all')));
    await tester.pump(const Duration(milliseconds: 240));
  });

  testWidgets('close action completes and dismisses the tour', (tester) async {
    await tester.pumpWidget(host());
    await tester.tap(find.byKey(const Key('open-onboarding')));
    await tester.pump(const Duration(milliseconds: 80));

    await tester.tap(find.byKey(const Key('onboarding-close-all')));
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.byType(OnboardingOverlay), findsNothing);
    final preferences = await SharedPreferences.getInstance();
    expect(
      preferences.getBool(OnboardingOverlay.completedPreferenceKey),
      isTrue,
    );
    expect(
      preferences.getString(OnboardingOverlay.completedVersionPreferenceKey),
      AppConstants.appVersion,
    );
  });

  test('automatic tour completion is tracked per app version', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      OnboardingOverlay.completedPreferenceKey: true,
    });
    expect(await OnboardingOverlay.hasCompleted(), isFalse);

    SharedPreferences.setMockInitialValues(<String, Object>{
      OnboardingOverlay.completedVersionPreferenceKey: AppConstants.appVersion,
    });
    expect(await OnboardingOverlay.hasCompleted(), isTrue);

    SharedPreferences.setMockInitialValues(<String, Object>{
      OnboardingOverlay.completedVersionPreferenceKey: '2.0.9',
    });
    expect(await OnboardingOverlay.hasCompleted(), isFalse);
  });

  testWidgets('exploration mode leaves the underlying page interactive', (
    tester,
  ) async {
    var taps = 0;
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) => Scaffold(
            body: Center(
              child: FilledButton(
                key: const Key('underlying-action'),
                onPressed: () => taps++,
                child: const Text('Underlying action'),
              ),
            ),
          ),
        ),
      ],
    );
    await tester.pumpWidget(
      MaterialApp.router(
        theme: AppTheme.light(
          const Color(0xFF0071C5),
          'HarmonyOSSans',
          style: VisualStyle.win11,
        ),
        routerConfig: router,
      ),
    );
    await tester.pump();
    final context = tester.element(find.byKey(const Key('underlying-action')));
    unawaited(OnboardingOverlay.show(context));
    await tester.pump(const Duration(milliseconds: 100));

    await tester.tap(find.widgetWithText(FilledButton, 'Open'));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.text('Start exploring'));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(find.byKey(const Key('underlying-action')));
    expect(taps, 1);

    await tester.tap(find.byKey(const Key('onboarding-close-all')));
    await tester.pump(const Duration(milliseconds: 240));
  });

  testWidgets('switching sections offers the matching tour', (tester) async {
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) => const Scaffold(body: Text('Home')),
        ),
        GoRoute(
          path: '/mirror',
          builder: (context, state) => const Scaffold(body: Text('Images')),
        ),
      ],
    );
    await tester.pumpWidget(
      MaterialApp.router(
        theme: AppTheme.light(
          const Color(0xFF0071C5),
          'HarmonyOSSans',
          style: VisualStyle.win11,
        ),
        routerConfig: router,
      ),
    );
    await tester.pump();
    final context = tester.element(find.text('Home'));
    unawaited(OnboardingOverlay.show(context));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.widgetWithText(FilledButton, 'Open'));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.text('Start exploring'));
    await tester.pump(const Duration(milliseconds: 100));

    router.go('/mirror');
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 120));
    expect(find.text('Switch this tour?'), findsOneWidget);
    await tester.tap(find.text('Switch tour'));
    await tester.pump(const Duration(milliseconds: 120));
    expect(find.text('Images'), findsOneWidget);
    expect(find.text('Switch this tour?'), findsNothing);

    await tester.tap(find.byKey(const Key('onboarding-close-all')));
    await tester.pump(const Duration(milliseconds: 240));
  });

  testWidgets('single-section tour asks before ending on section switch', (
    tester,
  ) async {
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) => const Scaffold(body: Text('Home')),
        ),
        GoRoute(
          path: '/mirror',
          builder: (context, state) => const Scaffold(body: Text('Images')),
        ),
      ],
    );
    await tester.pumpWidget(
      MaterialApp.router(
        theme: AppTheme.light(
          const Color(0xFF0071C5),
          'HarmonyOSSans',
          style: VisualStyle.win11,
        ),
        routerConfig: router,
      ),
    );
    await tester.pump();
    final context = tester.element(find.text('Home'));
    unawaited(OnboardingOverlay.show(context, section: OnboardingSection.home));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.widgetWithText(FilledButton, 'Open'));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.text('Start exploring'));
    await tester.pump(const Duration(milliseconds: 100));

    router.go('/mirror');
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 120));
    expect(find.text('End this tour?'), findsOneWidget);
    await tester.tap(find.text('End tour'));
    await tester.pump(const Duration(milliseconds: 240));
    expect(find.byKey(const Key('onboarding-close-all')), findsNothing);
  });

  testWidgets('single-section explore dock only offers end tour', (
    tester,
  ) async {
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) => const Scaffold(body: Text('Home')),
        ),
      ],
    );
    await tester.pumpWidget(
      MaterialApp.router(
        theme: AppTheme.light(
          const Color(0xFF0071C5),
          'HarmonyOSSans',
          style: VisualStyle.win11,
        ),
        routerConfig: router,
      ),
    );
    await tester.pump();
    final context = tester.element(find.text('Home'));
    unawaited(OnboardingOverlay.show(context, section: OnboardingSection.home));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.widgetWithText(FilledButton, 'Open'));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.text('Start exploring'));
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.byKey(const Key('onboarding-close-all')), findsOneWidget);
    expect(find.byKey(const Key('onboarding-explore-next')), findsNothing);
    expect(find.byIcon(Icons.skip_next_rounded), findsNothing);

    await tester.tap(find.byKey(const Key('onboarding-close-all')));
    await tester.pump(const Duration(milliseconds: 240));
  });

  testWidgets('full tour explore dock omits section skip action', (
    tester,
  ) async {
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) => const Scaffold(body: Text('Home')),
        ),
      ],
    );
    await tester.pumpWidget(
      MaterialApp.router(
        theme: AppTheme.light(
          const Color(0xFF0071C5),
          'HarmonyOSSans',
          style: VisualStyle.win11,
        ),
        routerConfig: router,
      ),
    );
    await tester.pump();
    final context = tester.element(find.text('Home'));
    unawaited(OnboardingOverlay.show(context));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.widgetWithText(FilledButton, 'Open'));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.text('Start exploring'));
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.byKey(const Key('onboarding-close-all')), findsOneWidget);
    expect(find.byKey(const Key('onboarding-skip-section')), findsNothing);
    expect(find.byIcon(Icons.skip_next_rounded), findsNothing);

    await tester.tap(find.byKey(const Key('onboarding-close-all')));
    await tester.pump(const Duration(milliseconds: 240));
  });

  testWidgets('settings finish keeps only the relevant actions', (
    tester,
  ) async {
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) => const Scaffold(body: Text('Home')),
        ),
        GoRoute(
          path: '/settings',
          builder: (context, state) => const Scaffold(body: Text('Settings')),
        ),
      ],
    );
    await tester.pumpWidget(
      MaterialApp.router(
        theme: AppTheme.light(
          const Color(0xFF0071C5),
          'HarmonyOSSans',
          style: VisualStyle.win11,
        ),
        routerConfig: router,
      ),
    );
    await tester.pump();
    final context = tester.element(find.text('Home'));
    unawaited(OnboardingOverlay.show(context));
    await tester.pump(const Duration(milliseconds: 100));

    for (var section = 0; section < 9; section++) {
      await tester.tap(find.byKey(const Key('onboarding-skip-section')));
      await tester.pump(const Duration(milliseconds: 50));
    }

    expect(find.byKey(const Key('onboarding-close-all')), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Open'), findsOneWidget);
    expect(find.byKey(const Key('onboarding-skip-section')), findsNothing);
    expect(find.byIcon(Icons.arrow_back_rounded), findsNothing);

    await tester.tap(find.widgetWithText(FilledButton, 'Open'));
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.byKey(const Key('onboarding-close-all')), findsOneWidget);
    expect(find.byKey(const Key('onboarding-start-exploring')), findsOneWidget);
    expect(find.byKey(const Key('onboarding-skip-section')), findsNothing);
    expect(find.byIcon(Icons.arrow_back_rounded), findsNothing);

    await tester.tap(find.byKey(const Key('onboarding-close-all')));
    await tester.pump(const Duration(milliseconds: 240));
  });

  testWidgets('child exploration returns to parent before the next child', (
    tester,
  ) async {
    final router = GoRouter(
      initialLocation: '/disk-tools',
      routes: [
        GoRoute(
          path: '/disk-tools',
          builder: (context, state) => Scaffold(
            body: Column(
              children: [
                const Text('Disk tools'),
                FilledButton(
                  key: AppNavigationKeys.diskDiagnosticsKey,
                  onPressed: () => context.go('/disk-tools/diagnostics'),
                  child: const Text('Disk diagnostics'),
                ),
                FilledButton(
                  key: AppNavigationKeys.bootRepairKey,
                  onPressed: () => context.go('/disk-tools/boot-repair'),
                  child: const Text('Boot repair'),
                ),
              ],
            ),
          ),
        ),
        GoRoute(
          path: '/disk-tools/diagnostics',
          builder: (context, state) =>
              const Scaffold(body: Text('Disk diagnostics page')),
        ),
        GoRoute(
          path: '/disk-tools/boot-repair',
          builder: (context, state) =>
              const Scaffold(body: Text('Boot repair page')),
        ),
      ],
    );
    await tester.pumpWidget(
      MaterialApp.router(
        theme: AppTheme.light(
          const Color(0xFF0071C5),
          'HarmonyOSSans',
          style: VisualStyle.win11,
        ),
        routerConfig: router,
      ),
    );
    await tester.pump();
    final context = tester.element(find.text('Disk tools'));
    unawaited(
      OnboardingOverlay.show(context, section: OnboardingSection.diskTools),
    );
    await tester.pump(const Duration(milliseconds: 100));

    // Navigation and overview steps.
    await tester.tap(find.widgetWithText(FilledButton, 'Open'));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.text('Start exploring'));
    await tester.pump(const Duration(milliseconds: 3000));
    await tester.tap(find.byKey(const Key('onboarding-explore-details')));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.byKey(const Key('onboarding-card-next')));
    await tester.pump(const Duration(milliseconds: 100));

    // Open diagnostics, then move to the next child.
    await tester.tap(find.text('Open & explore'));
    await tester.pump(const Duration(milliseconds: 100));
    expect(
      router.routeInformationProvider.value.uri.path,
      '/disk-tools/diagnostics',
    );
    expect(find.byKey(const Key('onboarding-spotlight-target')), findsNothing);
    await tester.pump(const Duration(milliseconds: 3000));
    await tester.tap(find.byKey(const Key('onboarding-explore-details')));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.byKey(const Key('onboarding-card-next')));
    await tester.pump(const Duration(milliseconds: 500));

    expect(router.routeInformationProvider.value.uri.path, '/disk-tools');

    await tester.tap(find.byKey(const Key('onboarding-close-all')));
    await tester.pump(const Duration(milliseconds: 240));
  });

  testWidgets(
    'full tour follows manually opened benchmark history and restores parent intro',
    (tester) async {
      final router = GoRouter(
        initialLocation: '/benchmark',
        routes: [
          GoRoute(
            path: '/benchmark',
            builder: (context, state) =>
                const Scaffold(body: Text('Benchmark page')),
          ),
          GoRoute(
            path: '/benchmark/history',
            builder: (context, state) =>
                const Scaffold(body: Text('Benchmark history page')),
          ),
        ],
      );
      await tester.pumpWidget(
        MaterialApp.router(
          theme: AppTheme.light(
            const Color(0xFF0071C5),
            'HarmonyOSSans',
            style: VisualStyle.win11,
          ),
          routerConfig: router,
        ),
      );
      await tester.pump();
      final context = tester.element(find.text('Benchmark page'));
      unawaited(OnboardingOverlay.show(context));
      await tester.pump(const Duration(milliseconds: 100));

      for (var section = 0; section < 4; section++) {
        await tester.tap(find.byKey(const Key('onboarding-skip-section')));
        await tester.pump(const Duration(milliseconds: 100));
      }
      await tester.tap(find.widgetWithText(FilledButton, 'Open'));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(find.byKey(const Key('onboarding-start-exploring')));
      await tester.pump(const Duration(milliseconds: 100));

      router.go('/benchmark/history');
      await tester.pump(const Duration(milliseconds: 300));
      expect(
        find.byKey(const Key('onboarding-start-exploring')),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const Key('onboarding-start-exploring')));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byKey(const Key('onboarding-explore-next')), findsNothing);
      await tester.pump(const Duration(milliseconds: 3000));
      expect(find.byKey(const Key('onboarding-explore-next')), findsOneWidget);

      router.go('/benchmark');
      await tester.pump(const Duration(milliseconds: 300));
      expect(
        find.byKey(const Key('onboarding-start-exploring')),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const Key('onboarding-close-all')));
      await tester.pump(const Duration(milliseconds: 240));
    },
  );

  testWidgets(
    'full tour follows both disk tool children and restores disk tools intro',
    (tester) async {
      final router = GoRouter(
        initialLocation: '/disk-tools',
        routes: [
          GoRoute(
            path: '/disk-tools',
            builder: (context, state) =>
                const Scaffold(body: Text('Disk tools page')),
          ),
          GoRoute(
            path: '/disk-tools/diagnostics',
            builder: (context, state) =>
                const Scaffold(body: Text('Disk diagnostics page')),
          ),
          GoRoute(
            path: '/disk-tools/boot-repair',
            builder: (context, state) =>
                const Scaffold(body: Text('Boot repair page')),
          ),
        ],
      );
      await tester.pumpWidget(
        MaterialApp.router(
          theme: AppTheme.light(
            const Color(0xFF0071C5),
            'HarmonyOSSans',
            style: VisualStyle.win11,
          ),
          routerConfig: router,
        ),
      );
      await tester.pump();
      final context = tester.element(find.text('Disk tools page'));
      unawaited(OnboardingOverlay.show(context));
      await tester.pump(const Duration(milliseconds: 100));

      for (var section = 0; section < 5; section++) {
        await tester.tap(find.byKey(const Key('onboarding-skip-section')));
        await tester.pump(const Duration(milliseconds: 100));
      }
      await tester.tap(find.widgetWithText(FilledButton, 'Open'));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(find.byKey(const Key('onboarding-start-exploring')));
      await tester.pump(const Duration(milliseconds: 100));

      router.go('/disk-tools/diagnostics');
      await tester.pump(const Duration(milliseconds: 300));
      expect(
        find.byKey(const Key('onboarding-start-exploring')),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const Key('onboarding-start-exploring')));
      await tester.pump(const Duration(milliseconds: 100));
      router.go('/disk-tools');
      await tester.pump(const Duration(milliseconds: 300));
      expect(
        find.byKey(const Key('onboarding-start-exploring')),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const Key('onboarding-start-exploring')));
      await tester.pump(const Duration(milliseconds: 100));
      router.go('/disk-tools/boot-repair');
      await tester.pump(const Duration(milliseconds: 300));
      expect(
        find.byKey(const Key('onboarding-start-exploring')),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const Key('onboarding-close-all')));
      await tester.pump(const Duration(milliseconds: 240));
    },
  );
}
