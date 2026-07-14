import 'package:flutter/material.dart';
import '../../../app/theme.dart';
import '../../../app/typography.dart';
import '../../../core/localization/strings.dart';
import '../../../shared/widgets/app_compact_label.dart';
import '../../../shared/widgets/app_page.dart';
import '../models/log_category.dart';
import '../services/log_center_service.dart';
import '../widgets/log_card.dart';
import '../widgets/recent_log_widget.dart';
import '../widgets/log_stat_widget.dart';

class LogsScreen extends StatefulWidget {
  const LogsScreen({super.key});

  @override
  State<LogsScreen> createState() => _LogsScreenState();
}

class _LogsScreenState extends State<LogsScreen> {
  final _service = LogCenterService();
  LogStats? _stats;
  List<LogActivity> _activities = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _loading = true);
    try {
      final stats = await _service.getStats();
      final activities = await _service.getRecentActivities();
      if (mounted) {
        setState(() {
          _stats = stats;
          _activities = activities;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
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
                    _buildStatsRow(context, colorScheme),
                    SizedBox(height: tokens.sectionSpacing),
                    _buildCategoryGrid(context),
                    SizedBox(height: tokens.sectionSpacing),
                    _buildRecentActivities(context, colorScheme),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildHeader(BuildContext context, ColorScheme colorScheme) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: AppPageHeader(
            icon: Icons.receipt_long_rounded,
            title: tr(context, 'logs_title'),
            subtitle: tr(context, 'logs_subtitle'),
          ),
        ),
        const SizedBox(width: 8),
        _buildHeaderActions(context),
      ],
    );
  }

  Widget _buildHeaderActions(BuildContext context) {
    return PopupMenuButton<String>(
      key: const Key('logs-header-menu'),
      icon: const Icon(Icons.more_vert),
      onSelected: (value) => _handleHeaderAction(context, value),
      itemBuilder: (context) => [
        PopupMenuItem(
          value: 'open',
          child: Row(
            children: [
              const Icon(Icons.folder_open_rounded),
              const SizedBox(width: 8),
              Text(tr(context, 'logs_open_folder')),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'export',
          child: Row(
            children: [
              const Icon(Icons.archive_rounded),
              const SizedBox(width: 8),
              Text(tr(context, 'logs_export')),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'clear',
          child: Row(
            children: [
              const Icon(Icons.delete_sweep_rounded),
              const SizedBox(width: 8),
              Text(tr(context, 'logs_clear')),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _handleHeaderAction(BuildContext context, String action) async {
    switch (action) {
      case 'open':
        await _service.openLogsFolder();
        break;
      case 'export':
        try {
          final path = await _service.exportLogs();
          if (mounted) {
            final msg = tr(
              this.context,
              'logs_exported',
            ).replaceAll('{path}', path);
            ScaffoldMessenger.of(
              this.context,
            ).showSnackBar(SnackBar(content: Text(msg)));
          }
        } catch (e) {
          if (mounted) {
            final msg = tr(
              this.context,
              'logs_export_failed',
            ).replaceAll('{error}', '$e');
            ScaffoldMessenger.of(
              this.context,
            ).showSnackBar(SnackBar(content: Text(msg)));
          }
        }
        break;
      case 'clear':
        _showClearDialog(context);
        break;
    }
  }

  void _showClearDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) =>
          _ClearLogsDialog(service: _service, onCleared: () => _loadData()),
    );
  }

  Widget _buildStatsRow(BuildContext context, ColorScheme colorScheme) {
    final stats = _stats;
    if (stats == null) return const SizedBox.shrink();

    final totalFilesText = stats.formattedSize;
    final lastActivityText = stats.lastActivityFormatted(
      (key) => tr(context, key),
    );

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(
          AppVisualTokens.of(context).surfaceRadius,
        ),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 560;
          if (compact) {
            return Column(
              children: [
                LogStatWidget(
                  title: tr(context, 'logs_total'),
                  value: '${stats.totalFiles}',
                  icon: Icons.description_rounded,
                  color: colorScheme.primary,
                ),
                const Divider(height: 24),
                LogStatWidget(
                  title: tr(context, 'logs_total_size'),
                  value: totalFilesText,
                  icon: Icons.storage_rounded,
                  color: colorScheme.secondary,
                ),
                const Divider(height: 24),
                LogStatWidget(
                  title: tr(context, 'logs_last_activity'),
                  value: lastActivityText,
                  icon: Icons.access_time_rounded,
                  color: colorScheme.tertiary,
                ),
              ],
            );
          }
          return Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              Expanded(
                child: LogStatWidget(
                  title: tr(context, 'logs_total'),
                  value: '${stats.totalFiles}',
                  icon: Icons.description_rounded,
                  color: colorScheme.primary,
                ),
              ),
              Container(
                width: 1,
                height: 60,
                color: colorScheme.outlineVariant,
              ),
              Expanded(
                child: LogStatWidget(
                  title: tr(context, 'logs_total_size'),
                  value: totalFilesText,
                  icon: Icons.storage_rounded,
                  color: colorScheme.secondary,
                ),
              ),
              Container(
                width: 1,
                height: 60,
                color: colorScheme.outlineVariant,
              ),
              Expanded(
                child: LogStatWidget(
                  title: tr(context, 'logs_last_activity'),
                  value: lastActivityText,
                  icon: Icons.access_time_rounded,
                  color: colorScheme.tertiary,
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildCategoryGrid(BuildContext context) {
    final stats = _stats;

    return LayoutBuilder(
      builder: (context, constraints) => GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
          // A single wide card preserves the details at phone-sized widths.
          maxCrossAxisExtent: constraints.maxWidth < 560
              ? constraints.maxWidth
              : 360,
          mainAxisExtent: 180,
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
        ),
        itemCount: LogCategory.values.length,
        itemBuilder: (context, index) {
          final category = LogCategory.values[index];
          final count = stats?.categoryCounts[category] ?? 0;

          return LogCategoryCard(
            category: category,
            categoryDisplayName: tr(context, category.nameKey),
            fileCount: count,
            lastUpdate: stats?.categoryLastUpdates[category],
            onTap: () => _service.openCategoryFolder(category),
          );
        },
      ),
    );
  }

  Widget _buildRecentActivities(BuildContext context, ColorScheme colorScheme) {
    if (_activities.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          tr(context, 'logs_recent'),
          style: AppTypography.sectionTitleWith(colorScheme.onSurface),
        ),
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: _activities.map((activity) {
                return RecentLogWidget(
                  activity: activity,
                  categoryDisplayName: tr(context, activity.category.nameKey),
                );
              }).toList(),
            ),
          ),
        ),
      ],
    );
  }
}

class _ClearLogsDialog extends StatefulWidget {
  final LogCenterService service;
  final VoidCallback onCleared;

  const _ClearLogsDialog({required this.service, required this.onCleared});

  @override
  State<_ClearLogsDialog> createState() => _ClearLogsDialogState();
}

class _ClearLogsDialogState extends State<_ClearLogsDialog> {
  // 0=all, 1=1day, 7=1week, 30=1month, -1=all time
  int _daysOld = 30;
  final Map<LogCategory, bool> _selected = {
    for (final c in LogCategory.values) c: true,
  };

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(tr(context, 'logs_clear_title')),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                tr(context, 'logs_clear_time'),
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _TimeChip(
                    label: tr(context, 'logs_clear_all'),
                    value: -1,
                    groupValue: _daysOld,
                    onSelected: (v) => setState(() => _daysOld = v),
                  ),
                  _TimeChip(
                    label: tr(context, 'logs_clear_1d'),
                    value: 1,
                    groupValue: _daysOld,
                    onSelected: (v) => setState(() => _daysOld = v),
                  ),
                  _TimeChip(
                    label: tr(context, 'logs_clear_7d'),
                    value: 7,
                    groupValue: _daysOld,
                    onSelected: (v) => setState(() => _daysOld = v),
                  ),
                  _TimeChip(
                    label: tr(context, 'logs_clear_30d'),
                    value: 30,
                    groupValue: _daysOld,
                    onSelected: (v) => setState(() => _daysOld = v),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Text(
                tr(context, 'logs_clear_categories'),
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              ...LogCategory.values.map(
                (c) => CheckboxListTile(
                  value: _selected[c],
                  onChanged: (v) => setState(() => _selected[c] = v ?? false),
                  title: Text(tr(context, c.nameKey)),
                  secondary: Icon(c.icon, color: c.color, size: 20),
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  visualDensity: VisualDensity.compact,
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(tr(context, 'logs_cancel')),
        ),
        FilledButton(
          onPressed: _doClear,
          child: Text(tr(context, 'logs_delete')),
        ),
      ],
    );
  }

  Future<void> _doClear() async {
    final categories = _selected.entries
        .where((e) => e.value)
        .map((e) => e.key)
        .toList();
    if (categories.isEmpty) return;

    Navigator.pop(context);
    final daysOld = _daysOld == -1 ? null : _daysOld;
    final count = await widget.service.clearOldLogs(
      daysOld: daysOld,
      categories: categories,
    );
    widget.onCleared();
    if (mounted) {
      final msg = tr(context, 'logs_deleted').replaceAll('{count}', '$count');
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    }
  }
}

class _TimeChip extends StatelessWidget {
  final String label;
  final int value;
  final int groupValue;
  final ValueChanged<int> onSelected;

  const _TimeChip({
    required this.label,
    required this.value,
    required this.groupValue,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final selected = value == groupValue;
    final colorScheme = Theme.of(context).colorScheme;
    return ChoiceChip(
      label: AppCompactLabel(label),
      selected: selected,
      onSelected: (_) => onSelected(value),
      selectedColor: colorScheme.primaryContainer,
      labelStyle: TextStyle(
        color: selected ? colorScheme.onPrimaryContainer : null,
        fontWeight: selected ? FontWeight.w600 : null,
      ),
    );
  }
}
