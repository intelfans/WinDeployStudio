import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/localization/strings.dart';
import '../models/update_models.dart';
import '../providers/update_provider.dart';

class UpdateDialog extends ConsumerWidget {
  const UpdateDialog({super.key});

  static void show(BuildContext context) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const UpdateDialog(),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(updateProvider);

    if (state.status == UpdateStatus.downloading) {
      return _DownloadingDialog(
        progress: state.downloadProgress,
        speed: state.downloadSpeed,
        remaining: state.downloadRemaining,
        phase: state.downloadPhase,
        onCancel: () => ref.read(updateProvider.notifier).cancelDownload(),
      );
    }

    if (state.status == UpdateStatus.downloaded) {
      return _InstallDialog(
        info: state.info!,
        onInstall: () async {
          final success = await ref.read(updateProvider.notifier).installUpdate();
          if (success && context.mounted) {
            Navigator.of(context).pop();
          }
        },
        onLater: () => Navigator.of(context).pop(),
      );
    }

    if (state.status == UpdateStatus.available && state.info != null) {
      return _AvailableDialog(
        info: state.info!,
        onUpdate: () {
          ref.read(updateProvider.notifier).startDownload();
        },
        onLater: () => Navigator.of(context).pop(),
        onIgnore: () {
          ref.read(updateProvider.notifier).ignoreVersion(state.info!.tagName);
          Navigator.of(context).pop();
        },
      );
    }

    return const SizedBox.shrink();
  }
}

class _AvailableDialog extends StatelessWidget {
  final UpdateInfo info;
  final VoidCallback onUpdate;
  final VoidCallback onLater;
  final VoidCallback onIgnore;

  const _AvailableDialog({
    required this.info,
    required this.onUpdate,
    required this.onLater,
    required this.onIgnore,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return AlertDialog(
      icon: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: colorScheme.primaryContainer,
          shape: BoxShape.circle,
        ),
        child: Icon(
          Icons.system_update_rounded,
          size: 32,
          color: colorScheme.primary,
        ),
      ),
      title: Text(
        '${tr(context, 'update_available_title')} v${info.version}',
        textAlign: TextAlign.center,
      ),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              tr(context, 'update_available_desc'),
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '${tr(context, 'update_published')}: ${info.publishedAt.year}-${info.publishedAt.month.toString().padLeft(2, '0')}-${info.publishedAt.day.toString().padLeft(2, '0')}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            if (info.body.isNotEmpty) ...[
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  tr(context, 'update_release_notes'),
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Container(
                constraints: const BoxConstraints(maxHeight: 200),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: SingleChildScrollView(
                  child: Text(
                    info.body,
                    style: theme.textTheme.bodySmall,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: onIgnore,
          child: Text(tr(context, 'update_ignore')),
        ),
        TextButton(
          onPressed: onLater,
          child: Text(tr(context, 'update_later')),
        ),
        FilledButton.icon(
          icon: const Icon(Icons.download_rounded, size: 18),
          onPressed: onUpdate,
          label: Text(tr(context, 'update_now')),
        ),
      ],
    );
  }
}

class _DownloadingDialog extends StatefulWidget {
  final double progress;
  final String speed;
  final String remaining;
  final DownloadPhase phase;
  final VoidCallback onCancel;

  const _DownloadingDialog({
    required this.progress,
    required this.speed,
    required this.remaining,
    required this.phase,
    required this.onCancel,
  });

  @override
  State<_DownloadingDialog> createState() => _DownloadingDialogState();
}

