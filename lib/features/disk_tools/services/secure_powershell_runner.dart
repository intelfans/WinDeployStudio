import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

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
  final String? elevatedPidToken;

  const PowerShellLaunchCommand({
    required this.executable,
    required this.arguments,
    required this.environment,
    this.elevatedPidToken,
  });
}

class PowerShellCommandBuilder {
  static const scriptPayloadVariable = 'WDS_PS_SCRIPT_GZIP';
  static const bootstrapVariable = 'WDS_PS_BOOTSTRAP';
  static const executableVariable = 'WDS_PS_EXECUTABLE';
  static const cancelPathVariable = 'WDS_PS_CANCEL_PATH';
  static const cancelGraceVariable = 'WDS_PS_CANCEL_GRACE_MS';
  static const elevatedPidTokenVariable = 'WDS_PS_ELEVATED_PID_TOKEN';
  static const elevatedPidMarker = '__WDS_ELEVATED_PID__=';

  static final RegExp _variableName = RegExp(r'^WDS_[A-Z0-9_]+$');
  static final Random _random = Random.secure();
  static const Set<String> _reservedVariables = {
    scriptPayloadVariable,
    bootstrapVariable,
    executableVariable,
    cancelPathVariable,
    cancelGraceVariable,
    elevatedPidTokenVariable,
  };

  static PowerShellLaunchCommand build({
    required String script,
    required Map<String, String> variables,
    required bool elevated,
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
    final elevatedPidToken = elevated ? _newElevationPidToken() : null;
    final environment = <String, String>{
      ...?baseEnvironment,
      ...checkedVariables,
      scriptPayloadVariable: payload,
      bootstrapVariable: bootstrap,
      executableVariable: powershellPath,
      cancelPathVariable: cancelPath,
      cancelGraceVariable: '${cancelGracePeriod.inMilliseconds}',
      ...?elevatedPidToken == null
          ? null
          : <String, String>{elevatedPidTokenVariable: elevatedPidToken},
    };
    final arguments = elevated
        ? [
            '-NoLogo',
            '-NoProfile',
            '-NonInteractive',
            '-ExecutionPolicy',
            'Bypass',
            '-EncodedCommand',
            _encodedElevationLauncher,
          ]
        : [
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
      elevatedPidToken: elevatedPidToken,
    );
  }

  static String _newElevationPidToken() => List<int>.generate(
    24,
    (_) => _random.nextInt(256),
  ).map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();

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

  static const _elevationLauncher = r'''
$ErrorActionPreference = 'Stop'
try {
  $markerToken = $env:WDS_PS_ELEVATED_PID_TOKEN
  if ([string]::IsNullOrWhiteSpace($markerToken)) {
    throw 'The elevated process marker token is missing.'
  }
  $arguments = @(
    '-NoLogo',
    '-NoProfile',
    '-NonInteractive',
    '-ExecutionPolicy',
    'Bypass',
    '-EncodedCommand',
    $env:WDS_PS_BOOTSTRAP
  )
  $process = Start-Process -FilePath $env:WDS_PS_EXECUTABLE `
    -ArgumentList $arguments -Verb RunAs -WindowStyle Hidden -PassThru
  [Console]::Out.WriteLine('__WDS_ELEVATED_PID__=' + $markerToken + ':' + $process.Id)
  [Console]::Out.Flush()
  $process.WaitForExit()
  exit $process.ExitCode
} catch {
  if ($_.Exception.NativeErrorCode -eq 1223) { exit 1223 }
  [Console]::Error.WriteLine($_.Exception.ToString())
  exit 1
}
''';

  static final String _encodedElevationLauncher = encodeCommand(
    _elevationLauncher,
  );
}

class PowerShellRunResult {
  final int processId;
  final int? elevatedProcessId;
  final int exitCode;
  final String stdout;
  final String stderr;
  final PowerShellCompletion completion;

  const PowerShellRunResult({
    required this.processId,
    required this.elevatedProcessId,
    required this.exitCode,
    required this.stdout,
    required this.stderr,
    required this.completion,
  });

  bool get timedOut => completion == PowerShellCompletion.timedOut;
  bool get cancelled => completion == PowerShellCompletion.cancelled;
  bool get elevationCancelled =>
      completion == PowerShellCompletion.exited && exitCode == 1223;
}

typedef DiskToolsProcessStarter =
    Future<Process> Function(
      String executable,
      List<String> arguments, {
      Map<String, String>? environment,
    });
typedef DiskToolsProcessTreeTerminator = Future<void> Function(int processId);
typedef DiskToolsProcessExitWaiter = Future<void> Function(int processId);

/// Accepts only complete, token-bound records emitted by the elevation launcher.
class _ElevatedPidRecordParser {
  static const _maximumRecordLength = 128;

  final String _prefix;
  String _pending = '';

  _ElevatedPidRecordParser(String token)
    : _prefix = '${PowerShellCommandBuilder.elevatedPidMarker}$token:';

  int? add(String text) {
    if (text.isEmpty) return null;

    final records = ('$_pending$text').split('\n');
    _pending = records.removeLast();
    if (_pending.length > _maximumRecordLength) _pending = '';

    for (final record in records) {
      final processId = _parseRecord(record);
      if (processId != null) return processId;
    }
    return null;
  }

