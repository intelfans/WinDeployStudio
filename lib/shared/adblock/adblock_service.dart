import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class AdBlockStats {
  int blockedAds = 0;
  int blockedTrackers = 0;
  DateTime date = DateTime.now();

  AdBlockStats();

  int get totalBlocked => blockedAds + blockedTrackers;

  Map<String, dynamic> toJson() => {
        'blockedAds': blockedAds,
        'blockedTrackers': blockedTrackers,
        'date': date.toIso8601String(),
      };

  factory AdBlockStats.fromJson(Map<String, dynamic> json) => AdBlockStats()
    ..blockedAds = json['blockedAds'] as int? ?? 0
    ..blockedTrackers = json['blockedTrackers'] as int? ?? 0
    ..date = DateTime.tryParse(json['date'] as String? ?? '') ?? DateTime.now();
}

class AdBlockService {
  static AdBlockService? _instance;
  factory AdBlockService() => _instance ??= AdBlockService._();
  AdBlockService._();

  final Set<String> _adDomains = {};
  final Set<String> _trackingDomains = {};
  final Set<String> _whitelistDomains = {};
  final AdBlockStats _stats = AdBlockStats();
  bool _enabled = true;
  bool _privacyEnabled = true;
  bool _loaded = false;

  bool get isEnabled => _enabled;
  bool get isPrivacyEnabled => _privacyEnabled;
  AdBlockStats get stats => _stats;
  Set<String> get whitelistDomains => _whitelistDomains;
  Set<String> get adDomains => _adDomains;
  Set<String> get trackingDomains => _trackingDomains;

  Future<void> loadRules() async {
    if (_loaded) return;
    try {
      _adDomains.addAll(await _loadAssetLines('assets/adblock/ad_domains.txt'));
      _trackingDomains.addAll(await _loadAssetLines('assets/adblock/tracking_domains.txt'));
      _whitelistDomains.addAll(await _loadAssetLines('assets/adblock/whitelist_domains.txt'));
      _loaded = true;
      debugPrint('[AdBlock] Loaded: ${_adDomains.length} ad, ${_trackingDomains.length} tracking, ${_whitelistDomains.length} whitelist');
    } catch (e) {
      debugPrint('[AdBlock] Failed to load rules: $e');
    }
  }

  Future<List<String>> _loadAssetLines(String path) async {
    final content = await rootBundle.loadString(path);
    return content.split('\n').map((l) => l.trim().toLowerCase()).where((l) => l.isNotEmpty && !l.startsWith('#')).toList();
  }

  bool shouldBlock(String url) {
    if (!_loaded || !_enabled) return false;

    final uri = Uri.tryParse(url);
    if (uri == null) return false;

    final host = uri.host.toLowerCase();
    if (host.isEmpty) return false;

    // Step 1: Whitelist check
    if (_isWhitelisted(host)) return false;

    // Step 2: Ad domains
    if (_matchesAny(host, _adDomains)) {
      _stats.blockedAds++;
      _logBlock('AD', host, url);
      return true;
    }

    // Step 3: Tracking domains
    if (_privacyEnabled && _matchesAny(host, _trackingDomains)) {
      _stats.blockedTrackers++;
      _logBlock('TRACKER', host, url);
      return true;
    }

    return false;
  }

  bool _isWhitelisted(String host) {
    for (final domain in _whitelistDomains) {
      if (host == domain || host.endsWith('.$domain')) return true;
    }
    return false;
  }

  bool _matchesAny(String host, Set<String> rules) {
    for (final rule in rules) {
      if (host == rule || host.endsWith('.$rule')) return true;
    }
    return false;
  }

  void _logBlock(String type, String host, String url) {
    final now = DateTime.now();
    final ts = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')} '
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}';
    debugPrint('[AdBlock] $ts BLOCKED $type Host=$host');
  }

  void setEnabled(bool value) {
    _enabled = value;
    debugPrint('[AdBlock] Enabled: $value');
  }

  void setPrivacyEnabled(bool value) {
    _privacyEnabled = value;
    debugPrint('[AdBlock] Privacy: $value');
  }

  void toggleEnabled() => setEnabled(!_enabled);
  void togglePrivacy() => setPrivacyEnabled(!_privacyEnabled);

  bool isDomainWhitelisted(String host) {
    final h = host.toLowerCase();
    for (final domain in _whitelistDomains) {
      if (h == domain || h.endsWith('.$domain')) return true;
    }
    return false;
  }
}
