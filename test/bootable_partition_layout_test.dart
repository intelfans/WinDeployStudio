import 'package:flutter_test/flutter_test.dart';
import 'package:win_deploy_studio/core/services/bootable_usb_service.dart';
import 'package:win_deploy_studio/core/services/wtg_service.dart';
import 'package:win_deploy_studio/features/deployment/models/deployment_plan.dart';

void main() {
  String scriptFor({
    required String currentStyle,
    required DeploymentBootMode bootMode,
  }) => BootableUsbService.installMediaDiskpartScriptForTesting(
    diskNumber: 7,
    currentPartitionStyle: currentStyle,
    deploymentBootMode: bootMode,
    volumeLabel: 'WDS_BOOT',
  );

  test('does not reconvert an already GPT UEFI target after clean', () {
    final script = scriptFor(
      currentStyle: 'GPT',
      bootMode: DeploymentBootMode.uefiGpt,
    );

    expect(script, contains('clean\ncreate partition primary'));
    expect(script, isNot(contains('convert gpt')));
    expect(script, contains('format fs=fat32 label="WDS_BOOT" quick'));
  });

  test('converts an MBR target to GPT for UEFI GPT media', () {
    final script = scriptFor(
      currentStyle: 'MBR',
      bootMode: DeploymentBootMode.uefiGpt,
    );

    expect(script, contains('clean\nconvert gpt\ncreate partition primary'));
  });

  test(
    'does not reconvert an already MBR target for BIOS-compatible media',
    () {
      final script = scriptFor(
        currentStyle: 'MBR',
        bootMode: DeploymentBootMode.uefiMbr,
      );

      expect(script, isNot(contains('convert mbr')));
      expect(script, contains('clean\ncreate partition primary'));
    },
  );

  test('converts a GPT target to MBR when BIOS compatibility is requested', () {
    final script = scriptFor(
      currentStyle: 'GPT',
      bootMode: DeploymentBootMode.legacyBios,
    );

    expect(script, contains('clean\nconvert mbr\ncreate partition primary'));
    expect(script, contains('\nactive\n'));
  });

  test('converts an unknown partition style to the requested layout', () {
    final script = scriptFor(
      currentStyle: 'Unknown',
      bootMode: DeploymentBootMode.uefiGpt,
    );

    expect(script, contains('convert gpt'));
  });

  test('Linux To Go does not reconvert an already GPT target', () {
    final script = BootableUsbService.linuxToGoDiskpartScriptForTesting(
      diskNumber: 7,
      bootPartitionSizeMb: 2048,
      bootLetter: 'S',
      liveLetter: 'W',
      liveVolumeLabel: 'WDS_LTG',
      currentPartitionStyle: 'GPT',
    );

    expect(script, contains('clean\ncreate partition efi'));
    expect(script, isNot(contains('convert gpt')));
  });

  test('Linux To Go converts a non-GPT target before creating EFI media', () {
    final script = BootableUsbService.linuxToGoDiskpartScriptForTesting(
      diskNumber: 7,
      bootPartitionSizeMb: 2048,
      bootLetter: 'S',
      liveLetter: 'W',
      liveVolumeLabel: 'WDS_LTG',
      currentPartitionStyle: 'MBR',
    );

    expect(script, contains('clean\nconvert gpt\ncreate partition efi'));
  });

  test('Windows To Go skips a redundant GPT conversion', () {
    final script = WtgService.diskpartScriptForTesting(
      diskNumber: 7,
      bootLayout: WtgBootLayout.uefiGpt,
      currentPartitionStyle: 'GPT',
      bootLetter: 'S',
      storageLetter: 'W',
    );

    expect(script, contains('clean\ncreate partition efi size=300'));
    expect(script, isNot(contains('convert gpt')));
  });

  test('Windows To Go converts layouts only when the target style differs', () {
    final toGpt = WtgService.diskpartScriptForTesting(
      diskNumber: 7,
      bootLayout: WtgBootLayout.uefiGpt,
      currentPartitionStyle: 'MBR',
      bootLetter: 'S',
      storageLetter: 'W',
    );
    final toMbr = WtgService.diskpartScriptForTesting(
      diskNumber: 7,
      bootLayout: WtgBootLayout.uefiMbr,
      currentPartitionStyle: 'GPT',
      bootLetter: 'S',
      storageLetter: 'W',
    );

    expect(toGpt, contains('clean\nconvert gpt\ncreate partition efi'));
    expect(toMbr, contains('clean\nconvert mbr\ncreate partition primary'));
  });
}
