import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:win_deploy_studio/core/services/background_file_hash_service.dart';
import 'package:win_deploy_studio/core/services/bootable_usb_service.dart';
import 'package:win_deploy_studio/core/services/linux_togo_image_preflight.dart';

void main() {
  test(
    'release tree excludes e2fsprogs binaries until source obligations are met',
    () async {
      final executable = File('tools/e2fsprogs/mke2fs.exe');
      final notice = File('tools/e2fsprogs/README.md');
      expect(await executable.exists(), isFalse);
      expect(await notice.exists(), isTrue);
      expect(
        await notice.readAsString(),
        contains('Complete corresponding source'),
      );
    },
  );

  test(
    'bundles the audited ext4 helper while keeping e2fsprogs excluded',
    () async {
      final executable = File('tools/ext4-builder/wds_ext4_builder.exe');
      final notice = File('tools/ext4-builder/README.md');
      expect(await executable.exists(), isTrue);
      expect(await notice.exists(), isTrue);
      expect(
        await BackgroundFileHashService.sha256File(executable),
        '85f4c3e74f6e005ecf94e0d688e1de6d35b715af21716151c4a23e9f52ab6184',
      );
      expect(await notice.readAsString(), contains('Upstream license: MIT'));
    },
  );

  test('Linux persistence is enabled for the audited release bundle', () {
    expect(BootableUsbService.linuxPersistenceToolDistributionApproved, isTrue);
  });

  test('casper and Debian retain separate persistence contracts', () {
    expect(
      BootableUsbService.linuxToGoPersistenceFileNameForFamily(
        LinuxToGoImageFamily.casper,
      ),
      'writable',
    );
    expect(
      BootableUsbService.linuxToGoPersistenceArgumentForFamily(
        LinuxToGoImageFamily.casper,
      ),
      'persistent',
    );
    expect(
      BootableUsbService.linuxToGoPersistenceFileNameForFamily(
        LinuxToGoImageFamily.debianLive,
      ),
      'persistence',
    );
    expect(
      BootableUsbService.linuxToGoPersistenceArgumentForFamily(
        LinuxToGoImageFamily.debianLive,
      ),
      'persistence',
    );
    expect(
      BootableUsbService.linuxToGoPersistenceFileNameForFamily(
        LinuxToGoImageFamily.deepinLive,
      ),
      'persistence',
    );
  });
}
