import 'package:flutter_test/flutter_test.dart';
import 'package:win_deploy_studio/core/services/wtg_service.dart';
import 'package:win_deploy_studio/features/deployment/models/deployment_plan.dart';

void main() {
  test('BootEx retry is limited to a missing EFI_EX boot manager', () {
    const missingBootEx = '''BFSVC: Unable to open file
W:\\Windows\\boot\\EFI_EX\\bootmgfw_EX.efi for read because the file
does not exist. BFSVC Error: Failed to validate boot manager checksum.''';

    expect(
      WtgBootContract.shouldRetryWithStandardBootFiles(
        exitCode: 193,
        output: missingBootEx,
        hasStandardBootManager: true,
      ),
      isTrue,
    );
    expect(
      WtgBootContract.shouldRetryWithStandardBootFiles(
        exitCode: 193,
        output: missingBootEx,
        hasStandardBootManager: false,
      ),
      isFalse,
    );
    expect(
      WtgBootContract.shouldRetryWithStandardBootFiles(
        exitCode: 5,
        output: 'Access is denied.',
        hasStandardBootManager: true,
      ),
      isFalse,
    );
  });

  test(
    'standard Windows To Go boot retry uses offline non-BootEx servicing',
    () {
      final arguments = WtgBootContract.bcdbootArguments(
        windowsPath: r'W:\\Windows',
        bootRoot: r'V:\\',
        firmware: 'UEFI',
        forceStandardBootFiles: true,
      );

      expect(arguments, containsAllInOrder([r'W:\\Windows', '/s', r'V:\\']));
      expect(arguments, containsAllInOrder(['/f', 'UEFI', '/v', '/offline']));
      expect(arguments, isNot(contains('/bootex')));
    },
  );

  test('direct deployment requires distinct device and osdevice bindings', () {
    final expected = WtgBootContract.expectedDevice(
      windowsDrive: r'W:\',
      storageDrive: r'W:\',
    );

    expect(expected, 'partition=W:');
    expect(
      WtgBootContract.listingMatches(
        'device partition=W:\ndevice partition=W:',
        expected,
      ),
      isFalse,
    );
    expect(
      WtgBootContract.listingMatches(
        'device partition=W:\nosdevice partition=W:',
        expected,
      ),
      isTrue,
    );
    expect(
      WtgBootContract.listingMatches('device partition=W:', expected),
      isFalse,
    );
  });

  test('virtual deployment binds the parent storage volume, not locate', () {
    final expected = WtgBootContract.expectedDevice(
      windowsDrive: r'I:\',
      storageDrive: r'R:\',
      virtualDiskFileName: 'Portable.vhdx',
    );

    expect(expected, r'vhd=[R:]\Portable.vhdx');
    expect(
      WtgBootContract.listingMatches(r'''device vhd=[R:]\Portable.vhdx
osdevice vhd=[R:]\Portable.vhdx''', expected),
      isTrue,
    );
    expect(
      WtgBootContract.listingMatches(r'''device vhd=[locate]\Portable.vhdx
osdevice vhd=[locate]\Portable.vhdx''', expected),
      isFalse,
    );
  });

  test('blank custom icon preserves the Windows default drive icon', () {
    const identity = WtgVolumeIdentity(
      volumeLabel: 'PORTABLE',
      customIconPath: '   ',
    );

    expect(identity.usesCustomIcon, isFalse);
    expect(identity.autorunContents, isNull);
  });

  test('custom icon produces only the expected volume autorun content', () {
    const plan = DeploymentPlan(
      platform: DeploymentPlatform.windows,
      purpose: DeploymentPurpose.toGo,
      imagePath: r'D:\Images\Windows.iso',
      customVolumeLabel: 'PORTABLE',
      customIconPath: r' D:\Icons\portable.ico ',
    );

    final identity = WtgVolumeIdentity.fromPlan(plan);

    expect(identity.usesCustomIcon, isTrue);
    expect(identity.customIconPath, r'D:\Icons\portable.ico');
    expect(
      identity.autorunContents,
      '[autorun]\r\nicon=.wds-drive.ico\r\nlabel=PORTABLE\r\n',
    );
  });
}
