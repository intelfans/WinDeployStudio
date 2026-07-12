import 'dart:math';

import '../models/benchmark_models.dart';

class BenchmarkThreadMetrics {
  final double peakMBps;
  final int peakThreadCount;
  final double multiplier;
  final double retention;
  final double normalizedEfficiency;
  final bool isComplete;

  const BenchmarkThreadMetrics({
    this.peakMBps = 0,
    this.peakThreadCount = 0,
    this.multiplier = 0,
    this.retention = 0,
    this.normalizedEfficiency = 0,
    this.isComplete = false,
  });
}

BenchmarkThreadMetrics analyzeThreadCurve(Map<int, double> throughputByThread) {
  final entries =
      throughputByThread.entries
          .where(
            (entry) => entry.key > 0 && entry.value.isFinite && entry.value > 0,
          )
          .toList()
        ..sort((left, right) => left.key.compareTo(right.key));
  if (entries.isEmpty) return const BenchmarkThreadMetrics();

  final single = entries.where((entry) => entry.key == 1).firstOrNull;
  final peak = entries.reduce(
    (left, right) => left.value >= right.value ? left : right,
  );
  final highestThread = entries.last;
  if (single == null || single.value <= 0 || peak.value <= 0) {
    return BenchmarkThreadMetrics(
      peakMBps: peak.value,
      peakThreadCount: peak.key,
    );
  }

  final multiplier = peak.value / single.value;
  return BenchmarkThreadMetrics(
    peakMBps: peak.value,
    peakThreadCount: peak.key,
    multiplier: multiplier,
    retention: (highestThread.value / peak.value).clamp(0.0, 1.0),
    normalizedEfficiency: (multiplier / peak.key).clamp(0.0, 1.0),
    isComplete: entries.length >= 2,
  );
}

double benchmarkPercentile(Iterable<double> values, double percentile) {
  final sorted = values.where((value) => value.isFinite).toList()..sort();
  if (sorted.isEmpty) return 0;
  final bounded = percentile.clamp(0.0, 1.0);
  final position = (sorted.length - 1) * bounded;
  final lower = position.floor();
  final upper = position.ceil();
  if (lower == upper) return sorted[lower];
  final fraction = position - lower;
  return sorted[lower] + (sorted[upper] - sorted[lower]) * fraction;
}

class BenchmarkSlcAnalysis {
  final BenchmarkSlcStatus status;
  final double inflectionGB;
  final double stableMBps;
  final double confidence;
  final double baselineMBps;

  const BenchmarkSlcAnalysis({
    required this.status,
    this.inflectionGB = 0,
    this.stableMBps = 0,
    this.confidence = 0,
    this.baselineMBps = 0,
  });
}

BenchmarkSlcAnalysis analyzeSlcSamples(
  Iterable<BenchmarkSample> source, {
  required bool wasRun,
  double minimumRangeGB = 4,
  int minimumSamples = 16,
}) {
  if (!wasRun) {
    return const BenchmarkSlcAnalysis(status: BenchmarkSlcStatus.notRun);
  }
  final samples =
      source
          .where(
            (sample) =>
                sample.x.isFinite &&
                sample.x > 0 &&
                sample.throughputMBps.isFinite &&
                sample.throughputMBps > 0,
          )
          .toList()
        ..sort((left, right) => left.x.compareTo(right.x));
  final coveredRange = samples.isEmpty ? 0.0 : samples.last.x;
  if (samples.length < minimumSamples || coveredRange < minimumRangeGB) {
    final rangeEvidence = minimumRangeGB <= 0
        ? 0.0
        : (coveredRange / minimumRangeGB).clamp(0.0, 1.0);
    final sampleEvidence = minimumSamples <= 0
        ? 0.0
        : (samples.length / minimumSamples).clamp(0.0, 1.0);
    return BenchmarkSlcAnalysis(
      status: BenchmarkSlcStatus.insufficientRange,
      confidence: min(rangeEvidence, sampleEvidence) * 0.45,
    );
  }

  final speeds = samples
      .map((sample) => sample.throughputMBps)
      .toList(growable: false);
  final baselineCount = min(6, max(4, samples.length ~/ 8));
  final baseline = benchmarkPercentile(speeds.take(baselineCount), 0.5);
  if (baseline <= 0) {
    return const BenchmarkSlcAnalysis(
      status: BenchmarkSlcStatus.insufficientRange,
    );
  }

  const postWindowSize = 6;
  for (
    var index = baselineCount;
    index + postWindowSize <= samples.length;
    index++
  ) {
    final postWindow = speeds.sublist(index, index + postWindowSize);
    final postMedian = benchmarkPercentile(postWindow, 0.5);
    final drop = baseline - postMedian;
    final dropRatio = drop / baseline;
    final sustainedLow = postWindow
        .where((speed) => speed <= baseline * 0.72)
        .length;
    if (drop < max(25.0, baseline * 0.25) ||
        dropRatio < 0.28 ||
        speeds[index] > baseline * 0.72 ||
        sustainedLow < postWindowSize - 1) {
      continue;
    }

    final postCache = speeds.skip(index + 1).toList(growable: false);
    final stable = benchmarkPercentile(postCache, 0.5);
    final deviations = postCache.map((speed) => (speed - stable).abs());
    final relativeMad = stable <= 0
        ? 1.0
        : benchmarkPercentile(deviations, 0.5) / stable;
    final dropEvidence = ((dropRatio - 0.25) / 0.40).clamp(0.0, 1.0);
    final persistenceEvidence = (postCache.length / 16).clamp(0.0, 1.0);
    final stabilityEvidence = (1 - relativeMad * 2).clamp(0.0, 1.0);
    final confidence =
        dropEvidence * 0.55 +
        persistenceEvidence * 0.25 +
        stabilityEvidence * 0.20;
    if (confidence < 0.55) continue;

    return BenchmarkSlcAnalysis(
      status: BenchmarkSlcStatus.detected,
      inflectionGB: samples[index].x,
      stableMBps: stable,
      confidence: confidence.clamp(0.0, 1.0),
      baselineMBps: baseline,
    );
  }

  final baselineDeviations = speeds
      .take(baselineCount)
      .map((speed) => (speed - baseline).abs());
  final baselineMad = benchmarkPercentile(baselineDeviations, 0.5);
  final stabilityEvidence = baseline <= 0
      ? 0.0
      : (1 - (baselineMad / baseline) * 2).clamp(0.0, 1.0);
  final coverageEvidence = (coveredRange / 16).clamp(0.25, 1.0);
  return BenchmarkSlcAnalysis(
    status: BenchmarkSlcStatus.noInflection,
    confidence: (0.55 + stabilityEvidence * 0.25 + coverageEvidence * 0.20)
        .clamp(0.0, 1.0),
    baselineMBps: baseline,
  );
}

