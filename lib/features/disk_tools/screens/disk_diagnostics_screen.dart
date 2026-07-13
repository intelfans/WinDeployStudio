import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/typography.dart';
import '../localization/disk_tools_localization.dart';
import '../models/disk_diagnostic_models.dart';
import '../services/secure_powershell_runner.dart';
import '../services/windows_disk_diagnostics_service.dart';

class DiskDiagnosticsScreen extends ConsumerStatefulWidget {
  const DiskDiagnosticsScreen({super.key});

  @override
  ConsumerState<DiskDiagnosticsScreen> createState() =>
      _DiskDiagnosticsScreenState();
}

class _DiskDiagnosticsScreenState extends ConsumerState<DiskDiagnosticsScreen> {
  DiskDiagnosticsSnapshot? _snapshot;
  int? _selectedDiskNumber;
  bool _loading = true;
  String? _errorKey;
  DiskToolsCancellationToken? _collectionCancellation;

  @override
  void initState() {
    super.initState();
    _collect();
  }

  @override
  void dispose() {
    _collectionCancellation?.cancel();
    super.dispose();
  }

  Future<void> _collect() async {
    final cancellationToken = DiskToolsCancellationToken();
    _collectionCancellation?.cancel();
    _collectionCancellation = cancellationToken;
    setState(() {
      _loading = true;
      _errorKey = null;
    });
    try {
      final snapshot = await ref
          .read(windowsDiskDiagnosticsServiceProvider)
          .collect(cancellationToken: cancellationToken);
      if (!mounted || !identical(_collectionCancellation, cancellationToken)) {
        return;
      }
      final selectedStillExists = snapshot.reports.any(
        (report) => report.diskNumber == _selectedDiskNumber,
      );
      setState(() {
        _snapshot = snapshot;
        if (!selectedStillExists) {
          _selectedDiskNumber = snapshot.reports.isEmpty
              ? null
              : snapshot.reports.first.diskNumber;
        }
        _loading = false;
      });
    } on DiskDiagnosticsException catch (error) {
      if (!mounted || !identical(_collectionCancellation, cancellationToken)) {
        return;
      }
      setState(() {
        _loading = false;
        _errorKey = error.localizationKey;
      });
    } catch (_) {
      if (!mounted || !identical(_collectionCancellation, cancellationToken)) {
        return;
      }
      setState(() {
        _loading = false;
        _errorKey = 'disk_diag_error';
      });
    } finally {
      if (identical(_collectionCancellation, cancellationToken)) {
        _collectionCancellation = null;
      }
    }
  }

  void _cancelCollection() {
    _collectionCancellation?.cancel();
  }

  DiskDiagnosticReport? get _selectedReport {
    final reports = _snapshot?.reports ?? const <DiskDiagnosticReport>[];
    for (final report in reports) {
      if (report.diskNumber == _selectedDiskNumber) return report;
    }
    return reports.isEmpty ? null : reports.first;
  }

