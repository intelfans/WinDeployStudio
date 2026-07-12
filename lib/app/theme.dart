import 'package:flutter/material.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'visual_style.dart';

export 'visual_style.dart';

final themeModeProvider = StateNotifierProvider<ThemeModeNotifier, ThemeMode>(
  (ref) => ThemeModeNotifier(ref.watch(initialAppearanceProvider).themeMode),
);

class ThemeModeNotifier extends StateNotifier<ThemeMode> {
  static const _prefKey = AppAppearanceSettings.themeModePreferenceKey;

  ThemeModeNotifier([super.initial = ThemeMode.system]);

  Future<void> setMode(ThemeMode mode) async {
    if (state != mode) state = mode;
    await WindowStyleChannel.instance.update(themeMode: mode);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefKey, mode.name);
  }
}

final seedColorProvider = StateNotifierProvider<SeedColorNotifier, Color>(
  (ref) => SeedColorNotifier(ref.watch(initialAppearanceProvider).accentColor),
);

final fontFamilyProvider = StateNotifierProvider<FontFamilyNotifier, String>(
  (ref) => FontFamilyNotifier(ref.watch(initialAppearanceProvider).fontFamily),
);

class SeedColorNotifier extends StateNotifier<Color> {
  static const _prefKey = AppAppearanceSettings.accentPreferenceKey;
  static const defaultColor = AppAppearanceSettings.defaultAccentColor;

  SeedColorNotifier([super.initial = defaultColor]);

  Future<void> setColor(Color color) async {
    if (state != color) state = color;
    await WindowStyleChannel.instance.update(accent: color);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_prefKey, color.toARGB32());
  }
}

class FontFamilyNotifier extends StateNotifier<String> {
  static const _prefKey = AppAppearanceSettings.fontFamilyPreferenceKey;
  static const defaultFont = AppAppearanceSettings.defaultFontFamily;

  FontFamilyNotifier([super.initial = defaultFont]);

  Future<void> setFont(String font) async {
    if (state != font) state = font;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefKey, font);
  }
}

@immutable
class AppVisualTokens extends ThemeExtension<AppVisualTokens> {
  const AppVisualTokens({
    required this.style,
    required this.surfaceRadius,
    required this.controlRadius,
    required this.compactRadius,
    required this.dialogRadius,
    required this.borderWidth,
    required this.controlHeight,
    required this.pagePadding,
    required this.sectionSpacing,
    required this.itemSpacing,
    required this.pageTitleSize,
    required this.sectionTitleSize,
    required this.bodyTextSize,
    required this.motionDuration,
    required this.surfaceShadow,
    required this.highContrast,
  });

  final VisualStyle style;
  final double surfaceRadius;
  final double controlRadius;
  final double compactRadius;
  final double dialogRadius;
  final double borderWidth;
  final double controlHeight;
  final double pagePadding;
  final double sectionSpacing;
  final double itemSpacing;
  final double pageTitleSize;
  final double sectionTitleSize;
  final double bodyTextSize;
  final Duration motionDuration;
  final List<BoxShadow> surfaceShadow;
  final bool highContrast;

  static AppVisualTokens of(BuildContext context) {
    return Theme.of(context).extension<AppVisualTokens>()!;
  }

