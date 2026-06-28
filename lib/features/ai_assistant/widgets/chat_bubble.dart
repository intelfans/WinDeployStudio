import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:markdown/markdown.dart' as md;
import '../../../core/localization/strings.dart';
import '../../../shared/webview/webview_helper.dart';
import '../models/chat_models.dart';

class ChatBubble extends StatelessWidget {
  final ChatMessage message;

  const ChatBubble({super.key, required this.message});

  @override
  Widget build(BuildContext context) {
    final isUser = message.role == 'user';
    final colorScheme = Theme.of(context).colorScheme;

    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.75,
        ),
        margin: EdgeInsets.only(
          left: isUser ? 48 : 0,
          right: isUser ? 0 : 48,
          top: 4,
          bottom: 4,
        ),
        child: Column(
          crossAxisAlignment: isUser
              ? CrossAxisAlignment.end
              : CrossAxisAlignment.start,
          children: [
            if (!isUser)
              Padding(
                padding: const EdgeInsets.only(bottom: 4, left: 4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.auto_awesome_rounded,
                      size: 14,
                      color: colorScheme.primary,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'WinDeploy AI',
                      style: TextStyle(
                        fontSize: 11,
                        color: colorScheme.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            Material(
              color: isUser
                  ? colorScheme.primaryContainer
                  : colorScheme.surfaceContainerHigh,
              borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(16),
                topRight: const Radius.circular(16),
                bottomLeft: Radius.circular(isUser ? 16 : 4),
                bottomRight: Radius.circular(isUser ? 4 : 16),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                child: message.content.isEmpty && message.isStreaming
                    ? _buildTypingIndicator(context, colorScheme)
                    : _buildContent(context, colorScheme),
              ),
            ),
            if (!isUser && !message.isStreaming)
              Padding(
                padding: const EdgeInsets.only(top: 4, left: 4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    GestureDetector(
                      onTap: () {
                        Clipboard.setData(ClipboardData(text: message.content));
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(tr(context, 'copied')),
                            duration: const Duration(seconds: 1),
                          ),
                        );
                      },
                      child: Icon(
                        Icons.copy_rounded,
                        size: 14,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            if (!isUser && message.sources.isNotEmpty) ...[
              const SizedBox(height: 8),
              _SourcesWidget(sources: message.sources),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildTypingIndicator(BuildContext context, ColorScheme colorScheme) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: colorScheme.primary,
          ),
        ),
        const SizedBox(width: 8),
        Text(
          tr(context, 'ai_thinking'),
          style: TextStyle(fontSize: 13, color: colorScheme.onSurfaceVariant),
        ),
      ],
    );
  }

  Widget _buildContent(BuildContext context, ColorScheme colorScheme) {
    return MarkdownBody(
      data: message.content,
      selectable: true,
      extensionSet: md.ExtensionSet.gitHubFlavored,
      styleSheet: MarkdownStyleSheet(
        p: TextStyle(fontSize: 14, color: colorScheme.onSurface, height: 1.5),
        code: TextStyle(
          fontSize: 13,
          color: colorScheme.onSurface,
          backgroundColor: colorScheme.surfaceContainerHighest,
          fontFamily: 'monospace',
        ),
        codeblockDecoration: BoxDecoration(
          color: colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: colorScheme.outlineVariant),
        ),
        codeblockPadding: const EdgeInsets.all(12),
        h1: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.bold,
          color: colorScheme.onSurface,
        ),
        h2: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.bold,
          color: colorScheme.onSurface,
        ),
        h3: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          color: colorScheme.onSurface,
        ),
        blockquoteDecoration: BoxDecoration(
          border: Border(
            left: BorderSide(color: colorScheme.primary, width: 3),
          ),
        ),
        blockquotePadding: const EdgeInsets.only(left: 12),
        tableBorder: TableBorder.all(color: colorScheme.outlineVariant),
        tableHead: TextStyle(
          fontWeight: FontWeight.w600,
          color: colorScheme.onSurface,
        ),
        tableBody: TextStyle(color: colorScheme.onSurface),
        listBullet: TextStyle(color: colorScheme.onSurface),
      ),
      onTapLink: (text, href, title) {
        if (href != null) {
          final ctx = context;
          if (ctx.mounted) WebviewHelper.openUrl(ctx, href);
        }
      },
    );
  }
}

class _SourcesWidget extends StatelessWidget {
  final List<Map<String, String>> sources;
  const _SourcesWidget({required this.sources});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.link_rounded, size: 14, color: colorScheme.primary),
              const SizedBox(width: 4),
              Text(
                tr(context, 'ai_sources'),
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: colorScheme.primary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ...sources.map(
            (s) => Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: GestureDetector(
                onTap: () {
                  final ctx = context;
                  if (ctx.mounted) {
                    WebviewHelper.openUrl(ctx, s['url']!, title: s['title']);
                  }
                },
                child: Text(
                  s['title']?.isNotEmpty == true ? s['title']! : s['url']!,
                  style: TextStyle(
                    fontSize: 12,
                    color: colorScheme.primary,
                    decoration: TextDecoration.underline,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