  Future<void> _copyReport() async {
    final report = _selectedReport;
    if (report == null) return;
    await Clipboard.setData(ClipboardData(text: report.toPlainText()));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(diskToolsText(context, 'disk_diag_report_copied')),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final warnings = _snapshot?.collectionWarnings ?? const <String>[];
    return Scaffold(
      appBar: AppBar(
        title: Text(diskToolsText(context, 'disk_diag_title')),
        actions: [
          if (_loading)
            Tooltip(
              message: diskToolsText(context, 'disk_tools_cancel'),
              child: IconButton(
                onPressed: _cancelCollection,
                icon: const Icon(Icons.stop_circle_outlined),
              ),
            ),
          Tooltip(
            message: diskToolsText(context, 'disk_tools_refresh'),
            child: IconButton(
              onPressed: _loading ? null : _collect,
              icon: const Icon(Icons.refresh_rounded),
            ),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(
        children: [
          if (_loading) const LinearProgressIndicator(minHeight: 2),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1180),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        diskToolsText(context, 'disk_diag_subtitle'),
                        style: AppTypography.bodyWith(colors.onSurfaceVariant),
                      ),
                      const SizedBox(height: 16),
                      if (warnings.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        _InlineMessage(
                          icon: Icons.info_outline_rounded,
                          text: warnings
                              .map((code) => diskToolsText(context, code))
                              .join('\n'),
                          color: colors.onSurfaceVariant,
                        ),
                      ],
                      const SizedBox(height: 20),
                      if (_loading && _snapshot == null)
                        _CenteredStatus(
                          icon: Icons.manage_search_rounded,
                          text: diskToolsText(context, 'disk_diag_collecting'),
                          showProgress: true,
                        )
                      else if (_errorKey != null && _snapshot == null)
                        _ErrorStatus(
                          message: diskToolsText(context, _errorKey!),
                          onRetry: _collect,
                        )
                      else if (_snapshot?.reports.isEmpty ?? true)
                        _CenteredStatus(
                          icon: Icons.storage_rounded,
                          text: diskToolsText(context, 'disk_diag_no_disks'),
                        )
                      else ...[
                        _DiskSelector(
                          reports: _snapshot!.reports,
                          selectedDiskNumber: _selectedDiskNumber,
                          onSelected: (value) {
                            if (value == null) return;
                            setState(() => _selectedDiskNumber = value);
                          },
                          onCopy: _copyReport,
                        ),
                        if (_errorKey != null) ...[
                          const SizedBox(height: 12),
                          _InlineMessage(
                            icon: Icons.warning_amber_rounded,
                            text: diskToolsText(context, _errorKey!),
                            color: colors.error,
                          ),
                        ],
                        const SizedBox(height: 16),
                        if (_selectedReport case final report?)
                          _DiagnosticReportView(report: report),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DiskSelector extends StatelessWidget {
  final List<DiskDiagnosticReport> reports;
  final int? selectedDiskNumber;
  final ValueChanged<int?> onSelected;
  final VoidCallback onCopy;

  const _DiskSelector({
    required this.reports,
    required this.selectedDiskNumber,
    required this.onSelected,
    required this.onCopy,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final selector = DropdownButtonFormField<int>(
          initialValue: selectedDiskNumber,
          isExpanded: true,
          decoration: InputDecoration(
            labelText: diskToolsText(context, 'disk_diag_select_disk'),
            prefixIcon: const Icon(Icons.storage_rounded),
          ),
          items: [
            for (final report in reports)
              DropdownMenuItem(
                value: report.diskNumber,
                child: Text(
                  '${report.diskNumber}: ${report.displayName}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
          onChanged: onSelected,
        );
        final copy = OutlinedButton.icon(
          onPressed: onCopy,
          icon: const Icon(Icons.copy_rounded),
          label: Text(diskToolsText(context, 'disk_diag_copy_report')),
        );
        if (constraints.maxWidth < 620) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [selector, const SizedBox(height: 12), copy],
          );
        }
        return Row(
          children: [
            Expanded(child: selector),
            const SizedBox(width: 12),
            copy,
          ],
        );
      },
    );
  }
}

class _DiagnosticReportView extends StatelessWidget {
  final DiskDiagnosticReport report;

  const _DiagnosticReportView({required this.report});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final healthKnown = report.health.isAvailable;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: colors.primaryContainer,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    Icons.storage_rounded,
                    color: colors.onPrimaryContainer,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        report.displayName,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 3),
                      Text(
                        _headerSubtitle(context, report),
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                if (report.hasKnownConnectionClassification)
                  _StatusChip(
                    label: diskToolsText(
                      context,
                      report.isExternal
                          ? 'disk_diag_external'
                          : 'disk_diag_internal',
                    ),
                    icon: report.isExternal
                        ? Icons.usb_rounded
                        : Icons.computer_rounded,
                  ),
                if (report.isSystemDisk || report.isBootDisk) ...[
                  const SizedBox(width: 8),
                  _StatusChip(
                    label: diskToolsText(context, 'disk_diag_system'),
                    icon: Icons.window_rounded,
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        if (!healthKnown) ...[
          _InlineMessage(
            icon: Icons.help_outline_rounded,
            text: diskToolsText(context, 'disk_diag_health_unknown_note'),
            color: colors.onSurfaceVariant,
          ),
          const SizedBox(height: 12),
        ],
        _InlineMessage(
          icon: Icons.data_object_rounded,
          text: diskToolsText(context, 'disk_diag_unavailable_note'),
          color: colors.primary,
        ),
        const SizedBox(height: 16),
        _ResponsiveSections(
          sections: [
            _DiagnosticSection(
              titleKey: 'disk_diag_section_identity',
              icon: Icons.fingerprint_rounded,
              rows: [
                _textRow('disk_diag_model', report.model),
                _bigIntRow(
                  'disk_diag_capacity',
                  report.sizeBytes,
                  formatDiagnosticBytes,
                ),
                _textRow('disk_diag_serial', report.serialNumber),
                _textRow('disk_diag_unique_id', report.uniqueId),
                _textRow('disk_diag_bus', report.busType),
                _textRow('disk_diag_vid', report.vendorId),
                _textRow('disk_diag_pid', report.productId),
                _textRow('disk_diag_firmware', report.firmwareVersion),
                _textRow('disk_diag_media_type', report.mediaType),
              ],
            ),
            _DiagnosticSection(
              titleKey: 'disk_diag_section_health',
              icon: Icons.monitor_heart_rounded,
              rows: [
                _textRow('disk_diag_health', report.health),
                _intRow(
                  'disk_diag_temperature',
                  report.temperatureCelsius,
                  (value) => '$value °C',
                ),
                _intRow(
                  'disk_diag_remaining_life',
                  report.estimatedRemainingLifePercent,
                  (value) => '$value%',
                  noteKey: 'disk_diag_remaining_life_note',
                ),
                _intRow(
                  'disk_diag_wear',
                  report.wearPercent,
                  (value) => '$value%',
                ),
                _bigIntRow(
                  'disk_diag_read_errors_corrected',
                  report.readErrorsCorrected,
                  formatDiagnosticInteger,
                ),
                _bigIntRow(
                  'disk_diag_read_errors_uncorrected',
                  report.readErrorsUncorrected,
                  formatDiagnosticInteger,
                ),
                _bigIntRow(
                  'disk_diag_read_errors_total',
                  report.readErrorsTotal,
                  formatDiagnosticInteger,
                ),
                _bigIntRow(
                  'disk_diag_write_errors_corrected',
                  report.writeErrorsCorrected,
                  formatDiagnosticInteger,
                ),
                _bigIntRow(
                  'disk_diag_write_errors_uncorrected',
                  report.writeErrorsUncorrected,
                  formatDiagnosticInteger,
                ),
                _bigIntRow(
                  'disk_diag_write_errors_total',
                  report.writeErrorsTotal,
                  formatDiagnosticInteger,
                ),
              ],
            ),
            _DiagnosticSection(
              titleKey: 'disk_diag_section_lifetime',
              icon: Icons.timelapse_rounded,
              rows: [
                _bigIntRow(
                  'disk_diag_power_on_hours',
                  report.powerOnHours,
                  formatDiagnosticHours,
                ),
                _bigIntRow(
                  'disk_diag_host_reads',
                  report.hostReadBytes,
                  formatDiagnosticBytes,
                ),
                _bigIntRow(
                  'disk_diag_host_writes',
                  report.hostWrittenBytes,
                  formatDiagnosticBytes,
                ),
                _bigIntRow(
                  'disk_diag_host_read_commands',
                  report.hostReadCommands,
                  formatDiagnosticInteger,
                ),
                _bigIntRow(
                  'disk_diag_host_write_commands',
                  report.hostWriteCommands,
                  formatDiagnosticInteger,
                ),
                _bigIntRow(
                  'disk_diag_media_errors',
                  report.mediaAndDataIntegrityErrors,
                  formatDiagnosticInteger,
                ),
              ],
            ),
            _DiagnosticSection(
              titleKey: 'disk_diag_section_topology',
              icon: Icons.account_tree_rounded,
              rows: [
                _textRow('disk_diag_partition_style', report.partitionStyle),
                _textRow(
                  'disk_diag_operational_status',
                  report.operationalStatus,
                ),
                _DiagnosticRowData(
                  labelKey: 'disk_diag_mounts',
                  value: report.driveLetters.isEmpty
                      ? diskToolsText(context, 'disk_tools_value_none')
                      : report.driveLetters.join(', '),
                  available: true,
                  sourceKey: 'disk_diag_source_cim',
                ),
                _textRow('disk_diag_pnp_id', report.pnpDeviceId),
                _textRow('disk_diag_device_path', report.devicePath),
                _boolRow('disk_diag_system_disk', report.isSystem),
                _boolRow('disk_diag_boot_disk', report.isBoot),
                _boolRow('disk_diag_offline', report.isOffline),
                _boolRow('disk_diag_read_only', report.isReadOnly),
                _boolRow('disk_diag_removable', report.isRemovable),
              ],
            ),
          ],
        ),
      ],
    );
  }

  String _headerSubtitle(BuildContext context, DiskDiagnosticReport report) {
    final parts = <String>['Disk ${report.diskNumber}'];
    final size = report.sizeBytes.value;
    if (size != null) parts.add(formatDiagnosticBytes(size).split(' (').first);
    final bus = report.busType.value;
    if (bus != null) parts.add(bus);
    return parts.join(' • ');
  }

  static _DiagnosticRowData _textRow(
    String key,
    DiagnosticValue<String> field,
  ) {
    if (key == 'disk_diag_health') {
      final statusKey = _healthStatusKey(field.value);
      return _DiagnosticRowData(
        labelKey: key,
        value: statusKey ?? field.value,
        valueIsKey: statusKey != null,
        available: field.isAvailable,
        sourceKey: _sourceKey(field.source),
        unavailableReasonKey: _unavailableReasonKey(field),
      );
    }
    return _DiagnosticRowData(
      labelKey: key,
      value: field.value,
      available: field.isAvailable,
      sourceKey: _sourceKey(field.source),
      unavailableReasonKey: _unavailableReasonKey(field),
    );
  }

  static _DiagnosticRowData _intRow(
    String key,
    DiagnosticValue<int> field,
    String Function(int) formatter, {
    String? noteKey,
  }) {
    return _DiagnosticRowData(
      labelKey: key,
      value: field.value == null ? null : formatter(field.value!),
      available: field.isAvailable,
      sourceKey: _sourceKey(field.source),
      noteKey: noteKey,
      unavailableReasonKey: _unavailableReasonKey(field),
    );
  }

  static _DiagnosticRowData _bigIntRow(
    String key,
    DiagnosticValue<BigInt> field,
    String Function(BigInt) formatter,
  ) {
    return _DiagnosticRowData(
      labelKey: key,
      value: field.value == null ? null : formatter(field.value!),
      available: field.isAvailable,
      sourceKey: _sourceKey(field.source),
      unavailableReasonKey: _unavailableReasonKey(field),
    );
  }

  static _DiagnosticRowData _boolRow(String key, DiagnosticValue<bool> field) {
    return _DiagnosticRowData(
      labelKey: key,
      value: field.value == true ? 'disk_tools_yes' : 'disk_tools_no',
      valueIsKey: true,
      available: field.isAvailable,
      sourceKey: _sourceKey(field.source),
      unavailableReasonKey: _unavailableReasonKey(field),
    );
  }

  static String? _unavailableReasonKey<T>(DiagnosticValue<T> field) {
    return field.isAvailable
        ? null
        : field.unavailableReasonKind?.localizationKey;
  }

  static String _sourceKey(String source) {
    final normalized = source.toLowerCase();
    if (normalized.contains('intel rst')) {
      return 'disk_diag_source_intel_rst';
    }
    if (normalized.contains('intel vroc')) {
      return 'disk_diag_source_intel_vroc';
    }
    if (normalized.contains('smart failure')) {
      return 'disk_diag_source_smart_prediction';
    }
    if (normalized.contains('ata smart') ||
        normalized.contains('sat pass-through')) {
      return 'disk_diag_source_ata_smart';
    }
    if (normalized.contains('calculated')) {
      return 'disk_diag_source_calculated';
    }
    if (normalized.contains('nvme')) return 'disk_diag_source_nvme';
    if (normalized.contains('reliability')) {
      return 'disk_diag_source_reliability';
    }
    if (normalized.contains('native')) return 'disk_diag_source_native';
    return 'disk_diag_source_cim';
  }

  static String? _healthStatusKey(String? value) {
    return switch (value?.trim().toLowerCase()) {
      'healthy' => 'disk_diag_health_healthy',
      'warning' => 'disk_diag_health_warning',
      'no_failure_predicted' ||
      'no failure predicted' => 'disk_diag_health_no_failure_predicted',
      'failure_predicted' ||
      'failure predicted' => 'disk_diag_health_failure_predicted',
      _ => null,
    };
  }
}

class _ResponsiveSections extends StatelessWidget {
  final List<_DiagnosticSection> sections;

  const _ResponsiveSections({required this.sections});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 920 ? 2 : 1;
        final width = columns == 1
            ? constraints.maxWidth
            : (constraints.maxWidth - 16) / 2;
        return Wrap(
          spacing: 16,
          runSpacing: 16,
          children: [
            for (final section in sections)
              SizedBox(width: width, child: section),
          ],
        );
      },
    );
  }
}

class _DiagnosticSection extends StatelessWidget {
  final String titleKey;
  final IconData icon;
  final List<_DiagnosticRowData> rows;

  const _DiagnosticSection({
    required this.titleKey,
    required this.icon,
    required this.rows,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 20, color: colors.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    diskToolsText(context, titleKey),
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            for (var index = 0; index < rows.length; index++) ...[
              _DiagnosticRow(data: rows[index]),
              if (index != rows.length - 1) const Divider(height: 20),
            ],
          ],
        ),
      ),
    );
  }
}