  @override
  AppVisualTokens copyWith({
    VisualStyle? style,
    double? surfaceRadius,
    double? controlRadius,
    double? compactRadius,
    double? dialogRadius,
    double? borderWidth,
    double? controlHeight,
    double? pagePadding,
    double? sectionSpacing,
    double? itemSpacing,
    double? pageTitleSize,
    double? sectionTitleSize,
    double? bodyTextSize,
    Duration? motionDuration,
    List<BoxShadow>? surfaceShadow,
    bool? highContrast,
  }) {
    return AppVisualTokens(
      style: style ?? this.style,
      surfaceRadius: surfaceRadius ?? this.surfaceRadius,
      controlRadius: controlRadius ?? this.controlRadius,
      compactRadius: compactRadius ?? this.compactRadius,
      dialogRadius: dialogRadius ?? this.dialogRadius,
      borderWidth: borderWidth ?? this.borderWidth,
      controlHeight: controlHeight ?? this.controlHeight,
      pagePadding: pagePadding ?? this.pagePadding,
      sectionSpacing: sectionSpacing ?? this.sectionSpacing,
      itemSpacing: itemSpacing ?? this.itemSpacing,
      pageTitleSize: pageTitleSize ?? this.pageTitleSize,
      sectionTitleSize: sectionTitleSize ?? this.sectionTitleSize,
      bodyTextSize: bodyTextSize ?? this.bodyTextSize,
      motionDuration: motionDuration ?? this.motionDuration,
      surfaceShadow: surfaceShadow ?? this.surfaceShadow,
      highContrast: highContrast ?? this.highContrast,
    );
  }

  @override
  AppVisualTokens lerp(AppVisualTokens? other, double t) {
    if (other == null) return this;
    return AppVisualTokens(
      style: t < 0.5 ? style : other.style,
      surfaceRadius: lerpDouble(surfaceRadius, other.surfaceRadius, t),
      controlRadius: lerpDouble(controlRadius, other.controlRadius, t),
      compactRadius: lerpDouble(compactRadius, other.compactRadius, t),
      dialogRadius: lerpDouble(dialogRadius, other.dialogRadius, t),
      borderWidth: lerpDouble(borderWidth, other.borderWidth, t),
      controlHeight: lerpDouble(controlHeight, other.controlHeight, t),
      pagePadding: lerpDouble(pagePadding, other.pagePadding, t),
      sectionSpacing: lerpDouble(sectionSpacing, other.sectionSpacing, t),
      itemSpacing: lerpDouble(itemSpacing, other.itemSpacing, t),
      pageTitleSize: lerpDouble(pageTitleSize, other.pageTitleSize, t),
      sectionTitleSize: lerpDouble(sectionTitleSize, other.sectionTitleSize, t),
      bodyTextSize: lerpDouble(bodyTextSize, other.bodyTextSize, t),
      motionDuration: t < 0.5 ? motionDuration : other.motionDuration,
      surfaceShadow: t < 0.5 ? surfaceShadow : other.surfaceShadow,
      highContrast: t < 0.5 ? highContrast : other.highContrast,
    );
  }

  static double lerpDouble(double begin, double end, double t) {
    return begin + (end - begin) * t;
  }
}

class AppTheme {
  AppTheme._();

  static const intelBlue = Color(0xFF0071C5);

  static const List<int> presetColors = [
    0xFF0071C5,
    0xFF00A4EF,
    0xFF107C10,
    0xFF7B61FF,
    0xFFEC4899,
    0xFFF97316,
    0xFFEF4444,
    0xFF6366F1,
    0xFF14B8A6,
    0xFFA855F7,
    0xFFEAB308,
    0xFF78716C,
  ];

  static const double bodyFontSize = 14;
  static const double sectionFontSize = 20;
  static const double pageFontSize = 28;

  static const double cardRadius = 12;
  static const double buttonRadius = 8;
  static const double dialogRadius = 12;
  static const double chipRadius = 8;

  static ThemeData light(
    Color seedColor,
    String fontFamily, {
    VisualStyle? style,
  }) {
    return _build(
      seedColor: seedColor,
      fontFamily: fontFamily,
      brightness: Brightness.light,
      style: style ?? VisualStyleNotifier.current,
      highContrast: false,
    );
  }

  static ThemeData dark(
    Color seedColor,
    String fontFamily, {
    VisualStyle? style,
  }) {
    return _build(
      seedColor: seedColor,
      fontFamily: fontFamily,
      brightness: Brightness.dark,
      style: style ?? VisualStyleNotifier.current,
      highContrast: false,
    );
  }

  static ThemeData highContrastLight(
    Color seedColor,
    String fontFamily, {
    VisualStyle? style,
  }) {
    return _build(
      seedColor: seedColor,
      fontFamily: fontFamily,
      brightness: Brightness.light,
      style: style ?? VisualStyleNotifier.current,
      highContrast: true,
    );
  }

