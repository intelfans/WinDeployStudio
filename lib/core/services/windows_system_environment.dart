import 'dart:io';

/// Normalizes the small set of Windows environment variables required by
/// inbox PowerShell modules and system executables.
///
/// A launched desktop app can inherit a reduced environment (for example from
/// a sandboxed launcher) without `SystemRoot` or `WINDIR`. The Storage module
/// expands `$env:windir` while loading, so preserve an explicit, valid value
/// whenever the app starts a Windows system process.
class WindowsSystemEnvironment {
  const WindowsSystemEnvironment._();

  static String get systemRoot => _resolveSystemRoot(Platform.environment);

  static String get powerShellExecutable =>
      '$systemRoot\\System32\\WindowsPowerShell\\v1.0\\powershell.exe';

  static String get taskkillExecutable => '$systemRoot\\System32\\taskkill.exe';

  static Map<String, String> withSystemRoot([
    Map<String, String>? baseEnvironment,
  ]) {
    final environment = <String, String>{
      ...(baseEnvironment ?? Platform.environment),
    };
    final root = _resolveSystemRoot(environment);
    environment.removeWhere(
      (key, _) =>
          key.toLowerCase() == 'systemroot' || key.toLowerCase() == 'windir',
    );
    environment['SystemRoot'] = root;
    environment['WINDIR'] = root;
    return environment;
  }

  static String _resolveSystemRoot(Map<String, String> environment) {
    for (final value in [
      _lookup(environment, 'SystemRoot'),
      _lookup(environment, 'WINDIR'),
      _rootFromComSpec(_lookup(environment, 'ComSpec')),
    ]) {
      final normalized = value?.trim() ?? '';
      if (_isAbsoluteWindowsDirectory(normalized)) return normalized;
    }
    // Windows itself normally resides here. The preceding values cover
    // non-default installations without relying on a shell lookup.
    return r'C:\Windows';
  }

  static String? _lookup(Map<String, String> environment, String name) {
    for (final entry in environment.entries) {
      if (entry.key.toLowerCase() == name.toLowerCase()) return entry.value;
    }
    return null;
  }

  static String? _rootFromComSpec(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    final normalized = value.trim().replaceAll('/', '\\');
    final marker = normalized.toLowerCase().lastIndexOf(r'\system32\');
    if (marker <= 2) return null;
    return normalized.substring(0, marker);
  }

  static bool _isAbsoluteWindowsDirectory(String value) =>
      RegExp(r'^[A-Za-z]:\\[^<>:"|?*]*$').hasMatch(value);
}
