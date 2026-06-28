import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import '../../../core/localization/strings.dart';
import '../../../core/services/disk_safety_service.dart';
import '../../../core/services/iso_parse_service.dart';
import '../../../core/services/wtg_service.dart';
import '../../../core/services/wtg_compatibility_service.dart';
import '../../logs/services/log_center_service.dart';

class WtgScreen extends ConsumerStatefulWidget {
  const WtgScreen({super.key});

  @override
  ConsumerState<WtgScreen> createState() => _WtgScreenState();
}

class _WtgScreenState extends ConsumerState<WtgScreen> {
  int _currentStep = 0;

  IsoMetadata? _selectedIso;
  DiskInfo? _selectedDisk;
  List<Map<String, dynamic>> _wimImages = [];
  int? _selectedImageIndex;

  List<DiskInfo> _disks = [];
  bool _isDetecting = false;

  WtgCompatibilityResult? _compatibilityResult;
  bool _isCheckingCompatibility = false;

  WtgProgress? _wtgProgress;

  // ISO parsing state
  bool _isParsing = false;
  String _parseStepText = '';
  int _parsePercent = 0;

  // WIM loading state
  bool _isLoadingWim = false;
  List<String> _debugLogs = [];

  // Confirmation state
  final TextEditingController _confirmController = TextEditingController();
  bool _isConfirmValid = false;

  // Progress tracking
  Stopwatch? _progressStopwatch;
  Timer? _progressTimer;

  // Lightweight waiting game state. UI-only; it never touches WTG creation.
  final Random _idleGameRandom = Random();
  int _idleGameTarget = 4;
  int _idleGameScore = 0;

  @override
  void initState() {
    super.initState();
    _detectDisks();
  }

