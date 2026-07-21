import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:win_deploy_studio/core/utils/keyed_async_queue.dart';

void main() {
  test('serializes operations that use the same key', () async {
    final queue = KeyedAsyncQueue<String>();
    final releaseFirst = Completer<void>();
    final events = <String>[];

    final first = queue.run('session', () async {
      events.add('first-start');
      await releaseFirst.future;
      events.add('first-end');
      return 1;
    });
    final second = queue.run('session', () async {
      events.add('second');
      return 2;
    });

    await Future<void>.delayed(Duration.zero);
    expect(events, ['first-start']);
    releaseFirst.complete();
    expect(await Future.wait([first, second]), [1, 2]);
    expect(events, ['first-start', 'first-end', 'second']);
  });

  test('allows different keys to proceed independently', () async {
    final queue = KeyedAsyncQueue<String>();
    final releaseFirst = Completer<void>();
    var secondStarted = false;

    final first = queue.run('first', () async {
      await releaseFirst.future;
    });
    final second = queue.run('second', () async {
      secondStarted = true;
    });

    await second;
    expect(secondStarted, isTrue);
    releaseFirst.complete();
    await first;
  });

  test('a failed operation does not block the next operation', () async {
    final queue = KeyedAsyncQueue<String>();
    final failed = queue.run<void>('session', () async {
      throw StateError('expected');
    });
    final next = queue.run('session', () async => 'saved');

    await expectLater(failed, throwsStateError);
    expect(await next, 'saved');
  });
}
