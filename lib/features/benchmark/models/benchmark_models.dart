import '../../../core/services/disk_safety_service.dart';

const benchmarkProtocolVersion = 3;
const supportedBenchmarkProtocolVersions = <int>{2, benchmarkProtocolVersion};

enum BenchmarkMode { quick, standard, extreme, fullWrite }

extension BenchmarkModeConfig on BenchmarkMode {
  String get titleKey => switch (this) {
    BenchmarkMode.quick => 'bench_mode_quick',
    BenchmarkMode.standard => 'bench_mode_standard',
    BenchmarkMode.extreme => 'bench_mode_extreme',
    BenchmarkMode.fullWrite => 'bench_mode_full_write',
  };

  String get descriptionKey => switch (this) {
    BenchmarkMode.quick => 'bench_mode_quick_desc',
    BenchmarkMode.standard => 'bench_mode_standard_desc',
    BenchmarkMode.extreme => 'bench_mode_extreme_desc',
    BenchmarkMode.fullWrite => 'bench_mode_full_write_desc',
  };

  int get sequentialSeconds => switch (this) {
    BenchmarkMode.quick => 6,
    BenchmarkMode.standard => 10,
    BenchmarkMode.extreme => 14,
    BenchmarkMode.fullWrite => 10,
  };

  int get random4kSeconds => switch (this) {
    BenchmarkMode.quick => 8,
    BenchmarkMode.standard => 12,
    BenchmarkMode.extreme => 18,
    BenchmarkMode.fullWrite => 12,
  };

  int get mixedWorkloadSeconds => switch (this) {
    BenchmarkMode.quick => 3,
    BenchmarkMode.standard => 5,
    BenchmarkMode.extreme => 8,
    BenchmarkMode.fullWrite => 5,
  };

  Duration get warmupDuration => switch (this) {
    BenchmarkMode.quick => const Duration(milliseconds: 750),
    BenchmarkMode.standard => const Duration(seconds: 1),
    BenchmarkMode.extreme => const Duration(seconds: 2),
    BenchmarkMode.fullWrite => const Duration(seconds: 1),
  };

  Duration get cooldownDuration => switch (this) {
    BenchmarkMode.quick => const Duration(milliseconds: 250),
    BenchmarkMode.standard => const Duration(milliseconds: 500),
    BenchmarkMode.extreme => const Duration(milliseconds: 750),
    BenchmarkMode.fullWrite => const Duration(milliseconds: 500),
  };

  Duration get fullWriteCooldownDuration => switch (this) {
    BenchmarkMode.fullWrite => const Duration(seconds: 15),
    _ => Duration.zero,
  };

  List<int> get threadCounts => switch (this) {
    BenchmarkMode.quick => const [1, 4, 8],
    BenchmarkMode.standard => const [1, 2, 4, 8, 16],
    BenchmarkMode.extreme => const [1, 2, 4, 8, 16, 32],
    BenchmarkMode.fullWrite => const [1, 2, 4, 8, 16],
  };

  int get threadSeconds => switch (this) {
    BenchmarkMode.quick => 3,
    BenchmarkMode.standard => 4,
    BenchmarkMode.extreme => 6,
    BenchmarkMode.fullWrite => 4,
  };

  int get sequentialLimitBytes => switch (this) {
    BenchmarkMode.quick => 512 * 1024 * 1024,
    BenchmarkMode.standard => 1024 * 1024 * 1024,
    BenchmarkMode.extreme => 2 * 1024 * 1024 * 1024,
    BenchmarkMode.fullWrite => 1024 * 1024 * 1024,
  };

  int get randomFileBytes => switch (this) {
    BenchmarkMode.quick => 256 * 1024 * 1024,
    BenchmarkMode.standard => 512 * 1024 * 1024,
    BenchmarkMode.extreme => 1024 * 1024 * 1024,
    BenchmarkMode.fullWrite => 512 * 1024 * 1024,
  };

  bool get includesFullWrite => this == BenchmarkMode.fullWrite;
}

enum BenchmarkFullWriteScope { selectedVolumeAvailableSpace }

enum BenchmarkFullWriteStatus { notRun, insufficientSpace, completed }

enum BenchmarkSlcStatus { notRun, insufficientRange, noInflection, detected }

class BenchmarkRunParameters {
  final int sequentialSeconds;
  final int random4kSeconds;
  final int mixedWorkloadSeconds;
  final int threadSeconds;
  final int sequentialLimitBytes;
  final int randomFileBytes;
  final int warmupMs;
  final int cooldownMs;
  final int fullWriteCooldownMs;
  final int fullWriteReserveBytes;
  final int fullWriteMinimumBytes;
  final List<int> threadCounts;
  final BenchmarkFullWriteScope fullWriteScope;

  const BenchmarkRunParameters({
    required this.sequentialSeconds,
    required this.random4kSeconds,
    required this.mixedWorkloadSeconds,
    required this.threadSeconds,
    required this.sequentialLimitBytes,
    required this.randomFileBytes,
    required this.warmupMs,
    required this.cooldownMs,
    required this.fullWriteCooldownMs,
    required this.fullWriteReserveBytes,
    required this.fullWriteMinimumBytes,
    required this.threadCounts,
    this.fullWriteScope = BenchmarkFullWriteScope.selectedVolumeAvailableSpace,
  });

  factory BenchmarkRunParameters.forMode(BenchmarkMode mode) {
    return BenchmarkRunParameters(
      sequentialSeconds: mode.sequentialSeconds,
      random4kSeconds: mode.random4kSeconds,
      mixedWorkloadSeconds: mode.mixedWorkloadSeconds,
      threadSeconds: mode.threadSeconds,
      sequentialLimitBytes: mode.sequentialLimitBytes,
      randomFileBytes: mode.randomFileBytes,
      warmupMs: mode.warmupDuration.inMilliseconds,
      cooldownMs: mode.cooldownDuration.inMilliseconds,
      fullWriteCooldownMs: mode.fullWriteCooldownDuration.inMilliseconds,
      fullWriteReserveBytes: 1024 * 1024 * 1024,
      fullWriteMinimumBytes: 1024 * 1024 * 1024,
      threadCounts: List.unmodifiable(mode.threadCounts),
    );
  }

