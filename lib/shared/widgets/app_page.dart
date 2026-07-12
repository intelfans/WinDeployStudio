import 'package:flutter/material.dart';

import '../../app/theme.dart';

class AppPageHeader extends StatelessWidget {
  const AppPageHeader({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.details,
    this.actions = const <Widget>[],
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? details;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final tokens = AppVisualTokens.of(context);

    final heading = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          key: ValueKey('app-page-header-${tokens.style.name}'),
          width: 52,
          height: 52,
          decoration: _iconDecoration(tokens, colors),
          child: Icon(icon, size: 28, color: _iconColor(colors)),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: theme.textTheme.headlineMedium,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              if (subtitle != null && subtitle!.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  subtitle!,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ],
              if (details != null) ...[const SizedBox(height: 8), details!],
            ],
          ),
        ),
      ],
    );

    if (actions.isEmpty) return heading;

    final actionBar = Wrap(
      alignment: WrapAlignment.end,
      spacing: 8,
      runSpacing: 8,
      children: actions,
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 560) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              heading,
              const SizedBox(height: 12),
              Align(
                alignment: AlignmentDirectional.centerEnd,
                child: actionBar,
              ),
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: heading),
            const SizedBox(width: 16),
            Flexible(child: actionBar),
          ],
        );
      },
    );
  }

  BoxDecoration _iconDecoration(AppVisualTokens tokens, ColorScheme colors) {
    final isWin7 = tokens.style == VisualStyle.win7;
    return BoxDecoration(
      color: colors.primaryContainer,
      borderRadius: BorderRadius.circular(tokens.controlRadius),
      border: isWin7
          ? Border.all(color: colors.outline, width: tokens.borderWidth)
          : null,
      boxShadow: isWin7 ? tokens.surfaceShadow : null,
    );
  }

  Color _iconColor(ColorScheme colors) {
    return colors.onPrimaryContainer;
  }
}

class AppInfoBox extends StatelessWidget {
  const AppInfoBox({
    super.key,
    required this.icon,
    required this.child,
    this.actions = const <Widget>[],
    this.color,
  });

  final IconData icon;
  final Widget child;
  final List<Widget> actions;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final tokens = AppVisualTokens.of(context);
    final accent = color ?? colors.primary;
    final content = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20, color: accent),
        const SizedBox(width: 12),
        Expanded(child: child),
      ],
    );

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(tokens.surfaceRadius),
        border: Border.all(
          color: accent.withValues(alpha: tokens.highContrast ? 1 : 0.35),
          width: tokens.borderWidth,
        ),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (actions.isEmpty) return content;
          final actionBar = Wrap(
            alignment: WrapAlignment.end,
            spacing: 8,
            runSpacing: 8,
            children: actions,
          );
          if (constraints.maxWidth < 560) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [content, const SizedBox(height: 12), actionBar],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(child: content),
              const SizedBox(width: 16),
              Flexible(child: actionBar),
            ],
          );
        },
      ),
    );
  }
}

class AdaptiveTwoPane extends StatelessWidget {
  const AdaptiveTwoPane({
    super.key,
    required this.primary,
    required this.secondary,
    this.breakpoint = 760,
    this.spacing = 20,
    this.primaryFlex = 2,
    this.secondaryFlex = 1,
  });

  final Widget primary;
  final Widget secondary;
  final double breakpoint;
  final double spacing;
  final int primaryFlex;
  final int secondaryFlex;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < breakpoint) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              primary,
              SizedBox(height: spacing),
              secondary,
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(flex: primaryFlex, child: primary),
            SizedBox(width: spacing),
            Expanded(flex: secondaryFlex, child: secondary),
          ],
        );
      },
    );
  }
}

class AppDialogActionBar extends StatelessWidget {
  const AppDialogActionBar({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      alignment: WrapAlignment.end,
      spacing: 8,
      runSpacing: 8,
      children: children,
    );
  }
}
