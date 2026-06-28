import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/localization/strings.dart';
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
    final theme = Theme.of(context);
    final mirrorState = ref.watch(mirrorProvider);
    final locale = Localizations.localeOf(context);

    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        tr(context, 'images_title'),
                        style: theme.textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        tr(context, 'images_subtitle'),
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.refresh),
                  tooltip: tr(context, 'images_retry'),
                  onPressed: () => ref
                      .read(mirrorProvider.notifier)
                      .loadBuiltInMirrors(force: true),
                ),
              ],
            ),
            const SizedBox(height: 24),
            Expanded(child: _buildContent(mirrorState, locale)),
          ],
        ),
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
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 200,
          child: Card(
            child: ListView(
              shrinkWrap: true,
              children: [
                _CategoryTile(
                  label: tr(context, 'images_category_all'),
                  icon: Icons.apps,
                  count:
                      categories.fold(0, (sum, c) => sum + c.items.length) +
                      localIsos.length,
                  isSelected: _selectedCategory == null,
                  onTap: () => setState(() => _selectedCategory = null),
                ),
                ...categories.map(
                  (cat) => _CategoryTile(
                    label: cat.name,
                    icon: _getCategoryIcon(cat.icon),
                    count: cat.items.length,
                    isSelected: _selectedCategory == cat.id,
                    onTap: () => setState(() => _selectedCategory = cat.id),
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
  const _CategoryTile({
    required this.label,
    required this.icon,
    required this.count,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListTile(
      leading: Icon(icon, size: 20),
      title: Text(label, style: theme.textTheme.bodyMedium),
      trailing: Text(
        '$count',
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
      selected: isSelected,
      selectedTileColor: theme.colorScheme.primaryContainer.withValues(
        alpha: 0.3,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      onTap: onTap,
    );
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
    final badgeLabel = item.isOfficialMicrosoft
        ? tr(context, 'mirror_badge_official')
        : item.isCommunityImage
        ? tr(context, 'mirror_badge_community')
        : '';
    final trustText = item.isOfficialMicrosoft
        ? tr(context, 'mirror_desc_official')
        : item.isCommunityImage
        ? tr(context, 'mirror_desc_community')
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
                  _catIcon(item.category),
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
                    if (type.isNotEmpty || item.size != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        [
                          if (type.isNotEmpty) type,
                          if (item.size != null) item.size,
                        ].join(' / '),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right,
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
      child: Text(
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
        return Icons.verified;
      case 'Community Images':
        return Icons.groups_outlined;
      default:
        return Icons.folder;
    }
  }

  Color _catColor(String category) {
    switch (category) {
      case 'Official Microsoft':
        return const Color(0xFF0071C5);
      case 'Community Images':
        return const Color(0xFF008272);
      default:
        return Colors.grey;
    }
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
