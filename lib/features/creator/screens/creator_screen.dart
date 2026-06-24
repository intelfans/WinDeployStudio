import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import '../../../core/localization/strings.dart';
import '../../../core/services/disk_safety_service.dart';
import '../../../core/services/iso_parse_service.dart';
import '../../../core/services/bootable_usb_service.dart';
import '../../logs/services/log_center_service.dart';

class CreatorScreen extends ConsumerStatefulWidget {
  const CreatorScreen({super.key});

  @override
  ConsumerState<CreatorScreen> createState() => _CreatorScreenState();
}

class _CreatorScreenState extends ConsumerState<CreatorScreen> {
  int _currentStep = 0;

  IsoMetadata? _selectedIso;
  DiskInfo? _selectedDisk;

  List<DiskInfo> _disks = [];
  bool _isDetecting = false;

  SafetyCheckResult? _safetyResult;

  CreateProgress? _createProgress;

  // ISO parsing state (inline, no dialog)
  bool _isParsing = false;
  String _parseStepText = '';
  int _parsePercent = 0;

  @override
  void initState() {
    super.initState();
    _detectDisks();
  }

  Future<void> _detectDisks() async {
    setState(() => _isDetecting = true);
    try {
      final safety = ref.read(diskSafetyServiceProvider);
      final disks = await safety.getRemovableDisks();
      if (!mounted) return;
      setState(() {
        _disks = disks;
        _isDetecting = false;
      });
      final logCenter = LogCenterService();
      await logCenter.logUsb('检测到 ${disks.length} 个可移动磁盘');
      for (final disk in disks) {
        await logCenter.logUsb('  磁盘 ${disk.diskNumber}: ${disk.model} | 容量: ${disk.sizeFormatted} | 总线: ${disk.busType} | 序列号: ${disk.serialNumber} | 分区表: ${disk.partitionStyle} | 盘符: ${disk.driveLetters.join(", ")}');
      }
    } catch (e) {
      debugPrint('Detect disks error: $e');
      if (!mounted) return;
      setState(() => _isDetecting = false);
    }
  }

