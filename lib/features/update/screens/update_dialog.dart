import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/localization/strings.dart';
import '../../../shared/widgets/app_page.dart';
import '../../../shared/widgets/special_thanks_section.dart';
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

    if (state.status == UpdateStatus.checking ||
        state.status == UpdateStatus.installing) {
      return _UpdateProgressDialog(
        messageKey: state.status == UpdateStatus.installing
            ? 'update_installing'
            : 'update_checking',
      );
    }

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
        error: state.error,
        releasePageUrl: ref.read(updateProvider.notifier).releasePageUrl,
        onInstall: () async {
          final success = await ref
              .read(updateProvider.notifier)
              .installUpdate();
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
        releasePageUrl: ref.read(updateProvider.notifier).releasePageUrl,
      );
    }

    if (state.status == UpdateStatus.error) {
      return _UpdateErrorDialog(
        message: state.error ?? tr(context, 'update_check_failed'),
        releasePageUrl: ref.read(updateProvider.notifier).releasePageUrl,
        onRetry: state.info == null
            ? () => ref
                  .read(updateProvider.notifier)
                  .checkForUpdate(forceRefresh: true)
            : () => ref.read(updateProvider.notifier).startDownload(),
        onClose: () => Navigator.of(context).pop(),
      );
    }

    return const SizedBox.shrink();
  }
}

class _UpdateProgressDialog extends StatelessWidget {
  final String messageKey;

  const _UpdateProgressDialog({required this.messageKey});

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      content: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(strokeWidth: 2.5),
          ),
          const SizedBox(width: 16),
          Flexible(child: Text(tr(context, messageKey))),
        ],
      ),
    );
  }
}

class _UpdateErrorDialog extends StatelessWidget {
  final String message;
  final String releasePageUrl;
  final VoidCallback onRetry;
  final VoidCallback onClose;

  const _UpdateErrorDialog({
    required this.message,
    required this.releasePageUrl,
    required this.onRetry,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return AlertDialog(
      icon: Icon(Icons.error_outline, color: colorScheme.error, size: 36),
      title: Text(tr(context, 'creator_error')),
      content: Text(message, textAlign: TextAlign.center),
      actions: [
        AppDialogActionBar(
          children: [
            TextButton(
              onPressed: onClose,
              child: Text(tr(context, 'detail_cancel')),
            ),
            OutlinedButton.icon(
              icon: const Icon(Icons.open_in_browser, size: 18),
              onPressed: () => launchUrl(Uri.parse(releasePageUrl)),
              label: Text(tr(context, 'update_open_browser')),
            ),
            FilledButton.icon(
              icon: const Icon(Icons.refresh, size: 18),
              onPressed: onRetry,
              label: Text(tr(context, 'images_retry')),
            ),
          ],
        ),
      ],
    );
  }
}

class _AvailableDialog extends StatelessWidget {
  final UpdateInfo info;
  final VoidCallback onUpdate;
  final VoidCallback onLater;
  final VoidCallback onIgnore;
  final String releasePageUrl;

  const _AvailableDialog({
    required this.info,
    required this.onUpdate,
    required this.onLater,
    required this.onIgnore,
    required this.releasePageUrl,
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
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 450),
        child: SingleChildScrollView(
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
                  alignment: AlignmentDirectional.centerStart,
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
                    child: MarkdownBody(
                      data: info.body,
                      styleSheet: MarkdownStyleSheet(
                        p: theme.textTheme.bodySmall,
                        h1: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                        h2: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                        h3: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                        code: theme.textTheme.bodySmall?.copyWith(
                          fontFamily: 'Consolas',
                          backgroundColor: colorScheme.surfaceContainerHighest,
                        ),
                        codeblockDecoration: BoxDecoration(
                          color: colorScheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        listBullet: theme.textTheme.bodySmall,
                      ),
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 12),
              const SpecialThanksSection(compact: true),
            ],
          ),
        ),
      ),
      actions: [
        AppDialogActionBar(
          children: [
            TextButton(
              onPressed: onIgnore,
              child: Text(tr(context, 'update_ignore')),
            ),
            TextButton(
              onPressed: onLater,
              child: Text(tr(context, 'update_later')),
            ),
            OutlinedButton.icon(
              icon: const Icon(Icons.open_in_browser, size: 18),
              onPressed: () => launchUrl(Uri.parse(releasePageUrl)),
              label: Text(tr(context, 'update_open_browser')),
            ),
            FilledButton.icon(
              icon: const Icon(Icons.download_rounded, size: 18),
              onPressed: onUpdate,
              label: Text(tr(context, 'update_now')),
            ),
          ],
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
    _progressAnim = Tween<double>(
      begin: 0,
      end: widget.progress,
    ).animate(CurvedAnimation(parent: _animController, curve: Curves.easeOut));
    _animController.forward();
    _startTipRotation();
  }

  @override
  void didUpdateWidget(_DownloadingDialog oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.progress != widget.progress) {
      _progressAnim =
          Tween<double>(
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
        child: Icon(_getPhaseIcon(), size: 32, color: colorScheme.primary),
      ),
      title: Text(
        tr(context, 'update_downloading'),
        textAlign: TextAlign.center,
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
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
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              spacing: 12,
              runSpacing: 4,
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
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 300),
                  child: Align(
                    key: ValueKey('${widget.phase}_$_tipIndex'),
                    alignment: AlignmentDirectional.centerStart,
                    child: Text(
                      _getCurrentTip(context),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.primary,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${tr(context, 'update_remaining')}: ${widget.remaining}',
                  textAlign: TextAlign.end,
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
  final String? error;
  final String releasePageUrl;
  final VoidCallback onInstall;
  final VoidCallback onLater;

  const _InstallDialog({
    required this.info,
    this.error,
    required this.releasePageUrl,
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
      title: Text(tr(context, 'update_install'), textAlign: TextAlign.center),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            tr(context, 'update_install_desc'),
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          if (error != null && error!.isNotEmpty) ...[
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: colorScheme.errorContainer,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                error!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colorScheme.onErrorContainer,
                ),
              ),
            ),
          ],
        ],
      ),
      actions: [
        AppDialogActionBar(
          children: [
            TextButton(
              onPressed: onLater,
              child: Text(tr(context, 'update_later')),
            ),
            OutlinedButton.icon(
              icon: const Icon(Icons.open_in_browser, size: 18),
              onPressed: () => launchUrl(Uri.parse(releasePageUrl)),
              label: Text(tr(context, 'update_open_browser')),
            ),
            FilledButton.icon(
              icon: const Icon(Icons.install_desktop_rounded, size: 18),
              onPressed: onInstall,
              label: Text(tr(context, 'update_install')),
            ),
          ],
        ),
      ],
    );
  }
}
