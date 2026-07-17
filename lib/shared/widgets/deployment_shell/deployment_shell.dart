import 'package:flutter/material.dart';

import '../../../app/theme.dart';

class DeploymentShellDestination {
  const DeploymentShellDestination({
    required this.label,
    required this.icon,
    this.selectedIcon,
    this.badge,
    this.enabled = true,
  });

  final String label;
  final IconData icon;
  final IconData? selectedIcon;
  final Widget? badge;
  final bool enabled;
}

class DeploymentShell extends StatelessWidget {
  const DeploymentShell({
    required this.title,
    required this.destinations,
    required this.selectedIndex,
    required this.onDestinationSelected,
    required this.body,
    super.key,
    this.subtitle,
    this.leading,
    this.actions = const <Widget>[],
    this.footer,
    this.maxContentWidth = 1180,
    this.compactBreakpoint = 760,
  });

  final Widget title;
  final Widget? subtitle;
  final Widget? leading;
  final List<Widget> actions;
  final List<DeploymentShellDestination> destinations;
  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;
  final Widget body;
  final Widget? footer;
  final double maxContentWidth;
  final double compactBreakpoint;

  @override
  Widget build(BuildContext context) {
    assert(destinations.isEmpty || selectedIndex < destinations.length);
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < compactBreakpoint;
        final content = _ShellContent(
          title: title,
          subtitle: subtitle,
          leading: leading,
          actions: actions,
          body: body,
          footer: footer,
          maxContentWidth: maxContentWidth,
          compact: compact,
        );

        if (compact) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (destinations.isNotEmpty)
                _DestinationStrip(
                  destinations: destinations,
                  selectedIndex: selectedIndex,
                  onSelected: onDestinationSelected,
                ),
              Expanded(child: content),
            ],
          );
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (destinations.isNotEmpty)
              _DestinationPane(
                destinations: destinations,
                selectedIndex: selectedIndex,
                onSelected: onDestinationSelected,
                expanded: true,
              ),
            Expanded(child: content),
          ],
        );
      },
    );
  }
}

class _ShellContent extends StatelessWidget {
  const _ShellContent({
    required this.title,
    required this.subtitle,
    required this.leading,
    required this.actions,
    required this.body,
    required this.footer,
    required this.maxContentWidth,
    required this.compact,
  });

  final Widget title;
  final Widget? subtitle;
  final Widget? leading;
  final List<Widget> actions;
  final Widget body;
  final Widget? footer;
  final double maxContentWidth;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final tokens = AppVisualTokens.of(context);
    final horizontalPadding = compact ? 16.0 : tokens.pagePadding;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: EdgeInsetsDirectional.fromSTEB(
            horizontalPadding,
            tokens.pagePadding,
            horizontalPadding,
            16,
          ),
          child: Align(
            alignment: AlignmentDirectional.center,
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: maxContentWidth),
              child: _PageHeader(
                title: title,
                subtitle: subtitle,
                leading: leading,
                actions: actions,
              ),
            ),
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: EdgeInsetsDirectional.fromSTEB(
              horizontalPadding,
              0,
              horizontalPadding,
              tokens.pagePadding,
            ),
            child: Align(
              alignment: AlignmentDirectional.topCenter,
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: maxContentWidth),
                child: body,
              ),
            ),
          ),
        ),
        if (footer != null)
          _ShellFooter(
            maxContentWidth: maxContentWidth,
            horizontalPadding: horizontalPadding,
            child: footer!,
          ),
      ],
    );
  }
}

class _PageHeader extends StatelessWidget {
  const _PageHeader({
    required this.title,
    required this.subtitle,
    required this.leading,
    required this.actions,
  });

