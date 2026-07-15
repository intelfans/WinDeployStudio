import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import '../../../core/services/windows_system_environment.dart';

enum PowerShellCompletion { exited, timedOut, cancelled }

class DiskToolsCancellationToken {
  final Completer<void> _cancelled = Completer<void>();

  bool get isCancelled => _cancelled.isCompleted;
  Future<void> get whenCancelled => _cancelled.future;

  void cancel() {
    if (!_cancelled.isCompleted) _cancelled.complete();
  }
}

class PowerShellLaunchCommand {
  final String executable;
  final List<String> arguments;
  final Map<String, String> environment;

  const PowerShellLaunchCommand({
    required this.executable,
    required this.arguments,
    required this.environment,
  });
}

class PowerShellCommandBuilder {
  static const scriptPayloadVariable = 'WDS_PS_SCRIPT_GZIP';
  static const bootstrapVariable = 'WDS_PS_BOOTSTRAP';
  static const cancelPathVariable = 'WDS_PS_CANCEL_PATH';
  static const cancelGraceVariable = 'WDS_PS_CANCEL_GRACE_MS';

  static final RegExp _variableName = RegExp(r'^WDS_[A-Z0-9_]+$');
  static const Set<String> _reservedVariables = {
    scriptPayloadVariable,
    bootstrapVariable,
    cancelPathVariable,
    cancelGraceVariable,
  };

  static PowerShellLaunchCommand build({
    required String script,
    required Map<String, String> variables,
    required String powershellPath,
    required String cancelPath,
    required Duration cancelGracePeriod,
    Map<String, String>? baseEnvironment,
  }) {
    if (script.trim().isEmpty || script.contains('\u0000')) {
      throw const FormatException('PowerShell source is empty or invalid.');
    }

    final checkedVariables = <String, String>{};
    for (final entry in variables.entries) {
      if (!_variableName.hasMatch(entry.key) ||
          _reservedVariables.contains(entry.key)) {
        throw FormatException(
          'Invalid or reserved PowerShell environment variable: ${entry.key}',
        );
      }
      if (entry.value.contains('\u0000')) {
        throw FormatException(
          'PowerShell environment variable ${entry.key} contains NUL.',
        );
      }
      checkedVariables[entry.key] = entry.value;
    }

    final payload = compressScript(script);
    if (payload.length > 24000) {
      throw const FormatException(
        'Compressed PowerShell source exceeds the safe environment limit.',
      );
    }

    final bootstrap = encodeCommand(_bootstrapScript);
    final environment = <String, String>{
      ...?baseEnvironment,
      ...checkedVariables,
      scriptPayloadVariable: payload,
      bootstrapVariable: bootstrap,
      cancelPathVariable: cancelPath,
      cancelGraceVariable: '${cancelGracePeriod.inMilliseconds}',
    };
    final arguments = [
      '-NoLogo',
      '-NoProfile',
      '-NonInteractive',
      '-ExecutionPolicy',
      'Bypass',
      '-EncodedCommand',
      bootstrap,
    ];
    return PowerShellLaunchCommand(
      executable: powershellPath,
      arguments: List.unmodifiable(arguments),
      environment: Map.unmodifiable(environment),
    );
  }

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
    final codeUnits = <int>[];
    for (var index = 0; index < bytes.length; index += 2) {
      codeUnits.add(bytes[index] | (bytes[index + 1] << 8));
    }
    return String.fromCharCodes(codeUnits);
  }

  static String compressScript(String source) {
    return base64Encode(gzip.encode(utf8.encode(source)));
  }

  static String decompressScript(String payload) {
    return utf8.decode(gzip.decode(base64Decode(payload)));
  }

  static const _bootstrapScript = r'''
$ErrorActionPreference = 'Stop'
$watcher = $null
try {
  $payload = $env:WDS_PS_SCRIPT_GZIP
  if ([string]::IsNullOrWhiteSpace($payload)) {
    throw 'The in-memory PowerShell payload is missing.'
  }

  $cancelPath = $env:WDS_PS_CANCEL_PATH
  if (-not [string]::IsNullOrWhiteSpace($cancelPath)) {
    $rootProcessId = $PID
    $graceMilliseconds = 0
    [void][int]::TryParse($env:WDS_PS_CANCEL_GRACE_MS, [ref]$graceMilliseconds)
    $watcher = Start-Job -ArgumentList $rootProcessId, $cancelPath, $graceMilliseconds -ScriptBlock {
      param([int]$RootProcessId, [string]$CancelPath, [int]$GraceMilliseconds)
      while (-not [IO.File]::Exists($CancelPath)) {
        Start-Sleep -Milliseconds 100
      }
      if ($GraceMilliseconds -gt 0) {
        Start-Sleep -Milliseconds $GraceMilliseconds
      }
      & (Join-Path $env:SystemRoot 'System32\taskkill.exe') /F /T /PID $RootProcessId *> $null
    }
  }

  $compressed = [Convert]::FromBase64String($payload)
  $inputStream = New-Object IO.MemoryStream(,$compressed)
  try {
    $gzipStream = New-Object IO.Compression.GZipStream(
      $inputStream,
      [IO.Compression.CompressionMode]::Decompress
    )
    try {
      $reader = New-Object IO.StreamReader(
        $gzipStream,
        (New-Object Text.UTF8Encoding($false))
      )
      try {
        $source = $reader.ReadToEnd()
      } finally {
        $reader.Dispose()
      }
    } finally {
      $gzipStream.Dispose()
    }
  } finally {
    $inputStream.Dispose()
  }

  & ([ScriptBlock]::Create($source))
} finally {
  if ($null -ne $watcher) {
    Stop-Job -Job $watcher -ErrorAction SilentlyContinue
    Remove-Job -Job $watcher -Force -ErrorAction SilentlyContinue
  }
}
''';
}