  @override
  void dispose() {
    _confirmController.dispose();
    _progressTimer?.cancel();
    _progressStopwatch?.stop();
    super.dispose();
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
    } catch (e) {
      debugPrint('Detect disks error: $e');
      if (!mounted) return;
      setState(() => _isDetecting = false);
    }
  }

  Future<void> _selectIsoFile() async {
    try {
      final result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['iso'],
        dialogTitle: tr(context, 'wtg_select_iso'),
      );

      if (result == null || result.files.single.path == null) return;
      final path = result.files.single.path!;
      debugPrint('ISO selected: $path');

      if (!mounted) return;

      // Show inline progress
      setState(() {
        _isParsing = true;
        _parseStepText = tr(context, 'wtg_parsing_iso');
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
            .timeout(const Duration(seconds: 90));
      } on TimeoutException {
        debugPrint('ISO parse timed out');
      } catch (e) {
        debugPrint('ISO parse error: $e');
      }

      if (!mounted) return;

      setState(() {
        _isParsing = false;
        if (metadata != null) {
          _selectedIso = metadata;
        }
      });

      if (metadata != null) {
        final logCenter = LogCenterService();
        await logCenter.logWTG(
          'WTG ISO 已选择 | 文件: ${metadata.fileName} | 版本: ${metadata.windowsVersion ?? "未知"}',
        );
        // Load WIM images
        await _loadWimImages(path);
      }
    } catch (e) {
      debugPrint('File picker error: $e');
      if (mounted) {
        setState(() => _isParsing = false);
      }
    }
  }

  Future<void> _loadWimImages(String isoPath) async {
    setState(() {
      _isLoadingWim = true;
      _debugLogs = [];
    });

    try {
      final wtgService = ref.read(wtgServiceProvider);
      final images = await wtgService.getWimImages(isoPath);

      if (!mounted) return;

      // Get debug logs from service
      final logs = wtgService.debugLogs;

      setState(() {
        _wimImages = images;
        _isLoadingWim = false;
        _debugLogs = logs;
        if (images.isNotEmpty) {
          _selectedImageIndex = images.first['index'] as int?;
          _currentStep = 2; // Move to image selection step
        }
      });
    } catch (e) {
      debugPrint('Load WIM images error: $e');
      if (mounted) {
        setState(() {
          _isLoadingWim = false;
          _debugLogs.add('Exception: $e');
        });
      }
    }
  }

  Future<void> _checkCompatibility(DiskInfo disk) async {
    setState(() => _isCheckingCompatibility = true);

    try {
      // Get drive letter - try from disk info first
      String driveLetter = '';
      if (disk.driveLetters.isNotEmpty) {
        final letter = disk.driveLetters.first;
        if (letter.isNotEmpty) {
          driveLetter = letter.length == 1 ? '$letter:' : letter;
        }
      }

      // If no drive letter from disk info, try to get it via PowerShell
      if (driveLetter.isEmpty) {
        try {
          final result = await Process.run('powershell', [
            '-NoProfile',
            '-Command',
            'Get-Partition -DiskNumber ${disk.diskNumber}'
                r' | Where-Object { $_.DriveLetter } | Select-Object -First 1 -ExpandProperty DriveLetter',
          ]).timeout(const Duration(seconds: 5));
          if (result.exitCode == 0) {
            final letter = result.stdout.toString().trim();
            if (letter.isNotEmpty) {
              driveLetter = letter.length == 1 ? '$letter:' : letter;
            }
          }
        } catch (_) {}
      }

      final compatibilityService = ref.read(wtgCompatibilityServiceProvider);
      final result = await compatibilityService.checkCompatibility(
        diskNumber: disk.diskNumber,
        driveLetter: driveLetter,
        fallbackDisk: disk,
      );

      if (!mounted) return;

      setState(() {
        _compatibilityResult = result;
        _isCheckingCompatibility = false;
      });
    } catch (e) {
      debugPrint('Compatibility check error: $e');
      if (mounted) {
        setState(() => _isCheckingCompatibility = false);
      }
    }
  }

  Future<void> _startWtgCreation() async {
    if (_selectedIso == null ||
        _selectedDisk == null ||
        _selectedImageIndex == null) {
      return;
    }

    // Start progress timer
    _progressStopwatch = Stopwatch()..start();

    // Update UI periodically to show elapsed time
    _progressTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted &&
          _progressStopwatch != null &&
          _progressStopwatch!.isRunning) {
        setState(() {}); // Refresh to update elapsed time display
      }
    });

    setState(() {
      _currentStep = 5; // Move to progress step
      _wtgProgress = WtgProgress(
        step: WtgStep.preparing,
        message: tr(context, 'wtg_starting'),
        progress: 0.0,
      );
    });

    final wtgService = ref.read(wtgServiceProvider);
    final driveLetter = _selectedDisk!.driveLetters.isNotEmpty
        ? _selectedDisk!.driveLetters.first
        : '';

    final result = await wtgService.createWtg(
      isoPath: _selectedIso!.filePath,
      imageIndex: _selectedImageIndex!,
      diskNumber: _selectedDisk!.diskNumber,
      driveLetter: driveLetter,
      onProgress: (progress) {
        if (mounted) {
          setState(() => _wtgProgress = progress);
        }
      },
    );

    if (mounted) {
      _progressTimer?.cancel();
      _progressStopwatch?.stop();
      setState(() {
        _currentStep = result ? 9 : 10; // Complete or Failed
      });
    }
  }

  String _resolveLocalizedMessage(BuildContext context, String key) {
    // Composite progress messages keep the first line as a localization key.
    final parts = key.split('\n\nLog: ');
    final messageLines = parts[0].split('\n');
    final actualKey = messageLines.first;
    final details = messageLines.skip(1).where((line) => line.isNotEmpty);
    final logPath = parts.length > 1 ? parts[1] : null;

    var resolved = tr(context, actualKey);
    if (details.isNotEmpty) {
      resolved = '$resolved\n${details.join('\n')}';
    }
    if (logPath != null) {
      resolved = '$resolved\n\n${tr(context, 'logs_title')}: $logPath';
    }
    return resolved;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              tr(context, 'wtg_title'),
              style: Theme.of(
                context,
              ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(
              tr(context, 'wtg_subtitle'),
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 24),
            Expanded(child: _buildCurrentStep()),
          ],
        ),
      ),
    );
  }

  Widget _buildCurrentStep() {
    switch (_currentStep) {
      case 0:
        return _buildStep1SelectIso();
      case 1:
        return _buildStep2ParseIso();
      case 2:
        return _buildStep3SelectImage();
      case 3:
        return _buildStep4SelectDisk();
      case 4:
        return _buildStep5Confirm();
      case 5:
        return _buildStep6Progress();
      case 9:
        return _buildStepComplete();
      case 10:
        return _buildStepFailed();
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _buildStep1SelectIso() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          tr(context, 'wtg_step1_title'),
          style: Theme.of(
            context,
          ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        Text(
          tr(context, 'wtg_step1_desc'),
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 24),
        if (_isParsing) ...[
          Center(
            child: Column(
              children: [
                const CircularProgressIndicator(),
                const SizedBox(height: 16),
                Text(_parseStepText),
                const SizedBox(height: 8),
                SizedBox(
                  width: 200,
                  child: LinearProgressIndicator(value: _parsePercent / 100.0),
                ),
                const SizedBox(height: 8),
                Text('$_parsePercent%'),
              ],
            ),
          ),
        ] else if (_selectedIso != null) ...[
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.check_circle, color: Colors.green),
                      const SizedBox(width: 8),
                      Text(
                        tr(context, 'wtg_iso_selected'),
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _InfoRow(tr(context, 'creator_file'), _selectedIso!.fileName),
                  _InfoRow(
                    tr(context, 'creator_version'),
                    _selectedIso!.windowsVersion ??
                        tr(context, 'creator_unknown'),
                  ),
                  _InfoRow(
                    tr(context, 'creator_size'),
                    _selectedIso!.displaySize,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              FilledButton.icon(
                onPressed: () => setState(() => _currentStep = 1),
                icon: const Icon(Icons.arrow_forward),
                label: Text(tr(context, 'wtg_next_parse')),
              ),
              const SizedBox(width: 12),
              OutlinedButton.icon(
                onPressed: () {
                  setState(() {
                    _selectedIso = null;
                    _wimImages = [];
                    _selectedImageIndex = null;
                  });
                },
                icon: const Icon(Icons.refresh),
                label: Text(tr(context, 'wtg_rescan')),
              ),
            ],
          ),
        ] else ...[
          Card(
            child: InkWell(
              onTap: _selectIsoFile,
              borderRadius: BorderRadius.circular(12),
              child: Container(
                padding: const EdgeInsets.all(32),
                child: Column(
                  children: [
                    Icon(
                      Icons.folder_open,
                      size: 48,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      tr(context, 'creator_select_btn'),
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      tr(context, 'creator_select_iso_desc'),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildStep2ParseIso() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          tr(context, 'wtg_step2_title'),
          style: Theme.of(
            context,
          ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        Text(
          tr(context, 'wtg_step2_desc'),
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 24),
        if (_isLoadingWim) ...[
          Center(
            child: Column(
              children: [
                const CircularProgressIndicator(),
                const SizedBox(height: 16),
                Text(tr(context, 'wtg_loading_wim')),
              ],
            ),
          ),
        ] else if (_wimImages.isNotEmpty) ...[
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.check_circle, color: Colors.green),
                      const SizedBox(width: 8),
                      Text(
                        tr(context, 'wtg_wim_loaded'),
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${_wimImages.length} ${tr(context, 'wtg_wim_count_suffix')}',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: () => setState(() => _currentStep = 2),
            icon: const Icon(Icons.arrow_forward),
            label: Text(tr(context, 'wtg_next_select_image')),
          ),
        ] else ...[
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.error_outline,
                        color: Theme.of(context).colorScheme.error,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        tr(context, 'wtg_no_wim_found'),
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ],
                  ),
                  if (_debugLogs.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    Text(
                      tr(context, 'wtg_debug_info'),
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      width: double.infinity,
                      height: 200,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Theme.of(
                          context,
                        ).colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Scrollbar(
                        child: SingleChildScrollView(
                          child: SelectableText(
                            _debugLogs.join('\n'),
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(fontFamily: 'monospace'),
                          ),
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      OutlinedButton.icon(
                        onPressed: () => setState(() {
                          _currentStep = 0;
                          _debugLogs = [];
                        }),
                        icon: const Icon(Icons.arrow_back),
                        label: Text(tr(context, 'creator_back')),
                      ),
                      const SizedBox(width: 12),
                      FilledButton.icon(
                        onPressed: () {
                          // Copy debug logs to clipboard
                          final text = _debugLogs.join('\n');
                          Clipboard.setData(ClipboardData(text: text));
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(tr(context, 'wtg_debug_copied')),
                              duration: Duration(seconds: 2),
                            ),
                          );
                        },
                        icon: const Icon(Icons.copy),
                        label: Text(tr(context, 'wtg_copy_debug')),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildStep3SelectImage() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          tr(context, 'wtg_step3_title'),
          style: Theme.of(
            context,
          ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        Text(
          tr(context, 'wtg_step3_desc'),
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 24),
        Expanded(
          child: RadioGroup<int>(
            groupValue: _selectedImageIndex,
            onChanged: (value) {
              setState(() => _selectedImageIndex = value);
            },
            child: ListView.builder(
              itemCount: _wimImages.length,
              itemBuilder: (context, index) {
                final image = _wimImages[index];
                final imageIndex = image['index'] as int;
                final isSelected = _selectedImageIndex == imageIndex;

                return Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    leading: Radio<int>(value: imageIndex),
                    title: Text(
                      image['name'] ??
                          tr(
                            context,
                            'wtg_image_fallback',
                          ).replaceAll('{index}', '$imageIndex'),
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (image['description'] != null)
                          Text(
                            image['description'],
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        const SizedBox(height: 4),
                        Wrap(
                          spacing: 8,
                          children: [
                            if (image['edition'] != null)
                              _Chip(label: image['edition']),
                            if (image['architecture'] != null)
                              _Chip(label: image['architecture']),
                            if (image['size'] != null)
                              _Chip(label: image['size']),
                          ],
                        ),
                      ],
                    ),
                    trailing: isSelected
                        ? Icon(
                            Icons.check_circle,
                            color: Theme.of(context).colorScheme.primary,
                          )
                        : null,
                    onTap: () {
                      setState(() => _selectedImageIndex = imageIndex);
                    },
                  ),
                );
              },
            ),
          ),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            FilledButton.icon(
              onPressed: _selectedImageIndex != null
                  ? () => setState(() => _currentStep = 3)
                  : null,
              icon: const Icon(Icons.arrow_forward),
              label: Text(tr(context, 'wtg_next_select_disk')),
            ),
            const SizedBox(width: 12),
            OutlinedButton.icon(
              onPressed: () => setState(() => _currentStep = 1),
              icon: const Icon(Icons.arrow_back),
              label: Text(tr(context, 'creator_back')),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildStep4SelectDisk() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          tr(context, 'wtg_step4_title'),
          style: Theme.of(
            context,
          ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        Text(
          tr(context, 'wtg_step4_desc'),
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 24),
        if (_isDetecting) ...[
          Center(
            child: Column(
              children: [
                const CircularProgressIndicator(),
                const SizedBox(height: 16),
                Text(tr(context, 'creator_no_usb')),
              ],
            ),
          ),
        ] else if (_disks.isEmpty) ...[
          Center(
            child: Column(
              children: [
                Icon(
                  Icons.usb_off,
                  size: 48,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
                const SizedBox(height: 16),
                Text(tr(context, 'creator_no_usb')),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: _detectDisks,
                  icon: const Icon(Icons.refresh),
                  label: Text(tr(context, 'creator_retry')),
                ),
              ],
            ),
          ),
        ] else ...[
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Disk list
                  ..._disks.map((disk) {
                    final isSelected =
                        _selectedDisk?.diskNumber == disk.diskNumber;
                    return Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        leading: Icon(
                          Icons.usb,
                          color: isSelected
                              ? Theme.of(context).colorScheme.primary
                              : Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                        title: Text(
                          disk.friendlyName,
                          style: Theme.of(context).textTheme.titleSmall
                              ?.copyWith(fontWeight: FontWeight.w600),
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${disk.sizeFormatted} • ${disk.busType}',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                            if (disk.serialNumber.isNotEmpty)
                              Text(
                                '${tr(context, 'creator_serial')}: ${disk.serialNumber}',
                                style: Theme.of(context).textTheme.bodySmall
                                    ?.copyWith(
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.onSurfaceVariant,
                                    ),
                              ),
                          ],
                        ),
                        trailing: isSelected
                            ? Icon(
                                Icons.check_circle,
                                color: Theme.of(context).colorScheme.primary,
                              )
                            : null,
                        onTap: () {
                          setState(() {
                            _selectedDisk = disk;
                            _compatibilityResult = null;
                          });
                          _checkCompatibility(disk);
                        },
                      ),
                    );
                  }),

                  // Compatibility checking indicator
                  if (_isCheckingCompatibility) ...[
                    const SizedBox(height: 16),
                    Center(
                      child: Column(
                        children: [
                          const CircularProgressIndicator(),
                          const SizedBox(height: 8),
                          Text(tr(context, 'wtg_checking_compatibility')),
                        ],
                      ),
                    ),
                  ],

                  // Compatibility result card
                  if (_compatibilityResult != null) ...[
                    const SizedBox(height: 16),
                    _buildCompatibilityCard(),
                  ],

                  // Action buttons
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      FilledButton.icon(
                        onPressed: _selectedDisk != null
                            ? () => setState(() => _currentStep = 4)
                            : null,
                        icon: const Icon(Icons.arrow_forward),
                        label: Text(tr(context, 'wtg_next_confirm')),
                      ),
                      const SizedBox(width: 12),
                      OutlinedButton.icon(
                        onPressed: () => setState(() => _currentStep = 2),
                        icon: const Icon(Icons.arrow_back),
                        label: Text(tr(context, 'creator_back')),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildCompatibilityCard() {
    final result = _compatibilityResult!;
    final gradeColor = _getGradeColor(result.grade);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: gradeColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Center(
                    child: Text(
                      result.gradeText,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        color: gradeColor,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        tr(context, 'wtg_compatibility_grade'),
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        tr(context, result.gradeDescription),
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _InfoRow(tr(context, 'wtg_bus_type'), result.busType),
            _InfoRow(tr(context, 'wtg_usb_version'), result.usbVersion),
            _InfoRow(tr(context, 'creator_size'), result.sizeFormatted),

            // Speed test results
            if (result.speedTestSuccess) ...[
              _InfoRow(
                tr(context, 'wtg_read_speed'),
                '${result.readSpeedMBps} MB/s',
              ),
              _InfoRow(
                tr(context, 'wtg_write_speed'),
                '${result.writeSpeedMBps} MB/s',
              ),
            ] else ...[
              const Divider(),
              Row(
                children: [
                  Icon(
                    Icons.speed,
                    size: 16,
                    color: Theme.of(context).colorScheme.error,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    tr(context, 'wtg_speed_test_failed'),
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.error,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              if (result.speedTestError != null) ...[
                const SizedBox(height: 4),
                Padding(
                  padding: const EdgeInsets.only(left: 24),
                  child: Text(
                    tr(context, result.speedTestError!),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              ],
            ],

            // Warnings
            if (result.warnings.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                tr(context, 'wtg_warnings'),
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: Theme.of(context).colorScheme.error,
                  fontWeight: FontWeight.w600,
                ),
              ),
              ...result.warnings.map(
                (w) => Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.warning_amber_rounded,
                        size: 16,
                        color: Theme.of(context).colorScheme.error,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          tr(context, w),
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: Theme.of(context).colorScheme.error,
                              ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],

            // Recommendations
            if (result.recommendations.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                tr(context, 'wtg_recommendations'),
                style: Theme.of(
                  context,
                ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
              ),
              ...result.recommendations.map(
                (r) => Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.info_outline,
                        size: 16,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          tr(context, r),
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],

            // Debug info section (collapsible)
            if (result.debugLogs.isNotEmpty) ...[
              const SizedBox(height: 12),
              Theme(
                data: Theme.of(
                  context,
                ).copyWith(dividerColor: Colors.transparent),
                child: ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  title: Text(
                    tr(context, 'wtg_debug_info'),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  children: [
                    Container(
                      width: double.infinity,
                      height: 200,
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Theme.of(
                          context,
                        ).colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Scrollbar(
                        child: SingleChildScrollView(
                          child: SelectableText(
                            result.debugLogs.join('\n'),
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(
                                  fontFamily: 'monospace',
                                  fontSize: 10,
                                ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Color _getGradeColor(WtgCompatibilityGrade grade) {
    switch (grade) {
      case WtgCompatibilityGrade.a:
        return Colors.green;
      case WtgCompatibilityGrade.b:
        return Colors.lightGreen;
      case WtgCompatibilityGrade.c:
        return Colors.orange;
      case WtgCompatibilityGrade.d:
        return Colors.deepOrange;
      case WtgCompatibilityGrade.f:
        return Colors.red;
      case WtgCompatibilityGrade.unknown:
        return Colors.grey;
    }
  }

  Widget _buildStep5Confirm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          tr(context, 'wtg_step5_title'),
          style: Theme.of(
            context,
          ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        Text(
          tr(context, 'wtg_step5_desc'),
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 24),
        Expanded(
          child: SingleChildScrollView(
            child: Column(
              children: [
                // ISO Info Card
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          tr(context, 'creator_iso_section'),
                          style: Theme.of(context).textTheme.titleSmall
                              ?.copyWith(fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 12),
                        _InfoRow(
                          tr(context, 'creator_file'),
                          _selectedIso?.fileName ?? '',
                        ),
                        _InfoRow(
                          tr(context, 'creator_version'),
                          _selectedIso?.windowsVersion ??
                              tr(context, 'creator_unknown'),
                        ),
                        _InfoRow(
                          tr(context, 'creator_size'),
                          _selectedIso?.displaySize ?? '',
                        ),
                        if (_selectedImageIndex != null) ...[
                          const Divider(),
                          Text(
                            tr(context, 'wtg_selected_image'),
                            style: Theme.of(context).textTheme.titleSmall
                                ?.copyWith(fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: 8),
                          ..._wimImages
                              .where(
                                (img) => img['index'] == _selectedImageIndex,
                              )
                              .map(
                                (img) => Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      img['name'] ??
                                          tr(
                                            context,
                                            'wtg_image_fallback',
                                          ).replaceAll(
                                            '{index}',
                                            '${img['index']}',
                                          ),
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodyMedium
                                          ?.copyWith(
                                            fontWeight: FontWeight.w600,
                                          ),
                                    ),
                                    if (img['edition'] != null)
                                      Text(
                                        img['edition'],
                                        style: Theme.of(
                                          context,
                                        ).textTheme.bodySmall,
                                      ),
                                  ],
                                ),
                              ),
                        ],
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                // Disk Info Card
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          tr(context, 'creator_usb_section'),
                          style: Theme.of(context).textTheme.titleSmall
                              ?.copyWith(fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 12),
                        _InfoRow(
                          tr(context, 'creator_disk'),
                          '${tr(context, 'wtg_disk_prefix')} ${_selectedDisk?.diskNumber ?? 0}',
                        ),
                        _InfoRow(
                          tr(context, 'creator_model'),
                          _selectedDisk?.friendlyName ?? '',
                        ),
                        _InfoRow(
                          tr(context, 'creator_serial'),
                          _selectedDisk?.serialNumber ?? '',
                        ),
                        _InfoRow(
                          tr(context, 'creator_size'),
                          _selectedDisk?.sizeFormatted ?? '',
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                // Warning Card
                Card(
                  color: Theme.of(context).colorScheme.errorContainer,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        Icon(
                          Icons.warning_amber_rounded,
                          size: 32,
                          color: Theme.of(context).colorScheme.error,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          tr(context, 'creator_warning'),
                          style: Theme.of(context).textTheme.titleSmall
                              ?.copyWith(
                                color: Theme.of(context).colorScheme.error,
                                fontWeight: FontWeight.bold,
                              ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                // Confirmation Input
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          tr(context, 'erase_title'),
                          style: Theme.of(context).textTheme.titleSmall
                              ?.copyWith(fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '${tr(context, 'erase_desc_prefix')} ${tr(context, 'wtg_erase_confirm_word')} ${tr(context, 'erase_desc_suffix')}',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _confirmController,
                          decoration: InputDecoration(
                            hintText: tr(context, 'wtg_erase_confirm_word'),
                            border: const OutlineInputBorder(),
                          ),
                          onChanged: (value) {
                            setState(() {
                              _isConfirmValid =
                                  value.trim() ==
                                  tr(context, 'wtg_erase_confirm_word');
                            });
                          },
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            FilledButton.icon(
              onPressed: _isConfirmValid ? _startWtgCreation : null,
              icon: const Icon(Icons.play_arrow),
              label: Text(tr(context, 'wtg_start_creation')),
            ),
            const SizedBox(width: 12),
            OutlinedButton.icon(
              onPressed: () => setState(() => _currentStep = 3),
              icon: const Icon(Icons.arrow_back),
              label: Text(tr(context, 'creator_back')),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildStep6Progress() {
    final progress = _wtgProgress;
    if (progress == null) return const SizedBox.shrink();

    String stepText;
    switch (progress.step) {
      case WtgStep.preparing:
        stepText = tr(context, 'wtg_step_preparing');
        break;
      case WtgStep.partitioningDisk:
        stepText = tr(context, 'wtg_step_partitioning');
        break;
      case WtgStep.mountingIso:
        stepText = tr(context, 'wtg_step_mounting');
        break;
      case WtgStep.applyingImage:
        stepText = tr(context, 'wtg_step_applying');
        break;
      case WtgStep.writingBootFiles:
        stepText = tr(context, 'wtg_step_boot');
        break;
      case WtgStep.verifying:
        stepText = tr(context, 'wtg_step_verifying');
        break;
      case WtgStep.complete:
        stepText = tr(context, 'step_complete');
        break;
      case WtgStep.failed:
        stepText = tr(context, 'step_failed');
        break;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          tr(context, 'wtg_step6_title'),
          style: Theme.of(
            context,
          ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        Text(
          tr(context, 'wtg_step6_desc'),
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 24),
        Expanded(
          child: Center(
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (progress.step != WtgStep.complete &&
                        progress.step != WtgStep.failed) ...[
                      const CircularProgressIndicator(),
                      const SizedBox(height: 24),
                    ] else if (progress.step == WtgStep.complete) ...[
                      Icon(Icons.check_circle, size: 64, color: Colors.green),
                      const SizedBox(height: 24),
                    ] else ...[
                      Icon(
                        Icons.error_outline,
                        size: 64,
                        color: Theme.of(context).colorScheme.error,
                      ),
                      const SizedBox(height: 24),
                    ],
                    Text(
                      stepText,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: 400,
                      child: LinearProgressIndicator(
                        value: progress.progress,
                        backgroundColor: Theme.of(
                          context,
                        ).colorScheme.surfaceContainerHighest,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '${(progress.progress * 100).toStringAsFixed(0)}%',
                      style: Theme.of(context).textTheme.headlineMedium
                          ?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    // Progress details (only during applying image)
                    if (progress.step == WtgStep.applyingImage) ...[
                      const SizedBox(height: 16),
                      _buildProgressDetails(progress),
                    ],
                    if (progress.currentFile != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        progress.currentFile!,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                    if (progress.message.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      Text(
                        _resolveLocalizedMessage(context, progress.message),
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: progress.step == WtgStep.failed
                              ? Theme.of(context).colorScheme.error
                              : Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildProgressDetails(WtgProgress progress) {
    final elapsed = _progressStopwatch?.elapsed ?? progress.elapsedTime;
    final formattedElapsed = _formatElapsed(elapsed ?? Duration.zero);

    return SizedBox(
      width: 560,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Theme.of(
            context,
          ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: _ProgressDetailItem(
                icon: Icons.timer_outlined,
                label: tr(context, 'wtg_elapsed'),
                value: formattedElapsed,
              ),
            ),
            const SizedBox(width: 20),
            _IdleGamePanel(
              activeIndex: _idleGameTarget,
              score: _idleGameScore,
              onTileTap: _handleIdleGameTap,
            ),
          ],
        ),
      ),
    );
  }

  String _formatElapsed(Duration elapsed) {
    final hours = elapsed.inHours.toString().padLeft(2, '0');
    final minutes = (elapsed.inMinutes % 60).toString().padLeft(2, '0');
    final seconds = (elapsed.inSeconds % 60).toString().padLeft(2, '0');
    return '$hours:$minutes:$seconds';
  }

  void _handleIdleGameTap(int index) {
    if (index != _idleGameTarget) return;
    setState(() {
      _idleGameScore++;
      var nextTarget = _idleGameRandom.nextInt(9);
      if (nextTarget == _idleGameTarget) {
        nextTarget = (nextTarget + 1) % 9;
      }
      _idleGameTarget = nextTarget;
    });
  }

  Widget _buildStepComplete() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          tr(context, 'wtg_step_complete_title'),
          style: Theme.of(
            context,
          ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        Text(
          tr(context, 'wtg_step_complete_desc'),
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 24),
        Expanded(
          child: Center(
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.check_circle, size: 64, color: Colors.green),
                    const SizedBox(height: 24),
                    Text(
                      tr(context, 'wtg_creation_complete'),
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      tr(context, 'wtg_creation_complete_desc'),
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            FilledButton.icon(
              onPressed: () {
                setState(() {
                  _currentStep = 0;
                  _selectedIso = null;
                  _selectedDisk = null;
                  _wimImages = [];
                  _selectedImageIndex = null;
                  _compatibilityResult = null;
                  _wtgProgress = null;
                  _confirmController.clear();
                  _isConfirmValid = false;
                });
              },
              icon: const Icon(Icons.refresh),
              label: Text(tr(context, 'creator_another')),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildStepFailed() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          tr(context, 'wtg_step_failed_title'),
          style: Theme.of(
            context,
          ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        Text(
          tr(context, 'wtg_step_failed_desc'),
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 24),
        Expanded(
          child: Center(
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.error_outline,
                      size: 64,
                      color: Theme.of(context).colorScheme.error,
                    ),
                    const SizedBox(height: 24),
                    Text(
                      tr(context, 'wtg_creation_failed'),
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        color: Theme.of(context).colorScheme.error,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    if (_wtgProgress?.message != null) ...[
                      Text(
                        _resolveLocalizedMessage(
                          context,
                          _wtgProgress!.message,
                        ),
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.error,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            FilledButton.icon(
              onPressed: () {
                setState(() {
                  _currentStep = 0;
                  _selectedIso = null;
                  _selectedDisk = null;
                  _wimImages = [];
                  _selectedImageIndex = null;
                  _compatibilityResult = null;
                  _wtgProgress = null;
                  _confirmController.clear();
                  _isConfirmValid = false;
                });
              },
              icon: const Icon(Icons.refresh),
              label: Text(tr(context, 'creator_another')),
            ),
            const SizedBox(width: 12),
            OutlinedButton.icon(
              onPressed: () => setState(() => _currentStep = 4),
              icon: const Icon(Icons.arrow_back),
              label: Text(tr(context, 'creator_back')),
            ),
          ],
        ),
      ],
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;

  const _InfoRow(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          Text(
            value,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final String label;

  const _Chip({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

class _ProgressDetailItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _ProgressDetailItem({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 18, color: Theme.of(context).colorScheme.primary),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              Text(
                value,
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _IdleGamePanel extends StatelessWidget {
  final int activeIndex;
  final int score;
  final ValueChanged<int> onTileTap;

  const _IdleGamePanel({
    required this.activeIndex,
    required this.score,
    required this.onTileTap,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return SizedBox(
      width: 132,
      child: Row(
        children: [
          SizedBox(
            width: 78,
            height: 78,
            child: GridView.builder(
              physics: const NeverScrollableScrollPhysics(),
              padding: EdgeInsets.zero,
              itemCount: 9,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                mainAxisSpacing: 6,
                crossAxisSpacing: 6,
              ),
              itemBuilder: (context, index) {
                final isActive = index == activeIndex;
                return Material(
                  color: isActive
                      ? colorScheme.primary
                      : colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(6),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(6),
                    onTap: () => onTileTap(index),
                    child: Center(
                      child: AnimatedScale(
                        scale: isActive ? 1 : 0.75,
                        duration: const Duration(milliseconds: 140),
                        child: Icon(
                          Icons.circle,
                          size: 8,
                          color: isActive
                              ? colorScheme.onPrimary
                              : colorScheme.outlineVariant,
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.sports_esports_outlined,
                  size: 20,
                  color: colorScheme.primary,
                ),
                const SizedBox(height: 6),
                Text(
                  score.toString(),
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
