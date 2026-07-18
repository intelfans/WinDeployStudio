import 'package:flutter_test/flutter_test.dart';
import 'package:win_deploy_studio/core/localization/strings.dart';
import 'package:win_deploy_studio/features/benchmark/models/benchmark_models.dart';

void main() {
  group('live benchmark progress', () {
    test('uses the active workload to distinguish reads from writes', () {
      expect(
        BenchmarkWorkload.sequentialRead.livePhaseTitleKey,
        'benchmark_history_sequential_read',
      );
      expect(
        BenchmarkWorkload.sequentialWrite.livePhaseTitleKey,
        'bench_phase_sequential',
      );
      expect(
        BenchmarkWorkload.random4kRead.livePhaseTitleKey,
        'benchmark_history_random_read',
      );
      expect(
        BenchmarkWorkload.random4kWrite.livePhaseTitleKey,
        'bench_phase_random4k',
      );
      expect(
        BenchmarkWorkload.fullSequentialWrite.livePhaseTitleKey,
        'bench_phase_full',
      );
    });

    test('keeps the active workload on a live progress update', () {
      const progress = BenchmarkProgress(
        phase: BenchmarkPhase.sequential,
        workload: BenchmarkWorkload.sequentialRead,
        progress: 0.14,
        elapsed: Duration(seconds: 3),
        messageKey: 'bench_msg_sequential',
      );

      expect(progress.workload, BenchmarkWorkload.sequentialRead);
    });

    test(
      'precise live workload titles resolve in every supported language',
      () {
        const titleKeys = <String>{
          'benchmark_history_sequential_read',
          'bench_phase_sequential',
          'benchmark_history_random_read',
          'bench_phase_random4k',
          'bench_phase_full',
        };

        for (final locale in supportedLocaleCodes) {
          final missing = trByCode(locale, 'translation_missing');
          for (final key in titleKeys) {
            expect(
              trByCode(locale, key),
              isNot(missing),
              reason: '$locale.$key must be translated',
            );
          }
        }
      },
    );
  });
}
