import 'package:flutter_test/flutter_test.dart';
import 'package:win_deploy_studio/core/services/bootable_usb_service.dart';

void main() {
  test(
    'Linux To Go custom label is applied only to the writable NTFS data partition',
    () {
      final script = BootableUsbService.linuxToGoDiskpartScriptForTesting(
        diskNumber: 7,
        bootPartitionSizeMb: 2048,
        bootLetter: 'S',
        liveLetter: 'W',
        liveVolumeLabel: 'Portable Linux',
      );

      expect(script, contains('format fs=fat32 label="WDS_LTG" quick'));
      expect(script, contains('format fs=ntfs label="Portable Linux" quick'));
      expect(script, isNot(contains('format fs=fat32 label="Portable Linux"')));
    },
  );

  test(
    'Linux To Go keeps the boot locator independent of its visible label',
    () {
      expect(
        BootableUsbService.linuxToGoLiveMediaArgumentForTesting(
          'a1b2c3d4e5f60718',
        ),
        'live-media=/dev/disk/by-uuid/A1B2C3D4E5F60718',
      );
      expect(
        BootableUsbService.linuxToGoVolumeLabelForTesting('  我的 Linux 盘  '),
        '我的 Linux 盘',
      );
    },
  );

  test('Linux To Go reads the full 64-bit NTFS serial from fsutil output', () {
    expect(
      BootableUsbService.linuxToGoNtfsUuidFromFsutilForTesting(
        'NTFS Volume Serial Number : 0xa1b2c3d4e5f60718',
      ),
      'A1B2C3D4E5F60718',
    );
    expect(
      BootableUsbService.linuxToGoNtfsUuidFromFsutilForTesting(
        'Volume Serial Number : 0xE2CE9508',
      ),
      isNull,
    );
  });

  test('a blank Linux To Go icon writes no autorun metadata', () {
    expect(
      BootableUsbService.linuxToGoAutorunForTesting(hasCustomIcon: false),
      isEmpty,
    );
    expect(
      BootableUsbService.linuxToGoAutorunForTesting(hasCustomIcon: true),
      '[autorun]\r\nicon=.wds-drive.ico\r\n',
    );
  });

  test(
    'Linux To Go custom icon verification requires matching bytes and autorun',
    () {
      const autorun = '[autorun]\r\nicon=.wds-drive.ico\r\n';
      expect(
        BootableUsbService.linuxToGoCustomIconMatchesForTesting(
          actualDigest: 'abc',
          expectedDigest: 'abc',
          autorunText: autorun,
        ),
        isTrue,
      );
      expect(
        BootableUsbService.linuxToGoCustomIconMatchesForTesting(
          actualDigest: 'changed',
          expectedDigest: 'abc',
          autorunText: autorun,
        ),
        isFalse,
      );
      expect(
        BootableUsbService.linuxToGoCustomIconMatchesForTesting(
          actualDigest: 'abc',
          expectedDigest: 'abc',
          autorunText: '[autorun]\r\nicon=other.ico\r\n',
        ),
        isFalse,
      );
    },
  );
}
