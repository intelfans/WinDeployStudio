import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../../core/services/disk_safety_service.dart';
import '../../benchmark_history/services/benchmark_history_service.dart';
import '../models/benchmark_models.dart';
import 'benchmark_analysis.dart';
import 'benchmark_workspace_cleanup.dart';

final driveBenchmarkServiceProvider = Provider<DriveBenchmarkService>((ref) {
  return DriveBenchmarkService(ref);
});

typedef BenchmarkProgressCallback = void Function(BenchmarkProgress progress);

class BenchmarkCancelToken {
  bool _isCancelled = false;
  final Completer<void> _cancelled = Completer<void>();

  bool get isCancelled => _isCancelled;
  Future<void> get whenCancelled => _cancelled.future;

  void cancel() {
    if (_isCancelled) return;
    _isCancelled = true;
    _cancelled.complete();
  }
}

class BenchmarkCancelledException implements Exception {
  const BenchmarkCancelledException();
}

class DriveBenchmarkService {
  static const _oneMB = 1024 * 1024;

  final Ref ref;
  final Random _random = Random.secure();

  DriveBenchmarkService(this.ref);

  Future<BenchmarkResult> run({
    required DiskInfo disk,
    required BenchmarkMode mode,
    required BenchmarkCancelToken cancelToken,
    BenchmarkProgressCallback? onProgress,
  }) async {
    final operationLock = await DiskOperationLock.tryAcquire(disk.diskNumber);
    if (operationLock == null) throw StateError('safety_disk_busy');

    try {
      final currentDisk = await ref
          .read(diskSafetyServiceProvider)
          .refreshDisk(disk);
      if (currentDisk == null) throw StateError('safety_disk_changed');
      final safety = await ref
          .read(diskSafetyServiceProvider)
          .checkDiskSafety(currentDisk);
      if (!safety.isSafe) throw StateError(safety.reason);

      final driveRoot = _driveRootForDisk(currentDisk);
      if (driveRoot == null) throw StateError('bench_error_no_drive_letter');
      if (!Directory(driveRoot).existsSync()) {
        throw StateError('bench_error_drive_not_ready');
      }

      final helperPath = p.join(
        p.dirname(Platform.resolvedExecutable),
        'wds_benchmark_helper.exe',
      );
      if (!await File(helperPath).exists()) {
        throw StateError('bench_error_helper_missing');
      }

      final startedAt = DateTime.now();
      final parameters = BenchmarkRunParameters.forMode(mode);
      final ownerToken =
          '${pid}_${startedAt.microsecondsSinceEpoch}_${_random.nextInt(1 << 32)}';
      final tempDir = Directory(
        p.join(driveRoot, '$benchmarkWorkspacePrefix$ownerToken'),
      );
      final workspaceCleaner = BenchmarkWorkspaceCleaner(
        volumeRoot: Directory(driveRoot),
        isProcessAlive: _isProcessAlive,
      );
      final stopwatch = Stopwatch()..start();
      final sequentialReadPoints = <BenchmarkPoint>[];
      final sequentialPoints = <BenchmarkPoint>[];
      final random4kReadPoints = <BenchmarkPoint>[];
      final random4kPoints = <BenchmarkPoint>[];
      final threadPoints = <BenchmarkPoint>[];
      final mixedWorkloadPoints = <BenchmarkPoint>[];
      final fullWritePoints = <BenchmarkPoint>[];
      final measurements = <BenchmarkMeasurement>[];
      final liveSeries = <_MutableBenchmarkSeries>[];
      var totalWarmup = Duration.zero;
      var totalCooldown = Duration.zero;

      void emit(
        BenchmarkPhase phase,
        double progress,
        String messageKey, {
        BenchmarkWorkload? workload,
        double currentSpeed = 0,
        double currentIops = 0,
        BenchmarkLatency latency = const BenchmarkLatency(),
      }) {
        onProgress?.call(
          BenchmarkProgress(
            phase: phase,
            workload: workload,
            progress: progress.clamp(0, 1),
            elapsed: stopwatch.elapsed,
            messageKey: messageKey,
            currentSpeedMBps: currentSpeed,
            currentIops: currentIops,
            currentLatency: latency,
            sequentialReadPoints: List.unmodifiable(sequentialReadPoints),
            sequentialPoints: List.unmodifiable(sequentialPoints),
            random4kReadPoints: List.unmodifiable(random4kReadPoints),
            random4kPoints: List.unmodifiable(random4kPoints),
            threadPoints: List.unmodifiable(threadPoints),
            mixedWorkloadPoints: List.unmodifiable(mixedWorkloadPoints),
            fullWritePoints: List.unmodifiable(fullWritePoints),
            sampleSeries: liveSeries
                .map((series) => series.snapshot())
                .toList(growable: false),
          ),
        );
      }

      void ensureNotCancelled() {
        if (cancelToken.isCancelled) throw const BenchmarkCancelledException();
      }

      Future<_NativeBenchmarkResult> runStage({
        required List<String> arguments,
        required BenchmarkPhase phase,
        required double progressStart,
        required double progressEnd,
        required String messageKey,
        required int seconds,
        required Duration warmup,
        required Duration cooldown,
        required BenchmarkWorkload workload,
        int threadCount = 1,
        int readPercent = 0,
        required void Function(BenchmarkSample sample) onSample,
        double Function(BenchmarkSample sample)? sampleProgress,
      }) async {
        totalWarmup += warmup;
        totalCooldown += cooldown;
        final series = _MutableBenchmarkSeries(
          workload: workload,
          threadCount: threadCount,
          readPercent: readPercent,
        );
        liveSeries.add(series);
        emit(
          BenchmarkPhase.warmingUp,
          progressStart,
          messageKey,
          workload: workload,
        );
        final result = await _runHelper(
          helperPath: helperPath,
          arguments: arguments,
          cancelToken: cancelToken,
          onState: (state) {
            final nativePhase = switch (state) {
              'WARMUP' => BenchmarkPhase.warmingUp,
              'COOLDOWN' => BenchmarkPhase.coolingDown,
              'PREPARING' => BenchmarkPhase.preparing,
              _ => phase,
            };
            emit(
              nativePhase,
              state == 'COOLDOWN' ? progressEnd : progressStart,
              messageKey,
              workload: workload,
            );
          },
          onSample: (sample) {
            series.samples.add(sample);
            onSample(sample);
            final fraction =
                sampleProgress?.call(sample) ??
                (seconds <= 0 ? 0.0 : (sample.x / seconds).clamp(0.0, 1.0));
            emit(
              phase,
              progressStart + (progressEnd - progressStart) * fraction,
              messageKey,
              workload: workload,
              currentSpeed: sample.throughputMBps,
              currentIops: sample.iops,
              latency: sample.latency,
            );
          },
        );
        series.complete(result);
        return result;
      }

      try {
        emit(BenchmarkPhase.preparing, 0.01, 'bench_msg_preparing');
        final recovery = await workspaceCleaner.recoverStaleWorkspaces();
        if (!recovery.succeeded) {
          throw StateError('bench_error_cleanup_failed');
        }
        await workspaceCleaner.writeMarker(
          tempDir,
          BenchmarkWorkspaceOwner(
            token: ownerToken,
            parentPid: pid,
            createdAt: startedAt,
          ),
        );

        final warmupMs = mode.warmupDuration.inMilliseconds;
        final cooldownMs = mode.cooldownDuration.inMilliseconds;

        ensureNotCancelled();
        final sequentialFile = File(p.join(tempDir.path, 'sequential.bin'));
        final sequentialWrite = await runStage(
          arguments: [
            'sequential-v3',
            'write',
            sequentialFile.path,
            '${mode.sequentialSeconds}',
            '${mode.sequentialLimitBytes}',
            '$warmupMs',
            '$cooldownMs',
            '0',
          ],
          phase: BenchmarkPhase.sequential,
          progressStart: 0.02,
          progressEnd: 0.10,
          messageKey: 'bench_msg_sequential',
          seconds: mode.sequentialSeconds,
          warmup: mode.warmupDuration,
          cooldown: mode.cooldownDuration,
          workload: BenchmarkWorkload.sequentialWrite,
          onSample: (sample) => sequentialPoints.add(sample.toPoint()),
        );
        measurements.add(
          sequentialWrite.toMeasurement(BenchmarkWorkload.sequentialWrite),
        );

        ensureNotCancelled();
        final sequentialRead = await runStage(
          arguments: [
            'sequential-v3',
            'read',
            sequentialFile.path,
            '${mode.sequentialSeconds}',
            '${mode.sequentialLimitBytes}',
            '$warmupMs',
            '$cooldownMs',
            '0',
          ],
          phase: BenchmarkPhase.sequential,
          progressStart: 0.10,
          progressEnd: 0.18,
          messageKey: 'bench_msg_sequential',
          seconds: mode.sequentialSeconds,
          warmup: mode.warmupDuration,
          cooldown: mode.cooldownDuration,
          workload: BenchmarkWorkload.sequentialRead,
          readPercent: 100,
          onSample: (sample) => sequentialReadPoints.add(sample.toPoint()),
        );
        measurements.add(
          sequentialRead.toMeasurement(
            BenchmarkWorkload.sequentialRead,
            readPercent: 100,
          ),
        );

        ensureNotCancelled();
        final randomFile = File(p.join(tempDir.path, 'random.bin'));
        final randomWrite = await runStage(
          arguments: [
            'random-v3',
            randomFile.path,
            '${mode.random4kSeconds}',
            '${mode.randomFileBytes}',
            '1',
            '0',
            '$warmupMs',
            '$cooldownMs',
          ],
          phase: BenchmarkPhase.random4k,
          progressStart: 0.18,
          progressEnd: 0.27,
          messageKey: 'bench_msg_random4k',
          seconds: mode.random4kSeconds,
          warmup: mode.warmupDuration,
          cooldown: mode.cooldownDuration,
          workload: BenchmarkWorkload.random4kWrite,
          onSample: (sample) => random4kPoints.add(sample.toPoint()),
        );
        measurements.add(
          randomWrite.toMeasurement(BenchmarkWorkload.random4kWrite),
        );

        ensureNotCancelled();
        final randomRead = await runStage(
          arguments: [
            'random-v3',
            randomFile.path,
            '${mode.random4kSeconds}',
            '${mode.randomFileBytes}',
            '1',
            '100',
            '$warmupMs',
            '$cooldownMs',
          ],
          phase: BenchmarkPhase.random4k,
          progressStart: 0.27,
          progressEnd: 0.36,
          messageKey: 'bench_msg_random4k',
          seconds: mode.random4kSeconds,
          warmup: mode.warmupDuration,
          cooldown: mode.cooldownDuration,
          workload: BenchmarkWorkload.random4kRead,
          readPercent: 100,
          onSample: (sample) => random4kReadPoints.add(sample.toPoint()),
        );
        measurements.add(
          randomRead.toMeasurement(
            BenchmarkWorkload.random4kRead,
            readPercent: 100,
          ),
        );
        final adjusted4k = _adjustedRandomSpeed(randomWrite.samples);

        ensureNotCancelled();
        final threadSpeeds = <double>[];
        final threadCounts = mode.threadCounts;
        for (var index = 0; index < threadCounts.length; index++) {
          ensureNotCancelled();
          final threadCount = threadCounts[index];
          final progressStart = 0.36 + 0.18 * (index / threadCounts.length);
          final progressEnd = 0.36 + 0.18 * ((index + 1) / threadCounts.length);
          final threadResult = await runStage(
            arguments: [
              'random-v3',
              randomFile.path,
              '${mode.threadSeconds}',
              '${mode.randomFileBytes}',
              '$threadCount',
              '50',
              '$warmupMs',
              '$cooldownMs',
            ],
            phase: BenchmarkPhase.multiThread,
            progressStart: progressStart,
            progressEnd: progressEnd,
            messageKey: 'bench_msg_multithread',
            seconds: mode.threadSeconds,
            warmup: mode.warmupDuration,
            cooldown: mode.cooldownDuration,
            workload: BenchmarkWorkload.random4kMultiThread,
            threadCount: threadCount,
            readPercent: 50,
            onSample: (_) {},
          );
          threadSpeeds.add(threadResult.averageMBps);
          threadPoints.add(
            BenchmarkPoint(
              x: threadCount.toDouble(),
              y: threadResult.averageMBps,
              label: '$threadCount',
            ),
          );
          measurements.add(
            threadResult.toMeasurement(
              BenchmarkWorkload.random4kMultiThread,
              threadCount: threadCount,
              readPercent: 50,
            ),
          );
          emit(
            BenchmarkPhase.multiThread,
            progressEnd,
            'bench_msg_multithread',
            currentSpeed: threadResult.averageMBps,
            currentIops: threadResult.iops,
            latency: threadResult.latency,
          );
        }
        final threadMetrics = analyzeThreadCurve({
          for (var index = 0; index < threadCounts.length; index++)
            if (index < threadSpeeds.length)
              threadCounts[index]: threadSpeeds[index],
        });

        final scenarios = MixedWorkloadScenario.values;
        for (var index = 0; index < scenarios.length; index++) {
          ensureNotCancelled();
          final scenario = scenarios[index];
          final progressStart = 0.54 + 0.26 * (index / scenarios.length);
          final progressEnd = 0.54 + 0.26 * ((index + 1) / scenarios.length);
          final scenarioResult = await runStage(
            arguments: [
              'scenario-v3',
              scenario.protocolName,
              randomFile.path,
              '${mode.mixedWorkloadSeconds}',
              '${mode.randomFileBytes}',
              '$warmupMs',
              '$cooldownMs',
            ],
            phase: BenchmarkPhase.mixedWorkloads,
            progressStart: progressStart,
            progressEnd: progressEnd,
            messageKey: 'bench_msg_multithread',
            seconds: mode.mixedWorkloadSeconds,
            warmup: mode.warmupDuration,
            cooldown: mode.cooldownDuration,
            workload: scenario.workload,
            onSample: (_) {},
          );
          mixedWorkloadPoints.add(
            BenchmarkPoint(
              x: (index + 1).toDouble(),
              y: scenarioResult.averageMBps,
              label: scenario.protocolName,
            ),
          );
          measurements.add(
            scenarioResult.toMeasurement(
              scenario.workload,
              threadCount: scenarioResult.threadCount,
              readPercent: scenarioResult.readPercent,
            ),
          );
          emit(
            BenchmarkPhase.mixedWorkloads,
            progressEnd,
            'bench_msg_multithread',
            currentSpeed: scenarioResult.averageMBps,
            currentIops: scenarioResult.iops,
            latency: scenarioResult.latency,
          );
        }

        var fullP10 = 0.0;
        var fullEnd = 0.0;
        var fullDrop = 0.0;
        var fullStatus = BenchmarkFullWriteStatus.notRun;
        var fullAvailableBytes = 0;
        var fullTargetBytes = 0;
        var slcAnalysis = const BenchmarkSlcAnalysis(
          status: BenchmarkSlcStatus.notRun,
        );
        if (mode.includesFullWrite) {
          ensureNotCancelled();
          if (!await _deleteShortWorkloadFiles([sequentialFile, randomFile])) {
            throw StateError('bench_error_cleanup_failed');
          }
          emit(BenchmarkPhase.coolingDown, 0.80, 'bench_msg_full');
          await _waitForCooldown(mode.fullWriteCooldownDuration, cancelToken);
          totalCooldown += mode.fullWriteCooldownDuration;
          ensureNotCancelled();

          fullAvailableBytes = await _freeSpaceBytes(driveRoot);
          fullTargetBytes = max(
            0,
            fullAvailableBytes - parameters.fullWriteReserveBytes,
          );
          if (fullTargetBytes < parameters.fullWriteMinimumBytes) {
            fullStatus = BenchmarkFullWriteStatus.insufficientSpace;
            emit(BenchmarkPhase.fullSequential, 0.96, 'bench_msg_full');
          } else {
            final fullDirectory = Directory(p.join(tempDir.path, 'full_write'));
            await fullDirectory.create();
            final fullFile = File(
              p.join(fullDirectory.path, 'available-space.bin'),
            );
            final full = await runStage(
              arguments: [
                'sequential-v3',
                'write',
                fullFile.path,
                '0',
                '$fullTargetBytes',
                '0',
                '${mode.fullWriteCooldownDuration.inMilliseconds}',
                '1',
              ],
              phase: BenchmarkPhase.fullSequential,
              progressStart: 0.80,
              progressEnd: 0.96,
              messageKey: 'bench_msg_full',
              seconds: 0,
              warmup: Duration.zero,
              cooldown: mode.fullWriteCooldownDuration,
              workload: BenchmarkWorkload.fullSequentialWrite,
              onSample: (sample) {
                fullWritePoints.add(
                  BenchmarkPoint(
                    x: sample.x,
                    y: sample.throughputMBps,
                    label: '${sample.x.toStringAsFixed(1)}GB',
                  ),
                );
              },
              sampleProgress: (sample) =>
                  ((sample.x * 1024 * _oneMB) / fullTargetBytes).clamp(
                    0.0,
                    1.0,
                  ),
            );
            measurements.add(
              full.toMeasurement(BenchmarkWorkload.fullSequentialWrite),
            );
            fullStatus = BenchmarkFullWriteStatus.completed;
            fullP10 = fullWriteP10(full.samples);
            fullEnd = full.samples.isEmpty
                ? 0.0
                : full.samples.last.throughputMBps;
            fullDrop = fullWriteDropRatio(full.samples);
            slcAnalysis = analyzeSlcSamples(full.samples, wasRun: true);
          }
        }

        emit(BenchmarkPhase.finalizing, 0.97, 'bench_msg_finalizing');
        final cleanupSucceeded = await workspaceCleaner.cleanupOwnedWorkspace(
          tempDir,
          ownerToken,
        );
        if (!cleanupSucceeded) throw StateError('bench_error_cleanup_failed');
        stopwatch.stop();

        final scenarioRatings = MixedWorkloadScenario.values
            .map((scenario) {
              final measurement = measurements.firstWhere(
                (item) => item.workload == scenario.workload,
              );
              return BenchmarkScenarioRatingSample(
                workload: scenario.workload,
                throughputMBps: measurement.averageMBps,
                p99Ms: measurement.latency.p99Ms,
              );
            })
            .toList(growable: false);
        final rating = calculateBenchmarkRating(
          BenchmarkRatingInput(
            sequentialWriteMBps: sequentialWrite.averageMBps,
            sequentialReadMBps: sequentialRead.averageMBps,
            adjusted4kMBps: adjusted4k,
            random4kReadIops: randomRead.iops,
            low4kMBps: randomWrite.lowMBps,
            stability: randomWrite.stability,
            randomReadP99Ms: randomRead.latency.p99Ms,
            randomWriteP99Ms: randomWrite.latency.p99Ms,
            multiThreadMultiplier: threadMetrics.multiplier,
            multiThreadRetention: threadMetrics.retention,
            multiThreadNormalizedEfficiency: threadMetrics.normalizedEfficiency,
            scenarios: scenarioRatings,
            fullWriteDropRatio: fullStatus == BenchmarkFullWriteStatus.completed
                ? fullDrop
                : null,
          ),
        );

        var result = BenchmarkResult(
          disk: currentDisk,
          device: BenchmarkDeviceIdentity.fromDisk(currentDisk),
          driveRoot: driveRoot,
          mode: mode,
          parameters: parameters,
          duration: stopwatch.elapsed,
          warmupDuration: totalWarmup,
          cooldownDuration: totalCooldown,
          sequentialReadMBps: sequentialRead.averageMBps,
          sequentialWriteMBps: sequentialWrite.averageMBps,
          random4kReadAverageMBps: randomRead.averageMBps,
          random4kReadIops: randomRead.iops,
          random4kWriteIops: randomWrite.iops,
          random4kAverageMBps: randomWrite.averageMBps,
          random4kAdjustedMBps: adjusted4k,
          random4kLowMBps: randomWrite.lowMBps,
          random4kStability: randomWrite.stability,
          multiThreadPeakMBps: threadMetrics.peakMBps,
          multiThreadMultiplier: threadMetrics.multiplier,
          multiThreadRetention: threadMetrics.retention,
          multiThreadNormalizedEfficiency: threadMetrics.normalizedEfficiency,
          fullWriteP10MBps: fullP10,
          fullWriteEndMBps: fullEnd,
          fullWriteDropRatio: fullDrop,
          fullWriteStatus: fullStatus,
          fullWriteAvailableBytes: fullAvailableBytes,
          fullWriteTargetBytes: fullTargetBytes,
          slcStatus: slcAnalysis.status,
          slcCacheInflectionGB: slcAnalysis.inflectionGB,
          postCacheStableMBps: slcAnalysis.stableMBps,
          slcConfidence: slcAnalysis.confidence,
          score: rating.score,
          suitability: rating.suitability,
          sequentialReadPoints: List.unmodifiable(sequentialReadPoints),
          sequentialPoints: List.unmodifiable(sequentialPoints),
          random4kReadPoints: List.unmodifiable(random4kReadPoints),
          random4kPoints: List.unmodifiable(random4kPoints),
          threadPoints: List.unmodifiable(threadPoints),
          mixedWorkloadPoints: List.unmodifiable(mixedWorkloadPoints),
          fullWritePoints: List.unmodifiable(fullWritePoints),
          measurements: List.unmodifiable(measurements),
          completedAt: DateTime.now(),
        );

        try {
          await ref.read(benchmarkHistoryServiceProvider).add(result);
        } catch (error) {
          debugPrint('Unable to save benchmark history: $error');
          result = result.withHistorySaveError(error);
        }
        emit(BenchmarkPhase.complete, 1, 'bench_msg_complete');
        return result;
      } on BenchmarkCancelledException {
        stopwatch.stop();
        emit(BenchmarkPhase.cancelled, 0, 'bench_msg_cancelled');
        final cleaned = await workspaceCleaner.cleanupOwnedWorkspace(
          tempDir,
          ownerToken,
        );
        if (!cleaned) throw StateError('bench_error_cleanup_failed');
        rethrow;
      } catch (error) {
        stopwatch.stop();
        debugPrint('Drive benchmark failed: $error');
        emit(BenchmarkPhase.failed, 0, 'bench_msg_failed');
        final cleaned = await workspaceCleaner.cleanupOwnedWorkspace(
          tempDir,
          ownerToken,
        );
        if (!cleaned) throw StateError('bench_error_cleanup_failed');
        rethrow;
      }
    } finally {
      await operationLock.release();
    }
  }

