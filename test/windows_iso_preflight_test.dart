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
}

Future<void> _writeWindowsInstallerLayout(
  Directory root, {
  required WindowsInstallImageFormat format,
  bool validInstallImage = true,
  bool includeBootManager = true,
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
}

Future<void> _writeWimHeader(File file) async {
  final bytes = Uint8List(0xD0);
  bytes.setRange(0, 8, const [0x4d, 0x53, 0x57, 0x49, 0x4d, 0, 0, 0]);
  bytes[8] = 0xD0;
  await file.writeAsBytes(bytes, flush: true);
}
