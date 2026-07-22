import 'dart:async';

typedef ToGoPeriodicTimerFactory =
    Timer Function(Duration duration, void Function(Timer timer) callback);

/// A small, self-contained timer for the To Go execution view.
///
/// Deployment services can spend long periods without emitting progress. This
/// timer deliberately uses a monotonic [Stopwatch] and a one-second UI tick so
/// the elapsed duration stays accurate without coupling it to those callbacks.
class ToGoExecutionTimer {
  final Stopwatch _stopwatch;
  final ToGoPeriodicTimerFactory _periodicTimerFactory;
  final int Function()? _elapsedSecondsReader;

  Timer? _ticker;
  int _lastReportedSeconds = 0;
  int _baseSeconds = 0;

  factory ToGoExecutionTimer({
    Stopwatch? stopwatch,
    ToGoPeriodicTimerFactory periodicTimerFactory = Timer.periodic,
    int Function()? elapsedSecondsReader,
  }) => ToGoExecutionTimer._(
    stopwatch ?? Stopwatch(),
    periodicTimerFactory,
    elapsedSecondsReader,
  );

  ToGoExecutionTimer._(
    this._stopwatch,
    this._periodicTimerFactory,
    this._elapsedSecondsReader,
  );

  int get elapsedSeconds =>
      _baseSeconds +
      (_elapsedSecondsReader?.call() ?? _stopwatch.elapsed.inSeconds);

  bool get isRunning => _stopwatch.isRunning;

  void start(
    void Function(int elapsedSeconds) onTick, {
    int initialElapsedSeconds = 0,
  }) {
    stop();
    _baseSeconds = initialElapsedSeconds < 0 ? 0 : initialElapsedSeconds;
    _stopwatch
      ..reset()
      ..start();
    _lastReportedSeconds = _baseSeconds;
    _ticker = _periodicTimerFactory(const Duration(seconds: 1), (_) {
      final seconds = elapsedSeconds;
      if (seconds == _lastReportedSeconds) return;
      _lastReportedSeconds = seconds;
      onTick(seconds);
    });
  }

  void stop() {
    _ticker?.cancel();
    _ticker = null;
    _stopwatch.stop();
  }

  void reset() {
    stop();
    _stopwatch.reset();
    _lastReportedSeconds = 0;
    _baseSeconds = 0;
  }

  void dispose() => reset();
}