class _DiagnosticRowData {
  final String labelKey;
  final String? value;
  final bool valueIsKey;
  final bool available;
  final String sourceKey;
  final String? noteKey;
  final String? unavailableReasonKey;

  const _DiagnosticRowData({
    required this.labelKey,
    required this.value,
    this.valueIsKey = false,
    required this.available,
    required this.sourceKey,
    this.noteKey,
    this.unavailableReasonKey,
  });
}

class _DiagnosticRow extends StatelessWidget {
  final _DiagnosticRowData data;

  const _DiagnosticRow({required this.data});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final value = data.available
        ? data.valueIsKey
              ? diskToolsText(context, data.value!)
              : data.value!
        : diskToolsText(context, 'disk_tools_value_unknown');
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          flex: 4,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                diskToolsText(context, data.labelKey),
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              if (data.noteKey != null)
                Text(
                  diskToolsText(context, data.noteKey!),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          flex: 5,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              SelectableText(
                value,
                textAlign: TextAlign.end,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: data.available
                      ? colors.onSurface
                      : colors.onSurfaceVariant,
                ),
              ),
              if (data.available)
                Text(
                  diskToolsText(context, data.sourceKey),
                  textAlign: TextAlign.end,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                )
              else if (data.unavailableReasonKey != null)
                Text(
                  diskToolsText(context, data.unavailableReasonKey!),
                  textAlign: TextAlign.end,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _StatusChip extends StatelessWidget {
  final String label;
  final IconData icon;

  const _StatusChip({required this.label, required this.icon});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: colors.secondaryContainer,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: colors.onSecondaryContainer),
          const SizedBox(width: 6),
          Text(
            label,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: colors.onSecondaryContainer,
            ),
          ),
        ],
      ),
    );
  }
}

class _InlineMessage extends StatelessWidget {
  final IconData icon;
  final String text;
  final Color color;

  const _InlineMessage({
    required this.icon,
    required this.text,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.28)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 20, color: color),
          const SizedBox(width: 10),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }
}

class _CenteredStatus extends StatelessWidget {
  final IconData icon;
  final String text;
  final bool showProgress;

  const _CenteredStatus({
    required this.icon,
    required this.text,
    this.showProgress = false,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 72),
      child: Center(
        child: Column(
          children: [
            if (showProgress)
              const SizedBox(
                width: 40,
                height: 40,
                child: CircularProgressIndicator(),
              )
            else
              Icon(icon, size: 48, color: colors.onSurfaceVariant),
            const SizedBox(height: 16),
            Text(text, textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}

class _ErrorStatus extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _ErrorStatus({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _CenteredStatus(icon: Icons.error_outline_rounded, text: message),
        FilledButton.icon(
          onPressed: onRetry,
          icon: const Icon(Icons.refresh_rounded),
          label: Text(diskToolsText(context, 'disk_tools_refresh')),
        ),
      ],
    );
  }
}
