import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:win_deploy_studio/core/services/bootable_usb_service.dart';
import 'package:win_deploy_studio/core/services/in_memory_powershell.dart';

void main() {
  test('PowerShell source and parameters stay in environment memory', () {
    const source = 'param([string]\$Value)\nWrite-Output \$Value';
    final command = InMemoryPowerShell.build(
      script: source,
      parameters: const {'Value': r'C:\Images\Linux.iso'},
    );

    expect(command.arguments, isNot(contains('-File')));
    expect(command.arguments, contains('-EncodedCommand'));
    expect(
      InMemoryPowerShell.decompressScript(
        command.environment[InMemoryPowerShell.scriptVariable]!,
      ),
      source,
    );
    final parameterJson = utf8.decode(
      base64Decode(command.environment[InMemoryPowerShell.parametersVariable]!),
    );
    expect(jsonDecode(parameterJson), {'Value': r'C:\Images\Linux.iso'});
  });

  test('encoded bootstrap is valid UTF-16LE and rejects unsafe values', () {
    final command = InMemoryPowerShell.build(
      script: 'Write-Output ok',
      parameters: const {},
    );
    final encoded = command.arguments.last;
    expect(InMemoryPowerShell.decodeCommand(encoded), contains('ScriptBlock'));
    expect(
      () => InMemoryPowerShell.build(
        script: 'Write-Output ok',
        parameters: const {'Bad-Name': 'value'},
      ),
      throwsFormatException,
    );
  });

  test(
    'Windows PowerShell executes the in-memory script and parameters',
    () async {
      if (!Platform.isWindows) return;
      const value = r'C:\Images\Linux.iso';
      final command = InMemoryPowerShell.build(
        script: r'param([string]$Value) Write-Output $Value',
        parameters: const {'Value': value},
      );

      final result = await Process.run(
        command.executable,
        command.arguments,
        environment: command.environment,
      ).timeout(const Duration(seconds: 20));

      expect(result.exitCode, 0, reason: result.stderr.toString());
      expect(result.stdout.toString().trim(), value);
    },
  );

  test(
    'PowerShell keeps a disk index separate while chunking a large ISO',
    () async {
      if (!Platform.isWindows) return;
      const imageLength = '6976131072';
      final command = InMemoryPowerShell.build(
        script: r'''
param([int]$DiskNumber, [int64]$ExpectedIsoLength)
$bufferLength = 8388608
$requested = [int][Math]::Min(
  [int64]$bufferLength,
  [int64]$ExpectedIsoLength
)
Write-Output ("{0}|{1}" -f $DiskNumber, $requested)
''',
        parameters: const {'DiskNumber': '1', 'ExpectedIsoLength': imageLength},
      );

      final result = await Process.run(
        command.executable,
        command.arguments,
        environment: command.environment,
      ).timeout(const Duration(seconds: 20));

      expect(result.exitCode, 0, reason: result.stderr.toString());
      expect(result.stdout.toString().trim(), '1|8388608');
    },
  );

  test('Linux raw verification uses an Int64 minimum for large ISO chunks', () {
    final script = BootableUsbService.linuxRawWriteScriptForTesting;

    expect(script, contains(r'[Math]::Min('));
    expect(script, contains(r'[int64]$bufferLength,'));
    expect(script, contains(r'[int64]($total - $verified)'));
    expect(
      script,
      isNot(contains(r'[Math]::Min($bufferLength, $total - $verified)')),
    );
  });

  test(
    'Linux raw imaging falls back to an exclusive handle until verification passes',
    () {
      final write = BootableUsbService.linuxRawWriteScriptForTesting;
      final finalize = BootableUsbService.linuxRawFinalizeScriptForTesting;

      expect(write, contains(r'Set-Disk -Number $DiskNumber -IsOffline $true'));
      expect(write, contains('Test-OfflineIsolationUnsupported'));
      expect(write, contains('WDS_ISOLATION:EXCLUSIVE'));
      expect(
        write.indexOf(r'Set-Disk -Number $DiskNumber -IsOffline $true'),
        lessThan(
          write.indexOf(r'$targetPath = "\\.\PhysicalDrive$DiskNumber"'),
        ),
      );
      expect(write, isNot(contains(r'Update-Disk -Number $DiskNumber')));
      expect(write, contains(r'[System.IO.FileShare]::None'));
      expect(write, contains('WDS_VERIFY_STARTED'));
      expect(write, contains('WDS_VERIFY_PROGRESS:0'));
      expect(
        write,
        contains(r'$blockMatches = if ($requested -eq $bufferLength)'),
      );
      expect(
        write.indexOf(r'$blockMatches = if ($requested -eq $bufferLength)'),
        lessThan(
          write.indexOf(
            r'if ($firstMismatchOffset -lt 0 -and -not $blockMatches)',
          ),
        ),
      );
      expect(
        write,
        contains('Full-stream SHA-256 verification mismatch at offset'),
      );
      expect(
        write.indexOf('WDS_VERIFY_STARTED'),
        lessThan(write.indexOf('WDS_DONE')),
      );
      expect(
        finalize,
        contains(r'Set-Disk -Number $DiskNumber -IsOffline $false'),
      );
      expect(finalize, contains(r'Update-Disk -Number $DiskNumber'));
      expect(
        finalize.indexOf(r'Set-Disk -Number $DiskNumber -IsOffline $false'),
        lessThan(finalize.indexOf(r'Update-Disk -Number $DiskNumber')),
      );
    },
  );

  test('Linux raw failure recovers the isolated target before reporting', () {
    final source = File(
      'lib/core/services/bootable_usb_service.dart',
    ).readAsStringSync();
    final rawWriterStart = source.indexOf('rawDiskMayNeedRestore = true;');
    final failureBranch = source.indexOf(
      'if (!result.success) {',
      rawWriterStart,
    );
    final failureReturn = source.indexOf('return false;', failureBranch);
    final failureRecovery = source.indexOf(
      'await _restoreLinuxRawDiskOnline(disk: disk)',
      failureBranch,
    );
    final catchBranch = source.indexOf('Linux creation EXCEPTION:');
    final catchRecovery = source.lastIndexOf(
      'await _restoreLinuxRawDiskOnline(disk: disk)',
      catchBranch,
    );

    expect(rawWriterStart, greaterThanOrEqualTo(0));
    expect(failureBranch, greaterThan(rawWriterStart));
    expect(failureRecovery, greaterThan(failureBranch));
    expect(failureRecovery, lessThan(failureReturn));
    expect(catchRecovery, greaterThanOrEqualTo(0));
  });

  test('Linux raw verification remains in the writer process', () {
    final source = File(
      'lib/core/services/bootable_usb_service.dart',
    ).readAsStringSync();

    expect(source, isNot(contains('_verifyLinuxRawWrite(')));
    expect(source, contains('onVerifyProgress: (verifyProgress)'));
    expect(source, contains('verificationFailed: verificationStarted'));
  });

  test('PowerShell failure summaries exclude CLIXML and stack traces', () {
    final summary = BootableUsbService.summarizePowerShellFailureForTesting(
      '''#< CLIXML
System.Management.Automation.MethodException: Cannot convert a large value.
   at System.Management.Automation.Interpreter.ActionCallInstruction.Run()
<Objs Version="1.1.0.1"></Objs>''',
    );

    expect(summary, 'Cannot convert a large value.');
    expect(summary, isNot(contains('CLIXML')));
    expect(summary, isNot(contains('Interpreter')));
  });

  test('Linux raw scripts fit and parse in Windows PowerShell', () async {
    if (!Platform.isWindows) return;
    const parser = r'''
$compressed = [Convert]::FromBase64String($env:WDS_PARSE_PAYLOAD)
$inputStream = [IO.MemoryStream]::new([byte[]]$compressed)
$gzipStream = [IO.Compression.GZipStream]::new($inputStream, [IO.Compression.CompressionMode]::Decompress)
$reader = [IO.StreamReader]::new($gzipStream, [Text.UTF8Encoding]::new($false))
try { [void][ScriptBlock]::Create($reader.ReadToEnd()) }
finally { $reader.Dispose(); $gzipStream.Dispose(); $inputStream.Dispose() }
''';
    for (final script in [
      BootableUsbService.linuxRawWriteScriptForTesting,
      BootableUsbService.linuxRawVerifyScriptForTesting,
      BootableUsbService.linuxRawFinalizeScriptForTesting,
    ]) {
      final command = InMemoryPowerShell.build(
        script: script,
        parameters: const {},
      );
      final result = await Process.run(
        command.executable,
        const ['-NoProfile', '-NonInteractive', '-Command', parser],
        environment: {
          ...Platform.environment,
          'WDS_PARSE_PAYLOAD': InMemoryPowerShell.compressScript(script),
        },
      ).timeout(const Duration(seconds: 20));
      expect(result.exitCode, 0, reason: result.stderr.toString());
    }
  });
}
