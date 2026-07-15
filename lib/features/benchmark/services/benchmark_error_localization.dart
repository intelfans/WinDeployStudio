import '../../../core/localization/strings.dart';

/// Converts benchmark error keys (optionally followed by native stderr) into
/// a localized, actionable message.
///
/// Native helpers append their diagnostic output to a stable key using a
/// colon, for example `bench_error_native_failed: access denied`. Treating
/// that whole value as a translation key makes the UI show the generic
/// missing-translation marker. Keep the key and detail separate so every
/// locale receives the translated explanation while retaining diagnostics.
String localizeBenchmarkError(String localeCode, String error) {
  final raw = error.trim();
  if (raw.isEmpty) {
    return trByCode(localeCode, 'bench_error_native_failed');
  }

  final separator = raw.indexOf(':');
  final key = separator > 0 ? raw.substring(0, separator).trim() : raw;
  final detail = separator > 0 ? raw.substring(separator + 1).trim() : '';

  // Non-key errors are already human-readable diagnostics from the platform.
  if (!key.startsWith('bench_')) return raw;

  final localized = trByCode(localeCode, key);
  final missing = trByCode(localeCode, 'translation_missing');
  final base = localized.isEmpty || localized == missing
      ? trByCode(localeCode, 'bench_error_native_failed')
      : localized;

  if (detail.isEmpty) return base;
  return '$base\n$detail';
}
