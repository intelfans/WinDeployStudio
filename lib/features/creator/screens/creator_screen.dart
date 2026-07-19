import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import '../../../core/localization/strings.dart';
import '../../../core/services/disk_safety_service.dart';
import '../../../core/services/iso_parse_service.dart';
import '../../../core/services/known_iso_verification_service.dart';
import '../../../core/services/linux_media_preflight.dart';
import '../../../core/services/bootable_usb_service.dart';
import '../../../shared/widgets/known_iso_verification_panel.dart';
import '../../deployment/models/deployment_plan.dart';
import '../../logs/services/log_center_service.dart';
import '../models/creator_progress_message.dart';
import '../models/creator_task_progress.dart';

enum _CreatorPlatform { windows, linux }

class CreatorScreen extends ConsumerStatefulWidget {
  const CreatorScreen({super.key});

  @override
  ConsumerState<CreatorScreen> createState() => _CreatorScreenState();
}

class _CreatorScreenState extends ConsumerState<CreatorScreen> {
  late final IsoParseService _isoParseService;
  int _currentStep = 0;
  _CreatorPlatform _platform = _CreatorPlatform.windows;

  IsoMetadata? _selectedIso;
  DiskInfo? _selectedDisk;

  List<DiskInfo> _disks = [];
  bool _isDetecting = false;

  SafetyCheckResult? _safetyResult;

  CreateProgress? _createProgress;
  BootableUsbService? _creationService;
  bool _creationRunning = false;
  bool _creationCancellable = false;
  bool _creationCancelled = false;
  bool _creationCancelRequested = false;

  DeploymentBootMode _bootMode = DeploymentBootMode.uefiGpt;
  String _preferredDriveLetter = '';
  String _customIconPath = '';
  final TextEditingController _volumeLabelController = TextEditingController(
    text: 'WINDEPLOY',
  );

  // ISO parsing state (inline, no dialog)
  bool _isParsing = false;
  String _parseStepText = '';
  int _parsePercent = 0;
  String? _isoSelectionErrorKey;
  KnownIsoVerification? _knownIsoVerification;
  LinuxIsoHybridInspection? _linuxIsoInspection;
  int _knownIsoVerificationRequest = 0;
  Locale? _knownIsoVerificationLocale;
  int _isoSelectionRequest = 0;
  LinuxIsoHybridInspectionCancellationToken? _linuxInspectionCancellation;

  @override
  void initState() {
    super.initState();
    // Cache the provider instance while the element is mounted. Riverpod
    // cannot be read from dispose(), after the element has been unmounted.
    _isoParseService = ref.read(isoParseServiceProvider);
    _detectDisks();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final locale = Localizations.localeOf(context);
    if (_knownIsoVerificationLocale == locale) return;
    _knownIsoVerificationLocale = locale;

    final iso = _selectedIso;
    if (iso == null) {
      _knownIsoVerification = null;
      _linuxIsoInspection = null;
      return;
    }
    final request = ++_knownIsoVerificationRequest;
    _knownIsoVerification = null;
    unawaited(_verifyKnownIso(iso.filePath, request, locale));
  }

  @override
  void dispose() {
    _cancelLinuxInspection();
    unawaited(_isoParseService.cancel());
    _volumeLabelController.dispose();
    super.dispose();
  }

  bool get _isLinuxMode => _platform == _CreatorPlatform.linux;

