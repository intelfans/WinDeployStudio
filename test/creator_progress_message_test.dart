import 'package:flutter_test/flutter_test.dart';
import 'package:win_deploy_studio/core/localization/strings.dart';
import 'package:win_deploy_studio/features/creator/models/creator_progress_message.dart';

void main() {
  test(
    'partition errors interpolate diagnostics in every supported language',
    () {
      const diagnostic = 'DiskPart returned access denied.';
      const logPath = r'C:\Users\Example\last_creation_log.txt';
      const rawMessage = 'boot_partition_failed\n\nLog: $logPath';

      for (final locale in supportedLocaleCodes) {
        final rendered = resolveCreatorProgressMessage(
          rawMessage: rawMessage,
          error: diagnostic,
          translate: (key) => trByCode(locale, key),
        );

        expect(rendered, isNot(contains('{error}')), reason: locale);
        expect(rendered, contains(diagnostic), reason: locale);
        expect(
          rendered,
          contains('${trByCode(locale, 'logs_title')}: $logPath'),
          reason: locale,
        );
      }
    },
  );

  test('a missing diagnostic never leaks an error placeholder', () {
    for (final locale in supportedLocaleCodes) {
      final rendered = resolveCreatorProgressMessage(
        rawMessage: 'boot_partition_failed',
        translate: (key) => trByCode(locale, key),
      );

      expect(rendered, isNot(contains('{error}')), reason: locale);
      expect(
        rendered,
        contains(trByCode(locale, 'creator_error')),
        reason: locale,
      );
    }
  });

  test('detailed safety failures interpolate the detection reason', () {
    const diagnostic = 'Disk inventory query timed out after 10 seconds.';
    for (final locale in supportedLocaleCodes) {
      final rendered = resolveCreatorProgressMessage(
        rawMessage: 'safety_detection_failed_detail',
        error: diagnostic,
        translate: (key) => trByCode(locale, key),
      );

      expect(rendered, contains(diagnostic), reason: locale);
      expect(rendered, isNot(contains('{detail}')), reason: locale);
    }
  });

  test(
    'a localized diagnostic token is resolved in every supported language',
    () {
      const keys = [
        'boot_partition_layout_not_ready',
        'boot_drive_letter_in_use',
      ];
      for (final key in keys) {
        for (final locale in supportedLocaleCodes) {
          final rendered = resolveCreatorProgressMessage(
            rawMessage: 'boot_partition_failed',
            error: 'i18n:$key',
            translate: (value) => trByCode(locale, value),
          );

          expect(rendered, contains(trByCode(locale, key)), reason: locale);
          expect(rendered, isNot(contains('i18n:')), reason: locale);
        }
      }
    },
  );

  test('storage safety diagnostics are localized in every language', () {
    const keys = [
      'safety_detail_storage_timeout',
      'safety_detail_storage_unavailable',
    ];
    for (final key in keys) {
      for (final locale in supportedLocaleCodes) {
        final localized = trByCode(locale, key);
        expect(localized, isNot(key), reason: '$locale:$key');
        expect(localized, isNot(trByCode(locale, 'translation_missing')));
        expect(
          resolveCreatorDiagnostic(
            'i18n:$key',
            (value) => trByCode(locale, value),
          ),
          localized,
          reason: '$locale:$key',
        );
      }
    }
  });

  test('localized diagnostics never leak their internal i18n token', () {
    for (final locale in supportedLocaleCodes) {
      final rendered = resolveCreatorProgressMessage(
        rawMessage: 'boot_preflight_failed',
        error: 'i18n:boot_preflight_source_location',
        translate: (key) => trByCode(locale, key),
      );

      expect(
        rendered,
        contains(trByCode(locale, 'boot_preflight_source_location')),
        reason: locale,
      );
      expect(rendered, isNot(contains('i18n:')), reason: locale);
    }
  });
}
