import 'package:flutter_test/flutter_test.dart';
import 'package:win_deploy_studio/features/deployment/services/windows_deployment_service.dart';

void main() {
  test(
    'does not run unsupported offline REAgentC when WinRE removal is requested',
    () async {
      final logs = <String>[];
      final service = WindowsDeploymentService(logs.add);

      final succeeded = await service.disableAndVerifyWinRe(
        windowsDrive: r'X:\',
        requested: true,
      );

      expect(succeeded, isTrue);
      expect(logs, contains(contains('offline WinRE removal is unsupported')));
    },
  );

  test('does nothing when WinRE removal was not selected', () async {
    final logs = <String>[];
    final succeeded = await WindowsDeploymentService(
      logs.add,
    ).disableAndVerifyWinRe(windowsDrive: r'X:\', requested: false);

    expect(succeeded, isTrue);
    expect(logs, contains('OPTION disableWinRe: not requested'));
  });
}
