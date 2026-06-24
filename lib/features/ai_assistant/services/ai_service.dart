import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../../../core/config/ai_config.dart';
import '../../logs/services/log_center_service.dart';

enum SearchMode { off, auto, force }

class SearchSource {
  final String title;
  final String url;
  SearchSource({required this.title, required this.url});
}

class AiService {
  static const String _model = 'mimo-v2.5-pro';

  static AiService? _instance;
  AiService._();
  factory AiService() => _instance ??= AiService._();

  String _mapErrorCode(int statusCode) {
    switch (statusCode) {
      case 401:
        return 'AI 服务未授权';
      case 429:
        return '请求过于频繁';
      case 500:
        return 'AI 服务暂时不可用';
      default:
        return 'AI 服务错误 ($statusCode)';
    }
  }

  Future<void> sendMessage({
    required List<Map<String, String>> messages,
    required void Function(String chunk) onChunk,
    required void Function() onComplete,
    required void Function(String error) onError,
    required void Function(List<SearchSource> sources) onSources,
    SearchMode searchMode = SearchMode.off,
    CancelToken? cancelToken,
  }) async {
    final url = '${AiConfig.proxyUrl}chat/completions';

    LogCenterService().logSystem(
      '[AI]\nProvider=CloudflareWorker\nURL=${AiConfig.proxyUrl}',
    );

    try {
      final request = http.Request('POST', Uri.parse(url));
      request.headers['Content-Type'] = 'application/json';

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
              'search_context_size': searchMode == SearchMode.force ? 'high' : 'medium',
            },
          },
        ];
      }

      request.body = jsonEncode(body);

      final client = http.Client();
      cancelToken?.client = client;

      final response = await client.send(request);

      if (response.statusCode != 200) {
        await response.stream.bytesToString();
        client.close();
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

      await for (final chunk in response.stream.transform(utf8.decoder)) {
        if (cancelToken?.cancelled ?? false) {
          client.close();
          onComplete();
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
            onComplete();
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
      onComplete();
    } catch (e) {
      if (cancelToken?.cancelled ?? false) {
        onComplete();
      } else {
        LogCenterService().logSystem(
          '[AI]\nRequestSuccess=false\nError=$e',
        );
        onError(e.toString());
      }
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

class CancelToken {
  bool cancelled = false;
  http.Client? client;

  void cancel() {
    cancelled = true;
    client?.close();
  }
}
