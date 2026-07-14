import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import 'package:url_launcher/url_launcher.dart';
import '../../../app/theme.dart';
import '../../../core/localization/strings.dart';
import '../../../core/services/mirror_speed_test_service.dart';
import '../../../shared/widgets/app_compact_label.dart';
import '../../../shared/widgets/app_page.dart';
import '../../../shared/webview/download_manager.dart';
import '../../../shared/webview/download_panel.dart';
import '../models/mirror_models.dart';
import '../providers/mirror_provider.dart';
import '../providers/mirror_source_provider.dart';
import '../providers/recent_mirrors_provider.dart';
import '../services/recent_mirrors_service.dart';
import '../widgets/ltsc_warning_dialog.dart';
import '../../logs/services/log_center_service.dart';
import '../../../shared/webview/webview_helper.dart';

class MirrorDetailScreen extends ConsumerStatefulWidget {
  final MirrorItem item;
  const MirrorDetailScreen({super.key, required this.item});

  @override
  ConsumerState<MirrorDetailScreen> createState() => _MirrorDetailScreenState();
}

class _MirrorDetailScreenState extends ConsumerState<MirrorDetailScreen> {
  MirrorTestResult? _testResult;
  bool _testing = false;
  final _recentMirrors = const RecentMirrorsService();

  @override
  void initState() {
    super.initState();
    unawaited(_recordRecentMirror());
    if (!widget.item.isOfficialMicrosoft && widget.item.hasGlobalMirror) {
      _runSpeedTest();
    }
  }

  Future<void> _recordRecentMirror() async {
    await _recentMirrors.recordMirror(widget.item.id);
    if (mounted) ref.invalidate(recentMirrorEntriesProvider);
  }

