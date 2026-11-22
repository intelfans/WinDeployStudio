import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Verifies the installer trust contract at the source level: the release
/// digest must stay a hard requirement, while the missing publisher signature
/// must be something the user can consciously accept.
void main() {
  late String source;

  setUpAll(() {
    source = File(
      'lib/features/update/services/update_service.dart',
    ).readAsStringSync();
  });

  test('the release digest is still enforced before anything runs', () {
    expect(source.contains('await _sha256File(file) != _lastPublishedDownloadHash'), isTrue);
    expect(source.contains('_lastPublishedDownloadSize'), isTrue);
  });

  test('an unsigned installer is blocked until the user consents', () {
    expect(source.contains('if (!signatureTrusted && !allowUnsigned)'), isTrue);
    expect(source.contains('lastInstallBlockedBySignature = true'), isTrue);
  });

  test('consent does not waive the digest check', () {
    final consentIndex = source.indexOf('if (!signatureTrusted && !allowUnsigned)');
    final digestIndex = source.indexOf('await _sha256File(file) != _lastPublishedDownloadHash');
    expect(digestIndex, greaterThan(0));
    expect(consentIndex, greaterThan(digestIndex),
        reason: 'the digest check must run before the consent gate');
  });

  test('the process never starts before both checks pass', () {
    final launch = source.indexOf("Process.start(filePath, [");
    final digest = source.indexOf('await _sha256File(file) != _lastPublishedDownloadHash');
    final consent = source.indexOf('if (!signatureTrusted && !allowUnsigned)');
    expect(launch, greaterThan(digest));
    expect(launch, greaterThan(consent));
  });
}
