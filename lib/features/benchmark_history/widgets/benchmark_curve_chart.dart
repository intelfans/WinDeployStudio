import 'dart:math';

import 'package:flutter/material.dart';

import '../../../core/localization/strings.dart';
import '../../benchmark/models/benchmark_models.dart';
import '../benchmark_history_copy.dart';

enum BenchmarkCurveMetric { throughput, iops, latencyP99 }

enum BenchmarkCurveXAxis { seconds, gigabytes, threads }

class BenchmarkCurveChart extends StatefulWidget {
  final List<BenchmarkSample> primary;
  final List<BenchmarkSample> secondary;
  final String primaryLabel;
  final String secondaryLabel;
  final double primaryMarkerX;
  final double secondaryMarkerX;
  final BenchmarkCurveXAxis xAxis;

  const BenchmarkCurveChart({
    super.key,
    required this.primary,
    this.secondary = const [],
    this.primaryLabel = '',
    this.secondaryLabel = '',
    this.primaryMarkerX = 0,
    this.secondaryMarkerX = 0,
    this.xAxis = BenchmarkCurveXAxis.seconds,
  });

  @override
  State<BenchmarkCurveChart> createState() => _BenchmarkCurveChartState();
}

class _BenchmarkCurveChartState extends State<BenchmarkCurveChart> {
  BenchmarkCurveMetric _metric = BenchmarkCurveMetric.throughput;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    if (widget.primary.isEmpty && widget.secondary.isEmpty) {
      return SizedBox(
        height: 220,
        child: Center(
          child: Text(
            tr(context, BenchmarkHistoryKeys.noSamples),
            style: TextStyle(color: colors.onSurfaceVariant),
          ),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SegmentedButton<BenchmarkCurveMetric>(
            showSelectedIcon: false,
            segments: [
              ButtonSegment(
                value: BenchmarkCurveMetric.throughput,
                icon: const Icon(Icons.speed_rounded, size: 18),
                label: Text(tr(context, BenchmarkHistoryKeys.throughput)),
              ),
              ButtonSegment(
                value: BenchmarkCurveMetric.iops,
                icon: const Icon(Icons.query_stats_rounded, size: 18),
                label: Text(tr(context, BenchmarkHistoryKeys.iops)),
              ),
              ButtonSegment(
                value: BenchmarkCurveMetric.latencyP99,
                icon: const Icon(Icons.timer_outlined, size: 18),
                label: Text(tr(context, BenchmarkHistoryKeys.latency)),
              ),
            ],
            selected: {_metric},
            onSelectionChanged: (selection) {
              setState(() => _metric = selection.first);
            },
          ),
        ),
        const SizedBox(height: 12),
        if (widget.secondary.isNotEmpty) ...[
          Wrap(
            spacing: 18,
            runSpacing: 6,
            children: [
              _Legend(color: colors.primary, label: widget.primaryLabel),
              _Legend(color: colors.tertiary, label: widget.secondaryLabel),
            ],
          ),
          const SizedBox(height: 8),
        ],
        SizedBox(
          height: 220,
          child: CustomPaint(
            painter: _CurvePainter(
              primary: widget.primary,
              secondary: widget.secondary,
              metric: _metric,
              primaryColor: colors.primary,
              secondaryColor: colors.tertiary,
              gridColor: colors.outlineVariant,
              textColor: colors.onSurfaceVariant,
              primaryMarkerX: widget.primaryMarkerX,
              secondaryMarkerX: widget.secondaryMarkerX,
              markerLabel: tr(context, BenchmarkHistoryKeys.slcInflection),
              xAxis: widget.xAxis,
              threadLabel: tr(context, BenchmarkHistoryKeys.threads),
            ),
            child: const SizedBox.expand(),
          ),
        ),
      ],
    );
  }
}

class _Legend extends StatelessWidget {
  final Color color;
  final String label;

  const _Legend({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 18, height: 3, color: color),
        const SizedBox(width: 7),
        Text(label, style: Theme.of(context).textTheme.labelMedium),
      ],
    );
  }
}

class _CurvePainter extends CustomPainter {
  final List<BenchmarkSample> primary;
  final List<BenchmarkSample> secondary;
  final BenchmarkCurveMetric metric;
  final Color primaryColor;
  final Color secondaryColor;
  final Color gridColor;
  final Color textColor;
  final double primaryMarkerX;
  final double secondaryMarkerX;
  final String markerLabel;
  final BenchmarkCurveXAxis xAxis;
  final String threadLabel;

  const _CurvePainter({
    required this.primary,
    required this.secondary,
    required this.metric,
    required this.primaryColor,
    required this.secondaryColor,
    required this.gridColor,
    required this.textColor,
    required this.primaryMarkerX,
    required this.secondaryMarkerX,
    required this.markerLabel,
    required this.xAxis,
    required this.threadLabel,
  });

