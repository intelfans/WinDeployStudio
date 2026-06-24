import 'dart:math';
import 'package:flutter/material.dart';
import '../../../app/typography.dart';
import '../../../core/localization/strings.dart';
import '../../../shared/webview/webview_helper.dart';
import '../models/tool_models.dart';

class ToolsScreen extends StatefulWidget {
  const ToolsScreen({super.key});

  @override
  State<ToolsScreen> createState() => _ToolsScreenState();
}

class _ToolsScreenState extends State<ToolsScreen> {
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
    _featuredTools = list.take(5).toList();
  }

  Future<void> _loadData() async {
    _lastLocale = L.currentLocale;
    final data = await ToolsData.load();
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
    final currentLocale = Localizations.localeOf(context).languageCode;
    if (currentLocale != _lastLocale && !_loading) {
      _loadData();
    }
    final colorScheme = Theme.of(context).colorScheme;
    final screenWidth = MediaQuery.of(context).size.width;
    final isCompact = screenWidth < 900;

    return Scaffold(
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: EdgeInsets.all(isCompact ? 16 : 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildHeader(context, colorScheme),
                  const SizedBox(height: 20),
                  _buildStatsBar(context, colorScheme),
                  const SizedBox(height: 20),
                  _buildSearchBar(context, colorScheme),
                  const SizedBox(height: 24),
                  if (_searchQuery.isEmpty) ...[
                    _buildFeaturedSection(context, colorScheme, isCompact),
                    const SizedBox(height: 32),
                  ],
                  ..._buildCategorySections(context, colorScheme, isCompact),
                ],
              ),
            ),
    );
  }

  Widget _buildHeader(BuildContext context, ColorScheme colorScheme) {
    return Row(
      children: [
        Container(
          width: 56, height: 56,
          decoration: BoxDecoration(
            color: colorScheme.primaryContainer,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Icon(Icons.handyman_rounded, size: 32, color: colorScheme.onPrimaryContainer),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(tr(context, 'tools_title'), style: AppTypography.pageTitleWith(colorScheme.onSurface)),
              const SizedBox(height: 4),
              Text(tr(context, 'tools_subtitle'), style: AppTypography.bodyWith(colorScheme.onSurfaceVariant)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildStatsBar(BuildContext context, ColorScheme colorScheme) {
    if (_data == null) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _StatItem(icon: Icons.apps_rounded, label: tr(context, 'tools_stat_total'), value: '${_data!.totalTools}'),
          Container(width: 1, height: 32, color: colorScheme.outlineVariant),
          _StatItem(icon: Icons.folder_rounded, label: tr(context, 'tools_stat_categories'), value: '${_data!.totalCategories}'),
          Container(width: 1, height: 32, color: colorScheme.outlineVariant),
          _StatItem(icon: Icons.update_rounded, label: tr(context, 'tools_stat_updated'), value: DateTime.now().toString().split(' ')[0]),
        ],
      ),
    );
  }

  Widget _buildSearchBar(BuildContext context, ColorScheme colorScheme) {
    return TextField(
      onChanged: (v) => setState(() => _searchQuery = v.toLowerCase()),
      decoration: InputDecoration(
        hintText: tr(context, 'tools_search'),
        prefixIcon: const Icon(Icons.search_rounded),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
        filled: true,
        fillColor: colorScheme.surfaceContainerHigh,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
    );
  }

  Widget _buildFeaturedSection(BuildContext context, ColorScheme colorScheme, bool isCompact) {
    if (_featuredTools.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.star_rounded, size: 20, color: colorScheme.primary),
            const SizedBox(width: 8),
            Text(tr(context, 'tools_featured'), style: AppTypography.sectionTitleWith(colorScheme.onSurface)),
          ],
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 160,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: _featuredTools.length,
            separatorBuilder: (_, __) => const SizedBox(width: 12),
            itemBuilder: (context, index) => _FeaturedCard(tool: _featuredTools[index]),
          ),
        ),
      ],
    );
  }

  List<Widget> _buildCategorySections(BuildContext context, ColorScheme colorScheme, bool isCompact) {
    if (_data == null) return [];
    final sections = <Widget>[];

    for (final category in _data!.categories) {
      final tools = _searchQuery.isEmpty
          ? category.tools
          : category.tools.where((t) =>
              t.name.toLowerCase().contains(_searchQuery) ||
              t.desc.toLowerCase().contains(_searchQuery) ||
              t.developer.toLowerCase().contains(_searchQuery) ||
              t.tags.any((tag) => tag.toLowerCase().contains(_searchQuery))).toList();

      if (tools.isEmpty) continue;

      sections.add(
        Padding(
          padding: const EdgeInsets.only(bottom: 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(width: 4, height: 22, decoration: BoxDecoration(color: category.displayColor, borderRadius: BorderRadius.circular(2))),
                  const SizedBox(width: 10),
                  Text(tr(context, category.nameKey), style: AppTypography.sectionTitleWith(colorScheme.onSurface)),
                ],
              ),
              const SizedBox(height: 16),
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: isCompact ? 1 : 2,
                  mainAxisSpacing: 16,
                  crossAxisSpacing: 16,
                  childAspectRatio: isCompact ? 2.5 : 2.8,
                ),
                itemCount: tools.length,
                itemBuilder: (context, index) => _ToolCard(tool: tools[index], categoryColor: category.displayColor),
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
                Icon(Icons.search_off_rounded, size: 48, color: colorScheme.onSurfaceVariant.withValues(alpha: 0.4)),
                const SizedBox(height: 12),
                Text(tr(context, 'tools_empty'), style: AppTypography.bodyWith(colorScheme.onSurfaceVariant)),
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
  const _FeaturedCard({required this.tool});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return SizedBox(
      width: 200,
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => Navigator.of(context, rootNavigator: true).push(MaterialPageRoute(builder: (_) => ToolDetailScreen(tool: tool))),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 48, height: 48,
                  decoration: BoxDecoration(
                    color: colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(tool.iconData, size: 24, color: colorScheme.onPrimaryContainer),
                ),
                const SizedBox(height: 12),
                Text(tool.name, style: AppTypography.cardTitleWith(colorScheme.onSurface), maxLines: 1, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 4),
                Text(tool.desc, style: AppTypography.captionWith(colorScheme.onSurfaceVariant), maxLines: 2, overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Tool Card ───

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
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final tool = widget.tool;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() { _hovered = false; _pressed = false; }),
      child: GestureDetector(
        onTapDown: (_) => setState(() => _pressed = true),
        onTapUp: (_) => setState(() => _pressed = false),
        onTapCancel: () => setState(() => _pressed = false),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          transform: _pressed
              ? (Matrix4.identity()..scale(0.96))
              : _hovered
                  ? (Matrix4.identity()..scale(1.02))
                  : Matrix4.identity(),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            boxShadow: _hovered
                ? [BoxShadow(color: widget.categoryColor.withValues(alpha: 0.2), blurRadius: 16, offset: const Offset(0, 4))]
                : [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 8, offset: const Offset(0, 2))],
          ),
          child: Card(
            clipBehavior: Clip.antiAlias,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            child: InkWell(
              onTap: () => Navigator.of(context, rootNavigator: true).push(MaterialPageRoute(builder: (_) => ToolDetailScreen(tool: tool))),
              child: Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                children: [
                  // Logo / Icon
                  Container(
                    width: 64, height: 64,
                    decoration: BoxDecoration(
                      color: widget.categoryColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Icon(tool.iconData, size: 32, color: widget.categoryColor),
                  ),
                  const SizedBox(width: 20),
                  // Info
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(tool.name, style: AppTypography.sectionTitleWith(colorScheme.onSurface)),
                        if (tool.developer.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text('${tr(context, 'tools_developer')}: ${tool.developer}',
                              style: AppTypography.captionWith(colorScheme.onSurfaceVariant)),
                        ],
                        if (tool.version.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text('${tr(context, 'tools_version')}: ${tool.version}',
                              style: AppTypography.captionWith(colorScheme.onSurfaceVariant)),
                        ],
                        const SizedBox(height: 8),
                        Text(tool.desc, style: AppTypography.bodyWith(colorScheme.onSurfaceVariant), maxLines: 2, overflow: TextOverflow.ellipsis),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 6, runSpacing: 4,
                          children: tool.tags.take(4).map((tag) => Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: widget.categoryColor.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(tag, style: TextStyle(fontSize: 11, color: widget.categoryColor)),
                          )).toList(),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),
                  // Buttons
                  Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      FilledButton.tonal(
                        onPressed: () => WebviewHelper.openUrl(context, tool.url, title: tool.name),
                        style: FilledButton.styleFrom(minimumSize: const Size(80, 36)),
                        child: Text(tr(context, 'tools_website'), style: const TextStyle(fontSize: 13)),
                      ),
                      const SizedBox(height: 8),
                      if (tool.downloadUrl != null)
                        FilledButton(
                          onPressed: () => WebviewHelper.openUrl(context, tool.downloadUrl!, title: tool.name),
                          style: FilledButton.styleFrom(minimumSize: const Size(80, 36)),
                          child: Text(tr(context, 'tools_download'), style: const TextStyle(fontSize: 13)),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
    );
  }
}

// ─── Stat Item ───

class _StatItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  const _StatItem({required this.icon, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Column(
      children: [
        Icon(icon, size: 20, color: colorScheme.primary),
        const SizedBox(height: 4),
        Text(value, style: AppTypography.sectionTitleWith(colorScheme.onSurface)),
        Text(label, style: AppTypography.captionWith(colorScheme.onSurfaceVariant)),
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
                // Header
                Row(
                  children: [
                    Container(
                      width: 72, height: 72,
                      decoration: BoxDecoration(
                        color: colorScheme.primaryContainer,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Icon(tool.iconData, size: 36, color: colorScheme.onPrimaryContainer),
                    ),
                    const SizedBox(width: 20),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(tool.name, style: AppTypography.pageTitleWith(colorScheme.onSurface)),
                          if (tool.developer.isNotEmpty)
                            Text(tool.developer, style: AppTypography.bodyWith(colorScheme.onSurfaceVariant)),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),

                // Info rows
                _DetailRow(label: tr(context, 'tools_developer'), value: tool.developer),
                if (tool.version.isNotEmpty) _DetailRow(label: tr(context, 'tools_version'), value: tool.version),
                if (tool.license.isNotEmpty) _DetailRow(label: tr(context, 'tools_license'), value: tool.license),
                if (tool.releaseDate.isNotEmpty) _DetailRow(label: tr(context, 'tools_release'), value: tool.releaseDate),
                if (tool.systemRequirements != null) _DetailRow(label: tr(context, 'tools_requirements'), value: tool.systemRequirements!),

                const SizedBox(height: 24),

                // Description
                Text(tr(context, 'tools_about'), style: AppTypography.sectionTitleWith(colorScheme.onSurface)),
                const SizedBox(height: 8),
                Text(tool.desc, style: AppTypography.bodyWith(colorScheme.onSurface)),
                const SizedBox(height: 24),

                // Features
                if (tool.features.isNotEmpty) ...[
                  Text(tr(context, 'tools_features'), style: AppTypography.sectionTitleWith(colorScheme.onSurface)),
                  const SizedBox(height: 8),
                  ...tool.features.map((f) => Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.check_circle_rounded, size: 16, color: Colors.green),
                        const SizedBox(width: 8),
                        Expanded(child: Text(f, style: AppTypography.bodyWith(colorScheme.onSurface))),
                      ],
                    ),
                  )),
                  const SizedBox(height: 24),
                ],

                // Tags
                if (tool.tags.isNotEmpty) ...[
                  Wrap(
                    spacing: 8, runSpacing: 6,
                    children: tool.tags.map((tag) => Chip(
                      label: Text(tag, style: const TextStyle(fontSize: 12)),
                      visualDensity: VisualDensity.compact,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    )).toList(),
                  ),
                  const SizedBox(height: 24),
                ],

                // Buttons
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.language_rounded),
                        label: Text(tr(context, 'tools_website')),
                        onPressed: () => WebviewHelper.openUrl(context, tool.url, title: tool.name),
                      ),
                    ),
                    const SizedBox(width: 12),
                    if (tool.downloadUrl != null)
                      Expanded(
                        child: FilledButton.icon(
                          icon: const Icon(Icons.download_rounded),
                          label: Text(tr(context, 'tools_download')),
                          onPressed: () => WebviewHelper.openUrl(context, tool.downloadUrl!, title: tool.name),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
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
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          SizedBox(
            width: 120,
            child: Text(label, style: AppTypography.captionWith(colorScheme.onSurfaceVariant)),
          ),
          Expanded(child: Text(value, style: AppTypography.bodyWith(colorScheme.onSurface))),
        ],
      ),
    );
  }
}
