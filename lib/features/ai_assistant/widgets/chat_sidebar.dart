import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../app/theme.dart';
import '../../../app/typography.dart';
import '../../../core/localization/strings.dart';
import '../providers/chat_provider.dart';

class ChatSidebar extends ConsumerWidget {
  const ChatSidebar({super.key, this.width = 260});

  final double width;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final chatState = ref.watch(chatProvider);
    final colorScheme = Theme.of(context).colorScheme;
    final tokens = AppVisualTokens.of(context);

    return Container(
      width: width,
      decoration: BoxDecoration(
        color: tokens.style == VisualStyle.win10
            ? colorScheme.surface
            : colorScheme.surfaceContainerLow,
        border: BorderDirectional(
          end: BorderSide(
            color: colorScheme.outlineVariant,
            width: tokens.borderWidth,
          ),
        ),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () =>
                    ref.read(chatProvider.notifier).createNewSession(),
                icon: const Icon(Icons.add_rounded, size: 18),
                label: Text(tr(context, 'ai_new_chat')),
              ),
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: chatState.sessions.isEmpty
                ? Center(
                    child: Text(
                      tr(context, 'ai_no_history'),
                      style: AppTypography.captionWith(
                        colorScheme.onSurfaceVariant,
                      ),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    itemCount: chatState.sessions.length,
                    itemBuilder: (context, index) {
                      final session = chatState.sessions[index];
                      final isActive = session.id == chatState.activeSessionId;
                      return _SessionTile(
                        title: session.title,
                        isActive: isActive,
                        onTap: () => ref
                            .read(chatProvider.notifier)
                            .selectSession(session.id),
                        onDelete: () => ref
                            .read(chatProvider.notifier)
                            .deleteSession(session.id),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _SessionTile extends StatelessWidget {
  final String title;
  final bool isActive;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  const _SessionTile({
    required this.title,
    required this.isActive,
    required this.onTap,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final tokens = AppVisualTokens.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      child: Material(
        color: isActive ? colorScheme.primaryContainer : Colors.transparent,
        borderRadius: BorderRadius.circular(tokens.controlRadius),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(tokens.controlRadius),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                Icon(
                  Icons.chat_outlined,
                  size: 16,
                  color: isActive
                      ? colorScheme.onPrimaryContainer
                      : colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.captionWith(
                      isActive
                          ? colorScheme.onPrimaryContainer
                          : colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                if (!isActive)
                  GestureDetector(
                    onTap: onDelete,
                    child: Icon(
                      Icons.close_rounded,
                      size: 14,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
