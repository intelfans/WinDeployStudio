import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../benchmark/models/benchmark_models.dart';
import '../benchmark_history_copy.dart';
import '../models/benchmark_history_models.dart';

final benchmarkHistoryServiceProvider = Provider<BenchmarkHistoryService>((
  ref,
) {
  return BenchmarkHistoryService();
});

typedef BenchmarkHistoryDirectoryProvider = Future<Directory> Function();

class BenchmarkHistoryService {
  static final RegExp _validId = RegExp(r'^[A-Za-z0-9_-]+$');

  final BenchmarkHistoryDirectoryProvider _directoryProvider;
  final Random _random = Random.secure();
  Future<void> _mutationTail = Future<void>.value();

  BenchmarkHistoryService({
    BenchmarkHistoryDirectoryProvider? directoryProvider,
  }) : _directoryProvider = directoryProvider ?? _defaultDirectory;

  static Future<Directory> _defaultDirectory() async {
    final support = await getApplicationSupportDirectory();
    return Directory(
      p.join(
        support.path,
        'benchmark_history',
        'v$benchmarkHistorySchemaVersion',
      ),
    );
  }

  Future<List<BenchmarkHistoryRecord>> list({
    DateTime? from,
    DateTime? to,
    BenchmarkDeviceIdentity? device,
    String? model,
    String? serialNumber,
    String? vid,
    String? pid,
  }) async {
    final directory = await _directoryProvider();
    if (!await directory.exists()) return const [];
    final records = <BenchmarkHistoryRecord>[];
    await for (final entity in directory.list(followLinks: false)) {
      if (entity is! File ||
          p.extension(entity.path).toLowerCase() != '.json') {
        continue;
      }
      try {
        final decoded = jsonDecode(await entity.readAsString());
        if (decoded is! Map) continue;
        final record = BenchmarkHistoryRecord.fromJson(
          Map<String, dynamic>.from(decoded),
        );
        if (record.id.isEmpty ||
            (from != null && record.result.completedAt.isBefore(from)) ||
            (to != null && record.result.completedAt.isAfter(to)) ||
            (device != null && !record.result.device.isSameDevice(device)) ||
            !_containsIdentity(record.result.device.model, model) ||
            !_containsIdentity(
              record.result.device.serialNumber,
              serialNumber,
            ) ||
            !_containsIdentity(record.result.device.vid, vid) ||
            !_containsIdentity(record.result.device.pid, pid)) {
          continue;
        }
        records.add(record);
      } catch (error) {
        debugPrint(
          'Ignoring unreadable benchmark history ${entity.path}: $error',
        );
      }
    }
    records.sort((left, right) {
      return right.result.completedAt.compareTo(left.result.completedAt);
    });
    return List.unmodifiable(records);
  }

  Future<BenchmarkHistoryRecord> add(BenchmarkResult result) {
    return _serializeMutation(() async {
      final directory = await _ensureDirectory();
      final savedAt = DateTime.now();
      final id = _newId(result.completedAt);
      final record = BenchmarkHistoryRecord(
        id: id,
        savedAt: savedAt,
        result: result,
      );
      await _writeRecordAtomically(directory, record);
      return record;
    });
  }

  Future<bool> deleteOne(String id) {
    return _serializeMutation(() async {
      final file = await _recordFile(id);
      if (!await file.exists()) return false;
      await file.delete();
      return true;
    });
  }

  Future<int> deleteAll() {
    return _serializeMutation(() async {
      final directory = await _directoryProvider();
      if (!await directory.exists()) return 0;
      var deleted = 0;
      await for (final entity in directory.list(followLinks: false)) {
        if (entity is File &&
            (p.extension(entity.path).toLowerCase() == '.json' ||
                p.extension(entity.path).toLowerCase() == '.tmp')) {
          await entity.delete();
          deleted++;
        }
      }
      return deleted;
    });
  }

  Future<int> deleteRange({required DateTime from, required DateTime to}) {
    if (to.isBefore(from)) {
      throw ArgumentError.value(to, 'to', 'must not be before from');
    }
    return _serializeMutation(() async {
      final records = await list(from: from, to: to);
      var deleted = 0;
      for (final record in records) {
        final file = await _recordFile(record.id);
        if (await file.exists()) {
          await file.delete();
          deleted++;
        }
      }
      return deleted;
    });
  }