  Future<void> _runSpeedTest({bool force = false}) async {
    if (_testing) return;
    setState(() => _testing = true);
    final result = await MirrorSpeedTestService.test(forceRefresh: force);
    if (mounted) {
      setState(() {
        _testResult = result;
        _testing = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final locale = Localizations.localeOf(context);
    final tokens = AppVisualTokens.of(context);

    return Scaffold(
      body: LayoutBuilder(
        builder: (context, constraints) => SingleChildScrollView(
          padding: EdgeInsets.all(
            constraints.maxWidth < 600 ? 16 : tokens.pagePadding,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextButton.icon(
                onPressed: () => context.go('/mirror'),
                icon: const Icon(Icons.arrow_back, size: 18),
                label: Text(tr(context, 'detail_back')),
              ),
              const SizedBox(height: 12),
              if (widget.item.requiresFontPack &&
                  _isChineseLocale(context)) ...[
                const _FontPackWarning(),
                SizedBox(height: tokens.sectionSpacing),
              ],
              _buildHeader(context, locale),
              SizedBox(height: tokens.sectionSpacing),
              AdaptiveTwoPane(
                primary: _buildInfoSection(context, locale),
                secondary: Column(
                  children: [
                    if (!widget.item.isOfficialMicrosoft &&
                        widget.item.hasGlobalMirror) ...[
                      _buildSpeedTestCard(context),
                      SizedBox(height: tokens.itemSpacing),
                    ],
                    if (widget.item.isEnterpriseLtsc) ...[
                      _buildLtscDisclaimer(context),
                      SizedBox(height: tokens.itemSpacing),
                    ],
                    _buildDownloadSection(context, locale),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context, Locale locale) {
    final name = widget.item.getName(locale);
    final type = widget.item.getType(locale);
    final size = widget.item.getSize(locale);
    final trustBadge = widget.item.isOfficialMicrosoft
        ? tr(context, 'mirror_badge_official')
        : widget.item.isCommunityImage
        ? tr(context, 'mirror_badge_community')
        : widget.item.isEnterpriseLtsc
        ? tr(context, 'mirror_badge_ltsc')
        : null;
    return AppPageHeader(
      icon: _catIcon(widget.item.category),
      title: name,
      details: Wrap(
        spacing: 8,
        runSpacing: 4,
        children: [
          if (type.isNotEmpty) _Tag(type),
          if (trustBadge != null) _Tag(trustBadge),
          Tooltip(
            message: tr(context, widget.item.skillLevel.tooltipKey),
            child: _Tag(tr(context, widget.item.skillLevel.labelKey)),
          ),
          if (widget.item.version != null) _Tag(widget.item.version!),
          if (widget.item.build != null) _Tag(widget.item.build!),
          if (widget.item.architecture != null) _Tag(widget.item.architecture!),
          if (size != null) _Tag(size),
        ],
      ),
    );
  }

  bool _isChineseLocale(BuildContext context) {
    return Localizations.localeOf(context).languageCode == 'zh';
  }

  Widget _buildLtscDisclaimer(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Card(
      color: colorScheme.errorContainer.withValues(alpha: 0.28),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _SectionTitle(
              Icons.policy_outlined,
              tr(context, 'mirror_ltsc_disclaimer_title'),
            ),
            const SizedBox(height: 8),
            Text(
              tr(context, 'mirror_ltsc_disclaimer_body'),
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest.withValues(
                  alpha: 0.55,
                ),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                widget.item.isIotLtsc
                    ? tr(context, 'mirror_ltsc_iot_language_notice')
                    : tr(context, 'mirror_ltsc_language_notice'),
                style: theme.textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSpeedTestCard(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.speed, size: 20, color: colorScheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    tr(context, 'mirror_speed_test_title'),
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (!_testing)
                  IconButton(
                    icon: const Icon(Icons.refresh, size: 18),
                    tooltip: tr(context, 'mirror_speed_test_refresh'),
                    onPressed: () => _runSpeedTest(force: true),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            if (_testing)
              Row(
                children: [
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    tr(context, 'mirror_speed_test_testing'),
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              )
            else if (_testResult == null)
              Text(
                tr(context, 'mirror_speed_test_failed'),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colorScheme.error,
                ),
              )
            else ...[
              _MirrorStatusRow(
                label: tr(context, 'mirror_china_title'),
                online: _testResult!.china.online,
                latency: _testResult!.china.latency,
              ),
              const SizedBox(height: 8),
              _MirrorStatusRow(
                label: tr(context, 'mirror_global_title'),
                online: _testResult!.global.online,
                latency: _testResult!.global.latency,
              ),
              if (_testResult!.bothOffline) ...[
                const SizedBox(height: 12),
                Text(
                  tr(context, 'mirror_speed_test_all_offline'),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.error,
                  ),
                ),
              ] else ...[
                const Divider(height: 20),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.recommend, size: 16, color: Colors.green),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(
                              text:
                                  '${tr(context, 'mirror_speed_test_recommend')}: ',
                            ),
                            TextSpan(
                              text: _testResult!.recommendedSource == 'china'
                                  ? tr(context, 'mirror_china_title')
                                  : tr(context, 'mirror_global_title'),
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                color: Colors.green,
                              ),
                            ),
                          ],
                        ),
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildInfoSection(BuildContext context, Locale locale) {
    final theme = Theme.of(context);
    final audience = widget.item.getAudience(locale);
    final pros = widget.item.getPros(locale);
    final notes = widget.item.getNotes(locale);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (audience.isNotEmpty) ...[
          _SectionTitle(Icons.people_outline, tr(context, 'detail_audience')),
          const SizedBox(height: 8),
          Text(audience, style: theme.textTheme.bodyMedium),
          const SizedBox(height: 20),
        ],
        if (pros.isNotEmpty) ...[
          _SectionTitle(Icons.check_circle_outline, tr(context, 'detail_pros')),
          const SizedBox(height: 8),
          ...pros.map(
            (p) => Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('•  ', style: TextStyle(color: Colors.green.shade600)),
                  Expanded(child: Text(p, style: theme.textTheme.bodyMedium)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
        ],
        if (notes.isNotEmpty) ...[
          _SectionTitle(Icons.info_outline, tr(context, 'detail_notes')),
          const SizedBox(height: 8),
          ...notes.map(
            (n) => Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('•  ', style: TextStyle(color: Colors.orange.shade700)),
                  Expanded(child: Text(n, style: theme.textTheme.bodyMedium)),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildDownloadSection(BuildContext context, Locale locale) {
    final theme = Theme.of(context);
    final size = widget.item.getSize(locale);
    final knownImage = _knownImageFor(locale);
    final description = widget.item.isOfficialMicrosoft
        ? tr(context, 'mirror_desc_official')
        : widget.item.isCommunityImage
        ? tr(context, 'mirror_desc_community')
        : widget.item.isEnterpriseLtsc
        ? tr(context, 'mirror_desc_ltsc')
        : '';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              tr(context, 'detail_download'),
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 12),
            if (description.isNotEmpty) ...[
              Text(description, style: theme.textTheme.bodySmall),
              const SizedBox(height: 12),
            ],
            if (size != null) _InfoRow(tr(context, 'detail_size'), size),
            if (widget.item.architecture != null)
              _InfoRow(tr(context, 'detail_arch'), widget.item.architecture!),
            if (knownImage != null) ...[
              const SizedBox(height: 14),
              _ChecksumValue(label: 'SHA-256', value: knownImage.sha256),
              const SizedBox(height: 10),
              _ChecksumValue(label: 'MD5', value: knownImage.md5),
            ],
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () => _openDownload(context, locale),
                icon: const Icon(Icons.open_in_browser, size: 18),
                label: Text(tr(context, 'detail_download_btn')),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () {
                  final url = widget.item.isOfficialMicrosoft
                      ? widget.item.downloadUrlFor(locale)
                      : ref
                            .read(mirrorSourceProvider.notifier)
                            .resolveUrl(widget.item);
                  Clipboard.setData(ClipboardData(text: url));
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(tr(context, 'detail_link_copied'))),
                  );
                },
                icon: const Icon(Icons.copy, size: 16),
                label: Text(tr(context, 'detail_copy_link')),
              ),
            ),
          ],
        ),
      ),
    );
  }

  KnownImage? _knownImageFor(Locale locale) {
    final data = ref.watch(mirrorProvider).data;
    if (data == null) return null;
    for (final image in data.knownImagesForLocale(locale)) {
      if (image.id == widget.item.id) return image;
    }
    return null;
  }

  Future<void> _openDownload(BuildContext context, Locale locale) async {
    if (widget.item.isOfficialMicrosoft) {
      await _openOfficialDownload(context, locale);
      return;
    }

    if (widget.item.isEnterpriseLtsc) {
      final allowed = await showLtscExpertWarning(context);
      if (!allowed || !context.mounted) return;
    }

    final name = widget.item.getName(locale);
    final hasChina = widget.item.hasChinaMirror;
    final hasGlobal = widget.item.hasGlobalMirror;
    final sourceNotifier = ref.read(mirrorSourceProvider.notifier);
    var sourceState = ref.read(mirrorSourceProvider);

    if (sourceState.geo == null && hasChina && hasGlobal) {
      await sourceNotifier.detectGeo();
      if (!context.mounted) {
        return;
      }
      sourceState = ref.read(mirrorSourceProvider);
    }

    if (!hasChina && !hasGlobal) {
      await _openResolvedDownload(
        context: context,
        name: name,
        url: widget.item.downloadUrl,
        mirrorLabel: tr(context, 'mirror_default_title'),
      );
      return;
    }

    final suggestedMirror = hasChina && !hasGlobal
        ? 'china'
        : hasGlobal && !hasChina
        ? 'global'
        : sourceState.isChina
        ? 'china'
        : 'global';
    final selectedMirror = await showDialog<String>(
      context: context,
      builder: (ctx) => _MirrorSelectionDialog(
        itemName: name,
        chinaUrl: widget.item.chinaUrl,
        globalUrl: widget.item.globalUrl,
        suggestedMirror: suggestedMirror,
      ),
    );

    if (selectedMirror == null || !context.mounted) {
      return;
    }

    final String url;
    final String mirrorLabel;
    final String mirrorLogName;
    if (selectedMirror == 'china') {
      url = widget.item.chinaUrl!;
      mirrorLabel = tr(context, 'mirror_china_title');
      mirrorLogName = '123';
    } else if (selectedMirror == 'global') {
      url = widget.item.globalUrl!;
      mirrorLabel = tr(context, 'mirror_global_title');
      mirrorLogName = 'Global Mirror';
    } else {
      return;
    }

    final confirmed = await _confirmMirrorDownload(
      context: context,
      name: name,
      mirrorLabel: mirrorLabel,
    );
    if (!confirmed || !context.mounted) return;

    await _openResolvedDownload(
      context: context,
      name: name,
      url: url,
      mirrorLabel: mirrorLabel,
      mirrorLogName: mirrorLogName,
    );
  }

  Future<bool> _confirmMirrorDownload({
    required BuildContext context,
    required String name,
    required String mirrorLabel,
  }) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr(ctx, 'mirror_download_confirm_title')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _InfoRow(tr(ctx, 'mirror_download_mirror'), name),
            _InfoRow(tr(ctx, 'mirror_download_source'), mirrorLabel),
            if (widget.item.isEnterpriseLtsc) ...[
              const SizedBox(height: 12),
              Text(
                widget.item.isIotLtsc
                    ? tr(ctx, 'mirror_ltsc_iot_language_notice')
                    : tr(ctx, 'mirror_ltsc_language_notice'),
                style: Theme.of(ctx).textTheme.bodySmall,
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(tr(ctx, 'detail_cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(tr(ctx, 'detail_download_btn')),
          ),
        ],
      ),
    );
    return confirmed == true;
  }

  Future<void> _openOfficialDownload(
    BuildContext context,
    Locale locale,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr(ctx, 'official_download_title')),
        content: SingleChildScrollView(
          child: Text(tr(ctx, 'official_download_message')),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(tr(ctx, 'detail_cancel')),
          ),
          FilledButton.icon(
            icon: const Icon(Icons.open_in_browser, size: 18),
            onPressed: () => Navigator.of(ctx).pop(true),
            label: Text(tr(ctx, 'official_download_open')),
          ),
        ],
      ),
    );

    if (confirmed != true || !context.mounted) return;

    await _recordRecentMirror();

    await LogCenterService().logDownload(
      '[OfficialDownload]\n'
      'Product=${widget.item.productLogName}\n'
      'Source=Microsoft\n'
      'Method=SystemBrowser',
    );

    final uri = Uri.parse(widget.item.downloadUrlFor(locale));
    final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!launched && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(tr(context, 'official_download_open_failed'))),
      );
    }
  }

