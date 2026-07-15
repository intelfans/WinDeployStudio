enum UpdateChannel {
  stable,
  beta,
  nightly;

  String get label {
    switch (this) {
      case UpdateChannel.stable:
        return 'Stable';
      case UpdateChannel.beta:
        return 'Beta';
      case UpdateChannel.nightly:
        return 'Nightly';
    }
  }
}

/// The two distribution channels exposed by the update dialog.
///
/// SourceForge is the preferred channel because it is the project's mirrored
/// download location. GitHub remains available as a fallback when the mirror
/// is not reachable.
enum UpdateDownloadSource { sourceForge, github }

class AppVersion implements Comparable<AppVersion> {
  final int major;
  final int minor;
  final int patch;
  final String preRelease;

  const AppVersion(this.major, this.minor, this.patch, {this.preRelease = ''});

  factory AppVersion.parse(String version) {
    final cleaned = version
        .trim()
        .replaceFirst(RegExp(r'^v', caseSensitive: false), '')
        .split('+')
        .first;
    final match = RegExp(
      r'^(\d+)\.(\d+)\.(\d+)(?:[-.]([0-9A-Za-z.-]+))?$',
    ).firstMatch(cleaned);
    if (match == null) {
      throw FormatException('Invalid version format: $version');
    }
    return AppVersion(
      int.parse(match.group(1)!),
      int.parse(match.group(2)!),
      int.parse(match.group(3)!),
      preRelease: match.group(4) ?? '',
    );
  }

  @override
  int compareTo(AppVersion other) {
    if (major != other.major) return major.compareTo(other.major);
    if (minor != other.minor) return minor.compareTo(other.minor);
    if (patch != other.patch) return patch.compareTo(other.patch);
    if (preRelease.isEmpty && other.preRelease.isEmpty) return 0;
    if (preRelease.isEmpty) return 1;
    if (other.preRelease.isEmpty) return -1;

    final left = preRelease.split('.');
    final right = other.preRelease.split('.');
    for (var index = 0; index < left.length && index < right.length; index++) {
      final leftNumber = BigInt.tryParse(left[index]);
      final rightNumber = BigInt.tryParse(right[index]);
      final comparison = switch ((leftNumber, rightNumber)) {
        (final BigInt leftValue, final BigInt rightValue) =>
          leftValue.compareTo(rightValue),
        (final BigInt _, null) => -1,
        (null, final BigInt _) => 1,
        _ => left[index].toLowerCase().compareTo(right[index].toLowerCase()),
      };
      if (comparison != 0) return comparison;
    }
    return left.length.compareTo(right.length);
  }

  bool operator >(AppVersion other) => compareTo(other) > 0;

  bool operator <(AppVersion other) => other > this;

  bool operator >=(AppVersion other) => this > other || this == other;

  bool operator <=(AppVersion other) => this < other || this == other;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is AppVersion &&
        other.major == major &&
        other.minor == minor &&
        other.patch == patch &&
        other.preRelease.toLowerCase() == preRelease.toLowerCase();
  }

  @override
  int get hashCode =>
      Object.hash(major, minor, patch, preRelease.toLowerCase());

  @override
  String toString() {
    final base = '$major.$minor.$patch';
    return preRelease.isEmpty ? base : '$base-$preRelease';
  }
}

class UpdateAsset {
  final String name;
  final String url;

  /// Optional SourceForge landing URL discovered from the mirror RSS feed.
  /// GitHub release metadata does not include this field.
  final String sourceForgeUrl;
  final int sizeBytes;
  final String contentType;
  final String digest;

  const UpdateAsset({
    required this.name,
    required this.url,
    this.sourceForgeUrl = '',
    required this.sizeBytes,
    required this.contentType,
    required this.digest,
  });

  factory UpdateAsset.fromJson(Map<String, dynamic> json) {
    return UpdateAsset(
      name: json['name'] as String? ?? '',
      url: json['browser_download_url'] as String? ?? '',
      sourceForgeUrl: json['sourceforge_url'] as String? ?? '',
      sizeBytes: json['size'] as int? ?? 0,
      contentType: json['content_type'] as String? ?? '',
      digest: json['digest'] as String? ?? '',
    );
  }