  bool isCompatibleWith(BenchmarkRunParameters other) {
    return sequentialSeconds == other.sequentialSeconds &&
        random4kSeconds == other.random4kSeconds &&
        mixedWorkloadSeconds == other.mixedWorkloadSeconds &&
        threadSeconds == other.threadSeconds &&
        sequentialLimitBytes == other.sequentialLimitBytes &&
        randomFileBytes == other.randomFileBytes &&
        warmupMs == other.warmupMs &&
        cooldownMs == other.cooldownMs &&
        fullWriteCooldownMs == other.fullWriteCooldownMs &&
        fullWriteReserveBytes == other.fullWriteReserveBytes &&
        fullWriteMinimumBytes == other.fullWriteMinimumBytes &&
        fullWriteScope == other.fullWriteScope &&
        _intListsEqual(threadCounts, other.threadCounts);
  }

  Map<String, dynamic> toJson() => {
    'sequentialSeconds': sequentialSeconds,
    'random4kSeconds': random4kSeconds,
    'mixedWorkloadSeconds': mixedWorkloadSeconds,
    'threadSeconds': threadSeconds,
    'sequentialLimitBytes': sequentialLimitBytes,
    'randomFileBytes': randomFileBytes,
    'warmupMs': warmupMs,
    'cooldownMs': cooldownMs,
    'fullWriteCooldownMs': fullWriteCooldownMs,
    'fullWriteReserveBytes': fullWriteReserveBytes,
    'fullWriteMinimumBytes': fullWriteMinimumBytes,
    'threadCounts': threadCounts,
    'fullWriteScope': fullWriteScope.name,
  };

  factory BenchmarkRunParameters.fromJson(
    Map<String, dynamic> json,
    BenchmarkMode mode,
  ) {
    final defaults = BenchmarkRunParameters.forMode(mode);
    return BenchmarkRunParameters(
      sequentialSeconds: _readInt(
        json['sequentialSeconds'],
        fallback: defaults.sequentialSeconds,
      ),
      random4kSeconds: _readInt(
        json['random4kSeconds'],
        fallback: defaults.random4kSeconds,
      ),
      mixedWorkloadSeconds: _readInt(
        json['mixedWorkloadSeconds'],
        fallback: defaults.mixedWorkloadSeconds,
      ),
      threadSeconds: _readInt(
        json['threadSeconds'],
        fallback: defaults.threadSeconds,
      ),
      sequentialLimitBytes: _readInt(
        json['sequentialLimitBytes'],
        fallback: defaults.sequentialLimitBytes,
      ),
      randomFileBytes: _readInt(
        json['randomFileBytes'],
        fallback: defaults.randomFileBytes,
      ),
      warmupMs: _readInt(json['warmupMs'], fallback: defaults.warmupMs),
      cooldownMs: _readInt(json['cooldownMs'], fallback: defaults.cooldownMs),
      fullWriteCooldownMs: _readInt(
        json['fullWriteCooldownMs'],
        fallback: defaults.fullWriteCooldownMs,
      ),
      fullWriteReserveBytes: _readInt(
        json['fullWriteReserveBytes'],
        fallback: defaults.fullWriteReserveBytes,
      ),
      fullWriteMinimumBytes: _readInt(
        json['fullWriteMinimumBytes'],
        fallback: defaults.fullWriteMinimumBytes,
      ),
      threadCounts: _readIntList(
        json['threadCounts'],
        fallback: defaults.threadCounts,
      ),
      fullWriteScope: _enumByName(
        BenchmarkFullWriteScope.values,
        json['fullWriteScope'],
        defaults.fullWriteScope,
      ),
    );
  }
}

enum BenchmarkPhase {
  idle,
  preparing,
  warmingUp,
  sequential,
  random4k,
  multiThread,
  mixedWorkloads,
  coolingDown,
  fullSequential,
  finalizing,
  complete,
  cancelled,
  failed,
}

extension BenchmarkPhaseInfo on BenchmarkPhase {
  String get titleKey => switch (this) {
    BenchmarkPhase.idle => 'bench_phase_idle',
    BenchmarkPhase.preparing ||
    BenchmarkPhase.warmingUp => 'bench_phase_preparing',
    BenchmarkPhase.sequential => 'bench_phase_sequential',
    BenchmarkPhase.random4k => 'bench_phase_random4k',
    BenchmarkPhase.multiThread ||
    BenchmarkPhase.mixedWorkloads => 'bench_phase_multithread',
    BenchmarkPhase.coolingDown ||
    BenchmarkPhase.finalizing => 'bench_phase_finalizing',
    BenchmarkPhase.fullSequential => 'bench_phase_full',
    BenchmarkPhase.complete => 'bench_phase_complete',
    BenchmarkPhase.cancelled => 'bench_phase_cancelled',
    BenchmarkPhase.failed => 'bench_phase_failed',
  };
}

enum BenchmarkSuitability {
  excellent,
  good,
  usable,
  limited,
  notRecommended,
  unmeasured,
}

extension BenchmarkSuitabilityInfo on BenchmarkSuitability {
  String get titleKey => switch (this) {
    BenchmarkSuitability.excellent => 'bench_rating_excellent',
    BenchmarkSuitability.good => 'bench_rating_good',
    BenchmarkSuitability.usable => 'bench_rating_usable',
    BenchmarkSuitability.limited => 'bench_rating_limited',
    BenchmarkSuitability.notRecommended => 'bench_rating_not_recommended',
    BenchmarkSuitability.unmeasured => 'bench_rating_unmeasured',
  };