  static ThemeData highContrastDark(
    Color seedColor,
    String fontFamily, {
    VisualStyle? style,
  }) {
    return _build(
      seedColor: seedColor,
      fontFamily: fontFamily,
      brightness: Brightness.dark,
      style: style ?? VisualStyleNotifier.current,
      highContrast: true,
    );
  }

  static ThemeData _build({
    required Color seedColor,
    required String fontFamily,
    required Brightness brightness,
    required VisualStyle style,
    required bool highContrast,
  }) {
    final resolvedStyle = style.resolved;
    final spec = _VisualStyleSpec.forStyle(
      resolvedStyle,
      brightness,
      highContrast: highContrast,
    );
    final colors = spec.colorScheme(seedColor);
    final textTheme = _textTheme(fontFamily, colors);
    final surfaceBorder = BorderSide(
      color: colors.outlineVariant,
      width: spec.borderWidth,
    );
    final controlShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(spec.controlRadius),
    );
    final surfaceShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(spec.surfaceRadius),
      side: surfaceBorder,
    );
    final buttonPadding = EdgeInsets.symmetric(
      horizontal: resolvedStyle == VisualStyle.win7 ? 14 : 18,
      vertical: 10,
    );

    final theme = ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: colors,
      scaffoldBackgroundColor: spec.scaffold,
      canvasColor: spec.scaffold,
      cardColor: spec.surface,
      dividerColor: colors.outlineVariant,
      fontFamily: fontFamily,
      textTheme: textTheme,
      primaryTextTheme: textTheme,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      visualDensity: spec.visualDensity,
      splashFactory: resolvedStyle == VisualStyle.win7
          ? InkSplash.splashFactory
          : InkRipple.splashFactory,
      extensions: <ThemeExtension<dynamic>>[spec.tokens],
      appBarTheme: AppBarTheme(
        centerTitle: false,
        elevation: 0,
        scrolledUnderElevation: resolvedStyle == VisualStyle.win11 ? 1 : 0,
        backgroundColor: spec.appBar,
        foregroundColor: colors.onSurface,
        surfaceTintColor: resolvedStyle == VisualStyle.win11
            ? colors.surfaceTint
            : Colors.transparent,
        titleTextStyle: textTheme.titleLarge,
        shape: highContrast
            ? Border(bottom: BorderSide(color: colors.outline, width: 2))
            : null,
      ),
      cardTheme: CardThemeData(
        elevation: spec.cardElevation,
        shadowColor: colors.shadow,
        surfaceTintColor: Colors.transparent,
        color: spec.surface,
        margin: EdgeInsets.zero,
        shape: surfaceShape,
      ),
      navigationRailTheme: NavigationRailThemeData(
        elevation: 0,
        backgroundColor: spec.navigation,
        indicatorColor: colors.secondaryContainer,
        indicatorShape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(spec.controlRadius),
        ),
        selectedIconTheme: IconThemeData(color: colors.onSecondaryContainer),
        selectedLabelTextStyle: textTheme.labelMedium?.copyWith(
          color: colors.onSurface,
          fontWeight: FontWeight.w600,
        ),
        unselectedIconTheme: IconThemeData(color: colors.onSurfaceVariant),
        unselectedLabelTextStyle: textTheme.labelMedium?.copyWith(
          color: colors.onSurfaceVariant,
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        elevation: 0,
        backgroundColor: spec.navigation,
        indicatorColor: colors.secondaryContainer,
        indicatorShape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(spec.controlRadius),
        ),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          return textTheme.labelMedium?.copyWith(
            color: states.contains(WidgetState.selected)
                ? colors.onSurface
                : colors.onSurfaceVariant,
            fontWeight: states.contains(WidgetState.selected)
                ? FontWeight.w600
                : FontWeight.w400,
          );
        }),
      ),
      inputDecorationTheme: InputDecorationThemeData(
        filled: true,
        fillColor: spec.input,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 12,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(spec.controlRadius),
          borderSide: surfaceBorder,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(spec.controlRadius),
          borderSide: surfaceBorder,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(spec.controlRadius),
          borderSide: BorderSide(
            color: colors.primary,
            width: highContrast ? 3 : 2,
          ),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(spec.controlRadius),
          borderSide: BorderSide(color: colors.error, width: spec.borderWidth),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(spec.controlRadius),
          borderSide: BorderSide(
            color: colors.error,
            width: highContrast ? 3 : 2,
          ),
        ),
        labelStyle: textTheme.bodyMedium?.copyWith(
          color: colors.onSurfaceVariant,
        ),
        hintStyle: textTheme.bodyMedium?.copyWith(
          color: colors.onSurfaceVariant,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          minimumSize: Size(0, spec.controlHeight),
          padding: buttonPadding,
          elevation: spec.buttonElevation,
          shadowColor: colors.shadow,
          foregroundColor: colors.primary,
          backgroundColor: spec.surface,
          disabledBackgroundColor: colors.surfaceContainerHighest,
          shape: controlShape.copyWith(side: surfaceBorder),
          textStyle: textTheme.labelLarge,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: Size(0, spec.controlHeight),
          padding: buttonPadding,
          shape: controlShape,
          textStyle: textTheme.labelLarge,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: Size(0, spec.controlHeight),
          padding: buttonPadding,
          side: BorderSide(
            color: highContrast ? colors.outline : colors.outlineVariant,
            width: spec.borderWidth,
          ),
          shape: controlShape,
          textStyle: textTheme.labelLarge,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          minimumSize: Size(0, spec.controlHeight),
          padding: buttonPadding,
          shape: controlShape,
          textStyle: textTheme.labelLarge,
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: ButtonStyle(
          minimumSize: WidgetStatePropertyAll(
            Size(spec.controlHeight, spec.controlHeight),
          ),
          shape: WidgetStatePropertyAll(controlShape),
        ),
      ),
      dialogTheme: DialogThemeData(
        elevation: spec.dialogElevation,
        shadowColor: colors.shadow,
        surfaceTintColor: Colors.transparent,
        backgroundColor: spec.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(spec.dialogRadius),
          side: surfaceBorder,
        ),
        titleTextStyle: textTheme.titleLarge,
        contentTextStyle: textTheme.bodyMedium,
      ),
      bottomSheetTheme: BottomSheetThemeData(
        elevation: spec.dialogElevation,
        modalElevation: spec.dialogElevation,
        backgroundColor: spec.surface,
        modalBackgroundColor: spec.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(spec.dialogRadius),
          ),
          side: surfaceBorder,
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: spec.input,
        selectedColor: colors.secondaryContainer,
        disabledColor: colors.surfaceContainerHighest,
        side: surfaceBorder,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(spec.compactRadius),
        ),
        labelStyle: textTheme.labelMedium,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      ),
      listTileTheme: ListTileThemeData(
        dense: resolvedStyle != VisualStyle.win11,
        minTileHeight: resolvedStyle == VisualStyle.win7 ? 40 : 44,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
        shape: controlShape,
        titleTextStyle: textTheme.bodyMedium?.copyWith(
          color: colors.onSurface,
          fontWeight: FontWeight.w500,
        ),
        subtitleTextStyle: textTheme.bodySmall?.copyWith(
          color: colors.onSurfaceVariant,
        ),
        iconColor: colors.onSurfaceVariant,
        selectedColor: colors.primary,
        selectedTileColor: colors.secondaryContainer,
      ),
      dividerTheme: DividerThemeData(
        color: highContrast ? colors.outline : colors.outlineVariant,
        thickness: spec.borderWidth,
        space: 1,
      ),
      checkboxTheme: CheckboxThemeData(
        side: BorderSide(color: colors.outline, width: spec.borderWidth),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(spec.compactRadius / 2),
        ),
      ),
      radioTheme: RadioThemeData(
        fillColor: WidgetStateProperty.resolveWith((states) {
          return states.contains(WidgetState.selected)
              ? colors.primary
              : colors.outline;
        }),
      ),
      switchTheme: SwitchThemeData(
        trackOutlineColor: WidgetStateProperty.resolveWith((states) {
          return states.contains(WidgetState.selected)
              ? colors.primary
              : colors.outline;
        }),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          minimumSize: WidgetStatePropertyAll(Size(0, spec.controlHeight)),
          side: WidgetStatePropertyAll(surfaceBorder),
          shape: WidgetStatePropertyAll(controlShape),
          textStyle: WidgetStatePropertyAll(textTheme.labelLarge),
        ),
      ),
      menuTheme: MenuThemeData(
        style: MenuStyle(
          backgroundColor: WidgetStatePropertyAll(spec.surface),
          elevation: WidgetStatePropertyAll(spec.dialogElevation),
          shadowColor: WidgetStatePropertyAll(colors.shadow),
          side: WidgetStatePropertyAll(surfaceBorder),
          shape: WidgetStatePropertyAll(surfaceShape),
          padding: const WidgetStatePropertyAll(EdgeInsets.all(4)),
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: spec.surface,
        surfaceTintColor: Colors.transparent,
        elevation: spec.dialogElevation,
        shadowColor: colors.shadow,
        shape: surfaceShape,
        textStyle: textTheme.bodyMedium,
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: colors.inverseSurface,
          borderRadius: BorderRadius.circular(spec.compactRadius),
          border: highContrast
              ? Border.all(color: colors.onInverseSurface, width: 2)
              : null,
        ),
        textStyle: textTheme.bodySmall?.copyWith(
          color: colors.onInverseSurface,
        ),
        waitDuration: const Duration(milliseconds: 500),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        elevation: spec.dialogElevation,
        backgroundColor: colors.inverseSurface,
        contentTextStyle: textTheme.bodyMedium?.copyWith(
          color: colors.onInverseSurface,
        ),
        shape: controlShape,
      ),
      scrollbarTheme: ScrollbarThemeData(
        thickness: WidgetStatePropertyAll(
          resolvedStyle == VisualStyle.win11 ? 6 : 8,
        ),
        radius: Radius.circular(spec.compactRadius),
        thumbColor: WidgetStateProperty.resolveWith((states) {
          return states.contains(WidgetState.hovered)
              ? colors.onSurfaceVariant
              : colors.outline;
        }),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: colors.primary,
        linearTrackColor: colors.surfaceContainerHighest,
        circularTrackColor: colors.surfaceContainerHighest,
      ),
    );

    return theme.copyWith(
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: <TargetPlatform, PageTransitionsBuilder>{
          TargetPlatform.windows: FadeForwardsPageTransitionsBuilder(),
        },
      ),
    );
  }

  static TextTheme _textTheme(String fontFamily, ColorScheme colors) {
    final typography = Typography.material2021(
      platform: TargetPlatform.windows,
      colorScheme: colors,
    );
    final base =
        (colors.brightness == Brightness.dark
                ? typography.white
                : typography.black)
            .apply(
              fontFamily: fontFamily,
              bodyColor: colors.onSurface,
              displayColor: colors.onSurface,
            );
    return base.copyWith(
      displaySmall: base.displaySmall?.copyWith(
        fontSize: pageFontSize,
        height: 1.2,
        fontWeight: FontWeight.w700,
        letterSpacing: 0,
      ),
      headlineMedium: base.headlineMedium?.copyWith(
        fontSize: pageFontSize,
        height: 1.2,
        fontWeight: FontWeight.w700,
        letterSpacing: 0,
      ),
      titleLarge: base.titleLarge?.copyWith(
        fontSize: sectionFontSize,
        height: 1.3,
        fontWeight: FontWeight.w600,
        letterSpacing: 0,
      ),
      titleMedium: base.titleMedium?.copyWith(
        fontSize: 16,
        height: 1.35,
        fontWeight: FontWeight.w600,
        letterSpacing: 0,
      ),
      titleSmall: base.titleSmall?.copyWith(
        fontSize: bodyFontSize,
        height: 1.4,
        fontWeight: FontWeight.w600,
        letterSpacing: 0,
      ),
      bodyLarge: base.bodyLarge?.copyWith(
        fontSize: bodyFontSize,
        height: 1.5,
        letterSpacing: 0,
      ),
      bodyMedium: base.bodyMedium?.copyWith(
        fontSize: bodyFontSize,
        height: 1.5,
        letterSpacing: 0,
      ),
      bodySmall: base.bodySmall?.copyWith(
        fontSize: 12,
        height: 1.45,
        letterSpacing: 0,
      ),
      labelLarge: base.labelLarge?.copyWith(
        fontSize: bodyFontSize,
        height: 1.2,
        fontWeight: FontWeight.w600,
        letterSpacing: 0,
      ),
      labelMedium: base.labelMedium?.copyWith(
        fontSize: 12,
        height: 1.2,
        fontWeight: FontWeight.w500,
        letterSpacing: 0,
      ),
      labelSmall: base.labelSmall?.copyWith(
        fontSize: 11,
        height: 1.2,
        letterSpacing: 0,
      ),
    );
  }
}

