import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:win_deploy_studio/features/disk_tools/services/secure_powershell_runner.dart';
import 'package:win_deploy_studio/features/disk_tools/services/windows_boot_repair_service.dart';

void main() {
  test(
    'rollback restores and hash-verifies an existing BCD backup',
    () async {
      final fixture = await _RollbackFixture.create();
      try {
        await fixture.backupFile.writeAsString('original BCD');
        await File(
          '${fixture.backupFile.path}.LOG1',
        ).writeAsString('original log');
        await fixture.storeFile.writeAsString('mutated BCD');
        await File('${fixture.storeFile.path}.LOG').writeAsString('new log');
        await File('${fixture.storeFile.path}.LOG2').writeAsString('new log 2');

        final result = await fixture.run(hadExistingStore: true);

        expect(result['rollbackAttempted'], isTrue);
        expect(result['rollbackSucceeded'], isTrue, reason: '$result');
        expect(result['storeExists'], isTrue);
        expect(result['storeContent'], 'original BCD');
        expect(
          await File('${fixture.storeFile.path}.LOG1').readAsString(),
          'original log',
        );
        expect(await File('${fixture.storeFile.path}.LOG').exists(), isFalse);
        expect(await File('${fixture.storeFile.path}.LOG2').exists(), isFalse);
      } finally {
        await fixture.dispose();
      }
    },
    skip: !Platform.isWindows,
  );

  test(
    'rollback removes BCD files when no store existed before repair',
    () async {
      final fixture = await _RollbackFixture.create();
      try {
        await fixture.storeFile.writeAsString('new BCD');
        await File('${fixture.storeFile.path}.LOG1').writeAsString('new log');

        final result = await fixture.run(hadExistingStore: false);

        expect(result['rollbackAttempted'], isTrue);
        expect(result['rollbackSucceeded'], isTrue);
        expect(result['storeExists'], isFalse);
        expect(await File('${fixture.storeFile.path}.LOG1').exists(), isFalse);
      } finally {
        await fixture.dispose();
      }
    },
    skip: !Platform.isWindows,
  );

  test(
    'rollback does not delete the current store when its backup is missing',
    () async {
      final fixture = await _RollbackFixture.create();
      try {
        await fixture.storeFile.writeAsString('current BCD');

        final result = await fixture.run(hadExistingStore: true);

        expect(result['rollbackAttempted'], isTrue);
        expect(result['rollbackSucceeded'], isFalse);
        expect(result['rollbackError'], contains('backup is missing'));
        expect(result['storeContent'], 'current BCD');
      } finally {
        await fixture.dispose();
      }
    },
    skip: !Platform.isWindows,
  );
}

class _RollbackFixture {
  final Directory root;
  final Directory backupDirectory;
  final File storeFile;
  final File backupFile;

  const _RollbackFixture({
    required this.root,
    required this.backupDirectory,
    required this.storeFile,
    required this.backupFile,
  });

  static Future<_RollbackFixture> create() async {
    final root = await Directory.systemTemp.createTemp('wds_rollback_test_');
    final storeDirectory = Directory('${root.path}\\target\\Boot');
    final backupDirectory = Directory('${root.path}\\backup');
    await storeDirectory.create(recursive: true);
    await backupDirectory.create(recursive: true);
    return _RollbackFixture(
      root: root,
      backupDirectory: backupDirectory,
      storeFile: File('${storeDirectory.path}\\BCD'),
      backupFile: File('${backupDirectory.path}\\BCD'),
    );
  }

  Future<Map<String, dynamic>> run({required bool hadExistingStore}) async {
    final workspace = await DiskToolsPowerShellWorkspace.create(
      'wds_rollback_result',
    );
    final script =
        r'''
$ErrorActionPreference = 'Stop'
$technicalLog = New-Object Collections.Generic.List[string]
$rollbackAttempted = $false
$rollbackSucceeded = $false
$rollbackError = ''
function Add-Log([string]$message) { $technicalLog.Add($message) }
''' +
        WindowsBootRepairService.bcdRollbackFunctionForTesting +
        r'''
Restore-BcdBackup `
  $env:WDS_TEST_STORE `
  $env:WDS_TEST_BACKUP `
  ([bool]::Parse($env:WDS_TEST_HAD_EXISTING))
$storeExists = Test-Path -LiteralPath $env:WDS_TEST_STORE -PathType Leaf
$storeContent = if ($storeExists) {
  [IO.File]::ReadAllText($env:WDS_TEST_STORE)
} else {
  $null
}
$payload = [PSCustomObject]@{
  rollbackAttempted = $rollbackAttempted
  rollbackSucceeded = $rollbackSucceeded
  rollbackError = $rollbackError
  storeExists = $storeExists
  storeContent = $storeContent
  log = @($technicalLog)
}
[IO.File]::WriteAllText(
  $env:WDS_TEST_OUTPUT,
  ($payload | ConvertTo-Json -Depth 4 -Compress),
  (New-Object Text.UTF8Encoding($false))
)
''';

    try {
      final result = await SecurePowerShellRunner().run(
        script: script,
        variables: {
          'WDS_TEST_STORE': storeFile.path,
          'WDS_TEST_BACKUP': backupDirectory.path,
          'WDS_TEST_HAD_EXISTING': '$hadExistingStore',
          'WDS_TEST_OUTPUT': workspace.outputFile.path,
        },
        timeout: const Duration(seconds: 20),
        cancelPath: workspace.cancelFile.path,
      );
      expect(result.exitCode, 0, reason: result.stderr);
      expect(
        await workspace.outputFile.exists(),
        isTrue,
        reason: result.stderr,
      );
      final decoded = jsonDecode(await workspace.outputFile.readAsString());
      return Map<String, dynamic>.from(decoded as Map);
    } finally {
      await workspace.dispose();
    }
  }

  Future<void> dispose() async {
    if (await root.exists()) await root.delete(recursive: true);
  }
}
