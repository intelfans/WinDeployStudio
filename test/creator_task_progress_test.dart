import 'package:flutter_test/flutter_test.dart';
import 'package:win_deploy_studio/core/services/bootable_usb_service.dart';
import 'package:win_deploy_studio/core/services/elevation_service.dart';
import 'package:win_deploy_studio/features/creator/models/creator_task_progress.dart';

void main() {
  test('maps server phase while preserving its complete message', () {
    const serverProgress = ElevatedTaskProgress(
      phase: 'verifying',
      message: 'linux_finalizing\nserver detail',
      progress: 0.96,
    );

    final progress = createProgressFromElevatedTask(serverProgress);

    expect(progress.step, CreateStep.verifying);
    expect(progress.progress, 0.96);
    expect(progress.message, 'linux_finalizing\nserver detail');
  });

  test('successful terminal state uses the final server message', () {
    const finalProgress = ElevatedTaskProgress(
      phase: 'complete',
      message: 'linux_complete',
      progress: 1,
    );

    final state = finishCreatorElevatedTask(
      success: true,
      latestProgress: finalProgress,
      cancelRequested: false,
    );

    expect(state.success, isTrue);
    expect(state.progress.step, CreateStep.complete);
    expect(state.progress.message, 'linux_complete');
  });

  test('failed terminal state ends and preserves server diagnostics', () {
    const finalProgress = ElevatedTaskProgress(
      phase: 'failed',
      message: 'linux_verify_failed\nbyte mismatch at 4096',
      progress: 0.98,
    );

    final state = finishCreatorElevatedTask(
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
    const finalProgress = ElevatedTaskProgress(
      phase: 'failed',
      message: 'deploy_cancel_requested',
      progress: 0.5,
    );

    final state = finishCreatorElevatedTask(
      success: false,
      latestProgress: finalProgress,
      cancelRequested: true,
    );

    expect(state.cancelled, isTrue);
    expect(state.progress.step, CreateStep.failed);
    expect(state.progress.message, 'deploy_cancel_requested');
  });

  test('false result without progress cannot remain in a running state', () {
    final state = finishCreatorElevatedTask(
      success: false,
      latestProgress: null,
      cancelRequested: false,
    );

    expect(state.progress.step, CreateStep.failed);
    expect(state.progress.message, 'creator_error');
  });
}
