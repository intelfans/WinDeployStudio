import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:win_deploy_studio/features/benchmark/models/benchmark_models.dart';
import 'package:win_deploy_studio/features/benchmark_history/widgets/benchmark_workload_chart.dart';

void main() {
  const series = <BenchmarkSampleSeries>[
    BenchmarkSampleSeries(
      workload: BenchmarkWorkload.sequentialWrite,
      samples: [BenchmarkSample(x: 1, throughputMBps: 100)],
    ),
    BenchmarkSampleSeries(
      workload: BenchmarkWorkload.random4kWrite,
      samples: [BenchmarkSample(x: 1, throughputMBps: 20)],
    ),
    BenchmarkSampleSeries(
      workload: BenchmarkWorkload.random4kRead,
      samples: [BenchmarkSample(x: 1, throughputMBps: 30)],
    ),
  ];

  Future<void> pumpChart(
    WidgetTester tester, {
    required BenchmarkWorkload? activeWorkload,
    List<BenchmarkSampleSeries> primarySeries = series,
  }) {
    return tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BenchmarkWorkloadChart(
            primarySeries: primarySeries,
            activeWorkload: activeWorkload,
          ),
        ),
      ),
    );
  }

  Finder selector(BenchmarkWorkload workload) =>
      find.byKey(ValueKey('benchmark-workload-selector-${workload.name}'));

  testWidgets(
    'follows each newly active live workload while keeping the selector',
    (tester) async {
      await pumpChart(
        tester,
        activeWorkload: BenchmarkWorkload.sequentialWrite,
      );
      expect(selector(BenchmarkWorkload.sequentialWrite), findsOneWidget);

      await pumpChart(tester, activeWorkload: BenchmarkWorkload.random4kRead);
      expect(selector(BenchmarkWorkload.random4kRead), findsOneWidget);
      expect(
        find.byType(DropdownButtonFormField<BenchmarkWorkload>),
        findsOneWidget,
      );
    },
  );

  testWidgets('keeps a manual choice until the active workload changes', (
    tester,
  ) async {
    await pumpChart(tester, activeWorkload: BenchmarkWorkload.random4kWrite);
    await tester.tap(selector(BenchmarkWorkload.random4kWrite));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Seq Write').last);
    await tester.pumpAndSettle();
    expect(selector(BenchmarkWorkload.sequentialWrite), findsOneWidget);

    await pumpChart(tester, activeWorkload: BenchmarkWorkload.random4kWrite);
    expect(selector(BenchmarkWorkload.sequentialWrite), findsOneWidget);

    await pumpChart(tester, activeWorkload: BenchmarkWorkload.random4kRead);
    expect(selector(BenchmarkWorkload.random4kRead), findsOneWidget);
  });

  testWidgets('shows a newly active stage before its first sample arrives', (
    tester,
  ) async {
    await pumpChart(
      tester,
      activeWorkload: BenchmarkWorkload.fullSequentialWrite,
      primarySeries: const [],
    );

    expect(selector(BenchmarkWorkload.fullSequentialWrite), findsOneWidget);
  });
}
