import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
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
    'Linux persistence stays disabled without a compliant release bundle',
    () {
      expect(
        BootableUsbService.linuxPersistenceToolDistributionApproved,
        isFalse,
      );
    },
  );

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
  });
}
