import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../core/localization/strings.dart';
import '../features/home/home_screen.dart';
import '../features/mirror/screens/mirror_screen.dart';
import '../features/mirror/screens/mirror_detail_screen.dart';
import '../features/mirror/models/mirror_models.dart';
import '../features/mirror/providers/mirror_provider.dart';
import '../features/creator/screens/creator_screen.dart';
import '../features/wtg/screens/wtg_screen.dart';
import '../features/benchmark/screens/drive_benchmark_screen.dart';
import '../features/benchmark_history/screens/benchmark_history_screen.dart';
import '../features/disk_tools/screens/disk_tools_screen.dart';
import '../features/disk_tools/screens/disk_diagnostics_screen.dart';
import '../features/disk_tools/screens/boot_repair_screen.dart';
import '../features/settings/settings_screen.dart';
import '../features/logs/screens/logs_screen.dart';
import '../features/ai_assistant/screens/ai_assistant_screen.dart';
import '../features/tools/screens/tools_screen.dart';
import '../shared/widgets/app_navigation_shell.dart';

final _shellNavigatorKey = GlobalKey<NavigatorState>(
  debugLabel: 'primary-navigation-shell',
);

final routerProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: '/',
    routes: [
      ShellRoute(
        navigatorKey: _shellNavigatorKey,
        builder: (context, state, child) {
          return ScaffoldWithNavigation(child: child);
        },
        routes: [
          GoRoute(
            path: '/',
            pageBuilder: (context, state) =>
                const NoTransitionPage(child: HomeScreen()),
          ),
          GoRoute(
            path: '/mirror',
            pageBuilder: (context, state) =>
                const NoTransitionPage(child: MirrorScreen()),
          ),
          GoRoute(
            path: '/creator',
            pageBuilder: (context, state) =>
                const NoTransitionPage(child: CreatorScreen()),
          ),
          GoRoute(
            path: '/wtg',
            pageBuilder: (context, state) =>
                const NoTransitionPage(child: WtgScreen()),
          ),
          GoRoute(
            path: '/benchmark',
            pageBuilder: (context, state) =>
                const NoTransitionPage(child: DriveBenchmarkScreen()),
            routes: [
              GoRoute(
                path: 'history',
                pageBuilder: (context, state) =>
                    const NoTransitionPage(child: BenchmarkHistoryScreen()),
              ),
            ],
          ),
          GoRoute(
            path: '/disk-tools',
            pageBuilder: (context, state) =>
                const NoTransitionPage(child: DiskToolsScreen()),
            routes: [
              GoRoute(
                path: 'diagnostics',
                pageBuilder: (context, state) =>
                    const NoTransitionPage(child: DiskDiagnosticsScreen()),
              ),
              GoRoute(
                path: 'boot-repair',
                pageBuilder: (context, state) =>
                    const NoTransitionPage(child: BootRepairScreen()),
              ),
            ],
          ),
          GoRoute(
            path: '/logs',
            pageBuilder: (context, state) =>
                const NoTransitionPage(child: LogsScreen()),
          ),
          GoRoute(
            path: '/ai',
            pageBuilder: (context, state) {
              final prompt = state.extra as String?;
              return NoTransitionPage(
                child: AiAssistantScreen(initialPrompt: prompt),
              );
            },
          ),
          GoRoute(
            path: '/tools',
            pageBuilder: (context, state) =>
                const NoTransitionPage(child: ToolsScreen()),
          ),
          GoRoute(
            path: '/settings',
            pageBuilder: (context, state) =>
                const NoTransitionPage(child: SettingsScreen()),
          ),
        ],
      ),
      GoRoute(
        path: '/mirror/:id',
        builder: (context, state) {
          final item = state.extra as MirrorItem?;
          final locale = Localizations.localeOf(context);
          final blocked = item != null && !item.isVisibleInLocale(locale);
          if (item != null && !blocked) {
            return MirrorDetailScreen(item: item);
          }

          // Try to find item by ID from provider
          final id = state.pathParameters['id'];
          final mirrorState = ref.watch(mirrorProvider);

          // If data not loaded yet, trigger load
          if (mirrorState.status == MirrorLoadStatus.initial ||
              mirrorState.status == MirrorLoadStatus.loading) {
            // Trigger load if not already loading
            if (mirrorState.status == MirrorLoadStatus.initial) {
              Future.microtask(
                () => ref.read(mirrorProvider.notifier).loadBuiltInMirrors(),
              );
            }
            return Scaffold(
              appBar: AppBar(),
              body: const Center(child: CircularProgressIndicator()),
            );
          }

          if (mirrorState.status == MirrorLoadStatus.error) {
            return Scaffold(
              appBar: AppBar(),
              body: Center(
                child: Text(
                  mirrorState.error == null
                      ? tr(context, 'images_error')
                      : '${tr(context, 'mirror_error_loading')} ${mirrorState.error}',
                ),
              ),
            );
          }

          final items = mirrorState.data?.items ?? [];
          final foundItem = items.where((i) => i.id == id).firstOrNull;

          final foundBlocked =
              foundItem != null && !foundItem.isVisibleInLocale(locale);
          if (foundItem != null && !foundBlocked) {
            return MirrorDetailScreen(item: foundItem);
          }

          return Scaffold(
            appBar: AppBar(),
            body: Center(child: Text(tr(context, 'mirror_not_found'))),
          );
        },
      ),
    ],
  );
});

