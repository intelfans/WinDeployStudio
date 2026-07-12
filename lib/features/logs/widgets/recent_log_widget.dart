import 'package:flutter/material.dart';
import '../../../app/typography.dart';
import '../models/log_category.dart';

class RecentLogWidget extends StatelessWidget {
  final LogActivity activity;
  final String categoryDisplayName;

  const RecentLogWidget({
    super.key,
    required this.activity,
    required this.categoryDisplayName,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: activity.category.color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              activity.category.icon,
              size: 18,
              color: activity.category.color,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  categoryDisplayName,
                  style: AppTypography.captionWith(
                    activity.category.color,
                  ).copyWith(fontWeight: FontWeight.w600),
                ),
                Text(
                  activity.title,
                  style: AppTypography.bodyWith(theme.colorScheme.onSurface),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            activity.timeFormatted,
            style: AppTypography.captionWith(
              theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
