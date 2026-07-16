import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:win_deploy_studio/core/services/bootable_usb_service.dart';
import 'package:win_deploy_studio/core/services/wtg_service.dart';
import 'package:win_deploy_studio/features/deployment/models/deployment_plan.dart';

void main() {
  String scriptFor({
    required String currentStyle,
    required DeploymentBootMode bootMode,
    int? diskSizeBytes,
  }) => BootableUsbService.installMediaDiskpartScriptForTesting(
    diskNumber: 7,
    currentPartitionStyle: currentStyle,
    deploymentBootMode: bootMode,
    volumeLabel: 'WDS_BOOT',
    diskSizeBytes: diskSizeBytes,
  );

  void expectPartitionOnlyScript(String script) {
    expect(script, isNot(contains('\nclean\n')));
    expect(script, isNot(contains('\nconvert ')));
  }

  void expectInitializationBeforeDiskpart({
    required String source,
    required String flowStart,
    required String flowEnd,
  }) {
    final start = source.indexOf(flowStart);
    final end = source.indexOf(flowEnd, start);
    expect(start, greaterThanOrEqualTo(0), reason: 'missing $flowStart');
    expect(end, greaterThan(start), reason: 'missing $flowEnd');

    final flow = source.substring(start, end);
    final initializer = flow.indexOf('initializeDiskPartitionStyle(');
    final diskpart = flow.indexOf('runGuardedDiskpart(');
    expect(
      initializer,
      greaterThanOrEqualTo(0),
      reason: 'partition flow must initialize the selected disk first',
    );
    expect(diskpart, greaterThan(initializer));
  }

  test('UEFI install-media script leaves disk initialization to Storage', () {
    final script = scriptFor(
      currentStyle: 'GPT',
      bootMode: DeploymentBootMode.uefiGpt,
    );

    expectPartitionOnlyScript(script);
    expect(script, contains('create partition primary'));
    expect(script, contains('format fs=fat32 label="WDS_BOOT" quick'));
  });

  test('legacy install-media script leaves disk initialization to Storage', () {
    final script = scriptFor(
      currentStyle: 'GPT',
      bootMode: DeploymentBootMode.legacyBios,
    );

    expectPartitionOnlyScript(script);
    expect(script, contains('create partition primary'));
    expect(script, contains('\nactive\n'));
  });

  test('install-media scripts do not depend on the stale style snapshot', () {
    final gptSnapshot = scriptFor(
      currentStyle: 'GPT',
      bootMode: DeploymentBootMode.uefiGpt,
    );
    final mbrSnapshot = scriptFor(
      currentStyle: 'MBR',
      bootMode: DeploymentBootMode.uefiGpt,
    );
    final unknownSnapshot = scriptFor(
      currentStyle: 'Unknown',
      bootMode: DeploymentBootMode.uefiGpt,
    );

    expect(gptSnapshot, mbrSnapshot);
    expect(gptSnapshot, unknownSnapshot);
  });

  test(
    'install media explicitly selects the new partition before formatting it',
    () {
      final script = scriptFor(
        currentStyle: 'Unknown',
        bootMode: DeploymentBootMode.uefiGpt,
      );

      // Newer DiskPart builds can retain disk focus after `create partition`.
      // Formatting and drive-letter assignment require the new partition/volume
      // to be the active focus rather than relying on that implicit behavior.
      expect(
        script,
        contains(
          'create partition primary\n'
          'select partition 1\n'
          'format fs=fat32 label="WDS_BOOT" quick\n'
          'assign',
        ),
      );
    },
  );

  test('caps a 57.6 GiB install-media FAT32 partition at 32760 MiB', () {
    final script = scriptFor(
      currentStyle: 'Unknown',
      bootMode: DeploymentBootMode.uefiGpt,
      diskSizeBytes: 61874329600,
    );

    expect(
      script,
      contains(
        'create partition primary size=32760\n'
        'select partition 1\n'
        'format fs=fat32 label="WDS_BOOT" quick',
      ),
    );
  });

  test(
    'keeps FAT32 install media full-sized on a target at or below 32 GiB',
    () {
      final script = scriptFor(
        currentStyle: 'Unknown',
        bootMode: DeploymentBootMode.uefiGpt,
        diskSizeBytes: 32 * 1024 * 1024 * 1024,
      );

      expect(script, contains('create partition primary\nselect partition 1'));
      expect(script, isNot(contains('create partition primary size=')));
    },
  );

  test(
    'legacy install media selects its partition before marking it active',
    () {
      final script = scriptFor(
        currentStyle: 'Unknown',
        bootMode: DeploymentBootMode.legacyBios,
      );

      expect(
        script,
        contains(
          'create partition primary\n'
          'select partition 1\n'
          'active\n'
          'format fs=fat32 label="WDS_BOOT" quick',
        ),
      );
    },
  );

  test('Linux To Go partition script leaves GPT initialization to Storage', () {
    final script = BootableUsbService.linuxToGoDiskpartScriptForTesting(
      diskNumber: 7,
      bootPartitionSizeMb: 2048,
      bootLetter: 'S',
      liveLetter: 'W',
      liveVolumeLabel: 'WDS_LTG',
      currentPartitionStyle: 'GPT',
    );

    expectPartitionOnlyScript(script);
    expect(script, contains('create partition efi'));
  });

  test('Linux To Go script does not depend on the stale style snapshot', () {
    String scriptForStyle(String style) =>
        BootableUsbService.linuxToGoDiskpartScriptForTesting(
          diskNumber: 7,
          bootPartitionSizeMb: 2048,
          bootLetter: 'S',
          liveLetter: 'W',
          liveVolumeLabel: 'WDS_LTG',
          currentPartitionStyle: style,
        );

    expect(scriptForStyle('GPT'), scriptForStyle('MBR'));
    expect(scriptForStyle('GPT'), scriptForStyle('Unknown'));
  });

  test('Linux To Go selects both created partitions before formatting', () {
    final script = BootableUsbService.linuxToGoDiskpartScriptForTesting(
      diskNumber: 7,
      bootPartitionSizeMb: 2048,
      bootLetter: 'S',
      liveLetter: 'W',
      liveVolumeLabel: 'WDS_LTG',
      currentPartitionStyle: 'Unknown',
    );

    expect(
      script,
      contains(
        'create partition efi size=2048\n'
        'select partition 1\n'
        'format fs=fat32 label="WDS_LTG" quick',
      ),
    );
    expect(
      script,
      contains(
        'create partition primary\n'
        'select partition 2\n'
        'format fs=ntfs label="WDS_LTG" quick',
      ),
    );
  });

  test('Windows To Go GPT script leaves disk initialization to Storage', () {
    final script = WtgService.diskpartScriptForTesting(
      diskNumber: 7,
      bootLayout: WtgBootLayout.uefiGpt,
      currentPartitionStyle: 'GPT',
      bootLetter: 'S',
      storageLetter: 'W',
    );

    expectPartitionOnlyScript(script);
    expect(script, contains('create partition efi size=300'));
  });

  test('Windows To Go scripts do not depend on stale style snapshots', () {
    final gptFromMbr = WtgService.diskpartScriptForTesting(
      diskNumber: 7,
      bootLayout: WtgBootLayout.uefiGpt,
      currentPartitionStyle: 'MBR',
      bootLetter: 'S',
      storageLetter: 'W',
    );
    final mbrFromGpt = WtgService.diskpartScriptForTesting(
      diskNumber: 7,
      bootLayout: WtgBootLayout.uefiMbr,
      currentPartitionStyle: 'GPT',
      bootLetter: 'S',
      storageLetter: 'W',
    );

    final gptFromGpt = WtgService.diskpartScriptForTesting(
      diskNumber: 7,
      bootLayout: WtgBootLayout.uefiGpt,
      currentPartitionStyle: 'GPT',
      bootLetter: 'S',
      storageLetter: 'W',
    );
    final mbrFromMbr = WtgService.diskpartScriptForTesting(
      diskNumber: 7,
      bootLayout: WtgBootLayout.uefiMbr,
      currentPartitionStyle: 'MBR',
      bootLetter: 'S',
      storageLetter: 'W',
    );

    expectPartitionOnlyScript(gptFromMbr);
    expectPartitionOnlyScript(mbrFromGpt);
    expectPartitionOnlyScript(mbrFromMbr);
    expect(gptFromMbr, gptFromGpt);
    expect(mbrFromGpt, mbrFromMbr);
  });

  test('Windows To Go selects each formatted partition explicitly', () {
    final script = WtgService.diskpartScriptForTesting(
      diskNumber: 7,
      bootLayout: WtgBootLayout.uefiGpt,
      currentPartitionStyle: 'Unknown',
      bootLetter: 'S',
      storageLetter: 'W',
      bootLabel: 'WDS_BOOT',
      storageLabel: 'WDS_STORAGE',
    );

    expect(
      script,
      contains(
        'create partition efi size=300\n'
        'select partition 1\n'
        'format fs=fat32 label="WDS_BOOT" quick',
      ),
    );
    expect(
      script,
      contains(
        'create partition primary\n'
        'select partition 3\n'
        'format fs=ntfs label="WDS_STORAGE" quick',
      ),
    );
  });

  test('Windows To Go MBR layout selects its boot and storage partitions', () {
    final script = WtgService.diskpartScriptForTesting(
      diskNumber: 7,
      bootLayout: WtgBootLayout.uefiMbr,
      currentPartitionStyle: 'Unknown',
      bootLetter: 'S',
      storageLetter: 'W',
      bootLabel: 'WDS_BOOT',
      storageLabel: 'WDS_STORAGE',
    );

    expect(
      script,
      contains(
        'create partition primary size=350\n'
        'select partition 1\n'
        'active\n'
        'format fs=fat32 label="WDS_BOOT" quick',
      ),
    );
    expect(
      script,
      contains(
        'create partition primary\n'
        'select partition 2\n'
        'format fs=ntfs label="WDS_STORAGE" quick',
      ),
    );
  });

  test(
    'all media partition flows initialize the selected disk before DiskPart creates partitions',
    () {
      final bootableSource = File(
        'lib/core/services/bootable_usb_service.dart',
      ).readAsStringSync();
      final wtgSource = File(
        'lib/core/services/wtg_service.dart',
      ).readAsStringSync();

      expectInitializationBeforeDiskpart(
        source: bootableSource,
        flowStart: 'Future<_DiskPartResult> _partitionDisk({',
        flowEnd: 'static String _buildInstallMediaDiskpartScript',
      );
      expectInitializationBeforeDiskpart(
        source: bootableSource,
        flowStart:
            'Future<_LinuxToGoPartitionResult> _partitionLinuxToGoDisk({',
        flowEnd: 'static String _buildLinuxToGoDiskpartScript',
      );
      expectInitializationBeforeDiskpart(
        source: wtgSource,
        flowStart: 'Future<_WtgPartitionLayout> _partitionDisk({',
        flowEnd: 'static String _buildWtgDiskpartScript',
      );
    },
  );
}
