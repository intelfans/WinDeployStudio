import 'dart:async';

import 'package:shared_preferences/shared_preferences.dart';

/// Caps how many searches may be sent to the bundled gateway per hour.
///
/// The gateway holds the search provider credential, so every gateway search is
/// billed to the application rather than to the user. This budget bounds that
/// cost: once the allowance is gone the client stops asking the gateway and
/// falls back to the keyless sources it already ships with, which keep working
/// at no cost.
///
/// The allowance is deliberately per installation. It is a cost guard for the
/// operator, not a licence enforcement mechanism; the gateway is still the
/// place to add a hard server-side limit if the billing risk grows.
class AiSearchBudget {
  AiSearchBudget._();

  /// Gateway searches allowed in one rolling window.
  static const int maxPerWindow = 10;

  /// The window is rolling, not aligned to the clock: a search from 50 minutes
  /// ago still occupies a slot until it ages out.
  static const Duration window = Duration(hours: 1);

  static const String _prefKey = 'ai_gateway_search_at_v1';

  /// Serialises read-modify-write cycles so two concurrent searches cannot
  /// both consume the last slot.
  static Future<void> _tail = Future<void>.value();

  static Future<T> _serialize<T>(Future<T> Function() action) {
    final completer = Completer<T>();
    _tail = _tail.then((_) async {
      try {
        completer.complete(await action());
      } catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      }
    });
    return completer.future;
  }

  /// Timestamps still inside the window, with expired ones dropped.
  static Future<List<int>> _activeTimestamps(DateTime now) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_prefKey) ?? const <String>[];
    final cutoff = now.subtract(window).millisecondsSinceEpoch;
    final kept = <int>[];
    for (final entry in raw) {
      final value = int.tryParse(entry.trim());
      if (value != null && value > cutoff) kept.add(value);
    }
    return kept;
  }

  static Future<void> _write(List<int> timestamps) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      _prefKey,
      timestamps.map((value) => '$value').toList(growable: false),
    );
  }

  /// Whether a gateway search would still be inside the allowance.
  static Future<bool> hasCapacity({DateTime? now}) {
    return _serialize(() async {
      final clock = now ?? DateTime.now();
      final active = await _activeTimestamps(clock);
      return active.length < maxPerWindow;
    });
  }

  /// Claims one slot. Returns false when the allowance is exhausted.
  static Future<bool> tryConsume({DateTime? now}) {
    return _serialize(() async {
      final clock = now ?? DateTime.now();
      final active = await _activeTimestamps(clock);
      if (active.length >= maxPerWindow) {
        // Persist the pruned list so the stored data does not grow forever.
        await _write(active);
        return false;
      }
      active.add(clock.millisecondsSinceEpoch);
      active.sort();
      await _write(active);
      return true;
    });
  }

  /// Releases the most recent claim.
  ///
  /// Used only when the gateway answered that it never reached the provider
  /// (the search route is missing or unconfigured), so the request cost the
  /// operator nothing and must not count against the user.
  static Future<void> refund({DateTime? now}) {
    return _serialize(() async {
      final active = await _activeTimestamps(now ?? DateTime.now());
      if (active.isEmpty) return;
      active.removeAt(active.length - 1);
      await _write(active);
    });
  }

  /// Slots left in the current window. Exposed for UI and tests.
  static Future<int> remaining({DateTime? now}) {
    return _serialize(() async {
      final clock = now ?? DateTime.now();
      final active = await _activeTimestamps(clock);
      final left = maxPerWindow - active.length;
      return left < 0 ? 0 : left;
    });
  }

  /// Clears the allowance. Used by tests and by the settings reset.
  static Future<void> reset() {
    return _serialize(() async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_prefKey);
    });
  }
}