  Future<void> _selectIsoFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['iso'],
        dialogTitle: tr(context, 'creator_select_iso'),
      );

      if (result == null || result.files.single.path == null) return;
      final path = result.files.single.path!;
      debugPrint('ISO selected: $path');

      if (!mounted) return;

      // Show inline progress
      setState(() {
        _isParsing = true;
        _parseStepText = tr(context, 'creator_parsing');
        _parsePercent = 0;
      });

      final isoService = ref.read(isoParseServiceProvider);
      IsoMetadata? metadata;

      try {
        metadata = await isoService
            .parseIso(
              path,
              onProgress: (step, percent) {
                if (!mounted) return;
                String stepText;
                switch (step) {
                  case 'detect':
                    stepText = tr(context, 'iso_step_detect');
                    break;
                  case 'mount':
                    stepText = tr(context, 'iso_step_mount');
                    break;
                  case 'info':
                    stepText = tr(context, 'iso_step_info');
                    break;
                  case 'cleanup':
                    stepText = tr(context, 'iso_step_cleanup');
                    break;
                  default:
                    stepText = step;
                }
                setState(() {
                  _parseStepText = stepText;
                  _parsePercent = percent;
                });
              },
            )
            .timeout(const Duration(seconds: 30), onTimeout: () {
          debugPrint('ISO parse overall timeout');
          isoService.cancel();
          return null;
        });
      } catch (e) {
        debugPrint('ISO parse error: $e');
      }

      if (!mounted) return;

      setState(() {
        _isParsing = false;
        if (metadata != null) {
          _selectedIso = metadata;
          _currentStep = 1;
        }
      });

      if (metadata != null) {
        final logCenter = LogCenterService();
        await logCenter.logIso('ISO 已选择 | 文件: ${metadata.fileName} | 版本: ${metadata.windowsVersion ?? "未知"} | 构建: ${metadata.buildNumber ?? "未知"}');
      }

      if (metadata == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(tr(context, 'creator_parse_error'))),
        );
      }
    } catch (e) {
      debugPrint('ISO select error: $e');
      if (!mounted) return;
      setState(() => _isParsing = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${tr(context, "creator_error")}: $e')),
      );
    }
  }

  void _cancelParsing() {
    ref.read(isoParseServiceProvider).cancel();
    if (mounted) {
      setState(() => _isParsing = false);
    }
  }

  Future<void> _checkDiskSafety(DiskInfo disk) async {
    try {
      final safety = ref.read(diskSafetyServiceProvider);
      final result = await safety.checkDiskSafety(disk);
      if (!mounted) return;
      setState(() {
        _safetyResult = result;
        if (result.isSafe) {
          _selectedDisk = disk;
        }
      });
    } catch (e) {
      debugPrint('Disk safety check error: $e');
      if (!mounted) return;
      setState(() {
        _safetyResult = SafetyCheckResult(
          isSafe: false,
          reason: '${tr(context, 'creator_safety_failed')}: $e',
        );
      });
    }
  }

  Future<void> _startCreation() async {
    debugPrint('[WDS] _startCreation called: disk=${_selectedDisk?.diskNumber}, iso=${_selectedIso?.fileName}');
    if (_selectedDisk == null || _selectedIso == null) {
      debugPrint('[WDS] _startCreation: disk or iso is null, returning');
      return;
    }

    setState(() {
      _currentStep = 3;
      _createProgress = CreateProgress(
        step: CreateStep.preparing,
        message: tr(context, 'creator_starting'),
      );
    });
    debugPrint('[WDS] _startCreation: step set to 3');

    try {
      final service = ref.read(bootableUsbServiceProvider);
      final success = await service.createBootableUsb(
        diskNumber: _selectedDisk!.diskNumber,
        isoPath: _selectedIso!.filePath,
        onProgress: (progress) {
          if (mounted) {
            setState(() => _createProgress = progress);
          }
        },
      );
      debugPrint('[WDS] _startCreation: createBootableUsb returned: $success');

      if (mounted) {
        if (success) {
          setState(() => _currentStep = 4);
        }
        // On failure, stay on step 3 — the error is already shown via _createProgress
        debugPrint('[WDS] _startCreation: final step = $_currentStep');
      }
    } catch (e, st) {
      debugPrint('[WDS] _startCreation exception: $e');
      debugPrint('[WDS] stacktrace: $st');
      if (mounted) {
        setState(() {
          _createProgress = CreateProgress(
            step: CreateStep.failed,
            message: 'Error: $e',
          );
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final screenWidth = MediaQuery.of(context).size.width;
    final isCompact = screenWidth < 900;

    return Scaffold(
      body: SingleChildScrollView(
        padding: EdgeInsets.all(isCompact ? 16 : 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              tr(context, 'creator_title'),
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              tr(context, 'creator_subtitle'),
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 24),
            _buildStepIndicator(),
            const SizedBox(height: 24),
            _buildStepContent(),
          ],
        ),
      ),
    );
  }

  Widget _buildStepIndicator() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          _StepItem(
            number: 1,
            label: tr(context, 'creator_step_iso'),
            isActive: _currentStep == 0,
            isCompleted: _currentStep > 0,
          ),
          _StepConnector(isCompleted: _currentStep > 0),
          _StepItem(
            number: 2,
            label: tr(context, 'creator_step_usb'),
            isActive: _currentStep == 1,
            isCompleted: _currentStep > 1,
          ),
          _StepConnector(isCompleted: _currentStep > 1),
          _StepItem(
            number: 3,
            label: tr(context, 'creator_step_confirm'),
            isActive: _currentStep == 2,
            isCompleted: _currentStep > 2,
          ),
          _StepConnector(isCompleted: _currentStep > 2),
          _StepItem(
            number: 4,
            label: tr(context, 'creator_step_create'),
            isActive: _currentStep == 3,
            isCompleted: _currentStep == 4,
          ),
        ],
      ),
    );
  }

  Widget _buildStepContent() {
    switch (_currentStep) {
      case 0:
        return _buildSelectIsoStep();
      case 1:
        return _buildSelectUsbStep();
      case 2:
        return _buildConfirmStep();
      case 3:
        return _buildCreatingStep();
      case 4:
        return _buildCompleteStep();
      default:
        return const SizedBox.shrink();
    }
  }

  // --- Step 0: Select ISO ---

  Widget _buildSelectIsoStep() {
    final theme = Theme.of(context);

    // Show inline parsing progress
    if (_isParsing) {
      return Center(
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 48,
                  height: 48,
                  child: CircularProgressIndicator(
                    value:
                        _parsePercent > 0 ? _parsePercent / 100.0 : null,
                    strokeWidth: 4,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  _parseStepText.isEmpty
                      ? tr(context, 'creator_parsing')
                      : _parseStepText,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                if (_parsePercent > 0) ...[
                  const SizedBox(height: 4),
                  Text('$_parsePercent%',
                      style: theme.textTheme.bodySmall),
                ],
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: _cancelParsing,
                    child: Text(tr(context, 'detail_cancel')),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Center(
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.album, size: 64, color: theme.colorScheme.primary),
              const SizedBox(height: 16),
              Text(tr(context, 'creator_select_iso'),
                  style: theme.textTheme.titleLarge),
              const SizedBox(height: 8),
              Text(
                tr(context, 'creator_select_iso_desc'),
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: _selectIsoFile,
                icon: const Icon(Icons.folder_open),
                label: Text(tr(context, 'creator_select_btn')),
              ),
              if (_selectedIso != null) ...[
                const SizedBox(height: 16),
                const Divider(),
                const SizedBox(height: 12),
                _IsoInfoCard(iso: _selectedIso!),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: () => setState(() => _currentStep = 1),
                  child: Text(tr(context, 'creator_next_usb')),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  // --- Step 1: Select USB ---

  Widget _buildSelectUsbStep() {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_selectedIso != null) ...[
          _IsoInfoCard(iso: _selectedIso!),
          const SizedBox(height: 16),
        ],
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(tr(context, 'creator_select_usb'),
                style: theme.textTheme.titleMedium),
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: _isDetecting ? null : _detectDisks,
              tooltip: tr(context, 'creator_retry'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (_isDetecting)
          const Center(
            child: Padding(
              padding: EdgeInsets.all(32),
              child: CircularProgressIndicator(),
            ),
          )
        else if (_disks.isEmpty)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Center(
                child: Column(
                  children: [
                    Icon(Icons.usb_off,
                        size: 48,
                        color: theme.colorScheme.onSurfaceVariant),
                    const SizedBox(height: 16),
                    Text(tr(context, 'creator_no_usb')),
                    const SizedBox(height: 8),
                    OutlinedButton(
                      onPressed: _detectDisks,
                      child: Text(tr(context, 'creator_retry')),
                    ),
                  ],
                ),
              ),
            ),
          )
        else
          ..._disks.map((disk) {
            final isSelected = _selectedDisk?.diskNumber == disk.diskNumber;
            return _DiskCard(
              disk: disk,
              isSelected: isSelected,
              safetyResult: isSelected ? _safetyResult : null,
              onTap: () {
                setState(() {
                  _selectedDisk = disk;
                  _safetyResult = null; // null = checking
                });
                _checkDiskSafety(disk);
              },
            );
          }),
        if (_selectedDisk != null) ...[
          if (_safetyResult == null) ...[
            const SizedBox(height: 16),
            Center(
              child: Padding(
                padding: EdgeInsets.all(8),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    SizedBox(width: 12),
                    Text(tr(context, 'creator_checking_safety')),
                  ],
                ),
              ),
            ),
          ],
          if (_safetyResult != null) ...[
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                OutlinedButton(
                  onPressed: () => setState(() => _currentStep = 0),
                  child: Text(tr(context, 'creator_back')),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: _safetyResult!.isSafe
                      ? () => setState(() => _currentStep = 2)
                      : null,
                  child: Text(tr(context, 'creator_next_confirm')),
                ),
              ],
            ),
          ],
        ],
      ],
    );
  }

  // --- Step 2: Confirm ---

  Widget _buildConfirmStep() {
    final theme = Theme.of(context);
    return Center(
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 500),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(tr(context, 'creator_confirm_title'),
                    style: theme.textTheme.titleLarge),
                const SizedBox(height: 16),
                _ConfirmSection(
                  title: tr(context, 'creator_iso_section'),
                  rows: [
                    _ConfirmRow(
                        label: tr(context, 'creator_file'), value: _selectedIso?.fileName ?? '-'),
                    _ConfirmRow(
                        label: tr(context, 'creator_version'),
                        value: _selectedIso?.windowsVersion ?? tr(context, 'creator_unknown')),
                    _ConfirmRow(
                        label: tr(context, 'creator_size'),
                        value: _selectedIso?.displaySize ?? '-'),
                  ],
                ),
                const Divider(),
                _ConfirmSection(
                  title: tr(context, 'creator_usb_section'),
                  rows: [
                    _ConfirmRow(
                        label: tr(context, 'creator_disk'),
                        value: '${tr(context, 'creator_disk_prefix')} ${_selectedDisk?.diskNumber}'),
                    _ConfirmRow(
                        label: tr(context, 'creator_model'),
                        value: _selectedDisk?.model ?? '-'),
                    _ConfirmRow(
                        label: tr(context, 'creator_size'),
                        value: _selectedDisk?.sizeFormatted ?? '-'),
                    _ConfirmRow(
                        label: tr(context, 'creator_serial'),
                        value: _selectedDisk?.serialNumber ?? '-'),
                  ],
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.errorContainer,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.warning_amber,
                          color: theme.colorScheme.error),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          tr(context, 'creator_warning'),
                          style: TextStyle(
                            color: theme.colorScheme.onErrorContainer,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    OutlinedButton(
                      onPressed: () => setState(() => _currentStep = 1),
                      child: Text(tr(context, 'creator_back')),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      onPressed: _showEraseConfirmation,
                      child: Text(tr(context, 'creator_start')),
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

  String _resolveLocalizedMessage(BuildContext context, String key) {
    // If the key contains newlines, it's a composite message with log path
    final parts = key.split('\n\nLog: ');
    final actualKey = parts[0];
    final logPath = parts.length > 1 ? parts[1] : null;
    
    var resolved = tr(context, actualKey);
    if (logPath != null) {
      resolved = '$resolved\n\nLog: $logPath';
    }
    return resolved;
  }

  // --- Step 3: Creating ---

  Widget _buildCreatingStep() {
    final theme = Theme.of(context);
    final progress = _createProgress;
    final rawMessage = progress?.message ?? 'step_preparing';
    final message = _resolveLocalizedMessage(context, rawMessage);
    final pct = ((progress?.progress ?? 0) * 100).toInt();
    final isFailed = progress?.step == CreateStep.failed;

    return Center(
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (isFailed) ...[
                Icon(Icons.error_outline,
                    size: 48, color: theme.colorScheme.error),
                const SizedBox(height: 16),
                Text(
                  tr(context, 'step_failed'),
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: theme.colorScheme.error,
                  ),
                ),
                const SizedBox(height: 8),
                Text(message,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    textAlign: TextAlign.center),
                const SizedBox(height: 24),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    OutlinedButton(
                      onPressed: () =>
                          setState(() => _currentStep = 2),
                      child: Text(tr(context, 'creator_back')),
                    ),
                    const SizedBox(width: 12),
                    FilledButton.icon(
                      onPressed: _startCreation,
                      icon: const Icon(Icons.refresh),
                      label: Text(tr(context, 'creator_retry')),
                    ),
                  ],
                ),
              ] else ...[
                const CircularProgressIndicator(),
                const SizedBox(height: 24),
                Text(
                  _stepDisplayName(
                      context, progress?.step ?? CreateStep.preparing),
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                Text(message,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    )),
                const SizedBox(height: 16),
                SizedBox(
                  width: 300,
                  child: LinearProgressIndicator(
                    value: progress?.progress ?? 0,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                const SizedBox(height: 8),
                Text('$pct%', style: theme.textTheme.bodySmall),
              ],
            ],
          ),
        ),
      ),
    );
  }

  String _stepDisplayName(BuildContext context, CreateStep step) {
    switch (step) {
      case CreateStep.preparing:
        return tr(context, 'step_preparing');
      case CreateStep.cleaningDisk:
        return tr(context, 'step_cleaning');
      case CreateStep.creatingPartitions:
        return tr(context, 'step_partitioning');
      case CreateStep.formatting:
        return tr(context, 'step_formatting');
      case CreateStep.mountingIso:
        return tr(context, 'step_mounting');
      case CreateStep.copyingFiles:
        return tr(context, 'step_copying');
      case CreateStep.splittingWim:
        return tr(context, 'step_splitting');
      case CreateStep.writingBootFiles:
        return tr(context, 'step_boot');
      case CreateStep.verifying:
        return tr(context, 'step_verifying');
      case CreateStep.complete:
        return tr(context, 'step_complete');
      case CreateStep.failed:
        return tr(context, 'step_failed');
    }
  }

  // --- Step 4: Complete ---

  Widget _buildCompleteStep() {
    final theme = Theme.of(context);
    return Center(
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.check_circle,
                  size: 64, color: theme.colorScheme.primary),
              const SizedBox(height: 24),
              Text(tr(context, 'creator_complete_title'),
                  style: theme.textTheme.titleLarge),
              const SizedBox(height: 8),
              Text(
                tr(context, 'creator_complete_desc'),
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: () {
                  setState(() {
                    _currentStep = 0;
                    _selectedIso = null;
                    _selectedDisk = null;
                    _safetyResult = null;
                    _createProgress = null;
                  });
                },
                child: Text(tr(context, 'creator_another')),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // --- Erase Confirmation ---

  void _showEraseConfirmation() {
    final controller = TextEditingController();
    final confirmWord = tr(context, 'erase_confirm_word');
    showDialog(
      context: context,
      builder: (dialogContext) {
        bool matches() =>
            controller.text.trim().toUpperCase() == confirmWord.toUpperCase();
        return AlertDialog(
          title: Text(tr(dialogContext, 'erase_title')),
          content: SizedBox(
            width: 400,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                    '${tr(dialogContext, 'erase_desc_prefix')} $confirmWord ${tr(dialogContext, 'erase_desc_suffix')}'),
                const SizedBox(height: 8),
                Text(
                  '${tr(dialogContext, 'creator_disk')} ${_selectedDisk?.diskNumber}: ${_selectedDisk?.model}',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                Text(
                  '${_selectedDisk?.sizeFormatted} - S/N: ${_selectedDisk?.serialNumber}',
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: controller,
                  autofocus: true,
                  decoration: InputDecoration(
                    hintText: confirmWord,
                  ),
                  onSubmitted: (value) {
                    debugPrint('[WDS] onSubmitted: value="$value", matches=${matches()}');
                    if (matches()) {
                      Navigator.pop(dialogContext);
                      _startCreation();
                    }
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(tr(dialogContext, 'detail_cancel')),
            ),
            FilledButton(
              onPressed: () {
                debugPrint('[WDS] Button pressed: text="${controller.text}", matches=${matches()}');
                if (matches()) {
                  Navigator.pop(dialogContext);
                  _startCreation();
                }
              },
              child: Text(tr(dialogContext, 'erase_confirm')),
            ),
          ],
        );
      },
    );
  }
}

// --- Sub-widgets ---

class _IsoInfoCard extends StatelessWidget {
  final IsoMetadata iso;
  const _IsoInfoCard({required this.iso});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      color:
          theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Icon(Icons.album, size: 20, color: theme.colorScheme.primary),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(iso.fileName,
                      style: theme.textTheme.titleSmall,
                      overflow: TextOverflow.ellipsis),
                  Wrap(
                    spacing: 12,
                    runSpacing: 2,
                    children: [
                      if (iso.windowsVersion != null)
                        Text(iso.windowsVersion!,
                            style: theme.textTheme.bodySmall),
                      if (iso.buildNumber != null)
                        Text('${tr(context, 'creator_build_prefix')} ${iso.buildNumber}',
                            style: theme.textTheme.bodySmall),
                      Text(iso.displaySize,
                          style: theme.textTheme.bodySmall),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DiskCard extends StatelessWidget {
  final DiskInfo disk;
  final bool isSelected;
  final SafetyCheckResult? safetyResult;
  final VoidCallback onTap;

  const _DiskCard({
    required this.disk,
    required this.isSelected,
    required this.safetyResult,
    required this.onTap,
  });

  String _resolveSafetyReasonLocal(BuildContext context, SafetyCheckResult result) {
    final params = result.params;
    var localized = tr(context, result.reason);
    if (params != null) {
      for (final entry in params.entries) {
        localized = localized.replaceAll('{${entry.key}}', entry.value);
      }
    }
    return localized;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isSafe = safetyResult?.isSafe ?? true;

    return Card(
      color: isSelected
          ? (isSafe
              ? theme.colorScheme.primaryContainer
              : theme.colorScheme.errorContainer)
          : null,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(Icons.usb,
                  color: isSelected
                      ? (isSafe
                          ? theme.colorScheme.primary
                          : theme.colorScheme.error)
                      : theme.colorScheme.onSurfaceVariant),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${tr(context, 'creator_disk_prefix')} ${disk.diskNumber}: ${disk.model}',
                        style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w600)),
                    const SizedBox(height: 4),
                    Text(
                      '${disk.sizeFormatted}  |  ${tr(context, 'creator_sn_prefix')} ${disk.serialNumber}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    if (safetyResult != null && !isSafe) ...[
                      const SizedBox(height: 4),
                      Text(_resolveSafetyReasonLocal(context, safetyResult!),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.error,
                            fontWeight: FontWeight.w600,
                          )),
                    ],
                  ],
                ),
              ),
              if (isSelected && isSafe)
                Icon(Icons.check_circle, color: theme.colorScheme.primary),
            ],
          ),
        ),
      ),
    );
  }
}

