enum BootFirmware {
  uefi('UEFI'),
  bios('BIOS');

  final String commandValue;

  const BootFirmware(this.commandValue);
}

class BoundExternalDisk {
  final int snapshotDiskNumber;
  final String model;
  final BigInt sizeBytes;
  final String serialNumber;
  final String uniqueId;
  final String devicePath;
  final String pnpDeviceId;
  final String busType;
  final String partitionStyle;
  final String identityKind;
  final String identityValue;
  final bool isReadOnly;

  const BoundExternalDisk({
    required this.snapshotDiskNumber,
    required this.model,
    required this.sizeBytes,
    required this.serialNumber,
    required this.uniqueId,
    required this.devicePath,
    required this.pnpDeviceId,
    required this.busType,
    required this.partitionStyle,
    required this.identityKind,
    required this.identityValue,
    required this.isReadOnly,
  });

  String get displayName =>
      model.isEmpty ? 'Physical disk $snapshotDiskNumber' : model;

  Map<String, dynamic> toJson() => {
    'snapshotDiskNumber': snapshotDiskNumber,
    'model': model,
    'sizeBytes': sizeBytes.toString(),
    'busType': busType,
    'partitionStyle': partitionStyle,
    'identityKind': identityKind,
    'identityValue': identityValue,
  };
}

class ExternalWindowsVolume {
  final BoundExternalDisk disk;
  final int partitionNumber;
  final BigInt partitionOffset;
  final String volumeGuidPath;
  final String? driveLetter;
  final String fileSystem;
  final String label;
  final BigInt sizeBytes;
  final List<BootTargetVolume> bootTargets;

  const ExternalWindowsVolume({
    required this.disk,
    required this.partitionNumber,
    required this.partitionOffset,
    required this.volumeGuidPath,
    required this.driveLetter,
    required this.fileSystem,
    required this.label,
    required this.sizeBytes,
    required this.bootTargets,
  });

  String get displayRoot => driveLetter ?? volumeGuidPath;

  String get displayName {
    final suffix = label.isEmpty ? '' : ' - $label';
    return '$displayRoot Windows$suffix';
  }

  Map<String, dynamic> toJson() => {
    'partitionNumber': partitionNumber,
    'partitionOffset': partitionOffset.toString(),
    'volumeGuidPath': volumeGuidPath,
  };
}

class BootTargetVolume {
  static const efiSystemPartitionGuid =
      '{C12A7328-F81F-11D2-BA4B-00A0C93EC93B}';

  final int diskNumber;
  final int partitionNumber;
  final BigInt partitionOffset;
  final String volumeGuidPath;
  final String? driveLetter;
  final String fileSystem;
  final String label;
  final BigInt sizeBytes;
  final BigInt? freeBytes;
  final String gptType;
  final bool isActive;
  final bool supportsUefi;
  final bool supportsBios;

  const BootTargetVolume({
    required this.diskNumber,
    required this.partitionNumber,
    required this.partitionOffset,
    required this.volumeGuidPath,
    required this.driveLetter,
    required this.fileSystem,
    required this.label,
    required this.sizeBytes,
    required this.freeBytes,
    required this.gptType,
    required this.isActive,
    required this.supportsUefi,
    required this.supportsBios,
  });

  bool supports(BootFirmware firmware) => switch (firmware) {
    BootFirmware.uefi => supportsUefi,
    BootFirmware.bios => supportsBios,
  };

  String get displayRoot => driveLetter ?? volumeGuidPath;

  String get displayName {
    final type = gptType.toUpperCase() == efiSystemPartitionGuid
        ? 'EFI System Partition'
        : isActive
        ? 'Active system partition'
        : 'Boot partition';
    return '$displayRoot - $type - $fileSystem';
  }

  Map<String, dynamic> toJson() => {
    'diskNumber': diskNumber,
    'partitionNumber': partitionNumber,
    'partitionOffset': partitionOffset.toString(),
    'volumeGuidPath': volumeGuidPath,
  };
}

