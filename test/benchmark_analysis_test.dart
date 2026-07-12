import 'package:flutter_test/flutter_test.dart';
import 'package:win_deploy_studio/features/benchmark/models/benchmark_models.dart';
import 'package:win_deploy_studio/features/benchmark/services/benchmark_analysis.dart';

void main() {
  test('Full is explicitly a selected-volume available-space workload', () {
    final parameters = BenchmarkRunParameters.forMode(BenchmarkMode.fullWrite);

    expect(
      parameters.fullWriteScope,
      BenchmarkFullWriteScope.selectedVolumeAvailableSpace,
    );
    expect(parameters.fullWriteReserveBytes, greaterThan(0));
    expect(parameters.fullWriteMinimumBytes, greaterThan(0));
    expect(parameters.fullWriteCooldownMs, greaterThanOrEqualTo(15000));
  });

  group('thread analysis', () {
    test('separates multiplier, retention, and normalized efficiency', () {
      final metrics = analyzeThreadCurve({1: 50, 4: 120, 8: 96});

      expect(metrics.peakMBps, 120);
      expect(metrics.peakThreadCount, 4);
      expect(metrics.multiplier, closeTo(2.4, 0.0001));
      expect(metrics.retention, closeTo(0.8, 0.0001));
      expect(metrics.normalizedEfficiency, closeTo(0.6, 0.0001));
      expect(metrics.isComplete, isTrue);
    });

    test('does not invent scaling without a one-thread baseline', () {
      final metrics = analyzeThreadCurve({4: 100, 8: 90});

      expect(metrics.peakMBps, 100);
      expect(metrics.multiplier, 0);
      expect(metrics.retention, 0);
      expect(metrics.normalizedEfficiency, 0);
      expect(metrics.isComplete, isFalse);
    });
  });

  group('full-write statistics', () {
    test('uses interpolated P10 instead of reporting a minimum', () {
      final samples = List.generate(
        11,
        (index) =>
            BenchmarkSample(x: index + 1, throughputMBps: 100 + index * 10),
      );

      expect(fullWriteP10(samples), 110);
      expect(fullWriteP10(samples), isNot(100));
    });

    test('compares stable initial and tail windows for drop ratio', () {
      final samples = <BenchmarkSample>[
        ..._samples(List.filled(8, 500), stepGB: 0.25),
        ..._samples(List.filled(8, 125), startGB: 2.25, stepGB: 0.25),
      ];

      expect(fullWriteDropRatio(samples), closeTo(0.75, 0.01));
    });
  });

  group('SLC four-state analysis', () {
    test('reports notRun when the long write did not execute', () {
      final analysis = analyzeSlcSamples(const [], wasRun: false);
      expect(analysis.status, BenchmarkSlcStatus.notRun);
    });

    test('reports insufficientRange for a short write', () {
      final analysis = analyzeSlcSamples(
        _samples(List.filled(8, 500), stepGB: 0.25),
        wasRun: true,
      );

      expect(analysis.status, BenchmarkSlcStatus.insufficientRange);
      expect(analysis.confidence, lessThan(0.5));
    });

    test('reports noInflection after a long stable write', () {
      final speeds = List.generate(28, (index) => 500 + (index % 3) * 4.0);
      final analysis = analyzeSlcSamples(
        _samples(speeds, stepGB: 0.25),
        wasRun: true,
      );

      expect(analysis.status, BenchmarkSlcStatus.noInflection);
      expect(analysis.confidence, greaterThanOrEqualTo(0.55));
      expect(analysis.inflectionGB, 0);
    });

    test('detects a sustained inflection with confidence', () {
      final analysis = analyzeSlcSamples(
        _samples([
          ...List.filled(6, 520.0),
          ...List.filled(22, 135.0),
        ], stepGB: 0.25),
        wasRun: true,
      );

      expect(analysis.status, BenchmarkSlcStatus.detected);
      expect(analysis.inflectionGB, closeTo(1.75, 0.01));
      expect(analysis.stableMBps, closeTo(135, 0.01));
      expect(analysis.confidence, greaterThanOrEqualTo(0.55));
    });
  });

  group('rating', () {
    test('awards excellent only with scenarios and healthy tail latency', () {
      final rating = calculateBenchmarkRating(_strongRatingInput());

      expect(rating.hasRequiredMeasurements, isTrue);
      expect(rating.score, greaterThan(82));
      expect(rating.suitability, BenchmarkSuitability.excellent);
    });

    test('tail-latency gate prevents a high average from rating highly', () {
      final rating = calculateBenchmarkRating(
        _strongRatingInput(randomWriteP99Ms: 320),
      );

      expect(rating.score, greaterThan(65));
      expect(
        rating.suitability.index,
        greaterThanOrEqualTo(BenchmarkSuitability.limited.index),
      );
    });

    test('critical 4K gate cannot be bypassed by other fast metrics', () {
      final rating = calculateBenchmarkRating(
        _strongRatingInput(adjusted4kMBps: 1, low4kMBps: 0.4),
      );

      expect(rating.suitability, BenchmarkSuitability.limited);
    });

    test('missing scenarios are unmeasured and score is capped', () {
      final rating = calculateBenchmarkRating(
        _strongRatingInput(scenarios: _strongScenarios().take(4).toList()),
      );

      expect(rating.hasRequiredMeasurements, isFalse);
      expect(rating.suitability, BenchmarkSuitability.unmeasured);
      expect(rating.score, lessThanOrEqualTo(49));
    });

    test('zero latency is treated as missing, not as perfect latency', () {
      final rating = calculateBenchmarkRating(
        _strongRatingInput(randomWriteP99Ms: 0),
      );

      expect(rating.hasRequiredMeasurements, isFalse);
      expect(rating.suitability, BenchmarkSuitability.unmeasured);
    });
  });
}