  String get descriptionKey => switch (this) {
    BenchmarkSuitability.excellent => 'bench_rating_excellent_desc',
    BenchmarkSuitability.good => 'bench_rating_good_desc',
    BenchmarkSuitability.usable => 'bench_rating_usable_desc',
    BenchmarkSuitability.limited => 'bench_rating_limited_desc',
    BenchmarkSuitability.notRecommended => 'bench_rating_not_recommended_desc',
    BenchmarkSuitability.unmeasured => 'bench_rating_unmeasured_desc',
  };
}

enum BenchmarkWorkload {
  sequentialRead,
  sequentialWrite,
  random4kRead,
  random4kWrite,
  random4kMultiThread,
  startup,
  browser,
  windowsUpdate,
  softwareInstall,
  multitasking,
  fullSequentialWrite,
}

enum MixedWorkloadScenario {
  startup,
  browser,
  windowsUpdate,
  softwareInstall,
  multitasking,
}

extension MixedWorkloadScenarioInfo on MixedWorkloadScenario {
  String get protocolName => switch (this) {
    MixedWorkloadScenario.startup => 'startup',
    MixedWorkloadScenario.browser => 'browser',
    MixedWorkloadScenario.windowsUpdate => 'windows_update',
    MixedWorkloadScenario.softwareInstall => 'software_install',
    MixedWorkloadScenario.multitasking => 'multitasking',
  };

  BenchmarkWorkload get workload => switch (this) {
    MixedWorkloadScenario.startup => BenchmarkWorkload.startup,
    MixedWorkloadScenario.browser => BenchmarkWorkload.browser,
    MixedWorkloadScenario.windowsUpdate => BenchmarkWorkload.windowsUpdate,
    MixedWorkloadScenario.softwareInstall => BenchmarkWorkload.softwareInstall,
    MixedWorkloadScenario.multitasking => BenchmarkWorkload.multitasking,
  };
}

class BenchmarkLatency {
  final double p50Ms;
  final double p95Ms;
  final double p99Ms;

  const BenchmarkLatency({this.p50Ms = 0, this.p95Ms = 0, this.p99Ms = 0});

  Map<String, dynamic> toJson() => {
    'p50Ms': p50Ms,
    'p95Ms': p95Ms,
    'p99Ms': p99Ms,
  };

  factory BenchmarkLatency.fromJson(Map<String, dynamic> json) {
    return BenchmarkLatency(
      p50Ms: _readDouble(json['p50Ms']),
      p95Ms: _readDouble(json['p95Ms']),
      p99Ms: _readDouble(json['p99Ms']),
    );
  }
}

class BenchmarkPoint {
  final double x;
  final double y;
  final String label;

  const BenchmarkPoint({required this.x, required this.y, this.label = ''});

  Map<String, dynamic> toJson() => {'x': x, 'y': y, 'label': label};

  factory BenchmarkPoint.fromJson(Map<String, dynamic> json) {
    return BenchmarkPoint(
      x: _readDouble(json['x']),
      y: _readDouble(json['y']),
      label: json['label']?.toString() ?? '',
    );
  }
}

class BenchmarkSample {
  final double x;
  final double throughputMBps;
  final double iops;
  final double readMBps;
  final double writeMBps;
  final BenchmarkLatency latency;
  final String label;

  const BenchmarkSample({
    required this.x,
    required this.throughputMBps,
    this.iops = 0,
    this.readMBps = 0,
    this.writeMBps = 0,
    this.latency = const BenchmarkLatency(),
    this.label = '',
  });

  BenchmarkPoint toPoint() =>
      BenchmarkPoint(x: x, y: throughputMBps, label: label);

  Map<String, dynamic> toJson() => {
    'x': x,
    'throughputMBps': throughputMBps,
    'iops': iops,
    'readMBps': readMBps,
    'writeMBps': writeMBps,
    'latency': latency.toJson(),
    'label': label,
  };

  factory BenchmarkSample.fromJson(Map<String, dynamic> json) {
    return BenchmarkSample(
      x: _readDouble(json['x']),
      throughputMBps: _readDouble(json['throughputMBps']),
      iops: _readDouble(json['iops']),
      readMBps: _readDouble(json['readMBps']),
      writeMBps: _readDouble(json['writeMBps']),
      latency: _readLatency(json['latency']),
      label: json['label']?.toString() ?? '',
    );
  }
}

class BenchmarkMeasurement {
  final BenchmarkWorkload workload;
  final int threadCount;
  final int readPercent;
  final double averageMBps;
  final double lowMBps;
  final double stability;
  final int bytesProcessed;
  final double iops;
  final double readMBps;
  final double writeMBps;
  final BenchmarkLatency latency;
  final double cacheInflectionGB;
  final double cacheStableMBps;
  final List<BenchmarkSample> samples;

  const BenchmarkMeasurement({
    required this.workload,
    this.threadCount = 1,
    this.readPercent = 0,
    required this.averageMBps,
    required this.lowMBps,
    required this.stability,
    this.bytesProcessed = 0,
    this.iops = 0,
    this.readMBps = 0,
    this.writeMBps = 0,
    this.latency = const BenchmarkLatency(),
    this.cacheInflectionGB = 0,
    this.cacheStableMBps = 0,
    this.samples = const [],
  });

  List<BenchmarkPoint> get points =>
      samples.map((sample) => sample.toPoint()).toList(growable: false);

  Map<String, dynamic> toJson() => {
    'workload': workload.name,
    'threadCount': threadCount,
    'readPercent': readPercent,
    'averageMBps': averageMBps,
    'lowMBps': lowMBps,
    'stability': stability,
    'bytesProcessed': bytesProcessed,
    'iops': iops,
    'readMBps': readMBps,
    'writeMBps': writeMBps,
    'latency': latency.toJson(),
    'cacheInflectionGB': cacheInflectionGB,
    'cacheStableMBps': cacheStableMBps,
    'samples': samples.map((sample) => sample.toJson()).toList(),
  };

