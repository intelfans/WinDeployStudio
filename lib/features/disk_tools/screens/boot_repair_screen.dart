import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/typography.dart';
import '../localization/disk_tools_localization.dart';
import '../models/boot_repair_models.dart';
import '../models/disk_diagnostic_models.dart';
import '../services/secure_powershell_runner.dart';
import '../services/windows_boot_repair_service.dart';

class BootRepairScreen extends ConsumerStatefulWidget {
  const BootRepairScreen({super.key});

  @override
  ConsumerState<BootRepairScreen> createState() => _BootRepairScreenState();
}

class _BootRepairScreenState extends ConsumerState<BootRepairScreen> {
  List<ExternalWindowsVolume> _volumes = const [];
  ExternalWindowsVolume? _selectedWindowsVolume;
  BootTargetVolume? _selectedTarget;
  BootFirmware _firmware = BootFirmware.uefi;
  BootRepairPreflight? _preflight;
  BootRepairResult? _result;
  String? _errorKey;
  bool _loading = true;
  bool _runningPreflight = false;
  bool _executing = false;
  bool _cancelling = false;
  DiskToolsCancellationToken? _executionCancellation;

  @override
  void initState() {
    super.initState();
    _discover();
  }

  @override
  void dispose() {
    _executionCancellation?.cancel();
    super.dispose();
  }

  List<BootTargetVolume> get _compatibleTargets {
    final source = _selectedWindowsVolume;
    if (source == null) return const [];
    return source.bootTargets
        .where((target) => target.supports(_firmware))
        .toList(growable: false);
  }

