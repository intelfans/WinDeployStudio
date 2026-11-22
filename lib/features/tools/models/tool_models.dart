import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'dart:io';
import '../../../core/constants/app_constants.dart';
import '../../../core/localization/strings.dart';

String _loc(dynamic json, String key) {
  if (json == null) return '';
  if (json is Map) {
    final locale = normalizeLocaleCode(L.currentLocale);
    final language = locale.split('_').first;
    // Fall back down the chain instead of returning an empty string for a
    // supported locale whose tag is absent from the catalogue: an empty name
    // rendered a blank card and made the entry unsearchable.
    final localized = locale.contains('_')
        ? json['${key}_$locale'] as String?
        : null;
    if (localized != null && localized.trim().isNotEmpty) return localized;
    final byLanguage = json['${key}_$language'] as String?;
    if (byLanguage != null && byLanguage.trim().isNotEmpty) return byLanguage;
    final base = json[key] as String?;
    if (base != null && base.trim().isNotEmpty) return base;
    final english = json['${key}_en'] as String?;
    if (english != null && english.trim().isNotEmpty) return english;
    return '';
  }
  if (json is String) return json;
  return '';
}

List<String> _locList(dynamic json, String key) {
  if (json == null) return [];
  if (json is Map) {
    final locale = normalizeLocaleCode(L.currentLocale);
    final language = locale.split('_').first;
    List<String>? asList(Object? value) => value is List
        ? value.map((item) => item.toString()).toList(growable: false)
        : null;
    if (locale.contains('_')) {
      final exact = asList(json['${key}_$locale']);
      if (exact != null && exact.isNotEmpty) return exact;
    }
    final byLanguage = asList(json['${key}_$language']);
    if (byLanguage != null && byLanguage.isNotEmpty) return byLanguage;
    final base = asList(json[key]);
    if (base != null && base.isNotEmpty) return base;
    return asList(json['${key}_en']) ?? const <String>[];
  }
  if (json is List) return json.cast<String>();
  return [];
}

enum ToolSafetyLevel {
  beginner,
  advanced,
  expert;

  static ToolSafetyLevel fromJson(String? value) {
    return switch (value?.toLowerCase()) {
      'advanced' => ToolSafetyLevel.advanced,
      'expert' => ToolSafetyLevel.expert,
      _ => ToolSafetyLevel.beginner,
    };
  }

  String get labelKey {
    return switch (this) {
      ToolSafetyLevel.beginner => 'tool_safety_beginner',
      ToolSafetyLevel.advanced => 'tool_safety_advanced',
      ToolSafetyLevel.expert => 'tool_safety_expert',
    };
  }
}

class ToolItem {
  final String name;
  final String desc;
  final String icon;
  final String url;
  final String? downloadUrl;
  final String developer;
  final String version;
  final String license;
  final String releaseDate;
  final String rating;
  final bool featured;
  final List<String> tags;
  final List<String> screenshots;
  final List<String> features;
  final String? systemRequirements;
  final ToolSafetyLevel safetyLevel;
  final String categoryKey;

  const ToolItem({
    required this.name,
    required this.desc,
    required this.icon,
    required this.url,
    this.downloadUrl,
    this.developer = '',
    this.version = '',
    this.license = '',
    this.releaseDate = '',
    this.rating = '',
    this.featured = false,
    this.tags = const [],
    this.screenshots = const [],
    this.features = const [],
    this.systemRequirements,
    this.safetyLevel = ToolSafetyLevel.beginner,
    this.categoryKey = '',
  });

  factory ToolItem.fromJson(
    Map<String, dynamic> json, {
    String categoryKey = '',
  }) => ToolItem(
    name: _loc(json, 'name'),
    desc: _loc(json, 'desc'),
    icon: json['icon'] as String? ?? 'apps',
    url: json['url'] as String? ?? '',
    downloadUrl: json['downloadUrl'] as String?,
    developer: json['developer'] as String? ?? '',
    version: json['version'] as String? ?? '',
    license: _loc(json, 'license'),
    releaseDate: json['releaseDate'] as String? ?? '',
    rating: json['rating'] as String? ?? '',
    featured: json['featured'] as bool? ?? false,
    tags: _locList(json, 'tags'),
    screenshots: (json['screenshots'] as List?)?.cast<String>() ?? const [],
    features: _locList(json, 'features'),
    systemRequirements: _loc(json, 'systemRequirements'),
    safetyLevel: ToolSafetyLevel.fromJson(json['safetyLevel'] as String?),
    categoryKey: categoryKey,
  );

  IconData get iconData => _iconMap[icon] ?? Icons.apps_rounded;

  bool get isActivationRelated => categoryKey == 'tools_cat_activation';

  static const _iconMap = <String, IconData>{
    'usb': Icons.usb_rounded,
    'disc': Icons.disc_full_rounded,
    'disk': Icons.storage_rounded,
    'system': Icons.computer_rounded,
    'driver': Icons.device_hub_rounded,
    'network': Icons.language_rounded,
    'security': Icons.shield_rounded,
    'tools': Icons.build_rounded,
    'apps': Icons.apps_rounded,
    'download': Icons.download_rounded,
    'speed': Icons.speed_rounded,
    'partition': Icons.pie_chart_rounded,
    'image': Icons.image_rounded,
    'terminal': Icons.terminal_rounded,
    'monitor': Icons.monitor_rounded,
    'clean': Icons.cleaning_services_rounded,
    'key': Icons.key_rounded,
    'file': Icons.insert_drive_file_rounded,
    'archive': Icons.archive_rounded,
    'search': Icons.search_rounded,
    'copy': Icons.content_copy_rounded,
  };
}

class ToolCategory {
  final String nameKey;
  final String color;
  final List<ToolItem> tools;

  const ToolCategory({
    required this.nameKey,
    required this.color,
    required this.tools,
  });

  factory ToolCategory.fromJson(Map<String, dynamic> json) => ToolCategory(
    nameKey: json['nameKey'] as String? ?? '',
    color: json['color'] as String? ?? '#0071C5',
    tools:
        (json['tools'] as List?)
            ?.map(
              (t) => ToolItem.fromJson(
                t as Map<String, dynamic>,
                categoryKey: json['nameKey'] as String? ?? '',
              ),
            )
            .toList() ??
        [],
  );

  Color get displayColor {
    final hex = color.replaceFirst('#', '');
    return Color(int.parse('FF$hex', radix: 16));
  }
}

class ToolsData {
  final List<ToolCategory> categories;

  const ToolsData({required this.categories});

  factory ToolsData.fromJson(Map<String, dynamic> json) => ToolsData(
    categories:
        (json['categories'] as List?)
            ?.map((c) => ToolCategory.fromJson(c as Map<String, dynamic>))
            .toList() ??
        [],
  );

  List<ToolItem> get allTools => categories.expand((c) => c.tools).toList();

  List<ToolItem> get featuredTools =>
      allTools.where((t) => t.featured).toList();

  int get totalTools => allTools.length;

  int get totalCategories => categories.length;

  static Future<ToolsData> load() async {
    try {
      final content = await rootBundle.loadString('data/tools.json');
      return ToolsData.fromJson(jsonDecode(content));
    } catch (_) {}

    try {
      final file = File(
        p.join(AppConstants.appDataPath, 'WinDeployStudio', 'tools.json'),
      );
      if (file.existsSync()) {
        final content = await file.readAsString();
        return ToolsData.fromJson(jsonDecode(content));
      }
    } catch (_) {}

    return ToolsData(categories: []);
  }
}