class _VisualStyleSpec {
  const _VisualStyleSpec({
    required this.style,
    required this.brightness,
    required this.highContrast,
    required this.scaffold,
    required this.surface,
    required this.input,
    required this.navigation,
    required this.appBar,
    required this.surfaceRadius,
    required this.controlRadius,
    required this.compactRadius,
    required this.dialogRadius,
    required this.borderWidth,
    required this.controlHeight,
    required this.cardElevation,
    required this.buttonElevation,
    required this.dialogElevation,
    required this.visualDensity,
    required this.surfaceShadow,
  });

  final VisualStyle style;
  final Brightness brightness;
  final bool highContrast;
  final Color scaffold;
  final Color surface;
  final Color input;
  final Color navigation;
  final Color appBar;
  final double surfaceRadius;
  final double controlRadius;
  final double compactRadius;
  final double dialogRadius;
  final double borderWidth;
  final double controlHeight;
  final double cardElevation;
  final double buttonElevation;
  final double dialogElevation;
  final VisualDensity visualDensity;
  final List<BoxShadow> surfaceShadow;

  AppVisualTokens get tokens => AppVisualTokens(
    style: style,
    surfaceRadius: surfaceRadius,
    controlRadius: controlRadius,
    compactRadius: compactRadius,
    dialogRadius: dialogRadius,
    borderWidth: borderWidth,
    controlHeight: controlHeight,
    pagePadding: style == VisualStyle.win11 ? 24 : 20,
    sectionSpacing: style == VisualStyle.win7 ? 16 : 20,
    itemSpacing: style == VisualStyle.win11 ? 12 : 8,
    pageTitleSize: AppTheme.pageFontSize,
    sectionTitleSize: AppTheme.sectionFontSize,
    bodyTextSize: AppTheme.bodyFontSize,
    motionDuration: switch (style) {
      VisualStyle.win11 => const Duration(milliseconds: 180),
      VisualStyle.win10 => const Duration(milliseconds: 120),
      VisualStyle.win7 => const Duration(milliseconds: 90),
      VisualStyle.auto => const Duration(milliseconds: 180),
    },
    surfaceShadow: surfaceShadow,
    highContrast: highContrast,
  );