class BootRepairSelection {
  final ExternalWindowsVolume windowsVolume;
  final BootTargetVolume bootTarget;
  final BootFirmware firmware;

  const BootRepairSelection({
    required this.windowsVolume,
    required this.bootTarget,
    required this.firmware,
  });

  Map<String, dynamic> toJson() => {
    'firmware': firmware.commandValue,
    'disk': windowsVolume.disk.toJson(),
    'windowsVolume': windowsVolume.toJson(),
    'bootTarget': bootTarget.toJson(),
  };
}

class BootRepairCheck {
  final String labelKey;
  final bool passed;
  final String detailKey;

  const BootRepairCheck({
    required this.labelKey,
    required this.passed,
    required this.detailKey,
  });
}

class BootRepairPreflight {
  final BootRepairSelection selection;
  final List<BootRepairCheck> checks;
  final List<String> warnings;
  final List<String> plannedActions;
  final String commandPreview;
  final DateTime completedAt;

  const BootRepairPreflight({
    required this.selection,
    required this.checks,
    required this.warnings,
    required this.plannedActions,
    required this.commandPreview,
    required this.completedAt,
  });

  bool get canExecute =>
      checks.isNotEmpty && checks.every((check) => check.passed);
}

class BootRepairVerification {
  final bool efiFallbackRequired;
  final bool bcdStoreExists;
  final bool bcdStoreReadable;
  final bool bootManagerExists;
  final bool efiFallbackExists;
  final bool efiFallbackMatchesBootManager;
  final bool defaultOsLoaderExists;
  final bool defaultOsLoaderDeviceMatches;
  final bool defaultOsLoaderOsDeviceMatches;
  final String bcdPath;
  final String? bootManagerPath;
  final String? efiFallbackPath;
  final String? bootManagerSha256;
  final String? efiFallbackSha256;
  final String? defaultOsLoaderDevice;
  final String? defaultOsLoaderOsDevice;

  const BootRepairVerification({
    required this.efiFallbackRequired,
    required this.bcdStoreExists,
    required this.bcdStoreReadable,
    required this.bootManagerExists,
    required this.efiFallbackExists,
    this.efiFallbackMatchesBootManager = false,
    this.defaultOsLoaderExists = false,
    this.defaultOsLoaderDeviceMatches = false,
    this.defaultOsLoaderOsDeviceMatches = false,
    required this.bcdPath,
    required this.bootManagerPath,
    required this.efiFallbackPath,
    this.bootManagerSha256,
    required this.efiFallbackSha256,
    this.defaultOsLoaderDevice,
    this.defaultOsLoaderOsDevice,
  });

  factory BootRepairVerification.fromJson(Map<String, dynamic> json) {
    return BootRepairVerification(
      efiFallbackRequired: json['efiFallbackRequired'] == true,
      bcdStoreExists: json['bcdStoreExists'] == true,
      bcdStoreReadable: json['bcdStoreReadable'] == true,
      bootManagerExists: json['bootManagerExists'] == true,
      efiFallbackExists: json['efiFallbackExists'] == true,
      efiFallbackMatchesBootManager:
          json['efiFallbackMatchesBootManager'] == true,
      defaultOsLoaderExists: json['defaultOsLoaderExists'] == true,
      defaultOsLoaderDeviceMatches:
          json['defaultOsLoaderDeviceMatches'] == true,
      defaultOsLoaderOsDeviceMatches:
          json['defaultOsLoaderOsDeviceMatches'] == true,
      bcdPath: json['bcdPath']?.toString() ?? '',
      bootManagerPath: _nullableJsonString(json['bootManagerPath']),
      efiFallbackPath: _nullableJsonString(json['efiFallbackPath']),
      bootManagerSha256: _nullableJsonString(json['bootManagerSha256']),
      efiFallbackSha256: _nullableJsonString(json['efiFallbackSha256']),
      defaultOsLoaderDevice: _nullableJsonString(json['defaultOsLoaderDevice']),
      defaultOsLoaderOsDevice: _nullableJsonString(
        json['defaultOsLoaderOsDevice'],
      ),
    );
  }

