import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:win_deploy_studio/core/config/ai_config.dart';

void main() {
  test('the bundled default model is the live replacement', () {
    expect(AiConfig.defaultModel, 'mimo-v2.6-pro');
  });

  test('retired upstream model IDs migrate to their replacements', () {
    const expected = <String, String>{
      'mimo-v2.5-pro': 'mimo-v2.6-pro',
      'mimo-v2.5': 'mimo-v2.6-flash',
      'mimo-v2-pro': 'mimo-v2.6-pro',
      'mimo-v2-omni': 'mimo-v2.6-flash',
      'mimo-v2-flash': 'mimo-v2.6-flash',
    };
    expected.forEach((retired, live) {
      expect(AiConfig.migrateRetiredModelId(retired), live, reason: retired);
      expect(AiConfig.migrateRetiredModelId('  $retired '), live);
      expect(AiConfig.migrateRetiredModelId(retired.toUpperCase()), live);
    });
  });

  test('custom and live model IDs are returned unchanged', () {
    expect(AiConfig.migrateRetiredModelId('mimo-v2.6-pro'), 'mimo-v2.6-pro');
    expect(AiConfig.migrateRetiredModelId('gpt-4o-mini'), 'gpt-4o-mini');
    expect(AiConfig.migrateRetiredModelId(''), '');
  });

  test('a retired model saved by an older build is rewritten on read', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'ai_endpoint_url': 'https://provider.example/v1',
      'ai_model': 'mimo-v2.5-pro',
      'ai_model_endpoint': 'https://provider.example/v1/',
    });

    expect(await AiConfig.getModel(), 'mimo-v2.6-pro');

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('ai_model'), 'mimo-v2.6-pro');
  });
}
