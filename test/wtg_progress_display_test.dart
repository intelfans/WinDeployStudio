import 'package:flutter_test/flutter_test.dart';
import 'package:win_deploy_studio/features/wtg/screens/wtg_screen.dart';

void main() {
  group('toGoProgressTitleKey', () {
    test('Linux To Go keeps the writer status for copied files', () {
      expect(
        toGoProgressTitleKey(
          isLinux: true,
          phase: 'copyingFiles',
          message: 'linux_writing_image',
        ),
        'linux_writing_image',
      );
    });

    test(
      'Linux To Go keeps neutral writer statuses instead of Windows labels',
      () {
        expect(
          toGoProgressTitleKey(
            isLinux: true,
            phase: 'copyingFiles',
            message: 'step_copying',
          ),
          'step_copying',
        );
        expect(
          toGoProgressTitleKey(
            isLinux: true,
            phase: 'verifying',
            message: 'linux_finalizing',
          ),
          'linux_finalizing',
        );
      },
    );

    test('Linux To Go falls back to a Linux preparation status', () {
      expect(
        toGoProgressTitleKey(isLinux: true, phase: 'copyingFiles', message: ''),
        'linux_preparing',
      );
    });

    test('Windows To Go preserves its Windows image phase mapping', () {
      expect(
        toGoProgressTitleKey(
          isLinux: false,
          phase: 'copyingFiles',
          message: 'step_copying',
        ),
        'wtg_step_applying',
      );
    });
  });
}
