import 'package:flutter_test/flutter_test.dart';
import 'package:win_deploy_studio/features/ai_assistant/services/ai_output_safety_filter.dart';

void main() {
  test('allows ordinary deployment and diagnostics guidance', () {
    expect(
      AiOutputSafetyFilter.blocks(
        'Use a Windows 11 ISO, verify the target disk, and create UEFI media.',
      ),
      isFalse,
    );
    expect(
      AiOutputSafetyFilter.blocks(
        'The helper process was killed after its timeout.',
      ),
      isFalse,
      reason: 'technical process termination is not physical harm',
    );
    expect(
      AiOutputSafetyFilter.blocks(
        'Use Task Manager to kill a stuck process, then retry the operation.',
      ),
      isFalse,
      reason: 'standard process-management terminology must remain usable',
    );
  });

  test('blocks prohibited categories in multiple app languages', () {
    const samples = <String>[
      'Political election commentary',
      'Pornographic and sexual material',
      'Instructions involving weapons and violence',
      'Instructions to kill a person',
      '赌博和毒品内容',
      '自殺と武器に関する内容',
      'наркотики и насилие',
      'محتوى عنف وسلاح',
    ];

    for (final sample in samples) {
      expect(AiOutputSafetyFilter.blocks(sample), isTrue, reason: sample);
    }
  });
}
