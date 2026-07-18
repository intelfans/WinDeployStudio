import 'dart:io';

import 'package:shared_preferences/shared_preferences.dart';

import '../services/user_data_protection_service.dart';

class AiConfig {
  AiConfig._();

  static const defaultEndpointUrl =
      'https://windeploystudio.bob-0910.workers.dev/';

  static const defaultModel = 'mimo-v2.5-pro';
  static const maxModelListResponseBytes = 2 * 1024 * 1024;
  static const connectionTimeout = Duration(seconds: 15);
  static const requestTimeout = Duration(seconds: 30);
  static const streamIdleTimeout = Duration(seconds: 60);
  static const errorResponseTimeout = Duration(seconds: 10);
  static const transientRetryDelay = Duration(milliseconds: 450);

  static const _prefKeyEndpointUrl = 'ai_endpoint_url';
  static const _legacyPrefKeyEndpointUrl = 'ai_proxy_url';
  static const _prefKeyApiKey = 'ai_api_key_protected';
  static const _prefKeyApiKeyEndpoint = 'ai_api_key_endpoint';
  static const _prefKeyModel = 'ai_model';
  static const _prefKeyModelEndpoint = 'ai_model_endpoint';
  static const _protectedValuePrefix = 'dpapi:v1:';

  static Future<String> getEndpointUrl() async {
    final prefs = await SharedPreferences.getInstance();
    final saved =
        prefs.getString(_prefKeyEndpointUrl) ??
        prefs.getString(_legacyPrefKeyEndpointUrl);
    if (saved == null || saved.trim().isEmpty) return defaultEndpointUrl;

    final normalized = normalizeEndpointUrl(saved);
    if (!isValidEndpointUrl(normalized)) {
      await clearApiKey();
      await clearModel();
      await prefs.remove(_prefKeyEndpointUrl);
      await prefs.remove(_legacyPrefKeyEndpointUrl);
      return defaultEndpointUrl;
    }
    if (normalized != saved || prefs.containsKey(_legacyPrefKeyEndpointUrl)) {
      await prefs.setString(_prefKeyEndpointUrl, normalized);
      await prefs.remove(_legacyPrefKeyEndpointUrl);
    }
    return normalized;
  }

  static Future<void> setEndpointUrl(String value) async {
    final prefs = await SharedPreferences.getInstance();
    final normalized = normalizeEndpointUrl(value);
    if (normalized.isEmpty || normalized == defaultEndpointUrl) {
      final current = await getEndpointUrl();
      if (current != defaultEndpointUrl) {
        await clearApiKey();
        await clearModel();
      }
      await prefs.remove(_prefKeyEndpointUrl);
      await prefs.remove(_legacyPrefKeyEndpointUrl);
      return;
    }
    if (!isValidEndpointUrl(normalized)) {
      throw const FormatException('Invalid AI service endpoint URL');
    }
    final current = await getEndpointUrl();
    if (current != normalized) {
      await clearApiKey();
      await clearModel();
    }
    await prefs.setString(_prefKeyEndpointUrl, normalized);
    await prefs.remove(_legacyPrefKeyEndpointUrl);
  }

  static Future<void> resetEndpointUrl() async {
    final prefs = await SharedPreferences.getInstance();
    await clearApiKey();
    await clearModel();
    await prefs.remove(_prefKeyEndpointUrl);
    await prefs.remove(_legacyPrefKeyEndpointUrl);
  }

  /// Returns the API key after decrypting it with the current Windows user
  /// profile. Invalid or legacy-unreadable values are removed silently so a
  /// corrupt preference never reaches the HTTP layer or an error message.
  static Future<String?> getApiKey({String? endpointUrl}) async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(_prefKeyApiKey);
    if (stored == null || stored.trim().isEmpty) return null;
    final targetEndpoint = normalizeEndpointUrl(
      endpointUrl ?? await getEndpointUrl(),
    );
    final boundEndpoint = prefs.getString(_prefKeyApiKeyEndpoint);

