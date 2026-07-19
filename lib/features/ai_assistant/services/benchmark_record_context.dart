import '../../benchmark/models/benchmark_models.dart';
import '../../benchmark_history/models/benchmark_history_models.dart';

/// The benchmark payload is deliberately bounded. A full-write run can have
/// hundreds of samples and chart points, which are useful for rendering but
/// make an AI request slow and unreliable when sent verbatim.
const int benchmarkRecordContextMaxCharacters = 12000;
const int _maxRecords = 3;
const int _maxMeasurementsPerRecord = 12;
const int _maxTextFieldLength = 160;

/// Converts selected, user-approved benchmark records into an auditable,
/// bounded plain-text context block for the AI request.
///
/// The summary intentionally omits raw sample lists, raw chart point lists,
/// serial numbers, unique IDs, device paths, and stable device keys. Those are
/// either redundant with the aggregate metrics or unnecessarily sensitive.
String buildBenchmarkRecordContext(Iterable<BenchmarkHistoryRecord> records) {
  final selected = records.toList(growable: false);
  final candidates = selected.take(_maxRecords).toList(growable: false);
  final buffer = StringBuffer()
    ..writeln('[SELECTED DISK TEST RECORDS]')
    ..writeln('Records selected: ${selected.length}')
    ..writeln('Records included: up to $_maxRecords')
    ..writeln(
      'These are user-selected local benchmark records. Analyze them as measurements, not as a guarantee of device health or future performance.',
    )
    ..writeln(
      'Raw samples and chart points are summarized to keep this AI request reliable.',
    )
    ..writeln()
    ..writeln('[METRIC DEFINITIONS]')
    ..writeln(
      '- Sequential read/write (MB/s): large contiguous transfers; relevant to ISO copying, image deployment, and sustained file transfers.',
    )
    ..writeln(
      '- 4K random read/write (MB/s and IOPS): small, scattered operations; relevant to Windows boot, application launches, paging, updates, and general To Go responsiveness.',
    )
    ..writeln(
      '- Average/low throughput and stability: typical speed, worst observed speed, and consistency during a stage. Higher is generally better.',
    )
    ..writeln(
      '- Latency p50/p95/p99 (ms): median, 95th-percentile, and 99th-percentile completion time. Lower is better; p95/p99 expose stalls.',
    )
    ..writeln(
      '- Multi-thread peak, retention, and normalized efficiency: concurrency scaling. Higher values indicate performance holds up under parallel work.',
    )
    ..writeln(
      '- Full-write P10/end/drop and SLC-cache values: sustained-write behavior after cache exhaustion. Lower drop and higher post-cache speed are better.',
    )
    ..writeln(
      '- Score and suitability are application heuristics derived from this test, not a replacement for SMART health data or a warranty assessment.',
    );

  var includedCount = 0;
  for (var index = 0; index < candidates.length; index++) {
    final recordText = _buildRecordContext(candidates[index], index + 1);
    if (!_hasRoomForRecord(buffer, recordText)) break;
    buffer.write(recordText);
    includedCount++;
  }

  final omittedCount = selected.length - includedCount;
  if (omittedCount > 0) {
    _appendWithinLimit(
      buffer,
      '\n[CONTEXT TRUNCATED] $omittedCount selected record(s) were omitted to keep the AI request within its reliability limit. Analyze only the included records.\n',
    );
  }

  return buffer.toString();
}

bool _hasRoomForRecord(StringBuffer buffer, String recordText) {
  // Leave enough space for a clear truncation notice when a later record does
  // not fit. A complete record is more useful than a partially cut one.
  const noticeReserve = 180;
  return buffer.length + recordText.length + noticeReserve <=
      benchmarkRecordContextMaxCharacters;
}

void _appendWithinLimit(StringBuffer buffer, String text) {
  final remaining = benchmarkRecordContextMaxCharacters - buffer.length;
  if (remaining <= 0) return;
  buffer.write(text.length <= remaining ? text : text.substring(0, remaining));
}

