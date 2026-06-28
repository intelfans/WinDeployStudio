import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/constants/app_constants.dart';
import '../../core/localization/strings.dart';
import '../../app/typography.dart';
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
  @override
  void initState() {
    super.initState();
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted) {
        _checkForUpdate();
      }
    });
  }

  Future<void> _checkForUpdate() async {
    final notifier = ref.read(updateProvider.notifier);
    final autoCheck = ref.read(updateProvider).autoCheckEnabled;

    if (!autoCheck) return;

    await notifier.checkForUpdate();

    if (mounted) {
      final state = ref.read(updateProvider);
      if (state.status == UpdateStatus.available && state.info != null) {
        UpdateDialog.show(context);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final screenWidth = MediaQuery.of(context).size.width;
    final isCompact = screenWidth < 900;

    return Scaffold(
      body: SingleChildScrollView(
        padding: EdgeInsets.all(isCompact ? 16 : 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
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
                        style: AppTypography.pageTitleWith(
                          colorScheme.onSurface,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        tr(context, 'home_subtitle'),
                        style: AppTypography.bodyWith(
                          colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 40),

            // Quick Actions
            Text(
              tr(context, 'home_quick_start'),
              style: AppTypography.sectionTitleWith(colorScheme.onSurface),
            ),
            const SizedBox(height: 20),

            // Quick Actions Grid
            if (isCompact)
              _buildCompactGrid(context)
            else
              _buildExpandedGrid(context),

            const SizedBox(height: 40),

            // About Section
            Text(
              tr(context, 'home_about'),
              style: AppTypography.sectionTitleWith(colorScheme.onSurface),
            ),
            const SizedBox(height: 20),
            _buildAboutCard(context, colorScheme),
          ],
        ),
      ),
    );
  }

  Widget _buildCompactGrid(BuildContext context) {
    return Column(
      children: [
        IntrinsicHeight(
          child: Row(
            children: [
              Expanded(
                child: _QuickActionCard(
                  icon: Icons.usb_outlined,
                  title: tr(context, 'home_bootable_usb'),
                  subtitle: tr(context, 'home_bootable_usb_desc'),
                  color: const Color(0xFF0071C5),
                  onTap: () => context.go('/creator'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _QuickActionCard(
                  icon: Icons.computer_outlined,
                  title: tr(context, 'home_wtg'),
                  subtitle: tr(context, 'home_wtg_desc'),
                  color: const Color(0xFF7B61FF),
                  onTap: () => context.go('/wtg'),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        IntrinsicHeight(
          child: Row(
            children: [
              Expanded(
                child: _QuickActionCard(
                  icon: Icons.cloud_outlined,
                  title: tr(context, 'home_image_library'),
                  subtitle: tr(context, 'home_image_library_desc'),
                  color: const Color(0xFF00A4EF),
                  onTap: () => context.go('/mirror'),
                ),
              ),
              if (_isChineseLocale(context)) ...[
                const SizedBox(width: 12),
                Expanded(
                  child: _QuickActionCard(
                    icon: Icons.font_download_outlined,
                    title: tr(context, 'home_font_pack'),
                    subtitle: tr(context, 'home_font_pack_desc'),
                    color: const Color(0xFF107C10),
                    onTap: () => context.go('/mirror/font-pack'),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildExpandedGrid(BuildContext context) {
    return IntrinsicHeight(
      child: Row(
        children: [
          Expanded(
            child: _QuickActionCard(
              icon: Icons.usb_outlined,
              title: tr(context, 'home_bootable_usb'),
              subtitle: tr(context, 'home_bootable_usb_desc'),
              color: const Color(0xFF0071C5),
              onTap: () => context.go('/creator'),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: _QuickActionCard(
              icon: Icons.computer_outlined,
              title: tr(context, 'home_wtg'),
              subtitle: tr(context, 'home_wtg_desc'),
              color: const Color(0xFF7B61FF),
              onTap: () => context.go('/wtg'),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: _QuickActionCard(
              icon: Icons.cloud_outlined,
              title: tr(context, 'home_image_library'),
              subtitle: tr(context, 'home_image_library_desc'),
              color: const Color(0xFF00A4EF),
              onTap: () => context.go('/mirror'),
            ),
          ),
          if (_isChineseLocale(context)) ...[
            const SizedBox(width: 16),
            Expanded(
              child: _QuickActionCard(
                icon: Icons.font_download_outlined,
                title: tr(context, 'home_font_pack'),
                subtitle: tr(context, 'home_font_pack_desc'),
                color: const Color(0xFF107C10),
                onTap: () => context.go('/mirror/font-pack'),
              ),
            ),
          ],
        ],
      ),
    );
  }

  bool _isChineseLocale(BuildContext context) {
    final locale = Localizations.localeOf(context);
    return locale.languageCode == 'zh';
  }

  Widget _buildAboutCard(BuildContext context, ColorScheme colorScheme) {
    return Card(
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

class _QuickActionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  const _QuickActionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(icon, size: 28, color: color),
              ),
              const SizedBox(height: 16),
              Text(
                title,
                style: AppTypography.cardTitleWith(theme.colorScheme.onSurface),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: AppTypography.captionWith(
                  theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
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
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
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
      ),
    );
  }
}
