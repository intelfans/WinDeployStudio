import 'package:flutter/material.dart';
import '../../../app/typography.dart';

class LogStatWidget extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;
  final Color color;

  const LogStatWidget({
    super.key,
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      children: [
        Icon(icon, size: 28, color: color),
        const SizedBox(height: 8),
        Text(
          value,
          style: AppTypography.sectionTitleWith(theme.colorScheme.onSurface),
        ),
        const SizedBox(height: 4),
        Text(
          title,
          style: AppTypography.captionWith(theme.colorScheme.onSurfaceVariant),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}
