import 'dart:ui';

import '../../../core/localization/strings.dart';

enum MirrorSkillLevel { beginner, advanced, expert }

extension MirrorSkillLevelLabel on MirrorSkillLevel {
  String get labelKey {
    return switch (this) {
      MirrorSkillLevel.beginner => 'tool_safety_beginner',
      MirrorSkillLevel.advanced => 'tool_safety_advanced',
      MirrorSkillLevel.expert => 'tool_safety_expert',
    };
  }

  String get tooltipKey {
    return switch (this) {
      MirrorSkillLevel.beginner => 'mirror_skill_beginner_tip',
      MirrorSkillLevel.advanced => 'mirror_skill_advanced_tip',
      MirrorSkillLevel.expert => 'mirror_skill_expert_tip',
    };
  }
}

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
  final Map<String, String>? _size;
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
    this._size,
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

  String? getSize(Locale locale) {
    final sizes = _size;
    if (sizes == null || sizes.isEmpty) return null;

    final code = _localeCode(locale);
    return sizes[code] ??
        sizes[locale.languageCode] ??
        sizes['en'] ??
        sizes['zh'] ??
        sizes.values.first;
  }

  String downloadUrlFor(Locale locale) {
    if (!isOfficialMicrosoftImage) return downloadUrl;
    return locale.languageCode == 'zh'
        ? chinaUrl ?? downloadUrl
        : globalUrl ?? downloadUrl;
  }

  bool get isOfficialMicrosoftImage =>
      category == 'Official Microsoft Images' ||
      category == 'Official Microsoft';
  bool get isOfficialMicrosoft => isOfficialMicrosoftImage;
  bool get isCommunityEdition =>
      category == 'Community Editions' || category == 'Community Images';
  bool get isCommunityImage => isCommunityEdition;
  bool get isEnterpriseLtsc => category == 'Enterprise & LTSC Builds';
  bool get isFontPack => id == 'font-pack';
  bool get isImageCenterItem =>
      isOfficialMicrosoftImage ||
      isCommunityEdition ||
      isEnterpriseLtsc ||
      isFontPack;
  bool get isStarValleyX => id == 'starvalleyx';
  bool get isChineseOnlyResource => isStarValleyX || isFontPack;
  bool get hasChinaMirror => chinaUrl?.trim().isNotEmpty ?? false;
  bool get hasGlobalMirror => globalUrl?.trim().isNotEmpty ?? false;
  bool get requiresFontPack => needsFontPack && !isStarValleyX;
  bool get isIotLtsc => id.contains('iot');

  MirrorSkillLevel get skillLevel {
    if (isOfficialMicrosoftImage || isFontPack) {
      return MirrorSkillLevel.beginner;
    }
    if (isEnterpriseLtsc) return MirrorSkillLevel.expert;
    return MirrorSkillLevel.advanced;
  }

  String get categoryLogName {
    if (isOfficialMicrosoftImage) return 'Official Microsoft Images';
    if (isEnterpriseLtsc) return 'LTSC';
    if (isCommunityEdition) return 'Community';
    return category;
  }

  String get productLogName {
    return switch (id) {
      'official-win11' => 'Windows11',
      'official-win10' => 'Windows10',
      'tiny11' => 'Tiny11',
      'tiny10' => 'Tiny10',
      'xlite11' => 'WindowsXLite11',
      'xlite10' => 'WindowsXLite10',
      'starvalleyx' => 'StarValleyX',
      'ltsc-win10-enterprise' => 'Windows10 Enterprise LTSC',
      'ltsc-win11-enterprise' => 'Windows11 Enterprise LTSC',
      'ltsc-win10-iot' => 'Windows10 IoT LTSC',
      'ltsc-win11-iot' => 'Windows11 IoT LTSC',
      _ => id,
    };
  }

  bool isVisibleInLocale(Locale locale) {
    if (!isImageCenterItem) return false;
    if (!isChineseOnlyResource) return true;
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
      size: parseStringMap(json['size']),
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
    if (_size != null) 'size': _size,
    'needsFontPack': needsFontPack,
    if (fontPackUrl != null) 'fontPackUrl': fontPackUrl,
    if (chinaUrl != null) 'chinaUrl': chinaUrl,
    if (globalUrl != null) 'globalUrl': globalUrl,
  };
}

/// A local ISO whose published checksums are known to the image library.
///
/// `visibleLocales` controls where an entry may be recognized. This keeps
/// locale-specific downloads such as the Chinese Enterprise images from being
/// identified in locales where their digest is not applicable.
class KnownImage {
  final String id;
  final Map<String, String> name;
  final String sha256;
  final String md5;
  final Set<String>? visibleLocales;

  const KnownImage._({
    required this.id,
    required this.name,
    required this.sha256,
    required this.md5,
    this.visibleLocales,
  });

