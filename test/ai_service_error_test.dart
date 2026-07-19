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

    test('retries transient failures before an HTTP response', () {
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
        isTrue,
      );
    });

    test('accepts all successful HTTP status codes for compatible APIs', () {
      expect(AiService.isSuccessfulHttpStatusForTesting(200), isTrue);
      expect(AiService.isSuccessfulHttpStatusForTesting(201), isTrue);
      expect(AiService.isSuccessfulHttpStatusForTesting(204), isTrue);
      expect(AiService.isSuccessfulHttpStatusForTesting(299), isTrue);
      expect(AiService.isSuccessfulHttpStatusForTesting(300), isFalse);
      expect(AiService.isSuccessfulHttpStatusForTesting(400), isFalse);
    });

    test('uses a buffered chat fallback only for stream-shape rejections', () {
      expect(AiService.shouldFallbackToNonStreamingChatForTesting(400), isTrue);
      expect(AiService.shouldFallbackToNonStreamingChatForTesting(422), isTrue);
      expect(
        AiService.shouldFallbackToNonStreamingChatForTesting(401),
        isFalse,
      );
      expect(
        AiService.shouldFallbackToNonStreamingChatForTesting(429),
        isFalse,
      );
      expect(
        AiService.shouldFallbackToNonStreamingChatForTesting(500),
        isFalse,
      );
    });
  });
}
