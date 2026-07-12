import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/localization/strings.dart';
import '../core/services/bootable_usb_service.dart';
import '../core/services/disk_safety_service.dart';
import '../core/services/elevation_service.dart';
import '../core/services/wtg_service.dart';
import 'localization.dart';
import 'theme.dart';

class ElevatedTaskApp extends StatelessWidget {
  final ElevatedTaskSpec task;

  const ElevatedTaskApp({super.key, required this.task});

  @override
  Widget build(BuildContext context) {
    final locale = localeFromCode(task.localeCode);
    final appearance = (task.appearance ?? AppAppearanceSettings.defaults)
        .copyWith(visualStyle: VisualStyle.win11);
    return MaterialApp(
      title: 'WinDeploy Studio',
      debugShowCheckedModeBanner: false,
      locale: locale,
      supportedLocales: supportedAppLocales,
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: AppTheme.light(
        appearance.accentColor,
        appearance.fontFamily,
        style: appearance.visualStyle,
      ),
      darkTheme: AppTheme.dark(
        appearance.accentColor,
        appearance.fontFamily,
        style: appearance.visualStyle,
      ),
      highContrastTheme: AppTheme.highContrastLight(
        appearance.accentColor,
        appearance.fontFamily,
        style: appearance.visualStyle,
      ),
      highContrastDarkTheme: AppTheme.highContrastDark(
        appearance.accentColor,
        appearance.fontFamily,
        style: appearance.visualStyle,
      ),
      themeMode: appearance.themeMode,
      home: _ElevatedTaskScreen(task: task),
    );
  }
}

class _ElevatedTaskScreen extends ConsumerStatefulWidget {
  final ElevatedTaskSpec task;

  const _ElevatedTaskScreen({required this.task});

  @override
  ConsumerState<_ElevatedTaskScreen> createState() =>
      _ElevatedTaskScreenState();
}

class _ElevatedTaskScreenState extends ConsumerState<_ElevatedTaskScreen> {
  double _progress = 0;
  String _messageKey = 'boot_preparing';
  bool _running = true;
  bool _success = false;
  Timer? _cancelTimer;
  final Stopwatch _stopwatch = Stopwatch();
  bool _cancelHandled = false;

  @override
  void initState() {
    super.initState();
    _stopwatch.start();
    WidgetsBinding.instance.addPostFrameCallback((_) => _run());
  }

  @override
  void dispose() {
    _cancelTimer?.cancel();
    _stopwatch.stop();
    super.dispose();
  }

  Future<void> _run() async {
    if (!await ElevationService.isAdministrator()) {
      _finish(false, 'boot_access_denied');
      return;
    }

    final taskValidationIssue = widget.task.validationIssueKey(
      requireIpcToken: true,
    );
    if (taskValidationIssue != null) {
      _finish(false, taskValidationIssue);
      return;
    }

    final operationLock = await DiskOperationLock.tryAcquire(
      widget.task.disk.diskNumber,
    );
    if (operationLock == null) {
      _finish(false, 'safety_disk_busy');
      return;
    }

    bool success;
    var failureMessageKey = 'creator_error';
    try {
      _cancelTimer = Timer.periodic(const Duration(milliseconds: 500), (_) {
        final cancelPath = widget.task.cancelPath;
        if (_cancelHandled ||
            cancelPath == null ||
            !File(cancelPath).existsSync() ||
            !_hasValidCancelMarker(cancelPath)) {
          return;
        }
        _cancelHandled = true;
        if (widget.task.kind == ElevatedTaskKind.windowsToGo) {
          ref.read(wtgServiceProvider).cancel();
        } else {
          ref.read(bootableUsbServiceProvider).cancel();
        }
      });
      switch (widget.task.kind) {
        case ElevatedTaskKind.windowsInstall:
          success = await ref
              .read(bootableUsbServiceProvider)
              .createBootableUsb(
                disk: widget.task.disk,
                isoPath: widget.task.isoPath,
                deploymentPlan: widget.task.deploymentPlan,
                onProgress: _onCreateProgress,
              );
        case ElevatedTaskKind.linuxInstall:
          final service = ref.read(bootableUsbServiceProvider);
          success = await service.createLinuxIsoUsb(
            disk: widget.task.disk,
            isoPath: widget.task.isoPath,
            kind: LinuxUsbKind.installMedia,
            deploymentPlan: widget.task.deploymentPlan,
            onProgress: _onCreateProgress,
          );
          if (!success && service.isCancelled) {
            failureMessageKey = 'deploy_cancel_requested';
          }
        case ElevatedTaskKind.linuxToGo:
          success = await ref
              .read(bootableUsbServiceProvider)
              .createLinuxIsoUsb(
                disk: widget.task.disk,
                isoPath: widget.task.isoPath,
                kind: LinuxUsbKind.toGo,
                deploymentPlan: widget.task.deploymentPlan,
                onProgress: _onCreateProgress,
              );
        case ElevatedTaskKind.windowsToGo:
          final service = ref.read(wtgServiceProvider);
          success = await service.createWtg(
            disk: widget.task.disk,
            isoPath: widget.task.isoPath,
            imageIndex: widget.task.imageIndex ?? 1,
            driveLetter: widget.task.disk.driveLetters.isEmpty
                ? ''
                : widget.task.disk.driveLetters.first,
            deploymentPlan: widget.task.deploymentPlan,
            onProgress: _onWtgProgress,
          );
          if (!success && service.isCancelled) {
            failureMessageKey = 'deploy_cancel_requested';
          }
      }
    } catch (_) {
      success = false;
    } finally {
      _cancelTimer?.cancel();
      await operationLock.release();
    }
    _finish(success, success ? 'boot_complete' : failureMessageKey);
  }