  bool get passed =>
      bcdStoreExists &&
      bcdStoreReadable &&
      bootManagerExists &&
      defaultOsLoaderExists &&
      defaultOsLoaderDeviceMatches &&
      defaultOsLoaderOsDeviceMatches &&
      efiFallbackContentVerified;

  bool get efiFallbackContentVerified {
    if (!efiFallbackRequired) return true;
    final managerHash = bootManagerSha256?.trim().toUpperCase();
    final fallbackHash = efiFallbackSha256?.trim().toUpperCase();
    return efiFallbackExists &&
        efiFallbackMatchesBootManager &&
        managerHash != null &&
        managerHash.isNotEmpty &&
        managerHash == fallbackHash;
  }
}

enum BootRepairRollbackStatus { notRequired, succeeded, failed }

class BootRepairResult {
  final bool success;
  final bool elevationCancelled;
  final String messageKey;
  final String backupPath;
  final bool existingBcdBackedUp;
  final bool rollbackAttempted;
  final bool rollbackSucceeded;
  final bool operationCancelled;
  final bool operationTimedOut;
  final BootRepairVerification? verification;
  final String logPath;
  final String logText;
  final DateTime completedAt;

  const BootRepairResult({
    required this.success,
    required this.elevationCancelled,
    required this.messageKey,
    required this.backupPath,
    required this.existingBcdBackedUp,
    this.rollbackAttempted = false,
    this.rollbackSucceeded = false,
    this.operationCancelled = false,
    this.operationTimedOut = false,
    required this.verification,
    required this.logPath,
    required this.logText,
    required this.completedAt,
  });

  factory BootRepairResult.fromResponse({
    required Map<String, dynamic> response,
    required String defaultBackupPath,
    required String logPath,
    required String logText,
    required DateTime completedAt,
  }) {
    final verificationRaw = response['verification'];
    final verification = verificationRaw is Map
        ? BootRepairVerification.fromJson(
            Map<String, dynamic>.from(verificationRaw),
          )
        : null;
    final elevationCancelled = response['elevationCancelled'] == true;
    final rollbackAttempted = response['rollbackAttempted'] == true;
    final rollbackSucceeded =
        rollbackAttempted && response['rollbackSucceeded'] == true;
    final operationCancelled = response['operationCancelled'] == true;
    final operationTimedOut = response['operationTimedOut'] == true;
    final success =
        !elevationCancelled &&
        !operationCancelled &&
        !operationTimedOut &&
        !rollbackAttempted &&
        response['ok'] == true &&
        verification?.passed == true;
    return BootRepairResult(
      success: success,
      elevationCancelled: elevationCancelled,
      messageKey: elevationCancelled
          ? 'boot_repair_result_cancelled'
          : success
          ? 'boot_repair_result_success'
          : 'boot_repair_result_failed',
      backupPath: response['backupPath']?.toString() ?? defaultBackupPath,
      existingBcdBackedUp: response['existingBcdBackedUp'] == true,
      rollbackAttempted: rollbackAttempted,
      rollbackSucceeded: rollbackSucceeded,
      operationCancelled: operationCancelled,
      operationTimedOut: operationTimedOut,
      verification: verification,
      logPath: logPath,
      logText: logText,
      completedAt: completedAt,
    );
  }

  BootRepairRollbackStatus get rollbackStatus {
    if (!rollbackAttempted) return BootRepairRollbackStatus.notRequired;
    return rollbackSucceeded
        ? BootRepairRollbackStatus.succeeded
        : BootRepairRollbackStatus.failed;
  }
}

String? _nullableJsonString(dynamic value) {
  if (value == null) return null;
  final text = value.toString().trim();
  return text.isEmpty ? null : text;
}
