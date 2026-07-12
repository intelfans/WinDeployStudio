import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/constants/app_constants.dart';
import '../../logs/services/log_center_service.dart';
import '../models/update_models.dart';

class UpdateService {
  static const _repoOwner = 'intelfans';
  static const _repoName = 'WinDeployStudio';
  static const _apiBaseUrl =
      'https://api.github.com/repos/$_repoOwner/$_repoName/releases';
  static const _apiUrl = '$_apiBaseUrl?per_page=100';
  static const _releasePageUrl =
      'https://github.com/$_repoOwner/$_repoName/releases';
  static const _cacheDuration = Duration(hours: 6);
  static const _maxRetries = 2;

  static const _allowedHosts = {
    'github.com',
    'objects.githubusercontent.com',
    'release-assets.githubusercontent.com',
  };
  static const _trustedPublisherCommonNames = {'intelfans', 'Bob Steve'};
  static const _prefKeyAutoCheck = 'update_auto_check';
  static const _prefKeyLastCheck = 'update_last_check';
  static const _prefKeyIgnoredVersion = 'update_ignored_version';
  static const _prefKeyChannel = 'update_channel';
  static const _prefKeyCachedInfo = 'update_cached_info';

  static UpdateService? _instance;
  UpdateService._();
  factory UpdateService() => _instance ??= UpdateService._();

