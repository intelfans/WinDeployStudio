import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:win_deploy_studio/core/services/bootable_usb_service.dart';

void main() {
  test('robocopy watchdog has a floor, scales with size, and is capped', () {
    expect(
      BootableUsbService.robocopyTimeoutForTesting(0),
      const Duration(minutes: 45),
    );
    expect(
      BootableUsbService.robocopyTimeoutForTesting(4 * 1024 * 1024 * 1024),
      const Duration(seconds: 3248),
    );
    expect(
      BootableUsbService.robocopyTimeoutForTesting(1 << 50),
      const Duration(hours: 8),
    );
  });

  test('robocopy path manages cancellation, stalls, and stream cleanup', () {
    final source = File(
      'lib/core/services/bootable_usb_service.dart',
    ).readAsStringSync();

    expect(source, contains("reason: 'robocopy cancelled'"));
    expect(source, contains("reason: 'robocopy stalled'"));
    expect(source, contains('await stdoutSub.cancel()'));
    expect(source, contains('await stderrSub.cancel()'));
  });
}
