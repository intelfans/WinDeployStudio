import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import '../constants/app_constants.dart';

enum LogLevel { info, warning, error, success }

class LogEntry {
  final DateTime timestamp;
  final String action;
  final String target;
  final String result;
  final LogLevel level;

  const LogEntry({
    required this.timestamp,
    required this.action,
    required this.target,
    required this.result,
    this.level = LogLevel.info,
  });

  @override
  String toString() {
    final time = timestamp.toString().substring(0, 19);
    final levelStr = level.name.toUpperCase();
    return '[$time] [$levelStr] $action | $target | $result';
  }
}

final fileLoggerServiceProvider = Provider<FileLoggerService>((ref) {
  return FileLoggerService();
});

class FileLoggerService {
  Directory? _logDir;
  final List<LogEntry> _entries = [];
  static const _maxEntries = 1000;

  List<LogEntry> get entries => List.unmodifiable(_entries);

  Future<Directory> get logDir async {
    if (_logDir != null) return _logDir!;
    final appDir = await getApplicationSupportDirectory();
    _logDir = Directory(p.join(appDir.path, AppConstants.logDirName));
    if (!await _logDir!.exists()) {
      await _logDir!.create(recursive: true);
    }
    return _logDir!;
  }

  Future<void> log({
    required String action,
    required String target,
    required String result,
    LogLevel level = LogLevel.info,
  }) async {
    final entry = LogEntry(
      timestamp: DateTime.now(),
      action: action,
      target: target,
      result: result,
      level: level,
    );

    _entries.add(entry);
    if (_entries.length > _maxEntries) {
      _entries.removeRange(0, _entries.length - _maxEntries);
    }

    try {
      final dir = await logDir;
      final now = DateTime.now();
      final dateStr = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
      final logFile = File(p.join(dir.path, '$dateStr.log'));

      await logFile.writeAsString(
        '${entry.toString()}\n',
        mode: FileMode.append,
      );

      await _cleanOldLogs(dir);
    } catch (_) {}
  }

  Future<void> _cleanOldLogs(Directory dir) async {
    try {
      final files = dir.listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.log'))
          .toList();

      if (files.length > AppConstants.maxLogFiles) {
        files.sort((a, b) => a.lastModifiedSync().compareTo(b.lastModifiedSync()));
        final toDelete = files.take(files.length - AppConstants.maxLogFiles);
        for (final file in toDelete) {
          await file.delete();
        }
      }
    } catch (_) {}
  }

  Future<List<LogEntry>> loadTodayLogs() async {
    try {
      final dir = await logDir;
      final now = DateTime.now();
      final dateStr = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
      final logFile = File(p.join(dir.path, '$dateStr.log'));

      if (!await logFile.exists()) return [];

      final lines = await logFile.readAsLines();
      return lines.where((l) => l.isNotEmpty).map((line) {
        final timestampMatch = RegExp(r'^\[(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2})\]').firstMatch(line);
        final timestamp = timestampMatch != null
            ? (DateTime.tryParse(timestampMatch.group(1)!) ?? DateTime.now())
            : DateTime.now();

        String action = '';
        String target = '';
        String result = line;

        final parts = RegExp(r'^\[.*?\]\s*\[\w+\]\s*(.+?)\s*\|\s*(.+?)\s*\|\s*(.+)$').firstMatch(line);
        if (parts != null) {
          action = parts.group(1) ?? '';
          target = parts.group(2) ?? '';
          result = parts.group(3) ?? '';
        }

        return LogEntry(
          timestamp: timestamp,
          action: action,
          target: target,
          result: result,
        );
      }).toList();
    } catch (_) {
      return [];
    }
  }
}
