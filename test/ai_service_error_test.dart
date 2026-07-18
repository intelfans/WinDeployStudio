import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:win_deploy_studio/features/ai_assistant/services/ai_service.dart';

void main() {
  group('AiService network error classification', () {
    test('adds Bearer authorization only for a valid configured key', () {
      expect(AiService.buildAuthorizationHeaders(null), isEmpty);
      expect(AiService.buildAuthorizationHeaders('sk-example\nvalue'), isEmpty);
      expect(AiService.buildAuthorizationHeaders(' sk-example-value '), {
        'Authorization': 'Bearer sk-example-value',
      });
    });

    test('classifies request timeout separately', () {
      expect(
        AiService.networkErrorKey(TimeoutException('request timed out')),
        'ai_error_timeout',
      );
    });

    test('classifies certificate-chain errors as TLS failures', () {
      expect(
        AiService.networkErrorKey(
          StateError('certificate verify failed: incomplete certificate chain'),
        ),
        'ai_error_tls',
      );
    });

    test('classifies unreachable network errors separately', () {
      expect(
        AiService.networkErrorKey(StateError('Connection refused')),
        'ai_error_unreachable',
      );
    });

    test('retries only transient network failures before an HTTP response', () {
      expect(
        AiService.shouldRetryTransportFailure(
          StateError('Connection terminated during handshake'),
        ),
        isFalse,
      );
      expect(
        AiService.shouldRetryTransportFailure(
          StateError('SocketException: errno = 121'),
        ),
        isTrue,
      );
      expect(
        AiService.shouldRetryTransportFailure(
          TimeoutException('response timed out'),
        ),
        isFalse,
      );
    });
  });
}
