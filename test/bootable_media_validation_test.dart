import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:win_deploy_studio/core/services/bootable_media_validation.dart';

void main() {
  test('accepts a well-formed ICO directory', () {
    final bytes = Uint8List.fromList(const [
      0,
      0,
      1,
      0,
      1,
      0,
      16,
      16,
      0,
      0,
      1,
      0,
      32,
      0,
      4,
      0,
      0,
      0,
      22,
      0,
      0,
      0,
      40,
      0,
      0,
      0,
    ]);

    expect(validateIcoBytes(bytes), isNull);
  });

  test('rejects ICO entries whose payload is outside the file', () {
    final bytes = Uint8List(22);
    bytes[2] = 1;
    bytes[4] = 1;
    bytes[14] = 40;
    bytes[18] = 0xff;

    expect(validateIcoBytes(bytes), contains('outside the file'));
  });

  test('robocopy accepts only exit codes zero through three', () {
    for (final code in [0, 1, 2, 3]) {
      expect(isAcceptedRobocopyExitCode(code), isTrue, reason: 'code $code');
    }
    for (final code in [-1, 4, 5, 6, 7, 8, 16]) {
      expect(isAcceptedRobocopyExitCode(code), isFalse, reason: 'code $code');
    }
  });
}
