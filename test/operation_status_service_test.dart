import 'package:flutter_test/flutter_test.dart';
import 'package:win_deploy_studio/core/services/operation_status_service.dart';
import 'package:win_deploy_studio/shared/widgets/operation_status_overlay.dart';

void main() {
  test('expanded operation overlay can reach the lower viewport', () {
    expect(operationOverlayMaxTop(1000, 198), 786);
    expect(operationOverlayMaxTop(1000, 64), 920);
    expect(operationOverlayMaxTop(160, 198), 12);
  });

  test(
    'operation status keeps independent activities and terminal snapshots',
    () {
      final notifier = OperationStatusNotifier();
      notifier.update(
        kind: TrackedOperationKind.installMedia,
        phase: 'copyingFiles',
        message: 'step_copying',
        progress: .42,
        isLinux: false,
      );
      notifier.update(
        kind: TrackedOperationKind.toGo,
        phase: 'applyingImage',
        message: 'wtg_step_applying',
        progress: .18,
        isLinux: true,
        writtenBytes: 18,
        totalBytes: 100,
      );

      expect(notifier.state[TrackedOperationKind.installMedia]?.progress, .42);
      expect(notifier.state[TrackedOperationKind.toGo]?.isLinux, isTrue);
      expect(notifier.state[TrackedOperationKind.toGo]?.totalBytes, 100);
      expect(
        notifier.state[TrackedOperationKind.toGo]?.effectiveElapsedSeconds,
        greaterThanOrEqualTo(0),
      );

      notifier.update(
        kind: TrackedOperationKind.installMedia,
        phase: 'failed',
        message: 'boot_format_failed',
        progress: .42,
        active: false,
      );
      expect(
        notifier.state[TrackedOperationKind.installMedia]?.active,
        isFalse,
      );
      expect(notifier.state[TrackedOperationKind.toGo]?.active, isTrue);
    },
  );

  test('operation history survives duplicate terminal publication', () {
    final notifier = OperationStatusNotifier();
    notifier.update(
      kind: TrackedOperationKind.toGo,
      phase: 'preparing',
      message: 'wtg_step_preparing',
      progress: 0,
    );
    notifier.update(
      kind: TrackedOperationKind.toGo,
      phase: 'applyingImage',
      message: 'wtg_step_applying',
      progress: .5,
    );
    notifier.update(
      kind: TrackedOperationKind.toGo,
      phase: 'failed',
      message: 'wtg_svc_apply_failed',
      progress: .5,
      active: false,
    );
    notifier.update(
      kind: TrackedOperationKind.toGo,
      phase: 'failed',
      message: 'wtg_svc_apply_failed',
      progress: .5,
      active: false,
    );

    expect(notifier.state[TrackedOperationKind.toGo]?.progressLog, [
      'wtg_step_preparing',
      'wtg_step_applying',
      'wtg_svc_apply_failed',
    ]);

    notifier.update(
      kind: TrackedOperationKind.toGo,
      phase: 'preparing',
      message: 'wtg_step_preparing',
      progress: 0,
      active: true,
    );
    expect(notifier.state[TrackedOperationKind.toGo]?.progressLog, [
      'wtg_step_preparing',
    ]);
  });

  test('terminal failure keeps the last meaningful progress metrics', () {
    final notifier = OperationStatusNotifier();
    notifier.update(
      kind: TrackedOperationKind.toGo,
      phase: 'copyingFiles',
      message: 'linux_writing_image',
      progress: .96,
      writtenBytes: 960,
      totalBytes: 1000,
      speedBytesPerSecond: 100,
    );
    notifier.update(
      kind: TrackedOperationKind.toGo,
      phase: 'failed',
      message: 'linux_write_failed',
      progress: 0,
      active: false,
    );

    final activity = notifier.state[TrackedOperationKind.toGo]!;
    expect(activity.progress, .96);
    expect(activity.writtenBytes, 960);
    expect(activity.totalBytes, 1000);
    expect(activity.speedBytesPerSecond, 100);
  });
}