  final Widget title;
  final Widget? subtitle;
  final Widget? leading;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final titleBlock = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (leading != null) ...[
          Padding(
            padding: const EdgeInsetsDirectional.only(end: 12),
            child: leading,
          ),
        ],
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              DefaultTextStyle(style: textTheme.headlineMedium!, child: title),
              if (subtitle != null) ...[
                const SizedBox(height: 4),
                DefaultTextStyle(
                  style: textTheme.bodyMedium!.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                  child: subtitle!,
                ),
              ],
            ],
          ),
        ),
      ],
    );
    if (actions.isEmpty) return titleBlock;

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 640) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              titleBlock,
              const SizedBox(height: 12),
              Align(
                alignment: AlignmentDirectional.centerEnd,
                child: Wrap(spacing: 8, runSpacing: 8, children: actions),
              ),
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: titleBlock),
            const SizedBox(width: 16),
            Flexible(child: Wrap(spacing: 8, runSpacing: 8, children: actions)),
          ],
        );
      },
    );
  }
}

class _ShellFooter extends StatelessWidget {
  const _ShellFooter({
    required this.maxContentWidth,
    required this.horizontalPadding,
    required this.child,
  });

  final double maxContentWidth;
  final double horizontalPadding;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final tokens = AppVisualTokens.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surface,
        border: BorderDirectional(
          top: BorderSide(
            color: colors.outlineVariant,
            width: tokens.borderWidth,
          ),
        ),
      ),
      child: Padding(
        padding: EdgeInsetsDirectional.fromSTEB(
          horizontalPadding,
          12,
          horizontalPadding,
          12,
        ),
        child: Align(
          alignment: AlignmentDirectional.center,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxContentWidth),
            child: child,
          ),
        ),
      ),
    );
  }
}

class _DestinationPane extends StatelessWidget {
  const _DestinationPane({
    required this.destinations,
    required this.selectedIndex,
    required this.onSelected,
    required this.expanded,
  });

  final List<DeploymentShellDestination> destinations;
  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final bool expanded;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final tokens = AppVisualTokens.of(context);
    final width = expanded ? 224.0 : 72.0;
    return SizedBox(
      width: width,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.surfaceContainerLow,
          border: BorderDirectional(
            end: BorderSide(
              color: colors.outlineVariant,
              width: tokens.borderWidth,
            ),
          ),
        ),
        child: ListView.separated(
          padding: EdgeInsets.all(expanded ? 12 : 8),
          itemCount: destinations.length,
          separatorBuilder: (_, _) => SizedBox(height: tokens.itemSpacing / 2),
          itemBuilder: (context, index) {
            final destination = destinations[index];
            return _DestinationButton(
              destination: destination,
              selected: selectedIndex == index,
              expanded: expanded,
              onPressed: destination.enabled ? () => onSelected(index) : null,
            );
          },
        ),
      ),
    );
  }
}

class _DestinationButton extends StatelessWidget {
  const _DestinationButton({
    required this.destination,
    required this.selected,
    required this.expanded,
    required this.onPressed,
  });

  final DeploymentShellDestination destination;
  final bool selected;
  final bool expanded;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final tokens = AppVisualTokens.of(context);
    final icon = Icon(
      selected
          ? destination.selectedIcon ?? destination.icon
          : destination.icon,
      size: 20,
    );
    final child = Row(
      mainAxisAlignment: expanded
          ? MainAxisAlignment.start
          : MainAxisAlignment.center,
      children: [
        icon,
        if (expanded) ...[
          const SizedBox(width: 12),
          Expanded(
            child: Text(destination.label, overflow: TextOverflow.ellipsis),
          ),
          if (destination.badge != null) destination.badge!,
        ],
      ],
    );