  Future<File> exportJson(
    String destinationPath, {
    Iterable<String>? ids,
  }) async {
    final records = await _selectRecords(ids);
    final export = BenchmarkHistoryExport(
      exportedAt: DateTime.now(),
      records: records,
    );
    final output = File(destinationPath);
    await output.parent.create(recursive: true);
    await output.writeAsString(
      const JsonEncoder.withIndent('  ').convert(export.toJson()),
      flush: true,
    );
    return output;
  }

  Future<File> exportCsv(
    String destinationPath, {
    Iterable<String>? ids,
  }) async {
    final records = await _selectRecords(ids);
    final rows = <List<Object?>>[
      const [
        'record_id',
        'completed_at',
        'mode',
        'disk_model',
        'serial_number',
        'unique_id',
        'vid',
        'pid',
        'device_key',
        'score',
        'workload',
        'threads',
        'read_percent',
        'average_mbps',
        'low_mbps',
        'iops',
        'read_mbps',
        'write_mbps',
        'latency_p50_ms',
        'latency_p95_ms',
        'latency_p99_ms',
        'cache_inflection_gb',
        'cache_stable_mbps',
        'sample_x',
        'sample_throughput_mbps',
        'sample_iops',
        'sample_read_mbps',
        'sample_write_mbps',
        'sample_latency_p50_ms',
        'sample_latency_p95_ms',
        'sample_latency_p99_ms',
      ],
    ];
    for (final record in records) {
      final result = record.result;
      for (final measurement in result.measurements) {
        final samples = measurement.samples.isEmpty
            ? const <BenchmarkSample?>[null]
            : measurement.samples.cast<BenchmarkSample?>();
        for (final sample in samples) {
          rows.add([
            record.id,
            result.completedAt.toUtc().toIso8601String(),
            result.mode.name,
            result.device.model,
            result.device.serialNumber,
            result.device.uniqueId,
            result.device.vid,
            result.device.pid,
            result.device.stableKey,
            result.score,
            measurement.workload.name,
            measurement.threadCount,
            measurement.readPercent,
            measurement.averageMBps,
            measurement.lowMBps,
            measurement.iops,
            measurement.readMBps,
            measurement.writeMBps,
            measurement.latency.p50Ms,
            measurement.latency.p95Ms,
            measurement.latency.p99Ms,
            measurement.cacheInflectionGB,
            measurement.cacheStableMBps,
            sample?.x,
            sample?.throughputMBps,
            sample?.iops,
            sample?.readMBps,
            sample?.writeMBps,
            sample?.latency.p50Ms,
            sample?.latency.p95Ms,
            sample?.latency.p99Ms,
          ]);
        }
      }
    }
    final csv = rows.map(encodeBenchmarkCsvRow).join('\r\n');
    final output = File(destinationPath);
    await output.parent.create(recursive: true);
    await output.writeAsBytes(<int>[
      0xEF,
      0xBB,
      0xBF,
      ...utf8.encode('$csv\r\n'),
    ], flush: true);
    return output;
  }

  BenchmarkComparisonCompatibility compatibilityFor(
    BenchmarkHistoryRecord baseline,
    BenchmarkHistoryRecord candidate,
  ) {
    if (!baseline.result.device.isSameDevice(candidate.result.device)) {
      return const BenchmarkComparisonCompatibility.incompatible(
        BenchmarkComparisonIncompatibility.differentDevice,
      );
    }
    if (baseline.result.protocolVersion != candidate.result.protocolVersion) {
      return const BenchmarkComparisonCompatibility.incompatible(
        BenchmarkComparisonIncompatibility.differentProtocol,
      );
    }
    if (baseline.result.mode != candidate.result.mode) {
      return const BenchmarkComparisonCompatibility.incompatible(
        BenchmarkComparisonIncompatibility.differentMode,
      );
    }
    if (!baseline.result.parameters.isCompatibleWith(
      candidate.result.parameters,
    )) {
      return const BenchmarkComparisonCompatibility.incompatible(
        BenchmarkComparisonIncompatibility.differentParameters,
      );
    }
    return const BenchmarkComparisonCompatibility.compatible();
  }

