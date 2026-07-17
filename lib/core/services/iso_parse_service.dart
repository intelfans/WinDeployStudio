import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import '../../features/logs/services/log_center_service.dart';
import 'wim_info_service.dart';
import 'windows_iso_preflight.dart';
import 'windows_system_environment.dart';

class IsoMetadata {
  final String filePath;
  final String fileName;
  final int fileSize;
  final String? windowsVersion;
  final String? buildNumber;
  final String? architecture;
  final String? language;
  final String? edition;
  final bool isValidWindowsIso;

  const IsoMetadata({
    required this.filePath,
    required this.fileName,
    required this.fileSize,
    this.windowsVersion,
    this.buildNumber,
    this.architecture,
    this.language,
    this.edition,
    this.isValidWindowsIso = false,
  });

  String get displaySize {
    if (fileSize < 1024 * 1024) {
      return '${(fileSize / 1024).toStringAsFixed(0)} KB';
    }
    if (fileSize < 1024 * 1024 * 1024) {
      return '${(fileSize / (1024 * 1024)).toStringAsFixed(0)} MB';
    }
    return '${(fileSize / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }
}

final isoParseServiceProvider = Provider<IsoParseService>((ref) {
  return IsoParseService();
});

typedef ProgressCallback = void Function(String step, int percent);

/// A read-only cancellation signal for one ISO parsing operation.
///
/// It deliberately belongs to an individual parse instead of the service.
/// Reusing a service for a later selection must never make an older selection
/// active again.
class IsoParseCancellationToken {
  final Completer<void> _cancelled = Completer<void>();

  bool get isCancelled => _cancelled.isCompleted;

  Future<void> get whenCancelled => _cancelled.future;

  void _cancel() {
    if (!_cancelled.isCompleted) _cancelled.complete();
  }
}

/// Test seam for the operation coordinator. Production uses the built-in ISO
/// parser; tests can supply a controlled worker without mounting an ISO.
typedef IsoParseWorker =
    Future<IsoMetadata?> Function(
      String isoPath, {
      required IsoParseCancellationToken cancellation,
      ProgressCallback? onProgress,
    });

class IsoParseService {
  IsoParseService({this.worker});

  final IsoParseWorker? worker;
  _IsoParseOperation? _activeOperation;

  Future<IsoMetadata?> parseIso(
    String isoPath, {
    ProgressCallback? onProgress,
  }) {
    final operation = _IsoParseOperation();
    return _runOperation(operation, isoPath, onProgress);
  }

  /// Requests cancellation and completes after the running parse has released
  /// its mount and subprocesses. Callers may fire-and-forget this when they
  /// only need to update the UI; a following [parseIso] always waits for the
  /// same cleanup before mounting another image.
  Future<void> cancel() async {
    final operation = _activeOperation;
    if (operation == null) return;
    operation.cancel();
    await operation.settled;
  }

  Future<IsoMetadata?> _runOperation(
    _IsoParseOperation operation,
    String isoPath,
    ProgressCallback? onProgress,
  ) async {
    final previous = _activeOperation;
    _activeOperation = operation;

    // Parsing is intentionally serialized. Mount-DiskImage and
    // Dismount-DiskImage operate on a system-wide image attachment, so a new
    // selection must not race a cancelled selection's metadata helper or
    // cleanup. The old operation retains its own cancellation token; it can
    // never be revived by this operation.
    if (previous != null) {
      previous.cancel();
      _report(operation, onProgress, 'cleanup', 0);
      await previous.settled;
      _report(operation, onProgress, 'cleanup', 100);
    }

    try {
      if (operation.isCancelled) return null;
      final worker = this.worker;
      if (worker != null) {
        return await worker(
          isoPath,
          cancellation: operation.cancellation,
          onProgress: (step, percent) =>
              _report(operation, onProgress, step, percent),
        );
      }
      return await _parseIsoInternal(operation, isoPath, onProgress);
    } finally {
      operation.complete();
      if (identical(_activeOperation, operation)) {
        _activeOperation = null;
      }
    }
  }

