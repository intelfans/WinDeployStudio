import '../../../core/services/bootable_usb_service.dart';

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

CreatorTaskTerminalState finishCreatorTask({
  required bool success,
  required CreateProgress? latestProgress,
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

  final normalizedMessage = latestMessage.toLowerCase();
  final cancelled =
      cancelRequested ||
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
