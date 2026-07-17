import 'package:flutter_test/flutter_test.dart';
import 'package:win_deploy_studio/features/ai_assistant/services/ai_system_proxy_resolver.dart';

void main() {
  group('AiSystemProxyResolver Windows settings parser', () {
    test('uses a standard single HTTPS proxy', () {
      expect(
        AiSystemProxyResolver.windowsProxyInstruction(
          proxyEnabledOutput: 'ProxyEnable    REG_DWORD    0x1',
          proxyServerOutput: 'ProxyServer    REG_SZ    127.0.0.1:7890',
          scheme: 'https',
        ),
        'PROXY 127.0.0.1:7890',
      );
    });

    test('selects HTTPS from a protocol-specific proxy value', () {
      expect(
        AiSystemProxyResolver.windowsProxyInstruction(
          proxyEnabledOutput: 'ProxyEnable    REG_DWORD    0x1',
          proxyServerOutput:
              'ProxyServer    REG_SZ    http=127.0.0.1:8080;https=proxy.example:8443',
          scheme: 'https',
        ),
        'PROXY proxy.example:8443',
      );
    });

    test('ignores disabled and malformed proxy values', () {
      expect(
        AiSystemProxyResolver.windowsProxyInstruction(
          proxyEnabledOutput: 'ProxyEnable    REG_DWORD    0x0',
          proxyServerOutput: 'ProxyServer    REG_SZ    127.0.0.1:7890',
          scheme: 'https',
        ),
        isNull,
      );
      expect(
        AiSystemProxyResolver.windowsProxyInstruction(
          proxyEnabledOutput: 'ProxyEnable    REG_DWORD    0x1',
          proxyServerOutput: 'ProxyServer    REG_SZ    user:pass@proxy:7890',
          scheme: 'https',
        ),
        isNull,
      );
    });

    test(
      'recognizes only loopback HTTP CONNECT proxies for stale detection',
      () {
        expect(
          AiSystemProxyResolver.loopbackProxyEndpoint('PROXY 127.0.0.1:7890'),
          (host: '127.0.0.1', port: 7890),
        );
        expect(
          AiSystemProxyResolver.isLoopbackProxyInstruction('PROXY [::1]:7890'),
          isTrue,
        );
        expect(
          AiSystemProxyResolver.isLoopbackProxyInstruction(
            'PROXY localhost:7890; DIRECT',
          ),
          isTrue,
        );
        expect(
          AiSystemProxyResolver.isLoopbackProxyInstruction(
            'PROXY proxy.example:8443',
          ),
          isFalse,
        );
      },
    );
  });
}
