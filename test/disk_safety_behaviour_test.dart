import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:win_deploy_studio/core/services/disk_safety_service.dart';

/// Replays recorded process transcripts instead of starting PowerShell.
class _Recorder {
  _Recorder(this.respond);

  final FutureOr<ProcessResult> Function(
    String executable,
    List<String> arguments,
    Map<String, String> environment,
  )
  respond;

  final List<({String exe, List<String> args, Map<String, String> env})> calls = [];

  Future<ProcessResult> run(
    String executable,
    List<String> arguments, {
    required Map<String, String> environment,
    required Duration timeout,
    required String timeoutMessage,
  }) async {
    calls.add((exe: executable, args: arguments, env: environment));
    return respond(executable, arguments, environment);
  }
}

DiskInfo _usbDiskFromFixture() {
  final raw = File('test/fixtures/disk_inventory_usb.json').readAsStringSync();
  final decoded = jsonDecode(raw) as Map<String, dynamic>;
  final reports = (decoded['reports'] as List).cast<Map<String, dynamic>>();
  final usb = reports.firstWhere((r) => r['diskNumber'] == 1);

  return DiskInfo(
    diskNumber: usb['diskNumber'] as int,
    model: usb['model'] as String,
    friendlyName: usb['model'] as String,
    sizeBytes: int.parse(usb['sizeBytes'] as String),
    sizeFormatted: '30.2 GB',
    serialNumber: usb['serialNumber'] as String,
    uniqueId: (usb['uniqueId'] as String?) ?? '',
    devicePath: usb['devicePath'] as String,
    busType: usb['busType'] as String,
    partitionStyle: usb['partitionStyle'] as String,
    isSystem: usb['isSystem'] as bool,
    isOffline: usb['isOffline'] as bool,
    isRemovable: usb['isRemovable'] as bool,
    driveLetters: (usb['driveLetters'] as List).cast<String>(),
  );
}

String _diskJson(DiskInfo disk, {String? model, String? bus, int? size, bool? isSystem}) {
  return jsonEncode({
    'DiskNumber': disk.diskNumber,
    'Model': model ?? disk.model,
    'FriendlyName': model ?? disk.friendlyName,
    'SizeBytes': size ?? disk.sizeBytes,
    'SerialNumber': disk.serialNumber,
    'UniqueId': disk.uniqueId,
    'DevicePath': disk.devicePath,
    'BusType': bus ?? disk.busType,
    'PartitionStyle': disk.partitionStyle,
    'IsSystem': isSystem ?? disk.isSystem,
    'IsBoot': false,
    'IsOffline': false,
    'IsRemovable': disk.isRemovable,
    'DriveLetters': disk.driveLetters,
    'Partitions': const [],
  });
}

void main() {
  late DiskInfo usb;

  setUpAll(() {
    usb = _usbDiskFromFixture();
  });

  test('the recorded fixture describes the external USB target', () {
    expect(usb.diskNumber, 1);
    expect(usb.busType, 'USB');
    expect(usb.isSystem, isFalse);
    expect(usb.sizeBytes, 32438747136);
    expect(usb.serialNumber, 'AA00000000000489');
  });

  test('a disk whose model changed between selection and use is rejected', () async {
    final recorder = _Recorder((_, _, _) async => ProcessResult(0, 0, _diskJson(usb, model: 'Other Stick'), ''));
    final service = DiskSafetyService(processRunner: recorder.run);

    final result = await service.checkDiskSafety(usb);

    expect(result.isSafe, isFalse);
    expect(result.reason, 'safety_disk_changed');
  });

  test('a disk whose size changed between selection and use is rejected', () async {
    final recorder = _Recorder((_, _, _) async => ProcessResult(0, 0, _diskJson(usb, size: 8 * 1024 * 1024 * 1024), ''));
    final service = DiskSafetyService(processRunner: recorder.run);

    final result = await service.checkDiskSafety(usb);

    expect(result.isSafe, isFalse);
    expect(result.reason, 'safety_disk_changed');
  });

  test('an internal disk that reports itself as system is refused', () async {
    final recorder = _Recorder((_, _, _) async => ProcessResult(0, 0, _diskJson(usb, isSystem: true), ''));
    final service = DiskSafetyService(processRunner: recorder.run);

    final result = await service.checkDiskSafety(usb);

    expect(result.isSafe, isFalse);
    expect(result.reason, anyOf('safety_system_disk', 'safety_disk_changed'));
  });

  test('an unknown system flag is treated as a system disk', () async {
    // Get-Disk can omit IsSystem from the report. Treating that as 'safe'
    // would let an unclassified disk be erased, so the parser must fail closed.
    final json = jsonEncode({
      'DiskNumber': usb.diskNumber,
      'Model': usb.model,
      'FriendlyName': usb.friendlyName,
      'SizeBytes': usb.sizeBytes,
      'SerialNumber': usb.serialNumber,
      'UniqueId': usb.uniqueId,
      'DevicePath': usb.devicePath,
      'BusType': usb.busType,
      'PartitionStyle': usb.partitionStyle,
      'IsSystem': null,
      'IsBoot': null,
      'IsOffline': false,
      'IsRemovable': usb.isRemovable,
      'DriveLetters': usb.driveLetters,
      'Partitions': const [],
    });
    final recorder = _Recorder((_, _, _) async => ProcessResult(0, 0, json, ''));
    final service = DiskSafetyService(processRunner: recorder.run);

    final result = await service.checkDiskSafety(usb);

    expect(result.isSafe, isFalse);
    expect(result.reason, anyOf('safety_system_disk', 'safety_disk_changed'));
  });

  test('a disk that is no longer external is refused', () async {
    final recorder = _Recorder((_, _, _) async => ProcessResult(0, 0, _diskJson(usb, bus: 'NVMe'), ''));
    final service = DiskSafetyService(processRunner: recorder.run);

    final result = await service.checkDiskSafety(usb);

    expect(result.isSafe, isFalse);
    expect(result.reason, anyOf('safety_not_external', 'safety_disk_changed'));
  });

  test('guarded diskpart is never started when the identity check fails', () async {
    final recorder = _Recorder((_, _, _) async => ProcessResult(0, 0, _diskJson(usb, model: 'Other Stick'), ''));
    final service = DiskSafetyService(processRunner: recorder.run);

    final result = await service.runGuardedDiskpart(usb, 'select disk 1\nclean\nexit');

    expect(result.exitCode, isNot(0));
    expect(result.stderr.toString(), 'safety_disk_changed');
    // Only the identity probe ran; diskpart was never invoked.
    expect(recorder.calls, hasLength(1));
    expect(recorder.calls.single.args.join(' '), isNot(contains('diskpart')));
  });

  test('the identity probe receives the selected disk number', () async {
    final recorder = _Recorder((_, _, _) async => ProcessResult(0, 0, _diskJson(usb), ''));
    final service = DiskSafetyService(processRunner: recorder.run);

    await service.refreshSelectedDisk(usb);

    expect(recorder.calls, isNotEmpty);
    expect(recorder.calls.first.env['WDS_DISK_NUMBER'], '1');
  });
}
