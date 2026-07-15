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
}
