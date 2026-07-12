import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import '../../app/visual_style.dart';
import '../../features/deployment/models/deployment_plan.dart';
import 'disk_safety_service.dart';

enum ElevatedTaskKind { windowsInstall, linuxInstall, windowsToGo, linuxToGo }

class ElevatedTaskProgress {
  final String phase;
  final String message;
  final double progress;
  final bool cancellable;
  final int writtenBytes;
  final int totalBytes;
  final int speedBytesPerSecond;
  final int elapsedSeconds;

  const ElevatedTaskProgress({
    required this.phase,
    required this.message,
    required this.progress,
    this.cancellable = false,
    this.writtenBytes = 0,
    this.totalBytes = 0,
    this.speedBytesPerSecond = 0,
    this.elapsedSeconds = 0,
  });

  factory ElevatedTaskProgress.fromJson(Map<String, dynamic> json) {
    return ElevatedTaskProgress(
      phase: json['phase']?.toString() ?? 'preparing',
      message: json['message']?.toString() ?? '',
      progress: ((json['progress'] as num?)?.toDouble() ?? 0).clamp(0, 1),
      cancellable: json['cancellable'] as bool? ?? false,
      writtenBytes: (json['writtenBytes'] as num?)?.toInt() ?? 0,
      totalBytes: (json['totalBytes'] as num?)?.toInt() ?? 0,
      speedBytesPerSecond: (json['speedBytesPerSecond'] as num?)?.toInt() ?? 0,
      elapsedSeconds: (json['elapsedSeconds'] as num?)?.toInt() ?? 0,
    );
  }
}

typedef ElevatedTaskProgressCallback =
    void Function(ElevatedTaskProgress progress);

class ElevatedTaskController {
  String? _cancelPath;
  String? _cancelToken;
  bool _cancelRequested = false;

  bool get cancelRequested => _cancelRequested;

  Future<void> cancel() async {
    _cancelRequested = true;
    final path = _cancelPath;
    if (path == null) return;
    await File(path).writeAsString(_cancelMarker(_cancelToken));
  }

  void _attach(String path, String? token) {
    _cancelPath = path;
    _cancelToken = token;
    if (_cancelRequested) {
      File(path).writeAsStringSync(_cancelMarker(token));
    }
  }

  void _detach() {
    _cancelPath = null;
    _cancelToken = null;
  }

  static String _cancelMarker(String? token) {
    return token == null ? 'cancel' : 'cancel|$token';
  }
}

class ElevatedTaskSpec {
  final ElevatedTaskKind kind;
  final DiskInfo disk;
  final String isoPath;
  final String localeCode;
  final AppAppearanceSettings? appearance;
  final int? imageIndex;
  final DeploymentPlan? deploymentPlan;
  final String? progressPath;
  final String? cancelPath;
  final String? resultPath;
  final String? ipcToken;

  const ElevatedTaskSpec({
    required this.kind,
    required this.disk,
    required this.isoPath,
    required this.localeCode,
    this.appearance,
    this.imageIndex,
    this.deploymentPlan,
    this.progressPath,
    this.cancelPath,
    this.resultPath,
    this.ipcToken,
  });

  Map<String, dynamic> toJson() => {
    'kind': kind.name,
    'disk': disk.toJson(),
    'isoPath': isoPath,
    'localeCode': localeCode,
    'appearance': appearance?.toJson(),
    'imageIndex': imageIndex,
    'deploymentPlan': deploymentPlan?.toJson(),
    'progressPath': progressPath,
    'cancelPath': cancelPath,
    'resultPath': resultPath,
    'ipcToken': ipcToken,
  };

  factory ElevatedTaskSpec.fromJson(Map<String, dynamic> json) {
    return ElevatedTaskSpec(
      kind: ElevatedTaskKind.values.byName(json['kind'] as String),
      disk: DiskInfo.fromJson(Map<String, dynamic>.from(json['disk'] as Map)),
      isoPath: json['isoPath'] as String,
      localeCode: json['localeCode'] as String? ?? 'en',
      appearance: json['appearance'] is Map
          ? AppAppearanceSettings.fromJson(
              Map<String, dynamic>.from(json['appearance'] as Map),
            )
          : null,
      imageIndex: (json['imageIndex'] as num?)?.toInt(),
      deploymentPlan: json['deploymentPlan'] is Map
          ? DeploymentPlan.fromJson(
              Map<String, dynamic>.from(json['deploymentPlan'] as Map),
            )
          : null,
      progressPath: json['progressPath'] as String?,
      cancelPath: json['cancelPath'] as String?,
      resultPath: json['resultPath'] as String?,
      ipcToken: json['ipcToken'] as String?,
    );
  }

  String encode() => base64Url.encode(utf8.encode(jsonEncode(toJson())));

  static ElevatedTaskSpec decode(String encoded) {
    final normalized = base64Url.normalize(encoded);
    final json = jsonDecode(utf8.decode(base64Url.decode(normalized)));
    return ElevatedTaskSpec.fromJson(Map<String, dynamic>.from(json as Map));
  }