  Future<IsoMetadata?> _parseIsoInternal(
    _IsoParseOperation operation,
    String isoPath,
    ProgressCallback? onProgress,
  ) async {
    final file = File(isoPath);
    if (!await file.exists()) return null;
    if (operation.isCancelled) return null;

    final fileSize = await file.length();
    if (operation.isCancelled) return null;
    final fileName = p.basename(isoPath);

    debugPrint('=== ISO Parse Start ===');
    debugPrint('File: $isoPath');
    debugPrint('Size: $fileSize bytes');

    final logCenter = LogCenterService();
    await logCenter.logIso(
      'ISO 解析开始 | 文件: $fileName | 大小: ${_formatSize(fileSize)}',
    );
    if (operation.isCancelled) return null;

    // Step 1: Filename detection (instant)
    _report(operation, onProgress, 'detect', 50);
    final fastResult = _detectFromFileName(fileName, isoPath, fileSize);
    debugPrint('Filename detection: ${fastResult.windowsVersion}');

    if (operation.isCancelled) return null;
    _report(operation, onProgress, 'detect', 100);

    // Step 2: Mount ISO
    _report(operation, onProgress, 'mount', 0);
    final mountPoint = await _mountIso(operation, isoPath);
    if (mountPoint == null) {
      debugPrint('Mount failed or cancelled');
      return operation.isCancelled ? null : fastResult;
    }
    Map<String, String>? dismInfo;
    try {
      if (operation.isCancelled) return null;
      _report(operation, onProgress, 'mount', 100);
      debugPrint('Mounted at: $mountPoint');
      _report(operation, onProgress, 'detect', 0);

      final layout = await WindowsIsoLayoutInspector.inspectMountedRoot(
        mountPoint,
        isCancelled: () => operation.isCancelled,
      );
      if (operation.isCancelled) return null;
      if (!layout.isValid || layout.imagePath == null) {
        debugPrint('Windows setup layout not found: ${layout.error}');
        return fastResult;
      }
      _report(operation, onProgress, 'detect', 100);
      if (operation.isCancelled) return null;

      if (layout.imageFormat != WindowsInstallImageFormat.swm) {
        _report(operation, onProgress, 'info', 30);
        final images = await WimInfoService.readImages(
          layout.imagePath!,
          cancellationSignal: operation.cancellation.whenCancelled,
        );
        if (operation.isCancelled) return null;
        final image = images.first;
        dismInfo = {
          'build': image.build,
          'architecture': image.architecture,
          'language': image.language,
          'edition': image.name.isEmpty ? image.edition : image.name,
        };
        final buildNumber = int.tryParse(image.build) ?? 0;
        if (buildNumber >= 22000) {
          dismInfo['version'] = 'Windows 11 (Build ${image.build})';
        } else if (buildNumber >= 10240) {
          dismInfo['version'] = 'Windows 10 (Build ${image.build})';
        } else if (image.version.isNotEmpty) {
          dismInfo['version'] = image.version;
        }
      } else {
        debugPrint(
          'Split WIM layout detected; skipping optional WIM metadata.',
        );
      }
      _report(operation, onProgress, 'info', 100);
    } catch (error) {
      if (!operation.isCancelled) {
        debugPrint('WIM metadata read failed: $error');
        _report(operation, onProgress, 'info', 100);
      }
    } finally {
      _report(operation, onProgress, 'cleanup', 0, allowCancelled: true);
      await _unmount(operation, isoPath);
      _report(operation, onProgress, 'cleanup', 100, allowCancelled: true);
    }

    if (operation.isCancelled) return null;

    // Build result
    if (dismInfo != null && dismInfo.isNotEmpty) {
      final version = dismInfo['version'] ?? fastResult.windowsVersion;
      final build = dismInfo['build'] ?? fastResult.buildNumber;
      final arch = dismInfo['architecture'];
      await logCenter.logIso(
        'ISO 解析成功 | 文件: $fileName | 版本: $version | 构建: $build | 架构: $arch',
      );
      return IsoMetadata(
        filePath: isoPath,
        fileName: fileName,
        fileSize: fileSize,
        windowsVersion: dismInfo['version'] ?? fastResult.windowsVersion,
        buildNumber: dismInfo['build'] ?? fastResult.buildNumber,
        architecture: dismInfo['architecture'],
        language: dismInfo['language'],
        edition: dismInfo['edition'],
        isValidWindowsIso: true,
      );
    }

    return IsoMetadata(
      filePath: isoPath,
      fileName: fileName,
      fileSize: fileSize,
      windowsVersion: fastResult.windowsVersion,
      buildNumber: fastResult.buildNumber,
      isValidWindowsIso: true,
    );
  }

  String _formatSize(int bytes) {
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(0)} KB';
    }
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(0)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  void _report(
    _IsoParseOperation operation,
    ProgressCallback? cb,
    String step,
    int percent, {
    bool allowCancelled = false,
  }) {
    if (allowCancelled || !operation.isCancelled) {
      cb?.call(step, percent);
    }
  }

