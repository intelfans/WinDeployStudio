import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';


final themeModeProvider = StateProvider<ThemeMode>(
  (_) => ThemeMode.system,
);

final seedColorProvider = StateNotifierProvider<SeedColorNotifier, Color>(
  (ref) => SeedColorNotifier(),
);

final fontFamilyProvider = StateNotifierProvider<FontFamilyNotifier, String>(
  (ref) => FontFamilyNotifier(),
);

class SeedColorNotifier extends StateNotifier<Color> {
  static const _prefKey = 'theme_color';
  static const defaultColor = Color(0xFF0071C5); // Intel Blue

  SeedColorNotifier() : super(defaultColor) {
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.getInt(_prefKey);
    if (value != null) {
      state = Color(value);
    }
  }

  Future<void> setColor(Color color) async {
    state = color;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_prefKey, color.toARGB32());
  }
}

class FontFamilyNotifier extends StateNotifier<String> {
  static const _prefKey = 'font_family';
  static const defaultFont = 'HarmonyOSSans';

  FontFamilyNotifier() : super(defaultFont) {
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.getString(_prefKey);
    if (value != null) {
      state = value;
    }
  }

  Future<void> setFont(String font) async {
    state = font;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefKey, font);
  }
}

class AppTheme {
  AppTheme._();

  // Intel Blue
  static const intelBlue = Color(0xFF0071C5);

  // Preset Colors
  static const List<int> presetColors = [
    0xFF0071C5, // Intel Blue
    0xFF00A4EF, // Cyan
    0xFF107C10, // Green
    0xFF7B61FF, // Purple
    0xFFEC4899, // Pink
    0xFFF97316, // Orange
    0xFFEF4444, // Red
    0xFF6366F1, // Indigo
    0xFF14B8A6, // Teal
    0xFFA855F7, // Violet
    0xFFEAB308, // Yellow
    0xFF78716C, // Stone
  ];

  // Win11 Border Radius
  static const double cardRadius = 20;
  static const double buttonRadius = 16;
  static const double dialogRadius = 24;
  static const double chipRadius = 8;

  static ThemeData light(Color seedColor, String fontFamily) {
    return ThemeData(
      useMaterial3: true,
      colorSchemeSeed: seedColor,
      brightness: Brightness.light,
      fontFamily: fontFamily,
      scaffoldBackgroundColor: const Color(0xFFF5F5F5),
      cardTheme: CardThemeData(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(cardRadius),
        ),
        color: Colors.white,
      ),
      appBarTheme: const AppBarTheme(
        centerTitle: false,
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: Colors.transparent,
        indicatorShape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(buttonRadius),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(buttonRadius),
          borderSide: BorderSide(color: Colors.grey.shade300),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(buttonRadius),
          borderSide: BorderSide(color: Colors.grey.shade300),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(buttonRadius),
          borderSide: BorderSide(color: seedColor, width: 2),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 12,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(buttonRadius),
          ),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(buttonRadius),
          ),
        ),
      ),
      dialogTheme: DialogThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(dialogRadius),
        ),
      ),
      chipTheme: ChipThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(chipRadius),
        ),
      ),
    );
  }

  static ThemeData dark(Color seedColor, String fontFamily) {
    return ThemeData(
      useMaterial3: true,
      colorSchemeSeed: seedColor,
      brightness: Brightness.dark,
      fontFamily: fontFamily,
      scaffoldBackgroundColor: const Color(0xFF1E1E1E),
      cardTheme: CardThemeData(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(cardRadius),
        ),
        color: const Color(0xFF2D2D2D),
      ),
      appBarTheme: const AppBarTheme(
        centerTitle: false,
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: Colors.transparent,
        indicatorShape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(buttonRadius),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0xFF2D2D2D),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(buttonRadius),
          borderSide: BorderSide(color: Colors.grey.shade700),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(buttonRadius),
          borderSide: BorderSide(color: Colors.grey.shade700),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(buttonRadius),
          borderSide: BorderSide(color: seedColor, width: 2),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 12,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(buttonRadius),
          ),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(buttonRadius),
          ),
        ),
      ),
      dialogTheme: DialogThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(dialogRadius),
        ),
      ),
      chipTheme: ChipThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(chipRadius),
        ),
      ),
    );
  }
}