  String? validationIssueKey({bool requireIpcToken = false}) {
    final plan = deploymentPlan;
    if (plan == null) return 'deploy_compat_plan_missing';

    final expectedPlatform = switch (kind) {
      ElevatedTaskKind.windowsInstall ||
      ElevatedTaskKind.windowsToGo => DeploymentPlatform.windows,
      ElevatedTaskKind.linuxInstall ||
      ElevatedTaskKind.linuxToGo => DeploymentPlatform.linux,
    };
    final expectedPurpose = switch (kind) {
      ElevatedTaskKind.windowsInstall ||
      ElevatedTaskKind.linuxInstall => DeploymentPurpose.installMedia,
      ElevatedTaskKind.windowsToGo ||
      ElevatedTaskKind.linuxToGo => DeploymentPurpose.toGo,
    };

    if (plan.platform != expectedPlatform || plan.purpose != expectedPurpose) {
      return 'deploy_compat_task_mismatch';
    }
    if (_normalizedPath(plan.imagePath) != _normalizedPath(isoPath)) {
      return 'deploy_compat_image_mismatch';
    }
    if (kind == ElevatedTaskKind.windowsToGo &&
        (imageIndex ?? plan.imageIndex) != plan.imageIndex) {
      return 'deploy_compat_index_mismatch';
    }

    final ipcIssue = _ipcValidationIssue(requireToken: requireIpcToken);
    if (ipcIssue != null) return ipcIssue;

    final compatibility = DeploymentCompatibility.evaluate(plan);
    return compatibility.canDeploy
        ? null
        : compatibility.errors.first.messageKey;
  }

  String? _ipcValidationIssue({required bool requireToken}) {
    final hasPaths =
        progressPath != null || cancelPath != null || resultPath != null;
    final token = ipcToken;
    if (token == null || token.isEmpty) {
      return requireToken && hasPaths ? 'deploy_compat_ipc_missing' : null;
    }
    if (!RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(token)) {
      return 'deploy_compat_ipc_invalid';
    }
    final expected = _ipcPaths(token);
    if (_normalizedPath(progressPath ?? '') !=
            _normalizedPath(expected.progress) ||
        _normalizedPath(cancelPath ?? '') !=
            _normalizedPath(expected.cancel) ||
        _normalizedPath(resultPath ?? '') !=
            _normalizedPath(expected.result)) {
      return 'deploy_compat_ipc_path_mismatch';
    }
    return null;
  }

  static _IpcPaths _ipcPaths(String token) {
    final base = '${Directory.systemTemp.path}\\wds_task_$token';
    return _IpcPaths(
      progress: '$base.progress',
      cancel: '$base.cancel',
      result: '$base.result',
    );
  }

  static String _normalizedPath(String value) => value
      .trim()
      .replaceAll('/', r'\')
      .replaceAll(RegExp(r'\\+'), r'\')
      .toUpperCase();
}

class ElevationService {
  const ElevationService._();

  static Future<bool> runTask(
    ElevatedTaskSpec task, {
    ElevatedTaskProgressCallback? onProgress,
    ElevatedTaskController? controller,
  }) async {
    final appearance = task.appearance ?? await AppAppearanceSettings.load();
    final token = _generateIpcToken();
    final paths = ElevatedTaskSpec._ipcPaths(token);
    final resultFile = File(paths.result);
    final progressFile = File(paths.progress);
    final cancelFile = File(paths.cancel);
    final preparedTask = ElevatedTaskSpec(
      kind: task.kind,
      disk: task.disk,
      isoPath: task.isoPath,
      localeCode: task.localeCode,
      appearance: appearance,
      imageIndex: task.imageIndex,
      deploymentPlan: task.deploymentPlan,
      progressPath: progressFile.path,
      cancelPath: cancelFile.path,
      resultPath: resultFile.path,
      ipcToken: token,
    );
    final executable = Platform.resolvedExecutable;
    final argument = '--elevated-task=${preparedTask.encode()}';
    Timer? progressTimer;
    DateTime? lastProgressModified;
    try {
      controller?._attach(cancelFile.path, token);
      if (onProgress != null) {
        progressTimer = Timer.periodic(const Duration(milliseconds: 250), (_) {
          try {
            if (!progressFile.existsSync()) return;
            final modified = progressFile.lastModifiedSync();
            if (lastProgressModified == modified) return;
            lastProgressModified = modified;
            final decoded = jsonDecode(progressFile.readAsStringSync());
            if (decoded is Map && decoded['ipcToken'] == token) {
              onProgress(
                ElevatedTaskProgress.fromJson(
                  Map<String, dynamic>.from(decoded),
                ),
              );
            }
          } catch (_) {}
        });
      }
      final result = await Process.run(
        'powershell',
        const [
          '-NoProfile',
          '-ExecutionPolicy',
          'Bypass',
          '-Command',
          r'''try {
  $process = Start-Process -FilePath $env:WDS_EXECUTABLE -ArgumentList $env:WDS_TASK_ARGUMENT -Verb RunAs -Wait -PassThru
  exit $process.ExitCode
} catch {
  Write-Error $_
  exit 1223
}''',
        ],
        environment: {
          ...Platform.environment,
          'WDS_EXECUTABLE': executable,
          'WDS_TASK_ARGUMENT': argument,
        },
      );
      if (result.exitCode != 0 || !await resultFile.exists()) return false;
      return (await resultFile.readAsString()).trim() == 'success|$token';
    } finally {
      progressTimer?.cancel();
      controller?._detach();
      try {
        if (await resultFile.exists()) await resultFile.delete();
      } catch (_) {}
      try {
        if (await progressFile.exists()) await progressFile.delete();
      } catch (_) {}
      try {
        if (await cancelFile.exists()) await cancelFile.delete();
      } catch (_) {}
    }
  }

  static Future<bool> isAdministrator() async {
    try {
      final result = await Process.run('net', ['session']);
      return result.exitCode == 0;
    } catch (_) {
      return false;
    }
  }

  static String _generateIpcToken() {
    final random = Random.secure();
    return List<int>.generate(32, (_) => random.nextInt(256))
        .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
        .join();
  }
}

class _IpcPaths {
  final String progress;
  final String cancel;
  final String result;

  const _IpcPaths({
    required this.progress,
    required this.cancel,
    required this.result,
  });
}