  // --- Mount ---

  String _psQuote(String value) => "'${value.replaceAll("'", "''")}'";

  Future<String?> _mountIso(
    _IsoParseOperation operation,
    String isoPath,
  ) async {
    var mounted = false;
    var mountHandedToCaller = false;
    try {
      final quotedPath = _psQuote(isoPath);
      final result = await _runPowerShell(operation, [
        '-NoProfile',
        '-NonInteractive',
        '-ExecutionPolicy',
        'Bypass',
        '-Command',
        "Mount-DiskImage -ImagePath $quotedPath",
      ], timeout: const Duration(seconds: 15));

      if (result == null || result.exitCode != 0) return null;
      mounted = true;
      if (operation.isCancelled) return null;

      // Retry getting drive letter
      for (int i = 0; i < 5; i++) {
        if (!await _waitOrCancel(
          operation,
          const Duration(milliseconds: 500),
        )) {
          return null;
        }
        final r = await _runPowerShell(operation, [
          '-NoProfile',
          '-NonInteractive',
          '-ExecutionPolicy',
          'Bypass',
          '-Command',
          "Get-DiskImage -ImagePath $quotedPath | Get-Volume | Select-Object -ExpandProperty DriveLetter",
        ], timeout: const Duration(seconds: 5));
        if (r != null && r.exitCode == 0) {
          final letter = r.stdout.toString().trim();
          if (letter.isNotEmpty) {
            mountHandedToCaller = true;
            return '$letter:\\';
          }
        }
      }
      return null;
    } catch (e) {
      debugPrint('Mount error: $e');
      return null;
    } finally {
      // A successful mount is retained only while the caller reads its
      // metadata. On cancellation or an unsuccessful drive-letter lookup,
      // release it before the next queued selection may start.
      if (mounted && !mountHandedToCaller) {
        await _unmount(operation, isoPath);
      }
    }
  }

  Future<void> _unmount(_IsoParseOperation operation, String isoPath) async {
    try {
      final quotedPath = _psQuote(isoPath);
      final result = await _runPowerShell(
        operation,
        [
          '-NoProfile',
          '-NonInteractive',
          '-ExecutionPolicy',
          'Bypass',
          '-Command',
          "Dismount-DiskImage -ImagePath $quotedPath -ErrorAction SilentlyContinue",
        ],
        timeout: const Duration(seconds: 10),
        allowWhenCancelled: true,
        stopOnCancellation: false,
      );
      debugPrint('Unmount exited: ${result?.exitCode ?? -1}');
    } catch (e) {
      debugPrint('Unmount error: $e');
    }
  }

  Future<bool> _waitOrCancel(
    _IsoParseOperation operation,
    Duration delay,
  ) async {
    if (operation.isCancelled) return false;
    return await Future.any<bool>([
      Future<bool>.delayed(delay, () => true),
      operation.cancellation.whenCancelled.then((_) => false),
    ]);
  }

  Future<ProcessResult?> _runPowerShell(
    _IsoParseOperation operation,
    List<String> arguments, {
    required Duration timeout,
    bool allowWhenCancelled = false,
    bool stopOnCancellation = true,
  }) {
    return _runTrackedProcess(
      operation,
      WindowsSystemEnvironment.powerShellExecutable,
      arguments,
      timeout: timeout,
      allowWhenCancelled: allowWhenCancelled,
      stopOnCancellation: stopOnCancellation,
    );
  }