  void _onCreateProgress(CreateProgress progress) {
    if (!mounted) return;
    setState(() {
      _progress = progress.progress;
      _messageKey = progress.message.split('\n').first;
    });
    _writeProgress(
      phase: progress.step.name,
      message: progress.message,
      progress: progress.progress,
      cancellable:
          widget.task.kind == ElevatedTaskKind.linuxInstall &&
          (progress.step == CreateStep.copyingFiles ||
              progress.step == CreateStep.verifying),
    );
  }

  void _onWtgProgress(WtgProgress progress) {
    if (!mounted) return;
    setState(() {
      _progress = progress.progress;
      _messageKey = progress.message.split('\n').first;
    });
    _writeProgress(
      phase: progress.step.name,
      message: progress.message,
      progress: progress.progress,
      cancellable:
          progress.step == WtgStep.mountingIso ||
          progress.step == WtgStep.applyingImage ||
          progress.step == WtgStep.verifying,
      writtenBytes: progress.writtenBytes,
      totalBytes: progress.totalBytes,
      speedBytesPerSecond: progress.currentSpeedBytes,
    );
  }

  void _writeProgress({
    required String phase,
    required String message,
    required double progress,
    required bool cancellable,
    int writtenBytes = 0,
    int totalBytes = 0,
    int speedBytesPerSecond = 0,
  }) {
    final path = widget.task.progressPath;
    if (path == null) return;
    try {
      final target = File(path);
      final pending = File('$path.tmp');
      pending.writeAsStringSync(
        jsonEncode({
          'phase': phase,
          'ipcToken': widget.task.ipcToken,
          'message': message,
          'progress': progress.clamp(0, 1),
          'cancellable': cancellable,
          'writtenBytes': writtenBytes,
          'totalBytes': totalBytes,
          'speedBytesPerSecond': speedBytesPerSecond,
          'elapsedSeconds': _stopwatch.elapsed.inSeconds,
        }),
        flush: true,
      );
      if (target.existsSync()) target.deleteSync();
      pending.renameSync(target.path);
    } catch (_) {}
  }

  void _finish(bool success, String messageKey) {
    if (!mounted) return;
    final resultPath = widget.task.resultPath;
    if (resultPath != null) {
      try {
        File(resultPath).writeAsStringSync(
          '${success ? 'success' : 'failed'}|${widget.task.ipcToken}',
        );
      } catch (_) {}
    }
    setState(() {
      _running = false;
      _success = success;
      _progress = success ? 1 : _progress;
      _messageKey = messageKey;
    });
    _writeProgress(
      phase: success ? 'complete' : 'failed',
      message: messageKey,
      progress: success ? 1 : _progress,
      cancellable: false,
    );
    Timer(const Duration(seconds: 2), () => exit(success ? 0 : 1));
  }

  bool _hasValidCancelMarker(String path) {
    final token = widget.task.ipcToken;
    if (token == null) return false;
    try {
      return File(path).readAsStringSync().trim() == 'cancel|$token';
    } catch (_) {
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final localized = tr(context, _messageKey);
    final message = localized == _messageKey && _messageKey.contains('_')
        ? tr(context, _success ? 'boot_complete' : 'creator_error')
        : localized;
    return PopScope(
      canPop: !_running,
      child: Scaffold(
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    _running
                        ? Icons.admin_panel_settings_outlined
                        : (_success
                              ? Icons.check_circle_outline
                              : Icons.error_outline),
                    size: 64,
                    color: _success
                        ? Colors.green
                        : (_running
                              ? theme.colorScheme.primary
                              : theme.colorScheme.error),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    tr(context, 'app_name'),
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(message, textAlign: TextAlign.center),
                  const SizedBox(height: 24),
                  LinearProgressIndicator(
                    value: _running ? _progress.clamp(0, 1) : 1,
                  ),
                  const SizedBox(height: 24),
                  if (!_running)
                    FilledButton(
                      onPressed: () => exit(_success ? 0 : 1),
                      child: Text(tr(context, 'close')),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
