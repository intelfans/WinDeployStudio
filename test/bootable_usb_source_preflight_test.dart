import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:win_deploy_studio/core/services/bootable_usb_service.dart';
import 'package:win_deploy_studio/core/services/disk_safety_service.dart';
import 'package:win_deploy_studio/core/services/linux_togo_image_preflight.dart';
import 'package:win_deploy_studio/core/services/windows_iso_preflight.dart';
import 'package:win_deploy_studio/features/deployment/models/deployment_plan.dart';

void main() {
  test('only non-loopback UNC ISO sources bypass local disk resolution', () {
    expect(
      BootableUsbService.isRemoteInstallMediaUncPathForTesting(
        r'\\fileserver\images\win11.iso',
      ),
      isTrue,
    );
    expect(
      BootableUsbService.isRemoteInstallMediaUncPathForTesting(
        r'\\localhost\images\win11.iso',
      ),
      isFalse,
    );
    expect(
      BootableUsbService.isRemoteInstallMediaUncPathForTesting(
        r'\\127.0.0.1\images\win11.iso',
      ),
      isFalse,
    );
    expect(
      BootableUsbService.isRemoteInstallMediaUncPathForTesting(
        r'C:\images\win11.iso',
      ),
      isFalse,
    );
  });

  test('extracts a normalized local source drive for fast disk binding', () {
    expect(
      BootableUsbService.windowsDriveRootForTesting(
        r'd:\ISO\Windows\Windows 8.1.iso',
      ),
      'D:',
    );
    expect(
      BootableUsbService.windowsDriveRootForTesting(r'\\server\share\win.iso'),
      isNull,
    );
  });

  test(
    'Windows creation rejects a non-Windows source before disk access',
    () async {
      final safety = _CountingDiskSafetyService();
      final container = ProviderContainer(
        overrides: [
          diskSafetyServiceProvider.overrideWithValue(safety),
          windowsIsoPreflightProvider.overrideWithValue(
            _StaticWindowsIsoPreflight(
              const WindowsIsoLayoutInspection.invalid('Linux layout'),
            ),
          ),
        ],
      );
      addTearDown(container.dispose);
      final updates = <CreateProgress>[];

      final created = await container
          .read(bootableUsbServiceProvider)
          .createBootableUsb(
            disk: _disk,
            isoPath: r'C:\images\ubuntu.iso',
            deploymentPlan: const DeploymentPlan(
              platform: DeploymentPlatform.windows,
              purpose: DeploymentPurpose.installMedia,
              imagePath: r'C:\images\ubuntu.iso',
            ),
            onProgress: updates.add,
          );

      expect(created, isFalse);
      expect(safety.checkCalls, 0);
      expect(updates.single.message, 'creator_invalid_windows_iso');
    },
  );

  test('preflight failures use their specific localized message key', () {
    final source = File(
      'lib/core/services/bootable_usb_service.dart',
    ).readAsStringSync();
    final failureStart = source.indexOf('if (!mediaPreflight.success)');
    final failureEnd = source.indexOf('final logCenter', failureStart);
    expect(failureStart, greaterThanOrEqualTo(0));
    expect(failureEnd, greaterThan(failureStart));
    final failureFlow = source.substring(failureStart, failureEnd);

    expect(failureFlow, contains('mediaPreflight.messageKey'));
    expect(failureFlow, contains('await saveLogToFile()'));
    expect(failureFlow, isNot(contains("error: 'i18n:")));
  });

  test('Linux creation rejects a Windows source before disk access', () async {
    final safety = _CountingDiskSafetyService();
    final container = ProviderContainer(
      overrides: [
        diskSafetyServiceProvider.overrideWithValue(safety),
        windowsIsoPreflightProvider.overrideWithValue(
          _StaticWindowsIsoPreflight(
            const WindowsIsoLayoutInspection.valid(
              imageFormat: WindowsInstallImageFormat.wim,
              imagePath: r'X:\sources\install.wim',
            ),
          ),
        ),
      ],
    );
    addTearDown(container.dispose);
    final updates = <CreateProgress>[];

    final created = await container
        .read(bootableUsbServiceProvider)
        .createLinuxIsoUsb(
          disk: _disk,
          isoPath: r'C:\images\win11.iso',
          kind: LinuxUsbKind.installMedia,
          deploymentPlan: const DeploymentPlan(
            platform: DeploymentPlatform.linux,
            purpose: DeploymentPurpose.installMedia,
            imagePath: r'C:\images\win11.iso',
          ),
          onProgress: updates.add,
        );

    expect(created, isFalse);
    expect(safety.checkCalls, 0);
    expect(updates.single.message, 'creator_windows_iso_in_linux_mode');
  });

  test('Linux To Go rejects a Windows source before disk access', () async {
    final safety = _CountingDiskSafetyService();
    final container = ProviderContainer(
      overrides: [
        diskSafetyServiceProvider.overrideWithValue(safety),
        windowsIsoPreflightProvider.overrideWithValue(
          _StaticWindowsIsoPreflight(
            const WindowsIsoLayoutInspection.valid(
              imageFormat: WindowsInstallImageFormat.esd,
              imagePath: r'X:\sources\install.esd',
            ),
          ),
        ),
      ],
    );
    addTearDown(container.dispose);
    final updates = <CreateProgress>[];

    final created = await container
        .read(bootableUsbServiceProvider)
        .createLinuxIsoUsb(
          disk: _disk,
          isoPath: r'C:\images\win11.iso',
          kind: LinuxUsbKind.toGo,
          deploymentPlan: const DeploymentPlan(
            platform: DeploymentPlatform.linux,
            purpose: DeploymentPurpose.toGo,
            imagePath: r'C:\images\win11.iso',
          ),
          onProgress: updates.add,
        );

    expect(created, isFalse);
    expect(safety.checkCalls, 0);
    expect(updates.single.message, 'creator_windows_iso_in_linux_mode');
  });

  test(
    'Linux To Go rejects an unsupported persistence layout before disk access',
    () async {
      final safety = _CountingDiskSafetyService();
      final container = ProviderContainer(
        overrides: [
          diskSafetyServiceProvider.overrideWithValue(safety),
          windowsIsoPreflightProvider.overrideWithValue(
            _StaticWindowsIsoPreflight(
              const WindowsIsoLayoutInspection.invalid('Linux layout'),
            ),
          ),
          linuxToGoImagePreflightProvider.overrideWithValue(
            const _StaticLinuxToGoImagePreflight(
              LinuxToGoImageInspection.unsupported(
                LinuxToGoImageIssue.debianLiveMissingNtfsSupport,
              ),
            ),
          ),
        ],
      );
      addTearDown(container.dispose);
      final updates = <CreateProgress>[];

      final created = await container
          .read(bootableUsbServiceProvider)
          .createLinuxIsoUsb(
            disk: _disk,
            isoPath: r'C:\images\debian-live.iso',
            kind: LinuxUsbKind.toGo,
            deploymentPlan: const DeploymentPlan(
              platform: DeploymentPlatform.linux,
              purpose: DeploymentPurpose.toGo,
              imagePath: r'C:\images\debian-live.iso',
            ),
            onProgress: updates.add,
          );

      expect(created, isFalse);
      expect(safety.checkCalls, 0);
      expect(
        updates.single.message,
        'linux_togo_debian_live_missing_ntfs_support',
      );
    },
  );
}

const _disk = DiskInfo(
  diskNumber: 7,
  model: 'Test USB',
  friendlyName: 'Test USB',
  sizeBytes: 64 * 1024 * 1024 * 1024,
  sizeFormatted: '64 GB',
  busType: 'USB',
  isRemovable: true,
);

class _StaticWindowsIsoPreflight implements WindowsIsoPreflight {
  const _StaticWindowsIsoPreflight(this.inspection);

  final WindowsIsoLayoutInspection inspection;

  @override
  Future<WindowsIsoLayoutInspection> inspect(String isoPath) async =>
      inspection;
}

class _StaticLinuxToGoImagePreflight implements LinuxToGoImagePreflight {
  const _StaticLinuxToGoImagePreflight(this.inspection);

  final LinuxToGoImageInspection inspection;

  @override
  Future<LinuxToGoImageInspection> inspect(String isoPath) async => inspection;
}

class _CountingDiskSafetyService extends DiskSafetyService {
  int checkCalls = 0;

  @override
  Future<SafetyCheckResult> checkDiskSafety(DiskInfo disk) async {
    checkCalls++;
    return const SafetyCheckResult(isSafe: true);
  }
}
