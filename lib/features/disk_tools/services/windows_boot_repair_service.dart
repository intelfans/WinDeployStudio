import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../../core/constants/app_constants.dart';
import '../../../core/services/disk_safety_service.dart';
import '../models/boot_repair_models.dart';
import 'secure_powershell_runner.dart';

final windowsBootRepairServiceProvider = Provider<WindowsBootRepairService>((
  ref,
) {
  return WindowsBootRepairService();
});

class BootRepairException implements Exception {
  final String messageKey;
  final String technicalDetail;

  const BootRepairException(this.messageKey, [this.technicalDetail = '']);

  @override
  String toString() => technicalDetail.isEmpty ? messageKey : technicalDetail;
}

class WindowsBootRepairService {
  final SecurePowerShellRunner _powerShellRunner;

  WindowsBootRepairService({SecurePowerShellRunner? powerShellRunner})
    : _powerShellRunner = powerShellRunner ?? SecurePowerShellRunner();

  Future<List<ExternalWindowsVolume>> discoverWindowsVolumes({
    DiskToolsCancellationToken? cancellationToken,
  }) async {
    if (!Platform.isWindows) {
      throw const BootRepairException('disk_tools_error_windows_only');
    }
    final response = await _runScript(
      script: _discoveryScript,
      timeout: const Duration(seconds: 30),
      cancellationToken: cancellationToken,
    );
    if (response['ok'] != true) {
      throw BootRepairException(
        'boot_repair_error_discovery',
        response['technicalError']?.toString() ?? '',
      );
    }

    final rawVolumes = response['windowsVolumes'];
    if (rawVolumes is! List) return const [];
    return rawVolumes
        .whereType<Map>()
        .map((raw) => _parseWindowsVolume(Map<String, dynamic>.from(raw)))
        .toList(growable: false);
  }

  Future<BootRepairPreflight> preflight(
    BootRepairSelection selection, {
    DiskToolsCancellationToken? cancellationToken,
  }) async {
    final response = await _runOperation(
      mode: 'preflight',
      selection: selection,
      timeout: const Duration(seconds: 30),
      cancellationToken: cancellationToken,
    );
    final checks = _parseChecks(response['checks']);
    return BootRepairPreflight(
      selection: selection,
      checks: checks,
      warnings: _stringList(response['warningKeys']),
      plannedActions: _stringList(response['plannedActionKeys']),
      commandPreview:
          'bcdboot <selected Windows volume>\\Windows /s '
          '<selected boot volume> /f ${selection.firmware.commandValue} /v',
      completedAt: DateTime.now(),
    );
  }

  Future<BootRepairResult> execute(
    BootRepairPreflight preflight, {
    DiskToolsCancellationToken? cancellationToken,
  }) async {
    if (!preflight.canExecute) {
      throw const BootRepairException('boot_repair_error_preflight_failed');
    }

    final diskNumber =
        preflight.selection.windowsVolume.disk.snapshotDiskNumber;
    final operationLock = await DiskOperationLock.tryAcquire(diskNumber);
    if (operationLock == null) {
      throw const BootRepairException('boot_repair_error_disk_busy');
    }

    final timestamp = DateTime.now()
        .toIso8601String()
        .replaceAll(':', '-')
        .replaceAll('.', '-');
    final backupDirectory = p.join(
      AppConstants.appDataPath,
      'WinDeployStudio',
      'boot_repair_backups',
      timestamp,
    );
    final logDirectory = p.join(
      AppConstants.appDataPath,
      'WinDeployStudio',
      'logs',
      'system',
    );
    final logPath = p.join(logDirectory, 'boot_repair_$timestamp.log');

    try {
      await Directory(logDirectory).create(recursive: true);
      final response = await _runOperation(
        mode: 'execute',
        selection: preflight.selection,
        backupDirectory: backupDirectory,
        logPath: logPath,
        timeout: const Duration(minutes: 3),
        cancellationToken: cancellationToken,
      );
      String logText = '';
      try {
        if (await File(logPath).exists()) {
          logText = await File(logPath).readAsString();
        }
      } catch (_) {}
      return BootRepairResult.fromResponse(
        response: response,
        defaultBackupPath: backupDirectory,
        logPath: logPath,
        logText: logText,
        completedAt: DateTime.now(),
      );
    } finally {
      await operationLock.release();
    }
  }

  Future<void> openLogFolder() async {
    final directory = p.join(
      AppConstants.appDataPath,
      'WinDeployStudio',
      'logs',
      'system',
    );
    await Directory(directory).create(recursive: true);
    await Process.run('explorer.exe', [directory]);
  }

  ExternalWindowsVolume _parseWindowsVolume(Map<String, dynamic> raw) {
    final diskRaw = Map<String, dynamic>.from(raw['disk'] as Map);
    final disk = BoundExternalDisk(
      snapshotDiskNumber: _intFrom(diskRaw['snapshotDiskNumber']) ?? -1,
      model: diskRaw['model']?.toString() ?? '',
      sizeBytes: _bigIntFrom(diskRaw['sizeBytes']) ?? BigInt.zero,
      serialNumber: diskRaw['serialNumber']?.toString() ?? '',
      uniqueId: diskRaw['uniqueId']?.toString() ?? '',
      devicePath: diskRaw['devicePath']?.toString() ?? '',
      pnpDeviceId: diskRaw['pnpDeviceId']?.toString() ?? '',
      busType: diskRaw['busType']?.toString() ?? 'Unknown',
      partitionStyle: diskRaw['partitionStyle']?.toString() ?? 'Unknown',
      identityKind: diskRaw['identityKind']?.toString() ?? '',
      identityValue: diskRaw['identityValue']?.toString() ?? '',
      isReadOnly: diskRaw['isReadOnly'] == true,
    );
    final targets = (raw['bootTargets'] as List<dynamic>? ?? const [])
        .whereType<Map>()
        .map((item) => _parseBootTarget(Map<String, dynamic>.from(item)))
        .toList(growable: false);
    return ExternalWindowsVolume(
      disk: disk,
      partitionNumber: _intFrom(raw['partitionNumber']) ?? -1,
      partitionOffset: _bigIntFrom(raw['partitionOffset']) ?? BigInt.zero,
      volumeGuidPath: raw['volumeGuidPath']?.toString() ?? '',
      driveLetter: _nullableString(raw['driveLetter']),
      fileSystem: raw['fileSystem']?.toString() ?? '',
      label: raw['label']?.toString() ?? '',
      sizeBytes: _bigIntFrom(raw['sizeBytes']) ?? BigInt.zero,
      bootTargets: targets,
    );
  }