  Future<void> _discover() async {
    setState(() {
      _loading = true;
      _errorKey = null;
      _preflight = null;
      _result = null;
    });
    try {
      final volumes = await ref
          .read(windowsBootRepairServiceProvider)
          .discoverWindowsVolumes();
      if (!mounted) return;
      final previousGuid = _selectedWindowsVolume?.volumeGuidPath;
      final selected = volumes.where(
        (volume) => volume.volumeGuidPath == previousGuid,
      );
      setState(() {
        _volumes = volumes;
        _selectedWindowsVolume = selected.isNotEmpty
            ? selected.first
            : volumes.isEmpty
            ? null
            : volumes.first;
        _loading = false;
        _syncTarget();
      });
    } on BootRepairException catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _errorKey = error.messageKey;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _errorKey = 'boot_repair_error_discovery';
      });
    }
  }

  void _syncTarget() {
    final targets = _compatibleTargets;
    final selectedStillExists = targets.any(
      (target) =>
          target.partitionOffset == _selectedTarget?.partitionOffset &&
          target.volumeGuidPath == _selectedTarget?.volumeGuidPath,
    );
    if (!selectedStillExists) {
      _selectedTarget = targets.isEmpty ? null : targets.first;
    }
  }

  void _selectionChanged() {
    _syncTarget();
    _preflight = null;
    _result = null;
    _errorKey = null;
  }

  BootRepairSelection? get _selection {
    final source = _selectedWindowsVolume;
    final target = _selectedTarget;
    if (source == null || target == null) return null;
    return BootRepairSelection(
      windowsVolume: source,
      bootTarget: target,
      firmware: _firmware,
    );
  }

  Future<void> _runPreflight() async {
    final selection = _selection;
    if (selection == null || _runningPreflight || _executing) return;
    setState(() {
      _runningPreflight = true;
      _preflight = null;
      _result = null;
      _errorKey = null;
    });
    try {
      final preflight = await ref
          .read(windowsBootRepairServiceProvider)
          .preflight(selection);
      if (!mounted) return;
      setState(() {
        _preflight = preflight;
        _runningPreflight = false;
      });
    } on BootRepairException catch (error) {
      if (!mounted) return;
      setState(() {
        _runningPreflight = false;
        _errorKey = error.messageKey;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _runningPreflight = false;
        _errorKey = 'boot_repair_error_preflight';
      });
    }
  }

  Future<void> _confirmAndExecute() async {
    final preflight = _preflight;
    if (preflight == null || !preflight.canExecute || _executing) return;
    final reviewed = await _showReviewConfirmation(preflight);
    if (reviewed != true || !mounted) return;
    final typed = await _showTypedConfirmation();
    if (typed != true || !mounted) return;
    await _execute(preflight);
  }

  Future<bool?> _showReviewConfirmation(BootRepairPreflight preflight) {
    final selection = preflight.selection;
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(diskToolsText(context, 'boot_repair_review_title')),
          content: SizedBox(
            width: 620,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    diskToolsTextWith(context, 'boot_repair_review_body', {
                      'disk':
                          '${selection.windowsVolume.disk.snapshotDiskNumber}: '
                          '${selection.windowsVolume.disk.displayName}',
                      'windows': selection.windowsVolume.displayRoot,
                      'target': selection.bootTarget.displayRoot,
                    }),
                  ),
                  const SizedBox(height: 16),
                  _BindingPreview(selection: selection, compact: true),
                  const SizedBox(height: 16),
                  for (final warningKey in preflight.warnings)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: _WarningLine(textKey: warningKey),
                    ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(diskToolsText(context, 'disk_tools_cancel')),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text(diskToolsText(context, 'disk_tools_continue')),
            ),
          ],
        );
      },
    );
  }

  Future<bool?> _showTypedConfirmation() {
    final controller = TextEditingController();
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final matches =
                controller.text.trim().toUpperCase() ==
                diskToolsText(context, 'boot_repair_confirm_word');
            return AlertDialog(
              title: Text(
                diskToolsText(context, 'boot_repair_final_confirm_title'),
              ),
              content: SizedBox(
                width: 480,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      diskToolsText(context, 'boot_repair_final_confirm_body'),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: controller,
                      autofocus: true,
                      autocorrect: false,
                      textCapitalization: TextCapitalization.characters,
                      decoration: InputDecoration(
                        labelText: diskToolsText(
                          context,
                          'boot_repair_confirm_label',
                        ),
                      ),
                      onChanged: (_) => setDialogState(() {}),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(false),
                  child: Text(diskToolsText(context, 'disk_tools_cancel')),
                ),
                FilledButton.icon(
                  onPressed: matches
                      ? () => Navigator.of(dialogContext).pop(true)
                      : null,
                  icon: const Icon(Icons.build_rounded),
                  label: Text(diskToolsText(context, 'boot_repair_execute')),
                ),
              ],
            );
          },
        );
      },
    ).whenComplete(controller.dispose);
  }

  Future<void> _execute(BootRepairPreflight preflight) async {
    final cancellationToken = DiskToolsCancellationToken();
    _executionCancellation = cancellationToken;
    setState(() {
      _executing = true;
      _cancelling = false;
      _result = null;
      _errorKey = null;
    });
    try {
      final result = await ref
          .read(windowsBootRepairServiceProvider)
          .execute(preflight, cancellationToken: cancellationToken);
      if (!mounted) return;
      setState(() {
        _result = result;
      });
    } on BootRepairException catch (error) {
      if (!mounted) return;
      setState(() {
        _errorKey = error.messageKey;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _errorKey = 'boot_repair_error_execution';
      });
    } finally {
      if (identical(_executionCancellation, cancellationToken)) {
        _executionCancellation = null;
      }
      if (mounted) {
        setState(() {
          _executing = false;
          _cancelling = false;
        });
      }
    }
  }

  void _cancelExecution() {
    final cancellation = _executionCancellation;
    if (cancellation == null || cancellation.isCancelled) return;
    cancellation.cancel();
    setState(() => _cancelling = true);
  }

  Future<void> _copyLog(BootRepairResult result) async {
    if (result.logText.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: result.logText));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(diskToolsText(context, 'boot_repair_log_copied'))),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final busy = _loading || _runningPreflight || _executing;
    return Scaffold(
      appBar: AppBar(
        title: Text(diskToolsText(context, 'boot_repair_title')),
        actions: [
          if (_executing)
            Tooltip(
              message: diskToolsText(context, 'disk_tools_cancel'),
              child: IconButton(
                onPressed: _cancelling ? null : _cancelExecution,
                icon: const Icon(Icons.stop_circle_outlined),
              ),
            ),
          Tooltip(
            message: diskToolsText(context, 'disk_tools_refresh'),
            child: IconButton(
              onPressed: busy ? null : _discover,
              icon: const Icon(Icons.refresh_rounded),
            ),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(
        children: [
          if (busy) const LinearProgressIndicator(minHeight: 2),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1040),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        diskToolsText(context, 'boot_repair_subtitle'),
                        style: AppTypography.bodyWith(colors.onSurfaceVariant),
                      ),
                      const SizedBox(height: 16),
                      _NoFormatBanner(),
                      const SizedBox(height: 20),
                      if (_loading)
                        _PageStatus(
                          icon: Icons.search_rounded,
                          textKey: 'boot_repair_loading',
                          progress: true,
                        )
                      else if (_errorKey != null && _volumes.isEmpty)
                        _PageError(errorKey: _errorKey!, onRetry: _discover)
                      else if (_volumes.isEmpty)
                        _EmptyState(onRefresh: _discover)
                      else ...[
                        _SelectionPanel(
                          volumes: _volumes,
                          source: _selectedWindowsVolume,
                          firmware: _firmware,
                          targets: _compatibleTargets,
                          target: _selectedTarget,
                          enabled: !busy,
                          onSourceChanged: (source) {
                            if (source == null) return;
                            setState(() {
                              _selectedWindowsVolume = source;
                              _selectionChanged();
                            });
                          },
                          onFirmwareChanged: (firmware) {
                            setState(() {
                              _firmware = firmware;
                              _selectionChanged();
                            });
                          },
                          onTargetChanged: (target) {
                            if (target == null) return;
                            setState(() {
                              _selectedTarget = target;
                              _preflight = null;
                              _result = null;
                              _errorKey = null;
                            });
                          },
                        ),
                        if (_selection case final selection?) ...[
                          const SizedBox(height: 16),
                          _BindingPreview(selection: selection),
                          const SizedBox(height: 16),
                          Align(
                            alignment: Alignment.centerRight,
                            child: FilledButton.icon(
                              onPressed: busy ? null : _runPreflight,
                              icon: const Icon(Icons.fact_check_rounded),
                              label: Text(
                                diskToolsText(
                                  context,
                                  _runningPreflight
                                      ? 'boot_repair_preflight_running'
                                      : 'boot_repair_run_preflight',
                                ),
                              ),
                            ),
                          ),
                        ],
                        if (_errorKey != null) ...[
                          const SizedBox(height: 16),
                          _MessageBanner(
                            icon: Icons.error_outline_rounded,
                            text: diskToolsText(context, _errorKey!),
                            color: colors.error,
                          ),
                        ],
                        if (_preflight case final preflight?) ...[
                          const SizedBox(height: 20),
                          _PreflightPanel(
                            preflight: preflight,
                            executing: _executing,
                            onExecute: _confirmAndExecute,
                          ),
                        ],
                        if (_executing) ...[
                          const SizedBox(height: 20),
                          _PageStatus(
                            icon: Icons.build_circle_outlined,
                            textKey: 'boot_repair_executing',
                            progress: true,
                          ),
                        ],
                        if (_result case final result?) ...[
                          const SizedBox(height: 20),
                          _ResultPanel(
                            result: result,
                            onOpenLogs: () => ref
                                .read(windowsBootRepairServiceProvider)
                                .openLogFolder(),
                            onCopyLog: () => _copyLog(result),
                          ),
                        ],
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

class _NoFormatBanner extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return _MessageBanner(
      icon: Icons.shield_outlined,
      text: diskToolsText(context, 'boot_repair_warning_no_format'),
      color: colors.primary,
    );
  }
}

class _SelectionPanel extends StatelessWidget {
  final List<ExternalWindowsVolume> volumes;
  final ExternalWindowsVolume? source;
  final BootFirmware firmware;
  final List<BootTargetVolume> targets;
  final BootTargetVolume? target;
  final bool enabled;
  final ValueChanged<ExternalWindowsVolume?> onSourceChanged;
  final ValueChanged<BootFirmware> onFirmwareChanged;
  final ValueChanged<BootTargetVolume?> onTargetChanged;

  const _SelectionPanel({
    required this.volumes,
    required this.source,
    required this.firmware,
    required this.targets,
    required this.target,
    required this.enabled,
    required this.onSourceChanged,
    required this.onFirmwareChanged,
    required this.onTargetChanged,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              diskToolsText(context, 'boot_repair_select_source'),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 14),
            DropdownButtonFormField<ExternalWindowsVolume>(
              initialValue: source,
              isExpanded: true,
              decoration: InputDecoration(
                labelText: diskToolsText(context, 'boot_repair_source_volume'),
                prefixIcon: const Icon(Icons.window_rounded),
              ),
              items: [
                for (final volume in volumes)
                  DropdownMenuItem(
                    value: volume,
                    child: Text(
                      '${volume.displayName} | '
                      '${volume.disk.snapshotDiskNumber}: ${volume.disk.displayName}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
              onChanged: enabled ? onSourceChanged : null,
            ),
            const SizedBox(height: 18),
            Text(
              diskToolsText(context, 'boot_repair_select_firmware'),
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 8),
            SegmentedButton<BootFirmware>(
              segments: [
                ButtonSegment(
                  value: BootFirmware.uefi,
                  icon: const Icon(Icons.memory_rounded),
                  label: Text(
                    diskToolsText(context, 'boot_repair_firmware_uefi'),
                  ),
                ),
                ButtonSegment(
                  value: BootFirmware.bios,
                  icon: const Icon(Icons.settings_input_component_rounded),
                  label: Text(
                    diskToolsText(context, 'boot_repair_firmware_bios'),
                  ),
                ),
              ],
              selected: {firmware},
              onSelectionChanged: enabled
                  ? (selection) => onFirmwareChanged(selection.first)
                  : null,
            ),
            const SizedBox(height: 18),
            if (targets.isEmpty)
              _MessageBanner(
                icon: Icons.warning_amber_rounded,
                text: diskToolsText(
                  context,
                  'boot_repair_no_compatible_target',
                ),
                color: colors.error,
              )
            else
              DropdownButtonFormField<BootTargetVolume>(
                initialValue: target,
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: diskToolsText(
                    context,
                    'boot_repair_target_volume',
                  ),
                  prefixIcon: const Icon(Icons.account_tree_rounded),
                ),
                items: [
                  for (final item in targets)
                    DropdownMenuItem(
                      value: item,
                      child: Text(
                        item.displayName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                onChanged: enabled ? onTargetChanged : null,
              ),
          ],
        ),
      ),
    );
  }
}

class _BindingPreview extends StatelessWidget {
  final BootRepairSelection selection;
  final bool compact;

  const _BindingPreview({required this.selection, this.compact = false});

  @override
  Widget build(BuildContext context) {
    final disk = selection.windowsVolume.disk;
    final rows = <_PreviewRowData>[
      _PreviewRowData(
        labelKey: 'boot_repair_binding_disk',
        value:
            '${disk.snapshotDiskNumber}: ${disk.displayName} | '
            '${disk.busType} | ${formatDiagnosticBytes(disk.sizeBytes)}',
      ),
      _PreviewRowData(
        labelKey: 'boot_repair_binding_identity',
        value:
            '${diskToolsText(context, _identityKey(disk.identityKind))}: '
            '${disk.identityValue}',
      ),
      _PreviewRowData(
        labelKey: 'boot_repair_binding_windows',
        value:
            '${selection.windowsVolume.displayRoot} | '
            '${diskToolsText(context, 'boot_repair_binding_partition')} '
            '${selection.windowsVolume.partitionNumber} | '
            '${selection.windowsVolume.fileSystem}',
      ),
      _PreviewRowData(
        labelKey: 'boot_repair_binding_target',
        value:
            '${selection.bootTarget.displayRoot} | '
            '${diskToolsText(context, 'boot_repair_binding_partition')} '
            '${selection.bootTarget.partitionNumber} | '
            '${selection.bootTarget.fileSystem}',
      ),
      _PreviewRowData(
        labelKey: 'boot_repair_firmware',
        value: diskToolsText(
          context,
          selection.firmware == BootFirmware.uefi
              ? 'boot_repair_firmware_uefi'
              : 'boot_repair_firmware_bios',
        ),
      ),
    ];

    return Card(
      child: Padding(
        padding: EdgeInsets.all(compact ? 12 : 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!compact) ...[
              Row(
                children: [
                  Icon(
                    Icons.link_rounded,
                    size: 20,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    diskToolsText(context, 'boot_repair_binding_title'),
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ],
              ),
              const SizedBox(height: 12),
            ],
            for (var index = 0; index < rows.length; index++) ...[
              _PreviewRow(data: rows[index]),
              if (index != rows.length - 1) const Divider(height: 16),
            ],
          ],
        ),
      ),
    );
  }

  static String _identityKey(String kind) => switch (kind) {
    'serialNumber' => 'boot_repair_identity_serial',
    'uniqueId' => 'boot_repair_identity_unique',
    'devicePath' => 'boot_repair_identity_path',
    'pnpDeviceId' => 'boot_repair_identity_pnp',
    _ => 'boot_repair_binding_identity',
  };
}

class _PreviewRowData {
  final String labelKey;
  final String value;

  const _PreviewRowData({required this.labelKey, required this.value});
}

class _PreviewRow extends StatelessWidget {
  final _PreviewRowData data;

  const _PreviewRow({required this.data});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 160,
          child: Text(
            diskToolsText(context, data.labelKey),
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: SelectableText(
            data.value,
            textAlign: TextAlign.end,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }
}

class _PreflightPanel extends StatelessWidget {
  final BootRepairPreflight preflight;
  final bool executing;
  final VoidCallback onExecute;

  const _PreflightPanel({
    required this.preflight,
    required this.executing,
    required this.onExecute,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final passed = preflight.canExecute;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  passed ? Icons.verified_rounded : Icons.gpp_bad_rounded,
                  color: passed ? colors.primary : colors.error,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        diskToolsText(context, 'boot_repair_preflight_title'),
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      Text(
                        diskToolsText(
                          context,
                          passed
                              ? 'boot_repair_preflight_passed'
                              : 'boot_repair_preflight_failed',
                        ),
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            for (final check in preflight.checks)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _CheckRow(check: check),
              ),
            const Divider(height: 24),
            Text(
              diskToolsText(context, 'boot_repair_plan_title'),
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 10),
            for (
              var index = 0;
              index < preflight.plannedActions.length;
              index++
            )
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 24,
                      child: Text(
                        '${index + 1}.',
                        style: Theme.of(context).textTheme.labelMedium,
                      ),
                    ),
                    Expanded(
                      child: Text(
                        diskToolsText(context, preflight.plannedActions[index]),
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 8),
            Text(
              diskToolsText(context, 'boot_repair_command_preview'),
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 6),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: colors.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(6),
              ),
              child: SelectableText(
                preflight.commandPreview,
                style: const TextStyle(fontFamily: 'Consolas', fontSize: 13),
              ),
            ),
            const SizedBox(height: 14),
            for (final warning in preflight.warnings)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _WarningLine(textKey: warning),
              ),
            if (passed) ...[
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton.icon(
                  onPressed: executing ? null : onExecute,
                  icon: const Icon(Icons.build_rounded),
                  label: Text(diskToolsText(context, 'boot_repair_execute')),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _CheckRow extends StatelessWidget {
  final BootRepairCheck check;

  const _CheckRow({required this.check});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final color = check.passed ? colors.primary : colors.error;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          check.passed ? Icons.check_circle_rounded : Icons.cancel_rounded,
          size: 20,
          color: color,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                diskToolsText(context, check.labelKey),
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
              ),
              Text(
                diskToolsText(context, check.detailKey),
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant),
              ),
            ],
          ),
        ),
        Text(
          diskToolsText(
            context,
            check.passed ? 'disk_tools_passed' : 'disk_tools_failed',
          ),
          style: Theme.of(
            context,
          ).textTheme.labelMedium?.copyWith(color: color),
        ),
      ],
    );
  }
}

