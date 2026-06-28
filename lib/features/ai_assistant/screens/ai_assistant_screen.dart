import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import '../../../app/typography.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/localization/strings.dart';
import '../../../core/services/disk_safety_service.dart';
import '../models/chat_models.dart';
import '../providers/chat_provider.dart';
import '../services/ai_service.dart';
import '../widgets/chat_bubble.dart';
import '../widgets/chat_input.dart';
import '../widgets/chat_sidebar.dart';
import '../widgets/welcome_screen.dart';

class AiAssistantScreen extends ConsumerStatefulWidget {
  final String? initialPrompt;
  const AiAssistantScreen({super.key, this.initialPrompt});

  @override
  ConsumerState<AiAssistantScreen> createState() => _AiAssistantScreenState();
}

class _AiAssistantScreenState extends ConsumerState<AiAssistantScreen> {
  static const _noticePrefKey = 'ai_assistant_notice_hidden';
  final _scrollController = ScrollController();
  bool _showSidebar = true;
  bool _initialPromptSent = false;
  bool _showNotice = false;

  @override
  void initState() {
    super.initState();
    _loadNoticePreference();
    // Send initial prompt after first frame
    if (widget.initialPrompt != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_initialPromptSent && mounted) {
          _initialPromptSent = true;
          ref.read(chatProvider.notifier).sendMessage(widget.initialPrompt!);
        }
      });
    }
  }

  Future<void> _loadNoticePreference() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _showNotice = !(prefs.getBool(_noticePrefKey) ?? false);
    });
  }

  Future<void> _dismissNotice({required bool persist}) async {
    if (persist) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_noticePrefKey, true);
    }
    if (!mounted) return;
    setState(() => _showNotice = false);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final chatState = ref.watch(chatProvider);
    final colorScheme = Theme.of(context).colorScheme;
    final session = chatState.activeSession;
    final messages = session?.messages ?? [];

    ref.listen<ChatState>(chatProvider, (prev, next) {
      if (next.activeSession?.messages.length !=
              prev?.activeSession?.messages.length ||
          next.isGenerating) {
        _scrollToBottom();
      }
    });

    return Scaffold(
      body: Row(
        children: [
          if (_showSidebar) const ChatSidebar(),
          Expanded(
            child: Column(
              children: [
                _buildHeader(context, chatState, colorScheme),
                const Divider(height: 1),
                if (_showNotice) _buildAiNotice(context, colorScheme),
                Expanded(
                  child: messages.isEmpty
                      ? Column(
                          children: [
                            Expanded(
                              child: WelcomeScreen(onSendPrompt: _handleSend),
                            ),
                            _buildQuickActions(context, colorScheme),
                          ],
                        )
                      : _buildMessageList(messages, colorScheme),
                ),
                ChatInput(
                  enabled: !chatState.isGenerating,
                  onSend: _handleSend,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAiNotice(BuildContext context, ColorScheme colorScheme) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colorScheme.secondaryContainer.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.info_outline_rounded,
            size: 20,
            color: colorScheme.onSecondaryContainer,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  tr(context, 'ai_notice_title'),
                  style: AppTypography.cardTitleWith(
                    colorScheme.onSecondaryContainer,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  tr(context, 'ai_notice_message'),
                  style: AppTypography.bodyWith(
                    colorScheme.onSecondaryContainer,
                  ),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    FilledButton.tonal(
                      onPressed: () => _dismissNotice(persist: false),
                      child: Text(tr(context, 'ai_notice_got_it')),
                    ),
                    TextButton(
                      onPressed: () => _dismissNotice(persist: true),
                      child: Text(tr(context, 'ai_notice_do_not_show')),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(
    BuildContext context,
    ChatState chatState,
    ColorScheme colorScheme,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          IconButton(
            icon: Icon(
              _showSidebar ? Icons.menu_open_rounded : Icons.menu_rounded,
            ),
            onPressed: () => setState(() => _showSidebar = !_showSidebar),
            tooltip: _showSidebar
                ? tr(context, 'ai_hide_sidebar')
                : tr(context, 'ai_show_sidebar'),
          ),
          const SizedBox(width: 8),
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: Colors.green,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            'WinDeploy AI',
            style: AppTypography.cardTitleWith(colorScheme.onSurface),
          ),
          const SizedBox(width: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              'MiMo 2.5 Pro',
              style: TextStyle(
                fontSize: 10,
                color: colorScheme.onPrimaryContainer,
              ),
            ),
          ),
          const Spacer(),
          _buildSearchToggle(context, chatState.searchMode, colorScheme),
          const SizedBox(width: 8),
          if (chatState.activeSession != null) ...[
            IconButton(
              icon: const Icon(Icons.delete_outline_rounded, size: 20),
              onPressed: () =>
                  ref.read(chatProvider.notifier).clearActiveSession(),
              tooltip: tr(context, 'ai_clear_chat'),
            ),
          ],
          IconButton(
            icon: const Icon(Icons.add_comment_outlined, size: 20),
            onPressed: () => ref.read(chatProvider.notifier).createNewSession(),
            tooltip: tr(context, 'ai_new_chat'),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchToggle(
    BuildContext context,
    SearchMode mode,
    ColorScheme colorScheme,
  ) {
    return PopupMenuButton<SearchMode>(
      onSelected: (m) => ref.read(chatProvider.notifier).setSearchMode(m),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: mode != SearchMode.off
              ? colorScheme.primaryContainer
              : colorScheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: mode != SearchMode.off
                ? colorScheme.primary
                : colorScheme.outlineVariant,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.language_rounded,
              size: 16,
              color: mode != SearchMode.off
                  ? colorScheme.onPrimaryContainer
                  : colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 6),
            Text(
              mode == SearchMode.off
                  ? tr(context, 'ai_search_off')
                  : mode == SearchMode.auto
                  ? tr(context, 'ai_search_auto')
                  : tr(context, 'ai_search_force'),
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: mode != SearchMode.off
                    ? colorScheme.onPrimaryContainer
                    : colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(width: 4),
            Icon(
              Icons.arrow_drop_down_rounded,
              size: 16,
              color: mode != SearchMode.off
                  ? colorScheme.onPrimaryContainer
                  : colorScheme.onSurfaceVariant,
            ),
          ],
        ),
      ),
      itemBuilder: (context) => [
        PopupMenuItem(
          value: SearchMode.off,
          child: _searchMenuItem(context, SearchMode.off),
        ),
        PopupMenuItem(
          value: SearchMode.auto,
          child: _searchMenuItem(context, SearchMode.auto),
        ),
        PopupMenuItem(
          value: SearchMode.force,
          child: _searchMenuItem(context, SearchMode.force),
        ),
      ],
    );
  }

  Widget _searchMenuItem(BuildContext context, SearchMode mode) {
    return Row(
      children: [
        Icon(
          mode == SearchMode.off
              ? Icons.language_outlined
              : mode == SearchMode.auto
              ? Icons.auto_mode_rounded
              : Icons.travel_explore_rounded,
          size: 18,
        ),
        const SizedBox(width: 8),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              mode == SearchMode.off
                  ? tr(context, 'ai_search_off')
                  : mode == SearchMode.auto
                  ? tr(context, 'ai_search_auto')
                  : tr(context, 'ai_search_force'),
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
            Text(
              mode == SearchMode.off
                  ? tr(context, 'ai_search_off_desc')
                  : mode == SearchMode.auto
                  ? tr(context, 'ai_search_auto_desc')
                  : tr(context, 'ai_search_force_desc'),
              style: TextStyle(
                fontSize: 11,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildMessageList(
    List<ChatMessage> messages,
    ColorScheme colorScheme,
  ) {
    return Column(
      children: [
        Expanded(
          child: ListView.builder(
            controller: _scrollController,
            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
            itemCount: messages.length,
            itemBuilder: (context, index) {
              return ChatBubble(message: messages[index]);
            },
          ),
        ),
        _buildQuickActions(context, colorScheme),
      ],
    );
  }

  Widget _buildQuickActions(BuildContext context, ColorScheme colorScheme) {
    final isGenerating = ref.watch(chatProvider).isGenerating;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _QuickActionChip(
                icon: Icons.bug_report_outlined,
                label: tr(context, 'ai_action_analyze_logs'),
                onTap: isGenerating ? null : () => _handleAnalyzeLogs(),
              ),
              _QuickActionChip(
                icon: Icons.disc_full_outlined,
                label: tr(context, 'ai_action_analyze_iso'),
                onTap: isGenerating ? null : () => _handleAnalyzeIso(),
              ),
              _QuickActionChip(
                icon: Icons.usb_outlined,
                label: tr(context, 'ai_action_analyze_usb'),
                onTap: isGenerating ? null : () => _handleAnalyzeUsb(),
              ),
              _QuickActionChip(
                icon: Icons.build_outlined,
                label: tr(context, 'ai_action_diagnose'),
                onTap: isGenerating ? null : () => _handleDiagnose(),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _QuickActionChip(
                icon: Icons.search_rounded,
                label: tr(context, 'ai_search_ms_update'),
                onTap: () =>
                    _handleSend(tr(context, 'ai_search_ms_update_prompt')),
              ),
              _QuickActionChip(
                icon: Icons.search_rounded,
                label: tr(context, 'ai_search_canary'),
                onTap: () =>
                    _handleSend(tr(context, 'ai_search_canary_prompt')),
              ),
              _QuickActionChip(
                icon: Icons.search_rounded,
                label: tr(context, 'ai_search_wtg_tutorial'),
                onTap: () =>
                    _handleSend(tr(context, 'ai_search_wtg_tutorial_prompt')),
              ),
              _QuickActionChip(
                icon: Icons.search_rounded,
                label: tr(context, 'ai_search_rufus'),
                onTap: () => _handleSend(tr(context, 'ai_search_rufus_prompt')),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _handleSend(String text) {
    if (ref.read(chatProvider).isGenerating) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(tr(context, 'ai_please_wait')),
          duration: const Duration(seconds: 2),
        ),
      );
      return;
    }
    ref
        .read(chatProvider.notifier)
        .sendMessage(text, systemPrompt: getSystemPrompt(context));
  }

  Future<void> _handleAnalyzeLogs() async {
    final noLogsText = tr(context, 'ai_no_logs');
    final analyzePromptBuilder = buildAnalyzeLogsPrompt;
    final logsPath = p.join(
      AppConstants.appDataPath,
      'WinDeployStudio',
      'logs',
    );

    final buffer = StringBuffer();
    for (final category in ['errors', 'wtg', 'usb', 'system']) {
      final dir = Directory(p.join(logsPath, category));
      if (!dir.existsSync()) {
        continue;
      }
      final files = dir
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.log'))
          .toList();
      files.sort(
        (a, b) => b.statSync().modified.compareTo(a.statSync().modified),
      );
      for (final file in files.take(5)) {
        buffer.writeln('=== ${file.path} ===');
        try {
          final content = await file.readAsString();
          final lines = content.split('\n');
          buffer.writeln(lines.take(50).join('\n'));
        } catch (_) {}
        buffer.writeln();
      }
    }

    if (!mounted) {
      return;
    }

    if (buffer.isEmpty) {
      _handleSend(noLogsText);
      return;
    }

    _handleSend(analyzePromptBuilder(context, buffer.toString()));
  }

  Future<void> _handleAnalyzeIso() async {
    final promptPrefix = getAnalyzePromptPrefix(context);
    final isoLogsLabel = tr(context, 'ai_prompt_iso_logs');
    final localIsosLabel = tr(context, 'ai_prompt_local_isos');
    final noIsoFoundLabel = tr(context, 'ai_prompt_no_iso_found');
    final logsPath = p.join(
      AppConstants.appDataPath,
      'WinDeployStudio',
      'logs',
      'iso',
    );
    final buffer = StringBuffer(promptPrefix);

    // Read ISO logs
    final dir = Directory(logsPath);
    if (dir.existsSync()) {
      final files = dir
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.log'))
          .toList();
      files.sort(
        (a, b) => b.statSync().modified.compareTo(a.statSync().modified),
      );
      if (files.isNotEmpty) {
        buffer.writeln(isoLogsLabel);
        for (final file in files.take(3)) {
          try {
            final content = await file.readAsString();
            buffer.writeln(
              content.length > 300
                  ? '${content.substring(0, 300)}...'
                  : content,
            );
          } catch (_) {}
        }
        buffer.writeln();
      }
    }

    // Find ISO files
    final isoDirs = [
      AppConstants.downloadsPath,
      '${AppConstants.userProfilePath}\\Desktop',
    ];
    buffer.writeln(localIsosLabel);
    int isoCount = 0;
    for (final dirPath in isoDirs) {
      if (dirPath.isEmpty) {
        continue;
      }
      final d = Directory(dirPath);
      if (!d.existsSync()) {
        continue;
      }
      try {
        final files = d
            .listSync(recursive: false)
            .whereType<File>()
            .where((f) => f.path.toLowerCase().endsWith('.iso'))
            .toList();
        for (final f in files.take(5)) {
          final size = f.statSync().size;
          final sizeStr = size < 1024 * 1024 * 1024
              ? '${(size / (1024 * 1024)).toStringAsFixed(0)} MB'
              : '${(size / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
          buffer.writeln('  - ${p.basename(f.path)} ($sizeStr)');
          isoCount++;
        }
      } catch (_) {}
    }
    if (isoCount == 0) {
      buffer.writeln(noIsoFoundLabel);
    }

    if (!mounted) {
      return;
    }

    _handleSend(buffer.toString());
  }

  Future<void> _handleAnalyzeUsb() async {
    final promptPrefix = getAnalyzePromptPrefix(context);
    final noUsbText = tr(context, 'ai_prompt_no_usb_detected');
    final usbDetectedTemplate = tr(context, 'ai_prompt_usb_detected');
    final diskLabel = tr(context, 'ai_prompt_disk');
    final capacityLabel = tr(context, 'ai_prompt_capacity');
    final busTypeLabel = tr(context, 'ai_prompt_bus_type');
    final serialLabel = tr(context, 'ai_prompt_serial');
    final partitionStyleLabel = tr(context, 'ai_prompt_partition_style');
    final driveLettersLabel = tr(context, 'ai_prompt_drive_letters');
    final partitionCountLabel = tr(context, 'ai_prompt_partition_count');
    final usbGetFailedLabel = tr(context, 'ai_prompt_usb_get_failed');
    final buffer = StringBuffer(promptPrefix);

    try {
      final safety = ref.read(diskSafetyServiceProvider);
      final disks = await safety.getRemovableDisks();

      if (disks.isEmpty) {
        buffer.writeln(noUsbText);
      } else {
        buffer.writeln(
          usbDetectedTemplate.replaceAll('{count}', '${disks.length}'),
        );
        buffer.writeln();
        for (final disk in disks) {
          buffer.writeln('$diskLabel ${disk.diskNumber}: ${disk.model}');
          buffer.writeln('  $capacityLabel: ${disk.sizeFormatted}');
          buffer.writeln('  $busTypeLabel: ${disk.busType}');
          buffer.writeln(
            '  $serialLabel: ${disk.serialNumber.isNotEmpty ? disk.serialNumber : "N/A"}',
          );
          buffer.writeln('  $partitionStyleLabel: ${disk.partitionStyle}');
          buffer.writeln(
            '  $driveLettersLabel: ${disk.driveLetters.isNotEmpty ? disk.driveLetters.join(", ") : "-"}',
          );
          buffer.writeln('  $partitionCountLabel: ${disk.partitions.length}');
          for (final p2 in disk.partitions) {
            buffer.writeln(
              '    - ${p2.type} ${p2.sizeBytes < 1024 * 1024 * 1024 ? "${(p2.sizeBytes / (1024 * 1024)).toStringAsFixed(0)} MB" : "${(p2.sizeBytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB"}${p2.driveLetter != null ? " (${p2.driveLetter}:)" : ""}',
            );
          }
          buffer.writeln();
        }
      }
    } catch (e) {
      buffer.writeln('$usbGetFailedLabel $e');
    }

    if (!mounted) {
      return;
    }

    _handleSend(buffer.toString());
  }

  Future<void> _handleDiagnose() async {
    final promptPrefix = getAnalyzePromptPrefix(context);
    final logSummaryLabel = tr(context, 'ai_prompt_log_summary');
    final filesLabel = tr(context, 'ai_prompt_files');
    final noLogsLabel = tr(context, 'ai_prompt_no_logs');
    final usbDevicesLabel = tr(context, 'ai_prompt_usb_devices');
    final noRemovableLabel = tr(context, 'ai_prompt_no_removable');
    final diskLabel = tr(context, 'ai_prompt_disk');
    final getFailedLabel = tr(context, 'ai_prompt_get_failed');
    final recentErrorsLabel = tr(context, 'ai_prompt_recent_errors');
    final noErrorsLabel = tr(context, 'ai_prompt_no_errors');
    final errorDirMissingLabel = tr(context, 'ai_prompt_error_dir_missing');
    final buffer = StringBuffer(promptPrefix);

    // Logs summary
    final logsPath = p.join(
      AppConstants.appDataPath,
      'WinDeployStudio',
      'logs',
    );
    int totalLogs = 0;
    buffer.writeln(logSummaryLabel);
    for (final category in ['errors', 'wtg', 'usb', 'iso', 'system']) {
      final dir = Directory(p.join(logsPath, category));
      if (!dir.existsSync()) {
        continue;
      }
      final count = dir
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.log'))
          .length;
      if (count > 0) {
        buffer.writeln('  $category: $count $filesLabel');
        totalLogs += count;
      }
    }
    if (totalLogs == 0) {
      buffer.writeln(noLogsLabel);
    }
    buffer.writeln();

    // USB info
    buffer.writeln(usbDevicesLabel);
    try {
      final safety = ref.read(diskSafetyServiceProvider);
      final disks = await safety.getRemovableDisks();
      if (disks.isEmpty) {
        buffer.writeln(noRemovableLabel);
      } else {
        for (final disk in disks) {
          buffer.writeln(
            '  $diskLabel ${disk.diskNumber}: ${disk.model} (${disk.sizeFormatted}, ${disk.busType})',
          );
        }
      }
    } catch (e) {
      buffer.writeln('  $getFailedLabel $e');
    }
    buffer.writeln();

    // Recent error logs
    buffer.writeln(recentErrorsLabel);
    final errorDir = Directory(p.join(logsPath, 'errors'));
    if (errorDir.existsSync()) {
      final files = errorDir
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.log'))
          .toList();
      files.sort(
        (a, b) => b.statSync().modified.compareTo(a.statSync().modified),
      );
      if (files.isNotEmpty) {
        for (final file in files.take(3)) {
          buffer.writeln('--- ${p.basename(file.path)} ---');
          try {
            final content = await file.readAsString();
            buffer.writeln(
              content.length > 500
                  ? '${content.substring(0, 500)}...'
                  : content,
            );
          } catch (_) {}
        }
      } else {
        buffer.writeln(noErrorsLabel);
      }
    } else {
      buffer.writeln(errorDirMissingLabel);
    }

    if (!mounted) {
      return;
    }

    _handleSend(buffer.toString());
  }
}

class _QuickActionChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  const _QuickActionChip({required this.icon, required this.label, this.onTap});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDisabled = onTap == null;
    return ActionChip(
      avatar: Icon(
        icon,
        size: 16,
        color: isDisabled
            ? colorScheme.onSurfaceVariant.withValues(alpha: 0.4)
            : colorScheme.primary,
      ),
      label: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          color: isDisabled
              ? colorScheme.onSurfaceVariant.withValues(alpha: 0.4)
              : colorScheme.onSurface,
        ),
      ),
      onPressed: onTap,
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
  }
}