class PowerShellRunResult {
  final int processId;
  final int exitCode;
  final String stdout;
  final String stderr;
  final PowerShellCompletion completion;

  const PowerShellRunResult({
    required this.processId,
    required this.exitCode,
    required this.stdout,
    required this.stderr,
    required this.completion,
  });

  bool get timedOut => completion == PowerShellCompletion.timedOut;
  bool get cancelled => completion == PowerShellCompletion.cancelled;
}

typedef DiskToolsProcessStarter =
    Future<Process> Function(
      String executable,
      List<String> arguments, {
      Map<String, String>? environment,
    });
typedef DiskToolsProcessTreeTerminator = Future<void> Function(int processId);

class SecurePowerShellRunner {
  final DiskToolsProcessStarter _startProcess;
  final DiskToolsProcessTreeTerminator _terminateProcessTree;
  final String powershellPath;

  SecurePowerShellRunner({
    DiskToolsProcessStarter? processStarter,
    DiskToolsProcessTreeTerminator? processTreeTerminator,
    String? powershellPath,
  }) : _startProcess = processStarter ?? _defaultStartProcess,
       _terminateProcessTree =
           processTreeTerminator ?? _defaultTerminateProcessTree,
       powershellPath = powershellPath ?? _defaultPowerShellPath;

  Future<PowerShellRunResult> run({
    required String script,
    Map<String, String> variables = const {},
    required Duration timeout,
    required String cancelPath,
    DiskToolsCancellationToken? cancellationToken,
    Duration cancellationGracePeriod = const Duration(seconds: 2),
  }) async {
    if (cancellationToken?.isCancelled == true) {
      return const PowerShellRunResult(
        processId: 0,
        exitCode: -1,
        stdout: '',
        stderr: '',
        completion: PowerShellCompletion.cancelled,
      );
    }

    final command = PowerShellCommandBuilder.build(
      script: script,
      variables: variables,
      powershellPath: powershellPath,
      cancelPath: cancelPath,
      cancelGracePeriod: cancellationGracePeriod,
      baseEnvironment: WindowsSystemEnvironment.withSystemRoot(),
    );
    final process = await _startProcess(
      command.executable,
      command.arguments,
      environment: command.environment,
    );

    final stdoutBuffer = StringBuffer();
    final stderrBuffer = StringBuffer();
    final stdoutDone = _capture(process.stdout, stdoutBuffer);
    final stderrDone = _capture(process.stderr, stderrBuffer);
    final exitCodeFuture = process.exitCode;
    final firstEvent = Completer<_ProcessEvent>();
    Timer? timeoutTimer;

    unawaited(
      exitCodeFuture.then((exitCode) {
        if (!firstEvent.isCompleted) {
          firstEvent.complete(_ProcessEvent.exited(exitCode));
        }
      }),
    );
    timeoutTimer = Timer(timeout, () {
      if (!firstEvent.isCompleted) {
        firstEvent.complete(const _ProcessEvent.timedOut());
      }
    });
    if (cancellationToken case final token?) {
      unawaited(
        token.whenCancelled.then((_) {
          if (!firstEvent.isCompleted) {
            firstEvent.complete(const _ProcessEvent.cancelled());
          }
        }),
      );
    }

    final event = await firstEvent.future;
    timeoutTimer.cancel();
    var exitCode = event.exitCode;
    if (event.completion != PowerShellCompletion.exited) {
      var cancellationSignalled = false;
      try {
        await File(cancelPath).writeAsString('cancel', flush: true);
        cancellationSignalled = true;
      } catch (_) {}
      exitCode = cancellationSignalled
          ? await _waitForGracefulExit(exitCodeFuture, cancellationGracePeriod)
          : null;
      if (exitCode == null) {
        await _terminateTree(process.pid);
        exitCode = await exitCodeFuture;
      }
    }

    await Future.wait([stdoutDone, stderrDone]);
    final confirmedExitCode = exitCode ?? await exitCodeFuture;
    return PowerShellRunResult(
      processId: process.pid,
      exitCode: confirmedExitCode,
      stdout: stdoutBuffer.toString(),
      stderr: stderrBuffer.toString(),
      completion: event.completion,
    );
  }

