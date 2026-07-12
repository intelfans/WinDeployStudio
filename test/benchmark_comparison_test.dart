import 'package:flutter_test/flutter_test.dart';
import 'package:win_deploy_studio/features/benchmark/models/benchmark_models.dart';
import 'package:win_deploy_studio/features/benchmark_history/models/benchmark_history_models.dart';
import 'package:win_deploy_studio/features/benchmark_history/services/benchmark_history_service.dart';

import 'benchmark_test_fixtures.dart';

void main() {
  final service = BenchmarkHistoryService();

  test('comparison requires matching protocol, mode, and parameters', () {
    final baseline = benchmarkTestRecord(
      benchmarkTestResult(protocolVersion: 2),
      id: 'baseline',
    );
    final differentProtocol = benchmarkTestRecord(
      benchmarkTestResult(protocolVersion: benchmarkProtocolVersion),
      id: 'protocol',
    );
    final differentMode = benchmarkTestRecord(
      benchmarkTestResult(mode: BenchmarkMode.quick),
      id: 'mode',
    );
    final changedParametersJson = BenchmarkRunParameters.forMode(
      BenchmarkMode.standard,
    ).toJson()..['threadSeconds'] = 99;
    final differentParameters = benchmarkTestRecord(
      benchmarkTestResult(
        protocolVersion: 2,
        parameters: BenchmarkRunParameters.fromJson(
          changedParametersJson,
          BenchmarkMode.standard,
        ),
      ),
      id: 'parameters',
    );

    expect(
      service.compatibilityFor(baseline, differentProtocol).incompatibility,
      BenchmarkComparisonIncompatibility.differentProtocol,
    );
    expect(
      service.compatibilityFor(baseline, differentMode).incompatibility,
      BenchmarkComparisonIncompatibility.differentProtocol,
    );
    expect(
      service.compatibilityFor(baseline, differentParameters).incompatibility,
      BenchmarkComparisonIncompatibility.differentParameters,
    );
    expect(
      () => service.compare(baseline, differentProtocol),
      throwsA(
        isA<BenchmarkComparisonException>().having(
          (error) => error.reason,
          'reason',
          BenchmarkComparisonIncompatibility.differentProtocol,
        ),
      ),
    );
  });

  test('mode mismatch is reported after protocol compatibility', () {
    final baseline = benchmarkTestRecord(benchmarkTestResult(), id: 'baseline');
    final candidate = benchmarkTestRecord(
      benchmarkTestResult(mode: BenchmarkMode.quick),
      id: 'candidate',
    );

    expect(
      service.compatibilityFor(baseline, candidate).incompatibility,
      BenchmarkComparisonIncompatibility.differentMode,
    );
  });

  test('missing measurements remain N/A instead of becoming zero', () {
    final baselineMeasurements = benchmarkTestMeasurements()
        .where(
          (measurement) =>
              measurement.workload != BenchmarkWorkload.random4kRead,
        )
        .toList();
    final comparison = service.compare(
      benchmarkTestRecord(
        benchmarkTestResult(measurements: baselineMeasurements),
        id: 'baseline',
      ),
      benchmarkTestRecord(benchmarkTestResult(score: 85), id: 'candidate'),
    );
    final latency = comparison.metrics.firstWhere(
      (metric) => metric.key == 'randomReadP99',
    );

    expect(latency.baseline, isNull);
    expect(latency.candidate, isNotNull);
    expect(latency.percentDelta, isNull);
    expect(latency.isAvailable, isFalse);
  });

  test('thread chart contains the complete configured curve', () {
    final result = benchmarkTestResult();

    final samples = result.chartSamplesFor(
      BenchmarkWorkload.random4kMultiThread,
    );

    expect(samples.map((sample) => sample.x), [1, 4, 8]);
    expect(samples.map((sample) => sample.throughputMBps), [50, 105, 90]);
  });

  test('result decoding accepts only explicitly supported protocols', () {
    final json = benchmarkTestResult().toJson();

    expect(BenchmarkResult.fromJson(json).protocolVersion, 3);
    expect(
      () => BenchmarkResult.fromJson(Map.of(json)..remove('protocolVersion')),
      throwsFormatException,
    );
    expect(
      () => BenchmarkResult.fromJson(
        Map<String, dynamic>.from(json)..['protocolVersion'] = 4,
      ),
      throwsFormatException,
    );
    expect(
      () => BenchmarkResult.fromJson(
        Map<String, dynamic>.from(json)..remove('parameters'),
      ),
      throwsFormatException,
    );
    expect(
      BenchmarkResult.fromJson(
        Map<String, dynamic>.from(json)..['protocolVersion'] = 2,
      ).protocolVersion,
      2,
    );
  });

  test('insufficient Full space is persisted as an explicit non-run', () {
    final json = benchmarkTestResult(mode: BenchmarkMode.fullWrite).toJson()
      ..['fullWriteStatus'] = BenchmarkFullWriteStatus.insufficientSpace.name
      ..['slcStatus'] = BenchmarkSlcStatus.notRun.name
      ..['fullWriteAvailableBytes'] = 900 * 1024 * 1024
      ..['fullWriteTargetBytes'] = 0;

    final restored = BenchmarkResult.fromJson(json);

    expect(
      restored.fullWriteStatus,
      BenchmarkFullWriteStatus.insufficientSpace,
    );
    expect(restored.slcStatus, BenchmarkSlcStatus.notRun);
    expect(restored.fullWriteTargetBytes, 0);
  });
}