double fullWriteP10(Iterable<BenchmarkSample> samples) =>
    benchmarkPercentile(samples.map((sample) => sample.throughputMBps), 0.10);

double fullWriteDropRatio(Iterable<BenchmarkSample> source) {
  final samples = source
      .where((sample) => sample.throughputMBps > 0)
      .toList(growable: false);
  if (samples.length < 4) return 0;
  final window = min(8, max(2, samples.length ~/ 4));
  final initial = benchmarkPercentile(
    samples.take(window).map((sample) => sample.throughputMBps),
    0.5,
  );
  final tail = benchmarkPercentile(
    samples
        .skip(samples.length - window)
        .map((sample) => sample.throughputMBps),
    0.5,
  );
  return initial <= 0 ? 0 : ((initial - tail) / initial).clamp(0.0, 1.0);
}

class BenchmarkScenarioRatingSample {
  final BenchmarkWorkload workload;
  final double throughputMBps;
  final double p99Ms;

  const BenchmarkScenarioRatingSample({
    required this.workload,
    required this.throughputMBps,
    required this.p99Ms,
  });
}

class BenchmarkRatingInput {
  final double? sequentialWriteMBps;
  final double? sequentialReadMBps;
  final double? adjusted4kMBps;
  final double? random4kReadIops;
  final double? low4kMBps;
  final double? stability;
  final double? randomReadP99Ms;
  final double? randomWriteP99Ms;
  final double? multiThreadMultiplier;
  final double? multiThreadRetention;
  final double? multiThreadNormalizedEfficiency;
  final List<BenchmarkScenarioRatingSample> scenarios;
  final double? fullWriteDropRatio;

  const BenchmarkRatingInput({
    this.sequentialWriteMBps,
    this.sequentialReadMBps,
    this.adjusted4kMBps,
    this.random4kReadIops,
    this.low4kMBps,
    this.stability,
    this.randomReadP99Ms,
    this.randomWriteP99Ms,
    this.multiThreadMultiplier,
    this.multiThreadRetention,
    this.multiThreadNormalizedEfficiency,
    this.scenarios = const [],
    this.fullWriteDropRatio,
  });
}

class BenchmarkRating {
  final double score;
  final BenchmarkSuitability suitability;
  final bool hasRequiredMeasurements;

  const BenchmarkRating({
    required this.score,
    required this.suitability,
    required this.hasRequiredMeasurements,
  });
}

