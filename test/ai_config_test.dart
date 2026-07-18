import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:win_deploy_studio/core/config/ai_config.dart';

void main() {
  group('AiConfig endpoint normalization', () {
    test('normalizes a host and preserves an API base path', () {
      expect(
        AiConfig.normalizeEndpointUrl('service.example/v1'),
        'https://service.example/v1/',
      );
      expect(
        AiConfig.chatCompletionsUri('https://service.example/v1/').toString(),
        'https://service.example/v1/chat/completions',
      );
      expect(
        AiConfig.chatCompletionsUri(
          'https://service.example/v1/chat/completions',
        ).toString(),
        'https://service.example/v1/chat/completions',
      );
    });

    test('accepts only safe HTTPS service endpoints', () {
      expect(
        AiConfig.isValidEndpointUrl('https://service.example/v1/'),
        isTrue,
      );
      expect(AiConfig.isValidEndpointUrl('http://service.example/'), isFalse);
      expect(
        AiConfig.isValidEndpointUrl('https://user:pass@service.example/'),
        isFalse,
      );
      expect(
        AiConfig.isValidEndpointUrl('https://service.example/?token=value'),
        isFalse,
      );
    });

    test(
      'builds the OpenAI-compatible models route for common endpoint forms',
      () {
        expect(
          AiConfig.modelsUri('https://service.example/v1/').toString(),
          'https://service.example/v1/models',
        );
        expect(
          AiConfig.modelsUri('https://provider.example/v1/').toString(),
          'https://provider.example/v1/models',
        );
        expect(
          AiConfig.modelsUri(
            'https://provider.example/v1/chat/completions',
          ).toString(),
          'https://provider.example/v1/models',
        );
      },
    );

    test('builds the Responses route for common endpoint forms', () {
      expect(
        AiConfig.responsesUri('https://service.example/v1/').toString(),
        'https://service.example/v1/responses',
      );
      expect(
        AiConfig.responsesUri('https://provider.example/v1/').toString(),
        'https://provider.example/v1/responses',
      );
      expect(
        AiConfig.responsesUri(
          'https://provider.example/v1/chat/completions',
        ).toString(),
        'https://provider.example/v1/responses',
      );
    });

    test(
      'rejects unsafe credentials and keeps the built-in endpoint isolated',
      () {
        expect(AiConfig.isValidApiKey('sk-example-value'), isTrue);
        expect(AiConfig.isValidApiKey('sk-example value'), isFalse);
        expect(AiConfig.isValidApiKey('sk-example\nvalue'), isFalse);
        expect(AiConfig.shouldSendApiKey(AiConfig.defaultEndpointUrl), isFalse);
        expect(
          AiConfig.shouldSendApiKey('https://provider.example/v1/'),
          isTrue,
        );
      },
    );

    test('protects, reads, and clears a saved API key', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});

      await expectLater(
        AiConfig.setApiKey('sk-test-secret'),
        throwsA(isA<StateError>()),
      );
      await AiConfig.setEndpointUrl('https://provider.example/v1/');
      await AiConfig.setApiKey('sk-test-secret');
      final preferences = await SharedPreferences.getInstance();
      final stored = preferences.getString('ai_api_key_protected');
      expect(stored, isNotNull);
      expect(stored, startsWith('dpapi:v1:'));
      expect(stored, isNot(contains('sk-test-secret')));
      expect(await AiConfig.getApiKey(), 'sk-test-secret');

      await AiConfig.setApiKey('');
      expect(preferences.getString('ai_api_key_protected'), isNull);
      expect(preferences.getString('ai_api_key_endpoint'), isNull);

      await AiConfig.setApiKey('sk-test-secret');

      await AiConfig.setEndpointUrl('https://other-provider.example/');
      expect(await AiConfig.getApiKey(), isNull);
      await AiConfig.setEndpointUrl('https://provider.example/v1/');
      expect(await AiConfig.getApiKey(), isNull);

      await AiConfig.clearApiKey();
      expect(await AiConfig.getApiKey(), isNull);
    });

    test('scopes a selected model to its service endpoint', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});

      await AiConfig.setEndpointUrl('https://provider.example/v1/');
      await AiConfig.setModel('gpt-5.4-mini');
      expect(await AiConfig.getModel(), 'gpt-5.4-mini');

      final preferences = await SharedPreferences.getInstance();
      expect(
        preferences.getString('ai_model_endpoint'),
        'https://provider.example/v1/',
      );

      await AiConfig.setEndpointUrl('https://other-provider.example/v1/');
      expect(await AiConfig.getModel(), isEmpty);
      expect(preferences.getString('ai_model'), isNull);
      expect(preferences.getString('ai_model_endpoint'), isNull);

      await AiConfig.resetEndpointUrl();
      expect(await AiConfig.getModel(), AiConfig.defaultModel);
    });
  });
}
