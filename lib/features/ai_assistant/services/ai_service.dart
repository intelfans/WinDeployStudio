import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import '../../../core/config/ai_config.dart';
import '../../../core/localization/strings.dart';
import '../../logs/services/log_center_service.dart';
import 'ai_system_proxy_resolver.dart';

enum SearchMode { off, auto, force }

class SearchSource {
  final String title;
  final String url;
  SearchSource({required this.title, required this.url});
}

/// The streaming surface consumed by the chat state layer.
///
/// Keeping this narrow makes request ownership testable without allowing a
/// stale stream to mutate the currently selected chat session.
abstract class AiMessageService {
  Future<void> sendMessage({
    required List<Map<String, String>> messages,
    required void Function(String chunk) onChunk,
    required void Function() onComplete,
    required void Function(String error) onError,
    required void Function(List<SearchSource> sources) onSources,
    SearchMode searchMode = SearchMode.off,
    CancelToken? cancelToken,
  });
}

class AiService implements AiMessageService {
  static const String _model = 'mimo-v2.5-pro';

  static AiService? _instance;
  AiService._();
  factory AiService() => _instance ??= AiService._();

  String _mapErrorCode(int statusCode) {
    switch (statusCode) {
      case 401:
        return trCurrent('ai_error_unauthorized');
      case 429:
        return trCurrent('ai_error_rate_limited');
      default:
        if (statusCode >= 500) {
          return trCurrent('ai_error_unavailable');
        }
        return trCurrent('ai_error_http').replaceAll('{status}', '$statusCode');
    }
  }

  /// Creates the desktop transport without weakening TLS validation.
  ///
  /// Dart does not automatically read Windows Internet Settings proxies.
  /// Respecting the environment and the user's standard Windows proxy setup
  /// makes the built-in endpoint usable on managed networks, while leaving
  /// Dart's default certificate and hostname verification intact.
  Future<_AiTransport> _createSecureClient(
    Uri endpoint, {
    bool forceDirect = false,
  }) async {
    final proxy = forceDirect
        ? const AiProxyResolution(
            instruction: 'DIRECT',
            source: AiProxySource.direct,
          )
        : await AiSystemProxyResolver.resolveFor(endpoint);
    final transport = HttpClient()
      ..connectionTimeout = AiConfig.connectionTimeout
      ..idleTimeout = AiConfig.streamIdleTimeout
      ..userAgent = 'WinDeployStudio AI';
    transport.findProxy = (target) {
      // Use the resolution captured for this request. Re-reading inherited
      // environment variables here would re-enable a dead Clash loopback
      // endpoint that the resolver intentionally rejected.
      return proxy.instruction;
    };
    return _AiTransport(client: IOClient(transport), proxy: proxy);
  }

  @visibleForTesting
  static String networkErrorKey(Object error) {
    if (error is TimeoutException) {
      return 'ai_error_timeout';
    }
    final text = error.toString().toLowerCase();
    if (error is HandshakeException ||
        text.contains('handshakeexception') ||
        text.contains('certificateexception') ||
        text.contains('tlsexception') ||
        text.contains('ssl handshake') ||
        text.contains('during handshake') ||
        text.contains('certificate verify failed') ||
        text.contains('certificate chain') ||
        text.contains('unknown ca') ||
        text.contains('untrusted certificate')) {
      return 'ai_error_tls';
    }
    if (error is SocketException ||
        text.contains('socketexception') ||
        text.contains('clientexception') ||
        text.contains('failed host lookup') ||
        text.contains('connection refused') ||
        text.contains('network is unreachable') ||
        text.contains('errno = 121') ||
        text.contains('connection timed out') ||
        text.contains('信号灯超时时间已到')) {
      return 'ai_error_unreachable';
    }
    return 'ai_error_connection';
  }

  /// A retry is safe only when HTTPS never reached the HTTP request stage.
  ///
  /// We deliberately do not retry timeouts or HTTP responses: either may have
  /// reached the service and retrying could create a duplicate AI request.
  @visibleForTesting
  static bool shouldRetryTransportFailure(Object error) {
    final key = networkErrorKey(error);
    return key == 'ai_error_tls' || key == 'ai_error_unreachable';
  }

  String _mapNetworkError(Object error, {required String proxyUrl}) {
    final key = networkErrorKey(error);
    if (key != 'ai_error_connection') return trCurrent(key);
    final diagnostic = _redactProxyUrl(error.toString(), proxyUrl);
    return trCurrent(key).replaceAll('{error}', diagnostic);
  }

  static String _redactProxyUrl(String value, String proxyUrl) {
    final uri = Uri.tryParse(proxyUrl);
    var redacted = value.replaceAll(proxyUrl, '<AI proxy>/');
    if (uri != null) redacted = redacted.replaceAll(uri.origin, '<AI proxy>');
    return redacted;
  }

