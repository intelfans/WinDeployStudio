import 'package:flutter_test/flutter_test.dart';
import 'package:win_deploy_studio/core/services/windows_system_environment.dart';

void main() {
  test('adds Windows system paths to a reduced child environment', () {
    final environment = WindowsSystemEnvironment.withSystemRoot({
      'WDS_TEST_VALUE': 'kept',
    });

    expect(environment['WDS_TEST_VALUE'], 'kept');
    expect(environment['SystemRoot'], matches(RegExp(r'^[A-Za-z]:\\')));
    expect(environment['WINDIR'], environment['SystemRoot']);
  });

  test('preserves a valid explicit Windows root', () {
    final environment = WindowsSystemEnvironment.withSystemRoot({
      'SystemRoot': r'D:\Windows',
      'WINDIR': r'C:\Windows',
    });

    expect(environment['SystemRoot'], r'D:\Windows');
    expect(environment['WINDIR'], r'D:\Windows');
  });

  test('normalizes case-insensitive Windows environment keys', () {
    final environment = WindowsSystemEnvironment.withSystemRoot({
      'windir': r'E:\Windows',
      'WDS_TEST_VALUE': 'kept',
    });

    expect(environment['SystemRoot'], r'E:\Windows');
    expect(environment['WINDIR'], r'E:\Windows');
    expect(environment.containsKey('windir'), isFalse);
    expect(environment['WDS_TEST_VALUE'], 'kept');
  });
}
