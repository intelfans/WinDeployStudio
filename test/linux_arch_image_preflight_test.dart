import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:win_deploy_studio/core/services/linux_arch_image_preflight.dart';
import 'package:win_deploy_studio/core/services/linux_initrd_entry_lister.dart';

void main() {
  late Directory testRoot;

  setUp(() async {
    testRoot = await Directory.systemTemp.createTemp('wds_arch_image_test_');
  });

  tearDown(() async {
    if (await testRoot.exists()) await testRoot.delete(recursive: true);
  });

  test('accepts the strict ArchISO three-partition profile', () async {
    await _writeArchLayout(testRoot);

    final result = await LinuxArchImagePreflightService.inspectMountedRoot(
      testRoot.path,
      initrdEntryLister: const _StaticEntryLister(
        LinuxInitrdEntryListing.success(_completeArchInitrdEntries),
      ),
    );

    expect(result.status, LinuxArchImageStatus.supported);
    expect(result.canCreate, isTrue);
    final image = result.image!;
    expect(image.efiBootRelativePath, 'EFI/BOOT/BOOTX64.EFI');
    expect(image.livePayloadRelativePath, 'arch/x86_64/airootfs.sfs');
    expect(
      image.bootEntry.relativePath,
      'loader/entries/01-archiso-x86_64-linux.conf',
    );
    expect(image.initrdCapabilities.isComplete, isTrue);
    expect(image.totalContentBytes, greaterThan(image.bootContentBytes));
  });

  test('rejects an Arch entry that already supplies COW state', () async {
    await _writeArchLayout(
      testRoot,
      options:
          'archisobasedir=arch archisodevice=UUID=archiso '
          'cow_device=PARTUUID=12345678-1234-1234-1234-123456789abc',
    );

    final result = await LinuxArchImagePreflightService.inspectMountedRoot(
      testRoot.path,
      initrdEntryLister: const _StaticEntryLister(
        LinuxInitrdEntryListing.success(_completeArchInitrdEntries),
      ),
    );

    expect(result.status, LinuxArchImageStatus.unsupported);
    expect(result.issue, LinuxArchImageIssue.noEligibleBootEntry);
  });

  test('accepts the current ArchISO archisosearchuuid argument', () async {
    await _writeArchLayout(
      testRoot,
      options: 'archisobasedir=arch archisosearchuuid=1234-ABCD',
    );

    final result = await LinuxArchImagePreflightService.inspectMountedRoot(
      testRoot.path,
      initrdEntryLister: const _StaticEntryLister(
        LinuxInitrdEntryListing.success(_completeArchInitrdEntries),
      ),
    );

    expect(result.status, LinuxArchImageStatus.supported);
    expect(
      result.image?.bootEntry.relativePath,
      'loader/entries/01-archiso-x86_64-linux.conf',
    );
  });

  test('rejects an Arch initrd that cannot prove NTFS support', () async {
    await _writeArchLayout(testRoot);

    final result = await LinuxArchImagePreflightService.inspectMountedRoot(
      testRoot.path,
      initrdEntryLister: const _StaticEntryLister(
        LinuxInitrdEntryListing.success({
          'usr/lib/initcpio/hooks/archiso',
          'usr/lib/modules/test/kernel/fs/ext4/ext4.ko.zst',
          'usr/lib/modules/test/kernel/fs/overlayfs/overlay.ko.zst',
        }),
      ),
    );

    expect(result.status, LinuxArchImageStatus.unsupported);
    expect(result.issue, LinuxArchImageIssue.initrdCapabilitiesMissing);
    expect(result.diagnostic, contains('NTFS'));
  });

  test('rejects an Arch root without the x64 UEFI fallback', () async {
    await _writeArchLayout(testRoot, includeEfi: false);

    final result = await LinuxArchImagePreflightService.inspectMountedRoot(
      testRoot.path,
      initrdEntryLister: const _StaticEntryLister(
        LinuxInitrdEntryListing.success(_completeArchInitrdEntries),
      ),
    );

    expect(result.status, LinuxArchImageStatus.unsupported);
    expect(result.issue, LinuxArchImageIssue.missingX64Efi);
  });
}

const _completeArchInitrdEntries = <String>{
  'usr/lib/initcpio/hooks/archiso',
  'usr/lib/modules/test/kernel/fs/ntfs3/ntfs3.ko.zst',
  'usr/lib/modules/test/kernel/fs/ext4/ext4.ko.zst',
  'usr/lib/modules/test/kernel/fs/overlayfs/overlay.ko.zst',
};

Future<void> _writeArchLayout(
  Directory root, {
  bool includeEfi = true,
  String options = 'archisobasedir=arch archisodevice=UUID=archiso',
}) async {
  if (includeEfi) {
    await _writeFile(p.join(root.path, 'EFI', 'BOOT', 'BOOTX64.EFI'), [1]);
  }
  await _writeFile(
    p.join(root.path, 'arch', 'boot', 'x86_64', 'vmlinuz-linux'),
    [2],
  );
  await _writeFile(
    p.join(root.path, 'arch', 'boot', 'x86_64', 'initramfs-linux.img'),
    [3],
  );
  await _writeFile(p.join(root.path, 'arch', 'x86_64', 'airootfs.sfs'), [
    4,
    5,
    6,
  ]);
  await _writeText(
    p.join(root.path, 'loader', 'entries', '01-archiso-x86_64-linux.conf'),
    'title Arch Linux install medium (x86_64, UEFI)\n'
    'linux /arch/boot/x86_64/vmlinuz-linux\n'
    'initrd /arch/boot/x86_64/initramfs-linux.img\n'
    'options $options\n',
  );
}

class _StaticEntryLister implements LinuxInitrdEntryLister {
  final LinuxInitrdEntryListing result;

  const _StaticEntryLister(this.result);

  @override
  Future<LinuxInitrdEntryListing> list(File initrd) async => result;
}

Future<void> _writeFile(String path, List<int> bytes) async {
  final file = File(path);
  await file.parent.create(recursive: true);
  await file.writeAsBytes(bytes, flush: true);
}

Future<void> _writeText(String path, String value) async {
  final file = File(path);
  await file.parent.create(recursive: true);
  await file.writeAsString(value, flush: true);
}
