import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../models/deployment_plan.dart';

typedef DeploymentProcessRunner =
    Future<ProcessResult> Function(
      String executable,
      List<String> arguments, {
      required Duration timeout,
    });

class WindowsDeploymentService {
  final void Function(String message) _log;
  final DeploymentProcessRunner? processRunner;

  WindowsDeploymentService(this._log, {this.processRunner});

  Future<bool> configureOfflineImage({
    required String windowsDrive,
    required DeploymentPlan plan,
    required String architecture,
    required List<String> driverInfPaths,
    required String? netFx3Source,
    required bool compactApplied,
    required bool wimBootApplied,
  }) async {
    final imageRoot = _driveRoot(windowsDrive);
    _log('Offline Windows configuration target: $imageRoot');

    if (!await _applySanPolicy(
      imageRoot: imageRoot,
      architecture: architecture,
      policy: plan.blockLocalDisks ? 4 : 1,
    )) {
      return false;
    }

    if (!await _configureAndVerifyRegistry(
      imageRoot: imageRoot,
      plan: plan,
      compactApplied: compactApplied,
    )) {
      return false;
    }

    if (plan.skipOobe) {
      if (!await _configureAndVerifyOobeBypass(
        imageRoot: imageRoot,
        architecture: architecture,
      )) {
        return false;
      }
    } else {
      _log('OPTION skipOobe: not requested');
    }

    if (driverInfPaths.isNotEmpty) {
      if (!await _injectAndVerifyDrivers(
        imageRoot: imageRoot,
        driverDirectory: plan.driverDirectory,
        infPaths: driverInfPaths,
      )) {
        return false;
      }
    } else {
      _log('OPTION offlineDrivers: not requested');
    }

    if (plan.enableNetFx3) {
      if (netFx3Source == null ||
          !await _enableAndVerifyNetFx3(imageRoot, netFx3Source)) {
        _log('OPTION NetFx3 FAILED: no verified matching payload was supplied');
        return false;
      }
    } else {
      _log('OPTION NetFx3: not requested');
    }

    if (wimBootApplied) {
      if (!await _verifyWimBoot(imageRoot)) return false;
    } else {
      _log('OPTION WIMBoot: not requested');
    }

    _log('Offline Windows configuration verified');
    return true;
  }

  Future<bool> disableAndVerifyWinRe({
    required String windowsDrive,
    required bool requested,
  }) async {
    if (!requested) {
      _log('OPTION disableWinRe: not requested');
      return true;
    }

    final windowsDirectory = p.join(_driveRoot(windowsDrive), 'Windows');
    _log('OPTION disableWinRe: executing REAgentC for $windowsDirectory');
    final disableResult = await _run('reagentc', [
      '/disable',
      '/target',
      windowsDirectory,
    ], timeout: const Duration(minutes: 2));
    if (!_succeeded(disableResult, 'REAgentC disable')) return false;

    final recoveryImages = <File>[
      File(p.join(windowsDirectory, 'System32', 'Recovery', 'Winre.wim')),
      File(
        p.join(_driveRoot(windowsDrive), 'Recovery', 'WindowsRE', 'Winre.wim'),
      ),
    ];
    for (final image in recoveryImages) {
      if (await image.exists()) {
        try {
          await image.delete();
          _log('Removed disabled WinRE payload: ${image.path}');
        } catch (error) {
          _log('OPTION disableWinRe FAILED deleting ${image.path}: $error');
          return false;
        }
      }
    }

    final infoResult = await _run('reagentc', [
      '/info',
      '/target',
      windowsDirectory,
    ], timeout: const Duration(minutes: 1));
    if (!_succeeded(infoResult, 'REAgentC status query')) return false;

    for (final image in recoveryImages) {
      if (await image.exists()) {
        _log('OPTION disableWinRe FAILED verification: ${image.path} exists');
        return false;
      }
    }

    _log(
      'OPTION disableWinRe VERIFIED: REAgentC succeeded and no WinRE payload remains',
    );
    return true;
  }

