import 'package:flutter_test/flutter_test.dart';

import 'package:win_deploy_studio/features/disk_tools/services/image_conversion_service.dart';

void main() {
  group('ImageConversionService classification', () {
    test('recognizes Windows image and virtual disk formats', () {
      expect(
        ImageConversionService.classifyPath('install.wim'),
        ImageConversionSourceKind.wim,
      );
      expect(
        ImageConversionService.classifyPath('install.esd'),
        ImageConversionSourceKind.esd,
      );
      expect(
        ImageConversionService.classifyPath('install2.swm'),
        ImageConversionSourceKind.swm,
      );
      expect(
        ImageConversionService.classifyPath('source.vhdx'),
        ImageConversionSourceKind.vhdx,
      );
    });

    test('keeps hybrid disk images out of ISO conversion', () {
      expect(
        ImageConversionService.classifyPath('ubuntu-live.img'),
        ImageConversionSourceKind.rawDiskImage,
      );
      expect(
        ImageConversionService.classifyPath('debian.raw'),
        ImageConversionSourceKind.rawDiskImage,
      );
    });
  });

  group('ISO volume labels', () {
    test('accepts safe labels and rejects unsafe labels', () {
      expect(
        ImageConversionService.validateVolumeLabel('WINDEPLOY_2026'),
        isNull,
      );
      expect(ImageConversionService.validateVolumeLabel(''), isNotNull);
      expect(
        ImageConversionService.validateVolumeLabel('bad/label'),
        isNotNull,
      );
      expect(
        ImageConversionService.validateVolumeLabel('a' * 33),
        'image_converter_label_too_long',
      );
    });
  });
}
