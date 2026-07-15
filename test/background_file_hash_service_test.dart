import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:win_deploy_studio/core/services/background_file_hash_service.dart';

void main() {
  test(
    'hashes a large file in the background with the expected digest',
    () async {
      final directory = await Directory.systemTemp.createTemp('wds-file-hash-');
      addTearDown(() => directory.delete(recursive: true));
      final content = List<int>.filled(
        BackgroundFileHashService.largeFileThresholdBytes,
        0x5a,
      );
      final file = File('${directory.path}${Platform.pathSeparator}large.bin');
      await file.writeAsBytes(content);

      expect(
        await BackgroundFileHashService.sha256File(file),
        sha256.convert(content).toString(),
      );
    },
  );
}
