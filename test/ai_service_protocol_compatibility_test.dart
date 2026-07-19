import 'package:flutter_test/flutter_test.dart';
import 'package:win_deploy_studio/features/ai_assistant/services/ai_service.dart';

void main() {
  group('AiService raw tool-call compatibility', () {
    test('extracts a search query from a complete raw tool-call payload', () {
      const content = '''
I will look that up.
<tool_call>{"name":"search_web","arguments":{"query":"Windows 11 25H2 release notes"}}</tool_call>''';

      expect(
        AiService.parseRawSearchToolCallQueryForTesting(content),
        'Windows 11 25H2 release notes',
      );
    });

    test('does not expose a complete raw tool-call payload to the user', () {
      const content = '''
I will look that up.
<tool_call>{"name":"search_web","arguments":{"query":"Windows 11 25H2 release notes"}}</tool_call>''';

      expect(
        AiService.sanitizeRawToolCallContentForTesting(content),
        'I will look that up.',
      );
    });

    test('does not expose an incomplete raw tool-call payload to the user', () {
      const content =
          'I will look that up.\n<tool_call>{"name":"search_web","arguments":{"query":"Windows';

      expect(
        AiService.sanitizeRawToolCallContentForTesting(content),
        'I will look that up.',
      );
    });

    test('keeps ordinary Markdown angle brackets intact', () {
      const content =
          'Open <https://example.com/docs> and verify that 1 < 2.\n\n`<tag>` is code.';

      expect(AiService.sanitizeRawToolCallContentForTesting(content), content);
    });

    test('hides a raw tool-call tag split across stream chunks', () {
      expect(
        AiService.sanitizeRawToolCallChunksForTesting([
          'I will look that up. <tool',
          '_call>{"name":"search_web",',
          '"arguments":{"query":"Windows release notes"}}</tool_call>',
          ' Done.',
        ]),
        'I will look that up. Done.',
      );
    });
  });

  group('AiService OpenAI-compatible response parsing', () {
    test('decodes CRLF SSE frames with multiple data lines', () {
      expect(
        AiService.decodeSseDataForTesting(
          'event: message\r\ndata: {"choices":\r\ndata: []}\r\n\r\ndata: [DONE]\r\n\r\n',
        ),
        ['{"choices":\n[]}', '[DONE]'],
      );
    });

    test('extracts streamed content parts and non-streaming messages', () {
      expect(
        AiService.extractChatTextForTesting({
          'choices': [
            {
              'delta': {
                'content': [
                  {'type': 'text', 'text': 'Hello '},
                  {'type': 'text', 'text': 'world'},
                ],
              },
            },
          ],
        }),
        'Hello world',
      );
      expect(
        AiService.extractChatTextForTesting({
          'choices': [
            {
              'message': {
                'content': [
                  {'type': 'text', 'text': 'Complete JSON response'},
                ],
              },
            },
          ],
        }),
        'Complete JSON response',
      );
    });

    test('extracts a standard Responses output message', () {
      expect(
        AiService.extractResponsesTextForTesting({
          'output': [
            {
              'type': 'message',
              'content': [
                {'type': 'output_text', 'text': 'Responses output'},
              ],
            },
          ],
        }),
        'Responses output',
      );
    });
  });

  group('AiService public search source filtering', () {
    test('rejects generic search engine homepages', () {
      for (final url in const [
        'https://www.baidu.com/',
        'https://www.sogou.com/',
        'https://www.so.com/',
        'https://www.google.com/search?q=intel',
        'https://www.bing.com/search?q=intel',
        'https://www.baidu.com/link?url=redirected',
        'https://www.bing.com/ck/a?redirect=search-result',
      ]) {
        expect(
          AiService.isUsableSearchUrlForTesting(url),
          isFalse,
          reason: url,
        );
      }
    });

    test('accepts a concrete result page', () {
      expect(
        AiService.isUsableSearchUrlForTesting(
          'https://www.intel.com/content/www/us/en/products/details/processors/core.html',
        ),
        isTrue,
      );
      expect(
        AiService.isUsableSearchUrlForTesting(
          'https://learn.microsoft.com/windows/deployment/',
        ),
        isTrue,
      );
    });

    test('rejects malformed, credential-bearing, and empty targets', () {
      expect(AiService.isUsableSearchUrlForTesting('not a url'), isFalse);
      expect(
        AiService.isUsableSearchUrlForTesting('https://example.com'),
        isFalse,
      );
      expect(
        AiService.isUsableSearchUrlForTesting(
          'https://user:password@example.com/docs',
        ),
        isFalse,
      );
    });

    test('rejects generic search navigation titles', () {
      for (final title in const [
        'Baidu - 百度一下，你就知道',
        '搜狗搜索引擎 - 上网从搜狗开始',
        '搜索引擎大全 | 一次搜索，全网直达',
      ]) {
        expect(
          AiService.isGenericSearchTitleForTesting(title),
          isTrue,
          reason: title,
        );
      }
      expect(
        AiService.isGenericSearchTitleForTesting('Intel Core processors'),
        isFalse,
      );
    });
  });
}
