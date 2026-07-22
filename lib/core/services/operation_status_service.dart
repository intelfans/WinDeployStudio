import 'package:flutter_riverpod/legacy.dart';

/// Operations that continue while the user browses another section.
enum TrackedOperationKind { installMedia, toGo }

class OperationActivity {
  final TrackedOperationKind kind;
  final String phase;
  final String message;
  final double progress;
  final bool cancellable;
  final int writtenBytes;
  final int totalBytes;
  final int speedBytesPerSecond;
  final int elapsedSeconds;
  final DateTime? startedAt;
  final String? error;
  final bool active;
  final bool isLinux;

  /// Raw localization keys for recent phases, retained across page disposal.
  final List<String> progressLog;

  const OperationActivity({
    required this.kind,
    required this.phase,
    required this.message,
    required this.progress,
    this.cancellable = false,
    this.writtenBytes = 0,
    this.totalBytes = 0,
    this.speedBytesPerSecond = 0,
    this.elapsedSeconds = 0,
    this.startedAt,
    this.error,
    this.active = true,
    this.isLinux = false,
    this.progressLog = const <String>[],
  });

  OperationActivity copyWith({
    String? phase,
    String? message,
    double? progress,
    bool? cancellable,
    int? writtenBytes,
    int? totalBytes,
    int? speedBytesPerSecond,
    int? elapsedSeconds,
    DateTime? startedAt,
    String? error,
    bool? active,
    bool? isLinux,
    List<String>? progressLog,
  }) {
    return OperationActivity(
      kind: kind,
      phase: phase ?? this.phase,
      message: message ?? this.message,
      progress: progress ?? this.progress,
      cancellable: cancellable ?? this.cancellable,
      writtenBytes: writtenBytes ?? this.writtenBytes,
      totalBytes: totalBytes ?? this.totalBytes,
      speedBytesPerSecond: speedBytesPerSecond ?? this.speedBytesPerSecond,
      elapsedSeconds: elapsedSeconds ?? this.elapsedSeconds,
      startedAt: startedAt ?? this.startedAt,
      error: error ?? this.error,
      active: active ?? this.active,
      isLinux: isLinux ?? this.isLinux,
      progressLog: progressLog ?? this.progressLog,
    );
  }

  int get effectiveElapsedSeconds {
    final start = startedAt;
    if (!active || start == null) return elapsedSeconds;
    final wallClockSeconds = DateTime.now().difference(start).inSeconds;
    return wallClockSeconds > elapsedSeconds
        ? wallClockSeconds
        : elapsedSeconds;
  }
}

class OperationStatusNotifier
    extends StateNotifier<Map<TrackedOperationKind, OperationActivity>> {
  OperationStatusNotifier() : super(const {});

  void update({
    required TrackedOperationKind kind,
    required String phase,
    required String message,
    required double progress,
    bool cancellable = false,
    int writtenBytes = 0,
    int totalBytes = 0,
    int speedBytesPerSecond = 0,
    int elapsedSeconds = 0,
    String? error,
    bool active = true,
    bool isLinux = false,
  }) {
    final next = Map<TrackedOperationKind, OperationActivity>.from(state);
    final previous = next[kind];
    final now = DateTime.now();
    final startedAt = previous?.active == true
        ? previous!.startedAt ?? now
        : active
        ? now
        : previous?.startedAt;
    final wallClockSeconds = startedAt == null
        ? 0
        : now.difference(startedAt).inSeconds;
    final resolvedElapsedSeconds = elapsedSeconds > wallClockSeconds
        ? elapsedSeconds
        : wallClockSeconds;
    final incomingProgress = progress.clamp(0, 1).toDouble();
    final preserveFailureProgress =
        phase.trim().toLowerCase() == 'failed' &&
        previous != null &&
        incomingProgress < previous.progress;
    final resolvedProgress = preserveFailureProgress
        ? previous.progress
        : incomingProgress;
    final resolvedWrittenBytes = preserveFailureProgress && writtenBytes == 0
        ? previous.writtenBytes
        : writtenBytes;
    final resolvedTotalBytes = preserveFailureProgress && totalBytes == 0
        ? previous.totalBytes
        : totalBytes;
    final resolvedSpeedBytesPerSecond =
        preserveFailureProgress && speedBytesPerSecond == 0
        ? previous.speedBytesPerSecond
        : speedBytesPerSecond;
    final messageKey = message.split('\n').first.trim();
    final history = <String>[];
    // A service and its screen may both publish the same terminal snapshot;
    // retain that operation's history. A new active update after a terminal
    // snapshot still starts a clean history because it does not enter here.
    if (previous?.active == true || (previous != null && !active)) {
      history.addAll(previous!.progressLog);
    }
    if (messageKey.isNotEmpty &&
        (history.isEmpty || history.last != messageKey)) {
      history.add(messageKey);
    }
    // File-copy callbacks can be frequent. Keep enough context for a
    // recreated screen without retaining an unbounded list.
    const maxProgressHistory = 40;
    if (history.length > maxProgressHistory) {
      history.removeRange(0, history.length - maxProgressHistory);
    }
    next[kind] = OperationActivity(
      kind: kind,
      phase: phase,
      message: message,
      progress: resolvedProgress,
      cancellable: cancellable,
      writtenBytes: resolvedWrittenBytes,
      totalBytes: resolvedTotalBytes,
      speedBytesPerSecond: resolvedSpeedBytesPerSecond,
      elapsedSeconds: resolvedElapsedSeconds,
      startedAt: startedAt,
      error: error,
      active: active,
      isLinux: isLinux,
      progressLog: List<String>.unmodifiable(history),
    );
    state = next;
  }

  void clear(TrackedOperationKind kind) {
    if (!state.containsKey(kind)) return;
    final next = Map<TrackedOperationKind, OperationActivity>.from(state)
      ..remove(kind);
    state = next;
  }
}

final operationStatusProvider =
    StateNotifierProvider<
      OperationStatusNotifier,
      Map<TrackedOperationKind, OperationActivity>
    >((ref) => OperationStatusNotifier());
