import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/localization/strings.dart';
import 'localization.dart';
import 'routes.dart';
import 'theme.dart';

class WinDeployStudioApp extends ConsumerStatefulWidget {
  const WinDeployStudioApp({
    super.key,
    this.hasSelectedLanguage,
    this.startupLocale,
  });

  final bool? hasSelectedLanguage;
  final Locale? startupLocale;

  @override
  ConsumerState<WinDeployStudioApp> createState() => _WinDeployStudioAppState();
}

class _WinDeployStudioAppState extends ConsumerState<WinDeployStudioApp> {
  bool _initialized = false;
  bool _langPageShown = false;

  @override
  void initState() {
    super.initState();
    final startupLocale = widget.startupLocale;
    if (startupLocale != null) {
      unawaited(ref.read(localeProvider.notifier).setLocale(startupLocale));
    }

    final hasSelectedLanguage = widget.hasSelectedLanguage;
    if (hasSelectedLanguage == null) {
      unawaited(_init());
      return;
    }

    _initialized = true;
    if (!hasSelectedLanguage) _scheduleLanguagePage();
  }

  Future<void> _init() async {
    final prefs = await SharedPreferences.getInstance();
    final hasLang = prefs.containsKey('language_code');

    if (!hasLang) {
      setState(() => _initialized = true);
      _scheduleLanguagePage();
    } else {
      setState(() => _initialized = true);
    }
  }

  void _scheduleLanguagePage() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !_langPageShown) {
        _langPageShown = true;
        unawaited(_showLanguagePage());
      }
    });
  }

  Future<void> _showLanguagePage() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const LanguageSelectPage(),
        fullscreenDialog: true,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final visualStyle = ref.watch(visualStyleProvider);
    final themeMode = ref.watch(themeModeProvider);
    final seedColor = ref.watch(seedColorProvider);
    final fontFamily = ref.watch(fontFamilyProvider);
    if (!_initialized) {
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(seedColor, fontFamily, style: visualStyle),
        darkTheme: AppTheme.dark(seedColor, fontFamily, style: visualStyle),
        highContrastTheme: AppTheme.highContrastLight(
          seedColor,
          fontFamily,
          style: visualStyle,
        ),
        highContrastDarkTheme: AppTheme.highContrastDark(
          seedColor,
          fontFamily,
          style: visualStyle,
        ),
        themeMode: themeMode,
        home: const Scaffold(body: Center(child: CircularProgressIndicator())),
      );
    }

    final router = ref.watch(routerProvider);
    final locale = ref.watch(localeProvider);

    return MaterialApp.router(
      title: 'WinDeploy Studio',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(seedColor, fontFamily, style: visualStyle),
      darkTheme: AppTheme.dark(seedColor, fontFamily, style: visualStyle),
      highContrastTheme: AppTheme.highContrastLight(
        seedColor,
        fontFamily,
        style: visualStyle,
      ),
      highContrastDarkTheme: AppTheme.highContrastDark(
        seedColor,
        fontFamily,
        style: visualStyle,
      ),
      themeMode: themeMode,
      locale: locale,
      supportedLocales: supportedAppLocales,
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      routerConfig: router,
      builder: (context, child) {
        return MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: MediaQuery.of(
              context,
            ).textScaler.clamp(minScaleFactor: 0.8, maxScaleFactor: 2.0),
          ),
          child: child ?? const SizedBox.shrink(),
        );
      },
    );
  }
}

class LanguageSelectPage extends ConsumerStatefulWidget {
  const LanguageSelectPage({super.key});

  @override
  ConsumerState<LanguageSelectPage> createState() => _LanguageSelectPageState();
}

class _LanguageSelectPageState extends ConsumerState<LanguageSelectPage> {
  String _selected = 'zh';

  String _tr(String key) => trByCode(_selected, key);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final screenWidth = MediaQuery.of(context).size.width;
    final isCompact = screenWidth < 600;
    final previewLocale = localeFromCode(_selected);

