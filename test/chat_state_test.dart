import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:win_deploy_studio/features/ai_assistant/models/chat_models.dart';
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
      isEmpty,
      reason: 'provider text must stay hidden until locally screened',
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

  test(
    'persists the provider-confirmed web-search status on the reply',
    () async {
      final service = _ControlledAiService();
      final notifier = ChatNotifier(
        service,
        loadHistory: false,
        persistHistory: false,
      );
      addTearDown(notifier.dispose);
      notifier.createNewSession();
      notifier.setSearchMode(SearchMode.force);

      final request = notifier.sendMessage('find current release notes');
      await _waitForRequests(service, 1);
      service.requests.single.addSearchStatus(AiSearchStatus.searching);
      expect(
        notifier.state.activeSession!.messages.last.searchStatus,
        AiSearchStatus.searching,
      );
      service.requests.single.addSearchStatus(AiSearchStatus.used);
      service.requests.single.complete();
      await request;

      expect(
        notifier.state.activeSession!.messages.last.searchStatus,
        AiSearchStatus.used,
      );
    },
  );

  test(
    'a single message can force search without changing the picker mode',
    () async {
      final service = _ControlledAiService();
      final notifier = ChatNotifier(
        service,
        loadHistory: false,
        persistHistory: false,
      );
      addTearDown(notifier.dispose);
      notifier.createNewSession();
      notifier.setSearchMode(SearchMode.off);

      final request = notifier.sendMessage(
        'search a current driver release',
        searchMode: SearchMode.force,
      );
      await _waitForRequests(service, 1);
      expect(service.requests.single.searchMode, SearchMode.force);
      service.requests.single.complete();
      await request;
    },
  );

  test('preserves streamed text when a later request error arrives', () async {
    final service = _ControlledAiService();
    final notifier = ChatNotifier(
      service,
      loadHistory: false,
      persistHistory: false,
    );
    addTearDown(notifier.dispose);
    notifier.createNewSession();

    final request = notifier.sendMessage('diagnose this');
    await _waitForRequests(service, 1);
    service.requests.single.addChunk('Useful partial diagnosis.');
    service.requests.single.addError('Network interrupted.');
    await request;

    final answer = notifier.state.activeSession!.messages.last;
    expect(answer.isStreaming, isFalse);
    expect(answer.content, contains('Useful partial diagnosis.'));
    expect(answer.content, contains('Network interrupted.'));
  });

  test('withholds safe provider output until screening completes', () async {
    final service = _ControlledAiService();
    final notifier = ChatNotifier(
      service,
      loadHistory: false,
      persistHistory: false,
    );
    addTearDown(notifier.dispose);
    notifier.createNewSession();

    final request = notifier.sendMessage('Explain Windows deployment');
    await _waitForRequests(service, 1);
    service.requests.single.addChunk('Use a verified Windows ISO.');

    expect(notifier.state.activeSession!.messages.last.content, isEmpty);
    expect(notifier.state.activeSession!.messages.last.isStreaming, isTrue);

    service.requests.single.complete();
    await request;

    expect(
      notifier.state.activeSession!.messages.last.content,
      'Use a verified Windows ISO.',
    );
  });

  test('blocks disallowed output and sources from any provider', () async {
    final service = _ControlledAiService();
    final notifier = ChatNotifier(
      service,
      loadHistory: false,
      persistHistory: false,
    );
    addTearDown(notifier.dispose);
    notifier.createNewSession();

    final request = notifier.sendMessage('third-party endpoint request');
    await _waitForRequests(service, 1);
    service.requests.single.addChunk(
      'A political election response that must never be displayed.',
    );
    service.requests.single.addSources([
      SearchSource(
        title: 'Political election source',
        url: 'https://example.com/election',
      ),
    ]);

    expect(notifier.state.activeSession!.messages.last.content, isEmpty);

    service.requests.single.complete();
    await request;

    final answer = notifier.state.activeSession!.messages.last;
    expect(answer.content, isNot(contains('political election')));
    expect(answer.content, contains('safety policy'));
    expect(answer.sources, isEmpty);
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
    required void Function(AiSearchStatus status) onSearchStatus,
    SearchMode searchMode = SearchMode.off,
    CancelToken? cancelToken,
  }) {
    final request = _ControlledRequest(
      onChunk: onChunk,
      onComplete: onComplete,
      onError: onError,
      onSources: onSources,
      onSearchStatus: onSearchStatus,
      searchMode: searchMode,
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
  final void Function(AiSearchStatus status) _onSearchStatus;
  final SearchMode searchMode;
  final CancelToken? cancelToken;
  final Completer<void> done = Completer<void>();

  _ControlledRequest({
    required this._onChunk,
    required this._onComplete,
    required this._onError,
    required this._onSources,
    required this._onSearchStatus,
    required this.searchMode,
    required this.cancelToken,
  });

  void addChunk(String chunk) => _onChunk(chunk);

  void addError(String error) {
    _onError(error);
    if (!done.isCompleted) done.complete();
  }

  void addSources(List<SearchSource> sources) => _onSources(sources);

  void addSearchStatus(AiSearchStatus status) => _onSearchStatus(status);

  void complete() {
    _onComplete();
    if (!done.isCompleted) done.complete();
  }
}
