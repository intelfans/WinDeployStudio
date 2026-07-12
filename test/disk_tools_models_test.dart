import 'package:flutter_test/flutter_test.dart';
import 'package:win_deploy_studio/features/disk_tools/models/boot_repair_models.dart';
import 'package:win_deploy_studio/features/disk_tools/models/disk_diagnostic_models.dart';

void main() {
  group('disk diagnostics', () {
    test('unavailable health remains explicitly unavailable', () {
      const health = DiagnosticValue<String>.unavailable(
        unavailableReason: 'The storage bridge returned no health state.',
      );

      expect(health.isAvailable, isFalse);
      expect(health.value, isNull);
      expect(health.unavailableReason, contains('no health state'));
    });

    test(
      'external classification requires an external bus or removable flag',
      () {
        final internal = _diagnosticReport(
          bus: const DiagnosticValue.available('NVMe', source: 'CIM'),
        );
        final usb = _diagnosticReport(
          bus: const DiagnosticValue.available('USB', source: 'CIM'),
        );
        final removable = _diagnosticReport(
          bus: const DiagnosticValue.available('SATA', source: 'CIM'),
          removable: true,
        );

        expect(internal.isExternal, isFalse);
        expect(usb.isExternal, isTrue);
        expect(removable.isExternal, isTrue);
      },
    );

    test('formats large counters without losing integer precision', () {
      expect(
        formatDiagnosticInteger(BigInt.parse('1234567890123456789')),
        '1,234,567,890,123,456,789',
      );
      expect(
        formatDiagnosticBytes(BigInt.from(1024 * 1024 * 5)),
        '5.0 MiB (5,242,880 B)',
      );
    });
  });

  group('boot repair', () {
    test('firmware compatibility is explicit per target', () {
      final target = _bootTarget(supportsUefi: true, supportsBios: false);

      expect(target.supports(BootFirmware.uefi), isTrue);
      expect(target.supports(BootFirmware.bios), isFalse);
    });

    test('selection serializes immutable disk and partition bindings', () {
      final disk = _boundDisk();
      final target = _bootTarget(supportsUefi: true, supportsBios: false);
      final volume = ExternalWindowsVolume(
        disk: disk,
        partitionNumber: 3,
        partitionOffset: BigInt.from(314572800),
        volumeGuidPath: r'\\?\Volume{windows}\',
        driveLetter: 'W:',
        fileSystem: 'NTFS',
        label: 'WINDOWS',
        sizeBytes: BigInt.from(100000000000),
        bootTargets: [target],
      );
      final selection = BootRepairSelection(
        windowsVolume: volume,
        bootTarget: target,
        firmware: BootFirmware.uefi,
      );

      final json = selection.toJson();

      expect(json['firmware'], 'UEFI');
      expect((json['disk'] as Map)['identityKind'], 'serialNumber');
      expect((json['disk'] as Map)['identityValue'], 'SERIAL-1234');
      expect((json['windowsVolume'] as Map)['partitionOffset'], '314572800');
      expect((json['bootTarget'] as Map)['partitionOffset'], '1048576');
    });

    test('preflight requires every check to pass', () {
      final selection = _selection();
      final allPassed = BootRepairPreflight(
        selection: selection,
        checks: const [
          BootRepairCheck(labelKey: 'disk', passed: true, detailKey: 'passed'),
          BootRepairCheck(
            labelKey: 'volume',
            passed: true,
            detailKey: 'passed',
          ),
        ],
        warnings: const [],
        plannedActions: const [],
        commandPreview: 'bcdboot <bound>',
        completedAt: DateTime.utc(2026, 7, 12),
      );
      final failed = BootRepairPreflight(
        selection: selection,
        checks: const [
          BootRepairCheck(
            labelKey: 'disk',
            passed: false,
            detailKey: 'changed',
          ),
        ],
        warnings: const [],
        plannedActions: const [],
        commandPreview: 'bcdboot <bound>',
        completedAt: DateTime.utc(2026, 7, 12),
      );

      expect(allPassed.canExecute, isTrue);
      expect(failed.canExecute, isFalse);
    });

    test('UEFI verification requires a fallback boot file', () {
      const missingFallback = BootRepairVerification(
        efiFallbackRequired: true,
        bcdStoreExists: true,
        bcdStoreReadable: true,
        bootManagerExists: true,
        efiFallbackExists: false,
        efiFallbackMatchesBootManager: false,
        defaultOsLoaderExists: true,
        defaultOsLoaderDeviceMatches: true,
        defaultOsLoaderOsDeviceMatches: true,
        bcdPath: r'S:\EFI\Microsoft\Boot\BCD',
        bootManagerPath: r'S:\EFI\Microsoft\Boot\bootmgfw.efi',
        efiFallbackPath: null,
        bootManagerSha256: 'BOOT-HASH',
        efiFallbackSha256: null,
        defaultOsLoaderDevice: 'partition=W:',
        defaultOsLoaderOsDevice: 'partition=W:',
      );
      const biosVerification = BootRepairVerification(
        efiFallbackRequired: false,
        bcdStoreExists: true,
        bcdStoreReadable: true,
        bootManagerExists: true,
        efiFallbackExists: false,
        efiFallbackMatchesBootManager: true,
        defaultOsLoaderExists: true,
        defaultOsLoaderDeviceMatches: true,
        defaultOsLoaderOsDeviceMatches: true,
        bcdPath: r'S:\Boot\BCD',
        bootManagerPath: r'S:\bootmgr',
        efiFallbackPath: null,
        bootManagerSha256: 'BOOT-HASH',
        efiFallbackSha256: null,
        defaultOsLoaderDevice: 'partition=W:',
        defaultOsLoaderOsDevice: 'partition=W:',
      );

      expect(missingFallback.passed, isFalse);
      expect(biosVerification.passed, isTrue);
    });

    test('verification rejects a default loader bound to another volume', () {
      final verification = BootRepairVerification.fromJson({
        ..._passingVerificationJson(),
        'defaultOsLoaderOsDeviceMatches': false,
        'defaultOsLoaderOsDevice': 'partition=C:',
      });

      expect(verification.defaultOsLoaderDeviceMatches, isTrue);
      expect(verification.defaultOsLoaderOsDeviceMatches, isFalse);
      expect(verification.passed, isFalse);
    });

    test('verification compares EFI hashes instead of trusting its flag', () {
      final verification = BootRepairVerification.fromJson({
        ..._passingVerificationJson(),
        'efiFallbackMatchesBootManager': true,
        'bootManagerSha256': 'HASH-A',
        'efiFallbackSha256': 'HASH-B',
      });

      expect(verification.efiFallbackMatchesBootManager, isTrue);
      expect(verification.efiFallbackContentVerified, isFalse);
      expect(verification.passed, isFalse);
    });

    test('failed result preserves backup and successful rollback state', () {
      final result = BootRepairResult.fromResponse(
        response: {
          'ok': false,
          'backupPath': r'C:\Backups\repair-1',
          'existingBcdBackedUp': true,
          'rollbackAttempted': true,
          'rollbackSucceeded': true,
          'verification': _passingVerificationJson(),
        },
        defaultBackupPath: r'C:\Backups\fallback',
        logPath: r'C:\Logs\repair.log',
        logText: 'failed, then restored',
        completedAt: DateTime.utc(2026, 7, 12),
      );

      expect(result.success, isFalse);
      expect(result.existingBcdBackedUp, isTrue);
      expect(result.rollbackAttempted, isTrue);
      expect(result.rollbackSucceeded, isTrue);
      expect(result.rollbackStatus, BootRepairRollbackStatus.succeeded);
      expect(result.backupPath, r'C:\Backups\repair-1');
    });

    test('response parser requires every post-repair verification', () {
      final result = BootRepairResult.fromResponse(
        response: {
          'ok': true,
          'existingBcdBackedUp': false,
          'rollbackAttempted': false,
          'rollbackSucceeded': false,
          'verification': {
            ..._passingVerificationJson(),
            'efiFallbackMatchesBootManager': false,
          },
        },
        defaultBackupPath: r'C:\Backups\repair-2',
        logPath: r'C:\Logs\repair.log',
        logText: '',
        completedAt: DateTime.utc(2026, 7, 12),
      );

      expect(result.verification, isNotNull);
      expect(result.verification!.passed, isFalse);
      expect(result.success, isFalse);
      expect(result.rollbackStatus, BootRepairRollbackStatus.notRequired);
    });

    test('cancelled execution cannot be promoted by a success payload', () {
      final result = BootRepairResult.fromResponse(
        response: {
          'ok': true,
          'operationCancelled': true,
          'existingBcdBackedUp': true,
          'rollbackAttempted': true,
          'rollbackSucceeded': true,
          'verification': _passingVerificationJson(),
        },
        defaultBackupPath: r'C:\Backups\repair-3',
        logPath: r'C:\Logs\repair.log',
        logText: 'cancelled and restored',
        completedAt: DateTime.utc(2026, 7, 12),
      );

      expect(result.operationCancelled, isTrue);
      expect(result.success, isFalse);
      expect(result.existingBcdBackedUp, isTrue);
      expect(result.rollbackStatus, BootRepairRollbackStatus.succeeded);
    });
  });
}

