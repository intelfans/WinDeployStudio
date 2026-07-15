import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:path/path.dart' as p;

import '../../../core/localization/strings.dart';
import '../../../core/services/bootable_usb_service.dart';
import '../../../core/services/disk_safety_service.dart';
import '../../../core/services/iso_parse_service.dart';
import '../../../core/services/linux_togo_image_preflight.dart';
import '../../../core/services/known_iso_verification_service.dart';
import '../../../core/services/wtg_service.dart';
import '../../../core/services/windows_iso_preflight.dart';
import '../../../shared/widgets/deployment_shell/deployment_shell_widgets.dart';
import '../../../shared/widgets/known_iso_verification_panel.dart';
import '../../deployment/models/deployment_plan.dart';
import '../../logs/services/log_center_service.dart';

/// Returns the localization key shown for a To Go execution phase. Linux To
/// Go emits explicit writer statuses; preserving those keys prevents the UI
/// from incorrectly presenting Windows image-application text.
String toGoProgressTitleKey({
  required bool isLinux,
  required String phase,
  required String message,
}) {
  final messageKey = message.split('\n').first.trim();
  if (isLinux && messageKey.isNotEmpty) return messageKey;
  if (isLinux) {
    return switch (phase) {
      'complete' => 'step_complete',
      'failed' => 'step_failed',
      _ => 'linux_preparing',
    };
  }
  return switch (phase) {
    'preparing' => 'wtg_step_preparing',
    'cleaningDisk' ||
    'creatingPartitions' ||
    'formatting' ||
    'partitioningDisk' ||
    'partitioning' => 'wtg_step_partitioning',
    'mountingIso' => 'wtg_step_mounting',
    'applyingImage' || 'copyingFiles' || 'splittingWim' => 'wtg_step_applying',
    'writingBootFiles' => 'wtg_step_boot',
    'verifying' => 'wtg_step_verifying',
    'complete' => 'step_complete',
    'failed' => 'step_failed',
    _ => 'wtg_step_preparing',
  };
}

enum _ToGoPlatform { windows, linux }

class _ToGoProgress {
  final String phase;
  final String message;
  final double progress;
  final bool cancellable;
  final int writtenBytes;
  final int totalBytes;
  final int speedBytesPerSecond;
  final int elapsedSeconds;

  const _ToGoProgress({
    required this.phase,
    required this.message,
    required this.progress,
    this.cancellable = false,
    this.writtenBytes = 0,
    this.totalBytes = 0,
    this.speedBytesPerSecond = 0,
    this.elapsedSeconds = 0,
  });

  factory _ToGoProgress.fromWtg(
    WtgProgress progress, {
    required int elapsedSeconds,
  }) {
    final step = progress.step;
    return _ToGoProgress(
      phase: step.name,
      message: progress.message,
      progress: progress.progress,
      cancellable:
          step == WtgStep.mountingIso ||
          step == WtgStep.applyingImage ||
          step == WtgStep.verifying,
      writtenBytes: progress.writtenBytes,
      totalBytes: progress.totalBytes,
      speedBytesPerSecond: progress.currentSpeedBytes,
      elapsedSeconds: elapsedSeconds,
    );
  }

  factory _ToGoProgress.fromLinux(
    CreateProgress progress, {
    required int elapsedSeconds,
  }) {
    final step = progress.step;
    return _ToGoProgress(
      phase: step.name,
      message: progress.message,
      progress: progress.progress,
      cancellable: step != CreateStep.complete && step != CreateStep.failed,
      elapsedSeconds: elapsedSeconds,
    );
  }
}

class WtgScreen extends ConsumerStatefulWidget {
  const WtgScreen({super.key});

  @override
  ConsumerState<WtgScreen> createState() => _WtgScreenState();
}

class _WtgScreenState extends ConsumerState<WtgScreen> {
  static const _configurationSteps = 5;

  final _virtualDiskNameController = TextEditingController(
    text: 'WinDeploy.vhdx',
  );
  final _virtualDiskSizeController = TextEditingController(text: '64');
  final _volumeLabelController = TextEditingController(text: 'WINDEPLOY');
  final _random = Random();

  _ToGoPlatform _platform = _ToGoPlatform.windows;
  int _step = 0;
  IsoMetadata? _iso;
  List<Map<String, dynamic>> _images = const [];
  int? _imageIndex;
  bool _loadingImage = false;
  String _imageStatus = '';
  LinuxToGoImageInspection? _linuxToGoInspection;
  KnownIsoVerification? _knownIsoVerification;
  int _knownIsoVerificationRequest = 0;
  Locale? _knownIsoVerificationLocale;
  int _isoSelectionRequest = 0;

  List<DiskInfo> _disks = const [];
  DiskInfo? _disk;
  SafetyCheckResult? _diskSafety;
  bool _loadingDisks = false;

  DeploymentBootMode _bootMode = DeploymentBootMode.uefiGpt;
  DeploymentMode _deploymentMode = DeploymentMode.direct;
  VirtualDiskType _virtualDiskType = VirtualDiskType.dynamic;
  bool _blockLocalDisks = true;
  bool _skipOobe = false;
  bool _disableWinRe = true;
  bool _disableUasp = false;
  bool _compactOs = false;
  bool _wimBoot = false;
  bool _fixVhdLetter = true;
  bool _enableNetFx3 = false;
  String _systemLetter = '';
  String _bootLetter = '';
  String _driverDirectory = '';
  String _customIconPath = '';

  bool _running = false;
  bool _finished = false;
  bool _success = false;
  _ToGoProgress? _taskProgress;
  WtgService? _activeWtgService;
  BootableUsbService? _activeLinuxService;
  final _executionStopwatch = Stopwatch();
  bool _cancelRequested = false;
  final List<String> _progressLog = [];
  int _gameTarget = 4;
  int _gameScore = 0;
  bool _showGame = false;

  bool get _isLinux => _platform == _ToGoPlatform.linux;

  @override
  void initState() {
    super.initState();
    _loadDisks();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final locale = Localizations.localeOf(context);
    if (_knownIsoVerificationLocale == locale) return;
    _knownIsoVerificationLocale = locale;

    final iso = _iso;
    if (iso == null) {
      _knownIsoVerification = null;
      return;
    }
    final request = ++_knownIsoVerificationRequest;
    _knownIsoVerification = null;
    unawaited(_verifyKnownIso(iso.filePath, request, locale));
  }

  @override
  void dispose() {
    _virtualDiskNameController.dispose();
    _virtualDiskSizeController.dispose();
    _volumeLabelController.dispose();
    super.dispose();
  }