  ColorScheme colorScheme(Color seedColor) {
    final generated = ColorScheme.fromSeed(
      seedColor: seedColor,
      brightness: brightness,
      contrastLevel: highContrast ? 1 : 0,
    );
    if (highContrast) {
      final isDark = brightness == Brightness.dark;
      final canvas = isDark ? Colors.black : Colors.white;
      final foreground = isDark ? Colors.white : Colors.black;
      return generated.copyWith(
        surface: canvas,
        surfaceDim: canvas,
        surfaceBright: canvas,
        surfaceContainerLowest: canvas,
        surfaceContainerLow: canvas,
        surfaceContainer: canvas,
        surfaceContainerHigh: canvas,
        surfaceContainerHighest: canvas,
        onSurface: foreground,
        onSurfaceVariant: foreground,
        outline: foreground,
        outlineVariant: foreground,
        shadow: Colors.transparent,
        scrim: foreground,
        surfaceTint: Colors.transparent,
      );
    }

    final isDark = brightness == Brightness.dark;
    final surfaceLow = switch ((style, isDark)) {
      (VisualStyle.win11, false) => const Color(0xFFF8F8F8),
      (VisualStyle.win11, true) => const Color(0xFF252525),
      (VisualStyle.win10, false) => const Color(0xFFF7F7F7),
      (VisualStyle.win10, true) => const Color(0xFF202020),
      (VisualStyle.win7, false) => const Color(0xFFF4F8FC),
      (VisualStyle.win7, true) => const Color(0xFF22272D),
      (VisualStyle.auto, false) => const Color(0xFFF8F8F8),
      (VisualStyle.auto, true) => const Color(0xFF252525),
    };
    final surfaceHigh = switch ((style, isDark)) {
      (VisualStyle.win11, false) => const Color(0xFFE9E9E9),
      (VisualStyle.win11, true) => const Color(0xFF3A3A3A),
      (VisualStyle.win10, false) => const Color(0xFFE1E1E1),
      (VisualStyle.win10, true) => const Color(0xFF393939),
      (VisualStyle.win7, false) => const Color(0xFFDCE7F1),
      (VisualStyle.win7, true) => const Color(0xFF3D464F),
      (VisualStyle.auto, false) => const Color(0xFFE9E9E9),
      (VisualStyle.auto, true) => const Color(0xFF3A3A3A),
    };
    final outline = switch ((style, isDark)) {
      (VisualStyle.win11, false) => const Color(0xFFD1D1D1),
      (VisualStyle.win11, true) => const Color(0xFF505050),
      (VisualStyle.win10, false) => const Color(0xFFB8B8B8),
      (VisualStyle.win10, true) => const Color(0xFF626262),
      (VisualStyle.win7, false) => const Color(0xFF9DADB9),
      (VisualStyle.win7, true) => const Color(0xFF6D7882),
      (VisualStyle.auto, false) => const Color(0xFFD1D1D1),
      (VisualStyle.auto, true) => const Color(0xFF505050),
    };
    return generated.copyWith(
      surface: surface,
      surfaceDim: scaffold,
      surfaceBright: surface,
      surfaceContainerLowest: surface,
      surfaceContainerLow: surfaceLow,
      surfaceContainer: input,
      surfaceContainerHigh: surfaceHigh,
      surfaceContainerHighest: surfaceHigh,
      outline: outline,
      outlineVariant: outline.withValues(alpha: 0.72),
      shadow: isDark ? Colors.black : const Color(0x55000000),
      surfaceTint: style == VisualStyle.win11
          ? generated.primary
          : Colors.transparent,
    );
  }

