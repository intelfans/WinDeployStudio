import 'package:flutter/material.dart';

import '../../app/theme.dart';

class AppNavigationDestination {
  const AppNavigationDestination({
    required this.icon,
    required this.selectedIcon,
    required this.label,
    this.startsSection = false,
  });

  final IconData icon;
  final IconData selectedIcon;
  final String label;
  final bool startsSection;
}

class AppNavigationShell extends StatelessWidget {
  const AppNavigationShell({
    super.key,
    required this.selectedIndex,
    required this.destinations,
    required this.onDestinationSelected,
    required this.child,
  });

  final int selectedIndex;
  final List<AppNavigationDestination> destinations;
  final ValueChanged<int> onDestinationSelected;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final tokens = AppVisualTokens.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 900;
        final width = compact
            ? 68.0
            : switch (tokens.style) {
                VisualStyle.win11 => 216.0,
                VisualStyle.win10 => 204.0,
                VisualStyle.win7 => 208.0,
                VisualStyle.auto => 216.0,
              };
        return Row(
          children: [
            SizedBox(
              key: ValueKey(
                'app-navigation-${tokens.style.name}-${compact ? 'compact' : 'expanded'}',
              ),
              width: width,
              child: _NavigationPane(
                compact: compact,
                selectedIndex: selectedIndex,
                destinations: destinations,
                onDestinationSelected: onDestinationSelected,
              ),
            ),
            Expanded(child: child),
          ],
        );
      },
    );
  }
}

class _NavigationPane extends StatelessWidget {
  const _NavigationPane({
    required this.compact,
    required this.selectedIndex,
    required this.destinations,
    required this.onDestinationSelected,
  });

  final bool compact;
  final int selectedIndex;
  final List<AppNavigationDestination> destinations;
  final ValueChanged<int> onDestinationSelected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final tokens = AppVisualTokens.of(context);
    final background = switch (tokens.style) {
      VisualStyle.win11 => colors.surfaceContainerLow,
      VisualStyle.win10 => colors.surface,
      VisualStyle.win7 => colors.surfaceContainerLow,
      VisualStyle.auto => colors.surfaceContainerLow,
    };

    return Material(
      color: background,
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: BorderDirectional(
            end: BorderSide(
              color: colors.outlineVariant,
              width: tokens.borderWidth,
            ),
          ),
        ),
        child: Column(
          children: [
            SizedBox(
              height: 72,
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: compact ? 10 : 14),
                child: Row(
                  mainAxisAlignment: compact
                      ? MainAxisAlignment.center
                      : MainAxisAlignment.start,
                  children: [
                    _BrandMark(style: tokens.style),
                    if (!compact) ...[
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'WinDeploy Studio',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleSmall,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            Divider(height: tokens.borderWidth),
            Expanded(
              child: Scrollbar(
                child: ListView.builder(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 8,
                  ),
                  itemCount: destinations.length,
                  itemBuilder: (context, index) {
                    final destination = destinations[index];
                    final tile = _NavigationTile(
                      compact: compact,
                      selected: index == selectedIndex,
                      destination: destination,
                      onTap: () => onDestinationSelected(index),
                    );
                    final destinationTile = compact
                        ? Tooltip(message: destination.label, child: tile)
                        : tile;
                    return Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (destination.startsSection) ...[
                          Padding(
                            key: ValueKey(
                              'app-navigation-group-divider-$index',
                            ),
                            padding: const EdgeInsetsDirectional.only(
                              start: 12,
                              end: 12,
                              top: 12,
                              bottom: 8,
                            ),
                            child: Divider(
                              height: tokens.borderWidth,
                              thickness: tokens.borderWidth,
                              color: colors.outlineVariant.withValues(
                                alpha: tokens.highContrast ? 1 : 0.72,
                              ),
                            ),
                          ),
                        ] else
                          const SizedBox(height: 4),
                        destinationTile,
                      ],
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BrandMark extends StatelessWidget {
  const _BrandMark({required this.style});

  final VisualStyle style;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final tokens = AppVisualTokens.of(context);
    final icon = switch (style) {
      VisualStyle.win11 => Icons.window_rounded,
      VisualStyle.win10 => Icons.grid_view_rounded,
      VisualStyle.win7 => Icons.desktop_windows_outlined,
      VisualStyle.auto => Icons.window_rounded,
    };
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: style == VisualStyle.win10
            ? colors.primary
            : colors.primaryContainer,
        borderRadius: BorderRadius.circular(tokens.controlRadius),
        border: style == VisualStyle.win7
            ? Border.all(color: colors.outline)
            : null,
        boxShadow: style == VisualStyle.win7 ? tokens.surfaceShadow : null,
      ),
      child: Icon(
        icon,
        size: 22,
        color: style == VisualStyle.win10
            ? colors.onPrimary
            : colors.onPrimaryContainer,
      ),
    );
  }
}

class _NavigationTile extends StatelessWidget {
  const _NavigationTile({
    required this.compact,
    required this.selected,
    required this.destination,
    required this.onTap,
  });

  final bool compact;
  final bool selected;
  final AppNavigationDestination destination;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final tokens = AppVisualTokens.of(context);
    final foreground = selected
        ? switch (tokens.style) {
            VisualStyle.win10 => colors.primary,
            _ => colors.onSecondaryContainer,
          }
        : colors.onSurfaceVariant;
    final decoration = switch (tokens.style) {
      VisualStyle.win11 => BoxDecoration(
        color: selected ? colors.secondaryContainer : Colors.transparent,
        borderRadius: BorderRadius.circular(tokens.controlRadius),
      ),
      VisualStyle.win10 => BoxDecoration(
        color: selected
            ? colors.primary.withValues(alpha: 0.10)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(tokens.controlRadius),
        border: selected
            ? BorderDirectional(
                start: BorderSide(color: colors.primary, width: 3),
              )
            : null,
      ),
      VisualStyle.win7 => BoxDecoration(
        color: selected ? colors.secondaryContainer : Colors.transparent,
        borderRadius: BorderRadius.circular(tokens.controlRadius),
        border: selected ? Border.all(color: colors.outline) : null,
        boxShadow: selected ? tokens.surfaceShadow : null,
      ),
      VisualStyle.auto => const BoxDecoration(),
    };

    return Semantics(
      selected: selected,
      button: true,
      label: destination.label,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(tokens.controlRadius),
          child: AnimatedContainer(
            duration: tokens.motionDuration,
            height: 46,
            padding: EdgeInsets.symmetric(horizontal: compact ? 0 : 12),
            decoration: decoration,
            child: Row(
              mainAxisAlignment: compact
                  ? MainAxisAlignment.center
                  : MainAxisAlignment.start,
              children: [
                Icon(
                  selected ? destination.selectedIcon : destination.icon,
                  size: 21,
                  color: foreground,
                ),
                if (!compact) ...[
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      destination.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: foreground,
                        fontWeight: selected
                            ? FontWeight.w600
                            : FontWeight.w400,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