  Future<void> _openResolvedDownload({
    required BuildContext context,
    required String name,
    required String url,
    required String mirrorLabel,
    String? mirrorLogName,
  }) async {
    await _recordRecentMirror();
    final logCenter = LogCenterService();
    await logCenter.logDownload(
      '[CommunityDownload]\n'
      'Product=${widget.item.productLogName}\n'
      'Mirror=${mirrorLogName ?? mirrorLabel}',
    );

    await logCenter.logDownload(
      '[Download]\n'
      'Category=${widget.item.categoryLogName}\n'
      'Image=$name\n'
      'Mirror=${mirrorLogName ?? mirrorLabel}\n'
      'Status=SourceSelected',
    );

    await logCenter.logDownload(
      '[MirrorSource] Category=${widget.item.categoryLogName} '
      'Selected=$mirrorLabel Image=$name URL=$url',
    );

    if (!context.mounted) return;

    if (_isSourceForgeUrl(url)) {
      await _startSourceForgeDownload(
        context: context,
        name: name,
        url: url,
        logCenter: logCenter,
        mirrorLogName: mirrorLogName ?? mirrorLabel,
      );
      return;
    }

    await WebviewHelper.openUrl(context, url, title: name);
    await logCenter.logDownload(
      '[Download]\n'
      'Category=${widget.item.categoryLogName}\n'
      'Image=$name\n'
      'Mirror=${mirrorLogName ?? mirrorLabel}\n'
      'Status=PageOpened',
    );
  }

