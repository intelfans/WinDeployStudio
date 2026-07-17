import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:win_deploy_studio/core/services/linux_media_preflight.dart';

void main() {
  late Directory testRoot;

  setUp(() async {
    testRoot = await Directory.systemTemp.createTemp('wds_iso_preflight_test_');
  });

  tearDown(() async {
    if (await testRoot.exists()) await testRoot.delete(recursive: true);
  });

  test(
    'accepts ISOHybrid with ISO9660, El Torito, and EFI FAT image',
    () async {
      final image = File('${testRoot.path}${Platform.pathSeparator}valid.iso');
      await image.writeAsBytes(_buildIsoHybridFixture(), flush: true);

      final result = await LinuxIsoHybridInspector.inspect(image.path);

      expect(result.isValid, isTrue, reason: result.error);
      expect(result.bootCatalogLba, 20);
      expect(result.efiImageLba, 30);
      expect(result.hasLegacyBiosBoot, isTrue);
      expect(result.hasUefiBoot, isTrue);
    },
  );

  test('returns a distinct cancellation result before starting I/O', () async {
    final image = File('${testRoot.path}${Platform.pathSeparator}valid.iso');
    await image.writeAsBytes(_buildIsoHybridFixture(), flush: true);
    final cancellation = LinuxIsoHybridInspectionCancellationToken()..cancel();

    final result = await LinuxIsoHybridInspector.inspect(
      image.path,
      cancellationToken: cancellation,
    );

    expect(result.isValid, isFalse);
    expect(result.wasCancelled, isTrue);
    expect(result.error, isNull);
  });

  test('rejects a hybrid MBR without ISO9660 descriptors', () async {
    final bytes = _buildIsoHybridFixture();
    bytes.fillRange(16 * 2048 + 1, 16 * 2048 + 6, 0);
    final image = File('${testRoot.path}${Platform.pathSeparator}no-pvd.iso');
    await image.writeAsBytes(bytes, flush: true);

    final result = await LinuxIsoHybridInspector.inspect(image.path);

    expect(result.isValid, isFalse);
    expect(result.error, contains('ISO9660'));
  });

  test('rejects an El Torito catalog with a bad checksum', () async {
    final bytes = _buildIsoHybridFixture();
    bytes[20 * 2048 + 4] ^= 0x01;
    final image = File('${testRoot.path}${Platform.pathSeparator}bad-cat.iso');
    await image.writeAsBytes(bytes, flush: true);

    final result = await LinuxIsoHybridInspector.inspect(image.path);

    expect(result.isValid, isFalse);
    expect(result.error, contains('checksum'));
  });

  test(
    'accepts a BIOS-only ISOHybrid without inventing UEFI support',
    () async {
      final bytes = _buildIsoHybridFixture();
      bytes.fillRange(20 * 2048 + 64, 20 * 2048 + 128, 0);
      final image = File(
        '${testRoot.path}${Platform.pathSeparator}bios-only.iso',
      );
      await image.writeAsBytes(bytes, flush: true);

      final result = await LinuxIsoHybridInspector.inspect(image.path);

      expect(result.isValid, isTrue, reason: result.error);
      expect(result.hasLegacyBiosBoot, isTrue);
      expect(result.hasUefiBoot, isFalse);
      expect(result.efiImageLba, 0);
    },
  );

  test(
    'reports standard x64 EFI fallback when the image advertises it',
    () async {
      final bytes = _buildIsoHybridFixture();
      _writeAscii(bytes, 30 * 2048 + 128, 'BOOTX64 EFI');
      final image = File('${testRoot.path}${Platform.pathSeparator}x64.iso');
      await image.writeAsBytes(bytes, flush: true);

      final result = await LinuxIsoHybridInspector.inspect(image.path);

      expect(result.isValid, isTrue, reason: result.error);
      expect(result.efiArchitectures, contains(LinuxEfiArchitecture.x64));
    },
  );

  test(
    'reports a UEFI-only image without inventing Legacy BIOS support',
    () async {
      final bytes = _buildIsoHybridFixture();
      const catalog = 20 * 2048;
      bytes[catalog + 1] = 0xef;
      _writeUint32(bytes, catalog + 32 + 8, 30);
      bytes.fillRange(catalog + 64, catalog + 128, 0);
      _recalculateCatalogChecksum(bytes);
      final image = File(
        '${testRoot.path}${Platform.pathSeparator}uefi-only.iso',
      );
      await image.writeAsBytes(bytes, flush: true);

      final result = await LinuxIsoHybridInspector.inspect(image.path);

      expect(result.isValid, isTrue, reason: result.error);
      expect(result.hasLegacyBiosBoot, isFalse);
      expect(result.hasUefiBoot, isTrue);
    },
  );

  test('rejects a malformed declared EFI boot image', () async {
    final bytes = _buildIsoHybridFixture();
    bytes[30 * 2048] = 0;
    final image = File(
      '${testRoot.path}${Platform.pathSeparator}bad-efi-image.iso',
    );
    await image.writeAsBytes(bytes, flush: true);

    final result = await LinuxIsoHybridInspector.inspect(image.path);

    expect(result.isValid, isFalse);
    expect(result.error, contains('FAT boot image'));
  });

  test('raw verification timeout scales with image size', () {
    expect(
      linuxRawVerificationTimeoutForBytes(0),
      linuxRawVerificationStartupAllowance,
    );
    expect(
      linuxRawVerificationTimeoutForBytes(8 * 1024 * 1024),
      const Duration(seconds: 122),
    );
    expect(
      linuxRawVerificationTimeoutForBytes(64 * 1024 * 1024 * 1024),
      greaterThan(const Duration(hours: 4)),
    );
  });

  test('raw writing timeout allows very slow external media', () {
    expect(
      linuxRawWriteTimeoutForBytes(8 * 1024 * 1024),
      const Duration(seconds: 128),
    );
    expect(
      linuxRawWriteTimeoutForBytes(64 * 1024 * 1024 * 1024),
      greaterThan(const Duration(hours: 18)),
    );
  });
}

