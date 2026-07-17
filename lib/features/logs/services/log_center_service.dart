import 'dart:io';
import 'package:path/path.dart' as p;
import '../../../core/constants/app_constants.dart';
import '../models/log_category.dart';

class LogCenterService {
  static LogCenterService? _instance;
  late final String _logsBasePath;
  DateTime? _lastAutomaticCleanup;

  LogCenterService._() {
    _logsBasePath = p.join(AppConstants.appDataPath, 'WinDeployStudio', 'logs');
    _ensureDirectories();
  }

  factory LogCenterService() {
    _instance ??= LogCenterService._();
    return _instance!;
  }

  String get logsBasePath => _logsBasePath;

  void _ensureDirectories() {
    for (final category in LogCategory.values) {
      final dir = Directory(p.join(_logsBasePath, category.folderName));
      if (!dir.existsSync()) {
        dir.createSync(recursive: true);
      }
    }
  }

  Future<void> log(LogCategory category, String message) async {
    final now = DateTime.now();
    final fileName =
        '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}_${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}${now.second.toString().padLeft(2, '0')}.log';
    final filePath = p.join(_logsBasePath, category.folderName, fileName);

    final file = File(filePath);
    final timestamp = now.toIso8601String();
    await file.writeAsString('[$timestamp] $message\n', mode: FileMode.append);
    await _runAutomaticCleanup(now);
  }

  Future<void> _runAutomaticCleanup(DateTime now) async {
    if (_lastAutomaticCleanup != null &&
        now.difference(_lastAutomaticCleanup!).inHours < 1) {
      return;
    }
    _lastAutomaticCleanup = now;
    final cutoff = now.subtract(
      const Duration(days: AppConstants.logRetentionDays),
    );
    for (final category in LogCategory.values) {
      final directory = Directory(p.join(_logsBasePath, category.folderName));
      if (!await directory.exists()) continue;
      final files = await directory
          .list()
          .where((entity) => entity is File && entity.path.endsWith('.log'))
          .cast<File>()
          .toList();
      files.sort(
        (left, right) =>
            right.lastModifiedSync().compareTo(left.lastModifiedSync()),
      );
      for (var index = 0; index < files.length; index++) {
        final file = files[index];
        final tooOld = file.lastModifiedSync().isBefore(cutoff);
        final overLimit = index >= AppConstants.maxLogFiles;
        if (tooOld || overLimit) {
          try {
            await file.delete();
          } catch (_) {}
        }
      }
    }
  }

  Future<void> logUsb(String message) => log(LogCategory.usb, message);
  Future<void> logToGo(String message) => log(LogCategory.wtg, message);
  Future<void> logBenchmark(String message) =>
      log(LogCategory.benchmark, message);
  Future<void> logDownload(String message) =>
      log(LogCategory.downloads, message);
  Future<void> logIso(String message) => log(LogCategory.iso, message);
  Future<void> logSystem(String message) => log(LogCategory.system, message);
  Future<void> logError(String message) => log(LogCategory.errors, message);
  Future<void> logUpdate(String message) => log(LogCategory.update, message);

  Future<LogStats> getStats() async {
    int totalFiles = 0;
    int totalSize = 0;
    DateTime? lastActivity;
    final categoryCounts = <LogCategory, int>{};
    final categoryLastUpdates = <LogCategory, DateTime?>{};

    for (final category in LogCategory.values) {
      final dir = Directory(p.join(_logsBasePath, category.folderName));
      if (dir.existsSync()) {
        final files = dir.listSync().whereType<File>().where(
          (f) => f.path.endsWith('.log'),
        );
        int count = 0;
        DateTime? categoryLastUpdate;
        for (final file in files) {
          count++;
          totalFiles++;
          final stat = file.statSync();
          totalSize += stat.size;
          if (lastActivity == null || stat.modified.isAfter(lastActivity)) {
            lastActivity = stat.modified;
          }
          if (categoryLastUpdate == null ||
              stat.modified.isAfter(categoryLastUpdate)) {
            categoryLastUpdate = stat.modified;
          }
        }
        categoryCounts[category] = count;
        categoryLastUpdates[category] = categoryLastUpdate;
      } else {
        categoryCounts[category] = 0;
        categoryLastUpdates[category] = null;
      }
    }

    return LogStats(
      totalFiles: totalFiles,
      totalSizeBytes: totalSize,
      lastActivity: lastActivity,
      categoryCounts: categoryCounts,
      categoryLastUpdates: categoryLastUpdates,
    );
  }

