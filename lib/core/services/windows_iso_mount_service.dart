import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'windows_system_environment.dart';

/// A process-wide, read-only ISO mount coordinator.
///
/// Windows exposes ISO attachments system-wide. Serializing leases prevents a
/// picker inspection, a To Go preflight, and a cancelled cleanup from mounting
/// or dismounting the same image underneath one another.
class WindowsIsoMountService {
  WindowsIsoMountService._();

  static final WindowsIsoMountService instance = WindowsIsoMountService._();

  static Future<void> _queueTail = Future<void>.value();

  String? lastDiagnostic;

  Future<WindowsIsoMountLease?> acquire(
    String isoPath, {
    bool Function()? isCancelled,
    Duration mountTimeout = const Duration(seconds: 30),
    Duration volumeTimeout = const Duration(seconds: 45),
    int mountAttempts = 2,
  }) async {
    final source = File(p.normalize(p.absolute(isoPath)));
    if (await FileSystemEntity.type(source.path, followLinks: false) !=
        FileSystemEntityType.file) {
      lastDiagnostic = 'The ISO source is not a local regular file.';
      return null;
    }

    final previous = _queueTail;
    final releaseQueue = Completer<void>();
    _queueTail = releaseQueue.future;
    try {
      await previous.catchError((_) {});
      if (isCancelled?.call() ?? false) {
        releaseQueue.complete();
        return null;
      }

      lastDiagnostic = null;
      var ownsMount = false;
      var state = await _queryMountState(source.path);
      bool? lastConfirmedAttached = state.querySucceeded
          ? state.attached
          : null;
      if (!state.attached) {
        ProcessResult? lastMount;
        final attempts = mountAttempts.clamp(1, 3);
        for (var attempt = 0; attempt < attempts; attempt++) {
          if (isCancelled?.call() ?? false) {
            releaseQueue.complete();
            return null;
          }
          lastMount = await _runPowerShell(
            const [
              '-NoProfile',
              '-NonInteractive',
              '-ExecutionPolicy',
              'Bypass',
              '-Command',
              r'Mount-DiskImage -ImagePath $env:WDS_ISO -ErrorAction Stop | Out-Null',
            ],
            isoPath: source.path,
            timeout: mountTimeout,
            isCancelled: isCancelled,
          );
          if (isCancelled?.call() ?? false) {
            state = await _queryMountState(source.path);
            if (state.attached) await _dismount(source.path);
            releaseQueue.complete();
            return null;
          }
          if (lastMount != null && lastMount.exitCode == 0) {
            // A successful Mount-DiskImage call may return before the volume
            // has a drive letter. Let the volume wait below observe it.
            ownsMount = true;
            lastConfirmedAttached = true;
            break;
          }

          // A timeout or transient Storage-module error can still have
          // attached the image. Re-query before retrying so we do not mount
          // the same ISO twice or make the user click a second time.
          state = await _queryMountState(source.path);
          if (state.querySucceeded) {
            lastConfirmedAttached = state.attached;
          }
          if (state.querySucceeded && state.attached) {
            ownsMount = true;
            break;
          }
          if (attempt + 1 < attempts) {
            await Future<void>.delayed(const Duration(milliseconds: 500));
          }
        }
        if (!ownsMount && state.querySucceeded && !state.attached) {
          lastDiagnostic = _processDiagnostic(
            lastMount,
            fallback: 'Windows could not mount the ISO after retrying.',
          );
          releaseQueue.complete();
          return null;
        }
      }

      final deadline = DateTime.now().add(volumeTimeout);
      while (DateTime.now().isBefore(deadline)) {
        if (isCancelled?.call() ?? false) {
          if (ownsMount) await _dismount(source.path);
          releaseQueue.complete();
          return null;
        }
        state = await _queryMountState(source.path);
        if (!state.querySucceeded) {
          await Future<void>.delayed(const Duration(milliseconds: 400));
          continue;
        }
        lastConfirmedAttached = state.attached;
        if (state.driveLetter != null) {
          return WindowsIsoMountLease._(
            service: this,
            isoPath: source.path,
            mountPoint: '${state.driveLetter}:\\',
            ownsMount: ownsMount,
            releaseQueue: releaseQueue,
          );
        }
        await Future<void>.delayed(const Duration(milliseconds: 400));
      }

      lastDiagnostic = switch (lastConfirmedAttached) {
        true =>
          'Windows mounted the ISO but did not assign a usable drive letter.',
        false =>
          'The ISO attachment disappeared before its volume became ready.',
        null =>
          'Windows mounted the ISO, but its virtual drive state could not be queried.',
      };
      if (ownsMount) await _dismount(source.path);
      releaseQueue.complete();
      return null;
    } catch (error) {
      lastDiagnostic = 'ISO mount coordination failed: $error';
      if (!releaseQueue.isCompleted) releaseQueue.complete();
      return null;
    }
  }

  Future<T?> withMountedIso<T>(
    String isoPath,
    Future<T> Function(String mountPoint) action, {
    bool Function()? isCancelled,
    Duration mountTimeout = const Duration(seconds: 30),
    Duration volumeTimeout = const Duration(seconds: 45),
    int mountAttempts = 2,
  }) async {
    final lease = await acquire(
      isoPath,
      isCancelled: isCancelled,
      mountTimeout: mountTimeout,
      volumeTimeout: volumeTimeout,
      mountAttempts: mountAttempts,
    );
    if (lease == null) return null;
    try {
      return await action(lease.mountPoint);
    } finally {
      await lease.release();
    }
  }

  Future<void> _release(WindowsIsoMountLease lease) async {
    if (lease._released) return;
    lease._released = true;
    try {
      if (lease.ownsMount) await _dismount(lease.isoPath);
    } finally {
      if (!lease.releaseQueue.isCompleted) lease.releaseQueue.complete();
    }
  }