  factory BenchmarkMeasurement.fromJson(Map<String, dynamic> json) {
    return BenchmarkMeasurement(
      workload: _enumByName(
        BenchmarkWorkload.values,
        json['workload'],
        BenchmarkWorkload.sequentialWrite,
      ),
      threadCount: _readInt(json['threadCount'], fallback: 1),
      readPercent: _readInt(json['readPercent']),
      averageMBps: _readDouble(json['averageMBps']),
      lowMBps: _readDouble(json['lowMBps']),
      stability: _readDouble(json['stability']),
      bytesProcessed: _readInt(json['bytesProcessed']),
      iops: _readDouble(json['iops']),
      readMBps: _readDouble(json['readMBps']),
      writeMBps: _readDouble(json['writeMBps']),
      latency: _readLatency(json['latency']),
      cacheInflectionGB: _readDouble(json['cacheInflectionGB']),
      cacheStableMBps: _readDouble(json['cacheStableMBps']),
      samples: _readMapList(json['samples'], BenchmarkSample.fromJson),
    );
  }

  BenchmarkSampleSeries toSeries() {
    return BenchmarkSampleSeries(
      workload: workload,
      threadCount: threadCount,
      readPercent: readPercent,
      averageMBps: averageMBps,
      iops: iops,
      readMBps: readMBps,
      writeMBps: writeMBps,
      latency: latency,
      samples: samples,
    );
  }
}

class BenchmarkSampleSeries {
  final BenchmarkWorkload workload;
  final int threadCount;
  final int readPercent;
  final double averageMBps;
  final double iops;
  final double readMBps;
  final double writeMBps;
  final BenchmarkLatency latency;
  final List<BenchmarkSample> samples;

  const BenchmarkSampleSeries({
    required this.workload,
    this.threadCount = 1,
    this.readPercent = 0,
    this.averageMBps = 0,
    this.iops = 0,
    this.readMBps = 0,
    this.writeMBps = 0,
    this.latency = const BenchmarkLatency(),
    this.samples = const [],
  });

  BenchmarkSampleSeries copyWith({
    double? averageMBps,
    double? iops,
    double? readMBps,
    double? writeMBps,
    BenchmarkLatency? latency,
    List<BenchmarkSample>? samples,
  }) {
    return BenchmarkSampleSeries(
      workload: workload,
      threadCount: threadCount,
      readPercent: readPercent,
      averageMBps: averageMBps ?? this.averageMBps,
      iops: iops ?? this.iops,
      readMBps: readMBps ?? this.readMBps,
      writeMBps: writeMBps ?? this.writeMBps,
      latency: latency ?? this.latency,
      samples: samples ?? this.samples,
    );
  }
}

List<BenchmarkSample> benchmarkChartSamples(
  Iterable<BenchmarkSampleSeries> series,
  BenchmarkWorkload workload,
) {
  final matching = series
      .where((item) => item.workload == workload)
      .toList(growable: false);
  if (workload != BenchmarkWorkload.random4kMultiThread) {
    final samples = matching.expand((item) => item.samples).toList();
    samples.sort((left, right) => left.x.compareTo(right.x));
    return List.unmodifiable(samples);
  }

  final samples = matching.map((item) {
    final sampleAverage = item.samples.isEmpty
        ? 0.0
        : item.samples
                  .map((sample) => sample.throughputMBps)
                  .reduce((left, right) => left + right) /
              item.samples.length;
    return BenchmarkSample(
      x: item.threadCount.toDouble(),
      throughputMBps: item.averageMBps > 0 ? item.averageMBps : sampleAverage,
      iops: item.iops,
      readMBps: item.readMBps,
      writeMBps: item.writeMBps,
      latency: item.latency,
      label: '${item.threadCount}',
    );
  }).toList();
  samples.sort((left, right) => left.x.compareTo(right.x));
  return List.unmodifiable(samples);
}

class BenchmarkDeviceIdentity {
  final int diskNumber;
  final String model;
  final String friendlyName;
  final String serialNumber;
  final String uniqueId;
  final String vid;
  final String pid;
  final String devicePath;
  final String busType;
  final int sizeBytes;

  const BenchmarkDeviceIdentity({
    required this.diskNumber,
    required this.model,
    required this.friendlyName,
    this.serialNumber = '',
    this.uniqueId = '',
    this.vid = '',
    this.pid = '',
    this.devicePath = '',
    this.busType = '',
    required this.sizeBytes,
  });

  factory BenchmarkDeviceIdentity.fromDisk(DiskInfo disk) {
    return BenchmarkDeviceIdentity(
      diskNumber: disk.diskNumber,
      model: disk.model,
      friendlyName: disk.friendlyName,
      serialNumber: disk.serialNumber,
      uniqueId: disk.uniqueId,
      vid: _extractHardwareId(disk.devicePath, 'VID'),
      pid: _extractHardwareId(disk.devicePath, 'PID'),
      devicePath: disk.devicePath,
      busType: disk.busType,
      sizeBytes: disk.sizeBytes,
    );
  }

  String get stableKey {
    final serial = _normalizeIdentity(serialNumber);
    if (_isUsableIdentity(serial)) return 'serial:$serial';
    final normalizedVid = _normalizeIdentity(vid);
    final normalizedPid = _normalizeIdentity(pid);
    if (_isUsableIdentity(normalizedVid) && _isUsableIdentity(normalizedPid)) {
      return 'usb:$normalizedVid:$normalizedPid:'
          '${_normalizeIdentity(model)}:$sizeBytes';
    }
    final unique = _normalizeIdentity(uniqueId);
    if (_isUsableIdentity(unique)) return 'uid:$unique';
    return 'fallback:${_normalizeIdentity(model)}:'
        '${_normalizeIdentity(busType)}:$sizeBytes';
  }

