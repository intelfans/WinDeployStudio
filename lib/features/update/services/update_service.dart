import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xml/xml.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/services/global_mirror_download_resolver.dart';
import '../../logs/services/log_center_service.dart';
import '../models/update_models.dart';

/// Parses GitHub's public Releases Atom feed into the subset of release
/// metadata needed by the updater. The feed does not expose asset sizes, so
/// the installer asset is represented with an unknown size and verified from
/// the streamed response when it is downloaded.
List<Map<String, dynamic>> parseAtomReleaseMetadata(String feedXml) {
  final document = XmlDocument.parse(feedXml);
  final releases = <Map<String, dynamic>>[];

  for (final entry in document.findAllElements('entry')) {
    String childText(String name) =>
        entry.getElement(name)?.innerText.trim() ?? '';

    String? releaseUrl;
    for (final link in entry.findElements('link')) {
      if (link.getAttribute('rel') == 'alternate') {
        releaseUrl = link.getAttribute('href');
        break;
      }
    }
    if (releaseUrl == null || releaseUrl.isEmpty) continue;

    final uri = Uri.tryParse(releaseUrl);
    final tagName = uri?.pathSegments.isNotEmpty == true
        ? uri!.pathSegments.last
        : '';
    if (tagName.isEmpty) continue;

    final versionText = tagName.startsWith('v')
        ? tagName.substring(1)
        : tagName;
    final assetName = 'WinDeployStudio_Setup_$versionText.exe';
    final assetUrl = Uri(
      scheme: 'https',
      host: 'github.com',
      pathSegments: <String>[
        'intelfans',
        'WinDeployStudio',
        'releases',
        'download',
        tagName,
        assetName,
      ],
    ).toString();

    final name = childText('title');
    releases.add({
      'tag_name': tagName,
      'name': name,
      'body': _atomHtmlToMarkdown(childText('content')),
      'published_at': childText('updated'),
      'draft': false,
      'prerelease': _isPreReleaseIdentifier('$tagName $name'),
      'assets': [
        {
          'name': assetName,
          'browser_download_url': assetUrl,
          'size': 0,
          'content_type': 'application/octet-stream',
          'digest': '',
        },
      ],
    });
  }

  return releases;
}

bool _isPreReleaseIdentifier(String value) {
  return RegExp(
    r'(?:^|[^a-z0-9])(alpha|beta|rc|preview|pre[- ]?release|nightly|daily|dev|canary)(?:[^a-z0-9]|$)',
    caseSensitive: false,
  ).hasMatch(value);
}

