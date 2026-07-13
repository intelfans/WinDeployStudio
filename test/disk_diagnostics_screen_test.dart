import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:win_deploy_studio/core/localization/strings.dart';
import 'package:win_deploy_studio/features/disk_tools/models/disk_diagnostic_models.dart';
import 'package:win_deploy_studio/features/disk_tools/screens/disk_diagnostics_screen.dart';
import 'package:win_deploy_studio/features/disk_tools/services/secure_powershell_runner.dart';
import 'package:win_deploy_studio/features/disk_tools/services/windows_disk_diagnostics_service.dart';

void main() {
  testWidgets('shows localized reasons for unavailable values and flags', (
    tester,
  ) async {
    const rawDriverReason =
        'The USB bridge did not expose ATA SMART data through SAT pass-through.';
    final snapshot = DiskDiagnosticsSnapshot(
      reports: [_report(rawDriverReason)],
      isAdministrator: true,
      collectedAt: DateTime.utc(2026, 7, 13),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          windowsDiskDiagnosticsServiceProvider.overrideWithValue(
            _StaticDiagnosticsService(snapshot),
          ),
        ],
        child: MaterialApp(
          locale: const Locale('en'),
          supportedLocales: const [Locale('en')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          home: const DiskDiagnosticsScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.text(trByCode('en', 'disk_diag_unavailable_driver')),
      findsWidgets,
    );
    expect(find.text(rawDriverReason), findsNothing);
    expect(find.text(trByCode('en', 'disk_diag_boot_disk')), findsOneWidget);
    expect(find.text(trByCode('en', 'disk_diag_offline')), findsOneWidget);
    expect(find.text(trByCode('en', 'disk_tools_value_unknown')), findsWidgets);
    expect(find.text(trByCode('en', 'disk_tools_no')), findsNothing);
  });

  testWidgets('shows a bridge-specific localized explanation', (tester) async {
    const rawBridgeReason =
        'The USB or SCSI bridge did not expose ATA SMART data through SAT pass-through.';
    final snapshot = DiskDiagnosticsSnapshot(
      reports: [
        _report(
          rawBridgeReason,
          unavailableReasonKind:
              DiagnosticUnavailableReason.usbBridgeUnsupported,
        ),
      ],
      isAdministrator: true,
      collectedAt: DateTime.utc(2026, 7, 13),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          windowsDiskDiagnosticsServiceProvider.overrideWithValue(
            _StaticDiagnosticsService(snapshot),
          ),
        ],
        child: MaterialApp(
          locale: const Locale('en'),
          supportedLocales: const [Locale('en')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          home: const DiskDiagnosticsScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.text(trByCode('en', 'disk_diag_unavailable_usb_bridge')),
      findsWidgets,
    );
    expect(find.text(rawBridgeReason), findsNothing);
  });
}

class _StaticDiagnosticsService extends WindowsDiskDiagnosticsService {
  final DiskDiagnosticsSnapshot snapshot;

  _StaticDiagnosticsService(this.snapshot) : super(helperPath: () => '');

  @override
  Future<DiskDiagnosticsSnapshot> collect({
    DiskToolsCancellationToken? cancellationToken,
  }) async {
    return snapshot;
  }
}

DiskDiagnosticReport _report(
  String rawDriverReason, {
  DiagnosticUnavailableReason unavailableReasonKind =
      DiagnosticUnavailableReason.notExposedByDeviceOrDriver,
}) {
  final unavailableString = DiagnosticValue<String>.unavailable(
    unavailableReason: rawDriverReason,
    unavailableReasonKind: unavailableReasonKind,
  );
  final unavailableInt = DiagnosticValue<int>.unavailable(
    unavailableReason: rawDriverReason,
    unavailableReasonKind: unavailableReasonKind,
  );
  final unavailableBigInt = DiagnosticValue<BigInt>.unavailable(
    unavailableReason: rawDriverReason,
    unavailableReasonKind: unavailableReasonKind,
  );
  final unavailableFlag = DiagnosticValue<bool>.unavailable(
    unavailableReason: 'Windows did not report this state.',
    unavailableReasonKind: DiagnosticUnavailableReason.notReported,
  );
  return DiskDiagnosticReport(
    diskNumber: 2,
    model: const DiagnosticValue.available('USB SSD', source: 'Windows'),
    sizeBytes: DiagnosticValue.available(BigInt.from(1000), source: 'Windows'),
    serialNumber: unavailableString,
    uniqueId: unavailableString,
    busType: const DiagnosticValue.available('USB', source: 'Windows'),
    vendorId: unavailableString,
    productId: unavailableString,
    health: unavailableString,
    temperatureCelsius: unavailableInt,
    wearPercent: unavailableInt,
    estimatedRemainingLifePercent: unavailableInt,
    readErrorsCorrected: unavailableBigInt,
    readErrorsUncorrected: unavailableBigInt,
    readErrorsTotal: unavailableBigInt,
    writeErrorsCorrected: unavailableBigInt,
    writeErrorsUncorrected: unavailableBigInt,
    writeErrorsTotal: unavailableBigInt,
    powerOnHours: unavailableBigInt,
    hostReadBytes: unavailableBigInt,
    hostWrittenBytes: unavailableBigInt,
    hostReadCommands: unavailableBigInt,
    hostWriteCommands: unavailableBigInt,
    mediaAndDataIntegrityErrors: unavailableBigInt,
    firmwareVersion: unavailableString,
    mediaType: unavailableString,
    partitionStyle: unavailableString,
    operationalStatus: unavailableString,
    pnpDeviceId: unavailableString,
    devicePath: const DiagnosticValue.available(
      r'\\.\PhysicalDrive2',
      source: 'Windows',
    ),
    driveLetters: const [],
    isSystem: unavailableFlag,
    isBoot: unavailableFlag,
    isOffline: unavailableFlag,
    isReadOnly: unavailableFlag,
    isRemovable: unavailableFlag,
  );
}