    try {
      if (!stored.startsWith(_protectedValuePrefix)) {
        // Migrate a key written by an early development build without ever
        // leaving it in plaintext after this call.
        if (!Platform.isWindows ||
            !shouldSendApiKey(targetEndpoint) ||
            !isValidApiKey(stored)) {
          await clearApiKey();
          return null;
        }
        final protectedValue = await UserDataProtectionService.protect(
          stored.trim(),
        );
        await prefs.setString(
          _prefKeyApiKey,
          '$_protectedValuePrefix$protectedValue',
        );
        await prefs.setString(_prefKeyApiKeyEndpoint, targetEndpoint);
        return stored.trim();
      }

      if (boundEndpoint == null ||
          normalizeEndpointUrl(boundEndpoint) != targetEndpoint) {
        return null;
      }
      final plaintext = await UserDataProtectionService.unprotect(
        stored.substring(_protectedValuePrefix.length),
      );
      if (!isValidApiKey(plaintext)) {
        await clearApiKey();
        return null;
      }
      return plaintext;
    } catch (_) {
      await clearApiKey();
      return null;
    }
  }

  static Future<void> setApiKey(String value) async {
    final normalized = value.trim();
    final prefs = await SharedPreferences.getInstance();
    if (normalized.isEmpty) {
      await clearApiKey();
      return;
    }
    if (!isValidApiKey(normalized)) {
      throw const FormatException('Invalid AI API key');
    }
    if (!Platform.isWindows) {
      throw UnsupportedError('API key protection requires Windows.');
    }
    final endpoint = await getEndpointUrl();
    if (!shouldSendApiKey(endpoint)) {
      throw StateError('A user-configured endpoint is required.');
    }
    final protectedValue = await UserDataProtectionService.protect(normalized);
    await prefs.setString(
      _prefKeyApiKey,
      '$_protectedValuePrefix$protectedValue',
    );
    await prefs.setString(_prefKeyApiKeyEndpoint, endpoint);
  }

  static Future<void> clearApiKey() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefKeyApiKey);
    await prefs.remove(_prefKeyApiKeyEndpoint);
  }

  static bool isValidApiKey(String value) {
    final normalized = value.trim();
    if (normalized.isEmpty || normalized.length > 4096) return false;
    return !normalized.contains(RegExp(r'[\s\x00-\x1F\x7F]'));
  }

  /// Returns the model selected for the active endpoint only. A model ID is
  /// provider-specific, so an old selection must never cross to a newly
  /// chosen endpoint.
  static Future<String> getModel({String? endpointUrl}) async {
    final prefs = await SharedPreferences.getInstance();
    final endpoint = normalizeEndpointUrl(
      endpointUrl ?? await getEndpointUrl(),
    );
    final saved = prefs.getString(_prefKeyModel)?.trim();
    if (saved == null || !isValidModelId(saved)) {
      if (saved != null) await clearModel();
      return endpoint == defaultEndpointUrl ? defaultModel : '';
    }
    final boundEndpoint = prefs.getString(_prefKeyModelEndpoint);
    if (boundEndpoint == null ||
        normalizeEndpointUrl(boundEndpoint) != endpoint) {
      await clearModel();
      return endpoint == defaultEndpointUrl ? defaultModel : '';
    }
    return saved;
  }

  static Future<void> setModel(String value, {String? endpointUrl}) async {
    final normalized = value.trim();
    if (normalized.isEmpty) {
      await clearModel();
      return;
    }
    if (!isValidModelId(normalized)) {
      throw const FormatException('Invalid AI model ID');
    }
    final prefs = await SharedPreferences.getInstance();
    final endpoint = normalizeEndpointUrl(
      endpointUrl ?? await getEndpointUrl(),
    );
    if (normalized == defaultModel && endpoint == defaultEndpointUrl) {
      await clearModel();
    } else {
      await prefs.setString(_prefKeyModel, normalized);
      await prefs.setString(_prefKeyModelEndpoint, endpoint);
    }
  }

  static Future<void> clearModel() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefKeyModel);
    await prefs.remove(_prefKeyModelEndpoint);
  }

  static bool isValidModelId(String value) {
    final normalized = value.trim();
    if (normalized.isEmpty || normalized.length > 256) return false;
    return !normalized.contains(RegExp(r'[\x00-\x1F\x7F]'));
  }

  /// Keys belong to the endpoint the user explicitly configured. The built-in
  /// service is deliberately never sent a user-provided credential.
  static bool shouldSendApiKey(String endpointUrl) =>
      normalizeEndpointUrl(endpointUrl) != defaultEndpointUrl;

  static String normalizeEndpointUrl(String value) {
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

  static bool isValidEndpointUrl(String value) {
    final uri = Uri.tryParse(value);
    if (uri == null) return false;
    if (uri.scheme.toLowerCase() != 'https') return false;
    return uri.host.isNotEmpty &&
        uri.userInfo.isEmpty &&
        uri.query.isEmpty &&
        uri.fragment.isEmpty;
  }

  /// Builds the fixed OpenAI-compatible chat route without manual string
  /// concatenation, so custom endpoints such as `/v1/` remain valid.
  static Uri chatCompletionsUri(String endpointUrl) {
    final endpoint = Uri.parse(endpointUrl);
    final path = endpoint.path.endsWith('/')
        ? endpoint.path.substring(0, endpoint.path.length - 1)
        : endpoint.path;
    if (path.endsWith('/chat/completions')) return endpoint;
    return endpoint.resolve('chat/completions');
  }

  /// Builds the OpenAI-compatible Responses route. Many compatible providers
  /// expose only Chat Completions, so callers must safely fall back when the
  /// endpoint or selected model does not support Responses.
  static Uri responsesUri(String endpointUrl) {
    final endpoint = Uri.parse(endpointUrl);
    final path = endpoint.path.endsWith('/')
        ? endpoint.path.substring(0, endpoint.path.length - 1)
        : endpoint.path;
    const chatSuffix = '/chat/completions';
    if (path.endsWith('/responses')) return endpoint;
    if (path.endsWith(chatSuffix)) {
      final basePath = path.substring(0, path.length - chatSuffix.length);
      return endpoint.replace(
        path: '${basePath.isEmpty ? '' : basePath}/responses',
      );
    }
    return endpoint.resolve('responses');
  }

  static Uri modelsUri(String endpointUrl) {
    final endpoint = Uri.parse(endpointUrl);
    final path = endpoint.path;
    if (path.endsWith('/models')) return endpoint;
    const chatSuffix = '/chat/completions';
    if (path.endsWith(chatSuffix)) {
      final basePath = path.substring(0, path.length - chatSuffix.length);
      return endpoint.replace(
        path: '${basePath.isEmpty ? '' : basePath}/models',
      );
    }
    return endpoint.resolve('models');
  }
}
