import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:win_deploy_studio/core/services/disk_safety_service.dart';
import 'package:win_deploy_studio/core/services/windows_iso_preflight.dart';
import 'package:win_deploy_studio/core/services/wtg_service.dart';
import 'package:win_deploy_studio/features/deployment/models/deployment_plan.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Windows To Go retries only transient ISO mount preflight failures', () {
    expect(
      shouldRetryWindowsToGoIsoPreflight(
        const WindowsIsoLayoutInspection.invalid(
          'The ISO could not be mounted for Windows setup validation.',
        ),
      ),
      isTrue,
    );
    expect(
      shouldRetryWindowsToGoIsoPreflight(
        const WindowsIsoLayoutInspection.invalid('Linux layout'),
      ),
      isFalse,
    );
  });

  test(
    'Windows To Go rejects a non-Windows source before disk access',
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
      final updates = <WtgProgress>[];

      final created = await container
          .read(wtgServiceProvider)
          .createWtg(
            disk: _disk,
            isoPath: r'C:\images\ubuntu.iso',
            imageIndex: 1,
            driveLetter: '',
            deploymentPlan: const DeploymentPlan(
              platform: DeploymentPlatform.windows,
              purpose: DeploymentPurpose.toGo,
              imagePath: r'C:\images\ubuntu.iso',
            ),
            onProgress: updates.add,
          );

      expect(created, isFalse);
      expect(safety.checkCalls, 0);
      expect(updates.last.message.split('\n').first, 'wtg_invalid_windows_iso');
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

class _CountingDiskSafetyService extends DiskSafetyService {
  int checkCalls = 0;

  @override
  Future<SafetyCheckResult> checkDiskSafety(DiskInfo disk) async {
    checkCalls++;
    return const SafetyCheckResult(isSafe: true);
  }
}