  static _VisualStyleSpec forStyle(
    VisualStyle style,
    Brightness brightness, {
    required bool highContrast,
  }) {
    final isDark = brightness == Brightness.dark;
    if (highContrast) {
      final canvas = isDark ? Colors.black : Colors.white;
      return _VisualStyleSpec(
        style: style,
        brightness: brightness,
        highContrast: true,
        scaffold: canvas,
        surface: canvas,
        input: canvas,
        navigation: canvas,
        appBar: canvas,
        surfaceRadius: _surfaceRadius(style),
        controlRadius: _controlRadius(style),
        compactRadius: _compactRadius(style),
        dialogRadius: _dialogRadius(style),
        borderWidth: 2,
        controlHeight: 44,
        cardElevation: 0,
        buttonElevation: 0,
        dialogElevation: 0,
        visualDensity: VisualDensity.standard,
        surfaceShadow: const <BoxShadow>[],
      );
    }

    return switch (style) {
      VisualStyle.win11 => _VisualStyleSpec(
        style: style,
        brightness: brightness,
        highContrast: false,
        scaffold: isDark ? const Color(0xFF202020) : const Color(0xFFF3F3F3),
        surface: isDark ? const Color(0xFF2B2B2B) : const Color(0xFFFBFBFB),
        input: isDark ? const Color(0xFF323232) : const Color(0xFFFFFFFF),
        navigation: isDark ? const Color(0xFF1E1E1E) : const Color(0xFFF7F7F7),
        appBar: AppVisualStyleColors.titleBarSurface(style, brightness),
        surfaceRadius: 12,
        controlRadius: 8,
        compactRadius: 8,
        dialogRadius: 12,
        borderWidth: 1,
        controlHeight: 40,
        cardElevation: 1,
        buttonElevation: 1,
        dialogElevation: 8,
        visualDensity: VisualDensity.standard,
        surfaceShadow: const [
          BoxShadow(
            color: Color(0x1A000000),
            blurRadius: 12,
            offset: Offset(0, 4),
          ),
        ],
      ),
      VisualStyle.win10 => _VisualStyleSpec(
        style: style,
        brightness: brightness,
        highContrast: false,
        scaffold: isDark ? const Color(0xFF171717) : const Color(0xFFF2F2F2),
        surface: isDark ? const Color(0xFF242424) : Colors.white,
        input: isDark ? const Color(0xFF2B2B2B) : Colors.white,
        navigation: isDark ? const Color(0xFF1C1C1C) : const Color(0xFFF2F2F2),
        appBar: AppVisualStyleColors.titleBarSurface(style, brightness),
        surfaceRadius: 8,
        controlRadius: 8,
        compactRadius: 8,
        dialogRadius: 8,
        borderWidth: 1,
        controlHeight: 38,
        cardElevation: 0,
        buttonElevation: 0,
        dialogElevation: 6,
        visualDensity: const VisualDensity(horizontal: -1, vertical: -1),
        surfaceShadow: const [
          BoxShadow(
            color: Color(0x24000000),
            blurRadius: 8,
            offset: Offset(0, 3),
          ),
        ],
      ),
      VisualStyle.win7 => _VisualStyleSpec(
        style: style,
        brightness: brightness,
        highContrast: false,
        scaffold: isDark ? const Color(0xFF1B2026) : const Color(0xFFEAF1F7),
        surface: isDark ? const Color(0xFF282E35) : const Color(0xFFFDFEFE),
        input: isDark ? const Color(0xFF20252B) : const Color(0xFFFFFFFF),
        navigation: isDark ? const Color(0xFF22282E) : const Color(0xFFDCE8F2),
        appBar: AppVisualStyleColors.titleBarSurface(style, brightness),
        surfaceRadius: 8,
        controlRadius: 8,
        compactRadius: 8,
        dialogRadius: 8,
        borderWidth: 1,
        controlHeight: 36,
        cardElevation: 2,
        buttonElevation: 1,
        dialogElevation: 10,
        visualDensity: const VisualDensity(horizontal: -1, vertical: -2),
        surfaceShadow: const [
          BoxShadow(
            color: Color(0x38000000),
            blurRadius: 6,
            offset: Offset(0, 2),
          ),
        ],
      ),
      VisualStyle.auto => throw StateError('VisualStyle.auto must be resolved'),
    };
  }

  static double _surfaceRadius(VisualStyle style) => switch (style) {
    VisualStyle.win11 || VisualStyle.auto => 12,
    VisualStyle.win10 => 8,
    VisualStyle.win7 => 8,
  };

  static double _controlRadius(VisualStyle style) => switch (style) {
    VisualStyle.win11 || VisualStyle.auto => 8,
    VisualStyle.win10 => 8,
    VisualStyle.win7 => 8,
  };

  static double _compactRadius(VisualStyle style) => switch (style) {
    VisualStyle.win11 || VisualStyle.auto => 8,
    VisualStyle.win10 => 8,
    VisualStyle.win7 => 8,
  };

  static double _dialogRadius(VisualStyle style) => switch (style) {
    VisualStyle.win11 || VisualStyle.auto => 12,
    VisualStyle.win10 => 8,
    VisualStyle.win7 => 8,
  };
}