Uint8List _buildIsoHybridFixture() {
  const sectors = 96;
  final bytes = Uint8List(sectors * 2048);

  bytes[510] = 0x55;
  bytes[511] = 0xaa;
  bytes[446 + 4] = 0x17;
  _writeUint32(bytes, 446 + 8, 1);
  _writeUint32(bytes, 446 + 12, sectors * 4 - 1);

  final pvd = 16 * 2048;
  bytes[pvd] = 1;
  _writeAscii(bytes, pvd + 1, 'CD001');
  bytes[pvd + 6] = 1;
  _writeUint32(bytes, pvd + 80, sectors);
  _writeUint32BigEndian(bytes, pvd + 84, sectors);
  _writeUint16(bytes, pvd + 128, 2048);
  _writeUint16BigEndian(bytes, pvd + 130, 2048);

  final bootRecord = 17 * 2048;
  bytes[bootRecord] = 0;
  _writeAscii(bytes, bootRecord + 1, 'CD001');
  bytes[bootRecord + 6] = 1;
  _writeAscii(bytes, bootRecord + 7, 'EL TORITO SPECIFICATION');
  _writeUint32(bytes, bootRecord + 71, 20);

  final terminator = 18 * 2048;
  bytes[terminator] = 255;
  _writeAscii(bytes, terminator + 1, 'CD001');
  bytes[terminator + 6] = 1;

  final catalog = 20 * 2048;
  bytes[catalog] = 1;
  bytes[catalog + 1] = 0;
  bytes[catalog + 30] = 0x55;
  bytes[catalog + 31] = 0xaa;
  var sum = 0;
  for (var offset = 0; offset < 32; offset += 2) {
    sum =
        (sum + bytes[catalog + offset] + (bytes[catalog + offset + 1] << 8)) &
        0xffff;
  }
  _writeUint16(bytes, catalog + 28, (-sum) & 0xffff);

  bytes[catalog + 32] = 0x88;
  _writeUint16(bytes, catalog + 32 + 6, 4);
  _writeUint32(bytes, catalog + 32 + 8, 25);

  bytes[catalog + 64] = 0x91;
  bytes[catalog + 65] = 0xef;
  _writeUint16(bytes, catalog + 66, 1);
  bytes[catalog + 96] = 0x88;
  _writeUint16(bytes, catalog + 96 + 6, 4);
  _writeUint32(bytes, catalog + 96 + 8, 30);

  final fat = 30 * 2048;
  bytes[fat] = 0xeb;
  bytes[fat + 1] = 0x3c;
  bytes[fat + 2] = 0x90;
  _writeUint16(bytes, fat + 11, 512);
  bytes[fat + 13] = 1;
  _writeUint16(bytes, fat + 19, 4);
  _writeAscii(bytes, fat + 54, 'FAT16   ');
  bytes[fat + 510] = 0x55;
  bytes[fat + 511] = 0xaa;

  return bytes;
}

void _writeAscii(Uint8List bytes, int offset, String value) {
  bytes.setRange(offset, offset + value.length, value.codeUnits);
}

void _recalculateCatalogChecksum(Uint8List bytes) {
  const catalog = 20 * 2048;
  _writeUint16(bytes, catalog + 28, 0);
  var sum = 0;
  for (var offset = 0; offset < 32; offset += 2) {
    sum =
        (sum + bytes[catalog + offset] + (bytes[catalog + offset + 1] << 8)) &
        0xffff;
  }
  _writeUint16(bytes, catalog + 28, (-sum) & 0xffff);
}

void _writeUint16(Uint8List bytes, int offset, int value) {
  bytes[offset] = value & 0xff;
  bytes[offset + 1] = (value >> 8) & 0xff;
}

void _writeUint16BigEndian(Uint8List bytes, int offset, int value) {
  bytes[offset] = (value >> 8) & 0xff;
  bytes[offset + 1] = value & 0xff;
}

void _writeUint32(Uint8List bytes, int offset, int value) {
  for (var index = 0; index < 4; index++) {
    bytes[offset + index] = (value >> (index * 8)) & 0xff;
  }
}

void _writeUint32BigEndian(Uint8List bytes, int offset, int value) {
  for (var index = 0; index < 4; index++) {
    bytes[offset + index] = (value >> ((3 - index) * 8)) & 0xff;
  }
}
