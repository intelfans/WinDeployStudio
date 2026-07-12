import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/typography.dart';
import '../../core/constants/app_constants.dart';
import '../../core/localization/strings.dart';
import '../../shared/widgets/special_thanks_section.dart';
import '../update/models/update_models.dart';
import '../update/providers/update_provider.dart';
import '../update/screens/update_dialog.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  Timer? _updateTimer;

  @override
  void initState() {
    super.initState();
    _updateTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) _checkForUpdate();
    });
  }

  @override
  void dispose() {
    _updateTimer?.cancel();
    super.dispose();
  }

  Future<void> _checkForUpdate() async {
    final notifier = ref.read(updateProvider.notifier);
    if (!ref.read(updateProvider).autoCheckEnabled) return;

    await notifier.checkForUpdate();
    if (!mounted) return;
    final state = ref.read(updateProvider);
    if (state.status == UpdateStatus.available && state.info != null) {
      UpdateDialog.show(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      body: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 900;
          final padding = compact ? 16.0 : 32.0;
          return SingleChildScrollView(
            padding: EdgeInsets.all(padding),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1680),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _HomeHeader(colorScheme: colorScheme),
                  SizedBox(height: compact ? 32 : 40),
                  Text(
                    tr(context, 'home_quick_start'),
                    style: AppTypography.sectionTitleWith(
                      colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 20),
                  const _QuickStartGrid(),
                  SizedBox(height: compact ? 32 : 40),
                  Text(
                    tr(context, 'home_about'),
                    style: AppTypography.sectionTitleWith(
                      colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 20),
                  const _AboutCard(),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _HomeHeader extends StatelessWidget {
  const _HomeHeader({required this.colorScheme});

  final ColorScheme colorScheme;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            color: colorScheme.primaryContainer,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Icon(
            Icons.desktop_windows_rounded,
            size: 32,
            color: colorScheme.onPrimaryContainer,
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                tr(context, 'home_title'),
                style: AppTypography.pageTitleWith(colorScheme.onSurface),
              ),
              const SizedBox(height: 4),
              Text(
                tr(context, 'home_subtitle'),
                style: AppTypography.bodyWith(colorScheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _QuickStartGrid extends StatelessWidget {
  const _QuickStartGrid();

  static const _gap = 16.0;
  static const _threeColumnBreakpoint = 720.0;
  static const _twoColumnBreakpoint = 480.0;

  @override
  Widget build(BuildContext context) {
    final cards = <Widget>[
      _QuickActionCard(
        key: const ValueKey('home-quick-action-image-library'),
        icon: Icons.cloud_outlined,
        title: tr(context, 'home_image_library'),
        subtitle: tr(context, 'home_image_library_desc'),
        color: const Color(0xFF00A4EF),
        onTap: () => context.go('/mirror'),
      ),
      _QuickActionCard(
        key: const ValueKey('home-quick-action-install-media'),
        icon: Icons.usb_outlined,
        title: tr(context, 'home_bootable_usb'),
        subtitle: tr(context, 'home_bootable_usb_desc'),
        color: const Color(0xFF0071C5),
        onTap: () => context.go('/creator'),
      ),
      _QuickActionCard(
        key: const ValueKey('home-quick-action-to-go'),
        icon: Icons.computer_outlined,
        title: tr(context, 'home_wtg'),
        subtitle: tr(context, 'home_wtg_desc'),
        color: const Color(0xFF7B61FF),
        onTap: () => context.go('/wtg'),
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        // This receives the content pane width, rather than the full window
        // width. Keep three useful actions side by side at ordinary desktop
        // sizes even when the navigation pane is expanded.
        if (constraints.maxWidth >= _threeColumnBreakpoint) {
          return _ActionRow(cards: cards);
        }

        if (constraints.maxWidth >= _twoColumnBreakpoint) {
          return Column(
            children: [
              _ActionRow(cards: cards.take(2).toList(growable: false)),
              const SizedBox(height: _gap),
              SizedBox(width: double.infinity, child: cards[2]),
            ],
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var index = 0; index < cards.length; index++) ...[
              cards[index],
              if (index != cards.length - 1) const SizedBox(height: 12),
            ],
          ],
        );
      },
    );
  }
}

class _ActionRow extends StatelessWidget {
  const _ActionRow({required this.cards});

  final List<Widget> cards;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var index = 0; index < cards.length; index++) ...[
              Expanded(child: cards[index]),
              if (index != cards.length - 1)
                const SizedBox(width: _QuickStartGrid._gap),
            ],
          ],
        ),
      ),
    );
  }
}

class _QuickActionCard extends StatelessWidget {
  const _QuickActionCard({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 156),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(icon, size: 26, color: color),
                    ),
                    const Spacer(),
                    Icon(
                      Icons.arrow_forward_rounded,
                      size: 20,
                      color: colors.onSurfaceVariant,
                    ),
                  ],
                ),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.cardTitleWith(colors.onSurface),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.captionWith(colors.onSurfaceVariant),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AboutCard extends StatelessWidget {
  const _AboutCard();

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            _InfoRow(tr(context, 'home_version'), AppConstants.appVersion),
            _InfoRow(tr(context, 'home_platform'), 'Windows Desktop'),
            _InfoRow(tr(context, 'home_engine'), 'Flutter 3.44'),
            const Divider(),
            _InfoRow(
              tr(context, 'home_focus'),
              tr(context, 'home_focus_value'),
            ),
            _InfoRow(tr(context, 'home_license'), AppConstants.licenseName),
            _InfoRow(
              tr(context, 'about_github_repository'),
              AppConstants.githubRepository,
            ),
            const SizedBox(height: 12),
            const SpecialThanksSection(compact: true),
          ],
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final stacked = constraints.maxWidth < 460;
          if (stacked) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: AppTypography.bodyWith(colorScheme.onSurfaceVariant),
                ),
                const SizedBox(height: 4),
                SelectableText(
                  value,
                  style: AppTypography.body.copyWith(
                    color: colorScheme.onSurface,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            );
          }

          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 150,
                child: Text(
                  label,
                  style: AppTypography.bodyWith(colorScheme.onSurfaceVariant),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: SelectableText(
                  value,
                  textAlign: TextAlign.end,
                  style: AppTypography.body.copyWith(
                    color: colorScheme.onSurface,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
