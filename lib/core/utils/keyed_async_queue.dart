import 'dart:async';

/// Serializes asynchronous work for the same key while allowing different
/// keys to proceed independently.
class KeyedAsyncQueue<K> {
  final Map<K, Future<void>> _tails = {};

  Future<T> run<T>(K key, Future<T> Function() operation) {
    final previous = _tails[key] ?? Future<void>.value();
    final result = Completer<T>();
    late final Future<void> tail;
    tail = previous.catchError((_) {}).then((_) async {
      try {
        result.complete(await operation());
      } catch (error, stackTrace) {
        result.completeError(error, stackTrace);
      }
    });
    _tails[key] = tail;
    unawaited(
      tail.whenComplete(() {
        if (identical(_tails[key], tail)) _tails.remove(key);
      }),
    );
    return result.future;
  }
}
