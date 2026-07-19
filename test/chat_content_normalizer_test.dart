import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:win_deploy_studio/features/ai_assistant/models/chat_models.dart';
import 'package:win_deploy_studio/features/ai_assistant/utils/chat_content_normalizer.dart';
import 'package:win_deploy_studio/features/ai_assistant/widgets/chat_bubble.dart';

void main() {
  group('normalizeChatDisplayContent', () {
    test('renders common HTML break variants as Markdown line breaks', () {
      expect(
        normalizeChatDisplayContent('First<br>Second<BR/>Third<br />Fourth'),
        'First\nSecond\nThird\nFourth',
      );
    });

    test('renders safely escaped HTML break variants as line breaks', () {
      expect(
        normalizeChatDisplayContent(
          'First&lt;br&gt;Second&lt;BR/&gt;Third&lt;br /&gt;Fourth',
        ),
        'First\nSecond\nThird\nFourth',
      );
    });

    test('normalizes nested escaping and invisible spacing from relays', () {
      expect(
        normalizeChatDisplayContent(
          'First&amp;lt;br&amp;gt;Second<\u200Bbr>Third&#60;BR /&#62;Fourth',
        ),
        'First\nSecond\nThird\nFourth',
      );
    });

    test('normalizes Windows and legacy Mac line endings', () {
      expect(
        normalizeChatDisplayContent('First\r\nSecond\rThird'),
        'First\nSecond\nThird',
      );
    });

    test(
      'preserves HTML examples inside inline code and fenced code blocks',
      () {
        const content = '''
Use `<br>` in HTML.<br>Outside code.

```html
line one<br>
line two<br />
```
''';

        expect(normalizeChatDisplayContent(content), '''
Use `<br>` in HTML.
Outside code.

```html
line one<br>
line two<br />
```
''');
      },
    );

    test(
      'preserves escaped HTML break examples inside inline code and fenced code blocks',
      () {
        const content = '''
Use `&lt;br&gt;`, `&lt;BR/&gt;`, and `&lt;br /&gt;` literally.&lt;br&gt;Outside code.

```html
line one &lt;br&gt;
line two &lt;BR/&gt;
line three &lt;br /&gt;
```
''';

        expect(normalizeChatDisplayContent(content), '''
Use `&lt;br&gt;`, `&lt;BR/&gt;`, and `&lt;br /&gt;` literally.
Outside code.

```html
line one &lt;br&gt;
line two &lt;BR/&gt;
line three &lt;br /&gt;
```
''');
      },
    );

    test('does not alter unrelated HTML-like text', () {
      expect(
        normalizeChatDisplayContent('Keep <strong>this</strong> intact.'),
        'Keep <strong>this</strong> intact.',
      );
    });

    test('removes provider citation markers from display text', () {
      expect(
        normalizeChatDisplayContent(
          'Intel 官网 [citation:1][citation: 2] 可从这里访问。',
        ),
        'Intel 官网  可从这里访问。',
      );
      expect(
        normalizeChatDisplayContent('结果<citation>内部标记</citation>已清理'),
        '结果内部标记已清理',
      );
    });

    test('keeps citation examples inside inline and fenced code', () {
      const content = '''
Use `[citation:1]` literally.

```text
[citation:2]
<citation>example</citation>
```
''';

      expect(normalizeChatDisplayContent(content), content);
    });

    test('keeps Markdown table cells intact when they contain HTML breaks', () {
      const content = '''
| Item | Details |
| --- | --- |
| ISO | First<br>Second |
''';

      final normalized = normalizeChatDisplayContent(content);
      final document = md.Document(
        extensionSet: md.ExtensionSet.gitHubFlavored,
      );
      final nodes = document.parseLines(normalized.split('\n'));

      expect(normalized, isNot(contains('<br>')));
      expect(normalized.trimRight().split('\n'), hasLength(3));
      expect(normalized, contains('First\u2028Second'));
      expect(nodes, hasLength(1));
      expect(nodes.single, isA<md.Element>());
      expect((nodes.single as md.Element).tag, 'table');
    });

    test('uses a Flutter line separator for table cell breaks', () {
      final painter = TextPainter(
        text: const TextSpan(text: 'First\u2028Second'),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: 200);
      addTearDown(painter.dispose);

      expect(painter.computeLineMetrics(), hasLength(2));
    });

    testWidgets('passes normalized table content to the chat bubble', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ChatBubble(
              message: ChatMessage(
                role: 'assistant',
                content: '''
| Item | Details |
| --- | --- |
| ISO | First<br>Second |
''',
              ),
            ),
          ),
        ),
      );

      expect(find.byType(Table), findsOneWidget);
      expect(find.textContaining('<br>'), findsNothing);
      expect(find.textContaining('First'), findsOneWidget);
      expect(find.textContaining('Second'), findsOneWidget);
    });
  });
}
