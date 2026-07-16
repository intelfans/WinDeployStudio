import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:win_deploy_studio/core/services/disk_safety_service.dart';

void main() {
  const base = DiskInfo(
    diskNumber: 4,
    model: 'Portable SSD',
    friendlyName: 'Portable SSD USB Device',
    sizeBytes: 1000204886016,
    sizeFormatted: '931 GB',
    serialNumber: 'SERIAL-1234',
    uniqueId: 'USB-UNIQUE-1234',
    devicePath: r'\\?\PhysicalDrive4',
    busType: 'USB',
    isRemovable: true,
  );

  test('physical identity follows a reliable serial across disk numbers', () {
    const current = DiskInfo(
      diskNumber: 7,
      model: 'Portable SSD',
      friendlyName: 'Portable SSD USB Device',
      sizeBytes: 1000204886016,
      sizeFormatted: '931 GB',
      serialNumber: ' serial-1234 ',
      uniqueId: 'CHANGED-BUT-LOWER-PRIORITY',
      devicePath: r'\\?\PhysicalDrive7',
      busType: 'USB',
      isRemovable: true,
    );

    expect(base.hasSamePhysicalIdentity(current), isTrue);
    expect(current.hasSamePhysicalIdentity(base), isTrue);
  });

  test('physical identity rejects changed capacity, model, bus, or serial', () {
    expect(
      base.hasSamePhysicalIdentity(
        const DiskInfo(
          diskNumber: 4,
          model: 'Portable SSD',
          friendlyName: 'Portable SSD',
          sizeBytes: 1000204886016,
          sizeFormatted: '931 GB',
          serialNumber: 'OTHER-9999',
          busType: 'USB',
        ),
      ),
      isFalse,
    );
    expect(
      base.hasSamePhysicalIdentity(
        const DiskInfo(
          diskNumber: 4,
          model: 'Portable SSD',
          friendlyName: 'Portable SSD',
          sizeBytes: 1000204886015,
          sizeFormatted: '931 GB',
          serialNumber: 'SERIAL-1234',
          busType: 'USB',
        ),
      ),
      isFalse,
    );
  });

  test('physical identity fails closed without a reliable hardware value', () {
    const unknown = DiskInfo(
      diskNumber: 4,
      model: 'USB Disk',
      friendlyName: 'USB Disk',
      sizeBytes: 64000000000,
      sizeFormatted: '59 GB',
      serialNumber: 'N/A',
      uniqueId: '0',
      devicePath: '',
      busType: 'USB',
      isRemovable: true,
    );

    expect(unknown.hasSamePhysicalIdentity(unknown), isFalse);
  });

  test(
    'guarded Storage initialization clears before initializing and confirms completion',
    () {
      final source = File(
        'lib/core/services/disk_safety_service.dart',
      ).readAsStringSync();
      final scriptStart = source.indexOf(
        'static const _guardedDiskInitializationScript',
      );
      final scriptEnd = source.indexOf("''';", scriptStart);
      final methodStart = source.indexOf(
        'Future<ProcessResult> initializeDiskPartitionStyle',
      );
      final methodEnd = source.indexOf(
        'Future<SafetyCheckResult> _checkCurrentDiskSafety',
        methodStart,
      );

      expect(scriptStart, greaterThanOrEqualTo(0));
      expect(scriptEnd, greaterThan(scriptStart));
      expect(methodStart, greaterThan(scriptEnd));
      expect(methodEnd, greaterThan(methodStart));

      final script = source.substring(scriptStart, scriptEnd);
      final initializer = source.substring(methodStart, methodEnd);
      final clear = script.indexOf('Clear-Disk');
      final initialize = script.indexOf('Initialize-Disk');
      final completion = script.indexOf('WDS_DISK_INITIALIZED');

      expect(script, contains(r'Assert-TargetDisk $true $true'));
      expect(script, contains(r'Assert-TargetDisk $false $false'));
      expect(clear, greaterThanOrEqualTo(0));
      expect(initialize, greaterThan(clear));
      expect(completion, greaterThan(initialize));
      expect(
        script.indexOf(r'Assert-TargetDisk $false $false'),
        greaterThan(clear),
      );
      expect(
        script.indexOf(r'Assert-TargetDisk $false $false'),
        lessThan(initialize),
      );
      expect(initializer, contains('checkDiskSafety(disk)'));
      expect(initializer, contains('_guardedDiskInitializationScript'));
      expect(initializer, contains("stdout.contains('WDS_DISK_INITIALIZED')"));
    },
  );
}
