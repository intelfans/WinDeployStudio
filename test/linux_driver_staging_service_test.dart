import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:win_deploy_studio/core/services/linux_driver_staging_service.dart';

void main() {
  late Directory testRoot;
  late LinuxDriverStagingService service;

  setUp(() async {
    testRoot = await Directory.systemTemp.createTemp('wds_linux_staging_test_');
    service = LinuxDriverStagingService(
      log: (_) {},
      sourceDiskRelationResolver: (_, _) async => false,
    );
  });

  tearDown(() async {
    if (await testRoot.exists()) {
      await _clearWindowsAttributes(testRoot);
      await testRoot.delete(recursive: true);
    }
  });

  test('accepts every supported Linux staging payload type', () async {
    final source = await _sourceDirectory(testRoot, 'supported');
    await _write(source, 'packages/network.deb', 'deb-content');
    await _write(source, 'packages/storage.rpm', 'rpm-content');
    await _write(source, 'packages/graphics.pkg.tar.zst', 'arch-content');
    await _write(source, 'modules/wifi.ko', 'module-content');
    await _write(source, 'modules/storage.ko.xz', 'compressed-module');
    await _write(source, 'scripts/configure.sh', '#!/bin/sh\nexit 0\n');

    final result = await service.prepare(
      sourceDirectory: source.path,
      targetDiskNumber: 9,
    );

    expect(result.success, isTrue, reason: result.error);
    expect(result.enabled, isTrue);
    expect(result.bundle!.entries, hasLength(6));
    expect(
      result.bundle!.entries.map((entry) => entry.kind).toSet(),
      LinuxStagingPayloadKind.values.toSet(),
    );
    expect(
      result.bundle!.entries.map((entry) => entry.relativePath),
      orderedEquals([
        'modules/storage.ko.xz',
        'modules/wifi.ko',
        'packages/graphics.pkg.tar.zst',
        'packages/network.deb',
        'packages/storage.rpm',
        'scripts/configure.sh',
      ]),
    );
  });

  for (final extension in ['inf', 'sys', 'cat']) {
    test('rejects Windows driver .$extension files', () async {
      final source = await _sourceDirectory(testRoot, 'windows-driver');
      await _write(source, 'driver.$extension', 'not-a-linux-driver');

      final result = await service.prepare(
        sourceDirectory: source.path,
        targetDiskNumber: 9,
      );

      expect(result.success, isFalse);
      expect(result.error, contains('cannot be injected into Linux'));
    });
  }

  for (final extension in ['exe', 'msi', 'bat', 'cmd', 'ps1', 'vbs', 'lnk']) {
    test('rejects dangerous .$extension files', () async {
      final source = await _sourceDirectory(testRoot, 'dangerous');
      await _write(source, 'payload.$extension', 'dangerous-content');

      final result = await service.prepare(
        sourceDirectory: source.path,
        targetDiskNumber: 9,
      );

      expect(result.success, isFalse);
      expect(result.error, contains('dangerous or non-Linux executable'));
    });
  }

  test('rejects empty supported files', () async {
    final source = await _sourceDirectory(testRoot, 'empty');
    await File(p.join(source.path, 'empty.deb')).create();

    final result = await service.prepare(
      sourceDirectory: source.path,
      targetDiskNumber: 9,
    );

    expect(result.success, isFalse);
    expect(result.error, contains('Empty Linux staging files'));
  });

  test('rejects duplicate kernel module names across directories', () async {
    final source = await _sourceDirectory(testRoot, 'duplicate-modules');
    await _write(source, 'first/storage.ko', 'first-module');
    await _write(source, 'second/storage.ko.xz', 'second-module');

    final result = await service.prepare(
      sourceDirectory: source.path,
      targetDiskNumber: 9,
    );

    expect(result.success, isFalse);
    expect(result.error, contains('duplicate kernel module names'));
  });

  test('rejects a symbolic link that escapes the source directory', () async {
    final source = await _sourceDirectory(testRoot, 'linked-source');
    final outside = File(p.join(testRoot.path, 'outside.deb'));
    await outside.writeAsString('outside-content');
    final link = Link(p.join(source.path, 'escaped.deb'));
    await link.create(outside.path);

    final result = await service.prepare(
      sourceDirectory: source.path,
      targetDiskNumber: 9,
    );

    expect(result.success, isFalse);
    expect(result.error, contains('Symbolic links and junctions'));
  });

  test('rejects the source directory itself when it is a link', () async {
    final actual = await _sourceDirectory(testRoot, 'actual-source');
    await _write(actual, 'driver.deb', 'deb-content');
    final linked = Link(p.join(testRoot.path, 'linked-root'));
    await linked.create(actual.path);

    final result = await service.prepare(
      sourceDirectory: linked.path,
      targetDiskNumber: 9,
    );

    expect(result.success, isFalse);
    expect(result.error, contains('cannot be a symbolic link or junction'));
  });

  test('fails closed when source disk identity cannot be resolved', () async {
    final source = await _sourceDirectory(testRoot, 'unknown-disk');
    await _write(source, 'driver.deb', 'deb-content');
    final failClosedService = LinuxDriverStagingService(
      log: (_) {},
      sourceDiskRelationResolver: (_, _) async => null,
    );

    final result = await failClosedService.prepare(
      sourceDirectory: source.path,
      targetDiskNumber: 9,
    );

    expect(result.success, isFalse);
    expect(result.error, contains('could not be verified'));
  });

  test('rejects staging stored on the target physical disk', () async {
    final source = await _sourceDirectory(testRoot, 'same-disk');
    await _write(source, 'driver.deb', 'deb-content');
    final sameDiskService = LinuxDriverStagingService(
      log: (_) {},
      sourceDiskRelationResolver: (_, targetDiskNumber) async {
        expect(targetDiskNumber, 9);
        return true;
      },
    );

    final result = await sameDiskService.prepare(
      sourceDirectory: source.path,
      targetDiskNumber: 9,
    );

    expect(result.success, isFalse);
    expect(result.error, contains('would be erased'));
  });

  test('manifest and hashes are stable across source locations', () async {
    final firstSource = await _sourceDirectory(testRoot, 'first-location');
    final secondSource = await _sourceDirectory(testRoot, 'second-location');
    for (final source in [firstSource, secondSource]) {
      await _write(source, 'packages/driver.deb', 'same-deb-content');
      await _write(source, 'scripts/setup.sh', '#!/bin/sh\necho ready\n');
    }

    final first = await service.prepare(
      sourceDirectory: firstSource.path,
      targetDiskNumber: 9,
    );
    final second = await service.prepare(
      sourceDirectory: secondSource.path,
      targetDiskNumber: 9,
    );

    expect(first.success, isTrue, reason: first.error);
    expect(second.success, isTrue, reason: second.error);
    expect(second.bundle!.manifestJson, first.bundle!.manifestJson);
    expect(second.bundle!.manifestSha256, first.bundle!.manifestSha256);
    expect(
      second.bundle!.entries.map((entry) => entry.id),
      orderedEquals(first.bundle!.entries.map((entry) => entry.id)),
    );
    expect(
      second.bundle!.entries.map((entry) => entry.sha256),
      orderedEquals(first.bundle!.entries.map((entry) => entry.sha256)),
    );

    final manifest = jsonDecode(first.bundle!.manifestJson) as Map;
    expect(manifest, isNot(contains('createdUtc')));
    expect(manifest, isNot(contains('sourceRoot')));
    expect(first.bundle!.manifestJson, isNot(contains(firstSource.path)));
  });

  test(
    'deploys NTFS bundle behind an initrd-anchored FAT32 trust root',
    () async {
      final source = await _sourceDirectory(testRoot, 'deploy-source');
      await _write(source, 'packages/network.deb', 'trusted-package');
      await _write(source, 'scripts/setup.sh', '#!/bin/sh\necho trusted\n');
      final preparation = await service.prepare(
        sourceDirectory: source.path,
        targetDiskNumber: 9,
      );
      expect(preparation.success, isTrue, reason: preparation.error);

      final boot = await _sourceDirectory(testRoot, 'boot-volume');
      final live = await _sourceDirectory(testRoot, 'live-volume');
      final bootInitrd = await _writeBytes(
        boot,
        'casper/initrd',
        utf8.encode('boot-initrd-original'),
      );
      final liveInitrd = await _writeBytes(
        live,
        'casper/initrd',
        utf8.encode('live-initrd-original'),
      );

      final result = await service.deploy(
        bundle: preparation.bundle!,
        liveDrive: live.path,
        bootDrive: boot.path,
      );

      expect(result.success, isTrue, reason: result.error);
      final bundleRoot = Directory(
        p.join(live.path, 'windeploy-studio', 'linux-staging'),
      );
      final trustRoot = Directory(
        p.join(boot.path, 'windeploy-studio', 'linux-staging-trust'),
      );
      expect(
        File(p.join(bundleRoot.path, 'manifest.json')).existsSync(),
        isTrue,
      );
      expect(File(p.join(bundleRoot.path, 'install.sh')).existsSync(), isFalse);
      expect(
        File(p.join(bundleRoot.path, 'bundle.sha256')).existsSync(),
        isFalse,
      );
      expect(File(p.join(trustRoot.path, 'install.sh')).existsSync(), isTrue);
      expect(
        File(p.join(trustRoot.path, 'bundle.sha256')).existsSync(),
        isTrue,
      );
      expect(File(p.join(trustRoot.path, 'trust.sha256')).existsSync(), isTrue);
      expect(
        File(
          p.join(trustRoot.path, LinuxDriverStagingService.serviceName),
        ).existsSync(),
        isTrue,
      );

      final trustDigest = File(
        p.join(trustRoot.path, '.trust-root'),
      ).readAsStringSync().trim();
      final bootArchiveText = latin1.decode(
        await bootInitrd.readAsBytes(),
        allowInvalid: true,
      );
      expect(bootArchiveText, contains('WDS-LTG-BOOTSTRAP-V1'));
      expect(bootArchiveText, contains(trustDigest));
      expect(
        await liveInitrd.length(),
        greaterThan('live-initrd-original'.length),
      );
      expect(
        await service.verifyDeployment(
          bundle: preparation.bundle!,
          liveDrive: live.path,
          bootDrive: boot.path,
        ),
        isTrue,
      );

      final stagedPayload = File(
        p.join(bundleRoot.path, 'payload', 'packages', 'network.deb'),
      );
      await stagedPayload.writeAsString('tampered-package', flush: true);
      expect(
        await service.verifyDeployment(
          bundle: preparation.bundle!,
          liveDrive: live.path,
          bootDrive: boot.path,
        ),
        isFalse,
      );
    },
  );

  test(
    'rolls back roots and exact initrd lengths after a late failure',
    () async {
      final source = await _sourceDirectory(testRoot, 'rollback-source');
      await _write(source, 'packages/network.deb', 'rollback-package');
      final rollbackService = LinuxDriverStagingService(
        log: (_) {},
        sourceDiskRelationResolver: (_, _) async => false,
        deploymentCheckpoint: (phase) async {
          if (phase == 'trustProtected') {
            throw StateError('injected late deployment failure');
          }
        },
      );
      final preparation = await rollbackService.prepare(
        sourceDirectory: source.path,
        targetDiskNumber: 9,
      );
      expect(preparation.success, isTrue, reason: preparation.error);

      final boot = await _sourceDirectory(testRoot, 'rollback-boot');
      final live = await _sourceDirectory(testRoot, 'rollback-live');
      final originalBoot = utf8.encode('rollback-boot-initrd');
      final originalLive = utf8.encode('rollback-live-initrd');
      final bootInitrd = await _writeBytes(boot, 'casper/initrd', originalBoot);
      final liveInitrd = await _writeBytes(live, 'casper/initrd', originalLive);

      final result = await rollbackService.deploy(
        bundle: preparation.bundle!,
        liveDrive: live.path,
        bootDrive: boot.path,
      );

      expect(result.success, isFalse);
      expect(result.error, contains('injected late deployment failure'));
      expect(await bootInitrd.readAsBytes(), orderedEquals(originalBoot));
      expect(await liveInitrd.readAsBytes(), orderedEquals(originalLive));
      expect(
        Directory(
          p.join(live.path, 'windeploy-studio', 'linux-staging'),
        ).existsSync(),
        isFalse,
      );
      expect(
        Directory(
          p.join(boot.path, 'windeploy-studio', 'linux-staging-trust'),
        ).existsSync(),
        isFalse,
      );
      final leftovers = await testRoot
          .list(recursive: true, followLinks: false)
          .where((entity) => p.basename(entity.path).endsWith('.tmp'))
          .toList();
      expect(leftovers, isEmpty);
    },
  );
}

Future<Directory> _sourceDirectory(Directory root, String name) async {
  return Directory(p.join(root.path, name)).create(recursive: true);
}

Future<void> _write(Directory root, String relativePath, String content) async {
  final file = File(p.joinAll([root.path, ...p.posix.split(relativePath)]));
  await file.parent.create(recursive: true);
  await file.writeAsString(content, flush: true);
}

Future<File> _writeBytes(
  Directory root,
  String relativePath,
  List<int> bytes,
) async {
  final file = File(p.joinAll([root.path, ...p.posix.split(relativePath)]));
  await file.parent.create(recursive: true);
  await file.writeAsBytes(bytes, flush: true);
  return file;
}

Future<void> _clearWindowsAttributes(Directory root) async {
  if (!Platform.isWindows) return;
  final paths = <String>[];
  await for (final entity in root.list(recursive: true, followLinks: false)) {
    paths.add(entity.path);
  }
  paths.sort((left, right) => right.length.compareTo(left.length));
  paths.add(root.path);
  for (final path in paths) {
    await Process.run('attrib', ['-R', '-H', '-S', path]);
  }
}
