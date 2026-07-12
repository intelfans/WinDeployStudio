import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:win_deploy_studio/core/services/bootable_usb_service.dart';

void main() {
  test('mke2fs path is fixed beside resolvedExecutable', () {
    final executable = p.join('C:\\', 'Program Files', 'WDS', 'WDS.exe');

    expect(
      BootableUsbService.trustedMke2fsPathForResolvedExecutable(executable),
      p.join(
        'C:\\',
        'Program Files',
        'WDS',
        'tools',
        'e2fsprogs',
        'mke2fs.exe',
      ),
    );
  });

  test('bundled mke2fs matches the pinned digest and version output', () async {
    final executable = File(p.join('tools', 'e2fsprogs', 'mke2fs.exe'));
    expect(await executable.exists(), isTrue);
    final digest = (await sha256.bind(executable.openRead()).first)
        .toString()
        .toUpperCase();
    expect(
      digest,
      'BE42ABB5D1651C8766E230E7AF834BD8E0F2085857CCB483463F58BA5AD65E1A',
    );

    final version = await Process.run(executable.path, const ['-V']);
    final output = '${version.stdout}\n${version.stderr}';
    expect(version.exitCode, 0);
    expect(BootableUsbService.isTrustedMke2fsVersionOutput(output), isTrue);
  });

  test('version validation rejects partial or different output', () {
    expect(
      BootableUsbService.isTrustedMke2fsVersionOutput(
        'mke2fs 1.47.2 (1-Jan-2025)',
      ),
      isFalse,
    );
    expect(
      BootableUsbService.isTrustedMke2fsVersionOutput(
        'mke2fs 1.47.1\nandroid-platform-15.0.0_r5-314-ga1f793f6b',
      ),
      isFalse,
    );
  });
}
