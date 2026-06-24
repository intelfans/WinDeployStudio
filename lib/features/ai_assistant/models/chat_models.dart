import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../../../core/localization/strings.dart';

class ChatMessage {
  final String id;
  final String role; // 'user', 'assistant', 'system'
  final String content;
  final DateTime timestamp;
  final bool isStreaming;
  final List<Map<String, String>> sources;

  ChatMessage({
    String? id,
    required this.role,
    required this.content,
    DateTime? timestamp,
    this.isStreaming = false,
    this.sources = const [],
  })  : id = id ?? const Uuid().v4(),
        timestamp = timestamp ?? DateTime.now();

  ChatMessage copyWith({
    String? content,
    bool? isStreaming,
    List<Map<String, String>>? sources,
  }) {
    return ChatMessage(
      id: id,
      role: role,
      content: content ?? this.content,
      timestamp: timestamp,
      isStreaming: isStreaming ?? this.isStreaming,
      sources: sources ?? this.sources,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'role': role,
        'content': content,
        'timestamp': timestamp.toIso8601String(),
        if (sources.isNotEmpty) 'sources': sources,
      };

  factory ChatMessage.fromJson(Map<String, dynamic> json) => ChatMessage(
        id: json['id'] as String? ?? '',
        role: json['role'] as String? ?? 'assistant',
        content: json['content'] as String? ?? '',
        timestamp: DateTime.tryParse(json['timestamp'] as String? ?? '') ?? DateTime.now(),
        sources: json['sources'] != null
            ? List<Map<String, String>>.from(
                (json['sources'] as List).map((s) => Map<String, String>.from(s)))
            : const [],
      );

  String get apiRole => role;
}

class ChatSession {
  final String id;
  final String title;
  final List<ChatMessage> messages;
  final DateTime createdAt;
  final DateTime updatedAt;

  ChatSession({
    String? id,
    required this.title,
    List<ChatMessage>? messages,
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : id = id ?? const Uuid().v4(),
        messages = messages ?? [],
        createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  ChatSession copyWith({
    String? title,
    List<ChatMessage>? messages,
    DateTime? updatedAt,
  }) {
    return ChatSession(
      id: id,
      title: title ?? this.title,
      messages: messages ?? this.messages,
      createdAt: createdAt,
      updatedAt: updatedAt ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'messages': messages.map((m) => m.toJson()).toList(),
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
      };

  factory ChatSession.fromJson(Map<String, dynamic> json) => ChatSession(
        id: json['id'] as String? ?? '',
        title: json['title'] as String? ?? '',
        messages: (json['messages'] as List?)
            ?.map((m) => ChatMessage.fromJson(m as Map<String, dynamic>))
            .toList() ?? [],
        createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ?? DateTime.now(),
        updatedAt: DateTime.tryParse(json['updatedAt'] as String? ?? '') ?? DateTime.now(),
      );
}

String getSystemPrompt(BuildContext context) => tr(context, 'ai_prompt_system');

String getAnalyzePromptPrefix(BuildContext context) => tr(context, 'ai_prompt_analyze_prefix');

String buildAnalyzeLogsPrompt(BuildContext context, String logContent) {
  return '${getAnalyzePromptPrefix(context)}${tr(context, 'ai_prompt_log_content')}\n$logContent';
}

String buildAnalyzeIsoPrompt(BuildContext context, Map<String, String> isoInfo) {
  final buffer = StringBuffer(getAnalyzePromptPrefix(context));
  buffer.writeln(tr(context, 'ai_prompt_iso_info'));
  isoInfo.forEach((key, value) {
    buffer.writeln('$key: $value');
  });
  return buffer.toString();
}

String buildAnalyzeUsbPrompt(BuildContext context, Map<String, String> usbInfo) {
  final buffer = StringBuffer(getAnalyzePromptPrefix(context));
  buffer.writeln(tr(context, 'ai_prompt_usb_info'));
  usbInfo.forEach((key, value) {
    buffer.writeln('$key: $value');
  });
  return buffer.toString();
}

String buildDiagnosePrompt(BuildContext context, {
  required String logsSummary,
  String? isoInfo,
  String? usbInfo,
  String? taskStatus,
}) {
  final buffer = StringBuffer(tr(context, 'ai_prompt_diagnose_prefix'));
  buffer.writeln('${tr(context, 'ai_prompt_log_summary')}\n$logsSummary');
  if (isoInfo != null) buffer.writeln('\n${tr(context, 'ai_prompt_iso_info')}\n$isoInfo');
  if (usbInfo != null) buffer.writeln('\n${tr(context, 'ai_prompt_usb_info')}\n$usbInfo');
  if (taskStatus != null) buffer.writeln('\n${tr(context, 'ai_prompt_task_status')}\n$taskStatus');
  buffer.writeln('\n${tr(context, 'ai_prompt_diagnose_suffix')}');
  return buffer.toString();
}