  Future<_IsoMountState> _queryMountState(String isoPath) async {
    final result = await _runPowerShell(
      const [
        '-NoProfile',
        '-NonInteractive',
        '-ExecutionPolicy',
        'Bypass',
        '-Command',
        r'''
$image = Get-DiskImage -ImagePath $env:WDS_ISO -ErrorAction SilentlyContinue
if ($null -eq $image -or -not [bool]$image.Attached) {
  Write-Output 'WDS_STATE:DETACHED'
  exit 0
}
Write-Output 'WDS_STATE:ATTACHED'
$letters = @(
  $image | Get-Volume -ErrorAction SilentlyContinue |
    Where-Object DriveLetter | Select-Object -ExpandProperty DriveLetter
)
if ($letters.Count -eq 0) {
  $letters = @(
    $image | Get-Disk -ErrorAction SilentlyContinue |
      Get-Partition -ErrorAction SilentlyContinue |
      Get-Volume -ErrorAction SilentlyContinue |
      Where-Object DriveLetter | Select-Object -ExpandProperty DriveLetter
  )
}
$letters | ForEach-Object { Write-Output ("WDS_DRIVE:{0}" -f $_) }
''',
      ],
      isoPath: isoPath,
      timeout: const Duration(seconds: 30),
    );
    if (result == null || result.exitCode != 0) {
      return const _IsoMountState(querySucceeded: false, attached: false);
    }
    var attached = false;
    String? driveLetter;
    for (final rawLine in result.stdout.toString().split(RegExp(r'\r?\n'))) {
      final line = rawLine.trim();
      if (line == 'WDS_STATE:ATTACHED') attached = true;
      if (line.startsWith('WDS_DRIVE:')) {
        final value = line.substring('WDS_DRIVE:'.length).trim().toUpperCase();
        if (RegExp(r'^[A-Z]$').hasMatch(value)) driveLetter ??= value;
      }
    }
    return _IsoMountState(
      querySucceeded: true,
      attached: attached,
      driveLetter: driveLetter,
    );
  }

  Future<void> _dismount(String isoPath) async {
    final result = await _runPowerShell(
      const [
        '-NoProfile',
        '-NonInteractive',
        '-ExecutionPolicy',
        'Bypass',
        '-Command',
        r'Dismount-DiskImage -ImagePath $env:WDS_ISO -ErrorAction SilentlyContinue | Out-Null',
      ],
      isoPath: isoPath,
      timeout: const Duration(seconds: 30),
    );
    if (result == null || result.exitCode != 0) {
      lastDiagnostic = _processDiagnostic(
        result,
        fallback: 'Windows could not release the mounted ISO.',
      );
    }
  }

  Future<ProcessResult?> _runPowerShell(
    List<String> arguments, {
    required String isoPath,
    required Duration timeout,
    bool Function()? isCancelled,
  }) async {
    Process? process;
    try {
      process = await Process.start(
        WindowsSystemEnvironment.powerShellExecutable,
        arguments,
        environment: WindowsSystemEnvironment.withSystemRoot({
          ...Platform.environment,
          'WDS_ISO': isoPath,
        }),
      );
      final stdout = process.stdout
          .transform(const SystemEncoding().decoder)
          .join();
      final stderr = process.stderr
          .transform(const SystemEncoding().decoder)
          .join();
      final exitCodeFuture = process.exitCode;
      final deadline = DateTime.now().add(timeout);
      int? exitCode;
      while (exitCode == null) {
        if (isCancelled?.call() ?? false) {
          process.kill(ProcessSignal.sigkill);
          try {
            await exitCodeFuture.timeout(const Duration(seconds: 4));
          } catch (_) {}
          return null;
        }
        final remaining = deadline.difference(DateTime.now());
        if (remaining <= Duration.zero) {
          process.kill(ProcessSignal.sigkill);
          try {
            await exitCodeFuture.timeout(const Duration(seconds: 4));
          } catch (_) {
            // The lease still releases its queue gate and later calls can retry.
          }
          return null;
        }
        try {
          exitCode = await exitCodeFuture.timeout(
            remaining.compareTo(const Duration(milliseconds: 250)) < 0
                ? remaining
                : const Duration(milliseconds: 250),
          );
        } on TimeoutException {
          // Poll cancellation while the Storage cmdlet is running.
        }
      }
      return ProcessResult(process.pid, exitCode, await stdout, await stderr);
    } catch (_) {
      process?.kill(ProcessSignal.sigkill);
      return null;
    }
  }

  static String _processDiagnostic(
    ProcessResult? result, {
    required String fallback,
  }) {
    if (result == null) return '$fallback The operation timed out.';
    final detail = result.stderr.toString().trim().isNotEmpty
        ? result.stderr.toString().trim()
        : result.stdout.toString().trim();
    if (detail.isEmpty) return fallback;
    final normalized = detail.replaceAll(RegExp(r'\s+'), ' ').trim();
    return normalized.length <= 500
        ? normalized
        : '${normalized.substring(0, 497)}...';
  }
}

class WindowsIsoMountLease {
  final WindowsIsoMountService service;
  final String isoPath;
  final String mountPoint;
  final bool ownsMount;
  final Completer<void> releaseQueue;
  bool _released = false;

  WindowsIsoMountLease._({
    required this.service,
    required this.isoPath,
    required this.mountPoint,
    required this.ownsMount,
    required this.releaseQueue,
  });

  Future<void> release() => service._release(this);
}

class _IsoMountState {
  final bool querySucceeded;
  final bool attached;
  final String? driveLetter;

  const _IsoMountState({
    required this.querySucceeded,
    required this.attached,
    this.driveLetter,
  });
}
