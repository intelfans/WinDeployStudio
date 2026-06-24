import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import '../../core/localization/strings.dart';
import 'download_manager.dart';

class DownloadPanel extends StatelessWidget {
  final VoidCallback onDownloadCurrentPage;

  const DownloadPanel({super.key, required this.onDownloadCurrentPage});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final manager = DownloadManager();

    return ListenableBuilder(
      listenable: manager,
      builder: (context, _) {
        final items = manager.items;
        final hasCompleted = items.any((i) => i.status == DownloadStatus.completed ||
            i.status == DownloadStatus.cancelled || i.status == DownloadStatus.error);

        return Material(
          elevation: 8,
          borderRadius: BorderRadius.circular(12),
          color: colorScheme.surfaceContainerHigh,
          child: Container(
            width: 380,
            constraints: const BoxConstraints(maxHeight: 420),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Header
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
                  child: Row(
                    children: [
                      Icon(Icons.download_rounded, size: 18, color: colorScheme.primary),
                      const SizedBox(width: 8),
                      Text(tr(context, 'dl_title'), style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                      const Spacer(),
                      if (hasCompleted)
                        TextButton(
                          onPressed: () => manager.clearCompleted(),
                          child: Text(tr(context, 'dl_clear'), style: TextStyle(fontSize: 12)),
                        ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                // Download list
                if (items.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(32),
                    child: Column(
                      children: [
                        Icon(Icons.download_done_rounded, size: 36, color: colorScheme.onSurfaceVariant.withValues(alpha: 0.4)),
                        const SizedBox(height: 8),
                        Text(tr(context, 'dl_empty'), style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 13)),
                      ],
                    ),
                  )
                else
                  Flexible(
                    child: ListView.builder(
                      shrinkWrap: true,
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      itemCount: items.length,
                      itemBuilder: (context, index) => _DownloadTile(item: items[index]),
                    ),
                  ),
                const Divider(height: 1),
                // Bottom padding
                const SizedBox(height: 4),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _DownloadTile extends StatelessWidget {
  final DownloadItem item;
  const _DownloadTile({required this.item});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isActive = item.status == DownloadStatus.downloading;
    final isPaused = item.status == DownloadStatus.paused;
    final isCompleted = item.status == DownloadStatus.completed;
    final isError = item.status == DownloadStatus.error;
    final isCancelled = item.status == DownloadStatus.cancelled;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Filename + status icon
          Row(
            children: [
              Icon(_statusIcon, size: 16, color: _statusColor(colorScheme)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  item.fileName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                ),
              ),
              if (isCompleted)
                IconButton(
                  icon: Icon(Icons.folder_open_rounded, size: 16),
                  visualDensity: VisualDensity.compact,
                  onPressed: () => Process.run('explorer', [p.dirname(item.savePath)]),
                  tooltip: tr(context, 'dl_open_folder'),
                ),
              if (isActive || isPaused) ...[
                IconButton(
                  icon: Icon(isPaused ? Icons.play_arrow_rounded : Icons.pause_rounded, size: 16),
                  visualDensity: VisualDensity.compact,
                  onPressed: () {
                    if (isPaused) {
                      DownloadManager().resumeDownload(item.id);
                    } else {
                      DownloadManager().pauseDownload(item.id);
                    }
                  },
                  tooltip: isPaused ? tr(context, 'dl_resume') : tr(context, 'dl_pause'),
                ),
                IconButton(
                  icon: Icon(Icons.close_rounded, size: 16),
                  visualDensity: VisualDensity.compact,
                  onPressed: () => DownloadManager().cancelDownload(item.id),
                  tooltip: tr(context, 'dl_cancel'),
                ),
              ],
              if (isError || isCancelled)
                IconButton(
                  icon: Icon(Icons.close_rounded, size: 16),
                  visualDensity: VisualDensity.compact,
                  onPressed: () => DownloadManager().removeItem(item.id),
                ),
            ],
          ),
          const SizedBox(height: 4),
          // Progress bar
          if (isActive || isPaused)
            ClipRRect(
              borderRadius: BorderRadius.circular(2),
              child: LinearProgressIndicator(
                value: item.progress > 0 ? item.progress : null,
                minHeight: 3,
                backgroundColor: colorScheme.surfaceContainerHighest,
              ),
            ),
          const SizedBox(height: 2),
          // Status text
          Row(
            children: [
              Text(
                _statusText(context),
                style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant),
              ),
              if (isActive && item.speed.isNotEmpty) ...[
                const SizedBox(width: 8),
                Text(
                  item.speed,
                  style: TextStyle(fontSize: 11, color: colorScheme.primary, fontWeight: FontWeight.w500),
                ),
              ],
              if (item.totalBytes > 0) ...[
                const Spacer(),
                Text(
                  '${_formatBytes(item.receivedBytes)} / ${_formatBytes(item.totalBytes)}',
                  style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  IconData get _statusIcon {
    switch (item.status) {
      case DownloadStatus.downloading:
        return Icons.downloading_rounded;
      case DownloadStatus.paused:
        return Icons.pause_circle_outline_rounded;
      case DownloadStatus.completed:
        return Icons.check_circle_outline_rounded;
      case DownloadStatus.error:
        return Icons.error_outline_rounded;
      case DownloadStatus.cancelled:
        return Icons.cancel_outlined;
    }
  }

  Color _statusColor(ColorScheme cs) {
    switch (item.status) {
      case DownloadStatus.downloading:
        return cs.primary;
      case DownloadStatus.paused:
        return cs.tertiary;
      case DownloadStatus.completed:
        return Colors.green;
      case DownloadStatus.error:
        return cs.error;
      case DownloadStatus.cancelled:
        return cs.onSurfaceVariant;
    }
  }

  String _statusText(BuildContext context) {
    switch (item.status) {
      case DownloadStatus.downloading:
        return '${(item.progress * 100).toStringAsFixed(0)}%';
      case DownloadStatus.paused:
        return tr(context, 'dl_paused');
      case DownloadStatus.completed:
        return tr(context, 'dl_done');
      case DownloadStatus.error:
        return '${tr(context, 'dl_failed')}: ${item.error ?? ''}';
      case DownloadStatus.cancelled:
        return tr(context, 'dl_cancelled');
    }
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
    if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }
}