Map<String, dynamic> _passingVerificationJson() => {
  'efiFallbackRequired': true,
  'bcdStoreExists': true,
  'bcdStoreReadable': true,
  'bootManagerExists': true,
  'efiFallbackExists': true,
  'efiFallbackMatchesBootManager': true,
  'defaultOsLoaderExists': true,
  'defaultOsLoaderDeviceMatches': true,
  'defaultOsLoaderOsDeviceMatches': true,
  'bcdPath': r'S:\EFI\Microsoft\Boot\BCD',
  'bootManagerPath': r'S:\EFI\Microsoft\Boot\bootmgfw.efi',
  'efiFallbackPath': r'S:\EFI\Boot\bootx64.efi',
  'bootManagerSha256': 'SAME-HASH',
  'efiFallbackSha256': 'SAME-HASH',
  'defaultOsLoaderDevice': 'partition=W:',
  'defaultOsLoaderOsDevice': 'partition=W:',
};

DiskDiagnosticReport _diagnosticReport({
  required DiagnosticValue<String> bus,
  bool removable = false,
}) {
  const unavailableString = DiagnosticValue<String>.unavailable(
    unavailableReason: 'Unavailable',
  );
  const unavailableInt = DiagnosticValue<int>.unavailable(
    unavailableReason: 'Unavailable',
  );
  const unavailableBigInt = DiagnosticValue<BigInt>.unavailable(
    unavailableReason: 'Unavailable',
  );
  return DiskDiagnosticReport(
    diskNumber: 0,
    model: const DiagnosticValue.available('Disk', source: 'CIM'),
    sizeBytes: DiagnosticValue.available(BigInt.from(1000), source: 'CIM'),
    serialNumber: unavailableString,
    uniqueId: unavailableString,
    busType: bus,
    vendorId: unavailableString,
    productId: unavailableString,
    health: unavailableString,
    temperatureCelsius: unavailableInt,
    wearPercent: unavailableInt,
    estimatedRemainingLifePercent: unavailableInt,
    readErrorsCorrected: unavailableBigInt,
    readErrorsUncorrected: unavailableBigInt,
    readErrorsTotal: unavailableBigInt,
    writeErrorsCorrected: unavailableBigInt,
    writeErrorsUncorrected: unavailableBigInt,
    writeErrorsTotal: unavailableBigInt,
    powerOnHours: unavailableBigInt,
    hostReadBytes: unavailableBigInt,
    hostWrittenBytes: unavailableBigInt,
    hostReadCommands: unavailableBigInt,
    hostWriteCommands: unavailableBigInt,
    mediaAndDataIntegrityErrors: unavailableBigInt,
    firmwareVersion: unavailableString,
    mediaType: unavailableString,
    partitionStyle: unavailableString,
    operationalStatus: unavailableString,
    pnpDeviceId: unavailableString,
    devicePath: unavailableString,
    driveLetters: const [],
    isSystem: false,
    isBoot: false,
    isOffline: false,
    isReadOnly: false,
    isRemovable: removable,
  );
}

