import 'dart:math';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../app/theme.dart';
import '../../../app/typography.dart';
import '../../../core/localization/strings.dart';
import '../../../shared/webview/webview_helper.dart';
import '../../../shared/widgets/app_compact_label.dart';
import '../../../shared/widgets/app_page.dart';
import '../models/tool_models.dart';

class ToolsScreen extends StatefulWidget {
  const ToolsScreen({super.key, this.dataLoader});

  final Future<ToolsData> Function()? dataLoader;

  @override
  State<ToolsScreen> createState() => _ToolsScreenState();
}

class _ToolsScreenState extends State<ToolsScreen> {
  static const double _featuredCardHeight = 136;
  static const double _featuredCardSpacing = 12;
  static const int _featuredDesktopColumns = 3;
  static const int _featuredDesktopItemCount = 6;
  static const double _featuredThreeColumnBreakpoint = 720;
  static const double _featuredTwoColumnBreakpoint = 440;
  static const double _toolCardHeight = 320;

  ToolsData? _data;
  bool _loading = true;
  String _searchQuery = '';
  List<ToolItem> _featuredTools = [];
  String _lastLocale = '';

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  void _shuffleFeatured() {
    final all = _data?.featuredTools ?? [];
    final list = List<ToolItem>.from(all);
    list.shuffle(Random());
    _featuredTools = list.take(_featuredItemCount(all.length)).toList();
  }

  int _featuredItemCount(int availableCount) {
    if (availableCount >= _featuredDesktopItemCount) {
      return _featuredDesktopItemCount;
    }
    // Keep desktop grids balanced when the source has fewer than six items.
    if (availableCount >= _featuredDesktopColumns) {
      return _featuredDesktopColumns;
    }
    return availableCount;
  }