  @override
  void paint(Canvas canvas, Size size) {
    const left = 58.0;
    const right = 16.0;
    const top = 12.0;
    const bottom = 31.0;
    final chart = Rect.fromLTWH(
      left,
      top,
      max(1, size.width - left - right),
      max(1, size.height - top - bottom),
    );
    final all = [...primary, ...secondary];
    if (all.isEmpty) return;
    final minX = all.map((sample) => sample.x).reduce(min);
    final maxX = all.map((sample) => sample.x).reduce(max);
    final maxYRaw = all.map(_value).fold<double>(0, max);
    final maxY = max(1.0, maxYRaw * 1.15);
    final xRange = max(0.0001, maxX - minX);

    final gridPaint = Paint()
      ..color = gridColor.withValues(alpha: 0.75)
      ..strokeWidth = 1;
    final labels = TextPainter(textDirection: TextDirection.ltr);
    for (var index = 0; index <= 4; index++) {
      final ratio = index / 4;
      final y = chart.bottom - chart.height * ratio;
      canvas.drawLine(Offset(chart.left, y), Offset(chart.right, y), gridPaint);
      labels.text = TextSpan(
        text: _formatAxis(maxY * ratio),
        style: TextStyle(color: textColor, fontSize: 10),
      );
      labels.layout(maxWidth: left - 8);
      labels.paint(canvas, Offset(0, y - labels.height / 2));
    }

    Offset mapSample(BenchmarkSample sample) {
      final x = chart.left + ((sample.x - minX) / xRange) * chart.width;
      final y = chart.bottom - (_value(sample) / maxY) * chart.height;
      return Offset(x, y);
    }

    void drawCurve(List<BenchmarkSample> samples, Color color) {
      if (samples.isEmpty) return;
      final path = Path();
      for (var index = 0; index < samples.length; index++) {
        final point = mapSample(samples[index]);
        if (index == 0) {
          path.moveTo(point.dx, point.dy);
        } else {
          path.lineTo(point.dx, point.dy);
        }
      }
      canvas.drawPath(
        path,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.4
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round,
      );
      canvas.drawCircle(mapSample(samples.last), 3.5, Paint()..color = color);
    }

    drawCurve(primary, primaryColor);
    drawCurve(secondary, secondaryColor);

    void drawMarker(double markerX, Color color, double labelOffset) {
      if (markerX <= 0 || markerX < minX || markerX > maxX) return;
      final x = chart.left + ((markerX - minX) / xRange) * chart.width;
      final markerPaint = Paint()
        ..color = color
        ..strokeWidth = 1.5;
      canvas.drawLine(
        Offset(x, chart.top),
        Offset(x, chart.bottom),
        markerPaint,
      );
      labels.text = TextSpan(
        text: '$markerLabel ${markerX.toStringAsFixed(1)} GB',
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.w700,
        ),
      );
      labels.layout(maxWidth: chart.width);
      labels.paint(
        canvas,
        Offset(
          min(x + 4, chart.right - labels.width),
          chart.top + 2 + labelOffset,
        ),
      );
    }

    drawMarker(primaryMarkerX, primaryColor, 0);
    drawMarker(secondaryMarkerX, secondaryColor, 14);

    labels.text = TextSpan(
      text: _unit,
      style: TextStyle(
        color: textColor,
        fontSize: 10,
        fontWeight: FontWeight.w600,
      ),
    );
    labels.layout();
    labels.paint(canvas, Offset(chart.left, size.height - 18));

    final rightLabel = switch (xAxis) {
      BenchmarkCurveXAxis.gigabytes => '${maxX.toStringAsFixed(1)} GB',
      BenchmarkCurveXAxis.threads => '${maxX.toStringAsFixed(0)} $threadLabel',
      BenchmarkCurveXAxis.seconds => '${maxX.toStringAsFixed(1)} s',
    };
    labels.text = TextSpan(
      text: rightLabel,
      style: TextStyle(color: textColor, fontSize: 10),
    );
    labels.layout();
    labels.paint(canvas, Offset(chart.right - labels.width, size.height - 18));
  }

  double _value(BenchmarkSample sample) => switch (metric) {
    BenchmarkCurveMetric.throughput => sample.throughputMBps,
    BenchmarkCurveMetric.iops => sample.iops,
    BenchmarkCurveMetric.latencyP99 => sample.latency.p99Ms,
  };

  String get _unit => switch (metric) {
    BenchmarkCurveMetric.throughput => 'MB/s',
    BenchmarkCurveMetric.iops => 'IOPS',
    BenchmarkCurveMetric.latencyP99 => 'ms',
  };

  String _formatAxis(double value) {
    if (value >= 10000) return '${(value / 1000).toStringAsFixed(0)}k';
    if (value >= 100) return value.toStringAsFixed(0);
    if (value >= 10) return value.toStringAsFixed(1);
    return value.toStringAsFixed(2);
  }

  @override
  bool shouldRepaint(covariant _CurvePainter oldDelegate) {
    return oldDelegate.primary != primary ||
        oldDelegate.secondary != secondary ||
        oldDelegate.metric != metric ||
        oldDelegate.primaryColor != primaryColor ||
        oldDelegate.secondaryColor != secondaryColor ||
        oldDelegate.gridColor != gridColor ||
        oldDelegate.textColor != textColor ||
        oldDelegate.primaryMarkerX != primaryMarkerX ||
        oldDelegate.secondaryMarkerX != secondaryMarkerX ||
        oldDelegate.markerLabel != markerLabel ||
        oldDelegate.xAxis != xAxis ||
        oldDelegate.threadLabel != threadLabel;
  }
}
