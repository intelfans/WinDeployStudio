import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:win_deploy_studio/core/services/iso_parse_service.dart';

void main() {
  test(
    'a replacement parse waits for cancelled cleanup and cannot revive it',
    () async {
      final firstStarted = Completer<void>();
      final firstCancelled = Completer<void>();
      final releaseFirstCleanup = Completer<void>();
      final secondStarted = Completer<void>();
      var activeWorkers = 0;
      var maximumActiveWorkers = 0;

      final service = IsoParseService(
        worker: (path, {required cancellation, onProgress}) async {
          activeWorkers++;
          maximumActiveWorkers = maximumActiveWorkers < activeWorkers
              ? activeWorkers
              : maximumActiveWorkers;
          try {
            if (path == 'first.iso') {
              firstStarted.complete();
              await cancellation.whenCancelled;
              firstCancelled.complete();
              await releaseFirstCleanup.future;
              return cancellation.isCancelled ? null : _metadata(path);
            }

            secondStarted.complete();
            return _metadata(path);
          } finally {
            activeWorkers--;
          }
        },
      );

      final first = service.parseIso('first.iso');
      await firstStarted.future;
      final second = service.parseIso('second.iso');

      await firstCancelled.future;
      expect(secondStarted.isCompleted, isFalse);
      expect(maximumActiveWorkers, 1);

      releaseFirstCleanup.complete();
      expect(await first, isNull);
      expect((await second)?.filePath, 'second.iso');
      expect(maximumActiveWorkers, 1);
    },
  );

  test('cancel completes only after the active parser has settled', () async {
    final started = Completer<void>();
    final cancelled = Completer<void>();
    final releaseCleanup = Completer<void>();
    var cancelCompleted = false;

    final service = IsoParseService(
      worker: (path, {required cancellation, onProgress}) async {
        started.complete();
        await cancellation.whenCancelled;
        cancelled.complete();
        await releaseCleanup.future;
        return null;
      },
    );

    final parse = service.parseIso('first.iso');
    await started.future;
    final cancel = service.cancel().whenComplete(() => cancelCompleted = true);

    await cancelled.future;
    expect(cancelCompleted, isFalse);

    releaseCleanup.complete();
    await cancel;
    expect(await parse, isNull);
    expect(cancelCompleted, isTrue);
  });

  test('a queued parse cancelled by a later selection never starts', () async {
    final firstStarted = Completer<void>();
    final firstCancelled = Completer<void>();
    final releaseFirstCleanup = Completer<void>();
    final startedPaths = <String>[];

    final service = IsoParseService(
      worker: (path, {required cancellation, onProgress}) async {
        startedPaths.add(path);
        if (path == 'first.iso') {
          firstStarted.complete();
          await cancellation.whenCancelled;
          firstCancelled.complete();
          await releaseFirstCleanup.future;
          return null;
        }
        return _metadata(path);
      },
    );

    final first = service.parseIso('first.iso');
    await firstStarted.future;
    final second = service.parseIso('second.iso');
    final third = service.parseIso('third.iso');

    await firstCancelled.future;
    releaseFirstCleanup.complete();

    expect(await first, isNull);
    expect(await second, isNull);
    expect((await third)?.filePath, 'third.iso');
    expect(startedPaths, <String>['first.iso', 'third.iso']);
  });
}

IsoMetadata _metadata(String path) => IsoMetadata(
  filePath: path,
  fileName: path,
  fileSize: 1,
  isValidWindowsIso: true,
);
