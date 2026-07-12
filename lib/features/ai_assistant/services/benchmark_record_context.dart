import '../../benchmark/models/benchmark_models.dart';
import '../../benchmark_history/models/benchmark_history_models.dart';

/// Converts selected, user-approved benchmark records into an auditable
/// plain-text context block for the AI request.
String buildBenchmarkRecordContext(Iterable<BenchmarkHistoryRecord> records) {
  final selected = records.toList(growable: false);
  final buffer = StringBuffer()
    ..writeln('[SELECTED DISK TEST RECORDS]')
    ..writeln('Record count: ${selected.length}')
    ..writeln(
      'These are user-selected local benchmark records. Analyze them as measurements, not as a guarantee of device health or future performance.',
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
      '- Multi-thread peak, multiplier, retention, and normalized efficiency: concurrency scaling. Higher retention and efficiency indicate that performance holds up under parallel work.',
    )
    ..writeln(
      '- Full-write P10/end/drop and SLC-cache values: sustained-write behavior after cache exhaustion. Lower drop and higher post-cache speed are better.',
    )
    ..writeln(
      '- Score and suitability are application heuristics derived from this test, not a replacement for SMART health data or a warranty assessment.',
    );

  for (var index = 0; index < selected.length; index++) {
    _writeRecord(buffer, selected[index], index + 1);
  }
  return buffer.toString();
}