  Future<void> _loadData() async {
    _lastLocale = normalizeLocaleCode(L.currentLocale);
    final data = await (widget.dataLoader?.call() ?? ToolsData.load());
    if (mounted) {
      setState(() {
        _data = data;
        _loading = false;
        _shuffleFeatured();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final locale = Localizations.localeOf(context);
    final currentLocale = normalizeLocaleCode(localeCodeFromLocale(locale));
    if (currentLocale != _lastLocale && !_loading) {
      _loadData();
    }
    final colorScheme = Theme.of(context).colorScheme;
    final tokens = AppVisualTokens.of(context);

    return Scaffold(
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : LayoutBuilder(
              builder: (context, constraints) => SingleChildScrollView(
                padding: EdgeInsets.all(
                  constraints.maxWidth < 600 ? 16 : tokens.pagePadding,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildHeader(context, colorScheme),
                    SizedBox(height: tokens.sectionSpacing),
                    _buildStatsBar(context, colorScheme),
                    SizedBox(height: tokens.sectionSpacing),
                    _buildSearchBar(context, colorScheme),
                    SizedBox(height: tokens.sectionSpacing),
                    if (_searchQuery.isEmpty) ...[
                      _buildFeaturedSection(context, colorScheme),
                      SizedBox(height: tokens.sectionSpacing * 1.5),
                    ],
                    ..._buildCategorySections(context, colorScheme),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildHeader(BuildContext context, ColorScheme colorScheme) {
    return AppPageHeader(
      icon: Icons.handyman_rounded,
      title: tr(context, 'tools_title'),
      subtitle: tr(context, 'tools_subtitle'),
    );
  }

  Widget _buildStatsBar(BuildContext context, ColorScheme colorScheme) {
    if (_data == null) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(
          AppVisualTokens.of(context).surfaceRadius,
        ),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final items = [
            _StatItem(
              icon: Icons.apps_rounded,
              label: tr(context, 'tools_stat_total'),
              value: '${_data!.totalTools}',
            ),
            _StatItem(
              icon: Icons.folder_rounded,
              label: tr(context, 'tools_stat_categories'),
              value: '${_data!.totalCategories}',
            ),
            _StatItem(
              icon: Icons.update_rounded,
              label: tr(context, 'tools_stat_updated'),
              value: DateTime.now().toString().split(' ')[0],
            ),
          ];
          if (constraints.maxWidth < 520) {
            return Column(
              children: [
                for (var index = 0; index < items.length; index++) ...[
                  items[index],
                  if (index < items.length - 1) const Divider(height: 20),
                ],
              ],
            );
          }
          return Row(
            children: [
              for (var index = 0; index < items.length; index++) ...[
                Expanded(child: items[index]),
                if (index < items.length - 1)
                  Container(
                    width: 1,
                    height: 32,
                    color: colorScheme.outlineVariant,
                  ),
              ],
            ],
          );
        },
      ),
    );
  }

  Widget _buildSearchBar(BuildContext context, ColorScheme colorScheme) {
    return TextField(
      onChanged: (v) => setState(() => _searchQuery = v.toLowerCase()),
      decoration: InputDecoration(
        hintText: tr(context, 'tools_search'),
        prefixIcon: const Icon(Icons.search_rounded),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        filled: true,
        fillColor: colorScheme.surfaceContainerHigh,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
      ),
    );
  }

  Widget _buildFeaturedSection(BuildContext context, ColorScheme colorScheme) {
    if (_featuredTools.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.star_rounded, size: 20, color: colorScheme.primary),
            const SizedBox(width: 8),
            Text(
              tr(context, 'tools_featured'),
              style: AppTypography.sectionTitleWith(colorScheme.onSurface),
            ),
          ],
        ),
        const SizedBox(height: 12),
        LayoutBuilder(
          builder: (context, constraints) {
            final columns = _featuredColumnCount(
              constraints.maxWidth,
              _featuredTools.length,
            );
            return GridView.builder(
              key: const ValueKey('tools-featured-grid'),
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: columns,
                mainAxisSpacing: _featuredCardSpacing,
                crossAxisSpacing: _featuredCardSpacing,
                mainAxisExtent: _featuredCardHeight,
              ),
              itemCount: _featuredTools.length,
              itemBuilder: (context, index) => _FeaturedCard(
                key: ValueKey(
                  'tools-featured-card-${_featuredTools[index].name}',
                ),
                tool: _featuredTools[index],
              ),
            );
          },
        ),
      ],
    );
  }

  int _featuredColumnCount(double maxWidth, int itemCount) {
    if (itemCount <= 0) return 1;
    if (itemCount >= _featuredDesktopColumns &&
        (maxWidth.isInfinite || maxWidth >= _featuredThreeColumnBreakpoint)) {
      return _featuredDesktopColumns;
    }
    if (itemCount >= 2 && maxWidth >= _featuredTwoColumnBreakpoint) {
      return 2;
    }
    return 1;
  }

