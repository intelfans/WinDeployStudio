import 'package:flutter_test/flutter_test.dart';
import 'package:win_deploy_studio/core/localization/strings.dart';
import 'package:win_deploy_studio/features/benchmark/services/benchmark_error_localization.dart';

void main() {
  test('localizes native errors with appended diagnostics', () {
    for (final locale in supportedLocaleCodes) {
      final missing = trByCode(locale, 'translation_missing');
      final localized = localizeBenchmarkError(
        locale,
        'bench_error_native_failed: The selected volume is not writable.',
      );

      expect(localized, isNotEmpty, reason: '$locale returned an empty error');
      expect(
        localized,
        isNot(missing),
        reason: '$locale showed the missing marker',
      );
      expect(localized, contains('The selected volume is not writable.'));
    }
  });

  test('falls back to a translated benchmark error for unknown keys', () {
    for (final locale in supportedLocaleCodes) {
      final missing = trByCode(locale, 'translation_missing');
      final localized = localizeBenchmarkError(
        locale,
        'bench_error_added_by_new_helper: details',
      );

      expect(localized, isNotEmpty, reason: '$locale returned an empty error');
      expect(
        localized,
        isNot(missing),
        reason: '$locale showed the missing marker',
      );
      expect(localized, contains('details'));
    }
  });

  test('keeps platform diagnostics that are not localization keys', () {
    expect(
      localizeBenchmarkError('en', 'The drive is not ready.'),
      'The drive is not ready.',
    );
  });
}