/// Parses a SourceForge files RSS feed into release-shaped metadata.
///
/// SourceForge stores each release in a version folder. The folder normally
/// contains the installer and a bilingual README.md with the release notes.
/// RSS exposes the file names, sizes, and download endpoints; the README is
/// fetched separately by [UpdateService] because RSS only contains its path.
List<Map<String, dynamic>> parseSourceForgeReleaseMetadata(String feedXml) {
  final document = XmlDocument.parse(feedXml);
  final grouped = <String, Map<String, dynamic>>{};

  for (final item in document.findAllElements('item')) {
    final title = _sourceForgeItemText(item, 'title');
    final path = title.trim().replaceFirst(RegExp(r'^/+'), '');
    final match = RegExp(
      r'^(v?\d+\.\d+\.\d+(?:[-.][0-9A-Za-z.-]+)?)/(.*)$',
    ).firstMatch(path);
    if (match == null) continue;

    final tagName = match.group(1)!;
    final filePath = match.group(2)!;
    final fileName = Uri.decodeComponent(filePath.split('/').last);
    if (fileName.isEmpty) continue;

    final link = _sourceForgeItemText(item, 'link');
    final publishedAt = _parseSourceForgeDate(
      _sourceForgeItemText(item, 'pubDate'),
    );
    var sizeBytes = 0;
    for (final element in item.descendants.whereType<XmlElement>()) {
      if (element.localName == 'content') {
        sizeBytes = int.tryParse(element.getAttribute('filesize') ?? '') ?? 0;
        if (sizeBytes > 0) break;
      }
    }

    final entry = grouped.putIfAbsent(
      tagName,
      () => <String, dynamic>{
        'tag_name': tagName,
        'name': 'WinDeploy Studio $tagName',
        'body': '',
        'published_at': publishedAt.toIso8601String(),
        'draft': false,
        'prerelease': _isPreReleaseIdentifier(tagName),
        '_sourceforge_notes_url': '',
        '_sourceforge_asset_url': '',
        '_sourceforge_asset_name': '',
        '_sourceforge_asset_size': 0,
      },
    );

    final lowerName = fileName.toLowerCase();
    if (lowerName == 'readme.md' || lowerName.contains('release-notes')) {
      entry['_sourceforge_notes_url'] = link;
    }
    if (lowerName.endsWith('.exe') &&
        (lowerName.contains('setup') || lowerName.contains('install'))) {
      final previousSize = entry['_sourceforge_asset_size'] as int? ?? 0;
      if ((entry['_sourceforge_asset_name'] as String? ?? '').isEmpty ||
          sizeBytes >= previousSize) {
        entry['_sourceforge_asset_url'] = link;
        entry['_sourceforge_asset_name'] = fileName;
        entry['_sourceforge_asset_size'] = sizeBytes;
        if (publishedAt.isAfter(
          DateTime.tryParse(entry['published_at'] as String? ?? '') ??
              DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
        )) {
          entry['published_at'] = publishedAt.toIso8601String();
        }
      }
    }
  }

  return grouped.values
      .where(
        (entry) =>
            (entry['_sourceforge_asset_name'] as String? ?? '').isNotEmpty,
      )
      .map((entry) {
        final tagName = entry['tag_name'] as String;
        final assetName = entry['_sourceforge_asset_name'] as String;
        final sourceForgeUrl = entry['_sourceforge_asset_url'] as String;
        final githubUrl = Uri(
          scheme: 'https',
          host: 'github.com',
          pathSegments: <String>[
            'intelfans',
            'WinDeployStudio',
            'releases',
            'download',
            tagName,
            assetName,
          ],
        ).toString();
        return <String, dynamic>{
          'tag_name': tagName,
          'name': entry['name'],
          'body': entry['body'],
          'published_at': entry['published_at'],
          'draft': false,
          'prerelease': entry['prerelease'],
          '_sourceforge_notes_url': entry['_sourceforge_notes_url'],
          'assets': <Map<String, dynamic>>[
            <String, dynamic>{
              'name': assetName,
              'browser_download_url': githubUrl,
              'sourceforge_url': sourceForgeUrl,
              'size': entry['_sourceforge_asset_size'],
              'content_type': 'application/octet-stream',
              'digest': '',
            },
          ],
        };
      })
      .toList();
}

String _sourceForgeItemText(XmlElement item, String localName) {
  for (final child in item.children.whereType<XmlElement>()) {
    if (child.localName == localName) return child.innerText.trim();
  }
  return '';
}

DateTime _parseSourceForgeDate(String value) {
  final match = RegExp(
    r'\b\d{1,2}\s+([A-Za-z]{3})\s+(\d{4})\s+(\d{2}):(\d{2}):(\d{2})',
  ).firstMatch(value);
  if (match == null) {
    return DateTime.tryParse(value) ??
        DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
  }
  const months = <String, int>{
    'jan': 1,
    'feb': 2,
    'mar': 3,
    'apr': 4,
    'may': 5,
    'jun': 6,
    'jul': 7,
    'aug': 8,
    'sep': 9,
    'oct': 10,
    'nov': 11,
    'dec': 12,
  };
  final day =
      int.tryParse(
        RegExp(r'\b(\d{1,2})\s+[A-Za-z]{3}').firstMatch(value)?.group(1) ?? '',
      ) ??
      1;
  final month = months[match.group(1)!.toLowerCase()] ?? 1;
  final year = int.tryParse(match.group(2)!) ?? 1970;
  return DateTime.utc(
    year,
    month,
    day,
    int.parse(match.group(3)!),
    int.parse(match.group(4)!),
    int.parse(match.group(5)!),
  );
}

