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
      'https://github.com/$_repoOwner/$_repoName/releases/latest';
  static const _cacheDuration = Duration(hours: 6);
  static const _maxRetries = 2;

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

  String? _lastTrustedDownloadPath;

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
    await prefs.setInt(
      _prefKeyLastCheck,
      DateTime.now().millisecondsSinceEpoch,
    );
  }

  Future<UpdateChannel> getChannel() async {
    final prefs = await SharedPreferences.getInstance();
    final index = prefs.getInt(_prefKeyChannel) ?? 0;
    if (index < 0 || index >= UpdateChannel.values.length) {
      return UpdateChannel.stable;
    }
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
    final current = getCurrentVersion();

    log.logUpdate('[Update] CheckStart=true\nCurrent=$current');

    if (!forceRefresh) {
      final cached = await _loadCachedInfo();
      if (cached != null) {
        final hasUpdate = cached.version > current;
        log.logUpdate(
          '[Update] Using cached\n'
          'Latest=${cached.version}\n'
          'CompareResult=$hasUpdate',
        );
        return cached;
      }
    }

    try {
      final response = await http
          .get(
            Uri.parse(_apiUrl),
            headers: {
              'Accept': 'application/vnd.github.v3+json',
              'User-Agent': 'WinDeployStudio/${AppConstants.appVersion}',
            },
          )
          .timeout(const Duration(seconds: 15));

      if (response.statusCode != 200) {
        log.logUpdate('[Update] API failed: ${response.statusCode}');
        return null;
      }

      final json = jsonDecode(response.body) as Map<String, dynamic>;
      final info = UpdateInfo.fromJson(json);

      await _saveCachedInfo(info);
      await _saveLastCheckTime();

      final hasUpdate = info.version > current;
      log.logUpdate(
        '[Update] LatestVersion=${info.version}\n'
        'CompareResult=$hasUpdate',
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

      return UpdateInfo.fromJson(
        jsonDecode(cachedJson) as Map<String, dynamic>,
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> _saveCachedInfo(UpdateInfo info) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _prefKeyCachedInfo,
      jsonEncode({
        'tag_name': info.tagName,
        'name': info.name,
        'body': info.body,
        'published_at': info.publishedAt.toIso8601String(),
        'assets': info.assets
            .map(
              (a) => {
                'name': a.name,
                'browser_download_url': a.url,
                'size': a.sizeBytes,
                'content_type': a.contentType,
              },
            )
            .toList(),
      }),
    );
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
      return uri.scheme == 'https' && _allowedHosts.contains(uri.host);
    } catch (_) {
      return false;
    }
  }

  Future<String?> downloadUpdate(
    UpdateInfo info,
    void Function(
      double progress,
      String speed,
      String remaining,
      DownloadPhase phase,
    )
    onProgress,
    CancelToken cancelToken,
  ) async {
    final asset = info.bestAsset;
    if (asset == null) {
      LogCenterService().logUpdate(
        '[Download] State=Failed\nReason=No asset found',
      );
      return null;
    }

    final downloadUrl = info.generateDownloadUrl();
    if (!isUrlAllowed(downloadUrl)) {
      LogCenterService().logUpdate(
        '[Download] State=Failed\nReason=Blocked URL',
      );
      return null;
    }

    final log = LogCenterService();
    log.logUpdate(
      '[Download] State=Connecting\n'
      'Asset=${asset.name}\n'
      'Size=${asset.formattedSize}\n'
      'CDN=GitHub',
    );

    onProgress(0.0, '0 KB/s', '--', DownloadPhase.connecting);

    for (int attempt = 0; attempt <= _maxRetries; attempt++) {
      if (attempt > 0) {
        log.logUpdate('[Download] State=Retrying\nAttempt=$attempt');
        onProgress(0.0, '0 KB/s', '--', DownloadPhase.retrying);
        await Future.delayed(Duration(seconds: attempt * 2));
      }

      final result = await _doDownload(downloadUrl, asset, (
        progress,
        speed,
        remaining,
        phase,
      ) {
        log.logUpdate('[Download] State=$phase\nSpeed=$speed');
        onProgress(progress, speed, remaining, phase);
      }, cancelToken);

      if (result != null) {
        _lastTrustedDownloadPath = result;
        log.logUpdate('[Download] State=Stable\nPath=$result');
        return result;
      }

      if (cancelToken.cancelled) {
        log.logUpdate('[Download] State=Failed\nReason=Cancelled');
        return null;
      }
    }

    log.logUpdate('[Download] State=Failed\nReason=Max retries exceeded');
    return null;
  }

  Future<String?> _doDownload(
    String url,
    UpdateAsset asset,
    void Function(
      double progress,
      String speed,
      String remaining,
      DownloadPhase phase,
    )
    onProgress,
    CancelToken cancelToken,
  ) async {
    try {
      final tempDir = await getTemporaryDirectory();
      final updateDir = Directory('${tempDir.path}\\WinDeployStudio\\update');
      if (!await updateDir.exists()) {
        await updateDir.create(recursive: true);
      }

      final filePath = '${updateDir.path}\\${asset.name}';
      final file = File(filePath);
      final sink = file.openWrite();

      final client = http.Client();
      cancelToken.client = client;

      final request = http.Request('GET', Uri.parse(url));
      request.headers['User-Agent'] =
          'WinDeployStudio/${AppConstants.appVersion}';

      final response = await client.send(request);

      if (response.statusCode != 200) {
        await sink.close();
        client.close();
        return null;
      }

      final totalBytes = (response.contentLength ?? 0) > 0
          ? response.contentLength!
          : asset.sizeBytes;
      int downloadedBytes = 0;
      int lastReportedBytes = 0;
      final stopwatch = Stopwatch()..start();
      final speedStopwatch = Stopwatch()..start();
      DownloadPhase currentPhase = DownloadPhase.connecting;

      await for (final chunk in response.stream) {
        if (cancelToken.cancelled) {
          await sink.close();
          client.close();
          return null;
        }

        sink.add(chunk);
        downloadedBytes += chunk.length;

        if (totalBytes > 0) {
          final progress = downloadedBytes / totalBytes;
          final elapsed = stopwatch.elapsedMilliseconds;

          if (downloadedBytes - lastReportedBytes > 65536 ||
              speedStopwatch.elapsedMilliseconds > 500) {
            final speed = elapsed > 0
                ? downloadedBytes * 1000.0 / elapsed
                : 0.0;

            DownloadPhase newPhase;
            if (elapsed < 5000) {
              newPhase = DownloadPhase.connecting;
            } else if (speed < 512000) {
              newPhase = DownloadPhase.optimizing;
            } else {
              newPhase = DownloadPhase.stable;
            }

            if (newPhase != currentPhase) {
              currentPhase = newPhase;
            }

            String remaining = '--';
            if (speed > 0 && totalBytes > downloadedBytes) {
              final remainingBytes = totalBytes - downloadedBytes;
              final remainingSec = remainingBytes / speed;
              if (remainingSec < 60) {
                remaining = '${remainingSec.ceil()}s';
              } else if (remainingSec < 3600) {
                remaining = '${(remainingSec / 60).ceil()}m';
              } else {
                remaining = '${(remainingSec / 3600).ceil()}h';
              }
            }

            onProgress(progress, _formatSpeed(speed), remaining, currentPhase);
            lastReportedBytes = downloadedBytes;
            speedStopwatch.reset();
          }
        }
      }

      await sink.close();
      client.close();
      stopwatch.stop();

      return filePath;
    } catch (e) {
      return null;
    }
  }

  String _formatSpeed(double bytesPerSecond) {
    if (bytesPerSecond < 1024) {
      return '${bytesPerSecond.toStringAsFixed(0)} B/s';
    }
    if (bytesPerSecond < 1024 * 1024) {
      return '${(bytesPerSecond / 1024).toStringAsFixed(1)} KB/s';
    }
    return '${(bytesPerSecond / (1024 * 1024)).toStringAsFixed(1)} MB/s';
  }

  Future<bool> installUpdate(String filePath) async {
    final log = LogCenterService();
    log.logUpdate('[Update] InstallStart\nPath=$filePath');

    try {
      final file = File(filePath);
      if (!await file.exists()) {
        log.logUpdate('[Update] InstallFail: File not found');
        return false;
      }

      final isExe = filePath.toLowerCase().endsWith('.exe');

      if (isExe) {
        final signature = await _verifyInstallerSignature(filePath);
        final unsignedAllowed =
            signature.status == 'NotSigned' &&
            _isLastTrustedDownload(file.absolute.path);
        if (!signature.valid && !unsignedAllowed) {
          log.logUpdate(
            '[Update] InstallFail: Signature invalid\n'
            'Status=${signature.status}\n'
            'Subject=${signature.subject}',
          );
          return false;
        }

        log.logUpdate(
          '[Update] InstallerSignature\n'
          'Valid=${signature.valid}\n'
          'Status=${signature.status}\n'
          'Subject=${signature.subject}\n'
          'UnsignedAllowed=$unsignedAllowed',
        );

        try {
          await Process.start(filePath, [
            '/silent',
          ], mode: ProcessStartMode.detached);
          log.logUpdate('[Update] Started with /silent');
          return true;
        } catch (_) {
          log.logUpdate('[Update] Silent failed, trying normal');
          await Process.start(filePath, [], mode: ProcessStartMode.detached);
          log.logUpdate('[Update] Started in normal mode');
          return true;
        }
      } else {
        log.logUpdate('[Update] Non-exe, manual install required');
        return false;
      }
    } catch (e) {
      log.logUpdate('[Update] Install error: $e');
      return false;
    }
  }

  bool _isLastTrustedDownload(String filePath) {
    if (_lastTrustedDownloadPath == null) return false;
    return File(_lastTrustedDownloadPath!).absolute.path.toLowerCase() ==
        filePath.toLowerCase();
  }

  Future<_SignatureCheck> _verifyInstallerSignature(String filePath) async {
    try {
      final quotedPath = _psQuote(filePath);
      final result = await Process.run('powershell', [
        '-NoProfile',
        '-ExecutionPolicy',
        'Bypass',
        '-Command',
        '''
        \$sig = Get-AuthenticodeSignature -LiteralPath $quotedPath
        [PSCustomObject]@{
          Status = \$sig.Status.ToString()
          Subject = if (\$sig.SignerCertificate) { \$sig.SignerCertificate.Subject } else { '' }
        } | ConvertTo-Json -Compress
        ''',
      ]).timeout(const Duration(seconds: 15));

      if (result.exitCode != 0) {
        return _SignatureCheck(
          false,
          'PowerShellFailed',
          result.stderr.toString(),
        );
      }

      final data = jsonDecode(result.stdout.toString()) as Map<String, dynamic>;
      final status = data['Status']?.toString() ?? '';
      final subject = data['Subject']?.toString() ?? '';
      return _SignatureCheck(status == 'Valid', status, subject);
    } catch (e) {
      return _SignatureCheck(false, 'Exception', e.toString());
    }
  }

  String _psQuote(String value) => "'${value.replaceAll("'", "''")}'";

  void clearCache() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefKeyCachedInfo);
    await prefs.remove(_prefKeyLastCheck);
  }
}

class _SignatureCheck {
  final bool valid;
  final String status;
  final String subject;

  const _SignatureCheck(this.valid, this.status, this.subject);
}

class CancelToken {
  bool cancelled = false;
  http.Client? client;

  void cancel() {
    cancelled = true;
    client?.close();
  }
}
