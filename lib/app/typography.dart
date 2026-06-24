import 'package:flutter/material.dart';

class AppTypography {
  AppTypography._();

  static const String _fontFamily = 'HarmonyOSSans';

  // Page Title - 36px Black (900)
  static const TextStyle pageTitle = TextStyle(
    fontFamily: _fontFamily,
    fontSize: 36,
    fontWeight: FontWeight.w900,
    height: 1.2,
  );

  // Section Title - 24px Bold (700)
  static const TextStyle sectionTitle = TextStyle(
    fontFamily: _fontFamily,
    fontSize: 24,
    fontWeight: FontWeight.w700,
    height: 1.3,
  );

  // Card Title - 18px Medium (500)
  static const TextStyle cardTitle = TextStyle(
    fontFamily: _fontFamily,
    fontSize: 18,
    fontWeight: FontWeight.w500,
    height: 1.4,
  );

  // Body - 14px Regular (400)
  static const TextStyle body = TextStyle(
    fontFamily: _fontFamily,
    fontSize: 14,
    fontWeight: FontWeight.w400,
    height: 1.5,
  );

  // Caption - 12px Light (300)
  static const TextStyle caption = TextStyle(
    fontFamily: _fontFamily,
    fontSize: 12,
    fontWeight: FontWeight.w300,
    height: 1.5,
  );

  // Helper methods for custom styles
  static TextStyle pageTitleWith(Color color) => pageTitle.copyWith(color: color);
  static TextStyle sectionTitleWith(Color color) => sectionTitle.copyWith(color: color);
  static TextStyle cardTitleWith(Color color) => cardTitle.copyWith(color: color);
  static TextStyle bodyWith(Color color) => body.copyWith(color: color);
  static TextStyle captionWith(Color color) => caption.copyWith(color: color);
}