  Future<void> _loadDisks() async {
    setState(() => _loadingDisks = true);
    List<DiskInfo> disks;
    try {
      disks = await ref.read(diskSafetyServiceProvider).getRemovableDisks();
    } catch (error) {
      if (!mounted) return;
      setState(() => _loadingDisks = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_localizedOrRaw(error.toString()))),
      );
      return;
    }
    if (!mounted) return;
    setState(() {
      _disks = disks;
      _loadingDisks = false;
      if (_disk != null &&
          !disks.any((item) => item.diskNumber == _disk!.diskNumber)) {
        _disk = null;
        _diskSafety = null;
      }
    });
  }

  void _changePlatform(_ToGoPlatform platform) {
    if (platform == _platform) return;
    setState(() {
      _platform = platform;
      _step = 0;
      _iso = null;
      _images = const [];
      _imageIndex = null;
      _linuxToGoInspection = null;
      _knownIsoVerification = null;
      _knownIsoVerificationRequest++;
      _isoSelectionRequest++;
      _loadingImage = false;
      _imageStatus = '';
      _deploymentMode = DeploymentMode.direct;
      _bootMode = DeploymentBootMode.uefiGpt;
      _compactOs = false;
      _wimBoot = false;
      _enableNetFx3 = false;
    });
  }

  Future<void> _pickIso() async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['iso'],
      dialogTitle: tr(
        context,
        _isLinux ? 'wtg_linux_select_iso' : 'wtg_select_iso',
      ),
    );
    if (result == null) return;
    final pickedFile = result.files.single;
    final path = pickedFile.path;
    if (path == null || !mounted) return;
    final selectedPlatform = _platform;
    final locale = Localizations.localeOf(context);
    final messenger = ScaffoldMessenger.of(context);
    final selectionRequest = ++_isoSelectionRequest;
    final verificationRequest = ++_knownIsoVerificationRequest;

    setState(() {
      _loadingImage = true;
      _imageStatus = tr(context, 'wtg_parsing_iso');
      _iso = null;
      _images = const [];
      _imageIndex = null;
      _linuxToGoInspection = null;
      _knownIsoVerification = null;
    });

    try {
      if (selectedPlatform == _ToGoPlatform.linux) {
        final windowsLayout = await ref
            .read(windowsIsoPreflightProvider)
            .inspect(path);
        if (!_isCurrentIsoSelection(selectionRequest, selectedPlatform)) {
          return;
        }
        if (windowsLayout.isValid) {
          throw StateError('wtg_windows_iso_in_linux_mode');
        }
        final inspection = await ref
            .read(linuxToGoImagePreflightProvider)
            .inspect(path);
        if (!_isCurrentIsoSelection(selectionRequest, selectedPlatform)) {
          return;
        }
        final iso = IsoMetadata(
          filePath: path,
          fileName: p.basename(path),
          fileSize: pickedFile.size,
          windowsVersion: 'Linux ISOHybrid',
        );
        setState(() {
          _iso = iso;
          _imageIndex = inspection.canCreate ? 1 : null;
          _linuxToGoInspection = inspection;
          if (inspection.canCreate &&
              inspection.image?.supportsDriverStaging != true) {
            _driverDirectory = '';
          }
        });
        unawaited(_verifyKnownIso(path, verificationRequest, locale));
        if (!inspection.canCreate) {
          final messageKey =
              inspection.messageKey ?? 'linux_togo_unsupported_iso';
          messenger.showSnackBar(
            SnackBar(content: Text(_localizedOrRaw(messageKey))),
          );
        }
      } else {
        final windowsLayout = await ref
            .read(windowsIsoPreflightProvider)
            .inspect(path);
        if (!_isCurrentIsoSelection(selectionRequest, selectedPlatform)) {
          return;
        }
        if (!windowsLayout.isValid) {
          throw StateError('wtg_invalid_windows_iso');
        }
        final iso = await ref
            .read(isoParseServiceProvider)
            .parseIso(
              path,
              onProgress: (phase, percent) {
                if (!_isCurrentIsoSelection(
                  selectionRequest,
                  selectedPlatform,
                )) {
                  return;
                }
                setState(() {
                  _imageStatus = '${tr(context, 'wtg_parsing_iso')} $percent%';
                });
              },
            );
        if (!_isCurrentIsoSelection(selectionRequest, selectedPlatform)) {
          return;
        }
        if (iso == null) throw StateError('creator_parse_error');
        final images = await ref.read(wtgServiceProvider).getWimImages(path);
        if (!_isCurrentIsoSelection(selectionRequest, selectedPlatform)) {
          return;
        }
        if (images.isEmpty) throw StateError('wtg_invalid_windows_iso');
        setState(() {
          _iso = iso;
          _images = images;
          _imageIndex = images.first['index'] as int?;
        });
        if (selectedPlatform == _ToGoPlatform.windows) {
          unawaited(_verifyKnownIso(path, verificationRequest, locale));
        }
      }
    } catch (error) {
      if (!_isCurrentIsoSelection(selectionRequest, selectedPlatform)) {
        return;
      }
      final key = error.toString().replaceFirst('Bad state: ', '');
      messenger.showSnackBar(SnackBar(content: Text(_localizedOrRaw(key))));
    } finally {
      if (_isCurrentIsoSelection(selectionRequest, selectedPlatform)) {
        setState(() {
          _loadingImage = false;
          _imageStatus = '';
        });
      }
    }
  }

  bool _isCurrentIsoSelection(int request, _ToGoPlatform platform) {
    return mounted && request == _isoSelectionRequest && _platform == platform;
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
        _iso?.filePath != filePath ||
        Localizations.localeOf(context) != locale ||
        verification == null) {
      return;
    }
    setState(() => _knownIsoVerification = verification);
  }

  Future<void> _selectDisk(DiskInfo disk) async {
    setState(() {
      _disk = disk;
      _diskSafety = null;
    });
    final safety = await ref
        .read(diskSafetyServiceProvider)
        .checkDiskSafety(disk);
    if (!mounted || _disk?.diskNumber != disk.diskNumber) return;
    setState(() {
      _diskSafety = safety;
      if (!safety.isSafe) _disk = null;
    });
    if (!safety.isSafe) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_localizedOrRaw(safety.reason))));
    }
  }

  Future<void> _pickDriverDirectory() async {
    final path = await FilePicker.getDirectoryPath(
      dialogTitle: tr(context, 'deploy_driver_directory'),
    );
    if (path != null && mounted) setState(() => _driverDirectory = path);
  }

  Future<void> _pickIcon() async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['ico'],
      dialogTitle: tr(context, 'deploy_custom_icon'),
    );
    final path = result?.files.single.path;
    if (path != null && mounted) setState(() => _customIconPath = path);
  }

  Map<String, dynamic>? get _selectedImage {
    final index = _imageIndex;
    if (index == null) return null;
    return _images.where((image) => image['index'] == index).firstOrNull;
  }

  DeploymentPlan get _plan {
    final image = _selectedImage;
    final build = image?['build']?.toString() ?? _iso?.buildNumber ?? '';
    final version = image?['version']?.toString() ?? _iso?.windowsVersion ?? '';
    return DeploymentPlan(
      platform: _isLinux
          ? DeploymentPlatform.linux
          : DeploymentPlatform.windows,
      purpose: DeploymentPurpose.toGo,
      imagePath: _iso?.filePath ?? '',
      imageIndex: _imageIndex ?? 1,
      imageName: image?['name']?.toString() ?? _iso?.fileName ?? '',
      imageEdition: image?['edition']?.toString() ?? '',
      imageBuild: build,
      imageArchitecture:
          image?['architecture']?.toString() ?? _iso?.architecture ?? '',
      windowsGeneration: DeploymentPlan.detectWindowsGeneration(
        build: build,
        version: version,
      ),
      bootMode: _bootMode,
      deploymentMode: _isLinux ? DeploymentMode.direct : _deploymentMode,
      virtualDiskType: _virtualDiskType,
      virtualDiskSizeGb:
          int.tryParse(_virtualDiskSizeController.text.trim()) ?? 64,
      virtualDiskFileName: _normalizedVirtualDiskName(),
      blockLocalDisks: !_isLinux && _blockLocalDisks,
      skipOobe: !_isLinux && _skipOobe,
      disableWinRe: !_isLinux && _disableWinRe,
      disableUasp: !_isLinux && _disableUasp,
      compactOs: !_isLinux && _compactOs,
      wimBoot: !_isLinux && _wimBoot,
      fixVhdDriveLetter:
          !_isLinux &&
          _deploymentMode != DeploymentMode.direct &&
          _fixVhdLetter,
      enableNetFx3: !_isLinux && _enableNetFx3,
      ntfsUefiSupport: !_isLinux && _bootMode != DeploymentBootMode.legacyBios,
      preferredSystemLetter: _isLinux ? '' : _systemLetter,
      preferredBootLetter: _isLinux ? '' : _bootLetter,
      driverDirectory:
          _isLinux && _linuxToGoInspection?.image?.supportsDriverStaging != true
          ? ''
          : _driverDirectory,
      customIconPath: _customIconPath,
      customVolumeLabel: _volumeLabelController.text.trim(),
    );
  }

  String _normalizedVirtualDiskName() {
    final raw = _virtualDiskNameController.text.trim();
    final base = raw.isEmpty ? 'WinDeploy' : p.basenameWithoutExtension(raw);
    final extension = _deploymentMode == DeploymentMode.vhd ? '.vhd' : '.vhdx';
    return '$base$extension';
  }

  bool _canContinue() {
    return switch (_step) {
      0 =>
        _iso != null &&
            (_isLinux
                ? _linuxToGoInspection?.canCreate == true &&
                      BootableUsbService
                          .linuxPersistenceToolDistributionApproved
                : _imageIndex != null),
      1 => _disk != null && _diskSafety?.isSafe == true,
      2 => DeploymentCompatibility.evaluate(_plan).canDeploy,
      3 => DeploymentCompatibility.evaluate(_plan).canDeploy,
      4 => DeploymentCompatibility.evaluate(_plan).canDeploy,
      _ => false,
    };
  }

  Future<void> _start() async {
    final disk = _disk;
    if (disk == null) return;
    final plan = _plan;
    final compatibility = DeploymentCompatibility.evaluate(plan);
    if (!compatibility.canDeploy) return;

    _executionStopwatch
      ..reset()
      ..start();
    setState(() {
      _running = true;
      _finished = false;
      _success = false;
      _cancelRequested = false;
      _taskProgress = const _ToGoProgress(
        phase: 'preparing',
        message: 'wtg_step_preparing',
        progress: 0,
      );
      _progressLog
        ..clear()
        ..add(tr(context, 'wtg_step_preparing'));
    });

    var success = false;
    DiskOperationLock? operationLock;
    try {
      await LogCenterService().logToGo('[DeploymentPlan] ${plan.toJson()}');
      if (!mounted) return;
      operationLock = await DiskOperationLock.tryAcquire(disk.diskNumber);
      if (Platform.isWindows && operationLock == null) {
        _updateTaskProgress(
          const _ToGoProgress(
            phase: 'failed',
            message: 'safety_disk_busy',
            progress: 0,
          ),
        );
        return;
      }

      if (_isLinux) {
        final service = ref.read(bootableUsbServiceProvider);
        _activeLinuxService = service;
        if (_cancelRequested) service.cancel();
        success = await service.createLinuxIsoUsb(
          disk: disk,
          isoPath: plan.imagePath,
          kind: LinuxUsbKind.toGo,
          deploymentPlan: plan,
          onProgress: _onLinuxProgress,
        );
        if (!success && service.isCancelled) {
          _updateTaskProgress(
            _ToGoProgress(
              phase: 'failed',
              message: 'deploy_cancel_requested',
              progress: _taskProgress?.progress ?? 0,
            ),
          );
        }
      } else {
        final service = ref.read(wtgServiceProvider);
        _activeWtgService = service;
        if (_cancelRequested) service.cancel();
        success = await service.createWtg(
          disk: disk,
          isoPath: plan.imagePath,
          imageIndex: plan.imageIndex,
          driveLetter: disk.driveLetters.isEmpty ? '' : disk.driveLetters.first,
          deploymentPlan: plan,
          onProgress: _onWtgProgress,
        );
        if (!success && service.isCancelled) {
          _updateTaskProgress(
            _ToGoProgress(
              phase: 'failed',
              message: 'deploy_cancel_requested',
              progress: _taskProgress?.progress ?? 0,
            ),
          );
        }
      }
    } catch (error) {
      _updateTaskProgress(
        _ToGoProgress(
          phase: 'failed',
          message: 'creator_error\n$error',
          progress: _taskProgress?.progress ?? 0,
        ),
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_localizedOrRaw(error.toString()))),
        );
      }
    } finally {
      await operationLock?.release();
      _executionStopwatch.stop();
      if (mounted) {
        setState(() {
          _running = false;
          _finished = true;
          _success = success;
          _activeWtgService = null;
          _activeLinuxService = null;
        });
      }
    }
  }

  void _onWtgProgress(WtgProgress progress) {
    _updateTaskProgress(
      _ToGoProgress.fromWtg(
        progress,
        elapsedSeconds: _executionStopwatch.elapsed.inSeconds,
      ),
    );
  }

  void _onLinuxProgress(CreateProgress progress) {
    _updateTaskProgress(
      _ToGoProgress.fromLinux(
        progress,
        elapsedSeconds: _executionStopwatch.elapsed.inSeconds,
      ),
    );
  }

  void _updateTaskProgress(_ToGoProgress progress) {
    if (!mounted) return;
    setState(() {
      _taskProgress = progress;
      final message = _localizedOrRaw(progress.message.split('\n').first);
      if (_progressLog.isEmpty || _progressLog.last != message) {
        _progressLog.add(message);
      }
    });
  }

  void _cancel() {
    if (_cancelRequested) return;
    if (_isLinux) {
      _activeLinuxService?.cancel();
    } else {
      _activeWtgService?.cancel();
    }
    if (!mounted) return;
    setState(() {
      _cancelRequested = true;
      _progressLog.add(tr(context, 'deploy_cancel_requested'));
    });
  }

  void _reset() {
    setState(() {
      _step = 0;
      _iso = null;
      _images = const [];
      _imageIndex = null;
      _linuxToGoInspection = null;
      _knownIsoVerification = null;
      _knownIsoVerificationRequest++;
      _isoSelectionRequest++;
      _loadingImage = false;
      _imageStatus = '';
      _disk = null;
      _diskSafety = null;
      _running = false;
      _finished = false;
      _taskProgress = null;
      _cancelRequested = false;
      _progressLog.clear();
    });
    _executionStopwatch.reset();
    _loadDisks();
  }

  @override
  Widget build(BuildContext context) {
    if (_running || _finished) return _buildExecutionView();
    return Scaffold(
      body: DeploymentShell(
        title: Text(tr(context, _isLinux ? 'wtg_linux_title' : 'wtg_title')),
        subtitle: Text(
          tr(context, _isLinux ? 'wtg_linux_subtitle' : 'wtg_subtitle'),
        ),
        destinations: _stepDestinations(),
        selectedIndex: _step,
        onDestinationSelected: _selectReachedStep,
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildPlatformSelector(),
            const SizedBox(height: 24),
            DeploymentSection(
              title: Text(tr(context, _stepTitleKey(_step))),
              description: Text(tr(context, _stepDescriptionKey(_step))),
              leading: Icon(_stepIcon(_step)),
              framed: false,
              child: _buildStep(),
            ),
          ],
        ),
        footer: _buildNavigation(),
      ),
    );
  }

  List<DeploymentShellDestination> _stepDestinations() {
    final labels = [
      tr(context, 'deploy_step_image'),
      tr(context, 'deploy_step_disk'),
      tr(context, 'deploy_step_method'),
      tr(context, 'deploy_step_advanced'),
      tr(context, 'deploy_step_summary'),
    ];
    return List.generate(
      _configurationSteps,
      (index) => DeploymentShellDestination(
        label: labels[index],
        icon: _stepIcon(index),
        selectedIcon: index < _step ? Icons.check_circle : null,
        enabled: index <= _step,
      ),
    );
  }

  IconData _stepIcon(int index) => switch (index) {
    0 => Icons.disc_full_outlined,
    1 => Icons.usb_rounded,
    2 => Icons.install_desktop_outlined,
    3 => Icons.tune_rounded,
    4 => Icons.fact_check_outlined,
    _ => Icons.circle_outlined,
  };

  String _stepTitleKey(int index) => switch (index) {
    0 => 'deploy_image_title',
    1 => 'deploy_disk_title',
    2 => 'deploy_method_title',
    3 => 'deploy_advanced_title',
    4 => 'deploy_summary_title',
    _ => 'wtg_title',
  };

  String _stepDescriptionKey(int index) => switch (index) {
    0 => 'deploy_image_desc',
    1 => 'deploy_disk_desc',
    2 => _isLinux ? 'deploy_linux_method_desc' : 'deploy_method_desc',
    3 => 'deploy_advanced_desc',
    4 => 'deploy_summary_desc',
    _ => 'wtg_subtitle',
  };

  void _selectReachedStep(int index) {
    if (index < 0 || index > _step) return;
    setState(() => _step = index);
  }

  Widget _buildPlatformSelector() {
    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: SizedBox(
          width: double.infinity,
          child: SegmentedButton<_ToGoPlatform>(
            key: const Key('wtg-platform-selector'),
            expandedInsets: EdgeInsets.zero,
            showSelectedIcon: false,
            style: ButtonStyle(
              minimumSize: const WidgetStatePropertyAll(Size.fromHeight(60)),
              padding: const WidgetStatePropertyAll(
                EdgeInsets.symmetric(horizontal: 4, vertical: 8),
              ),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              visualDensity: const VisualDensity(horizontal: -4),
              iconSize: const WidgetStatePropertyAll(22),
              textStyle: WidgetStatePropertyAll(
                Theme.of(
                  context,
                ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w600),
              ),
            ),
            segments: [
              ButtonSegment(
                value: _ToGoPlatform.windows,
                icon: const Icon(Icons.window_rounded),
                label: Text(
                  tr(context, 'wtg_platform_windows'),
                  key: const Key('wtg-platform-windows-label'),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                ),
              ),
              ButtonSegment(
                value: _ToGoPlatform.linux,
                icon: const Icon(Icons.terminal_rounded),
                label: Text(
                  tr(context, 'wtg_platform_linux'),
                  key: const Key('wtg-platform-linux-label'),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                ),
              ),
            ],
            selected: {_platform},
            onSelectionChanged: (value) => _changePlatform(value.first),
          ),
        ),
      ),
    );
  }

  Widget _buildStep() => switch (_step) {
    0 => _buildImageStep(),
    1 => _buildDiskStep(),
    2 => _buildDeploymentStep(),
    3 => _buildAdvancedStep(),
    4 => _buildSummaryStep(),
    _ => const SizedBox.shrink(),
  };

  Widget _stepContainer({required Widget child}) {
    return Align(
      alignment: AlignmentDirectional.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 980),
        child: child,
      ),
    );
  }

  Widget _buildImageStep() {
    return _stepContainer(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SelectionPanel(
            icon: Icons.disc_full_outlined,
            // Keep the empty-state prompt aligned with the selected To Go platform.
            // WTG remains Windows-only; LTG should never present a Windows ISO prompt.
            title:
                _iso?.fileName ??
                tr(
                  context,
                  _isLinux ? 'wtg_linux_select_iso' : 'wtg_select_iso',
                ),
            subtitle: _iso == null
                ? tr(context, 'deploy_image_none')
                : '${_iso!.displaySize}  •  ${_iso!.windowsVersion ?? ''}',
            selected: _isLinux
                ? _linuxToGoInspection?.canCreate == true
                : _iso != null,
            trailing: FilledButton.tonalIcon(
              onPressed: _loadingImage ? null : _pickIso,
              icon: const Icon(Icons.folder_open),
              label: Text(tr(context, 'creator_select_btn')),
            ),
            stackTrailingNarrowly: true,
          ),
          if (_knownIsoVerification != null) ...[
            const SizedBox(height: 12),
            KnownIsoVerificationPanel(
              verification: _knownIsoVerification,
              iso: _iso,
            ),
          ],
          if (_isLinux && _linuxToGoInspection != null) ...[
            const SizedBox(height: 12),
            _buildLinuxToGoInspectionBanner(_linuxToGoInspection!),
          ],
          if (_loadingImage) ...[
            const SizedBox(height: 12),
            LinearProgressIndicator(semanticsLabel: _imageStatus),
            const SizedBox(height: 8),
            Text(_imageStatus),
          ],
          if (!_isLinux && _images.isNotEmpty) ...[
            const SizedBox(height: 20),
            Text(
              tr(context, 'wtg_step3_title'),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 10),
            ..._images.map((image) {
              final index = image['index'] as int? ?? 1;
              final selected = index == _imageIndex;
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _SelectionPanel(
                  icon: Icons.window_outlined,
                  title: image['name']?.toString() ?? 'Windows',
                  subtitle:
                      [image['edition'], image['architecture'], image['build']]
                          .where(
                            (value) => value != null && '$value'.isNotEmpty,
                          )
                          .join(' • '),
                  selected: selected,
                  onTap: () => setState(() => _imageIndex = index),
                ),
              );
            }),
          ],
        ],
      ),
    );
  }

  Widget _buildLinuxToGoInspectionBanner(LinuxToGoImageInspection inspection) {
    final layoutSupported = inspection.canCreate;
    final supported =
        layoutSupported &&
        BootableUsbService.linuxPersistenceToolDistributionApproved;
    final colorScheme = Theme.of(context).colorScheme;
    final color = supported ? colorScheme.primary : colorScheme.error;
    final messageKey = !layoutSupported
        ? inspection.messageKey ?? 'linux_togo_unsupported_iso'
        : !BootableUsbService.linuxPersistenceToolDistributionApproved
        ? 'linux_togo_mke2fs_missing'
        : inspection.image?.family == LinuxToGoImageFamily.debianLive
        ? 'linux_togo_debian_image_supported'
        : inspection.image?.family == LinuxToGoImageFamily.deepinLive
        ? 'linux_togo_deepin_image_supported'
        : 'linux_togo_image_supported';

    return Semantics(
      key: const Key('ltg-image-inspection'),
      liveRegion: true,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          border: Border.all(color: color.withValues(alpha: 0.5)),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              supported ? Icons.verified_outlined : Icons.error_outline,
              color: color,
            ),
            const SizedBox(width: 10),
            Expanded(child: Text(_localizedOrRaw(messageKey))),
          ],
        ),
      ),
    );
  }

  Widget _buildDiskStep() {
    return _stepContainer(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_knownIsoVerification != null) ...[
            KnownIsoVerificationPanel(
              verification: _knownIsoVerification,
              iso: _iso,
            ),
            const SizedBox(height: 12),
          ],
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              IconButton(
                tooltip: tr(context, 'creator_retry'),
                onPressed: _loadingDisks ? null : _loadDisks,
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
          if (_loadingDisks)
            const Center(child: CircularProgressIndicator())
          else if (_disks.isEmpty)
            _EmptyState(
              icon: Icons.usb_off,
              text: tr(context, 'creator_no_usb'),
            )
          else
            ..._disks.map((disk) {
              final selected = _disk?.diskNumber == disk.diskNumber;
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: DiskSelectionRow(
                  title: Text(disk.friendlyName),
                  subtitle: disk.model == disk.friendlyName
                      ? null
                      : Text(disk.model),
                  details: [
                    Text(disk.sizeFormatted),
                    Text(disk.busType),
                    Text(
                      '${tr(context, 'wtg_disk_prefix')} ${disk.diskNumber}',
                    ),
                    if (disk.serialNumber.isNotEmpty)
                      Text(
                        '${tr(context, 'creator_serial')}: ${disk.serialNumber}',
                      ),
                  ],
                  selected: selected,
                  status: selected && _diskSafety == null
                      ? DiskSelectionStatus.checking
                      : selected && _diskSafety?.isSafe == true
                      ? DiskSelectionStatus.safe
                      : DiskSelectionStatus.normal,
                  onPressed: () => _selectDisk(disk),
                ),
              );
            }),
          if (_disk != null) ...[
            const SizedBox(height: 12),
            Card(
              child: ListTile(
                leading: const Icon(Icons.monitor_heart_outlined),
                title: Text(tr(context, 'wtg_benchmark_tip_title')),
                subtitle: Text(tr(context, 'wtg_benchmark_tip_desc')),
                trailing: OutlinedButton.icon(
                  onPressed: () => context.go('/benchmark'),
                  icon: const Icon(Icons.speed),
                  label: Text(tr(context, 'wtg_benchmark_tip_button')),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildDeploymentStep() {
    if (_isLinux) {
      return _stepContainer(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_knownIsoVerification != null) ...[
              KnownIsoVerificationPanel(
                verification: _knownIsoVerification,
                iso: _iso,
              ),
              const SizedBox(height: 12),
            ],
            _OptionTile(
              icon: Icons.terminal,
              title: tr(context, 'deploy_direct'),
              subtitle: tr(context, 'deploy_linux_direct_desc'),
              selected: true,
            ),
          ],
        ),
      );
    }

    final availableModes = DeploymentCompatibility.deploymentModesFor(_plan);
    if (!availableModes.contains(_deploymentMode)) {
      _deploymentMode = availableModes.first;
    }
    return _stepContainer(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_knownIsoVerification != null) ...[
            KnownIsoVerificationPanel(
              verification: _knownIsoVerification,
              iso: _iso,
            ),
            const SizedBox(height: 12),
          ],
          Text(
            tr(context, 'deploy_boot_mode'),
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 10),
          SegmentedButton<DeploymentBootMode>(
            segments: [
              ButtonSegment(
                value: DeploymentBootMode.uefiGpt,
                label: Text(tr(context, 'deploy_boot_uefi_gpt')),
              ),
              ButtonSegment(
                value: DeploymentBootMode.uefiMbr,
                label: Text(tr(context, 'deploy_boot_uefi_mbr')),
              ),
              ButtonSegment(
                value: DeploymentBootMode.legacyBios,
                label: Text(tr(context, 'deploy_boot_legacy')),
              ),
            ],
            selected: {_bootMode},
            onSelectionChanged: (value) =>
                setState(() => _bootMode = value.first),
          ),
          const SizedBox(height: 24),
          Text(
            tr(context, 'deploy_mode'),
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: availableModes.map((mode) {
              return SizedBox(
                width: 280,
                child: _OptionTile(
                  icon: switch (mode) {
                    DeploymentMode.direct => Icons.install_desktop,
                    DeploymentMode.vhd => Icons.storage,
                    DeploymentMode.vhdx => Icons.dns_outlined,
                  },
                  title: _deploymentModeLabel(mode),
                  subtitle: _deploymentModeDescription(mode),
                  selected: mode == _deploymentMode,
                  onTap: () {
                    setState(() {
                      _deploymentMode = mode;
                      _virtualDiskNameController.text =
                          _normalizedVirtualDiskName();
                    });
                  },
                ),
              );
            }).toList(),
          ),
          if (_deploymentMode != DeploymentMode.direct) ...[
            const SizedBox(height: 20),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    SegmentedButton<VirtualDiskType>(
                      segments: [
                        ButtonSegment(
                          value: VirtualDiskType.dynamic,
                          label: Text(tr(context, 'deploy_vdisk_dynamic')),
                        ),
                        ButtonSegment(
                          value: VirtualDiskType.fixed,
                          label: Text(tr(context, 'deploy_vdisk_fixed')),
                        ),
                      ],
                      selected: {_virtualDiskType},
                      onSelectionChanged: (value) =>
                          setState(() => _virtualDiskType = value.first),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _virtualDiskSizeController,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: tr(context, 'deploy_vdisk_size'),
                        suffixText: 'GB',
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _virtualDiskNameController,
                      decoration: InputDecoration(
                        labelText: tr(context, 'deploy_vdisk_name'),
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                  ],
                ),
              ),
            ),
          ],
          _buildCompatibilityNotices(),
        ],
      ),
    );
  }

  Widget _buildAdvancedStep() {
    final plan = _plan;
    final canStageLinuxDrivers =
        !_isLinux || _linuxToGoInspection?.image?.supportsDriverStaging == true;
    return _stepContainer(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_knownIsoVerification != null) ...[
            KnownIsoVerificationPanel(
              verification: _knownIsoVerification,
              iso: _iso,
            ),
            const SizedBox(height: 12),
          ],
          Card(
            child: ExpansionTile(
              initiallyExpanded: true,
              leading: const Icon(Icons.tune),
              title: Text(tr(context, 'deploy_standard_options')),
              children: [
                if (!_isLinux) ...[
                  _switchTile(
                    'deploy_block_local',
                    'deploy_block_local_desc',
                    _blockLocalDisks,
                    (value) => _blockLocalDisks = value,
                  ),
                  _switchTile(
                    'deploy_skip_oobe',
                    'deploy_skip_oobe_desc',
                    _skipOobe,
                    (value) => _skipOobe = value,
                  ),
                  _switchTile(
                    'deploy_disable_winre',
                    'deploy_disable_winre_desc',
                    _disableWinRe,
                    (value) => _disableWinRe = value,
                  ),
                  _switchTile(
                    'deploy_disable_uasp',
                    'deploy_disable_uasp_desc',
                    _disableUasp,
                    (value) => _disableUasp = value,
                  ),
                  if (DeploymentCompatibility.supportsCompactOs(plan))
                    _switchTile(
                      'deploy_compact_os',
                      'deploy_compact_os_desc',
                      _compactOs,
                      (value) => _compactOs = value,
                    ),
                  if (_deploymentMode != DeploymentMode.direct)
                    _switchTile(
                      'deploy_fix_vhd_letter',
                      'deploy_fix_vhd_letter_desc',
                      _fixVhdLetter,
                      (value) => _fixVhdLetter = value,
                    ),
                  _switchTile(
                    'deploy_netfx3',
                    'deploy_netfx3_desc',
                    _enableNetFx3,
                    (value) => _enableNetFx3 = value,
                  ),
                ],
                if (canStageLinuxDrivers)
                  ListTile(
                    leading: const Icon(Icons.folder_copy_outlined),
                    title: Text(tr(context, 'deploy_driver_directory')),
                    subtitle: Text(
                      _driverDirectory.isEmpty
                          ? tr(
                              context,
                              _isLinux
                                  ? 'deploy_linux_driver_desc'
                                  : 'deploy_windows_driver_desc',
                            )
                          : _driverDirectory,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: IconButton(
                      onPressed: _pickDriverDirectory,
                      icon: const Icon(Icons.folder_open),
                    ),
                  ),
              ],
            ),
          ),
          if (!_isLinux) ...[
            const SizedBox(height: 12),
            Card(
              child: ExpansionTile(
                leading: const Icon(Icons.science_outlined),
                title: Text(tr(context, 'deploy_expert_options')),
                subtitle: Text(tr(context, 'deploy_expert_desc')),
                children: [
                  if (DeploymentCompatibility.supportsWimBoot(plan))
                    _switchTile(
                      'deploy_wimboot',
                      'deploy_wimboot_desc',
                      _wimBoot,
                      (value) => _wimBoot = value,
                    ),
                  if (plan.usesNtfsUefiLayout)
                    ListTile(
                      leading: const Icon(Icons.verified_outlined),
                      title: Text(tr(context, 'deploy_ntfs_uefi')),
                      subtitle: Text(tr(context, 'deploy_ntfs_uefi_desc')),
                    ),
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        Expanded(
                          child: _letterDropdown(
                            'deploy_system_letter',
                            _systemLetter,
                            (value) => _systemLetter = value,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _letterDropdown(
                            'deploy_boot_letter',
                            _bootLetter,
                            (value) => _bootLetter = value,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 12),
          _buildVolumeIdentityCard(),
          _buildCompatibilityNotices(),
        ],
      ),
    );
  }

  Widget _buildVolumeIdentityCard() {
    final hasCustomIcon = _customIconPath.trim().isNotEmpty;
    return Card(
      child: ExpansionTile(
        leading: const Icon(Icons.drive_file_rename_outline),
        title: Text(tr(context, 'deploy_volume_identity')),
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              key: const Key('wtg-volume-label'),
              controller: _volumeLabelController,
              maxLength: 32,
              decoration: InputDecoration(
                labelText: tr(context, 'deploy_volume_label'),
              ),
              onChanged: (_) => setState(() {}),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.image_outlined),
            title: Text(tr(context, 'deploy_custom_icon')),
            subtitle: Text(
              hasCustomIcon
                  ? _customIconPath
                  : tr(context, 'deploy_custom_icon_default'),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (hasCustomIcon)
                  IconButton(
                    key: const Key('wtg-icon-clear'),
                    tooltip: tr(context, 'deploy_clear_custom_icon'),
                    onPressed: () => setState(() => _customIconPath = ''),
                    icon: const Icon(Icons.close),
                  ),
                IconButton(
                  key: const Key('wtg-icon-picker'),
                  tooltip: tr(context, 'deploy_custom_icon'),
                  onPressed: _pickIcon,
                  icon: const Icon(Icons.folder_open),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryStep() {
    final plan = _plan;
    final disk = _disk;
    return _stepContainer(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Card(
            child: Column(
              children: [
                _summaryRow('deploy_summary_image', plan.imageName),
                _summaryRow(
                  'deploy_summary_disk',
                  disk == null
                      ? '-'
                      : '${disk.friendlyName} • ${disk.sizeFormatted} • Disk ${disk.diskNumber}',
                ),
                _summaryRow(
                  'deploy_summary_boot',
                  _bootModeLabel(plan.bootMode),
                ),
                _summaryRow(
                  'deploy_summary_method',
                  _deploymentModeLabel(plan.deploymentMode),
                ),
                if (plan.usesVirtualDisk)
                  _summaryRow(
                    'deploy_summary_virtual_disk',
                    '${plan.virtualDiskFileName} • ${plan.virtualDiskSizeGb} GB • ${_virtualDiskTypeLabel(plan.virtualDiskType)}',
                  ),
                _summaryRow(
                  'deploy_summary_drivers',
                  plan.driverDirectory.isEmpty
                      ? tr(context, 'deploy_none')
                      : plan.driverDirectory,
                ),
                _summaryRow('deploy_volume_label', plan.customVolumeLabel),
                _summaryRow(
                  'deploy_custom_icon',
                  plan.customIconPath.trim().isEmpty
                      ? tr(context, 'deploy_custom_icon_default')
                      : p.basename(plan.customIconPath),
                ),
                _summaryRow(
                  'deploy_summary_options',
                  _enabledOptions(plan).join(', '),
                ),
              ],
            ),
          ),
          if (_knownIsoVerification != null) ...[
            const SizedBox(height: 12),
            KnownIsoVerificationPanel(
              verification: _knownIsoVerification,
              iso: _iso,
            ),
          ],
          _buildCompatibilityNotices(),
          const SizedBox(height: 12),
          Card(
            color: Theme.of(context).colorScheme.errorContainer,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Icon(
                    Icons.warning_amber_rounded,
                    color: Theme.of(context).colorScheme.error,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      tr(
                        context,
                        _isLinux ? 'creator_linux_warning' : 'creator_warning',
                      ),
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onErrorContainer,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCompatibilityNotices() {
    final report = DeploymentCompatibility.evaluate(_plan);
    if (report.issues.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Column(
        children: report.issues.map((issue) {
          final color = issue.severity == CompatibilitySeverity.error
              ? Theme.of(context).colorScheme.error
              : Theme.of(context).colorScheme.tertiary;
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.08),
                border: Border.all(color: color.withValues(alpha: 0.45)),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(
                    issue.severity == CompatibilitySeverity.error
                        ? Icons.error_outline
                        : Icons.info_outline,
                    color: color,
                  ),
                  const SizedBox(width: 10),
                  Expanded(child: Text(tr(context, issue.messageKey))),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildNavigation() {
    return Row(
      children: [
        if (_step > 0)
          OutlinedButton.icon(
            onPressed: () => setState(() => _step--),
            icon: const Icon(Icons.arrow_back),
            label: Text(tr(context, 'creator_back')),
          ),
        const Spacer(),
        if (_step < _configurationSteps - 1)
          FilledButton.icon(
            onPressed: _canContinue() ? () => setState(() => _step++) : null,
            icon: const Icon(Icons.arrow_forward),
            label: Text(tr(context, 'creator_next')),
          )
        else
          FilledButton.icon(
            onPressed: _canContinue() ? _start : null,
            icon: const Icon(Icons.play_arrow),
            label: Text(tr(context, 'wtg_start_creation')),
          ),
      ],
    );
  }

  Widget _buildExecutionView() {
    final progress = _taskProgress;
    final colorScheme = Theme.of(context).colorScheme;
    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 900),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _finished
                      ? tr(
                          context,
                          _success ? 'deploy_complete' : 'deploy_failed',
                        )
                      : tr(context, 'deploy_running'),
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  _finished
                      ? tr(
                          context,
                          _success
                              ? 'deploy_complete_desc'
                              : 'deploy_failed_desc',
                        )
                      : _localizedOrRaw(
                          progress?.message.split('\n').first ??
                              'wtg_step_preparing',
                        ),
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
                if (_knownIsoVerification != null) ...[
                  const SizedBox(height: 16),
                  KnownIsoVerificationPanel(
                    verification: _knownIsoVerification,
                    iso: _iso,
                  ),
                ],
                const SizedBox(height: 24),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            Icon(
                              _finished
                                  ? (_success
                                        ? Icons.check_circle
                                        : Icons.error_outline)
                                  : Icons.sync,
                              size: 42,
                              color: _success
                                  ? Colors.green
                                  : (_finished
                                        ? colorScheme.error
                                        : colorScheme.primary),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _phaseLabel(
                                      progress?.phase ?? 'preparing',
                                      message: progress?.message ?? '',
                                    ),
                                    style: Theme.of(
                                      context,
                                    ).textTheme.titleMedium,
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    '${((progress?.progress ?? (_success ? 1 : 0)) * 100).toStringAsFixed(0)}%',
                                  ),
                                ],
                              ),
                            ),
                            _Metric(
                              label: tr(context, 'wtg_elapsed'),
                              value: _formatDuration(
                                progress?.elapsedSeconds ?? 0,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 18),
                        LinearProgressIndicator(
                          value: _finished && _success
                              ? 1
                              : progress?.progress ?? 0,
                        ),
                        if ((progress?.totalBytes ?? 0) > 0) ...[
                          const SizedBox(height: 14),
                          Row(
                            children: [
                              Expanded(
                                child: _Metric(
                                  label: tr(context, 'deploy_written'),
                                  value:
                                      '${_formatBytes(progress!.writtenBytes)} / ${_formatBytes(progress.totalBytes)}',
                                ),
                              ),
                              Expanded(
                                child: _Metric(
                                  label: tr(context, 'deploy_speed'),
                                  value:
                                      '${_formatBytes(progress.speedBytesPerSecond)}/s',
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Expanded(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        child: Card(
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  tr(context, 'deploy_log_summary'),
                                  style: Theme.of(context).textTheme.titleSmall,
                                ),
                                const SizedBox(height: 10),
                                Expanded(
                                  child: ListView.builder(
                                    itemCount: _progressLog.length,
                                    itemBuilder: (context, index) => Padding(
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 4,
                                      ),
                                      child: Row(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Icon(
                                            Icons.check_circle_outline,
                                            size: 16,
                                            color: colorScheme.primary,
                                          ),
                                          const SizedBox(width: 8),
                                          Expanded(
                                            child: Text(_progressLog[index]),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      if (_showGame) ...[
                        const SizedBox(width: 12),
                        SizedBox(width: 230, child: _buildGame()),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    if (!_finished)
                      TextButton.icon(
                        onPressed: () => setState(() => _showGame = !_showGame),
                        icon: const Icon(Icons.sports_esports_outlined),
                        label: Text(tr(context, 'deploy_waiting_game')),
                      ),
                    const Spacer(),
                    if (!_finished)
                      OutlinedButton.icon(
                        onPressed:
                            progress?.cancellable == true && !_cancelRequested
                            ? _cancel
                            : null,
                        icon: const Icon(Icons.stop_circle_outlined),
                        label: Text(tr(context, 'cancel')),
                      )
                    else
                      FilledButton.icon(
                        onPressed: _reset,
                        icon: const Icon(Icons.refresh),
                        label: Text(tr(context, 'creator_another')),
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

  Widget _buildGame() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Text(
              tr(context, 'deploy_waiting_game'),
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 8),
            Text('${tr(context, 'deploy_game_score')}: $_gameScore'),
            const SizedBox(height: 16),
            Expanded(
              child: GridView.builder(
                physics: const NeverScrollableScrollPhysics(),
                itemCount: 9,
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  mainAxisSpacing: 8,
                  crossAxisSpacing: 8,
                ),
                itemBuilder: (context, index) {
                  final active = index == _gameTarget;
                  return IconButton.filledTonal(
                    onPressed: () {
                      if (!active) return;
                      setState(() {
                        _gameScore++;
                        var next = _random.nextInt(9);
                        if (next == _gameTarget) next = (next + 1) % 9;
                        _gameTarget = next;
                      });
                    },
                    icon: Icon(active ? Icons.bolt : Icons.circle_outlined),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _switchTile(
    String titleKey,
    String subtitleKey,
    bool value,
    ValueChanged<bool> update,
  ) {
    return SwitchListTile(
      title: Text(tr(context, titleKey)),
      subtitle: Text(tr(context, subtitleKey)),
      value: value,
      onChanged: (next) => setState(() => update(next)),
    );
  }

  Widget _letterDropdown(
    String labelKey,
    String value,
    ValueChanged<String> update,
  ) {
    final letters = [
      '',
      ...List.generate(23, (index) => String.fromCharCode(68 + index)),
    ];
    return DropdownButtonFormField<String>(
      initialValue: value,
      decoration: InputDecoration(labelText: tr(context, labelKey)),
      items: letters
          .map(
            (letter) => DropdownMenuItem(
              value: letter,
              child: Text(
                letter.isEmpty ? tr(context, 'deploy_auto') : '$letter:',
              ),
            ),
          )
          .toList(),
      onChanged: (next) => setState(() => update(next ?? '')),
    );
  }

  Widget _summaryRow(String labelKey, String value) {
    return ListTile(
      title: Text(tr(context, labelKey)),
      subtitle: Text(value.isEmpty ? '-' : value),
    );
  }

  List<String> _enabledOptions(DeploymentPlan plan) {
    final values = <String>[];
    if (plan.blockLocalDisks) values.add(tr(context, 'deploy_block_local'));
    if (plan.skipOobe) values.add(tr(context, 'deploy_skip_oobe'));
    if (plan.disableWinRe) values.add(tr(context, 'deploy_disable_winre'));
    if (plan.disableUasp) values.add(tr(context, 'deploy_disable_uasp'));
    if (plan.compactOs) values.add('CompactOS');
    if (plan.wimBoot) values.add('WIMBoot');
    if (plan.enableNetFx3) values.add('.NET Framework 3.5');
    if (plan.usesNtfsUefiLayout) {
      values.add(tr(context, 'deploy_ntfs_uefi'));
    }
    return values.isEmpty ? [tr(context, 'deploy_none')] : values;
  }

  String _deploymentModeLabel(DeploymentMode mode) => switch (mode) {
    DeploymentMode.direct => tr(context, 'deploy_direct'),
    DeploymentMode.vhd => 'VHD',
    DeploymentMode.vhdx => 'VHDX',
  };

  String _deploymentModeDescription(DeploymentMode mode) => switch (mode) {
    DeploymentMode.direct => tr(context, 'deploy_direct_desc'),
    DeploymentMode.vhd => tr(context, 'deploy_vhd_desc'),
    DeploymentMode.vhdx => tr(context, 'deploy_vhdx_desc'),
  };

  String _bootModeLabel(DeploymentBootMode mode) => switch (mode) {
    DeploymentBootMode.uefiGpt => tr(context, 'deploy_boot_uefi_gpt'),
    DeploymentBootMode.uefiMbr => tr(context, 'deploy_boot_uefi_mbr'),
    DeploymentBootMode.legacyBios => tr(context, 'deploy_boot_legacy'),
  };

  String _virtualDiskTypeLabel(VirtualDiskType type) => switch (type) {
    VirtualDiskType.dynamic => tr(context, 'deploy_vdisk_dynamic'),
    VirtualDiskType.fixed => tr(context, 'deploy_vdisk_fixed'),
  };

  String _phaseLabel(String phase, {required String message}) {
    return tr(
      context,
      toGoProgressTitleKey(isLinux: _isLinux, phase: phase, message: message),
    );
  }

  String _localizedOrRaw(String value) {
    final localized = tr(context, value);
    return localized.isEmpty || localized.contains('unavailable')
        ? value
        : localized;
  }

  String _formatDuration(int seconds) {
    final duration = Duration(seconds: seconds);
    final hours = duration.inHours.toString().padLeft(2, '0');
    final minutes = (duration.inMinutes % 60).toString().padLeft(2, '0');
    final secs = (duration.inSeconds % 60).toString().padLeft(2, '0');
    return '$hours:$minutes:$secs';
  }

  String _formatBytes(int bytes) {
    if (bytes <= 0) return '0 B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }
}

class _SelectionPanel extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback? onTap;
  final Widget? trailing;
  final bool stackTrailingNarrowly;

  const _SelectionPanel({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.selected,
    this.onTap,
    this.trailing,
    this.stackTrailingNarrowly = false,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Material(
      color: selected
          ? colorScheme.primaryContainer.withValues(alpha: 0.35)
          : colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(
          color: selected ? colorScheme.primary : colorScheme.outlineVariant,
          width: selected ? 1.5 : 1,
        ),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final stackTrailing =
                stackTrailingNarrowly &&
                trailing != null &&
                constraints.maxWidth < 420;
            final details = Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  title,
                  style: Theme.of(
                    context,
                  ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                ),
                if (subtitle.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            );
            final leadingAndDetails = Row(
              children: [
                Icon(
                  icon,
                  color: selected
                      ? colorScheme.primary
                      : colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 14),
                Expanded(child: details),
              ],
            );

            return ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 78),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                child: stackTrailing
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          leadingAndDetails,
                          const SizedBox(height: 12),
                          trailing!,
                        ],
                      )
                    : Row(
                        children: [
                          Icon(
                            icon,
                            color: selected
                                ? colorScheme.primary
                                : colorScheme.onSurfaceVariant,
                          ),
                          const SizedBox(width: 14),
                          Expanded(child: details),
                          if (trailing != null) ...[
                            const SizedBox(width: 12),
                            trailing!,
                          ],
                        ],
                      ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _OptionTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback? onTap;

  const _OptionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.selected,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return _SelectionPanel(
      icon: icon,
      title: title,
      subtitle: subtitle,
      selected: selected,
      onTap: onTap,
      trailing: selected ? const Icon(Icons.check_circle) : null,
    );
  }
}

class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String text;

  const _EmptyState({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(48),
      child: Center(
        child: Column(
          children: [
            Icon(
              icon,
              size: 48,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 12),
            Text(text),
          ],
        ),
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  final String label;
  final String value;

  const _Metric({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: Theme.of(context).textTheme.labelSmall),
          const SizedBox(height: 2),
          Text(
            value,
            style: Theme.of(
              context,
            ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}
