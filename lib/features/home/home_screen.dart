import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/typography.dart';
import '../../core/constants/app_constants.dart';
import '../../core/localization/strings.dart';
import '../../shared/widgets/special_thanks_section.dart';
import '../mirror/models/mirror_models.dart';
import '../mirror/providers/mirror_provider.dart';
import '../mirror/providers/recent_mirrors_provider.dart';
import '../mirror/services/recent_mirrors_service.dart';
import '../update/models/update_models.dart';
import '../update/providers/update_provider.dart';
import '../update/screens/update_dialog.dart';
import 'models/home_storage_overview.dart';
import 'providers/home_dashboard_preferences.dart';
import 'providers/home_storage_overview_provider.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  Timer? _updateTimer;

  @override
  void initState() {
    super.initState();
    // MirrorNotifier updates state synchronously before loading its asset.
    // Start it after the first frame so Riverpod is not mutated during mount.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(ref.read(mirrorProvider.notifier).loadBuiltInMirrors());
    });
    _updateTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) _checkForUpdate();
    });
  }

  @override
  void dispose() {
    _updateTimer?.cancel();
    super.dispose();
  }

  Future<void> _checkForUpdate() async {
    final notifier = ref.read(updateProvider.notifier);
    if (!ref.read(updateProvider).autoCheckEnabled) return;

    await notifier.checkForUpdate();
    if (!mounted) return;
    final state = ref.read(updateProvider);
    if (state.status == UpdateStatus.available && state.info != null) {
      UpdateDialog.show(context);
    }
  }

  Future<void> _showHomeEditor(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const _HomeEditorSheet(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final preferences = ref.watch(homeDashboardPreferencesProvider);
    final hasWorkspace =
        preferences.isModuleVisible(HomeDashboardModule.recentImages) ||
        preferences.isModuleVisible(HomeDashboardModule.storageOverview);

    return Scaffold(
      body: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 900;
          final padding = compact ? 16.0 : 32.0;
          return SingleChildScrollView(
            padding: EdgeInsets.all(padding),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1680),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _HomeHeader(colorScheme: colorScheme),
                  SizedBox(height: compact ? 32 : 40),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          tr(context, 'home_quick_start'),
                          style: AppTypography.sectionTitleWith(
                            colorScheme.onSurface,
                          ),
                        ),
                      ),
                      Tooltip(
                        message: tr(context, 'home_customize'),
                        child: IconButton(
                          onPressed: () => _showHomeEditor(context),
                          icon: const Icon(Icons.tune_rounded),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  const _QuickStartGrid(),
                  if (hasWorkspace) ...[
                    const SizedBox(height: 32),
                    const _HomeWorkspace(),
                  ],
                  SizedBox(height: compact ? 32 : 40),
                  Text(
                    tr(context, 'home_about'),
                    style: AppTypography.sectionTitleWith(
                      colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 20),
                  const _AboutCard(),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _HomeHeader extends StatelessWidget {
  const _HomeHeader({required this.colorScheme});

  final ColorScheme colorScheme;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            color: colorScheme.primaryContainer,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Icon(
            Icons.desktop_windows_rounded,
            size: 32,
            color: colorScheme.onPrimaryContainer,
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                tr(context, 'home_title'),
                style: AppTypography.pageTitleWith(colorScheme.onSurface),
              ),
              const SizedBox(height: 4),
              Text(
                tr(context, 'home_subtitle'),
                style: AppTypography.bodyWith(colorScheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _QuickStartGrid extends ConsumerWidget {
  const _QuickStartGrid();

  static const _gap = 16.0;
  static const _threeColumnBreakpoint = 720.0;
  static const _twoColumnBreakpoint = 480.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final preferences = ref.watch(homeDashboardPreferencesProvider);
    final notifier = ref.read(homeDashboardPreferencesProvider.notifier);
    final cards = preferences.visibleQuickActions
        .map((action) => _quickActionDefinitions[action])
        .whereType<_QuickActionDefinition>()
        .map(
          (action) => _QuickActionCard(
            key: ValueKey(action.key),
            icon: action.icon,
            title: tr(context, action.titleKey),
            subtitle: tr(context, action.subtitleKey),
            color: action.color,
            onTap: () => context.go(action.route),
          ),
        )
        .toList(growable: false);

    if (cards.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              const Icon(Icons.dashboard_customize_outlined),
              const SizedBox(width: 12),
              Expanded(child: Text(tr(context, 'home_quick_start_empty'))),
              Tooltip(
                message: tr(context, 'home_customize_reset'),
                child: IconButton(
                  onPressed: notifier.reset,
                  icon: const Icon(Icons.restart_alt_rounded),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        // This receives the content pane width, rather than the full window
        // width. Keep three useful actions side by side at ordinary desktop
        // sizes even when the navigation pane is expanded.
        if (constraints.maxWidth >= _threeColumnBreakpoint) {
          return _ActionRow(cards: cards);
        }

        if (constraints.maxWidth >= _twoColumnBreakpoint) {
          if (cards.length <= 2) return _ActionRow(cards: cards);
          return Column(
            children: [
              _ActionRow(cards: cards.take(2).toList(growable: false)),
              for (var index = 2; index < cards.length; index++) ...[
                const SizedBox(height: _gap),
                SizedBox(width: double.infinity, child: cards[index]),
              ],
            ],
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var index = 0; index < cards.length; index++) ...[
              cards[index],
              if (index != cards.length - 1) const SizedBox(height: 12),
            ],
          ],
        );
      },
    );
  }
}

class _QuickActionDefinition {
  const _QuickActionDefinition({
    required this.key,
    required this.icon,
    required this.titleKey,
    required this.subtitleKey,
    required this.color,
    required this.route,
  });

  final String key;
  final IconData icon;
  final String titleKey;
  final String subtitleKey;
  final Color color;
  final String route;
}

const _quickActionDefinitions = <HomeQuickAction, _QuickActionDefinition>{
  HomeQuickAction.imageLibrary: _QuickActionDefinition(
    key: 'home-quick-action-image-library',
    icon: Icons.cloud_outlined,
    titleKey: 'home_image_library',
    subtitleKey: 'home_image_library_desc',
    color: Color(0xFF00A4EF),
    route: '/mirror',
  ),
  HomeQuickAction.installMedia: _QuickActionDefinition(
    key: 'home-quick-action-install-media',
    icon: Icons.usb_outlined,
    titleKey: 'home_bootable_usb',
    subtitleKey: 'home_bootable_usb_desc',
    color: Color(0xFF0071C5),
    route: '/creator',
  ),
  HomeQuickAction.toGo: _QuickActionDefinition(
    key: 'home-quick-action-to-go',
    icon: Icons.computer_outlined,
    titleKey: 'home_wtg',
    subtitleKey: 'home_wtg_desc',
    color: Color(0xFF7B61FF),
    route: '/wtg',
  ),
};

class _ActionRow extends StatelessWidget {
  const _ActionRow({required this.cards});

  final List<Widget> cards;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var index = 0; index < cards.length; index++) ...[
              Expanded(child: cards[index]),
              if (index != cards.length - 1)
                const SizedBox(width: _QuickStartGrid._gap),
            ],
          ],
        ),
      ),
    );
  }
}

