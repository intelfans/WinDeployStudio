enum DiagnosticUnavailableReason {
  notReported,
  notExposedByDeviceOrDriver,
  notApplicable,
  queryFailed,
  administratorRequired,
  permissionDenied,
  usbBridgeUnsupported,
  protocolResponseInvalid,
}

extension DiagnosticUnavailableReasonLocalization
    on DiagnosticUnavailableReason {
  String get localizationKey {
    return switch (this) {
      DiagnosticUnavailableReason.notReported =>
        'disk_diag_unavailable_not_reported',
      DiagnosticUnavailableReason.notExposedByDeviceOrDriver =>
        'disk_diag_unavailable_driver',
      DiagnosticUnavailableReason.notApplicable =>
        'disk_diag_unavailable_not_applicable',
      DiagnosticUnavailableReason.queryFailed =>
        'disk_diag_unavailable_query_failed',
      DiagnosticUnavailableReason.administratorRequired =>
        'disk_diag_unavailable_admin_required',
      DiagnosticUnavailableReason.permissionDenied =>
        'disk_diag_unavailable_permission_denied',
      DiagnosticUnavailableReason.usbBridgeUnsupported =>
        'disk_diag_unavailable_usb_bridge',
      DiagnosticUnavailableReason.protocolResponseInvalid =>
        'disk_diag_unavailable_protocol_invalid',
    };
  }
}

class DiagnosticValue<T> {
  final T? value;
  final String source;

  /// Technical detail retained for copied reports, never rendered directly in
  /// the localized interface.
  final String? unavailableReason;
  final DiagnosticUnavailableReason? unavailableReasonKind;

  const DiagnosticValue.available(this.value, {required this.source})
    : unavailableReason = null,
      unavailableReasonKind = null;

  const DiagnosticValue.unavailable({
    required this.unavailableReason,
    this.unavailableReasonKind = DiagnosticUnavailableReason.notReported,
    this.source = 'Windows did not expose this value',
  }) : value = null;

  bool get isAvailable => value != null;
}

class DiskDiagnosticsSnapshot {
  final List<DiskDiagnosticReport> reports;
  final bool isAdministrator;
  final DateTime collectedAt;
  final List<String> collectionWarnings;

  const DiskDiagnosticsSnapshot({
    required this.reports,
    required this.isAdministrator,
    required this.collectedAt,
    this.collectionWarnings = const [],
  });
}

class DiskDiagnosticReport {
  final int diskNumber;
  final DiagnosticValue<String> model;
  final DiagnosticValue<BigInt> sizeBytes;
  final DiagnosticValue<String> serialNumber;
  final DiagnosticValue<String> uniqueId;
  final DiagnosticValue<String> busType;
  final DiagnosticValue<String> vendorId;
  final DiagnosticValue<String> productId;
  final DiagnosticValue<String> health;
  final DiagnosticValue<int> temperatureCelsius;
  final DiagnosticValue<int> wearPercent;
  final DiagnosticValue<int> estimatedRemainingLifePercent;
  final DiagnosticValue<BigInt> readErrorsCorrected;
  final DiagnosticValue<BigInt> readErrorsUncorrected;
  final DiagnosticValue<BigInt> readErrorsTotal;
  final DiagnosticValue<BigInt> writeErrorsCorrected;
  final DiagnosticValue<BigInt> writeErrorsUncorrected;
  final DiagnosticValue<BigInt> writeErrorsTotal;
  final DiagnosticValue<BigInt> powerOnHours;
  final DiagnosticValue<BigInt> hostReadBytes;
  final DiagnosticValue<BigInt> hostWrittenBytes;
  final DiagnosticValue<BigInt> hostReadCommands;
  final DiagnosticValue<BigInt> hostWriteCommands;
  final DiagnosticValue<BigInt> mediaAndDataIntegrityErrors;
  final DiagnosticValue<String> firmwareVersion;
  final DiagnosticValue<String> mediaType;
  final DiagnosticValue<String> partitionStyle;
  final DiagnosticValue<String> operationalStatus;
  final DiagnosticValue<String> pnpDeviceId;
  final DiagnosticValue<String> devicePath;
  final List<String> driveLetters;
  final DiagnosticValue<bool> isSystem;
  final DiagnosticValue<bool> isBoot;
  final DiagnosticValue<bool> isOffline;
  final DiagnosticValue<bool> isReadOnly;
  final DiagnosticValue<bool> isRemovable;

  const DiskDiagnosticReport({
    required this.diskNumber,
    required this.model,
    required this.sizeBytes,
    required this.serialNumber,
    required this.uniqueId,
    required this.busType,
    required this.vendorId,
    required this.productId,
    required this.health,
    required this.temperatureCelsius,
    required this.wearPercent,
    required this.estimatedRemainingLifePercent,
    required this.readErrorsCorrected,
    required this.readErrorsUncorrected,
    required this.readErrorsTotal,
    required this.writeErrorsCorrected,
    required this.writeErrorsUncorrected,
    required this.writeErrorsTotal,
    required this.powerOnHours,
    required this.hostReadBytes,
    required this.hostWrittenBytes,
    required this.hostReadCommands,
    required this.hostWriteCommands,
    required this.mediaAndDataIntegrityErrors,
    required this.firmwareVersion,
    required this.mediaType,
    required this.partitionStyle,
    required this.operationalStatus,
    required this.pnpDeviceId,
    required this.devicePath,
    required this.driveLetters,
    required this.isSystem,
    required this.isBoot,
    required this.isOffline,
    required this.isReadOnly,
    required this.isRemovable,
  });

