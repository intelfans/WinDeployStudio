import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/localization/strings.dart';
import '../../benchmark/models/benchmark_models.dart';
import '../benchmark_history_copy.dart';
import '../models/benchmark_history_models.dart';
import '../services/benchmark_history_service.dart';
import 'benchmark_comparison_screen.dart';
import 'benchmark_history_detail_screen.dart';

enum _ExportFormat { csv, json }

class BenchmarkHistoryScreen extends ConsumerStatefulWidget {
  const BenchmarkHistoryScreen({super.key});

  @override
  ConsumerState<BenchmarkHistoryScreen> createState() =>
      _BenchmarkHistoryScreenState();
}

class _BenchmarkHistoryScreenState
    extends ConsumerState<BenchmarkHistoryScreen> {
  List<BenchmarkHistoryRecord> _records = const [];
  final Set<String> _selectedIds = {};
  final TextEditingController _modelFilter = TextEditingController();
  final TextEditingController _serialFilter = TextEditingController();
  final TextEditingController _vidFilter = TextEditingController();
  final TextEditingController _pidFilter = TextEditingController();
  DateTimeRange? _dateRange;
  bool _loading = true;
  bool _working = false;
  String? _error;

  BenchmarkHistoryService get _service =>
      ref.read(benchmarkHistoryServiceProvider);

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _modelFilter.dispose();
    _serialFilter.dispose();
    _vidFilter.dispose();
    _pidFilter.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final records = await _service.list(
        from: _dateRange?.start,
        to: _dateRange == null ? null : _endOfDay(_dateRange!.end),
        model: _modelFilter.text,
        serialNumber: _serialFilter.text,
        vid: _vidFilter.text,
        pid: _pidFilter.text,
      );
      if (!mounted) return;
      setState(() {
        _records = records;
        _selectedIds.removeWhere(
          (id) => !records.any((record) => record.id == id),
        );
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = BenchmarkHistoryKeys.loadFailed;
      });
    }
  }

  Future<void> _pickDateRange() async {
    final now = DateTime.now();
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 10),
      lastDate: DateTime(now.year + 1),
      initialDateRange: _dateRange,
    );
    if (range == null || !mounted) return;
    setState(() {
      _dateRange = range;
      _selectedIds.clear();
    });
    await _load();
  }

  Future<void> _export(_ExportFormat format) async {
    if (_records.isEmpty || _working) return;
    final selected = _selectedIds.isEmpty
        ? _records.map((record) => record.id).toList(growable: false)
        : _selectedIds.toList(growable: false);
    final extension = format.name;
    final destination = await FilePicker.saveFile(
      dialogTitle: format == _ExportFormat.csv
          ? tr(context, BenchmarkHistoryKeys.exportCsv)
          : tr(context, BenchmarkHistoryKeys.exportJson),
      fileName:
          'wds_${DateFormat('yyyyMMdd_HHmmss').format(DateTime.now())}.$extension',
      type: FileType.custom,
      allowedExtensions: [extension],
    );
    if (destination == null || !mounted) return;
    await _runAction(() async {
      if (format == _ExportFormat.csv) {
        await _service.exportCsv(destination, ids: selected);
      } else {
        await _service.exportJson(destination, ids: selected);
      }
      if (!mounted) return null;
      _showMessage(BenchmarkHistoryKeys.exportComplete);
      return null;
    }, reload: false);
  }

  Future<void> _deleteOne(BenchmarkHistoryRecord record) async {
    final confirmed = await _confirm(
      titleKey: BenchmarkHistoryKeys.deleteRecordTitle,
      bodyKey: BenchmarkHistoryKeys.deleteRecordBody,
    );
    if (confirmed != true) return;
    await _runAction(() => _service.deleteOne(record.id));
  }

  Future<void> _deleteRange() async {
    var range = _dateRange;
    if (range == null) {
      final now = DateTime.now();
      range = await showDateRangePicker(
        context: context,
        firstDate: DateTime(now.year - 10),
        lastDate: DateTime(now.year + 1),
      );
    }
    if (range == null || !mounted) return;
    final confirmed = await _confirm(
      titleKey: BenchmarkHistoryKeys.deleteRangeTitle,
      bodyKey: BenchmarkHistoryKeys.deleteRangeBody,
    );
    if (confirmed != true) return;
    await _runAction(
      () => _service.deleteRange(from: range!.start, to: _endOfDay(range.end)),
    );
  }

  Future<void> _deleteAll() async {
    final confirmed = await _confirm(
      titleKey: BenchmarkHistoryKeys.deleteAllTitle,
      bodyKey: BenchmarkHistoryKeys.deleteAllBody,
    );
    if (confirmed != true) return;
    await _runAction(_service.deleteAll);
  }

  Future<void> _runAction(
    Future<Object?> Function() action, {
    bool reload = true,
  }) async {
    if (_working) return;
    setState(() => _working = true);
    try {
      await action();
      if (!mounted) return;
      if (reload) await _load();
    } catch (_) {
      if (!mounted) return;
      _showMessage(BenchmarkHistoryKeys.actionFailed, isError: true);
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<bool?> _confirm({required String titleKey, required String bodyKey}) {
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(tr(context, titleKey)),
        content: Text(tr(context, bodyKey)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(tr(context, BenchmarkHistoryKeys.cancel)),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(tr(context, BenchmarkHistoryKeys.confirmDelete)),
          ),
        ],
      ),
    );
  }

  void _toggleSelection(BenchmarkHistoryRecord record, bool selected) {
    if (!selected) {
      setState(() => _selectedIds.remove(record.id));
      return;
    }
    if (_selectedIds.length >= 2) {
      _showMessage(BenchmarkHistoryKeys.selectionLimit, isError: true);
      return;
    }
    if (_selectedIds.isNotEmpty) {
      final first = _records.firstWhere(
        (candidate) => candidate.id == _selectedIds.first,
      );
      final compatibility = _service.compatibilityFor(first, record);
      if (!compatibility.isCompatible) {
        _showMessage(
          compatibility.incompatibility ==
                  BenchmarkComparisonIncompatibility.differentDevice
              ? BenchmarkHistoryKeys.sameDeviceOnly
              : BenchmarkHistoryKeys.actionFailed,
          isError: true,
        );
        return;
      }
    }
    setState(() => _selectedIds.add(record.id));
  }

  void _compareSelected() {
    if (_selectedIds.length != 2) {
      _showMessage(BenchmarkHistoryKeys.selectTwo, isError: true);
      return;
    }
    final selected =
        _selectedIds
            .map((id) => _records.firstWhere((record) => record.id == id))
            .toList()
          ..sort(
            (left, right) =>
                left.result.completedAt.compareTo(right.result.completedAt),
          );
    try {
      final comparison = _service.compare(selected.first, selected.last);
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => BenchmarkComparisonScreen(comparison: comparison),
        ),
      );
    } on BenchmarkComparisonException catch (error) {
      _showMessage(
        error.reason == BenchmarkComparisonIncompatibility.differentDevice
            ? BenchmarkHistoryKeys.sameDeviceOnly
            : BenchmarkHistoryKeys.actionFailed,
        isError: true,
      );
    }
  }

  void _showMessage(String messageKey, {bool isError = false}) {
    final colors = Theme.of(context).colorScheme;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(tr(context, messageKey)),
        backgroundColor: isError ? colors.error : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Text(tr(context, BenchmarkHistoryKeys.history)),
        actions: [
          IconButton(
            tooltip: tr(context, BenchmarkHistoryKeys.refresh),
            onPressed: _working ? null : _load,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: Column(
        children: [
          _buildToolbar(context),
          _buildIdentityFilters(context),
          if (_working) const LinearProgressIndicator(minHeight: 2),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                ? _MessageState(
                    icon: Icons.error_outline_rounded,
                    title: tr(context, _error!),
                    action: TextButton.icon(
                      onPressed: _load,
                      icon: const Icon(Icons.refresh_rounded),
                      label: Text(tr(context, BenchmarkHistoryKeys.refresh)),
                    ),
                  )
                : _records.isEmpty
                ? _MessageState(
                    icon: Icons.history_rounded,
                    title: tr(context, BenchmarkHistoryKeys.empty),
                    subtitle: tr(context, BenchmarkHistoryKeys.emptySubtitle),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(24, 8, 24, 28),
                    itemCount: _records.length,
                    separatorBuilder: (_, _) =>
                        Divider(height: 1, color: colors.outlineVariant),
                    itemBuilder: (context, index) {
                      final record = _records[index];
                      return _HistoryRow(
                        record: record,
                        selected: _selectedIds.contains(record.id),
                        onSelected: (value) => _toggleSelection(record, value),
                        onOpen: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) =>
                                BenchmarkHistoryDetailScreen(record: record),
                          ),
                        ),
                        onDelete: _working ? null : () => _deleteOne(record),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildToolbar(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final dateText = _dateRange == null
        ? tr(context, BenchmarkHistoryKeys.filterDates)
        : '${DateFormat.yMd().format(_dateRange!.start)} - '
              '${DateFormat.yMd().format(_dateRange!.end)}';
    return Material(
      color: colors.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 14, 24, 14),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    tr(context, BenchmarkHistoryKeys.historySubtitle),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (_selectedIds.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      '${_selectedIds.length} '
                      '${tr(context, BenchmarkHistoryKeys.selected)}',
                      style: TextStyle(
                        color: colors.primary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 12),
            Flexible(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                reverse: true,
                child: Row(
                  children: [
                    OutlinedButton.icon(
                      onPressed: _working ? null : _pickDateRange,
                      icon: const Icon(Icons.date_range_rounded),
                      label: Text(dateText),
                    ),
                    if (_dateRange != null) ...[
                      const SizedBox(width: 6),
                      IconButton(
                        tooltip: tr(context, BenchmarkHistoryKeys.clearDates),
                        onPressed: _working
                            ? null
                            : () async {
                                setState(() => _dateRange = null);
                                await _load();
                              },
                        icon: const Icon(Icons.filter_alt_off_rounded),
                      ),
                    ],
                    const SizedBox(width: 8),
                    FilledButton.icon(
                      onPressed: _selectedIds.length == 2
                          ? _compareSelected
                          : null,
                      icon: const Icon(Icons.compare_arrows_rounded),
                      label: Text(tr(context, BenchmarkHistoryKeys.compare)),
                    ),
                    const SizedBox(width: 8),
                    PopupMenuButton<_ExportFormat>(
                      tooltip: tr(context, BenchmarkHistoryKeys.export),
                      enabled: _records.isNotEmpty && !_working,
                      onSelected: _export,
                      itemBuilder: (context) => [
                        PopupMenuItem(
                          value: _ExportFormat.csv,
                          child: ListTile(
                            leading: const Icon(Icons.table_view_rounded),
                            title: Text(
                              tr(context, BenchmarkHistoryKeys.exportCsv),
                            ),
                            contentPadding: EdgeInsets.zero,
                          ),
                        ),
                        PopupMenuItem(
                          value: _ExportFormat.json,
                          child: ListTile(
                            leading: const Icon(Icons.data_object_rounded),
                            title: Text(
                              tr(context, BenchmarkHistoryKeys.exportJson),
                            ),
                            contentPadding: EdgeInsets.zero,
                          ),
                        ),
                      ],
                      child: _ToolbarButton(
                        icon: Icons.download_rounded,
                        label: tr(context, BenchmarkHistoryKeys.export),
                      ),
                    ),
                    const SizedBox(width: 8),
                    PopupMenuButton<String>(
                      tooltip: tr(context, BenchmarkHistoryKeys.delete),
                      enabled: !_working && _records.isNotEmpty,
                      onSelected: (value) {
                        if (value == 'range') _deleteRange();
                        if (value == 'all') _deleteAll();
                      },
                      itemBuilder: (context) => [
                        PopupMenuItem(
                          value: 'range',
                          child: ListTile(
                            leading: const Icon(Icons.date_range_rounded),
                            title: Text(
                              tr(context, BenchmarkHistoryKeys.deleteRange),
                            ),
                            contentPadding: EdgeInsets.zero,
                          ),
                        ),
                        PopupMenuItem(
                          value: 'all',
                          child: ListTile(
                            leading: const Icon(Icons.delete_sweep_rounded),
                            title: Text(
                              tr(context, BenchmarkHistoryKeys.deleteAll),
                            ),
                            contentPadding: EdgeInsets.zero,
                          ),
                        ),
                      ],
                      child: _ToolbarButton(
                        icon: Icons.delete_outline_rounded,
                        label: tr(context, BenchmarkHistoryKeys.delete),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildIdentityFilters(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final hasFilter = [
      _modelFilter,
      _serialFilter,
      _vidFilter,
      _pidFilter,
    ].any((controller) => controller.text.trim().isNotEmpty);
    return Material(
      color: colors.surface,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 10, 24, 12),
        child: Row(
          children: [
            Expanded(
              child: Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  _IdentityFilterField(
                    controller: _modelFilter,
                    label: tr(context, BenchmarkHistoryKeys.model),
                    onSubmitted: (_) => _load(),
                  ),
                  _IdentityFilterField(
                    controller: _serialFilter,
                    label: tr(context, BenchmarkHistoryKeys.serialNumber),
                    onSubmitted: (_) => _load(),
                  ),
                  _IdentityFilterField(
                    controller: _vidFilter,
                    label: 'VID',
                    onSubmitted: (_) => _load(),
                  ),
                  _IdentityFilterField(
                    controller: _pidFilter,
                    label: 'PID',
                    onSubmitted: (_) => _load(),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            IconButton.filledTonal(
              tooltip: tr(context, BenchmarkHistoryKeys.refresh),
              onPressed: _working
                  ? null
                  : () {
                      _selectedIds.clear();
                      _load();
                    },
              icon: const Icon(Icons.filter_alt_rounded),
            ),
            const SizedBox(width: 6),
            IconButton(
              tooltip: tr(context, BenchmarkHistoryKeys.clearDates),
              onPressed: !hasFilter || _working
                  ? null
                  : () {
                      _modelFilter.clear();
                      _serialFilter.clear();
                      _vidFilter.clear();
                      _pidFilter.clear();
                      _selectedIds.clear();
                      _load();
                    },
              icon: const Icon(Icons.filter_alt_off_rounded),
            ),
          ],
        ),
      ),
    );
  }
}

class _IdentityFilterField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final ValueChanged<String> onSubmitted;

  const _IdentityFilterField({
    required this.controller,
    required this.label,
    required this.onSubmitted,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 180,
      child: TextField(
        controller: controller,
        onSubmitted: onSubmitted,
        decoration: InputDecoration(
          isDense: true,
          labelText: label,
          border: const OutlineInputBorder(),
        ),
      ),
    );
  }
}

class _HistoryRow extends StatelessWidget {
  final BenchmarkHistoryRecord record;
  final bool selected;
  final ValueChanged<bool> onSelected;
  final VoidCallback onOpen;
  final VoidCallback? onDelete;

  const _HistoryRow({
    required this.record,
    required this.selected,
    required this.onSelected,
    required this.onOpen,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final result = record.result;
    final colors = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onOpen,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: Row(
          children: [
            Checkbox(
              value: selected,
              onChanged: (value) => onSelected(value ?? false),
            ),
            const SizedBox(width: 8),
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: colors.primaryContainer,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(Icons.storage_rounded, color: colors.primary),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    result.device.friendlyName.isEmpty
                        ? result.device.model
                        : result.device.friendlyName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${DateFormat.yMd().add_Hms().format(result.completedAt)}  |  '
                    '${tr(context, result.mode.titleKey)}  |  '
                    '${result.disk.sizeFormatted}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: colors.onSurfaceVariant),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '${tr(context, BenchmarkHistoryKeys.serialNumber)}: '
                    '${_available(context, result.device.serialNumber)}  |  '
                    '${tr(context, BenchmarkHistoryKeys.vidPid)}: '
                    '${result.device.vid.isEmpty ? "----" : result.device.vid} / '
                    '${result.device.pid.isEmpty ? "----" : result.device.pid}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            SizedBox(
              width: 78,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    result.score.toStringAsFixed(0),
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      color: colors.primary,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  Text(tr(context, BenchmarkHistoryKeys.score)),
                ],
              ),
            ),
            IconButton(
              tooltip: tr(context, BenchmarkHistoryKeys.viewDetails),
              onPressed: onOpen,
              icon: const Icon(Icons.open_in_new_rounded),
            ),
            IconButton(
              tooltip: tr(context, BenchmarkHistoryKeys.delete),
              onPressed: onDelete,
              icon: const Icon(Icons.delete_outline_rounded),
            ),
          ],
        ),
      ),
    );
  }
}

class _ToolbarButton extends StatelessWidget {
  final IconData icon;
  final String label;

  const _ToolbarButton({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 13),
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).colorScheme.outline),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18),
          const SizedBox(width: 8),
          Text(label),
          const SizedBox(width: 4),
          const Icon(Icons.arrow_drop_down_rounded),
        ],
      ),
    );
  }
}

class _MessageState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? action;

  const _MessageState({
    required this.icon,
    required this.title,
    this.subtitle,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 44, color: colors.onSurfaceVariant),
            const SizedBox(height: 12),
            Text(
              title,
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 6),
              Text(
                subtitle!,
                textAlign: TextAlign.center,
                style: TextStyle(color: colors.onSurfaceVariant),
              ),
            ],
            if (action != null) ...[const SizedBox(height: 12), action!],
          ],
        ),
      ),
    );
  }
}

DateTime _endOfDay(DateTime date) => DateTime(
  date.year,
  date.month,
  date.day + 1,
).subtract(const Duration(microseconds: 1));

String _available(BuildContext context, String value) {
  final normalized = value.trim();
  return normalized.isEmpty || normalized.toUpperCase() == 'N/A'
      ? tr(context, BenchmarkHistoryKeys.unknown)
      : normalized;
}
