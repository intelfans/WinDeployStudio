import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../../features/logs/services/log_center_service.dart';

class MirrorLatency {
  final String source;
  final bool online;
  final int latency;
  final DateTime testTime;

  const MirrorLatency({
    required this.source,
    required this.online,
    required this.latency,
    required this.testTime,
  });

  String get latencyLabel => online ? '${latency}ms' : 'Offline';
}

class MirrorTestResult {
  final MirrorLatency china;
  final MirrorLatency global;

  const MirrorTestResult({required this.china, required this.global});

  bool get bothOffline => !china.online && !global.online;

  String get recommendedSource {
    if (!china.online && !global.online) return '';
    if (!china.online) return 'global';
    if (!global.online) return 'china';
    return china.latency <= global.latency ? 'china' : 'global';
  }

  MirrorLatency get recommended =>
      recommendedSource == 'china' ? china : global;
}

class MirrorSpeedTestService {
  static const _chinaTestUrl = 'https://www.123684.com';
  static const _globalTestUrl = 'https://gofile.io';
  static const _timeout = Duration(seconds: 5);
  static const _cacheDuration = Duration(minutes: 30);

  static const _cacheKeyChinaLatency = 'mirror_china_latency';
  static const _cacheKeyGlobalLatency = 'mirror_global_latency';
  static const _cacheKeyChinaOnline = 'mirror_china_online';
  static const _cacheKeyGlobalOnline = 'mirror_global_online';
  static const _cacheKeyTestTime = 'mirror_test_time';

  static MirrorTestResult? _cached;

  static Future<MirrorTestResult> test({bool forceRefresh = false}) async {
    if (!forceRefresh && _cached != null) return _cached!;

    if (!forceRefresh) {
      final cached = await _loadCache();
      if (cached != null) {
        _cached = cached;
        return cached;
      }
    }

    final results = await Future.wait([
      _testSource('ChinaMirror', _chinaTestUrl),
      _testSource('GlobalMirror', _globalTestUrl),
    ]);

    final result = MirrorTestResult(china: results[0], global: results[1]);
    _cached = result;
    await _saveCache(result);

    _logResult(result);
    return result;
  }

  static Future<MirrorLatency> _testSource(String name, String url) async {
    final sw = Stopwatch()..start();
    try {
      final response = await http
          .head(Uri.parse(url))
          .timeout(_timeout);
      sw.stop();
      final online = response.statusCode < 500;
      final latency = online ? sw.elapsedMilliseconds : -1;

      LogCenterService().logSystem(
        '[MirrorTest] Target=$name Latency=${sw.elapsedMilliseconds} '
        'Status=${online ? "Online" : "Offline"}',
      );

      return MirrorLatency(
        source: name,
        online: online,
        latency: latency,
        testTime: DateTime.now(),
      );
    } catch (e) {
      sw.stop();
      debugPrint('[MirrorSpeedTest] $name failed: $e');

      LogCenterService().logSystem(
        '[MirrorTest] Target=$name Latency=-1 Status=Offline Error=$e',
      );

      return MirrorLatency(
        source: name,
        online: false,
        latency: -1,
        testTime: DateTime.now(),
      );
    }
  }

  static Future<MirrorTestResult?> _loadCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final testTimeMs = prefs.getInt(_cacheKeyTestTime);
      if (testTimeMs == null) return null;

      final elapsed = DateTime.now().millisecondsSinceEpoch - testTimeMs;
      if (elapsed > _cacheDuration.inMilliseconds) return null;

      final chinaLatency = prefs.getInt(_cacheKeyChinaLatency) ?? -1;
      final globalLatency = prefs.getInt(_cacheKeyGlobalLatency) ?? -1;
      final chinaOnline = prefs.getBool(_cacheKeyChinaOnline) ?? false;
      final globalOnline = prefs.getBool(_cacheKeyGlobalOnline) ?? false;
      final testTime = DateTime.fromMillisecondsSinceEpoch(testTimeMs);

      return MirrorTestResult(
        china: MirrorLatency(
          source: 'ChinaMirror',
          online: chinaOnline,
          latency: chinaLatency,
          testTime: testTime,
        ),
        global: MirrorLatency(
          source: 'GlobalMirror',
          online: globalOnline,
          latency: globalLatency,
          testTime: testTime,
        ),
      );
    } catch (_) {
      return null;
    }
  }

  static Future<void> _saveCache(MirrorTestResult result) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_cacheKeyChinaLatency, result.china.latency);
      await prefs.setInt(_cacheKeyGlobalLatency, result.global.latency);
      await prefs.setBool(_cacheKeyChinaOnline, result.china.online);
      await prefs.setBool(_cacheKeyGlobalOnline, result.global.online);
      await prefs.setInt(
          _cacheKeyTestTime, DateTime.now().millisecondsSinceEpoch);
    } catch (_) {}
  }

  static void _logResult(MirrorTestResult result) {
    final reason = result.recommendedSource == 'china'
        ? 'LowerLatency'
        : result.recommendedSource == 'global'
            ? 'LowerLatency'
            : 'AllOffline';

    LogCenterService().logSystem(
      '[MirrorRecommendation] '
      'Recommended=${result.recommendedSource} Reason=$reason',
    );
  }

  static void clearCache() {
    _cached = null;
  }
}