  void _setPlatform(_CreatorPlatform platform) {
    if (_platform == platform || _creationRunning) return;
    _cancelLinuxInspection();
    unawaited(ref.read(isoParseServiceProvider).cancel());
    setState(() {
      _platform = platform;
      _currentStep = 0;
      _selectedIso = null;
      _selectedDisk = null;
      _safetyResult = null;
      _createProgress = null;
      _creationService = null;
      _creationCancellable = false;
      _creationCancelled = false;
      _creationCancelRequested = false;
      _isParsing = false;
      _parseStepText = '';
      _parsePercent = 0;
      _isoSelectionErrorKey = null;
      _knownIsoVerification = null;
      _knownIsoVerificationRequest++;
      _isoSelectionRequest++;
    });
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
        await logCenter.logUsb(
          '  磁盘 ${disk.diskNumber}: ${disk.model} | 容量: ${disk.sizeFormatted} | 总线: ${disk.busType} | 序列号: ${disk.serialNumber} | 分区表: ${disk.partitionStyle} | 盘符: ${disk.driveLetters.join(", ")}',
        );
      }
    } catch (e) {
      debugPrint('Detect disks error: $e');
      if (!mounted) return;
      setState(() => _isDetecting = false);
    }
  }

  Future<void> _selectIsoFile() async {
    int? activeSelectionRequest;
    bool? activeLinuxMode;
    try {
      final result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['iso'],
        dialogTitle: tr(
          context,
          _isLinuxMode ? 'creator_linux_select_iso' : 'creator_select_iso',
        ),
      );

      if (result == null || result.files.single.path == null) return;
      final path = result.files.single.path!;
      debugPrint('ISO selected: $path');

      if (!mounted) return;

      _cancelLinuxInspection();
      final selectedLinuxMode = _isLinuxMode;
      final selectionRequest = ++_isoSelectionRequest;
      activeSelectionRequest = selectionRequest;
      activeLinuxMode = selectedLinuxMode;
      final verificationRequest = ++_knownIsoVerificationRequest;
      setState(() {
        _isParsing = true;
        _parseStepText = tr(context, 'creator_parsing');
        _parsePercent = 0;
        _isoSelectionErrorKey = null;
        _selectedIso = null;
        _linuxIsoInspection = null;
        _knownIsoVerification = null;
      });
      final selectedLocale = Localizations.localeOf(context);

      final isoService = ref.read(isoParseServiceProvider);
      IsoMetadata? metadata;

      try {
        metadata = await isoService
            .parseIso(
              path,
              onProgress: (step, percent) {
                if (!_isCurrentIsoSelection(
                  selectionRequest,
                  selectedLinuxMode,
                )) {
                  return;
                }
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
            .timeout(
              selectedLinuxMode
                  ? const Duration(seconds: 60)
                  : const Duration(seconds: 120),
              onTimeout: () async {
                debugPrint('ISO parse overall timeout');
                if (_isCurrentIsoSelection(
                  selectionRequest,
                  selectedLinuxMode,
                )) {
                  // Wait for the old mount/helper process and dismount to
                  // settle before re-enabling the picker. Otherwise a quick
                  // second click is queued behind stale cleanup and appears
                  // to be ignored.
                  await isoService.cancel();
                }
                return null;
              },
            );
      } catch (e) {
        debugPrint('ISO parse error: $e');
      }

      if (!_isCurrentIsoSelection(selectionRequest, selectedLinuxMode)) {
        return;
      }

      if (metadata == null) {
        _showIsoSelectionError('creator_parse_error');
        return;
      }

      if (selectedLinuxMode) {
        if (metadata.isValidWindowsIso) {
          _showIsoSelectionError('creator_windows_iso_in_linux_mode');
          return;
        }
        final inspectionCancellation =
            LinuxIsoHybridInspectionCancellationToken();
        _linuxInspectionCancellation = inspectionCancellation;
        setState(() {
          // Keep the existing cancellable progress surface visible while the
          // Linux ISOHybrid structure is inspected. This inspection only reads
          // bounded portions of the image, but may still wait on slow media.
          _parseStepText = tr(context, 'creator_parsing');
          _parsePercent = 100;
        });
        final linuxInspection =
            await LinuxIsoHybridInspector.inspect(
              path,
              cancellationToken: inspectionCancellation,
            ).timeout(
              const Duration(seconds: 30),
              onTimeout: () {
                inspectionCancellation.cancel();
                return const LinuxIsoHybridInspection.failure(
                  'ISOHybrid structure inspection timed out.',
                );
              },
            );
        if (identical(_linuxInspectionCancellation, inspectionCancellation)) {
          _linuxInspectionCancellation = null;
        }
        if (!_isCurrentIsoSelection(selectionRequest, selectedLinuxMode)) {
          return;
        }
        setState(() => _isParsing = false);
        if (linuxInspection.wasCancelled) return;
        if (!linuxInspection.isValid) {
          debugPrint(
            'Linux ISOHybrid inspection rejected $path: '
            '${linuxInspection.error}',
          );
          _showIsoSelectionError('linux_not_isohybrid');
          return;
        }
        final linuxMetadata = IsoMetadata(
          filePath: metadata.filePath,
          fileName: metadata.fileName,
          fileSize: metadata.fileSize,
          windowsVersion: 'Linux ISOHybrid',
        );
        setState(() {
          _selectedIso = linuxMetadata;
          _linuxIsoInspection = linuxInspection;
          _currentStep = 1;
          _isoSelectionErrorKey = null;
        });
        final logCenter = LogCenterService();
        await logCenter.logIso(
          'Linux ISO 已选择 | 文件: ${linuxMetadata.fileName} | 大小: ${linuxMetadata.displaySize}',
        );
        if (!_isCurrentIsoSelection(selectionRequest, selectedLinuxMode)) {
          return;
        }
        unawaited(
          _verifyKnownIso(
            linuxMetadata.filePath,
            verificationRequest,
            selectedLocale,
          ),
        );
        return;
      }

      setState(() => _isParsing = false);

      if (!metadata.isValidWindowsIso) {
        _showIsoSelectionError('creator_invalid_windows_iso');
        return;
      }

      setState(() {
        _selectedIso = metadata;
        _linuxIsoInspection = null;
        _currentStep = 1;
        _isoSelectionErrorKey = null;
        _bootMode = _preferredBootModeForIso(metadata!);
      });
      unawaited(
        _verifyKnownIso(metadata.filePath, verificationRequest, selectedLocale),
      );
      final logCenter = LogCenterService();
      await logCenter.logIso(
        'ISO 已选择 | 文件: ${metadata.fileName} | 版本: ${metadata.windowsVersion ?? "未知"} | 构建: ${metadata.buildNumber ?? "未知"}',
      );
    } catch (e) {
      debugPrint('ISO select error: $e');
      if (!mounted ||
          (activeSelectionRequest != null &&
              activeLinuxMode != null &&
              !_isCurrentIsoSelection(
                activeSelectionRequest,
                activeLinuxMode,
              ))) {
        return;
      }
      _showIsoSelectionError('creator_error');
    }
  }

  bool _isCurrentIsoSelection(int request, bool isLinuxMode) {
    return mounted &&
        request == _isoSelectionRequest &&
        _isLinuxMode == isLinuxMode;
  }

  DeploymentBootMode _preferredBootModeForIso(IsoMetadata iso) {
    if (!iso.canBootUefi && iso.canBootLegacy) {
      return DeploymentBootMode.legacyBios;
    }
    if (!iso.canBootLegacy && iso.canBootUefi) {
      return DeploymentBootMode.uefiGpt;
    }
    return _bootMode;
  }

  void _showIsoSelectionError(String messageKey) {
    if (!mounted) return;
    setState(() {
      _isParsing = false;
      _isoSelectionErrorKey = messageKey;
    });
  }

  Future<void> _verifyKnownIso(
    String filePath,
    int request,
    Locale locale,
  ) async {
    final verification = await ref
        .read(knownIsoVerificationServiceProvider)
        .verify(filePath, locale);
    if (!mounted ||
        request != _knownIsoVerificationRequest ||
        _selectedIso?.filePath != filePath ||
        Localizations.localeOf(context) != locale ||
        verification == null) {
      return;
    }
    setState(() => _knownIsoVerification = verification);
  }

  void _cancelParsing() {
    _isoSelectionRequest++;
    _cancelLinuxInspection();
    unawaited(ref.read(isoParseServiceProvider).cancel());
    if (mounted) {
      setState(() => _isParsing = false);
    }
  }

  void _cancelLinuxInspection() {
    final cancellation = _linuxInspectionCancellation;
    _linuxInspectionCancellation = null;
    cancellation?.cancel();
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

  Future<void> _pickCustomIcon() async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['ico'],
      dialogTitle: tr(context, 'deploy_custom_icon'),
    );
    final path = result?.files.single.path;
    if (path != null && mounted) setState(() => _customIconPath = path);
  }

  Future<void> _startCreation() async {
    debugPrint(
      '[WDS] _startCreation called: disk=${_selectedDisk?.diskNumber}, iso=${_selectedIso?.fileName}',
    );
    final disk = _selectedDisk;
    final iso = _selectedIso;
    if (disk == null || iso == null) {
      debugPrint('[WDS] _startCreation: disk or iso is null, returning');
      return;
    }

    final isLinuxMode = _isLinuxMode;
    final service = ref.read(bootableUsbServiceProvider);
    setState(() {
      _currentStep = 3;
      _creationRunning = true;
      _creationCancellable = false;
      _creationCancelled = false;
      _creationCancelRequested = false;
      _creationService = service;
      // Progress messages are localization keys. Resolving this here would make
      // the renderer attempt a second lookup using the translated text as a key.
      _createProgress = const CreateProgress(
        step: CreateStep.preparing,
        message: 'creator_starting',
      );
    });
    debugPrint('[WDS] _startCreation: step set to 3');

    try {
      final plan = DeploymentPlan(
        platform: isLinuxMode
            ? DeploymentPlatform.linux
            : DeploymentPlatform.windows,
        purpose: DeploymentPurpose.installMedia,
        imagePath: iso.filePath,
        imageName: iso.fileName,
        imageBuild: iso.buildNumber ?? '',
        imageArchitecture: iso.architecture ?? '',
        windowsGeneration: DeploymentPlan.detectWindowsGeneration(
          build: iso.buildNumber ?? '',
          version: iso.windowsVersion ?? '',
        ),
        bootMode: _bootMode,
        preferredSystemLetter: _preferredDriveLetter,
        customIconPath: _customIconPath,
        customVolumeLabel: _volumeLabelController.text.trim(),
      );
      final compatibility = DeploymentCompatibility.evaluate(plan);
      if (!compatibility.canDeploy) {
        _finishCreation(
          success: false,
          latestProgress: CreateProgress(
            step: CreateStep.failed,
            message: compatibility.errors.isEmpty
                ? 'deploy_compat_install_direct_only'
                : compatibility.errors.first.messageKey,
          ),
        );
        return;
      }

      final operationLock = await DiskOperationLock.tryAcquire(disk.diskNumber);
      if (operationLock == null) {
        _finishCreation(
          success: false,
          latestProgress: const CreateProgress(
            step: CreateStep.failed,
            message: 'safety_disk_busy',
          ),
        );
        return;
      }

      bool success;
      try {
        success = isLinuxMode
            ? await service.createLinuxIsoUsb(
                disk: disk,
                isoPath: iso.filePath,
                kind: LinuxUsbKind.installMedia,
                deploymentPlan: plan,
                onProgress: _onCreationProgress,
              )
            : await service.createBootableUsb(
                disk: disk,
                isoPath: iso.filePath,
                deploymentPlan: plan,
                onProgress: _onCreationProgress,
              );
      } finally {
        await operationLock.release();
      }

      debugPrint('[WDS] _startCreation: direct task returned: $success');
      _finishCreation(
        success: success,
        cancelRequested:
            _creationCancelRequested || (isLinuxMode && service.isCancelled),
      );
    } catch (e, st) {
      debugPrint('[WDS] _startCreation exception: $e');
      debugPrint('[WDS] stacktrace: $st');
      _finishCreation(
        success: false,
        cancelRequested: _creationCancelRequested,
        latestProgress: CreateProgress(
          step: CreateStep.failed,
          message: _creationCancelRequested
              ? 'deploy_cancel_requested'
              : 'creator_error\n$e',
        ),
      );
    }
  }

  void _onCreationProgress(CreateProgress progress) {
    if (!mounted) return;
    setState(() {
      final current = _createProgress;
      final preserveDetailedFailure =
          progress.step == CreateStep.failed &&
          progress.message == 'creator_error' &&
          current?.step == CreateStep.failed &&
          current!.message.isNotEmpty &&
          current.message != 'creator_error';
      if (!preserveDetailedFailure) {
        _createProgress = progress;
      }
      _creationCancellable =
          _isLinuxMode &&
          (progress.step == CreateStep.copyingFiles ||
              progress.step == CreateStep.verifying);
    });
  }

  void _finishCreation({
    required bool success,
    bool cancelRequested = false,
    CreateProgress? latestProgress,
  }) {
    if (!mounted) return;
    final terminal = finishCreatorTask(
      success: success,
      latestProgress: latestProgress ?? _createProgress,
      cancelRequested: cancelRequested,
    );
    setState(() {
      _creationRunning = false;
      _creationCancellable = false;
      _creationCancelled = terminal.cancelled;
      _creationService = null;
      _createProgress = terminal.progress;
      _currentStep = terminal.success ? 4 : 3;
    });
    debugPrint('[WDS] _startCreation: final step = $_currentStep');
  }

  void _cancelCreation() {
    final service = _creationService;
    if (service == null || _creationCancelRequested) return;
    service.cancel();
    if (!mounted) return;
    setState(() {
      _creationCancelRequested = true;
      _creationCancelled = true;
      _creationCancellable = false;
      _createProgress = CreateProgress(
        step: _createProgress?.step ?? CreateStep.preparing,
        progress: _createProgress?.progress ?? 0,
        message: 'deploy_cancel_requested',
      );
    });
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
              tr(
                context,
                _isLinuxMode ? 'creator_linux_title' : 'creator_title',
              ),
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              tr(
                context,
                _isLinuxMode ? 'creator_linux_subtitle' : 'creator_subtitle',
              ),
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            _buildPlatformSelector(),
            const SizedBox(height: 24),
            _buildStepIndicator(),
            const SizedBox(height: 24),
            _buildStepContent(),
          ],
        ),
      ),
    );
  }

  Widget _buildPlatformSelector() {
    return SegmentedButton<_CreatorPlatform>(
      segments: [
        ButtonSegment(
          value: _CreatorPlatform.windows,
          icon: const Icon(Icons.window),
          label: Text(tr(context, 'creator_platform_windows')),
        ),
        ButtonSegment(
          value: _CreatorPlatform.linux,
          icon: const Icon(Icons.terminal),
          label: Text(tr(context, 'creator_platform_linux')),
        ),
      ],
      selected: {_platform},
      onSelectionChanged: _creationRunning
          ? null
          : (selection) => _setPlatform(selection.first),
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
                    value: _parsePercent > 0 ? _parsePercent / 100.0 : null,
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
                  Text('$_parsePercent%', style: theme.textTheme.bodySmall),
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
              Text(
                tr(
                  context,
                  _isLinuxMode
                      ? 'creator_linux_select_iso'
                      : 'creator_select_iso',
                ),
                style: theme.textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              Text(
                tr(
                  context,
                  _isLinuxMode
                      ? 'creator_linux_select_iso_desc'
                      : 'creator_select_iso_desc',
                ),
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 14),
              _CreatorNotice(
                icon: Icons.info_outline,
                text: tr(
                  context,
                  _isLinuxMode
                      ? 'creator_linux_install_iso_required'
                      : 'creator_windows_install_iso_required',
                ),
              ),
              if (_isoSelectionErrorKey != null) ...[
                const SizedBox(height: 16),
                _IsoSelectionError(
                  message: tr(context, _isoSelectionErrorKey!),
                ),
              ],
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: _selectIsoFile,
                icon: const Icon(Icons.folder_open),
                label: Text(tr(context, 'creator_select_btn')),
              ),
              if (_selectedIso != null && _isoSelectionErrorKey == null) ...[
                const SizedBox(height: 16),
                const Divider(),
                const SizedBox(height: 12),
                _IsoInfoCard(iso: _selectedIso!),
                if (_isLinuxMode && _linuxIsoInspection != null) ...[
                  const SizedBox(height: 12),
                  _LinuxIsoHybridCapabilityPanel(
                    inspection: _linuxIsoInspection!,
                  ),
                ],
                if (_knownIsoVerification != null) ...[
                  const SizedBox(height: 12),
                  KnownIsoVerificationPanel(
                    verification: _knownIsoVerification,
                    iso: _selectedIso,
                  ),
                ],
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
          if (_isLinuxMode && _linuxIsoInspection != null) ...[
            const SizedBox(height: 12),
            _LinuxIsoHybridCapabilityPanel(inspection: _linuxIsoInspection!),
          ],
          if (_knownIsoVerification != null) ...[
            const SizedBox(height: 12),
            KnownIsoVerificationPanel(
              verification: _knownIsoVerification,
              iso: _selectedIso,
            ),
          ],
          const SizedBox(height: 16),
        ],
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              tr(context, 'creator_select_usb'),
              style: theme.textTheme.titleMedium,
            ),
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
                    Icon(
                      Icons.usb_off,
                      size: 48,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
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
                Text(
                  tr(
                    context,
                    _isLinuxMode
                        ? 'creator_linux_confirm_title'
                        : 'creator_confirm_title',
                  ),
                  style: theme.textTheme.titleLarge,
                ),
                const SizedBox(height: 16),
                _ConfirmSection(
                  title: tr(context, 'creator_iso_section'),
                  rows: [
                    _ConfirmRow(
                      label: tr(context, 'creator_file'),
                      value: _selectedIso?.fileName ?? '-',
                    ),
                    _ConfirmRow(
                      label: tr(context, 'creator_version'),
                      value:
                          _selectedIso?.windowsVersion ??
                          tr(context, 'creator_unknown'),
                    ),
                    _ConfirmRow(
                      label: tr(context, 'creator_size'),
                      value: _selectedIso?.displaySize ?? '-',
                    ),
                  ],
                ),
                if (_knownIsoVerification != null) ...[
                  const SizedBox(height: 12),
                  KnownIsoVerificationPanel(
                    verification: _knownIsoVerification,
                    iso: _selectedIso,
                  ),
                ],
                if (_isLinuxMode && _linuxIsoInspection != null) ...[
                  const SizedBox(height: 12),
                  _LinuxIsoHybridCapabilityPanel(
                    inspection: _linuxIsoInspection!,
                  ),
                ],
                const Divider(),
                _ConfirmSection(
                  title: tr(context, 'creator_usb_section'),
                  rows: [
                    _ConfirmRow(
                      label: tr(context, 'creator_disk'),
                      value:
                          '${tr(context, 'creator_disk_prefix')} ${_selectedDisk?.diskNumber}',
                    ),
                    _ConfirmRow(
                      label: tr(context, 'creator_model'),
                      value: _selectedDisk?.model ?? '-',
                    ),
                    _ConfirmRow(
                      label: tr(context, 'creator_size'),
                      value: _selectedDisk?.sizeFormatted ?? '-',
                    ),
                    _ConfirmRow(
                      label: tr(context, 'creator_serial'),
                      value: _selectedDisk?.serialNumber ?? '-',
                    ),
                  ],
                ),
                if (!_isLinuxMode) ...[
                  const Divider(),
                  ExpansionTile(
                    tilePadding: EdgeInsets.zero,
                    title: Text(tr(context, 'deploy_install_options')),
                    subtitle: Text(
                      '${_bootModeLabel(_bootMode)} • ${_preferredDriveLetter.isEmpty ? tr(context, 'deploy_auto') : '$_preferredDriveLetter:'}',
                    ),
                    children: [
                      Align(
                        alignment: Alignment.centerLeft,
                        child: SegmentedButton<DeploymentBootMode>(
                          segments: [
                            ButtonSegment(
                              value: DeploymentBootMode.uefiGpt,
                              label: Text(tr(context, 'deploy_boot_uefi_gpt')),
                              enabled: _selectedIso?.canBootUefi ?? true,
                            ),
                            ButtonSegment(
                              value: DeploymentBootMode.uefiMbr,
                              label: Text(tr(context, 'deploy_boot_uefi_mbr')),
                              enabled: _selectedIso?.canBootUefi ?? true,
                            ),
                            ButtonSegment(
                              value: DeploymentBootMode.legacyBios,
                              label: Text(tr(context, 'deploy_boot_legacy')),
                              enabled: _selectedIso?.canBootLegacy ?? true,
                            ),
                          ],
                          selected: {_bootMode},
                          onSelectionChanged: (value) =>
                              setState(() => _bootMode = value.first),
                        ),
                      ),
                      if (_selectedIso != null &&
                          (!_selectedIso!.canBootUefi ||
                              !_selectedIso!.canBootLegacy)) ...[
                        const SizedBox(height: 8),
                        _CreatorNotice(
                          icon: Icons.info_outline,
                          text: tr(
                            context,
                            _selectedIso!.canBootUefi
                                ? 'deploy_image_uefi_only'
                                : 'deploy_image_legacy_only',
                          ),
                        ),
                      ],
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        initialValue: _preferredDriveLetter,
                        decoration: InputDecoration(
                          labelText: tr(context, 'deploy_system_letter'),
                        ),
                        items: [
                          DropdownMenuItem(
                            value: '',
                            child: Text(tr(context, 'deploy_auto')),
                          ),
                          ...List.generate(23, (index) {
                            final letter = String.fromCharCode(68 + index);
                            return DropdownMenuItem(
                              value: letter,
                              child: Text('$letter:'),
                            );
                          }),
                        ],
                        onChanged: (value) =>
                            setState(() => _preferredDriveLetter = value ?? ''),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        key: const Key('creator-volume-label'),
                        controller: _volumeLabelController,
                        maxLength: 11,
                        decoration: InputDecoration(
                          labelText: tr(context, 'deploy_volume_label'),
                        ),
                      ),
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.image_outlined),
                        title: Text(tr(context, 'deploy_custom_icon')),
                        subtitle: Text(
                          _customIconPath.trim().isEmpty
                              ? tr(context, 'deploy_custom_icon_default')
                              : _customIconPath,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (_customIconPath.trim().isNotEmpty)
                              IconButton(
                                key: const Key('creator-icon-clear'),
                                tooltip: tr(
                                  context,
                                  'deploy_clear_custom_icon',
                                ),
                                onPressed: () =>
                                    setState(() => _customIconPath = ''),
                                icon: const Icon(Icons.close),
                              ),
                            IconButton(
                              key: const Key('creator-icon-picker'),
                              tooltip: tr(context, 'deploy_custom_icon'),
                              onPressed: _pickCustomIcon,
                              icon: const Icon(Icons.folder_open),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.errorContainer,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.warning_amber, color: theme.colorScheme.error),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          tr(
                            context,
                            _isLinuxMode
                                ? 'creator_linux_warning'
                                : 'creator_warning',
                          ),
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

  String _resolveLocalizedMessage(
    BuildContext context,
    String rawMessage, {
    String? error,
  }) {
    return resolveCreatorProgressMessage(
      rawMessage: rawMessage,
      error: error,
      translate: (key) => tr(context, key),
    );
  }

  String _bootModeLabel(DeploymentBootMode mode) => switch (mode) {
    DeploymentBootMode.uefiGpt => tr(context, 'deploy_boot_uefi_gpt'),
    DeploymentBootMode.uefiMbr => tr(context, 'deploy_boot_uefi_mbr'),
    DeploymentBootMode.legacyBios => tr(context, 'deploy_boot_legacy'),
  };

  // --- Step 3: Creating ---

  Widget _buildCreatingStep() {
    final theme = Theme.of(context);
    final progress = _createProgress;
    final rawMessage = progress?.message ?? 'step_preparing';
    final message = _resolveLocalizedMessage(
      context,
      rawMessage,
      error: progress?.error,
    );
    final pct = ((progress?.progress ?? 0) * 100).toInt();
    final isFailed = progress?.step == CreateStep.failed;

    return Center(
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_knownIsoVerification != null) ...[
                KnownIsoVerificationPanel(
                  verification: _knownIsoVerification,
                  iso: _selectedIso,
                ),
                const SizedBox(height: 24),
              ],
              if (isFailed) ...[
                Icon(
                  Icons.error_outline,
                  size: 48,
                  color: theme.colorScheme.error,
                ),
                const SizedBox(height: 16),
                Text(
                  tr(
                    context,
                    _creationCancelled ? 'cancel_title' : 'step_failed',
                  ),
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: theme.colorScheme.error,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  message,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    OutlinedButton(
                      onPressed: () => setState(() => _currentStep = 2),
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
                    context,
                    progress?.step ?? CreateStep.preparing,
                  ),
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  message,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
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
                if (_creationRunning && _creationCancellable) ...[
                  const SizedBox(height: 16),
                  OutlinedButton.icon(
                    onPressed: _cancelCreation,
                    icon: const Icon(Icons.close),
                    label: Text(tr(context, 'detail_cancel')),
                  ),
                ],
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
        if (_isLinuxMode) {
          return tr(context, 'linux_step_writing_image');
        }
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
    final serverMessage = _resolveLocalizedMessage(
      context,
      _createProgress?.message ??
          (_isLinuxMode ? 'linux_complete' : 'boot_complete'),
    );
    return Center(
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.check_circle,
                size: 64,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(height: 24),
              Text(
                tr(
                  context,
                  _isLinuxMode
                      ? 'creator_linux_complete_title'
                      : 'creator_complete_title',
                ),
                style: theme.textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              Text(
                serverMessage,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
              if (_knownIsoVerification != null) ...[
                const SizedBox(height: 16),
                KnownIsoVerificationPanel(
                  verification: _knownIsoVerification,
                  iso: _selectedIso,
                ),
              ],
              const SizedBox(height: 24),
              FilledButton(
                onPressed: () {
                  setState(() {
                    _currentStep = 0;
                    _selectedIso = null;
                    _linuxIsoInspection = null;
                    _selectedDisk = null;
                    _safetyResult = null;
                    _createProgress = null;
                    _creationService = null;
                    _creationRunning = false;
                    _creationCancellable = false;
                    _creationCancelled = false;
                    _creationCancelRequested = false;
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
                  '${tr(dialogContext, 'erase_desc_prefix')} $confirmWord ${tr(dialogContext, 'erase_desc_suffix')}',
                ),
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
                  decoration: InputDecoration(hintText: confirmWord),
                  onSubmitted: (value) {
                    debugPrint(
                      '[WDS] onSubmitted: value="$value", matches=${matches()}',
                    );
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
                debugPrint(
                  '[WDS] Button pressed: text="${controller.text}", matches=${matches()}',
                );
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

class _LinuxIsoHybridCapabilityPanel extends StatelessWidget {
  final LinuxIsoHybridInspection inspection;

  const _LinuxIsoHybridCapabilityPanel({required this.inspection});

  String _state(BuildContext context, bool available) => tr(
    context,
    available ? 'linux_media_available' : 'linux_media_not_advertised',
  );

  String _architectures(BuildContext context) {
    if (!inspection.hasUefiBoot) {
      return tr(context, 'linux_media_not_advertised');
    }
    if (!inspection.hasKnownEfiArchitecture) {
      return tr(context, 'linux_media_arch_unknown');
    }
    return inspection.efiArchitectures
        .map(
          (architecture) => switch (architecture) {
            LinuxEfiArchitecture.ia32 => 'IA32',
            LinuxEfiArchitecture.x64 => 'x64',
            LinuxEfiArchitecture.arm32 => 'ARM32',
            LinuxEfiArchitecture.arm64 => 'ARM64',
            LinuxEfiArchitecture.riscv64 => 'RISC-V 64',
            LinuxEfiArchitecture.loongarch64 => 'LoongArch64',
          },
        )
        .join(', ');
  }

  String _withValue(BuildContext context, String key, String value) =>
      tr(context, key).replaceAll('{value}', value);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Semantics(
      container: true,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.secondaryContainer.withValues(alpha: 0.52),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: colors.secondary.withValues(alpha: 0.28)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.verified_user_outlined,
                    size: 18,
                    color: colors.onSecondaryContainer,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      tr(context, 'linux_media_capabilities_title'),
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: colors.onSecondaryContainer,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                _withValue(
                  context,
                  'linux_media_legacy_boot',
                  _state(context, inspection.hasLegacyBiosBoot),
                ),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colors.onSecondaryContainer,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                _withValue(
                  context,
                  'linux_media_uefi_boot',
                  _state(context, inspection.hasUefiBoot),
                ),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colors.onSecondaryContainer,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                _withValue(
                  context,
                  'linux_media_efi_architectures',
                  _architectures(context),
                ),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colors.onSecondaryContainer,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                tr(context, 'linux_media_raw_write_notice'),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colors.onSecondaryContainer,
                  height: 1.35,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _IsoSelectionError extends StatelessWidget {
  final String message;

  const _IsoSelectionError({required this.message});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Semantics(
      container: true,
      liveRegion: true,
      child: DecoratedBox(
        key: const Key('creator-iso-selection-error'),
        decoration: BoxDecoration(
          color: colors.errorContainer,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: colors.error.withValues(alpha: 0.55)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.error_outline_rounded,
                color: colors.onErrorContainer,
                semanticLabel: '',
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  message,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: colors.onErrorContainer,
                    fontWeight: FontWeight.w600,
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

class _CreatorNotice extends StatelessWidget {
  final IconData icon;
  final String text;

  const _CreatorNotice({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: colors.secondaryContainer.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: colors.onSecondaryContainer),
          const SizedBox(width: 8),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }
}

class _IsoInfoCard extends StatelessWidget {
  final IsoMetadata iso;

  const _IsoInfoCard({required this.iso});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
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
                  Text(
                    iso.fileName,
                    style: theme.textTheme.titleSmall,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Wrap(
                    spacing: 12,
                    runSpacing: 2,
                    children: [
                      if (iso.windowsVersion != null)
                        Text(
                          iso.windowsVersion!,
                          style: theme.textTheme.bodySmall,
                        ),
                      if (iso.buildNumber != null)
                        Text(
                          '${tr(context, 'creator_build_prefix')} ${iso.buildNumber}',
                          style: theme.textTheme.bodySmall,
                        ),
                      Text(iso.displaySize, style: theme.textTheme.bodySmall),
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

  String _resolveSafetyReasonLocal(
    BuildContext context,
    SafetyCheckResult result,
  ) {
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
              Icon(
                Icons.usb,
                color: isSelected
                    ? (isSafe
                          ? theme.colorScheme.primary
                          : theme.colorScheme.error)
                    : theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${tr(context, 'creator_disk_prefix')} ${disk.diskNumber}: ${disk.model}',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${disk.sizeFormatted}  |  ${tr(context, 'creator_sn_prefix')} ${disk.serialNumber}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    if (safetyResult != null && !isSafe) ...[
                      const SizedBox(height: 4),
                      Text(
                        _resolveSafetyReasonLocal(context, safetyResult!),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.error,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
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
        Text(
          title,
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
            color: Theme.of(context).colorScheme.primary,
          ),
        ),
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
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w500),
            ),
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
                : Text(
                    '$number',
                    style: TextStyle(
                      color: isActive
                          ? cs.onPrimaryContainer
                          : cs.onSurfaceVariant,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: theme.textTheme.bodySmall?.copyWith(
            color: isActive ? cs.primary : cs.onSurfaceVariant,
          ),
        ),
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
