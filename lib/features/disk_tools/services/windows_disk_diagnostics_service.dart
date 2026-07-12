import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../models/disk_diagnostic_models.dart';
import 'secure_powershell_runner.dart';

final windowsDiskDiagnosticsServiceProvider =
    Provider<WindowsDiskDiagnosticsService>((ref) {
      return WindowsDiskDiagnosticsService();
    });

class DiskDiagnosticsException implements Exception {
  final String message;
  final bool elevationCancelled;
  final bool operationCancelled;

  const DiskDiagnosticsException(
    this.message, {
    this.elevationCancelled = false,
    this.operationCancelled = false,
  });

  @override
  String toString() => message;
}

typedef DiskDiagnosticsProcessStarter =
    Future<Process> Function(String executable, List<String> arguments);

/// Collects disk information through the bundled native helper.
///
/// The helper isolates each storage IOCTL in its own process. That matters for
/// USB bridges and storage drivers which can leave a normal synchronous query
/// blocked indefinitely. PowerShell is only used to request an optional
/// elevated launch; it never enumerates the storage provider for this feature.
class WindowsDiskDiagnosticsService {
  static const _nativeSource = 'Native Windows storage APIs';
  static const _reliabilitySource = 'Windows Storage Reliability Counter';
  static const _nvmeSource = 'Windows NVMe protocol query';
  static const _helperName = 'wds_disk_diagnostics_helper.exe';
  static const _helperTimeout = Duration(seconds: 24);
  static const _streamDrainTimeout = Duration(seconds: 2);

  final SecurePowerShellRunner _powerShellRunner;
  final DiskDiagnosticsProcessStarter _startNativeProcess;
  final String Function() _helperPath;

  WindowsDiskDiagnosticsService({
    SecurePowerShellRunner? powerShellRunner,
    DiskDiagnosticsProcessStarter? nativeProcessStarter,
    String Function()? helperPath,
  }) : _powerShellRunner = powerShellRunner ?? SecurePowerShellRunner(),
       _startNativeProcess = nativeProcessStarter ?? _defaultStartNativeProcess,
       _helperPath = helperPath ?? _defaultHelperPath;

  Future<DiskDiagnosticsSnapshot> collect({
    bool requestAdministrator = false,
    DiskToolsCancellationToken? cancellationToken,
  }) async {
    if (!Platform.isWindows) {
      throw const DiskDiagnosticsException(
        'Disk diagnostics are available on Windows only.',
      );
    }
    if (cancellationToken?.isCancelled == true) {
      throw const DiskDiagnosticsException(
        'Disk diagnostic collection was cancelled.',
        operationCancelled: true,
      );
    }

    final helper = File(_helperPath());
    if (!await helper.exists()) {
      throw const DiskDiagnosticsException(
        'The bundled disk diagnostic helper is unavailable.',
      );
    }

    final nativeResponse = requestAdministrator
        ? await _runElevatedHelper(helper, cancellationToken)
        : await _runHelperDirectly(helper, cancellationToken);
    final root = _decodeResponse(nativeResponse);
    if (root['ok'] != true) {
      throw DiskDiagnosticsException(
        _cleanString(root['error']) ?? 'Disk diagnostic collection failed.',
      );
    }

    final rawReports = root['reports'];
    if (rawReports is! List) {
      throw const DiskDiagnosticsException(
        'Windows returned no physical disk list.',
      );
    }

    final reports = <DiskDiagnosticReport>[];
    for (final raw in rawReports) {
      if (raw is! Map) {
        throw const DiskDiagnosticsException(
          'Windows returned an invalid physical disk entry.',
        );
      }
      final report = Map<String, dynamic>.from(raw);
      reports.add(
        _parseReport(report, _NvmeHealthData.fromJson(report['nvme'])),
      );
    }
    reports.sort((left, right) => left.diskNumber.compareTo(right.diskNumber));

    return DiskDiagnosticsSnapshot(
      reports: List.unmodifiable(reports),
      isAdministrator: root['isAdministrator'] == true,
      collectedAt: DateTime.now(),
      collectionWarnings: List.unmodifiable(_stringList(root['warnings'])),
    );
  }