class _WarningLine extends StatelessWidget {
  final String textKey;

  const _WarningLine({required this.textKey});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.warning_amber_rounded, size: 20, color: colors.error),
        const SizedBox(width: 10),
        Expanded(child: Text(diskToolsText(context, textKey))),
      ],
    );
  }
}

class _ResultPanel extends StatelessWidget {
  final BootRepairResult result;
  final VoidCallback onOpenLogs;
  final VoidCallback onCopyLog;

  const _ResultPanel({
    required this.result,
    required this.onOpenLogs,
    required this.onCopyLog,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final statusColor = result.success ? colors.primary : colors.error;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  result.success
                      ? Icons.task_alt_rounded
                      : Icons.error_outline_rounded,
                  color: statusColor,
                  size: 28,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        diskToolsText(context, 'boot_repair_result_title'),
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      Text(diskToolsText(context, result.messageKey)),
                    ],
                  ),
                ),
              ],
            ),
            if (!result.elevationCancelled) ...[
              const SizedBox(height: 16),
              Text(
                diskToolsText(context, 'boot_repair_backup_title'),
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 8),
              _ResultPathRow(
                labelKey: result.existingBcdBackedUp
                    ? 'boot_repair_backup_created'
                    : 'boot_repair_backup_not_present',
                value: result.backupPath,
              ),
              const SizedBox(height: 8),
              _ResultPathRow(
                labelKey: 'boot_repair_log_path',
                value: result.logPath,
              ),
              if (result.verification case final verification?) ...[
                const Divider(height: 28),
                Text(
                  diskToolsText(context, 'boot_repair_verification_title'),
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: 10),
                _VerificationRow(
                  labelKey: 'boot_repair_verify_bcd_exists',
                  passed: verification.bcdStoreExists,
                ),
                _VerificationRow(
                  labelKey: 'boot_repair_verify_bcd_readable',
                  passed: verification.bcdStoreReadable,
                ),
                _VerificationRow(
                  labelKey: 'boot_repair_verify_boot_manager',
                  passed: verification.bootManagerExists,
                ),
                _VerificationRow(
                  labelKey: 'boot_repair_verify_fallback',
                  passed: verification.efiFallbackRequired
                      ? verification.efiFallbackExists &&
                            verification.efiFallbackMatchesBootManager
                      : true,
                  notRequired: !verification.efiFallbackRequired,
                ),
              ],
              const SizedBox(height: 16),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  OutlinedButton.icon(
                    onPressed: onOpenLogs,
                    icon: const Icon(Icons.folder_open_rounded),
                    label: Text(
                      diskToolsText(context, 'boot_repair_open_logs'),
                    ),
                  ),
                  OutlinedButton.icon(
                    onPressed: result.logText.isEmpty ? null : onCopyLog,
                    icon: const Icon(Icons.copy_rounded),
                    label: Text(diskToolsText(context, 'boot_repair_copy_log')),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ResultPathRow extends StatelessWidget {
  final String labelKey;
  final String value;

  const _ResultPathRow({required this.labelKey, required this.value});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: Text(diskToolsText(context, labelKey))),
        const SizedBox(width: 12),
        Expanded(
          child: SelectableText(
            value,
            textAlign: TextAlign.end,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant),
          ),
        ),
      ],
    );
  }
}

