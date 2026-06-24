import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/constants/app_constants.dart';
import '../../logs/services/log_center_service.dart';
import '../models/update_models.dart';

class UpdateService {
  static const _repoOwner = 'intelfans';
  static const _repoName = 'WinDeployStudio';
  static const _apiUrl =
      'https://api.github.com/repos/$_repoOwner/$_repoName/releases/latest';
  static const _releasePageUrl =
      'https://github.com/$_repoOwner/$_repoName/releases';
  static const _cacheDuration = Duration(hours: 6);

  static const _allowedHosts = {
    'github.com',
    'objects.githubusercontent.com',
    'release-assets.githubusercontent.com',
  };

  static const _prefKeyAutoCheck = 'update_auto_check';
  static const _prefKeyLastCheck = 'update_last_check';
  static const _prefKeyIgnoredVersion = 'update_ignored_version';
  static const _prefKeyChannel = 'update_channel';
  static const _prefKeyCachedInfo = 'update_cached_info';

  static UpdateService? _instance;
  UpdateService._();
  factory UpdateService() => _instance ??= UpdateService._();

  String get releasePageUrl => _releasePageUrl;

  Future<bool> getAutoCheckEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_prefKeyAutoCheck) ?? true;
  }

  Future<void> setAutoCheckEnabled(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefKeyAutoCheck, value);
  }

  Future<String?> getIgnoredVersion() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_prefKeyIgnoredVersion);
  }

  Future<void> setIgnoredVersion(String? version) async {
    final prefs = await SharedPreferences.getInstance();
    if (version == null) {
      await prefs.remove(_prefKeyIgnoredVersion);
    } else {
      await prefs.setString(_prefKeyIgnoredVersion, version);
    }
  }

  Future<DateTime?> getLastCheckTime() async {
    final prefs = await SharedPreferences.getInstance();
    final ms = prefs.getInt(_prefKeyLastCheck);
    return ms != null ? DateTime.fromMillisecondsSinceEpoch(ms) : null;
  }

  Future<void> _saveLastCheckTime() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_prefKeyLastCheck, DateTime.now().millisecondsSinceEpoch);
  }

  Future<UpdateChannel> getChannel() async {
    final prefs = await SharedPreferences.getInstance();
    final index = prefs.getInt(_prefKeyChannel) ?? 0;
    return UpdateChannel.values[index];
  }

  Future<void> setChannel(UpdateChannel channel) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_prefKeyChannel, channel.index);
  }

  AppVersion getCurrentVersion() {
    return AppVersion.parse(AppConstants.appVersion);
  }

  Future<UpdateInfo?> checkForUpdate({bool forceRefresh = false}) async {
    final log = LogCenterService();

    log.logUpdate(
      '[Update] Checking for updates...\n'
      'Current=${getCurrentVersion()}',
    );

    if (!forceRefresh) {
      final cached = await _loadCachedInfo();
      if (cached != null) {
        log.logUpdate(
          '[Update] Using cached info\n'
          'Latest=${cached.version}',
        );
        return cached;
      }
    }

    try {
      final response = await http.get(
        Uri.parse(_apiUrl),
        headers: {
          'Accept': 'application/vnd.github.v3+json',
          'User-Agent': 'WinDeployStudio/${AppConstants.appVersion}',
        },
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode != 200) {
        log.logUpdate(
          '[Update] API request failed\n'
          'StatusCode=${response.statusCode}',
        );
        return null;
      }

      final json = jsonDecode(response.body) as Map<String, dynamic>;
      final info = UpdateInfo.fromJson(json);

      await _saveCachedInfo(info);
      await _saveLastCheckTime();

      log.logUpdate(
        '[Update] Check complete\n'
        'Current=${getCurrentVersion()}\n'
        'Latest=${info.version}',
      );

      return info;
    } catch (e) {
      log.logUpdate('[Update] Check failed: $e');
      return null;
    }
  }

  Future<UpdateInfo?> _loadCachedInfo() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final lastCheckMs = prefs.getInt(_prefKeyLastCheck);
      if (lastCheckMs == null) return null;

      final elapsed = DateTime.now().millisecondsSinceEpoch - lastCheckMs;
      if (elapsed > _cacheDuration.inMilliseconds) return null;

      final cachedJson = prefs.getString(_prefKeyCachedInfo);
      if (cachedJson == null) return null;

      return UpdateInfo.fromJson(jsonDecode(cachedJson) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  Future<void> _saveCachedInfo(UpdateInfo info) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefKeyCachedInfo, jsonEncode({
      'tag_name': info.tagName,
      'name': info.name,
      'body': info.body,
      'published_at': info.publishedAt.toIso8601String(),
      'assets': info.assets.map((a) => {
        'name': a.name,
        'browser_download_url': a.url,
        'size': a.sizeBytes,
        'content_type': a.contentType,
      }).toList(),
    }));
  }

  bool isUpdateAvailable(UpdateInfo? info) {
    if (info == null) return false;
    final current = getCurrentVersion();
    return info.version > current;
  }

  Future<bool> isIgnored(UpdateInfo info) async {
    final ignored = await getIgnoredVersion();
    return ignored != null && ignored == info.tagName;
  }

  bool isUrlAllowed(String url) {
    try {
      final uri = Uri.parse(url);
      return _allowedHosts.contains(uri.host);
    } catch (_) {
      return false;
    }
  }

  Future<String?> downloadUpdate(
    UpdateInfo info,
    void Function(double progress, String speed) onProgress,
    CancelToken cancelToken,
  ) async {
    final asset = info.bestAsset;
    if (asset == null) {
      LogCenterService().logUpdate('[Update] No suitable asset found');
      return null;
    }

    if (!isUrlAllowed(asset.url)) {
      LogCenterService().logUpdate(
        '[Update] Blocked download from untrusted host: ${Uri.parse(asset.url).host}',
      );
      return null;
    }

    final log = LogCenterService();
    log.logUpdate(
      '[Update] Downloading update\n'
      'Asset=${asset.name}\n'
      'Size=${asset.formattedSize}\n'
      'URL=${asset.url}',
    );

    try {
      final tempDir = await getTemporaryDirectory();
      final updateDir = Directory('${tempDir.path}\\WinDeployStudioUpdate');
      if (!await updateDir.exists()) {
        await updateDir.create(recursive: true);
      }

      final filePath = '${updateDir.path}\\${asset.name}';
      final file = File(filePath);
      final sink = file.openWrite();

      final request = http.Request('GET', Uri.parse(asset.url));
      request.headers['User-Agent'] = 'WinDeployStudio/${AppConstants.appVersion}';

      final client = http.Client();
      cancelToken.client = client;

      final response = await client.send(request);

      if (response.statusCode != 200) {
        await sink.close();
        client.close();
        log.logUpdate('[Update] Download failed: HTTP ${response.statusCode}');
        return null;
      }

      final totalBytes = response.contentLength ?? asset.sizeBytes;
      int downloadedBytes = 0;
      final stopwatch = Stopwatch()..start();
      final speedBuffer = <int>[];
      final timeBuffer = <DateTime>[];

      await for (final chunk in response.stream) {
        if (cancelToken.cancelled) {
          await sink.close();
          client.close();
          log.logUpdate('[Update] Download cancelled by user');
          return null;
        }

        sink.add(chunk);
        downloadedBytes += chunk.length;

        speedBuffer.add(downloadedBytes);
        timeBuffer.add(DateTime.now());

        while (timeBuffer.length > 1 &&
            DateTime.now().difference(timeBuffer.first).inSeconds > 1) {
          speedBuffer.removeAt(0);
          timeBuffer.removeAt(0);
        }

        if (totalBytes > 0) {
          final progress = downloadedBytes / totalBytes;
          final elapsed = stopwatch.elapsedMilliseconds;
          final speed = elapsed > 0
              ? _formatSpeed(downloadedBytes * 1000 / elapsed)
              : '--';

          onProgress(progress, speed);
        }
      }

      await sink.close();
      client.close();
      stopwatch.stop();

      log.logUpdate(
        '[Update] Download complete\n'
        'Path=$filePath\n'
        'Size=${asset.formattedSize}',
      );

      return filePath;
    } catch (e) {
      log.logUpdate('[Update] Download error: $e');
      return null;
    }
  }

  String _formatSpeed(double bytesPerSecond) {
    if (bytesPerSecond < 1024) return '${bytesPerSecond.toStringAsFixed(0)} B/s';
    if (bytesPerSecond < 1024 * 1024) {
      return '${(bytesPerSecond / 1024).toStringAsFixed(1)} KB/s';
    }
    return '${(bytesPerSecond / (1024 * 1024)).toStringAsFixed(1)} MB/s';
  }

  Future<bool> installUpdate(String filePath) async {
    final log = LogCenterService();
    log.logUpdate('[Update] Installing update\nPath=$filePath');

    try {
      final file = File(filePath);
      if (!await file.exists()) {
        log.logUpdate('[Update] Installer file not found');
        return false;
      }

      final isExe = filePath.toLowerCase().endsWith('.exe');

      if (isExe) {
        try {
          await Process.start(filePath, ['/silent'], mode: ProcessStartMode.detached);
          log.logUpdate('[Update] Started installer with /silent');
          return true;
        } catch (_) {
          log.logUpdate('[Update] Silent install failed, trying normal mode');
          await Process.start(filePath, [], mode: ProcessStartMode.detached);
          log.logUpdate('[Update] Started installer in normal mode');
          return true;
        }
      } else {
        log.logUpdate('[Update] Non-exe download, manual installation required');
        return false;
      }
    } catch (e) {
      log.logUpdate('[Update] Install error: $e');
      return false;
    }
  }

  void clearCache() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefKeyCachedInfo);
    await prefs.remove(_prefKeyLastCheck);
  }
}

class CancelToken {
  bool cancelled = false;
  http.Client? client;

  void cancel() {
    cancelled = true;
    client?.close();
  }
}
