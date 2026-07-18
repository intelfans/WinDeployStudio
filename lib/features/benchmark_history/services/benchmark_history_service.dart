import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../../core/localization/strings.dart';
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

  /// Deletes the supplied history records atomically with other history
  /// mutations. Unknown ids are ignored so stale selections remain harmless.
  Future<int> deleteMany(Iterable<String> ids) {
    final uniqueIds = ids.toSet();
    return _serializeMutation(() async {
      var deleted = 0;
      for (final id in uniqueIds) {
        final file = await _recordFile(id);
        if (await file.exists()) {
          await file.delete();
          deleted++;
        }
      }
      return deleted;
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

  /// Writes a self-contained, human-readable HTML report.
  ///
  /// The report deliberately has no external assets, scripts, or stylesheets
  /// so that it can be opened offline and safely attached to a support ticket.
  /// The complete record JSON is embedded in each record's raw-data section;
  /// the tables and inline SVG chart provide a quick visual summary.
  Future<File> exportHtml(
    String destinationPath, {
    Iterable<String>? ids,

    /// Locale code used for visible report text (for example `zh`, `zh_TW`,
    /// or `fr`). Callers should pass the active application locale explicitly.
    /// English is used only as a deterministic fallback for non-UI callers.
    String localeCode = 'en',
  }) async {
    final records = await _selectRecords(ids);
    final output = File(destinationPath);
    await output.parent.create(recursive: true);
    await output.writeAsString(
      _buildBenchmarkHtmlReport(
        records,
        exportedAt: DateTime.now(),
        localeCode: localeCode,
      ),
      encoding: utf8,
      flush: true,
    );
    return output;
  }

  BenchmarkComparisonCompatibility compatibilityFor(
    BenchmarkHistoryRecord baseline,
    BenchmarkHistoryRecord candidate,
  ) {
    // Results from different physical disks are intentionally comparable. The
    // comparison screen identifies both devices so users can make the context
    // explicit; only protocol and test configuration must match.
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

String _buildBenchmarkHtmlReport(
  List<BenchmarkHistoryRecord> records, {
  required DateTime exportedAt,
  required String localeCode,
}) {
  final labels = _HtmlReportLabels(localeCode);
  final locale = labels.locale;
  final lang = locale.replaceAll('_', '-');
  final buffer = StringBuffer()
    ..write('<!doctype html>')
    ..write(
      '<html lang="$lang"${locale == 'ar' ? ' dir="rtl"' : ''}><head><meta charset="utf-8">',
    )
    ..write(
      '<meta name="viewport" content="width=device-width,initial-scale=1">',
    )
    ..write('<title>${_escapeHtml(labels.text('reportTitle'))}</title>')
    ..write('''<style>
:root { color-scheme: light dark; --bg: #f5f7fb; --surface: #fff; --ink: #172033; --muted: #667085; --line: #d9dee9; --accent: #2563eb; }
@media (prefers-color-scheme: dark) { :root { --bg: #111827; --surface: #1f2937; --ink: #f3f4f6; --muted: #aab4c3; --line: #3a4658; --accent: #70a0ff; } }
* { box-sizing: border-box; }
body { margin: 0; padding: 28px; background: var(--bg); color: var(--ink); font: 14px/1.5 system-ui, -apple-system, "Segoe UI", sans-serif; }
main { max-width: 1180px; margin: 0 auto; }
h1 { margin: 0 0 6px; font-size: 28px; letter-spacing: -.01em; }
h2 { margin: 0; font-size: 20px; }
h3 { margin: 22px 0 8px; font-size: 15px; }
.muted { color: var(--muted); }
.header { margin-bottom: 24px; }
.record { margin: 20px 0 28px; padding: 24px; background: var(--surface); border: 1px solid var(--line); border-radius: 14px; box-shadow: 0 5px 18px rgba(17, 24, 39, .06); }
.record-header { display: flex; flex-wrap: wrap; justify-content: space-between; align-items: baseline; gap: 8px 20px; }
.grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(260px, 1fr)); gap: 14px; margin-top: 14px; }
.panel { min-width: 0; padding: 14px; border: 1px solid var(--line); border-radius: 10px; }
.panel h3 { margin-top: 0; }
.charts { display: grid; grid-template-columns: repeat(auto-fit, minmax(360px, 1fr)); gap: 16px; margin-top: 8px; }
.chart h4 { margin: 0 0 8px; font-size: 14px; }
dl { display: grid; grid-template-columns: minmax(120px, 42%) 1fr; gap: 5px 12px; margin: 0; }
dt { color: var(--muted); overflow-wrap: anywhere; }
dd { margin: 0; overflow-wrap: anywhere; font-variant-numeric: tabular-nums; }
table { width: 100%; border-collapse: collapse; margin-top: 8px; font-variant-numeric: tabular-nums; }
th, td { padding: 7px 8px; border-bottom: 1px solid var(--line); text-align: left; vertical-align: top; }
th { color: var(--muted); font-size: 12px; font-weight: 600; }
tbody tr:last-child td { border-bottom: 0; }
.table-wrap { overflow-x: auto; }
.chart { margin-top: 8px; padding: 10px; border: 1px solid var(--line); border-radius: 10px; }
.chart svg { display: block; width: 100%; height: auto; min-height: 230px; }
details { margin-top: 14px; border: 1px solid var(--line); border-radius: 10px; }
summary { cursor: pointer; padding: 10px 12px; color: var(--muted); }
pre { max-height: 580px; overflow: auto; margin: 0; padding: 14px; border-top: 1px solid var(--line); font: 12px/1.45 ui-monospace, SFMono-Regular, Consolas, monospace; white-space: pre-wrap; overflow-wrap: anywhere; }
.empty { padding: 24px; color: var(--muted); text-align: center; }
@media print { body { padding: 0; background: #fff; } .record { break-inside: avoid; box-shadow: none; } details { display: none; } }
</style>''')
    ..write('</head><body><main>')
    ..write(
      '<header class="header"><h1>${_escapeHtml(labels.text('reportTitle'))}</h1>',
    )
    ..write(
      '<div class="muted">${_escapeHtml(labels.text('exported'))} ${_escapeHtml(_formatHtmlDate(exportedAt))} · ${records.length} ${_escapeHtml(labels.text('records'))}</div></header>',
    );

  if (records.isEmpty) {
    buffer.write(
      '<section class="record"><div class="empty">${_escapeHtml(labels.text('noRecords'))}</div></section>',
    );
  } else {
    for (var index = 0; index < records.length; index++) {
      _writeBenchmarkRecordHtml(buffer, records[index], index + 1, labels);
    }
  }
  buffer.write('</main></body></html>');
  return buffer.toString();
}

void _writeBenchmarkRecordHtml(
  StringBuffer buffer,
  BenchmarkHistoryRecord record,
  int ordinal,
  _HtmlReportLabels labels,
) {
  final result = record.result;
  final identity = <String, Object?>{
    labels.app(BenchmarkHistoryKeys.model): result.device.model,
    labels.text('friendlyName'): result.device.friendlyName,
    labels.app(BenchmarkHistoryKeys.serialNumber): result.device.serialNumber,
    labels.app(BenchmarkHistoryKeys.uniqueId): result.device.uniqueId,
    labels.app(BenchmarkHistoryKeys.vidPid): _joinIdentifier(
      result.device.vid,
      result.device.pid,
    ),
    labels.app(BenchmarkHistoryKeys.bus): result.device.busType,
    labels.text('devicePath'): result.device.devicePath,
    labels.text('diskNumber'): result.device.diskNumber,
    labels.text('capacityBytes'): result.device.sizeBytes,
    labels.app(BenchmarkHistoryKeys.capacity): result.disk.sizeFormatted,
    labels.text('stableIdentity'): result.device.stableKey,
    labels.text('driveRoot'): result.driveRoot,
    labels.app('ai_prompt_partition_style'): result.disk.partitionStyle,
    labels.app('ai_prompt_drive_letters'): result.disk.driveLetters,
    labels.text('systemDisk'): result.disk.isSystem,
    labels.text('bootDisk'): result.disk.isBoot,
    labels.text('offline'): result.disk.isOffline,
    labels.text('removable'): result.disk.isRemovable,
  };
  final summary = <String, Object?>{
    labels.app(BenchmarkHistoryKeys.mode): labels.mode(result.mode),
    labels.text('protocol'): result.protocolVersion,
    labels.app(BenchmarkHistoryKeys.completed): result.completedAt,
    labels.app(BenchmarkHistoryKeys.duration): result.durationText,
    labels.app(BenchmarkHistoryKeys.score): _formatHtmlNumber(
      result.score,
      labels,
    ),
    labels.text('suitability'): labels.suitability(result.suitability),
    '${labels.app(BenchmarkHistoryKeys.sequentialRead)} (MB/s)':
        _formatHtmlNumber(result.sequentialReadMBps, labels),
    '${labels.app(BenchmarkHistoryKeys.sequentialWrite)} (MB/s)':
        _formatHtmlNumber(result.sequentialWriteMBps, labels),
    '${labels.app(BenchmarkHistoryKeys.randomRead)} (MB/s)': _formatHtmlNumber(
      result.random4kReadAverageMBps,
      labels,
    ),
    '${labels.app(BenchmarkHistoryKeys.randomWrite)} (MB/s)': _formatHtmlNumber(
      result.random4kAverageMBps,
      labels,
    ),
    '${labels.app(BenchmarkHistoryKeys.randomRead)} IOPS': _formatHtmlNumber(
      result.random4kReadIops,
      labels,
    ),
    '${labels.app(BenchmarkHistoryKeys.randomWrite)} IOPS': _formatHtmlNumber(
      result.random4kWriteIops,
      labels,
    ),
    '${labels.app(BenchmarkHistoryKeys.multiThreadPeak)} (MB/s)':
        _formatHtmlNumber(result.multiThreadPeakMBps, labels),
    labels.text('fullWriteStatus'): labels.fullWriteStatus(
      result.fullWriteStatus,
    ),
    '${labels.app(BenchmarkHistoryKeys.fullWriteP10)} (MB/s)':
        _formatHtmlNumber(result.fullWriteP10MBps, labels),
    labels.text('slcStatus'): labels.slcStatus(result.slcStatus),
    '${labels.app(BenchmarkHistoryKeys.slcInflection)} (GB)': _formatHtmlNumber(
      result.slcCacheInflectionGB,
      labels,
    ),
  };

  buffer
    ..write('<article class="record"><div class="record-header">')
    ..write('<h2>#$ordinal ${_escapeHtml(_recordTitle(result, labels))}</h2>')
    ..write(
      '<span class="muted">${_escapeHtml(labels.text('recordId'))} ${_escapeHtml(record.id)}</span></div>',
    )
    ..write('<div class="grid">')
    ..write(
      '<section class="panel"><h3>${_escapeHtml(labels.app(BenchmarkHistoryKeys.deviceIdentity))}</h3>',
    )
    ..write(_definitionList(identity, labels))
    ..write(
      '</section><section class="panel"><h3>${_escapeHtml(labels.text('summaryTitle'))}</h3>',
    )
    ..write(_definitionList(summary, labels))
    ..write(
      '</section><section class="panel"><h3>${_escapeHtml(labels.text('parametersTitle'))}</h3>',
    )
    ..write(
      _definitionList(_parameterValues(result.parameters, labels), labels),
    )
    ..write('</section></div>')
    ..write('<h3>${_escapeHtml(labels.text('chartsTitle'))}</h3>')
    ..write(_performanceCharts(result, labels))
    ..write(
      '<h3>${_escapeHtml(labels.app(BenchmarkHistoryKeys.measurements))}</h3>',
    )
    ..write(_measurementTable(result, labels))
    ..write(
      '<details><summary>${_escapeHtml(labels.text('rawDataTitle'))}</summary><pre>',
    )
    ..write(
      _escapeHtml(const JsonEncoder.withIndent('  ').convert(record.toJson())),
    )
    ..write('</pre></details></article>');
}

String _recordTitle(BenchmarkResult result, _HtmlReportLabels labels) {
  final friendly = result.device.friendlyName.trim();
  if (friendly.isNotEmpty) return friendly;
  final model = result.device.model.trim();
  return model.isNotEmpty ? model : labels.text('unnamedDisk');
}

String _joinIdentifier(String vid, String pid) {
  final values = [vid.trim(), pid.trim()].where((value) => value.isNotEmpty);
  return values.join(' / ');
}

Map<String, Object?> _parameterValues(
  BenchmarkRunParameters parameters,
  _HtmlReportLabels labels,
) => <String, Object?>{
  labels.text('sequentialSeconds'): '${parameters.sequentialSeconds} s',
  labels.text('random4kSeconds'): '${parameters.random4kSeconds} s',
  labels.text('mixedWorkloadSeconds'): '${parameters.mixedWorkloadSeconds} s',
  labels.text('threadSeconds'): '${parameters.threadSeconds} s',
  labels.text('sequentialLimit'): _formatHtmlByteCount(
    parameters.sequentialLimitBytes,
    labels,
  ),
  labels.text('randomFileSize'): _formatHtmlByteCount(
    parameters.randomFileBytes,
    labels,
  ),
  labels.text('warmup'): '${parameters.warmupMs} ms',
  labels.text('cooldown'): '${parameters.cooldownMs} ms',
  labels.text('fullWriteCooldown'): '${parameters.fullWriteCooldownMs} ms',
  labels.text('fullWriteReserve'): _formatHtmlByteCount(
    parameters.fullWriteReserveBytes,
    labels,
  ),
  labels.text('fullWriteMinimum'): _formatHtmlByteCount(
    parameters.fullWriteMinimumBytes,
    labels,
  ),
  labels.app(BenchmarkHistoryKeys.threads): parameters.threadCounts,
  labels.text('fullWriteScope'): labels.fullWriteScope(
    parameters.fullWriteScope,
  ),
};

String _definitionList(Map<String, Object?> values, _HtmlReportLabels labels) {
  final buffer = StringBuffer('<dl>');
  for (final entry in values.entries) {
    buffer
      ..write('<dt>${_escapeHtml(entry.key)}</dt>')
      ..write('<dd>${_escapeHtml(_formatHtmlValue(entry.value, labels))}</dd>');
  }
  buffer.write('</dl>');
  return buffer.toString();
}

String _measurementTable(BenchmarkResult result, _HtmlReportLabels labels) {
  if (result.measurements.isEmpty) {
    return '<div class="panel empty">${_escapeHtml(labels.app(BenchmarkHistoryKeys.noSamples))}</div>';
  }
  final buffer = StringBuffer()
    ..write('<div class="table-wrap"><table><thead><tr>')
    ..write(
      '<th>${_escapeHtml(labels.text('workload'))}</th><th>${_escapeHtml(labels.app(BenchmarkHistoryKeys.threads))}</th><th>${_escapeHtml(labels.text('readPercent'))}</th><th>${_escapeHtml(labels.text('averageMBps'))}</th>',
    )
    ..write(
      '<th>${_escapeHtml(labels.text('lowMBps'))}</th><th>${_escapeHtml(labels.text('stability'))}</th><th>${_escapeHtml(labels.app(BenchmarkHistoryKeys.iops))}</th><th>${_escapeHtml(labels.text('readMBps'))}</th>',
    )
    ..write(
      '<th>${_escapeHtml(labels.text('writeMBps'))}</th><th>${_escapeHtml(labels.text('bytes'))}</th><th>${_escapeHtml(labels.text('samples'))}</th></tr></thead><tbody>',
    );
  for (final measurement in result.measurements) {
    buffer
      ..write(
        '<tr><td>${_escapeHtml(labels.workload(measurement.workload))}</td>',
      )
      ..write(
        '<td>${measurement.threadCount}</td><td>${measurement.readPercent}</td>',
      )
      ..write('<td>${_formatHtmlNumber(measurement.averageMBps, labels)}</td>')
      ..write('<td>${_formatHtmlNumber(measurement.lowMBps, labels)}</td>')
      ..write('<td>${_formatHtmlNumber(measurement.stability, labels)}</td>')
      ..write('<td>${_formatHtmlNumber(measurement.iops, labels)}</td>')
      ..write('<td>${_formatHtmlNumber(measurement.readMBps, labels)}</td>')
      ..write('<td>${_formatHtmlNumber(measurement.writeMBps, labels)}</td>')
      ..write(
        '<td>${measurement.bytesProcessed}</td><td>${measurement.samples.length}</td></tr>',
      );
  }
  buffer.write('</tbody></table></div>');
  return buffer.toString();
}

String _performanceCharts(BenchmarkResult result, _HtmlReportLabels labels) {
  final charts = _chartSeries(result, labels);
  if (charts.isEmpty) {
    return '<div class="panel empty">${_escapeHtml(labels.app(BenchmarkHistoryKeys.noSamples))}</div>';
  }
  final buffer = StringBuffer('<div class="charts">');
  for (var index = 0; index < charts.length; index++) {
    final chart = charts[index];
    buffer
      ..write('<section class="chart"><h4>${_escapeHtml(chart.label)}</h4>')
      ..write(_benchmarkSvg(chart, labels, index))
      ..write('</section>');
  }
  buffer.write('</div>');
  return buffer.toString();
}

String _benchmarkSvg(
  _HtmlChartSeries chart,
  _HtmlReportLabels labels,
  int colorIndex,
) {
  const width = 960.0;
  const height = 300.0;
  const left = 62.0;
  const right = 18.0;
  const top = 18.0;
  const bottom = 36.0;
  final chartWidth = width - left - right;
  final chartHeight = height - top - bottom;
  final minX = chart.points.map((point) => point.x).reduce(min);
  final maxX = chart.points.map((point) => point.x).reduce(max);
  final maxY = max(
    1.0,
    chart.points.map((point) => point.throughputMBps).reduce(max) * 1.12,
  );
  final xRange = max(0.000001, maxX - minX);
  double xPosition(double value) =>
      left + ((value - minX) / xRange) * chartWidth;
  double yPosition(double value) =>
      top + chartHeight - (value / maxY) * chartHeight;

  final buffer = StringBuffer()
    ..write('<svg viewBox="0 0 $width $height" role="img" aria-label="')
    ..write(_escapeHtml('${labels.text('chartsTitle')}: ${chart.label}'))
    ..write('" xmlns="http://www.w3.org/2000/svg">')
    ..write('<rect width="100%" height="100%" fill="transparent"/>');
  for (var index = 0; index <= 4; index++) {
    final ratio = index / 4;
    final y = top + chartHeight * ratio;
    final label = _formatHtmlNumber(maxY * (1 - ratio), labels);
    buffer
      ..write('<line x1="$left" y1="$y" x2="${left + chartWidth}" y2="$y" ')
      ..write('stroke="#cbd5e1" stroke-width="1" stroke-dasharray="3 4"/>')
      ..write('<text x="${left - 8}" y="${y + 4}" text-anchor="end" ')
      ..write('fill="#64748b" font-size="11">${_escapeHtml(label)}</text>');
  }
  buffer
    ..write(
      '<line x1="$left" y1="$top" x2="$left" y2="${top + chartHeight}" stroke="#94a3b8"/>',
    )
    ..write(
      '<line x1="$left" y1="${top + chartHeight}" x2="${left + chartWidth}" y2="${top + chartHeight}" stroke="#94a3b8"/>',
    )
    ..write(
      '<text x="$left" y="${height - 8}" fill="#64748b" font-size="11">${_escapeHtml(labels.text('chartXAxis'))}</text>',
    )
    ..write(
      '<text x="${left + chartWidth}" y="${height - 8}" text-anchor="end" fill="#64748b" font-size="11">MB/s</text>',
    );

  final path = StringBuffer();
  for (var pointIndex = 0; pointIndex < chart.points.length; pointIndex++) {
    final point = chart.points[pointIndex];
    path
      ..write(pointIndex == 0 ? 'M ' : ' L ')
      ..write(
        '${xPosition(point.x).toStringAsFixed(2)} ${yPosition(point.throughputMBps).toStringAsFixed(2)}',
      );
  }
  final color = _htmlChartColors[colorIndex % _htmlChartColors.length];
  buffer
    ..write(
      '<path d="${path.toString()}" fill="none" stroke="$color" stroke-width="2.8" ',
    )
    ..write('stroke-linecap="round" stroke-linejoin="round"/>');
  buffer.write('</svg>');
  return buffer.toString();
}

class _HtmlChartSeries {
  final String label;
  final List<BenchmarkSample> points;

  const _HtmlChartSeries(this.label, this.points);
}

/// Keeps the standalone report readable without depending on Flutter's widget
/// tree. The app translations cover shared benchmark terms; this table covers
/// report-only labels that do not otherwise exist in the UI catalog.
class _HtmlReportLabels {
  final String locale;

  const _HtmlReportLabels._(this.locale);

  factory _HtmlReportLabels(String localeCode) {
    final normalized = normalizeLocaleCode(localeCode);
    return _HtmlReportLabels._(
      supportedLocaleCodes.contains(normalized) ? normalized : 'en',
    );
  }

  String app(String key) {
    final localized = trByCode(locale, key);
    if (localized.isNotEmpty && localized != 'translation_missing') {
      return localized;
    }
    final english = trByCode('en', key);
    return english.isEmpty ? key : english;
  }

  String text(String key) =>
      (_htmlReportText[locale] ?? _htmlReportText['en']!)[key] ??
      _htmlReportText['en']![key] ??
      key;

  String mode(BenchmarkMode value) => app(value.titleKey);

  String suitability(BenchmarkSuitability value) => app(value.titleKey);

  String workload(BenchmarkWorkload value) =>
      app(BenchmarkHistoryKeys.workload(value));

  String fullWriteStatus(BenchmarkFullWriteStatus value) =>
      text(switch (value) {
        BenchmarkFullWriteStatus.notRun => 'fullWriteNotRun',
        BenchmarkFullWriteStatus.insufficientSpace =>
          'fullWriteInsufficientSpace',
        BenchmarkFullWriteStatus.completed => 'fullWriteCompleted',
      });

  String slcStatus(BenchmarkSlcStatus value) => text(switch (value) {
    BenchmarkSlcStatus.notRun => 'slcNotRun',
    BenchmarkSlcStatus.insufficientRange => 'slcInsufficientRange',
    BenchmarkSlcStatus.noInflection => 'slcNoInflection',
    BenchmarkSlcStatus.detected => 'slcDetected',
  });

  String fullWriteScope(BenchmarkFullWriteScope value) => text(switch (value) {
    BenchmarkFullWriteScope.selectedVolumeAvailableSpace =>
      'scopeSelectedVolume',
  });
}

const _htmlReportText = <String, Map<String, String>>{
  'en': {
    'reportTitle': 'WinDeploy Studio Disk Benchmark Report',
    'exported': 'Exported',
    'records': 'record(s)',
    'noRecords': 'No benchmark records were selected.',
    'friendlyName': 'Friendly name',
    'devicePath': 'Device path',
    'diskNumber': 'Disk number',
    'capacityBytes': 'Capacity (bytes)',
    'stableIdentity': 'Stable identity',
    'driveRoot': 'Drive root',
    'systemDisk': 'System disk',
    'bootDisk': 'Boot disk',
    'offline': 'Offline',
    'removable': 'Removable',
    'protocol': 'Protocol',
    'suitability': 'Suitability',
    'fullWriteStatus': 'Full-write status',
    'slcStatus': 'SLC status',
    'recordId': 'Record',
    'summaryTitle': 'Summary',
    'parametersTitle': 'Test parameters',
    'chartsTitle': 'Performance curves',
    'rawDataTitle': 'Raw data (complete JSON)',
    'unnamedDisk': 'Disk benchmark',
    'sequentialSeconds': 'Sequential duration',
    'random4kSeconds': '4K random duration',
    'mixedWorkloadSeconds': 'Mixed-workload duration',
    'threadSeconds': 'Thread duration',
    'sequentialLimit': 'Sequential data limit',
    'randomFileSize': 'Random test file size',
    'warmup': 'Warm-up',
    'cooldown': 'Cooldown',
    'fullWriteCooldown': 'Full-write cooldown',
    'fullWriteReserve': 'Full-write reserved space',
    'fullWriteMinimum': 'Full-write minimum space',
    'fullWriteScope': 'Full-write scope',
    'workload': 'Workload',
    'readPercent': 'Read %',
    'averageMBps': 'Average MB/s',
    'lowMBps': 'Low MB/s',
    'stability': 'Stability',
    'readMBps': 'Read MB/s',
    'writeMBps': 'Write MB/s',
    'bytes': 'Bytes',
    'samples': 'Samples',
    'chartXAxis': 'Sample',
    'notAvailable': 'N/A',
    'yes': 'Yes',
    'no': 'No',
    'fullWriteNotRun': 'Not run',
    'fullWriteInsufficientSpace': 'Insufficient space',
    'fullWriteCompleted': 'Completed',
    'slcNotRun': 'Not run',
    'slcInsufficientRange': 'Insufficient range',
    'slcNoInflection': 'No inflection detected',
    'slcDetected': 'Detected',
    'scopeSelectedVolume': 'Available space on the selected volume',
  },
  'zh': {
    'reportTitle': 'WinDeploy Studio 磁盘测试报告',
    'exported': '导出时间',
    'records': '条记录',
    'noRecords': '未选择任何磁盘测试记录。',
    'friendlyName': '友好名称',
    'devicePath': '设备路径',
    'diskNumber': '磁盘编号',
    'capacityBytes': '容量（字节）',
    'stableIdentity': '稳定标识',
    'driveRoot': '驱动器根目录',
    'systemDisk': '系统磁盘',
    'bootDisk': '引导磁盘',
    'offline': '脱机',
    'removable': '可移动设备',
    'protocol': '协议',
    'suitability': '适用性',
    'fullWriteStatus': '全盘写入状态',
    'slcStatus': 'SLC 状态',
    'recordId': '记录',
    'summaryTitle': '摘要',
    'parametersTitle': '测试参数',
    'chartsTitle': '性能曲线',
    'rawDataTitle': '原始数据（完整 JSON）',
    'unnamedDisk': '磁盘测试',
    'sequentialSeconds': '顺序测试时长',
    'random4kSeconds': '4K 随机测试时长',
    'mixedWorkloadSeconds': '混合负载测试时长',
    'threadSeconds': '多线程测试时长',
    'sequentialLimit': '顺序测试数据上限',
    'randomFileSize': '随机测试文件大小',
    'warmup': '预热',
    'cooldown': '冷却',
    'fullWriteCooldown': '全盘写入冷却',
    'fullWriteReserve': '全盘写入预留空间',
    'fullWriteMinimum': '全盘写入最小空间',
    'fullWriteScope': '全盘写入范围',
    'workload': '测试负载',
    'readPercent': '读取 %',
    'averageMBps': '平均 MB/s',
    'lowMBps': '最低 MB/s',
    'stability': '稳定性',
    'readMBps': '读取 MB/s',
    'writeMBps': '写入 MB/s',
    'bytes': '字节',
    'samples': '样本',
    'chartXAxis': '样本序号',
    'notAvailable': '不适用',
    'yes': '是',
    'no': '否',
    'fullWriteNotRun': '未运行',
    'fullWriteInsufficientSpace': '空间不足',
    'fullWriteCompleted': '已完成',
    'slcNotRun': '未运行',
    'slcInsufficientRange': '范围不足',
    'slcNoInflection': '未检测到拐点',
    'slcDetected': '已检测到',
    'scopeSelectedVolume': '选定卷的可用空间',
  },
  'zh_TW': {
    'reportTitle': 'WinDeploy Studio 磁碟測試報告',
    'exported': '匯出時間',
    'records': '筆記錄',
    'noRecords': '未選取任何磁碟測試記錄。',
    'friendlyName': '易讀名稱',
    'devicePath': '裝置路徑',
    'diskNumber': '磁碟編號',
    'capacityBytes': '容量（位元組）',
    'stableIdentity': '穩定識別碼',
    'driveRoot': '磁碟機根目錄',
    'systemDisk': '系統磁碟',
    'bootDisk': '開機磁碟',
    'offline': '離線',
    'removable': '卸除式裝置',
    'protocol': '通訊協定',
    'suitability': '適用性',
    'fullWriteStatus': '全碟寫入狀態',
    'slcStatus': 'SLC 狀態',
    'recordId': '記錄',
    'summaryTitle': '摘要',
    'parametersTitle': '測試參數',
    'chartsTitle': '效能曲線',
    'rawDataTitle': '原始資料（完整 JSON）',
    'unnamedDisk': '磁碟測試',
    'sequentialSeconds': '循序測試時間',
    'random4kSeconds': '4K 隨機測試時間',
    'mixedWorkloadSeconds': '混合負載測試時間',
    'threadSeconds': '多執行緒測試時間',
    'sequentialLimit': '循序測試資料上限',
    'randomFileSize': '隨機測試檔案大小',
    'warmup': '預熱',
    'cooldown': '冷卻',
    'fullWriteCooldown': '全碟寫入冷卻',
    'fullWriteReserve': '全碟寫入保留空間',
    'fullWriteMinimum': '全碟寫入最小空間',
    'fullWriteScope': '全碟寫入範圍',
    'workload': '測試負載',
    'readPercent': '讀取 %',
    'averageMBps': '平均 MB/s',
    'lowMBps': '最低 MB/s',
    'stability': '穩定性',
    'readMBps': '讀取 MB/s',
    'writeMBps': '寫入 MB/s',
    'bytes': '位元組',
    'samples': '樣本',
    'chartXAxis': '樣本序號',
    'notAvailable': '不適用',
    'yes': '是',
    'no': '否',
    'fullWriteNotRun': '未執行',
    'fullWriteInsufficientSpace': '空間不足',
    'fullWriteCompleted': '已完成',
    'slcNotRun': '未執行',
    'slcInsufficientRange': '範圍不足',
    'slcNoInflection': '未偵測到轉折點',
    'slcDetected': '已偵測到',
    'scopeSelectedVolume': '選定磁碟區的可用空間',
  },
  'fr': {
    'reportTitle': 'Rapport de test de disque WinDeploy Studio',
    'exported': 'Exporté',
    'records': 'enregistrement(s)',
    'noRecords': 'Aucun résultat de test de disque n’a été sélectionné.',
    'friendlyName': 'Nom convivial',
    'devicePath': 'Chemin du périphérique',
    'diskNumber': 'Numéro de disque',
    'capacityBytes': 'Capacité (octets)',
    'stableIdentity': 'Identité stable',
    'driveRoot': 'Racine du lecteur',
    'systemDisk': 'Disque système',
    'bootDisk': 'Disque de démarrage',
    'offline': 'Hors connexion',
    'removable': 'Amovible',
    'protocol': 'Protocole',
    'suitability': 'Adéquation',
    'fullWriteStatus': 'État d’écriture complète',
    'slcStatus': 'État SLC',
    'recordId': 'Enregistrement',
    'summaryTitle': 'Résumé',
    'parametersTitle': 'Paramètres du test',
    'chartsTitle': 'Courbes de performances',
    'rawDataTitle': 'Données brutes (JSON complet)',
    'unnamedDisk': 'Test de disque',
    'sequentialSeconds': 'Durée séquentielle',
    'random4kSeconds': 'Durée aléatoire 4K',
    'mixedWorkloadSeconds': 'Durée de charge mixte',
    'threadSeconds': 'Durée multi-thread',
    'sequentialLimit': 'Limite des données séquentielles',
    'randomFileSize': 'Taille du fichier de test aléatoire',
    'warmup': 'Préchauffage',
    'cooldown': 'Refroidissement',
    'fullWriteCooldown': 'Refroidissement après écriture complète',
    'fullWriteReserve': 'Espace réservé à l’écriture complète',
    'fullWriteMinimum': 'Espace minimal pour écriture complète',
    'fullWriteScope': 'Portée de l’écriture complète',
    'workload': 'Charge',
    'readPercent': 'Lecture %',
    'averageMBps': 'Moyenne MB/s',
    'lowMBps': 'Minimum MB/s',
    'stability': 'Stabilité',
    'readMBps': 'Lecture MB/s',
    'writeMBps': 'Écriture MB/s',
    'bytes': 'Octets',
    'samples': 'Échantillons',
    'chartXAxis': 'Échantillon',
    'notAvailable': 'N/D',
    'yes': 'Oui',
    'no': 'Non',
    'fullWriteNotRun': 'Non exécuté',
    'fullWriteInsufficientSpace': 'Espace insuffisant',
    'fullWriteCompleted': 'Terminé',
    'slcNotRun': 'Non exécuté',
    'slcInsufficientRange': 'Plage insuffisante',
    'slcNoInflection': 'Aucune inflexion détectée',
    'slcDetected': 'Détecté',
    'scopeSelectedVolume': 'Espace disponible sur le volume sélectionné',
  },
  'de': {
    'reportTitle': 'WinDeploy Studio Datenträger-Testbericht',
    'exported': 'Exportiert',
    'records': 'Datensatz/Datensätze',
    'noRecords': 'Es wurden keine Datenträger-Testdatensätze ausgewählt.',
    'friendlyName': 'Anzeigename',
    'devicePath': 'Gerätepfad',
    'diskNumber': 'Datenträgernummer',
    'capacityBytes': 'Kapazität (Byte)',
    'stableIdentity': 'Stabile Identität',
    'driveRoot': 'Stammverzeichnis des Laufwerks',
    'systemDisk': 'Systemdatenträger',
    'bootDisk': 'Startdatenträger',
    'offline': 'Offline',
    'removable': 'Wechselmedium',
    'protocol': 'Protokoll',
    'suitability': 'Eignung',
    'fullWriteStatus': 'Status des vollständigen Schreibtests',
    'slcStatus': 'SLC-Status',
    'recordId': 'Datensatz',
    'summaryTitle': 'Zusammenfassung',
    'parametersTitle': 'Testparameter',
    'chartsTitle': 'Leistungskurven',
    'rawDataTitle': 'Rohdaten (vollständiges JSON)',
    'unnamedDisk': 'Datenträgertest',
    'sequentialSeconds': 'Sequenzielle Dauer',
    'random4kSeconds': '4K-Zufallsdauer',
    'mixedWorkloadSeconds': 'Dauer der gemischten Last',
    'threadSeconds': 'Thread-Dauer',
    'sequentialLimit': 'Sequenzielles Datenlimit',
    'randomFileSize': 'Zufällige Testdateigröße',
    'warmup': 'Aufwärmen',
    'cooldown': 'Abkühlung',
    'fullWriteCooldown': 'Abkühlung nach vollständigem Schreiben',
    'fullWriteReserve': 'Reservierter Speicher für vollständiges Schreiben',
    'fullWriteMinimum': 'Mindestspeicher für vollständiges Schreiben',
    'fullWriteScope': 'Umfang des vollständigen Schreibens',
    'workload': 'Arbeitslast',
    'readPercent': 'Lesen %',
    'averageMBps': 'Durchschnitt MB/s',
    'lowMBps': 'Minimum MB/s',
    'stability': 'Stabilität',
    'readMBps': 'Lesen MB/s',
    'writeMBps': 'Schreiben MB/s',
    'bytes': 'Byte',
    'samples': 'Messwerte',
    'chartXAxis': 'Messwert',
    'notAvailable': 'k. A.',
    'yes': 'Ja',
    'no': 'Nein',
    'fullWriteNotRun': 'Nicht ausgeführt',
    'fullWriteInsufficientSpace': 'Nicht genügend Speicher',
    'fullWriteCompleted': 'Abgeschlossen',
    'slcNotRun': 'Nicht ausgeführt',
    'slcInsufficientRange': 'Bereich unzureichend',
    'slcNoInflection': 'Kein Knick erkannt',
    'slcDetected': 'Erkannt',
    'scopeSelectedVolume': 'Verfügbarer Speicher auf dem ausgewählten Volume',
  },
  'es': {
    'reportTitle': 'Informe de prueba de disco de WinDeploy Studio',
    'exported': 'Exportado',
    'records': 'registro(s)',
    'noRecords': 'No se seleccionaron registros de prueba de disco.',
    'friendlyName': 'Nombre descriptivo',
    'devicePath': 'Ruta del dispositivo',
    'diskNumber': 'Número de disco',
    'capacityBytes': 'Capacidad (bytes)',
    'stableIdentity': 'Identidad estable',
    'driveRoot': 'Raíz de la unidad',
    'systemDisk': 'Disco del sistema',
    'bootDisk': 'Disco de arranque',
    'offline': 'Sin conexión',
    'removable': 'Extraíble',
    'protocol': 'Protocolo',
    'suitability': 'Idoneidad',
    'fullWriteStatus': 'Estado de escritura completa',
    'slcStatus': 'Estado de SLC',
    'recordId': 'Registro',
    'summaryTitle': 'Resumen',
    'parametersTitle': 'Parámetros de prueba',
    'chartsTitle': 'Curvas de rendimiento',
    'rawDataTitle': 'Datos sin procesar (JSON completo)',
    'unnamedDisk': 'Prueba de disco',
    'sequentialSeconds': 'Duración secuencial',
    'random4kSeconds': 'Duración aleatoria 4K',
    'mixedWorkloadSeconds': 'Duración de carga mixta',
    'threadSeconds': 'Duración de hilos',
    'sequentialLimit': 'Límite de datos secuenciales',
    'randomFileSize': 'Tamaño de archivo de prueba aleatorio',
    'warmup': 'Calentamiento',
    'cooldown': 'Enfriamiento',
    'fullWriteCooldown': 'Enfriamiento tras escritura completa',
    'fullWriteReserve': 'Espacio reservado para escritura completa',
    'fullWriteMinimum': 'Espacio mínimo para escritura completa',
    'fullWriteScope': 'Ámbito de escritura completa',
    'workload': 'Carga de trabajo',
    'readPercent': 'Lectura %',
    'averageMBps': 'Promedio MB/s',
    'lowMBps': 'Mínimo MB/s',
    'stability': 'Estabilidad',
    'readMBps': 'Lectura MB/s',
    'writeMBps': 'Escritura MB/s',
    'bytes': 'Bytes',
    'samples': 'Muestras',
    'chartXAxis': 'Muestra',
    'notAvailable': 'N/D',
    'yes': 'Sí',
    'no': 'No',
    'fullWriteNotRun': 'No ejecutado',
    'fullWriteInsufficientSpace': 'Espacio insuficiente',
    'fullWriteCompleted': 'Completado',
    'slcNotRun': 'No ejecutado',
    'slcInsufficientRange': 'Rango insuficiente',
    'slcNoInflection': 'No se detectó inflexión',
    'slcDetected': 'Detectado',
    'scopeSelectedVolume': 'Espacio disponible en el volumen seleccionado',
  },
  'pt': {
    'reportTitle': 'Relatório de teste de disco do WinDeploy Studio',
    'exported': 'Exportado',
    'records': 'registro(s)',
    'noRecords': 'Nenhum registro de teste de disco foi selecionado.',
    'friendlyName': 'Nome amigável',
    'devicePath': 'Caminho do dispositivo',
    'diskNumber': 'Número do disco',
    'capacityBytes': 'Capacidade (bytes)',
    'stableIdentity': 'Identidade estável',
    'driveRoot': 'Raiz da unidade',
    'systemDisk': 'Disco do sistema',
    'bootDisk': 'Disco de inicialização',
    'offline': 'Offline',
    'removable': 'Removível',
    'protocol': 'Protocolo',
    'suitability': 'Adequação',
    'fullWriteStatus': 'Status de gravação completa',
    'slcStatus': 'Status SLC',
    'recordId': 'Registro',
    'summaryTitle': 'Resumo',
    'parametersTitle': 'Parâmetros de teste',
    'chartsTitle': 'Curvas de desempenho',
    'rawDataTitle': 'Dados brutos (JSON completo)',
    'unnamedDisk': 'Teste de disco',
    'sequentialSeconds': 'Duração sequencial',
    'random4kSeconds': 'Duração aleatória 4K',
    'mixedWorkloadSeconds': 'Duração de carga mista',
    'threadSeconds': 'Duração de threads',
    'sequentialLimit': 'Limite de dados sequenciais',
    'randomFileSize': 'Tamanho do arquivo de teste aleatório',
    'warmup': 'Aquecimento',
    'cooldown': 'Resfriamento',
    'fullWriteCooldown': 'Resfriamento após gravação completa',
    'fullWriteReserve': 'Espaço reservado para gravação completa',
    'fullWriteMinimum': 'Espaço mínimo para gravação completa',
    'fullWriteScope': 'Escopo da gravação completa',
    'workload': 'Carga de trabalho',
    'readPercent': 'Leitura %',
    'averageMBps': 'Média MB/s',
    'lowMBps': 'Mínimo MB/s',
    'stability': 'Estabilidade',
    'readMBps': 'Leitura MB/s',
    'writeMBps': 'Gravação MB/s',
    'bytes': 'Bytes',
    'samples': 'Amostras',
    'chartXAxis': 'Amostra',
    'notAvailable': 'N/D',
    'yes': 'Sim',
    'no': 'Não',
    'fullWriteNotRun': 'Não executado',
    'fullWriteInsufficientSpace': 'Espaço insuficiente',
    'fullWriteCompleted': 'Concluído',
    'slcNotRun': 'Não executado',
    'slcInsufficientRange': 'Faixa insuficiente',
    'slcNoInflection': 'Nenhum ponto de inflexão detectado',
    'slcDetected': 'Detectado',
    'scopeSelectedVolume': 'Espaço disponível no volume selecionado',
  },
  'ru': {
    'reportTitle': 'Отчет WinDeploy Studio о тестировании диска',
    'exported': 'Экспортировано',
    'records': 'запись(ей)',
    'noRecords': 'Не выбраны записи тестирования диска.',
    'friendlyName': 'Понятное имя',
    'devicePath': 'Путь к устройству',
    'diskNumber': 'Номер диска',
    'capacityBytes': 'Емкость (байт)',
    'stableIdentity': 'Стабильный идентификатор',
    'driveRoot': 'Корень диска',
    'systemDisk': 'Системный диск',
    'bootDisk': 'Загрузочный диск',
    'offline': 'Отключен',
    'removable': 'Съемный',
    'protocol': 'Протокол',
    'suitability': 'Пригодность',
    'fullWriteStatus': 'Статус полной записи',
    'slcStatus': 'Статус SLC',
    'recordId': 'Запись',
    'summaryTitle': 'Сводка',
    'parametersTitle': 'Параметры теста',
    'chartsTitle': 'Кривые производительности',
    'rawDataTitle': 'Исходные данные (полный JSON)',
    'unnamedDisk': 'Тест диска',
    'sequentialSeconds': 'Длительность последовательного теста',
    'random4kSeconds': 'Длительность случайного теста 4K',
    'mixedWorkloadSeconds': 'Длительность смешанной нагрузки',
    'threadSeconds': 'Длительность многопоточного теста',
    'sequentialLimit': 'Лимит последовательных данных',
    'randomFileSize': 'Размер файла случайного теста',
    'warmup': 'Прогрев',
    'cooldown': 'Охлаждение',
    'fullWriteCooldown': 'Охлаждение после полной записи',
    'fullWriteReserve': 'Резерв для полной записи',
    'fullWriteMinimum': 'Минимальное место для полной записи',
    'fullWriteScope': 'Область полной записи',
    'workload': 'Нагрузка',
    'readPercent': 'Чтение %',
    'averageMBps': 'Среднее MB/s',
    'lowMBps': 'Минимум MB/s',
    'stability': 'Стабильность',
    'readMBps': 'Чтение MB/s',
    'writeMBps': 'Запись MB/s',
    'bytes': 'Байты',
    'samples': 'Образцы',
    'chartXAxis': 'Образец',
    'notAvailable': 'Н/Д',
    'yes': 'Да',
    'no': 'Нет',
    'fullWriteNotRun': 'Не выполнялся',
    'fullWriteInsufficientSpace': 'Недостаточно места',
    'fullWriteCompleted': 'Завершено',
    'slcNotRun': 'Не выполнялся',
    'slcInsufficientRange': 'Недостаточный диапазон',
    'slcNoInflection': 'Перегиб не обнаружен',
    'slcDetected': 'Обнаружено',
    'scopeSelectedVolume': 'Доступное место на выбранном томе',
  },
  'ar': {
    'reportTitle': 'تقرير اختبار القرص من WinDeploy Studio',
    'exported': 'تم التصدير',
    'records': 'سجل/سجلات',
    'noRecords': 'لم يتم تحديد أي سجلات لاختبار القرص.',
    'friendlyName': 'الاسم المألوف',
    'devicePath': 'مسار الجهاز',
    'diskNumber': 'رقم القرص',
    'capacityBytes': 'السعة (بايت)',
    'stableIdentity': 'معرّف ثابت',
    'driveRoot': 'جذر محرك الأقراص',
    'systemDisk': 'قرص النظام',
    'bootDisk': 'قرص الإقلاع',
    'offline': 'غير متصل',
    'removable': 'قابل للإزالة',
    'protocol': 'البروتوكول',
    'suitability': 'الملاءمة',
    'fullWriteStatus': 'حالة الكتابة الكاملة',
    'slcStatus': 'حالة SLC',
    'recordId': 'السجل',
    'summaryTitle': 'الملخص',
    'parametersTitle': 'معلمات الاختبار',
    'chartsTitle': 'منحنيات الأداء',
    'rawDataTitle': 'البيانات الخام (JSON كامل)',
    'unnamedDisk': 'اختبار القرص',
    'sequentialSeconds': 'مدة الاختبار المتسلسل',
    'random4kSeconds': 'مدة الاختبار العشوائي 4K',
    'mixedWorkloadSeconds': 'مدة الحمل المختلط',
    'threadSeconds': 'مدة الاختبار متعدد الخيوط',
    'sequentialLimit': 'حد البيانات المتسلسلة',
    'randomFileSize': 'حجم ملف الاختبار العشوائي',
    'warmup': 'تهيئة',
    'cooldown': 'تهدئة',
    'fullWriteCooldown': 'تهدئة بعد الكتابة الكاملة',
    'fullWriteReserve': 'مساحة محجوزة للكتابة الكاملة',
    'fullWriteMinimum': 'الحد الأدنى لمساحة الكتابة الكاملة',
    'fullWriteScope': 'نطاق الكتابة الكاملة',
    'workload': 'عبء العمل',
    'readPercent': 'قراءة %',
    'averageMBps': 'المتوسط MB/s',
    'lowMBps': 'الأدنى MB/s',
    'stability': 'الاستقرار',
    'readMBps': 'قراءة MB/s',
    'writeMBps': 'كتابة MB/s',
    'bytes': 'بايت',
    'samples': 'عينات',
    'chartXAxis': 'عينة',
    'notAvailable': 'غير متاح',
    'yes': 'نعم',
    'no': 'لا',
    'fullWriteNotRun': 'لم يتم التشغيل',
    'fullWriteInsufficientSpace': 'مساحة غير كافية',
    'fullWriteCompleted': 'مكتمل',
    'slcNotRun': 'لم يتم التشغيل',
    'slcInsufficientRange': 'نطاق غير كافٍ',
    'slcNoInflection': 'لم يتم اكتشاف نقطة انعطاف',
    'slcDetected': 'تم الاكتشاف',
    'scopeSelectedVolume': 'المساحة المتاحة على وحدة التخزين المحددة',
  },
  'ko': {
    'reportTitle': 'WinDeploy Studio 디스크 벤치마크 보고서',
    'exported': '내보낸 시간',
    'records': '개 기록',
    'noRecords': '선택한 디스크 벤치마크 기록이 없습니다.',
    'friendlyName': '표시 이름',
    'devicePath': '장치 경로',
    'diskNumber': '디스크 번호',
    'capacityBytes': '용량(바이트)',
    'stableIdentity': '고정 식별자',
    'driveRoot': '드라이브 루트',
    'systemDisk': '시스템 디스크',
    'bootDisk': '부팅 디스크',
    'offline': '오프라인',
    'removable': '이동식',
    'protocol': '프로토콜',
    'suitability': '적합성',
    'fullWriteStatus': '전체 쓰기 상태',
    'slcStatus': 'SLC 상태',
    'recordId': '기록',
    'summaryTitle': '요약',
    'parametersTitle': '테스트 매개변수',
    'chartsTitle': '성능 곡선',
    'rawDataTitle': '원시 데이터(전체 JSON)',
    'unnamedDisk': '디스크 벤치마크',
    'sequentialSeconds': '순차 테스트 시간',
    'random4kSeconds': '4K 임의 테스트 시간',
    'mixedWorkloadSeconds': '혼합 작업 시간',
    'threadSeconds': '다중 스레드 테스트 시간',
    'sequentialLimit': '순차 데이터 제한',
    'randomFileSize': '임의 테스트 파일 크기',
    'warmup': '워밍업',
    'cooldown': '쿨다운',
    'fullWriteCooldown': '전체 쓰기 쿨다운',
    'fullWriteReserve': '전체 쓰기 예약 공간',
    'fullWriteMinimum': '전체 쓰기 최소 공간',
    'fullWriteScope': '전체 쓰기 범위',
    'workload': '작업 부하',
    'readPercent': '읽기 %',
    'averageMBps': '평균 MB/s',
    'lowMBps': '최저 MB/s',
    'stability': '안정성',
    'readMBps': '읽기 MB/s',
    'writeMBps': '쓰기 MB/s',
    'bytes': '바이트',
    'samples': '샘플',
    'chartXAxis': '샘플',
    'notAvailable': '해당 없음',
    'yes': '예',
    'no': '아니요',
    'fullWriteNotRun': '실행 안 함',
    'fullWriteInsufficientSpace': '공간 부족',
    'fullWriteCompleted': '완료됨',
    'slcNotRun': '실행 안 함',
    'slcInsufficientRange': '범위 부족',
    'slcNoInflection': '변곡점이 감지되지 않음',
    'slcDetected': '감지됨',
    'scopeSelectedVolume': '선택한 볼륨의 사용 가능한 공간',
  },
  'ja': {
    'reportTitle': 'WinDeploy Studio ディスクベンチマークレポート',
    'exported': 'エクスポート日時',
    'records': '件の記録',
    'noRecords': '選択されたディスクベンチマーク記録はありません。',
    'friendlyName': '表示名',
    'devicePath': 'デバイス パス',
    'diskNumber': 'ディスク番号',
    'capacityBytes': '容量（バイト）',
    'stableIdentity': '固定識別子',
    'driveRoot': 'ドライブ ルート',
    'systemDisk': 'システム ディスク',
    'bootDisk': 'ブート ディスク',
    'offline': 'オフライン',
    'removable': 'リムーバブル',
    'protocol': 'プロトコル',
    'suitability': '適性',
    'fullWriteStatus': '全域書き込み状態',
    'slcStatus': 'SLC 状態',
    'recordId': '記録',
    'summaryTitle': '概要',
    'parametersTitle': 'テスト パラメーター',
    'chartsTitle': '性能曲線',
    'rawDataTitle': '生データ（完全な JSON）',
    'unnamedDisk': 'ディスクベンチマーク',
    'sequentialSeconds': 'シーケンシャル テスト時間',
    'random4kSeconds': '4K ランダム テスト時間',
    'mixedWorkloadSeconds': '混合ワークロード時間',
    'threadSeconds': 'マルチスレッド テスト時間',
    'sequentialLimit': 'シーケンシャル データ上限',
    'randomFileSize': 'ランダム テスト ファイル サイズ',
    'warmup': 'ウォームアップ',
    'cooldown': 'クールダウン',
    'fullWriteCooldown': '全域書き込みクールダウン',
    'fullWriteReserve': '全域書き込み予約領域',
    'fullWriteMinimum': '全域書き込み最小領域',
    'fullWriteScope': '全域書き込み範囲',
    'workload': 'ワークロード',
    'readPercent': '読み取り %',
    'averageMBps': '平均 MB/s',
    'lowMBps': '最低 MB/s',
    'stability': '安定性',
    'readMBps': '読み取り MB/s',
    'writeMBps': '書き込み MB/s',
    'bytes': 'バイト',
    'samples': 'サンプル',
    'chartXAxis': 'サンプル',
    'notAvailable': '該当なし',
    'yes': 'はい',
    'no': 'いいえ',
    'fullWriteNotRun': '未実行',
    'fullWriteInsufficientSpace': '空き容量不足',
    'fullWriteCompleted': '完了',
    'slcNotRun': '未実行',
    'slcInsufficientRange': '範囲不足',
    'slcNoInflection': '変曲点は検出されませんでした',
    'slcDetected': '検出済み',
    'scopeSelectedVolume': '選択したボリュームの空き領域',
  },
};

List<_HtmlChartSeries> _chartSeries(
  BenchmarkResult result,
  _HtmlReportLabels labels,
) {
  final series = <_HtmlChartSeries>[];
  for (final measurement in result.measurements) {
    final points = measurement.samples
        .where((sample) => sample.x.isFinite && sample.throughputMBps.isFinite)
        .toList(growable: false);
    if (points.isNotEmpty) {
      series.add(
        _HtmlChartSeries(
          '${labels.workload(measurement.workload)} · ${measurement.threadCount}T',
          _limitChartPoints(points),
        ),
      );
    }
  }
  if (series.isNotEmpty) return series;
  final legacy = <(BenchmarkWorkload, List<BenchmarkPoint>)>[
    (BenchmarkWorkload.sequentialRead, result.sequentialReadPoints),
    (BenchmarkWorkload.sequentialWrite, result.sequentialPoints),
    (BenchmarkWorkload.random4kRead, result.random4kReadPoints),
    (BenchmarkWorkload.random4kWrite, result.random4kPoints),
    (BenchmarkWorkload.random4kMultiThread, result.threadPoints),
    (BenchmarkWorkload.multitasking, result.mixedWorkloadPoints),
    (BenchmarkWorkload.fullSequentialWrite, result.fullWritePoints),
  ];
  for (final entry in legacy) {
    final points = entry.$2
        .where((point) => point.x.isFinite && point.y.isFinite)
        .map((point) => BenchmarkSample(x: point.x, throughputMBps: point.y))
        .toList(growable: false);
    if (points.isNotEmpty) {
      series.add(
        _HtmlChartSeries(labels.workload(entry.$1), _limitChartPoints(points)),
      );
    }
  }
  return series;
}

List<BenchmarkSample> _limitChartPoints(List<BenchmarkSample> points) {
  const maxPoints = 600;
  if (points.length <= maxPoints) return points;
  final stride = (points.length - 1) / (maxPoints - 1);
  return List<BenchmarkSample>.generate(
    maxPoints,
    (index) =>
        points[(index * stride).round().clamp(0, points.length - 1).toInt()],
    growable: false,
  );
}

String _formatHtmlValue(Object? value, _HtmlReportLabels labels) {
  if (value == null) return labels.text('notAvailable');
  if (value is DateTime) return _formatHtmlDate(value);
  if (value is bool) return labels.text(value ? 'yes' : 'no');
  if (value is Iterable) {
    final formatted = value.map((item) => item.toString()).join(', ');
    return formatted.isEmpty ? labels.text('notAvailable') : formatted;
  }
  if (value is num) return _formatHtmlNumber(value, labels);
  if (value.toString().trim().isEmpty) return labels.text('notAvailable');
  return value.toString();
}

String _formatHtmlDate(DateTime value) => value
    .toLocal()
    .toIso8601String()
    .replaceFirst('T', ' ')
    .replaceFirst(RegExp(r'\.\d{3,}'), '');

String _formatHtmlNumber(num value, _HtmlReportLabels labels) {
  if (!value.isFinite) return labels.text('notAvailable');
  if (value == value.roundToDouble()) return value.toStringAsFixed(0);
  return value
      .toStringAsFixed(3)
      .replaceFirst(RegExp(r'0+$'), '')
      .replaceFirst(RegExp(r'\.$'), '');
}

String _formatHtmlByteCount(int bytes, _HtmlReportLabels labels) {
  const units = ['B', 'KiB', 'MiB', 'GiB', 'TiB'];
  var value = bytes.toDouble();
  var unit = 0;
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024;
    unit++;
  }
  return '${_formatHtmlNumber(value, labels)} ${units[unit]}';
}

String _escapeHtml(String value) => value
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&#39;');

const _htmlChartColors = <String>['#eab308', '#dc2626'];

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
