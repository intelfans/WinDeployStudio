import 'package:shared_preferences/shared_preferences.dart';

class AiConfig {
  AiConfig._();

  static const defaultProxyUrl =
      'https://windeploystudio.bob-0910.workers.dev/';
  static const requestTimeout = Duration(seconds: 30);
  static const streamIdleTimeout = Duration(seconds: 60);

  static const _prefKeyProxyUrl = 'ai_proxy_url';

  static Future<String> getProxyUrl() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_prefKeyProxyUrl);
    if (saved == null || saved.trim().isEmpty) return defaultProxyUrl;

    final normalized = normalizeProxyUrl(saved);
    if (!isValidProxyUrl(normalized)) {
      await prefs.remove(_prefKeyProxyUrl);
      return defaultProxyUrl;
    }
    if (normalized != saved) {
      await prefs.setString(_prefKeyProxyUrl, normalized);
    }
    return normalized;
  }

  static Future<void> setProxyUrl(String value) async {
    final prefs = await SharedPreferences.getInstance();
    final normalized = normalizeProxyUrl(value);
    if (normalized.isEmpty || normalized == defaultProxyUrl) {
      await prefs.remove(_prefKeyProxyUrl);
      return;
    }
    if (!isValidProxyUrl(normalized)) {
      throw const FormatException('Invalid AI proxy URL');
    }
    await prefs.setString(_prefKeyProxyUrl, normalized);
  }

  static Future<void> resetProxyUrl() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefKeyProxyUrl);
  }

  static String normalizeProxyUrl(String value) {
    var normalized = value.trim();
    if (normalized.isEmpty) return '';

    final hasScheme = RegExp(
      r'^[a-zA-Z][a-zA-Z0-9+.-]*://',
    ).hasMatch(normalized);
    if (!hasScheme) {
      normalized = 'https://$normalized';
    }

    final uri = Uri.tryParse(normalized);
    if (uri == null || uri.scheme.toLowerCase() != 'https') {
      return normalized;
    }
    final path = uri.path.endsWith('/') ? uri.path : '${uri.path}/';
    return uri.replace(scheme: 'https', path: path).toString();
  }

  static bool isValidProxyUrl(String value) {
    final uri = Uri.tryParse(value);
    if (uri == null) return false;
    if (uri.scheme.toLowerCase() != 'https') return false;
    return uri.host.isNotEmpty &&
        uri.userInfo.isEmpty &&
        uri.query.isEmpty &&
        uri.fragment.isEmpty;
  }
}
