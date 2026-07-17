import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:win_deploy_studio/features/disk_tools/services/secure_powershell_runner.dart';
import 'package:win_deploy_studio/features/disk_tools/services/windows_boot_repair_service.dart';

void main() {
  group('secure PowerShell command construction', () {
    test('scripts remain in memory and parameters stay serialized', () {
      const script = r'''
$value = $env:WDS_TEST_SPEC | ConvertFrom-Json
if ($value.path -ne 'C:\quoted path') { throw 'bad spec' }
''';
      final serialized = jsonEncode({
        'path': r'C:\quoted path',
        'text': 'quotes " and newlines\nremain JSON',
      });

      final command = PowerShellCommandBuilder.build(
        script: script,
        variables: {'WDS_TEST_SPEC': serialized},
        powershellPath:
            r'C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe',
        cancelPath: r'C:\Temp\wds\cancel.signal',
        cancelGracePeriod: const Duration(seconds: 5),
        baseEnvironment: const {'SystemRoot': r'C:\Windows'},
      );

      expect(command.arguments, contains('-EncodedCommand'));
      expect(command.arguments, isNot(contains('-File')));
      expect(command.arguments.join(' '), isNot(contains('.ps1')));
      expect(command.arguments.join(' '), isNot(contains(script)));
      expect(command.environment['WDS_TEST_SPEC'], serialized);
      expect(
        PowerShellCommandBuilder.decompressScript(
          command.environment[PowerShellCommandBuilder.scriptPayloadVariable]!,
        ),
        script,
      );

      final bootstrap = PowerShellCommandBuilder.decodeCommand(
        command.arguments.last,
      );
      expect(
        command.arguments.last,
        command.environment[PowerShellCommandBuilder.bootstrapVariable],
      );
      expect(bootstrap, isNot(contains('Start-Process')));
      expect(bootstrap, isNot(contains('RunAs')));
      expect(bootstrap, isNot(contains("'-File'")));
      expect(bootstrap, contains('GZipStream'));
      expect(bootstrap, contains('[ScriptBlock]::Create'));
      expect(bootstrap, contains('taskkill.exe'));
    });

    test('rejects environment names outside the disk-tools contract', () {
      expect(
        () => PowerShellCommandBuilder.build(
          script: 'Write-Output ok',
          variables: const {'PATH': 'untrusted'},
          powershellPath: 'powershell.exe',
          cancelPath: r'C:\Temp\cancel.signal',
          cancelGracePeriod: Duration.zero,
        ),
        throwsFormatException,
      );
    });

    test('both feature scripts fit and round-trip through gzip transport', () {
      final scripts = [
        WindowsBootRepairService.discoveryScriptForTesting,
        WindowsBootRepairService.bootOperationScriptForTesting,
      ];

      for (final script in scripts) {
        final payload = PowerShellCommandBuilder.compressScript(script);
        expect(payload.length, lessThanOrEqualTo(24000));
        expect(PowerShellCommandBuilder.decompressScript(payload), script);
      }
    });

    test(
      'boot script contains transactional rollback and full verification',
      () {
        final script = WindowsBootRepairService.bootOperationScriptForTesting;

        expect(script, contains('Restore-BcdBackup'));
        expect(script, contains(r'rollbackAttempted = $rollbackAttempted'));
        expect(script, contains(r'existingBcdBackedUp = $existingBcdBackedUp'));
        expect(script, contains("'/enum' '{default}' '/v'"));
        expect(
          script,
          contains(r"Get-BcdElementValue $defaultOutput 'device'"),
        );
        expect(
          script,
          contains(r"Get-BcdElementValue $defaultOutput 'osdevice'"),
        );
        expect(script, contains('efiFallbackMatchesBootManager'));
        expect(script, contains(r'Get-FileSha256 $bootManagerPath'));
        expect(script, contains(r"$bootManagerRelative = 'bootmgr'"));
        expect(script, contains(r"$bcdRelative = 'Boot\BCD'"));
      },
    );

    test('boot disk binding rejects generic physical-drive aliases', () {
      final discovery = WindowsBootRepairService.discoveryScriptForTesting;
      final operation = WindowsBootRepairService.bootOperationScriptForTesting;

      expect(
        discovery,
        contains(r'function Is-GenericPhysicalDriveAlias($value)'),
      );
      expect(
        discovery,
        contains(
          r"-not ($candidate[0] -eq 'devicePath' -and (Is-GenericPhysicalDriveAlias $candidate[1]))",
        ),
      );
      expect(
        operation,
        contains(r'function Is-GenericPhysicalDriveAlias($value)'),
      );
      expect(
        operation,
        contains(r"if (Is-GenericPhysicalDriveAlias $value) { return '' }"),
      );
    });

    test(
      'Windows PowerShell parses every in-memory feature script',
      () async {
        final scripts = [
          WindowsBootRepairService.discoveryScriptForTesting,
          WindowsBootRepairService.bootOperationScriptForTesting,
        ];
        const parserScript = r'''
$compressed = [Convert]::FromBase64String($env:WDS_TEST_SCRIPT_GZIP)
$inputStream = New-Object IO.MemoryStream(,$compressed)
try {
  $gzipStream = New-Object IO.Compression.GZipStream(
    $inputStream,
    [IO.Compression.CompressionMode]::Decompress
  )
  try {
    $reader = New-Object IO.StreamReader($gzipStream, (New-Object Text.UTF8Encoding($false)))
    try { $source = $reader.ReadToEnd() } finally { $reader.Dispose() }
  } finally { $gzipStream.Dispose() }
} finally { $inputStream.Dispose() }
[void][ScriptBlock]::Create($source)
''';

        for (final script in scripts) {
          final workspace = await DiskToolsPowerShellWorkspace.create(
            'wds_parse_test',
          );
          try {
            final result = await SecurePowerShellRunner().run(
              script: parserScript,
              variables: {
                'WDS_TEST_SCRIPT_GZIP': PowerShellCommandBuilder.compressScript(
                  script,
                ),
              },
              timeout: const Duration(seconds: 20),
              cancelPath: workspace.cancelFile.path,
            );
            expect(result.exitCode, 0, reason: result.stderr);
          } finally {
            await workspace.dispose();
          }
        }
      },
      skip: !Platform.isWindows,
      // This starts a real Windows PowerShell process for each generated
      // script. Full-suite parallelism can delay process startup well beyond
      // the framework default even though the parser itself remains healthy.
      timeout: const Timeout(Duration(minutes: 2)),
    );
  });

  test('cancellation terminates the direct PowerShell process tree', () async {
    final fake = _FakeProcess(91);
    final started = Completer<void>();
    final lifecycle = <String>[];
    final token = DiskToolsCancellationToken();
    final workspace = await DiskToolsPowerShellWorkspace.create(
      'wds_runner_test',
    );
    final runner = SecurePowerShellRunner(
      powershellPath: 'powershell.exe',
      processStarter: (executable, arguments, {environment}) async {
        started.complete();
        return fake;
      },
      processTreeTerminator: (processId) async {
        lifecycle.add('terminate:$processId');
        if (processId == fake.pid) fake.complete(9);
      },
    );

    try {
      final run = runner.run(
        script: 'Start-Sleep -Seconds 30',
        timeout: const Duration(minutes: 1),
        cancelPath: workspace.cancelFile.path,
        cancellationToken: token,
        cancellationGracePeriod: Duration.zero,
      );
      await started.future;
      token.cancel();

      final result = await run;

      expect(result.cancelled, isTrue);
      expect(result.processId, fake.pid);
      expect(await workspace.cancelFile.exists(), isTrue);
      expect(lifecycle, ['terminate:91']);
    } finally {
      fake.complete(9);
      await workspace.dispose();
    }
  });
}

class _FakeProcess implements Process {
  @override
  final int pid;

  final Completer<int> _exitCode = Completer<int>();
  final StreamController<List<int>> _stdout = StreamController<List<int>>();
  final StreamController<List<int>> _stderr = StreamController<List<int>>();
  final StreamController<List<int>> _stdin = StreamController<List<int>>();

  _FakeProcess(this.pid);

  @override
  Future<int> get exitCode => _exitCode.future;

  @override
  Stream<List<int>> get stdout => _stdout.stream;

  @override
  Stream<List<int>> get stderr => _stderr.stream;

  @override
  IOSink get stdin => IOSink(_stdin.sink);

  void complete(int value) {
    if (_exitCode.isCompleted) return;
    _exitCode.complete(value);
    unawaited(_stdout.close());
    unawaited(_stderr.close());
    unawaited(_stdin.close());
  }

  @override
  bool kill([ProcessSignal signal = ProcessSignal.sigterm]) {
    complete(-1);
    return true;
  }
}
