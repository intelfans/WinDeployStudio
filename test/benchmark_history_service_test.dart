import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:win_deploy_studio/core/services/disk_safety_service.dart';
import 'package:win_deploy_studio/features/benchmark/models/benchmark_models.dart';
import 'package:win_deploy_studio/features/benchmark_history/services/benchmark_history_service.dart';

void main() {
  late Directory historyDirectory;
  late BenchmarkHistoryService service;

  setUp(() async {
    historyDirectory = await Directory.systemTemp.createTemp(
      'wds_benchmark_history_test_',
    );
    service = BenchmarkHistoryService(
      directoryProvider: () async => historyDirectory,
    );
  });

  tearDown(() async {
    if (await historyDirectory.exists()) {
      await historyDirectory.delete(recursive: true);
    }
  });

  test('stores and restores complete benchmark records', () async {
    final result = _result(
      completedAt: DateTime.utc(2026, 7, 12, 8),
      score: 84,
    );

    final saved = await service.add(result);
    final records = await service.list();

    expect(records, hasLength(1));
    expect(records.single.id, saved.id);
    expect(records.single.result.toJson(), result.toJson());
    expect(
      historyDirectory.listSync().whereType<File>().where(
        (file) => file.path.endsWith('.tmp'),
      ),
      isEmpty,
    );
  });

  test('filters and deletes records by inclusive time range', () async {
    final old = await service.add(
      _result(completedAt: DateTime.utc(2026, 7, 1), score: 60),
    );
    final middle = await service.add(
      _result(completedAt: DateTime.utc(2026, 7, 10), score: 70),
    );
    final recent = await service.add(
      _result(completedAt: DateTime.utc(2026, 7, 12), score: 80),
    );

    final filtered = await service.list(
      from: DateTime.utc(2026, 7, 5),
      to: DateTime.utc(2026, 7, 11),
    );
    final deleted = await service.deleteRange(
      from: DateTime.utc(2026, 7, 5),
      to: DateTime.utc(2026, 7, 11),
    );
    final remaining = await service.list();

    expect(filtered.map((record) => record.id), [middle.id]);
    expect(deleted, 1);
    expect(remaining.map((record) => record.id).toSet(), {old.id, recent.id});
  });

  test('deletes one record and then all remaining records', () async {
    final first = await service.add(
      _result(completedAt: DateTime.utc(2026, 7, 11), score: 70),
    );
    await service.add(
      _result(completedAt: DateTime.utc(2026, 7, 12), score: 80),
    );

    expect(await service.deleteOne(first.id), isTrue);
    expect(await service.deleteOne(first.id), isFalse);
    expect(await service.list(), hasLength(1));
    expect(await service.deleteAll(), 1);
    expect(await service.list(), isEmpty);
  });

  test('exports raw samples to versioned JSON and UTF-8 CSV', () async {
    final saved = await service.add(
      _result(completedAt: DateTime.utc(2026, 7, 12), score: 82),
    );
    final exportDirectory = await Directory.systemTemp.createTemp(
      'wds_benchmark_export_test_',
    );
    addTearDown(() async {
      if (await exportDirectory.exists()) {
        await exportDirectory.delete(recursive: true);
      }
    });

    final jsonFile = await service.exportJson(
      '${exportDirectory.path}${Platform.pathSeparator}history.json',
      ids: [saved.id],
    );
    final csvFile = await service.exportCsv(
      '${exportDirectory.path}${Platform.pathSeparator}history.csv',
      ids: [saved.id],
    );
    final jsonData = jsonDecode(await jsonFile.readAsString());
    final csvBytes = await csvFile.readAsBytes();
    final csvText = utf8.decode(csvBytes.skip(3).toList());

    expect(jsonData['schema'], 'win-deploy-studio/benchmark-history/export');
    expect(jsonData['records'], hasLength(1));
    expect(csvBytes.take(3), [0xEF, 0xBB, 0xBF]);
    expect(csvText, contains('sample_throughput_mbps'));
    expect(csvText, contains('random4kWrite'));
    expect(csvText, contains('SERIAL-1234'));
  });

  test('compares records only when stable device identity matches', () async {
    final baseline = await service.add(
      _result(completedAt: DateTime.utc(2026, 7, 11), score: 70),
    );
    final candidate = await service.add(
      _result(completedAt: DateTime.utc(2026, 7, 12), score: 84),
    );

    final comparison = service.compare(baseline, candidate);

    expect(comparison.metrics, isNotEmpty);
    expect(
      comparison.metrics.firstWhere((metric) => metric.key == 'score').improved,
      isTrue,
    );
  });
}