void _writeRecord(
  StringBuffer buffer,
  BenchmarkHistoryRecord record,
  int index,
) {
  final result = record.result;
  final disk = result.disk;
  final device = result.device;
  final parameters = result.parameters;
  buffer
    ..writeln()
    ..writeln('[DISK TEST RECORD $index]')
    ..writeln('Record ID: ${record.id}')
    ..writeln('Saved at (local): ${record.savedAt.toIso8601String()}')
    ..writeln('Completed at (local): ${result.completedAt.toIso8601String()}')
    ..writeln('Protocol version: ${result.protocolVersion}')
    ..writeln('Mode: ${result.mode.name}')
    ..writeln('Duration: ${_duration(result.duration)}')
    ..writeln('Warmup: ${_duration(result.warmupDuration)}')
    ..writeln('Cooldown: ${_duration(result.cooldownDuration)}')
    ..writeln()
    ..writeln('[DEVICE AND VOLUME]')
    ..writeln('Disk number: ${disk.diskNumber}')
    ..writeln('Model: ${_value(disk.model)}')
    ..writeln('Friendly name: ${_value(disk.friendlyName)}')
    ..writeln(
      'Capacity: ${disk.sizeBytes} bytes (${_value(disk.sizeFormatted)})',
    )
    ..writeln('Bus type: ${_value(disk.busType)}')
    ..writeln('Partition style: ${_value(disk.partitionStyle)}')
    ..writeln('Drive root: ${_value(result.driveRoot)}')
    ..writeln('Drive letters: ${_value(disk.driveLetters.join(', '))}')
    ..writeln('Serial number: ${_value(device.serialNumber)}')
    ..writeln('Unique ID: ${_value(device.uniqueId)}')
    ..writeln('VID/PID: ${_value(device.vid)}/${_value(device.pid)}')
    ..writeln('Device path: ${_value(device.devicePath)}')
    ..writeln('Stable identity key: ${_value(device.stableKey)}')
    ..writeln('System disk: ${disk.isSystem}')
    ..writeln('Boot disk: ${disk.isBoot}')
    ..writeln('Offline: ${disk.isOffline}')
    ..writeln('Removable: ${disk.isRemovable}')
    ..writeln('Partitions: ${disk.partitions.length}');
  for (final partition in disk.partitions) {
    buffer.writeln(
      '  Partition: type=${_value(partition.type)}, sizeBytes=${partition.sizeBytes}, drive=${_value(partition.driveLetter ?? '')}, system=${partition.isSystem}, active=${partition.isActive}',
    );
  }

  buffer
    ..writeln()
    ..writeln('[RUN PARAMETERS]')
    ..writeln('Sequential stage seconds: ${parameters.sequentialSeconds}')
    ..writeln('4K random stage seconds: ${parameters.random4kSeconds}')
    ..writeln(
      'Mixed workload stage seconds: ${parameters.mixedWorkloadSeconds}',
    )
    ..writeln('Thread stage seconds: ${parameters.threadSeconds}')
    ..writeln('Sequential limit bytes: ${parameters.sequentialLimitBytes}')
    ..writeln('Random test file bytes: ${parameters.randomFileBytes}')
    ..writeln('Warmup ms: ${parameters.warmupMs}')
    ..writeln('Cooldown ms: ${parameters.cooldownMs}')
    ..writeln('Full-write cooldown ms: ${parameters.fullWriteCooldownMs}')
    ..writeln('Full-write reserve bytes: ${parameters.fullWriteReserveBytes}')
    ..writeln('Full-write minimum bytes: ${parameters.fullWriteMinimumBytes}')
    ..writeln('Thread counts: ${parameters.threadCounts.join(', ')}')
    ..writeln('Full-write scope: ${parameters.fullWriteScope.name}')
    ..writeln()
    ..writeln('[SUMMARY METRICS]')
    ..writeln('Score: ${_number(result.score)}/100')
    ..writeln('Suitability: ${result.suitability.name}')
    ..writeln('Sequential read: ${_number(result.sequentialReadMBps)} MB/s')
    ..writeln('Sequential write: ${_number(result.sequentialWriteMBps)} MB/s')
    ..writeln(
      '4K random read: ${_number(result.random4kReadAverageMBps)} MB/s, ${_number(result.random4kReadIops)} IOPS',
    )
    ..writeln(
      '4K random write: ${_number(result.random4kAverageMBps)} MB/s, ${_number(result.random4kWriteIops)} IOPS',
    )
    ..writeln(
      '4K adjusted throughput: ${_number(result.random4kAdjustedMBps)} MB/s',
    )
    ..writeln('4K low throughput: ${_number(result.random4kLowMBps)} MB/s')
    ..writeln('4K stability: ${_number(result.random4kStability * 100)}%')
    ..writeln('Multi-thread peak: ${_number(result.multiThreadPeakMBps)} MB/s')
    ..writeln(
      'Multi-thread multiplier: ${_number(result.multiThreadMultiplier)}x',
    )
    ..writeln(
      'Multi-thread retention: ${_number(result.multiThreadRetention * 100)}%',
    )
    ..writeln(
      'Multi-thread normalized efficiency: ${_number(result.multiThreadNormalizedEfficiency * 100)}%',
    )
    ..writeln('Full-write status: ${result.fullWriteStatus.name}')
    ..writeln('Full-write available bytes: ${result.fullWriteAvailableBytes}')
    ..writeln('Full-write target bytes: ${result.fullWriteTargetBytes}')
    ..writeln('Full-write P10: ${_number(result.fullWriteP10MBps)} MB/s')
    ..writeln('Full-write end: ${_number(result.fullWriteEndMBps)} MB/s')
    ..writeln(
      'Full-write drop ratio: ${_number(result.fullWriteDropRatio * 100)}%',
    )
    ..writeln('SLC status: ${result.slcStatus.name}')
    ..writeln(
      'SLC cache inflection: ${_number(result.slcCacheInflectionGB)} GB',
    )
    ..writeln(
      'Post-cache stable speed: ${_number(result.postCacheStableMBps)} MB/s',
    )
    ..writeln('SLC confidence: ${_number(result.slcConfidence * 100)}%')
    ..writeln('History save error: ${_value(result.historySaveError)}')
    ..writeln()
    ..writeln('[WORKLOAD MEASUREMENTS]');

  for (final measurement in result.measurements) {
    buffer
      ..writeln(
        'Workload: ${measurement.workload.name}; threads=${measurement.threadCount}; readPercent=${measurement.readPercent}',
      )
      ..writeln(
        '  average=${_number(measurement.averageMBps)} MB/s; low=${_number(measurement.lowMBps)} MB/s; stability=${_number(measurement.stability * 100)}%; bytesProcessed=${measurement.bytesProcessed}',
      )
      ..writeln(
        '  IOPS=${_number(measurement.iops)}; read=${_number(measurement.readMBps)} MB/s; write=${_number(measurement.writeMBps)} MB/s',
      )
      ..writeln(
        '  latency p50=${_number(measurement.latency.p50Ms)} ms; p95=${_number(measurement.latency.p95Ms)} ms; p99=${_number(measurement.latency.p99Ms)} ms',
      )
      ..writeln(
        '  cache inflection=${_number(measurement.cacheInflectionGB)} GB; cache stable=${_number(measurement.cacheStableMBps)} MB/s; samples=${measurement.samples.length}',
      );
    for (
      var sampleIndex = 0;
      sampleIndex < measurement.samples.length;
      sampleIndex++
    ) {
      final sample = measurement.samples[sampleIndex];
      buffer.writeln(
        '  sample ${sampleIndex + 1}: x=${_number(sample.x)}; throughput=${_number(sample.throughputMBps)} MB/s; IOPS=${_number(sample.iops)}; read=${_number(sample.readMBps)} MB/s; write=${_number(sample.writeMBps)} MB/s; p50=${_number(sample.latency.p50Ms)} ms; p95=${_number(sample.latency.p95Ms)} ms; p99=${_number(sample.latency.p99Ms)} ms; label=${_value(sample.label)}',
      );
    }
  }

  buffer
    ..writeln()
    ..writeln('[CHART POINTS]');
  _writePoints(buffer, 'Sequential read', result.sequentialReadPoints);
  _writePoints(buffer, 'Sequential write', result.sequentialPoints);
  _writePoints(buffer, '4K random read', result.random4kReadPoints);
  _writePoints(buffer, '4K random write', result.random4kPoints);
  _writePoints(buffer, 'Multi-thread', result.threadPoints);
  _writePoints(buffer, 'Mixed workload', result.mixedWorkloadPoints);
  _writePoints(buffer, 'Full sequential write', result.fullWritePoints);
}

void _writePoints(
  StringBuffer buffer,
  String label,
  List<BenchmarkPoint> points,
) {
  buffer.writeln('$label points: ${points.length}');
  for (var index = 0; index < points.length; index++) {
    final point = points[index];
    buffer.writeln(
      '  point ${index + 1}: x=${_number(point.x)}; y=${_number(point.y)}; label=${_value(point.label)}',
    );
  }
}

String _duration(Duration value) => '${value.inMilliseconds} ms';

String _value(String value) => value.trim().isEmpty ? '(not reported)' : value;

String _number(double value) {
  if (!value.isFinite) return '(not reported)';
  if (value == value.roundToDouble()) return value.toStringAsFixed(0);
  return value.toStringAsFixed(2);
}