  Future<bool> _applySanPolicy({
    required String imageRoot,
    required String architecture,
    required int policy,
  }) async {
    final token = '${pid}_${DateTime.now().microsecondsSinceEpoch}';
    final answerFile = File(
      p.join(Directory.systemTemp.path, 'wds_san_policy_$token.xml'),
    );
    final xml =
        '''<?xml version="1.0" encoding="utf-8"?>
<unattend xmlns="urn:schemas-microsoft-com:unattend">
  <settings pass="offlineServicing">
    <component name="Microsoft-Windows-PartitionManager" processorArchitecture="$architecture" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS" xmlns:wcm="http://schemas.microsoft.com/WMIConfig/2002/State" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
      <SanPolicy>$policy</SanPolicy>
    </component>
  </settings>
</unattend>
''';

    try {
      await answerFile.writeAsString(xml, flush: true);
      _log(
        'OPTION blockLocalDisks: applying SAN policy $policy '
        '(${policy == 4 ? 'OfflineInternal' : 'OnlineAll'})',
      );
      final result = await _run('dism', [
        '/English',
        '/Image:$imageRoot',
        '/Apply-Unattend:${answerFile.path}',
      ], timeout: const Duration(minutes: 5));
      return _succeeded(result, 'SAN policy unattend');
    } catch (error) {
      _log('OPTION blockLocalDisks FAILED: $error');
      return false;
    } finally {
      try {
        if (await answerFile.exists()) await answerFile.delete();
      } catch (error) {
        _log('SAN policy temporary-file cleanup warning: $error');
      }
    }
  }

  Future<bool> _configureAndVerifyRegistry({
    required String imageRoot,
    required DeploymentPlan plan,
    required bool compactApplied,
  }) async {
    final systemHive = p.join(
      imageRoot,
      'Windows',
      'System32',
      'config',
      'SYSTEM',
    );
    if (!await File(systemHive).exists()) {
      _log('Offline SYSTEM hive is missing: $systemHive');
      return false;
    }

    final hiveName =
        'WDS_DEPLOY_${pid}_${DateTime.now().microsecondsSinceEpoch}';
    final hiveRoot = 'HKLM\\$hiveName';
    var loaded = false;
    var successful = false;
    try {
      final loadResult = await _run('reg', ['load', hiveRoot, systemHive]);
      if (!_succeeded(loadResult, 'SYSTEM hive load')) return false;
      loaded = true;

      final controlSet = await _defaultControlSet(hiveRoot);
      if (controlSet == null) return false;

      if (!await _setDword(
        '$hiveRoot\\$controlSet\\Control',
        'PortableOperatingSystem',
        1,
      )) {
        return false;
      }

      final sanPolicy = plan.blockLocalDisks ? 4 : 1;
      final partmgrKey =
          '$hiveRoot\\$controlSet\\Services\\partmgr\\Parameters';
      if (!await _setDword(partmgrKey, 'SanPolicy', sanPolicy)) return false;

      if (plan.disableUasp) {
        _log('OPTION disableUasp: setting UASPStor service Start=4');
        final uaspKey = '$hiveRoot\\$controlSet\\Services\\UASPStor';
        if (!await _setDword(uaspKey, 'Start', 4)) return false;
      } else {
        _log('OPTION disableUasp: not requested');
      }

      if (plan.usesVirtualDisk && plan.fixVhdDriveLetter) {
        _log('OPTION fixVhdDriveLetter: clearing offline MountedDevices');
        final mountedDevicesKey = '$hiveRoot\\MountedDevices';
        await _run('reg', ['delete', mountedDevicesKey, '/f']);
        final queryResult = await _run('reg', ['query', mountedDevicesKey]);
        if (queryResult == null || queryResult.exitCode == 0) {
          _log('OPTION fixVhdDriveLetter FAILED: MountedDevices still exists');
          return false;
        }
        _log(
          'OPTION fixVhdDriveLetter VERIFIED: mappings will regenerate at first boot',
        );
      } else if (plan.usesVirtualDisk) {
        _log('OPTION fixVhdDriveLetter: not requested');
      } else {
        _log('OPTION fixVhdDriveLetter: not applicable to direct deployment');
      }

      final portableValue = await _queryDword(
        '$hiveRoot\\$controlSet\\Control',
        'PortableOperatingSystem',
      );
      final sanValue = await _queryDword(partmgrKey, 'SanPolicy');
      if (portableValue != 1 || sanValue != sanPolicy) {
        _log(
          'Portable/SAN registry verification FAILED: '
          'Portable=$portableValue SAN=$sanValue expected=$sanPolicy',
        );
        return false;
      }
      _log('OPTION blockLocalDisks VERIFIED: offline SAN policy is $sanPolicy');

      if (plan.disableUasp) {
        final uaspValue = await _queryDword(
          '$hiveRoot\\$controlSet\\Services\\UASPStor',
          'Start',
        );
        if (uaspValue != 4) {
          _log('OPTION disableUasp FAILED verification: Start=$uaspValue');
          return false;
        }
        _log('OPTION disableUasp VERIFIED: UASPStor Start=4');
      }

      if (compactApplied) {
        final compactValue = await _queryDword('$hiveRoot\\Setup', 'Compact');
        if (compactValue != 1) {
          _log('OPTION CompactOS FAILED verification: Compact=$compactValue');
          return false;
        }
        _log('OPTION CompactOS VERIFIED: offline SYSTEM Setup\\Compact=1');
      } else {
        _log('OPTION CompactOS: not requested');
      }

      successful = true;
    } catch (error) {
      _log('Offline registry configuration FAILED: $error');
    } finally {
      if (loaded) {
        final unloaded = await _unloadHive(hiveRoot);
        if (!unloaded) successful = false;
      }
    }
    return successful;
  }

