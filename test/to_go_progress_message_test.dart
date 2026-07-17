import 'package:flutter_test/flutter_test.dart';
import 'package:win_deploy_studio/core/localization/strings.dart';
import 'package:win_deploy_studio/features/wtg/models/to_go_progress_message.dart';

void main() {
  test(
    'image application progress fills percent in every supported language',
    () {
      for (final locale in supportedLocaleCodes) {
        final message = resolveToGoProgressMessage(
          rawMessage: 'wtg_svc_applying_percent',
          translate: (key) => trByCode(locale, key),
          translationMissing: trByCode(locale, 'translation_missing'),
          writtenBytes: 230,
          totalBytes: 1000,
          progress: 0.33,
        );

        expect(message, isNot(contains('{percent}')), reason: locale);
        expect(message, contains('23'), reason: locale);
      }
    },
  );

  test(
    'progress falls back to the image-application phase before byte data',
    () {
      expect(
        toGoImageApplyPercent(
          writtenBytes: 0,
          totalBytes: 0,
          progress: 0.22 + (0.48 * 0.42),
        ),
        42,
      );
    },
  );

  test(
    'an unknown progress key remains diagnostic text, not a missing string',
    () {
      const rawMessage = 'custom deployment diagnostic';
      expect(
        resolveToGoProgressMessage(
          rawMessage: rawMessage,
          translate: (key) => key == 'translation_missing'
              ? 'Unavailable in this language'
              : 'Unavailable in this language',
          translationMissing: 'Unavailable in this language',
        ),
        rawMessage,
      );
    },
  );
}
