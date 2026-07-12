import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
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
            'warnings': ['One disk did not expose a health log.'],
            'reports': [
              {
                'diskNumber': 0,
                'model': 'Example NVMe',
                'sizeBytes': '1024',
                'busType': 'NVMe',
                'devicePath': r'\\.\PhysicalDrive0',
                'isSystem': true,
                'isBoot': true,
                'isOffline': false,
                'isReadOnly': false,
                'isRemovable': false,
                'nvme': {
                  'available': true,
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
          expect(snapshot.collectionWarnings, hasLength(1));
          expect(snapshot.reports, hasLength(1));
          final report = snapshot.reports.single;
          expect(report.model.value, 'Example NVMe');
          expect(report.temperatureCelsius.value, 31);
          expect(report.wearPercent.value, 7);
          expect(report.estimatedRemainingLifePercent.value, 93);
          expect(report.hostWrittenBytes.value, BigInt.from(1024000));
          expect(report.isSystem, isTrue);
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
