import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../config/ai_config.dart';

class GeoResult {
  final String countryCode;
  final String countryName;

  const GeoResult({required this.countryCode, required this.countryName});

  bool get isChina => countryCode == 'CN';
}

class GeoService {
  static const _cacheKeyCountryCode = 'geo_country_code';
  static const _cacheKeyCountryName = 'geo_country_name';
  static const _cacheKeyTimestamp = 'geo_last_check';
  static const _cacheDuration = Duration(hours: 24);
  static const _apiUrl = 'https://ipapi.co/json/';
  static const _timeout = Duration(seconds: 5);

  static GeoResult? _cached;

  /// Whether this build may contact the geolocation endpoint.
  ///
  /// The installer privacy option must cover *every* remote call, not just the
  /// assistant: a plain language-country probe still discloses the user's IP
  /// to a third party on the first download click. Exposed for tests.
  @visibleForTesting
  static bool remoteLookupAllowed() => !AiConfig.isRemoteAiDisabled();

  static Future<GeoResult?> getCountry({bool forceRefresh = false}) async {
    if (_cached != null && !forceRefresh) return _cached;
    if (!remoteLookupAllowed()) {
      return _cachedFromCache();
    }

    try {
      final prefs = await SharedPreferences.getInstance();
      if (!forceRefresh) {
        final cachedCode = prefs.getString(_cacheKeyCountryCode);
        final cachedName = prefs.getString(_cacheKeyCountryName);
        final cachedTime = prefs.getInt(_cacheKeyTimestamp);
        if (cachedCode != null && cachedTime != null) {
          final elapsed = DateTime.now().millisecondsSinceEpoch - cachedTime;
          if (elapsed < _cacheDuration.inMilliseconds) {
            _cached = GeoResult(
              countryCode: cachedCode,
              countryName: cachedName ?? cachedCode,
            );
            return _cached;
          }
        }
      }

      final response = await http.get(Uri.parse(_apiUrl)).timeout(_timeout);
      if (response.statusCode == 200) {
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        // A missing country must not be silently treated as the United States:
        // that flipped the mirror recommendation for every other region.
        final rawCode = json['country_code'];
        final code = rawCode is String ? rawCode.trim().toUpperCase() : '';
        if (code.isEmpty) {
          debugPrint('[GeoService] Response carried no country code');
          return _cachedFromCache();
        }
        final rawName = json['country_name'];
        final name = rawName is String && rawName.trim().isNotEmpty
            ? rawName.trim()
            : code;

        await prefs.setString(_cacheKeyCountryCode, code);
        await prefs.setString(_cacheKeyCountryName, name);
        await prefs.setInt(
          _cacheKeyTimestamp,
          DateTime.now().millisecondsSinceEpoch,
        );

        _cached = GeoResult(countryCode: code, countryName: name);
        debugPrint('[GeoService] Country: $code ($name)');
        return _cached;
      }
    } catch (e) {
      debugPrint('[GeoService] Failed: $e');
    }

    // Fallback: try cache even if expired
    try {
      final prefs = await SharedPreferences.getInstance();
      final cachedCode = prefs.getString(_cacheKeyCountryCode);
      final cachedName = prefs.getString(_cacheKeyCountryName);
      if (cachedCode != null) {
        _cached = GeoResult(
          countryCode: cachedCode,
          countryName: cachedName ?? cachedCode,
        );
        return _cached;
      }
    } catch (_) {}

    return null;
  }

  /// Returns the last stored country without touching the network.
  static Future<GeoResult?> _cachedFromCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cachedCode = prefs.getString(_cacheKeyCountryCode);
      if (cachedCode == null || cachedCode.trim().isEmpty) return null;
      return GeoResult(
        countryCode: cachedCode,
        countryName: prefs.getString(_cacheKeyCountryName) ?? cachedCode,
      );
    } catch (_) {
      return null;
    }
  }

  static void clearCache() {
    _cached = null;
  }
}
