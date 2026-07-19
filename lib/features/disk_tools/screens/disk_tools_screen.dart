import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../app/typography.dart';
import '../../../shared/widgets/app_navigation_shell.dart';
import '../localization/disk_tools_localization.dart';

class DiskToolsScreen extends StatelessWidget {
  const DiskToolsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: Text(diskToolsText(context, 'disk_tools_title'))),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 980),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  diskToolsText(context, 'disk_tools_title'),
                  style: AppTypography.pageTitleWith(colors.onSurface),
                ),
                const SizedBox(height: 6),
                Text(
                  diskToolsText(context, 'disk_tools_subtitle'),
                  style: AppTypography.bodyWith(colors.onSurfaceVariant),
                ),
                const SizedBox(height: 24),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final compact = constraints.maxWidth < 720;
                    final width = compact
                        ? constraints.maxWidth
                        : (constraints.maxWidth - 16) / 2;
                    return Wrap(
                      spacing: 16,
                      runSpacing: 16,
                      children: [
                        SizedBox(
                          width: width,
                          child: _ToolEntry(
                            key: AppNavigationKeys.diskDiagnosticsKey,
                            icon: Icons.monitor_heart_outlined,
                            titleKey: 'disk_tools_diagnostics_title',
                            descriptionKey: 'disk_tools_diagnostics_desc',
                            onOpen: () => context.go('/disk-tools/diagnostics'),
                          ),
                        ),
                        SizedBox(
                          width: width,
                          child: _ToolEntry(
                            key: AppNavigationKeys.bootRepairKey,
                            icon: Icons.settings_input_component_rounded,
                            titleKey: 'disk_tools_boot_repair_title',
                            descriptionKey: 'disk_tools_boot_repair_desc',
                            onOpen: () => context.go('/disk-tools/boot-repair'),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ToolEntry extends StatelessWidget {
  final IconData icon;
  final String titleKey;
  final String descriptionKey;
  final VoidCallback onOpen;

  const _ToolEntry({
    super.key,
    required this.icon,
    required this.titleKey,
    required this.descriptionKey,
    required this.onOpen,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onOpen,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: colors.primaryContainer,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: colors.onPrimaryContainer),
              ),
              const SizedBox(height: 16),
              Text(
                diskToolsText(context, titleKey),
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 6),
              SizedBox(
                height: 64,
                child: Text(
                  diskToolsText(context, descriptionKey),
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton.icon(
                  onPressed: onOpen,
                  icon: const Icon(Icons.open_in_new_rounded),
                  label: Text(diskToolsText(context, 'disk_tools_open')),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
