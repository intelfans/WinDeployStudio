import 'package:flutter_test/flutter_test.dart';
import 'package:win_deploy_studio/core/localization/strings.dart';
import 'package:win_deploy_studio/features/benchmark/models/benchmark_models.dart';
import 'package:win_deploy_studio/features/benchmark_history/benchmark_history_copy.dart';

void main() {
  const fullWriteKeys = <String>{
    'bench_mode_full_write',
    'bench_mode_full_write_desc',
    'bench_phase_full',
    'bench_msg_full',
    BenchmarkHistoryKeys.workloadFullSequentialWrite,
    BenchmarkHistoryKeys.fullWriteP10,
    BenchmarkHistoryKeys.fullWriteScope,
  };

  test('full-write UI copy is translated in every supported locale', () {
    final english = <String, String>{
      for (final key in fullWriteKeys) key: trByCode('en', key),
    };

    for (final locale in supportedLocaleCodes) {
      final missing = trByCode(locale, 'translation_missing');
      for (final key in fullWriteKeys) {
        final translated = trByCode(locale, key);
        expect(translated, isNotEmpty, reason: '$locale.$key is empty');
        expect(translated, isNot(missing), reason: '$locale.$key is missing');
        if (locale != 'en') {
          expect(
            translated,
            isNot(english[key]),
            reason: '$locale.$key must not fall back to English',
          );
        }
      }
    }
  });

  test('full-write workload resolves to the localized live phase title', () {
    expect(
      BenchmarkWorkload.fullSequentialWrite.livePhaseTitleKey,
      BenchmarkPhase.fullSequential.titleKey,
    );
  });
}
