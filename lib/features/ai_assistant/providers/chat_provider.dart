import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:path/path.dart' as p;
import '../../../core/constants/app_constants.dart';
import '../../../core/localization/strings.dart';
import '../../../core/services/user_data_protection_service.dart';
import '../../../core/utils/keyed_async_queue.dart';
import '../models/chat_models.dart';
import '../services/ai_output_safety_filter.dart';
import '../services/ai_service.dart';
import '../../logs/services/log_center_service.dart';

class ChatState {
  static const Object _unset = Object();

  final List<ChatSession> sessions;
  final String? activeSessionId;
  final bool isGenerating;
  final SearchMode searchMode;

  ChatState({
    this.sessions = const [],
    this.activeSessionId,
    this.isGenerating = false,
    this.searchMode = SearchMode.auto,
  });

  ChatSession? get activeSession {
    if (activeSessionId == null) return null;
    return sessions.where((s) => s.id == activeSessionId).firstOrNull;
  }

  bool get canSend => !isGenerating;

  ChatState copyWith({
    List<ChatSession>? sessions,
    Object? activeSessionId = _unset,
    bool? isGenerating,
    SearchMode? searchMode,
  }) {
    return ChatState(
      sessions: sessions ?? this.sessions,
      activeSessionId: identical(activeSessionId, _unset)
          ? this.activeSessionId
          : activeSessionId as String?,
      isGenerating: isGenerating ?? this.isGenerating,
      searchMode: searchMode ?? this.searchMode,
    );
  }
}

class ChatNotifier extends StateNotifier<ChatState> {
  final AiMessageService _aiService;
  final bool persistHistory;
  CancelToken? _cancelToken;
  _ChatGeneration? _activeGeneration;
  int _generationRequest = 0;
  bool _disposed = false;
  final KeyedAsyncQueue<String> _historyOperations = KeyedAsyncQueue();

  ChatNotifier(
    this._aiService, {
    bool loadHistory = true,
    this.persistHistory = true,
  }) : super(ChatState()) {
    if (loadHistory) unawaited(_loadSessions());
  }

  String get _storageDir {
    return p.join(AppConstants.appDataPath, 'WinDeployStudio', 'chat_history');
  }

  Future<void> _loadSessions() async {
    try {
      final dir = Directory(_storageDir);
      if (!dir.existsSync()) {
        dir.createSync(recursive: true);
        return;
      }

      final files =
          dir
              .listSync()
              .whereType<File>()
              .where(
                (file) =>
                    file.path.endsWith('.chat') || file.path.endsWith('.json'),
              )
              .toList()
            ..sort((left, right) {
              final leftPriority = left.path.endsWith('.chat') ? 0 : 1;
              final rightPriority = right.path.endsWith('.chat') ? 0 : 1;
              return leftPriority.compareTo(rightPriority);
            });
      final sessionsById = <String, ChatSession>{};
      for (final file in files) {
        try {
          final stored = await file.readAsString();
          final content = file.path.endsWith('.chat')
              ? await UserDataProtectionService.unprotect(stored)
              : stored;
          final json = jsonDecode(content) as Map<String, dynamic>;
          final session = ChatSession.fromJson(json);
          if (file.path.endsWith('.json')) {
            final encryptedCopy = sessionsById[session.id];
            final plaintextIsNewer =
                encryptedCopy == null ||
                session.updatedAt.isAfter(encryptedCopy.updatedAt);
            if (plaintextIsNewer && !await _saveSession(session)) {
              sessionsById[session.id] = session;
              continue;
            }
            if (encryptedCopy != null && !plaintextIsNewer) {
              sessionsById[session.id] = encryptedCopy;
            } else {
              sessionsById[session.id] = session;
            }
            if (encryptedCopy != null || plaintextIsNewer) {
              await _deleteHistoryFile(file, action: 'Migration cleanup');
            }
          }
          if (file.path.endsWith('.chat')) {
            sessionsById[session.id] = session;
          }
        } catch (error) {
          await _logHistoryError('Load', file, error);
        }
      }

      for (final session in state.sessions) {
        sessionsById[session.id] = session;
      }
      final sessions = sessionsById.values.toList();
      sessions.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      final retained = sessions.take(50).toList();
      final retainedIds = retained.map((session) => session.id).toSet();
      for (final file in dir.listSync().whereType<File>()) {
        final id = p.basenameWithoutExtension(file.path);
        if ((file.path.endsWith('.chat') || file.path.endsWith('.json')) &&
            !retainedIds.contains(id)) {
          await _deleteHistoryFile(file, action: 'Retention cleanup');
        }
      }
      if (_disposed) return;
      state = state.copyWith(sessions: retained);
    } catch (error) {
      await LogCenterService().logError(
        '[ChatHistory] Load directory failed: $error',
      );
    }
  }

