import 'package:flutter/material.dart';

import '../../../core/localization/strings.dart';
import '../../benchmark/models/benchmark_models.dart';
import '../benchmark_history_copy.dart';
import 'benchmark_curve_chart.dart';

class BenchmarkWorkloadChart extends StatefulWidget {
  final List<BenchmarkSampleSeries> primarySeries;
  final List<BenchmarkSampleSeries> secondarySeries;
  final String primaryLabel;
  final String secondaryLabel;
  final double primarySlcMarkerGB;
  final double secondarySlcMarkerGB;
  final BenchmarkWorkload initialWorkload;

  const BenchmarkWorkloadChart({
    super.key,
    required this.primarySeries,
    this.secondarySeries = const [],
    this.primaryLabel = '',
    this.secondaryLabel = '',
    this.primarySlcMarkerGB = 0,
    this.secondarySlcMarkerGB = 0,
    this.initialWorkload = BenchmarkWorkload.random4kWrite,
  });

  @override
  State<BenchmarkWorkloadChart> createState() => _BenchmarkWorkloadChartState();
}

class _BenchmarkWorkloadChartState extends State<BenchmarkWorkloadChart> {
  late BenchmarkWorkload _workload = widget.initialWorkload;

  @override
  Widget build(BuildContext context) {
    final primaryWorkloads = widget.primarySeries
        .where((series) => series.samples.isNotEmpty)
        .map((series) => series.workload)
        .toSet();
    final secondaryWorkloads = widget.secondarySeries
        .where((series) => series.samples.isNotEmpty)
        .map((series) => series.workload)
        .toSet();
    final workloads = BenchmarkWorkload.values
        .where((workload) {
          if (!primaryWorkloads.contains(workload)) return false;
          return widget.secondarySeries.isEmpty ||
              secondaryWorkloads.contains(workload);
        })
        .toList(growable: false);
    if (!workloads.contains(_workload) && workloads.isNotEmpty) {
      _workload = workloads.first;
    }

    final primary = benchmarkChartSamples(widget.primarySeries, _workload);
    final secondary = benchmarkChartSamples(widget.secondarySeries, _workload);
    final isFull = _workload == BenchmarkWorkload.fullSequentialWrite;
    final xAxis = switch (_workload) {
      BenchmarkWorkload.fullSequentialWrite => BenchmarkCurveXAxis.gigabytes,
      BenchmarkWorkload.random4kMultiThread => BenchmarkCurveXAxis.threads,
      _ => BenchmarkCurveXAxis.seconds,
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (workloads.isNotEmpty) ...[
          DropdownButtonFormField<BenchmarkWorkload>(
            initialValue: _workload,
            decoration: InputDecoration(
              labelText: tr(context, BenchmarkHistoryKeys.measurements),
              border: const OutlineInputBorder(),
            ),
            items: workloads
                .map(
                  (workload) => DropdownMenuItem(
                    value: workload,
                    child: Text(
                      tr(context, BenchmarkHistoryKeys.workload(workload)),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                )
                .toList(growable: false),
            onChanged: (value) {
              if (value != null) setState(() => _workload = value);
            },
          ),
          const SizedBox(height: 16),
        ],
        BenchmarkCurveChart(
          primary: primary,
          secondary: secondary,
          primaryLabel: widget.primaryLabel,
          secondaryLabel: widget.secondaryLabel,
          primaryMarkerX: isFull ? widget.primarySlcMarkerGB : 0,
          secondaryMarkerX: isFull ? widget.secondarySlcMarkerGB : 0,
          xAxis: xAxis,
        ),
      ],
    );
  }
}