  BenchmarkComparison compare(
    BenchmarkHistoryRecord baseline,
    BenchmarkHistoryRecord candidate,
  ) {
    final compatibility = compatibilityFor(baseline, candidate);
    if (!compatibility.isCompatible) {
      throw BenchmarkComparisonException(compatibility.incompatibility!);
    }
    final baselineRandom = baseline.result.measurementFor(
      BenchmarkWorkload.random4kWrite,
    );
    final candidateRandom = candidate.result.measurementFor(
      BenchmarkWorkload.random4kWrite,
    );
    final baselineRandomRead = baseline.result.measurementFor(
      BenchmarkWorkload.random4kRead,
    );
    final candidateRandomRead = candidate.result.measurementFor(
      BenchmarkWorkload.random4kRead,
    );
    final metrics = <BenchmarkMetricDelta>[
      _metric(
        'score',
        BenchmarkHistoryKeys.score,
        '',
        baseline.result.suitability == BenchmarkSuitability.unmeasured
            ? null
            : baseline.result.score,
        candidate.result.suitability == BenchmarkSuitability.unmeasured
            ? null
            : candidate.result.score,
      ),
      _metric(
        'sequentialReadMBps',
        BenchmarkHistoryKeys.sequentialRead,
        'MB/s',
        _workloadAverage(
          baseline.result,
          BenchmarkWorkload.sequentialRead,
          baseline.result.sequentialReadMBps,
        ),
        _workloadAverage(
          candidate.result,
          BenchmarkWorkload.sequentialRead,
          candidate.result.sequentialReadMBps,
        ),
      ),
      _metric(
        'sequentialWriteMBps',
        BenchmarkHistoryKeys.sequentialWrite,
        'MB/s',
        _workloadAverage(
          baseline.result,
          BenchmarkWorkload.sequentialWrite,
          baseline.result.sequentialWriteMBps,
        ),
        _workloadAverage(
          candidate.result,
          BenchmarkWorkload.sequentialWrite,
          candidate.result.sequentialWriteMBps,
        ),
      ),
      _metric(
        'random4kReadAverageMBps',
        BenchmarkHistoryKeys.randomRead,
        'MB/s',
        _workloadAverage(
          baseline.result,
          BenchmarkWorkload.random4kRead,
          baseline.result.random4kReadAverageMBps,
        ),
        _workloadAverage(
          candidate.result,
          BenchmarkWorkload.random4kRead,
          candidate.result.random4kReadAverageMBps,
        ),
      ),
      _metric(
        'random4kWriteAverageMBps',
        BenchmarkHistoryKeys.randomWrite,
        'MB/s',
        _workloadAverage(
          baseline.result,
          BenchmarkWorkload.random4kWrite,
          baseline.result.random4kAverageMBps,
        ),
        _workloadAverage(
          candidate.result,
          BenchmarkWorkload.random4kWrite,
          candidate.result.random4kAverageMBps,
        ),
      ),
      _metric(
        'random4kReadIops',
        BenchmarkHistoryKeys.randomRead,
        'IOPS',
        _positiveOrNull(
          baselineRandomRead?.iops ?? baseline.result.random4kReadIops,
        ),
        _positiveOrNull(
          candidateRandomRead?.iops ?? candidate.result.random4kReadIops,
        ),
      ),
      _metric(
        'random4kWriteIops',
        BenchmarkHistoryKeys.randomWrite,
        'IOPS',
        _positiveOrNull(
          baselineRandom?.iops ?? baseline.result.random4kWriteIops,
        ),
        _positiveOrNull(
          candidateRandom?.iops ?? candidate.result.random4kWriteIops,
        ),
      ),
      _metric(
        'randomReadP50',
        BenchmarkHistoryKeys.randomReadLatencyP50,
        'ms',
        _positiveOrNull(baselineRandomRead?.latency.p50Ms),
        _positiveOrNull(candidateRandomRead?.latency.p50Ms),
        lowerIsBetter: true,
      ),
      _metric(
        'randomReadP95',
        BenchmarkHistoryKeys.randomReadLatencyP95,
        'ms',
        _positiveOrNull(baselineRandomRead?.latency.p95Ms),
        _positiveOrNull(candidateRandomRead?.latency.p95Ms),
        lowerIsBetter: true,
      ),
      _metric(
        'randomReadP99',
        BenchmarkHistoryKeys.randomReadLatencyP99,
        'ms',
        _positiveOrNull(baselineRandomRead?.latency.p99Ms),
        _positiveOrNull(candidateRandomRead?.latency.p99Ms),
        lowerIsBetter: true,
      ),
      _metric(
        'randomP50',
        BenchmarkHistoryKeys.randomWriteLatencyP50,
        'ms',
        _positiveOrNull(baselineRandom?.latency.p50Ms),
        _positiveOrNull(candidateRandom?.latency.p50Ms),
        lowerIsBetter: true,
      ),
      _metric(
        'randomP95',
        BenchmarkHistoryKeys.randomWriteLatencyP95,
        'ms',
        _positiveOrNull(baselineRandom?.latency.p95Ms),
        _positiveOrNull(candidateRandom?.latency.p95Ms),
        lowerIsBetter: true,
      ),
      _metric(
        'randomP99',
        BenchmarkHistoryKeys.randomWriteLatencyP99,
        'ms',
        _positiveOrNull(baselineRandom?.latency.p99Ms),
        _positiveOrNull(candidateRandom?.latency.p99Ms),
        lowerIsBetter: true,
      ),
      _metric(
        'multiThreadPeakMBps',
        BenchmarkHistoryKeys.multiThreadPeak,
        'MB/s',
        _threadMetric(baseline.result, baseline.result.multiThreadPeakMBps),
        _threadMetric(candidate.result, candidate.result.multiThreadPeakMBps),
      ),
      _metric(
        'multiThreadMultiplier',
        BenchmarkHistoryKeys.multiThreadScale,
        'x',
        _threadMetric(baseline.result, baseline.result.multiThreadMultiplier),
        _threadMetric(candidate.result, candidate.result.multiThreadMultiplier),
      ),
      _metric(
        'multiThreadRetention',
        BenchmarkHistoryKeys.multiThreadScale,
        '%',
        _threadMetric(
          baseline.result,
          baseline.result.multiThreadRetention * 100,
        ),
        _threadMetric(
          candidate.result,
          candidate.result.multiThreadRetention * 100,
        ),
      ),
      _metric(
        'multiThreadNormalizedEfficiency',
        BenchmarkHistoryKeys.multiThreadScale,
        '%',
        _threadMetric(
          baseline.result,
          baseline.result.multiThreadNormalizedEfficiency * 100,
        ),
        _threadMetric(
          candidate.result,
          candidate.result.multiThreadNormalizedEfficiency * 100,
        ),
      ),
      _metric(
        'slcCacheInflectionGB',
        BenchmarkHistoryKeys.slcInflection,
        'GB',
        baseline.result.slcStatus == BenchmarkSlcStatus.detected
            ? baseline.result.slcCacheInflectionGB
            : null,
        candidate.result.slcStatus == BenchmarkSlcStatus.detected
            ? candidate.result.slcCacheInflectionGB
            : null,
      ),
      _metric(
        'postCacheStableMBps',
        BenchmarkHistoryKeys.postCacheStable,
        'MB/s',
        baseline.result.slcStatus == BenchmarkSlcStatus.detected
            ? baseline.result.postCacheStableMBps
            : null,
        candidate.result.slcStatus == BenchmarkSlcStatus.detected
            ? candidate.result.postCacheStableMBps
            : null,
      ),
    ];
    for (final scenario in MixedWorkloadScenario.values) {
      final baselineScenario = baseline.result.measurementFor(
        scenario.workload,
      );
      final candidateScenario = candidate.result.measurementFor(
        scenario.workload,
      );
      metrics.add(
        _metric(
          'scenario.${scenario.protocolName}',
          BenchmarkHistoryKeys.workload(scenario.workload),
          'IOPS',
          _positiveOrNull(baselineScenario?.iops),
          _positiveOrNull(candidateScenario?.iops),
        ),
      );
    }
    return BenchmarkComparison(
      baseline: baseline,
      candidate: candidate,
      metrics: List.unmodifiable(metrics),
    );
  }