  int? _parseRecord(String record) {
    if (record.endsWith('\r')) {
      record = record.substring(0, record.length - 1);
    }
    if (!record.startsWith(_prefix)) return null;

    final processIdText = record.substring(_prefix.length);
    if (!RegExp(r'^[1-9][0-9]*$').hasMatch(processIdText)) return null;
    final processId = int.tryParse(processIdText);
    if (processId == null || processId > 0xffffffff) return null;
    return processId;
  }
}

class SecurePowerShellRunner {
  final DiskToolsProcessStarter _startProcess;
  final DiskToolsProcessTreeTerminator _terminateProcessTree;
  final DiskToolsProcessExitWaiter _waitForProcessExit;
  final String powershellPath;

  SecurePowerShellRunner({
    DiskToolsProcessStarter? processStarter,
    DiskToolsProcessTreeTerminator? processTreeTerminator,
    DiskToolsProcessExitWaiter? processExitWaiter,
    String? powershellPath,
  }) : _startProcess = processStarter ?? _defaultStartProcess,
       _terminateProcessTree =
           processTreeTerminator ?? _defaultTerminateProcessTree,
       _waitForProcessExit = processExitWaiter ?? _defaultWaitForProcessExit,
       powershellPath = powershellPath ?? _defaultPowerShellPath;

  Future<PowerShellRunResult> run({
    required String script,
    Map<String, String> variables = const {},
    required bool elevated,
    required Duration timeout,
    required String cancelPath,
    DiskToolsCancellationToken? cancellationToken,
    Duration cancellationGracePeriod = const Duration(seconds: 2),
  }) async {
    if (cancellationToken?.isCancelled == true) {
      return const PowerShellRunResult(
        processId: 0,
        elevatedProcessId: null,
        exitCode: -1,
        stdout: '',
        stderr: '',
        completion: PowerShellCompletion.cancelled,
      );
    }

    final command = PowerShellCommandBuilder.build(
      script: script,
      variables: variables,
      elevated: elevated,
      powershellPath: powershellPath,
      cancelPath: cancelPath,
      cancelGracePeriod: cancellationGracePeriod,
      baseEnvironment: Platform.environment,
    );
    final process = await _startProcess(
      command.executable,
      command.arguments,
      environment: command.environment,
    );

    int? elevatedProcessId;
    final stdoutBuffer = StringBuffer();
    final stderrBuffer = StringBuffer();
    final elevatedPidParser = command.elevatedPidToken == null
        ? null
        : _ElevatedPidRecordParser(command.elevatedPidToken!);
    final stdoutDone = _capture(
      process.stdout,
      stdoutBuffer,
      onText: (text) {
        final processId = elevatedPidParser?.add(text);
        if (processId != null) elevatedProcessId ??= processId;
      },
    );
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
        final elevatedPid = elevatedProcessId;
        if (elevatedPid != null) {
          await _terminateTree(elevatedPid);
          await _waitForProcessExit(elevatedPid);
        }
        await _terminateTree(process.pid);
        exitCode = await exitCodeFuture;
      }
    }

    await Future.wait([stdoutDone, stderrDone]);
    final confirmedExitCode = exitCode ?? await exitCodeFuture;
    return PowerShellRunResult(
      processId: process.pid,
      elevatedProcessId: elevatedProcessId,
      exitCode: confirmedExitCode,
      stdout: stdoutBuffer.toString(),
      stderr: stderrBuffer.toString(),
      completion: event.completion,
    );
  }

  static Future<void> _capture(
    Stream<List<int>> stream,
    StringBuffer target, {
    void Function(String text)? onText,
  }) {
    final completed = Completer<void>();
    stream
        .transform(const SystemEncoding().decoder)
        .listen(
          (chunk) {
            target.write(chunk);
            onText?.call(chunk);
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
    final systemRoot = Platform.environment['SystemRoot'] ?? r'C:\Windows';
    final taskkill = '$systemRoot\\System32\\taskkill.exe';
    try {
      await Process.run(taskkill, [
        '/F',
        '/T',
        '/PID',
        '$processId',
      ]).timeout(const Duration(seconds: 15));
    } catch (_) {}
  }

  static Future<void> _defaultWaitForProcessExit(int processId) async {
    final systemRoot = Platform.environment['SystemRoot'] ?? r'C:\Windows';
    final tasklist = '$systemRoot\\System32\\tasklist.exe';
    final deadline = DateTime.now().add(const Duration(seconds: 30));
    while (DateTime.now().isBefore(deadline)) {
      try {
        final result = await Process.run(tasklist, [
          '/FI',
          'PID eq $processId',
          '/FO',
          'CSV',
          '/NH',
        ]).timeout(const Duration(seconds: 5));
        final output = result.stdout.toString();
        if (!RegExp('(?:^|,)"?$processId"?(?:,|\$)').hasMatch(output)) {
          return;
        }
      } catch (_) {
        return;
      }
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    throw TimeoutException('Process $processId did not exit after taskkill.');
  }

  static String get _defaultPowerShellPath {
    final systemRoot = Platform.environment['SystemRoot'] ?? r'C:\Windows';
    return '$systemRoot\\System32\\WindowsPowerShell\\v1.0\\powershell.exe';
  }
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
