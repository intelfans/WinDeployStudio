import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// A persisted reference to an image opened from the image library.
///
/// Only the stable image ID is saved. Callers resolve it against the current
/// built-in image list so names remain localized and removed entries disappear
/// naturally.
class RecentMirrorEntry {
  final String mirrorId;
  final DateTime lastOpenedAt;

  const RecentMirrorEntry({required this.mirrorId, required this.lastOpenedAt});

  factory RecentMirrorEntry.fromJson(Map<String, dynamic> json) {
    final mirrorId = json['mirrorId'];
    final lastOpenedAt = json['lastOpenedAt'];
    if (mirrorId is! String || mirrorId.trim().isEmpty) {
      throw const FormatException('Recent mirror entry is missing an ID.');
    }
    if (lastOpenedAt is! int) {
      throw const FormatException(
        'Recent mirror entry is missing a timestamp.',
      );
    }

    return RecentMirrorEntry(
      mirrorId: mirrorId,
      lastOpenedAt: DateTime.fromMillisecondsSinceEpoch(lastOpenedAt),
    );
  }

  Map<String, dynamic> toJson() => {
    'mirrorId': mirrorId,
    'lastOpenedAt': lastOpenedAt.millisecondsSinceEpoch,
  };
}

/// Stores the small, ordered list of images a user opened most recently.
class RecentMirrorsService {
  static const preferenceKey = 'recent_mirrors_v1';
  static const maxEntries = 3;

  const RecentMirrorsService();

  Future<List<RecentMirrorEntry>> load() async {
    final preferences = await SharedPreferences.getInstance();
    final serialized = preferences.getString(preferenceKey);
    if (serialized == null || serialized.isEmpty) return const [];

    try {
      final decoded = jsonDecode(serialized);
      if (decoded is! List) return const [];

      final entries = <RecentMirrorEntry>[];
      for (final value in decoded) {
        if (value is! Map) continue;
        try {
          entries.add(
            RecentMirrorEntry.fromJson(Map<String, dynamic>.from(value)),
          );
        } on FormatException {
          // Old or malformed entries should not prevent the homepage loading.
        }
      }

      entries.sort((a, b) => b.lastOpenedAt.compareTo(a.lastOpenedAt));
      final uniqueIds = <String>{};
      return entries
          .where((entry) => uniqueIds.add(entry.mirrorId))
          .take(maxEntries)
          .toList(growable: false);
    } on FormatException {
      return const [];
    }
  }

  Future<void> recordMirror(String mirrorId, {DateTime? openedAt}) async {
    final normalizedId = mirrorId.trim();
    if (normalizedId.isEmpty) return;

    final entry = RecentMirrorEntry(
      mirrorId: normalizedId,
      lastOpenedAt: openedAt ?? DateTime.now(),
    );
    final current = await load();
    final updated = <RecentMirrorEntry>[
      entry,
      ...current.where((item) => item.mirrorId != normalizedId),
    ].take(maxEntries).toList(growable: false);

    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(
      preferenceKey,
      jsonEncode(updated.map((item) => item.toJson()).toList()),
    );
  }

  Future<void> clear() async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.remove(preferenceKey);
  }
}