  Future<List<BenchmarkHistoryRecord>> _selectRecords(
    Iterable<String>? ids,
  ) async {
    final records = await list();
    if (ids == null) return records;
    final selected = ids.toSet();
    return records
        .where((record) => selected.contains(record.id))
        .toList(growable: false);
  }

  Future<Directory> _ensureDirectory() async {
    final directory = await _directoryProvider();
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }
    return directory;
  }

  Future<File> _recordFile(String id) async {
    if (!_validId.hasMatch(id)) {
      throw ArgumentError.value(id, 'id', 'contains invalid characters');
    }
    final directory = await _directoryProvider();
    return File(p.join(directory.path, '$id.json'));
  }

  Future<void> _writeRecordAtomically(
    Directory directory,
    BenchmarkHistoryRecord record,
  ) async {
    final target = File(p.join(directory.path, '${record.id}.json'));
    if (await target.exists()) {
      throw StateError('Benchmark history id already exists');
    }
    final temporary = File(
      p.join(directory.path, '.${record.id}.${_random.nextInt(1 << 32)}.tmp'),
    );
    try {
      await temporary.writeAsString(jsonEncode(record.toJson()), flush: true);
      await temporary.rename(target.path);
    } catch (_) {
      if (await temporary.exists()) {
        try {
          await temporary.delete();
        } catch (_) {}
      }
      rethrow;
    }
  }

  String _newId(DateTime completedAt) {
    final micros = completedAt.toUtc().microsecondsSinceEpoch;
    final random = _random.nextInt(1 << 32).toRadixString(16).padLeft(8, '0');
    return 'bench_${micros}_$random';
  }

  Future<T> _serializeMutation<T>(Future<T> Function() action) {
    final completer = Completer<T>();
    _mutationTail = _mutationTail.then((_) async {
      try {
        completer.complete(await action());
      } catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      }
    });
    return completer.future;
  }
}