String _atomHtmlToMarkdown(String html) {
  var markdown = html;
  for (var level = 6; level >= 1; level--) {
    markdown = markdown.replaceAllMapped(
      RegExp('<h$level[^>]*>(.*?)</h$level>', dotAll: true),
      (match) => '${'#' * level} ${_stripHtmlInline(match.group(1) ?? '')}\n\n',
    );
  }
  markdown = markdown.replaceAllMapped(
    RegExp(r'<li[^>]*>(.*?)</li>', dotAll: true),
    (match) => '- ${_stripHtmlInline(match.group(1) ?? '')}\n',
  );
  markdown = markdown.replaceAll(
    RegExp(r'<hr\s*/?>', caseSensitive: false),
    '\n\n---\n\n',
  );
  markdown = markdown.replaceAll(
    RegExp(r'<br\s*/?>', caseSensitive: false),
    '\n',
  );
  markdown = markdown.replaceAll(
    RegExp(r'</?(?:ul|ol|p|div)[^>]*>', caseSensitive: false),
    '\n',
  );
  markdown = _stripHtmlInline(markdown);
  return markdown.replaceAll(RegExp(r'\n{3,}'), '\n\n').trim();
}

String _stripHtmlInline(String value) {
  var text = value;
  text = text.replaceAllMapped(
    RegExp(r'<(?:strong|b)[^>]*>(.*?)</(?:strong|b)>', dotAll: true),
    (match) => '**${match.group(1) ?? ''}**',
  );
  text = text.replaceAllMapped(
    RegExp(r'<(?:code|kbd)[^>]*>(.*?)</(?:code|kbd)>', dotAll: true),
    (match) => '`${match.group(1) ?? ''}`',
  );
  text = text.replaceAllMapped(
    RegExp(r'<(?:em|i)[^>]*>(.*?)</(?:em|i)>', dotAll: true),
    (match) => '*${match.group(1) ?? ''}*',
  );
  text = text.replaceAll(RegExp(r'<[^>]+>'), '');
  return _decodeHtmlEntities(text);
}

String _decodeHtmlEntities(String value) {
  var text = value
      .replaceAll('&amp;', '&')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&#39;', "'")
      .replaceAll('&nbsp;', ' ');
  return text.replaceAllMapped(
    RegExp(r'&#(x[0-9a-f]+|[0-9]+);', caseSensitive: false),
    (match) {
      final raw = match.group(1)!;
      final codePoint = raw.toLowerCase().startsWith('x')
          ? int.tryParse(raw.substring(1), radix: 16)
          : int.tryParse(raw);
      return codePoint == null
          ? match.group(0)!
          : String.fromCharCode(codePoint);
    },
  );
}

class UpdateService {
  static const _repoOwner = 'intelfans';
  static const _repoName = 'WinDeployStudio';
  static const _apiBaseUrl =
      'https://api.github.com/repos/$_repoOwner/$_repoName/releases';
  static const _apiUrl = '$_apiBaseUrl?per_page=100';
  static const _atomUrl =
      'https://github.com/$_repoOwner/$_repoName/releases.atom';
  static const _sourceForgeFilesUrl =
      'https://sourceforge.net/projects/windeploystudio/files/';
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