  Future<String> _runHelperDirectly(
    File helper,
    DiskToolsCancellationToken? cancellationToken,
  ) async {
    Process process;
    try {
      process = await _startNativeProcess(helper.path, const ['--inventory']);
    } on ProcessException {
      throw const DiskDiagnosticsException(
        'The bundled disk diagnostic helper could not be started.',
      );
    }

    final stdout = _NativeOutputCapture(process.stdout);
    final stderr = _NativeOutputCapture(process.stderr);
    final firstEvent = Completer<_HelperProcessEvent>();
    final timeout = Timer(_helperTimeout, () {
      if (!firstEvent.isCompleted) {
        firstEvent.complete(const _HelperProcessEvent.timedOut());
      }
    });
    unawaited(
      process.exitCode.then((exitCode) {
        if (!firstEvent.isCompleted) {
          firstEvent.complete(_HelperProcessEvent.exited(exitCode));
        }
      }),
    );
    if (cancellationToken case final token?) {
      unawaited(
        token.whenCancelled.then((_) {
          if (!firstEvent.isCompleted) {
            firstEvent.complete(const _HelperProcessEvent.cancelled());
          }
        }),
      );
    }

    final event = await firstEvent.future;
    timeout.cancel();
    if (event.kind != _HelperProcessEventKind.exited) {
      process.kill();
      unawaited(stdout.cancel());
      unawaited(stderr.cancel());
      throw DiskDiagnosticsException(
        event.kind == _HelperProcessEventKind.cancelled
            ? 'Disk diagnostic collection was cancelled.'
            : 'The native disk diagnostic helper timed out.',
        operationCancelled: event.kind == _HelperProcessEventKind.cancelled,
      );
    }

    try {
      await Future.wait([
        stdout.done,
        stderr.done,
      ]).timeout(_streamDrainTimeout);
    } on TimeoutException {
      process.kill();
      unawaited(stdout.cancel());
      unawaited(stderr.cancel());
      throw const DiskDiagnosticsException(
        'The native disk diagnostic helper did not finish reading its response.',
      );
    }

    if (event.exitCode != 0) {
      final detail = _cleanString(stderr.text);
      throw DiskDiagnosticsException(
        detail == null
            ? 'The native disk diagnostic helper did not complete.'
            : 'The native disk diagnostic helper failed: $detail',
      );
    }
    final response = stdout.text.trim();
    if (response.isEmpty) {
      throw const DiskDiagnosticsException(
        'The native disk diagnostic helper returned no data.',
      );
    }
    return response;
  }

  Future<String> _runElevatedHelper(
    File helper,
    DiskToolsCancellationToken? cancellationToken,
  ) async {
    final workspace = await DiskToolsPowerShellWorkspace.create(
      'wds_disk_diagnostics',
    );
    final outputFile = workspace.outputFile;
    try {
      final result = await _powerShellRunner.run(
        script: _elevatedHelperScript,
        variables: {
          'WDS_DIAGNOSTICS_HELPER': helper.path,
          'WDS_DIAGNOSTICS_OUTPUT': outputFile.path,
          'WDS_RESPONSE_NONCE': workspace.nonce,
        },
        elevated: true,
        timeout: const Duration(seconds: 35),
        cancelPath: workspace.cancelFile.path,
        cancellationToken: cancellationToken,
      );
      if (result.timedOut) {
        throw const DiskDiagnosticsException(
          'The native disk diagnostic helper timed out.',
        );
      }
      if (result.cancelled) {
        throw const DiskDiagnosticsException(
          'Disk diagnostic collection was cancelled.',
          operationCancelled: true,
        );
      }
      if (!await outputFile.exists()) {
        final cancelled = result.elevationCancelled;
        throw DiskDiagnosticsException(
          cancelled
              ? 'Administrator access was cancelled.'
              : 'The native disk diagnostic helper returned no data.',
          elevationCancelled: cancelled,
        );
      }

      final envelope = _decodeResponse(await outputFile.readAsString());
      if (envelope['responseNonce'] != workspace.nonce) {
        throw const DiskDiagnosticsException(
          'Windows returned an invalid diagnostic response.',
        );
      }
      if (envelope['ok'] != true) {
        throw DiskDiagnosticsException(
          _cleanString(envelope['error']) ??
              'The native disk diagnostic helper did not complete.',
        );
      }
      final nativeResponse = _cleanString(envelope['nativeResponse']);
      if (nativeResponse == null) {
        throw const DiskDiagnosticsException(
          'The native disk diagnostic helper returned no data.',
        );
      }
      return nativeResponse;
    } finally {
      try {
        await workspace.dispose();
      } catch (_) {}
    }
  }