class _QuickActionCard extends StatelessWidget {
  const _QuickActionCard({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 88),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, size: 24, color: color),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.cardTitleWith(colors.onSurface),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        subtitle,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.captionWith(
                          colors.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _HomeWorkspace extends ConsumerWidget {
  const _HomeWorkspace();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final preferences = ref.watch(homeDashboardPreferencesProvider);
    final panels = <Widget>[
      if (preferences.isModuleVisible(HomeDashboardModule.recentImages))
        const _RecentImagesPanel(),
      if (preferences.isModuleVisible(HomeDashboardModule.storageOverview))
        const _StorageOverviewPanel(),
    ];
    if (panels.isEmpty) return const SizedBox.shrink();

    final colors = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          tr(context, 'home_workspace'),
          style: AppTypography.sectionTitleWith(colors.onSurface),
        ),
        const SizedBox(height: 16),
        LayoutBuilder(
          builder: (context, constraints) {
            if (panels.length == 1) return panels.single;
            if (constraints.maxWidth < 720) {
              return Column(
                children: [panels[0], const SizedBox(height: 16), panels[1]],
              );
            }
            return IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(child: panels[0]),
                  const SizedBox(width: 16),
                  Expanded(child: panels[1]),
                ],
              ),
            );
          },
        ),
      ],
    );
  }
}

class _DashboardPanel extends StatelessWidget {
  const _DashboardPanel({
    super.key,
    required this.icon,
    required this.title,
    required this.child,
    this.trailing,
  });

