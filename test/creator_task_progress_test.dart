import 'package:flutter_test/flutter_test.dart';
import 'package:win_deploy_studio/core/localization/strings.dart';
import 'package:win_deploy_studio/core/services/bootable_usb_service.dart';
import 'package:win_deploy_studio/features/creator/models/creator_task_progress.dart';

void main() {
  test('successful terminal state uses the final direct progress message', () {
    const finalProgress = CreateProgress(
      step: CreateStep.complete,
      message: 'linux_complete',
      progress: 1,
    );

    final state = finishCreatorTask(
      success: true,
      latestProgress: finalProgress,
      cancelRequested: false,
    );

    expect(state.success, isTrue);
    expect(state.progress.step, CreateStep.complete);
    expect(state.progress.message, 'linux_complete');
  });

  test('failed terminal state ends and preserves direct diagnostics', () {
    const finalProgress = CreateProgress(
      step: CreateStep.failed,
      message: 'linux_verify_failed\nbyte mismatch at 4096',
      progress: 0.98,
    );

    final state = finishCreatorTask(
      success: false,
      latestProgress: finalProgress,
      cancelRequested: false,
    );

    expect(state.success, isFalse);
    expect(state.cancelled, isFalse);
    expect(state.progress.step, CreateStep.failed);
    expect(
      state.progress.message,
      'linux_verify_failed\nbyte mismatch at 4096',
    );
  });

  test('requested cancellation becomes a terminal cancelled result', () {
    const finalProgress = CreateProgress(
      step: CreateStep.failed,
      message: 'deploy_cancel_requested',
      progress: 0.5,
    );

    final state = finishCreatorTask(
      success: false,
      latestProgress: finalProgress,
      cancelRequested: true,
    );

    expect(state.cancelled, isTrue);
    expect(state.progress.step, CreateStep.failed);
    expect(state.progress.message, 'deploy_cancel_requested');
  });

  test('false result without progress cannot remain in a running state', () {
    final state = finishCreatorTask(
      success: false,
      latestProgress: null,
      cancelRequested: false,
    );

    expect(state.progress.step, CreateStep.failed);
    expect(state.progress.message, 'creator_error');
  });

  test('Linux creation progress keys resolve in all supported languages', () {
    const progressKeys = <String>[
      'creator_starting',
      'linux_preparing',
      'linux_locking_disk',
      'linux_writing_image',
      'linux_finalizing',
      'linux_complete',
      'linux_verify_failed',
      'linux_iso_not_found',
      'linux_access_denied',
      'linux_write_failed',
    ];

    for (final locale in supportedLocaleCodes) {
      final missing = trByCode(locale, 'translation_missing');
      for (final key in progressKeys) {
        final value = trByCode(locale, key);
        expect(value, isNotEmpty, reason: '$locale/$key is empty');
        expect(value, isNot(missing), reason: '$locale/$key is missing');
      }
    }
  });
}
