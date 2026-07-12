import 'package:win_deploy_studio/core/services/disk_safety_service.dart';
import 'package:win_deploy_studio/features/benchmark/models/benchmark_models.dart';
import 'package:win_deploy_studio/features/benchmark_history/models/benchmark_history_models.dart';

BenchmarkResult benchmarkTestResult({
  DateTime? completedAt,
  int protocolVersion = benchmarkProtocolVersion,
  BenchmarkMode mode = BenchmarkMode.standard,
  BenchmarkRunParameters? parameters,
  String model = 'Portable SSD',
  String serialNumber = 'SERIAL-1234',
  String uniqueId = 'UNIQUE-1234',
  String vid = '1234',
  String pid = '5678',
  double score = 82,
  BenchmarkSuitability suitability = BenchmarkSuitability.good,
  List<BenchmarkMeasurement>? measurements,
  BenchmarkSlcStatus slcStatus = BenchmarkSlcStatus.notRun,
  double slcInflectionGB = 0,
}) {
  final disk = DiskInfo(
    diskNumber: 3,
    model: model,
    friendlyName: model,
    sizeBytes: 512110190592,
    sizeFormatted: '476.9 GB',
    serialNumber: serialNumber,
    uniqueId: uniqueId,
    devicePath: 'USBSTOR\\VID_$vid&PID_$pid',
    busType: 'USB',
    partitionStyle: 'GPT',
    isRemovable: true,
    driveLetters: const ['R:'],
  );
  final device = BenchmarkDeviceIdentity(
    diskNumber: disk.diskNumber,
    model: model,
    friendlyName: model,
    serialNumber: serialNumber,
    uniqueId: uniqueId,
    vid: vid,
    pid: pid,
    devicePath: disk.devicePath,
    busType: disk.busType,
    sizeBytes: disk.sizeBytes,
  );
  final values = measurements ?? benchmarkTestMeasurements();
  return BenchmarkResult(
    protocolVersion: protocolVersion,
    disk: disk,
    device: device,
    driveRoot: r'R:\',
    mode: mode,
    parameters: parameters ?? BenchmarkRunParameters.forMode(mode),
    duration: const Duration(minutes: 2),
    warmupDuration: const Duration(seconds: 10),
    cooldownDuration: const Duration(seconds: 5),
    sequentialReadMBps: 440,
    sequentialWriteMBps: 390,
    random4kReadAverageMBps: 36,
    random4kReadIops: 9200,
    random4kWriteIops: 7000,
    random4kAverageMBps: 28,
    random4kAdjustedMBps: 25,
    random4kLowMBps: 19,
    random4kStability: 0.9,
    multiThreadPeakMBps: 105,
    multiThreadMultiplier: 2.1,
    multiThreadRetention: 0.86,
    multiThreadNormalizedEfficiency: 0.52,
    fullWriteP10MBps: 0,
    fullWriteEndMBps: 0,
    fullWriteDropRatio: 0,
    slcStatus: slcStatus,
    slcCacheInflectionGB: slcInflectionGB,
    postCacheStableMBps: slcStatus == BenchmarkSlcStatus.detected ? 125 : 0,
    slcConfidence: slcStatus == BenchmarkSlcStatus.detected ? 0.87 : 0,
    score: score,
    suitability: suitability,
    sequentialReadPoints: const [BenchmarkPoint(x: 1, y: 440)],
    sequentialPoints: const [BenchmarkPoint(x: 1, y: 390)],
    random4kReadPoints: const [BenchmarkPoint(x: 1, y: 36)],
    random4kPoints: const [BenchmarkPoint(x: 1, y: 28)],
    threadPoints: const [
      BenchmarkPoint(x: 1, y: 50),
      BenchmarkPoint(x: 4, y: 105),
      BenchmarkPoint(x: 8, y: 90),
    ],
    mixedWorkloadPoints: const [BenchmarkPoint(x: 1, y: 35)],
    fullWritePoints: const [],
    measurements: values,
    completedAt: completedAt ?? DateTime.utc(2026, 7, 12),
  );
}

List<BenchmarkMeasurement> benchmarkTestMeasurements() {
  BenchmarkMeasurement measurement(
    BenchmarkWorkload workload, {
    double speed = 40,
    double iops = 8000,
    int threads = 1,
    int readPercent = 0,
    double p99 = 12,
  }) {
    final latency = BenchmarkLatency(p50Ms: 1, p95Ms: 5, p99Ms: p99);
    return BenchmarkMeasurement(
      workload: workload,
      threadCount: threads,
      readPercent: readPercent,
      averageMBps: speed,
      lowMBps: speed * 0.8,
      stability: 0.9,
      bytesProcessed: 64 * 1024 * 1024,
      iops: iops,
      readMBps: readPercent > 0 ? speed * readPercent / 100 : 0,
      writeMBps: readPercent < 100 ? speed * (100 - readPercent) / 100 : 0,
      latency: latency,
      samples: [
        BenchmarkSample(
          x: 0.5,
          throughputMBps: speed * 0.95,
          iops: iops * 0.95,
          latency: latency,
        ),
        BenchmarkSample(
          x: 1,
          throughputMBps: speed,
          iops: iops,
          latency: latency,
        ),
      ],
    );
  }

  return [
    measurement(BenchmarkWorkload.sequentialWrite, speed: 390, iops: 50),
    measurement(
      BenchmarkWorkload.sequentialRead,
      speed: 440,
      iops: 55,
      readPercent: 100,
    ),
    measurement(BenchmarkWorkload.random4kWrite, speed: 28, iops: 7000),
    measurement(
      BenchmarkWorkload.random4kRead,
      speed: 36,
      iops: 9200,
      readPercent: 100,
    ),
    measurement(
      BenchmarkWorkload.random4kMultiThread,
      speed: 50,
      iops: 12500,
      threads: 1,
      readPercent: 50,
    ),
    measurement(
      BenchmarkWorkload.random4kMultiThread,
      speed: 105,
      iops: 26250,
      threads: 4,
      readPercent: 50,
    ),
    measurement(
      BenchmarkWorkload.random4kMultiThread,
      speed: 90,
      iops: 22500,
      threads: 8,
      readPercent: 50,
    ),
    measurement(BenchmarkWorkload.startup, speed: 40, iops: 6000),
    measurement(BenchmarkWorkload.browser, speed: 30, iops: 5000),
    measurement(BenchmarkWorkload.windowsUpdate, speed: 70, iops: 3500),
    measurement(BenchmarkWorkload.softwareInstall, speed: 100, iops: 1800),
    measurement(BenchmarkWorkload.multitasking, speed: 60, iops: 7000),
  ];
}

BenchmarkHistoryRecord benchmarkTestRecord(
  BenchmarkResult result, {
  String id = 'record',
}) {
  return BenchmarkHistoryRecord(
    id: id,
    savedAt: result.completedAt,
    result: result,
  );
}
