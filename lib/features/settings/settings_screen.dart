import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/config/ai_config.dart';
import '../../core/constants/app_constants.dart';
import '../../core/localization/strings.dart';
import '../../app/theme.dart';
import '../logs/services/log_center_service.dart';
import '../update/models/update_models.dart';
import '../update/providers/update_provider.dart';
import '../update/screens/update_dialog.dart';
import '../../shared/widgets/app_compact_label.dart';
import '../../shared/widgets/app_page.dart';
import '../../shared/widgets/special_thanks_section.dart';
import '../ai_assistant/services/ai_service.dart';
import '../onboarding/onboarding_overlay.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  static const _requiredEasterEggTaps = 5;
  static const _requiredIntelLogoTaps = 5;
  static const _easterEggResetDelay = Duration(seconds: 3);

  Timer? _easterEggResetTimer;
  Timer? _intelLogoResetTimer;
  int _easterEggTapCount = 0;
  int _intelLogoTapCount = 0;
  String? _aiEndpointUrl;
  bool _aiApiKeyConfigured = false;
  String? _aiModel;

  bool get _usesDefaultAiService =>
      _aiEndpointUrl == null || _aiEndpointUrl == AiConfig.defaultEndpointUrl;

  @override
  void initState() {
    super.initState();
    _loadAiPreferences();
  }

  @override
  void dispose() {
    _easterEggResetTimer?.cancel();
    _intelLogoResetTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadAiPreferences() async {
    final url = await AiConfig.getEndpointUrl();
    final apiKey = await AiConfig.getApiKey();
    final model = await AiConfig.getModel();
    if (mounted) {
      setState(() {
        _aiEndpointUrl = url;
        _aiApiKeyConfigured = apiKey != null;
        // The built-in worker has an internal model fallback. Do not expose
        // that implementation detail as a provider-branded default in UI.
        _aiModel =
            url == AiConfig.defaultEndpointUrl && model == AiConfig.defaultModel
            ? null
            : model.isEmpty
            ? null
            : model;
      });
    }
  }

  void _handleEasterEggTap() {
    _easterEggResetTimer?.cancel();
    _easterEggTapCount += 1;
    if (_easterEggTapCount >= _requiredEasterEggTaps) {
      _easterEggTapCount = 0;
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        barrierColor: Colors.black,
        builder: (context) => const _EasterEggDialog(),
      );
      return;
    }

    _easterEggResetTimer = Timer(_easterEggResetDelay, () {
      _easterEggTapCount = 0;
    });
  }

  void _handleIntelLogoTap() {
    _intelLogoResetTimer?.cancel();
    _intelLogoTapCount += 1;
    if (_intelLogoTapCount >= _requiredIntelLogoTaps) {
      _intelLogoTapCount = 0;
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (context) => const IntelMuseumDialog(),
      );
      return;
    }

    _intelLogoResetTimer = Timer(_easterEggResetDelay, () {
      _intelLogoTapCount = 0;
    });
  }

  @override
  Widget build(BuildContext context) {
    final themeMode = ref.watch(themeModeProvider);
    final tokens = AppVisualTokens.of(context);

    ref.listen<UpdateState>(updateProvider, (prev, next) {
      if (next.status == UpdateStatus.available && next.info != null) {
        UpdateDialog.show(context);
      } else if (next.status == UpdateStatus.upToDate &&
          prev?.status == UpdateStatus.checking) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(tr(context, 'update_up_to_date')),
            duration: const Duration(seconds: 2),
          ),
        );
      } else if (next.status == UpdateStatus.error &&
          prev?.status == UpdateStatus.checking) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(next.error ?? tr(context, 'update_checking')),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    });

    return Scaffold(
      body: LayoutBuilder(
        builder: (context, constraints) => SingleChildScrollView(
          padding: EdgeInsets.all(
            constraints.maxWidth < 600 ? 16 : tokens.pagePadding,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AppPageHeader(
                icon: Icons.settings_outlined,
                title: tr(context, 'settings_title'),
              ),
              SizedBox(height: tokens.sectionSpacing),
              _SettingsSection(
                title: tr(context, 'settings_appearance'),
                children: [
                  _SettingsTile(
                    icon: Icons.palette_outlined,
                    title: tr(context, 'settings_theme'),
                    subtitle: _themeModeName(themeMode),
                    trailing: DropdownButton<ThemeMode>(
                      value: themeMode,
                      underline: const SizedBox.shrink(),
                      items: [
                        DropdownMenuItem(
                          value: ThemeMode.system,
                          child: Text(tr(context, 'settings_theme_system')),
                        ),
                        DropdownMenuItem(
                          value: ThemeMode.light,
                          child: Text(tr(context, 'settings_theme_light')),
                        ),
                        DropdownMenuItem(
                          value: ThemeMode.dark,
                          child: Text(tr(context, 'settings_theme_dark')),
                        ),
                      ],
                      onChanged: (mode) {
                        if (mode != null) {
                          ref.read(themeModeProvider.notifier).setMode(mode);
                          LogCenterService().logSystem(
                            '[Settings] Theme=${mode.name}',
                          );
                        }
                      },
                    ),
                  ),
                  _SettingsTile(
                    icon: Icons.language,
                    title: tr(context, 'settings_language'),
                    subtitle: tr(context, 'settings_language_desc'),
                    trailing: DropdownButton<Locale>(
                      value: ref.watch(localeProvider),
                      underline: const SizedBox.shrink(),
                      items: const [
                        DropdownMenuItem(
                          value: Locale('zh'),
                          child: Text('简体中文'),
                        ),
                        DropdownMenuItem(
                          value: Locale('zh', 'TW'),
                          child: Text('繁體中文'),
                        ),
                        DropdownMenuItem(
                          value: Locale('en'),
                          child: Text('English'),
                        ),
                        DropdownMenuItem(
                          value: Locale('fr'),
                          child: Text('Français'),
                        ),
                        DropdownMenuItem(
                          value: Locale('de'),
                          child: Text('Deutsch'),
                        ),
                        DropdownMenuItem(
                          value: Locale('es'),
                          child: Text('Español'),
                        ),
                        DropdownMenuItem(
                          value: Locale('pt'),
                          child: Text('Português'),
                        ),
                        DropdownMenuItem(
                          value: Locale('ru'),
                          child: Text('Русский'),
                        ),
                        DropdownMenuItem(
                          value: Locale('ar'),
                          child: Text('العربية'),
                        ),
                        DropdownMenuItem(
                          value: Locale('ko'),
                          child: Text('한국어'),
                        ),
                        DropdownMenuItem(
                          value: Locale('ja'),
                          child: Text('日本語'),
                        ),
                      ],
                      onChanged: (locale) {
                        if (locale != null) {
                          ref.read(localeProvider.notifier).setLocale(locale);
                          LogCenterService().logSystem(
                            '[Settings] Language=${localeCodeFromLocale(locale)}',
                          );
                        }
                      },
                    ),
                  ),
                  _SettingsTile(
                    icon: Icons.font_download_outlined,
                    title: tr(context, 'settings_font'),
                    subtitle: _fontFamilyName(ref.watch(fontFamilyProvider)),
                    trailing: DropdownButton<String>(
                      value: ref.watch(fontFamilyProvider),
                      underline: const SizedBox.shrink(),
                      items: const [
                        DropdownMenuItem(
                          value: 'HarmonyOSSans',
                          child: Text('HarmonyOS Sans'),
                        ),
                        DropdownMenuItem(
                          value: 'Microsoft YaHei UI',
                          child: Text('Microsoft YaHei UI'),
                        ),
                        DropdownMenuItem(
                          value: 'MiSans',
                          child: Text('MiSans'),
                        ),
                      ],
                      onChanged: (font) {
                        if (font != null) {
                          ref.read(fontFamilyProvider.notifier).setFont(font);
                        }
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _SettingsSection(
                title: tr(context, 'settings_theme_color'),
                children: [
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        for (final colorValue in AppTheme.presetColors)
                          _ColorSwatch(
                            color: Color(colorValue),
                            selected:
                                ref.watch(seedColorProvider).toARGB32() ==
                                colorValue,
                            onTap: () => ref
                                .read(seedColorProvider.notifier)
                                .setColor(Color(colorValue)),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _SettingsSection(
                title: onboardingCopy(context, 'replayTitle'),
                children: [
                  _SettingsTile(
                    icon: Icons.explore_outlined,
                    title: onboardingCopy(context, 'replayTitle'),
                    subtitle: onboardingCopy(context, 'replayDescription'),
                    trailing: Wrap(
                      alignment: WrapAlignment.end,
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        OutlinedButton.icon(
                          key: const Key('settings-onboarding-section'),
                          onPressed: _showOnboardingSectionPicker,
                          icon: const Icon(Icons.view_list_outlined, size: 18),
                          label: Text(onboardingCopy(context, 'replaySection')),
                        ),
                        FilledButton.tonalIcon(
                          key: const Key('settings-onboarding-all'),
                          onPressed: () => OnboardingOverlay.show(context),
                          icon: const Icon(Icons.play_arrow_rounded, size: 18),
                          label: Text(onboardingCopy(context, 'replayAll')),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _SettingsSection(
                title: tr(context, 'ai_settings_section'),
                children: [
                  _SettingsTile(
                    icon: Icons.smart_toy_outlined,
                    title: tr(context, 'ai_proxy_url'),
                    subtitle:
                        _aiEndpointUrl ?? tr(context, 'ai_proxy_url_loading'),
                    trailing: FilledButton.tonal(
                      key: const Key('settings-ai-endpoint-edit'),
                      onPressed: _showAiEndpointDialog,
                      child: Text(tr(context, 'settings_edit')),
                    ),
                  ),
                  _SettingsTile(
                    icon: Icons.key_outlined,
                    title: tr(context, 'ai_api_key'),
                    subtitle: _usesDefaultAiService
                        ? tr(context, 'ai_default')
                        : _aiApiKeyConfigured
                        ? tr(context, 'ai_api_key_saved')
                        : tr(context, 'ai_api_key_not_set'),
                    trailing: FilledButton.tonal(
                      key: const Key('settings-ai-api-key-edit'),
                      onPressed: _usesDefaultAiService
                          ? null
                          : _showAiApiKeyDialog,
                      child: Text(tr(context, 'settings_edit')),
                    ),
                  ),
                  _SettingsTile(
                    icon: Icons.auto_awesome_outlined,
                    title: tr(context, 'ai_model'),
                    subtitle: _usesDefaultAiService
                        ? tr(context, 'ai_default')
                        : _aiModel ?? tr(context, 'ai_model_not_set'),
                    trailing: FilledButton.tonal(
                      key: const Key('settings-ai-model-edit'),
                      onPressed: _usesDefaultAiService
                          ? null
                          : _showAiModelDialog,
                      child: Text(tr(context, 'settings_edit')),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _SettingsSection(
                title: tr(context, 'update_section'),
                children: [
                  _SettingsTile(
                    icon: Icons.update_outlined,
                    title: tr(context, 'update_current_version'),
                    subtitle: AppConstants.appVersion,
                    trailing: const SizedBox.shrink(),
                  ),
                  _SettingsTile(
                    icon: Icons.sync_outlined,
                    title: tr(context, 'update_auto_check'),
                    subtitle: '',
                    trailing: Switch(
                      value: ref.watch(updateProvider).autoCheckEnabled,
                      onChanged: (v) {
                        ref.read(updateProvider.notifier).setAutoCheck(v);
                      },
                    ),
                  ),
                  _SettingsTile(
                    icon: Icons.search_outlined,
                    title: tr(context, 'update_check_now'),
                    subtitle:
                        ref.watch(updateProvider.notifier).lastCheckFormatted ??
                        tr(context, 'update_never'),
                    trailing: FilledButton.tonal(
                      onPressed: () {
                        ref
                            .read(updateProvider.notifier)
                            .checkForUpdate(forceRefresh: true);
                      },
                      child: Text(tr(context, 'update_check_now')),
                    ),
                  ),
                  _SettingsTile(
                    icon: Icons.open_in_new_outlined,
                    title: tr(context, 'update_view_release'),
                    subtitle: '',
                    trailing: IconButton(
                      icon: const Icon(Icons.open_in_new, size: 18),
                      onPressed: () {
                        final url = ref
                            .read(updateProvider.notifier)
                            .releasePageUrl;
                        _launchUrl(url);
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _SettingsSection(
                title: tr(context, 'settings_about'),
                children: [
                  GestureDetector(
                    key: const Key('settings-version-easter-egg'),
                    behavior: HitTestBehavior.opaque,
                    onTap: _handleEasterEggTap,
                    child: _SettingsTile(
                      icon: Icons.info_outline,
                      title: tr(context, 'settings_version'),
                      subtitle: AppConstants.appVersion,
                      trailing: const SizedBox.shrink(),
                    ),
                  ),
                  _SettingsTile(
                    icon: Icons.description_outlined,
                    title: tr(context, 'settings_license'),
                    subtitle: AppConstants.licenseName,
                    trailing: const SizedBox.shrink(),
                  ),
                  _SettingsTile(
                    icon: Icons.language_outlined,
                    title: tr(context, 'about_official_website'),
                    subtitle: AppConstants.officialWebsite,
                    trailing: IconButton(
                      icon: const Icon(Icons.open_in_new, size: 18),
                      onPressed: () => _launchUrl(AppConstants.officialWebsite),
                    ),
                  ),
                  _SettingsTile(
                    icon: Icons.code_outlined,
                    title: tr(context, 'about_github_repository'),
                    subtitle: AppConstants.githubRepository,
                    trailing: IconButton(
                      icon: const Icon(Icons.open_in_new, size: 18),
                      onPressed: () =>
                          _launchUrl(AppConstants.githubRepository),
                    ),
                  ),
                  _SettingsTile(
                    icon: Icons.public_outlined,
                    title: tr(context, 'sourceforge_repository_title'),
                    subtitle: AppConstants.globalMirrorRepository,
                    trailing: IconButton(
                      icon: const Icon(Icons.open_in_new, size: 18),
                      onPressed: () =>
                          _launchUrl(AppConstants.globalMirrorRepository),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _buildAboutCard(context),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAboutCard(BuildContext context) {
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
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    'WD',
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: colorScheme.onPrimaryContainer,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    tr(context, 'settings_about_title'),
                    style: theme.textTheme.titleMedium,
                  ),
                ),
                // Intel Logo with easter egg
                GestureDetector(
                  key: const Key('settings-intel-easter-egg'),
                  onTap: _handleIntelLogoTap,
                  child: Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      image: const DecorationImage(
                        image: AssetImage('assets/intel-1.jpg'),
                        fit: BoxFit.cover,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              tr(context, 'settings_built_with'),
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final tool in _builtWithTools)
                  Chip(
                    label: AppCompactLabel(tool),
                    visualDensity: VisualDensity.compact,
                    side: BorderSide(color: colorScheme.outlineVariant),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            GestureDetector(
              onTap: _handleEasterEggTap,
              child: Text(
                tr(context, 'settings_copyright'),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            const SizedBox(height: 16),
            const SpecialThanksSection(),
          ],
        ),
      ),
    );
  }

  static const _builtWithTools = [
    'Flutter',
    'Dart',
    'Material 3',
    'Riverpod',
    'GoRouter',
  ];

  String _themeModeName(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.system:
        return tr(context, 'settings_theme_system');
      case ThemeMode.light:
        return tr(context, 'settings_theme_light');
      case ThemeMode.dark:
        return tr(context, 'settings_theme_dark');
    }
  }

  String _fontFamilyName(String fontFamily) {
    switch (fontFamily) {
      case 'HarmonyOSSans':
        return 'HarmonyOS Sans';
      case 'Microsoft YaHei UI':
        return 'Microsoft YaHei UI';
      case 'MiSans':
        return 'MiSans';
      default:
        return fontFamily;
    }
  }

  Future<void> _showAiEndpointDialog() async {
    final controller = TextEditingController(
      text: _aiEndpointUrl ?? AiConfig.defaultEndpointUrl,
    );
    var errorText = '';

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            Future<void> save() async {
              final normalized = AiConfig.normalizeEndpointUrl(controller.text);
              if (normalized.isNotEmpty &&
                  !AiConfig.isValidEndpointUrl(normalized)) {
                setDialogState(() {
                  errorText = tr(context, 'ai_proxy_url_invalid');
                });
                return;
              }
              try {
                await AiConfig.setEndpointUrl(normalized);
                await _loadAiPreferences();
                if (dialogContext.mounted) Navigator.of(dialogContext).pop();
              } catch (_) {
                setDialogState(() {
                  errorText = tr(context, 'ai_proxy_url_invalid');
                });
              }
            }

            Future<void> reset() async {
              await AiConfig.resetEndpointUrl();
              await _loadAiPreferences();
              if (dialogContext.mounted) Navigator.of(dialogContext).pop();
            }

            return AlertDialog(
              title: Text(tr(context, 'ai_proxy_url')),
              content: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(tr(context, 'ai_proxy_url_desc')),
                      const SizedBox(height: 16),
                      TextField(
                        controller: controller,
                        autofocus: true,
                        decoration: InputDecoration(
                          labelText: tr(context, 'ai_proxy_url'),
                          hintText: AiConfig.defaultEndpointUrl,
                          errorText: errorText.isEmpty ? null : errorText,
                          border: const OutlineInputBorder(),
                        ),
                        keyboardType: TextInputType.url,
                        onSubmitted: (_) => save(),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: reset,
                  child: Text(tr(context, 'settings_reset_default')),
                ),
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: Text(tr(context, 'detail_cancel')),
                ),
                FilledButton(
                  onPressed: save,
                  child: Text(tr(context, 'settings_save')),
                ),
              ],
            );
          },
        );
      },
    );

    controller.dispose();
  }

  Future<void> _showAiApiKeyDialog() async {
    final controller = TextEditingController();
    var obscureText = true;
    var errorText = '';

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            Future<void> save() async {
              try {
                await AiConfig.setApiKey(controller.text);
                await _loadAiPreferences();
                if (dialogContext.mounted) Navigator.of(dialogContext).pop();
              } catch (error) {
                setDialogState(() {
                  errorText = error is StateError
                      ? tr(context, 'ai_api_key_endpoint_required')
                      : tr(context, 'ai_api_key_invalid');
                });
              }
            }

            Future<void> clear() async {
              await AiConfig.clearApiKey();
              await _loadAiPreferences();
              if (dialogContext.mounted) Navigator.of(dialogContext).pop();
            }

            return AlertDialog(
              title: Text(tr(context, 'ai_api_key')),
              content: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(tr(context, 'ai_api_key_desc')),
                      const SizedBox(height: 16),
                      TextField(
                        controller: controller,
                        autofocus: true,
                        obscureText: obscureText,
                        autocorrect: false,
                        enableSuggestions: false,
                        decoration: InputDecoration(
                          labelText: tr(context, 'ai_api_key'),
                          hintText: _aiApiKeyConfigured ? '••••••••' : null,
                          errorText: errorText.isEmpty ? null : errorText,
                          border: const OutlineInputBorder(),
                          suffixIcon: IconButton(
                            tooltip: obscureText
                                ? tr(context, 'ai_api_key_show')
                                : tr(context, 'ai_api_key_hide'),
                            icon: Icon(
                              obscureText
                                  ? Icons.visibility_outlined
                                  : Icons.visibility_off_outlined,
                            ),
                            onPressed: () => setDialogState(
                              () => obscureText = !obscureText,
                            ),
                          ),
                        ),
                        onSubmitted: (_) => save(),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                if (_aiApiKeyConfigured)
                  TextButton(
                    onPressed: clear,
                    child: Text(tr(context, 'ai_api_key_clear')),
                  ),
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: Text(tr(context, 'detail_cancel')),
                ),
                FilledButton(
                  onPressed: save,
                  child: Text(tr(context, 'settings_save')),
                ),
              ],
            );
          },
        );
      },
    );

    controller.dispose();
  }

  Future<void> _showAiModelDialog() async {
    final controller = TextEditingController(text: _aiModel ?? '');
    var errorText = '';
    var loadingModels = false;
    var availableModels = <String>[];

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            Future<void> refreshModels() async {
              setDialogState(() {
                loadingModels = true;
                errorText = '';
              });
              try {
                final models = await AiService().fetchModels();
                if (dialogContext.mounted) {
                  setDialogState(() {
                    availableModels = models;
                    loadingModels = false;
                  });
                }
              } catch (_) {
                if (dialogContext.mounted) {
                  setDialogState(() {
                    loadingModels = false;
                    errorText = tr(context, 'ai_models_load_failed');
                  });
                }
              }
            }

            Future<void> save() async {
              try {
                await AiConfig.setModel(controller.text);
                await _loadAiPreferences();
                if (dialogContext.mounted) Navigator.of(dialogContext).pop();
              } catch (_) {
                setDialogState(() {
                  errorText = tr(context, 'ai_model_invalid');
                });
              }
            }

            final current = controller.text.trim();
            return AlertDialog(
              title: Text(tr(context, 'ai_model')),
              content: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(tr(context, 'ai_model_desc')),
                      const SizedBox(height: 16),
                      TextField(
                        controller: controller,
                        decoration: InputDecoration(
                          labelText: tr(context, 'ai_model'),
                          errorText: errorText.isEmpty ? null : errorText,
                          border: const OutlineInputBorder(),
                        ),
                        onChanged: (_) => setDialogState(() {}),
                        onSubmitted: (_) => save(),
                      ),
                      const SizedBox(height: 12),
                      Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: OutlinedButton.icon(
                          onPressed: loadingModels ? null : refreshModels,
                          icon: loadingModels
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.refresh),
                          label: Text(
                            loadingModels
                                ? tr(context, 'ai_model_loading')
                                : tr(context, 'ai_models_refresh'),
                          ),
                        ),
                      ),
                      if (availableModels.isNotEmpty) ...[
                        const SizedBox(height: 16),
                        Text(
                          tr(context, 'ai_model_select'),
                          style: Theme.of(context).textTheme.labelLarge,
                        ),
                        const SizedBox(height: 6),
                        DropdownButtonFormField<String>(
                          initialValue: availableModels.contains(current)
                              ? current
                              : null,
                          decoration: const InputDecoration(
                            border: OutlineInputBorder(),
                          ),
                          items: [
                            for (final model in availableModels)
                              DropdownMenuItem<String>(
                                value: model,
                                child: Text(
                                  model,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                          ],
                          onChanged: (value) {
                            if (value != null) {
                              controller.text = value;
                              controller.selection = TextSelection.collapsed(
                                offset: value.length,
                              );
                              setDialogState(() {});
                            }
                          },
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: Text(tr(context, 'detail_cancel')),
                ),
                FilledButton(
                  onPressed: save,
                  child: Text(tr(context, 'settings_save')),
                ),
              ],
            );
          },
        );
      },
    );

    controller.dispose();
  }

  Future<void> _launchUrl(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${tr(context, 'detail_open_failed')}: $e')),
        );
      }
    }
  }

  Future<void> _showOnboardingSectionPicker() async {
    final section = await showDialog<OnboardingSection>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: Text(onboardingCopy(context, 'replaySection')),
        children: [
          for (final section in OnboardingSection.values)
            SimpleDialogOption(
              onPressed: () => Navigator.of(dialogContext).pop(section),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Text(onboardingSectionLabel(context, section)),
              ),
            ),
        ],
      ),
    );
    if (section != null && mounted) {
      await OnboardingOverlay.show(context, section: section);
    }
  }
}

class _SettingsSection extends StatelessWidget {
  final String title;
  final List<Widget> children;
  const _SettingsSection({required this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
            color: Theme.of(context).colorScheme.primary,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        Card(
          child: Column(
            children: [
              for (int i = 0; i < children.length; i++) ...[
                children[i],
                if (i < children.length - 1) const Divider(height: 1),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _SettingsTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Widget trailing;
  const _SettingsTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final text = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(title, style: theme.textTheme.bodyMedium),
        if (subtitle.isNotEmpty) ...[
          const SizedBox(height: 2),
          Text(
            subtitle,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ],
    );
    final sizedTrailing = trailing is SizedBox ? trailing as SizedBox : null;
    final hasTrailing =
        sizedTrailing == null ||
        sizedTrailing.child != null ||
        sizedTrailing.width != 0 ||
        sizedTrailing.height != 0;

    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 640;
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: compact
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(icon),
                        const SizedBox(width: 12),
                        Expanded(child: text),
                      ],
                    ),
                    if (hasTrailing) ...[
                      const SizedBox(height: 8),
                      Padding(
                        padding: const EdgeInsetsDirectional.only(start: 36),
                        child: Align(
                          alignment: AlignmentDirectional.centerEnd,
                          child: ConstrainedBox(
                            constraints: BoxConstraints(
                              maxWidth: (constraints.maxWidth - 64)
                                  .clamp(0.0, 320.0)
                                  .toDouble(),
                            ),
                            child: trailing,
                          ),
                        ),
                      ),
                    ],
                  ],
                )
              : Row(
                  children: [
                    Icon(icon),
                    const SizedBox(width: 12),
                    Expanded(child: text),
                    if (hasTrailing) ...[
                      const SizedBox(width: 16),
                      Flexible(
                        child: Align(
                          alignment: AlignmentDirectional.centerEnd,
                          child: trailing,
                        ),
                      ),
                    ],
                  ],
                ),
        );
      },
    );
  }
}

class _ColorSwatch extends StatelessWidget {
  const _ColorSwatch({
    required this.color,
    required this.selected,
    required this.onTap,
  });

  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final brightness = ThemeData.estimateBrightnessForColor(color);
    final iconColor = brightness == Brightness.dark
        ? Colors.white
        : Colors.black;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(
            color: selected
                ? Theme.of(context).colorScheme.onSurface
                : Colors.transparent,
            width: 3,
          ),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: color.withValues(alpha: 0.4),
                    blurRadius: 8,
                    spreadRadius: 1,
                  ),
                ]
              : null,
        ),
        child: selected ? Icon(Icons.check, size: 20, color: iconColor) : null,
      ),
    );
  }
}