  BootTargetVolume _parseBootTarget(Map<String, dynamic> raw) {
    return BootTargetVolume(
      diskNumber: _intFrom(raw['diskNumber']) ?? -1,
      partitionNumber: _intFrom(raw['partitionNumber']) ?? -1,
      partitionOffset: _bigIntFrom(raw['partitionOffset']) ?? BigInt.zero,
      volumeGuidPath: raw['volumeGuidPath']?.toString() ?? '',
      driveLetter: _nullableString(raw['driveLetter']),
      fileSystem: raw['fileSystem']?.toString() ?? '',
      label: raw['label']?.toString() ?? '',
      sizeBytes: _bigIntFrom(raw['sizeBytes']) ?? BigInt.zero,
      freeBytes: _bigIntFrom(raw['freeBytes']),
      gptType: raw['gptType']?.toString() ?? '',
      isActive: raw['isActive'] == true,
      supportsUefi: raw['supportsUefi'] == true,
      supportsBios: raw['supportsBios'] == true,
    );
  }

  List<BootRepairCheck> _parseChecks(dynamic raw) {
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((item) {
          return BootRepairCheck(
            labelKey:
                item['labelKey']?.toString() ?? 'boot_repair_check_unknown',
            passed: item['passed'] == true,
            detailKey:
                item['detailKey']?.toString() ??
                'boot_repair_check_detail_failed',
          );
        })
        .toList(growable: false);
  }

  Future<Map<String, dynamic>> _runOperation({
    required String mode,
    required BootRepairSelection selection,
    String backupDirectory = '',
    String logPath = '',
    required Duration timeout,
    DiskToolsCancellationToken? cancellationToken,
  }) {
    final spec = <String, dynamic>{
      ...selection.toJson(),
      'mode': mode,
      'backupDirectory': backupDirectory,
      'logPath': logPath,
    };
    return _runScript(
      script: _bootOperationScript,
      variables: {'WDS_BOOT_SPEC': jsonEncode(spec)},
      isExecution: mode == 'execute',
      timeout: timeout,
      cancellationToken: cancellationToken,
      cancellationGracePeriod: mode == 'execute'
          ? const Duration(seconds: 15)
          : const Duration(seconds: 2),
    );
  }

  Future<Map<String, dynamic>> _runScript({
    required String script,
    Map<String, String> variables = const {},
    bool isExecution = false,
    required Duration timeout,
    DiskToolsCancellationToken? cancellationToken,
    Duration cancellationGracePeriod = const Duration(seconds: 2),
  }) async {
    final workspace = await DiskToolsPowerShellWorkspace.create(
      'wds_boot_repair',
    );
    final outputFile = workspace.outputFile;

    try {
      final result = await _powerShellRunner.run(
        script: script,
        variables: {
          ...variables,
          'WDS_BOOT_OUTPUT': outputFile.path,
          'WDS_RESPONSE_NONCE': workspace.nonce,
        },
        timeout: timeout,
        cancelPath: workspace.cancelFile.path,
        cancellationToken: cancellationToken,
        cancellationGracePeriod: cancellationGracePeriod,
      );

      if (!await outputFile.exists()) {
        if (result.timedOut) {
          throw BootRepairException(
            isExecution
                ? 'boot_repair_error_execution_timeout'
                : 'boot_repair_error_preflight_timeout',
          );
        }
        throw BootRepairException(
          isExecution
              ? 'boot_repair_error_execution'
              : 'boot_repair_error_preflight',
          result.stderr,
        );
      }
      final text = (await outputFile.readAsString()).replaceFirst('\ufeff', '');
      final decoded = jsonDecode(text);
      if (decoded is! Map) {
        throw const BootRepairException('boot_repair_error_invalid_response');
      }
      final response = Map<String, dynamic>.from(decoded);
      if (response['responseNonce'] != workspace.nonce) {
        throw const BootRepairException('boot_repair_error_invalid_response');
      }
      if (result.cancelled) {
        response['ok'] = false;
        response['operationCancelled'] = true;
      }
      if (result.timedOut) {
        response['ok'] = false;
        response['operationTimedOut'] = true;
      }
      return response;
    } on FormatException catch (error) {
      throw BootRepairException(
        'boot_repair_error_invalid_response',
        error.toString(),
      );
    } finally {
      try {
        await workspace.dispose();
      } catch (_) {}
    }
  }

  static String get discoveryScriptForTesting => _discoveryScript;
  static String get bootOperationScriptForTesting => _bootOperationScript;
  static String get bcdRollbackFunctionForTesting {
    const beginMarker = '# WDS_BCD_ROLLBACK_BEGIN';
    const endMarker = '# WDS_BCD_ROLLBACK_END';
    final begin = _bootOperationScript.indexOf(beginMarker);
    final end = _bootOperationScript.indexOf(endMarker);
    if (begin < 0 || end <= begin) {
      throw StateError('BCD rollback function markers are missing.');
    }
    return _bootOperationScript.substring(begin + beginMarker.length, end);
  }

