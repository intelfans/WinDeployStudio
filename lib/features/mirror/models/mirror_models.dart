import 'dart:ui';

import '../../../core/localization/strings.dart';

class MirrorItem {
  final String id;
  final Map<String, String> _name;
  final String category;
  final Map<String, String>? _type;
  final String? version;
  final String? build;
  final String? architecture;
  final Map<String, String>? _description;
  final Map<String, String>? _audience;
  final Map<String, List<String>> _pros;
  final Map<String, List<String>> _notes;
  final String downloadUrl;
  final String? sha256;
  final String? size;
  final bool needsFontPack;
  final String? fontPackUrl;
  final String? chinaUrl;
  final String? globalUrl;

  const MirrorItem._({
    required this.id,
    required this._name,
    required this.category,
    this._type,
    this.version,
    this.build,
    this.architecture,
    this._description,
    this._audience,
    this._pros = const {},
    this._notes = const {},
    required this.downloadUrl,
    this.sha256,
    this.size,
    this.needsFontPack = false,
    this.fontPackUrl,
    this.chinaUrl,
    this.globalUrl,
  });

  String _localize(Map<String, String>? map, Locale locale) {
    if (map == null) return '';
    final code = _localeCode(locale);
    final isSupported = isSupportedLocaleCode(code);
    final localized = isSupported && code.contains('_')
        ? map[code]
        : map[code] ?? map[locale.languageCode];
    if (localized != null) return localized;
    return '';
  }

  List<String> _localizeList(Map<String, List<String>>? map, Locale locale) {
    if (map == null) return [];
    final code = _localeCode(locale);
    final isSupported = isSupportedLocaleCode(code);
    final localized = isSupported && code.contains('_')
        ? map[code]
        : map[code] ?? map[locale.languageCode];
    if (localized != null) return localized;
    return [];
  }

  String _localeCode(Locale locale) {
    return normalizeLocaleCode(localeCodeFromLocale(locale));
  }

  String getName(Locale locale) => _localize(_name, locale);
  String getType(Locale locale) => _localize(_type, locale);
  String getDescription(Locale locale) => _localize(_description, locale);
  String getAudience(Locale locale) => _localize(_audience, locale);
  List<String> getPros(Locale locale) => _localizeList(_pros, locale);
  List<String> getNotes(Locale locale) => _localizeList(_notes, locale);

  bool get isOfficialMicrosoft => category == 'Official Microsoft';
  bool get isCommunityImage => category == 'Community Images';
  bool get isImageCenterItem => isOfficialMicrosoft || isCommunityImage;
  bool get isStarValleyX => id == 'starvalleyx';

  String get productLogName {
    return switch (id) {
      'official-win11' => 'Windows11',
      'official-win10' => 'Windows10',
      'tiny11' => 'Tiny11',
      'tiny10' => 'Tiny10',
      'xlite11' => 'WindowsXLite11',
      'xlite10' => 'WindowsXLite10',
      'starvalleyx' => 'StarValleyX',
      _ => id,
    };
  }

  bool isVisibleInLocale(Locale locale) {
    if (!isImageCenterItem) return false;
    if (!isStarValleyX) return true;
    return normalizeLocaleCode(localeCodeFromLocale(locale)).startsWith('zh');
  }

