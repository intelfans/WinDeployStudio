import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:win_deploy_studio/features/wtg/models/to_go_execution_timer.dart';

void main() {
  test('timer reports elapsed time independently and stops cleanly', () {
    var elapsed = 0;
    late _ManualTimer scheduledTimer;
    late void Function(Timer) tick;
    final reported = <int>[];
    final timer = ToGoExecutionTimer(
      elapsedSecondsReader: () => elapsed,
      periodicTimerFactory: (_, callback) {
        tick = callback;
        scheduledTimer = _ManualTimer();
        return scheduledTimer;
      },
    );

    timer.start(reported.add);
    expect(timer.isRunning, isTrue);
    expect(reported, isEmpty);

    elapsed = 1;
    scheduledTimer.fire(tick);
    scheduledTimer.fire(tick);
    elapsed = 4;
    scheduledTimer.fire(tick);
    expect(reported, <int>[1, 4]);

    timer.stop();
    expect(timer.isRunning, isFalse);
    elapsed = 5;
    scheduledTimer.fire(tick);
    expect(reported, <int>[1, 4]);

    timer.dispose();
    expect(scheduledTimer.isActive, isFalse);
  });
}

class _ManualTimer implements Timer {
  bool _isActive = true;
  var _tick = 0;

  @override
  bool get isActive => _isActive;

  @override
  int get tick => _tick;

  @override
  void cancel() {
    _isActive = false;
  }

  void fire(void Function(Timer) callback) {
    if (!_isActive) return;
    _tick++;
    callback(this);
  }
}
