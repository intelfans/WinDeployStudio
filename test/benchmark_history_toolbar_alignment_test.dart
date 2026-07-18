import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:win_deploy_studio/features/benchmark/models/benchmark_models.dart';
import 'package:win_deploy_studio/features/benchmark_history/models/benchmark_history_models.dart';
import 'package:win_deploy_studio/features/benchmark_history/screens/benchmark_history_screen.dart';
import 'package:win_deploy_studio/features/benchmark_history/services/benchmark_history_service.dart';

import 'benchmark_test_fixtures.dart';

void main() {
  testWidgets(
    'history toolbar actions stay flush-right before and after selection',
    (tester) async {
      final service = _FixedHistoryService([
        benchmarkTestRecord(benchmarkTestResult(), id: 'first'),
        benchmarkTestRecord(
          benchmarkTestResult(completedAt: DateTime.utc(2026, 7, 13)),
          id: 'second',
        ),
      ]);
      await tester.binding.setSurfaceSize(const Size(1600, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            benchmarkHistoryServiceProvider.overrideWithValue(service),
          ],
          child: const MaterialApp(home: BenchmarkHistoryScreen()),
        ),
      );
      for (
        var index = 0;
        index < 20 && find.byType(Checkbox).evaluate().length < 2;
        index++
      ) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(find.byType(Checkbox), findsNWidgets(2));

      final actions = find.byKey(
        const ValueKey('benchmark-history-toolbar-actions'),
      );
      expect(actions, findsOneWidget);
      final unselectedRight = tester.getBottomRight(actions).dx;
      expect(unselectedRight, closeTo(1576, 0.1));

      await tester.tap(find.byType(Checkbox).first);
      await tester.pump();

      final selectedRight = tester.getBottomRight(actions).dx;
      expect(selectedRight, closeTo(unselectedRight, 0.1));
      expect(selectedRight, closeTo(1576, 0.1));
    },
  );
}

class _FixedHistoryService extends BenchmarkHistoryService {
  _FixedHistoryService(this.records);

  final List<BenchmarkHistoryRecord> records;

  @override
  Future<List<BenchmarkHistoryRecord>> list({
    DateTime? from,
    DateTime? to,
    BenchmarkDeviceIdentity? device,
    String? model,
    String? serialNumber,
    String? vid,
    String? pid,
  }) async {
    return records;
  }
}