  Future<String?> _defaultControlSet(String hiveRoot) async {
    final value = await _queryDword('$hiveRoot\\Select', 'Default');
    if (value == null || value < 1 || value > 999) {
      _log('Unable to determine the offline default control set: $value');
      return null;
    }
    return 'ControlSet${value.toString().padLeft(3, '0')}';
  }

  Future<bool> _setDword(String key, String name, int value) async {
    final result = await _run('reg', [
      'add',
      key,
      '/v',
      name,
      '/t',
      'REG_DWORD',
      '/d',
      '$value',
      '/f',
    ]);
    return _succeeded(result, 'reg add $key\\$name');
  }

  Future<int?> _queryDword(String key, String name) async {
    final result = await _run('reg', ['query', key, '/v', name]);
    if (result == null || result.exitCode != 0) {
      _log('Registry query FAILED: $key\\$name');
      return null;
    }
    final match = RegExp(
      r'REG_DWORD\s+0x([0-9a-f]+)',
      caseSensitive: false,
    ).firstMatch(result.stdout.toString());
    if (match == null) {
      _log('Registry DWORD parse FAILED: $key\\$name');
      return null;
    }
    return int.tryParse(match.group(1)!, radix: 16);
  }

  Future<bool> _unloadHive(String hiveRoot) async {
    for (var attempt = 1; attempt <= 3; attempt++) {
      final result = await _run('reg', ['unload', hiveRoot]);
      if (result != null && result.exitCode == 0) {
        _log('Offline registry hive unloaded: $hiveRoot');
        return true;
      }
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }
    _log('Offline registry hive unload FAILED: $hiveRoot');
    return false;
  }

