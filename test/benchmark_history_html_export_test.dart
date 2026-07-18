import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:win_deploy_studio/features/benchmark_history/services/benchmark_history_service.dart';

import 'benchmark_test_fixtures.dart';

void main() {
  test(
    'HTML export is self-contained and includes identity, data, and SVG',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'wds_benchmark_html_test_',
      );
      addTearDown(() async {
        if (await directory.exists()) await directory.delete(recursive: true);
      });
      final service = BenchmarkHistoryService(
        directoryProvider: () async => directory,
      );
      final saved = await service.add(benchmarkTestResult());

      final output = await service.exportHtml(
        p.join(directory.path, 'report.html'),
        ids: [saved.id],
      );
      final html = await output.readAsString();

      expect(html, startsWith('<!doctype html>'));
      expect(html, contains('<svg '));
      expect(html, contains('Portable SSD'));
      expect(html, contains('SERIAL-1234'));
      expect(html, contains('random4kWrite'));
      expect(html, contains('sequentialWrite'));
      expect(html, contains('samples'));
      expect(html, contains('sequentialSeconds'));
      expect(html, isNot(contains('https://')));
    },
  );

  test('HTML export with no selected records remains a valid report', () async {
    final directory = await Directory.systemTemp.createTemp(
      'wds_benchmark_html_empty_test_',
    );
    addTearDown(() async {
      if (await directory.exists()) await directory.delete(recursive: true);
    });
    final service = BenchmarkHistoryService(
      directoryProvider: () async => directory,
    );

    final output = await service.exportHtml(
      p.join(directory.path, 'empty.html'),
      ids: const ['missing'],
    );
    final html = await output.readAsString();

    expect(html, contains('No benchmark records were selected.'));
    expect(html, contains('</html>'));
  });

  test(
    'HTML export localizes every supported report title and separates charts',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'wds_benchmark_html_locale_test_',
      );
      addTearDown(() async {
        if (await directory.exists()) await directory.delete(recursive: true);
      });
      final service = BenchmarkHistoryService(
        directoryProvider: () async => directory,
      );
      final saved = await service.add(benchmarkTestResult());
      const expectedTitles = <String, String>{
        'en': 'WinDeploy Studio Disk Benchmark Report',
        'zh': 'WinDeploy Studio 磁盘测试报告',
        'zh_TW': 'WinDeploy Studio 磁碟測試報告',
        'fr': 'Rapport de test de disque WinDeploy Studio',
        'de': 'WinDeploy Studio Datenträger-Testbericht',
        'es': 'Informe de prueba de disco de WinDeploy Studio',
        'pt': 'Relatório de teste de disco do WinDeploy Studio',
        'ru': 'Отчет WinDeploy Studio о тестировании диска',
        'ar': 'تقرير اختبار القرص من WinDeploy Studio',
        'ko': 'WinDeploy Studio 디스크 벤치마크 보고서',
        'ja': 'WinDeploy Studio ディスクベンチマークレポート',
      };

      for (final entry in expectedTitles.entries) {
        final output = await service.exportHtml(
          p.join(directory.path, 'report_${entry.key}.html'),
          ids: [saved.id],
          localeCode: entry.key,
        );
        final html = await output.readAsString();

        expect(html, contains('<html lang="${entry.key.replaceAll('_', '-')}'));
        expect(html, contains(entry.value));
        expect(
          RegExp(r'<svg\b').allMatches(html).length,
          saved.result.measurements.length,
        );
      }
    },
  );
}
