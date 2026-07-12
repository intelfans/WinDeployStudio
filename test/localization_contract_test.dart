import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:win_deploy_studio/app/visual_style.dart';
import 'package:win_deploy_studio/core/localization/strings.dart';
import 'package:win_deploy_studio/features/benchmark_history/benchmark_history_copy.dart';
import 'package:win_deploy_studio/features/disk_tools/localization/disk_tools_localization.dart';

void main() {
  final languages = <String, Map<String, String>>{
    'zh': L.zh,
    'zh_TW': L.zhTW,
    'en': L.en,
    'fr': L.fr,
    'de': L.de,
    'es': L.es,
    'pt': L.pt,
    'ru': L.ru,
    'ar': L.ar,
    'ko': L.ko,
    'ja': L.ja,
  };

  test('all supported languages expose the same complete key set', () {
    final expected = languages['en']!.keys.toSet();

    for (final entry in languages.entries) {
      expect(
        entry.value.keys.toSet(),
        expected,
        reason: '${entry.key} must not rely on another language as fallback',
      );
    }
  });

  test('localized values are non-empty and contain no corruption markers', () {
    final mojibake = RegExp(r'(?:\?{4,}|\uFFFD)');

    for (final language in languages.entries) {
      for (final value in language.value.entries) {
        expect(
          value.value.trim(),
          isNotEmpty,
          reason: '${language.key}.${value.key} is empty',
        );
        expect(
          mojibake.hasMatch(value.value),
          isFalse,
          reason: '${language.key}.${value.key} contains corrupted text',
        );
      }
    }
  });

  test(
    'all statically referenced translation keys exist in every language',
    () {
      final referencedKeys = <String>{};
      final dartFiles = Directory('lib')
          .listSync(recursive: true)
          .whereType<File>()
          .where((file) => file.path.endsWith('.dart'));

      final trPattern = RegExp(
        r'''\btr\s*\(\s*[^,\n]+,\s*(['"])([a-zA-Z0-9_]+)\1''',
        multiLine: true,
      );
      final currentPattern = RegExp(
        r'''\btrCurrent\s*\(\s*(['"])([a-zA-Z0-9_]+)\1''',
        multiLine: true,
      );
      final byCodePattern = RegExp(
        r'''\btrByCode\s*\(\s*[^,\n]+,\s*(['"])([a-zA-Z0-9_]+)\1''',
        multiLine: true,
      );
      final deploymentPattern = RegExp(r'''['"](deploy_[a-z0-9_]+)['"]''');

      for (final file in dartFiles) {
        final source = file.readAsStringSync();
        for (final pattern in [
          trPattern,
          currentPattern,
          byCodePattern,
          deploymentPattern,
        ]) {
          referencedKeys.addAll(
            pattern.allMatches(source).map((match) {
              final keyGroup = match.groupCount >= 2 ? 2 : 1;
              return match.group(keyGroup)!;
            }),
          );
        }
      }

      referencedKeys.addAll(diskToolsEnglish.keys);
      referencedKeys.addAll(benchmarkHistoryLocalizationKeys);
      referencedKeys.addAll(VisualStyleLocalizationKeys.all);

      referencedKeys.addAll(_dataTranslationKeys(File('data/tools.json')));

      for (final language in languages.entries) {
        final missing = referencedKeys.difference(language.value.keys.toSet());
        expect(
          missing,
          isEmpty,
          reason: '${language.key} is missing referenced translation keys',
        );
      }
    },
  );
}

Set<String> _dataTranslationKeys(File file) {
  if (!file.existsSync()) return const {};
  final result = <String>{};

  void visit(Object? value) {
    if (value is List) {
      for (final item in value) {
        visit(item);
      }
      return;
    }
    if (value is! Map) return;
    for (final entry in value.entries) {
      final key = entry.key.toString();
      if (key.toLowerCase().endsWith('key') && entry.value is String) {
        result.add(entry.value as String);
      }
      visit(entry.value);
    }
  }

  visit(jsonDecode(file.readAsStringSync()));
  return result;
}
