import '../../benchmark/models/benchmark_models.dart';

const benchmarkHistorySchema = 'win-deploy-studio/benchmark-history';
const benchmarkHistorySchemaVersion = 1;

class BenchmarkHistoryRecord {
  final String id;
  final DateTime savedAt;
  final BenchmarkResult result;

  const BenchmarkHistoryRecord({
    required this.id,
    required this.savedAt,
    required this.result,
  });

  Map<String, dynamic> toJson() => {
    'schema': benchmarkHistorySchema,
    'schemaVersion': benchmarkHistorySchemaVersion,
    'id': id,
    'savedAt': savedAt.toUtc().toIso8601String(),
    'result': result.toJson(),
  };

  factory BenchmarkHistoryRecord.fromJson(Map<String, dynamic> json) {
    final schema = json['schema']?.toString();
    final version = _readInt(json['schemaVersion']);
    if (schema != benchmarkHistorySchema ||
        version < 1 ||
        version > benchmarkHistorySchemaVersion) {
      throw const FormatException('Unsupported benchmark history schema');
    }
    final resultJson = json['result'];
    if (resultJson is! Map) {
      throw const FormatException('Benchmark history result is missing');
    }
    return BenchmarkHistoryRecord(
      id: json['id']?.toString() ?? '',
      savedAt:
          DateTime.tryParse(json['savedAt']?.toString() ?? '')?.toLocal() ??
          DateTime.fromMillisecondsSinceEpoch(0),
      result: BenchmarkResult.fromJson(Map<String, dynamic>.from(resultJson)),
    );
  }
}

class BenchmarkMetricDelta {
  final String key;
  final String label;
  final String unit;
  final double? baseline;
  final double? candidate;
  final bool lowerIsBetter;

  const BenchmarkMetricDelta({
    required this.key,
    required this.label,
    required this.unit,
    required this.baseline,
    required this.candidate,
    this.lowerIsBetter = false,
  });

  bool get isAvailable => baseline != null && candidate != null;

  double? get absoluteDelta => isAvailable ? candidate! - baseline! : null;

  double? get percentDelta => !isAvailable || baseline == 0
      ? null
      : (candidate! - baseline!) / baseline! * 100;

  bool get improved =>
      isAvailable &&
      (lowerIsBetter ? candidate! < baseline! : candidate! > baseline!);
}

enum BenchmarkComparisonIncompatibility {
  differentDevice,
  differentProtocol,
  differentMode,
  differentParameters,
}

class BenchmarkComparisonCompatibility {
  final BenchmarkComparisonIncompatibility? incompatibility;

  const BenchmarkComparisonCompatibility._(this.incompatibility);

  const BenchmarkComparisonCompatibility.compatible() : this._(null);

  const BenchmarkComparisonCompatibility.incompatible(
    BenchmarkComparisonIncompatibility reason,
  ) : this._(reason);

  bool get isCompatible => incompatibility == null;
}

class BenchmarkComparisonException implements Exception {
  final BenchmarkComparisonIncompatibility reason;

  const BenchmarkComparisonException(this.reason);

  @override
  String toString() => 'Incompatible benchmark comparison: ${reason.name}';
}

class BenchmarkComparison {
  final BenchmarkHistoryRecord baseline;
  final BenchmarkHistoryRecord candidate;
  final List<BenchmarkMetricDelta> metrics;

  const BenchmarkComparison({
    required this.baseline,
    required this.candidate,
    required this.metrics,
  });
}

class BenchmarkHistoryExport {
  final DateTime exportedAt;
  final List<BenchmarkHistoryRecord> records;

  const BenchmarkHistoryExport({
    required this.exportedAt,
    required this.records,
  });

  Map<String, dynamic> toJson() => {
    'schema': '$benchmarkHistorySchema/export',
    'schemaVersion': benchmarkHistorySchemaVersion,
    'exportedAt': exportedAt.toUtc().toIso8601String(),
    'records': records.map((record) => record.toJson()).toList(),
  };
}

int _readInt(dynamic value) {
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '') ?? 0;
}
