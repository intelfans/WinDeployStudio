import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/localization/strings.dart';
import '../../benchmark/models/benchmark_models.dart';
import '../benchmark_history_copy.dart';
import '../models/benchmark_history_models.dart';
import '../widgets/benchmark_workload_chart.dart';

class BenchmarkComparisonScreen extends StatefulWidget {
  final BenchmarkComparison comparison;

  const BenchmarkComparisonScreen({super.key, required this.comparison});

  @override
  State<BenchmarkComparisonScreen> createState() =>
      _BenchmarkComparisonScreenState();
}

class _BenchmarkComparisonScreenState extends State<BenchmarkComparisonScreen> {
  @override
  Widget build(BuildContext context) {
    final comparison = widget.comparison;
    final baseline = comparison.baseline.result;
    final candidate = comparison.candidate.result;
    final dateFormat = DateFormat.yMd().add_Hm();

    return Scaffold(
      appBar: AppBar(title: Text(tr(context, BenchmarkHistoryKeys.comparison))),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text(
            baseline.device.friendlyName.isEmpty
                ? baseline.device.model
                : baseline.device.friendlyName,
            style: Theme.of(
              context,
            ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 4),
          Text(
            '${_available(context, baseline.device.serialNumber)}  |  '
            '${baseline.disk.sizeFormatted}',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 20),
          _ComparisonTable(comparison: comparison),
          const SizedBox(height: 20),
          if (baseline.sampleSeries.isNotEmpty &&
              candidate.sampleSeries.isNotEmpty)
            _Panel(
              title: tr(context, BenchmarkHistoryKeys.comparisonCurves),
              child: BenchmarkWorkloadChart(
                primarySeries: baseline.sampleSeries,
                secondarySeries: candidate.sampleSeries,
                primaryLabel:
                    '${tr(context, BenchmarkHistoryKeys.baseline)}: '
                    '${dateFormat.format(baseline.completedAt)}',
                secondaryLabel:
                    '${tr(context, BenchmarkHistoryKeys.candidate)}: '
                    '${dateFormat.format(candidate.completedAt)}',
                primarySlcMarkerGB:
                    baseline.slcStatus == BenchmarkSlcStatus.detected
                    ? baseline.slcCacheInflectionGB
                    : 0,
                secondarySlcMarkerGB:
                    candidate.slcStatus == BenchmarkSlcStatus.detected
                    ? candidate.slcCacheInflectionGB
                    : 0,
              ),
            ),
        ],
      ),
    );
  }
}

class _ComparisonTable extends StatelessWidget {
  final BenchmarkComparison comparison;

  const _ComparisonTable({required this.comparison});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final dateFormat = DateFormat.yMd().add_Hm();
    return _Panel(
      title: tr(context, BenchmarkHistoryKeys.comparison),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          headingRowColor: WidgetStatePropertyAll(
            colors.surfaceContainerHighest,
          ),
          columns: [
            DataColumn(
              label: Text(tr(context, BenchmarkHistoryKeys.measurements)),
            ),
            DataColumn(
              label: Text(
                '${tr(context, BenchmarkHistoryKeys.baseline)}\n'
                '${dateFormat.format(comparison.baseline.result.completedAt)}',
              ),
            ),
            DataColumn(
              label: Text(
                '${tr(context, BenchmarkHistoryKeys.candidate)}\n'
                '${dateFormat.format(comparison.candidate.result.completedAt)}',
              ),
            ),
            DataColumn(
              label: Text(tr(context, BenchmarkHistoryKeys.difference)),
            ),
          ],
          rows: comparison.metrics.map((metric) {
            final delta = metric.absoluteDelta;
            final percentDelta = metric.percentDelta;
            final color = delta == null || delta == 0
                ? colors.onSurfaceVariant
                : metric.improved
                ? const Color(0xFF138A45)
                : colors.error;
            final sign = delta != null && delta > 0 ? '+' : '';
            return DataRow(
              cells: [
                DataCell(Text(_metricLabel(context, metric))),
                DataCell(Text(_formatMetric(metric.baseline, metric.unit))),
                DataCell(Text(_formatMetric(metric.candidate, metric.unit))),
                DataCell(
                  Text(
                    percentDelta == null
                        ? 'N/A'
                        : '$sign${percentDelta.toStringAsFixed(1)}%',
                    style: TextStyle(color: color, fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            );
          }).toList(),
        ),
      ),
    );
  }
}

class _Panel extends StatelessWidget {
  final String title;
  final Widget child;

  const _Panel({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        border: Border.all(color: colors.outlineVariant),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              title,
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 14),
            child,
          ],
        ),
      ),
    );
  }
}

String _formatMetric(double? value, String unit) {
  if (value == null) return 'N/A';
  final formatted = unit == 'IOPS'
      ? value.toStringAsFixed(0)
      : value.toStringAsFixed(2);
  return unit.isEmpty ? formatted : '$formatted $unit';
}

String _available(BuildContext context, String value) {
  final normalized = value.trim();
  return normalized.isEmpty || normalized.toUpperCase() == 'N/A'
      ? tr(context, BenchmarkHistoryKeys.unknown)
      : normalized;
}

String _metricLabel(BuildContext context, BenchmarkMetricDelta metric) {
  final chinese = Localizations.localeOf(context).languageCode == 'zh';
  return switch (metric.key) {
    'multiThreadMultiplier' => chinese ? '多线程倍率' : 'Thread multiplier',
    'multiThreadRetention' => chinese ? '峰值保持率' : 'Peak retention',
    'multiThreadNormalizedEfficiency' =>
      chinese ? '归一化效率' : 'Normalized efficiency',
    _ => tr(context, metric.label),
  };
}