  bool _isSourceForgeUrl(String url) {
    final host = Uri.tryParse(url)?.host.toLowerCase();
    return host == 'sourceforge.net' ||
        host == 'www.sourceforge.net' ||
        host == 'downloads.sourceforge.net' ||
        (host?.endsWith('.dl.sourceforge.net') ?? false);
  }

  Future<void> _startSourceForgeDownload({
    required BuildContext context,
    required String name,
    required String url,
    required LogCenterService logCenter,
    required String mirrorLogName,
  }) async {
    final fileName = _downloadFileName(url, name);
    final savePath = await FilePicker.saveFile(
      dialogTitle: tr(context, 'webview_save_title'),
      fileName: fileName,
      type: FileType.any,
    );
    if (savePath == null || !context.mounted) {
      await logCenter.logDownload(
        '[Download]\n'
        'Category=${widget.item.categoryLogName}\n'
        'Image=$name\n'
        'Mirror=$mirrorLogName\n'
        'Status=Cancelled',
      );
      return;
    }

    await DownloadManager().startDownload(
      url: url,
      fileName: p.basename(savePath),
      savePath: savePath,
    );
    await logCenter.logDownload(
      '[Download]\n'
      'Category=${widget.item.categoryLogName}\n'
      'Image=$name\n'
      'Mirror=$mirrorLogName\n'
      'Status=Started\n'
      'Path=$savePath',
    );
    if (context.mounted) _showDownloadProgress(context);
  }

