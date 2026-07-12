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
}