  Future<bool> _configureAndVerifyOobeBypass({
    required String imageRoot,
    required String architecture,
  }) async {
    final token = '${pid}_${DateTime.now().microsecondsSinceEpoch}';
    final answerFile = File(
      p.join(Directory.systemTemp.path, 'wds_skip_oobe_$token.xml'),
    );
    final xml =
        '''<?xml version="1.0" encoding="utf-8"?>
<unattend xmlns="urn:schemas-microsoft-com:unattend">
  <settings pass="oobeSystem">
    <component name="Microsoft-Windows-Deployment" processorArchitecture="$architecture" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS" xmlns:wcm="http://schemas.microsoft.com/WMIConfig/2002/State" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
      <Reseal>
        <Mode>Audit</Mode>
        <ForceShutdownNow>false</ForceShutdownNow>
      </Reseal>
    </component>
    <component name="Microsoft-Windows-Shell-Setup" processorArchitecture="$architecture" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS" xmlns:wcm="http://schemas.microsoft.com/WMIConfig/2002/State" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
      <OOBE>
        <HideEULAPage>true</HideEULAPage>
        <HideOnlineAccountScreens>true</HideOnlineAccountScreens>
        <HideWirelessSetupInOOBE>true</HideWirelessSetupInOOBE>
        <SkipMachineOOBE>true</SkipMachineOOBE>
        <SkipUserOOBE>true</SkipUserOOBE>
        <ProtectYourPC>3</ProtectYourPC>
      </OOBE>
    </component>
  </settings>
</unattend>
''';

    try {
      await answerFile.writeAsString(xml, flush: true);
      _log('OPTION skipOobe: caching Audit-mode OOBE bypass answer file');
      final result = await _run('dism', [
        '/English',
        '/Image:$imageRoot',
        '/Apply-Unattend:${answerFile.path}',
      ], timeout: const Duration(minutes: 5));
      if (!_succeeded(result, 'OOBE answer file')) return false;

      final target = File(
        p.join(imageRoot, 'Windows', 'Panther', 'Unattend', 'Unattend.xml'),
      );
      await target.parent.create(recursive: true);
      await answerFile.copy(target.path);
      final cached = await target.readAsString();
      if (!cached.contains('<Mode>Audit</Mode>') ||
          !cached.contains('<SkipMachineOOBE>true</SkipMachineOOBE>') ||
          !cached.contains('<SkipUserOOBE>true</SkipUserOOBE>')) {
        _log(
          'OPTION skipOobe FAILED verification: cached answer file is incomplete',
        );
        return false;
      }
      _log('OPTION skipOobe VERIFIED: first boot is configured for Audit mode');
      return true;
    } catch (error) {
      _log('OPTION skipOobe FAILED: $error');
      return false;
    } finally {
      try {
        if (await answerFile.exists()) await answerFile.delete();
      } catch (error) {
        _log('OOBE temporary-file cleanup warning: $error');
      }
    }
  }

  Future<bool> _injectAndVerifyDrivers({
    required String imageRoot,
    required String driverDirectory,
    required List<String> infPaths,
  }) async {
    _log(
      'OPTION offlineDrivers: injecting ${infPaths.length} INF file(s) '
      'from $driverDirectory',
    );
    final addResult = await _run('dism', [
      '/English',
      '/Image:$imageRoot',
      '/Add-Driver',
      '/Driver:$driverDirectory',
      '/Recurse',
    ], timeout: const Duration(minutes: 30));
    if (!_succeeded(addResult, 'offline driver injection')) return false;

    final queryResult = await _run('dism', [
      '/English',
      '/Image:$imageRoot',
      '/Get-Drivers',
      '/All',
      '/Format:List',
    ], timeout: const Duration(minutes: 10));
    if (!_succeeded(queryResult, 'offline driver verification')) return false;

    final output = queryResult!.stdout.toString().toLowerCase();
    final missing = infPaths
        .map((path) => p.basename(path).toLowerCase())
        .toSet()
        .where((name) => !output.contains(name))
        .toList(growable: false);
    if (missing.isNotEmpty) {
      _log(
        'OPTION offlineDrivers FAILED verification: missing ${missing.join(', ')}',
      );
      return false;
    }
    _log('OPTION offlineDrivers VERIFIED: every requested INF is present');
    return true;
  }

