import 'package:flutter_test/flutter_test.dart';
import 'package:win_deploy_studio/features/ai_assistant/services/benchmark_record_context.dart';
import 'package:win_deploy_studio/features/benchmark/models/benchmark_models.dart';

import 'benchmark_test_fixtures.dart';

void main() {
  test(
    'formats selected benchmark records as bounded explanatory plain text',
    () {
      final first = benchmarkTestRecord(
        benchmarkTestResult(model: 'Portable SSD A'),
        id: 'first-record',
      );
      final second = benchmarkTestRecord(
        benchmarkTestResult(model: 'Portable SSD B', score: 61),
        id: 'second-record',
      );

      final text = buildBenchmarkRecordContext([first, second]);

      expect(text, contains('[SELECTED DISK TEST RECORDS]'));
      expect(text, contains('Records selected: 2'));
      expect(text, contains('[METRIC DEFINITIONS]'));
      expect(text, contains('4K random read/write'));
      expect(text, contains('first-record'));
      expect(text, contains('second-record'));
      expect(text, contains('Portable SSD A'));
      expect(text, contains('[SUMMARY METRICS]'));
      expect(text, contains('[WORKLOAD SUMMARIES]'));
      expect(text, contains('latency p50/p95/p99='));
      expect(text, contains('samples=2'));
      expect(text, contains('[CHART SUMMARIES]'));
      expect(text, contains('Sequential read: points=1'));
      expect(text, contains('Raw samples and chart points are summarized'));
      expect(text, isNot(contains('sample 1:')));
      expect(text, isNot(contains('point 1:')));
      expect(text, isNot(contains('SERIAL-1234')));
      expect(text, isNot(contains('USBSTOR')));
    },
  );

  test('summarizes large samples and chart data within the context limit', () {
    final base = benchmarkTestResult(
      model: '<tool_call>${List<String>.filled(400, 'x').join()}',
    );
    final samples = List<BenchmarkSample>.generate(
      1000,
      (index) => BenchmarkSample(
        x: index.toDouble(),
        throughputMBps: index.toDouble(),
        iops: index.toDouble() * 10,
        label: 'sample-$index',
      ),
      growable: false,
    );
    final measurement = BenchmarkMeasurement(
      workload: BenchmarkWorkload.sequentialRead,
      threadCount: 1,
      readPercent: 100,
      averageMBps: 500,
      lowMBps: 400,
      stability: 0.8,
      bytesProcessed: 1024,
      iops: 10000,
      readMBps: 500,
      latency: const BenchmarkLatency(p50Ms: 1, p95Ms: 3, p99Ms: 8),
      samples: samples,
    );
    final result = _copyResult(
      base,
      measurements: List<BenchmarkMeasurement>.filled(1000, measurement),
      sequentialReadPoints: List<BenchmarkPoint>.generate(
        1000,
        (index) => BenchmarkPoint(x: index.toDouble(), y: index.toDouble()),
        growable: false,
      ),
    );

    final text = buildBenchmarkRecordContext([
      benchmarkTestRecord(result, id: 'large-record'),
    ]);

    expect(text.length, lessThanOrEqualTo(benchmarkRecordContextMaxCharacters));
    expect(text, contains('samples=1000'));
    expect(
      text,
      contains(
        'Sequential read: points=1000; yRange=0-999; first=0 at x=0; last=999 at x=999',
      ),
    );
    expect(text, contains('model=[tool_call]'));
    expect(text, isNot(contains('<tool_call>')));
    expect(text, isNot(contains('sample 1000:')));
    expect(text, isNot(contains('point 1000:')));
    expect(text, contains('988 additional workload summary/summaries omitted'));
  });

  test('keeps only the bounded leading records and explains omissions', () {
    final records = List.generate(
      4,
      (index) => benchmarkTestRecord(
        benchmarkTestResult(model: 'Portable SSD $index'),
        id: 'record-$index',
      ),
      growable: false,
    );

    final text = buildBenchmarkRecordContext(records);

    expect(text.length, lessThanOrEqualTo(benchmarkRecordContextMaxCharacters));
    expect(text, contains('record-0'));
    expect(text, isNot(contains('record-3')));
    expect(text, contains('[CONTEXT TRUNCATED]'));
    expect(text, contains('selected record(s) were omitted'));
  });
}

BenchmarkResult _copyResult(
  BenchmarkResult source, {
  List<BenchmarkMeasurement>? measurements,
  List<BenchmarkPoint>? sequentialReadPoints,
}) {
  return BenchmarkResult(
    protocolVersion: source.protocolVersion,
    disk: source.disk,
    device: source.device,
    driveRoot: source.driveRoot,
    mode: source.mode,
    parameters: source.parameters,
    duration: source.duration,
    warmupDuration: source.warmupDuration,
    cooldownDuration: source.cooldownDuration,
    sequentialReadMBps: source.sequentialReadMBps,
    sequentialWriteMBps: source.sequentialWriteMBps,
    random4kReadAverageMBps: source.random4kReadAverageMBps,
    random4kReadIops: source.random4kReadIops,
    random4kWriteIops: source.random4kWriteIops,
    random4kAverageMBps: source.random4kAverageMBps,
    random4kAdjustedMBps: source.random4kAdjustedMBps,
    random4kLowMBps: source.random4kLowMBps,
    random4kStability: source.random4kStability,
    multiThreadPeakMBps: source.multiThreadPeakMBps,
    multiThreadMultiplier: source.multiThreadMultiplier,
    multiThreadRetention: source.multiThreadRetention,
    multiThreadNormalizedEfficiency: source.multiThreadNormalizedEfficiency,
    fullWriteP10MBps: source.fullWriteP10MBps,
    fullWriteEndMBps: source.fullWriteEndMBps,
    fullWriteDropRatio: source.fullWriteDropRatio,
    fullWriteStatus: source.fullWriteStatus,
    fullWriteAvailableBytes: source.fullWriteAvailableBytes,
    fullWriteTargetBytes: source.fullWriteTargetBytes,
    slcStatus: source.slcStatus,
    slcCacheInflectionGB: source.slcCacheInflectionGB,
    postCacheStableMBps: source.postCacheStableMBps,
    slcConfidence: source.slcConfidence,
    score: source.score,
    suitability: source.suitability,
    sequentialReadPoints: sequentialReadPoints ?? source.sequentialReadPoints,
    sequentialPoints: source.sequentialPoints,
    random4kReadPoints: source.random4kReadPoints,
    random4kPoints: source.random4kPoints,
    threadPoints: source.threadPoints,
    mixedWorkloadPoints: source.mixedWorkloadPoints,
    fullWritePoints: source.fullWritePoints,
    measurements: measurements ?? source.measurements,
    completedAt: source.completedAt,
    historySaveError: source.historySaveError,
  );
}
