import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:win_deploy_studio/features/benchmark/services/benchmark_workspace_cleanup.dart';

void main() {
  late Directory volumeRoot;

  setUp(() async {
    volumeRoot = await Directory.systemTemp.createTemp(
      'wds_benchmark_cleanup_test_',
    );
  });

  tearDown(() async {
    if (await volumeRoot.exists()) {
      await volumeRoot.delete(recursive: true);
    }
  });

  test('deletes the owner marker only after all payload is gone', () async {
    const token = 'owner_delete_1234';
    final workspace = Directory(
      p.join(volumeRoot.path, '$benchmarkWorkspacePrefix$token'),
    );
    final deleted = <String>[];
    final cleaner = BenchmarkWorkspaceCleaner(
      volumeRoot: volumeRoot,
      isProcessAlive: (_) async => false,
      retryDelays: const [Duration.zero],
      deleteEntity: (entity) async {
        deleted.add(p.basename(entity.path));
        await entity.delete(recursive: entity is Directory);
      },
    );
    await cleaner.writeMarker(workspace, _owner(token, 100));
    await File(p.join(workspace.path, 'random.bin')).writeAsString('payload');
    final nested = Directory(p.join(workspace.path, 'full_write'));
    await nested.create();
    await File(p.join(nested.path, 'available-space.bin')).writeAsString('x');

    expect(await cleaner.cleanupOwnedWorkspace(workspace, token), isTrue);
    expect(await workspace.exists(), isFalse);
    expect(await cleaner.cleanupOwnedWorkspace(workspace, token), isTrue);
    expect(
      deleted.indexOf(benchmarkWorkspaceMarkerName),
      greaterThan(deleted.indexOf('random.bin')),
    );
    expect(
      deleted.indexOf(benchmarkWorkspaceMarkerName),
      greaterThan(deleted.indexOf('full_write')),
    );
  });

  test('keeps the owner marker when a payload cannot be deleted', () async {
    const token = 'owner_locked_1234';
    final workspace = Directory(
      p.join(volumeRoot.path, '$benchmarkWorkspacePrefix$token'),
    );
    final cleaner = BenchmarkWorkspaceCleaner(
      volumeRoot: volumeRoot,
      isProcessAlive: (_) async => false,
      retryDelays: const [Duration.zero],
      deleteEntity: (entity) async {
        if (p.basename(entity.path) == 'locked.bin') {
          throw const FileSystemException('locked');
        }
        await entity.delete(recursive: entity is Directory);
      },
    );
    await cleaner.writeMarker(workspace, _owner(token, 100));
    await File(p.join(workspace.path, 'locked.bin')).writeAsString('payload');

    expect(await cleaner.cleanupOwnedWorkspace(workspace, token), isFalse);
    expect(
      await File(p.join(workspace.path, benchmarkWorkspaceMarkerName)).exists(),
      isTrue,
    );
    expect(await File(p.join(workspace.path, 'locked.bin')).exists(), isTrue);
  });

  test(
    'startup recovery removes stale workspaces and skips live owners',
    () async {
      const staleToken = 'owner_stale_1234';
      const activeToken = 'owner_active_1234';
      final cleaner = BenchmarkWorkspaceCleaner(
        volumeRoot: volumeRoot,
        isProcessAlive: (processId) async => processId == 200,
        retryDelays: const [Duration.zero],
      );
      final stale = Directory(
        p.join(volumeRoot.path, '$benchmarkWorkspacePrefix$staleToken'),
      );
      final active = Directory(
        p.join(volumeRoot.path, '$benchmarkWorkspacePrefix$activeToken'),
      );
      await cleaner.writeMarker(stale, _owner(staleToken, 100));
      await cleaner.writeMarker(active, _owner(activeToken, 200));
      await File(p.join(stale.path, 'sequential.bin')).writeAsString('stale');
      await File(p.join(active.path, 'random.bin')).writeAsString('active');

      final report = await cleaner.recoverStaleWorkspaces();

      expect(report.recovered, 1);
      expect(report.active, 1);
      expect(report.succeeded, isTrue);
      expect(await stale.exists(), isFalse);
      expect(await active.exists(), isTrue);
    },
  );

  test(
    'recovery never deletes a prefixed directory without a valid marker',
    () async {
      final unowned = Directory(
        p.join(volumeRoot.path, '${benchmarkWorkspacePrefix}not_owned_1234'),
      );
      await unowned.create();
      await File(p.join(unowned.path, 'keep.bin')).writeAsString('keep');
      final cleaner = BenchmarkWorkspaceCleaner(
        volumeRoot: volumeRoot,
        isProcessAlive: (_) async => false,
        retryDelays: const [Duration.zero],
      );

      final report = await cleaner.recoverStaleWorkspaces();

      expect(report.recovered, 0);
      expect(await unowned.exists(), isTrue);
    },
  );
}

BenchmarkWorkspaceOwner _owner(String token, int parentPid) {
  return BenchmarkWorkspaceOwner(
    token: token,
    parentPid: parentPid,
    createdAt: DateTime.utc(2026, 7, 12),
  );
}
