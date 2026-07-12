import 'package:flutter_test/flutter_test.dart';
import 'package:win_deploy_studio/features/ai_assistant/services/benchmark_record_context.dart';

import 'benchmark_test_fixtures.dart';

void main() {
  test('formats selected benchmark records as explanatory plain text', () {
    final first = benchmarkTestRecord(
      benchmarkTestResult(model: 'Portable SSD A'),
      id: 'first-record',
    );
    final second = benchmarkTestRecord(
      benchmarkTestResult(model: 'Portable SSD B', score: 61),
      id: 'second-record',
    );

    final text = buildBenchmarkRecordContext([first, second]);

    expect(text, contains('[SELECTED DISK TEST RECORDS]'));
    expect(text, contains('Record count: 2'));
    expect(text, contains('[METRIC DEFINITIONS]'));
    expect(text, contains('4K random read/write'));
    expect(text, contains('first-record'));
    expect(text, contains('second-record'));
    expect(text, contains('Portable SSD A'));
    expect(text, contains('SERIAL-1234'));
    expect(text, contains('[RUN PARAMETERS]'));
    expect(text, contains('[WORKLOAD MEASUREMENTS]'));
    expect(text, contains('latency p50='));
    expect(text, contains('sample 1:'));
    expect(text, contains('[CHART POINTS]'));
  });
}