  final IconData icon;
  final String title;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 20, color: colors.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    style: AppTypography.cardTitleWith(colors.onSurface),
                  ),
                ),
                ?trailing,
              ],
            ),
            const SizedBox(height: 14),
            Expanded(child: child),
          ],
        ),
      ),
    );
  }
}

const _homeWorkspacePanelHeight = 200.0;

class _DashboardEmptyState extends StatelessWidget {
  const _DashboardEmptyState({required this.icon, required this.message});

  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Center(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: colors.onSurfaceVariant),
          const SizedBox(width: 10),
          Flexible(
            child: Text(
              message,
              style: AppTypography.bodyWith(colors.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
  }
}

class _RecentImagesPanel extends ConsumerStatefulWidget {
  const _RecentImagesPanel();

  @override
  ConsumerState<_RecentImagesPanel> createState() => _RecentImagesPanelState();
}

class _RecentImagesPanelState extends ConsumerState<_RecentImagesPanel> {
  final _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final entries = ref.watch(recentMirrorEntriesProvider);
    final mirrorState = ref.watch(mirrorProvider);
    final locale = Localizations.localeOf(context);
    final colors = Theme.of(context).colorScheme;
    final canClear = entries.asData?.value.isNotEmpty ?? false;

    return SizedBox(
      height: _homeWorkspacePanelHeight,
      child: _DashboardPanel(
        key: const ValueKey('home-recent-images-panel'),
        icon: Icons.history_rounded,
        title: tr(context, 'home_recent_images'),
        trailing: Tooltip(
          message: tr(context, 'home_recent_images_clear'),
          child: IconButton(
            key: const ValueKey('home-clear-recent-images'),
            onPressed: canClear
                ? () => unawaited(_clearRecentImages(ref))
                : null,
            icon: const Icon(Icons.delete_sweep_outlined),
          ),
        ),
        child: entries.when(
          loading: () => const Center(
            child: SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
          error: (_, _) => _DashboardEmptyState(
            icon: Icons.image_not_supported_outlined,
            message: tr(context, 'home_recent_images_empty'),
          ),
          data: (records) {
            final byId = <String, MirrorItem>{
              for (final item in mirrorState.data?.items ?? const [])
                item.id: item,
            };
            final items = records
                .map((record) => byId[record.mirrorId])
                .whereType<MirrorItem>()
                .where((item) => item.isVisibleInLocale(locale))
                .toList(growable: false);

            if (items.isEmpty) {
              return _DashboardEmptyState(
                icon: Icons.image_outlined,
                message: tr(context, 'home_recent_images_empty'),
              );
            }

            return Scrollbar(
              key: const ValueKey('home-recent-images-scrollbar'),
              controller: _scrollController,
              thumbVisibility: true,
              interactive: true,
              child: ListView.separated(
                key: const ValueKey('home-recent-images-list'),
                controller: _scrollController,
                primary: false,
                physics: const ClampingScrollPhysics(),
                itemCount: items.length,
                separatorBuilder: (_, _) => const Divider(height: 6),
                itemBuilder: (context, index) {
                  final item = items[index];
                  final detailParts = <String>[
                    if (item.getType(locale).isNotEmpty) item.getType(locale),
                    if (item.version != null) item.version!,
                  ];
                  return InkWell(
                    borderRadius: BorderRadius.circular(6),
                    onTap: () => context.go('/mirror/${item.id}', extra: item),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 1,
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.album_outlined,
                            size: 20,
                            color: colors.primary,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  item.getName(locale),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: AppTypography.body.copyWith(
                                    color: colors.onSurface,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                if (detailParts.isNotEmpty)
                                  Text(
                                    detailParts.join(' · '),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: AppTypography.captionWith(
                                      colors.onSurfaceVariant,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            );
          },
        ),
      ),
    );
  }

  Future<void> _clearRecentImages(WidgetRef ref) async {
    await const RecentMirrorsService().clear();
    ref.invalidate(recentMirrorEntriesProvider);
  }
}

class _StorageOverviewPanel extends ConsumerWidget {
  const _StorageOverviewPanel();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final overview = ref.watch(homeStorageOverviewProvider);
    final colors = Theme.of(context).colorScheme;
    return SizedBox(
      height: _homeWorkspacePanelHeight,
      child: _DashboardPanel(
        key: const ValueKey('home-storage-overview-panel'),
        icon: Icons.storage_rounded,
        title: tr(context, 'home_storage_overview'),
        child: overview.when(
          loading: () => const Center(
            child: SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
          error: (_, _) => _DashboardEmptyState(
            icon: Icons.usb_off_outlined,
            message: tr(context, 'home_storage_empty'),
          ),
          data: (data) {
            if (data.devices.isEmpty) {
              return _DashboardEmptyState(
                icon: Icons.usb_off_outlined,
                message: tr(context, 'home_storage_empty'),
              );
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  tr(
                    context,
                    'home_storage_devices',
                  ).replaceAll('{count}', '${data.externalDeviceCount}'),
                  style: AppTypography.captionWith(colors.onSurfaceVariant),
                ),
                const SizedBox(height: 6),
                Expanded(
                  child: Scrollbar(
                    child: ListView.separated(
                      key: const ValueKey('home-storage-devices-list'),
                      primary: false,
                      padding: EdgeInsets.zero,
                      itemCount: data.devices.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (context, index) =>
                          _StorageDeviceRow(device: data.devices[index]),
                    ),
                  ),
                ),
                Align(
                  alignment: AlignmentDirectional.centerEnd,
                  child: TextButton.icon(
                    onPressed: () => context.go('/disk-tools'),
                    icon: const Icon(Icons.storage_outlined, size: 18),
                    label: Text(tr(context, 'home_storage_open')),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _StorageDeviceRow extends StatelessWidget {
  const _StorageDeviceRow({required this.device});

  final HomeStorageDeviceOverview device;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final details = <String>[
      device.capacityLabel,
      device.busType,
      if (device.driveLetters.isNotEmpty) device.driveLetters.join(', '),
    ];
    final name = device.name.isEmpty
        ? tr(context, 'home_storage_overview')
        : device.name;

    return Semantics(
      label: '$name, ${details.join(' · ')}',
      child: SizedBox(
        key: ValueKey('home-storage-device-${device.diskNumber}'),
        height: 32,
        child: Row(
          children: [
            Icon(Icons.usb_rounded, size: 17, color: colors.primary),
            const SizedBox(width: 8),
            Expanded(
              flex: 3,
              child: Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.caption.copyWith(
                  color: colors.onSurface,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              flex: 2,
              child: Text(
                details.join(' · '),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.end,
                style: AppTypography.captionWith(colors.onSurfaceVariant),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HomeEditorSheet extends ConsumerWidget {
  const _HomeEditorSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final preferences = ref.watch(homeDashboardPreferencesProvider);
    final notifier = ref.read(homeDashboardPreferencesProvider.notifier);
    final colors = Theme.of(context).colorScheme;
    final maxHeight = MediaQuery.sizeOf(context).height * 0.72;

    return SafeArea(
      child: SizedBox(
        key: const ValueKey('home-editor-sheet'),
        height: maxHeight,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      tr(context, 'home_customize'),
                      style: AppTypography.sectionTitleWith(colors.onSurface),
                    ),
                  ),
                  Tooltip(
                    message: tr(context, 'home_customize_reset'),
                    child: IconButton(
                      onPressed: notifier.reset,
                      icon: const Icon(Icons.restart_alt_rounded),
                    ),
                  ),
                ],
              ),
              const Divider(height: 24),
              Expanded(
                child: ListView(
                  children: [
                    for (
                      var index = 0;
                      index < preferences.quickActionOrder.length;
                      index++
                    )
                      _HomeEditorQuickActionRow(
                        action: preferences.quickActionOrder[index],
                        index: index,
                        total: preferences.quickActionOrder.length,
                        visible: preferences.isQuickActionVisible(
                          preferences.quickActionOrder[index],
                        ),
                        onVisibleChanged: (visible) {
                          final action = preferences.quickActionOrder[index];
                          if (!visible &&
                              preferences.visibleQuickActions.length == 1) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  tr(context, 'home_quick_start_empty'),
                                ),
                              ),
                            );
                            return;
                          }
                          unawaited(
                            notifier.setQuickActionVisible(action, visible),
                          );
                        },
                        onMove: (offset) {
                          final target = index + offset;
                          if (target < 0 ||
                              target >= preferences.quickActionOrder.length) {
                            return;
                          }
                          final order = List<HomeQuickAction>.of(
                            preferences.quickActionOrder,
                          );
                          final action = order.removeAt(index);
                          order.insert(target, action);
                          unawaited(notifier.setQuickActionOrder(order));
                        },
                      ),
                    const Divider(height: 28),
                    _HomeEditorModuleRow(
                      module: HomeDashboardModule.recentImages,
                      icon: Icons.history_rounded,
                      title: tr(context, 'home_recent_images'),
                      visible: preferences.isModuleVisible(
                        HomeDashboardModule.recentImages,
                      ),
                      onVisibleChanged: (visible) => unawaited(
                        notifier.setModuleVisible(
                          HomeDashboardModule.recentImages,
                          visible,
                        ),
                      ),
                    ),
                    _HomeEditorModuleRow(
                      module: HomeDashboardModule.storageOverview,
                      icon: Icons.storage_rounded,
                      title: tr(context, 'home_storage_overview'),
                      visible: preferences.isModuleVisible(
                        HomeDashboardModule.storageOverview,
                      ),
                      onVisibleChanged: (visible) => unawaited(
                        notifier.setModuleVisible(
                          HomeDashboardModule.storageOverview,
                          visible,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HomeEditorQuickActionRow extends StatelessWidget {
  const _HomeEditorQuickActionRow({
    required this.action,
    required this.index,
    required this.total,
    required this.visible,
    required this.onVisibleChanged,
    required this.onMove,
  });

  final HomeQuickAction action;
  final int index;
  final int total;
  final bool visible;
  final ValueChanged<bool> onVisibleChanged;
  final ValueChanged<int> onMove;

  @override
  Widget build(BuildContext context) {
    final definition = _quickActionDefinitions[action]!;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      key: ValueKey('home-editor-quick-action-${action.name}'),
      leading: Icon(definition.icon),
      title: Text(tr(context, definition.titleKey)),
      trailing: Wrap(
        spacing: 2,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Tooltip(
            message: tr(context, 'home_customize_move_up'),
            child: IconButton(
              onPressed: index == 0 ? null : () => onMove(-1),
              icon: const Icon(Icons.arrow_upward_rounded),
            ),
          ),
          Tooltip(
            message: tr(context, 'home_customize_move_down'),
            child: IconButton(
              onPressed: index == total - 1 ? null : () => onMove(1),
              icon: const Icon(Icons.arrow_downward_rounded),
            ),
          ),
          Switch(
            key: ValueKey('home-editor-quick-action-${action.name}-switch'),
            value: visible,
            onChanged: onVisibleChanged,
          ),
        ],
      ),
    );
  }
}

class _HomeEditorModuleRow extends StatelessWidget {
  const _HomeEditorModuleRow({
    required this.module,
    required this.icon,
    required this.title,
    required this.visible,
    required this.onVisibleChanged,
  });

  final HomeDashboardModule module;
  final IconData icon;
  final String title;
  final bool visible;
  final ValueChanged<bool> onVisibleChanged;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      key: ValueKey('home-editor-module-${module.name}'),
      leading: Icon(icon),
      title: Text(title),
      trailing: Switch(
        key: ValueKey('home-editor-module-${module.name}-switch'),
        value: visible,
        onChanged: onVisibleChanged,
      ),
    );
  }
}

class _AboutCard extends StatelessWidget {
  const _AboutCard();

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            _InfoRow(tr(context, 'home_version'), AppConstants.appVersion),
            _InfoRow(tr(context, 'home_platform'), 'Windows Desktop'),
            _InfoRow(tr(context, 'home_engine'), 'Flutter 3.44'),
            const Divider(),
            _InfoRow(
              tr(context, 'home_focus'),
              tr(context, 'home_focus_value'),
            ),
            _InfoRow(tr(context, 'home_license'), AppConstants.licenseName),
            _InfoRow(
              tr(context, 'about_github_repository'),
              AppConstants.githubRepository,
            ),
            _InfoRow(
              tr(context, 'sourceforge_repository_title'),
              AppConstants.globalMirrorRepository,
            ),
            const SizedBox(height: 12),
            const SpecialThanksSection(compact: true),
          ],
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final stacked = constraints.maxWidth < 460;
          if (stacked) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: AppTypography.bodyWith(colorScheme.onSurfaceVariant),
                ),
                const SizedBox(height: 4),
                SelectableText(
                  value,
                  style: AppTypography.body.copyWith(
                    color: colorScheme.onSurface,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            );
          }

          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 150,
                child: Text(
                  label,
                  style: AppTypography.bodyWith(colorScheme.onSurfaceVariant),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: SelectableText(
                  value,
                  textAlign: TextAlign.end,
                  style: AppTypography.body.copyWith(
                    color: colorScheme.onSurface,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
