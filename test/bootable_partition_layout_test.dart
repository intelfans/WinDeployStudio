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

  test(
    'UEFI GPT install-media script uses a removable-compatible FAT32 primary partition',
    () {
      final script = scriptFor(
        currentStyle: 'GPT',
        bootMode: DeploymentBootMode.uefiGpt,
      );

      expectPartitionOnlyScript(script);
      expect(script, contains('create partition primary'));
      expect(script, isNot(contains('create partition efi')));
      expect(script, contains('format fs=fat32 label="WDS_BOOT" quick'));
    },
  );

  test(
    'summarizes DiskPart label failures without repeated progress noise',
    () {
      final summary = BootableUsbService.summarizeDiskpartFailureForTesting('''
Microsoft DiskPart version 10.0
    0 percent completed
    0 percent completed
Virtual Disk Service error:
The label is invalid.
''');
      expect(summary, 'i18n:deploy_compat_invalid_volume_label');
    },
  );

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
    'install media formats its selected partition before binding a drive letter',
    () {
      final script = scriptFor(
        currentStyle: 'Unknown',
        bootMode: DeploymentBootMode.uefiGpt,
      );

      expect(
        script,
        contains(
          'create partition primary\n'
          'select partition 1\n'
          'format fs=fat32 label="WDS_BOOT" quick\n'
          'remove all noerr\n'
          'assign letter=Z',
        ),
      );
      expect(script, isNot(contains('select volume Z')));
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
        'format fs=fat32 label="WDS_BOOT" quick\n'
        'remove all noerr\n'
        'assign letter=Z',
      ),
    );
  });

  test('keeps FAT32 install media full-sized on a target at or below 32 GiB', () {
    final script = scriptFor(
      currentStyle: 'Unknown',
      bootMode: DeploymentBootMode.uefiGpt,
      diskSizeBytes: 32 * 1024 * 1024 * 1024,
    );

    expect(
      script,
      contains(
        'create partition primary\nselect partition 1\nformat fs=fat32 label="WDS_BOOT" quick\nremove all noerr\nassign letter=Z',
      ),
    );
    expect(script, isNot(contains('create partition primary size=')));
  });

  test(
    'UEFI + MBR keeps an MBR primary partition without a BIOS active flag',
    () {
      final script = scriptFor(
        currentStyle: 'Unknown',
        bootMode: DeploymentBootMode.uefiMbr,
      );

      expect(script, contains('create partition primary'));
      expect(script, isNot(contains('\nactive\n')));
    },
  );

  test(
    'legacy install media selects its partition before formatting and activation',
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
          'format fs=fat32 label="WDS_BOOT" quick\n'
          'remove all noerr\n'
          'assign letter=Z\n'
          'select partition 1\n'
          'active',
        ),
      );
    },
  );

  test('recognizes the localized no-volume failure emitted by DiskPart', () {
    expect(
      BootableUsbService.noVolumeSelectedMessageForTesting(
        '没有指定卷。\n请选择一个卷，再试一次。',
      ),
      isTrue,
    );
    expect(
      BootableUsbService.noVolumeSelectedMessageForTesting(
        'There is no volume selected.',
      ),
      isTrue,
    );
  });

  test(
    'install-media postcondition accepts only the requested FAT32 volume',
    () {
      const expected = <String, Object?>{
        'DiskNumber': 7,
        'PartitionStyle': 'GPT',
        'Label': 'WDS_BOOT',
        'FileSystem': 'FAT32',
        'EfiSystemPartition': false,
        'IsActive': false,
      };
      bool matches(Map<String, Object?> actual) =>
          BootableUsbService.installMediaPartitionMatchesForTesting(
            actual: actual,
            expectedDiskNumber: 7,
            expectedPartitionStyle: 'gpt',
            expectedLabel: 'wds_boot',
            expectedEfiSystemPartition: false,
            expectedActive: false,
          );

      expect(matches(expected), isTrue);
      expect(matches({...expected, 'Label': ''}), isFalse);
      expect(matches({...expected, 'FileSystem': ''}), isFalse);
      expect(matches({...expected, 'DiskNumber': 8}), isFalse);
      expect(matches({...expected, 'PartitionStyle': 'MBR'}), isFalse);
      expect(matches({...expected, 'EfiSystemPartition': true}), isFalse);
      expect(matches({...expected, 'IsActive': true}), isFalse);
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

  test(
    'Linux To Go explicitly selects each new partition before formatting',
    () {
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
          'assign letter=S\n'
          'select volume S\n'
          'format fs=fat32 label="WDS_LTG" quick',
        ),
      );
      expect(
        script,
        contains(
          'create partition primary\n'
          'select partition 2\n'
          'assign letter=W\n'
          'select volume W\n'
          'format fs=ntfs label="WDS_LTG" quick',
        ),
      );
    },
  );

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

  test(
    'Windows To Go GPT explicitly selects each new partition before formatting',
    () {
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
          'assign letter=S\n'
          'select volume S\n'
          'format fs=fat32 label="WDS_BOOT" quick',
        ),
      );
      expect(
        script,
        contains(
          'create partition primary\n'
          'select partition 3\n'
          'assign letter=W\n'
          'select volume W\n'
          'format fs=ntfs label="WDS_STORAGE" quick',
        ),
      );
    },
  );

  test(
    'Windows To Go MBR marks its boot partition active after formatting',
    () {
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
          'assign letter=S\n'
          'select volume S\n'
          'format fs=fat32 label="WDS_BOOT" quick\n'
          'select partition 1\n'
          'active',
        ),
      );
      expect(
        script,
        contains(
          'create partition primary\n'
          'select partition 2\n'
          'assign letter=W\n'
          'select volume W\n'
          'format fs=ntfs label="WDS_STORAGE" quick',
        ),
      );
    },
  );

  test(
    'Windows To Go legacy BIOS selects each MBR partition before formatting',
    () {
      final script = WtgService.diskpartScriptForTesting(
        diskNumber: 7,
        bootLayout: WtgBootLayout.legacyBios,
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
          'assign letter=S\n'
          'select volume S\n'
          'format fs=ntfs label="WDS_BOOT" quick',
        ),
      );
      expect(
        script,
        contains(
          'create partition primary\n'
          'select partition 2\n'
          'assign letter=W\n'
          'select volume W\n'
          'format fs=ntfs label="WDS_STORAGE" quick',
        ),
      );
    },
  );

  test(
    'Windows To Go virtual disk selects its new partition before formatting',
    () {
      final script = WtgService.virtualDiskpartScriptForTesting(
        filePath: r'S:\WinDeploy.vhdx',
        maximumMb: 32768,
        type: 'expandable',
        imageLetter: 'V',
      );

      expect(
        script,
        contains(
          'create partition primary\n'
          'select partition 1\n'
          'assign letter=V\n'
          'select volume V\n'
          'format fs=ntfs label="WDS_OS" quick',
        ),
      );
    },
  );

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

  test('install-media verification tolerates delayed Storage enumeration', () {
    final source = File(
      'lib/core/services/bootable_usb_service.dart',
    ).readAsStringSync();
    final start = source.indexOf('Future<bool> _verifyInstallMediaPartition');
    final end = source.indexOf(
      'static String? _normalizePreferredLetter',
      start,
    );
    expect(start, greaterThanOrEqualTo(0));
    expect(end, greaterThan(start));
    final verifier = source.substring(start, end);

    expect(verifier, contains("AddSeconds(25)"));
    expect(verifier, contains('Start-Sleep -Milliseconds 500'));
    expect(verifier, contains('Duration(seconds: 35)'));
    expect(verifier, contains('WDS_EXPECTED_DISK_NUMBER'));
    expect(verifier, contains('WDS_EXPECTED_PARTITION_STYLE'));
    expect(verifier, contains('WDS_EXPECTED_LABEL'));
    expect(verifier, contains("FileSystem.ToUpperInvariant() -eq 'FAT32'"));
    expect(verifier, contains('verification output'));
  });

  test(
    'install-media drive-letter query does not report a timeout as occupied',
    () {
      final source = File(
        'lib/core/services/bootable_usb_service.dart',
      ).readAsStringSync();
      final start = source.indexOf(
        'Future<_DriveLetterAvailability> _checkDriveLetterAvailability',
      );
      final end = source.indexOf('String _sanitizeVolumeLabel', start);
      expect(start, greaterThanOrEqualTo(0));
      expect(end, greaterThan(start));
      final check = source.substring(start, end);

      expect(check, contains('Duration(seconds: 30)'));
      expect(
        check,
        contains(
          'result.exitCode == 1) return _DriveLetterAvailability.occupied',
        ),
      );
      expect(check, contains('return _DriveLetterAvailability.unknown'));

      final partitionStart = source.indexOf(
        'Future<_DiskPartResult> _partitionDisk({',
      );
      final partitionEnd = source.indexOf(
        'static String _buildInstallMediaDiskpartScript',
        partitionStart,
      );
      final partitionFlow = source.substring(partitionStart, partitionEnd);
      expect(
        partitionFlow,
        contains('availability == _DriveLetterAvailability.occupied'),
      );
      expect(
        partitionFlow,
        contains('availability == _DriveLetterAvailability.unknown'),
      );
    },
  );

  test(
    'install-media Storage checks use a managed timeout that terminates a stuck PowerShell child',
    () {
      final source = File(
        'lib/core/services/bootable_usb_service.dart',
      ).readAsStringSync();
      final runnerStart = source.indexOf(
        'Future<ProcessResult> _runPowerShell',
      );
      final runnerEnd = source.indexOf('void cancel()', runnerStart);
      expect(runnerStart, greaterThanOrEqualTo(0));
      expect(runnerEnd, greaterThan(runnerStart));
      final runner = source.substring(runnerStart, runnerEnd);

      expect(runner, contains('Duration? timeout'));
      expect(runner, contains('if (timeout != null)'));
      expect(runner, contains('_runLinuxUtility('));
      expect(runner, contains('trackForCancellation: false'));

      final verifierStart = source.indexOf(
        'Future<bool> _verifyInstallMediaPartition',
      );
      final verifierEnd = source.indexOf(
        'static String? _normalizePreferredLetter',
        verifierStart,
      );
      final verifier = source.substring(verifierStart, verifierEnd);
      expect(verifier, contains('timeout: const Duration(seconds: 35)'));
      expect(verifier, isNot(contains(').timeout(')));

      final managedRunnerStart = source.indexOf(
        'Future<ProcessResult> _runLinuxUtility',
      );
      final managedRunnerEnd = source.indexOf(
        'static const String _linuxRawWriteScript',
        managedRunnerStart,
      );
      final managedRunner = source.substring(
        managedRunnerStart,
        managedRunnerEnd,
      );
      expect(managedRunner, contains('await _terminateProcessTree(process'));
    },
  );
}
