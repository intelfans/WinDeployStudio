import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../app/theme.dart';
import '../../../core/localization/strings.dart';
import '../../../shared/widgets/app_compact_label.dart';
import '../../../shared/widgets/app_page.dart';
import '../providers/mirror_provider.dart';
import '../models/mirror_models.dart';

class MirrorScreen extends ConsumerStatefulWidget {
  const MirrorScreen({super.key});

  @override
  ConsumerState<MirrorScreen> createState() => _MirrorScreenState();
}

class _MirrorScreenState extends ConsumerState<MirrorScreen> {
  String? _selectedCategory;

  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      ref.read(mirrorProvider.notifier).loadBuiltInMirrors();
    });
  }

  @override
  Widget build(BuildContext context) {
    final mirrorState = ref.watch(mirrorProvider);
    final locale = Localizations.localeOf(context);
    final tokens = AppVisualTokens.of(context);

    return Scaffold(
      body: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 600;
          return Padding(
            padding: EdgeInsets.all(compact ? 16 : tokens.pagePadding),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AppPageHeader(
                  icon: Icons.cloud_outlined,
                  title: tr(context, 'images_title'),
                  subtitle: tr(context, 'images_subtitle'),
                ),
                SizedBox(height: tokens.sectionSpacing),
                Expanded(child: _buildContent(mirrorState, locale)),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildContent(MirrorState state, Locale locale) {
    switch (state.status) {
      case MirrorLoadStatus.initial:
      case MirrorLoadStatus.loading:
        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 16),
              Text(tr(context, 'images_loading')),
            ],
          ),
        );

      case MirrorLoadStatus.error:
        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.error_outline,
                size: 48,
                color: Theme.of(context).colorScheme.error,
              ),
              const SizedBox(height: 16),
              Text(
                state.error == null
                    ? tr(context, 'images_error')
                    : '${tr(context, 'mirror_error_loading')} ${state.error}',
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: () => ref
                    .read(mirrorProvider.notifier)
                    .loadBuiltInMirrors(force: true),
                icon: const Icon(Icons.refresh),
                label: Text(tr(context, 'images_retry')),
              ),
            ],
          ),
        );

      case MirrorLoadStatus.loaded:
        final categories = state.data?.categories(locale) ?? [];
        if (categories.isEmpty && state.localIsos.isEmpty) {
          return Center(child: Text(tr(context, 'images_empty')));
        }
        return _buildMirrorList(categories, state.localIsos, locale);
    }
  }

  Widget _buildMirrorList(
    List<MirrorCategory> categories,
    List<LocalIsoInfo> localIsos,
    Locale locale,
  ) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 680) {
          return Column(
            children: [
              DropdownButtonFormField<String>(
                initialValue: _selectedCategory ?? '__all__',
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: tr(context, 'images_category_all'),
                  prefixIcon: const Icon(Icons.filter_list),
                ),
                items: [
                  DropdownMenuItem(
                    value: '__all__',
                    child: Text(tr(context, 'images_category_all')),
                  ),
                  for (final category in categories)
                    DropdownMenuItem(
                      value: category.id,
                      child: Text(
                        category.name,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  if (localIsos.isNotEmpty)
                    DropdownMenuItem(
                      value: '__local__',
                      child: Text(tr(context, 'images_local_library')),
                    ),
                ],
                onChanged: (value) => setState(
                  () => _selectedCategory = value == '__all__' ? null : value,
                ),
              ),
              const SizedBox(height: 12),
              Expanded(child: _buildItemsList(categories, localIsos, locale)),
            ],
          );
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 252,
              child: Card(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    _CategoryTile(
                      label: tr(context, 'images_category_all'),
                      icon: Icons.apps,
                      count:
                          categories.fold(
                            0,
                            (sum, category) => sum + category.items.length,
                          ) +
                          localIsos.length,
                      isSelected: _selectedCategory == null,
                      onTap: () => setState(() => _selectedCategory = null),
                    ),
                    ...categories.map(
                      (category) => _CategoryTile(
                        label: category.name,
                        icon: _getCategoryIcon(category.icon),
                        count: category.items.length,
                        isSelected: _selectedCategory == category.id,
                        skillLevel: category.items.first.skillLevel,
                        onTap: () =>
                            setState(() => _selectedCategory = category.id),
                      ),
                    ),
                    if (localIsos.isNotEmpty)
                      _CategoryTile(
                        label: tr(context, 'images_local_library'),
                        icon: Icons.folder,
                        count: localIsos.length,
                        isSelected: _selectedCategory == '__local__',
                        onTap: () =>
                            setState(() => _selectedCategory = '__local__'),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(child: _buildItemsList(categories, localIsos, locale)),
          ],
        );
      },
    );
  }

  Widget _buildItemsList(
    List<MirrorCategory> categories,
    List<LocalIsoInfo> localIsos,
    Locale locale,
  ) {
    if (_selectedCategory == '__local__') {
      return _buildLocalIsoList(localIsos);
    }

    List<MirrorItem> items;
    if (_selectedCategory == null) {
      items = categories.expand((c) => c.items).toList();
    } else {
      final cat = categories
          .where((c) => c.id == _selectedCategory)
          .firstOrNull;
      items = cat?.items ?? [];
    }

    return ListView(
      children: [
        const _ArchitectureNotice(),
        const SizedBox(height: 12),
        ...items.map((item) => _MirrorItemCard(item: item, locale: locale)),
        if (_selectedCategory == null && localIsos.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.only(top: 16, bottom: 8),
            child: Text(
              tr(context, 'images_local_library'),
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
          ),
          ...localIsos.map((iso) => _LocalIsoCard(iso: iso)),
        ],
      ],
    );
  }

  Widget _buildLocalIsoList(List<LocalIsoInfo> localIsos) {
    if (localIsos.isEmpty) {
      return Center(child: Text(tr(context, 'images_local_empty')));
    }
    return ListView.builder(
      itemCount: localIsos.length,
      itemBuilder: (context, index) => _LocalIsoCard(iso: localIsos[index]),
    );
  }

  IconData _getCategoryIcon(String icon) {
    switch (icon) {
      case 'official':
        return Icons.verified;
      case 'community':
        return Icons.groups_outlined;
      case 'ltsc':
        return Icons.admin_panel_settings_outlined;
      case 'tools':
        return Icons.build;
      default:
        return Icons.folder;
    }
  }
}

