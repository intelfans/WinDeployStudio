import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Diagnostic logs are exported for support and read verbatim by the AI
/// assistant, so they must stay language-neutral.
void main() {
  late String source;

  setUpAll(() {
    source = File('lib/features/creator/screens/creator_screen.dart')
        .readAsStringSync();
  });

  test('no CJK text remains in the creator screen', () {
    final offenders = <String>[];
    final lines = source.split('\n');
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      if (line.trimLeft().startsWith('//')) continue;
      if (RegExp(r'[\u4e00-\u9fff]').hasMatch(line)) {
        offenders.add('${i + 1}: ${line.trim()}');
      }
    }
    expect(offenders, isEmpty, reason: offenders.join('\n'));
  });

  test('log records use structured key=value fields', () {
    expect(source.contains("logUsb('removable.disks detect count="), isTrue);
    expect(source.contains("'removable.disk'"), isTrue);
    expect(source.contains(r'number=${disk.diskNumber}'), isTrue);
    expect(source.contains('iso.selected platform=linux'), isTrue);
    expect(source.contains('iso.selected platform=windows'), isTrue);
  });

  test('missing ISO metadata is reported as a neutral token, not a locale word', () {
    expect(source.contains('"unknown"'), isTrue);
  });
}
