import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class GeoResult {
  final String countryCode;
  final String countryName;

  const GeoResult({required this.countryCode, required this.countryName});

  bool get isChina => countryCode == 'CN';

  String get regionLabel => isChina ? 'China' : countryName;
  String get mirrorLabel => isChina ? 'China Mirror' : 'Global Mirror';
}

class GeoService {
  static const _cacheKeyCountryCode = 'geo_country_code';
  static const _cacheKeyCountryName = 'geo_country_name';
  static const _cacheKeyTimestamp = 'geo_last_check';
  static const _cacheDuration = Duration(hours: 24);
  static const _apiUrl = 'https://ipapi.co/json/';
  static const _timeout = Duration(seconds: 5);

  static GeoResult? _cached;

  static Future<GeoResult?> getCountry({bool forceRefresh = false}) async {
    if (_cached != null && !forceRefresh) return _cached;

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
        final code = json['country_code'] as String? ?? 'US';
        final name = json['country_name'] as String? ?? code;

        await prefs.setString(_cacheKeyCountryCode, code);
        await prefs.setString(_cacheKeyCountryName, name);
        await prefs.setInt(_cacheKeyTimestamp, DateTime.now().millisecondsSinceEpoch);

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

  static void clearCache() {
    _cached = null;
  }
}
