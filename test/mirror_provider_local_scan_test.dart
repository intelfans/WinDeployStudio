import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:win_deploy_studio/features/mirror/providers/mirror_provider.dart';

void main() {
  late Directory temporaryDirectory;

  setUp(() async {
    temporaryDirectory = await Directory.systemTemp.createTemp(
      'win_deploy_studio_mirror_scan_',
    );
  });

  tearDown(() async {
    if (await temporaryDirectory.exists()) {
      await temporaryDirectory.delete(recursive: true);
    }
  });

  Future<File> createFile(String relativePath, List<int> bytes) async {
    final file = File(
      '${temporaryDirectory.path}${Platform.pathSeparator}$relativePath',
    );
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes);
    return file;
  }

  test('indexes ISO files recursively with stable ordering', () async {
    final first = await createFile('a.iso', <int>[1, 2]);
    final second = await createFile(
      'nested${Platform.pathSeparator}B.ISO',
      <int>[1, 2, 3],
    );
    await createFile('nested${Platform.pathSeparator}not-an-image.txt', <int>[
      1,
    ]);

    final notifier = MirrorNotifier();
    addTearDown(notifier.dispose);

    await notifier.scanLocalDirectory(temporaryDirectory.path);

    expect(notifier.state.localIsos.map((iso) => iso.filePath), <String>[
      first.path,
      second.path,
    ]);
    expect(notifier.state.localIsos.map((iso) => iso.fileSize), <int>[2, 3]);
  });

  test(
    'a newer scan prevents an older scan from replacing its results',
    () async {
      final firstDirectory = Directory(
        '${temporaryDirectory.path}${Platform.pathSeparator}first',
      );
      final secondDirectory = Directory(
        '${temporaryDirectory.path}${Platform.pathSeparator}second',
      );
      await firstDirectory.create();
      await secondDirectory.create();
      final firstImage = File(
        '${firstDirectory.path}${Platform.pathSeparator}first.iso',
      );
      final secondImage = File(
        '${secondDirectory.path}${Platform.pathSeparator}second.iso',
      );
      await firstImage.writeAsBytes(<int>[1]);
      await secondImage.writeAsBytes(<int>[2]);

      final firstScanGate = Completer<void>();
      final notifier = MirrorNotifier.withLocalIsoScanHook((path) {
        return path == firstDirectory.path
            ? firstScanGate.future
            : Future<void>.value();
      });
      addTearDown(notifier.dispose);

      final staleScan = notifier.scanLocalDirectory(firstDirectory.path);
      await Future<void>.delayed(Duration.zero);
      await notifier.scanLocalDirectory(secondDirectory.path);
      firstScanGate.complete();
      await staleScan;

      expect(notifier.state.localIsos, hasLength(1));
      expect(notifier.state.localIsos.single.filePath, secondImage.path);
    },
  );

  test('clearing the local library cancels a pending scan', () async {
    final image = await createFile('pending.iso', <int>[1]);
    final scanGate = Completer<void>();
    final notifier = MirrorNotifier.withLocalIsoScanHook(
      (_) => scanGate.future,
    );
    addTearDown(notifier.dispose);

    final scan = notifier.scanLocalDirectory(temporaryDirectory.path);
    await Future<void>.delayed(Duration.zero);
    notifier.clearLocalIsos();
    scanGate.complete();
    await scan;

    expect(image.existsSync(), isTrue);
    expect(notifier.state.localIsos, isEmpty);
  });

  test('limits the local library result set', () async {
    for (
      var index = 0;
      index < MirrorNotifier.maxLocalIsoResults + 2;
      index++
    ) {
      await createFile('image_$index.iso', <int>[index % 256]);
    }

    final notifier = MirrorNotifier();
    addTearDown(notifier.dispose);

    await notifier.scanLocalDirectory(temporaryDirectory.path);

    expect(
      notifier.state.localIsos,
      hasLength(MirrorNotifier.maxLocalIsoResults),
    );
  });

  test('does not follow ISO file links when links are available', () async {
    final externalDirectory = await Directory.systemTemp.createTemp(
      'win_deploy_studio_mirror_link_target_',
    );
    addTearDown(() async {
      if (await externalDirectory.exists()) {
        await externalDirectory.delete(recursive: true);
      }
    });
    final externalImage = File(
      '${externalDirectory.path}${Platform.pathSeparator}external.iso',
    );
    await externalImage.writeAsBytes(<int>[1, 2, 3]);
    final linkedImage = Link(
      '${temporaryDirectory.path}${Platform.pathSeparator}linked.iso',
    );

    try {
      await linkedImage.create(externalImage.path);
    } on FileSystemException {
      // Some Windows test hosts do not permit symlink creation. The behavior
      // is still covered by the explicit followLinks: false production path.
      return;
    }

    final notifier = MirrorNotifier();
    addTearDown(notifier.dispose);

    await notifier.scanLocalDirectory(temporaryDirectory.path);

    expect(notifier.state.localIsos, isEmpty);
  });
}
