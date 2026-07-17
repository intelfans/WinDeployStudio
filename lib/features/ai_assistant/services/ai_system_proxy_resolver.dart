import 'dart:async';
import 'dart:io';

enum AiProxySource { direct, environment, windowsSettings }

class AiProxyResolution {
  final String instruction;
  final AiProxySource source;

  const AiProxyResolution({required this.instruction, required this.source});

  bool get isDirect => instruction == 'DIRECT';

  /// A loopback proxy is normally supplied by a local app such as Clash.
  /// It must be treated as transient: the OS setting or inherited environment
  /// can outlive the local listener after that app exits.
  bool get isLoopbackProxy =>
      AiSystemProxyResolver.isLoopbackProxyInstruction(instruction);
}

/// Resolves a secure HTTP CONNECT proxy for the AI transport.
///
/// Dart honours HTTPS_PROXY when explicitly asked to do so, but it does not
/// automatically read the Windows Internet Settings proxy used by browsers.
/// This resolver supports that common desktop setup without accepting a PAC
/// script or weakening TLS verification.
class AiSystemProxyResolver {
  AiSystemProxyResolver._();

  static const _internetSettingsKey =
      r'HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings';

  static Future<AiProxyResolution> resolveFor(Uri target) async {
    final environmentInstruction = HttpClient.findProxyFromEnvironment(target);
    if (!_isDirect(environmentInstruction)) {
      return _useIfAvailable(
        AiProxyResolution(
          instruction: environmentInstruction,
          source: AiProxySource.environment,
        ),
      );
    }

    if (!Platform.isWindows) {
      return const AiProxyResolution(
        instruction: 'DIRECT',
        source: AiProxySource.direct,
      );
    }

    try {
      final results = await Future.wait([
        _readWindowsSetting('ProxyEnable'),
        _readWindowsSetting('ProxyServer'),
      ]);
      final instruction = windowsProxyInstruction(
        proxyEnabledOutput: results[0],
        proxyServerOutput: results[1],
        scheme: target.scheme,
      );
      if (instruction != null) {
        return _useIfAvailable(
          AiProxyResolution(
            instruction: instruction,
            source: AiProxySource.windowsSettings,
          ),
        );
      }
    } catch (_) {
      // A denied or unavailable registry query should never prevent a direct
      // HTTPS request. The regular connection diagnostics handle that path.
    }

    return const AiProxyResolution(
      instruction: 'DIRECT',
      source: AiProxySource.direct,
    );
  }

  static Future<String> _readWindowsSetting(String name) async {
    final result = await Process.run('reg.exe', [
      'query',
      _internetSettingsKey,
      '/v',
      name,
    ]);
    if (result.exitCode != 0) return '';
    return result.stdout.toString();
  }

  static bool _isDirect(String instruction) =>
      instruction.trim().toUpperCase() == 'DIRECT';

  /// Avoid sending an AI request to a stale local proxy after its owner exits.
  /// Only loopback endpoints are probed, so this never adds a reachability
  /// probe for a user-managed remote corporate proxy.
  static Future<AiProxyResolution> _useIfAvailable(
    AiProxyResolution resolution,
  ) async {
    final endpoint = loopbackProxyEndpoint(resolution.instruction);
    if (endpoint == null) return resolution;

    try {
      final socket = await Socket.connect(
        endpoint.host,
        endpoint.port,
        timeout: const Duration(milliseconds: 600),
      );
      socket.destroy();
      return resolution;
    } on SocketException {
      return const AiProxyResolution(
        instruction: 'DIRECT',
        source: AiProxySource.direct,
      );
    } on TimeoutException {
      return const AiProxyResolution(
        instruction: 'DIRECT',
        source: AiProxySource.direct,
      );
    }
  }

  /// Returns a local HTTP CONNECT proxy endpoint, if [instruction] represents
  /// one. Kept public for focused tests and diagnostics.
  static ({String host, int port})? loopbackProxyEndpoint(String instruction) {
    final match = RegExp(
      r'^\s*PROXY\s+(\[[^\]]+\]|[^:\s;]+):(\d+)(?:\s*;.*)?$',
      caseSensitive: false,
    ).firstMatch(instruction);
    if (match == null) return null;
    final host = match.group(1)!.replaceAll(RegExp(r'^\[|\]$'), '');
    final port = int.tryParse(match.group(2)!);
    if (port == null || port <= 0 || port > 65535) return null;
    final normalizedHost = host.toLowerCase();
    if (normalizedHost != 'localhost' &&
        normalizedHost != '::1' &&
        normalizedHost != '127.0.0.1') {
      return null;
    }
    return (host: host, port: port);
  }

  static bool isLoopbackProxyInstruction(String instruction) =>
      loopbackProxyEndpoint(instruction) != null;

  /// Parses `reg query` output into a Dart [HttpClient.findProxy] directive.
  /// Only standard HTTP CONNECT proxies are accepted; unsupported or malformed
  /// values fall back to direct HTTPS instead of silently changing security.
  static String? windowsProxyInstruction({
    required String proxyEnabledOutput,
    required String proxyServerOutput,
    required String scheme,
  }) {
    if (!RegExp(
      r'REG_DWORD\s+0x1\b',
      caseSensitive: false,
    ).hasMatch(proxyEnabledOutput)) {
      return null;
    }

    final valueMatch = RegExp(
      r'REG_SZ\s+(.+)$',
      caseSensitive: false,
      multiLine: true,
    ).firstMatch(proxyServerOutput);
    final rawValue = valueMatch?.group(1)?.trim();
    if (rawValue == null || rawValue.isEmpty) return null;

    final candidate = _selectProxyValue(rawValue, scheme);
    if (candidate == null) return null;
    return _toHttpConnectDirective(candidate);
  }

  static String? _selectProxyValue(String rawValue, String scheme) {
    final entries = rawValue
        .split(';')
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toList(growable: false);
    if (entries.isEmpty) return null;

    String? fallback;
    for (final entry in entries) {
      final separator = entry.indexOf('=');
      if (separator < 1) {
        fallback ??= entry;
        continue;
      }
      final key = entry.substring(0, separator).trim().toLowerCase();
      final value = entry.substring(separator + 1).trim();
      if (value.isEmpty) continue;
      if (key == scheme.toLowerCase()) return value;
      if (key == 'http') fallback ??= value;
    }
    return fallback;
  }

  static String? _toHttpConnectDirective(String value) {
    var candidate = value.trim();
    if (candidate.isEmpty || candidate.contains('@')) return null;
    if (!RegExp(r'^[a-zA-Z][a-zA-Z0-9+.-]*://').hasMatch(candidate)) {
      candidate = 'http://$candidate';
    }

    final uri = Uri.tryParse(candidate);
    if (uri == null ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.path.isNotEmpty && uri.path != '/') {
      return null;
    }

    final host = uri.host.contains(':') ? '[${uri.host}]' : uri.host;
    final port = uri.hasPort ? uri.port : 80;
    if (port <= 0 || port > 65535) return null;
    return 'PROXY $host:$port';
  }
}