  Future<ProcessResult?> _runTrackedProcess(
    _IsoParseOperation operation,
    String executable,
    List<String> arguments, {
    required Duration timeout,
    bool allowWhenCancelled = false,
    bool stopOnCancellation = true,
  }) async {
    if (operation.isCancelled && !allowWhenCancelled) return null;

    Process? process;
    try {
      process = await Process.start(
        executable,
        arguments,
        environment: WindowsSystemEnvironment.withSystemRoot(),
      );
      operation.trackProcess(process, stopOnCancellation: stopOnCancellation);
      final stdout = process.stdout
          .transform(const SystemEncoding().decoder)
          .join();
      final stderr = process.stderr
          .transform(const SystemEncoding().decoder)
          .join();
      final exitCode = process.exitCode;
      final outcome = await Future.any<_ProcessOutcome>([
        exitCode.then(_ProcessOutcome.exited),
        Future<_ProcessOutcome>.delayed(timeout, _ProcessOutcome.timedOut),
        if (stopOnCancellation && !allowWhenCancelled)
          operation.cancellation.whenCancelled.then(
            (_) => const _ProcessOutcome.cancelled(),
          ),
      ]);

      if (!outcome.didExit) {
        if (outcome.timedOut) {
          debugPrint(
            'ISO parser subprocess timed out after ${timeout.inSeconds}s',
          );
        }
        await operation.terminateTrackedProcess(process);
        try {
          await exitCode.timeout(const Duration(seconds: 5));
        } catch (_) {
          // The next selection still waits for this operation's cleanup.
        }
        await stdout.timeout(const Duration(seconds: 2), onTimeout: () => '');
        await stderr.timeout(const Duration(seconds: 2), onTimeout: () => '');
        return null;
      }

      return ProcessResult(
        process.pid,
        outcome.exitCode!,
        await stdout,
        await stderr,
      );
    } catch (error) {
      debugPrint('ISO parser subprocess error: $error');
      return null;
    } finally {
      if (process != null) operation.untrackProcess(process);
    }
  }

  // --- Filename detection ---

  IsoMetadata _detectFromFileName(
    String fileName,
    String filePath,
    int fileSize,
  ) {
    String? windowsVersion;
    String? buildNumber;
    final lower = fileName.toLowerCase();

    if (lower.contains('win11') ||
        lower.contains('windows11') ||
        lower.contains('26100') ||
        lower.contains('22621') ||
        lower.contains('22000')) {
      windowsVersion = 'Windows 11';
    } else if (lower.contains('win10') ||
        lower.contains('windows10') ||
        lower.contains('19045') ||
        lower.contains('19044') ||
        lower.contains('19043')) {
      windowsVersion = 'Windows 10';
    } else if (lower.contains('server')) {
      windowsVersion = 'Windows Server';
    }

    final buildMatch = RegExp(r'(\d{5})').firstMatch(lower);
    if (buildMatch != null) buildNumber = buildMatch.group(1);

    return IsoMetadata(
      filePath: filePath,
      fileName: fileName,
      fileSize: fileSize,
      windowsVersion: windowsVersion,
      buildNumber: buildNumber,
    );
  }
}

class _IsoParseOperation {
  final IsoParseCancellationToken cancellation = IsoParseCancellationToken();
  final Completer<void> _settled = Completer<void>();
  Process? _activeProcess;
  bool _stopActiveProcessOnCancel = true;
  Future<void>? _termination;

  bool get isCancelled => cancellation.isCancelled;
  Future<void> get settled => _settled.future;

  void cancel() {
    if (isCancelled) return;
    cancellation._cancel();
    final process = _activeProcess;
    if (process != null && _stopActiveProcessOnCancel) {
      unawaited(terminateTrackedProcess(process));
    }
    debugPrint('=== ISO Parse Cancelled ===');
  }

  void complete() {
    if (!_settled.isCompleted) _settled.complete();
  }

  void trackProcess(Process process, {required bool stopOnCancellation}) {
    _activeProcess = process;
    _stopActiveProcessOnCancel = stopOnCancellation;
    if (isCancelled && stopOnCancellation) {
      unawaited(terminateTrackedProcess(process));
    }
  }

  void untrackProcess(Process process) {
    if (!identical(_activeProcess, process)) return;
    _activeProcess = null;
    _stopActiveProcessOnCancel = true;
    _termination = null;
  }

  Future<void> terminateTrackedProcess(Process process) {
    final existing = _termination;
    if (existing != null) return existing;
    final termination = _terminateProcessTree(process);
    _termination = termination;
    return termination;
  }

  Future<void> _terminateProcessTree(Process process) async {
    try {
      await Process.run(
        WindowsSystemEnvironment.taskkillExecutable,
        ['/F', '/T', '/PID', '${process.pid}'],
        environment: WindowsSystemEnvironment.withSystemRoot(),
      ).timeout(const Duration(seconds: 5));
    } catch (_) {
      process.kill();
    }
  }
}

class _ProcessOutcome {
  final int? exitCode;
  final bool timedOut;

  const _ProcessOutcome._({this.exitCode, this.timedOut = false});

  const _ProcessOutcome.cancelled() : this._();
  const _ProcessOutcome.timedOut() : this._(timedOut: true);
  _ProcessOutcome.exited(int exitCode) : this._(exitCode: exitCode);

  bool get didExit => exitCode != null;
}