  String? get sha256 {
    final match = RegExp(
      r'^sha256:([0-9a-f]{64})$',
      caseSensitive: false,
    ).firstMatch(digest.trim());
    return match?.group(1)?.toUpperCase();
  }

  String get formattedSize {
    if (sizeBytes <= 0) return 'Unknown size';
    if (sizeBytes < 1024) return '$sizeBytes B';
    if (sizeBytes < 1024 * 1024) {
      return '${(sizeBytes / 1024).toStringAsFixed(1)} KB';
    }
    return '${(sizeBytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}

class UpdateInfo {
  final AppVersion version;
  final String tagName;
  final String name;
  final String body;
  final DateTime publishedAt;
  final List<UpdateAsset> assets;

  /// Whether the matching SourceForge file was reachable during the last
  /// release check. A null value means the release came from an older cache
  /// that did not contain availability metadata.
  final bool? sourceForgeAvailable;

  const UpdateInfo({
    required this.version,
    required this.tagName,
    required this.name,
    required this.body,
    required this.publishedAt,
    required this.assets,
    this.sourceForgeAvailable,
  });

  factory UpdateInfo.fromJson(Map<String, dynamic> json) {
    final tagName = json['tag_name'] as String? ?? '';
    final version = AppVersion.parse(tagName);
    final assetsList = (json['assets'] as List<dynamic>? ?? [])
        .map((a) => UpdateAsset.fromJson(a as Map<String, dynamic>))
        .toList();

    return UpdateInfo(
      version: version,
      tagName: tagName,
      name: json['name'] as String? ?? '',
      body: json['body'] as String? ?? '',
      publishedAt:
          DateTime.tryParse(json['published_at'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      assets: assetsList,
      sourceForgeAvailable: json['sourceforge_available'] as bool?,
    );
  }

  UpdateInfo copyWith({bool? sourceForgeAvailable}) {
    return UpdateInfo(
      version: version,
      tagName: tagName,
      name: name,
      body: body,
      publishedAt: publishedAt,
      assets: assets,
      sourceForgeAvailable: sourceForgeAvailable ?? this.sourceForgeAvailable,
    );
  }

  UpdateAsset? get bestAsset {
    if (assets.isEmpty) return null;

    final exeAssets = assets
        .where((a) => a.name.toLowerCase().endsWith('.exe'))
        .toList();

    UpdateAsset? setupExe;
    for (final asset in exeAssets) {
      final name = asset.name.toLowerCase();
      if (name.contains('setup') || name.contains('install')) {
        if (setupExe == null || asset.sizeBytes > setupExe.sizeBytes) {
          setupExe = asset;
        }
      }
    }

    if (setupExe != null) return setupExe;
    if (exeAssets.isNotEmpty) {
      exeAssets.sort((a, b) => b.sizeBytes.compareTo(a.sizeBytes));
      return exeAssets.first;
    }
    return null;
  }

  String generateDownloadUrl() {
    final asset = bestAsset;
    if (asset == null) return '';
    // A SourceForge-only fallback still needs a usable GitHub fallback. The
    // canonical release URL is deterministic and avoids accidentally sending
    // a SourceForge URL through the GitHub download button.
    if (asset.url.isNotEmpty) {
      final host = Uri.tryParse(asset.url)?.host.toLowerCase();
      if (host == 'github.com' || host?.endsWith('.github.com') == true) {
        return asset.url;
      }
    }
    return 'https://github.com/intelfans/WinDeployStudio/releases/download/$tagName/${Uri.encodeComponent(asset.name)}';
  }

  /// SourceForge's stable file landing URL. The final mirror URL is signed
  /// and short-lived, so it is resolved immediately before downloading.
  String? generateSourceForgeLandingUrl() {
    final asset = bestAsset;
    if (asset == null || tagName.trim().isEmpty || asset.name.trim().isEmpty) {
      return null;
    }
    if (asset.sourceForgeUrl.trim().isNotEmpty) {
      return asset.sourceForgeUrl;
    }
    return Uri(
      scheme: 'https',
      host: 'sourceforge.net',
      pathSegments: <String>[
        'projects',
        'windeploystudio',
        'files',
        tagName,
        asset.name,
        'download',
      ],
    ).toString();
  }

  /// Returns the release-note section matching the selected UI language.
  ///
  /// Releases are authored with English and Simplified Chinese sections
  /// separated by a horizontal rule. Other locales use the English section;
  /// when a release has no clear bilingual separator the original body is
  /// preserved verbatim.
  String bodyForLocale(String localeCode) {
    final normalized = localeCode.replaceAll('-', '_').toLowerCase();
    final sections = body
        .split(
          RegExp(
            r'^\s*(?:---+|<hr\s*/?>)\s*$',
            multiLine: true,
            caseSensitive: false,
          ),
        )
        .map((section) => section.trim())
        .where((section) => section.isNotEmpty)
        .toList();
    if (sections.length < 2) return body;

    int chineseScore(String value) =>
        RegExp(r'[\u3400-\u4dbf\u4e00-\u9fff]').allMatches(value).length;
    if (normalized.startsWith('zh')) {
      sections.sort(
        (left, right) => chineseScore(right).compareTo(chineseScore(left)),
      );
    } else {
      sections.sort(
        (left, right) => chineseScore(left).compareTo(chineseScore(right)),
      );
    }
    return sections.first;
  }
}

enum DownloadPhase {
  connecting,
  optimizing,
  stable,
  retrying,
  failed;

  String get labelKey {
    switch (this) {
      case DownloadPhase.connecting:
        return 'download_connecting';
      case DownloadPhase.optimizing:
        return 'download_optimizing';
      case DownloadPhase.stable:
        return 'download_stable';
      case DownloadPhase.retrying:
        return 'download_retrying';
      case DownloadPhase.failed:
        return 'download_failed';
    }
  }
}

enum UpdateStatus {
  idle,
  checking,
  available,
  downloading,
  downloaded,
  installing,
  upToDate,
  error,
}

class UpdateState {
  final UpdateStatus status;
  final UpdateInfo? info;
  final double downloadProgress;
  final String downloadSpeed;
  final String downloadRemaining;
  final DownloadPhase downloadPhase;
  final int retryCount;
  final String? error;
  final DateTime? lastCheckTime;
  final bool autoCheckEnabled;
  final UpdateChannel channel;
  final String? ignoredVersion;
  final UpdateDownloadSource downloadSource;

  const UpdateState({
    this.status = UpdateStatus.idle,
    this.info,
    this.downloadProgress = 0.0,
    this.downloadSpeed = '',
    this.downloadRemaining = '',
    this.downloadPhase = DownloadPhase.connecting,
    this.retryCount = 0,
    this.error,
    this.lastCheckTime,
    this.autoCheckEnabled = true,
    this.channel = UpdateChannel.stable,
    this.ignoredVersion,
    this.downloadSource = UpdateDownloadSource.sourceForge,
  });

  UpdateState copyWith({
    UpdateStatus? status,
    UpdateInfo? info,
    double? downloadProgress,
    String? downloadSpeed,
    String? downloadRemaining,
    DownloadPhase? downloadPhase,
    int? retryCount,
    String? error,
    DateTime? lastCheckTime,
    bool? autoCheckEnabled,
    UpdateChannel? channel,
    String? ignoredVersion,
    UpdateDownloadSource? downloadSource,
  }) {
    return UpdateState(
      status: status ?? this.status,
      info: info ?? this.info,
      downloadProgress: downloadProgress ?? this.downloadProgress,
      downloadSpeed: downloadSpeed ?? this.downloadSpeed,
      downloadRemaining: downloadRemaining ?? this.downloadRemaining,
      downloadPhase: downloadPhase ?? this.downloadPhase,
      retryCount: retryCount ?? this.retryCount,
      error: error ?? this.error,
      lastCheckTime: lastCheckTime ?? this.lastCheckTime,
      autoCheckEnabled: autoCheckEnabled ?? this.autoCheckEnabled,
      channel: channel ?? this.channel,
      ignoredVersion: ignoredVersion ?? this.ignoredVersion,
      downloadSource: downloadSource ?? this.downloadSource,
    );
  }

  bool get hasUpdate {
    if (info == null) return false;
    if (ignoredVersion != null && info!.tagName == ignoredVersion) return false;
    return status == UpdateStatus.available;
  }
}