BenchmarkResult _result({
  required DateTime completedAt,
  required double score,
}) {
  const disk = DiskInfo(
    diskNumber: 3,
    model: 'Portable SSD',
    friendlyName: 'Portable SSD USB Device',
    sizeBytes: 512110190592,
    sizeFormatted: '476.9 GB',
    serialNumber: 'SERIAL-1234',
    uniqueId: 'USB-PORTABLE-SSD-1234',
    devicePath: r'USBSTOR\DISK&VEN_WDS&PROD_PORTABLE\VID_1234&PID_5678',
    busType: 'USB',
    partitionStyle: 'GPT',
    isRemovable: true,
    driveLetters: ['R:'],
  );
  final device = BenchmarkDeviceIdentity.fromDisk(disk);
  const latency = BenchmarkLatency(p50Ms: 0.8, p95Ms: 2.5, p99Ms: 4.1);
  const samples = [
    BenchmarkSample(
      x: 0.5,
      throughputMBps: 25,
      iops: 6400,
      writeMBps: 25,
      latency: latency,
    ),
    BenchmarkSample(
      x: 1,
      throughputMBps: 23,
      iops: 5888,
      writeMBps: 23,
      latency: latency,
    ),
  ];
  const measurement = BenchmarkMeasurement(
    workload: BenchmarkWorkload.random4kWrite,
    averageMBps: 24,
    lowMBps: 23,
    stability: 0.95,
    bytesProcessed: 50331648,
    iops: 6144,
    writeMBps: 24,
    latency: latency,
    samples: samples,
  );

  return BenchmarkResult(
    disk: disk,
    device: device,
    driveRoot: r'R:\',
    mode: BenchmarkMode.standard,
    parameters: BenchmarkRunParameters.forMode(BenchmarkMode.standard),
    duration: const Duration(minutes: 2),
    warmupDuration: const Duration(seconds: 5),
    cooldownDuration: const Duration(seconds: 3),
    sequentialReadMBps: 420,
    sequentialWriteMBps: 380,
    random4kReadAverageMBps: 32,
    random4kReadIops: 8192,
    random4kWriteIops: 6144,
    random4kAverageMBps: 24,
    random4kAdjustedMBps: 22,
    random4kLowMBps: 23,
    random4kStability: 0.95,
    multiThreadPeakMBps: 140,
    multiThreadMultiplier: 1.7,
    multiThreadRetention: 0.9,
    multiThreadNormalizedEfficiency: 0.35,
    fullWriteP10MBps: 120,
    fullWriteEndMBps: 130,
    fullWriteDropRatio: 0.4,
    fullWriteStatus: BenchmarkFullWriteStatus.completed,
    fullWriteAvailableBytes: 20 * 1024 * 1024 * 1024,
    fullWriteTargetBytes: 19 * 1024 * 1024 * 1024,
    slcStatus: BenchmarkSlcStatus.detected,
    slcCacheInflectionGB: 18,
    postCacheStableMBps: 128,
    slcConfidence: 0.88,
    score: score,
    suitability: BenchmarkSuitability.good,
    sequentialReadPoints: const [BenchmarkPoint(x: 1, y: 420)],
    sequentialPoints: const [BenchmarkPoint(x: 1, y: 380)],
    random4kReadPoints: const [BenchmarkPoint(x: 1, y: 32)],
    random4kPoints: const [BenchmarkPoint(x: 1, y: 24)],
    threadPoints: const [BenchmarkPoint(x: 4, y: 140)],
    mixedWorkloadPoints: const [BenchmarkPoint(x: 1, y: 40)],
    fullWritePoints: const [BenchmarkPoint(x: 18, y: 128)],
    measurements: const [measurement],
    completedAt: completedAt,
  );
}
