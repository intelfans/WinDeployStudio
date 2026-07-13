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
  final String localizationKey;
  final bool operationCancelled;

  const DiskDiagnosticsException(
    this.message, {
    this.localizationKey = 'disk_diag_error',
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
/// blocked indefinitely. The main application always starts elevated, so the
/// helper inherits the same token without opening a second UAC flow.
class WindowsDiskDiagnosticsService {
  static const _nativeSource = 'Native Windows storage APIs';
  static const _reliabilitySource = 'Windows Storage Reliability Counter';
  static const _helperName = 'wds_disk_diagnostics_helper.exe';
  static const _helperTimeout = Duration(seconds: 24);
  static const _streamDrainTimeout = Duration(seconds: 2);

  final DiskDiagnosticsProcessStarter _startNativeProcess;
  final String Function() _helperPath;

  WindowsDiskDiagnosticsService({
    DiskDiagnosticsProcessStarter? nativeProcessStarter,
    String Function()? helperPath,
  }) : _startNativeProcess = nativeProcessStarter ?? _defaultStartNativeProcess,
       _helperPath = helperPath ?? _defaultHelperPath;

  Future<DiskDiagnosticsSnapshot> collect({
    DiskToolsCancellationToken? cancellationToken,
  }) async {
    if (!Platform.isWindows) {
      throw const DiskDiagnosticsException(
        'Disk diagnostics are available on Windows only.',
        localizationKey: 'disk_tools_error_windows_only',
      );
    }
    if (cancellationToken?.isCancelled == true) {
      throw const DiskDiagnosticsException(
        'Disk diagnostic collection was cancelled.',
        localizationKey: 'disk_diag_error_cancelled',
        operationCancelled: true,
      );
    }

    final helper = File(_helperPath());
    if (!await helper.exists()) {
      throw const DiskDiagnosticsException(
        'The bundled disk diagnostic helper is unavailable.',
        localizationKey: 'disk_diag_error_helper_missing',
      );
    }

    final nativeResponse = await _runHelperDirectly(helper, cancellationToken);
    final root = _decodeResponse(nativeResponse);
    if (root['ok'] != true) {
      throw DiskDiagnosticsException(
        _cleanString(root['error']) ?? 'Disk diagnostic collection failed.',
        localizationKey: _errorLocalizationKey(root['errorCode']),
      );
    }

    final rawReports = root['reports'];
    if (rawReports is! List) {
      throw const DiskDiagnosticsException(
        'Windows returned no physical disk list.',
        localizationKey: 'disk_diag_error_invalid_response',
      );
    }

    final reports = <DiskDiagnosticReport>[];
    for (final raw in rawReports) {
      if (raw is! Map) {
        throw const DiskDiagnosticsException(
          'Windows returned an invalid physical disk entry.',
          localizationKey: 'disk_diag_error_invalid_response',
        );
      }
      final report = Map<String, dynamic>.from(raw);
      reports.add(
        _parseReport(
          report,
          _NvmeHealthData.fromJson(report['nvme']),
          _AtaSmartData.fromJson(report['ataSmart']),
        ),
      );
    }
    reports.sort((left, right) => left.diskNumber.compareTo(right.diskNumber));

    return DiskDiagnosticsSnapshot(
      reports: List.unmodifiable(reports),
      isAdministrator: root['isAdministrator'] == true,
      collectedAt: DateTime.now(),
      collectionWarnings: List.unmodifiable(_warningCodes(root['warnings'])),
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
        localizationKey: 'disk_diag_error_helper_start',
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
        localizationKey: event.kind == _HelperProcessEventKind.cancelled
            ? 'disk_diag_error_cancelled'
            : 'disk_diag_error_timeout',
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
        localizationKey: 'disk_diag_error_invalid_response',
      );
    }

    if (event.exitCode != 0) {
      final detail = _cleanString(stderr.text);
      throw DiskDiagnosticsException(
        detail == null
            ? 'The native disk diagnostic helper did not complete.'
            : 'The native disk diagnostic helper failed: $detail',
        localizationKey: 'disk_diag_error_helper_failed',
      );
    }
    final response = stdout.text.trim();
    if (response.isEmpty) {
      throw const DiskDiagnosticsException(
        'The native disk diagnostic helper returned no data.',
        localizationKey: 'disk_diag_error_no_data',
      );
    }
    return response;
  }

  DiskDiagnosticReport _parseReport(
    Map<String, dynamic> raw,
    _NvmeHealthData nvme,
    _AtaSmartData ataSmart,
  ) {
    final reliabilityReason =
        _cleanString(raw['reliabilityUnavailableReason']) ??
        'The storage driver did not expose a reliability counter.';
    final reliabilityReasonCode =
        _cleanString(raw['reliabilityUnavailableReasonCode']) ??
        _cleanString(raw['reliabilityReasonCode']);
    final reliabilityWindowsError =
        _intFrom(raw['reliabilityUnavailableWindowsError']) ??
        _intFrom(raw['reliabilityWindowsError']) ??
        _intFrom(raw['reliabilityUnavailableError']);
    final reliabilityUnavailableReasonKind =
        _unavailabilityKindForTechnicalReason(
          reliabilityReason,
          reasonCode: reliabilityReasonCode,
          windowsError: reliabilityWindowsError,
          fallback: DiagnosticUnavailableReason.notExposedByDeviceOrDriver,
        );
    final diskNumber = _intFrom(raw['diskNumber']) ?? -1;
    final busType = _stringDiagnostic(
      raw['busType'],
      _nativeSource,
      'Windows reported the bus type as unknown.',
      rejectUnknown: true,
    );
    final usbIdentifierUnavailableReasonKind =
        busType.isAvailable && busType.value?.toUpperCase() != 'USB'
        ? DiagnosticUnavailableReason.notApplicable
        : DiagnosticUnavailableReason.notReported;
    final smartFallback = _SmartMetricFallback.forDisk(
      busType: busType,
      nvme: nvme,
      ataSmart: ataSmart,
      reliabilityReason: reliabilityReason,
      reliabilityUnavailableReasonKind: reliabilityUnavailableReasonKind,
    );
    // The native top-level metrics come exclusively from Windows storage
    // counters. ATA/SAT values live in ataSmart and are only used below as a
    // fallback, so the rendered source always matches the actual query path.
    const topLevelMetricSource = _reliabilitySource;
    final topLevelMetricUnavailableReason = reliabilityReason;
    final topLevelMetricUnavailableReasonKind =
        reliabilityUnavailableReasonKind;
    final wear =
        _intDiagnostic(
          raw['wearPercent'],
          topLevelMetricSource,
          topLevelMetricUnavailableReason,
          unavailableReasonKind: topLevelMetricUnavailableReasonKind,
        ).orElse(
          smartFallback.percentageUsed,
          smartFallback.source,
          smartFallback.unavailableReason,
          smartFallback.unavailableReasonKind,
        );
    final wearValue = wear.value;
    final remainingLife = wearValue == null
        ? DiagnosticValue<int>.unavailable(
            unavailableReason: wear.unavailableReason,
            source: wear.source,
            unavailableReasonKind:
                wear.unavailableReasonKind ??
                DiagnosticUnavailableReason.notReported,
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
      busType: busType,
      vendorId: _stringDiagnostic(
        raw['vendorId'],
        'Windows PnP device ancestry',
        'No USB VID was present in the PnP device ancestry.',
        unavailableReasonKind: usbIdentifierUnavailableReasonKind,
      ),
      productId: _stringDiagnostic(
        raw['productId'],
        'Windows PnP device ancestry',
        'No USB PID was present in the PnP device ancestry.',
        unavailableReasonKind: usbIdentifierUnavailableReasonKind,
      ),
      health: _stringDiagnostic(
        raw['health'],
        _cleanString(raw['healthSource']) ?? _nativeSource,
        smartFallback.unavailableReason,
        rejectUnknown: true,
        unavailableReasonKind: smartFallback.unavailableReasonKind,
      ),
      temperatureCelsius:
          _intDiagnostic(
            raw['temperatureCelsius'],
            topLevelMetricSource,
            topLevelMetricUnavailableReason,
            unavailableReasonKind: topLevelMetricUnavailableReasonKind,
          ).orElse(
            smartFallback.temperatureCelsius,
            smartFallback.source,
            smartFallback.unavailableReason,
            smartFallback.unavailableReasonKind,
          ),
      wearPercent: wear,
      estimatedRemainingLifePercent: remainingLife,
      readErrorsCorrected: _bigIntDiagnostic(
        raw['readErrorsCorrected'],
        topLevelMetricSource,
        topLevelMetricUnavailableReason,
        unavailableReasonKind: topLevelMetricUnavailableReasonKind,
      ),
      readErrorsUncorrected: _bigIntDiagnostic(
        raw['readErrorsUncorrected'],
        topLevelMetricSource,
        topLevelMetricUnavailableReason,
        unavailableReasonKind: topLevelMetricUnavailableReasonKind,
      ),
      readErrorsTotal: _bigIntDiagnostic(
        raw['readErrorsTotal'],
        topLevelMetricSource,
        topLevelMetricUnavailableReason,
        unavailableReasonKind: topLevelMetricUnavailableReasonKind,
      ),
      writeErrorsCorrected: _bigIntDiagnostic(
        raw['writeErrorsCorrected'],
        topLevelMetricSource,
        topLevelMetricUnavailableReason,
        unavailableReasonKind: topLevelMetricUnavailableReasonKind,
      ),
      writeErrorsUncorrected: _bigIntDiagnostic(
        raw['writeErrorsUncorrected'],
        topLevelMetricSource,
        topLevelMetricUnavailableReason,
        unavailableReasonKind: topLevelMetricUnavailableReasonKind,
      ),
      writeErrorsTotal: _bigIntDiagnostic(
        raw['writeErrorsTotal'],
        topLevelMetricSource,
        topLevelMetricUnavailableReason,
        unavailableReasonKind: topLevelMetricUnavailableReasonKind,
      ),
      powerOnHours:
          _bigIntDiagnostic(
            raw['powerOnHours'],
            topLevelMetricSource,
            topLevelMetricUnavailableReason,
            unavailableReasonKind: topLevelMetricUnavailableReasonKind,
          ).orElse(
            smartFallback.powerOnHours,
            smartFallback.source,
            smartFallback.unavailableReason,
            smartFallback.unavailableReasonKind,
          ),
      hostReadBytes: _diagnosticFromNullable(
        smartFallback.hostReadBytes,
        source: smartFallback.source,
        unavailableReason: smartFallback.unavailableReason,
        unavailableReasonKind: smartFallback.unavailableReasonKind,
      ),
      hostWrittenBytes: _diagnosticFromNullable(
        smartFallback.hostWrittenBytes,
        source: smartFallback.source,
        unavailableReason: smartFallback.unavailableReason,
        unavailableReasonKind: smartFallback.unavailableReasonKind,
      ),
      hostReadCommands: _diagnosticFromNullable(
        smartFallback.hostReadCommands,
        source: smartFallback.source,
        unavailableReason: smartFallback.unavailableReason,
        unavailableReasonKind: smartFallback.unavailableReasonKind,
      ),
      hostWriteCommands: _diagnosticFromNullable(
        smartFallback.hostWriteCommands,
        source: smartFallback.source,
        unavailableReason: smartFallback.unavailableReason,
        unavailableReasonKind: smartFallback.unavailableReasonKind,
      ),
      mediaAndDataIntegrityErrors: _diagnosticFromNullable(
        smartFallback.mediaAndDataIntegrityErrors,
        source: smartFallback.source,
        unavailableReason: smartFallback.unavailableReason,
        unavailableReasonKind: smartFallback.unavailableReasonKind,
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
      isSystem: _boolDiagnostic(
        raw['isSystem'],
        'Windows volume mapping',
        'Windows did not report whether this is the system disk.',
      ),
      isBoot: _boolDiagnostic(
        raw['isBoot'],
        _nativeSource,
        'Windows did not report whether this is the boot disk.',
      ),
      isOffline: _boolDiagnostic(
        raw['isOffline'],
        _nativeSource,
        'Windows did not report the offline state.',
      ),
      isReadOnly: _boolDiagnostic(
        raw['isReadOnly'],
        _nativeSource,
        'Windows did not report the read-only state.',
      ),
      isRemovable: _boolDiagnostic(
        raw['isRemovable'],
        _nativeSource,
        'Windows did not report the removable-media state.',
      ),
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
        localizationKey: 'disk_diag_error_invalid_response',
      );
    }
  }

  static String _errorLocalizationKey(dynamic rawCode) {
    const supported = <String>{
      'disk_diag_error_helper_missing',
      'disk_diag_error_helper_start',
      'disk_diag_error_helper_failed',
      'disk_diag_error_timeout',
      'disk_diag_error_no_data',
      'disk_diag_error_invalid_response',
    };
    final code = _cleanString(rawCode);
    return code != null && supported.contains(code) ? code : 'disk_diag_error';
  }

  static List<String> _warningCodes(dynamic raw) {
    if (raw is! List || raw.isEmpty) return const [];
    const supported = <String>{'disk_diag_warning_partial'};
    final codes = <String>{};
    for (final item in raw) {
      final code = item is Map
          ? _cleanString(item['code'])
          : item is String
          ? null
          : null;
      // Legacy helpers returned English warning text. Preserve the warning
      // state without rendering their driver-specific text in the UI.
      codes.add(
        code != null && supported.contains(code)
            ? code
            : 'disk_diag_warning_partial',
      );
    }
    return List.unmodifiable(codes);
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
}

extension<T> on DiagnosticValue<T> {
  DiagnosticValue<T> orElse(
    T? fallback,
    String fallbackSource,
    String fallbackReason,
    DiagnosticUnavailableReason fallbackReasonKind,
  ) {
    if (isAvailable) return this;
    return _diagnosticFromNullable(
      fallback,
      source: fallbackSource,
      unavailableReason: fallbackReason,
      unavailableReasonKind: fallbackReasonKind,
    );
  }
}

DiagnosticValue<T> _diagnosticFromNullable<T>(
  T? value, {
  required String source,
  required String unavailableReason,
  DiagnosticUnavailableReason unavailableReasonKind =
      DiagnosticUnavailableReason.notReported,
}) {
  return value == null
      ? DiagnosticValue<T>.unavailable(
          unavailableReason: unavailableReason,
          source: source,
          unavailableReasonKind: unavailableReasonKind,
        )
      : DiagnosticValue<T>.available(value, source: source);
}

DiagnosticValue<String> _stringDiagnostic(
  dynamic raw,
  String source,
  String unavailableReason, {
  bool rejectUnknown = false,
  DiagnosticUnavailableReason unavailableReasonKind =
      DiagnosticUnavailableReason.notReported,
}) {
  final value = _cleanString(raw);
  final normalized = value?.toUpperCase();
  final unavailable =
      value == null ||
      const {
        'N/A',
        'NA',
        'NOT AVAILABLE',
        'UNAVAILABLE',
      }.contains(normalized) ||
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
          unavailableReasonKind: unavailableReasonKind,
        )
      : DiagnosticValue<String>.available(value, source: source);
}

DiagnosticValue<int> _intDiagnostic(
  dynamic raw,
  String source,
  String unavailableReason, {
  DiagnosticUnavailableReason unavailableReasonKind =
      DiagnosticUnavailableReason.notReported,
}) {
  return _diagnosticFromNullable(
    _intFrom(raw),
    source: source,
    unavailableReason: unavailableReason,
    unavailableReasonKind: unavailableReasonKind,
  );
}

DiagnosticValue<BigInt> _bigIntDiagnostic(
  dynamic raw,
  String source,
  String unavailableReason, {
  DiagnosticUnavailableReason unavailableReasonKind =
      DiagnosticUnavailableReason.notReported,
}) {
  return _diagnosticFromNullable(
    _bigIntFrom(raw),
    source: source,
    unavailableReason: unavailableReason,
    unavailableReasonKind: unavailableReasonKind,
  );
}

DiagnosticValue<bool> _boolDiagnostic(
  dynamic raw,
  String source,
  String unavailableReason, {
  DiagnosticUnavailableReason unavailableReasonKind =
      DiagnosticUnavailableReason.notReported,
}) {
  return _diagnosticFromNullable(
    _boolFrom(raw),
    source: source,
    unavailableReason: unavailableReason,
    unavailableReasonKind: unavailableReasonKind,
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

bool? _boolFrom(dynamic raw) {
  if (raw is bool) return raw;
  final normalized = raw?.toString().trim().toLowerCase();
  return switch (normalized) {
    'true' || '1' => true,
    'false' || '0' => false,
    _ => null,
  };
}

DiagnosticUnavailableReason _unavailabilityKindForTechnicalReason(
  String? reason, {
  String? reasonCode,
  int? windowsError,
  required DiagnosticUnavailableReason fallback,
}) {
  final normalizedCode = _normalizeTechnicalReasonCode(reasonCode);
  final normalized = reason?.toLowerCase() ?? '';
  if (const {
    'administrator_required',
    'administrative_privileges_required',
    'elevation_required',
    'elevated_access_required',
    'privilege_not_held',
    'requires_administrator',
  }.contains(normalizedCode)) {
    return DiagnosticUnavailableReason.administratorRequired;
  }
  if (const {
    'access_denied',
    'permission_denied',
    'query_access_denied',
  }.contains(normalizedCode)) {
    return DiagnosticUnavailableReason.permissionDenied;
  }
  if (const {
    'usb_bridge_unsupported',
    'usb_bridge_not_supported',
    'scsi_bridge_unsupported',
    'sat_unsupported',
    'sat_pass_through_unsupported',
  }.contains(normalizedCode)) {
    return DiagnosticUnavailableReason.usbBridgeUnsupported;
  }
  if (const {
    'protocol_response_invalid',
    'invalid_protocol_response',
    'malformed_protocol_response',
    'invalid_response',
    'malformed_response',
    'invalid_data',
  }.contains(normalizedCode)) {
    return DiagnosticUnavailableReason.protocolResponseInvalid;
  }

  // Win32 error codes are intentionally handled before English text so a new
  // native helper can retain diagnostics without coupling the UI to wording.
  switch (windowsError) {
    case 740: // ERROR_ELEVATION_REQUIRED
    case 1314: // ERROR_PRIVILEGE_NOT_HELD
      return DiagnosticUnavailableReason.administratorRequired;
    case 5: // ERROR_ACCESS_DENIED
      return DiagnosticUnavailableReason.permissionDenied;
    case 13: // ERROR_INVALID_DATA
      return DiagnosticUnavailableReason.protocolResponseInvalid;
  }

  if (normalized.contains('administrator') ||
      normalized.contains('elevat') ||
      normalized.contains('privilege') ||
      normalized.contains('requires admin')) {
    return DiagnosticUnavailableReason.administratorRequired;
  }
  if (normalized.contains('access denied') ||
      normalized.contains('permission denied') ||
      normalized.contains('access is denied') ||
      normalized.contains('denied by policy')) {
    return DiagnosticUnavailableReason.permissionDenied;
  }
  if ((normalized.contains('usb') || normalized.contains('scsi')) &&
      normalized.contains('bridge') &&
      (normalized.contains('smart') ||
          normalized.contains('sat') ||
          normalized.contains('pass-through'))) {
    return DiagnosticUnavailableReason.usbBridgeUnsupported;
  }
  if (normalized.contains('invalid reliability counter') ||
      normalized.contains('invalid protocol') ||
      normalized.contains('invalid response') ||
      normalized.contains('malformed response') ||
      normalized.contains('invalid data') ||
      normalized.contains('invalid metadata')) {
    return DiagnosticUnavailableReason.protocolResponseInvalid;
  }
  if (normalized.contains('not applicable') ||
      normalized.contains('not an nvme') ||
      normalized.contains('not a sata') ||
      normalized.contains('this storage bus') ||
      normalized.contains('not supported by this device type')) {
    return DiagnosticUnavailableReason.notApplicable;
  }
  if (normalized.contains('could not') ||
      normalized.contains('failed') ||
      normalized.contains('timed out') ||
      normalized.contains('error')) {
    return DiagnosticUnavailableReason.queryFailed;
  }
  if (normalized.contains('did not expose') ||
      normalized.contains('does not expose') ||
      normalized.contains('not expose') ||
      normalized.contains('not support') ||
      normalized.contains('denied')) {
    return DiagnosticUnavailableReason.notExposedByDeviceOrDriver;
  }
  return fallback;
}

String? _normalizeTechnicalReasonCode(String? code) {
  final value = _cleanString(code);
  if (value == null) return null;
  return value
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
      .replaceAll(RegExp(r'^_+|_+$'), '');
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
  final String source;
  final String unavailableReason;
  final DiagnosticUnavailableReason unavailableReasonKind;

  const _NvmeHealthData({
    required this.temperatureCelsius,
    required this.percentageUsed,
    required this.hostReadBytes,
    required this.hostWrittenBytes,
    required this.hostReadCommands,
    required this.hostWriteCommands,
    required this.powerOnHours,
    required this.mediaAndDataIntegrityErrors,
    required this.source,
  }) : unavailableReason =
           'The device or storage driver did not expose this NVMe value.',
       unavailableReasonKind =
           DiagnosticUnavailableReason.notExposedByDeviceOrDriver;

  const _NvmeHealthData.unavailable(
    this.unavailableReason, {
    this.source = 'Windows NVMe protocol query',
    this.unavailableReasonKind =
        DiagnosticUnavailableReason.notExposedByDeviceOrDriver,
  }) : temperatureCelsius = null,
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
      final reason =
          _cleanString(map['reason']) ??
          'The device or storage driver did not expose NVMe health data.';
      final reasonCode = _cleanString(map['reasonCode']);
      final windowsError = _intFrom(map['windowsError']);
      return _NvmeHealthData.unavailable(
        reason,
        source: _cleanString(map['source']) ?? 'Windows NVMe protocol query',
        unavailableReasonKind: _unavailabilityKindForTechnicalReason(
          reason,
          reasonCode: reasonCode,
          windowsError: windowsError,
          fallback: DiagnosticUnavailableReason.notExposedByDeviceOrDriver,
        ),
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
      source: _cleanString(map['source']) ?? 'Windows NVMe protocol query',
    );
  }
}

class _AtaSmartData {
  final bool isAvailable;
  final bool wasReported;
  final int? temperatureCelsius;
  final int? wearPercent;
  final BigInt? powerOnHours;
  final String source;
  final String unavailableReason;
  final DiagnosticUnavailableReason unavailableReasonKind;

  const _AtaSmartData.available({
    required this.source,
    required this.temperatureCelsius,
    required this.wearPercent,
    required this.powerOnHours,
  }) : isAvailable = true,
       wasReported = true,
       unavailableReason = 'The ATA SMART response did not include this value.',
       unavailableReasonKind = DiagnosticUnavailableReason.notReported;

  const _AtaSmartData.unavailable(
    this.unavailableReason, {
    required this.wasReported,
    this.source = 'ATA SMART / SAT pass-through',
    this.unavailableReasonKind =
        DiagnosticUnavailableReason.notExposedByDeviceOrDriver,
  }) : isAvailable = false,
       temperatureCelsius = null,
       wearPercent = null,
       powerOnHours = null;

  String get missingValueReason {
    return isAvailable
        ? 'The ATA SMART response did not include this value.'
        : unavailableReason;
  }

  DiagnosticUnavailableReason get missingValueReasonKind {
    return isAvailable
        ? DiagnosticUnavailableReason.notReported
        : unavailableReasonKind;
  }

  factory _AtaSmartData.fromJson(dynamic raw) {
    if (raw is! Map) {
      return const _AtaSmartData.unavailable(
        'The native helper did not return an ATA SMART response.',
        wasReported: false,
      );
    }
    final map = Map<String, dynamic>.from(raw);
    final source =
        _cleanString(map['source']) ?? 'ATA SMART / SAT pass-through';
    if (map['available'] == true) {
      return _AtaSmartData.available(
        source: source,
        temperatureCelsius: _intFrom(map['temperatureCelsius']),
        wearPercent: _intFrom(map['wearPercent']),
        powerOnHours: _bigIntFrom(map['powerOnHours']),
      );
    }
    final reason =
        _cleanString(map['reason']) ??
        'The device or storage driver did not expose ATA SMART data.';
    final reasonCode = _cleanString(map['reasonCode']);
    final windowsError = _intFrom(map['windowsError']);
    return _AtaSmartData.unavailable(
      reason,
      wasReported: true,
      source: source,
      unavailableReasonKind: _unavailabilityKindForTechnicalReason(
        reason,
        reasonCode: reasonCode,
        windowsError: windowsError,
        fallback: DiagnosticUnavailableReason.notExposedByDeviceOrDriver,
      ),
    );
  }
}

class _SmartMetricFallback {
  final int? temperatureCelsius;
  final int? percentageUsed;
  final BigInt? hostReadBytes;
  final BigInt? hostWrittenBytes;
  final BigInt? hostReadCommands;
  final BigInt? hostWriteCommands;
  final BigInt? powerOnHours;
  final BigInt? mediaAndDataIntegrityErrors;
  final String source;
  final String unavailableReason;
  final DiagnosticUnavailableReason unavailableReasonKind;

  const _SmartMetricFallback({
    required this.temperatureCelsius,
    required this.percentageUsed,
    required this.hostReadBytes,
    required this.hostWrittenBytes,
    required this.hostReadCommands,
    required this.hostWriteCommands,
    required this.powerOnHours,
    required this.mediaAndDataIntegrityErrors,
    required this.source,
    required this.unavailableReason,
    required this.unavailableReasonKind,
  });

  factory _SmartMetricFallback.forDisk({
    required DiagnosticValue<String> busType,
    required _NvmeHealthData nvme,
    required _AtaSmartData ataSmart,
    required String reliabilityReason,
    required DiagnosticUnavailableReason reliabilityUnavailableReasonKind,
  }) {
    final bus = busType.value?.toUpperCase();
    if (bus == 'NVME' || bus == 'RAID') {
      return _SmartMetricFallback(
        temperatureCelsius: nvme.temperatureCelsius,
        percentageUsed: nvme.percentageUsed,
        hostReadBytes: nvme.hostReadBytes,
        hostWrittenBytes: nvme.hostWrittenBytes,
        hostReadCommands: nvme.hostReadCommands,
        hostWriteCommands: nvme.hostWriteCommands,
        powerOnHours: nvme.powerOnHours,
        mediaAndDataIntegrityErrors: nvme.mediaAndDataIntegrityErrors,
        source: nvme.source,
        unavailableReason: nvme.unavailableReason,
        unavailableReasonKind: nvme.unavailableReasonKind,
      );
    }
    if (ataSmart.wasReported) {
      return _SmartMetricFallback(
        temperatureCelsius: ataSmart.temperatureCelsius,
        percentageUsed: ataSmart.wearPercent,
        hostReadBytes: null,
        hostWrittenBytes: null,
        hostReadCommands: null,
        hostWriteCommands: null,
        powerOnHours: ataSmart.powerOnHours,
        mediaAndDataIntegrityErrors: null,
        source: ataSmart.source,
        unavailableReason: ataSmart.missingValueReason,
        unavailableReasonKind: ataSmart.missingValueReasonKind,
      );
    }
    return _SmartMetricFallback(
      temperatureCelsius: null,
      percentageUsed: null,
      hostReadBytes: null,
      hostWrittenBytes: null,
      hostReadCommands: null,
      hostWriteCommands: null,
      powerOnHours: null,
      mediaAndDataIntegrityErrors: null,
      source: WindowsDiskDiagnosticsService._reliabilitySource,
      unavailableReason: reliabilityReason,
      unavailableReasonKind: reliabilityUnavailableReasonKind,
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
