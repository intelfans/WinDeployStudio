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

class AppVersion {
  final int major;
  final int minor;
  final int patch;

  const AppVersion(this.major, this.minor, this.patch);

  factory AppVersion.parse(String version) {
    final cleaned = version
        .trim()
        .replaceFirst(RegExp(r'^v', caseSensitive: false), '')
        .split('+')
        .first;
    final match = RegExp(
      r'^(\d+)\.(\d+)\.(\d+)(?:[.-].*)?$',
    ).firstMatch(cleaned);
    if (match == null) {
      throw FormatException('Invalid version format: $version');
    }
    return AppVersion(
      int.parse(match.group(1)!),
      int.parse(match.group(2)!),
      int.parse(match.group(3)!),
    );
  }

  bool operator >(AppVersion other) {
    if (major != other.major) return major > other.major;
    if (minor != other.minor) return minor > other.minor;
    return patch > other.patch;
  }

  bool operator <(AppVersion other) => other > this;

  bool operator >=(AppVersion other) => this > other || this == other;

  bool operator <=(AppVersion other) => this < other || this == other;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is AppVersion &&
        other.major == major &&
        other.minor == minor &&
        other.patch == patch;
  }

  @override
  int get hashCode => Object.hash(major, minor, patch);

  @override
  String toString() => '$major.$minor.$patch';
}

class UpdateAsset {
  final String name;
  final String url;
  final int sizeBytes;
  final String contentType;

  const UpdateAsset({
    required this.name,
    required this.url,
    required this.sizeBytes,
    required this.contentType,
  });

  factory UpdateAsset.fromJson(Map<String, dynamic> json) {
    return UpdateAsset(
      name: json['name'] as String? ?? '',
      url: json['browser_download_url'] as String? ?? '',
      sizeBytes: json['size'] as int? ?? 0,
      contentType: json['content_type'] as String? ?? '',
    );
  }

  String get formattedSize {
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

  const UpdateInfo({
    required this.version,
    required this.tagName,
    required this.name,
    required this.body,
    required this.publishedAt,
    required this.assets,
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
          DateTime.now(),
      assets: assetsList,
    );
  }

  UpdateAsset? get bestAsset {
    if (assets.isEmpty) return null;

    final exeAssets = assets
        .where((a) => a.name.toLowerCase().endsWith('.exe'))
        .toList();
    final zipAssets = assets
        .where((a) => a.name.toLowerCase().endsWith('.zip'))
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
    if (zipAssets.isNotEmpty) {
      zipAssets.sort((a, b) => b.sizeBytes.compareTo(a.sizeBytes));
      return zipAssets.first;
    }

    return assets.first;
  }

  String generateDownloadUrl() {
    final asset = bestAsset;
    if (asset == null) return '';
    if (asset.url.isNotEmpty) return asset.url;
    return 'https://github.com/intelfans/WinDeployStudio/releases/download/$tagName/${Uri.encodeComponent(asset.name)}';
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
    );
  }

  bool get hasUpdate {
    if (info == null) return false;
    if (ignoredVersion != null && info!.tagName == ignoredVersion) return false;
    return status == UpdateStatus.available;
  }
}