  @override
  Future<void> sendMessage({
    required List<Map<String, String>> messages,
    required void Function(String chunk) onChunk,
    required void Function() onComplete,
    required void Function(String error) onError,
    required void Function(List<SearchSource> sources) onSources,
    SearchMode searchMode = SearchMode.off,
    CancelToken? cancelToken,
  }) async {
    final proxyUrl = await AiConfig.getProxyUrl();
    final url = '${proxyUrl}chat/completions';
    LogCenterService().logSystem(
      '[AI]\nProvider=OpenAICompatibleProxy\n'
      'Proxy=${proxyUrl == AiConfig.defaultProxyUrl ? 'default' : 'custom'}',
    );

    http.Client? client;
    AiProxyResolution? activeTransportProxy;
    var completed = false;

    void completeOnce() {
      if (completed) return;
      completed = true;
      onComplete();
    }

    try {
      final body = <String, dynamic>{
        'model': _model,
        'messages': messages,
        'stream': true,
      };

      if (searchMode != SearchMode.off) {
        body['tools'] = [
          {
            'type': 'web_search',
            'web_search': {
              'search_context_size': searchMode == SearchMode.force
                  ? 'high'
                  : 'medium',
            },
          },
        ];
      }

      http.Request buildRequest() {
        final request = http.Request('POST', Uri.parse(url));
        request.headers['Content-Type'] = 'application/json';
        request.headers['Accept'] = 'text/event-stream';
        request.headers['Cache-Control'] = 'no-cache';
        request.body = jsonEncode(body);
        return request;
      }

      Future<http.StreamedResponse> sendRequest({
        bool forceDirect = false,
      }) async {
        client?.close();
        final transport = await _createSecureClient(
          Uri.parse(url),
          forceDirect: forceDirect,
        );
        activeTransportProxy = transport.proxy;
        client = transport.client;
        cancelToken?.client = client;
        return client!.send(buildRequest()).timeout(AiConfig.requestTimeout);
      }

      late final http.StreamedResponse response;
      try {
        response = await sendRequest();
      } catch (error) {
        if (cancelToken?.cancelled == true ||
            !shouldRetryTransportFailure(error)) {
          rethrow;
        }
        final category = networkErrorKey(error);
        final bypassStaleLoopbackProxy =
            activeTransportProxy?.isLoopbackProxy == true;
        LogCenterService().logSystem(
          '[AI]\nRequestSuccess=false\nFailureCategory=$category\n'
          'Retrying=true\nRetryAttempt=2\n'
          'BypassLoopbackProxy=$bypassStaleLoopbackProxy',
        );
        await Future<void>.delayed(AiConfig.transientRetryDelay);
        if (cancelToken?.cancelled == true) {
          throw StateError('AI request cancelled');
        }
        response = await sendRequest(forceDirect: bypassStaleLoopbackProxy);
      }

      if (response.statusCode != 200) {
        await response.stream.bytesToString();
        final errorMsg = _mapErrorCode(response.statusCode);

        LogCenterService().logSystem(
          '[AI]\nRequestSuccess=false\nStatusCode=${response.statusCode}\nError=$errorMsg',
        );

        onError(errorMsg);
        return;
      }

      LogCenterService().logSystem('[AI]\nRequestSuccess=true');

      String buffer = '';
      final List<SearchSource> sources = [];

      await for (final chunk
          in response.stream
              .transform(utf8.decoder)
              .timeout(AiConfig.streamIdleTimeout)) {
        if (cancelToken?.cancelled ?? false) {
          completeOnce();
          return;
        }

        buffer += chunk;
        final lines = buffer.split('\n');
        buffer = lines.removeLast();

        for (final line in lines) {
          final trimmed = line.trim();
          if (trimmed.isEmpty || !trimmed.startsWith('data: ')) continue;
          final data = trimmed.substring(6);
          if (data == '[DONE]') {
            if (sources.isNotEmpty) onSources(sources);
            completeOnce();
            return;
          }

          try {
            final json = jsonDecode(data);
            final choices = json['choices'] as List?;
            if (choices != null && choices.isNotEmpty) {
              final delta = choices[0]['delta'];
              if (delta != null) {
                if (delta['content'] != null) {
                  onChunk(delta['content'] as String);
                }
                _extractSources(delta, sources);
              }
            }
          } catch (_) {}
        }
      }
      if (sources.isNotEmpty) onSources(sources);
      completeOnce();
    } catch (e) {
      if (cancelToken?.cancelled ?? false) {
        completeOnce();
      } else {
        final errorMsg = _mapNetworkError(e, proxyUrl: proxyUrl);
        final diagnostic = _redactProxyUrl(e.toString(), proxyUrl);
        final category = networkErrorKey(e);
        LogCenterService().logSystem(
          '[AI]\nRequestSuccess=false\nFailureCategory=$category\n'
          'Error=$diagnostic\n'
          'UserMessage=$errorMsg',
        );
        onError(errorMsg);
      }
    } finally {
      client?.close();
    }
  }

  void _extractSources(Map<String, dynamic> delta, List<SearchSource> sources) {
    final annotations = delta['annotations'] as List?;
    if (annotations != null) {
      for (final ann in annotations) {
        if (ann['type'] == 'url_citation') {
          final title = ann['title'] as String? ?? '';
          final url = ann['url'] as String? ?? '';
          if (url.isNotEmpty && !sources.any((s) => s.url == url)) {
            sources.add(SearchSource(title: title, url: url));
          }
        }
      }
    }
  }
}

class _AiTransport {
  final http.Client client;
  final AiProxyResolution proxy;

  const _AiTransport({required this.client, required this.proxy});
}

class CancelToken {
  bool cancelled = false;
  http.Client? client;

  void cancel() {
    cancelled = true;
    client?.close();
  }
}
