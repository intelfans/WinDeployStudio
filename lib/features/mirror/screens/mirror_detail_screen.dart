import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/localization/strings.dart';
import '../../../core/services/mirror_speed_test_service.dart';
import '../models/mirror_models.dart';
import '../providers/mirror_source_provider.dart';
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
    _runSpeedTest();
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
                ? Column(children: [
                    _buildInfoSection(context, locale),
                    const SizedBox(height: 24),
                    _buildSpeedTestCard(context),
                    const SizedBox(height: 24),
                    _buildDownloadSection(context, locale),
                  ])
                : Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(flex: 2, child: _buildInfoSection(context, locale)),
                      const SizedBox(width: 24),
                      Expanded(flex: 1, child: Column(children: [
                        _buildSpeedTestCard(context),
                        const SizedBox(height: 16),
                        _buildDownloadSection(context, locale),
                      ])),
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
          child: Icon(_catIcon(widget.item.category),
              size: 32, color: _catColor(widget.item.category)),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(name,
                  style: theme.textTheme.headlineSmall
                      ?.copyWith(fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  if (type.isNotEmpty) _Tag(type),
                  if (widget.item.version != null) _Tag(widget.item.version!),
                  if (widget.item.build != null) _Tag(widget.item.build!),
                  if (widget.item.architecture != null) _Tag(widget.item.architecture!),
                  if (widget.item.size != null) _Tag(widget.item.size!),
                ],
              ),
            ],
          ),
        ),
      ],
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
                Text(tr(context, 'mirror_speed_test_title'),
                    style: theme.textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.w600)),
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
                    width: 16, height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  const SizedBox(width: 12),
                  Text(tr(context, 'mirror_speed_test_testing'),
                      style: theme.textTheme.bodySmall),
                ],
              )
            else if (_testResult == null)
              Text(tr(context, 'mirror_speed_test_failed'),
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: colorScheme.error))
            else ...[
              _MirrorStatusRow(
                label: 'China Mirror',
                online: _testResult!.china.online,
                latency: _testResult!.china.latency,
              ),
              const SizedBox(height: 8),
              _MirrorStatusRow(
                label: 'Global Mirror',
                online: _testResult!.global.online,
                latency: _testResult!.global.latency,
              ),
              if (_testResult!.bothOffline) ...[
                const SizedBox(height: 12),
                Text(tr(context, 'mirror_speed_test_all_offline'),
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: colorScheme.error)),
              ] else ...[
                const Divider(height: 20),
                Row(
                  children: [
                    Icon(Icons.recommend, size: 16, color: Colors.green),
                    const SizedBox(width: 6),
                    Text('${tr(context, 'mirror_speed_test_recommend')}: ',
                        style: theme.textTheme.bodySmall),
                    Text(
                      _testResult!.recommendedSource == 'china'
                          ? 'China Mirror'
                          : 'Global Mirror',
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
          ...pros.map((p) => Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('•  ',
                        style: TextStyle(color: Colors.green.shade600)),
                    Expanded(
                        child: Text(p, style: theme.textTheme.bodyMedium)),
                  ],
                ),
              )),
          const SizedBox(height: 20),
        ],
        if (notes.isNotEmpty) ...[
          _SectionTitle(Icons.info_outline, tr(context, 'detail_notes')),
          const SizedBox(height: 8),
          ...notes.map((n) => Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('•  ',
                        style: TextStyle(color: Colors.orange.shade700)),
                    Expanded(
                        child: Text(n, style: theme.textTheme.bodyMedium)),
                  ],
                ),
              )),
        ],
        if (widget.item.sha256 != null && widget.item.sha256!.isNotEmpty) ...[
          const SizedBox(height: 20),
          _SectionTitle(Icons.fingerprint, 'SHA256'),
          const SizedBox(height: 8),
          InkWell(
            onTap: () {
              Clipboard.setData(ClipboardData(text: widget.item.sha256!));
              ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(tr(context, 'detail_sha256_copied'))));
            },
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest
                    .withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Row(children: [
                Expanded(
                    child: Text(widget.item.sha256!,
                        style: theme.textTheme.bodySmall
                            ?.copyWith(fontFamily: 'Consolas'),
                        overflow: TextOverflow.ellipsis)),
                const SizedBox(width: 8),
                Icon(Icons.copy, size: 14, color: theme.colorScheme.primary),
              ]),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildDownloadSection(BuildContext context, Locale locale) {
    final theme = Theme.of(context);
    final description = widget.item.getDescription(locale);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(tr(context, 'detail_download'),
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w600)),
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
                  Clipboard.setData(ClipboardData(text: widget.item.downloadUrl));
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                      content: Text(tr(context, 'detail_link_copied'))));
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
    final name = widget.item.getName(locale);

    final selectedMirror = await showDialog<String>(
      context: context,
      builder: (ctx) => _MirrorSelectionDialog(
        itemName: name,
        chinaUrl: widget.item.chinaUrl,
        globalUrl: widget.item.globalUrl,
      ),
    );

    if (selectedMirror == null || !context.mounted) return;

    String url;
    String mirrorLabel;

    if (selectedMirror == 'china') {
      url = widget.item.chinaUrl ?? widget.item.downloadUrl;
      mirrorLabel = 'China Mirror';
    } else {
      url = widget.item.globalUrl ?? widget.item.downloadUrl;
      mirrorLabel = 'Global Mirror';
    }

    final logCenter = LogCenterService();
    await logCenter.logDownload(
      '[MirrorSource] Selected=$mirrorLabel Mirror=$name URL=$url',
    );

    if (context.mounted) {
      await WebviewHelper.openUrl(context, url, title: name);
    }
  }

  IconData _catIcon(String category) {
    switch (category) {
      case 'Official Original':
      case 'Official LTSC':
        return Icons.verified;
      case 'TinyOS':
        return Icons.compress;
      case 'X-Lite':
        return Icons.speed;
      case 'Custom':
        return Icons.palette;
      case 'Tools':
        return Icons.build;
      default:
        return Icons.folder;
    }
  }

  Color _catColor(String category) {
    switch (category) {
      case 'Official Original':
      case 'Official LTSC':
        return Colors.blue;
      case 'TinyOS':
        return Colors.green;
      case 'X-Lite':
        return Colors.orange;
      case 'Custom':
        return Colors.purple;
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
    return Row(children: [
      Icon(icon, size: 18, color: theme.colorScheme.primary),
      const SizedBox(width: 8),
      Text(title,
          style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w600,
              color: theme.colorScheme.primary)),
    ]);
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
        color: Theme.of(context)
            .colorScheme
            .surfaceContainerHighest
            .withValues(alpha: 0.5),
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
          Text(value,
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(fontWeight: FontWeight.w500)),
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
      child: Row(children: [
        Icon(Icons.warning_amber, color: colorScheme.tertiary),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(tr(context, 'fontpack_warning'),
                  style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: colorScheme.onTertiaryContainer)),
              const SizedBox(height: 4),
              Text(tr(context, 'fontpack_recommend'),
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: colorScheme.onTertiaryContainer)),
            ],
          ),
        ),
        const SizedBox(width: 12),
        FilledButton.tonal(
          onPressed: () => context.go('/mirror/font-pack'),
          child: Text(tr(context, 'fontpack_download')),
        ),
      ]),
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

  const _MirrorSelectionDialog({
    required this.itemName,
    this.chinaUrl,
    this.globalUrl,
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
                tag: tr(context, 'mirror_china_tag'),
                tagColor: Colors.blue,
                onTap: () => Navigator.of(context).pop('china'),
              ),
            if (hasChina && hasGlobal) const SizedBox(height: 12),
            if (hasGlobal)
              _MirrorOption(
                icon: Icons.public_outlined,
                title: tr(context, 'mirror_global_title'),
                subtitle: tr(context, 'mirror_global_desc'),
                tag: tr(context, 'mirror_global_tag'),
                tagColor: Colors.green,
                onTap: () => Navigator.of(context).pop('global'),
              ),
            if (!hasChina && !hasGlobal) ...[
              _MirrorOption(
                icon: Icons.download_outlined,
                title: tr(context, 'mirror_default_title'),
                subtitle: tr(context, 'mirror_default_desc'),
                tag: null,
                onTap: () => Navigator.of(context).pop('default'),
              ),
            ],
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
                            color: (tagColor ?? colorScheme.primary)
                                .withValues(alpha: 0.1),
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