    return Directionality(
      textDirection: textDirectionForLocale(previewLocale),
      child: Scaffold(
        backgroundColor: colorScheme.surface,
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: EdgeInsets.symmetric(
                horizontal: isCompact ? 24 : 48,
                vertical: 32,
              ),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // App icon
                    Container(
                      width: 80,
                      height: 80,
                      decoration: BoxDecoration(
                        color: colorScheme.primaryContainer,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        Icons.desktop_windows_rounded,
                        size: 48,
                        color: colorScheme.onPrimaryContainer,
                      ),
                    ),
                    const SizedBox(height: 24),
                    // Title
                    Text(
                      _tr('lang_select_title'),
                      style: theme.textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 8),
                    // Subtitle
                    Text(
                      _tr('lang_select_desc'),
                      style: theme.textTheme.bodyLarge?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 32),
                    // Language options
                    _LangOption(
                      label: '简体中文',
                      isSelected: _selected == 'zh',
                      onTap: () => setState(() => _selected = 'zh'),
                    ),
                    const SizedBox(height: 10),
                    _LangOption(
                      label: '繁體中文',
                      isSelected: _selected == 'zh_TW',
                      onTap: () => setState(() => _selected = 'zh_TW'),
                    ),
                    const SizedBox(height: 10),
                    _LangOption(
                      label: 'English',
                      isSelected: _selected == 'en',
                      onTap: () => setState(() => _selected = 'en'),
                    ),
                    const SizedBox(height: 10),
                    _LangOption(
                      label: 'Français',
                      isSelected: _selected == 'fr',
                      onTap: () => setState(() => _selected = 'fr'),
                    ),
                    const SizedBox(height: 10),
                    _LangOption(
                      label: 'Deutsch',
                      isSelected: _selected == 'de',
                      onTap: () => setState(() => _selected = 'de'),
                    ),
                    const SizedBox(height: 10),
                    _LangOption(
                      label: 'Español',
                      isSelected: _selected == 'es',
                      onTap: () => setState(() => _selected = 'es'),
                    ),
                    const SizedBox(height: 10),
                    _LangOption(
                      label: 'Português',
                      isSelected: _selected == 'pt',
                      onTap: () => setState(() => _selected = 'pt'),
                    ),
                    const SizedBox(height: 10),
                    _LangOption(
                      label: 'Русский',
                      isSelected: _selected == 'ru',
                      onTap: () => setState(() => _selected = 'ru'),
                    ),
                    const SizedBox(height: 10),
                    _LangOption(
                      label: 'العربية',
                      isSelected: _selected == 'ar',
                      onTap: () => setState(() => _selected = 'ar'),
                    ),
                    const SizedBox(height: 10),
                    _LangOption(
                      label: '한국어',
                      isSelected: _selected == 'ko',
                      onTap: () => setState(() => _selected = 'ko'),
                    ),
                    const SizedBox(height: 10),
                    _LangOption(
                      label: '日本語',
                      isSelected: _selected == 'ja',
                      onTap: () => setState(() => _selected = 'ja'),
                    ),
                    const SizedBox(height: 32),
                    // Confirm button
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: FilledButton(
                        onPressed: () async {
                          final locale = _selected == 'zh_TW'
                              ? const Locale('zh', 'TW')
                              : Locale(_selected);
                          await ref
                              .read(localeProvider.notifier)
                              .setLocale(locale);
                          if (context.mounted) Navigator.pop(context);
                        },
                        child: Text(_tr('lang_select_confirm')),
                      ),
                    ),
                    const SizedBox(height: 12),
                    // Settings hint
                    Text(
                      _tr('lang_select_settings_hint'),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _LangOption extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _LangOption({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected
                ? theme.colorScheme.primary
                : theme.colorScheme.outlineVariant,
            width: isSelected ? 2 : 1,
          ),
          color: isSelected
              ? theme.colorScheme.primaryContainer.withValues(alpha: 0.3)
              : null,
        ),
        child: Row(
          children: [
            Icon(
              Icons.language,
              color: isSelected
                  ? theme.colorScheme.primary
                  : theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                style: theme.textTheme.bodyLarge?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            if (isSelected)
              Icon(Icons.check_circle, color: theme.colorScheme.primary),
          ],
        ),
      ),
    );
  }
}