  String getName(Locale locale) {
    final code = normalizeLocaleCode(localeCodeFromLocale(locale));
    return name[code] ??
        name[locale.languageCode] ??
        name['en'] ??
        name['zh'] ??
        id;
  }

  bool isVisibleInLocale(Locale locale) {
    final allowedLocales = visibleLocales;
    if (allowedLocales == null) return true;

    final code = normalizeLocaleCode(localeCodeFromLocale(locale));
    return allowedLocales.contains(code) ||
        (code.contains('_') && allowedLocales.contains(locale.languageCode));
  }

  bool matches({required String sha256, required String md5}) {
    final normalizedSha256 = this.sha256.trim().toLowerCase();
    final normalizedMd5 = this.md5.trim().toLowerCase();
    return (normalizedSha256.isNotEmpty &&
            normalizedSha256 == sha256.trim().toLowerCase()) ||
        (normalizedMd5.isNotEmpty && normalizedMd5 == md5.trim().toLowerCase());
  }

  factory KnownImage.fromJson(Map<String, dynamic> json) {
    final rawName = json['name'];
    final name = rawName is String
        ? <String, String>{'zh': rawName, 'en': rawName}
        : rawName is Map
        ? rawName.map(
            (key, value) => MapEntry(key.toString(), value.toString()),
          )
        : <String, String>{};
    final rawVisibleLocales = json['visibleLocales'];
    final visibleLocales = rawVisibleLocales is List
        ? rawVisibleLocales
              .map((value) => normalizeLocaleCode(value.toString()))
              .toSet()
        : null;

    return KnownImage._(
      id: json['id'] as String? ?? '',
      name: name,
      sha256: json['sha256'] as String? ?? '',
      md5: json['md5'] as String? ?? '',
      visibleLocales: visibleLocales,
    );
  }
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
  final List<KnownImage> knownImages;

  const MirrorListData({
    required this.lastUpdate,
    required this.items,
    this.knownImages = const [],
  });

  factory MirrorListData.fromJson(Map<String, dynamic> json) {
    final itemsJson = json['items'] as List<dynamic>? ?? [];
    final knownImagesJson = json['knownImages'] as List<dynamic>? ?? [];
    return MirrorListData(
      lastUpdate: json['lastUpdate'] as String? ?? '',
      items: itemsJson
          .map((e) => MirrorItem.fromJson(e as Map<String, dynamic>))
          .toList(),
      knownImages: knownImagesJson
          .whereType<Map>()
          .map((entry) => KnownImage.fromJson(Map<String, dynamic>.from(entry)))
          .where((entry) => entry.id.isNotEmpty)
          .toList(),
    );
  }

  List<KnownImage> knownImagesForLocale(Locale locale) => knownImages
      .where((entry) => entry.isVisibleInLocale(locale))
      .toList(growable: false);

  List<MirrorCategory> categories(Locale locale) {
    final map = <String, List<MirrorItem>>{};
    for (final item in items) {
      if (!item.isVisibleInLocale(locale)) continue;
      map.putIfAbsent(item.category, () => []).add(item);
    }

    const order = [
      'Official Microsoft Images',
      'Official Microsoft',
      'Community Editions',
      'Community Images',
      'Enterprise & LTSC Builds',
      'Tools',
    ];

    final categories = <MirrorCategory>[];
    final seen = <String>{};
    for (final id in order) {
      final list = map[id];
      if (list == null || seen.contains(id)) continue;
      seen.add(id);
      categories.add(
        MirrorCategory(
          id: id,
          name: _categoryName(id, locale),
          icon: _categoryIcon(id),
          items: list,
        ),
      );
    }

    for (final entry in map.entries) {
      if (seen.contains(entry.key)) continue;
      categories.add(
        MirrorCategory(
          id: entry.key,
          name: _categoryName(entry.key, locale),
          icon: _categoryIcon(entry.key),
          items: entry.value,
        ),
      );
    }

    return categories;
  }

  static String _categoryName(String category, Locale locale) {
    final code = localeCodeFromLocale(locale);
    return switch (category) {
      'Official Microsoft Images' => trByCode(
        code,
        'mirror_category_official_microsoft',
      ),
      'Official Microsoft' => trByCode(
        code,
        'mirror_category_official_microsoft',
      ),
      'Community Editions' => trByCode(code, 'mirror_category_community'),
      'Community Images' => trByCode(code, 'mirror_category_community'),
      'Enterprise & LTSC Builds' => trByCode(code, 'mirror_category_ltsc'),
      'Tools' => trByCode(code, 'tools_title'),
      _ => category,
    };
  }

  static String _categoryIcon(String category) {
    switch (category) {
      case 'Official Microsoft Images':
      case 'Official Microsoft':
        return 'official';
      case 'Community Editions':
      case 'Community Images':
        return 'community';
      case 'Enterprise & LTSC Builds':
        return 'ltsc';
      case 'Tools':
        return 'tools';
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
