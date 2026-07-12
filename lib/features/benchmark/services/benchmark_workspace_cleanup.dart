import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

const benchmarkWorkspacePrefix = '.wds_benchmark_';
const benchmarkWorkspaceMarkerName = '.wds_benchmark_owner';
const benchmarkWorkspaceMarkerSchema =
    'win-deploy-studio/benchmark-workspace-owner';

typedef BenchmarkProcessAlive = Future<bool> Function(int processId);
typedef BenchmarkEntityDeleter = Future<void> Function(FileSystemEntity entity);

class BenchmarkWorkspaceOwner {
  final String token;
  final int parentPid;
  final DateTime createdAt;

  const BenchmarkWorkspaceOwner({
    required this.token,
    required this.parentPid,
    required this.createdAt,
  });

  Map<String, dynamic> toJson() => {
    'schema': benchmarkWorkspaceMarkerSchema,
    'token': token,
    'parentPid': parentPid,
    'createdAt': createdAt.toUtc().toIso8601String(),
  };

  factory BenchmarkWorkspaceOwner.fromJson(Map<String, dynamic> json) {
    if (json['schema'] != benchmarkWorkspaceMarkerSchema) {
      throw const FormatException('Unsupported benchmark owner marker');
    }
    final token = json['token']?.toString() ?? '';
    final parentPid = json['parentPid'] is num
        ? (json['parentPid'] as num).toInt()
        : int.tryParse(json['parentPid']?.toString() ?? '') ?? 0;
    final createdAt = DateTime.tryParse(json['createdAt']?.toString() ?? '');
    if (!_validOwnerToken(token) || parentPid <= 0 || createdAt == null) {
      throw const FormatException('Invalid benchmark owner marker');
    }
    return BenchmarkWorkspaceOwner(
      token: token,
      parentPid: parentPid,
      createdAt: createdAt,
    );
  }
}

class BenchmarkRecoveryReport {
  final int recovered;
  final int active;
  final List<String> failedPaths;

  const BenchmarkRecoveryReport({
    required this.recovered,
    required this.active,
    required this.failedPaths,
  });

  bool get succeeded => failedPaths.isEmpty;
}

class BenchmarkWorkspaceCleaner {
  final Directory volumeRoot;
  final BenchmarkProcessAlive isProcessAlive;
  final BenchmarkEntityDeleter _deleteEntity;
  final List<Duration> retryDelays;

  BenchmarkWorkspaceCleaner({
    required this.volumeRoot,
    required this.isProcessAlive,
    BenchmarkEntityDeleter? deleteEntity,
    this.retryDelays = const [
      Duration.zero,
      Duration(milliseconds: 250),
      Duration(milliseconds: 500),
      Duration(seconds: 1),
      Duration(seconds: 2),
    ],
  }) : _deleteEntity = deleteEntity ?? _defaultDelete;

  Future<File> writeMarker(
    Directory workspace,
    BenchmarkWorkspaceOwner owner,
  ) async {
    if (!_isOwnedWorkspacePath(workspace, expectedToken: owner.token)) {
      throw ArgumentError.value(workspace.path, 'workspace');
    }
    await workspace.create();
    final marker = File(p.join(workspace.path, benchmarkWorkspaceMarkerName));
    await marker.writeAsString(jsonEncode(owner.toJson()), flush: true);
    return marker;
  }

  Future<BenchmarkRecoveryReport> recoverStaleWorkspaces() async {
    if (!await volumeRoot.exists()) {
      return const BenchmarkRecoveryReport(
        recovered: 0,
        active: 0,
        failedPaths: [],
      );
    }
    var recovered = 0;
    var active = 0;
    final failed = <String>[];
    await for (final entity in volumeRoot.list(followLinks: false)) {
      if (entity is! Directory || !_isOwnedWorkspacePath(entity)) continue;
      final owner = await readOwner(entity);
      if (owner == null ||
          !_isOwnedWorkspacePath(entity, expectedToken: owner.token)) {
        continue;
      }
      if (await isProcessAlive(owner.parentPid)) {
        active++;
        continue;
      }
      if (await cleanupOwnedWorkspace(entity, owner.token)) {
        recovered++;
      } else {
        failed.add(entity.path);
      }
    }
    return BenchmarkRecoveryReport(
      recovered: recovered,
      active: active,
      failedPaths: List.unmodifiable(failed),
    );
  }

  Future<BenchmarkWorkspaceOwner?> readOwner(Directory workspace) async {
    if (!_isOwnedWorkspacePath(workspace)) return null;
    final marker = File(p.join(workspace.path, benchmarkWorkspaceMarkerName));
    try {
      final decoded = jsonDecode(await marker.readAsString());
      if (decoded is! Map) return null;
      return BenchmarkWorkspaceOwner.fromJson(
        Map<String, dynamic>.from(decoded),
      );
    } catch (_) {
      return null;
    }
  }

  Future<bool> cleanupOwnedWorkspace(
    Directory workspace,
    String expectedToken,
  ) async {
    if (!_validOwnerToken(expectedToken) ||
        !_isOwnedWorkspacePath(workspace, expectedToken: expectedToken)) {
      return false;
    }
    if (!await workspace.exists()) return true;
    final owner = await readOwner(workspace);
    if (owner == null || owner.token != expectedToken) return false;

    for (final delay in retryDelays) {
      if (delay > Duration.zero) await Future<void>.delayed(delay);
      if (!await workspace.exists()) return true;
      final payloadDeleted = await _deletePayload(workspace);
      if (!payloadDeleted) continue;

      final marker = File(p.join(workspace.path, benchmarkWorkspaceMarkerName));
      try {
        if (await marker.exists()) await _deleteEntity(marker);
      } catch (_) {
        continue;
      }
      if (await marker.exists()) continue;
      try {
        await _deleteEntity(workspace);
      } catch (_) {}
      if (!await workspace.exists()) return true;
    }
    return false;
  }

  Future<bool> _deletePayload(Directory workspace) async {
    try {
      final entities = await workspace.list(followLinks: false).toList();
      for (final entity in entities) {
        if (p.basename(entity.path) == benchmarkWorkspaceMarkerName) continue;
        try {
          await _deleteEntity(entity);
        } catch (_) {
          return false;
        }
      }
      final remaining = await workspace.list(followLinks: false).toList();
      return remaining.every(
        (entity) => p.basename(entity.path) == benchmarkWorkspaceMarkerName,
      );
    } catch (_) {
      return false;
    }
  }

  bool _isOwnedWorkspacePath(Directory workspace, {String? expectedToken}) {
    final root = p.canonicalize(volumeRoot.absolute.path);
    final candidate = p.canonicalize(workspace.absolute.path);
    if (!p.isWithin(root, candidate)) return false;
    final name = p.basename(candidate);
    if (!name.startsWith(benchmarkWorkspacePrefix)) return false;
    if (expectedToken == null) return true;
    return name == '$benchmarkWorkspacePrefix$expectedToken';
  }

  static Future<void> _defaultDelete(FileSystemEntity entity) =>
      entity.delete(recursive: entity is Directory);
}

bool _validOwnerToken(String value) =>
    RegExp(r'^[A-Za-z0-9_-]{8,160}$').hasMatch(value);