class _EasterEggDialog extends StatelessWidget {
  const _EasterEggDialog();

  static const _assetPath = 'assets/easter_egg/easter_egg.png';

  @override
  Widget build(BuildContext context) {
    return Dialog.fullscreen(
      backgroundColor: Colors.black,
      child: Shortcuts(
        shortcuts: const {
          SingleActivator(LogicalKeyboardKey.escape): DismissIntent(),
        },
        child: Actions(
          actions: {
            DismissIntent: CallbackAction<DismissIntent>(
              onInvoke: (_) {
                Navigator.of(context).maybePop();
                return null;
              },
            ),
          },
          child: Focus(
            autofocus: true,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => Navigator.of(context).maybePop(),
              child: Stack(
                children: [
                  Center(
                    child: GestureDetector(
                      onTap: () {},
                      child: Image.asset(
                        _assetPath,
                        fit: BoxFit.contain,
                        errorBuilder: (context, error, stackTrace) {
                          return Padding(
                            padding: const EdgeInsets.all(32),
                            child: Text(
                              tr(context, 'easter_egg_missing'),
                              textAlign: TextAlign.center,
                              style: Theme.of(context).textTheme.titleMedium
                                  ?.copyWith(color: Colors.white),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                  PositionedDirectional(
                    top: 16,
                    end: 16,
                    child: IconButton.filledTonal(
                      tooltip: tr(context, 'close'),
                      onPressed: () => Navigator.of(context).maybePop(),
                      icon: const Icon(Icons.close),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class IntelMuseumDialog extends StatefulWidget {
  const IntelMuseumDialog({super.key, this.loadSystemInfo = true});

  final bool loadSystemInfo;

  @override
  State<IntelMuseumDialog> createState() => _IntelMuseumDialogState();
}

class _IntelMuseumDialogState extends State<IntelMuseumDialog> {
  String _cpuInfo = '';
  String _gpuInfo = '';
  String _memoryInfo = '';
  String _windowsVersion = '';

  @override
  void initState() {
    super.initState();
    if (widget.loadSystemInfo) _loadSystemInfo();
  }

  Future<void> _loadSystemInfo() async {
    // Run all PowerShell commands in parallel for faster loading
    final results = await Future.wait([
      _getCPUInfoAsync(),
      _getGPUInfoAsync(),
      _getMemoryInfoAsync(),
      _getWindowsVersionAsync(),
    ]);

    if (mounted) {
      setState(() {
        _cpuInfo = results[0];
        _gpuInfo = results[1];
        _memoryInfo = results[2];
        _windowsVersion = results[3];
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final loadingText = tr(context, 'intel_loading');
    final size = MediaQuery.sizeOf(context);
    final compactHeight = size.height < 520;
    final dialogWidth = (size.width - 32).clamp(0.0, 720.0).toDouble();
    final infoRows = <({String label, String value})>[
      (
        label: tr(context, 'intel_cpu'),
        value: _cpuInfo.isEmpty ? loadingText : _cpuInfo,
      ),
      (
        label: tr(context, 'intel_gpu'),
        value: _gpuInfo.isEmpty ? loadingText : _gpuInfo,
      ),
      (
        label: tr(context, 'intel_memory'),
        value: _memoryInfo.isEmpty ? loadingText : _memoryInfo,
      ),
      (
        label: 'Windows',
        value: _windowsVersion.isEmpty ? loadingText : _windowsVersion,
      ),
      (label: 'Flutter', value: '3.44.0'),
      (
        label: tr(context, 'intel_build_time'),
        value: DateTime.now().toString().split('.')[0],
      ),
    ];

    return Dialog(
      insetPadding: EdgeInsets.symmetric(
        horizontal: 16,
        vertical: compactHeight ? 8 : 24,
      ),
      child: SizedBox(
        width: dialogWidth,
        child: Padding(
          padding: EdgeInsets.all(compactHeight ? 12 : 20),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final useGrid = constraints.maxWidth >= 560;
              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.memory, color: colorScheme.primary),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          tr(context, 'intel_museum_title'),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleLarge,
                        ),
                      ),
                      IconButton(
                        tooltip: tr(context, 'close'),
                        onPressed: () => Navigator.of(context).maybePop(),
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                  SizedBox(height: compactHeight ? 4 : 8),
                  Text(
                    tr(context, 'intel_museum_desc'),
                    maxLines: compactHeight ? 1 : 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                  SizedBox(height: compactHeight ? 8 : 16),
                  if (useGrid)
                    Wrap(
                      spacing: 12,
                      runSpacing: 8,
                      children: [
                        for (final info in infoRows)
                          SizedBox(
                            width: (constraints.maxWidth - 12) / 2,
                            child: _IntelInfoCard(
                              label: info.label,
                              value: info.value,
                            ),
                          ),
                      ],
                    )
                  else
                    Column(
                      children: [
                        for (final info in infoRows)
                          _IntelInfoRow(
                            label: info.label,
                            value: info.value,
                            compact: compactHeight,
                          ),
                      ],
                    ),
                  SizedBox(height: compactHeight ? 8 : 16),
                  Text(
                    'Intel® is a trademark of Intel Corporation.',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                  Text(
                    'This project is not affiliated with Intel.',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                  SizedBox(height: compactHeight ? 8 : 16),
                  Align(
                    alignment: AlignmentDirectional.centerEnd,
                    child: FilledButton(
                      onPressed: () => Navigator.of(context).maybePop(),
                      child: Text(tr(context, 'close')),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Future<String> _getCPUInfoAsync() async {
    try {
      final result = await Process.run('powershell', [
        '-NoProfile',
        '-Command',
        '(Get-CimInstance Win32_Processor).Name',
      ], runInShell: true);
      if (result.exitCode == 0) {
        final output = result.stdout.toString().trim();
        if (output.isNotEmpty && !output.contains('Error')) {
          return output;
        }
      }
    } catch (_) {}

    final identifier = Platform.environment['PROCESSOR_IDENTIFIER'] ?? '';
    if (identifier.isNotEmpty) {
      if (identifier.contains('Intel')) {
        return 'Intel Core Processor';
      } else if (identifier.contains('AMD')) {
        return 'AMD Ryzen Processor';
      }
      return identifier;
    }
    return 'Unknown CPU';
  }

  Future<String> _getGPUInfoAsync() async {
    try {
      final result = await Process.run('powershell', [
        '-NoProfile',
        '-Command',
        '(Get-CimInstance Win32_VideoController).Name',
      ], runInShell: true);
      if (result.exitCode == 0) {
        final output = result.stdout.toString().trim();
        if (output.isNotEmpty && !output.contains('Error')) {
          final gpus = output
              .split('\n')
              .map((g) => g.trim())
              .where((g) => g.isNotEmpty)
              .where((g) => !_isVirtualGPU(g))
              .toList();

          if (gpus.isNotEmpty) {
            return gpus.join('\n');
          }
        }
      }
    } catch (_) {}
    return 'Unknown GPU';
  }

  Future<String> _getMemoryInfoAsync() async {
    try {
      final result = await Process.run('powershell', [
        '-NoProfile',
        '-Command',
        '[math]::Round((Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory/1GB, 1)',
      ], runInShell: true);
      if (result.exitCode == 0) {
        final output = result.stdout.toString().trim();
        if (output.isNotEmpty && !output.contains('Error')) {
          return '$output GB';
        }
      }
    } catch (_) {}
    return 'Unknown';
  }

  Future<String> _getWindowsVersionAsync() async {
    try {
      final result = await Process.run('powershell', [
        '-NoProfile',
        '-Command',
        '(Get-CimInstance Win32_OperatingSystem).Caption',
      ], runInShell: true);
      if (result.exitCode == 0) {
        final output = result.stdout.toString().trim();
        if (output.isNotEmpty && !output.contains('Error')) {
          return output;
        }
      }
    } catch (_) {}

    final version = Platform.operatingSystemVersion;
    if (version.contains('10.0.2')) {
      return 'Windows 11';
    } else if (version.contains('10.0.1')) {
      return 'Windows 10';
    }
    return 'Windows $version';
  }

  static bool _isVirtualGPU(String gpuName) {
    final lower = gpuName.toLowerCase();
    return lower.contains('vmware') ||
        lower.contains('mumu') ||
        lower.contains('virtual') ||
        lower.contains('remote') ||
        lower.contains('basic display') ||
        lower.contains('microsoft basic');
  }
}

class _IntelInfoCard extends StatelessWidget {
  const _IntelInfoCard({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelMedium?.copyWith(
              color: colors.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 2),
          Text(value, maxLines: 2, overflow: TextOverflow.ellipsis),
        ],
      ),
    );
  }
}

class _IntelInfoRow extends StatelessWidget {
  const _IntelInfoRow({
    required this.label,
    required this.value,
    required this.compact,
  });

  final String label;
  final String value;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.symmetric(vertical: compact ? 2 : 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 96,
            child: Text(
              label,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              value,
              maxLines: compact ? 1 : 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }
}