  DiskDiagnosticReport _parseReport(
    Map<String, dynamic> raw,
    _NvmeHealthData nvme,
  ) {
    final reliabilityReason =
        _cleanString(raw['reliabilityUnavailableReason']) ??
        'The storage driver did not expose a reliability counter.';
    final diskNumber = _intFrom(raw['diskNumber']) ?? -1;
    final wear = _intDiagnostic(
      raw['wearPercent'],
      _reliabilitySource,
      reliabilityReason,
    ).orElse(nvme.percentageUsed, _nvmeSource, nvme.unavailableReason);
    final wearValue = wear.value;
    final remainingLife = wearValue == null
        ? DiagnosticValue<int>.unavailable(
            unavailableReason: wear.unavailableReason,
            source: wear.source,
          )
        : DiagnosticValue<int>.available(
            (100 - wearValue).clamp(0, 100),
            source: '${wear.source}; calculated as 100 - wear used',
          );

    return DiskDiagnosticReport(
      diskNumber: diskNumber,
      model: _stringDiagnostic(
        raw['model'],
        _nativeSource,
        'Windows did not report a model for this disk.',
      ),
      sizeBytes: _bigIntDiagnostic(
        raw['sizeBytes'],
        _nativeSource,
        'Windows did not report the disk capacity.',
      ),
      serialNumber: _stringDiagnostic(
        raw['serialNumber'],
        _nativeSource,
        'Windows did not expose a serial number.',
      ),
      uniqueId: _stringDiagnostic(
        raw['uniqueId'],
        _nativeSource,
        'Windows did not expose a unique disk identifier.',
      ),
      busType: _stringDiagnostic(
        raw['busType'],
        _nativeSource,
        'Windows reported the bus type as unknown.',
        rejectUnknown: true,
      ),
      vendorId: _stringDiagnostic(
        raw['vendorId'],
        'Windows PnP device ancestry',
        'No USB VID was present in the PnP device ancestry.',
      ),
      productId: _stringDiagnostic(
        raw['productId'],
        'Windows PnP device ancestry',
        'No USB PID was present in the PnP device ancestry.',
      ),
      health: _stringDiagnostic(
        raw['health'],
        _cleanString(raw['healthSource']) ?? _nativeSource,
        'Windows did not report a usable health state.',
        rejectUnknown: true,
      ),
      temperatureCelsius: _intDiagnostic(
        raw['temperatureCelsius'],
        _reliabilitySource,
        reliabilityReason,
      ).orElse(nvme.temperatureCelsius, _nvmeSource, nvme.unavailableReason),
      wearPercent: wear,
      estimatedRemainingLifePercent: remainingLife,
      readErrorsCorrected: _bigIntDiagnostic(
        raw['readErrorsCorrected'],
        _reliabilitySource,
        reliabilityReason,
      ),
      readErrorsUncorrected: _bigIntDiagnostic(
        raw['readErrorsUncorrected'],
        _reliabilitySource,
        reliabilityReason,
      ),
      readErrorsTotal: _bigIntDiagnostic(
        raw['readErrorsTotal'],
        _reliabilitySource,
        reliabilityReason,
      ),
      writeErrorsCorrected: _bigIntDiagnostic(
        raw['writeErrorsCorrected'],
        _reliabilitySource,
        reliabilityReason,
      ),
      writeErrorsUncorrected: _bigIntDiagnostic(
        raw['writeErrorsUncorrected'],
        _reliabilitySource,
        reliabilityReason,
      ),
      writeErrorsTotal: _bigIntDiagnostic(
        raw['writeErrorsTotal'],
        _reliabilitySource,
        reliabilityReason,
      ),
      powerOnHours: _bigIntDiagnostic(
        raw['powerOnHours'],
        _reliabilitySource,
        reliabilityReason,
      ).orElse(nvme.powerOnHours, _nvmeSource, nvme.unavailableReason),
      hostReadBytes: _diagnosticFromNullable(
        nvme.hostReadBytes,
        source: _nvmeSource,
        unavailableReason: nvme.unavailableReason,
      ),
      hostWrittenBytes: _diagnosticFromNullable(
        nvme.hostWrittenBytes,
        source: _nvmeSource,
        unavailableReason: nvme.unavailableReason,
      ),
      hostReadCommands: _diagnosticFromNullable(
        nvme.hostReadCommands,
        source: _nvmeSource,
        unavailableReason: nvme.unavailableReason,
      ),
      hostWriteCommands: _diagnosticFromNullable(
        nvme.hostWriteCommands,
        source: _nvmeSource,
        unavailableReason: nvme.unavailableReason,
      ),
      mediaAndDataIntegrityErrors: _diagnosticFromNullable(
        nvme.mediaAndDataIntegrityErrors,
        source: _nvmeSource,
        unavailableReason: nvme.unavailableReason,
      ),
      firmwareVersion: _stringDiagnostic(
        raw['firmwareVersion'],
        _nativeSource,
        'Windows did not expose the firmware version.',
      ),
      mediaType: _stringDiagnostic(
        raw['mediaType'],
        _nativeSource,
        'Windows reported the media type as unknown.',
        rejectUnknown: true,
      ),
      partitionStyle: _stringDiagnostic(
        raw['partitionStyle'],
        _nativeSource,
        'Windows reported the partition style as unknown.',
        rejectUnknown: true,
      ),
      operationalStatus: _stringDiagnostic(
        raw['operationalStatus'],
        _nativeSource,
        'Windows did not report an operational status.',
        rejectUnknown: true,
      ),
      pnpDeviceId: _stringDiagnostic(
        raw['pnpDeviceId'],
        'Native Windows device descriptor',
        'Windows did not expose a PnP device ID.',
      ),
      devicePath: _stringDiagnostic(
        raw['devicePath'],
        _nativeSource,
        'Windows did not expose a storage device path.',
      ),
      driveLetters: _stringList(raw['driveLetters']),
      isSystem: raw['isSystem'] == true,
      isBoot: raw['isBoot'] == true,
      isOffline: raw['isOffline'] == true,
      isReadOnly: raw['isReadOnly'] == true,
      isRemovable: raw['isRemovable'] == true,
    );
  }

