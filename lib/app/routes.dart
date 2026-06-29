import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../core/localization/strings.dart';
import '../features/home/home_screen.dart';
import '../features/mirror/screens/mirror_screen.dart';
import '../features/mirror/screens/mirror_detail_screen.dart';
import '../features/mirror/models/mirror_models.dart';
import '../features/mirror/providers/mirror_provider.dart';
import '../features/mirror/widgets/ltsc_warning_dialog.dart';
import '../features/creator/screens/creator_screen.dart';
import '../features/wtg/screens/wtg_screen.dart';
import '../features/settings/settings_screen.dart';
import '../features/logs/screens/logs_screen.dart';
import '../features/ai_assistant/screens/ai_assistant_screen.dart';
import '../features/tools/screens/tools_screen.dart';

final routerProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: '/',
    routes: [
      ShellRoute(
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
          final blocked =
              item?.isStarValleyX == true && !item!.isVisibleInLocale(locale);
          if (item != null && !blocked) {
            if (item.isEnterpriseLtsc) {
              Future.microtask(() async {
                if (!context.mounted) return;
                final allowed = await showLtscExpertWarning(context);
                if (!allowed && context.mounted) context.go('/mirror');
              });
            }
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
              foundItem?.isStarValleyX == true &&
              !foundItem!.isVisibleInLocale(locale);
          if (foundItem != null && !foundBlocked) {
            if (foundItem.isEnterpriseLtsc) {
              Future.microtask(() async {
                if (!context.mounted) return;
                final allowed = await showLtscExpertWarning(context);
                if (!allowed && context.mounted) context.go('/mirror');
              });
            }
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
    '/logs',
    '/ai',
    '/tools',
    '/settings',
  ];

  @override
  Widget build(BuildContext context) {
    final currentPath = GoRouterState.of(context).uri.path;
    int selectedIndex = _paths.indexOf(currentPath);
    if (selectedIndex < 0) selectedIndex = 0;

    final destinations = [
      NavigationRailDestination(
        icon: const Icon(Icons.home_outlined),
        selectedIcon: const Icon(Icons.home),
        label: Text(tr(context, 'nav_home')),
      ),
      NavigationRailDestination(
        icon: const Icon(Icons.cloud_outlined),
        selectedIcon: const Icon(Icons.cloud),
        label: Text(tr(context, 'nav_images')),
      ),
      NavigationRailDestination(
        icon: const Icon(Icons.usb_outlined),
        selectedIcon: const Icon(Icons.usb),
        label: Text(tr(context, 'nav_creator')),
      ),
      NavigationRailDestination(
        icon: const Icon(Icons.computer_outlined),
        selectedIcon: const Icon(Icons.computer),
        label: Text(tr(context, 'nav_wtg')),
      ),
      NavigationRailDestination(
        icon: const Icon(Icons.receipt_long_outlined),
        selectedIcon: const Icon(Icons.receipt_long),
        label: Text(tr(context, 'nav_logs')),
      ),
      NavigationRailDestination(
        icon: const Icon(Icons.auto_awesome_outlined),
        selectedIcon: const Icon(Icons.auto_awesome),
        label: Text(tr(context, 'nav_ai')),
      ),
      NavigationRailDestination(
        icon: const Icon(Icons.handyman_outlined),
        selectedIcon: const Icon(Icons.handyman),
        label: Text(tr(context, 'nav_tools')),
      ),
      NavigationRailDestination(
        icon: const Icon(Icons.settings_outlined),
        selectedIcon: const Icon(Icons.settings),
        label: Text(tr(context, 'nav_settings')),
      ),
    ];

    return Scaffold(
      body: Row(
        children: [
          Container(
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerLow,
              border: Border(
                right: BorderSide(
                  color: Theme.of(context).colorScheme.outlineVariant,
                ),
              ),
            ),
            child: NavigationRail(
              selectedIndex: selectedIndex,
              onDestinationSelected: (index) {
                // Pop all routes back to root before navigating
                Navigator.of(
                  context,
                  rootNavigator: true,
                ).popUntil((route) => route.isFirst);
                context.go(_paths[index]);
              },
              labelType: NavigationRailLabelType.all,
              leading: Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Column(
                  children: [
                    Icon(
                      Icons.desktop_windows_rounded,
                      size: 32,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'WDS',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                  ],
                ),
              ),
              destinations: destinations,
            ),
          ),
          const VerticalDivider(thickness: 1, width: 1),
          Expanded(child: widget.child),
        ],
      ),
    );
  }
}
