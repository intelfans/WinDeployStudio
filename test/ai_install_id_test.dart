import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:win_deploy_studio/core/services/ai_install_id.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    AiInstallId.resetForTesting();
  });

  test('generates an id and reuses it', () async {
    final first = await AiInstallId.get();
    expect(first.length, greaterThanOrEqualTo(8));
    expect(RegExp(r'^[0-9a-fA-F-]+$').hasMatch(first), isTrue);

    AiInstallId.resetForTesting();
    final second = await AiInstallId.get();
    expect(second, first, reason: 'the stored id must survive a restart');
  });

  test('replaces a malformed stored value', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'ai_install_id_v1': 'bad value with spaces!',
    });
    AiInstallId.resetForTesting();
    final id = await AiInstallId.get();
    expect(id.contains(' '), isFalse);
    expect(id.length, greaterThanOrEqualTo(8));
  });

  test('concurrent callers receive the same id', () async {
    final ids = await Future.wait(List.generate(5, (_) => AiInstallId.get()));
    expect(ids.toSet(), hasLength(1));
  });
}
