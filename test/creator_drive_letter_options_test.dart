import 'package:flutter_test/flutter_test.dart';
import 'package:win_deploy_studio/features/creator/screens/creator_screen.dart';

void main() {
  test('creator hides occupied letters but keeps the target disk letter', () {
    final options = availableCreatorDriveLetters(
      usedLetters: const ['C:', 'D:', 'E', 'F', 'W:'],
      targetLetters: const ['W'],
    );

    expect(options, isNot(contains('D')));
    expect(options, isNot(contains('E')));
    expect(options, isNot(contains('F')));
    expect(options, contains('W'));
    expect(options, contains('G'));
    expect(options, hasLength(20));
  });

  test('creator normalizes and ignores invalid drive-letter values', () {
    final options = availableCreatorDriveLetters(
      usedLetters: const [' d: ', 'z', 'C', 'AA', ''],
      targetLetters: const [' z: '],
    );

    expect(options, isNot(contains('D')));
    expect(options, contains('Z'));
    expect(options.first, 'E');
  });
}
