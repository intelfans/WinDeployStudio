import 'package:flutter_test/flutter_test.dart';
import 'package:win_deploy_studio/features/benchmark/models/benchmark_models.dart';

void main() {
  test('matching is symmetric when only one side has a serial number', () {
    final left = _identity(serial: 'SERIAL-A', uniqueId: 'UID-A');
    final right = _identity(serial: '', uniqueId: 'UID-A');

    expect(left.isSameDevice(right), isTrue);
    expect(right.isSameDevice(left), isTrue);
  });

  test('a shared serial is the highest-priority identity', () {
    final left = _identity(
      serial: 'SERIAL-A',
      uniqueId: 'UID-A',
      model: 'Old Label',
    );
    final renamed = _identity(
      serial: ' serial-a ',
      uniqueId: 'UID-B',
      model: 'New Label',
    );
    final conflict = _identity(serial: 'SERIAL-B', uniqueId: 'UID-A');

    expect(left.isSameDevice(renamed), isTrue);
    expect(left.isSameDevice(conflict), isFalse);
    expect(left.stableKey, 'serial:SERIALA');
  });

  test('VID/PID agreement uses UniqueId to distinguish identical products', () {
    final left = _identity(
      serial: '',
      vid: '1234',
      pid: '5678',
      uniqueId: 'UID-A',
    );
    final same = _identity(
      serial: '',
      vid: '1234',
      pid: '5678',
      uniqueId: 'UID-A',
    );
    final otherUnit = _identity(
      serial: '',
      vid: '1234',
      pid: '5678',
      uniqueId: 'UID-B',
    );

    expect(left.isSameDevice(same), isTrue);
    expect(left.isSameDevice(otherUnit), isFalse);
    expect(otherUnit.isSameDevice(left), isFalse);
  });

  test('model, capacity, and bus are the final symmetric fallback', () {
    final left = _identity(serial: '', uniqueId: '', vid: '', pid: '');
    final same = _identity(
      serial: 'UNKNOWN',
      uniqueId: 'N/A',
      vid: '',
      pid: '',
      model: ' portable-ssd ',
    );
    final differentSize = _identity(
      serial: '',
      uniqueId: '',
      vid: '',
      pid: '',
      sizeBytes: 256000000000,
    );

    expect(left.isSameDevice(same), isTrue);
    expect(same.isSameDevice(left), isTrue);
    expect(left.isSameDevice(differentSize), isFalse);
  });

  test('model fallback preserves non-ASCII model identities', () {
    final left = _identity(
      serial: '',
      uniqueId: '',
      model: '\u79fb\u52a8\u56fa\u6001\u786c\u76d8',
    );
    final right = _identity(
      serial: '',
      uniqueId: '',
      model: ' \u79fb\u52a8\u56fa\u6001\u786c\u76d8 ',
    );

    expect(left.isSameDevice(right), isTrue);
    expect(left.stableKey, contains('\u79fb\u52a8\u56fa\u6001\u786c\u76d8'));
  });
}

BenchmarkDeviceIdentity _identity({
  String serial = 'SERIAL-A',
  String uniqueId = 'UID-A',
  String vid = '',
  String pid = '',
  String model = 'Portable SSD',
  int sizeBytes = 512000000000,
}) {
  return BenchmarkDeviceIdentity(
    diskNumber: 3,
    model: model,
    friendlyName: model,
    serialNumber: serial,
    uniqueId: uniqueId,
    vid: vid,
    pid: pid,
    busType: 'USB',
    sizeBytes: sizeBytes,
  );
}
