import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:win_deploy_studio/core/services/windows_driver_preflight.dart';

void main() {
  late Directory testRoot;

  setUp(() async {
    testRoot = await Directory.systemTemp.createTemp('wds_windows_driver_');
  });

  tearDown(() async {
    if (await testRoot.exists()) await testRoot.delete(recursive: true);
  });

  WindowsDriverPreflightService serviceFor({
    required Future<int?> Function(String path) resolveDisk,
  }) => WindowsDriverPreflightService(sourceDiskResolver: resolveDisk);

  test(
    'accepts a local Windows INF driver package without writing to it',
    () async {
      final source = await _sourceDirectory(testRoot, 'valid');
      await _writeInf(source, 'net/adapter.inf');
      await _write(source, 'net/adapter.sys', 'driver-binary');
      await _write(source, 'net/adapter.cat', 'catalog');
      final originalMtime = await File(
        p.join(source.path, 'net', 'adapter.inf'),
      ).lastModified();
      final service = serviceFor(resolveDisk: (_) async => 3);

      final result = await service.prepare(
        sourceDirectory: source.path,
        targetDiskNumber: 8,
      );

      expect(result.success, isTrue, reason: result.error);
      expect(result.enabled, isTrue);
      expect(result.fileCount, 3);
      expect(result.infCount, 1);
      expect(result.manifest!.sourceDiskNumber, 3);
      expect(
        await File(p.join(source.path, 'net', 'adapter.inf')).lastModified(),
        originalMtime,
      );
    },
  );

  test('allows no driver directory as an explicitly disabled option', () async {
    final result = await serviceFor(
      resolveDisk: (_) async => 3,
    ).prepare(sourceDirectory: '', targetDiskNumber: 8);

    expect(result.success, isTrue);
    expect(result.enabled, isFalse);
    expect(result.manifest, isNull);
  });

  test('rejects a folder with no INF driver', () async {
    final source = await _sourceDirectory(testRoot, 'no-inf');
    await _write(source, 'adapter.sys', 'driver-binary');

    final result = await serviceFor(
      resolveDisk: (_) async => 3,
    ).prepare(sourceDirectory: source.path, targetDiskNumber: 8);

    expect(result.success, isFalse);
    expect(result.errorCode, WindowsDriverPreflightError.infRequired);
    expect(result.error, contains('no INF'));
  });

  test(
    'rejects EXE or MSI installers even beside a valid INF package',
    () async {
      final source = await _sourceDirectory(testRoot, 'with-installer');
      await _writeInf(source, 'adapter.inf');
      await _write(source, 'vendor/setup.exe', 'installer');
      final service = serviceFor(resolveDisk: (_) async => 3);

      final executableResult = await service.prepare(
        sourceDirectory: source.path,
        targetDiskNumber: 8,
      );

      expect(executableResult.success, isFalse);
      expect(
        executableResult.errorCode,
        WindowsDriverPreflightError.invalidSource,
      );
      expect(executableResult.error, contains('EXE/MSI'));

      await File(p.join(source.path, 'vendor', 'setup.exe')).delete();
      await _write(source, 'vendor/setup.msi', 'installer');
      final msiResult = await service.prepare(
        sourceDirectory: source.path,
        targetDiskNumber: 8,
      );

      expect(msiResult.success, isFalse);
      expect(msiResult.errorCode, WindowsDriverPreflightError.invalidSource);
      expect(msiResult.error, contains('EXE/MSI'));
    },
  );

  test('rejects an empty or malformed INF file', () async {
    final empty = await _sourceDirectory(testRoot, 'empty-inf');
    await File(p.join(empty.path, 'adapter.inf')).create();
    final malformed = await _sourceDirectory(testRoot, 'malformed-inf');
    await _write(malformed, 'adapter.inf', 'not an INF file');
    final service = serviceFor(resolveDisk: (_) async => 3);

    final emptyResult = await service.prepare(
      sourceDirectory: empty.path,
      targetDiskNumber: 8,
    );
    final malformedResult = await service.prepare(
      sourceDirectory: malformed.path,
      targetDiskNumber: 8,
    );

    expect(emptyResult.success, isFalse);
    expect(emptyResult.errorCode, WindowsDriverPreflightError.infRequired);
    expect(malformedResult.success, isFalse);
    expect(malformedResult.errorCode, WindowsDriverPreflightError.infRequired);
    expect(malformedResult.error, contains('[Version]'));
  });

  test('rejects a source directory on the target disk', () async {
    final source = await _sourceDirectory(testRoot, 'target-disk');
    await _writeInf(source, 'adapter.inf');

    final result = await serviceFor(
      resolveDisk: (_) async => 8,
    ).prepare(sourceDirectory: source.path, targetDiskNumber: 8);

    expect(result.success, isFalse);
    expect(result.errorCode, WindowsDriverPreflightError.sourceOnTargetDisk);
    expect(result.error, contains('would be erased'));
  });

  test('fails closed when the source disk cannot be resolved', () async {
    final source = await _sourceDirectory(testRoot, 'unknown-disk');
    await _writeInf(source, 'adapter.inf');

    final result = await serviceFor(
      resolveDisk: (_) async => null,
    ).prepare(sourceDirectory: source.path, targetDiskNumber: 8);

    expect(result.success, isFalse);
    expect(result.errorCode, WindowsDriverPreflightError.invalidSource);
    expect(result.error, contains('could not be verified'));
  });

  test(
    'rejects link and junction-like entries before files are hashed',
    () async {
      final source = await _sourceDirectory(testRoot, 'linked');
      final outside = await _sourceDirectory(testRoot, 'outside');
      await _writeInf(source, 'adapter.inf');
      await _write(outside, 'payload.sys', 'outside');
      final link = Link(p.join(source.path, 'escaped.sys'));
      await link.create(p.join(outside.path, 'payload.sys'));

      final result = await serviceFor(
        resolveDisk: (_) async => 3,
      ).prepare(sourceDirectory: source.path, targetDiskNumber: 8);

      expect(result.success, isFalse);
      expect(result.errorCode, WindowsDriverPreflightError.invalidSource);
      expect(result.error, contains('symbolic links or junctions'));
    },
  );

  test('rejects a network or device source before querying its disk', () async {
    var resolverCalls = 0;
    final result = await serviceFor(
      resolveDisk: (_) async {
        resolverCalls++;
        return 3;
      },
    ).prepare(sourceDirectory: r'\\server\drivers', targetDiskNumber: 8);

    expect(result.success, isFalse);
    expect(result.errorCode, WindowsDriverPreflightError.invalidSource);
    expect(resolverCalls, 0);
  });

  test(
    'detects source changes before secure staging or DISM injection',
    () async {
      final source = await _sourceDirectory(testRoot, 'changed');
      final inf = await _writeInf(source, 'adapter.inf');
      final service = serviceFor(resolveDisk: (_) async => 3);
      final preparation = await service.prepare(
        sourceDirectory: source.path,
        targetDiskNumber: 8,
      );
      expect(preparation.success, isTrue, reason: preparation.error);

      await inf.writeAsString(
        '${await inf.readAsString()}\n; changed',
        flush: true,
      );
      final verification = await service.verify(
        manifest: preparation.manifest!,
        targetDiskNumber: 8,
      );

      expect(verification.success, isFalse);
      expect(verification.errorCode, WindowsDriverPreflightError.sourceChanged);
      expect(verification.error, contains('changed after preflight'));
    },
  );

  test('detects a link added after selection', () async {
    final source = await _sourceDirectory(testRoot, 'link-added');
    await _writeInf(source, 'adapter.inf');
    final service = serviceFor(resolveDisk: (_) async => 3);
    final preparation = await service.prepare(
      sourceDirectory: source.path,
      targetDiskNumber: 8,
    );
    expect(preparation.success, isTrue, reason: preparation.error);
    final outside = File(p.join(testRoot.path, 'outside.sys'));
    await outside.writeAsString('outside', flush: true);
    await Link(p.join(source.path, 'later.sys')).create(outside.path);

    final verification = await service.verify(
      manifest: preparation.manifest!,
      targetDiskNumber: 8,
    );

    expect(verification.success, isFalse);
    expect(verification.errorCode, WindowsDriverPreflightError.sourceChanged);
    expect(verification.error, contains('symbolic link'));
  });
}

Future<Directory> _sourceDirectory(Directory root, String name) =>
    Directory(p.join(root.path, name)).create(recursive: true);

Future<File> _write(Directory root, String relativePath, String content) async {
  final file = File(p.joinAll([root.path, ...p.posix.split(relativePath)]));
  await file.parent.create(recursive: true);
  await file.writeAsString(content, flush: true);
  return file;
}

Future<File> _writeInf(Directory root, String relativePath) =>
    _write(root, relativePath, '''[Version]
Signature="\$Windows NT\$"
Class=Net
ClassGuid={4d36e972-e325-11ce-bfc1-08002be10318}
Provider=%ProviderName%

[Manufacturer]
%ProviderName%=Models,NTamd64
''');
