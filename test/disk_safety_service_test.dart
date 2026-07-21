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

  test(
    'physical identity falls back when a selected-disk refresh omits serial',
    () {
      const current = DiskInfo(
        diskNumber: 4,
        model: 'Portable SSD',
        friendlyName: 'Portable SSD USB Device',
        sizeBytes: 1000204886016,
        sizeFormatted: '931 GB',
        uniqueId: 'USB-UNIQUE-1234',
        devicePath: r'\\?\PhysicalDrive4',
        busType: 'USB',
        isRemovable: true,
      );

      expect(base.hasSamePhysicalIdentity(current), isTrue);
      expect(current.hasSamePhysicalIdentity(base), isTrue);
    },
  );

  test('selected-disk safety query avoids a full physical-disk inventory', () {
    final source = File(
      'lib/core/services/disk_safety_service.dart',
    ).readAsStringSync();
    final scriptStart = source.indexOf(
      'static const String _getDiskByNumberScript',
    );
    final scriptEnd = source.indexOf("''';", scriptStart);

    expect(scriptStart, greaterThanOrEqualTo(0));
    expect(scriptEnd, greaterThan(scriptStart));
    final script = source.substring(scriptStart, scriptEnd);
    expect(script, contains(r'Get-Disk -Number $targetNumber'));
    expect(script, isNot(contains('Get-PhysicalDisk')));
    expect(script, isNot(contains('Get-Partition')));
    expect(script, contains('DriveLetters   = @()'));
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

  test('preferred drive letter selects the largest mounted data partition', () {
    const disk = DiskInfo(
      diskNumber: 8,
      model: 'USB SSD',
      friendlyName: 'USB SSD',
      sizeBytes: 128000000000,
      sizeFormatted: '119 GB',
      driveLetters: ['S', 'E'],
      partitions: [
        DiskPartition(
          type: 'System',
          sizeBytes: 268435456,
          driveLetter: 'S',
          isSystem: true,
        ),
        DiskPartition(type: 'Basic', sizeBytes: 127000000000, driveLetter: 'E'),
      ],
    );

    expect(disk.preferredDriveLetter, 'E');
  });

  test('preferred drive letter accepts native volume paths', () {
    const disk = DiskInfo(
      diskNumber: 11,
      model: 'USB SSD',
      friendlyName: 'USB SSD',
      sizeBytes: 64000000000,
      sizeFormatted: '59 GB',
      driveLetters: ['E:\\'],
    );

    expect(disk.preferredDriveLetter, 'E');
  });

  test(
    'preferred drive letter avoids an EFI volume without IsSystem metadata',
    () {
      const disk = DiskInfo(
        diskNumber: 10,
        model: 'Portable Windows',
        friendlyName: 'Portable Windows',
        sizeBytes: 128000000000,
        sizeFormatted: '119 GB',
        driveLetters: ['S', 'E'],
        partitions: [
          DiskPartition(type: 'System', sizeBytes: 268435456, driveLetter: 'S'),
          DiskPartition(
            type: 'Basic',
            sizeBytes: 127000000000,
            driveLetter: 'E',
          ),
        ],
      );

      expect(disk.preferredDriveLetter, 'E');
    },
  );

  test(
    'preferred drive letter falls back when partition metadata is absent',
    () {
      const disk = DiskInfo(
        diskNumber: 9,
        model: 'USB Disk',
        friendlyName: 'USB Disk',
        sizeBytes: 64000000000,
        sizeFormatted: '59 GB',
        driveLetters: ['f'],
      );

      expect(disk.preferredDriveLetter, 'F');
    },
  );

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
      final postClearPartitions = script.indexOf('Get-Partition', clear);
      final zeroPartitionGuard = script.indexOf(
        'Target disk still has partitions after it was cleared.',
      );
      final rawBranch = RegExp(
        r"if\s*\(\s*\$[A-Za-z][A-Za-z0-9_]*\s*-eq\s*'RAW'\s*\)",
      ).firstMatch(script);
      final mismatchBranch = RegExp(
        r'(?:elseif|else\s+if)\s*\([^)]*-ne\s*\$targetStyle',
      ).firstMatch(script);
      final finalStyleValidation = script.lastIndexOf(
        'PartitionStyle.ToString().ToUpperInvariant() -ne \$targetStyle',
      );
      final finalPartitionCheck = script.lastIndexOf('Get-Partition');

      expect(script, contains(r'Assert-TargetDisk $true $true'));
      expect(clear, greaterThanOrEqualTo(0));
      expect(postClearPartitions, greaterThan(clear));
      expect(zeroPartitionGuard, greaterThan(postClearPartitions));
      expect(rawBranch, isNotNull);
      expect(mismatchBranch, isNotNull);
      expect(zeroPartitionGuard, lessThan(rawBranch!.start));
      expect(rawBranch.start, greaterThan(postClearPartitions));
      expect(mismatchBranch!.start, greaterThan(postClearPartitions));

      final rawBranchBody = script.substring(
        rawBranch.start,
        mismatchBranch.start,
      );
      final mismatchBranchBody = script.substring(
        mismatchBranch.start,
        finalStyleValidation,
      );
      expect(rawBranchBody, contains('Initialize-Disk'));
      expect(mismatchBranchBody.toLowerCase(), contains('convert'));
      expect(mismatchBranchBody, contains(r'$targetStyle'));
      expect(initialize, greaterThanOrEqualTo(0));
      expect(finalStyleValidation, greaterThan(mismatchBranch.start));
      expect(finalPartitionCheck, greaterThan(finalStyleValidation));
      expect(completion, greaterThan(finalPartitionCheck));
      expect(initializer, contains('checkDiskSafety(disk)'));
      expect(initializer, contains('_guardedDiskInitializationScript'));
      expect(initializer, contains("stdout.contains('WDS_DISK_INITIALIZED')"));
    },
  );
}
