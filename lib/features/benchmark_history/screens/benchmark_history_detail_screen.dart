import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/localization/strings.dart';
import '../../benchmark/models/benchmark_models.dart';
import '../benchmark_history_copy.dart';
import '../models/benchmark_history_models.dart';
import '../widgets/benchmark_curve_chart.dart';
import '../widgets/benchmark_workload_chart.dart';

class BenchmarkHistoryDetailScreen extends StatelessWidget {
  final BenchmarkHistoryRecord record;

  const BenchmarkHistoryDetailScreen({super.key, required this.record});

  @override
  Widget build(BuildContext context) {
    final result = record.result;
    return Scaffold(
      appBar: AppBar(
        title: Text(tr(context, BenchmarkHistoryKeys.resultDetails)),
      ),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          _Section(
            title: tr(context, BenchmarkHistoryKeys.deviceIdentity),
            child: Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                _Value(
                  label: tr(context, BenchmarkHistoryKeys.model),
                  value: _available(context, result.device.model),
                ),
                _Value(
                  label: tr(context, BenchmarkHistoryKeys.serialNumber),
                  value: _available(context, result.device.serialNumber),
                ),
                _Value(
                  label: tr(context, BenchmarkHistoryKeys.uniqueId),
                  value: _available(context, result.device.uniqueId),
                ),
                _Value(
                  label: tr(context, BenchmarkHistoryKeys.vidPid),
                  value: _vidPid(result.device),
                ),
                _Value(
                  label: tr(context, BenchmarkHistoryKeys.bus),
                  value: _available(context, result.device.busType),
                ),
                _Value(
                  label: tr(context, BenchmarkHistoryKeys.capacity),
                  value: result.disk.sizeFormatted,
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _Section(
            title: tr(context, BenchmarkHistoryKeys.resultDetails),
            child: Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                _Value(
                  label: tr(context, BenchmarkHistoryKeys.completed),
                  value: DateFormat.yMd().add_Hms().format(result.completedAt),
                ),
                _Value(
                  label: tr(context, BenchmarkHistoryKeys.mode),
                  value: tr(context, result.mode.titleKey),
                ),
                _Value(
                  label: tr(context, BenchmarkHistoryKeys.duration),
                  value: result.durationText,
                ),
                _Value(
                  label: tr(context, BenchmarkHistoryKeys.score),
                  value: result.score.toStringAsFixed(1),
                ),
                _Value(
                  label: tr(context, BenchmarkHistoryKeys.sequentialRead),
                  value: _speed(result.sequentialReadMBps),
                ),
                _Value(
                  label: tr(context, BenchmarkHistoryKeys.sequentialWrite),
                  value: _speed(result.sequentialWriteMBps),
                ),
                _Value(
                  label: tr(context, BenchmarkHistoryKeys.randomRead),
                  value: _iops(result.random4kReadIops),
                ),
                _Value(
                  label: tr(context, BenchmarkHistoryKeys.randomWrite),
                  value: _iops(result.random4kWriteIops),
                ),
                _Value(
                  label: tr(context, BenchmarkHistoryKeys.slcInflection),
                  value: _slcStatus(context, result),
                ),
                _Value(
                  label: tr(context, BenchmarkHistoryKeys.postCacheStable),
                  value: result.postCacheStableMBps > 0
                      ? _speed(result.postCacheStableMBps)
                      : tr(context, BenchmarkHistoryKeys.unknown),
                ),
                _Value(
                  label: tr(context, BenchmarkHistoryKeys.multiThreadScale),
                  value: '${result.multiThreadMultiplier.toStringAsFixed(2)}x',
                ),
                _Value(
                  label: _threadLabel(context, 'retention'),
                  value:
                      '${(result.multiThreadRetention * 100).toStringAsFixed(0)}%',
                ),
                _Value(
                  label: _threadLabel(context, 'efficiency'),
                  value:
                      '${(result.multiThreadNormalizedEfficiency * 100).toStringAsFixed(0)}%',
                ),
                _Value(
                  label: 'Full P10',
                  value:
                      result.fullWriteStatus ==
                          BenchmarkFullWriteStatus.completed
                      ? _speed(result.fullWriteP10MBps)
                      : 'N/A',
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _Section(
            title: tr(context, BenchmarkHistoryKeys.comparisonCurves),
            child: BenchmarkWorkloadChart(
              primarySeries: result.sampleSeries,
              primarySlcMarkerGB:
                  result.slcStatus == BenchmarkSlcStatus.detected
                  ? result.slcCacheInflectionGB
                  : 0,
            ),
          ),
          const SizedBox(height: 16),
          _Section(
            title: tr(context, BenchmarkHistoryKeys.measurements),
            padding: EdgeInsets.zero,
            child: result.measurements.isEmpty
                ? Padding(
                    padding: const EdgeInsets.all(20),
                    child: Text(tr(context, BenchmarkHistoryKeys.noSamples)),
                  )
                : Column(
                    children: [
                      for (
                        var index = 0;
                        index < result.measurements.length;
                        index++
                      )
                        _MeasurementTile(
                          measurement: result.measurements[index],
                          initiallyExpanded: index == 0,
                        ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

class _MeasurementTile extends StatelessWidget {
  final BenchmarkMeasurement measurement;
  final bool initiallyExpanded;

  const _MeasurementTile({
    required this.measurement,
    required this.initiallyExpanded,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return ExpansionTile(
      initiallyExpanded: initiallyExpanded,
      title: Text(
        _workloadTitle(context, measurement),
        style: const TextStyle(fontWeight: FontWeight.w700),
      ),
      subtitle: Text(
        '${_speed(measurement.averageMBps)}  |  '
        '${_iops(measurement.iops)}  |  '
        '${tr(context, BenchmarkHistoryKeys.latencyP99)}: '
        '${measurement.latency.p99Ms.toStringAsFixed(3)} ms',
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      childrenPadding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      children: [
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            _Value(
              label: tr(context, BenchmarkHistoryKeys.throughput),
              value: _speed(measurement.averageMBps),
            ),
            _Value(
              label: tr(context, BenchmarkHistoryKeys.iops),
              value: _iops(measurement.iops),
            ),
            _Value(
              label: tr(context, BenchmarkHistoryKeys.latencyP50),
              value: '${measurement.latency.p50Ms.toStringAsFixed(3)} ms',
            ),
            _Value(
              label: tr(context, BenchmarkHistoryKeys.latencyP95),
              value: '${measurement.latency.p95Ms.toStringAsFixed(3)} ms',
            ),
            _Value(
              label: tr(context, BenchmarkHistoryKeys.latencyP99),
              value: '${measurement.latency.p99Ms.toStringAsFixed(3)} ms',
            ),
          ],
        ),
        const SizedBox(height: 18),
        DecoratedBox(
          decoration: BoxDecoration(
            color: colors.surfaceContainerLowest,
            border: Border.all(color: colors.outlineVariant),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: BenchmarkCurveChart(
              primary: measurement.samples,
              primaryMarkerX:
                  measurement.workload == BenchmarkWorkload.fullSequentialWrite
                  ? measurement.cacheInflectionGB
                  : 0,
              xAxis:
                  measurement.workload == BenchmarkWorkload.fullSequentialWrite
                  ? BenchmarkCurveXAxis.gigabytes
                  : BenchmarkCurveXAxis.seconds,
            ),
          ),
        ),
      ],
    );
  }
}

class _Section extends StatelessWidget {
  final String title;
  final Widget child;
  final EdgeInsetsGeometry padding;

  const _Section({
    required this.title,
    required this.child,
    this.padding = const EdgeInsets.all(20),
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        border: Border.all(color: colors.outlineVariant),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
            child: Text(
              title,
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
            ),
          ),
          Padding(padding: padding, child: child),
        ],
      ),
    );
  }
}

class _Value extends StatelessWidget {
  final String label;
  final String value;

  const _Value({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 180, maxWidth: 340),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: Theme.of(
              context,
            ).textTheme.labelMedium?.copyWith(color: colors.onSurfaceVariant),
          ),
          const SizedBox(height: 4),
          SelectableText(
            value,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

String _available(BuildContext context, String value) {
  final normalized = value.trim();
  return normalized.isEmpty || normalized.toUpperCase() == 'N/A'
      ? tr(context, BenchmarkHistoryKeys.unknown)
      : normalized;
}

String _workloadTitle(BuildContext context, BenchmarkMeasurement measurement) {
  final title = tr(
    context,
    BenchmarkHistoryKeys.workload(measurement.workload),
  );
  if (measurement.workload != BenchmarkWorkload.random4kMultiThread) {
    return title;
  }
  return '$title: ${measurement.threadCount} '
      '${tr(context, BenchmarkHistoryKeys.threads)}';
}

String _vidPid(BenchmarkDeviceIdentity device) {
  final vid = device.vid.isEmpty ? '----' : device.vid;
  final pid = device.pid.isEmpty ? '----' : device.pid;
  return '$vid / $pid';
}

String _speed(double value) => '${value.toStringAsFixed(2)} MB/s';

String _iops(double value) => '${value.toStringAsFixed(0)} IOPS';

String _slcStatus(BuildContext context, BenchmarkResult result) {
  return switch (result.slcStatus) {
    BenchmarkSlcStatus.detected =>
      '${result.slcCacheInflectionGB.toStringAsFixed(2)} GB '
          '(${(result.slcConfidence * 100).toStringAsFixed(0)}%)',
    BenchmarkSlcStatus.noInflection => tr(
      context,
      BenchmarkHistoryKeys.noCacheInflection,
    ),
    BenchmarkSlcStatus.insufficientRange =>
      'N/A (${tr(context, BenchmarkHistoryKeys.noSamples)})',
    BenchmarkSlcStatus.notRun => 'N/A',
  };
}

String _threadLabel(BuildContext context, String metric) {
  final chinese = Localizations.localeOf(context).languageCode == 'zh';
  return switch (metric) {
    'retention' => chinese ? '峰值保持率' : 'Peak retention',
    _ => chinese ? '归一化效率' : 'Normalized efficiency',
  };
}
