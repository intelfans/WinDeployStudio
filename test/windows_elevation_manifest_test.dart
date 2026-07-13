import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Windows runner always requests administrator privileges', () async {
    final manifest = await File(
      'windows/runner/runner.exe.manifest',
    ).readAsString();
    final cmake = await File('windows/runner/CMakeLists.txt').readAsString();

    expect(manifest, contains('level="requireAdministrator"'));
    expect(manifest, contains('uiAccess="false"'));
    expect(manifest, isNot(contains('level="asInvoker"')));
    expect(cmake, contains('/MANIFESTUAC:NO'));
  });
}