  Future<bool> _saveSession(ChatSession session) async {
    if (!persistHistory) return true;
    return _historyOperations.run(session.id, () async {
      try {
        final dir = Directory(_storageDir);
        if (!dir.existsSync()) dir.createSync(recursive: true);
        final file = File(p.join(_storageDir, '${session.id}.chat'));
        final protected = await UserDataProtectionService.protect(
          jsonEncode(session.toJson()),
        );
        await file.writeAsString(protected, flush: true);
        return true;
      } catch (error) {
        await LogCenterService().logError(
          '[ChatHistory] Save failed for ${session.id}: $error',
        );
        return false;
      }
    });
  }

  Future<void> _deleteSessionFile(String sessionId) async {
    await _historyOperations.run(sessionId, () async {
      for (final extension in ['chat', 'json']) {
        final file = File(p.join(_storageDir, '$sessionId.$extension'));
        if (file.existsSync()) {
          await _deleteHistoryFile(file, action: 'Delete');
        }
      }
    });
  }

  Future<void> _deleteHistoryFile(File file, {required String action}) async {
    try {
      if (await file.exists()) await file.delete();
    } catch (error) {
      await _logHistoryError(action, file, error);
    }
  }

  Future<void> _logHistoryError(String action, File file, Object error) {
    return LogCenterService().logError(
      '[ChatHistory] $action failed for ${p.basename(file.path)}: $error',
    );
  }

  void createNewSession() {
    _cancelActiveGeneration();
    final session = ChatSession(title: trCurrent('ai_new_chat'));
    final sessions = [session, ...state.sessions];
    state = state.copyWith(
      sessions: sessions.take(50).toList(),
      activeSessionId: session.id,
    );
    unawaited(_saveSession(session));
  }

  void selectSession(String sessionId) {
    if (state.activeSessionId != sessionId) {
      _cancelActiveGeneration();
    }
    state = state.copyWith(activeSessionId: sessionId);
  }

  void deleteSession(String sessionId) {
    final deletingActiveGeneration = _activeGeneration?.sessionId == sessionId;
    if (deletingActiveGeneration) {
      _cancelActiveGeneration(save: false);
    }
    final sessions = state.sessions.where((s) => s.id != sessionId).toList();
    final newActiveId = state.activeSessionId == sessionId
        ? (sessions.isNotEmpty ? sessions.first.id : null)
        : state.activeSessionId;
    state = state.copyWith(sessions: sessions, activeSessionId: newActiveId);
    unawaited(_deleteSessionFile(sessionId));
  }

  void setSearchMode(SearchMode mode) {
    state = state.copyWith(searchMode: mode);
  }

