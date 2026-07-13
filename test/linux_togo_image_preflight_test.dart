import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:win_deploy_studio/core/services/linux_togo_image_preflight.dart';

void main() {
  late Directory testRoot;

  setUp(() async {
    testRoot = await Directory.systemTemp.createTemp('wds_ltg_image_test_');
  });

  tearDown(() async {
    if (await testRoot.exists()) await testRoot.delete(recursive: true);
  });

  test('accepts a structurally valid x64 casper Live root', () async {
    await _writeCasperLayout(testRoot);

    final result = await LinuxToGoImagePreflightService.inspectMountedRoot(
      testRoot.path,
    );

    expect(result.status, LinuxToGoImageStatus.supported);
    expect(result.canCreate, isTrue);
    expect(result.canCreateLinuxToGo, isTrue);
    final image = result.image;
    expect(image, isNotNull);
    expect(image!.family, LinuxToGoImageFamily.casper);
    expect(
      image.persistenceStrategy,
      LinuxToGoPersistenceStrategy.casperWritableImage,
    );
    expect(image.efiBootRelativePath, 'EFI/BOOT/BOOTX64.EFI');
    expect(image.kernelRelativePath, 'casper/vmlinuz');
    expect(image.initrdRelativePath, 'casper/initrd');
    expect(image.patchableBootConfigs, hasLength(1));
    expect(
      image.patchableBootConfigs.single.relativePath,
      'boot/grub/grub.cfg',
    );
    expect(image.livePayloads, hasLength(1));
    expect(
      image.livePayloads.single.relativePath,
      'casper/filesystem.squashfs',
    );
    expect(image.bootContentBytes, greaterThan(0));
    expect(image.totalContentBytes, greaterThan(image.bootContentBytes));
    expect(image.supportsDriverStaging, isTrue);
  });

  test('rejects a casper root without the x64 UEFI boot file', () async {
    await _writeCasperLayout(testRoot, includeEfi: false);

    final result = await LinuxToGoImagePreflightService.inspectMountedRoot(
      testRoot.path,
    );

    expect(result.status, LinuxToGoImageStatus.unsupported);
    expect(result.issue, LinuxToGoImageIssue.missingX64Efi);
    expect(result.messageKey, 'linux_togo_missing_x64_efi');
    expect(result.image, isNull);
  });

  test('rejects a casper root without a patchable GRUB entry', () async {
    await _writeCasperLayout(
      testRoot,
      grubText: 'menuentry "Live" {\n  linux /linux quiet\n}\n',
    );

    final result = await LinuxToGoImagePreflightService.inspectMountedRoot(
      testRoot.path,
    );

    expect(result.status, LinuxToGoImageStatus.unsupported);
    expect(result.issue, LinuxToGoImageIssue.noPatchableBootConfig);
    expect(result.messageKey, 'linux_togo_boot_config_unsupported');
  });

  test('identifies a Debian Live layout and explicitly rejects it', () async {
    await _writeFile(p.join(testRoot.path, 'live', 'vmlinuz'), [1]);
    await _writeFile(p.join(testRoot.path, 'live', 'initrd.img'), [2]);
    await _writeFile(p.join(testRoot.path, 'live', 'filesystem.squashfs'), [
      3,
      4,
      5,
    ]);
    await _writeFile(p.join(testRoot.path, 'EFI', 'BOOT', 'BOOTX64.EFI'), [6]);

    final result = await LinuxToGoImagePreflightService.inspectMountedRoot(
      testRoot.path,
    );

    expect(result.status, LinuxToGoImageStatus.unsupported);
    expect(result.issue, LinuxToGoImageIssue.debianLiveUnsupported);
    expect(result.messageKey, 'linux_togo_debian_live_unsupported');
  });

  test(
    'recognizes a Windows installer before classifying Linux layouts',
    () async {
      await _writeWindowsInstallerLayout(testRoot);
      await _writeCasperLayout(testRoot);

      final result = await LinuxToGoImagePreflightService.inspectMountedRoot(
        testRoot.path,
      );

      expect(result.status, LinuxToGoImageStatus.unsupported);
      expect(result.issue, LinuxToGoImageIssue.windowsInstaller);
      expect(result.messageKey, 'creator_windows_iso_in_linux_mode');
    },
  );

  test('service rejects a directory source without mounting it', () async {
    final result = await const LinuxToGoImagePreflightService().inspect(
      testRoot.path,
    );

    expect(result.status, LinuxToGoImageStatus.unsupported);
    expect(result.issue, LinuxToGoImageIssue.sourceNotRegularFile);
    expect(result.messageKey, 'linux_togo_source_not_regular_file');
  });
}

Future<void> _writeCasperLayout(
  Directory root, {
  bool includeEfi = true,
  String grubText =
      'menuentry "Live" {\n'
      '  linux /casper/vmlinuz quiet ---\n'
      '}\n',
}) async {
  await _writeFile(p.join(root.path, 'casper', 'vmlinuz'), [1]);
  await _writeFile(p.join(root.path, 'casper', 'initrd'), [2]);
  await _writeFile(p.join(root.path, 'casper', 'filesystem.squashfs'), [
    3,
    4,
    5,
  ]);
  await _writeText(p.join(root.path, 'boot', 'grub', 'grub.cfg'), grubText);
  if (includeEfi) {
    await _writeFile(p.join(root.path, 'EFI', 'BOOT', 'BOOTX64.EFI'), [6]);
  }
}

Future<void> _writeWindowsInstallerLayout(Directory root) async {
  final header = List<int>.filled(0xD0, 0);
  header.setRange(0, 8, const [0x4d, 0x53, 0x57, 0x49, 0x4d, 0, 0, 0]);
  header[8] = 0xD0;
  await _writeFile(p.join(root.path, 'sources', 'boot.wim'), header);
  await _writeFile(p.join(root.path, 'sources', 'install.wim'), header);
  await _writeFile(p.join(root.path, 'bootmgr'), [0x42]);
}

Future<void> _writeFile(String path, List<int> bytes) async {
  final file = File(path);
  await file.parent.create(recursive: true);
  await file.writeAsBytes(bytes, flush: true);
}

Future<void> _writeText(String path, String text) async {
  final file = File(path);
  await file.parent.create(recursive: true);
  await file.writeAsString(text, flush: true);
}
