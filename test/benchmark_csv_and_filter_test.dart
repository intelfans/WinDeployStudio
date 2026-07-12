import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:win_deploy_studio/features/benchmark_history/services/benchmark_history_service.dart';

import 'benchmark_test_fixtures.dart';

void main() {
  test(
    'CSV cells neutralize spreadsheet formulas without changing numbers',
    () {
      expect(encodeBenchmarkCsvCell('=1+1'), "'=1+1");
      expect(encodeBenchmarkCsvCell('  +SUM(A1:A2)'), "'  +SUM(A1:A2)");
      expect(encodeBenchmarkCsvCell('-42'), "'-42");
      expect(encodeBenchmarkCsvCell(-42), '-42');
      expect(encodeBenchmarkCsvCell('@cmd'), "'@cmd");
      expect(encodeBenchmarkCsvCell('\tcmd'), "'\tcmd");
      expect(encodeBenchmarkCsvCell('plain'), 'plain');
      expect(encodeBenchmarkCsvCell('hello,world'), '"hello,world"');
      expect(encodeBenchmarkCsvCell('=cmd,"x"'), '"\'=cmd,""x"""');
    },
  );

  test('CSV export sanitizes device identity fields', () async {
    final directory = await Directory.systemTemp.createTemp(
      'wds_benchmark_csv_test_',
    );
    addTearDown(() async {
      if (await directory.exists()) await directory.delete(recursive: true);
    });
    final service = BenchmarkHistoryService(
      directoryProvider: () async => directory,
    );
    final saved = await service.add(
      benchmarkTestResult(
        model: '=HYPERLINK("https://example.invalid")',
        serialNumber: '+cmd',
      ),
    );

    final output = await service.exportCsv(
      p.join(directory.path, 'export.csv'),
      ids: [saved.id],
    );
    final bytes = await output.readAsBytes();
    final text = utf8.decode(bytes.skip(3).toList());

    expect(text, contains("'=HYPERLINK"));
    expect(text, contains("'+cmd"));
    expect(text, isNot(contains(',=HYPERLINK')));
  });

  test('history supports model, serial, VID, and PID filters', () async {
    final directory = await Directory.systemTemp.createTemp(
      'wds_benchmark_filter_test_',
    );
    addTearDown(() async {
      if (await directory.exists()) await directory.delete(recursive: true);
    });
    final service = BenchmarkHistoryService(
      directoryProvider: () async => directory,
    );
    final wanted = await service.add(
      benchmarkTestResult(
        model: 'Portable Alpha',
        serialNumber: 'SERIAL-ALPHA',
        uniqueId: 'UID-ALPHA',
        vid: '1234',
        pid: '5678',
      ),
    );
    await service.add(
      benchmarkTestResult(
        model: 'Portable Beta',
        serialNumber: 'SERIAL-BETA',
        uniqueId: 'UID-BETA',
        vid: 'ABCD',
        pid: 'EF01',
      ),
    );

    final filtered = await service.list(
      model: 'alpha',
      serialNumber: 'serial-alpha',
      vid: '1234',
      pid: '5678',
    );

    expect(filtered.map((record) => record.id), [wanted.id]);
    expect(await service.list(vid: 'ffff'), isEmpty);
  });
}