  Future<_NativeBenchmarkResult> _runHelper({
    required String helperPath,
    required List<String> arguments,
    required BenchmarkCancelToken cancelToken,
    void Function(String state)? onState,
    void Function(BenchmarkSample sample)? onSample,
  }) async {
    final process = await Process.start(helperPath, [
      '--parent-pid',
      '$pid',
      ...arguments,
    ]);
    final samples = <BenchmarkSample>[];
    int? protocolVersion;
    var protocolInvalid = false;
    var resultReceived = false;
    var average = 0.0;
    var low = 0.0;
    var stability = 0.0;
    var bytesProcessed = 0;
    var iops = 0.0;
    var readMBps = 0.0;
    var writeMBps = 0.0;
    var latency = const BenchmarkLatency();
    var cacheInflectionGB = 0.0;
    var cacheStableMBps = 0.0;
    var cacheStatus = BenchmarkSlcStatus.notRun;
    var cacheConfidence = 0.0;
    var cacheReceived = false;
    var threadCount = 1;
    var readPercent = 0;
    final stderr = StringBuffer();

    final stdoutDone = process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) {
          final parts = line.trim().split('|');
          if (parts.isEmpty) return;
          final recordType = parts[0];
          final validShape = switch (recordType) {
            'PROTO' => parts.length == 2,
            'STATE' => parts.length == 2 || parts.length == 3,
            'PROFILE' => parts.length == 4,
            'SAMPLE' => parts.length == 9,
            'RESULT' => parts.length == 15,
            'CACHE' => parts.length == 5,
            _ => true,
          };
          if (!validShape) {
            protocolInvalid = true;
            return;
          }
          switch (parts[0]) {
            case 'PROTO' when parts.length == 2:
              final parsed = int.tryParse(parts[1]);
              if (protocolVersion != null ||
                  parsed != benchmarkProtocolVersion) {
                protocolInvalid = true;
              } else {
                protocolVersion = parsed;
              }
            case 'STATE' when parts.length >= 2:
              if (parts.length > 3 ||
                  (parts.length == 3 && _nonNegativeInt(parts[2]) == null)) {
                protocolInvalid = true;
                return;
              }
              onState?.call(parts[1]);
            case 'PROFILE' when parts.length >= 4:
              if (parts.length != 4) {
                protocolInvalid = true;
                return;
              }
              final parsedReadPercent = int.tryParse(parts[2]);
              final parsedThreadCount = int.tryParse(parts[3]);
              if (parsedReadPercent == null ||
                  parsedReadPercent < 0 ||
                  parsedReadPercent > 100 ||
                  parsedThreadCount == null ||
                  parsedThreadCount < 1 ||
                  parsedThreadCount > 64) {
                protocolInvalid = true;
                return;
              }
              readPercent = parsedReadPercent;
              threadCount = parsedThreadCount;
            case 'SAMPLE' when parts.length >= 3:
              if (parts.length != 9) {
                protocolInvalid = true;
                return;
              }
              final values = List<double?>.generate(
                8,
                (index) => _nonNegativeDouble(parts[index + 1]),
              );
              if (values.any((value) => value == null)) {
                protocolInvalid = true;
                return;
              }
              final x = values[0]!;
              final speed = values[1]!;
              final sample = BenchmarkSample(
                x: x,
                throughputMBps: speed,
                iops: values[2]!,
                readMBps: values[3]!,
                writeMBps: values[4]!,
                latency: BenchmarkLatency(
                  p50Ms: values[5]!,
                  p95Ms: values[6]!,
                  p99Ms: values[7]!,
                ),
              );
              samples.add(sample);
              onSample?.call(sample);
            case 'RESULT' when parts.length == 15:
              if (resultReceived) {
                protocolInvalid = true;
                return;
              }
              final values = List<double?>.generate(
                3,
                (index) => _nonNegativeDouble(parts[index + 1]),
              );
              final parsedBytes = _nonNegativeInt(parts[4]);
              final throughputValues = List<double?>.generate(
                3,
                (index) => _nonNegativeDouble(parts[index + 5]),
              );
              final latencyValues = List<double?>.generate(
                3,
                (index) => _nonNegativeDouble(parts[index + 8]),
              );
              final parsedStatus = _parseSlcStatus(parts[11]);
              final cacheValues = List<double?>.generate(
                3,
                (index) => _nonNegativeDouble(parts[index + 12]),
              );
              if (values.any((value) => value == null) ||
                  parsedBytes == null ||
                  throughputValues.any((value) => value == null) ||
                  latencyValues.any((value) => value == null) ||
                  parsedStatus == null ||
                  cacheValues.any((value) => value == null) ||
                  values[2]! > 1.0 ||
                  cacheValues[2]! > 1.0) {
                protocolInvalid = true;
                return;
              }
              resultReceived = true;
              average = values[0]!;
              low = values[1]!;
              stability = values[2]!;
              bytesProcessed = parsedBytes;
              iops = throughputValues[0]!;
              readMBps = throughputValues[1]!;
              writeMBps = throughputValues[2]!;
              latency = BenchmarkLatency(
                p50Ms: latencyValues[0]!,
                p95Ms: latencyValues[1]!,
                p99Ms: latencyValues[2]!,
              );
              cacheStatus = parsedStatus;
              cacheInflectionGB = cacheValues[0]!;
              cacheStableMBps = cacheValues[1]!;
              cacheConfidence = cacheValues[2]!;
            case 'CACHE' when parts.length == 5:
              if (cacheReceived) {
                protocolInvalid = true;
                return;
              }
              final parsedStatus = _parseSlcStatus(parts[1]);
              final values = List<double?>.generate(
                3,
                (index) => _nonNegativeDouble(parts[index + 2]),
              );
              if (parsedStatus == null ||
                  values.any((value) => value == null) ||
                  values[2]! > 1.0) {
                protocolInvalid = true;
                return;
              }
              cacheReceived = true;
              cacheStatus = parsedStatus;
              cacheInflectionGB = values[0]!;
              cacheStableMBps = values[1]!;
              cacheConfidence = values[2]!;
          }
        })
        .asFuture<void>();
    final stderrDone = process.stderr
        .transform(utf8.decoder)
        .listen(stderr.write)
        .asFuture<void>();
    final exitFuture = process.exitCode;

    final cancelledFirst = await Future.any<bool>([
      exitFuture.then((_) => false),
      cancelToken.whenCancelled.then((_) => true),
    ]);
    if (cancelledFirst) {
      await _terminateHelper(process);
      await stdoutDone.catchError((_) {});
      await stderrDone.catchError((_) {});
      throw const BenchmarkCancelledException();
    }

    final exitCode = await exitFuture;
    await stdoutDone;
    await stderrDone;
    if (cancelToken.isCancelled) throw const BenchmarkCancelledException();
    if (exitCode != 0 ||
        protocolInvalid ||
        protocolVersion != benchmarkProtocolVersion ||
        !resultReceived ||
        samples.isEmpty ||
        average <= 0) {
      final detail = stderr.toString().trim();
      throw StateError(
        detail.isEmpty
            ? 'bench_error_native_failed'
            : 'bench_error_native_failed: $detail',
      );
    }
    return _NativeBenchmarkResult(
      protocolVersion: protocolVersion!,
      averageMBps: average,
      lowMBps: low,
      stability: stability.clamp(0.0, 1.0),
      bytesProcessed: bytesProcessed,
      iops: iops,
      readMBps: readMBps,
      writeMBps: writeMBps,
      latency: latency,
      cacheInflectionGB: cacheInflectionGB,
      cacheStableMBps: cacheStableMBps,
      cacheStatus: cacheStatus,
      cacheConfidence: cacheConfidence,
      threadCount: threadCount,
      readPercent: readPercent,
      samples: List.unmodifiable(samples),
    );
  }

  Future<void> _terminateHelper(Process process) async {
    process.kill();
    try {
      await process.exitCode.timeout(const Duration(seconds: 2));
      return;
    } on TimeoutException {
      await Process.run('taskkill', [
        '/F',
        '/T',
        '/PID',
        '${process.pid}',
      ]).timeout(const Duration(seconds: 5));
    }
    await process.exitCode.timeout(const Duration(seconds: 5));
  }

  Future<bool> _deleteShortWorkloadFiles(List<File> files) async {
    for (var attempt = 0; attempt < 5; attempt++) {
      for (final file in files) {
        try {
          if (await file.exists()) await file.delete();
        } catch (_) {}
      }
      if (await Future.wait(
        files.map((file) => file.exists()),
      ).then((states) => states.every((exists) => !exists))) {
        return true;
      }
      await Future<void>.delayed(Duration(milliseconds: 250 * (attempt + 1)));
    }
    return false;
  }

  Future<void> _waitForCooldown(
    Duration duration,
    BenchmarkCancelToken cancelToken,
  ) async {
    if (duration <= Duration.zero) return;
    final cancelled = await Future.any<bool>([
      Future<void>.delayed(duration).then((_) => false),
      cancelToken.whenCancelled.then((_) => true),
    ]);
    if (cancelled) throw const BenchmarkCancelledException();
  }

  Future<bool> _isProcessAlive(int processId) async {
    if (processId <= 0) return false;
    if (processId == pid) return true;
    try {
      final result = await Process.run('tasklist', [
        '/FI',
        'PID eq $processId',
        '/FO',
        'CSV',
        '/NH',
      ]).timeout(const Duration(seconds: 3));
      if (result.exitCode != 0) return true;
      return RegExp(
        '(^|,)"?$processId"?(,|\$)',
        multiLine: true,
      ).hasMatch(result.stdout.toString());
    } catch (_) {
      return true;
    }
  }

  Future<int> _freeSpaceBytes(String driveRoot) async {
    final drive = driveRoot.substring(0, 1);
    try {
      final result = await Process.run('powershell', [
        '-NoProfile',
        '-ExecutionPolicy',
        'Bypass',
        '-Command',
        '(Get-PSDrive -Name "$drive" -PSProvider FileSystem).Free',
      ]).timeout(const Duration(seconds: 5));
      if (result.exitCode == 0) {
        return int.tryParse(result.stdout.toString().trim()) ?? 0;
      }
    } catch (_) {}
    return 0;
  }

  String? _driveRootForDisk(DiskInfo disk) {
    if (disk.driveLetters.isEmpty) return null;
    final letter = disk.driveLetters.first.trim();
    if (letter.isEmpty) return null;
    if (letter.length == 1) return '${letter.toUpperCase()}:\\';
    if (letter.endsWith(':')) return '${letter.toUpperCase()}\\';
    if (letter.endsWith('\\')) return letter;
    return '$letter\\';
  }

  double _adjustedRandomSpeed(List<BenchmarkSample> samples) {
    if (samples.isEmpty) return 0;
    final speeds = samples
        .map((sample) => sample.throughputMBps)
        .toList(growable: false);
    final average = speeds.reduce((a, b) => a + b) / speeds.length;
    final low = benchmarkPercentile(speeds, 0.10);
    final lastHalf = speeds.length > 2
        ? speeds.skip(speeds.length ~/ 2).reduce((a, b) => a + b) /
              (speeds.length - speeds.length ~/ 2)
        : average;
    return (average + lastHalf * 2 + low * 2) / 5;
  }
}

