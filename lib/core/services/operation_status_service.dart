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
  final bool active;
  final bool isLinux;

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
    this.active = true,
    this.isLinux = false,
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
    bool? active,
    bool? isLinux,
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
      active: active ?? this.active,
      isLinux: isLinux ?? this.isLinux,
    );
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
    bool active = true,
    bool isLinux = false,
  }) {
    final next = Map<TrackedOperationKind, OperationActivity>.from(state);
    next[kind] = OperationActivity(
      kind: kind,
      phase: phase,
      message: message,
      progress: progress.clamp(0, 1).toDouble(),
      cancellable: cancellable,
      writtenBytes: writtenBytes,
      totalBytes: totalBytes,
      speedBytesPerSecond: speedBytesPerSecond,
      elapsedSeconds: elapsedSeconds,
      active: active,
      isLinux: isLinux,
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