  static const _discoveryScript = r'''
$ErrorActionPreference = 'Stop'
$espGuid = '{C12A7328-F81F-11D2-BA4B-00A0C93EC93B}'

function Clean-Text($value) {
  if ($null -eq $value) { return '' }
  return $value.ToString().Trim()
}

function Normalize-Identity($value) {
  return (Clean-Text $value -replace '\s+', '').ToUpperInvariant()
}

function Is-ReliableIdentity($value) {
  $normalized = Normalize-Identity $value
  if ($normalized.Length -lt 4 -or $normalized -in @('UNKNOWN', 'N/A')) { return $false }
  $compact = $normalized -replace '[^A-Z0-9]', ''
  return $compact.Length -ge 4 -and $compact -notmatch '^(0+|F+)$'
}

function Is-GenericPhysicalDriveAlias($value) {
  return (Normalize-Identity $value) -match '^(?:\\\\[.?]\\)?PHYSICALDRIVE\d+$'
}

try {
  $diskDrives = @(Get-CimInstance Win32_DiskDrive -ErrorAction SilentlyContinue)
  $physicalDisks = @(Get-PhysicalDisk -ErrorAction SilentlyContinue)
  $windowsVolumes = @()

  foreach ($disk in @(Get-Disk -ErrorAction Stop | Sort-Object Number)) {
    $bus = Clean-Text $disk.BusType
    $isExternal = $bus.ToUpperInvariant() -in @('USB', 'SD', 'MMC') -or [bool]$disk.IsRemovable
    if (-not $isExternal -or $disk.IsSystem -or $disk.IsBoot -or $disk.IsOffline) { continue }

    $diskDrive = $diskDrives | Where-Object { [int]$_.Index -eq [int]$disk.Number } | Select-Object -First 1
    $physical = $physicalDisks | Where-Object { $_.DeviceId -eq $disk.Number.ToString() } | Select-Object -First 1
    $serial = Clean-Text $physical.SerialNumber
    if (-not $serial) { $serial = Clean-Text $disk.SerialNumber }
    if (-not $serial) { $serial = Clean-Text $diskDrive.SerialNumber }
    $uniqueId = Clean-Text $disk.UniqueId
    $devicePath = Clean-Text $disk.Path
    $pnpDeviceId = Clean-Text $diskDrive.PNPDeviceID

    $identityKind = ''
    $identityValue = ''
    foreach ($candidate in @(
      @('serialNumber', $serial),
      @('uniqueId', $uniqueId),
      @('devicePath', $devicePath),
      @('pnpDeviceId', $pnpDeviceId)
    )) {
      if ((Is-ReliableIdentity $candidate[1]) -and
          -not ($candidate[0] -eq 'devicePath' -and (Is-GenericPhysicalDriveAlias $candidate[1]))) {
        $identityKind = $candidate[0]
        $identityValue = Normalize-Identity $candidate[1]
        break
      }
    }
    if (-not $identityKind) { continue }

    $model = Clean-Text $physical.Model
    if (-not $model) { $model = Clean-Text $diskDrive.Model }
    if (-not $model) { $model = Clean-Text $disk.FriendlyName }

    $diskInfo = [PSCustomObject]@{
      snapshotDiskNumber = [int]$disk.Number
      model = $model
      sizeBytes = $disk.Size.ToString()
      serialNumber = $serial
      uniqueId = $uniqueId
      devicePath = $devicePath
      pnpDeviceId = $pnpDeviceId
      busType = $bus
      partitionStyle = Clean-Text $disk.PartitionStyle
      identityKind = $identityKind
      identityValue = $identityValue
      isReadOnly = [bool]$disk.IsReadOnly
    }

    $partitions = @(Get-Partition -DiskNumber $disk.Number -ErrorAction SilentlyContinue)
    $targets = @()
    foreach ($partition in $partitions) {
      $volume = $partition | Get-Volume -ErrorAction SilentlyContinue
      if ($null -eq $volume -or -not $volume.Path) { continue }
      $fileSystem = Clean-Text $volume.FileSystem
      $gptType = Clean-Text $partition.GptType
      $supportsUefi = (
        (Clean-Text $disk.PartitionStyle).ToUpperInvariant() -eq 'GPT' -and
        $gptType.ToUpperInvariant() -eq $espGuid -and
        $fileSystem.ToUpperInvariant() -eq 'FAT32'
      )
      $supportsBios = (
        (Clean-Text $disk.PartitionStyle).ToUpperInvariant() -eq 'MBR' -and
        [bool]$partition.IsActive -and
        $fileSystem.ToUpperInvariant() -in @('NTFS', 'FAT32')
      )
      if (-not $supportsUefi -and -not $supportsBios) { continue }
      $targets += [PSCustomObject]@{
        diskNumber = [int]$disk.Number
        partitionNumber = [int]$partition.PartitionNumber
        partitionOffset = $partition.Offset.ToString()
        volumeGuidPath = Clean-Text $volume.Path
        driveLetter = if ($partition.DriveLetter) { $partition.DriveLetter.ToString().ToUpperInvariant() + ':\' } else { $null }
        fileSystem = $fileSystem
        label = Clean-Text $volume.FileSystemLabel
        sizeBytes = $partition.Size.ToString()
        freeBytes = if ($null -ne $volume.SizeRemaining) { $volume.SizeRemaining.ToString() } else { $null }
        gptType = $gptType
        isActive = [bool]$partition.IsActive
        supportsUefi = $supportsUefi
        supportsBios = $supportsBios
      }
    }

    foreach ($partition in $partitions) {
      $volume = $partition | Get-Volume -ErrorAction SilentlyContinue
      if ($null -eq $volume -or -not $volume.Path) { continue }
      $windowsPath = Join-Path $volume.Path 'Windows'
      $system32Path = Join-Path $windowsPath 'System32'
      try {
        $containsWindows = (Test-Path -LiteralPath $windowsPath -PathType Container) -and
          (Test-Path -LiteralPath $system32Path -PathType Container)
      } catch {
        $containsWindows = $false
      }
      if (-not $containsWindows) { continue }

      $windowsVolumes += [PSCustomObject]@{
        disk = $diskInfo
        partitionNumber = [int]$partition.PartitionNumber
        partitionOffset = $partition.Offset.ToString()
        volumeGuidPath = Clean-Text $volume.Path
        driveLetter = if ($partition.DriveLetter) { $partition.DriveLetter.ToString().ToUpperInvariant() + ':\' } else { $null }
        fileSystem = Clean-Text $volume.FileSystem
        label = Clean-Text $volume.FileSystemLabel
        sizeBytes = $partition.Size.ToString()
        bootTargets = $targets
      }
    }
  }

  $payload = [PSCustomObject]@{ ok = $true; windowsVolumes = $windowsVolumes }
} catch {
  $payload = [PSCustomObject]@{
    ok = $false
    technicalError = $_.Exception.Message
    windowsVolumes = @()
  }
}
$payload | Add-Member -NotePropertyName responseNonce `
  -NotePropertyValue $env:WDS_RESPONSE_NONCE -Force
[IO.File]::WriteAllText(
  $env:WDS_BOOT_OUTPUT,
  ($payload | ConvertTo-Json -Depth 9 -Compress),
  (New-Object Text.UTF8Encoding($false))
)
''';