  Future<bool> _enableAndVerifyNetFx3(
    String imageRoot,
    String sourceDirectory,
  ) async {
    _log('OPTION NetFx3: enabling from verified ISO payload $sourceDirectory');
    final enableResult = await _run('dism', [
      '/English',
      '/Image:$imageRoot',
      '/Enable-Feature',
      '/FeatureName:NetFx3',
      '/All',
      '/LimitAccess',
      '/Source:$sourceDirectory',
    ], timeout: const Duration(minutes: 30));
    if (!_succeeded(enableResult, 'NetFx3 enable')) return false;

    final queryResult = await _run('dism', [
      '/English',
      '/Image:$imageRoot',
      '/Get-FeatureInfo',
      '/FeatureName:NetFx3',
    ], timeout: const Duration(minutes: 10));
    if (!_succeeded(queryResult, 'NetFx3 verification')) return false;
    final output = queryResult!.stdout.toString();
    if (!RegExp(
      r'^\s*State\s*:\s*Enabled\s*$',
      caseSensitive: false,
      multiLine: true,
    ).hasMatch(output)) {
      _log('OPTION NetFx3 FAILED verification: feature state is not Enabled');
      return false;
    }
    _log('OPTION NetFx3 VERIFIED: feature state is Enabled');
    return true;
  }

  Future<bool> _verifyWimBoot(String imageRoot) async {
    final kernel = p.join(imageRoot, 'Windows', 'System32', 'ntoskrnl.exe');
    if (!await File(kernel).exists()) {
      _log('OPTION WIMBoot FAILED verification: kernel is missing');
      return false;
    }
    final result = await _run('fsutil', ['wim', 'queryFile', kernel]);
    if (!_succeeded(result, 'WIMBoot pointer verification')) return false;
    final output = '${result!.stdout}\n${result.stderr}'.trim();
    if (output.isEmpty) {
      _log(
        'OPTION WIMBoot FAILED verification: FSUtil returned no backing data',
      );
      return false;
    }
    _log('OPTION WIMBoot VERIFIED: ntoskrnl.exe is WIM-backed');
    return true;
  }

  Future<ProcessResult?> _run(
    String executable,
    List<String> arguments, {
    Duration timeout = const Duration(seconds: 60),
  }) async {
    final runner = processRunner;
    if (runner != null) {
      final result = await runner(executable, arguments, timeout: timeout);
      _log('$executable ${arguments.join(' ')} exit=${result.exitCode}');
      if (result.exitCode != 0) {
        final stdout = _trimOutput(result.stdout);
        final stderr = _trimOutput(result.stderr);
        if (stdout.isNotEmpty) _log('$executable stdout: $stdout');
        if (stderr.isNotEmpty) _log('$executable stderr: $stderr');
      }
      return result;
    }
    try {
      final result = await Process.run(executable, arguments).timeout(timeout);
      _log('$executable ${arguments.join(' ')} exit=${result.exitCode}');
      if (result.exitCode != 0) {
        final stdout = _trimOutput(result.stdout);
        final stderr = _trimOutput(result.stderr);
        if (stdout.isNotEmpty) _log('$executable stdout: $stdout');
        if (stderr.isNotEmpty) _log('$executable stderr: $stderr');
      }
      return result;
    } on TimeoutException {
      _log('$executable timed out after ${timeout.inSeconds}s');
      return null;
    } catch (error) {
      _log('$executable execution FAILED: $error');
      return null;
    }
  }

  bool _succeeded(ProcessResult? result, String operation) {
    if (result == null || result.exitCode != 0) {
      _log('$operation FAILED');
      return false;
    }
    _log('$operation completed');
    return true;
  }

  String _trimOutput(Object? value) {
    final text = value?.toString().trim() ?? '';
    return text.length <= 4000 ? text : '${text.substring(0, 4000)}...';
  }

  String _driveRoot(String drive) {
    final value = drive.trim();
    if (value.endsWith('\\')) return value;
    if (value.endsWith(':')) return '$value\\';
    if (value.length == 1) return '$value:\\';
    return value;
  }
}
