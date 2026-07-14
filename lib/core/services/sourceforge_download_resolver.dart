import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

/// Resolves SourceForge landing and redirect URLs to a short-lived mirror URL.
///
/// SourceForge sometimes serves a file landing page before choosing a mirror.
/// A browser understands that page, but an application download manager needs
/// the actual `*.dl.sourceforge.net` attachment URL instead.
class SourceForgeDownloadResolver {
  static const _maxRedirects = 5;
  static const _requestTimeout = Duration(seconds: 15);
  static const _maxHtmlBytes = 512 * 1024;

  /// Returns [url] unchanged unless it belongs to SourceForge.
  ///
  /// For SourceForge URLs, this follows only SourceForge redirects and parses
  /// a landing page for its current mirror URL. The returned mirror URL can be
  /// passed directly to a streaming download request.
  static Future<String> resolve(String url, {http.Client? client}) async {
    final initial = Uri.tryParse(url);
    if (initial == null || !isSourceForgeUrl(initial)) return url;

    final ownsClient = client == null;
    final requestClient = client ?? http.Client();
    try {
      final resolved = await _resolveUri(initial, requestClient);
      return resolved.toString();
    } finally {
      if (ownsClient) requestClient.close();
    }
  }

  /// Whether [uri] is a SourceForge page or mirror URL trusted by this
  /// resolver. Keeping the redirect boundary here prevents a malicious page
  /// from redirecting the download manager to an unrelated host.
  static bool isSourceForgeUrl(Uri uri) {
    if (uri.scheme != 'https') return false;
    final host = uri.host.toLowerCase();
    return host == 'sourceforge.net' || host.endsWith('.sourceforge.net');
  }

  /// Whether [uri] is the mirror attachment endpoint rather than a landing
  /// page. These URLs contain an expiring signature and should be requested
  /// immediately by the caller.
  static bool isDirectDownloadUrl(Uri uri) {
    return uri.scheme == 'https' &&
        uri.host.toLowerCase().endsWith('.dl.sourceforge.net');
  }

  /// Extracts a trusted SourceForge mirror URL from a SourceForge HTML page.
  ///
  /// This method is intentionally pure so it can be regression-tested against
  /// SourceForge's meta-refresh and JavaScript response formats.
  static Uri? extractDirectUrl(String html, {required Uri baseUri}) {
    final candidates = <String>[];

    for (final match in RegExp(
      r'<meta\b[^>]*>',
      caseSensitive: false,
    ).allMatches(html)) {
      final tag = match.group(0)!;
      final httpEquiv = _attributeValue(tag, 'http-equiv')?.toLowerCase();
      final content = _attributeValue(tag, 'content');
      if (httpEquiv != 'refresh' || content == null) continue;
      final refreshMatch = RegExp(
        r'url\s*=\s*(.+)$',
        caseSensitive: false,
      ).firstMatch(content);
      if (refreshMatch != null) candidates.add(refreshMatch.group(1)!);
    }

    const assignmentPatterns = <String>[
      r'''(?:window\.)?(?:top\.)?location(?:\.href)?\s*=\s*["']([^"']+)["']''',
      r'''(?:window\.)?(?:top\.)?location\.replace\(\s*["']([^"']+)["']\s*\)''',
      r'''(?:download|direct)[_-]?(?:url|link)\s*[:=]\s*["']([^"']+)["']''',
    ];
    for (final pattern in assignmentPatterns) {
      for (final match in RegExp(
        pattern,
        caseSensitive: false,
      ).allMatches(html)) {
        candidates.add(match.group(1)!);
      }
    }

    for (final match in RegExp(
      r'''<a\b[^>]*\bhref\s*=\s*["']([^"']+)["']''',
      caseSensitive: false,
    ).allMatches(html)) {
      candidates.add(match.group(1)!);
    }

    // Some SourceForge pages embed the URL in a JSON payload rather than an
    // anchor or a location assignment.
    for (final match in RegExp(
      r'''(?:https?:)?//[^\s"'<>]+\.dl\.sourceforge\.net/[^\s"'<>]+''',
      caseSensitive: false,
    ).allMatches(html)) {
      candidates.add(match.group(0)!);
    }

    for (final candidate in candidates) {
      final uri = _parseCandidate(candidate, baseUri);
      if (uri != null && isDirectDownloadUrl(uri)) return uri;
    }
    return null;
  }

