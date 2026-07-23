import 'dart:io';

import 'package:shared_preferences/shared_preferences.dart';

import '../services/user_data_protection_service.dart';

class AiConfig {
  AiConfig._();

  static const defaultEndpointUrl = 'https://ai.xueyanzhang.top/';

  // These were built-in endpoints in released builds. Treating one as a
  // custom provider after an upgrade would incorrectly permit a user key to
  // be associated with it, so saved values migrate back to the current
  // built-in endpoint.
  static const _retiredBuiltInEndpointUrls = <String>{
    'https://windeploystudio.bob-0910.workers.dev/',
  };

  static const _directApiRouteSuffixes = <String>{
    '/chat/completions',
    '/responses',
    '/models',
  };

  static const defaultModel = 'mimo-v2.5-pro';
  static const remoteAiDisabledMarkerFileName = 'remote-ai-disabled.flag';
  static const maxModelListResponseBytes = 2 * 1024 * 1024;
  static const connectionTimeout = Duration(seconds: 15);
  // Gateways are allowed a little longer to return response headers. This is
  // important for OpenAI-compatible relays that buffer an upstream response
  // before forwarding it; stream-idle handling remains separate below.
  static const requestTimeout = Duration(seconds: 60);
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

  static bool _isRetiredBuiltInEndpoint(String endpointUrl) =>
      _retiredBuiltInEndpointUrls.contains(normalizeEndpointUrl(endpointUrl));

  static Future<void> _clearRetiredEndpointBindings(
    SharedPreferences prefs,
  ) async {
    final apiKeyEndpoint = prefs.getString(_prefKeyApiKeyEndpoint);
    if (apiKeyEndpoint != null && _isRetiredBuiltInEndpoint(apiKeyEndpoint)) {
      await prefs.remove(_prefKeyApiKey);
      await prefs.remove(_prefKeyApiKeyEndpoint);
    }

    final modelEndpoint = prefs.getString(_prefKeyModelEndpoint);
    if (modelEndpoint != null && _isRetiredBuiltInEndpoint(modelEndpoint)) {
      await prefs.remove(_prefKeyModel);
      await prefs.remove(_prefKeyModelEndpoint);
    }
  }

  static Future<String> getEndpointUrl() async {
    final prefs = await SharedPreferences.getInstance();
    await _clearRetiredEndpointBindings(prefs);
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
    if (_isRetiredBuiltInEndpoint(normalized)) {
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
    final retiredBuiltInEndpoint = _isRetiredBuiltInEndpoint(normalized);
    if (normalized.isEmpty ||
        normalized == defaultEndpointUrl ||
        retiredBuiltInEndpoint) {
      final current = await getEndpointUrl();
      if (current != defaultEndpointUrl || retiredBuiltInEndpoint) {
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
    final targetEndpoint = normalizeEndpointUrl(
      endpointUrl ?? await getEndpointUrl(),
    );
    if (!shouldSendApiKey(targetEndpoint)) {
      await clearApiKey();
      return null;
    }
    final stored = prefs.getString(_prefKeyApiKey);
    if (stored == null || stored.trim().isEmpty) return null;
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
    if (_isRetiredBuiltInEndpoint(endpoint)) {
      await clearModel();
      return defaultModel;
    }
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
    if (_isRetiredBuiltInEndpoint(endpoint)) {
      await clearModel();
      return;
    }
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
  static bool shouldSendApiKey(String endpointUrl) {
    final normalized = normalizeEndpointUrl(endpointUrl);
    return normalized != defaultEndpointUrl &&
        !_isRetiredBuiltInEndpoint(normalized);
  }

  /// The installer can opt the machine out of all remote AI and web-search
  /// traffic by placing this marker beside the installed executable.
  ///
  /// Keep this check local and synchronous so no network or preferences are
  /// touched before the opt-out is honored.
  static bool isRemoteAiDisabled() {
    try {
      final executable = File(Platform.resolvedExecutable);
      final marker = File(
        '${executable.parent.path}${Platform.pathSeparator}'
        '$remoteAiDisabledMarkerFileName',
      );
      return marker.existsSync();
    } catch (_) {
      return false;
    }
  }

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
    final pathWithoutTrailingSlash = uri.path.replaceFirst(RegExp(r'/+$'), '');
    final isDirectApiRoute = _directApiRouteSuffixes.any(
      pathWithoutTrailingSlash.endsWith,
    );
    final path = isDirectApiRoute
        ? pathWithoutTrailingSlash
        : (uri.path.endsWith('/') ? uri.path : '${uri.path}/');
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
