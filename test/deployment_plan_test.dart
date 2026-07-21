import 'package:flutter_test/flutter_test.dart';
import 'package:win_deploy_studio/features/deployment/models/deployment_plan.dart';

void main() {
  group('DeploymentPlan', () {
    test('round-trips every deployment option through JSON', () {
      const plan = DeploymentPlan(
        platform: DeploymentPlatform.windows,
        purpose: DeploymentPurpose.toGo,
        imagePath: r'D:\Images\Windows.iso',
        imageIndex: 4,
        imageName: 'Windows 11 Pro',
        imageEdition: 'Professional',
        imageBuild: '26100',
        imageArchitecture: 'x64',
        windowsGeneration: WindowsGeneration.windows11,
        windowsProductFamily: WindowsProductFamily.server,
        bootMode: DeploymentBootMode.uefiMbr,
        deploymentMode: DeploymentMode.vhdx,
        virtualDiskType: VirtualDiskType.fixed,
        virtualDiskSizeGb: 128,
        virtualDiskFileName: 'Portable.vhdx',
        blockLocalDisks: false,
        skipOobe: true,
        disableWinRe: false,
        disableUasp: true,
        compactOs: true,
        wimBoot: false,
        fixVhdDriveLetter: true,
        enableNetFx3: true,
        ntfsUefiSupport: true,
        preferredSystemLetter: 'R',
        preferredBootLetter: 'S',
        driverDirectory: r'D:\Drivers',
        customIconPath: r'D:\Icons\drive.ico',
        customVolumeLabel: 'PORTABLE',
      );

      final decoded = DeploymentPlan.fromJson(plan.toJson());

      expect(decoded.toJson(), plan.toJson());
    });

    test('detects supported Windows generations from build numbers', () {
      expect(
        DeploymentPlan.detectWindowsGeneration(build: '26100'),
        WindowsGeneration.windows11,
      );
      expect(
        DeploymentPlan.detectWindowsGeneration(build: '19045'),
        WindowsGeneration.windows10,
      );
      expect(
        DeploymentPlan.detectWindowsGeneration(build: '9600'),
        WindowsGeneration.windows81,
      );
      expect(
        DeploymentPlan.detectWindowsGeneration(build: '9200'),
        WindowsGeneration.windows8,
      );
      expect(
        DeploymentPlan.detectWindowsGeneration(build: '7601'),
        WindowsGeneration.windows7,
      );
    });

    test('identifies Server release names that do not include a build', () {
      expect(
        DeploymentPlan.detectWindowsGeneration(version: 'Windows Server 2012'),
        WindowsGeneration.windows8,
      );
      expect(
        DeploymentPlan.detectWindowsGeneration(
          version: 'Windows Server 2012 R2',
        ),
        WindowsGeneration.windows81,
      );
      expect(
        DeploymentPlan.detectWindowsGeneration(version: 'Windows Server 2022'),
        WindowsGeneration.windows10,
      );
      expect(
        DeploymentPlan.detectWindowsGeneration(version: 'Windows Server 2025'),
        WindowsGeneration.windows11,
      );
    });

    test('identifies Server product family from WIM metadata', () {
      expect(
        DeploymentPlan.detectWindowsProductFamily(
          installationType: 'Server',
          edition: 'ServerStandard',
          name: 'Windows Server 2022 Standard',
        ),
        WindowsProductFamily.server,
      );
      expect(
        DeploymentPlan.detectWindowsProductFamily(
          edition: 'ServerDatacenterCore',
        ),
        WindowsProductFamily.server,
      );
      expect(
        DeploymentPlan.detectWindowsProductFamily(
          name: 'Windows Server 2019 Datacenter',
        ),
        WindowsProductFamily.server,
      );
      expect(
        DeploymentPlan.detectWindowsProductFamily(
          installationType: 'Client',
          edition: 'EnterpriseS',
          name: 'Windows 10 Enterprise LTSC 2021',
        ),
        WindowsProductFamily.client,
      );
      expect(
        DeploymentPlan.detectWindowsProductFamily(
          installationType: 'Client',
          name: 'Windows Server label from a customized ISO',
        ),
        WindowsProductFamily.client,
      );
    });
  });

  group('DeploymentCompatibility', () {
    DeploymentPlan windowsPlan({
      WindowsGeneration generation = WindowsGeneration.windows11,
      WindowsProductFamily productFamily = WindowsProductFamily.client,
      DeploymentMode mode = DeploymentMode.direct,
      DeploymentBootMode bootMode = DeploymentBootMode.uefiGpt,
      bool wimBoot = false,
      bool compactOs = false,
      String architecture = 'x64',
      String imageName = 'Windows 11 Pro',
      String imageEdition = 'Professional',
      String systemLetter = '',
      String bootLetter = '',
    }) {
      return DeploymentPlan(
        platform: DeploymentPlatform.windows,
        purpose: DeploymentPurpose.toGo,
        imagePath: r'D:\Images\Windows.iso',
        windowsGeneration: generation,
        deploymentMode: mode,
        virtualDiskFileName: mode == DeploymentMode.vhd
            ? 'WinDeploy.vhd'
            : 'WinDeploy.vhdx',
        bootMode: bootMode,
        wimBoot: wimBoot,
        compactOs: compactOs,
        imageArchitecture: architecture,
        imageName: imageName,
        imageEdition: imageEdition,
        windowsProductFamily: productFamily,
        preferredSystemLetter: systemLetter,
        preferredBootLetter: bootLetter,
      );
    }

    test('blocks VHDX for Windows 7', () {
      final report = DeploymentCompatibility.evaluate(
        windowsPlan(
          generation: WindowsGeneration.windows7,
          mode: DeploymentMode.vhdx,
        ),
      );

      expect(report.canDeploy, isFalse);
      expect(report.errors.map((issue) => issue.code), contains('win7_vhdx'));
    });

    test('allows Windows 7 native VHD only for Enterprise or Ultimate', () {
      final professional = DeploymentCompatibility.evaluate(
        windowsPlan(
          generation: WindowsGeneration.windows7,
          mode: DeploymentMode.vhd,
          imageName: 'Windows 7 Professional',
          imageEdition: 'Professional',
        ),
      );
      final enterprise = DeploymentCompatibility.evaluate(
        windowsPlan(
          generation: WindowsGeneration.windows7,
          mode: DeploymentMode.vhd,
          imageName: 'Windows 7 Enterprise',
          imageEdition: 'Enterprise',
        ),
      );

      expect(
        professional.errors.map((issue) => issue.code),
        contains('win7_vhd_edition'),
      );
      expect(
        enterprise.errors.map((issue) => issue.code),
        isNot(contains('win7_vhd_edition')),
      );
      expect(
        DeploymentCompatibility.deploymentModesFor(
          windowsPlan(
            generation: WindowsGeneration.windows7,
            imageName: 'Windows 7 Professional Enterprise Tools',
            imageEdition: 'Professional',
          ),
        ),
        [DeploymentMode.direct],
      );
    });

    test('fails closed for ARM legacy boot and unknown virtual disks', () {
      final armLegacy = DeploymentCompatibility.evaluate(
        windowsPlan(
          architecture: 'ARM64',
          bootMode: DeploymentBootMode.legacyBios,
        ),
      );
      final unknownVhd = DeploymentCompatibility.evaluate(
        windowsPlan(
          generation: WindowsGeneration.unknown,
          mode: DeploymentMode.vhd,
        ),
      );

      expect(
        armLegacy.errors.map((issue) => issue.code),
        contains('arm_requires_uefi_gpt'),
      );
      expect(
        unknownVhd.errors.map((issue) => issue.code),
        contains('unknown_virtual_disk'),
      );
      expect(
        DeploymentCompatibility.deploymentModesFor(
          windowsPlan(generation: WindowsGeneration.unknown),
        ),
        [DeploymentMode.direct],
      );
    });

    test('fails closed for unrecognized and 32-bit ARM architectures', () {
      final unknown = DeploymentCompatibility.evaluate(
        windowsPlan(architecture: 'mips64'),
      );
      final arm32 = DeploymentCompatibility.evaluate(
        windowsPlan(architecture: 'arm'),
      );

      expect(
        unknown.errors.map((issue) => issue.code),
        contains('unsupported_architecture'),
      );
      expect(
        arm32.errors.map((issue) => issue.code),
        contains('unsupported_architecture'),
      );
    });

    test('allows WIMBoot only for direct Windows 8.1 deployment', () {
      final supported = DeploymentCompatibility.evaluate(
        windowsPlan(generation: WindowsGeneration.windows81, wimBoot: true),
      );
      final unsupported = DeploymentCompatibility.evaluate(
        windowsPlan(generation: WindowsGeneration.windows10, wimBoot: true),
      );

      expect(
        supported.errors.map((issue) => issue.code),
        isNot(contains('wimboot_scope')),
      );
      expect(
        unsupported.errors.map((issue) => issue.code),
        contains('wimboot_scope'),
      );
    });

    test('blocks CompactOS outside Windows 10 and Windows 11', () {
      final report = DeploymentCompatibility.evaluate(
        windowsPlan(generation: WindowsGeneration.windows7, compactOs: true),
      );

      expect(
        report.errors.map((issue) => issue.code),
        contains('compact_scope'),
      );
    });

    test('rejects obsolete offline WinRE removal before deployment', () {
      final report = DeploymentCompatibility.evaluate(
        windowsPlan().copyWith(disableWinRe: true),
      );

      expect(
        report.errors.map((issue) => issue.code),
        contains('offline_winre_unsupported'),
      );
    });

    test('allows Windows 8 virtual-disk deployment', () {
      final plan = windowsPlan(
        generation: WindowsGeneration.windows8,
        mode: DeploymentMode.vhdx,
        imageName: 'Windows 8 Pro',
        imageEdition: 'Professional',
      );

      expect(DeploymentCompatibility.evaluate(plan).canDeploy, isTrue);
      expect(
        DeploymentCompatibility.deploymentModesFor(plan),
        DeploymentMode.values,
      );
    });

    test('allows Server native VHD using Server 2008 R2 metadata', () {
      final plan = windowsPlan(
        generation: WindowsGeneration.windows7,
        productFamily: WindowsProductFamily.server,
        mode: DeploymentMode.vhd,
        imageName: 'Windows Server 2008 R2 Standard',
        imageEdition: 'ServerStandard',
      );

      final report = DeploymentCompatibility.evaluate(plan);
      expect(report.canDeploy, isTrue);
      expect(DeploymentCompatibility.deploymentModesFor(plan), const [
        DeploymentMode.direct,
        DeploymentMode.vhd,
      ]);
    });

    test('rejects client-only To Go features for Windows Server', () {
      final compactServer = DeploymentCompatibility.evaluate(
        windowsPlan(
          generation: WindowsGeneration.windows10,
          productFamily: WindowsProductFamily.server,
          compactOs: true,
          imageName: 'Windows Server 2022 Standard',
          imageEdition: 'ServerStandard',
        ),
      );
      final wimBootServer = DeploymentCompatibility.evaluate(
        windowsPlan(
          generation: WindowsGeneration.windows81,
          productFamily: WindowsProductFamily.server,
          wimBoot: true,
          imageName: 'Windows Server 2012 R2 Standard',
          imageEdition: 'ServerStandard',
        ),
      );

      expect(
        compactServer.errors.map((issue) => issue.code),
        contains('compact_scope'),
      );
      expect(
        wimBootServer.errors.map((issue) => issue.code),
        contains('wimboot_scope'),
      );
      expect(
        DeploymentCompatibility.supportsCompactOs(
          windowsPlan(
            generation: WindowsGeneration.windows10,
            productFamily: WindowsProductFamily.server,
          ),
        ),
        isFalse,
      );
      expect(
        DeploymentCompatibility.supportsWimBoot(
          windowsPlan(
            generation: WindowsGeneration.windows81,
            productFamily: WindowsProductFamily.server,
          ),
        ),
        isFalse,
      );
    });

    test('blocks duplicate or invalid assigned drive letters', () {
      final duplicate = DeploymentCompatibility.evaluate(
        windowsPlan(systemLetter: 'W:', bootLetter: 'W'),
      );
      final invalid = DeploymentCompatibility.evaluate(
        windowsPlan(systemLetter: 'C'),
      );

      expect(
        duplicate.errors.map((issue) => issue.code),
        contains('duplicate_letters'),
      );
      expect(
        invalid.errors.map((issue) => issue.code),
        contains('invalid_letter'),
      );
    });

    test('blocks virtual disk deployment for Linux', () {
      const plan = DeploymentPlan(
        platform: DeploymentPlatform.linux,
        purpose: DeploymentPurpose.toGo,
        imagePath: r'D:\Images\Linux.iso',
        deploymentMode: DeploymentMode.vhd,
      );

      final report = DeploymentCompatibility.evaluate(plan);

      expect(report.canDeploy, isFalse);
      expect(
        report.errors.map((issue) => issue.code),
        contains('linux_virtual_disk'),
      );
    });

    test('blocks hidden Windows-only options for Linux', () {
      const plan = DeploymentPlan(
        platform: DeploymentPlatform.linux,
        purpose: DeploymentPurpose.toGo,
        imagePath: r'D:\Images\Linux.iso',
        skipOobe: true,
      );

      final report = DeploymentCompatibility.evaluate(plan);

      expect(report.canDeploy, isFalse);
      expect(
        report.errors.map((issue) => issue.code),
        contains('linux_windows_options'),
      );
    });

    test('validates virtual disk names and extensions', () {
      final invalidName = DeploymentCompatibility.evaluate(
        windowsPlan(
          mode: DeploymentMode.vhdx,
        ).copyWith(virtualDiskFileName: r'folder\Portable.vhdx'),
      );
      final wrongExtension = DeploymentCompatibility.evaluate(
        windowsPlan(
          mode: DeploymentMode.vhd,
        ).copyWith(virtualDiskFileName: 'Portable.vhdx'),
      );

      expect(
        invalidName.errors.map((issue) => issue.code),
        contains('vhd_invalid_name'),
      );
      expect(
        wrongExtension.errors.map((issue) => issue.code),
        contains('vhd_wrong_extension'),
      );
    });

    test('validates volume labels and icon extensions', () {
      final invalidLabel = DeploymentCompatibility.evaluate(
        windowsPlan().copyWith(customVolumeLabel: 'BAD/LABEL'),
      );
      final invalidIcon = DeploymentCompatibility.evaluate(
        windowsPlan().copyWith(customIconPath: r'D:\Icons\drive.png'),
      );

      expect(
        invalidLabel.errors.map((issue) => issue.code),
        contains('invalid_volume_label'),
      );
      expect(
        invalidIcon.errors.map((issue) => issue.code),
        contains('invalid_icon'),
      );
      for (final character in const ['+', ',', ';', '=', '[', ']']) {
        expect(
          DeploymentCompatibility.isVolumeLabelValid(
            'WDS${character}USB',
            maxLength: 11,
          ),
          isFalse,
          reason: 'character $character must be rejected immediately',
        );
      }
      expect(
        DeploymentCompatibility.isVolumeLabelValid('Win8.1', maxLength: 11),
        isFalse,
      );
      expect(
        DeploymentCompatibility.isVolumeLabelValid(
          'Win8.1',
          maxLength: 32,
          allowPeriod: true,
        ),
        isTrue,
      );
      expect(
        DeploymentCompatibility.isVolumeLabelValid('', maxLength: 11),
        isTrue,
      );
    });
  });
}