BoundExternalDisk _boundDisk() => BoundExternalDisk(
  snapshotDiskNumber: 7,
  model: 'Portable SSD',
  sizeBytes: BigInt.from(512110190592),
  serialNumber: 'SERIAL-1234',
  uniqueId: 'UNIQUE-1234',
  devicePath: r'\\?\PhysicalDrive7',
  pnpDeviceId: r'USBSTOR\VID_1234&PID_5678',
  busType: 'USB',
  partitionStyle: 'GPT',
  identityKind: 'serialNumber',
  identityValue: 'SERIAL-1234',
  isReadOnly: false,
);

BootTargetVolume _bootTarget({
  required bool supportsUefi,
  required bool supportsBios,
}) => BootTargetVolume(
  diskNumber: 7,
  partitionNumber: 1,
  partitionOffset: BigInt.from(1048576),
  volumeGuidPath: r'\\?\Volume{efi}\',
  driveLetter: 'S:',
  fileSystem: 'FAT32',
  label: 'WDS_EFI',
  sizeBytes: BigInt.from(314572800),
  freeBytes: BigInt.from(200000000),
  gptType: BootTargetVolume.efiSystemPartitionGuid,
  isActive: false,
  supportsUefi: supportsUefi,
  supportsBios: supportsBios,
);

BootRepairSelection _selection() {
  final disk = _boundDisk();
  final target = _bootTarget(supportsUefi: true, supportsBios: false);
  return BootRepairSelection(
    windowsVolume: ExternalWindowsVolume(
      disk: disk,
      partitionNumber: 3,
      partitionOffset: BigInt.from(314572800),
      volumeGuidPath: r'\\?\Volume{windows}\',
      driveLetter: 'W:',
      fileSystem: 'NTFS',
      label: 'WINDOWS',
      sizeBytes: BigInt.from(100000000000),
      bootTargets: [target],
    ),
    bootTarget: target,
    firmware: BootFirmware.uefi,
  );
}
