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
$remaining = [int64]$ExpectedIsoLength
$requested = if ($remaining -lt [int64]$bufferLength) {
  [int]$remaining
} else {
  [int]$bufferLength
}
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

  test(
    'Linux raw verification bounds large ISO chunks without Int32 overflow',
    () {
      final script = BootableUsbService.linuxRawWriteScriptForTesting;

      expect(script, contains(r'$remaining = [int64]($total - $verified)'));
      expect(script, contains(r'$remaining -lt [int64]$bufferLength'));
      expect(script, contains(r'[int]$remaining'));
      expect(script, contains(r'[int]$bufferLength'));
      expect(script, isNot(contains(r'[Math]::Min(')));
    },
  );

  test(
    'Linux raw imaging keeps the target isolated through verification and restores it before completion',
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
      expect(write, contains(r'[System.IO.FileShare]::None'));
      expect(write, contains('WDS_VERIFY_STARTED'));
      expect(write, contains('WDS_VERIFY_PROGRESS:0'));
      expect(write, contains('WDS_VERIFY_COMPLETE'));
      expect(write, contains('WDS_DISK_ONLINE'));
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
        lessThan(write.indexOf('WDS_VERIFY_COMPLETE')),
      );
      expect(
        write.indexOf('WDS_VERIFY_COMPLETE'),
        lessThan(write.indexOf('WDS_DISK_ONLINE')),
      );
      expect(
        write.indexOf('WDS_DISK_ONLINE'),
        lessThan(write.indexOf('WDS_DONE')),
      );
      expect(
        write,
        contains(r'Set-Disk -Number $DiskNumber -IsOffline $false'),
      );
      expect(write, contains(r'Update-Disk -Number $DiskNumber'));
      expect(
        write.lastIndexOf(r'$target.Dispose()'),
        lessThan(
          write.lastIndexOf(r'Set-Disk -Number $DiskNumber -IsOffline $false'),
        ),
      );
      expect(
        write.lastIndexOf(r'Set-Disk -Number $DiskNumber -IsOffline $false'),
        lessThan(write.lastIndexOf(r'Update-Disk -Number $DiskNumber')),
      );
      expect(
        write.lastIndexOf(r'Update-Disk -Number $DiskNumber'),
        lessThan(
          write.lastIndexOf(
            r'$onlineDisk = Get-Disk -Number $DiskNumber -ErrorAction Stop',
          ),
        ),
      );
      expect(write, contains(r'if ([bool]$onlineDisk.IsOffline) {'));
      expect(
        write.lastIndexOf(
          r'$onlineDisk = Get-Disk -Number $DiskNumber -ErrorAction Stop',
        ),
        lessThan(write.lastIndexOf('WDS_DISK_ONLINE')),
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

  test('Linux raw writer parses completion markers and preserves progress', () {
    final source = File(
      'lib/core/services/bootable_usb_service.dart',
    ).readAsStringSync();
    final writerStart = source.indexOf(
      'Future<_LinuxRawWriteResult> _writeIsoHybridRaw',
    );
    final restoreStart = source.indexOf(
      'Future<_LinuxRawWriteResult> _restoreLinuxRawDiskOnline',
      writerStart,
    );
    final writer = source.substring(writerStart, restoreStart);

    expect(writerStart, greaterThanOrEqualTo(0));
    expect(restoreStart, greaterThan(writerStart));
    expect(writer, contains("cleanLine == 'WDS_VERIFY_COMPLETE'"));
    expect(writer, contains("cleanLine == 'WDS_DISK_ONLINE'"));
    expect(writer, contains("cleanLine == 'WDS_DONE'"));
    expect(writer, contains('imageVerified = true;'));
    expect(writer, contains('diskOnline = true;'));
    expect(writer, contains("substring('WDS_PROGRESS:'.length)"));
    expect(writer, contains(".split(':');"));

    final doneMarker = writer.indexOf("if (cleanLine == 'WDS_DONE')");
    final doneMarkerEnd = writer.indexOf('\n            }', doneMarker);
    expect(doneMarker, greaterThanOrEqualTo(0));
    expect(doneMarkerEnd, greaterThan(doneMarker));
    final doneBlock = writer.substring(doneMarker, doneMarkerEnd);
    expect(doneBlock, contains('completed = true;'));
    expect(doneBlock, isNot(contains('imageVerified = true;')));
  });

  test(
    'Linux raw disk recovery failure is not reported as a verification failure',
    () {
      final source = File(
        'lib/core/services/bootable_usb_service.dart',
      ).readAsStringSync();
      final writerStart = source.indexOf(
        'Future<_LinuxRawWriteResult> _writeIsoHybridRaw',
      );
      final restoreStart = source.indexOf(
        'Future<_LinuxRawWriteResult> _restoreLinuxRawDiskOnline',
        writerStart,
      );
      final writer = source.substring(writerStart, restoreStart);

      expect(
        writer,
        contains(
          "failureMessageKey: imageVerified && !diskOnline\n              ? 'linux_write_failed'",
        ),
      );
      expect(
        writer,
        contains('verificationFailed: verificationStarted && !imageVerified'),
      );
      expect(
        writer,
        contains(
          "failureMessageKey: imageVerified ? 'linux_write_failed' : null",
        ),
      );
      expect(writer, contains('verificationFailed: !imageVerified'));
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
    final successfulRawPathStart = source.indexOf(
      '// The raw writer returns the disk online before emitting WDS_DONE.',
    );
    final successfulRawPathEnd = source.indexOf(
      "_logLine('Linux verify:",
      successfulRawPathStart,
    );

    expect(source, isNot(contains('_verifyLinuxRawWrite(')));
    expect(source, contains('onVerifyProgress: (verifyProgress)'));
    expect(source, contains('verificationFailed: verificationStarted'));
    expect(successfulRawPathStart, greaterThanOrEqualTo(0));
    expect(successfulRawPathEnd, greaterThan(successfulRawPathStart));
    expect(
      source.substring(successfulRawPathStart, successfulRawPathEnd),
      isNot(contains('_restoreLinuxRawDiskOnline')),
    );
  });

  test('Linux raw install-media completion explains the native ISO layout', () {
    final source = File(
      'lib/core/services/bootable_usb_service.dart',
    ).readAsStringSync();
    final creationStart = source.indexOf('Future<bool> createLinuxIsoUsb');
    final rawSuccess = source.indexOf(
      "? 'linux_media_raw_complete'",
      creationStart,
    );

    expect(creationStart, greaterThanOrEqualTo(0));
    expect(rawSuccess, greaterThan(creationStart));
    expect(
      source.substring(creationStart, rawSuccess),
      contains("? 'linux_complete'"),
      reason: 'Linux To Go keeps its separate completion message',
    );
  });

  test('Linux capability panel explains duplicate boot-menu entries', () {
    final source = File(
      'lib/features/creator/screens/creator_screen.dart',
    ).readAsStringSync();

    expect(source, contains("'linux_media_boot_menu_notice'"));
    expect(source, contains("tr(context, 'linux_media_raw_write_notice')"));
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