List<BenchmarkSample> _samples(
  List<double> speeds, {
  double startGB = 0.25,
  double stepGB = 0.25,
}) {
  return List.generate(
    speeds.length,
    (index) => BenchmarkSample(
      x: startGB + index * stepGB,
      throughputMBps: speeds[index],
    ),
  );
}

BenchmarkRatingInput _strongRatingInput({
  double adjusted4kMBps = 35,
  double low4kMBps = 18,
  double randomWriteP99Ms = 8,
  List<BenchmarkScenarioRatingSample>? scenarios,
}) {
  return BenchmarkRatingInput(
    sequentialWriteMBps: 500,
    sequentialReadMBps: 700,
    adjusted4kMBps: adjusted4kMBps,
    random4kReadIops: 18000,
    low4kMBps: low4kMBps,
    stability: 0.95,
    randomReadP99Ms: 6,
    randomWriteP99Ms: randomWriteP99Ms,
    multiThreadMultiplier: 3,
    multiThreadRetention: 0.9,
    multiThreadNormalizedEfficiency: 0.65,
    scenarios: scenarios ?? _strongScenarios(),
  );
}

List<BenchmarkScenarioRatingSample> _strongScenarios() => const [
  BenchmarkScenarioRatingSample(
    workload: BenchmarkWorkload.startup,
    throughputMBps: 40,
    p99Ms: 15,
  ),
  BenchmarkScenarioRatingSample(
    workload: BenchmarkWorkload.browser,
    throughputMBps: 30,
    p99Ms: 15,
  ),
  BenchmarkScenarioRatingSample(
    workload: BenchmarkWorkload.windowsUpdate,
    throughputMBps: 70,
    p99Ms: 20,
  ),
  BenchmarkScenarioRatingSample(
    workload: BenchmarkWorkload.softwareInstall,
    throughputMBps: 100,
    p99Ms: 20,
  ),
  BenchmarkScenarioRatingSample(
    workload: BenchmarkWorkload.multitasking,
    throughputMBps: 60,
    p99Ms: 18,
  ),
];
