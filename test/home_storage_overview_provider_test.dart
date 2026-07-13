import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:win_deploy_studio/core/services/disk_safety_service.dart';
import 'package:win_deploy_studio/features/home/models/home_storage_overview.dart';
import 'package:win_deploy_studio/features/home/providers/home_storage_overview_provider.dart';

void main() {
  const firstDisk = DiskInfo(
    diskNumber: 1,
    model: 'Fast USB SSD',
    friendlyName: 'Portable SSD',
    sizeBytes: 1_000_204_886_016,
    sizeFormatted: '931 GB',
    busType: 'USB',
    isRemovable: true,
    driveLetters: ['E'],
  );
  const secondDisk = DiskInfo(
    diskNumber: 4,
    model: 'USB Flash Disk',
    friendlyName: 'USB Flash Disk',
    sizeBytes: 64_000_000_000,
    sizeFormatted: '59.6 GB',
    busType: 'USB',
    isRemovable: true,
    driveLetters: ['F'],
  );

  test('overview retains every external device in a stable order', () {
    final overview = HomeStorageOverview.fromDisks([secondDisk, firstDisk]);

    expect(overview.externalDeviceCount, 2);
    expect(overview.hasExternalDevice, isTrue);
    expect(overview.isAvailable, isTrue);
    expect(overview.devices.map((device) => device.diskNumber), [1, 4]);
    expect(overview.devices.map((device) => device.name), [
      'Portable SSD',
      'USB Flash Disk',
    ]);
    expect(overview.primaryDevice?.diskNumber, 1);
    expect(overview.primaryDevice?.name, 'Portable SSD');
    expect(overview.primaryDevice?.capacityBytes, 1_000_204_886_016);
    expect(overview.primaryDevice?.capacityLabel, '931 GB');
    expect(overview.primaryDevice?.busType, 'USB');
    expect(overview.primaryDevice?.driveLetters, ['E']);
  });

  test('overview ignores offline disks and reports no available device', () {
    const offlineDisk = DiskInfo(
      diskNumber: 2,
      model: 'Offline USB disk',
      friendlyName: 'Offline USB disk',
      sizeBytes: 32_000_000_000,
      sizeFormatted: '29.8 GB',
      busType: 'USB',
      isRemovable: true,
      isOffline: true,
    );

    final overview = HomeStorageOverview.fromDisks([offlineDisk]);

    expect(overview.externalDeviceCount, 0);
    expect(overview.hasExternalDevice, isFalse);
    expect(overview.isAvailable, isFalse);
    expect(overview.primaryDevice, isNull);
  });

  test('provider uses the safe removable-disk enumeration result', () async {
    final container = ProviderContainer(
      overrides: [
        diskSafetyServiceProvider.overrideWithValue(
          _FakeDiskSafetyService([secondDisk, firstDisk]),
        ),
      ],
    );
    addTearDown(container.dispose);

    final overview = await container.read(homeStorageOverviewProvider.future);

    expect(overview.externalDeviceCount, 2);
    expect(overview.devices, hasLength(2));
    expect(overview.primaryDevice?.name, 'Portable SSD');
  });
}

class _FakeDiskSafetyService extends DiskSafetyService {
  final List<DiskInfo> disks;

  _FakeDiskSafetyService(this.disks);

  @override
  Future<List<DiskInfo>> getRemovableDisks() async => disks;
}
