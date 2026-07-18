import 'package:flutter_test/flutter_test.dart';
import 'package:win_deploy_studio/features/ai_assistant/services/ai_system_proxy_resolver.dart';

void main() {
  group('AiSystemNetworkResolver route parser', () {
    test('returns a safe route from the active system configuration', () async {
      final route = await AiSystemNetworkResolver.resolveFor(
        Uri.parse('https://service.example/v1/chat/completions'),
      );

      expect(
        route.instruction == 'DIRECT' || route.instruction.startsWith('PROXY '),
        isTrue,
      );
    });

    test('keeps an explicit direct system route', () {
      expect(
        AiSystemNetworkResolver.systemRouteInstruction('DIRECT'),
        'DIRECT',
      );
    });

    test('converts a standard system route to an HTTP CONNECT directive', () {
      expect(
        AiSystemNetworkResolver.systemRouteInstruction(
          'http://network.example:8443/',
        ),
        'PROXY network.example:8443',
      );
      expect(
        AiSystemNetworkResolver.systemRouteInstruction(
          'http://[2001:db8::1]:8080/',
        ),
        'PROXY [2001:db8::1]:8080',
      );
    });

    test('rejects unsafe or unsupported system route values', () {
      expect(AiSystemNetworkResolver.systemRouteInstruction(''), isNull);
      expect(
        AiSystemNetworkResolver.systemRouteInstruction(
          'http://user:pass@network.example:8080/',
        ),
        isNull,
      );
      expect(
        AiSystemNetworkResolver.systemRouteInstruction(
          'socks5://network.example:1080/',
        ),
        isNull,
      );
      expect(
        AiSystemNetworkResolver.systemRouteInstruction(
          'https://network.example:8443/',
        ),
        isNull,
      );
      expect(
        AiSystemNetworkResolver.systemRouteInstruction(
          'http://network.example:8080/path',
        ),
        isNull,
      );
    });
  });
}
