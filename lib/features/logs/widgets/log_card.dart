import 'package:flutter/material.dart';
import '../../../app/typography.dart';
import '../../../core/localization/strings.dart';
import '../models/log_category.dart';

class LogCategoryCard extends StatelessWidget {
  final LogCategory category;
  final String categoryDisplayName;
  final int fileCount;
  final DateTime? lastUpdate;
  final VoidCallback onTap;

  const LogCategoryCard({
    super.key,
    required this.category,
    required this.categoryDisplayName,
    required this.fileCount,
    this.lastUpdate,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isError = category == LogCategory.errors;
    final hasFiles = fileCount > 0;
    final filesText = tr(context, 'logs_files').replaceAll('{count}', '$fileCount');
    final noErrorsText = tr(context, 'logs_no_errors');
    final lastUpdateLabel = tr(context, 'logs_last_update');

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: category.color.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(category.icon, size: 22, color: category.color),
                  ),
                  const Spacer(),
                  if (isError && hasFiles)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.red,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '$fileCount',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                categoryDisplayName,
                style: AppTypography.cardTitleWith(theme.colorScheme.onSurface),
              ),
              const SizedBox(height: 4),
              Text(
                isError
                    ? (hasFiles ? '⚠ $filesText' : '✓ $noErrorsText')
                    : filesText,
                style: AppTypography.captionWith(
                  isError
                      ? (hasFiles ? Colors.red : Colors.green)
                      : theme.colorScheme.onSurfaceVariant,
                ),
              ),
              if (lastUpdate != null) ...[
                const SizedBox(height: 8),
                Text(
                  lastUpdateLabel,
                  style: AppTypography.captionWith(theme.colorScheme.onSurfaceVariant),
                ),
                Text(
                  _formatDateTime(lastUpdate!),
                  style: AppTypography.captionWith(theme.colorScheme.onSurfaceVariant),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  String _formatDateTime(DateTime dt) {
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} '
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }
}