  void _showDownloadProgress(BuildContext context) {
    unawaited(
      showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        backgroundColor: Colors.transparent,
        constraints: const BoxConstraints(maxWidth: 420),
        builder: (sheetContext) => SafeArea(
          top: false,
          child: Center(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
              child: DownloadPanel(onDownloadCurrentPage: () {}),
            ),
          ),
        ),
      ),
    );
  }

  String _downloadFileName(String url, String fallbackName) {
    final uri = Uri.tryParse(url);
    final lastSegment = uri?.pathSegments.isNotEmpty == true
        ? uri!.pathSegments.last
        : '';
    final decoded = Uri.decodeComponent(lastSegment).trim();
    if (decoded.contains('.') && !decoded.endsWith('.')) return decoded;
    final safeName = fallbackName.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    return '$safeName.iso';
  }

  IconData _catIcon(String category) {
    switch (category) {
      case 'Official Microsoft':
      case 'Official Microsoft Images':
        return Icons.verified;
      case 'Community Images':
      case 'Community Editions':
        return Icons.groups_outlined;
      case 'Enterprise & LTSC Builds':
        return Icons.admin_panel_settings_outlined;
      case 'Tools':
        return Icons.build;
      default:
        return Icons.folder;
    }
  }
}

class _SectionTitle extends StatelessWidget {
  final IconData icon;
  final String title;
  const _SectionTitle(this.icon, this.title);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Icon(icon, size: 18, color: theme.colorScheme.primary),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            title,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w600,
              color: theme.colorScheme.primary,
            ),
          ),
        ),
      ],
    );
  }
}

class _Tag extends StatelessWidget {
  final String label;
  const _Tag(this.label);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: Theme.of(
          context,
        ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(4),
      ),
      child: AppCompactLabel(
        label,
        style: Theme.of(context).textTheme.labelSmall,
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  const _InfoRow(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return LayoutBuilder(
      builder: (context, constraints) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: constraints.maxWidth < 300
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: theme.textTheme.bodySmall),
                  Text(
                    value,
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              )
            : Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(label, style: theme.textTheme.bodySmall),
                  ),
                  const SizedBox(width: 12),
                  Flexible(
                    child: Text(
                      value,
                      textAlign: TextAlign.end,
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

class _ChecksumValue extends StatelessWidget {
  final String label;
  final String value;

  const _ChecksumValue({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest.withValues(alpha: 0.48),
        border: Border.all(color: colors.outlineVariant.withValues(alpha: 0.7)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: theme.textTheme.labelMedium?.copyWith(
              color: colors.onSurfaceVariant,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          SelectableText(
            value,
            style: theme.textTheme.bodySmall?.copyWith(
              fontFamily: 'monospace',
              fontWeight: FontWeight.w600,
              height: 1.45,
            ),
          ),
        ],
      ),
    );
  }
}

class _FontPackWarning extends StatelessWidget {
  const _FontPackWarning();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final message = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          tr(context, 'fontpack_warning'),
          style: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w600,
            color: colorScheme.onTertiaryContainer,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          tr(context, 'fontpack_recommend'),
          style: theme.textTheme.bodySmall?.copyWith(
            color: colorScheme.onTertiaryContainer,
          ),
        ),
      ],
    );
    final button = FilledButton.tonalIcon(
      onPressed: () => context.go('/mirror/font-pack'),
      icon: const Icon(Icons.font_download_outlined, size: 18),
      label: Text(tr(context, 'fontpack_download')),
    );

    return AppInfoBox(
      icon: Icons.info_outline,
      color: colorScheme.tertiary,
      actions: [button],
      child: message,
    );
  }
}

