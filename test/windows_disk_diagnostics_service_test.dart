import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:win_deploy_studio/features/disk_tools/models/disk_diagnostic_models.dart';
import 'package:win_deploy_studio/features/disk_tools/services/secure_powershell_runner.dart';
import 'package:win_deploy_studio/features/disk_tools/services/windows_disk_diagnostics_service.dart';

void main() {
  group('WindowsDiskDiagnosticsService native inventory', () {
    test(
      'parses a partial read-only native inventory without PowerShell',
      () async {
        final directory = await Directory.systemTemp.createTemp(
          'wds_disk_diagnostics_test_',
        );
        final helper = File(
          '${directory.path}\\wds_disk_diagnostics_helper.exe',
        );
        await helper.create();
        final process = _FakeNativeProcess(710);
        process.complete(
          stdout: jsonEncode({
            'ok': true,
            'isAdministrator': false,
            'warnings': [
              {'code': 'disk_diag_warning_partial'},
            ],
            'reports': [
              {
                'diskNumber': 0,
                'model': 'Example NVMe',
                'sizeBytes': '1024',
                'busType': 'NVMe',
                'health': 'healthy',
                'healthSource': 'Intel RST NVMe miniport protocol',
                'devicePath': r'\\.\PhysicalDrive0',
                'isSystem': true,
                'isBoot': true,
                'isOffline': false,
                'isReadOnly': false,
                'isRemovable': false,
                'nvme': {
                  'available': true,
                  'source': 'Intel RST NVMe miniport protocol',
                  'temperatureCelsius': 31,
                  'percentageUsed': 7,
                  'hostReadBytes': '512000',
                  'hostWrittenBytes': '1024000',
                  'hostReadCommands': '20',
                  'hostWriteCommands': '10',
                  'powerOnHours': '42',
                  'mediaAndDataIntegrityErrors': '0',
                },
              },
            ],
          }),
        );
        final service = WindowsDiskDiagnosticsService(
          helperPath: () => helper.path,
          nativeProcessStarter: (_, _) async => process,
        );

        try {
          final snapshot = await service.collect();

          expect(snapshot.isAdministrator, isFalse);
          expect(snapshot.collectionWarnings, const [
            'disk_diag_warning_partial',
          ]);
          expect(snapshot.reports, hasLength(1));
          final report = snapshot.reports.single;
          expect(report.model.value, 'Example NVMe');
          expect(report.temperatureCelsius.value, 31);
          expect(
            report.temperatureCelsius.source,
            'Intel RST NVMe miniport protocol',
          );
          expect(report.wearPercent.value, 7);
          expect(report.estimatedRemainingLifePercent.value, 93);
          expect(report.hostWrittenBytes.value, BigInt.from(1024000));
          expect(report.isSystem.value, isTrue);
          expect(report.isBoot.value, isTrue);
          expect(report.isOffline.value, isFalse);
        } finally {
          await directory.delete(recursive: true);
        }
      },
      skip: !Platform.isWindows,
    );

    test(
      'keeps omitted disk flags unknown and classifies native unavailability',
      () async {
        final directory = await Directory.systemTemp.createTemp(
          'wds_disk_diagnostics_test_',
        );
        final helper = File(
          '${directory.path}\\wds_disk_diagnostics_helper.exe',
        );
        await helper.create();
        final process = _FakeNativeProcess(714);
        process.complete(
          stdout: jsonEncode({
            'ok': true,
            'isAdministrator': true,
            'reports': [
              {
                'diskNumber': 2,
                'model': 'USB bridge',
                'busType': 'USB',
                'health': 'N/A',
                'devicePath': r'\\.\PhysicalDrive2',
                'isSystem': null,
                'isBoot': null,
                'isOffline': null,
                'isReadOnly': null,
                'isRemovable': null,
                'reliabilityUnavailableReason':
                    'The storage driver did not expose a reliability counter.',
                'nvme': {
                  'available': false,
                  'source': 'Windows NVMe protocol query',
                  'reason':
                      'The device or storage driver did not expose NVMe health data.',
                },
                'ataSmart': {
                  'available': false,
                  'source': 'ATA SMART / SAT pass-through',
                  'reason': 'The USB bridge did not expose ATA SMART data.',
                },
              },
            ],
          }),
        );
        final service = WindowsDiskDiagnosticsService(
          helperPath: () => helper.path,
          nativeProcessStarter: (_, _) async => process,
        );

        try {
          final report = (await service.collect()).reports.single;

          expect(report.isBoot.value, isNull);
          expect(report.isBoot.isAvailable, isFalse);
          expect(
            report.isBoot.unavailableReasonKind,
            DiagnosticUnavailableReason.notReported,
          );
          expect(report.isOffline.value, isNull);
          expect(
            report.health.unavailableReasonKind,
            DiagnosticUnavailableReason.usbBridgeUnsupported,
          );
          expect(
            report.temperatureCelsius.unavailableReasonKind,
            DiagnosticUnavailableReason.usbBridgeUnsupported,
          );
        } finally {
          await directory.delete(recursive: true);
        }
      },
      skip: !Platform.isWindows,
    );

    test(
      'uses ATA SMART values only when Windows counters omit the metric',
      () async {
        final directory = await Directory.systemTemp.createTemp(
          'wds_disk_diagnostics_test_',
        );
        final helper = File(
          '${directory.path}\\wds_disk_diagnostics_helper.exe',
        );
        await helper.create();
        final process = _FakeNativeProcess(715);
        process.complete(
          stdout: jsonEncode({
            'ok': true,
            'isAdministrator': true,
            'reports': [
              {
                'diskNumber': 3,
                'model': 'SATA SSD',
                'busType': 'SATA',
                'devicePath': r'\\.\PhysicalDrive3',
                'ataSmart': {
                  'available': true,
                  'source': 'ATA SMART / SAT pass-through',
                  'reason': null,
                  'temperatureCelsius': 28,
                  'wearPercent': 4,
                  'powerOnHours': '105',
                },
                'nvme': {
                  'available': false,
                  'source': 'Windows NVMe protocol query',
                  'reason': 'Not an NVMe device.',
                },
              },
            ],
          }),
        );
        final service = WindowsDiskDiagnosticsService(
          helperPath: () => helper.path,
          nativeProcessStarter: (_, _) async => process,
        );

        try {
          final report = (await service.collect()).reports.single;

          expect(report.temperatureCelsius.value, 28);
          expect(
            report.temperatureCelsius.source,
            'ATA SMART / SAT pass-through',
          );
          expect(report.powerOnHours.value, BigInt.from(105));
          expect(report.powerOnHours.source, 'ATA SMART / SAT pass-through');
          expect(report.wearPercent.value, 4);
          expect(report.wearPercent.source, 'ATA SMART / SAT pass-through');
        } finally {
          await directory.delete(recursive: true);
        }
      },
      skip: !Platform.isWindows,
    );

    test(
      'classifies permission, bridge, and protocol diagnostics precisely',
      () async {
        final directory = await Directory.systemTemp.createTemp(
          'wds_disk_diagnostics_test_',
        );
        final helper = File(
          '${directory.path}\\wds_disk_diagnostics_helper.exe',
        );
        await helper.create();
        final process = _FakeNativeProcess(717);
        process.complete(
          stdout: jsonEncode({
            'ok': true,
            'isAdministrator': true,
            'reports': [
              {
                'diskNumber': 5,
                'busType': 'SATA',
                'health': 'N/A',
                'ataSmart': {
                  'available': false,
                  'reason': 'The storage query was denied.',
                  'windowsError': 5,
                },
              },
              {
                'diskNumber': 6,
                'busType': 'NVMe',
                'health': 'N/A',
                'nvme': {
                  'available': false,
                  'reasonCode': 'administrator_required',
                  'reason': 'The query requires elevated access.',
                  'windowsError': 740,
                },
              },
              {
                'diskNumber': 7,
                'busType': 'USB',
                'health': 'N/A',
                'ataSmart': {
                  'available': false,
                  'reasonCode': 'usb_bridge_unsupported',
                  'reason':
                      'The USB or SCSI bridge did not expose ATA SMART data through SAT pass-through.',
                  'windowsError': 50,
                },
              },
              {
                'diskNumber': 8,
                'busType': 'SATA',
                'health': 'N/A',
                'ataSmart': {
                  'available': false,
                  'reasonCode': 'protocol_response_invalid',
                  'reason':
                      'The ATA SMART protocol response was invalid or incomplete.',
                  'windowsError': 13,
                },
              },
            ],
          }),
        );
        final service = WindowsDiskDiagnosticsService(
          helperPath: () => helper.path,
          nativeProcessStarter: (_, _) async => process,
        );

        try {
          final reports = (await service.collect()).reports;
          final byDisk = {
            for (final report in reports) report.diskNumber: report,
          };

          expect(
            byDisk[5]!.health.unavailableReasonKind,
            DiagnosticUnavailableReason.permissionDenied,
          );
          expect(
            byDisk[6]!.health.unavailableReasonKind,
            DiagnosticUnavailableReason.administratorRequired,
          );
          expect(
            byDisk[7]!.temperatureCelsius.unavailableReasonKind,
            DiagnosticUnavailableReason.usbBridgeUnsupported,
          );
          expect(
            byDisk[8]!.health.unavailableReasonKind,
            DiagnosticUnavailableReason.protocolResponseInvalid,
          );
        } finally {
          await directory.delete(recursive: true);
        }
      },
      skip: !Platform.isWindows,
    );

    test(
      'keeps Windows counter values ahead of ATA SMART fallbacks',
      () async {
        final directory = await Directory.systemTemp.createTemp(
          'wds_disk_diagnostics_test_',
        );
        final helper = File(
          '${directory.path}\\wds_disk_diagnostics_helper.exe',
        );
        await helper.create();
        final process = _FakeNativeProcess(716);
        process.complete(
          stdout: jsonEncode({
            'ok': true,
            'isAdministrator': true,
            'reports': [
              {
                'diskNumber': 4,
                'model': 'SATA SSD',
                'busType': 'SATA',
                'temperatureCelsius': 31,
                'wearPercent': 3,
                'powerOnHours': '11',
                'devicePath': r'\\.\PhysicalDrive4',
                'reliabilityUnavailableReason':
                    'ATA SMART data did not include this reliability metric.',
                'ataSmart': {
                  'available': true,
                  'source': 'ATA SMART / SAT pass-through',
                  'temperatureCelsius': 28,
                  'wearPercent': 4,
                  'powerOnHours': '105',
                },
                'nvme': {'available': false},
              },
            ],
          }),
        );
        final service = WindowsDiskDiagnosticsService(
          helperPath: () => helper.path,
          nativeProcessStarter: (_, _) async => process,
        );

        try {
          final report = (await service.collect()).reports.single;

          expect(report.temperatureCelsius.value, 31);
          expect(
            report.temperatureCelsius.source,
            'Windows Storage Reliability Counter',
          );
          expect(report.wearPercent.value, 3);
          expect(report.powerOnHours.value, BigInt.from(11));
        } finally {
          await directory.delete(recursive: true);
        }
      },
      skip: !Platform.isWindows,
    );

    test(
      'normalizes legacy helper warning text without exposing it to the UI',
      () async {
        final directory = await Directory.systemTemp.createTemp(
          'wds_disk_diagnostics_test_',
        );
        final helper = File(
          '${directory.path}\\wds_disk_diagnostics_helper.exe',
        );
        await helper.create();
        final process = _FakeNativeProcess(712);
        process.complete(
          stdout: jsonEncode({
            'ok': true,
            'isAdministrator': false,
            'warnings': ['Raw driver warning in English'],
            'reports': const [],
          }),
        );
        final service = WindowsDiskDiagnosticsService(
          helperPath: () => helper.path,
          nativeProcessStarter: (_, _) async => process,
        );

        try {
          final snapshot = await service.collect();
          expect(snapshot.collectionWarnings, const [
            'disk_diag_warning_partial',
          ]);
        } finally {
          await directory.delete(recursive: true);
        }
      },
      skip: !Platform.isWindows,
    );

    test(
      'uses a localized error key when the helper returns no data',
      () async {
        final directory = await Directory.systemTemp.createTemp(
          'wds_disk_diagnostics_test_',
        );
        final helper = File(
          '${directory.path}\\wds_disk_diagnostics_helper.exe',
        );
        await helper.create();
        final process = _FakeNativeProcess(713);
        process.complete();
        final service = WindowsDiskDiagnosticsService(
          helperPath: () => helper.path,
          nativeProcessStarter: (_, _) async => process,
        );

        try {
          await expectLater(
            service.collect(),
            throwsA(
              isA<DiskDiagnosticsException>().having(
                (error) => error.localizationKey,
                'localizationKey',
                'disk_diag_error_no_data',
              ),
            ),
          );
        } finally {
          await directory.delete(recursive: true);
        }
      },
      skip: !Platform.isWindows,
    );

    test(
      'cancellation terminates a helper that has not returned',
      () async {
        final directory = await Directory.systemTemp.createTemp(
          'wds_disk_diagnostics_test_',
        );
        final helper = File(
          '${directory.path}\\wds_disk_diagnostics_helper.exe',
        );
        await helper.create();
        final process = _FakeNativeProcess(711);
        final started = Completer<void>();
        final cancellation = DiskToolsCancellationToken();
        final service = WindowsDiskDiagnosticsService(
          helperPath: () => helper.path,
          nativeProcessStarter: (_, _) async {
            started.complete();
            return process;
          },
        );

        try {
          final collection = service.collect(cancellationToken: cancellation);
          await started.future;
          cancellation.cancel();

          await expectLater(
            collection,
            throwsA(
              isA<DiskDiagnosticsException>().having(
                (error) => error.operationCancelled,
                'operationCancelled',
                isTrue,
              ),
            ),
          );
          expect(process.wasKilled, isTrue);
        } finally {
          process.complete();
          await directory.delete(recursive: true);
        }
      },
      skip: !Platform.isWindows,
    );
  });
}