  bool isSameDevice(BenchmarkDeviceIdentity other) {
    final thisSerial = _normalizeIdentity(serialNumber);
    final otherSerial = _normalizeIdentity(other.serialNumber);
    if (_isUsableIdentity(thisSerial) && _isUsableIdentity(otherSerial)) {
      return thisSerial == otherSerial;
    }

    final thisVid = _normalizeIdentity(vid);
    final otherVid = _normalizeIdentity(other.vid);
    final thisPid = _normalizeIdentity(pid);
    final otherPid = _normalizeIdentity(other.pid);
    final bothHaveHardwareIds =
        _isUsableIdentity(thisVid) &&
        _isUsableIdentity(otherVid) &&
        _isUsableIdentity(thisPid) &&
        _isUsableIdentity(otherPid);
    if (bothHaveHardwareIds) {
      if (thisVid != otherVid || thisPid != otherPid) return false;
      final thisUniqueId = _normalizeIdentity(uniqueId);
      final otherUniqueId = _normalizeIdentity(other.uniqueId);
      if (_isUsableIdentity(thisUniqueId) && _isUsableIdentity(otherUniqueId)) {
        return thisUniqueId == otherUniqueId;
      }
      return _fallbackIdentityMatches(other);
    }

    final thisUniqueId = _normalizeIdentity(uniqueId);
    final otherUniqueId = _normalizeIdentity(other.uniqueId);
    if (_isUsableIdentity(thisUniqueId) && _isUsableIdentity(otherUniqueId)) {
      return thisUniqueId == otherUniqueId;
    }

    return _fallbackIdentityMatches(other);
  }

  bool _fallbackIdentityMatches(BenchmarkDeviceIdentity other) {
    final thisModel = _normalizeIdentity(model);
    final otherModel = _normalizeIdentity(other.model);
    if (!_isUsableIdentity(thisModel) ||
        !_isUsableIdentity(otherModel) ||
        thisModel != otherModel ||
        sizeBytes <= 0 ||
        sizeBytes != other.sizeBytes) {
      return false;
    }
    final thisBus = _normalizeIdentity(busType);
    final otherBus = _normalizeIdentity(other.busType);
    return !_isUsableIdentity(thisBus) ||
        !_isUsableIdentity(otherBus) ||
        thisBus == otherBus;
  }

  Map<String, dynamic> toJson() => {
    'diskNumber': diskNumber,
    'model': model,
    'friendlyName': friendlyName,
    'serialNumber': serialNumber,
    'uniqueId': uniqueId,
    'vid': vid,
    'pid': pid,
    'devicePath': devicePath,
    'busType': busType,
    'sizeBytes': sizeBytes,
    'stableKey': stableKey,
  };

  factory BenchmarkDeviceIdentity.fromJson(Map<String, dynamic> json) {
    return BenchmarkDeviceIdentity(
      diskNumber: _readInt(json['diskNumber']),
      model: json['model']?.toString() ?? '',
      friendlyName: json['friendlyName']?.toString() ?? '',
      serialNumber: json['serialNumber']?.toString() ?? '',
      uniqueId: json['uniqueId']?.toString() ?? '',
      vid: json['vid']?.toString() ?? '',
      pid: json['pid']?.toString() ?? '',
      devicePath: json['devicePath']?.toString() ?? '',
      busType: json['busType']?.toString() ?? '',
      sizeBytes: _readInt(json['sizeBytes']),
    );
  }
}

class BenchmarkProgress {
  final BenchmarkPhase phase;
  final double progress;
  final Duration elapsed;
  final String messageKey;
  final double currentSpeedMBps;
  final double currentIops;
  final BenchmarkLatency currentLatency;
  final List<BenchmarkPoint> sequentialReadPoints;
  final List<BenchmarkPoint> sequentialPoints;
  final List<BenchmarkPoint> random4kReadPoints;
  final List<BenchmarkPoint> random4kPoints;
  final List<BenchmarkPoint> threadPoints;
  final List<BenchmarkPoint> mixedWorkloadPoints;
  final List<BenchmarkPoint> fullWritePoints;
  final List<BenchmarkSampleSeries> sampleSeries;

  const BenchmarkProgress({
    required this.phase,
    required this.progress,
    required this.elapsed,
    required this.messageKey,
    this.currentSpeedMBps = 0,
    this.currentIops = 0,
    this.currentLatency = const BenchmarkLatency(),
    this.sequentialReadPoints = const [],
    this.sequentialPoints = const [],
    this.random4kReadPoints = const [],
    this.random4kPoints = const [],
    this.threadPoints = const [],
    this.mixedWorkloadPoints = const [],
    this.fullWritePoints = const [],
    this.sampleSeries = const [],
  });
}