class _MirrorStatusRow extends StatelessWidget {
  final String label;
  final bool online;
  final int latency;

  const _MirrorStatusRow({
    required this.label,
    required this.online,
    required this.latency,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Icon(
          online ? Icons.check_circle : Icons.cancel,
          size: 16,
          color: online ? Colors.green : Colors.red,
        ),
        const SizedBox(width: 8),
        Expanded(child: Text(label, style: theme.textTheme.bodySmall)),
        const SizedBox(width: 8),
        Text(
          online ? '${latency}ms' : 'Offline',
          style: theme.textTheme.bodySmall?.copyWith(
            fontWeight: FontWeight.w600,
            color: online ? null : Colors.red,
          ),
        ),
      ],
    );
  }
}

class _MirrorSelectionDialog extends StatelessWidget {
  final String itemName;
  final String? chinaUrl;
  final String? globalUrl;
  final String suggestedMirror;

  const _MirrorSelectionDialog({
    required this.itemName,
    this.chinaUrl,
    this.globalUrl,
    required this.suggestedMirror,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final hasChina = chinaUrl != null && chinaUrl!.isNotEmpty;
    final hasGlobal = globalUrl != null && globalUrl!.isNotEmpty;

    return AlertDialog(
      icon: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: colorScheme.primaryContainer,
          shape: BoxShape.circle,
        ),
        child: Icon(
          Icons.cloud_download_outlined,
          size: 32,
          color: colorScheme.primary,
        ),
      ),
      title: Text(
        tr(context, 'mirror_select_title'),
        textAlign: TextAlign.center,
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 380),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              itemName,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              tr(context, 'mirror_select_desc'),
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            if (hasChina)
              _MirrorOption(
                icon: Icons.flag_outlined,
                title: tr(context, 'mirror_china_title'),
                subtitle: tr(context, 'mirror_china_desc'),
                tag: suggestedMirror == 'china'
                    ? tr(context, 'mirror_speed_test_recommend')
                    : tr(context, 'mirror_china_tag'),
                tagColor: Colors.blue,
                onTap: () => Navigator.of(context).pop('china'),
              ),
            if (hasChina && hasGlobal) const SizedBox(height: 12),
            if (hasGlobal)
              _MirrorOption(
                icon: Icons.public_outlined,
                title: tr(context, 'mirror_global_title'),
                subtitle: tr(context, 'mirror_global_desc'),
                tag: suggestedMirror == 'global'
                    ? tr(context, 'mirror_speed_test_recommend')
                    : tr(context, 'mirror_global_tag'),
                tagColor: Colors.green,
                onTap: () => Navigator.of(context).pop('global'),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(tr(context, 'detail_cancel')),
        ),
      ],
    );
  }
}

class _MirrorOption extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final String? tag;
  final Color? tagColor;
  final VoidCallback onTap;

  const _MirrorOption({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.tag,
    this.tagColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          border: Border.all(color: colorScheme.outlineVariant),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, size: 24, color: colorScheme.primary),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      Text(
                        title,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (tag != null) ...[
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: (tagColor ?? colorScheme.primary).withValues(
                              alpha: 0.1,
                            ),
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(
                              color: (tagColor ?? colorScheme.primary)
                                  .withValues(alpha: 0.3),
                            ),
                          ),
                          child: AppCompactLabel(
                            tag!,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: tagColor ?? colorScheme.primary,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Directionality.of(context) == TextDirection.rtl
                  ? Icons.arrow_back_ios_new
                  : Icons.arrow_forward_ios,
              size: 16,
              color: colorScheme.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
  }
}
