import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart' show Provider;
import 'package:flutter_riverpod/legacy.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Flutter-rendered skins inspired by Windows 11/WinUI, Windows 10/Metro,
/// and Windows 7/Aero. They do not depend on the Windows App SDK. The native
/// runner remains a Windows 10 1809+ Win32 host; [win7] changes appearance only.
enum VisualStyle {
  auto,
  win11,
  win10,
  win7;

  VisualStyle get resolved =>
      this == VisualStyle.auto ? VisualStyleHost.detect() : this;

  String get labelKey => switch (this) {
    VisualStyle.auto => VisualStyleLocalizationKeys.autoLabel,
    VisualStyle.win11 => VisualStyleLocalizationKeys.windows11Label,
    VisualStyle.win10 => VisualStyleLocalizationKeys.windows10Label,
    VisualStyle.win7 => VisualStyleLocalizationKeys.windows7Label,
  };

  String get descriptionKey => switch (this) {
    VisualStyle.auto => VisualStyleLocalizationKeys.autoDescription,
    VisualStyle.win11 => VisualStyleLocalizationKeys.windows11Description,
    VisualStyle.win10 => VisualStyleLocalizationKeys.windows10Description,
    VisualStyle.win7 => VisualStyleLocalizationKeys.windows7Description,
  };

  static VisualStyle? fromName(String? value) {
    for (final style in VisualStyle.values) {
      if (style.name == value) return style;
    }
    return null;
  }
}

@immutable
class AppAppearanceSettings {
  const AppAppearanceSettings({
    this.themeMode = ThemeMode.system,
    this.visualStyle = VisualStyle.win11,
    this.accentColor = defaultAccentColor,
    this.fontFamily = defaultFontFamily,
  });

  static const themeModePreferenceKey = 'theme_mode';
  static const visualStylePreferenceKey = 'visual_style';
  static const accentPreferenceKey = 'theme_color';
  static const fontFamilyPreferenceKey = 'font_family';
  static const defaultAccentColor = Color(0xFF0071C5);
  static const defaultFontFamily = 'HarmonyOSSans';
  static const defaults = AppAppearanceSettings();

  final ThemeMode themeMode;
  final VisualStyle visualStyle;
  final Color accentColor;
  final String fontFamily;

  VisualStyle get resolvedStyle => visualStyle.resolved;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'themeMode': themeMode.name,
    'style': visualStyle.name,
    'accent': accentColor.toARGB32(),
    'fontFamily': fontFamily,
  };

  factory AppAppearanceSettings.fromJson(Map<String, dynamic> json) {
    return AppAppearanceSettings(
      themeMode: _themeModeFromName(json['themeMode']?.toString()),
      visualStyle:
          VisualStyle.fromName(json['style']?.toString()) ??
          defaults.visualStyle,
      accentColor: _colorFromValue(json['accent']),
      fontFamily: _fontFromValue(json['fontFamily']),
    );
  }

  factory AppAppearanceSettings.fromPreferences(SharedPreferences prefs) {
    return AppAppearanceSettings(
      themeMode: _themeModeFromName(prefs.getString(themeModePreferenceKey)),
      visualStyle:
          VisualStyle.fromName(prefs.getString(visualStylePreferenceKey)) ??
          defaults.visualStyle,
      accentColor: Color(
        prefs.getInt(accentPreferenceKey) ?? defaultAccentColor.toARGB32(),
      ),
      fontFamily: _fontFromValue(prefs.getString(fontFamilyPreferenceKey)),
    );
  }

  static Future<AppAppearanceSettings> load() async {
    try {
      final preferences = await SharedPreferences.getInstance();
      return AppAppearanceSettings.fromPreferences(preferences);
    } catch (_) {
      return defaults;
    }
  }

  AppAppearanceSettings copyWith({
    ThemeMode? themeMode,
    VisualStyle? visualStyle,
    Color? accentColor,
    String? fontFamily,
  }) {
    return AppAppearanceSettings(
      themeMode: themeMode ?? this.themeMode,
      visualStyle: visualStyle ?? this.visualStyle,
      accentColor: accentColor ?? this.accentColor,
      fontFamily: fontFamily ?? this.fontFamily,
    );
  }

  static ThemeMode _themeModeFromName(String? value) {
    return ThemeMode.values.firstWhere(
      (mode) => mode.name == value,
      orElse: () => ThemeMode.system,
    );
  }

  static Color _colorFromValue(Object? value) {
    final numeric = value is num ? value.toInt() : int.tryParse('$value');
    return Color(numeric ?? defaultAccentColor.toARGB32());
  }

  static String _fontFromValue(Object? value) {
    final font = value?.toString().trim() ?? '';
    return font.isEmpty ? defaultFontFamily : font;
  }
}

abstract final class AppVisualStyleColors {
  static Color titleBarSurface(VisualStyle style, Brightness brightness) {
    final resolvedStyle = style.resolved;
    final isDark = brightness == Brightness.dark;
    return switch ((resolvedStyle, isDark)) {
      (VisualStyle.win11, false) => const Color(0xFFF3F3F3),
      (VisualStyle.win11, true) => const Color(0xFF202020),
      (VisualStyle.win10, false) => Colors.white,
      (VisualStyle.win10, true) => const Color(0xFF1C1C1C),
      (VisualStyle.win7, false) => const Color(0xFFE4EFF8),
      (VisualStyle.win7, true) => const Color(0xFF252B32),
      (VisualStyle.auto, _) => throw StateError('VisualStyle.auto unresolved'),
    };
  }
}