class BenchmarkResult {
  final int protocolVersion;
  final DiskInfo disk;
  final BenchmarkDeviceIdentity device;
  final String driveRoot;
  final BenchmarkMode mode;
  final BenchmarkRunParameters parameters;
  final Duration duration;
  final Duration warmupDuration;
  final Duration cooldownDuration;
  final double sequentialReadMBps;
  final double sequentialWriteMBps;
  final double random4kReadAverageMBps;
  final double random4kReadIops;
  final double random4kWriteIops;
  final double random4kAverageMBps;
  final double random4kAdjustedMBps;
  final double random4kLowMBps;
  final double random4kStability;
  final double multiThreadPeakMBps;
  final double multiThreadMultiplier;
  final double multiThreadRetention;
  final double multiThreadNormalizedEfficiency;
  final double fullWriteP10MBps;
  final double fullWriteEndMBps;
  final double fullWriteDropRatio;
  final BenchmarkFullWriteStatus fullWriteStatus;
  final int fullWriteAvailableBytes;
  final int fullWriteTargetBytes;
  final BenchmarkSlcStatus slcStatus;
  final double slcCacheInflectionGB;
  final double postCacheStableMBps;
  final double slcConfidence;
  final double score;
  final BenchmarkSuitability suitability;
  final List<BenchmarkPoint> sequentialReadPoints;
  final List<BenchmarkPoint> sequentialPoints;
  final List<BenchmarkPoint> random4kReadPoints;
  final List<BenchmarkPoint> random4kPoints;
  final List<BenchmarkPoint> threadPoints;
  final List<BenchmarkPoint> mixedWorkloadPoints;
  final List<BenchmarkPoint> fullWritePoints;
  final List<BenchmarkMeasurement> measurements;
  final DateTime completedAt;
  final String historySaveError;

  const BenchmarkResult({
    this.protocolVersion = benchmarkProtocolVersion,
    required this.disk,
    required this.device,
    required this.driveRoot,
    required this.mode,
    required this.parameters,
    required this.duration,
    this.warmupDuration = Duration.zero,
    this.cooldownDuration = Duration.zero,
    this.sequentialReadMBps = 0,
    required this.sequentialWriteMBps,
    this.random4kReadAverageMBps = 0,
    this.random4kReadIops = 0,
    this.random4kWriteIops = 0,
    required this.random4kAverageMBps,
    required this.random4kAdjustedMBps,
    required this.random4kLowMBps,
    required this.random4kStability,
    required this.multiThreadPeakMBps,
    required this.multiThreadMultiplier,
    required this.multiThreadRetention,
    required this.multiThreadNormalizedEfficiency,
    required this.fullWriteP10MBps,
    required this.fullWriteEndMBps,
    required this.fullWriteDropRatio,
    this.fullWriteStatus = BenchmarkFullWriteStatus.notRun,
    this.fullWriteAvailableBytes = 0,
    this.fullWriteTargetBytes = 0,
    this.slcStatus = BenchmarkSlcStatus.notRun,
    this.slcCacheInflectionGB = 0,
    this.postCacheStableMBps = 0,
    this.slcConfidence = 0,
    required this.score,
    required this.suitability,
    this.sequentialReadPoints = const [],
    required this.sequentialPoints,
    this.random4kReadPoints = const [],
    required this.random4kPoints,
    required this.threadPoints,
    this.mixedWorkloadPoints = const [],
    required this.fullWritePoints,
    this.measurements = const [],
    required this.completedAt,
    this.historySaveError = '',
  });

  double get multiThreadScaleRatio => multiThreadRetention;

  double get fullWriteMinMBps => fullWriteP10MBps;

  bool get historySaveFailed => historySaveError.isNotEmpty;

  List<BenchmarkSampleSeries> get sampleSeries => measurements
      .map((measurement) => measurement.toSeries())
      .toList(growable: false);

  String get durationText {
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds.remainder(60);
    if (minutes <= 0) return '${seconds}s';
    return '${minutes}m ${seconds}s';
  }

  BenchmarkMeasurement? measurementFor(
    BenchmarkWorkload workload, {
    int? threadCount,
  }) {
    for (final measurement in measurements) {
      if (measurement.workload == workload &&
          (threadCount == null || measurement.threadCount == threadCount)) {
        return measurement;
      }
    }
    return null;
  }

  List<BenchmarkMeasurement> measurementsFor(BenchmarkWorkload workload) =>
      measurements
          .where((measurement) => measurement.workload == workload)
          .toList(growable: false);

  List<BenchmarkSample> chartSamplesFor(BenchmarkWorkload workload) =>
      benchmarkChartSamples(sampleSeries, workload);

  BenchmarkResult withHistorySaveError(Object error) {
    return BenchmarkResult(
      protocolVersion: protocolVersion,
      disk: disk,
      device: device,
      driveRoot: driveRoot,
      mode: mode,
      parameters: parameters,
      duration: duration,
      warmupDuration: warmupDuration,
      cooldownDuration: cooldownDuration,
      sequentialReadMBps: sequentialReadMBps,
      sequentialWriteMBps: sequentialWriteMBps,
      random4kReadAverageMBps: random4kReadAverageMBps,
      random4kReadIops: random4kReadIops,
      random4kWriteIops: random4kWriteIops,
      random4kAverageMBps: random4kAverageMBps,
      random4kAdjustedMBps: random4kAdjustedMBps,
      random4kLowMBps: random4kLowMBps,
      random4kStability: random4kStability,
      multiThreadPeakMBps: multiThreadPeakMBps,
      multiThreadMultiplier: multiThreadMultiplier,
      multiThreadRetention: multiThreadRetention,
      multiThreadNormalizedEfficiency: multiThreadNormalizedEfficiency,
      fullWriteP10MBps: fullWriteP10MBps,
      fullWriteEndMBps: fullWriteEndMBps,
      fullWriteDropRatio: fullWriteDropRatio,
      fullWriteStatus: fullWriteStatus,
      fullWriteAvailableBytes: fullWriteAvailableBytes,
      fullWriteTargetBytes: fullWriteTargetBytes,
      slcStatus: slcStatus,
      slcCacheInflectionGB: slcCacheInflectionGB,
      postCacheStableMBps: postCacheStableMBps,
      slcConfidence: slcConfidence,
      score: score,
      suitability: suitability,
      sequentialReadPoints: sequentialReadPoints,
      sequentialPoints: sequentialPoints,
      random4kReadPoints: random4kReadPoints,
      random4kPoints: random4kPoints,
      threadPoints: threadPoints,
      mixedWorkloadPoints: mixedWorkloadPoints,
      fullWritePoints: fullWritePoints,
      measurements: measurements,
      completedAt: completedAt,
      historySaveError: error.toString(),
    );
  }

