/// Formats a creator progress payload for display.
///
/// The first line of [rawMessage] is a localization key. Progress services can
/// place a technical diagnostic in [error] and append a log path as
/// `\n\nLog: <path>`. Templates such as `boot_partition_failed` use an
/// `{error}` placeholder, which is resolved here before rendering.
String resolveCreatorProgressMessage({
  required String rawMessage,
  required String Function(String key) translate,
  String? error,
}) {
  final parts = rawMessage.split('\n\nLog: ');
  final messageLines = parts.first.split('\n');
  final messageKey = messageLines.first;
  final inlineDetails = messageLines
      .skip(1)
      .map((line) => line.trim())
      .where((line) => line.isNotEmpty)
      .toList(growable: false);
  final logPath = parts.length > 1 ? parts[1] : null;
  final diagnostic = error?.trim();

  final localizedTemplate = translate(messageKey);
  final usesErrorPlaceholder = localizedTemplate.contains('{error}');
  final usesDetailPlaceholder = localizedTemplate.contains('{detail}');
  final resolvedError = diagnostic?.isNotEmpty == true
      ? resolveCreatorDiagnostic(diagnostic!, translate)
      : translate('creator_error');
  var resolved = localizedTemplate
      .replaceAll('{error}', usesErrorPlaceholder ? resolvedError : '{error}')
      .replaceAll(
        '{detail}',
        usesDetailPlaceholder ? resolvedError : '{detail}',
      );

  // Diagnostics are normally embedded in the localized template. For keys
  // without an error placeholder, show a separately provided diagnostic once.
  final details = <String>[
    ...inlineDetails,
    if (!usesErrorPlaceholder &&
        !usesDetailPlaceholder &&
        inlineDetails.isEmpty &&
        diagnostic?.isNotEmpty == true)
      resolvedError,
  ];
  if (details.isNotEmpty) {
    resolved = '$resolved\n${details.join('\n')}';
  }
  if (logPath != null) {
    resolved = '$resolved\n\n${translate('logs_title')}: $logPath';
  }
  return resolved;
}

String resolveCreatorDiagnostic(
  String diagnostic,
  String Function(String key) translate,
) {
  const prefix = 'i18n:';
  if (!diagnostic.startsWith(prefix)) return diagnostic;
  return translate(diagnostic.substring(prefix.length));
}