  static Future<void> _capture(Stream<List<int>> stream, StringBuffer target) {
    final completed = Completer<void>();
    stream
        .transform(const SystemEncoding().decoder)
        .listen(
          (chunk) {
            target.write(chunk);
          },
          onError: (_) {
            if (!completed.isCompleted) completed.complete();
          },
          onDone: () {
            if (!completed.isCompleted) completed.complete();
          },
          cancelOnError: true,
        );
    return completed.future;
  }

  static Future<int?> _waitForGracefulExit(
    Future<int> exitCode,
    Duration gracePeriod,
  ) async {
    if (gracePeriod <= Duration.zero) return null;
    try {
      return await exitCode.timeout(gracePeriod);
    } on TimeoutException {
      return null;
    }
  }

  Future<void> _terminateTree(int processId) async {
    try {
      await _terminateProcessTree(processId);
    } catch (_) {
      await _defaultTerminateProcessTree(processId);
    }
  }

  static Future<Process> _defaultStartProcess(
    String executable,
    List<String> arguments, {
    Map<String, String>? environment,
  }) {
    return Process.start(
      executable,
      arguments,
      environment: environment,
      runInShell: false,
    );
  }

  static Future<void> _defaultTerminateProcessTree(int processId) async {
    try {
      await Process.run(
        WindowsSystemEnvironment.taskkillExecutable,
        ['/F', '/T', '/PID', '$processId'],
        environment: WindowsSystemEnvironment.withSystemRoot(),
      ).timeout(const Duration(seconds: 15));
    } catch (_) {}
  }

  static String get _defaultPowerShellPath =>
      WindowsSystemEnvironment.powerShellExecutable;
}

class DiskToolsPowerShellWorkspace {
  final Directory directory;
  final String nonce;

  DiskToolsPowerShellWorkspace._(this.directory, this.nonce);

  File get outputFile => File('${directory.path}\\$nonce.result.json');
  File get cancelFile => File('${directory.path}\\$nonce.cancel.signal');

  static Future<DiskToolsPowerShellWorkspace> create(String prefix) async {
    if (!RegExp(r'^[a-z0-9_]+$').hasMatch(prefix)) {
      throw const FormatException('Invalid PowerShell workspace prefix.');
    }
    final random = Random.secure();
    final nonce = base64Url
        .encode(List<int>.generate(24, (_) => random.nextInt(256)))
        .replaceAll('=', '');
    final directory = await Directory.systemTemp.createTemp(
      '${prefix}_${nonce}_',
    );
    return DiskToolsPowerShellWorkspace._(directory, nonce);
  }

  Future<void> dispose() async {
    if (await directory.exists()) {
      await directory.delete(recursive: true);
    }
  }
}

class _ProcessEvent {
  final PowerShellCompletion completion;
  final int? exitCode;

  const _ProcessEvent._(this.completion, this.exitCode);

  const _ProcessEvent.exited(int exitCode)
    : this._(PowerShellCompletion.exited, exitCode);

  const _ProcessEvent.timedOut() : this._(PowerShellCompletion.timedOut, null);

  const _ProcessEvent.cancelled()
    : this._(PowerShellCompletion.cancelled, null);
}