  Future<List<LogFileInfo>> getCategoryFiles(LogCategory category) async {
    final dir = Directory(p.join(_logsBasePath, category.folderName));
    if (!dir.existsSync()) return [];

    final files = dir
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.log'))
        .toList();

    files.sort(
      (a, b) => b.statSync().modified.compareTo(a.statSync().modified),
    );

    return files.map((f) {
      final stat = f.statSync();
      return LogFileInfo(
        path: f.path,
        name: p.basename(f.path),
        sizeBytes: stat.size,
        lastModified: stat.modified,
      );
    }).toList();
  }

  Future<List<LogActivity>> getRecentActivities({int limit = 20}) async {
    final activities = <LogActivity>[];

    for (final category in LogCategory.values) {
      final files = await getCategoryFiles(category);
      for (final file in files.take(5)) {
        activities.add(
          LogActivity(
            category: category,
            title: _extractTitle(file.name),
            timestamp: file.lastModified,
          ),
        );
      }
    }

    activities.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return activities.take(limit).toList();
  }

  String _extractTitle(String fileName) {
    final name = fileName.replaceAll('.log', '');
    final parts = name.split('_');
    if (parts.length >= 2) {
      return parts.sublist(1).join('_').replaceAll('-', ' ');
    }
    return name;
  }

  Future<void> openLogsFolder() async {
    await Process.run('explorer', [_logsBasePath]);
  }

  Future<void> openCategoryFolder(LogCategory category) async {
    final path = p.join(_logsBasePath, category.folderName);
    await Process.run('explorer', [path]);
  }

  Future<String> exportLogs() async {
    final timestamp = DateTime.now()
        .toIso8601String()
        .replaceAll(':', '-')
        .split('.')
        .first;

    String downloadsPath;
    try {
      final result = await Process.run('powershell', [
        '-NoProfile',
        '-Command',
        '[Environment]::GetFolderPath("UserProfile")',
      ]);
      if (result.exitCode == 0) {
        downloadsPath = p.join(result.stdout.toString().trim(), 'Downloads');
      } else {
        downloadsPath = p.join(
          Platform.environment['USERPROFILE'] ?? '',
          'Downloads',
        );
      }
    } catch (_) {
      downloadsPath = p.join(
        Platform.environment['USERPROFILE'] ?? '',
        'Downloads',
      );
    }

    final downloadsDir = Directory(downloadsPath);
    if (!downloadsDir.existsSync()) {
      downloadsDir.createSync(recursive: true);
    }

    final zipPath = p.join(
      downloadsPath,
      'WinDeployStudio_Logs_$timestamp.zip',
    );

    final result = await Process.run(
      'powershell',
      [
        '-NoProfile',
        '-ExecutionPolicy',
        'Bypass',
        '-Command',
        r'''
$base = $env:WDS_LOGS_BASE
$zip = $env:WDS_LOGS_ZIP
$files = @(Get-ChildItem -LiteralPath $base -Recurse -File -ErrorAction SilentlyContinue)
if ($files.Count -gt 0) {
  Compress-Archive -Path (Join-Path $base '*') -DestinationPath $zip -Force -ErrorAction Stop
} else {
  $marker = Join-Path ([IO.Path]::GetTempPath()) ('WinDeployStudio_NoLogs_' + [Guid]::NewGuid().ToString() + '.txt')
  try {
    Set-Content -LiteralPath $marker -Value 'No log files found.' -Encoding UTF8 -ErrorAction Stop
    Compress-Archive -LiteralPath $marker -DestinationPath $zip -Force -ErrorAction Stop
  } finally {
    Remove-Item -LiteralPath $marker -Force -ErrorAction SilentlyContinue
  }
}
''',
      ],
      environment: {
        ...Platform.environment,
        'WDS_LOGS_BASE': _logsBasePath,
        'WDS_LOGS_ZIP': zipPath,
      },
    );

    if (result.exitCode != 0) {
      throw Exception('Export failed: ${result.stderr}');
    }

    await Process.run('explorer', ['/select,', zipPath]);

    return zipPath;
  }

  Future<int> clearOldLogs({
    int? daysOld,
    List<LogCategory>? categories,
  }) async {
    int deletedCount = 0;
    final cutoff = daysOld != null
        ? DateTime.now().subtract(Duration(days: daysOld))
        : null;
    final targetCategories = categories ?? LogCategory.values;

    for (final category in targetCategories) {
      final dir = Directory(p.join(_logsBasePath, category.folderName));
      if (dir.existsSync()) {
        final files = dir.listSync().whereType<File>().where(
          (f) => f.path.endsWith('.log'),
        );
        for (final file in files) {
          if (cutoff == null || file.statSync().modified.isBefore(cutoff)) {
            await file.delete();
            deletedCount++;
          }
        }
      }
    }

    return deletedCount;
  }
}