class _ConfirmSection extends StatelessWidget {
  final String title;
  final List<Widget> rows;

  const _ConfirmSection({required this.title, required this.rows});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title,
            style: Theme.of(context)
                .textTheme
                .labelLarge
                ?.copyWith(color: Theme.of(context).colorScheme.primary)),
        const SizedBox(height: 4),
        ...rows,
      ],
    );
  }
}

class _ConfirmRow extends StatelessWidget {
  final String label;
  final String value;

  const _ConfirmRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          SizedBox(
            width: 80,
            child: Text(label,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant)),
          ),
          Expanded(
            child: Text(value,
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(fontWeight: FontWeight.w500)),
          ),
        ],
      ),
    );
  }
}

class _StepItem extends StatelessWidget {
  final int number;
  final String label;
  final bool isActive;
  final bool isCompleted;

  const _StepItem({
    required this.number,
    required this.label,
    required this.isActive,
    required this.isCompleted,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Column(
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: isCompleted
                ? cs.primary
                : isActive
                    ? cs.primaryContainer
                    : cs.surfaceContainerHighest,
          ),
          child: Center(
            child: isCompleted
                ? Icon(Icons.check, size: 16, color: cs.onPrimary)
                : Text('$number',
                    style: TextStyle(
                      color: isActive
                          ? cs.onPrimaryContainer
                          : cs.onSurfaceVariant,
                      fontWeight: FontWeight.bold,
                    )),
          ),
        ),
        const SizedBox(height: 4),
        Text(label,
            style: theme.textTheme.bodySmall?.copyWith(
              color: isActive ? cs.primary : cs.onSurfaceVariant,
            )),
      ],
    );
  }
}

class _StepConnector extends StatelessWidget {
  final bool isCompleted;

  const _StepConnector({required this.isCompleted});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 40,
      height: 2,
      margin: const EdgeInsets.symmetric(horizontal: 4),
      color: isCompleted
          ? Theme.of(context).colorScheme.primary
          : Theme.of(context).colorScheme.surfaceContainerHighest,
    );
  }
}