class ScaffoldWithNavigation extends ConsumerStatefulWidget {
  final Widget child;
  const ScaffoldWithNavigation({super.key, required this.child});

  @override
  ConsumerState<ScaffoldWithNavigation> createState() =>
      _ScaffoldWithNavigationState();
}

class _ScaffoldWithNavigationState
    extends ConsumerState<ScaffoldWithNavigation> {
  static const _paths = [
    '/',
    '/mirror',
    '/creator',
    '/wtg',
    '/benchmark',
    '/disk-tools',
    '/logs',
    '/ai',
    '/tools',
    '/settings',
  ];

  @override
  Widget build(BuildContext context) {
    final currentPath = GoRouterState.of(context).uri.path;
    final selectedIndex = appNavigationIndexForPath(currentPath);

    final destinations = [
      AppNavigationDestination(
        key: AppNavigationKeys.destinationKeys[0],
        icon: Icons.home_outlined,
        selectedIcon: Icons.home,
        label: tr(context, 'nav_home'),
      ),
      AppNavigationDestination(
        key: AppNavigationKeys.destinationKeys[1],
        icon: Icons.cloud_outlined,
        selectedIcon: Icons.cloud,
        label: tr(context, 'nav_images'),
      ),
      AppNavigationDestination(
        key: AppNavigationKeys.destinationKeys[2],
        icon: Icons.usb_outlined,
        selectedIcon: Icons.usb,
        label: tr(context, 'nav_creator'),
        startsSection: true,
      ),
      AppNavigationDestination(
        key: AppNavigationKeys.destinationKeys[3],
        icon: Icons.computer_outlined,
        selectedIcon: Icons.computer,
        label: tr(context, 'nav_wtg'),
      ),
      AppNavigationDestination(
        key: AppNavigationKeys.destinationKeys[4],
        icon: Icons.monitor_heart_outlined,
        selectedIcon: Icons.monitor_heart,
        label: tr(context, 'nav_benchmark'),
      ),
      AppNavigationDestination(
        key: AppNavigationKeys.destinationKeys[5],
        icon: Icons.storage_outlined,
        selectedIcon: Icons.storage,
        label: tr(context, 'disk_tools_title'),
      ),
      AppNavigationDestination(
        key: AppNavigationKeys.destinationKeys[6],
        icon: Icons.receipt_long_outlined,
        selectedIcon: Icons.receipt_long,
        label: tr(context, 'nav_logs'),
        startsSection: true,
      ),
      AppNavigationDestination(
        key: AppNavigationKeys.destinationKeys[7],
        icon: Icons.auto_awesome_outlined,
        selectedIcon: Icons.auto_awesome,
        label: tr(context, 'nav_ai'),
      ),
      AppNavigationDestination(
        key: AppNavigationKeys.destinationKeys[8],
        icon: Icons.handyman_outlined,
        selectedIcon: Icons.handyman,
        label: tr(context, 'nav_tools'),
        startsSection: true,
      ),
      AppNavigationDestination(
        key: AppNavigationKeys.destinationKeys[9],
        icon: Icons.settings_outlined,
        selectedIcon: Icons.settings,
        label: tr(context, 'nav_settings'),
      ),
    ];

    return Scaffold(
      body: AppNavigationShell(
        selectedIndex: selectedIndex,
        destinations: destinations,
        onDestinationSelected: (index) {
          // Secondary disk-tool and benchmark pages are pushed on the shell
          // navigator. Clear that stack before changing the primary route.
          Navigator.of(
            context,
            rootNavigator: true,
          ).popUntil((route) => route.isFirst);
          _shellNavigatorKey.currentState?.popUntil((route) => route.isFirst);
          context.go(_paths[index]);
        },
        child: widget.child,
      ),
    );
  }
}

int appNavigationIndexForPath(String path) {
  const paths = <String>[
    '/',
    '/mirror',
    '/creator',
    '/wtg',
    '/benchmark',
    '/disk-tools',
    '/logs',
    '/ai',
    '/tools',
    '/settings',
  ];
  final directIndex = paths.indexOf(path);
  if (directIndex >= 0) return directIndex;

  if (path.startsWith('/benchmark/')) return paths.indexOf('/benchmark');
  if (path.startsWith('/disk-tools/')) return paths.indexOf('/disk-tools');
  return 0;
}