class _FakeNativeProcess implements Process {
  @override
  final int pid;

  final Completer<int> _exitCode = Completer<int>();
  final StreamController<List<int>> _stdout = StreamController<List<int>>();
  final StreamController<List<int>> _stderr = StreamController<List<int>>();
  final StreamController<List<int>> _stdin = StreamController<List<int>>();
  bool wasKilled = false;

  _FakeNativeProcess(this.pid);

  @override
  Future<int> get exitCode => _exitCode.future;

  @override
  Stream<List<int>> get stdout => _stdout.stream;

  @override
  Stream<List<int>> get stderr => _stderr.stream;

  @override
  IOSink get stdin => IOSink(_stdin.sink);

  void complete({String stdout = '', String stderr = '', int exitCode = 0}) {
    if (_exitCode.isCompleted) return;
    if (stdout.isNotEmpty) _stdout.add(utf8.encode(stdout));
    if (stderr.isNotEmpty) _stderr.add(utf8.encode(stderr));
    _exitCode.complete(exitCode);
    unawaited(_stdout.close());
    unawaited(_stderr.close());
    unawaited(_stdin.close());
  }

  @override
  bool kill([ProcessSignal signal = ProcessSignal.sigterm]) {
    wasKilled = true;
    complete(exitCode: -1);
    return true;
  }
}
