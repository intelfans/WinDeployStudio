import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:win_deploy_studio/features/ai_assistant/providers/chat_provider.dart';
import 'package:win_deploy_studio/features/ai_assistant/services/ai_service.dart';

void main() {
  test('deleting the final session can clear the active session id', () {
    final state = ChatState(activeSessionId: 'removed');

    final cleared = state.copyWith(activeSessionId: null);

    expect(cleared.activeSessionId, isNull);
  });

  test('stopped stream callbacks cannot overwrite a later response', () async {
    final service = _ControlledAiService();
    final notifier = ChatNotifier(
      service,
      loadHistory: false,
      persistHistory: false,
    );
    addTearDown(notifier.dispose);
    notifier.createNewSession();

    final first = notifier.sendMessage('first request');
    await _waitForRequests(service, 1);
    service.requests[0].addChunk('partial old answer');
    expect(
      notifier.state.activeSession!.messages.last.content,
      'partial old answer',
    );

    notifier.stopGeneration();
    expect(service.requests[0].cancelToken?.cancelled, isTrue);
    expect(notifier.state.isGenerating, isFalse);
    expect(notifier.state.activeSession!.messages.last.isStreaming, isFalse);

    final second = notifier.sendMessage('second request');
    await _waitForRequests(service, 2);
    service.requests[0].addChunk(' must be ignored');
    service.requests[0].complete();

    expect(notifier.state.activeSession!.messages.last.content, isEmpty);
    expect(notifier.state.activeSession!.messages.last.isStreaming, isTrue);

    service.requests[1].addChunk('new answer');
    service.requests[1].complete();
    await Future.wait([first, second]);

    expect(notifier.state.isGenerating, isFalse);
    expect(notifier.state.activeSession!.messages.last.content, 'new answer');
    expect(notifier.state.activeSession!.messages.last.isStreaming, isFalse);
  });

  test('switching sessions invalidates an active stream', () async {
    final service = _ControlledAiService();
    final notifier = ChatNotifier(
      service,
      loadHistory: false,
      persistHistory: false,
    );
    addTearDown(notifier.dispose);
    notifier.createNewSession();
    final firstSessionId = notifier.state.activeSessionId!;

    final request = notifier.sendMessage('session one');
    await _waitForRequests(service, 1);
    notifier.createNewSession();
    final secondSessionId = notifier.state.activeSessionId!;

    service.requests.single.addChunk('late content');
    service.requests.single.complete();
    await request;

    expect(secondSessionId, isNot(firstSessionId));
    expect(notifier.state.activeSessionId, secondSessionId);
    expect(notifier.state.activeSession!.messages, isEmpty);
    final firstSession = notifier.state.sessions.firstWhere(
      (session) => session.id == firstSessionId,
    );
    expect(firstSession.messages.last.content, isEmpty);
    expect(firstSession.messages.last.isStreaming, isFalse);
  });
}

Future<void> _waitForRequests(_ControlledAiService service, int count) async {
  for (
    var attempt = 0;
    attempt < 20 && service.requests.length < count;
    attempt++
  ) {
    await Future<void>.delayed(Duration.zero);
  }
  expect(service.requests, hasLength(count));
}

class _ControlledAiService implements AiMessageService {
  final List<_ControlledRequest> requests = [];

  @override
  Future<void> sendMessage({
    required List<Map<String, String>> messages,
    required void Function(String chunk) onChunk,
    required void Function() onComplete,
    required void Function(String error) onError,
    required void Function(List<SearchSource> sources) onSources,
    SearchMode searchMode = SearchMode.off,
    CancelToken? cancelToken,
  }) {
    final request = _ControlledRequest(
      onChunk: onChunk,
      onComplete: onComplete,
      onError: onError,
      onSources: onSources,
      cancelToken: cancelToken,
    );
    requests.add(request);
    return request.done.future;
  }
}

class _ControlledRequest {
  final void Function(String chunk) _onChunk;
  final void Function() _onComplete;
  final void Function(String error) _onError;
  final void Function(List<SearchSource> sources) _onSources;
  final CancelToken? cancelToken;
  final Completer<void> done = Completer<void>();

  _ControlledRequest({
    required this._onChunk,
    required this._onComplete,
    required this._onError,
    required this._onSources,
    required this.cancelToken,
  });

  void addChunk(String chunk) => _onChunk(chunk);

  void addError(String error) => _onError(error);

  void addSources(List<SearchSource> sources) => _onSources(sources);

  void complete() {
    _onComplete();
    if (!done.isCompleted) done.complete();
  }
}