BenchmarkRating calculateBenchmarkRating(BenchmarkRatingInput input) {
  final expectedScenarios = MixedWorkloadScenario.values
      .map((scenario) => scenario.workload)
      .toSet();
  final measuredScenarios = input.scenarios
      .where(
        (scenario) =>
            scenario.throughputMBps.isFinite &&
            scenario.throughputMBps > 0 &&
            scenario.p99Ms.isFinite &&
            scenario.p99Ms > 0,
      )
      .toList(growable: false);
  final positiveMeasurements = <double?>[
    input.sequentialWriteMBps,
    input.sequentialReadMBps,
    input.adjusted4kMBps,
    input.random4kReadIops,
    input.low4kMBps,
    input.randomReadP99Ms,
    input.randomWriteP99Ms,
    input.multiThreadMultiplier,
    input.multiThreadRetention,
    input.multiThreadNormalizedEfficiency,
  ];
  final hasRequiredMeasurements =
      positiveMeasurements.every(
        (value) => value != null && value.isFinite && value > 0,
      ) &&
      input.stability != null &&
      input.stability!.isFinite &&
      measuredScenarios
          .map((scenario) => scenario.workload)
          .toSet()
          .containsAll(expectedScenarios);

  final scenarioTargets = <BenchmarkWorkload, double>{
    BenchmarkWorkload.startup: 35,
    BenchmarkWorkload.browser: 25,
    BenchmarkWorkload.windowsUpdate: 60,
    BenchmarkWorkload.softwareInstall: 90,
    BenchmarkWorkload.multitasking: 50,
  };
  final scenarioPerformance = expectedScenarios.isEmpty
      ? 0.0
      : expectedScenarios
                .map((workload) {
                  final scenario = measuredScenarios
                      .where((item) => item.workload == workload)
                      .firstOrNull;
                  if (scenario == null) return 0.0;
                  return (scenario.throughputMBps / scenarioTargets[workload]!)
                      .clamp(0.0, 1.0);
                })
                .reduce((left, right) => left + right) /
            expectedScenarios.length;
  final scenarioLatency = expectedScenarios.isEmpty
      ? 0.0
      : expectedScenarios
                .map((workload) {
                  final scenario = measuredScenarios
                      .where((item) => item.workload == workload)
                      .firstOrNull;
                  return _latencyQuality(
                    scenario?.p99Ms,
                    goodMs: 25,
                    badMs: 250,
                  );
                })
                .reduce((left, right) => left + right) /
            expectedScenarios.length;
  final randomLatency =
      (_latencyQuality(input.randomReadP99Ms, goodMs: 8, badMs: 120) +
          _latencyQuality(input.randomWriteP99Ms, goodMs: 12, badMs: 160)) /
      2;

  var score =
      _ratio(input.adjusted4kMBps, 25) * 22 +
      _ratio(input.low4kMBps, 12) * 10 +
      _ratio(input.random4kReadIops, 12000) * 6 +
      _ratio(input.sequentialWriteMBps, 250) * 6 +
      _ratio(input.sequentialReadMBps, 400) * 4 +
      (input.stability ?? 0).clamp(0.0, 1.0) * 7 +
      _ratio(input.multiThreadMultiplier, 3) * 5 +
      (input.multiThreadRetention ?? 0).clamp(0.0, 1.0) * 4 +
      _ratio(input.multiThreadNormalizedEfficiency, 0.65) * 4 +
      scenarioPerformance * 16 +
      randomLatency * 8 +
      scenarioLatency * 8;
  final fullDrop = input.fullWriteDropRatio;
  if (fullDrop != null && fullDrop > 0.55) {
    score -= ((fullDrop - 0.55) / 0.35).clamp(0.0, 1.0) * 10;
  }
  score = score.clamp(0.0, 100.0);

  if (!hasRequiredMeasurements) {
    return BenchmarkRating(
      score: min(score, 49),
      suitability: BenchmarkSuitability.unmeasured,
      hasRequiredMeasurements: false,
    );
  }

  final adjusted = input.adjusted4kMBps!;
  final low = input.low4kMBps!;
  final sequentialWrite = input.sequentialWriteMBps!;
  final randomTail = max(input.randomReadP99Ms!, input.randomWriteP99Ms!);
  final scenarioTail = measuredScenarios
      .map((scenario) => scenario.p99Ms)
      .reduce(max);
  final retention = input.multiThreadRetention!;
  final suitability = switch (score) {
    >= 82
        when adjusted >= 15 &&
            low >= 8 &&
            sequentialWrite >= 120 &&
            randomTail <= 25 &&
            scenarioTail <= 80 &&
            retention >= 0.75 =>
      BenchmarkSuitability.excellent,
    >= 65
        when adjusted >= 7 &&
            low >= 3 &&
            sequentialWrite >= 60 &&
            randomTail <= 80 &&
            scenarioTail <= 200 =>
      BenchmarkSuitability.good,
    >= 42
        when adjusted >= 2 &&
            low >= 1 &&
            randomTail <= 250 &&
            scenarioTail <= 500 =>
      BenchmarkSuitability.usable,
    >= 22 when adjusted >= 0.6 && low >= 0.25 => BenchmarkSuitability.limited,
    _ => BenchmarkSuitability.notRecommended,
  };
  return BenchmarkRating(
    score: score,
    suitability: suitability,
    hasRequiredMeasurements: true,
  );
}

double _ratio(double? value, double target) {
  if (value == null || !value.isFinite || target <= 0) return 0;
  return (value / target).clamp(0.0, 1.0);
}

double _latencyQuality(
  double? value, {
  required double goodMs,
  required double badMs,
}) {
  if (value == null || !value.isFinite || value <= 0) return 0;
  if (value <= goodMs) return 1;
  if (value >= badMs) return 0;
  return (badMs - value) / (badMs - goodMs);
}
