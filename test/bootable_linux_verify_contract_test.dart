import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Extracts the raw PowerShell body of a named constant from the service file.
String _scriptBody(String source, String constantName) {
  final start = source.indexOf('static const String $constantName');
  expect(start, greaterThan(0), reason: 'constant $constantName not found');
  final open = source.indexOf("r'''", start);
  expect(open, greaterThan(0), reason: 'raw literal for $constantName not found');
  final bodyStart = open + 4;
  final close = source.indexOf("''';", bodyStart);
  expect(close, greaterThan(bodyStart));
  return source.substring(bodyStart, close);
}

void main() {
  late String source;
  late String writeScript;

  setUpAll(() {
    source = File('lib/core/services/bootable_usb_service.dart').readAsStringSync();
    writeScript = _scriptBody(source, '_linuxRawWriteScript');
  });

  test('the raw write script emits a post-mount verification marker', () {
    expect(writeScript.contains('WDS_VERIFY_ONLINE_STARTED'), isTrue);
    expect(writeScript.contains('WDS_VERIFY_ONLINE_COMPLETE'), isTrue);
  });

  test('the post-mount pass runs after the disk is online', () {
    final online = writeScript.indexOf('Write-Output "WDS_DISK_ONLINE"');
    final started = writeScript.indexOf('WDS_VERIFY_ONLINE_STARTED');
    final complete = writeScript.indexOf('WDS_VERIFY_ONLINE_COMPLETE');
    final done = writeScript.indexOf('Write-Output "WDS_DONE"');
    expect(online, greaterThan(0));
    expect(started, greaterThan(online), reason: 'verification must follow the mount');
    expect(complete, greaterThan(started));
    expect(done, greaterThan(complete));
  });

  test('the GPT header window is excluded from the comparison', () {
    expect(writeScript.contains('verifySkipStart = [int64]512'), isTrue);
    expect(writeScript.contains('verifySkipEnd = [int64]1023'), isTrue);
  });

  test('the comparison resumes after the window instead of stopping there', () {
    // A block that contains the window must still be compared after it.
    expect(writeScript.contains('afterStart'), isTrue);
    expect(writeScript.contains(r'$segments += ,@'), isTrue);
  });

  test('success requires the post-mount marker', () {
    expect(source.contains('var onlineVerified = false;'), isTrue);
    expect(source.contains('if (!onlineVerified) {'), isTrue,
        reason: 'the Dart result must not report success without the marker');
  });
}
