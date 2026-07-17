import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:win_deploy_studio/core/services/windows_iso_preflight.dart';

void main() {
  late Directory testRoot;

  setUp(() async {
    testRoot = await Directory.systemTemp.createTemp('wds_windows_iso_test_');
  });

  tearDown(() async {
    if (await testRoot.exists()) await testRoot.delete(recursive: true);
  });

  for (final format in WindowsInstallImageFormat.values) {
    test(
      'accepts a structurally valid ${format.name} Windows installer',
      () async {
        await _writeWindowsInstallerLayout(testRoot, format: format);

        final inspection = await WindowsIsoLayoutInspector.inspectMountedRoot(
          testRoot.path,
        );

        expect(inspection.isValid, isTrue, reason: inspection.error);
        expect(inspection.imageFormat, format);
        expect(inspection.imagePath, endsWith('install.${format.name}'));
      },
    );
  }

  test('rejects a Linux-like layout without Windows setup markers', () async {
    await Directory(p.join(testRoot.path, 'casper')).create(recursive: true);
    await File(p.join(testRoot.path, 'casper', 'vmlinuz')).writeAsBytes([1]);
    await File(p.join(testRoot.path, 'casper', 'initrd')).writeAsBytes([2]);

    final inspection = await WindowsIsoLayoutInspector.inspectMountedRoot(
      testRoot.path,
    );

    expect(inspection.isValid, isFalse);
    expect(inspection.error, contains('boot.wim'));
  });

  test('rejects an installer image with a fake WIM extension', () async {
    await _writeWindowsInstallerLayout(
      testRoot,
      format: WindowsInstallImageFormat.wim,
      validInstallImage: false,
    );

    final inspection = await WindowsIsoLayoutInspector.inspectMountedRoot(
      testRoot.path,
    );

    expect(inspection.isValid, isFalse);
    expect(inspection.error, contains('install.wim'));
  });

  test('rejects a layout without a Windows boot manager', () async {
    await _writeWindowsInstallerLayout(
      testRoot,
      format: WindowsInstallImageFormat.esd,
      includeBootManager: false,
    );

    final inspection = await WindowsIsoLayoutInspector.inspectMountedRoot(
      testRoot.path,
    );

    expect(inspection.isValid, isFalse);
    expect(inspection.error, contains('boot manager'));
  });

  test('reports BIOS, UEFI architecture, and FAT32 metadata', () async {
    await _writeWindowsInstallerLayout(
      testRoot,
      format: WindowsInstallImageFormat.wim,
      includeBiosBcd: true,
      includeEfiBcd: true,
      efiFallbackArchitecture: WindowsEfiBootArchitecture.x64,
    );

    final inspection = await WindowsIsoLayoutInspector.inspectMountedRoot(
      testRoot.path,
    );

    expect(inspection.isValid, isTrue, reason: inspection.error);
    expect(inspection.hasBiosBootManager, isTrue);
    expect(inspection.hasBiosBcd, isTrue);
    expect(inspection.hasEfiBcd, isTrue);
    expect(
      inspection.efiBootArchitectures,
      contains(WindowsEfiBootArchitecture.x64),
    );
    expect(inspection.installImageBytes, greaterThan(0));
    expect(
      inspection.totalFileBytes,
      greaterThan(inspection.installImageBytes),
    );
    expect(inspection.fat32OversizedFiles, isEmpty);
  });

  test(
    'reports a missing UEFI BCD without treating the ISO as Windows-invalid',
    () async {
      await _writeWindowsInstallerLayout(
        testRoot,
        format: WindowsInstallImageFormat.wim,
        efiFallbackArchitecture: WindowsEfiBootArchitecture.x64,
      );

      final inspection = await WindowsIsoLayoutInspector.inspectMountedRoot(
        testRoot.path,
      );

      expect(inspection.isValid, isTrue, reason: inspection.error);
      expect(inspection.hasEfiBcd, isFalse);
    },
  );

  test(
    'reports the executable architecture instead of trusting its file name',
    () async {
      final efi = File(p.join(testRoot.path, 'EFI', 'Boot', 'bootx64.efi'));
      await _writeEfiBinary(efi, WindowsEfiBootArchitecture.arm64);

      expect(
        await WindowsIsoLayoutInspector.readEfiArchitecture(efi.path),
        WindowsEfiBootArchitecture.arm64,
      );
    },
  );

  test(
    'does not trust an EFI fallback file with the wrong PE architecture',
    () async {
      await _writeWindowsInstallerLayout(
        testRoot,
        format: WindowsInstallImageFormat.wim,
        efiFallbackArchitecture: WindowsEfiBootArchitecture.arm64,
        efiFallbackFileName: 'bootx64.efi',
      );

      final inspection = await WindowsIsoLayoutInspector.inspectMountedRoot(
        testRoot.path,
      );

      expect(inspection.isValid, isTrue, reason: inspection.error);
      expect(inspection.efiBootArchitectures, isEmpty);
    },
  );

  test('records files that cannot be copied to FAT32', () async {
    await _writeWindowsInstallerLayout(
      testRoot,
      format: WindowsInstallImageFormat.wim,
    );
    final oversized = File(p.join(testRoot.path, 'sources', 'payload.bin'));
    final handle = await oversized.open(mode: FileMode.write);
    await handle.setPosition(WindowsIsoLayoutInspector.fat32MaximumFileBytes);
    await handle.writeByte(0);
    await handle.close();

    final inspection = await WindowsIsoLayoutInspector.inspectMountedRoot(
      testRoot.path,
    );

    expect(inspection.isValid, isTrue, reason: inspection.error);
    expect(inspection.fat32OversizedFiles, hasLength(1));
    expect(
      inspection.fat32OversizedFiles.single.relativePath,
      endsWith(r'sources\payload.bin'),
    );
  });
}