  List<Widget> _buildCategorySections(
    BuildContext context,
    ColorScheme colorScheme,
  ) {
    if (_data == null) return [];
    final sections = <Widget>[];

    for (final category in _data!.categories) {
      final tools = _searchQuery.isEmpty
          ? category.tools
          : category.tools
                .where(
                  (t) =>
                      t.name.toLowerCase().contains(_searchQuery) ||
                      t.desc.toLowerCase().contains(_searchQuery) ||
                      t.developer.toLowerCase().contains(_searchQuery) ||
                      t.tags.any(
                        (tag) => tag.toLowerCase().contains(_searchQuery),
                      ),
                )
                .toList();

      if (tools.isEmpty) continue;

      sections.add(
        Padding(
          padding: const EdgeInsets.only(bottom: 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 4,
                    height: 22,
                    decoration: BoxDecoration(
                      color: category.displayColor,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    tr(context, category.nameKey),
                    style: AppTypography.sectionTitleWith(
                      colorScheme.onSurface,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              LayoutBuilder(
                builder: (context, constraints) => GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: constraints.maxWidth < 980 ? 1 : 2,
                    mainAxisSpacing: 16,
                    crossAxisSpacing: 16,
                    mainAxisExtent: constraints.maxWidth < 620
                        ? 380
                        : _toolCardHeight,
                  ),
                  itemCount: tools.length,
                  itemBuilder: (context, index) => _ToolCard(
                    tool: tools[index],
                    categoryColor: category.displayColor,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (sections.isEmpty) {
      sections.add(
        Center(
          child: Padding(
            padding: const EdgeInsets.all(48),
            child: Column(
              children: [
                Icon(
                  Icons.search_off_rounded,
                  size: 48,
                  color: colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
                ),
                const SizedBox(height: 12),
                Text(
                  tr(context, 'tools_empty'),
                  style: AppTypography.bodyWith(colorScheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return sections;
  }
}

// ─── Featured Card ───

class _FeaturedCard extends StatelessWidget {
  final ToolItem tool;
  const _FeaturedCard({super.key, required this.tool});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => Navigator.of(
          context,
          rootNavigator: true,
        ).push(MaterialPageRoute(builder: (_) => ToolDetailScreen(tool: tool))),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  tool.iconData,
                  size: 22,
                  color: colorScheme.onPrimaryContainer,
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(left: 12),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        tool.name,
                        style: AppTypography.cardTitleWith(
                          colorScheme.onSurface,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      _SafetyBadge(tool: tool),
                      const SizedBox(height: 6),
                      Text(
                        tool.desc,
                        style: AppTypography.captionWith(
                          colorScheme.onSurfaceVariant,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Tool Card ───

Future<void> _openToolUrl(
  BuildContext context,
  ToolItem tool,
  String url,
) async {
  if (url.isEmpty) return;
  final proceed = await _confirmToolSafety(context, tool);
  if (!context.mounted || !proceed) return;
  await WebviewHelper.openUrl(context, url, title: tool.name);
}

Future<bool> _confirmToolSafety(BuildContext context, ToolItem tool) async {
  if (tool.isActivationRelated) {
    return _confirmActivationToolNotice(context);
  }

  final warning = _ToolSafetyWarning.forTool(tool);
  if (warning == null) return true;

  final result = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(tr(ctx, warning.titleKey)),
      content: SingleChildScrollView(child: Text(tr(ctx, warning.messageKey))),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: Text(tr(ctx, 'tool_warning_cancel')),
        ),
        FilledButton(
          onPressed: () => Navigator.of(ctx).pop(true),
          child: Text(tr(ctx, 'tool_warning_continue')),
        ),
      ],
    ),
  );
  return result == true;
}

Future<bool> _confirmActivationToolNotice(BuildContext context) async {
  const prefKey = 'activation_tool_notice_hidden';
  final prefs = await SharedPreferences.getInstance();
  if (prefs.getBool(prefKey) ?? false) return true;
  if (!context.mounted) return false;

  final result = await showDialog<_ActivationNoticeResult>(
    context: context,
    builder: (ctx) => const _ActivationToolNoticeDialog(),
  );
  if (result == null || !result.continueToTool) return false;
  if (result.doNotShowAgain) {
    await prefs.setBool(prefKey, true);
  }
  return true;
}

class _ActivationNoticeResult {
  final bool continueToTool;
  final bool doNotShowAgain;

  const _ActivationNoticeResult({
    required this.continueToTool,
    required this.doNotShowAgain,
  });
}

class _ActivationToolNoticeDialog extends StatefulWidget {
  const _ActivationToolNoticeDialog();

  @override
  State<_ActivationToolNoticeDialog> createState() =>
      _ActivationToolNoticeDialogState();
}

class _ActivationToolNoticeDialogState
    extends State<_ActivationToolNoticeDialog> {
  bool _doNotShowAgain = false;

  void _close(bool continueToTool) {
    Navigator.of(context).pop(
      _ActivationNoticeResult(
        continueToTool: continueToTool,
        doNotShowAgain: continueToTool && _doNotShowAgain,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(tr(context, 'activation_tool_notice_title')),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(tr(context, 'activation_tool_notice_message')),
            const SizedBox(height: 16),
            CheckboxListTile(
              value: _doNotShowAgain,
              onChanged: (value) =>
                  setState(() => _doNotShowAgain = value ?? false),
              title: Text(tr(context, 'tool_warning_do_not_show_again')),
              controlAffinity: ListTileControlAffinity.leading,
              contentPadding: EdgeInsets.zero,
              dense: true,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => _close(false),
          child: Text(tr(context, 'tool_warning_cancel')),
        ),
        FilledButton(
          onPressed: () => _close(true),
          child: Text(tr(context, 'tool_warning_continue')),
        ),
      ],
    );
  }
}

class _ToolSafetyWarning {
  final String titleKey;
  final String messageKey;

  const _ToolSafetyWarning({required this.titleKey, required this.messageKey});

  static _ToolSafetyWarning? forTool(ToolItem tool) {
    final normalized = tool.name.toLowerCase().replaceAll(' ', '');
    if (normalized == 'dism++') {
      return const _ToolSafetyWarning(
        titleKey: 'tool_warning_dism_title',
        messageKey: 'tool_warning_dism_message',
      );
    }
    if (normalized == 'windhawk') {
      return const _ToolSafetyWarning(
        titleKey: 'tool_warning_windhawk_title',
        messageKey: 'tool_warning_windhawk_message',
      );
    }
    if (tool.safetyLevel == ToolSafetyLevel.expert) {
      return const _ToolSafetyWarning(
        titleKey: 'tool_warning_expert_title',
        messageKey: 'tool_warning_expert_message',
      );
    }
    return null;
  }
}

class _SafetyBadge extends StatelessWidget {
  final ToolItem tool;
  const _SafetyBadge({required this.tool});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final displayLevel = tool.isActivationRelated
        ? ToolSafetyLevel.advanced
        : tool.safetyLevel;
    final color = switch (displayLevel) {
      ToolSafetyLevel.beginner => Colors.green,
      ToolSafetyLevel.advanced => colorScheme.primary,
      ToolSafetyLevel.expert => Colors.deepOrange,
    };
    final badge = Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.28)),
      ),
      child: AppCompactLabel(
        tr(context, displayLevel.labelKey),
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
    if (!tool.isActivationRelated) return badge;
    return Tooltip(
      message: tr(context, 'activation_tool_badge_tooltip'),
      child: badge,
    );
  }
}

class _ToolCard extends StatefulWidget {
  final ToolItem tool;
  final Color categoryColor;
  const _ToolCard({required this.tool, required this.categoryColor});

  @override
  State<_ToolCard> createState() => _ToolCardState();
}

class _ToolCardState extends State<_ToolCard> {
  bool _hovered = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final tokens = AppVisualTokens.of(context);

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() {
        _hovered = false;
        _pressed = false;
      }),
      child: GestureDetector(
        onTapDown: (_) => setState(() => _pressed = true),
        onTapUp: (_) => setState(() => _pressed = false),
        onTapCancel: () => setState(() => _pressed = false),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          transform: _pressed
              ? (Matrix4.identity()..scaleByDouble(0.96, 0.96, 1.0, 1.0))
              : _hovered
              ? (Matrix4.identity()..scaleByDouble(1.02, 1.02, 1.0, 1.0))
              : Matrix4.identity(),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(tokens.surfaceRadius),
            boxShadow: _hovered
                ? [
                    BoxShadow(
                      color: widget.categoryColor.withValues(alpha: 0.2),
                      blurRadius: 16,
                      offset: const Offset(0, 4),
                    ),
                  ]
                : [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.05),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
          ),
          child: Card(
            clipBehavior: Clip.antiAlias,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(tokens.surfaceRadius),
            ),
            child: InkWell(
              onTap: () => Navigator.of(context, rootNavigator: true).push(
                MaterialPageRoute(
                  builder: (_) => ToolDetailScreen(tool: widget.tool),
                ),
              ),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final compact = constraints.maxWidth < 620;
                  final icon = _buildIcon(compact ? 56 : 64);
                  final info = _buildInfo(context);
                  final buttons = _buildButtons(context);
                  return Padding(
                    padding: const EdgeInsets.all(20),
                    child: compact
                        ? Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Expanded(
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    icon,
                                    const SizedBox(width: 16),
                                    Expanded(child: info),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 12),
                              buttons,
                            ],
                          )
                        : Row(
                            children: [
                              icon,
                              const SizedBox(width: 20),
                              Expanded(child: info),
                              const SizedBox(width: 16),
                              SizedBox(width: 148, child: buttons),
                            ],
                          ),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildIcon(double size) {
    final tokens = AppVisualTokens.of(context);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: widget.categoryColor.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(tokens.controlRadius),
      ),
      child: Icon(
        widget.tool.iconData,
        size: size / 2,
        color: widget.categoryColor,
      ),
    );
  }

  Widget _buildInfo(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final tool = widget.tool;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          tool.name,
          style: AppTypography.cardTitleWith(colorScheme.onSurface),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 6),
        _SafetyBadge(tool: tool),
        if (tool.developer.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            '${tr(context, 'tools_developer')}: ${tool.developer}',
            style: AppTypography.captionWith(colorScheme.onSurfaceVariant),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
        if (tool.version.isNotEmpty) ...[
          const SizedBox(height: 2),
          Text(
            '${tr(context, 'tools_version')}: ${tool.version}',
            style: AppTypography.captionWith(colorScheme.onSurfaceVariant),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
        const SizedBox(height: 8),
        Text(
          tool.desc,
          style: AppTypography.bodyWith(colorScheme.onSurfaceVariant),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          runSpacing: 4,
          children: [
            for (final tag in tool.tags.take(4))
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: widget.categoryColor.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: AppCompactLabel(
                  tag,
                  style: TextStyle(fontSize: 11, color: widget.categoryColor),
                ),
              ),
          ],
        ),
      ],
    );
  }

  Widget _buildButtons(BuildContext context) {
    final tool = widget.tool;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FilledButton.tonalIcon(
          onPressed: () => _openToolUrl(context, tool, tool.url),
          icon: const Icon(Icons.language_rounded, size: 18),
          label: Text(
            tr(context, 'tools_website'),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (tool.downloadUrl != null) ...[
          const SizedBox(height: 8),
          FilledButton.icon(
            onPressed: () => _openToolUrl(context, tool, tool.downloadUrl!),
            icon: const Icon(Icons.download_rounded, size: 18),
            label: Text(
              tr(context, 'tools_download'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ],
    );
  }
}

// ─── Stat Item ───

class _StatItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  const _StatItem({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Column(
      children: [
        Icon(icon, size: 20, color: colorScheme.primary),
        const SizedBox(height: 4),
        Text(
          value,
          style: AppTypography.sectionTitleWith(colorScheme.onSurface),
        ),
        Text(
          label,
          style: AppTypography.captionWith(colorScheme.onSurfaceVariant),
        ),
      ],
    );
  }
}

// ─── Tool Detail Screen ───

class ToolDetailScreen extends StatelessWidget {
  final ToolItem tool;
  const ToolDetailScreen({super.key, required this.tool});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: Text(tool.name)),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 700),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AppPageHeader(
                  icon: tool.iconData,
                  title: tool.name,
                  details: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _SafetyBadge(tool: tool),
                      if (tool.developer.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          tool.developer,
                          style: AppTypography.bodyWith(
                            colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 24),

                // Info rows
                _DetailRow(
                  label: tr(context, 'tools_developer'),
                  value: tool.developer,
                ),
                if (tool.version.isNotEmpty)
                  _DetailRow(
                    label: tr(context, 'tools_version'),
                    value: tool.version,
                  ),
                if (tool.license.isNotEmpty)
                  _DetailRow(
                    label: tr(context, 'tools_license'),
                    value: tool.license,
                  ),
                if (tool.releaseDate.isNotEmpty)
                  _DetailRow(
                    label: tr(context, 'tools_release'),
                    value: tool.releaseDate,
                  ),
                if (tool.systemRequirements != null)
                  _DetailRow(
                    label: tr(context, 'tools_requirements'),
                    value: tool.systemRequirements!,
                  ),

                const SizedBox(height: 24),

                // Description
                Text(
                  tr(context, 'tools_about'),
                  style: AppTypography.sectionTitleWith(colorScheme.onSurface),
                ),
                const SizedBox(height: 8),
                Text(
                  tool.desc,
                  style: AppTypography.bodyWith(colorScheme.onSurface),
                ),
                const SizedBox(height: 24),

                // Features
                if (tool.features.isNotEmpty) ...[
                  Text(
                    tr(context, 'tools_features'),
                    style: AppTypography.sectionTitleWith(
                      colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 8),
                  ...tool.features.map(
                    (f) => Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            Icons.check_circle_rounded,
                            size: 16,
                            color: Colors.green,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              f,
                              style: AppTypography.bodyWith(
                                colorScheme.onSurface,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                ],

                // Tags
                if (tool.tags.isNotEmpty) ...[
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: tool.tags
                        .map(
                          (tag) => Chip(
                            label: AppCompactLabel(
                              tag,
                              style: const TextStyle(fontSize: 12),
                            ),
                            visualDensity: VisualDensity.compact,
                            materialTapTargetSize:
                                MaterialTapTargetSize.shrinkWrap,
                          ),
                        )
                        .toList(),
                  ),
                  const SizedBox(height: 24),
                ],

                if (tool.isActivationRelated) ...[
                  const _ActivationDisclaimerSection(),
                  const SizedBox(height: 24),
                ],

                LayoutBuilder(
                  builder: (context, constraints) {
                    final websiteButton = OutlinedButton.icon(
                      icon: const Icon(Icons.language_rounded),
                      label: Text(tr(context, 'tools_website')),
                      onPressed: () => _openToolUrl(context, tool, tool.url),
                    );
                    final downloadButton = tool.downloadUrl == null
                        ? null
                        : FilledButton.icon(
                            icon: const Icon(Icons.download_rounded),
                            label: Text(tr(context, 'tools_download')),
                            onPressed: () =>
                                _openToolUrl(context, tool, tool.downloadUrl!),
                          );
                    if (constraints.maxWidth < 480) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          websiteButton,
                          if (downloadButton != null) ...[
                            const SizedBox(height: 8),
                            downloadButton,
                          ],
                        ],
                      );
                    }
                    return Row(
                      children: [
                        Expanded(child: websiteButton),
                        if (downloadButton != null) ...[
                          const SizedBox(width: 12),
                          Expanded(child: downloadButton),
                        ],
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ActivationDisclaimerSection extends StatelessWidget {
  const _ActivationDisclaimerSection();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.info_outline_rounded,
            size: 20,
            color: colorScheme.primary,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  tr(context, 'activation_tool_disclaimer_title'),
                  style: AppTypography.cardTitleWith(colorScheme.onSurface),
                ),
                const SizedBox(height: 6),
                Text(
                  tr(context, 'activation_tool_disclaimer_message'),
                  style: AppTypography.bodyWith(colorScheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;
  const _DetailRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final labelWidget = Text(
      label,
      style: AppTypography.captionWith(colorScheme.onSurfaceVariant),
    );
    final valueWidget = Text(
      value,
      style: AppTypography.bodyWith(colorScheme.onSurface),
    );
    return LayoutBuilder(
      builder: (context, constraints) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: constraints.maxWidth < 420
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [labelWidget, const SizedBox(height: 2), valueWidget],
              )
            : Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(width: 120, child: labelWidget),
                  Expanded(child: valueWidget),
                ],
              ),
      ),
    );
  }
}