  static const _bootOperationScript = r'''
$ErrorActionPreference = 'Stop'
$espGuid = '{C12A7328-F81F-11D2-BA4B-00A0C93EC93B}'
$spec = $env:WDS_BOOT_SPEC | ConvertFrom-Json
$checks = New-Object Collections.Generic.List[object]
$technicalLog = New-Object Collections.Generic.List[string]
$mountedPaths = New-Object Collections.Generic.List[object]
$result = $null
$verification = $null
$bcdPath = $null
$existingBcd = $false
$existingBcdBackedUp = $false
$backupCompleted = $false
$repairStarted = $false
$rollbackAttempted = $false
$rollbackSucceeded = $false
$rollbackError = ''

function Add-Log([string]$message) {
  $technicalLog.Add(('{0:o} {1}' -f [DateTime]::Now, $message))
}

function Add-Check([string]$labelKey, [bool]$passed, [string]$detailKey, [string]$technical) {
  $checks.Add([PSCustomObject]@{
    labelKey = $labelKey
    passed = $passed
    detailKey = $detailKey
  })
  Add-Log ("CHECK $labelKey = $passed; $technical")
}

function Clean-Text($value) {
  if ($null -eq $value) { return '' }
  return $value.ToString().Trim()
}

function Normalize-Identity($value) {
  return (Clean-Text $value -replace '\s+', '').ToUpperInvariant()
}

function Is-GenericPhysicalDriveAlias($value) {
  return (Normalize-Identity $value) -match '^(?:\\\\[.?]\\)?PHYSICALDRIVE\d+$'
}

function Get-DiskIdentity($disk, $diskDrive, [string]$kind) {
  switch ($kind) {
    'serialNumber' {
      $physical = Get-PhysicalDisk -ErrorAction SilentlyContinue |
        Where-Object { $_.DeviceId -eq $disk.Number.ToString() } | Select-Object -First 1
      $value = Clean-Text $physical.SerialNumber
      if (-not $value) { $value = Clean-Text $disk.SerialNumber }
      if (-not $value) { $value = Clean-Text $diskDrive.SerialNumber }
      return Normalize-Identity $value
    }
    'uniqueId' { return Normalize-Identity $disk.UniqueId }
    'devicePath' {
      $value = Normalize-Identity $disk.Path
      if (Is-GenericPhysicalDriveAlias $value) { return '' }
      return $value
    }
    'pnpDeviceId' { return Normalize-Identity $diskDrive.PNPDeviceID }
    default { return '' }
  }
}

function Resolve-BoundDisk {
  $diskDrives = @(Get-CimInstance Win32_DiskDrive -ErrorAction SilentlyContinue)
  $matches = @()
  foreach ($disk in @(Get-Disk -ErrorAction Stop)) {
    $diskDrive = $diskDrives | Where-Object { [int]$_.Index -eq [int]$disk.Number } | Select-Object -First 1
    $identity = Get-DiskIdentity $disk $diskDrive $spec.disk.identityKind
    if ($identity -ne $spec.disk.identityValue) { continue }
    if ([int]$disk.Number -ne [int]$spec.disk.snapshotDiskNumber) { continue }
    if ([uint64]$disk.Size -ne [uint64]$spec.disk.sizeBytes) { continue }
    if ((Clean-Text $disk.BusType).ToUpperInvariant() -ne $spec.disk.busType.ToUpperInvariant()) { continue }
    $matches += $disk
  }
  if ($matches.Count -ne 1) { return $null }
  return $matches[0]
}

function Resolve-BoundPartition($disk, $binding) {
  $matches = @(Get-Partition -DiskNumber $disk.Number -ErrorAction Stop | Where-Object {
    [uint64]$_.Offset -eq [uint64]$binding.partitionOffset
  })
  if ($matches.Count -ne 1) { return $null }
  $partition = $matches[0]
  $volume = $partition | Get-Volume -ErrorAction SilentlyContinue
  if ($null -eq $volume -or -not $volume.Path) { return $null }
  if ((Clean-Text $volume.Path).ToUpperInvariant() -ne $binding.volumeGuidPath.ToUpperInvariant()) { return $null }
  return [PSCustomObject]@{ Partition = $partition; Volume = $volume }
}

function Get-UnusedDriveRoot {
  $used = @(Get-Volume -ErrorAction SilentlyContinue | Where-Object { $_.DriveLetter } |
    ForEach-Object { $_.DriveLetter.ToString().ToUpperInvariant() })
  foreach ($code in 90..68) {
    $letter = [char]$code
    if ($letter.ToString() -notin $used) { return $letter.ToString() + ':\' }
  }
  throw 'No unused temporary drive letter is available.'
}

function Get-PartitionRoot($boundPartition) {
  if ($boundPartition.Partition.DriveLetter) {
    return $boundPartition.Partition.DriveLetter.ToString().ToUpperInvariant() + ':\'
  }
  $root = Get-UnusedDriveRoot
  Add-PartitionAccessPath -DiskNumber $boundPartition.Partition.DiskNumber `
    -PartitionNumber $boundPartition.Partition.PartitionNumber `
    -AccessPath $root -ErrorAction Stop
  $mountedPaths.Add([PSCustomObject]@{
    DiskNumber = [int]$boundPartition.Partition.DiskNumber
    PartitionNumber = [int]$boundPartition.Partition.PartitionNumber
    AccessPath = $root
  })
  Add-Log "Temporarily mounted disk $($boundPartition.Partition.DiskNumber), partition $($boundPartition.Partition.PartitionNumber) at $root"
  return $root
}

function Get-EfiFallbackName([string]$bootManagerPath) {
  $stream = [IO.File]::Open($bootManagerPath, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
  try {
    $reader = New-Object IO.BinaryReader($stream)
    $stream.Position = 0x3c
    $peOffset = $reader.ReadInt32()
    $stream.Position = $peOffset + 4
    $machine = $reader.ReadUInt16()
    switch ($machine) {
      0x8664 { return 'bootx64.efi' }
      0xAA64 { return 'bootaa64.efi' }
      0x014c { return 'bootia32.efi' }
      0x01c4 { return 'bootarm.efi' }
      default { throw ('Unsupported EFI PE machine type: 0x{0:X4}' -f $machine) }
    }
  } finally {
    $stream.Dispose()
  }
}

function Test-CancelRequested {
  $cancelPath = $env:WDS_PS_CANCEL_PATH
  return -not [string]::IsNullOrWhiteSpace($cancelPath) -and
    [IO.File]::Exists($cancelPath)
}

function Invoke-BcdBootTracked(
  [string]$executable,
  [string]$windowsPath,
  [string]$targetRoot,
  [string]$firmware
) {
  if ($windowsPath.Contains('"') -or $targetRoot.Contains('"')) {
    throw 'A bound boot path contains an invalid quote character.'
  }
  $startInfo = New-Object Diagnostics.ProcessStartInfo
  $startInfo.FileName = $executable
  $startInfo.Arguments = ('"{0}" /s "{1}" /f {2} /v' -f $windowsPath, $targetRoot, $firmware)
  $startInfo.UseShellExecute = $false
  $startInfo.CreateNoWindow = $true
  $startInfo.RedirectStandardOutput = $true
  $startInfo.RedirectStandardError = $true
  $process = New-Object Diagnostics.Process
  $process.StartInfo = $startInfo
  try {
    if (-not $process.Start()) { throw 'Could not start bcdboot.' }
    $stdoutTask = $process.StandardOutput.ReadToEndAsync()
    $stderrTask = $process.StandardError.ReadToEndAsync()
    while (-not $process.WaitForExit(100)) {
      if (Test-CancelRequested) {
        & (Join-Path $env:SystemRoot 'System32\taskkill.exe') `
          /F /T /PID $process.Id *> $null
        $process.WaitForExit()
        throw 'Boot repair was cancelled.'
      }
    }
    $process.WaitForExit()
    $lines = @()
    $lines += @($stdoutTask.Result -split "`r?`n" | Where-Object { $_ })
    $lines += @($stderrTask.Result -split "`r?`n" | Where-Object { $_ })
    return [PSCustomObject]@{ ExitCode = $process.ExitCode; Output = $lines }
  } finally {
    $process.Dispose()
  }
}

# WDS_BCD_ROLLBACK_BEGIN
function Get-FileSha256([string]$path) {
  $stream = [IO.File]::Open(
    $path,
    [IO.FileMode]::Open,
    [IO.FileAccess]::Read,
    [IO.FileShare]::Read
  )
  $algorithm = [Security.Cryptography.SHA256]::Create()
  try {
    return ([BitConverter]::ToString($algorithm.ComputeHash($stream))).Replace('-', '')
  } finally {
    $algorithm.Dispose()
    $stream.Dispose()
  }
}

function Restore-BcdBackup(
  [string]$storePath,
  [string]$backupDirectory,
  [bool]$hadExistingStore
) {
  Set-Variable -Name rollbackAttempted -Value $true -Scope 1
  try {
    $backupStore = Join-Path $backupDirectory 'BCD'
    if ($hadExistingStore -and
        -not (Test-Path -LiteralPath $backupStore -PathType Leaf)) {
      throw 'The BCD backup is missing.'
    }
    foreach ($suffix in @('', '.LOG', '.LOG1', '.LOG2')) {
      $currentPath = $storePath + $suffix
      if (Test-Path -LiteralPath $currentPath -PathType Leaf) {
        Remove-Item -LiteralPath $currentPath -Force -ErrorAction Stop
      }
    }

    if ($hadExistingStore) {
      foreach ($suffix in @('', '.LOG', '.LOG1', '.LOG2')) {
        $backupPath = Join-Path $backupDirectory ('BCD' + $suffix)
        if (Test-Path -LiteralPath $backupPath -PathType Leaf) {
          Copy-Item -LiteralPath $backupPath -Destination ($storePath + $suffix) `
            -Force -ErrorAction Stop
        }
      }
      $backupHash = Get-FileSha256 $backupStore
      $restoredHash = Get-FileSha256 $storePath
      if ($backupHash -ne $restoredHash) {
        throw 'The restored BCD does not match its backup.'
      }
      Add-Log 'Rollback restored and hash-verified the original BCD store.'
    } else {
      if (Test-Path -LiteralPath $storePath -PathType Leaf) {
        throw 'Rollback could not remove the newly-created BCD store.'
      }
      Add-Log 'Rollback removed the BCD store created by the failed repair.'
    }
    Set-Variable -Name rollbackSucceeded -Value $true -Scope 1
  } catch {
    $errorMessage = $_.Exception.Message
    Set-Variable -Name rollbackSucceeded -Value $false -Scope 1
    Set-Variable -Name rollbackError -Value $errorMessage -Scope 1
    Add-Log "ROLLBACK ERROR: $errorMessage"
  }
}
# WDS_BCD_ROLLBACK_END

function Get-BcdElementValue([string[]]$lines, [string]$elementName) {
  foreach ($line in $lines) {
    if ($line -match '^\s*([A-Za-z][A-Za-z0-9]*)\s+(.+?)\s*$' -and
        $Matches[1].Equals($elementName, [StringComparison]::OrdinalIgnoreCase)) {
      return $Matches[2].Trim()
    }
  }
  return ''
}

function Normalize-BcdPartition([string]$value) {
  return (Clean-Text $value).Replace('/', '\').TrimEnd('\').ToUpperInvariant()
}

function Test-BcdPartitionTarget(
  [string]$actual,
  [string]$windowsRoot,
  [string]$windowsVolumePath
) {
  $normalized = Normalize-BcdPartition $actual
  $expected = @(
    Normalize-BcdPartition ('partition=' + $windowsRoot),
    Normalize-BcdPartition ('partition=' + $windowsVolumePath)
  )
  return $normalized -in $expected
}

function Write-TechnicalLog {
  if (-not $spec.logPath) { return }
  $directory = Split-Path -Parent $spec.logPath
  if ($directory) { New-Item -ItemType Directory -Path $directory -Force | Out-Null }
  [IO.File]::WriteAllLines($spec.logPath, $technicalLog, (New-Object Text.UTF8Encoding($false)))
}

try {
  Add-Log "Mode=$($spec.mode); Firmware=$($spec.firmware)"
  $disk = Resolve-BoundDisk
  $diskBound = $null -ne $disk
  if ($diskBound) {
    $bus = (Clean-Text $disk.BusType).ToUpperInvariant()
    $isExternal = $bus -in @('USB', 'SD', 'MMC') -or [bool]$disk.IsRemovable
    $diskSafe = $isExternal -and -not $disk.IsSystem -and -not $disk.IsBoot -and -not $disk.IsOffline
  } else {
    $diskSafe = $false
  }
  Add-Check 'boot_repair_check_disk_binding' $diskBound `
    $(if ($diskBound) { 'boot_repair_check_detail_passed' } else { 'boot_repair_check_detail_disk_changed' }) `
    'Bound external physical disk identity, size, and bus type.'
  Add-Check 'boot_repair_check_external_disk' $diskSafe `
    $(if ($diskSafe) { 'boot_repair_check_detail_passed' } else { 'boot_repair_check_detail_not_safe_external' }) `
    'Disk must remain external, online, non-system, and non-boot.'

  $windowsBound = if ($diskBound) { Resolve-BoundPartition $disk $spec.windowsVolume } else { $null }
  $targetBound = if ($diskBound) { Resolve-BoundPartition $disk $spec.bootTarget } else { $null }
  Add-Check 'boot_repair_check_windows_binding' ($null -ne $windowsBound) `
    $(if ($windowsBound) { 'boot_repair_check_detail_passed' } else { 'boot_repair_check_detail_volume_changed' }) `
    'Matched the Windows partition by physical disk, offset, and volume GUID.'
  Add-Check 'boot_repair_check_target_binding' ($null -ne $targetBound) `
    $(if ($targetBound) { 'boot_repair_check_detail_passed' } else { 'boot_repair_check_detail_volume_changed' }) `
    'Matched the boot partition by physical disk, offset, and volume GUID.'

  $containsWindows = $false
  if ($windowsBound) {
    try {
      $containsWindows = (Test-Path -LiteralPath (Join-Path $windowsBound.Volume.Path 'Windows') -PathType Container) -and
        (Test-Path -LiteralPath (Join-Path $windowsBound.Volume.Path 'Windows\System32') -PathType Container)
    } catch { $containsWindows = $false }
  }
  Add-Check 'boot_repair_check_windows_directory' $containsWindows `
    $(if ($containsWindows) { 'boot_repair_check_detail_passed' } else { 'boot_repair_check_detail_windows_missing' }) `
    'Verified Windows and Windows\System32 directories on the bound source volume.'

  $sameDisk = $windowsBound -and $targetBound -and
    $windowsBound.Partition.DiskNumber -eq $targetBound.Partition.DiskNumber -and
    $windowsBound.Partition.DiskNumber -eq $disk.Number
  Add-Check 'boot_repair_check_same_disk' $sameDisk `
    $(if ($sameDisk) { 'boot_repair_check_detail_passed' } else { 'boot_repair_check_detail_cross_disk' }) `
    'Source and target partitions must remain on the same bound external disk.'

  $writable = $diskSafe -and -not [bool]$disk.IsReadOnly -and $targetBound -and
    -not [bool]$targetBound.Partition.IsReadOnly
  Add-Check 'boot_repair_check_writable' $writable `
    $(if ($writable) { 'boot_repair_check_detail_passed' } else { 'boot_repair_check_detail_read_only' }) `
    'Bound disk and target partition must be writable.'

  $firmwareCompatible = $false
  if ($targetBound -and $spec.firmware -eq 'UEFI') {
    $firmwareCompatible = (Clean-Text $disk.PartitionStyle).ToUpperInvariant() -eq 'GPT' -and
      (Clean-Text $targetBound.Partition.GptType).ToUpperInvariant() -eq $espGuid -and
      (Clean-Text $targetBound.Volume.FileSystem).ToUpperInvariant() -eq 'FAT32'
  } elseif ($targetBound -and $spec.firmware -eq 'BIOS') {
    $firmwareCompatible = (Clean-Text $disk.PartitionStyle).ToUpperInvariant() -eq 'MBR' -and
      [bool]$targetBound.Partition.IsActive -and
      (Clean-Text $targetBound.Volume.FileSystem).ToUpperInvariant() -in @('NTFS', 'FAT32')
  }
  Add-Check 'boot_repair_check_firmware_target' $firmwareCompatible `
    $(if ($firmwareCompatible) { 'boot_repair_check_detail_passed' } else { 'boot_repair_check_detail_firmware_mismatch' }) `
    'UEFI requires a FAT32 GPT ESP; BIOS requires an active MBR NTFS/FAT32 partition.'

  $bcdbootPath = Join-Path $env:SystemRoot 'System32\bcdboot.exe'
  $bcdeditPath = Join-Path $env:SystemRoot 'System32\bcdedit.exe'
  $toolsPresent = (Test-Path -LiteralPath $bcdbootPath -PathType Leaf) -and
    (Test-Path -LiteralPath $bcdeditPath -PathType Leaf)
  Add-Check 'boot_repair_check_windows_tools' $toolsPresent `
    $(if ($toolsPresent) { 'boot_repair_check_detail_passed' } else { 'boot_repair_check_detail_tools_missing' }) `
    'Verified system bcdboot.exe and bcdedit.exe.'

  $canContinue = $checks.Count -gt 0 -and @($checks | Where-Object { -not $_.passed }).Count -eq 0
  $plannedActions = @(
    'boot_repair_plan_revalidate',
    'boot_repair_plan_mount',
    'boot_repair_plan_backup',
    'boot_repair_plan_bcdboot',
    'boot_repair_plan_verify',
    'boot_repair_plan_unmount'
  )
  if ($spec.firmware -eq 'UEFI') {
    $plannedActions = @($plannedActions[0..3]) + @('boot_repair_plan_fallback') + @($plannedActions[4..5])
  }

  if ($spec.mode -eq 'preflight') {
    $result = [PSCustomObject]@{
      ok = $canContinue
      checks = @($checks)
      warningKeys = @('boot_repair_warning_no_format', 'boot_repair_warning_boot_change')
      plannedActionKeys = $plannedActions
    }
  } elseif ($spec.mode -eq 'execute') {
    if (-not $canContinue) { throw 'Elevated revalidation failed before bcdboot.' }
    $windowsRoot = Get-PartitionRoot $windowsBound
    if ($windowsBound.Partition.DiskNumber -eq $targetBound.Partition.DiskNumber -and
        $windowsBound.Partition.PartitionNumber -eq $targetBound.Partition.PartitionNumber) {
      $targetRoot = $windowsRoot
    } else {
      $targetRoot = Get-PartitionRoot $targetBound
    }
    $windowsPath = Join-Path $windowsRoot 'Windows'

    if ($spec.firmware -eq 'UEFI') {
      $bcdRelative = 'EFI\Microsoft\Boot\BCD'
      $bootManagerRelative = 'EFI\Microsoft\Boot\bootmgfw.efi'
    } else {
      $bcdRelative = 'Boot\BCD'
      $bootManagerRelative = 'bootmgr'
    }
    $bcdPath = Join-Path $targetRoot $bcdRelative
    New-Item -ItemType Directory -Path $spec.backupDirectory -Force | Out-Null
    $existingBcd = Test-Path -LiteralPath $bcdPath -PathType Leaf
    if ($existingBcd) {
      $backupStorePath = Join-Path $spec.backupDirectory 'BCD'
      Copy-Item -LiteralPath $bcdPath -Destination $backupStorePath -Force -ErrorAction Stop
      foreach ($suffix in @('.LOG', '.LOG1', '.LOG2')) {
        if (Test-Path -LiteralPath ($bcdPath + $suffix) -PathType Leaf) {
          Copy-Item -LiteralPath ($bcdPath + $suffix) `
            -Destination (Join-Path $spec.backupDirectory ('BCD' + $suffix)) -Force -ErrorAction Stop
        }
      }
      $sourceHash = Get-FileSha256 $bcdPath
      $backupHash = Get-FileSha256 $backupStorePath
      if ($sourceHash -ne $backupHash) { throw 'The BCD backup hash does not match the source store.' }
      $existingBcdBackedUp = $true
      Add-Log 'Backed up and hash-verified the existing BCD before running bcdboot.'
    } else {
      [IO.File]::WriteAllText(
        (Join-Path $spec.backupDirectory 'NO_EXISTING_BCD.txt'),
        'No BCD store existed on the selected target before bcdboot.',
        (New-Object Text.UTF8Encoding($false))
      )
      Add-Log 'No existing BCD store was present; recorded this before running bcdboot.'
    }
    $backupCompleted = $true
    [IO.File]::WriteAllText(
      (Join-Path $spec.backupDirectory 'binding.json'),
      ($spec | ConvertTo-Json -Depth 8),
      (New-Object Text.UTF8Encoding($false))
    )
    $rollbackState = [PSCustomObject]@{
      backupCompleted = $backupCompleted
      existingBcdBackedUp = $existingBcdBackedUp
      hadExistingBcd = $existingBcd
      bcdRelativePath = $bcdRelative
    }
    [IO.File]::WriteAllText(
      (Join-Path $spec.backupDirectory 'rollback_state.json'),
      ($rollbackState | ConvertTo-Json -Compress),
      (New-Object Text.UTF8Encoding($false))
    )

    if (Test-CancelRequested) { throw 'Boot repair was cancelled.' }
    Add-Log "Running system bcdboot for firmware $($spec.firmware)."
    $repairStarted = $true
    $bcdbootResult = Invoke-BcdBootTracked $bcdbootPath $windowsPath $targetRoot $spec.firmware
    foreach ($line in $bcdbootResult.Output) { Add-Log "BCDBOOT: $line" }
    Add-Log "bcdboot exit code: $($bcdbootResult.ExitCode)"
    if ($bcdbootResult.ExitCode -ne 0) {
      throw "bcdboot failed with exit code $($bcdbootResult.ExitCode)."
    }
    if (Test-CancelRequested) { throw 'Boot repair was cancelled.' }

    $bootManagerPath = Join-Path $targetRoot $bootManagerRelative
    $fallbackPath = $null
    $fallbackHash = $null
    $bootManagerHash = $null
    $fallbackExists = $false
    $fallbackMatchesBootManager = $spec.firmware -ne 'UEFI'
    if ($spec.firmware -eq 'UEFI') {
      if (-not (Test-Path -LiteralPath $bootManagerPath -PathType Leaf)) {
        throw 'bcdboot did not create the Microsoft EFI boot manager.'
      }
      $bootManagerHash = Get-FileSha256 $bootManagerPath
      $fallbackName = Get-EfiFallbackName $bootManagerPath
      $fallbackDirectory = Join-Path $targetRoot 'EFI\Boot'
      $fallbackPath = Join-Path $fallbackDirectory $fallbackName
      $copyFallback = -not (Test-Path -LiteralPath $fallbackPath -PathType Leaf)
      if (-not $copyFallback) {
        $currentFallbackHash = Get-FileSha256 $fallbackPath
        $copyFallback = $currentFallbackHash -ne $bootManagerHash
      }
      if ($copyFallback) {
        New-Item -ItemType Directory -Path $fallbackDirectory -Force | Out-Null
        Copy-Item -LiteralPath $bootManagerPath -Destination $fallbackPath -Force -ErrorAction Stop
        Add-Log "Synchronized EFI fallback from the Microsoft boot manager: $fallbackName"
      }
      $fallbackExists = Test-Path -LiteralPath $fallbackPath -PathType Leaf
      if ($fallbackExists) {
        $fallbackHash = Get-FileSha256 $fallbackPath
        $fallbackMatchesBootManager = $fallbackHash -eq $bootManagerHash
      }
    } elseif (Test-Path -LiteralPath $bootManagerPath -PathType Leaf) {
      $bootManagerHash = Get-FileSha256 $bootManagerPath
    }
    if (Test-CancelRequested) { throw 'Boot repair was cancelled.' }

    $bcdExists = Test-Path -LiteralPath $bcdPath -PathType Leaf
    $bcdReadable = $false
    if ($bcdExists) {
      $bcdOutput = @(& $bcdeditPath '/store' $bcdPath '/enum' '{bootmgr}' '/v' 2>&1 |
        ForEach-Object { $_.ToString() })
      $bcdExitCode = $LASTEXITCODE
      foreach ($line in $bcdOutput) { Add-Log "BCDEDIT BOOTMGR: $line" }
      $bcdReadable = $bcdExitCode -eq 0
    }
    $bootManagerExists = Test-Path -LiteralPath $bootManagerPath -PathType Leaf
    $defaultOsLoaderExists = $false
    $defaultDevice = ''
    $defaultOsDevice = ''
    $defaultDeviceMatches = $false
    $defaultOsDeviceMatches = $false
    if ($bcdReadable) {
      $defaultOutput = @(& $bcdeditPath '/store' $bcdPath '/enum' '{default}' '/v' 2>&1 |
        ForEach-Object { $_.ToString() })
      $defaultExitCode = $LASTEXITCODE
      foreach ($line in $defaultOutput) { Add-Log "BCDEDIT DEFAULT: $line" }
      $defaultOsLoaderExists = $defaultExitCode -eq 0
      if ($defaultOsLoaderExists) {
        $defaultDevice = Get-BcdElementValue $defaultOutput 'device'
        $defaultOsDevice = Get-BcdElementValue $defaultOutput 'osdevice'
        $defaultDeviceMatches = Test-BcdPartitionTarget `
          $defaultDevice $windowsRoot $windowsBound.Volume.Path
        $defaultOsDeviceMatches = Test-BcdPartitionTarget `
          $defaultOsDevice $windowsRoot $windowsBound.Volume.Path
      }
    }
    if (Test-CancelRequested) { throw [OperationCanceledException]::new('Boot repair was cancelled.') }
    $verification = [PSCustomObject]@{
      efiFallbackRequired = $spec.firmware -eq 'UEFI'
      bcdStoreExists = $bcdExists
      bcdStoreReadable = $bcdReadable
      bootManagerExists = $bootManagerExists
      efiFallbackExists = $fallbackExists
      efiFallbackMatchesBootManager = $fallbackMatchesBootManager
      defaultOsLoaderExists = $defaultOsLoaderExists
      defaultOsLoaderDeviceMatches = $defaultDeviceMatches
      defaultOsLoaderOsDeviceMatches = $defaultOsDeviceMatches
      bcdPath = $bcdPath
      bootManagerPath = $bootManagerPath
      efiFallbackPath = $fallbackPath
      bootManagerSha256 = $bootManagerHash
      efiFallbackSha256 = $fallbackHash
      defaultOsLoaderDevice = $defaultDevice
      defaultOsLoaderOsDevice = $defaultOsDevice
    }
    $verified = $bcdExists -and $bcdReadable -and $bootManagerExists -and
      $defaultOsLoaderExists -and $defaultDeviceMatches -and $defaultOsDeviceMatches -and
      ($spec.firmware -ne 'UEFI' -or ($fallbackExists -and $fallbackMatchesBootManager))
    Add-Log "Verification passed: $verified"
    if (-not $verified) { throw 'Post-repair boot verification failed.' }
    $result = [PSCustomObject]@{
      ok = $true
      checks = @($checks)
      existingBcdBackedUp = $existingBcdBackedUp
      rollbackAttempted = $false
      rollbackSucceeded = $false
      backupPath = $spec.backupDirectory
      verification = $verification
    }
  } else {
    throw 'Unknown boot repair mode.'
  }
} catch {
  $technicalError = $_.Exception.Message
  Add-Log "ERROR: $technicalError"
  if ($spec.mode -eq 'execute' -and $repairStarted -and $backupCompleted -and $bcdPath) {
    Restore-BcdBackup $bcdPath $spec.backupDirectory $existingBcd
  }
  $result = [PSCustomObject]@{
    ok = $false
    checks = @($checks)
    existingBcdBackedUp = $existingBcdBackedUp
    rollbackAttempted = $rollbackAttempted
    rollbackSucceeded = $rollbackSucceeded
    rollbackError = $rollbackError
    backupPath = Clean-Text $spec.backupDirectory
    verification = $verification
    technicalError = $technicalError
  }
} finally {
  foreach ($mount in @($mountedPaths | Sort-Object { $_.AccessPath } -Descending)) {
    try {
      Remove-PartitionAccessPath -DiskNumber $mount.DiskNumber `
        -PartitionNumber $mount.PartitionNumber -AccessPath $mount.AccessPath `
        -Confirm:$false -ErrorAction Stop
      Add-Log "Removed temporary access path $($mount.AccessPath)"
    } catch {
      Add-Log "WARNING: Could not remove temporary access path $($mount.AccessPath): $($_.Exception.Message)"
    }
  }
  Write-TechnicalLog
  $result | Add-Member -NotePropertyName responseNonce `
    -NotePropertyValue $env:WDS_RESPONSE_NONCE -Force
  [IO.File]::WriteAllText(
    $env:WDS_BOOT_OUTPUT,
    ($result | ConvertTo-Json -Depth 9 -Compress),
    (New-Object Text.UTF8Encoding($false))
  )
}
''';
}

List<String> _stringList(dynamic raw) {
  if (raw is! List) return const [];
  return raw.map((value) => value.toString()).toList(growable: false);
}

String? _nullableString(dynamic value) {
  if (value == null) return null;
  final text = value.toString().trim();
  return text.isEmpty ? null : text;
}

int? _intFrom(dynamic value) {
  if (value is int) return value;
  return int.tryParse(value?.toString() ?? '');
}

BigInt? _bigIntFrom(dynamic value) {
  if (value == null) return null;
  return BigInt.tryParse(value.toString());
}
