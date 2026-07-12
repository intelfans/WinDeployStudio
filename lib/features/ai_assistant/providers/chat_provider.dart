import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:path/path.dart' as p;
import '../../../core/constants/app_constants.dart';
import '../../../core/localization/strings.dart';
import '../../../core/services/user_data_protection_service.dart';
import '../models/chat_models.dart';
import '../services/ai_service.dart';
import '../../logs/services/log_center_service.dart';

class ChatState {
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
    String? activeSessionId,
    bool? isGenerating,
    SearchMode? searchMode,
  }) {
    return ChatState(
      sessions: sessions ?? this.sessions,
      activeSessionId: activeSessionId ?? this.activeSessionId,
      isGenerating: isGenerating ?? this.isGenerating,
      searchMode: searchMode ?? this.searchMode,
    );
  }
}

class ChatNotifier extends StateNotifier<ChatState> {
  final AiService _aiService;
  CancelToken? _cancelToken;
  String _streamBuffer = '';

  ChatNotifier(this._aiService) : super(ChatState()) {
    unawaited(_loadSessions());
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
      state = state.copyWith(sessions: retained);
    } catch (error) {
      await LogCenterService().logError(
        '[ChatHistory] Load directory failed: $error',
      );
    }
  }

  Future<bool> _saveSession(ChatSession session) async {
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
  }

  Future<void> _deleteSessionFile(String sessionId) async {
    for (final extension in ['chat', 'json']) {
      final file = File(p.join(_storageDir, '$sessionId.$extension'));
      if (file.existsSync()) {
        await _deleteHistoryFile(file, action: 'Delete');
      }
    }
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
    final session = ChatSession(title: trCurrent('ai_new_chat'));
    final sessions = [session, ...state.sessions];
    state = state.copyWith(
      sessions: sessions.take(50).toList(),
      activeSessionId: session.id,
    );
    unawaited(_saveSession(session));
  }

  void selectSession(String sessionId) {
    state = state.copyWith(activeSessionId: sessionId);
  }

  void deleteSession(String sessionId) {
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

  Future<void> sendMessage(String content, {String? systemPrompt}) async {
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

    final assistantMessage = ChatMessage(
      role: 'assistant',
      content: '',
      isStreaming: true,
    );
    final withAssistant = [...updatedSession.messages, assistantMessage];
    _updateSession(updatedSession.copyWith(messages: withAssistant));

    state = state.copyWith(isGenerating: true);
    _streamBuffer = '';
    _cancelToken = CancelToken();

    final apiMessages = [
      {
        'role': 'system',
        'content': systemPrompt ?? 'You are WinDeploy AI assistant.',
      },
      ...updatedMessages.map((m) => {'role': m.apiRole, 'content': m.content}),
    ];

    await _aiService.sendMessage(
      messages: apiMessages,
      cancelToken: _cancelToken,
      searchMode: state.searchMode,
      onChunk: (chunk) {
        _streamBuffer += chunk;
        _updateLastMessage(_streamBuffer, isStreaming: true);
      },
      onSources: (sources) {
        final sourceMaps = sources
            .map((s) => {'title': s.title, 'url': s.url})
            .toList();
        _updateLastMessageSources(sourceMaps);
      },
      onComplete: () {
        _updateLastMessage(_streamBuffer, isStreaming: false);
        state = state.copyWith(isGenerating: false);
        _saveCurrentSession();
      },
      onError: (error) {
        _updateLastMessage(
          '${trCurrent('creator_error')}: $error',
          isStreaming: false,
        );
        state = state.copyWith(isGenerating: false);
        _saveCurrentSession();
      },
    );
  }

  void stopGeneration() {
    _cancelToken?.cancel();
    state = state.copyWith(isGenerating: false);
    _saveCurrentSession();
  }

  void _updateSession(ChatSession session) {
    final sessions = state.sessions
        .map((s) => s.id == session.id ? session : s)
        .toList();
    state = state.copyWith(sessions: sessions);
  }

  void _updateLastMessage(String content, {required bool isStreaming}) {
    final session = state.activeSession;
    if (session == null || session.messages.isEmpty) return;

    final lastMsg = session.messages.last;
    final updated = lastMsg.copyWith(
      content: content,
      isStreaming: isStreaming,
    );
    final messages = [
      ...session.messages.sublist(0, session.messages.length - 1),
      updated,
    ];
    _updateSession(
      session.copyWith(messages: messages, updatedAt: DateTime.now()),
    );
  }

  void _updateLastMessageSources(List<Map<String, String>> sources) {
    final session = state.activeSession;
    if (session == null || session.messages.isEmpty) return;

    final lastMsg = session.messages.last;
    final updated = lastMsg.copyWith(sources: sources);
    final messages = [
      ...session.messages.sublist(0, session.messages.length - 1),
      updated,
    ];
    _updateSession(
      session.copyWith(messages: messages, updatedAt: DateTime.now()),
    );
  }

  void _saveCurrentSession() {
    final session = state.activeSession;
    if (session != null) unawaited(_saveSession(session));
  }

  void clearActiveSession() {
    final session = state.activeSession;
    if (session == null) return;
    final cleared = session.copyWith(messages: [], updatedAt: DateTime.now());
    _updateSession(cleared);
    unawaited(_saveSession(cleared));
  }
}

final aiServiceProvider = Provider<AiService>((ref) => AiService());

final chatProvider = StateNotifierProvider<ChatNotifier, ChatState>((ref) {
  return ChatNotifier(ref.read(aiServiceProvider));
});