  factory MirrorItem.fromJson(Map<String, dynamic> json) {
    Map<String, String>? parseStringMap(dynamic value) {
      if (value == null) return null;
      if (value is String) return {'zh': value, 'en': value};
      if (value is Map) return Map<String, String>.from(value);
      return null;
    }

    Map<String, List<String>>? parseListMap(dynamic value) {
      if (value == null) return null;
      if (value is List) {
        final list = value.map((e) => e.toString()).toList();
        return {'zh': list, 'en': list};
      }
      if (value is Map) {
        return value.map(
          (k, v) => MapEntry(
            k.toString(),
            (v as List).map((e) => e.toString()).toList(),
          ),
        );
      }
      return null;
    }

    return MirrorItem._(
      id: json['id'] as String? ?? '',
      name: parseStringMap(json['name']) ?? {},
      category: json['category'] as String? ?? 'Other',
      type: parseStringMap(json['type']),
      version: json['version'] as String?,
      build: json['build'] as String?,
      architecture: json['architecture'] as String?,
      description: parseStringMap(json['description']),
      audience: parseStringMap(json['audience']),
      pros: parseListMap(json['pros']) ?? {},
      notes: parseListMap(json['notes']) ?? {},
      downloadUrl: json['downloadUrl'] as String? ?? '',
      sha256: json['sha256'] as String?,
      size: json['size'] as String?,
      needsFontPack: json['needsFontPack'] as bool? ?? false,
      fontPackUrl: json['fontPackUrl'] as String?,
      chinaUrl: json['chinaUrl'] as String?,
      globalUrl: json['globalUrl'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': _name,
    'category': category,
    if (_type != null) 'type': _type,
    if (version != null) 'version': version,
    if (build != null) 'build': build,
    if (architecture != null) 'architecture': architecture,
    if (_description != null) 'description': _description,
    if (_audience != null) 'audience': _audience,
    if (_pros.isNotEmpty) 'pros': _pros,
    if (_notes.isNotEmpty) 'notes': _notes,
    'downloadUrl': downloadUrl,
    if (sha256 != null) 'sha256': sha256,
    if (size != null) 'size': size,
    'needsFontPack': needsFontPack,
    if (fontPackUrl != null) 'fontPackUrl': fontPackUrl,
    if (chinaUrl != null) 'chinaUrl': chinaUrl,
    if (globalUrl != null) 'globalUrl': globalUrl,
  };
}

class MirrorCategory {
  final String id;
  final String name;
  final String icon;
  final List<MirrorItem> items;

  const MirrorCategory({
    required this.id,
    required this.name,
    required this.icon,
    required this.items,
  });
}

class MirrorListData {
  final String lastUpdate;
  final List<MirrorItem> items;

  const MirrorListData({required this.lastUpdate, required this.items});

  factory MirrorListData.fromJson(Map<String, dynamic> json) {
    final itemsJson = json['items'] as List<dynamic>? ?? [];
    return MirrorListData(
      lastUpdate: json['lastUpdate'] as String? ?? '',
      items: itemsJson
          .map((e) => MirrorItem.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  List<MirrorCategory> categories(Locale locale) {
    final map = <String, List<MirrorItem>>{};
    for (final item in items) {
      if (!item.isVisibleInLocale(locale)) continue;
      map.putIfAbsent(item.category, () => []).add(item);
    }
    return map.entries
        .map(
          (e) => MirrorCategory(
            id: e.key,
            name: _categoryName(e.key, locale),
            icon: _categoryIcon(e.key),
            items: e.value,
          ),
        )
        .toList();
  }

  static String _categoryName(String category, Locale locale) {
    final code = localeCodeFromLocale(locale);
    return switch (category) {
      'Official Microsoft' => trByCode(
        code,
        'mirror_category_official_microsoft',
      ),
      'Community Images' => trByCode(code, 'mirror_category_community'),
      _ => category,
    };
  }

  static String _categoryIcon(String category) {
    switch (category) {
      case 'Official Microsoft':
        return 'official';
      case 'Community Images':
        return 'community';
      default:
        return 'other';
    }
  }
}

class LocalIsoInfo {
  final String filePath;
  final String fileName;
  final int fileSize;

  const LocalIsoInfo({
    required this.filePath,
    required this.fileName,
    required this.fileSize,
  });

  String get displaySize {
    if (fileSize < 1024 * 1024) {
      return '${(fileSize / 1024).toStringAsFixed(0)} KB';
    }
    if (fileSize < 1024 * 1024 * 1024) {
      return '${(fileSize / (1024 * 1024)).toStringAsFixed(0)} MB';
    }
    return '${(fileSize / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }
}