  String get displayName => model.value ?? 'Physical disk $diskNumber';

  bool get isExternal {
    final bus = busType.value?.toUpperCase();
    return isRemovable.value == true ||
        bus == 'USB' ||
        bus == 'SD' ||
        bus == 'MMC';
  }

  bool get isSystemDisk => isSystem.value == true;

  bool get isBootDisk => isBoot.value == true;

  bool get hasKnownConnectionClassification {
    final bus = busType.value?.toUpperCase();
    return isRemovable.value == true ||
        const {
          'USB',
          'SD',
          'MMC',
          'SATA',
          'NVME',
          'ATA',
          'SAS',
          'RAID',
        }.contains(bus);
  }

  String toPlainText() {
    final lines = <String>[
      'Disk $diskNumber - $displayName',
      'Collected from native Windows storage APIs',
      '',
    ];

    void add<T>(
      String label,
      DiagnosticValue<T> field,
      String Function(T) fmt,
    ) {
      final value = field.value;
      if (value == null) {
        lines.add('$label: Unavailable (${field.unavailableReason})');
      } else {
        lines.add('$label: ${fmt(value)} [${field.source}]');
      }
    }

    add('Model', model, (value) => value);
    add('Capacity', sizeBytes, formatDiagnosticBytes);
    add('Serial number', serialNumber, (value) => value);
    add('Unique ID', uniqueId, (value) => value);
    add('Bus', busType, (value) => value);
    add('VID', vendorId, (value) => value);
    add('PID', productId, (value) => value);
    add('Health', health, (value) => value);
    add('Temperature', temperatureCelsius, (value) => '$value C');
    add(
      'Estimated remaining life',
      estimatedRemainingLifePercent,
      (value) => '$value%',
    );
    add('Wear used', wearPercent, (value) => '$value%');
    add('Read errors corrected', readErrorsCorrected, formatDiagnosticInteger);
    add(
      'Read errors uncorrected',
      readErrorsUncorrected,
      formatDiagnosticInteger,
    );
    add('Read errors total', readErrorsTotal, formatDiagnosticInteger);
    add(
      'Write errors corrected',
      writeErrorsCorrected,
      formatDiagnosticInteger,
    );
    add(
      'Write errors uncorrected',
      writeErrorsUncorrected,
      formatDiagnosticInteger,
    );
    add('Write errors total', writeErrorsTotal, formatDiagnosticInteger);
    add('Power-on time', powerOnHours, formatDiagnosticHours);
    add('Lifetime host reads', hostReadBytes, formatDiagnosticBytes);
    add('Lifetime host writes', hostWrittenBytes, formatDiagnosticBytes);
    add('Host read commands', hostReadCommands, formatDiagnosticInteger);
    add('Host write commands', hostWriteCommands, formatDiagnosticInteger);
    add(
      'Media/data integrity errors',
      mediaAndDataIntegrityErrors,
      formatDiagnosticInteger,
    );
    add('Firmware', firmwareVersion, (value) => value);
    add('Media type', mediaType, (value) => value);
    add('Partition style', partitionStyle, (value) => value);
    add('Operational status', operationalStatus, (value) => value);
    add('PnP device ID', pnpDeviceId, (value) => value);
    add('Device path', devicePath, (value) => value);
    lines.add('System disk: ${_formatDiagnosticFlag(isSystem)}');
    lines.add('Boot disk: ${_formatDiagnosticFlag(isBoot)}');
    lines.add('Offline: ${_formatDiagnosticFlag(isOffline)}');
    lines.add('Read-only: ${_formatDiagnosticFlag(isReadOnly)}');
    lines.add('Removable: ${_formatDiagnosticFlag(isRemovable)}');
    lines.add(
      'Mounted volumes: ${driveLetters.isEmpty ? 'None' : driveLetters.join(', ')}',
    );
    return lines.join('\n');
  }
}

String _formatDiagnosticFlag(DiagnosticValue<bool> field) {
  final value = field.value;
  if (value == null) {
    return 'Unknown (${field.unavailableReason ?? 'not reported'})';
  }
  return '${value ? 'Yes' : 'No'} [${field.source}]';
}

String formatDiagnosticInteger(BigInt value) {
  final text = value.toString();
  final output = StringBuffer();
  for (var index = 0; index < text.length; index++) {
    if (index > 0 && (text.length - index) % 3 == 0) output.write(',');
    output.write(text[index]);
  }
  return output.toString();
}

String formatDiagnosticBytes(BigInt bytes) {
  const names = ['B', 'KiB', 'MiB', 'GiB', 'TiB', 'PiB', 'EiB'];
  final base = BigInt.from(1024);
  var divisor = BigInt.one;
  var unit = 0;
  while (unit < names.length - 1 && bytes >= divisor * base) {
    divisor *= base;
    unit++;
  }
  if (unit == 0) return '${formatDiagnosticInteger(bytes)} B';
  final whole = bytes ~/ divisor;
  final decimal = ((bytes.remainder(divisor) * BigInt.from(10)) ~/ divisor)
      .toInt();
  return '$whole.$decimal ${names[unit]} (${formatDiagnosticInteger(bytes)} B)';
}

String formatDiagnosticHours(BigInt hours) {
  final days = hours ~/ BigInt.from(24);
  return '${formatDiagnosticInteger(hours)} h '
      '(${formatDiagnosticInteger(days)} d)';
}
