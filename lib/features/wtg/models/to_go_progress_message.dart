/// Resolves the dynamic To Go progress template without leaking placeholders
/// such as `{percent}` into the execution view.
String resolveToGoProgressMessage({
  required String rawMessage,
  required String Function(String key) translate,
  required String translationMissing,
  int writtenBytes = 0,
  int totalBytes = 0,
  double progress = 0,
}) {
  final localized = translate(rawMessage);
  final template = localized.isEmpty || localized == translationMissing
      ? rawMessage
      : localized;
  if (!template.contains('{percent}')) return template;

  final percent = toGoImageApplyPercent(
    writtenBytes: writtenBytes,
    totalBytes: totalBytes,
    progress: progress,
  );
  return template.replaceAll('{percent}', percent.toString());
}

/// DISM reports image-application progress separately from the overall
/// deployment percentage. Prefer its byte count, with the known To Go phase
/// range as a fallback before the first byte estimate is available.
int toGoImageApplyPercent({
  required int writtenBytes,
  required int totalBytes,
  required double progress,
}) {
  if (totalBytes > 0) {
    return ((writtenBytes * 100) / totalBytes).round().clamp(0, 100);
  }

  const applyStart = 0.22;
  const applyRange = 0.48;
  return (((progress - applyStart) / applyRange) * 100).round().clamp(0, 100);
}