  Map<String, dynamic> toJson() => {
    'protocolVersion': protocolVersion,
    'disk': disk.toJson(),
    'device': device.toJson(),
    'driveRoot': driveRoot,
    'mode': mode.name,
    'parameters': parameters.toJson(),
    'durationMs': duration.inMilliseconds,
    'warmupMs': warmupDuration.inMilliseconds,
    'cooldownMs': cooldownDuration.inMilliseconds,
    'sequentialReadMBps': sequentialReadMBps,
    'sequentialWriteMBps': sequentialWriteMBps,
    'random4kReadAverageMBps': random4kReadAverageMBps,
    'random4kReadIops': random4kReadIops,
    'random4kWriteIops': random4kWriteIops,
    'random4kAverageMBps': random4kAverageMBps,
    'random4kAdjustedMBps': random4kAdjustedMBps,
    'random4kLowMBps': random4kLowMBps,
    'random4kStability': random4kStability,
    'multiThreadPeakMBps': multiThreadPeakMBps,
    'multiThreadMultiplier': multiThreadMultiplier,
    'multiThreadRetention': multiThreadRetention,
    'multiThreadNormalizedEfficiency': multiThreadNormalizedEfficiency,
    'fullWriteP10MBps': fullWriteP10MBps,
    'fullWriteEndMBps': fullWriteEndMBps,
    'fullWriteDropRatio': fullWriteDropRatio,
    'fullWriteStatus': fullWriteStatus.name,
    'fullWriteAvailableBytes': fullWriteAvailableBytes,
    'fullWriteTargetBytes': fullWriteTargetBytes,
    'slcStatus': slcStatus.name,
    'slcCacheInflectionGB': slcCacheInflectionGB,
    'postCacheStableMBps': postCacheStableMBps,
    'slcConfidence': slcConfidence,
    'score': score,
    'suitability': suitability.name,
    'sequentialReadPoints': _pointsToJson(sequentialReadPoints),
    'sequentialPoints': _pointsToJson(sequentialPoints),
    'random4kReadPoints': _pointsToJson(random4kReadPoints),
    'random4kPoints': _pointsToJson(random4kPoints),
    'threadPoints': _pointsToJson(threadPoints),
    'mixedWorkloadPoints': _pointsToJson(mixedWorkloadPoints),
    'fullWritePoints': _pointsToJson(fullWritePoints),
    'measurements': measurements
        .map((measurement) => measurement.toJson())
        .toList(),
    'completedAt': completedAt.toUtc().toIso8601String(),
  };

  factory BenchmarkResult.fromJson(Map<String, dynamic> json) {
    final protocolVersion = _readInt(json['protocolVersion']);
    if (!supportedBenchmarkProtocolVersions.contains(protocolVersion)) {
      throw FormatException(
        'Unsupported benchmark protocol version: $protocolVersion',
      );
    }
    final diskJson = _readMap(json['disk']);
    final disk = DiskInfo.fromJson(diskJson);
    final deviceJson = _readMap(json['device']);
    final mode = _enumByName(
      BenchmarkMode.values,
      json['mode'],
      BenchmarkMode.standard,
    );
    final parametersJson = _readMap(json['parameters']);
    if (protocolVersion >= 3 && parametersJson.isEmpty) {
      throw const FormatException('Benchmark parameters are missing');
    }
    final threadPoints = _readPoints(json['threadPoints']);
    final fullWritePoints = _readPoints(json['fullWritePoints']);
    final legacyInflection = _readDouble(json['slcCacheInflectionGB']);
    final legacyRetention = _readDouble(json['multiThreadScaleRatio']);
    final inferredFullStatus = !mode.includesFullWrite
        ? BenchmarkFullWriteStatus.notRun
        : fullWritePoints.isEmpty
        ? BenchmarkFullWriteStatus.insufficientSpace
        : BenchmarkFullWriteStatus.completed;
    final inferredSlcStatus = !mode.includesFullWrite
        ? BenchmarkSlcStatus.notRun
        : fullWritePoints.length < 16
        ? BenchmarkSlcStatus.insufficientRange
        : legacyInflection > 0
        ? BenchmarkSlcStatus.detected
        : BenchmarkSlcStatus.noInflection;
    return BenchmarkResult(
      protocolVersion: protocolVersion,
      disk: disk,
      device: deviceJson.isEmpty
          ? BenchmarkDeviceIdentity.fromDisk(disk)
          : BenchmarkDeviceIdentity.fromJson(deviceJson),
      driveRoot: json['driveRoot']?.toString() ?? '',
      mode: mode,
      parameters: BenchmarkRunParameters.fromJson(parametersJson, mode),
      duration: Duration(milliseconds: _readInt(json['durationMs'])),
      warmupDuration: Duration(milliseconds: _readInt(json['warmupMs'])),
      cooldownDuration: Duration(milliseconds: _readInt(json['cooldownMs'])),
      sequentialReadMBps: _readDouble(json['sequentialReadMBps']),
      sequentialWriteMBps: _readDouble(json['sequentialWriteMBps']),
      random4kReadAverageMBps: _readDouble(json['random4kReadAverageMBps']),
      random4kReadIops: _readDouble(json['random4kReadIops']),
      random4kWriteIops: _readDouble(json['random4kWriteIops']),
      random4kAverageMBps: _readDouble(json['random4kAverageMBps']),
      random4kAdjustedMBps: _readDouble(json['random4kAdjustedMBps']),
      random4kLowMBps: _readDouble(json['random4kLowMBps']),
      random4kStability: _readDouble(json['random4kStability']),
      multiThreadPeakMBps: _readDouble(json['multiThreadPeakMBps']),
      multiThreadMultiplier: _readDouble(
        json['multiThreadMultiplier'],
        fallback: _threadMultiplier(threadPoints),
      ),
      multiThreadRetention: _readDouble(
        json['multiThreadRetention'],
        fallback: legacyRetention,
      ),
      multiThreadNormalizedEfficiency: _readDouble(
        json['multiThreadNormalizedEfficiency'],
        fallback: _threadEfficiency(threadPoints),
      ),
      fullWriteP10MBps: _readDouble(
        json['fullWriteP10MBps'],
        fallback: _readDouble(json['fullWriteMinMBps']),
      ),
      fullWriteEndMBps: _readDouble(json['fullWriteEndMBps']),
      fullWriteDropRatio: _readDouble(json['fullWriteDropRatio']),
      fullWriteStatus: _enumByName(
        BenchmarkFullWriteStatus.values,
        json['fullWriteStatus'],
        inferredFullStatus,
      ),
      fullWriteAvailableBytes: _readInt(json['fullWriteAvailableBytes']),
      fullWriteTargetBytes: _readInt(json['fullWriteTargetBytes']),
      slcStatus: _enumByName(
        BenchmarkSlcStatus.values,
        json['slcStatus'],
        inferredSlcStatus,
      ),
      slcCacheInflectionGB: legacyInflection,
      postCacheStableMBps: _readDouble(json['postCacheStableMBps']),
      slcConfidence: _readDouble(json['slcConfidence']),
      score: _readDouble(json['score']),
      suitability: _enumByName(
        BenchmarkSuitability.values,
        json['suitability'],
        BenchmarkSuitability.unmeasured,
      ),
      sequentialReadPoints: _readPoints(json['sequentialReadPoints']),
      sequentialPoints: _readPoints(json['sequentialPoints']),
      random4kReadPoints: _readPoints(json['random4kReadPoints']),
      random4kPoints: _readPoints(json['random4kPoints']),
      threadPoints: threadPoints,
      mixedWorkloadPoints: _readPoints(json['mixedWorkloadPoints']),
      fullWritePoints: fullWritePoints,
      measurements: _readMapList(
        json['measurements'],
        BenchmarkMeasurement.fromJson,
      ),
      completedAt:
          DateTime.tryParse(json['completedAt']?.toString() ?? '')?.toLocal() ??
          DateTime.fromMillisecondsSinceEpoch(0),
    );
  }
}

