import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:win_deploy_studio/features/benchmark/models/benchmark_models.dart';
import 'package:win_deploy_studio/features/benchmark_history/widgets/benchmark_curve_chart.dart';

void main() {
  const samples = [
    BenchmarkSample(x: 1, throughputMBps: 100),
    BenchmarkSample(x: 2, throughputMBps: 120),
  ];

  Future<void> pumpComparisonChart(WidgetTester tester, Brightness brightness) {
    return tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(brightness: brightness),
        home: Scaffold(
          body: BenchmarkCurveChart(
            primary: samples,
            secondary: samples,
            primaryLabel: 'Baseline',
            secondaryLabel: 'Candidate',
          ),
        ),
      ),
    );
  }

  Iterable<Color> legendColors(WidgetTester tester) => tester
      .widgetList<Container>(find.byType(Container))
      .map((container) => container.color)
      .whereType<Color>();

  testWidgets(
    'comparison legend uses distinct gold and red colors in light mode',
    (tester) async {
      await pumpComparisonChart(tester, Brightness.light);

      expect(
        legendColors(tester),
        containsAll(const [Color(0xFF9C6500), Color(0xFFB3261E)]),
      );
    },
  );

  testWidgets(
    'comparison legend uses bright gold and red colors in dark mode',
    (tester) async {
      await pumpComparisonChart(tester, Brightness.dark);

      expect(
        legendColors(tester),
        containsAll(const [Color(0xFFFFD740), Color(0xFFFF8A80)]),
      );
    },
  );
}
