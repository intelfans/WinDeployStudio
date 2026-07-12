import '../../../core/services/bootable_usb_service.dart';
import '../../../core/services/elevation_service.dart';

class CreatorTaskTerminalState {
  final CreateProgress progress;
  final bool success;
  final bool cancelled;

  const CreatorTaskTerminalState({
    required this.progress,
    required this.success,
    required this.cancelled,
  });
}

CreateProgress createProgressFromElevatedTask(ElevatedTaskProgress progress) {
  final step = switch (progress.phase.trim()) {
    'cleaningDisk' => CreateStep.cleaningDisk,
    'creatingPartitions' => CreateStep.creatingPartitions,
    'formatting' => CreateStep.formatting,
    'mountingIso' => CreateStep.mountingIso,
    'copyingFiles' => CreateStep.copyingFiles,
    'splittingWim' => CreateStep.splittingWim,
    'writingBootFiles' => CreateStep.writingBootFiles,
    'verifying' => CreateStep.verifying,
    'complete' => CreateStep.complete,
    'failed' || 'cancelled' => CreateStep.failed,
    _ => CreateStep.preparing,
  };
  return CreateProgress(
    step: step,
    progress: progress.progress,
    message: progress.message.isEmpty
        ? _fallbackMessage(step)
        : progress.message,
  );
}

CreatorTaskTerminalState finishCreatorElevatedTask({
  required bool success,
  required ElevatedTaskProgress? latestProgress,
  required bool cancelRequested,
}) {
  final latestMessage = latestProgress?.message.trim() ?? '';
  if (success) {
    return CreatorTaskTerminalState(
      success: true,
      cancelled: false,
      progress: CreateProgress(
        step: CreateStep.complete,
        progress: 1,
        message: latestMessage.isEmpty ? 'boot_complete' : latestMessage,
      ),
    );
  }

  final phase = latestProgress?.phase.trim().toLowerCase() ?? '';
  final normalizedMessage = latestMessage.toLowerCase();
  final cancelled =
      cancelRequested ||
      phase == 'cancelled' ||
      normalizedMessage == 'deploy_cancel_requested' ||
      normalizedMessage.contains('cancelled') ||
      normalizedMessage.contains('canceled');
  return CreatorTaskTerminalState(
    success: false,
    cancelled: cancelled,
    progress: CreateProgress(
      step: CreateStep.failed,
      progress: latestProgress?.progress ?? 0,
      message: latestMessage.isNotEmpty
          ? latestMessage
          : (cancelled ? 'deploy_cancel_requested' : 'creator_error'),
    ),
  );
}

String _fallbackMessage(CreateStep step) => switch (step) {
  CreateStep.complete => 'boot_complete',
  CreateStep.failed => 'creator_error',
  _ => 'step_preparing',
};