class _VerificationRow extends StatelessWidget {
  final String labelKey;
  final bool passed;
  final bool notRequired;

  const _VerificationRow({
    required this.labelKey,
    required this.passed,
    this.notRequired = false,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final color = passed ? colors.primary : colors.error;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Icon(
            passed ? Icons.check_circle_rounded : Icons.cancel_rounded,
            size: 19,
            color: color,
          ),
          const SizedBox(width: 9),
          Expanded(child: Text(diskToolsText(context, labelKey))),
          Text(
            diskToolsText(
              context,
              notRequired
                  ? 'boot_repair_verify_not_required'
                  : passed
                  ? 'disk_tools_passed'
                  : 'disk_tools_failed',
            ),
            style: Theme.of(
              context,
            ).textTheme.labelMedium?.copyWith(color: color),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final VoidCallback onRefresh;

  const _EmptyState({required this.onRefresh});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 64),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Column(
            children: [
              Icon(
                Icons.usb_off_rounded,
                size: 52,
                color: colors.onSurfaceVariant,
              ),
              const SizedBox(height: 16),
              Text(
                diskToolsText(context, 'boot_repair_no_windows_volumes'),
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Text(
                diskToolsText(context, 'boot_repair_no_windows_volumes_hint'),
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 18),
              FilledButton.icon(
                onPressed: onRefresh,
                icon: const Icon(Icons.refresh_rounded),
                label: Text(diskToolsText(context, 'disk_tools_refresh')),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PageStatus extends StatelessWidget {
  final IconData icon;
  final String textKey;
  final bool progress;

  const _PageStatus({
    required this.icon,
    required this.textKey,
    this.progress = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 52),
      child: Center(
        child: Column(
          children: [
            if (progress)
              const SizedBox(
                width: 40,
                height: 40,
                child: CircularProgressIndicator(),
              )
            else
              Icon(icon, size: 44),
            const SizedBox(height: 14),
            Text(diskToolsText(context, textKey), textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}

class _PageError extends StatelessWidget {
  final String errorKey;
  final VoidCallback onRetry;

  const _PageError({required this.errorKey, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _PageStatus(icon: Icons.error_outline_rounded, textKey: errorKey),
        FilledButton.icon(
          onPressed: onRetry,
          icon: const Icon(Icons.refresh_rounded),
          label: Text(diskToolsText(context, 'disk_tools_refresh')),
        ),
      ],
    );
  }
}

class _MessageBanner extends StatelessWidget {
  final IconData icon;
  final String text;
  final Color color;

  const _MessageBanner({
    required this.icon,
    required this.text,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: color),
          const SizedBox(width: 10),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }
}
