import 'dart:convert';
import 'dart:io';

import 'windows_system_environment.dart';

class InMemoryPowerShellCommand {
  final String executable;
  final List<String> arguments;
  final Map<String, String> environment;

  const InMemoryPowerShellCommand({
    required this.executable,
    required this.arguments,
    required this.environment,
  });
}

class InMemoryPowerShell {
  static const scriptVariable = 'WDS_MEMORY_PS_SCRIPT';
  static const parametersVariable = 'WDS_MEMORY_PS_PARAMETERS';

  const InMemoryPowerShell._();

  static InMemoryPowerShellCommand build({
    required String script,
    required Map<String, String> parameters,
  }) {
    if (script.trim().isEmpty || script.contains('\u0000')) {
      throw const FormatException('PowerShell source is empty or invalid.');
    }
    if (parameters.entries.any(
      (entry) =>
          !RegExp(r'^[A-Za-z][A-Za-z0-9]*$').hasMatch(entry.key) ||
          entry.value.contains('\u0000'),
    )) {
      throw const FormatException('PowerShell parameters are invalid.');
    }

    final compressedScript = base64Encode(gzip.encode(utf8.encode(script)));
    final serializedParameters = base64Encode(
      utf8.encode(jsonEncode(parameters)),
    );
    if (compressedScript.length > 24000 ||
        serializedParameters.length > 16000) {
      throw const FormatException('In-memory PowerShell payload is too large.');
    }

    return InMemoryPowerShellCommand(
      executable: WindowsSystemEnvironment.powerShellExecutable,
      arguments: [
        '-NoLogo',
        '-NoProfile',
        '-NonInteractive',
        '-ExecutionPolicy',
        'Bypass',
        '-EncodedCommand',
        _encodedBootstrap,
      ],
      environment: {
        ...WindowsSystemEnvironment.withSystemRoot(),
        scriptVariable: compressedScript,
        parametersVariable: serializedParameters,
      },
    );
  }

  static String compressScript(String script) =>
      base64Encode(gzip.encode(utf8.encode(script)));

  static String decompressScript(String payload) =>
      utf8.decode(gzip.decode(base64Decode(payload)));

  static String encodeCommand(String source) {
    final bytes = <int>[];
    for (final codeUnit in source.codeUnits) {
      bytes
        ..add(codeUnit & 0xff)
        ..add((codeUnit >> 8) & 0xff);
    }
    return base64Encode(bytes);
  }

  static String decodeCommand(String encoded) {
    final bytes = base64Decode(encoded);
    if (bytes.length.isOdd) {
      throw const FormatException('PowerShell command is not UTF-16LE.');
    }
    return String.fromCharCodes([
      for (var index = 0; index < bytes.length; index += 2)
        bytes[index] | (bytes[index + 1] << 8),
    ]);
  }

  static const _bootstrap = r'''
$ErrorActionPreference = 'Stop'
try {
  $compressed = [Convert]::FromBase64String($env:WDS_MEMORY_PS_SCRIPT)
  $inputStream = [IO.MemoryStream]::new([byte[]]$compressed)
  try {
    $gzipStream = [IO.Compression.GZipStream]::new(
      $inputStream,
      [IO.Compression.CompressionMode]::Decompress
    )
    try {
      $reader = [IO.StreamReader]::new(
        $gzipStream,
        [Text.UTF8Encoding]::new($false)
      )
      try { $source = $reader.ReadToEnd() } finally { $reader.Dispose() }
    } finally { $gzipStream.Dispose() }
  } finally { $inputStream.Dispose() }

  $parameters = @{}
  $parameterJson = [Text.Encoding]::UTF8.GetString(
    [Convert]::FromBase64String($env:WDS_MEMORY_PS_PARAMETERS)
  )
  if (-not [string]::IsNullOrWhiteSpace($parameterJson)) {
    (ConvertFrom-Json $parameterJson).PSObject.Properties | ForEach-Object {
      $parameters[$_.Name] = [string]$_.Value
    }
  }
  & ([ScriptBlock]::Create($source)) @parameters
  exit $LASTEXITCODE
} catch {
  [Console]::Error.WriteLine($_.Exception.ToString())
  exit 1
}
''';

  static final String _encodedBootstrap = encodeCommand(_bootstrap);
}