abstract final class VisualStyleLocalizationKeys {
  static const settingLabel = 'settings_visual_style';
  static const settingDescription = 'settings_visual_style_desc';
  static const autoLabel = 'settings_visual_style_auto';
  static const autoDescription = 'settings_visual_style_auto_desc';
  static const windows11Label = 'settings_visual_style_win11';
  static const windows11Description = 'settings_visual_style_win11_desc';
  static const windows10Label = 'settings_visual_style_win10';
  static const windows10Description = 'settings_visual_style_win10_desc';
  static const windows7Label = 'settings_visual_style_win7';
  static const windows7Description = 'settings_visual_style_win7_desc';

  static const all = <String>[
    settingLabel,
    settingDescription,
    autoLabel,
    autoDescription,
    windows11Label,
    windows11Description,
    windows10Label,
    windows10Description,
    windows7Label,
    windows7Description,
  ];
}

abstract final class VisualStyleHost {
  static VisualStyle detect([String? operatingSystemVersion]) {
    if (!Platform.isWindows && operatingSystemVersion == null) {
      return VisualStyle.win11;
    }

    final version = operatingSystemVersion ?? Platform.operatingSystemVersion;
    final buildMatch = RegExp(
      r'build[\s.:_-]*(\d{4,6})',
      caseSensitive: false,
    ).firstMatch(version);
    final versionMatch = RegExp(
      r'\b(\d+)\.(\d+)(?:\.(\d{4,6}))?',
      caseSensitive: false,
    ).firstMatch(version);
    final major = int.tryParse(versionMatch?.group(1) ?? '');
    if (major != null) {
      if (major < 10) return VisualStyle.win7;
      final build = int.tryParse(
        versionMatch?.group(3) ?? buildMatch?.group(1) ?? '',
      );
      return build != null && build >= 22000
          ? VisualStyle.win11
          : VisualStyle.win10;
    }

    final build = int.tryParse(buildMatch?.group(1) ?? '');
    if (build == null) return VisualStyle.win7;
    if (build >= 22000) return VisualStyle.win11;
    return build >= 10240 ? VisualStyle.win10 : VisualStyle.win7;
  }
}

final initialAppearanceProvider = Provider<AppAppearanceSettings>(
  (ref) => AppAppearanceSettings.defaults,
);

final visualStyleProvider =
    StateNotifierProvider<VisualStyleNotifier, VisualStyle>(
      (ref) =>
          VisualStyleNotifier(ref.watch(initialAppearanceProvider).visualStyle),
    );

class VisualStyleNotifier extends StateNotifier<VisualStyle> {
  static const preferenceKey = AppAppearanceSettings.visualStylePreferenceKey;
  static VisualStyle _current = VisualStyle.win11;

  static VisualStyle get current => _current;

  VisualStyleNotifier([VisualStyle initial = VisualStyle.win11])
    : super(initial) {
    _current = initial;
  }

  Future<void> setStyle(VisualStyle style) async {
    _current = style;
    if (state != style) state = style;
    await WindowStyleChannel.instance.update(style: style);
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(preferenceKey, style.name);
  }
}

class WindowStyleChannel with WidgetsBindingObserver {
  WindowStyleChannel._() {
    WidgetsBinding.instance.addObserver(this);
  }

  static final WindowStyleChannel instance = WindowStyleChannel._();
  static const MethodChannel _channel = MethodChannel('wds/window_style');

  VisualStyle _style = VisualStyle.win11;
  ThemeMode _themeMode = ThemeMode.system;
  Color _accent = const Color(0xFF0071C5);

  Future<void> initialize(AppAppearanceSettings appearance) {
    return update(
      style: appearance.visualStyle,
      themeMode: appearance.themeMode,
      accent: appearance.accentColor,
    );
  }

  Future<void> update({
    VisualStyle? style,
    ThemeMode? themeMode,
    Brightness? brightness,
    Color? accent,
  }) async {
    if (style != null) _style = style;
    if (themeMode != null) _themeMode = themeMode;
    if (accent != null) _accent = accent;

    final effectiveBrightness =
        brightness ?? _brightnessForThemeMode(_themeMode);
    if (!Platform.isWindows) return;

    final resolvedStyle = _style.resolved;
    final titleBarSurface = AppVisualStyleColors.titleBarSurface(
      resolvedStyle,
      effectiveBrightness,
    );

    try {
      await _channel.invokeMethod<void>('update', <String, Object>{
        'style': resolvedStyle.name,
        'brightness': effectiveBrightness.name,
        'accent': _accent.toARGB32(),
        'surface': titleBarSurface.toARGB32(),
      });
    } on MissingPluginException {
      // Native styling is optional when running Dart-only tests.
    } on PlatformException {
      // Keep the Flutter theme usable if an older runner is installed.
    }
  }

  @override
  void didChangePlatformBrightness() {
    if (_themeMode == ThemeMode.system) unawaited(update());
  }

  @override
  void didChangeAccessibilityFeatures() {
    unawaited(update());
  }

  Brightness _brightnessForThemeMode(ThemeMode mode) {
    return switch (mode) {
      ThemeMode.light => Brightness.light,
      ThemeMode.dark => Brightness.dark,
      ThemeMode.system =>
        WidgetsBinding.instance.platformDispatcher.platformBrightness,
    };
  }
}
