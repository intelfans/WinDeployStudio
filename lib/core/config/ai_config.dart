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
    final normalized = normalizeProxyUrl(saved ?? '');
    return normalized.isNotEmpty ? normalized : defaultProxyUrl;
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
    if (!normalized.startsWith('http://') &&
        !normalized.startsWith('https://')) {
      normalized = 'https://$normalized';
    }
    if (!normalized.endsWith('/')) normalized = '$normalized/';
    return normalized;
  }

  static bool isValidProxyUrl(String value) {
    final uri = Uri.tryParse(value);
    if (uri == null) return false;
    if (uri.scheme != 'http' && uri.scheme != 'https') return false;
    return uri.host.isNotEmpty;
  }
}
