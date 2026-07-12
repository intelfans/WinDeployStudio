import '../../../core/services/bootable_usb_service.dart';
import '../../../core/services/disk_safety_service.dart';
import '../../../core/services/iso_parse_service.dart';

enum CreatorPlatform { windows, linux }

enum CreatorStep { selectIso, selectDisk, confirm, creating, complete }

class ParseProgress {
  final String step;
  final int percent;

  const ParseProgress({required this.step, required this.percent});
}

class CreatorState {
  final CreatorPlatform platform;
  final CreatorStep step;
  final IsoMetadata? selectedIso;
  final List<DiskInfo> disks;
  final DiskInfo? selectedDisk;
  final SafetyCheckResult? safetyResult;
  final ParseProgress? parseProgress;
  final CreateProgress? createProgress;
  final bool isDetecting;
  final bool isParsing;
  final bool isCheckingSafety;
  final String? notification;

  const CreatorState({
    this.platform = CreatorPlatform.windows,
    this.step = CreatorStep.selectIso,
    this.selectedIso,
    this.disks = const [],
    this.selectedDisk,
    this.safetyResult,
    this.parseProgress,
    this.createProgress,
    this.isDetecting = false,
    this.isParsing = false,
    this.isCheckingSafety = false,
    this.notification,
  });

  bool get isLinux => platform == CreatorPlatform.linux;

  CreatorState copyWith({
    CreatorPlatform? platform,
    CreatorStep? step,
    IsoMetadata? selectedIso,
    bool clearSelectedIso = false,
    List<DiskInfo>? disks,
    DiskInfo? selectedDisk,
    bool clearSelectedDisk = false,
    SafetyCheckResult? safetyResult,
    bool clearSafetyResult = false,
    ParseProgress? parseProgress,
    bool clearParseProgress = false,
    CreateProgress? createProgress,
    bool clearCreateProgress = false,
    bool? isDetecting,
    bool? isParsing,
    bool? isCheckingSafety,
    String? notification,
    bool clearNotification = false,
  }) {
    return CreatorState(
      platform: platform ?? this.platform,
      step: step ?? this.step,
      selectedIso: clearSelectedIso ? null : (selectedIso ?? this.selectedIso),
      disks: disks ?? this.disks,
      selectedDisk: clearSelectedDisk
          ? null
          : (selectedDisk ?? this.selectedDisk),
      safetyResult: clearSafetyResult
          ? null
          : (safetyResult ?? this.safetyResult),
      parseProgress: clearParseProgress
          ? null
          : (parseProgress ?? this.parseProgress),
      createProgress: clearCreateProgress
          ? null
          : (createProgress ?? this.createProgress),
      isDetecting: isDetecting ?? this.isDetecting,
      isParsing: isParsing ?? this.isParsing,
      isCheckingSafety: isCheckingSafety ?? this.isCheckingSafety,
      notification: clearNotification
          ? null
          : (notification ?? this.notification),
    );
  }
}
