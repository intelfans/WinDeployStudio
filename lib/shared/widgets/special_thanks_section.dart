import 'package:flutter/material.dart';
import '../../app/typography.dart';
import '../../core/localization/strings.dart';

class SpecialThanksSection extends StatelessWidget {
  const SpecialThanksSection({super.key, this.compact = false});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final entries = [
      _ThanksEntry(
        name: 'Star__P',
        description: tr(context, 'thanks_astra_desc'),
      ),
      _ThanksEntry(
        name: 'Timme',
        description: tr(context, 'thanks_timme_desc'),
      ),
      _ThanksEntry(
        name: 'Microsoft Sysinternals Team',
        description: tr(context, 'thanks_sysinternals_desc'),
      ),
      _ThanksEntry(
        name: 'Open Source Community',
        description: tr(context, 'thanks_open_source_desc'),
      ),
    ];

    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(compact ? 14 : 16),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            tr(context, 'special_thanks_title'),
            style: AppTypography.cardTitleWith(colorScheme.onSurface),
          ),
          const SizedBox(height: 8),
          Text(
            tr(context, 'special_thanks_intro'),
            style: AppTypography.bodyWith(colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 12),
          ...entries.map(
            (entry) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _ThanksRow(entry: entry),
            ),
          ),
        ],
      ),
    );
  }
}

class _ThanksEntry {
  final String name;
  final String description;

  const _ThanksEntry({required this.name, required this.description});
}

class _ThanksRow extends StatelessWidget {
  const _ThanksRow({required this.entry});

  final _ThanksEntry entry;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.check_circle_outline, size: 18, color: colorScheme.primary),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                entry.name,
                style: AppTypography.body.copyWith(
                  color: colorScheme.onSurface,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                entry.description,
                style: AppTypography.captionWith(colorScheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