  Future<void> sendMessage(
    String content, {
    String? systemPrompt,
    SearchMode? searchMode,
  }) async {
    if (state.isGenerating) return;
    if (content.trim().isEmpty) return;

    var session = state.activeSession;
    if (session == null) {
      createNewSession();
      session = state.activeSession;
      if (session == null) return;
    }

    final userMessage = ChatMessage(role: 'user', content: content);
    final updatedMessages = [...session.messages, userMessage];
    var updatedSession = session.copyWith(
      messages: updatedMessages,
      updatedAt: DateTime.now(),
    );

    if (session.messages.isEmpty) {
      final title = content.length > 30
          ? '${content.substring(0, 30)}...'
          : content;
      updatedSession = updatedSession.copyWith(title: title);
    }

    _updateSession(updatedSession);

    final selectedSearchMode = searchMode ?? state.searchMode;

    final assistantMessage = ChatMessage(
      role: 'assistant',
      content: '',
      isStreaming: true,
      searchStatus: selectedSearchMode == SearchMode.off
          ? AiSearchStatus.none
          : AiSearchStatus.requested,
    );
    final withAssistant = [...updatedSession.messages, assistantMessage];
    _updateSession(updatedSession.copyWith(messages: withAssistant));

    final cancelToken = CancelToken();
    final generation = _ChatGeneration(
      id: ++_generationRequest,
      sessionId: updatedSession.id,
      messageId: assistantMessage.id,
      cancelToken: cancelToken,
    );
    _activeGeneration = generation;
    _cancelToken = cancelToken;
    state = state.copyWith(isGenerating: true);

    final apiMessages = [
      {
        'role': 'system',
        'content': systemPrompt ?? 'You are WinDeploy AI assistant.',
      },
      ...updatedMessages.map((m) => {'role': m.apiRole, 'content': m.content}),
    ];

    try {
      await _aiService.sendMessage(
        messages: apiMessages,
        cancelToken: cancelToken,
        searchMode: selectedSearchMode,
        onChunk: (chunk) {
          if (!_isCurrentGeneration(generation)) return;
          generation.buffer += chunk;
          // Do not expose provider text until the complete response has
          // passed the local safety policy. This applies equally to the
          // bundled endpoint and every custom OpenAI-compatible endpoint.
        },
        onSources: (sources) {
          if (!_isCurrentGeneration(generation)) return;
          generation.sources = sources
              .map((source) => {'title': source.title, 'url': source.url})
              .toList();
        },
        onSearchStatus: (status) {
          if (!_isCurrentGeneration(generation)) return;
          _updateMessage(
            sessionId: generation.sessionId,
            messageId: generation.messageId,
            searchStatus: status,
          );
        },
        onComplete: () {
          if (!_isCurrentGeneration(generation)) return;
          final screened = _screenAssistantOutput(
            generation.buffer,
            sources: generation.sources,
          );
          _updateMessage(
            sessionId: generation.sessionId,
            messageId: generation.messageId,
            content: screened.content,
            isStreaming: false,
            sources: screened.blocked ? const [] : generation.sources,
          );
          _finishGeneration(generation);
        },
        onError: (error) {
          if (!_isCurrentGeneration(generation)) return;
          final partialResponse = generation.buffer.trimRight();
          final combined = partialResponse.isEmpty
              ? '${trCurrent('creator_error')}: $error'
              : '$partialResponse\n\n${trCurrent('creator_error')}: $error';
          final screened = _screenAssistantOutput(
            combined,
            sources: generation.sources,
          );
          _updateMessage(
            sessionId: generation.sessionId,
            messageId: generation.messageId,
            content: screened.content,
            isStreaming: false,
            sources: screened.blocked ? const [] : generation.sources,
          );
          _finishGeneration(generation);
        },
      );
    } catch (error) {
      if (!_isCurrentGeneration(generation)) return;
      final screened = _screenAssistantOutput(
        '${trCurrent('creator_error')}: $error',
      );
      _updateMessage(
        sessionId: generation.sessionId,
        messageId: generation.messageId,
        content: screened.content,
        isStreaming: false,
      );
      _finishGeneration(generation);
    }
  }

  void stopGeneration() {
    _cancelActiveGeneration();
  }

