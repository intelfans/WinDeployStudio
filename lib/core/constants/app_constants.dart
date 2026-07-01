import 'dart:io';

class AppConstants {
  AppConstants._();

  static const String appName = 'WinDeploy Studio';
  static const String appVersion = '1.1.2';
  static const String licenseName = 'MIT License';
  static const String githubRepository =
      'https://github.com/intelfans/WinDeployStudio';

  // Download
  static const int maxConcurrentDownloads = 3;
  static const int downloadChunkSize = 1024 * 1024; // 1MB

  // UI
  static const double sidebarWidth = 72.0;
  static const double contentMaxWidth = 1200.0;
  static const double cardBorderRadius = 8.0;
  static const double minWindowWidth = 1280.0;
  static const double minWindowHeight = 800.0;

  // Safety
  static const String eraseConfirmation = 'ERASE';

  // Logging
  static const String logDirName = 'logs';
  static const int maxLogFiles = 30;

  static String get appDataPath {
    return Platform.environment['APPDATA'] ??
        Platform.environment['LOCALAPPDATA'] ??
        Directory.current.path;
  }

  static String get userProfilePath {
    return Platform.environment['USERPROFILE'] ?? Directory.current.path;
  }

  static String get downloadsPath {
    return '$userProfilePath\\Downloads';
  }
}