class _CategoryTile extends StatelessWidget {
  final String label;
  final IconData icon;
  final int count;
  final bool isSelected;
  final VoidCallback onTap;
  final MirrorSkillLevel? skillLevel;
  const _CategoryTile({
    required this.label,
    required this.icon,
    required this.count,
    required this.isSelected,
    required this.onTap,
    this.skillLevel,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      minLeadingWidth: 30,
      leading: Icon(icon, size: 20),
      title: Tooltip(
        message: label,
        child: Text(
          label,
          maxLines: 1,
          softWrap: false,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
          ),
        ),
      ),
      subtitle: Row(
        children: [
          AppCompactLabel(
            '$count',
            style: theme.textTheme.labelSmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          if (skillLevel != null) ...[
            const Spacer(),
            Tooltip(
              message: tr(context, skillLevel!.tooltipKey),
              child: AppCompactLabel(
                tr(context, skillLevel!.labelKey),
                style: theme.textTheme.labelSmall?.copyWith(
                  color: _skillColor(skillLevel!, colorScheme),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ],
      ),
      selected: isSelected,
      selectedTileColor: colorScheme.primaryContainer.withValues(alpha: 0.3),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      onTap: onTap,
    );
  }

  Color _skillColor(MirrorSkillLevel level, ColorScheme colorScheme) {
    return switch (level) {
      MirrorSkillLevel.beginner => colorScheme.primary,
      MirrorSkillLevel.advanced => colorScheme.tertiary,
      MirrorSkillLevel.expert => colorScheme.error,
    };
  }
}

class _MirrorItemCard extends StatelessWidget {
  final MirrorItem item;
  final Locale locale;
  const _MirrorItemCard({required this.item, required this.locale});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final name = item.getName(locale);
    final type = item.getType(locale);
    final size = item.getSize(locale);
    final badgeLabel = item.isOfficialMicrosoft
        ? tr(context, 'mirror_badge_official')
        : item.isCommunityImage
        ? tr(context, 'mirror_badge_community')
        : item.isEnterpriseLtsc
        ? tr(context, 'mirror_badge_ltsc')
        : '';
    final trustText = item.isOfficialMicrosoft
        ? tr(context, 'mirror_desc_official')
        : item.isCommunityImage
        ? tr(context, 'mirror_desc_community')
        : item.isEnterpriseLtsc
        ? tr(context, 'mirror_desc_ltsc')
        : '';
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => context.go('/mirror/${item.id}', extra: item),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: _catColor(item.category).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  item.isFontPack ? Icons.build : _catIcon(item.category),
                  color: _catColor(item.category),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: [
                        if (badgeLabel.isNotEmpty)
                          _buildTag(
                            context,
                            badgeLabel,
                            _catColor(item.category),
                          ),
                        Tooltip(
                          message: tr(context, item.skillLevel.tooltipKey),
                          child: _buildTag(
                            context,
                            tr(context, item.skillLevel.labelKey),
                            _skillColor(item.skillLevel, theme.colorScheme),
                          ),
                        ),
                        if (item.version != null)
                          _buildTag(
                            context,
                            item.version!,
                            const Color(0xFF0071C5),
                          ),
                        if (item.build != null)
                          _buildTag(
                            context,
                            item.build!,
                            const Color(0xFF107C10),
                          ),
                        if (item.architecture != null)
                          _buildTag(
                            context,
                            item.architecture!,
                            const Color(0xFF5C2D91),
                          ),
                      ],
                    ),
                    if (trustText.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        trustText,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.primary,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                    if (type.isNotEmpty || size != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        [if (type.isNotEmpty) type, ?size].join(' / '),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              Icon(
                Directionality.of(context) == TextDirection.rtl
                    ? Icons.chevron_left
                    : Icons.chevron_right,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTag(BuildContext context, String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: AppCompactLabel(
        label,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
          color: color,
          fontWeight: FontWeight.w500,
          fontSize: 11,
        ),
      ),
    );
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
      default:
        return Colors.grey;
    }
  }

  Color _skillColor(MirrorSkillLevel level, ColorScheme colorScheme) {
    return switch (level) {
      MirrorSkillLevel.beginner => colorScheme.primary,
      MirrorSkillLevel.advanced => colorScheme.tertiary,
      MirrorSkillLevel.expert => colorScheme.error,
    };
  }
}

class _ArchitectureNotice extends StatelessWidget {
  const _ArchitectureNotice();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return AppInfoBox(
      icon: Icons.memory_outlined,
      child: Text(
        tr(context, 'mirror_arch_notice'),
        style: theme.textTheme.bodyMedium?.copyWith(
          color: colorScheme.onSurface,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _LocalIsoCard extends StatelessWidget {
  final LocalIsoInfo iso;
  const _LocalIsoCard({required this.iso});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Icon(Icons.album, color: theme.colorScheme.primary),
        title: Text(iso.fileName, overflow: TextOverflow.ellipsis),
        subtitle: Text(iso.displaySize),
        trailing: const Icon(Icons.folder_outlined, size: 20),
      ),
    );
  }
}
