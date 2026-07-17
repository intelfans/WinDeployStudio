import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:win_deploy_studio/core/services/linux_initrd_entry_lister.dart';
import 'package:win_deploy_studio/core/services/linux_kiwi_image_preflight.dart';

void main() {
  late Directory testRoot;

  setUp(() async {
    testRoot = await Directory.systemTemp.createTemp('wds_kiwi_image_test_');
  });

  tearDown(() async {
    if (await testRoot.exists()) await testRoot.delete(recursive: true);
  });

  test('accepts a strict KIWI persistent Live layout', () async {
    await _writeKiwiLayout(testRoot);

    final result = await LinuxKiwiImagePreflightService.inspectMountedRoot(
      testRoot.path,
    );

    expect(result.status, LinuxKiwiImageStatus.supported);
    expect(result.canCreate, isTrue);
    final image = result.image;
    expect(image, isNotNull);
    expect(image!.livePayloadRelativePath, 'LiveOS/squashfs.img');
    expect(image.livePayloadBytes, 3);
    expect(image.bootEntry.bootConfigRelativePath, 'boot/grub2/grub.cfg');
    expect(image.bootEntry.kernelRelativePath, 'boot/x86_64/loader/linux');
    expect(image.bootEntry.initrdRelativePath, 'boot/x86_64/loader/initrd');
    expect(image.bootEntry.liveCdLabel, 'openSUSE-Tumbleweed');
    expect(image.initrdCapabilities.isComplete, isTrue);
  });

  test(
    'ignores installer and checksum entries when an ordinary Live entry exists',
    () async {
      await _writeKiwiLayout(
        testRoot,
        grubText:
            'menuentry "Install" {\n'
            '  linux /boot/x86_64/loader/linux '
            'root=live:CDLABEL=openSUSE-Tumbleweed rd.live.image '
            'rd.live.overlay.persistent installer\n'
            '  initrd /boot/x86_64/loader/initrd\n'
            '}\n'
            'menuentry "Check media" {\n'
            '  linux /boot/x86_64/loader/linux '
            'root=live:CDLABEL=openSUSE-Tumbleweed rd.live.image '
            'rd.live.overlay.persistent mediacheck\n'
            '  initrd /boot/x86_64/loader/initrd\n'
            '}\n'
            'menuentry "Live" {\n'
            '  linux /boot/x86_64/loader/linux '
            'root=live:CDLABEL=openSUSE-Tumbleweed rd.live.image '
            'rd.live.overlay.persistent rd.live.overlay.cowfs=ext4\n'
            '  initrd /boot/x86_64/loader/initrd\n'
            '}\n',
      );

      final result = await LinuxKiwiImagePreflightService.inspectMountedRoot(
        testRoot.path,
      );

      expect(result.status, LinuxKiwiImageStatus.supported);
      expect(result.image!.bootEntry.liveCdLabel, 'openSUSE-Tumbleweed');
    },
  );

  test('rejects a layout without the x64 EFI fallback file', () async {
    await _writeKiwiLayout(testRoot, includeEfi: false);

    final result = await LinuxKiwiImagePreflightService.inspectMountedRoot(
      testRoot.path,
    );

    expect(result.status, LinuxKiwiImageStatus.unsupported);
    expect(result.issue, LinuxKiwiImageIssue.missingX64Efi);
    expect(result.issue!.code, 'kiwi_missing_x64_efi');
  });

  test('rejects a layout without LiveOS/squashfs.img', () async {
    await _writeKiwiLayout(testRoot, includeLivePayload: false);

    final result = await LinuxKiwiImagePreflightService.inspectMountedRoot(
      testRoot.path,
    );

    expect(result.status, LinuxKiwiImageStatus.unsupported);
    expect(result.issue, LinuxKiwiImageIssue.missingLivePayload);
  });

  test(
    'rejects a normal Live entry without KIWI persistence enabled',
    () async {
      await _writeKiwiLayout(
        testRoot,
        grubText:
            'menuentry "Live" {\n'
            '  linux /boot/x86_64/loader/linux '
            'root=live:CDLABEL=openSUSE-Tumbleweed rd.live.image\n'
            '  initrd /boot/x86_64/loader/initrd\n'
            '}\n',
      );

      final result = await LinuxKiwiImagePreflightService.inspectMountedRoot(
        testRoot.path,
      );

      expect(result.status, LinuxKiwiImageStatus.unsupported);
      expect(result.issue, LinuxKiwiImageIssue.noEligibleLiveBootEntry);
    },
  );

  test('rejects temporary and non-ext4 conflicting overlay options', () async {
    await _writeKiwiLayout(
      testRoot,
      grubText:
          'menuentry "Temporary Live" {\n'
          '  linux /boot/x86_64/loader/linux '
          'root=live:CDLABEL=openSUSE-Tumbleweed rd.live.image '
          'rd.live.overlay.persistent rd.live.overlay.temporary\n'
          '  initrd /boot/x86_64/loader/initrd\n'
          '}\n'
          'menuentry "XFS Live" {\n'
          '  linux /boot/x86_64/loader/linux '
          'root=live:CDLABEL=openSUSE-Tumbleweed rd.live.image '
          'rd.live.overlay.persistent rd.live.overlay.cowfs=xfs\n'
          '  initrd /boot/x86_64/loader/initrd\n'
          '}\n',
    );

    final result = await LinuxKiwiImagePreflightService.inspectMountedRoot(
      testRoot.path,
    );

    expect(result.status, LinuxKiwiImageStatus.unsupported);
    expect(result.issue, LinuxKiwiImageIssue.noEligibleLiveBootEntry);
  });

  test(
    'rejects installer, check, and rescue-only boot configurations',
    () async {
      await _writeKiwiLayout(
        testRoot,
        grubText:
            'menuentry "Install" {\n'
            '  linux /boot/x86_64/loader/linux '
            'root=live:CDLABEL=openSUSE-Tumbleweed rd.live.image '
            'rd.live.overlay.persistent installer\n'
            '  initrd /boot/x86_64/loader/initrd\n'
            '}\n'
            'menuentry "Rescue" {\n'
            '  linux /boot/x86_64/loader/linux '
            'root=live:CDLABEL=openSUSE-Tumbleweed rd.live.image '
            'rd.live.overlay.persistent\n'
            '  initrd /boot/x86_64/loader/initrd\n'
            '}\n',
      );

      final result = await LinuxKiwiImagePreflightService.inspectMountedRoot(
        testRoot.path,
      );

      expect(result.status, LinuxKiwiImageStatus.unsupported);
      expect(result.issue, LinuxKiwiImageIssue.noEligibleLiveBootEntry);
    },
  );

  test(
    'rejects a KIWI layout when the initrd cannot be parsed as newc CPIO',
    () async {
      await _writeKiwiLayout(testRoot, initrdBytes: const [1, 2, 3]);

      final result = await LinuxKiwiImagePreflightService.inspectMountedRoot(
        testRoot.path,
      );

      expect(result.status, LinuxKiwiImageStatus.unsupported);
      expect(result.issue, LinuxKiwiImageIssue.initrdUnreadable);
    },
  );

  test('accepts a compressed KIWI initrd only when the bounded archive listing '
      'proves every required capability', () async {
    await _writeKiwiLayout(testRoot, initrdBytes: const [0x28, 0xb5, 0x2f]);

    final result = await LinuxKiwiImagePreflightService.inspectMountedRoot(
      testRoot.path,
      initrdEntryLister: const _StaticInitrdEntryLister(
        LinuxInitrdEntryListing.success({
          'sbin/kiwi-live-root',
          'lib/kiwi-live-lib.sh',
          'usr/lib/dracut/modules.d/55kiwi-live/parse-kiwi-live.sh',
          'usr/sbin/fdisk',
          'usr/bin/partx',
          'usr/sbin/mkfs.ext4',
          'usr/bin/mount',
          'usr/sbin/blkid',
          'usr/lib/modules/test/kernel/fs/overlayfs/overlay.ko.zst',
          'usr/lib/modules/test/kernel/fs/ext4/ext4.ko.zst',
          'usr/lib/modules/test/kernel/fs/isofs/isofs.ko.zst',
        }),
      ),
    );

    expect(result.status, LinuxKiwiImageStatus.supported);
    expect(result.image!.initrdCapabilities.isComplete, isTrue);
  });

  test(
    'rejects a KIWI initrd that lacks a required disk-boot capability',
    () async {
      await _writeKiwiLayout(testRoot, includePartx: false);

      final result = await LinuxKiwiImagePreflightService.inspectMountedRoot(
        testRoot.path,
      );

      expect(result.status, LinuxKiwiImageStatus.unsupported);
      expect(result.issue, LinuxKiwiImageIssue.initrdCapabilitiesMissing);
      expect(result.diagnostic, contains('partx'));
    },
  );

  test(
    'rejects a non-ISOHybrid regular file before attempting a mount',
    () async {
      final invalidImage = File(p.join(testRoot.path, 'not-hybrid.iso'));
      await invalidImage.writeAsBytes(const [0, 1, 2, 3], flush: true);

      final result = await const LinuxKiwiImagePreflightService().inspect(
        invalidImage.path,
      );

      expect(result.status, LinuxKiwiImageStatus.unsupported);
      expect(result.issue, LinuxKiwiImageIssue.isoHybridInvalid);
    },
  );
}

