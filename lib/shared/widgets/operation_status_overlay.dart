import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/localization/strings.dart';
import '../../core/services/operation_status_service.dart';
import '../../features/ai_assistant/models/chat_models.dart';
import '../../features/ai_assistant/providers/chat_provider.dart';

/// A movable, non-modal activity indicator that survives navigation. The
/// operation itself lives in a service; this widget only presents its latest
/// snapshot and never blocks the current page.
class OperationStatusOverlay extends ConsumerStatefulWidget {
  final String currentPath;

  const OperationStatusOverlay({super.key, required this.currentPath});

  @override
  ConsumerState<OperationStatusOverlay> createState() =>
      _OperationStatusOverlayState();
}

class _OperationStatusOverlayState
    extends ConsumerState<OperationStatusOverlay> {
  Offset _dragOffset = Offset.zero;
  bool _collapsed = false;

  void _move(DragUpdateDetails details) {
    setState(() => _dragOffset += details.delta);
  }

  List<_ActivityView> _activities(BuildContext context, WidgetRef ref) {
    final activities = ref.watch(operationStatusProvider);
    final chat = ref.watch(chatProvider);
    final items = <_ActivityView>[];

    for (final activity in activities.values) {
      if (!activity.active) continue;
      final hidden =
          activity.kind == TrackedOperationKind.installMedia &&
              widget.currentPath == '/creator' ||
          activity.kind == TrackedOperationKind.toGo &&
              widget.currentPath == '/wtg';
      if (hidden) continue;
      items.add(
        _ActivityView(
          icon: activity.kind == TrackedOperationKind.installMedia
              ? Icons.usb_outlined
              : Icons.computer_outlined,
          label: activity.kind == TrackedOperationKind.installMedia
              ? tr(context, 'creator_title')
              : tr(context, 'wtg_title'),
          message: _resolveOperationMessage(context, activity),
          progress: activity.progress,
          route: activity.kind == TrackedOperationKind.installMedia
              ? '/creator'
              : '/wtg',
        ),
      );
    }

    if (chat.isGenerating && widget.currentPath != '/ai') {
      final lastAssistant = chat.activeSession?.messages
          .where((message) => message.role == 'assistant')
          .lastOrNull;
      final searchKey = lastAssistant?.searchStatus == AiSearchStatus.searching
          ? 'ai_search_searching'
          : (lastAssistant?.content.trim().isNotEmpty == true
                ? 'ai_answering'
                : 'ai_thinking');
      items.add(
        _ActivityView(
          icon: Icons.auto_awesome_outlined,
          label: tr(context, 'nav_ai'),
          message: tr(context, searchKey),
          route: '/ai',
        ),
      );
    }
    return items;
  }

  String _resolveOperationMessage(
    BuildContext context,
    OperationActivity activity,
  ) {
    final key = activity.message.split('\n').first.trim();
    if (key.isEmpty) return tr(context, 'deploy_running');
    return tr(context, key);
  }

  @override
  Widget build(BuildContext context) {
    final items = _activities(context, ref);
    if (items.isEmpty) return const SizedBox.shrink();

    final size = MediaQuery.sizeOf(context);
    final availableWidth = math.max(56.0, size.width - 32);
    final panelWidth = (_collapsed ? 64.0 : math.min(430.0, availableWidth))
        .toDouble();
    final defaultLeft = math.max(16.0, size.width - panelWidth - 16).toDouble();
    final maxTop = math
        .max(12.0, size.height - (_collapsed ? 80.0 : 340.0))
        .toDouble();
    final left = (defaultLeft + _dragOffset.dx)
        .clamp(16.0, math.max(16.0, size.width - panelWidth - 16))
        .toDouble();
    final top = (12.0 + _dragOffset.dy).clamp(12.0, maxTop).toDouble();

    return Positioned(
      left: left,
      top: top,
      width: panelWidth,
      child: MouseRegion(
        cursor: SystemMouseCursors.move,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onPanUpdate: _move,
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 220),
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeInCubic,
            child: _collapsed
                ? _buildOrb(context, items)
                : _buildPanel(context, items, panelWidth),
          ),
        ),
      ),
    );
  }

  Widget _buildPanel(
    BuildContext context,
    List<_ActivityView> items,
    double width,
  ) {
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      elevation: 6,
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 14, 12, 14),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    Icons.sync_rounded,
                    size: 20,
                    color: theme.colorScheme.onPrimaryContainer,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    tr(context, 'deploy_running'),
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  tooltip: tr(context, 'close'),
                  onPressed: () => setState(() => _collapsed = true),
                  icon: const Icon(Icons.keyboard_arrow_down_rounded),
                ),
              ],
            ),
            const SizedBox(height: 8),
            for (var index = 0; index < items.length; index++) ...[
              if (index > 0) const Divider(height: 12),
              _ActivityRow(
                item: items[index],
                onTap: () => context.go(items[index].route),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildOrb(BuildContext context, List<_ActivityView> items) {
    final theme = Theme.of(context);
    return Tooltip(
      message: tr(context, 'deploy_running'),
      child: Material(
        color: theme.colorScheme.primaryContainer,
        elevation: 7,
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => setState(() => _collapsed = false),
          child: SizedBox(
            width: 64,
            height: 64,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Icon(
                  items.first.icon,
                  color: theme.colorScheme.onPrimaryContainer,
                  size: 29,
                ),
                if (items.length > 1)
                  Positioned(
                    right: 2,
                    top: 2,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 5,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.error,
                        shape: BoxShape.circle,
                      ),
                      child: Text(
                        '${items.length}',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.onError,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
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

class _ActivityView {
  final IconData icon;
  final String label;
  final String message;
  final double? progress;
  final String route;

  const _ActivityView({
    required this.icon,
    required this.label,
    required this.message,
    required this.route,
    this.progress,
  });
}

class _ActivityRow extends StatelessWidget {
  final _ActivityView item;
  final VoidCallback onTap;

  const _ActivityRow({required this.item, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
          child: Row(
            children: [
              Icon(item.icon, size: 22, color: theme.colorScheme.primary),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      item.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      item.progress == null
                          ? item.message
                          : '${item.message} ${(item.progress! * 100).round()}%',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall,
                    ),
                    if (item.progress != null) ...[
                      const SizedBox(height: 6),
                      LinearProgressIndicator(
                        value: item.progress,
                        minHeight: 4,
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                Icons.open_in_new_rounded,
                size: 16,
                color: theme.colorScheme.outline,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
