import 'package:flutter_test/flutter_test.dart';
import 'package:win_deploy_studio/core/services/wtg_service.dart';

void main() {
  test('WTG failure preserves the last reported deployment progress', () {
    const previous = WtgProgress(
      step: WtgStep.configuringImage,
      progress: 0.72,
      message: 'wtg_svc_configuring',
      writtenBytes: 1024,
      totalBytes: 1024,
    );
    const failure = WtgProgress(
      step: WtgStep.failed,
      message: 'wtg_svc_winre_failed',
      error: 'WinRE configuration failed verification.',
    );

    final result = preserveWtgFailureProgress(previous, failure);

    expect(result.step, WtgStep.failed);
    expect(result.progress, 0.72);
    expect(result.writtenBytes, 1024);
    expect(result.totalBytes, 1024);
    expect(result.message, 'wtg_svc_winre_failed');
    expect(result.error, 'WinRE configuration failed verification.');
  });

  test('WTG progress does not rewrite non-failure updates', () {
    const previous = WtgProgress(step: WtgStep.applyingImage, progress: 0.7);
    const next = WtgProgress(step: WtgStep.verifying, progress: 0.9);

    expect(preserveWtgFailureProgress(previous, next), same(next));
  });
}