List<Map<String, dynamic>> _pointsToJson(List<BenchmarkPoint> points) =>
    points.map((point) => point.toJson()).toList(growable: false);

List<BenchmarkPoint> _readPoints(dynamic value) =>
    _readMapList(value, BenchmarkPoint.fromJson);

BenchmarkLatency _readLatency(dynamic value) {
  final json = _readMap(value);
  return json.isEmpty
      ? const BenchmarkLatency()
      : BenchmarkLatency.fromJson(json);
}

Map<String, dynamic> _readMap(dynamic value) {
  if (value is! Map) return const {};
  return Map<String, dynamic>.from(value);
}

List<T> _readMapList<T>(
  dynamic value,
  T Function(Map<String, dynamic>) decode,
) {
  if (value is! List) return const [];
  return value
      .whereType<Map>()
      .map((item) => decode(Map<String, dynamic>.from(item)))
      .toList(growable: false);
}

T _enumByName<T extends Enum>(List<T> values, dynamic value, T fallback) {
  final name = value?.toString();
  for (final item in values) {
    if (item.name == name) return item;
  }
  return fallback;
}

double _readDouble(dynamic value, {double fallback = 0}) {
  if (value is num) return value.toDouble();
  return double.tryParse(value?.toString() ?? '') ?? fallback;
}

int _readInt(dynamic value, {int fallback = 0}) {
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '') ?? fallback;
}

List<int> _readIntList(dynamic value, {required List<int> fallback}) {
  if (value is! List) return List.unmodifiable(fallback);
  final values = value
      .map((item) => _readInt(item, fallback: -1))
      .where((item) => item > 0)
      .toList(growable: false);
  return values.isEmpty
      ? List.unmodifiable(fallback)
      : List.unmodifiable(values);
}

bool _intListsEqual(List<int> left, List<int> right) {
  if (left.length != right.length) return false;
  for (var index = 0; index < left.length; index++) {
    if (left[index] != right[index]) return false;
  }
  return true;
}

double _threadMultiplier(List<BenchmarkPoint> points) {
  if (points.isEmpty) return 0;
  final single = points.where((point) => point.x.round() == 1).firstOrNull;
  if (single == null || single.y <= 0) return 0;
  final peak = points
      .map((point) => point.y)
      .reduce((left, right) => left > right ? left : right);
  return peak / single.y;
}

double _threadEfficiency(List<BenchmarkPoint> points) {
  if (points.isEmpty) return 0;
  final single = points.where((point) => point.x.round() == 1).firstOrNull;
  if (single == null || single.y <= 0) return 0;
  final peak = points.reduce((left, right) => left.y >= right.y ? left : right);
  if (peak.x <= 0) return 0;
  return (peak.y / (single.y * peak.x)).clamp(0.0, 1.0);
}

String _extractHardwareId(String path, String key) {
  final match = RegExp(
    '$key(?:_|&|%5F)([0-9A-Fa-f]{4})',
    caseSensitive: false,
  ).firstMatch(path);
  return match?.group(1)?.toUpperCase() ?? '';
}

String _normalizeIdentity(String value) => value
    .trim()
    .toUpperCase()
    .replaceAll(RegExp(r'\s+'), '')
    .replaceAll(RegExp(r'[-_.:/\\&{}()\[\]]'), '');

bool _isUsableIdentity(String value) =>
    value.isNotEmpty &&
    value != 'NA' &&
    value != 'NONE' &&
    value != 'UNKNOWN' &&
    value != '0' &&
    value != 'TOBEFILLEDBYOEM';
