import 'dart:ui';

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

  const MirrorItem({
    required this.id,
    required Map<String, String> name,
    required this.category,
    Map<String, String>? type,
    this.version,
    this.build,
    this.architecture,
    Map<String, String>? description,
    Map<String, String>? audience,
    Map<String, List<String>> pros = const {},
    Map<String, List<String>> notes = const {},
    required this.downloadUrl,
    this.sha256,
    this.size,
    this.needsFontPack = false,
    this.fontPackUrl,
    this.chinaUrl,
    this.globalUrl,
  })  : _name = name,
        _type = type,
        _description = description,
        _audience = audience,
        _pros = pros,
        _notes = notes;

  String _localize(Map<String, String>? map, Locale locale) {
    if (map == null) return '';
    return map[locale.languageCode] ?? map['en'] ?? map['zh'] ?? '';
  }

  List<String> _localizeList(Map<String, List<String>>? map, Locale locale) {
    if (map == null) return [];
    return map[locale.languageCode] ?? map['en'] ?? map['zh'] ?? [];
  }

  String getName(Locale locale) => _localize(_name, locale);
  String getType(Locale locale) => _localize(_type, locale);
  String getDescription(Locale locale) => _localize(_description, locale);
  String getAudience(Locale locale) => _localize(_audience, locale);
  List<String> getPros(Locale locale) => _localizeList(_pros, locale);
  List<String> getNotes(Locale locale) => _localizeList(_notes, locale);

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
        return value.map((k, v) => MapEntry(
            k.toString(), (v as List).map((e) => e.toString()).toList()));
      }
      return null;
    }

    return MirrorItem(
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
  final String name;
  final String icon;
  final List<MirrorItem> items;

  const MirrorCategory({
    required this.name,
    required this.icon,
    required this.items,
  });
}

class MirrorListData {
  final String lastUpdate;
  final List<MirrorItem> items;

  const MirrorListData({
    required this.lastUpdate,
    required this.items,
  });

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
      map.putIfAbsent(item.category, () => []).add(item);
    }
    return map.entries
        .map((e) => MirrorCategory(
              name: _categoryName(e.key, locale),
              icon: _categoryIcon(e.key),
              items: e.value,
            ))
        .toList();
  }

  static String _categoryName(String category, Locale locale) {
    final code = locale.languageCode;
    switch (category) {
      case 'Official Original':
        return switch (code) {
          'zh' => '官方原版',
          'ru' => 'Официальные',
          'fr' => 'Officiel',
          'ja' => '公式',
          _ => 'Official',
        };
      case 'Official LTSC':
        return 'LTSC';
      case 'TinyOS':
        return 'TinyOS';
      case 'X-Lite':
        return 'X-Lite';
      case 'Custom':
        return switch (code) {
          'zh' => '美化版',
          'ru' => 'Пользовательские',
          'fr' => 'Personnalisé',
          'ja' => 'カスタム',
          _ => 'Custom',
        };
      case 'Tools':
        return switch (code) {
          'zh' => '工具',
          'ru' => 'Инструменты',
          'fr' => 'Outils',
          'ja' => 'ツール',
          _ => 'Tools',
        };
      default:
        return switch (code) {
          'zh' => '其他',
          'ru' => 'Другие',
          'fr' => 'Autre',
          'ja' => 'その他',
          _ => 'Other',
        };
    }
  }

  static String _categoryIcon(String category) {
    switch (category) {
      case 'Official Original':
      case 'Official LTSC':
      case 'Official Insider':
        return 'official';
      case 'TinyOS':
        return 'tiny';
      case 'X-Lite':
        return 'xlite';
      case 'Custom':
        return 'custom';
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