String _buildRecordContext(BenchmarkHistoryRecord record, int index) {
  final result = record.result;
  final disk = result.disk;
  final device = result.device;
  final parameters = result.parameters;
  final includedMeasurements = result.measurements
      .take(_maxMeasurementsPerRecord)
      .toList(growable: false);
  final measurementOmitted =
      result.measurements.length - includedMeasurements.length;
  final buffer = StringBuffer()
    ..writeln()
    ..writeln('[DISK TEST RECORD $index]')
    ..writeln(
      'Record: id=${_text(record.id)}; saved=${record.savedAt.toIso8601String()}; completed=${result.completedAt.toIso8601String()}',
    )
    ..writeln(
      'Test: protocol=${result.protocolVersion}; mode=${result.mode.name}; duration=${_duration(result.duration)}; warmup=${_duration(result.warmupDuration)}; cooldown=${_duration(result.cooldownDuration)}',
    )
    ..writeln(
      'Device: disk=${disk.diskNumber}; model=${_text(disk.model)}; capacity=${_text(disk.sizeFormatted)}; bus=${_text(disk.busType)}; partitionStyle=${_text(disk.partitionStyle)}; drive=${_text(result.driveRoot)}',
    )
    ..writeln(
      'Volume: partitions=${disk.partitions.length}; driveLetters=${_text(disk.driveLetters.join(', '))}; removable=${disk.isRemovable}; system=${disk.isSystem}; boot=${disk.isBoot}; offline=${disk.isOffline}',
    )
    ..writeln(
      'Hardware class: VID/PID=${_text(device.vid)}/${_text(device.pid)}',
    )
    ..writeln(
      'Configuration: sequential=${parameters.sequentialSeconds}s; 4K=${parameters.random4kSeconds}s; mixed=${parameters.mixedWorkloadSeconds}s; threads=${parameters.threadSeconds}s (${parameters.threadCounts.join(', ')}); fullWriteScope=${parameters.fullWriteScope.name}',
    )
    ..writeln('[SUMMARY METRICS]')
    ..writeln(
      'Score=${_number(result.score)}/100; suitability=${result.suitability.name}; sequential read/write=${_number(result.sequentialReadMBps)}/${_number(result.sequentialWriteMBps)} MB/s',
    )
    ..writeln(
      '4K read/write=${_number(result.random4kReadAverageMBps)}/${_number(result.random4kAverageMBps)} MB/s; IOPS=${_number(result.random4kReadIops)}/${_number(result.random4kWriteIops)}; adjusted=${_number(result.random4kAdjustedMBps)} MB/s; low=${_number(result.random4kLowMBps)} MB/s; stability=${_percent(result.random4kStability)}',
    )
    ..writeln(
      'Multi-thread: peak=${_number(result.multiThreadPeakMBps)} MB/s; multiplier=${_number(result.multiThreadMultiplier)}x; retention=${_percent(result.multiThreadRetention)}; efficiency=${_percent(result.multiThreadNormalizedEfficiency)}',
    )
    ..writeln(
      'Full write: status=${result.fullWriteStatus.name}; P10=${_number(result.fullWriteP10MBps)} MB/s; end=${_number(result.fullWriteEndMBps)} MB/s; drop=${_percent(result.fullWriteDropRatio)}; targetBytes=${result.fullWriteTargetBytes}',
    )
    ..writeln(
      'SLC/cache: status=${result.slcStatus.name}; inflection=${_number(result.slcCacheInflectionGB)} GB; postCache=${_number(result.postCacheStableMBps)} MB/s; confidence=${_percent(result.slcConfidence)}',
    )
    ..writeln('[WORKLOAD SUMMARIES]');

  for (final measurement in includedMeasurements) {
    buffer.writeln(
      '- ${measurement.workload.name}: threads=${measurement.threadCount}; read=${measurement.readPercent}%; average=${_number(measurement.averageMBps)} MB/s; low=${_number(measurement.lowMBps)} MB/s; stability=${_percent(measurement.stability)}; IOPS=${_number(measurement.iops)}; latency p50/p95/p99=${_number(measurement.latency.p50Ms)}/${_number(measurement.latency.p95Ms)}/${_number(measurement.latency.p99Ms)} ms; samples=${measurement.samples.length}',
    );
  }
  if (measurementOmitted > 0) {
    buffer.writeln(
      '- $measurementOmitted additional workload summary/summaries omitted per-record.',
    );
  }

  buffer
    ..writeln('[CHART SUMMARIES]')
    ..write(_chartSummary('Sequential read', result.sequentialReadPoints))
    ..write(_chartSummary('Sequential write', result.sequentialPoints))
    ..write(_chartSummary('4K random read', result.random4kReadPoints))
    ..write(_chartSummary('4K random write', result.random4kPoints))
    ..write(_chartSummary('Multi-thread', result.threadPoints))
    ..write(_chartSummary('Mixed workload', result.mixedWorkloadPoints))
    ..write(_chartSummary('Full sequential write', result.fullWritePoints))
    ..writeln(
      'Raw sample and point lists are intentionally omitted; use these aggregates with the workload summaries above.',
    );
  return buffer.toString();
}

String _chartSummary(String name, List<BenchmarkPoint> points) {
  if (points.isEmpty) return '- $name: points=0\n';

  final finiteY = points
      .map((point) => point.y)
      .where((value) => value.isFinite)
      .toList(growable: false);
  if (finiteY.isEmpty) return '- $name: points=${points.length}; usableY=0\n';

  var minimum = finiteY.first;
  var maximum = finiteY.first;
  for (final value in finiteY.skip(1)) {
    if (value < minimum) minimum = value;
    if (value > maximum) maximum = value;
  }
  final first = points.first;
  final last = points.last;
  return '- $name: points=${points.length}; yRange=${_number(minimum)}-${_number(maximum)}; first=${_number(first.y)} at x=${_number(first.x)}; last=${_number(last.y)} at x=${_number(last.x)}\n';
}

String _duration(Duration value) => '${value.inMilliseconds} ms';

String _text(String value, {int maxLength = _maxTextFieldLength}) {
  final compact = value.trim().replaceAll(RegExp(r'\s+'), ' ');
  if (compact.isEmpty) return '(not reported)';
  final neutralized = compact.replaceAll('<', '[').replaceAll('>', ']');
  if (neutralized.length <= maxLength) return neutralized;
  return '${neutralized.substring(0, maxLength - 3)}...';
}

String _percent(double value) => '${_number(value * 100)}%';

String _number(double value) {
  if (!value.isFinite) return '(not reported)';
  if (value == value.roundToDouble()) return value.toStringAsFixed(0);
  return value.toStringAsFixed(2);
}
