/// Normalizes harmless formatting artifacts from provider responses before
/// they are rendered as Markdown. This is deliberately display-only: the
/// saved message keeps the provider's original text for transport/history.
String normalizeChatDisplayContent(String content) {
  if (content.isEmpty) return content;

  final normalizedLineEndings = content
      .replaceAll('\r\n', '\n')
      .replaceAll('\r', '\n');
  final lines = normalizedLineEndings.split('\n');
  final markdownTableLines = _findMarkdownTableLines(lines);
  final buffer = StringBuffer();
  String? fenceCharacter;
  var fenceLength = 0;

  for (var index = 0; index < lines.length; index++) {
    final line = lines[index];
    final openingFence = _fencePattern.firstMatch(line);

    if (fenceCharacter != null) {
      buffer.write(line);
      if (_isClosingFence(line, fenceCharacter, fenceLength)) {
        fenceCharacter = null;
        fenceLength = 0;
      }
    } else if (openingFence != null) {
      final marker = openingFence.group(1)!;
      fenceCharacter = marker[0];
      fenceLength = marker.length;
      buffer.write(line);
    } else {
      // A literal newline would split a Markdown table row. U+2028 is laid
      // out as a line break by Flutter while remaining inside that table cell.
      final breakReplacement = markdownTableLines.contains(index)
          ? _tableCellLineSeparator
          : '\n';
      buffer.write(_normalizeLineOutsideInlineCode(line, breakReplacement));
    }

    if (index < lines.length - 1) buffer.write('\n');
  }

  return buffer.toString();
}

final RegExp _fencePattern = RegExp(r'^\s*(`{3,}|~{3,})');
const _formattingWhitespace = r'[\s\u200B\u200C\u200D\uFEFF]*';
final RegExp _htmlBreakPattern = RegExp(
  '<$_formattingWhitespace'
  'br$_formattingWhitespace/?$_formattingWhitespace>',
  caseSensitive: false,
);
// Some OpenAI-compatible relays HTML-escape the whole response while still
// returning Markdown. Treat only the harmless escaped line-break token as a
// line break; all other escaped HTML remains untouched text.
final RegExp _escapedHtmlBreakPattern = RegExp(
  '(?:&amp;)*(?:&?lt;|&#0*60;|&#x0*3c;)$_formattingWhitespace'
  'br$_formattingWhitespace/?$_formattingWhitespace'
  '(?:&amp;)*(?:&?gt;|&#0*62;|&#x0*3e;)',
  caseSensitive: false,
);
final RegExp _tableDividerPattern = RegExp(
  r'^\s*\|?\s*:?-{3,}:?\s*(?:\|\s*:?-{3,}:?\s*)*\|?\s*$',
);

const _tableCellLineSeparator = '\u2028';

Set<int> _findMarkdownTableLines(List<String> lines) {
  final tableLines = <int>{};

  for (var index = 1; index < lines.length; index++) {
    if (!_tableDividerPattern.hasMatch(lines[index]) ||
        !_looksLikeMarkdownTableRow(lines[index - 1])) {
      continue;
    }

    tableLines.add(index - 1);
    for (
      var rowIndex = index + 1;
      rowIndex < lines.length && _looksLikeMarkdownTableRow(lines[rowIndex]);
      rowIndex++
    ) {
      tableLines.add(rowIndex);
    }
  }

  return tableLines;
}

bool _looksLikeMarkdownTableRow(String line) => line.contains('|');

bool _isClosingFence(String line, String character, int minimumLength) {
  final pattern = RegExp(
    '^\\s*${RegExp.escape(character)}{$minimumLength,}\\s*\$',
  );
  return pattern.hasMatch(line);
}

String _normalizeLineOutsideInlineCode(String line, String breakReplacement) {
  final buffer = StringBuffer();
  var segmentStart = 0;
  var cursor = 0;

  while (cursor < line.length) {
    if (line.codeUnitAt(cursor) != 0x60 ||
        (cursor > 0 && line.codeUnitAt(cursor - 1) == 0x5c)) {
      cursor++;
      continue;
    }

    var delimiterEnd = cursor + 1;
    while (delimiterEnd < line.length &&
        line.codeUnitAt(delimiterEnd) == 0x60) {
      delimiterEnd++;
    }
    final delimiter = line.substring(cursor, delimiterEnd);
    final closing = line.indexOf(delimiter, delimiterEnd);
    if (closing < 0) {
      cursor = delimiterEnd;
      continue;
    }

    buffer.write(
      line
          .substring(segmentStart, cursor)
          .replaceAll(_htmlBreakPattern, breakReplacement)
          .replaceAll(_escapedHtmlBreakPattern, breakReplacement)
          .replaceAll(_citationMarkerPattern, '')
          .replaceAll(_citationTagPattern, ''),
    );
    buffer.write(line.substring(cursor, closing + delimiter.length));
    cursor = closing + delimiter.length;
    segmentStart = cursor;
  }

  buffer.write(
    line
        .substring(segmentStart)
        .replaceAll(_htmlBreakPattern, breakReplacement)
        .replaceAll(_escapedHtmlBreakPattern, breakReplacement)
        .replaceAll(_citationMarkerPattern, '')
        .replaceAll(_citationTagPattern, ''),
  );
  return buffer.toString();
}

// Some search relays append provider-internal citation markers to otherwise
// normal Markdown. They are not useful to users because the app renders the
// structured source list separately. Keep this display-only and outside code
// spans/fences so literal examples remain intact.
final RegExp _citationMarkerPattern = RegExp(
  r'\[\s*citation\s*:\s*\d+\s*\]',
  caseSensitive: false,
);
final RegExp _citationTagPattern = RegExp(
  r'</?\s*citation(?:\s+[^>]*)?>',
  caseSensitive: false,
);
