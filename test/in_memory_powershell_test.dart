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
