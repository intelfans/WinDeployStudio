import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;

import '../../../core/localization/strings.dart';
import '../../benchmark/models/benchmark_models.dart';
import '../benchmark_history_copy.dart';
import '../models/benchmark_history_models.dart';
import '../services/benchmark_history_service.dart';
import 'benchmark_comparison_screen.dart';
import 'benchmark_history_detail_screen.dart';

enum _ExportFormat { csv, json, html }

enum _DeleteTarget { range, all }

final RegExp _invalidFileNameCharacters = RegExp(r'[<>:"/\\|?*\x00-\x1F]');

String _safeFileComponent(String value, {required String fallback}) {
  final sanitized = value
      .replaceAll(_invalidFileNameCharacters, '_')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim()
      .replaceFirst(RegExp(r'[. ]+$'), '');
  if (sanitized.isEmpty) return fallback;
  return sanitized.length <= 48 ? sanitized : sanitized.substring(0, 48);
}

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
    var selected = _selectedRecordIds();
    if (selected.isEmpty) {
      final picked = await _pickRecordsForExport();
      if (!mounted || picked == null || picked.isEmpty) return;
      selected = picked;
    }
    final selectedRecords = _records
        .where((record) => selected.contains(record.id))
        .toList(growable: false);
    if (selectedRecords.isEmpty) return;
    final extension = format.name;
    final titleKey = switch (format) {
      _ExportFormat.csv => BenchmarkHistoryKeys.exportCsv,
      _ExportFormat.json => BenchmarkHistoryKeys.exportJson,
      _ExportFormat.html => BenchmarkHistoryKeys.exportHtml,
    };
    final localeCode = localeCodeFromLocale(Localizations.localeOf(context));

    if (selectedRecords.length == 1) {
      final destination = await FilePicker.saveFile(
        dialogTitle: tr(context, titleKey),
        fileName: _exportFileName(selectedRecords.single, extension),
        type: FileType.custom,
        allowedExtensions: [extension],
      );
      if (destination == null || !mounted) return;
      await _runAction(() async {
        await _writeExport(
          format: format,
          destination: destination,
          recordId: selectedRecords.single.id,
          localeCode: localeCode,
        );
        if (mounted) _showMessage(BenchmarkHistoryKeys.exportComplete);
        return null;
      }, reload: false);
      return;
    }

    final directory = await FilePicker.getDirectoryPath(
      dialogTitle: tr(context, titleKey),
    );
    if (directory == null || !mounted) return;
    await _runAction(() async {
      for (final record in selectedRecords) {
        final destination = await _uniqueExportPath(
          directory,
          _exportFileName(record, extension),
        );
        await _writeExport(
          format: format,
          destination: destination,
          recordId: record.id,
          localeCode: localeCode,
        );
      }
      if (mounted) _showMessage(BenchmarkHistoryKeys.exportComplete);
      return null;
    }, reload: false);
  }

  Future<void> _writeExport({
    required _ExportFormat format,
    required String destination,
    required String recordId,
    required String localeCode,
  }) async {
    switch (format) {
      case _ExportFormat.csv:
        await _service.exportCsv(destination, ids: [recordId]);
      case _ExportFormat.json:
        await _service.exportJson(destination, ids: [recordId]);
      case _ExportFormat.html:
        await _service.exportHtml(
          destination,
          ids: [recordId],
          localeCode: localeCode,
        );
    }
  }

  String _exportFileName(BenchmarkHistoryRecord record, String extension) {
    final result = record.result;
    final deviceName = result.device.friendlyName.trim().isNotEmpty
        ? result.device.friendlyName
        : result.device.model;
    final timestamp = DateFormat('yyyyMMdd_HHmmss').format(result.completedAt);
    final device = _safeFileComponent(deviceName, fallback: 'disk');
    final id = _safeFileComponent(record.id, fallback: 'record');
    return 'WinDeployStudio_Benchmark_${timestamp}_${device}_$id.$extension';
  }

  Future<String> _uniqueExportPath(String directory, String fileName) async {
    final extension = p.extension(fileName);
    final stem = p.basenameWithoutExtension(fileName);
    var candidate = p.join(directory, fileName);
    var suffix = 2;
    while (await File(candidate).exists()) {
      candidate = p.join(directory, '$stem-$suffix$extension');
      suffix++;
    }
    return candidate;
  }

  List<String> _selectedRecordIds() {
    return _records
        .where((record) => _selectedIds.contains(record.id))
        .map((record) => record.id)
        .toList(growable: false);
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

  Future<void> _deleteSelected() async {
    final ids = _selectedRecordIds();
    if (ids.isEmpty) return;
    final confirmed = await _confirm(
      titleKey: BenchmarkHistoryKeys.deleteSelectedTitle,
      bodyKey: BenchmarkHistoryKeys.deleteSelectedBody,
    );
    if (confirmed != true) return;
    await _runAction(() async {
      final deleted = await _service.deleteMany(ids);
      _selectedIds.removeAll(ids);
      return deleted;
    });
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
    setState(() => _selectedIds.add(record.id));
  }

  Future<void> _compareSelected() async {
    if (_records.length < 2) {
      _showMessage(BenchmarkHistoryKeys.selectTwo, isError: true);
      return;
    }
    final currentSelection = _selectedRecordIds();
    final selectedIds = currentSelection.length == 2
        ? currentSelection
        : await _pickRecordsForComparison();
    if (!mounted || selectedIds == null || selectedIds.length != 2) return;
    await _openComparison(selectedIds);
  }

  Future<void> _openComparison(List<String> selectedIds) async {
    final selected =
        selectedIds
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
    } on BenchmarkComparisonException {
      _showMessage(BenchmarkHistoryKeys.actionFailed, isError: true);
    }
  }

  Future<List<String>?> _pickRecordsForComparison() {
    final currentSelection = _selectedRecordIds();
    final initial = currentSelection.length == 1
        ? currentSelection
        : const <String>[];
    return showDialog<List<String>>(
      context: context,
      builder: (_) => _HistoryRecordSelectionDialog(
        records: _records,
        initialSelection: initial,
        minSelection: 2,
        maxSelection: 2,
        titleKey: BenchmarkHistoryKeys.comparisonSelectTitle,
        hintKey: BenchmarkHistoryKeys.comparisonSelectHint,
        countKey: BenchmarkHistoryKeys.comparisonSelectionCount,
        confirmKey: BenchmarkHistoryKeys.compare,
        confirmIcon: Icons.compare_arrows_rounded,
      ),
    );
  }

  Future<List<String>?> _pickRecordsForExport() {
    return showDialog<List<String>>(
      context: context,
      builder: (_) => _HistoryRecordSelectionDialog(
        records: _records,
        initialSelection: const <String>[],
        minSelection: 1,
        titleKey: BenchmarkHistoryKeys.export,
        countKey: BenchmarkHistoryKeys.selected,
        confirmKey: BenchmarkHistoryKeys.export,
        confirmIcon: Icons.download_rounded,
      ),
    );
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
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 1120;
          final description = Column(
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
          );
          final actions = _buildToolbarActions(
            context,
            dateText,
            scrollable: compact,
          );
          return Padding(
            padding: const EdgeInsets.fromLTRB(24, 14, 24, 14),
            child: compact
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      description,
                      const SizedBox(height: 12),
                      actions,
                    ],
                  )
                : Row(
                    children: [
                      Expanded(child: description),
                      const SizedBox(width: 12),
                      actions,
                    ],
                  ),
          );
        },
      ),
    );
  }

  Widget _buildToolbarActions(
    BuildContext context,
    String dateText, {
    required bool scrollable,
  }) {
    final actionRow = Row(
      key: const ValueKey('benchmark-history-toolbar-actions'),
      mainAxisSize: MainAxisSize.min,
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
          onPressed: _records.length >= 2 && !_working
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
                title: Text(tr(context, BenchmarkHistoryKeys.exportCsv)),
                contentPadding: EdgeInsets.zero,
              ),
            ),
            PopupMenuItem(
              value: _ExportFormat.json,
              child: ListTile(
                leading: const Icon(Icons.data_object_rounded),
                title: Text(tr(context, BenchmarkHistoryKeys.exportJson)),
                contentPadding: EdgeInsets.zero,
              ),
            ),
            PopupMenuItem(
              value: _ExportFormat.html,
              child: ListTile(
                leading: const Icon(Icons.stacked_line_chart_rounded),
                title: Text(tr(context, BenchmarkHistoryKeys.exportHtml)),
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
        _buildDeleteControls(context),
      ],
    );
    if (!scrollable) return actionRow;
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        reverse: true,
        child: ConstrainedBox(
          constraints: BoxConstraints(minWidth: constraints.maxWidth),
          child: Align(alignment: Alignment.centerRight, child: actionRow),
        ),
      ),
    );
  }

  Widget _buildDeleteControls(BuildContext context) {
    final enabled = !_working && _records.isNotEmpty;
    if (_selectedRecordIds().isNotEmpty) {
      return FilledButton.icon(
        onPressed: enabled ? _deleteSelected : null,
        icon: const Icon(Icons.delete_outline_rounded),
        label: Text(tr(context, BenchmarkHistoryKeys.delete)),
      );
    }
    return PopupMenuButton<_DeleteTarget>(
      tooltip: tr(context, BenchmarkHistoryKeys.delete),
      enabled: enabled,
      onSelected: (target) async {
        switch (target) {
          case _DeleteTarget.range:
            await _deleteRange();
          case _DeleteTarget.all:
            await _deleteAll();
        }
      },
      itemBuilder: (context) => [
        PopupMenuItem(
          value: _DeleteTarget.range,
          child: ListTile(
            leading: const Icon(Icons.date_range_rounded),
            title: Text(tr(context, BenchmarkHistoryKeys.deleteRange)),
            contentPadding: EdgeInsets.zero,
          ),
        ),
        PopupMenuItem(
          value: _DeleteTarget.all,
          child: ListTile(
            leading: const Icon(Icons.delete_sweep_rounded),
            title: Text(tr(context, BenchmarkHistoryKeys.deleteAll)),
            contentPadding: EdgeInsets.zero,
          ),
        ),
      ],
      child: _ToolbarButton(
        icon: Icons.delete_outline_rounded,
        label: tr(context, BenchmarkHistoryKeys.delete),
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

class _HistoryRecordSelectionDialog extends StatefulWidget {
  final List<BenchmarkHistoryRecord> records;
  final List<String> initialSelection;
  final int minSelection;
  final int? maxSelection;
  final String titleKey;
  final String? hintKey;
  final String countKey;
  final String confirmKey;
  final IconData confirmIcon;

  const _HistoryRecordSelectionDialog({
    required this.records,
    required this.initialSelection,
    required this.minSelection,
    this.maxSelection,
    required this.titleKey,
    this.hintKey,
    required this.countKey,
    required this.confirmKey,
    required this.confirmIcon,
  }) : assert(minSelection > 0),
       assert(maxSelection == null || maxSelection >= minSelection);

  @override
  State<_HistoryRecordSelectionDialog> createState() =>
      _HistoryRecordSelectionDialogState();
}

class _HistoryRecordSelectionDialogState
    extends State<_HistoryRecordSelectionDialog> {
  late final Set<String> _selectedIds;

  @override
  void initState() {
    super.initState();
    final validIds = widget.records.map((record) => record.id).toSet();
    final initial = widget.initialSelection.where(validIds.contains);
    _selectedIds =
        (widget.maxSelection == null
                ? initial
                : initial.take(widget.maxSelection!))
            .toSet();
  }

  void _toggle(String id, bool selected) {
    setState(() {
      if (selected) {
        if (widget.maxSelection == null ||
            _selectedIds.length < widget.maxSelection!) {
          _selectedIds.add(id);
        }
      } else {
        _selectedIds.remove(id);
      }
    });
  }

  List<String> _selectionInRecordOrder() {
    return widget.records
        .where((record) => _selectedIds.contains(record.id))
        .map((record) => record.id)
        .toList(growable: false);
  }

  bool get _canConfirm {
    return _selectedIds.length >= widget.minSelection &&
        (widget.maxSelection == null ||
            _selectedIds.length <= widget.maxSelection!);
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final media = MediaQuery.sizeOf(context);
    final count = widget.maxSelection == null
        ? '${_selectedIds.length} ${tr(context, widget.countKey)}'
        : '${_selectedIds.length}/${widget.maxSelection} '
              '${tr(context, widget.countKey)}';
    return AlertDialog(
      title: Text(tr(context, widget.titleKey)),
      content: SizedBox(
        width: media.width.clamp(320, 720).toDouble(),
        height: (media.height * .62).clamp(280, 560).toDouble(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (widget.hintKey != null) ...[
              Text(
                tr(context, widget.hintKey!),
                style: TextStyle(color: colors.onSurfaceVariant),
              ),
              const SizedBox(height: 8),
            ],
            Text(
              count,
              style: TextStyle(
                color: _canConfirm ? colors.primary : colors.onSurfaceVariant,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: ListView.separated(
                itemCount: widget.records.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final record = widget.records[index];
                  final result = record.result;
                  final title = result.device.friendlyName.isEmpty
                      ? result.device.model
                      : result.device.friendlyName;
                  final serial = result.device.serialNumber.trim();
                  final identity = serial.isEmpty || serial == 'N/A'
                      ? result.device.uniqueId
                      : serial;
                  final checked = _selectedIds.contains(record.id);
                  final atLimit =
                      !checked &&
                      widget.maxSelection != null &&
                      _selectedIds.length >= widget.maxSelection!;
                  return CheckboxListTile(
                    value: checked,
                    onChanged: atLimit
                        ? null
                        : (value) => _toggle(record.id, value ?? false),
                    title: Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(
                      '${DateFormat.yMd().add_Hm().format(result.completedAt)}  |  '
                      '${tr(context, result.mode.titleKey)}  |  '
                      '${identity.isEmpty ? tr(context, BenchmarkHistoryKeys.unknown) : identity}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    controlAffinity: ListTileControlAffinity.leading,
                    contentPadding: EdgeInsets.zero,
                  );
                },
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(tr(context, BenchmarkHistoryKeys.cancel)),
        ),
        FilledButton.icon(
          onPressed: _canConfirm
              ? () => Navigator.of(context).pop(_selectionInRecordOrder())
              : null,
          icon: Icon(widget.confirmIcon),
          label: Text(tr(context, widget.confirmKey)),
        ),
      ],
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