  ({String content, bool blocked}) _screenAssistantOutput(
    String content, {
    List<Map<String, String>> sources = const [],
  }) {
    final sourceText = sources.expand((source) => source.values);
    final blocked =
        AiOutputSafetyFilter.blocks(content) ||
        AiOutputSafetyFilter.blocksAny(sourceText);
    return (
      content: blocked ? trCurrent('ai_output_safety_blocked') : content,
      blocked: blocked,
    );
  }

  void _updateSession(ChatSession session) {
    final sessions = state.sessions
        .map((s) => s.id == session.id ? session : s)
        .toList();
    state = state.copyWith(sessions: sessions);
  }

  bool _isCurrentGeneration(_ChatGeneration generation) {
    return !_disposed &&
        identical(_activeGeneration, generation) &&
        generation.id == _generationRequest &&
        state.isGenerating &&
        state.activeSessionId == generation.sessionId;
  }

  void _finishGeneration(_ChatGeneration generation) {
    if (!identical(_activeGeneration, generation) || _disposed) return;
    _activeGeneration = null;
    if (identical(_cancelToken, generation.cancelToken)) {
      _cancelToken = null;
    }
    state = state.copyWith(isGenerating: false);
    _saveSessionById(generation.sessionId);
  }

  void _cancelActiveGeneration({bool save = true}) {
    final generation = _activeGeneration;
    _generationRequest++;
    _activeGeneration = null;
    _cancelToken = null;
    generation?.cancelToken.cancel();

    if (generation != null && !_disposed) {
      final screened = _screenAssistantOutput(
        generation.buffer,
        sources: generation.sources,
      );
      _updateMessage(
        sessionId: generation.sessionId,
        messageId: generation.messageId,
        content: screened.content,
        isStreaming: false,
        sources: screened.blocked ? const [] : generation.sources,
      );
    }
    if (!_disposed && state.isGenerating) {
      state = state.copyWith(isGenerating: false);
    }
    if (generation != null && save && !_disposed) {
      _saveSessionById(generation.sessionId);
    }
  }

  void _updateMessage({
    required String sessionId,
    required String messageId,
    String? content,
    bool? isStreaming,
    List<Map<String, String>>? sources,
    AiSearchStatus? searchStatus,
  }) {
    final sessionIndex = state.sessions.indexWhere(
      (session) => session.id == sessionId,
    );
    if (sessionIndex < 0) return;
    final session = state.sessions[sessionIndex];
    final messageIndex = session.messages.indexWhere(
      (message) => message.id == messageId,
    );
    if (messageIndex < 0) return;

    final messages = [...session.messages];
    messages[messageIndex] = messages[messageIndex].copyWith(
      content: content,
      isStreaming: isStreaming,
      sources: sources,
      searchStatus: searchStatus,
    );
    _updateSession(
      session.copyWith(messages: messages, updatedAt: DateTime.now()),
    );
  }

  void _saveSessionById(String sessionId) {
    final session = state.sessions
        .where((candidate) => candidate.id == sessionId)
        .firstOrNull;
    if (session != null) unawaited(_saveSession(session));
  }

  void clearActiveSession() {
    final session = state.activeSession;
    if (session == null) return;
    if (_activeGeneration?.sessionId == session.id) {
      _cancelActiveGeneration(save: false);
    }
    final cleared = session.copyWith(messages: [], updatedAt: DateTime.now());
    _updateSession(cleared);
    unawaited(_saveSession(cleared));
  }

  @override
  void dispose() {
    _cancelActiveGeneration(save: false);
    _disposed = true;
    super.dispose();
  }
}

class _ChatGeneration {
  final int id;
  final String sessionId;
  final String messageId;
  final CancelToken cancelToken;
  String buffer = '';
  List<Map<String, String>> sources = const [];

  _ChatGeneration({
    required this.id,
    required this.sessionId,
    required this.messageId,
    required this.cancelToken,
  });
}

final aiServiceProvider = Provider<AiService>((ref) => AiService());

final chatProvider = StateNotifierProvider<ChatNotifier, ChatState>((ref) {
  return ChatNotifier(ref.read(aiServiceProvider));
});