    return Tooltip(
      message: expanded ? '' : destination.label,
      child: Semantics(
        selected: selected,
        button: true,
        child: Material(
          color: selected ? colors.secondaryContainer : Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(tokens.controlRadius),
            side: selected && tokens.highContrast
                ? BorderSide(color: colors.outline, width: tokens.borderWidth)
                : BorderSide.none,
          ),
          child: InkWell(
            onTap: onPressed,
            borderRadius: BorderRadius.circular(tokens.controlRadius),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: tokens.controlHeight),
              child: Padding(
                padding: EdgeInsetsDirectional.symmetric(
                  horizontal: expanded ? 12 : 8,
                ),
                child: IconTheme.merge(
                  data: IconThemeData(
                    color: selected
                        ? colors.onSecondaryContainer
                        : colors.onSurfaceVariant,
                  ),
                  child: DefaultTextStyle(
                    style: Theme.of(context).textTheme.bodyMedium!.copyWith(
                      color: selected
                          ? colors.onSecondaryContainer
                          : colors.onSurface,
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                    ),
                    child: child,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DestinationStrip extends StatelessWidget {
  const _DestinationStrip({
    required this.destinations,
    required this.selectedIndex,
    required this.onSelected,
  });

  final List<DeploymentShellDestination> destinations;
  final int selectedIndex;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final tokens = AppVisualTokens.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        border: BorderDirectional(
          bottom: BorderSide(
            color: colors.outlineVariant,
            width: tokens.borderWidth,
          ),
        ),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.all(8),
        child: Row(
          children: List.generate(destinations.length, (index) {
            final destination = destinations[index];
            return Padding(
              padding: const EdgeInsetsDirectional.only(end: 4),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minWidth: 96, maxWidth: 240),
                child: _DestinationButton(
                  destination: destination,
                  selected: selectedIndex == index,
                  expanded: true,
                  onPressed: destination.enabled
                      ? () => onSelected(index)
                      : null,
                ),
              ),
            );
          }),
        ),
      ),
    );
  }
}

class DeploymentSection extends StatelessWidget {
  const DeploymentSection({
    required this.title,
    required this.child,
    super.key,
    this.description,
    this.leading,
    this.trailing,
    this.enabled = true,
    this.framed = true,
  });

  final Widget title;
  final Widget? description;
  final Widget? leading;
  final Widget? trailing;
  final Widget child;
  final bool enabled;
  final bool framed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final tokens = AppVisualTokens.of(context);
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (leading != null) ...[
              Padding(
                padding: const EdgeInsetsDirectional.only(end: 12),
                child: leading,
              ),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  DefaultTextStyle(
                    style: theme.textTheme.titleLarge!,
                    child: title,
                  ),
                  if (description != null) ...[
                    const SizedBox(height: 4),
                    DefaultTextStyle(
                      style: theme.textTheme.bodyMedium!.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                      child: description!,
                    ),
                  ],
                ],
              ),
            ),
            if (trailing != null) ...[const SizedBox(width: 12), trailing!],
          ],
        ),
        SizedBox(height: tokens.sectionSpacing),
        child,
      ],
    );

    final decorated = !framed
        ? content
        : DecoratedBox(
            decoration: BoxDecoration(
              color: colors.surface,
              borderRadius: BorderRadius.circular(tokens.surfaceRadius),
              border: Border.all(
                color: colors.outlineVariant,
                width: tokens.borderWidth,
              ),
              boxShadow: tokens.surfaceShadow,
            ),
            child: Padding(padding: const EdgeInsets.all(20), child: content),
          );

    return IgnorePointer(
      ignoring: !enabled,
      child: AnimatedOpacity(
        opacity: enabled ? 1 : 0.55,
        duration: tokens.motionDuration,
        child: decorated,
      ),
    );
  }
}

class DeploymentSubsection extends StatelessWidget {
  const DeploymentSubsection({
    required this.title,
    required this.child,
    super.key,
    this.description,
    this.trailing,
  });

  final Widget title;
  final Widget? description;
  final Widget? trailing;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final tokens = AppVisualTokens.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(tokens.controlRadius),
        border: Border.all(
          color: colors.outlineVariant,
          width: tokens.borderWidth,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      DefaultTextStyle(
                        style: theme.textTheme.titleMedium!,
                        child: title,
                      ),
                      if (description != null) ...[
                        const SizedBox(height: 2),
                        DefaultTextStyle(
                          style: theme.textTheme.bodySmall!.copyWith(
                            color: colors.onSurfaceVariant,
                          ),
                          child: description!,
                        ),
                      ],
                    ],
                  ),
                ),
                if (trailing != null) ...[const SizedBox(width: 12), trailing!],
              ],
            ),
            SizedBox(height: tokens.itemSpacing),
            child,
          ],
        ),
      ),
    );
  }
}
