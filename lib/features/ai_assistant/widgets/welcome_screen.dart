import 'package:flutter/material.dart';
import '../../../app/typography.dart';
import '../../../core/localization/strings.dart';
import '../../../shared/widgets/app_compact_label.dart';

class WelcomeScreen extends StatelessWidget {
  final void Function(String) onSendPrompt;
  final VoidCallback onAnalyzeUsbQuestion;

  const WelcomeScreen({
    super.key,
    required this.onSendPrompt,
    required this.onAnalyzeUsbQuestion,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final screenWidth = MediaQuery.of(context).size.width;
    final isNarrow = screenWidth < 600;

    return Center(
      child: SingleChildScrollView(
        padding: EdgeInsets.symmetric(
          horizontal: isNarrow ? 24 : 64,
          vertical: 32,
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 700),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Icon(
                  Icons.auto_awesome_rounded,
                  size: 36,
                  color: colorScheme.onPrimaryContainer,
                ),
              ),
              const SizedBox(height: 24),
              Text(
                tr(context, 'ai_welcome_title'),
                style: AppTypography.sectionTitleWith(colorScheme.onSurface),
              ),
              const SizedBox(height: 12),
              Text(
                tr(context, 'ai_welcome_desc'),
                textAlign: TextAlign.center,
                style: AppTypography.bodyWith(colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: 32),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                alignment: WrapAlignment.center,
                children: [
                  _AbilityChip(label: tr(context, 'ai_ability_windows')),
                  _AbilityChip(label: tr(context, 'ai_ability_wtg')),
                  _AbilityChip(label: tr(context, 'ai_ability_usb')),
                  _AbilityChip(label: tr(context, 'ai_ability_iso')),
                  _AbilityChip(label: tr(context, 'ai_ability_dism')),
                  _AbilityChip(label: tr(context, 'ai_ability_bcdboot')),
                  _AbilityChip(label: tr(context, 'ai_ability_powershell')),
                  _AbilityChip(label: tr(context, 'ai_ability_logs')),
                ],
              ),
              const SizedBox(height: 32),
              Text(
                tr(context, 'ai_example_questions'),
                style: AppTypography.captionWith(colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: 12),
              _ExampleQuestion(
                question: tr(context, 'ai_example_q1'),
                onTap: () => onSendPrompt(tr(context, 'ai_example_q1')),
              ),
              const SizedBox(height: 8),
              _ExampleQuestion(
                question: tr(context, 'ai_example_q2'),
                onTap: () => onSendPrompt(tr(context, 'ai_example_q2')),
              ),
              const SizedBox(height: 8),
              _ExampleQuestion(
                question: tr(context, 'ai_example_q3'),
                onTap: onAnalyzeUsbQuestion,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AbilityChip extends StatelessWidget {
  final String label;
  const _AbilityChip({required this.label});

  @override
  Widget build(BuildContext context) {
    return Chip(
      label: AppCompactLabel(label, style: const TextStyle(fontSize: 12)),
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
  }
}

class _ExampleQuestion extends StatelessWidget {
  final String question;
  final VoidCallback onTap;
  const _ExampleQuestion({required this.question, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Material(
      color: colorScheme.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  question,
                  style: AppTypography.bodyWith(colorScheme.onSurface),
                ),
              ),
              Icon(
                Icons.arrow_forward_rounded,
                size: 16,
                color: colorScheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