class _NativeBenchmarkResult {
  final int protocolVersion;
  final double averageMBps;
  final double lowMBps;
  final double stability;
  final int bytesProcessed;
  final double iops;
  final double readMBps;
  final double writeMBps;
  final BenchmarkLatency latency;
  final double cacheInflectionGB;
  final double cacheStableMBps;
  final BenchmarkSlcStatus cacheStatus;
  final double cacheConfidence;
  final int threadCount;
  final int readPercent;
  final List<BenchmarkSample> samples;

  const _NativeBenchmarkResult({
    required this.protocolVersion,
    required this.averageMBps,
    required this.lowMBps,
    required this.stability,
    required this.bytesProcessed,
    required this.iops,
    required this.readMBps,
    required this.writeMBps,
    required this.latency,
    required this.cacheInflectionGB,
    required this.cacheStableMBps,
    required this.cacheStatus,
    required this.cacheConfidence,
    required this.threadCount,
    required this.readPercent,
    required this.samples,
  });

  BenchmarkMeasurement toMeasurement(
    BenchmarkWorkload workload, {
    int? threadCount,
    int? readPercent,
  }) {
    return BenchmarkMeasurement(
      workload: workload,
      threadCount: threadCount ?? this.threadCount,
      readPercent: readPercent ?? this.readPercent,
      averageMBps: averageMBps,
      lowMBps: lowMBps,
      stability: stability,
      bytesProcessed: bytesProcessed,
      iops: iops,
      readMBps: readMBps,
      writeMBps: writeMBps,
      latency: latency,
      cacheInflectionGB: cacheInflectionGB,
      cacheStableMBps: cacheStableMBps,
      samples: samples,
    );
  }
}