  String? _lastTrustedDownloadPath;
  String? _lastPublishedDownloadHash;
  int? _lastPublishedDownloadSize;

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
    await clearCache();
  }

  AppVersion getCurrentVersion() {
    return AppVersion.parse(AppConstants.appVersion);
  }

  Future<UpdateInfo?> checkForUpdate({bool forceRefresh = false}) async {
    final log = LogCenterService();
    final current = getCurrentVersion();
    final channel = await getChannel();

    log.logUpdate(
      '[Update] CheckStart=true\nCurrent=$current\nChannel=${channel.name}',
    );

    if (!forceRefresh) {
      final cached = await _loadCachedInfo(channel);
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

      final decoded = jsonDecode(response.body);
      if (decoded is! List) return null;
      final releases = decoded
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .where((item) => item['draft'] != true)
          .toList();
      final selected = _selectReleaseForChannel(releases, channel);
      if (selected == null) return null;
      final info = UpdateInfo.fromJson(selected);

      await _saveCachedInfo(info, channel);
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

  Future<UpdateInfo?> _loadCachedInfo(UpdateChannel channel) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final lastCheckMs = prefs.getInt(_prefKeyLastCheck);
      if (lastCheckMs == null) return null;

      final elapsed = DateTime.now().millisecondsSinceEpoch - lastCheckMs;
      if (elapsed > _cacheDuration.inMilliseconds) return null;

      final cachedJson = prefs.getString(_prefKeyCachedInfo);
      if (cachedJson == null) return null;
      final decoded = jsonDecode(cachedJson) as Map<String, dynamic>;
      if (decoded['_channel'] != channel.name) return null;
      return UpdateInfo.fromJson(decoded);
    } catch (_) {
      return null;
    }
  }

  Future<void> _saveCachedInfo(UpdateInfo info, UpdateChannel channel) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _prefKeyCachedInfo,
      jsonEncode({
        '_channel': channel.name,
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
                'digest': a.digest,
              },
            )
            .toList(),
      }),
    );
  }

  Map<String, dynamic>? _selectReleaseForChannel(
    List<Map<String, dynamic>> releases,
    UpdateChannel channel,
  ) {
    final candidates = releases.where((release) {
      if (!_releaseAllowedForChannel(release, channel)) return false;
      try {
        final asset = UpdateInfo.fromJson(release).bestAsset;
        return asset != null && asset.sizeBytes > 0 && asset.sha256 != null;
      } catch (_) {
        return false;
      }
    }).toList();

    candidates.sort((left, right) {
      final leftInfo = UpdateInfo.fromJson(left);
      final rightInfo = UpdateInfo.fromJson(right);
      final versionComparison = rightInfo.version.compareTo(leftInfo.version);
      if (versionComparison != 0) return versionComparison;
      return rightInfo.publishedAt.compareTo(leftInfo.publishedAt);
    });
    return candidates.firstOrNull;
  }

  bool _releaseAllowedForChannel(
    Map<String, dynamic> release,
    UpdateChannel channel,
  ) {
    final text = '${release['tag_name']} ${release['name']}'.toLowerCase();
    final isNightly = RegExp(
      r'(?:^|[^a-z0-9])(nightly|daily|dev|canary)(?:[^a-z0-9]|$)',
    ).hasMatch(text);
    return switch (channel) {
      UpdateChannel.stable => release['prerelease'] != true && !isNightly,
      UpdateChannel.beta => !isNightly,
      UpdateChannel.nightly => true,
    };
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
    _lastTrustedDownloadPath = null;
    _lastPublishedDownloadHash = null;
    _lastPublishedDownloadSize = null;

    final freshRelease = await _fetchReleaseByTag(info.tagName);
    final channel = await getChannel();
    if (freshRelease == null ||
        !_releaseAllowedForChannel(freshRelease, channel)) {
      LogCenterService().logUpdate(
        '[Download] State=Failed\nReason=Release metadata unavailable',
      );
      return null;
    }

    final freshInfo = UpdateInfo.fromJson(freshRelease);
    final asset = freshInfo.bestAsset;
    if (asset == null) {
      LogCenterService().logUpdate(
        '[Download] State=Failed\nReason=No asset found',
      );
      return null;
    }

    final publishedHash = asset.sha256;
    if (asset.sizeBytes <= 0 || publishedHash == null) {
      LogCenterService().logUpdate(
        '[Download] State=Failed\nReason=Missing trusted release digest',
      );
      return null;
    }

    final downloadUrl = freshInfo.generateDownloadUrl();
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
        _lastPublishedDownloadHash = publishedHash;
        _lastPublishedDownloadSize = asset.sizeBytes;
        log.logUpdate(
          '[Download] State=Stable\nPath=$result\nTrust=GitHubReleaseDigest',
        );
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

  Future<Map<String, dynamic>?> _fetchReleaseByTag(String tagName) async {
    try {
      final response = await http
          .get(
            Uri.parse('$_apiBaseUrl/tags/${Uri.encodeComponent(tagName)}'),
            headers: {
              'Accept': 'application/vnd.github+json',
              'User-Agent': 'WinDeployStudio/${AppConstants.appVersion}',
            },
          )
          .timeout(const Duration(seconds: 15));
      if (response.statusCode != 200) return null;
      final decoded = jsonDecode(response.body);
      if (decoded is! Map) return null;
      final release = Map<String, dynamic>.from(decoded);
      if (release['draft'] == true || release['tag_name'] != tagName) {
        return null;
      }
      return release;
    } catch (_) {
      return null;
    }
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
    File? file;
    IOSink? sink;
    final client = http.Client();
    var completed = false;
    cancelToken.client = client;
    try {
      final tempDir = await getTemporaryDirectory();
      final updateDir = Directory('${tempDir.path}\\WinDeployStudio\\update');
      if (!await updateDir.exists()) {
        await updateDir.create(recursive: true);
      }

      final safeAssetName = _sanitizeAssetName(asset.name);
      final filePath = p.join(updateDir.path, safeAssetName);
      file = File(filePath);

      final response = await _sendAllowedGet(client, url);

      if (response == null || response.statusCode != 200) {
        return null;
      }

      final expectedHash = asset.sha256;
      final responseLength = response.contentLength;
      if (expectedHash == null ||
          asset.sizeBytes <= 0 ||
          (responseLength != null && responseLength != asset.sizeBytes)) {
        return null;
      }

      sink = file.openWrite();

      final totalBytes = asset.sizeBytes;
      int downloadedBytes = 0;
      int lastReportedBytes = 0;
      final stopwatch = Stopwatch()..start();
      final speedStopwatch = Stopwatch()..start();
      DownloadPhase currentPhase = DownloadPhase.connecting;

      await for (final chunk in response.stream.timeout(
        const Duration(seconds: 60),
      )) {
        if (cancelToken.cancelled) {
          return null;
        }

        if (downloadedBytes + chunk.length > totalBytes) {
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

      await sink.flush();
      await sink.close();
      sink = null;
      stopwatch.stop();

      final finalLength = await file.length();
      if (totalBytes <= 0 ||
          finalLength != totalBytes ||
          (asset.sizeBytes > 0 && finalLength != asset.sizeBytes)) {
        return null;
      }

      final actualHash = await _sha256File(file);
      if (actualHash != expectedHash) {
        LogCenterService().logUpdate(
          '[Download] State=Failed\nReason=Published digest mismatch',
        );
        return null;
      }

      completed = true;
      return filePath;
    } catch (_) {
      return null;
    } finally {
      try {
        await sink?.close();
      } catch (_) {}
      client.close();
      if (identical(cancelToken.client, client)) {
        cancelToken.client = null;
      }
      if (!completed && file != null) {
        try {
          if (await file.exists()) await file.delete();
        } catch (_) {}
      }
    }
  }

  Future<http.StreamedResponse?> _sendAllowedGet(
    http.Client client,
    String url,
  ) async {
    var current = Uri.parse(url);
    for (var redirect = 0; redirect <= 5; redirect++) {
      if (!isUrlAllowed(current.toString())) return null;
      final request = http.Request('GET', current)
        ..followRedirects = false
        ..headers['User-Agent'] = 'WinDeployStudio/${AppConstants.appVersion}'
        ..headers['Accept-Encoding'] = 'identity';
      final response = await client
          .send(request)
          .timeout(const Duration(seconds: 30));
      if (!response.isRedirect) return response;
      final location = response.headers['location'];
      await response.stream.drain<void>();
      if (location == null || location.isEmpty) return null;
      current = current.resolve(location);
    }
    return null;
  }

  String _sanitizeAssetName(String name) {
    final base = p
        .basename(name)
        .replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1F]'), '_');
    return base.isEmpty ? 'WinDeployStudio-Update.exe' : base;
  }

  Future<String> _sha256File(File file) async {
    final digest = await sha256.bind(file.openRead()).first;
    return digest.toString().toUpperCase();
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
        if (!_isLastTrustedDownload(file.absolute.path) ||
            _lastPublishedDownloadHash == null ||
            _lastPublishedDownloadSize == null ||
            await file.length() != _lastPublishedDownloadSize ||
            await _sha256File(file) != _lastPublishedDownloadHash) {
          log.logUpdate(
            '[Update] InstallFail: Published digest verification failed',
          );
          return false;
        }

        final signature = await _verifyInstallerSignature(filePath);
        if (!signature.valid ||
            signature.status != 'Valid' ||
            signature.thumbprint.isEmpty ||
            signature.subjectCommonName != signature.publisherCommonName ||
            !_isTrustedPublisher(signature.publisherCommonName)) {
          log.logUpdate(
            '[Update] InstallFail: Authenticode verification failed\n'
            'Status=${signature.status}\n'
            'Publisher=${signature.publisherCommonName}\n'
            'SubjectCN=${signature.subjectCommonName}\n'
            'Subject=${signature.subject}\n'
            'Thumbprint=${signature.thumbprint}\n'
            'Error=${signature.error}',
          );
          return false;
        }

        log.logUpdate(
          '[Update] InstallerTrust\n'
          'ReleaseDigest=Valid\n'
          'Authenticode=Valid\n'
          'Publisher=${signature.publisherCommonName}\n'
          'SubjectCN=${signature.subjectCommonName}\n'
          'Subject=${signature.subject}\n'
          'Thumbprint=${signature.thumbprint}',
        );

        try {
          await Process.start(filePath, [
            '/silent',
            '/CLOSEAPPLICATIONS',
            '/RESTARTAPPLICATIONS',
          ], mode: ProcessStartMode.detached);
          log.logUpdate('[Update] Started with /silent');
          Timer(const Duration(milliseconds: 800), () => exit(0));
          return true;
        } catch (_) {
          log.logUpdate('[Update] Silent failed, trying normal');
          await Process.start(filePath, [], mode: ProcessStartMode.detached);
          log.logUpdate('[Update] Started in normal mode');
          Timer(const Duration(milliseconds: 800), () => exit(0));
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

  bool _isTrustedPublisher(String commonName) {
    final normalized = commonName.trim().toLowerCase();
    return _trustedPublisherCommonNames.any(
      (allowed) => allowed.toLowerCase() == normalized,
    );
  }

  Future<_SignatureCheck> _verifyInstallerSignature(String filePath) async {
    final quotedPath = _psQuote(filePath);
    final script =
        '''
\$signature = Get-AuthenticodeSignature -LiteralPath $quotedPath
\$certificate = \$signature.SignerCertificate
[PSCustomObject]@{
  Status = \$signature.Status.ToString()
  Subject = if (\$null -ne \$certificate) { \$certificate.Subject } else { '' }
  Publisher = if (\$null -ne \$certificate) {
    \$certificate.GetNameInfo(
      [System.Security.Cryptography.X509Certificates.X509NameType]::SimpleName,
      \$false
    )
  } else { '' }
  Thumbprint = if (\$null -ne \$certificate) { \$certificate.Thumbprint } else { '' }
  Error = if (\$signature.StatusMessage) { \$signature.StatusMessage } else { '' }
} | ConvertTo-Json -Compress
''';

    Object? lastError;
    for (final executable in const ['pwsh.exe', 'powershell.exe']) {
      try {
        final result = await Process.run(executable, [
          '-NoLogo',
          '-NoProfile',
          '-NonInteractive',
          '-Command',
          script,
        ]).timeout(const Duration(seconds: 20));
        if (result.exitCode != 0) {
          lastError = result.stderr.toString().trim();
          continue;
        }

        final decoded = jsonDecode(result.stdout.toString());
        if (decoded is! Map) {
          lastError = 'Invalid PowerShell signature response';
          continue;
        }
        final data = Map<String, dynamic>.from(decoded);
        final status = data['Status']?.toString() ?? '';
        final subject = data['Subject']?.toString() ?? '';
        final publisher = data['Publisher']?.toString() ?? '';
        final thumbprint = data['Thumbprint']?.toString() ?? '';
        final error = data['Error']?.toString() ?? '';
        final subjectCommonName = _extractSubjectCommonName(subject);
        return _SignatureCheck(
          valid:
              status == 'Valid' &&
              subject.isNotEmpty &&
              publisher.isNotEmpty &&
              thumbprint.isNotEmpty &&
              subjectCommonName == publisher,
          status: status,
          subject: subject,
          subjectCommonName: subjectCommonName,
          publisherCommonName: publisher,
          thumbprint: thumbprint,
          error: error,
        );
      } catch (error) {
        lastError = error;
      }
    }

    return _SignatureCheck(
      valid: false,
      status: 'VerificationFailed',
      subject: '',
      subjectCommonName: '',
      publisherCommonName: '',
      thumbprint: '',
      error: lastError?.toString() ?? 'No PowerShell runtime available',
    );
  }

  String _psQuote(String value) => "'${value.replaceAll("'", "''")}'";

  String _extractSubjectCommonName(String subject) {
    final match = RegExp(
      r'(?:^|,\s*)CN\s*=\s*(?:"([^"]+)"|([^,]+))',
      caseSensitive: false,
    ).firstMatch(subject);
    return (match?.group(1) ?? match?.group(2) ?? '').trim();
  }

  Future<void> clearCache() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefKeyCachedInfo);
    await prefs.remove(_prefKeyLastCheck);
  }
}

class _SignatureCheck {
  final bool valid;
  final String status;
  final String subject;
  final String subjectCommonName;
  final String publisherCommonName;
  final String thumbprint;
  final String error;

  const _SignatureCheck({
    required this.valid,
    required this.status,
    required this.subject,
    required this.subjectCommonName,
    required this.publisherCommonName,
    required this.thumbprint,
    required this.error,
  });
}

class CancelToken {
  bool cancelled = false;
  http.Client? client;

  void cancel() {
    cancelled = true;
    client?.close();
  }
}