Future<void> _writeKiwiLayout(
  Directory root, {
  bool includeEfi = true,
  bool includeLivePayload = true,
  bool includePartx = true,
  String? grubText,
  List<int>? initrdBytes,
}) async {
  if (includeEfi) {
    await _writeFile(p.join(root.path, 'EFI', 'BOOT', 'BOOTX64.EFI'), [1]);
  }
  if (includeLivePayload) {
    await _writeFile(p.join(root.path, 'LiveOS', 'squashfs.img'), [2, 3, 4]);
  }
  await _writeFile(p.join(root.path, 'boot', 'x86_64', 'loader', 'linux'), [5]);
  await _writeFile(
    p.join(root.path, 'boot', 'x86_64', 'loader', 'initrd'),
    initrdBytes ?? _newcArchive(_kiwiInitrdEntries(includePartx: includePartx)),
  );
  await _writeText(
    p.join(root.path, 'boot', 'grub2', 'grub.cfg'),
    grubText ??
        'menuentry "Live" {\n'
            '  linux /boot/x86_64/loader/linux '
            'root=live:CDLABEL=openSUSE-Tumbleweed rd.live.image '
            'rd.live.overlay.persistent\n'
            '  initrd /boot/x86_64/loader/initrd\n'
            '}\n',
  );
}

Map<String, List<int>> _kiwiInitrdEntries({required bool includePartx}) => {
  'sbin/kiwi-live-root': const [],
  'lib/kiwi-live-lib.sh': const [],
  'usr/lib/dracut/modules.d/55kiwi-live/parse-kiwi-live.sh': const [],
  'usr/sbin/fdisk': const [],
  if (includePartx) 'usr/bin/partx': const [],
  'usr/sbin/mkfs.ext4': const [],
  'usr/bin/mount': const [],
  'usr/sbin/blkid': const [],
  'usr/lib/modules/test/kernel/fs/overlayfs/overlay.ko.xz': const [],
  'usr/lib/modules/test/kernel/fs/ext4/ext4.ko.xz': const [],
  'usr/lib/modules/test/kernel/fs/isofs/isofs.ko.xz': const [],
};

class _StaticInitrdEntryLister implements LinuxInitrdEntryLister {
  final LinuxInitrdEntryListing result;

  const _StaticInitrdEntryLister(this.result);

  @override
  Future<LinuxInitrdEntryListing> list(File initrd) async => result;
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
