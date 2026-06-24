import 'package:flutter/material.dart';

enum LogCategory {
  usb('logs_cat_usb', 'usb', Icons.usb_rounded, Color(0xFF0071C5)),
  wtg('logs_cat_wtg', 'wtg', Icons.computer_rounded, Color(0xFF7B61FF)),
  downloads('logs_cat_downloads', 'downloads', Icons.download_rounded, Color(0xFF00A4EF)),
  iso('logs_cat_iso', 'iso', Icons.folder_rounded, Color(0xFFFF8C00)),
  system('logs_cat_system', 'system', Icons.settings_rounded, Color(0xFF107C10)),
  errors('logs_cat_errors', 'errors', Icons.error_rounded, Color(0xFFE81123)),
  update('logs_cat_update', 'update', Icons.system_update_rounded, Color(0xFF00B7C3));

  final String nameKey;
  final String folderName;
  final IconData icon;
  final Color color;

  const LogCategory(this.nameKey, this.folderName, this.icon, this.color);
}

class LogFileInfo {
  final String path;
  final String name;
  final int sizeBytes;
  final DateTime lastModified;

  LogFileInfo({
    required this.path,
    required this.name,
    required this.sizeBytes,
    required this.lastModified,
  });
}

class LogStats {
  final int totalFiles;
  final int totalSizeBytes;
  final DateTime? lastActivity;
  final Map<LogCategory, int> categoryCounts;

  LogStats({
    required this.totalFiles,
    required this.totalSizeBytes,
    this.lastActivity,
    required this.categoryCounts,
  });

  String get formattedSize {
    if (totalSizeBytes < 1024) return '$totalSizeBytes B';
    if (totalSizeBytes < 1024 * 1024) {
      return '${(totalSizeBytes / 1024).toStringAsFixed(1)} KB';
    }
    return '${(totalSizeBytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  String lastActivityFormatted(String Function(String) tr) {
    if (lastActivity == null) return tr('logs_never');
    final diff = DateTime.now().difference(lastActivity!);
    if (diff.inMinutes < 1) return tr('logs_just_now');
    if (diff.inMinutes < 60) return tr('logs_min_ago').replaceAll('{n}', '${diff.inMinutes}');
    if (diff.inHours < 24) return tr('logs_hours_ago').replaceAll('{n}', '${diff.inHours}');
    return tr('logs_days_ago').replaceAll('{n}', '${diff.inDays}');
  }
}

class LogActivity {
  final LogCategory category;
  final String title;
  final DateTime timestamp;

  LogActivity({
    required this.category,
    required this.title,
    required this.timestamp,
  });

  String get timeFormatted {
    return '${timestamp.hour.toString().padLeft(2, '0')}:${timestamp.minute.toString().padLeft(2, '0')}';
  }
}
