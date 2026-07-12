import 'package:flutter/material.dart';

class AppTypography {
  AppTypography._();

  // Primary app scale: 28px page, 20px section, 14px content.
  static const TextStyle pageTitle = TextStyle(
    fontSize: 28,
    fontWeight: FontWeight.w700,
    height: 1.2,
    letterSpacing: 0,
  );

  static const TextStyle sectionTitle = TextStyle(
    fontSize: 20,
    fontWeight: FontWeight.w600,
    height: 1.3,
    letterSpacing: 0,
  );

  static const TextStyle cardTitle = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w600,
    height: 1.4,
    letterSpacing: 0,
  );

  static const TextStyle body = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w400,
    height: 1.5,
    letterSpacing: 0,
  );

  static const TextStyle caption = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w400,
    height: 1.5,
    letterSpacing: 0,
  );

  static TextStyle pageTitleWith(Color color) =>
      pageTitle.copyWith(color: color);
  static TextStyle sectionTitleWith(Color color) =>
      sectionTitle.copyWith(color: color);
  static TextStyle cardTitleWith(Color color) =>
      cardTitle.copyWith(color: color);
  static TextStyle bodyWith(Color color) => body.copyWith(color: color);
  static TextStyle captionWith(Color color) => caption.copyWith(color: color);
}