class _DownloadingDialogState extends State<_DownloadingDialog>
    with SingleTickerProviderStateMixin {
  late AnimationController _animController;
  late Animation<double> _progressAnim;
  int _tipIndex = 0;
  Timer? _tipTimer;

  static const _connectingTips = [
    'download_tip_connecting_1',
    'download_tip_connecting_2',
    'download_tip_connecting_3',
  ];

  static const _optimizingTips = [
    'download_tip_optimizing_1',
    'download_tip_optimizing_2',
    'download_tip_optimizing_3',
  ];

  static const _retryingTips = [
    'download_tip_retrying_1',
    'download_tip_retrying_2',
  ];

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _progressAnim = Tween<double>(begin: 0, end: widget.progress).animate(
      CurvedAnimation(parent: _animController, curve: Curves.easeOut),
    );
    _animController.forward();
    _startTipRotation();
  }

  @override
  void didUpdateWidget(_DownloadingDialog oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.progress != widget.progress) {
      _progressAnim = Tween<double>(
        begin: _progressAnim.value,
        end: widget.progress,
      ).animate(
        CurvedAnimation(parent: _animController, curve: Curves.easeOut),
      );
      _animController.forward(from: 0);
    }
    if (oldWidget.phase != widget.phase) {
      _tipIndex = 0;
    }
  }

  void _startTipRotation() {
    _tipTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      if (mounted) {
        setState(() {
          _tipIndex++;
        });
      }
    });
  }

  @override
  void dispose() {
    _animController.dispose();
    _tipTimer?.cancel();
    super.dispose();
  }

  String _getCurrentTip(BuildContext context) {
    List<String> tips;
    switch (widget.phase) {
      case DownloadPhase.connecting:
        tips = _connectingTips;
        break;
      case DownloadPhase.optimizing:
        tips = _optimizingTips;
        break;
      case DownloadPhase.retrying:
        tips = _retryingTips;
        break;
      case DownloadPhase.stable:
        return tr(context, 'download_tip_stable');
      case DownloadPhase.failed:
        return tr(context, 'download_tip_failed');
    }
    return tr(context, tips[_tipIndex % tips.length]);
  }

  IconData _getPhaseIcon() {
    switch (widget.phase) {
      case DownloadPhase.connecting:
        return Icons.wifi_find_outlined;
      case DownloadPhase.optimizing:
        return Icons.speed_outlined;
      case DownloadPhase.stable:
        return Icons.cloud_download_outlined;
      case DownloadPhase.retrying:
        return Icons.refresh_outlined;
      case DownloadPhase.failed:
        return Icons.error_outline;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final percent = (widget.progress * 100).toStringAsFixed(0);

    return AlertDialog(
      icon: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: colorScheme.primaryContainer,
          shape: BoxShape.circle,
        ),
        child: Icon(
          _getPhaseIcon(),
          size: 32,
          color: colorScheme.primary,
        ),
      ),
      title: Text(
        tr(context, 'update_downloading'),
        textAlign: TextAlign.center,
      ),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedBuilder(
              animation: _progressAnim,
              builder: (context, _) {
                return ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: LinearProgressIndicator(
                    value: _progressAnim.value,
                    minHeight: 8,
                    backgroundColor: colorScheme.surfaceContainerHighest,
                    color: colorScheme.primary,
                  ),
                );
              },
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '${tr(context, 'update_progress')}: $percent%',
                  style: theme.textTheme.bodyMedium,
                ),
                Text(
                  widget.speed.isNotEmpty ? widget.speed : '0 KB/s',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 300),
                  child: Text(
                    _getCurrentTip(context),
                    key: ValueKey('${widget.phase}_$_tipIndex'),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colorScheme.primary,
                    ),
                  ),
                ),
                Text(
                  '${tr(context, 'update_remaining')}: ${widget.remaining}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: widget.onCancel,
          child: Text(tr(context, 'detail_cancel')),
        ),
      ],
    );
  }
}

class _InstallDialog extends StatelessWidget {
  final UpdateInfo info;
  final VoidCallback onInstall;
  final VoidCallback onLater;

  const _InstallDialog({
    required this.info,
    required this.onInstall,
    required this.onLater,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return AlertDialog(
      icon: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: colorScheme.primaryContainer,
          shape: BoxShape.circle,
        ),
        child: Icon(
          Icons.check_circle_rounded,
          size: 32,
          color: colorScheme.primary,
        ),
      ),
      title: Text(
        tr(context, 'update_install'),
        textAlign: TextAlign.center,
      ),
      content: Text(
        tr(context, 'update_install_desc'),
        textAlign: TextAlign.center,
        style: theme.textTheme.bodyMedium?.copyWith(
          color: colorScheme.onSurfaceVariant,
        ),
      ),
      actions: [
        TextButton(
          onPressed: onLater,
          child: Text(tr(context, 'update_later')),
        ),
        FilledButton.icon(
          icon: const Icon(Icons.install_desktop_rounded, size: 18),
          onPressed: onInstall,
          label: Text(tr(context, 'update_install')),
        ),
      ],
    );
  }
}
