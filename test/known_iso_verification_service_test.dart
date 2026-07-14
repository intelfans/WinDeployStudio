import 'dart:io';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:win_deploy_studio/core/services/known_iso_verification_service.dart';
import 'package:win_deploy_studio/features/mirror/models/mirror_models.dart';

void main() {
  test('matches a known image by SHA-256', () async {
    final directory = await Directory.systemTemp.createTemp('wds-known-iso-');
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}${Platform.pathSeparator}image.iso');
    await file.writeAsBytes(const [1, 2, 3, 4]);

    final service = KnownIsoVerificationService(
      knownImagesLoader: () async => [
        KnownImage.fromJson(<String, dynamic>{
          'id': 'sha-image',
          'name': <String, String>{'en': 'SHA image'},
          'sha256':
              '9F64A747E1B97F131FABB6B447296C9B6F0201E79FB3C5356E6C77E89B6A806A',
          'md5': '00000000000000000000000000000000',
        }),
      ],
    );

    final recognized = await service.verify(file.path, const Locale('en'));
    expect(recognized?.image.id, 'sha-image');
    expect(
      recognized?.sha256,
      '9f64a747e1b97f131fabb6b447296c9b6f0201e79fb3c5356e6c77e89b6a806a',
    );
  });

  test('matches by MD5 and silently ignores unknown or missing files', () async {
    final directory = await Directory.systemTemp.createTemp('wds-known-iso-');
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}${Platform.pathSeparator}image.iso');
    await file.writeAsBytes(const [1, 2, 3, 4]);
    final unknown = File(
      '${directory.path}${Platform.pathSeparator}unknown.iso',
    );
    await unknown.writeAsBytes(const [4, 3, 2, 1]);

    final service = KnownIsoVerificationService(
      knownImagesLoader: () async => [
        KnownImage.fromJson(<String, dynamic>{
          'id': 'md5-image',
          'name': <String, String>{'en': 'MD5 image'},
          // The SHA-256 is deliberately unrelated: MD5 alone must identify it.
          'sha256':
              '0000000000000000000000000000000000000000000000000000000000000000',
          'md5': '08D6C05A21512A79A1DFEB9D2A8F262F',
        }),
      ],
    );

    final recognized = await service.verify(file.path, const Locale('en'));
    expect(recognized?.image.id, 'md5-image');
    expect(recognized?.md5, '08d6c05a21512a79a1dfeb9d2a8f262f');

    expect(await service.verify(unknown.path, const Locale('en')), isNull);
    expect(
      await service.verify(
        '${directory.path}${Platform.pathSeparator}missing.iso',
        const Locale('en'),
      ),
      isNull,
    );
  });

  test('does not recognize an Enterprise image in Chinese locales', () async {
    final directory = await Directory.systemTemp.createTemp('wds-known-iso-');
    addTearDown(() => directory.delete(recursive: true));
    final file = File(
      '${directory.path}${Platform.pathSeparator}enterprise.iso',
    );
    await file.writeAsBytes(const [1, 2, 3, 4]);

    final service = KnownIsoVerificationService(
      knownImagesLoader: () async => [
        KnownImage.fromJson(<String, dynamic>{
          'id': 'ltsc-win10-enterprise',
          'name': <String, String>{'en': 'Windows 10 Enterprise LTSC'},
          'sha256':
              '9f64a747e1b97f131fabb6b447296c9b6f0201e79fb3c5356e6c77e89b6a806a',
          'md5': '08d6c05a21512a79a1dfeb9d2a8f262f',
          'visibleLocales': ['en', 'fr'],
        }),
      ],
    );

    expect(
      (await service.verify(file.path, const Locale('en')))?.image.id,
      'ltsc-win10-enterprise',
    );
    expect(await service.verify(file.path, const Locale('zh')), isNull);
    expect(await service.verify(file.path, const Locale('zh', 'TW')), isNull);
  });
}