  static Map<String, dynamic> _decodeResponse(String rawText) {
    try {
      final decoded = jsonDecode(rawText.replaceFirst('\ufeff', ''));
      if (decoded is! Map) throw const FormatException();
      return Map<String, dynamic>.from(decoded);
    } on FormatException {
      throw const DiskDiagnosticsException(
        'Windows returned malformed disk diagnostic data.',
      );
    }
  }

  static Future<Process> _defaultStartNativeProcess(
    String executable,
    List<String> arguments,
  ) {
    return Process.start(executable, arguments, runInShell: false);
  }

  static String _defaultHelperPath() {
    return p.join(p.dirname(Platform.resolvedExecutable), _helperName);
  }

  static String get diagnosticsScriptForTesting => _elevatedHelperScript;

  static const _elevatedHelperScript = r'''
$ErrorActionPreference = 'Stop'

function Write-DiagnosticEnvelope([bool]$ok, [string]$error, [string]$nativeResponse) {
  $payload = [PSCustomObject]@{
    ok = $ok
    error = $error
    nativeResponse = $nativeResponse
    responseNonce = $env:WDS_RESPONSE_NONCE
  } | ConvertTo-Json -Compress
  [IO.File]::WriteAllText(
    $env:WDS_DIAGNOSTICS_OUTPUT,
    $payload,
    (New-Object Text.UTF8Encoding($false))
  )
}

try {
  $helper = $env:WDS_DIAGNOSTICS_HELPER
  if ([string]::IsNullOrWhiteSpace($helper) -or
      -not (Test-Path -LiteralPath $helper -PathType Leaf)) {
    throw 'The bundled disk diagnostic helper is unavailable.'
  }
  $nativeLines = @(& $helper '--inventory')
  if ($LASTEXITCODE -ne 0) {
    throw 'The bundled disk diagnostic helper did not complete.'
  }
  $nativeResponse = $nativeLines -join [Environment]::NewLine
  if ([string]::IsNullOrWhiteSpace($nativeResponse)) {
    throw 'The bundled disk diagnostic helper returned no data.'
  }
  Write-DiagnosticEnvelope $true $null $nativeResponse
} catch {
  Write-DiagnosticEnvelope $false 'The bundled disk diagnostic helper did not complete.' $null
  exit 1
}
''';
}

