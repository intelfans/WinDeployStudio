import 'dart:async';
import 'dart:convert';
import 'dart:io';

enum AiNetworkRouteSource { direct, environment, windowsSystem }

/// A standard network route selected for one HTTPS request.
///
/// [instruction] uses the `HttpClient.findProxy` directive format and is
/// intentionally limited to `DIRECT` or an unauthenticated HTTP CONNECT
/// route. TLS validation remains entirely under Dart's normal validation.
class AiNetworkRoute {
  final String instruction;
  final AiNetworkRouteSource source;

  const AiNetworkRoute({required this.instruction, required this.source});

  bool get isDirect => instruction == 'DIRECT';
}

/// Resolves the normal desktop network route for an AI request.
///
/// The order follows standard user and operating-system configuration:
/// environment variables (including their exclusions), the Windows system
/// resolver (static settings, PAC, WPAD and exceptions), then direct access.
/// No application-specific network software is detected or treated specially.
class AiSystemNetworkResolver {
  AiSystemNetworkResolver._();

  static const _resolutionTimeout = Duration(seconds: 4);

  static Future<AiNetworkRoute> resolveFor(Uri target) async {
    final environmentInstruction = _environmentInstructionFor(target);
    if (!_isDirect(environmentInstruction)) {
      return AiNetworkRoute(
        instruction: environmentInstruction,
        source: AiNetworkRouteSource.environment,
      );
    }

    // An explicit environment network configuration may intentionally bypass
    // this host through NO_PROXY. Do not override it with a Windows route.
    if (_hasEnvironmentNetworkConfiguration()) {
      return const AiNetworkRoute(
        instruction: 'DIRECT',
        source: AiNetworkRouteSource.environment,
      );
    }

    if (Platform.isWindows) {
      final instruction = await _readWindowsSystemRoute(target);
      if (instruction != null && !_isDirect(instruction)) {
        return AiNetworkRoute(
          instruction: instruction,
          source: AiNetworkRouteSource.windowsSystem,
        );
      }
    }

    return const AiNetworkRoute(
      instruction: 'DIRECT',
      source: AiNetworkRouteSource.direct,
    );
  }

  static bool _hasEnvironmentNetworkConfiguration() {
    const names = {'HTTP_PROXY', 'HTTPS_PROXY', 'ALL_PROXY'};
    return Platform.environment.entries.any(
      (entry) =>
          names.contains(entry.key.toUpperCase()) &&
          entry.value.trim().isNotEmpty,
    );
  }

  static String _environmentInstructionFor(Uri target) {
    final standard = HttpClient.findProxyFromEnvironment(target);
    if (!_isDirect(standard) || _environmentNoProxyMatches(target)) {
      return standard;
    }

    // ALL_PROXY is a widely used standard environment setting that is not
    // represented by every Dart runtime's built-in resolver. Treat it exactly
    // like an HTTP CONNECT route while preserving NO_PROXY exclusions.
    final allProxy = _environmentValue('ALL_PROXY');
    return allProxy == null
        ? standard
        : systemRouteInstruction(allProxy) ?? standard;
  }

  static String? _environmentValue(String name) {
    for (final entry in Platform.environment.entries) {
      if (entry.key.toUpperCase() == name && entry.value.trim().isNotEmpty) {
        return entry.value.trim();
      }
    }
    return null;
  }

  static bool _environmentNoProxyMatches(Uri target) {
    final raw = _environmentValue('NO_PROXY');
    if (raw == null) return false;
    final host = target.host.toLowerCase();
    return raw.split(',').map((entry) => entry.trim().toLowerCase()).any((
      entry,
    ) {
      if (entry.isEmpty) return false;
      if (entry == '*') return true;
      final value = entry.startsWith('.') ? entry.substring(1) : entry;
      final hasSinglePortSeparator =
          ':'.allMatches(value).length == 1 && !value.startsWith('[');
      final candidate = hasSinglePortSeparator
          ? value.substring(0, value.lastIndexOf(':'))
          : value.replaceAll(RegExp(r'^\[|\]$'), '');
      return candidate.isNotEmpty &&
          (host == candidate || host.endsWith('.$candidate'));
    });
  }

  /// Lets Windows evaluate the exact URL through its standard resolver. That
  /// includes static proxy settings, ProxyOverride, PAC and WPAD when enabled
  /// by the user or organisation. The URL is passed via an environment value,
  /// never interpolated into a command string.
  static Future<String?> _readWindowsSystemRoute(Uri target) async {
    Process? process;
    try {
      process = await Process.start(
        'powershell.exe',
        [
          '-NoLogo',
          '-NoProfile',
          '-NonInteractive',
          '-Command',
          r'''
$target = [Uri]$env:WDS_AI_NETWORK_TARGET
$proxy = [System.Net.WebRequest]::GetSystemWebProxy()
if ($proxy.IsBypassed($target)) {
  [Console]::Out.Write('DIRECT')
  exit 0
}
$resolved = $proxy.GetProxy($target)
if ($null -eq $resolved -or $resolved.AbsoluteUri -eq $target.AbsoluteUri) {
  [Console]::Out.Write('DIRECT')
} else {
  [Console]::Out.Write($resolved.AbsoluteUri)
}
''',
        ],
        environment: {
          ...Platform.environment,
          'WDS_AI_NETWORK_TARGET': target.toString(),
        },
      );
      final stdout = process.stdout.transform(utf8.decoder).join();
      final stderr = process.stderr.transform(utf8.decoder).join();
      final exitCode = await process.exitCode.timeout(_resolutionTimeout);
      final output = await stdout;
      await stderr;
      if (exitCode != 0) return null;
      return systemRouteInstruction(output);
    } on TimeoutException {
      process?.kill();
      return null;
    } on ProcessException {
      return null;
    } catch (_) {
      return null;
    }
  }

  static bool _isDirect(String instruction) =>
      instruction.trim().toUpperCase() == 'DIRECT';

  /// Parses the bounded output of Windows' standard system proxy resolver.
  /// Kept public for focused tests without invoking a Windows process.
  static String? systemRouteInstruction(String output) {
    final value = output.trim();
    if (value.isEmpty) return null;
    if (_isDirect(value)) return 'DIRECT';
    return _toHttpConnectDirective(value);
  }

  static String? _toHttpConnectDirective(String value) {
    var candidate = value.trim();
    if (candidate.isEmpty || candidate.contains('@')) return null;
    if (!RegExp(r'^[a-zA-Z][a-zA-Z0-9+.-]*://').hasMatch(candidate)) {
      candidate = 'http://$candidate';
    }

    final uri = Uri.tryParse(candidate);
    if (uri == null ||
        uri.scheme.toLowerCase() != 'http' ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        (uri.path.isNotEmpty && uri.path != '/')) {
      return null;
    }

    final host = uri.host.contains(':') ? '[${uri.host}]' : uri.host;
    final port = uri.hasPort ? uri.port : 80;
    if (port <= 0 || port > 65535) return null;
    return 'PROXY $host:$port';
  }
}