class _MutableBenchmarkSeries {
  final BenchmarkWorkload workload;
  final int threadCount;
  final int readPercent;
  final List<BenchmarkSample> samples = [];
  _NativeBenchmarkResult? _result;

  _MutableBenchmarkSeries({
    required this.workload,
    required this.threadCount,
    required this.readPercent,
  });

  void complete(_NativeBenchmarkResult result) {
    _result = result;
  }

  BenchmarkSampleSeries snapshot() {
    final result = _result;
    return BenchmarkSampleSeries(
      workload: workload,
      threadCount: threadCount,
      readPercent: readPercent,
      averageMBps: result?.averageMBps ?? 0,
      iops: result?.iops ?? 0,
      readMBps: result?.readMBps ?? 0,
      writeMBps: result?.writeMBps ?? 0,
      latency: result?.latency ?? const BenchmarkLatency(),
      samples: List.unmodifiable(samples),
    );
  }
}

BenchmarkSlcStatus? _parseSlcStatus(String value) {
  for (final status in BenchmarkSlcStatus.values) {
    if (status.name == value) return status;
  }
  return null;
}

double? _nonNegativeDouble(String value) {
  final parsed = double.tryParse(value);
  if (parsed == null || !parsed.isFinite || parsed < 0) return null;
  return parsed;
}

int? _nonNegativeInt(String value) {
  final parsed = int.tryParse(value);
  if (parsed == null || parsed < 0) return null;
  return parsed;
}
