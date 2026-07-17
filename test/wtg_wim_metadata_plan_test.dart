import 'package:flutter_test/flutter_test.dart';
import 'package:win_deploy_studio/core/services/wim_info_service.dart';
import 'package:win_deploy_studio/core/services/wtg_service.dart';
import 'package:win_deploy_studio/features/deployment/models/deployment_plan.dart';

void main() {
  const server2022 = WimImageInfo(
    index: 2,
    name: 'Windows Server 2022 SERVERSTANDARD',
    description: 'Windows Server 2022 Standard (Desktop Experience)',
    sizeBytes: 8 * 1024 * 1024 * 1024,
    architecture: 'x64',
    edition: 'ServerStandard',
    version: '10.0.20348.0',
    build: '20348',
    installationType: 'Server',
    language: 'en-US',
  );

  const requestedClientPlan = DeploymentPlan(
    platform: DeploymentPlatform.windows,
    purpose: DeploymentPurpose.toGo,
    imagePath: r'D:\Images\server.iso',
    imageIndex: 2,
    imageName: 'Windows 11 Pro',
    imageEdition: 'Professional',
    imageBuild: '26100',
    imageArchitecture: 'x64',
    windowsGeneration: WindowsGeneration.windows11,
    windowsProductFamily: WindowsProductFamily.client,
  );

  test('WTG re-inspection derives Server family from the selected WIM', () {
    final effectivePlan = resolveWindowsToGoPlanFromWimImage(
      requestedPlan: requestedClientPlan,
      image: server2022,
    );

    expect(effectivePlan.windowsProductFamily, WindowsProductFamily.server);
    expect(effectivePlan.windowsGeneration, WindowsGeneration.windows10);
    expect(effectivePlan.imageName, server2022.name);
    expect(effectivePlan.imageEdition, server2022.edition);
    expect(effectivePlan.imageBuild, server2022.build);
    expect(effectivePlan.imageArchitecture, server2022.architecture);
    expect(DeploymentCompatibility.evaluate(effectivePlan).canDeploy, isTrue);
  });

  test(
    'WTG re-inspection prevents a Server WIM using client-only CompactOS',
    () {
      final effectivePlan = resolveWindowsToGoPlanFromWimImage(
        requestedPlan: requestedClientPlan.copyWith(compactOs: true),
        image: server2022,
      );
      final report = DeploymentCompatibility.evaluate(effectivePlan);

      expect(
        report.errors.map((issue) => issue.code),
        contains('compact_scope'),
      );
    },
  );
}