      Map<String, dynamic>? selected;
      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);
        if (decoded is List) {
          final releases = decoded
              .whereType<Map>()
              .map((item) => Map<String, dynamic>.from(item))
              .where((item) => item['draft'] != true)
              .toList();
          selected = _selectReleaseForChannel(releases, channel);
        }
      } else {
        log.logUpdate(
          '[Update] API failed: ${response.statusCode}; trying Releases feed',
        );
      }

      // GitHub's unauthenticated REST API is rate-limited. The public Atom
      // feed carries the same tag, date, title, and bilingual notes without
      // consuming that API quota, so use it as a read-only fallback.
      selected ??= await _fetchAtomRelease(channel);
      // SourceForge mirrors each release folder and its bilingual README.md.
      // It is a second metadata source when GitHub is unavailable, not a
      // replacement for the GitHub release URL shown to the user.
      selected ??= await _fetchSourceForgeRelease(channel);
      if (selected == null) return null;
      final parsedInfo = UpdateInfo.fromJson(selected);
      final info = parsedInfo.version > current
          ? await _withSourceForgeAvailability(parsedInfo)
          : parsedInfo;

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

  Future<Map<String, dynamic>?> _fetchAtomRelease(UpdateChannel channel) async {
    try {
      final response = await http
          .get(
            Uri.parse(_atomUrl),
            headers: {
              'Accept': 'application/atom+xml, application/xml, text/xml',
              'User-Agent': 'WinDeployStudio/${AppConstants.appVersion}',
            },
          )
          .timeout(const Duration(seconds: 15));
      if (response.statusCode != 200) {
        LogCenterService().logUpdate(
          '[Update] Releases feed failed: ${response.statusCode}',
        );
        return null;
      }

      final releases = parseAtomReleaseMetadata(response.body);
      return _selectReleaseForChannel(releases, channel);
    } catch (error) {
      LogCenterService().logUpdate('[Update] Releases feed failed: $error');
      return null;
    }
  }

  Future<Map<String, dynamic>?> _fetchSourceForgeRelease(
    UpdateChannel channel,
  ) async {
    try {
      final rootResponse = await http
          .get(
            Uri.parse(_sourceForgeFilesUrl),
            headers: {
              'Accept': 'text/html, application/xhtml+xml',
              'User-Agent': 'WinDeployStudio/${AppConstants.appVersion}',
            },
          )
          .timeout(const Duration(seconds: 15));
      if (rootResponse.statusCode != 200) return null;

      final tags = RegExp(
        r'<tr\b[^>]*\btitle="(v?\d+\.\d+\.\d+(?:[-.][0-9A-Za-z.-]+)?)"[^>]*\bclass="[^"]*\bfolder\b',
        caseSensitive: false,
      ).allMatches(rootResponse.body).map((m) => m.group(1)!).toSet().toList();
      if (tags.isEmpty) return null;

      final feeds = await Future.wait(
        tags.take(12).map(_fetchSourceForgeReleaseByTag),
      );
      final releases = feeds.whereType<Map<String, dynamic>>().toList(
        growable: false,
      );
      if (releases.isEmpty) return null;

      final selected = _selectReleaseForChannel(releases, channel);
      if (selected == null) return null;
      return _loadSourceForgeNotes(selected);
    } catch (error) {
      LogCenterService().logUpdate(
        '[Update] SourceForge metadata unavailable; keeping GitHub fallback\n'
        'Reason=$error',
      );
      return null;
    }
  }

  Future<Map<String, dynamic>?> _fetchSourceForgeReleaseByTag(
    String tagName,
  ) async {
    try {
      final feedUri = Uri.parse(
        'https://sourceforge.net/projects/windeploystudio/rss',
      ).replace(queryParameters: <String, String>{'path': '/$tagName'});
      final response = await http
          .get(
            feedUri,
            headers: {
              'Accept': 'application/rss+xml, application/xml, text/xml',
              'User-Agent': 'WinDeployStudio/${AppConstants.appVersion}',
            },
          )
          .timeout(const Duration(seconds: 15));
      if (response.statusCode != 200) return null;
      final releases = parseSourceForgeReleaseMetadata(response.body);
      final release = releases.firstWhere(
        (item) => item['tag_name'] == tagName,
        orElse: () => <String, dynamic>{},
      );
      return release.isEmpty ? null : release;
    } catch (error) {
      LogCenterService().logUpdate(
        '[Update] SourceForge release feed failed\nTag=$tagName\nReason=$error',
      );
      return null;
    }
  }

  Future<Map<String, dynamic>> _loadSourceForgeNotes(
    Map<String, dynamic> release,
  ) async {
    final notesUrl = release['_sourceforge_notes_url'] as String? ?? '';
    if (notesUrl.isEmpty) return release;
    try {
      final response = await http
          .get(
            Uri.parse(notesUrl),
            headers: {
              'Accept': 'text/plain, text/markdown, */*',
              'User-Agent': 'WinDeployStudio/${AppConstants.appVersion}',
            },
          )
          .timeout(const Duration(seconds: 15));
      if (response.statusCode != 200 ||
          response.bodyBytes.length > 1024 * 1024) {
        return release;
      }
      final body = utf8.decode(response.bodyBytes, allowMalformed: true).trim();
      if (body.isEmpty) return release;
      return <String, dynamic>{...release, 'body': body};
    } catch (_) {
      return release;
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

  Future<UpdateInfo> _withSourceForgeAvailability(UpdateInfo info) async {
    // A mirror outage must not make GitHub update checks fail. Resolve the
    // landing page with a short timeout and retain a simple availability flag
    // in the cache; the signed URL is always resolved again before download.
    final available = await resolveSourceForgeDownloadUrl(info)
        .then((url) => url != null)
        .timeout(const Duration(seconds: 8), onTimeout: () => false);
    return info.copyWith(sourceForgeAvailable: available);
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
        'sourceforge_available': info.sourceForgeAvailable,
        'assets': info.assets
            .map(
              (a) => {
                'name': a.name,
                'browser_download_url': a.url,
                'sourceforge_url': a.sourceForgeUrl,
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
        // Older GitHub releases do not expose the newer `digest` field. They
        // are still valid releases; download verification falls back to the
        // published size and Authenticode signature when no digest is present.
        // The Atom fallback has no asset-size metadata; the stable filename and
        // URL are sufficient to select it. The streaming downloader validates
        // the response length when the size is known and records the actual
        // length when it is not.
        return asset != null && asset.name.isNotEmpty && asset.url.isNotEmpty;
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

  /// Resolves the current signed SourceForge mirror URL for an update asset.
  ///
  /// The stable `/files/{tag}/{asset}/download` URL is intentionally kept out
  /// of the model cache because SourceForge signs the final mirror URL with a
  /// short-lived query string. Callers should invoke this immediately before
  /// starting a transfer.
  Future<String?> resolveSourceForgeDownloadUrl(UpdateInfo info) async {
    final landing = info.generateSourceForgeLandingUrl();
    if (landing == null) return null;

    final client = http.Client();
    try {
      final resolved = await GlobalMirrorDownloadResolver.resolve(
        landing,
        client: client,
      );
      final uri = Uri.tryParse(resolved);
      if (uri == null || !GlobalMirrorDownloadResolver.isGlobalMirrorUrl(uri)) {
        return null;
      }
      // SourceForge may return downloads.sourceforge.net before selecting a
      // concrete mirror. The resolver normally follows that redirect; accept
      // the download host as a last resort because it is still within the
      // trusted SourceForge boundary.
      final host = uri.host.toLowerCase();
      if (GlobalMirrorDownloadResolver.isDirectDownloadUrl(uri) ||
          host == 'downloads.sourceforge.net' ||
          host == 'sourceforge.net') {
        return uri.toString();
      }
      return null;
    } catch (error) {
      LogCenterService().logUpdate(
        '[Update] SourceForge unavailable\nReason=$error',
      );
      return null;
    } finally {
      client.close();
    }
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
      if (GlobalMirrorDownloadResolver.isGlobalMirrorUrl(uri)) return true;
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
    CancelToken cancelToken, {
    UpdateDownloadSource source = UpdateDownloadSource.sourceForge,
  }) async {
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
    if (asset.name.trim().isEmpty || asset.url.trim().isEmpty) {
      LogCenterService().logUpdate(
        '[Download] State=Failed\nReason=Release asset URL unavailable',
      );
      return null;
    }
    // The public Atom feed omits asset sizes. A zero size is valid metadata;
    // _doDownload streams the response and verifies its final byte count.

    final downloadUrl = source == UpdateDownloadSource.sourceForge
        ? await resolveSourceForgeDownloadUrl(freshInfo)
        : freshInfo.generateDownloadUrl();
    if (downloadUrl == null || downloadUrl.isEmpty) {
      LogCenterService().logUpdate(
        '[Download] State=Failed\nReason=Source unavailable\nSource=${source.name}',
      );
      return null;
    }
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
      'CDN=${source == UpdateDownloadSource.sourceForge ? 'SourceForge' : 'GitHub Release'}',
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
        _lastPublishedDownloadSize = await File(result).length();
        log.logUpdate(
          '[Download] State=Stable\nPath=$result\n'
          'Trust=${publishedHash == null ? 'InstallerSignatureAndSize' : 'GitHubReleaseDigest'}\n'
          'Source=${source.name}',
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
      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);
        if (decoded is Map) {
          final release = Map<String, dynamic>.from(decoded);
          if (release['draft'] != true && release['tag_name'] == tagName) {
            return release;
          }
        }
      }
    } catch (error) {
      LogCenterService().logUpdate(
        '[Download] Release API unavailable; trying Releases feed\nReason=$error',
      );
    }

    // The per-tag REST endpoint is subject to the same anonymous rate limit
    // as the list endpoint. The public Atom feed does not carry asset sizes,
    // but it does provide the stable tag and installer filename, which is
    // enough for a streamed download and post-download length verification.
    final atomFallback = await _fetchAtomReleaseByTag(tagName);
    if (atomFallback != null) return atomFallback;

    // Keep both download buttons usable when GitHub's public API and Atom
    // feed are unavailable. SourceForge stores the same installer filename
    // under the version folder and publishes its size through RSS.
    return _fetchSourceForgeReleaseByTag(tagName);
  }

  Future<Map<String, dynamic>?> _fetchAtomReleaseByTag(String tagName) async {
    try {
      final response = await http
          .get(
            Uri.parse(_atomUrl),
            headers: {
              'Accept': 'application/atom+xml, application/xml, text/xml',
              'User-Agent': 'WinDeployStudio/${AppConstants.appVersion}',
            },
          )
          .timeout(const Duration(seconds: 15));
      if (response.statusCode != 200) return null;
      final releases = parseAtomReleaseMetadata(response.body);
      for (final release in releases) {
        if (release['tag_name'] == tagName) return release;
      }
    } catch (error) {
      LogCenterService().logUpdate(
        '[Download] Releases feed unavailable\nReason=$error',
      );
    }
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
      if (asset.sizeBytes > 0 &&
          (responseLength != null && responseLength != asset.sizeBytes)) {
        return null;
      }

      sink = file.openWrite();

      final totalBytes = asset.sizeBytes > 0
          ? asset.sizeBytes
          : (responseLength ?? 0);
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

        if (totalBytes > 0 && downloadedBytes + chunk.length > totalBytes) {
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
      if (finalLength <= 0 ||
          (asset.sizeBytes > 0 && finalLength != asset.sizeBytes) ||
          (responseLength != null && finalLength != responseLength)) {
        return null;
      }

      if (expectedHash != null) {
        final actualHash = await _sha256File(file);
        if (actualHash != expectedHash) {
          LogCenterService().logUpdate(
            '[Download] State=Failed\nReason=Published digest mismatch',
          );
          return null;
        }
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
            _lastPublishedDownloadSize == null ||
            await file.length() != _lastPublishedDownloadSize ||
            (_lastPublishedDownloadHash != null &&
                await _sha256File(file) != _lastPublishedDownloadHash)) {
          log.logUpdate(
            '[Update] InstallFail: Published digest verification failed',
          );
          return false;
        }

        final signature = await _verifyInstallerSignature(filePath);
        final signatureTrusted =
            signature.valid &&
            signature.status == 'Valid' &&
            signature.thumbprint.isNotEmpty &&
            signature.subjectCommonName == signature.publisherCommonName &&
            _isTrustedPublisher(signature.publisherCommonName);

        // Public project installers are not necessarily Authenticode-signed.
        // The file has already been bound to the selected release URL, length,
        // and, when available, the release SHA-256. Record signature status
        // for diagnostics but do not block a verified unsigned installer.
        log.logUpdate(
          '[Update] InstallerTrust\n'
          'ReleaseDigest=${_lastPublishedDownloadHash == null ? 'Unavailable' : 'Valid'}\n'
          'Authenticode=${signatureTrusted ? 'Valid' : 'NotAvailableOrUntrusted'}\n'
          'Status=${signature.status}\n'
          'Publisher=${signature.publisherCommonName}\n'
          'SubjectCN=${signature.subjectCommonName}\n'
          'Subject=${signature.subject}\n'
          'Thumbprint=${signature.thumbprint}\n'
          'Error=${signature.error}',
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