  static Future<Uri> _resolveUri(Uri initial, http.Client client) async {
    var current = initial;
    final seen = <String>{};

    for (
      var redirectCount = 0;
      redirectCount <= _maxRedirects;
      redirectCount++
    ) {
      if (!seen.add(current.toString())) {
        throw const SourceForgeDownloadResolutionException(
          'SourceForge redirect loop',
        );
      }
      if (isDirectDownloadUrl(current)) return current;

      final request = http.Request('GET', current)
        ..followRedirects = false
        ..headers['Accept'] = 'text/html,application/xhtml+xml,*/*;q=0.8'
        ..headers['Accept-Encoding'] = 'identity'
        // This keeps a possible direct response small while checking whether
        // SourceForge selected a mirror.
        ..headers['Range'] = 'bytes=0-0'
        ..headers['User-Agent'] = 'WinDeployStudio/2.0 SourceForge resolver';
      final response = await client.send(request).timeout(_requestTimeout);

      final location = response.headers['location'];
      if (_isRedirect(response.statusCode) && location != null) {
        await _cancel(response);
        final next = _parseCandidate(location, current);
        if (next == null || !isSourceForgeUrl(next)) {
          throw const SourceForgeDownloadResolutionException(
            'SourceForge returned an untrusted redirect',
          );
        }
        if (isDirectDownloadUrl(next)) return next;
        current = next;
        continue;
      }

      final contentType = response.headers['content-type']?.toLowerCase() ?? '';
      if (response.statusCode >= 200 &&
          response.statusCode < 300 &&
          !contentType.contains('text/html') &&
          !contentType.contains('application/xhtml+xml')) {
        await _cancel(response);
        return current;
      }

      if (response.statusCode >= 200 && response.statusCode < 300) {
        final html = await _readHtml(response);
        final next = extractDirectUrl(html, baseUri: current);
        if (next != null) return next;
        throw const SourceForgeDownloadResolutionException(
          'SourceForge did not provide a direct download URL',
        );
      }

      await _cancel(response);
      throw SourceForgeDownloadResolutionException(
        'SourceForge returned HTTP ${response.statusCode}',
      );
    }

    throw const SourceForgeDownloadResolutionException(
      'Too many SourceForge redirects',
    );
  }

  static bool _isRedirect(int statusCode) =>
      statusCode == 301 ||
      statusCode == 302 ||
      statusCode == 303 ||
      statusCode == 307 ||
      statusCode == 308;

  static Future<String> _readHtml(http.StreamedResponse response) async {
    final buffer = BytesBuilder(copy: false);
    await for (final chunk in response.stream) {
      buffer.add(chunk);
      if (buffer.length > _maxHtmlBytes) {
        throw const SourceForgeDownloadResolutionException(
          'SourceForge landing page is too large',
        );
      }
    }
    return utf8.decode(buffer.takeBytes(), allowMalformed: true);
  }

  static Future<void> _cancel(http.StreamedResponse response) async {
    await response.stream.listen((_) {}).cancel();
  }

  static Uri? _parseCandidate(String raw, Uri baseUri) {
    var value = _decodeEscapes(raw.trim());
    value = value.replaceFirst(RegExp(r'''^["']+'''), '');
    value = value.replaceFirst(RegExp(r'''["';,\s]+$'''), '');
    if (value.startsWith('//')) value = '${baseUri.scheme}:$value';
    final parsed = Uri.tryParse(value);
    if (parsed == null) return null;
    return parsed.hasScheme ? parsed : baseUri.resolveUri(parsed);
  }

  static String _decodeEscapes(String value) {
    return value
        .replaceAll('&amp;', '&')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'")
        .replaceAll(r'\/', '/')
        .replaceAll(r'\u0026', '&')
        .replaceAll(r'\x26', '&');
  }

  static String? _attributeValue(String tag, String name) {
    final match = RegExp(
      '${RegExp.escape(name)}\\s*=\\s*(?:"([^"]*)"|\'([^\']*)\'|([^\\s>]+))',
      caseSensitive: false,
    ).firstMatch(tag);
    return match?.group(1) ?? match?.group(2) ?? match?.group(3);
  }
}

class SourceForgeDownloadResolutionException implements Exception {
  final String message;

  const SourceForgeDownloadResolutionException(this.message);

  @override
  String toString() => message;
}
