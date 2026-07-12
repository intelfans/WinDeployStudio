import 'package:flutter/material.dart';

import '../../../app/theme.dart';

enum DiskSelectionStatus { normal, checking, safe, warning, blocked }

class DiskSelectionRow extends StatelessWidget {
  const DiskSelectionRow({
    required this.title,
    required this.selected,
    super.key,
    this.subtitle,
    this.details = const <Widget>[],
    this.leading,
    this.trailing,
    this.status = DiskSelectionStatus.normal,
    this.statusLabel,
    this.enabled = true,
    this.onPressed,
  });

  final Widget title;
  final Widget? subtitle;
  final List<Widget> details;
  final Widget? leading;
  final Widget? trailing;
  final bool selected;
  final DiskSelectionStatus status;
  final Widget? statusLabel;
  final bool enabled;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final tokens = AppVisualTokens.of(context);
    final statusColor = _statusColor(colors, highContrast: tokens.highContrast);
    final effectiveSelectedColor = status == DiskSelectionStatus.blocked
        ? colors.errorContainer
        : colors.secondaryContainer;
    final borderColor = selected
        ? statusColor
        : tokens.highContrast
        ? colors.outline
        : colors.outlineVariant;
    final row = Semantics(
      button: onPressed != null,
      enabled: enabled,
      selected: selected,
      child: Material(
        color: selected ? effectiveSelectedColor : colors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(tokens.controlRadius),
          side: BorderSide(color: borderColor, width: tokens.borderWidth),
        ),
        child: InkWell(
          onTap: enabled ? onPressed : null,
          borderRadius: BorderRadius.circular(tokens.controlRadius),
          child: Padding(
            padding: EdgeInsetsDirectional.fromSTEB(14, 10, 14, 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                _DiskLeading(
                  customLeading: leading,
                  selected: selected,
                  status: status,
                  color: statusColor,
                ),
                SizedBox(width: tokens.itemSpacing),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      DefaultTextStyle(
                        style: theme.textTheme.titleSmall!.copyWith(
                          color: colors.onSurface,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        child: title,
                      ),
                      if (subtitle != null) ...[
                        const SizedBox(height: 2),
                        DefaultTextStyle(
                          style: theme.textTheme.bodySmall!.copyWith(
                            color: colors.onSurfaceVariant,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          child: subtitle!,
                        ),
                      ],
                      if (details.isNotEmpty) ...[
                        SizedBox(height: tokens.itemSpacing / 2),
                        Wrap(
                          spacing: 6,
                          runSpacing: 4,
                          children: details
                              .map(
                                (detail) => _DiskDetail(
                                  color: colors.surfaceContainerHigh,
                                  child: detail,
                                ),
                              )
                              .toList(growable: false),
                        ),
                      ],
                      if (statusLabel != null) ...[
                        const SizedBox(height: 4),
                        DefaultTextStyle(
                          style: theme.textTheme.bodySmall!.copyWith(
                            color: statusColor,
                            fontWeight: FontWeight.w600,
                          ),
                          child: statusLabel!,
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                trailing ?? _SelectionIndicator(selected: selected),
              ],
            ),
          ),
        ),
      ),
    );

    return AnimatedOpacity(
      opacity: enabled ? 1 : 0.55,
      duration: tokens.motionDuration,
      child: DecoratedBox(
        decoration: BoxDecoration(boxShadow: tokens.surfaceShadow),
        child: row,
      ),
    );
  }

  Color _statusColor(ColorScheme colors, {required bool highContrast}) {
    if (highContrast) {
      return switch (status) {
        DiskSelectionStatus.normal ||
        DiskSelectionStatus.safe => colors.primary,
        DiskSelectionStatus.checking ||
        DiskSelectionStatus.warning => colors.tertiary,
        DiskSelectionStatus.blocked => colors.error,
      };
    }
    final dark = colors.brightness == Brightness.dark;
    return switch (status) {
      DiskSelectionStatus.normal => colors.primary,
      DiskSelectionStatus.checking => colors.tertiary,
      DiskSelectionStatus.safe =>
        dark ? const Color(0xFF6CCB5F) : const Color(0xFF0F6B0F),
      DiskSelectionStatus.warning =>
        dark ? const Color(0xFFFFC83D) : const Color(0xFF8A4F00),
      DiskSelectionStatus.blocked => colors.error,
    };
  }
}

class _DiskLeading extends StatelessWidget {
  const _DiskLeading({
    required this.customLeading,
    required this.selected,
    required this.status,
    required this.color,
  });

  final Widget? customLeading;
  final bool selected;
  final DiskSelectionStatus status;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final tokens = AppVisualTokens.of(context);
    if (customLeading != null) return customLeading!;
    final icon = switch (status) {
      DiskSelectionStatus.checking => null,
      DiskSelectionStatus.warning => Icons.warning_amber_rounded,
      DiskSelectionStatus.blocked => Icons.block_rounded,
      DiskSelectionStatus.safe => Icons.storage_rounded,
      DiskSelectionStatus.normal => Icons.storage_rounded,
    };
    return SizedBox.square(
      dimension: tokens.controlHeight,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: color.withValues(alpha: selected ? 0.2 : 0.1),
          borderRadius: BorderRadius.circular(tokens.compactRadius),
          border: Border.all(color: color.withValues(alpha: 0.7)),
        ),
        child: Center(
          child: icon == null
              ? SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: color,
                  ),
                )
              : Icon(icon, size: 21, color: color),
        ),
      ),
    );
  }
}

class _SelectionIndicator extends StatelessWidget {
  const _SelectionIndicator({required this.selected});

  final bool selected;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return AnimatedSwitcher(
      duration: AppVisualTokens.of(context).motionDuration,
      child: selected
          ? Icon(
              Icons.check_circle_rounded,
              key: const ValueKey(true),
              color: colors.primary,
            )
          : Icon(
              Icons.radio_button_unchecked_rounded,
              key: const ValueKey(false),
              color: colors.outline,
            ),
    );
  }
}

class _DiskDetail extends StatelessWidget {
  const _DiskDetail({required this.color, required this.child});

  final Color color;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final tokens = AppVisualTokens.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(tokens.compactRadius),
      ),
      child: Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(6, 2, 6, 2),
        child: DefaultTextStyle(
          style: Theme.of(context).textTheme.labelSmall!,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          child: child,
        ),
      ),
    );
  }
}