extension<T> on DiagnosticValue<T> {
  DiagnosticValue<T> orElse(
    T? fallback,
    String fallbackSource,
    String fallbackReason,
  ) {
    if (isAvailable) return this;
    return _diagnosticFromNullable(
      fallback,
      source: fallbackSource,
      unavailableReason: fallbackReason,
    );
  }
}

DiagnosticValue<T> _diagnosticFromNullable<T>(
  T? value, {
  required String source,
  required String unavailableReason,
}) {
  return value == null
      ? DiagnosticValue<T>.unavailable(
          unavailableReason: unavailableReason,
          source: source,
        )
      : DiagnosticValue<T>.available(value, source: source);
}

DiagnosticValue<String> _stringDiagnostic(
  dynamic raw,
  String source,
  String unavailableReason, {
  bool rejectUnknown = false,
}) {
  final value = _cleanString(raw);
  final unavailable =
      value == null ||
      (rejectUnknown &&
          const {
            'UNKNOWN',
            'UNSPECIFIED',
            'DEFAULT',
          }.contains(value.toUpperCase()));
  return unavailable
      ? DiagnosticValue<String>.unavailable(
          unavailableReason: unavailableReason,
          source: source,
        )
      : DiagnosticValue<String>.available(value, source: source);
}

DiagnosticValue<int> _intDiagnostic(
  dynamic raw,
  String source,
  String unavailableReason,
) {
  return _diagnosticFromNullable(
    _intFrom(raw),
    source: source,
    unavailableReason: unavailableReason,
  );
}

DiagnosticValue<BigInt> _bigIntDiagnostic(
  dynamic raw,
  String source,
  String unavailableReason,
) {
  return _diagnosticFromNullable(
    _bigIntFrom(raw),
    source: source,
    unavailableReason: unavailableReason,
  );
}

String? _cleanString(dynamic raw) {
  if (raw == null) return null;
  final value = raw.toString().trim();
  return value.isEmpty ? null : value;
}

List<String> _stringList(dynamic raw) {
  if (raw is! List) return const [];
  return raw.map(_cleanString).whereType<String>().toList(growable: false);
}

