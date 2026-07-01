import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/localization/strings.dart';
import '../../../core/services/mirror_speed_test_service.dart';
import '../models/mirror_models.dart';
import '../providers/mirror_source_provider.dart';
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

  @override
  void initState() {
    super.initState();
    if (!widget.item.isOfficialMicrosoft) {
      _runSpeedTest();
    }
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
    final screenWidth = MediaQuery.of(context).size.width;
    final isCompact = screenWidth < 900;
    final locale = Localizations.localeOf(context);

    return Scaffold(
      body: SingleChildScrollView(
        padding: EdgeInsets.all(isCompact ? 16 : 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextButton.icon(
              onPressed: () => context.go('/mirror'),
              icon: const Icon(Icons.arrow_back, size: 18),
              label: Text(tr(context, 'detail_back')),
            ),
            const SizedBox(height: 16),
            if (widget.item.needsFontPack && _isChineseLocale(context)) ...[
              const _FontPackWarning(),
              const SizedBox(height: 16),
            ],
            _buildHeader(context, locale),
            const SizedBox(height: 24),
            isCompact
                ? Column(
                    children: [
                      if (widget.item.isEnterpriseLtsc) ...[
                        _buildLtscDisclaimer(context),
                        const SizedBox(height: 24),
                      ],
                      _buildInfoSection(context, locale),
                      if (!widget.item.isOfficialMicrosoft) ...[
                        const SizedBox(height: 24),
                        _buildSpeedTestCard(context),
                      ],
                      const SizedBox(height: 24),
                      _buildDownloadSection(context, locale),
                    ],
                  )
                : Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        flex: 2,
                        child: _buildInfoSection(context, locale),
                      ),
                      const SizedBox(width: 24),
                      Expanded(
                        flex: 1,
                        child: Column(
                          children: [
                            if (!widget.item.isOfficialMicrosoft) ...[
                              _buildSpeedTestCard(context),
                              const SizedBox(height: 16),
                            ],
                            if (widget.item.isEnterpriseLtsc) ...[
                              _buildLtscDisclaimer(context),
                              const SizedBox(height: 16),
                            ],
                            _buildDownloadSection(context, locale),
                          ],
                        ),
                      ),
                    ],
                  ),
          ],
        ),
      ),
    );
  }

  bool _isChineseLocale(BuildContext context) {
    final code = Localizations.localeOf(context).languageCode;
    return code == 'zh';
  }

  Widget _buildHeader(BuildContext context, Locale locale) {
    final theme = Theme.of(context);
    final name = widget.item.getName(locale);
    final type = widget.item.getType(locale);
    final trustBadge = widget.item.isOfficialMicrosoft
        ? tr(context, 'mirror_badge_official')
        : widget.item.isCommunityImage
        ? tr(context, 'mirror_badge_community')
        : widget.item.isEnterpriseLtsc
        ? tr(context, 'mirror_badge_ltsc')
        : null;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            color: _catColor(widget.item.category).withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(
            _catIcon(widget.item.category),
            size: 32,
            color: _catColor(widget.item.category),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                name,
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              Wrap(
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
                  if (widget.item.architecture != null)
                    _Tag(widget.item.architecture!),
                  if (widget.item.size != null) _Tag(widget.item.size!),
                ],
              ),
            ],
          ),
        ),
      ],
    );
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
                Text(
                  tr(context, 'mirror_speed_test_title'),
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
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
                  children: [
                    Icon(Icons.recommend, size: 16, color: Colors.green),
                    const SizedBox(width: 6),
                    Text(
                      '${tr(context, 'mirror_speed_test_recommend')}: ',
                      style: theme.textTheme.bodySmall,
                    ),
                    Text(
                      _testResult!.recommendedSource == 'china'
                          ? tr(context, 'mirror_china_title')
                          : tr(context, 'mirror_global_title'),
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: Colors.green,
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
        if (widget.item.sha256 != null && widget.item.sha256!.isNotEmpty) ...[
          const SizedBox(height: 20),
          _SectionTitle(Icons.fingerprint, 'SHA256'),
          const SizedBox(height: 8),
          InkWell(
            onTap: () {
              Clipboard.setData(ClipboardData(text: widget.item.sha256!));
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(tr(context, 'detail_sha256_copied'))),
              );
            },
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest.withValues(
                  alpha: 0.5,
                ),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.item.sha256!,
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontFamily: 'Consolas',
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(Icons.copy, size: 14, color: theme.colorScheme.primary),
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
            if (widget.item.size != null)
              _InfoRow(tr(context, 'detail_size'), widget.item.size!),
            if (widget.item.architecture != null)
              _InfoRow(tr(context, 'detail_arch'), widget.item.architecture!),
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
                      ? widget.item.downloadUrl
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

  Future<void> _openDownload(BuildContext context, Locale locale) async {
    if (widget.item.isOfficialMicrosoft) {
      await _openOfficialDownload(context);
      return;
    }

    if (widget.item.isEnterpriseLtsc) {
      final allowed = await showLtscExpertWarning(context);
      if (!allowed || !context.mounted) return;
    }

    final name = widget.item.getName(locale);
    final sourceNotifier = ref.read(mirrorSourceProvider.notifier);
    var sourceState = ref.read(mirrorSourceProvider);

    if (sourceState.geo == null) {
      await sourceNotifier.detectGeo();
      if (!context.mounted) {
        return;
      }
      sourceState = ref.read(mirrorSourceProvider);
    }

    final hasChina =
        widget.item.chinaUrl != null && widget.item.chinaUrl!.isNotEmpty;
    final hasGlobal =
        widget.item.globalUrl != null && widget.item.globalUrl!.isNotEmpty;

    if (!hasChina && !hasGlobal) {
      await _openResolvedDownload(
        context: context,
        name: name,
        url: widget.item.downloadUrl,
        mirrorLabel: tr(context, 'mirror_default_title'),
      );
      return;
    }

    final suggestedMirror = sourceState.isChina ? 'china' : 'global';
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
      mirrorLogName = 'GoFile';
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

  Future<void> _openOfficialDownload(BuildContext context) async {
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

    await LogCenterService().logDownload(
      '[OfficialDownload]\n'
      'Product=${widget.item.productLogName}\n'
      'Source=Microsoft\n'
      'Method=SystemBrowser',
    );

    final uri = Uri.parse(widget.item.downloadUrl);
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
      'Status=Started',
    );

    await logCenter.logDownload(
      '[MirrorSource] Category=${widget.item.categoryLogName} '
      'Selected=$mirrorLabel Image=$name URL=$url',
    );

    if (context.mounted) {
      await WebviewHelper.openUrl(context, url, title: name);
      await logCenter.logDownload(
        '[Download]\n'
        'Category=${widget.item.categoryLogName}\n'
        'Image=$name\n'
        'Mirror=${mirrorLogName ?? mirrorLabel}\n'
        'Status=Success',
      );
    }
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

  Color _catColor(String category) {
    switch (category) {
      case 'Official Microsoft':
      case 'Official Microsoft Images':
        return const Color(0xFF0071C5);
      case 'Community Images':
      case 'Community Editions':
        return const Color(0xFF008272);
      case 'Enterprise & LTSC Builds':
        return const Color(0xFFC43E1C);
      case 'Tools':
        return Colors.teal;
      default:
        return Colors.grey;
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
        Text(
          title,
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w600,
            color: theme.colorScheme.primary,
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
      child: Text(label, style: Theme.of(context).textTheme.labelSmall),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  const _InfoRow(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: Theme.of(context).textTheme.bodySmall),
          Text(
            value,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w500),
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
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colorScheme.tertiaryContainer,
        border: Border.all(color: colorScheme.tertiary),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(Icons.warning_amber, color: colorScheme.tertiary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
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
            ),
          ),
          const SizedBox(width: 12),
          FilledButton.tonal(
            onPressed: () => context.go('/mirror/font-pack'),
            child: Text(tr(context, 'fontpack_download')),
          ),
        ],
      ),
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
        Text(label, style: theme.textTheme.bodySmall),
        const Spacer(),
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
      content: SizedBox(
        width: 380,
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
                  Row(
                    children: [
                      Text(
                        title,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (tag != null) ...[
                        const SizedBox(width: 8),
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
                          child: Text(
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
              Icons.arrow_forward_ios,
              size: 16,
              color: colorScheme.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
  }
}
