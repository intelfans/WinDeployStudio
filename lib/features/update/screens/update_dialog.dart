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
      builder: (_) => const UpdateDialog(),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(updateProvider);
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    if (state.status == UpdateStatus.downloading) {
      return _DownloadingDialog(
        progress: state.downloadProgress,
        speed: state.downloadSpeed,
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
        tr(context, 'update_available_title'),
        textAlign: TextAlign.center,
      ),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '${tr(context, 'update_available_desc')}\n${info.name}',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
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

class _DownloadingDialog extends StatelessWidget {
  final double progress;
  final String speed;
  final VoidCallback onCancel;

  const _DownloadingDialog({
    required this.progress,
    required this.speed,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final percent = (progress * 100).toStringAsFixed(0);

    return AlertDialog(
      icon: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: colorScheme.primaryContainer,
          shape: BoxShape.circle,
        ),
        child: Icon(
          Icons.download_rounded,
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
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 8,
                backgroundColor: colorScheme.surfaceContainerHighest,
                color: colorScheme.primary,
              ),
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
                  '${tr(context, 'update_speed')}: $speed',
                  style: theme.textTheme.bodyMedium?.copyWith(
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
          onPressed: onCancel,
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