int? _intFrom(dynamic raw) {
  if (raw is int) return raw;
  return int.tryParse(raw?.toString() ?? '');
}

BigInt? _bigIntFrom(dynamic raw) {
  if (raw == null) return null;
  return BigInt.tryParse(raw.toString());
}

class _NvmeHealthData {
  final int? temperatureCelsius;
  final int? percentageUsed;
  final BigInt? hostReadBytes;
  final BigInt? hostWrittenBytes;
  final BigInt? hostReadCommands;
  final BigInt? hostWriteCommands;
  final BigInt? powerOnHours;
  final BigInt? mediaAndDataIntegrityErrors;
  final String unavailableReason;

  const _NvmeHealthData({
    required this.temperatureCelsius,
    required this.percentageUsed,
    required this.hostReadBytes,
    required this.hostWrittenBytes,
    required this.hostReadCommands,
    required this.hostWriteCommands,
    required this.powerOnHours,
    required this.mediaAndDataIntegrityErrors,
  }) : unavailableReason =
           'The device or storage driver did not expose this NVMe value.';

  const _NvmeHealthData.unavailable(this.unavailableReason)
    : temperatureCelsius = null,
      percentageUsed = null,
      hostReadBytes = null,
      hostWrittenBytes = null,
      hostReadCommands = null,
      hostWriteCommands = null,
      powerOnHours = null,
      mediaAndDataIntegrityErrors = null;

  factory _NvmeHealthData.fromJson(dynamic raw) {
    if (raw is! Map) {
      return const _NvmeHealthData.unavailable(
        'The native helper did not return an NVMe health response.',
      );
    }
    final map = Map<String, dynamic>.from(raw);
    if (map['available'] != true) {
      return _NvmeHealthData.unavailable(
        _cleanString(map['reason']) ??
            'The device or storage driver did not expose NVMe health data.',
      );
    }
    return _NvmeHealthData(
      temperatureCelsius: _intFrom(map['temperatureCelsius']),
      percentageUsed: _intFrom(map['percentageUsed']),
      hostReadBytes: _bigIntFrom(map['hostReadBytes']),
      hostWrittenBytes: _bigIntFrom(map['hostWrittenBytes']),
      hostReadCommands: _bigIntFrom(map['hostReadCommands']),
      hostWriteCommands: _bigIntFrom(map['hostWriteCommands']),
      powerOnHours: _bigIntFrom(map['powerOnHours']),
      mediaAndDataIntegrityErrors: _bigIntFrom(
        map['mediaAndDataIntegrityErrors'],
      ),
    );
  }
}

enum _HelperProcessEventKind { exited, timedOut, cancelled }

class _HelperProcessEvent {
  final _HelperProcessEventKind kind;
  final int? exitCode;

  const _HelperProcessEvent._(this.kind, this.exitCode);

  const _HelperProcessEvent.exited(int exitCode)
    : this._(_HelperProcessEventKind.exited, exitCode);

  const _HelperProcessEvent.timedOut()
    : this._(_HelperProcessEventKind.timedOut, null);

  const _HelperProcessEvent.cancelled()
    : this._(_HelperProcessEventKind.cancelled, null);
}

class _NativeOutputCapture {
  final StringBuffer _buffer = StringBuffer();
  final Completer<void> _completed = Completer<void>();
  late final StreamSubscription<String> _subscription;

  _NativeOutputCapture(Stream<List<int>> stream) {
    _subscription = stream
        .transform(utf8.decoder)
        .listen(
          _buffer.write,
          onError: (_, _) {
            if (!_completed.isCompleted) _completed.complete();
          },
          onDone: () {
            if (!_completed.isCompleted) _completed.complete();
          },
          cancelOnError: true,
        );
  }

  String get text => _buffer.toString();
  Future<void> get done => _completed.future;

  Future<void> cancel() => _subscription.cancel();
}