BenchmarkMetricDelta _metric(
  String key,
  String label,
  String unit,
  double? baseline,
  double? candidate, {
  bool lowerIsBetter = false,
}) {
  return BenchmarkMetricDelta(
    key: key,
    label: label,
    unit: unit,
    baseline: baseline,
    candidate: candidate,
    lowerIsBetter: lowerIsBetter,
  );
}

bool _containsIdentity(String value, String? filter) {
  final query = filter?.trim().toUpperCase() ?? '';
  return query.isEmpty || value.trim().toUpperCase().contains(query);
}

double? _positiveOrNull(double? value) {
  if (value == null || !value.isFinite || value <= 0) return null;
  return value;
}

double? _workloadAverage(
  BenchmarkResult result,
  BenchmarkWorkload workload,
  double legacyValue,
) {
  return _positiveOrNull(
    result.measurementFor(workload)?.averageMBps ?? legacyValue,
  );
}

double? _threadMetric(BenchmarkResult result, double value) {
  final measurements = result.measurementsFor(
    BenchmarkWorkload.random4kMultiThread,
  );
  if (measurements.length < 2 && result.threadPoints.length < 2) return null;
  return _positiveOrNull(value);
}

String encodeBenchmarkCsvRow(List<Object?> values) =>
    values.map(encodeBenchmarkCsvCell).join(',');

String encodeBenchmarkCsvCell(Object? value) {
  if (value == null) return '';
  var text = value.toString();
  if (value is String &&
      (RegExp(r'^[\t\r\n]').hasMatch(text) ||
          RegExp(r'^[\t\r\n ]*[=+\-@]').hasMatch(text))) {
    text = "'$text";
  }
  if (!text.contains(RegExp('[,"\\r\\n]'))) return text;
  return '"${text.replaceAll('"', '""')}"';
}
