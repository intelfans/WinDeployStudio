import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

/// A random, persistent identifier for this installation.
///
/// Sent only with gateway search requests so the server can apply a per-install
/// allowance. It carries no user information, is not derived from the machine,
/// and is regenerated only if the stored value is missing or malformed.
///
/// It deliberately lives in the same preferences store as the rest of the app,
/// so a user who already cleared app data gets a fresh identity. The server-side
/// global daily cap is the backstop that does not depend on this value.
class AiInstallId {
  AiInstallId._();

  static const String _prefKey = 'ai_install_id_v1';
  static const Uuid _uuid = Uuid();

  static Future<String>? _cached;

  /// Returns the installation id, creating one on first use.
  static Future<String> get() {
    return _cached ??= _load();
  }

  static Future<String> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final stored = prefs.getString(_prefKey)?.trim();
      if (stored != null && _isWellFormed(stored)) return stored;
      final generated = _uuid.v4();
      await prefs.setString(_prefKey, generated);
      return generated;
    } catch (_) {
      // A preferences failure must not break search; an in-memory id still
      // lets the server apply a per-process allowance.
      return _uuid.v4();
    }
  }

  static bool _isWellFormed(String value) {
    if (value.length < 8 || value.length > 64) return false;
    return RegExp(r'^[0-9a-fA-F-]+$').hasMatch(value);
  }

  /// Forgets the cached value. Used by tests.
  static void resetForTesting() {
    _cached = null;
  }
}