Future<void> _writeWindowsInstallerLayout(
  Directory root, {
  required WindowsInstallImageFormat format,
  bool validInstallImage = true,
  bool includeBootManager = true,
  bool includeBiosBcd = false,
  bool includeEfiBcd = false,
  WindowsEfiBootArchitecture? efiFallbackArchitecture,
  String? efiFallbackFileName,
}) async {
  final sources = Directory(p.join(root.path, 'sources'));
  await sources.create(recursive: true);
  await _writeWimHeader(File(p.join(sources.path, 'boot.wim')));
  final installImage = File(p.join(sources.path, 'install.${format.name}'));
  if (validInstallImage) {
    await _writeWimHeader(installImage);
  } else {
    await installImage.writeAsBytes(Uint8List(0xD0), flush: true);
  }
  if (includeBootManager) {
    await File(p.join(root.path, 'bootmgr')).writeAsBytes([0x42], flush: true);
  }
  if (includeBiosBcd) {
    final bcd = File(p.join(root.path, 'boot', 'BCD'));
    await bcd.parent.create(recursive: true);
    await bcd.writeAsBytes([0x42]);
  }
  if (includeEfiBcd) {
    final bcd = File(p.join(root.path, 'EFI', 'Microsoft', 'Boot', 'BCD'));
    await bcd.parent.create(recursive: true);
    await bcd.writeAsBytes([0x42]);
  }
  if (efiFallbackArchitecture != null) {
    final fallbackName =
        efiFallbackFileName ??
        switch (efiFallbackArchitecture) {
          WindowsEfiBootArchitecture.x64 => 'bootx64.efi',
          WindowsEfiBootArchitecture.arm64 => 'bootaa64.efi',
          WindowsEfiBootArchitecture.ia32 => 'bootia32.efi',
        };
    await _writeEfiBinary(
      File(p.join(root.path, 'EFI', 'Boot', fallbackName)),
      efiFallbackArchitecture,
    );
  }
}

Future<void> _writeWimHeader(File file) async {
  final bytes = Uint8List(0xD0);
  bytes.setRange(0, 8, const [0x4d, 0x53, 0x57, 0x49, 0x4d, 0, 0, 0]);
  bytes[8] = 0xD0;
  await file.writeAsBytes(bytes, flush: true);
}

Future<void> _writeEfiBinary(
  File file,
  WindowsEfiBootArchitecture architecture,
) async {
  await file.parent.create(recursive: true);
  final machine = switch (architecture) {
    WindowsEfiBootArchitecture.x64 => 0x8664,
    WindowsEfiBootArchitecture.arm64 => 0xaa64,
    WindowsEfiBootArchitecture.ia32 => 0x014c,
  };
  final bytes = Uint8List(0x80);
  bytes[0] = 0x4d;
  bytes[1] = 0x5a;
  bytes[0x3c] = 0x40;
  bytes[0x40] = 0x50;
  bytes[0x41] = 0x45;
  bytes[0x44] = machine & 0xff;
  bytes[0x45] = machine >> 8;
  await file.writeAsBytes(bytes, flush: true);
}
