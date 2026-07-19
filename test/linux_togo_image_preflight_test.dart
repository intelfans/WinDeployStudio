import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

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

  test(
    'accepts a structurally valid Debian Live root with NTFS support',
    () async {
      await _writeDebianLayout(testRoot);

      final result = await LinuxToGoImagePreflightService.inspectMountedRoot(
        testRoot.path,
      );

      expect(result.status, LinuxToGoImageStatus.supported);
      expect(result.canCreate, isTrue);
      final image = result.image;
      expect(image, isNotNull);
      expect(image!.family, LinuxToGoImageFamily.debianLive);
      expect(
        image.persistenceStrategy,
        LinuxToGoPersistenceStrategy.debianPersistenceImage,
      );
      expect(image.kernelRelativePath, 'live/vmlinuz');
      expect(image.initrdRelativePath, 'live/initrd.img');
      expect(image.supportsDriverStaging, isFalse);
    },
  );

  test(
    'rejects Debian Live when the initrd cannot expose NTFS support',
    () async {
      await _writeDebianLayout(testRoot, includeNtfsSupport: false);

      final result = await LinuxToGoImagePreflightService.inspectMountedRoot(
        testRoot.path,
      );

      expect(result.status, LinuxToGoImageStatus.unsupported);
      expect(result.issue, LinuxToGoImageIssue.debianLiveMissingNtfsSupport);
      expect(result.messageKey, 'linux_togo_debian_live_missing_ntfs_support');
    },
  );

  test('accepts the structurally bounded Deepin Live profile', () async {
    await _writeDeepinLayout(testRoot);

    final result = await LinuxToGoImagePreflightService.inspectMountedRoot(
      testRoot.path,
      includeContentManifest: true,
    );

    expect(result.status, LinuxToGoImageStatus.supported);
    final image = result.image;
    expect(image, isNotNull);
    expect(image!.family, LinuxToGoImageFamily.deepinLive);
    expect(
      image.persistenceStrategy,
      LinuxToGoPersistenceStrategy.debianPersistenceImage,
    );
    expect(image.kernelRelativePath, 'live/vmlinuz.efi');
    expect(image.initrdRelativePath, 'live/initrd');
    expect(image.livePayloads.single.relativePath, 'live/filesys0.squ');
    expect(image.livePayloadExtensions, contains('squ'));
    expect(image.hasCompleteContentManifest, isTrue);
    expect(image.contentFiles, isNotEmpty);
    expect(
      image.contentFiles.any(
        (file) => file.relativePath == 'live/filesys0.squ',
      ),
      isTrue,
    );
  });

  test('accepts the Deepin 25 Linglong layout marker', () async {
    await _writeDeepinLayout(testRoot, useLinglongMarker: true);

    final result = await LinuxToGoImagePreflightService.inspectMountedRoot(
      testRoot.path,
      includeContentManifest: true,
    );

    expect(result.status, LinuxToGoImageStatus.supported);
    expect(result.image?.family, LinuxToGoImageFamily.deepinLive);
    expect(result.image?.kernelRelativePath, 'live/vmlinuz.efi');
    expect(result.image?.initrdRelativePath, 'live/initrd');
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

  test(
    'distinguishes Debian-style installer media from a Live source',
    () async {
      await _writeFile(p.join(testRoot.path, 'dists', 'stable', 'Release'), [
        1,
      ]);
      await _writeFile(p.join(testRoot.path, 'install', 'amd', 'initrd'), [2]);
      await _writeFile(p.join(testRoot.path, 'isolinux', 'isolinux.bin'), [3]);

      final result = await LinuxToGoImagePreflightService.inspectMountedRoot(
        testRoot.path,
      );

      expect(result.status, LinuxToGoImageStatus.unsupported);
      expect(result.issue, LinuxToGoImageIssue.installerImage);
      expect(result.messageKey, 'linux_togo_installer_image');
    },
  );

  test('explains that ArchISO Live needs its dedicated writer', () async {
    await _writeFile(p.join(testRoot.path, 'arch', 'x86_64', 'airootfs.sfs'), [
      1,
    ]);

    final result = await LinuxToGoImagePreflightService.inspectMountedRoot(
      testRoot.path,
    );

    expect(result.status, LinuxToGoImageStatus.unsupported);
    expect(result.issue, LinuxToGoImageIssue.archIsoUnsupported);
    expect(result.messageKey, 'linux_togo_arch_iso_unsupported');
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

Future<void> _writeDebianLayout(
  Directory root, {
  bool includeNtfsSupport = true,
}) async {
  await _writeFile(p.join(root.path, 'live', 'vmlinuz'), [1]);
  await _writeFile(
    p.join(root.path, 'live', 'initrd.img'),
    _newcArchive({
      'scripts/live': const [],
      if (includeNtfsSupport)
        'usr/lib/modules/test/kernel/fs/ntfs3/ntfs3.ko.xz': const [],
    }),
  );
  await _writeFile(p.join(root.path, 'live', 'filesystem.squashfs'), [3]);
  await _writeText(
    p.join(root.path, 'boot', 'grub', 'grub.cfg'),
    'menuentry "Live" {\n'
    '  linux /live/vmlinuz boot=live components ---\n'
    '}\n',
  );
  await _writeFile(p.join(root.path, 'EFI', 'BOOT', 'BOOTX64.EFI'), [6]);
}

Future<void> _writeDeepinLayout(
  Directory root, {
  bool useLinglongMarker = false,
}) async {
  await _writeFile(
    p.join(
      root.path,
      'live',
      useLinglongMarker ? 'filesystem.linglong-manifest' : 'filesyst.lin',
    ),
    [1],
  );
  await _writeFile(p.join(root.path, 'live', 'vmlinuz.efi'), [2]);
  await _writeFile(p.join(root.path, 'live', 'initrd'), [3]);
  await _writeFile(p.join(root.path, 'live', 'filesys0.squ'), [4, 5, 6]);
  await _writeText(
    p.join(root.path, 'boot', 'grub', 'grub.cfg'),
    'menuentry "Deepin" {\n'
    '  linux /live/vmlinuz.efi boot=live union=overlay ---\n'
    '}\n',
  );
  await _writeFile(p.join(root.path, 'EFI', 'BOOT', 'BOOTX64.EFI'), [7]);
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

List<int> _newcArchive(Map<String, List<int>> entries) {
  final result = BytesBuilder(copy: false);
  var inode = 1;
  void addEntry(String name, List<int> data) {
    final nameBytes = ascii.encode(name);
    String hex(int value) => value.toRadixString(16).padLeft(8, '0');
    final header = StringBuffer('070701')
      ..write(hex(inode++))
      ..write(hex(0x81a4))
      ..write(hex(0))
      ..write(hex(0))
      ..write(hex(1))
      ..write(hex(0))
      ..write(hex(data.length))
      ..write(hex(0))
      ..write(hex(0))
      ..write(hex(0))
      ..write(hex(0))
      ..write(hex(nameBytes.length + 1))
      ..write(hex(0));
    result.add(ascii.encode(header.toString()));
    result
      ..add(nameBytes)
      ..addByte(0);
    while (result.length % 4 != 0) {
      result.addByte(0);
    }
    result.add(data);
    while (result.length % 4 != 0) {
      result.addByte(0);
    }
  }

  entries.forEach(addEntry);
  addEntry('TRAILER!!!', const []);
  return result.takeBytes();
}
