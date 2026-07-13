import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:win_deploy_studio/features/mirror/services/recent_mirrors_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test('keeps the three newest unique mirrors in recency order', () async {
    const service = RecentMirrorsService();
    final base = DateTime(2026, 7, 13, 9);

    await service.recordMirror('official-win11', openedAt: base);
    await service.recordMirror(
      'official-win10',
      openedAt: base.add(const Duration(minutes: 1)),
    );
    await service.recordMirror(
      'tiny11',
      openedAt: base.add(const Duration(minutes: 2)),
    );
    await service.recordMirror(
      'official-win11',
      openedAt: base.add(const Duration(minutes: 3)),
    );
    await service.recordMirror(
      'tiny10',
      openedAt: base.add(const Duration(minutes: 4)),
    );

    final entries = await service.load();

    expect(entries.map((entry) => entry.mirrorId), [
      'tiny10',
      'official-win11',
      'tiny11',
    ]);
    expect(entries.first.lastOpenedAt, base.add(const Duration(minutes: 4)));
  });

  test(
    'ignores malformed persisted records without failing the list',
    () async {
      final validTimestamp = DateTime(2026, 7, 13, 10).millisecondsSinceEpoch;
      SharedPreferences.setMockInitialValues(<String, Object>{
        RecentMirrorsService.preferenceKey: jsonEncode([
          {'mirrorId': 'official-win11', 'lastOpenedAt': validTimestamp},
          {'mirrorId': '', 'lastOpenedAt': validTimestamp},
          {'mirrorId': 'bad-time', 'lastOpenedAt': 'never'},
          'not a map',
        ]),
      });

      const service = RecentMirrorsService();
      final entries = await service.load();

      expect(entries, hasLength(1));
      expect(entries.single.mirrorId, 'official-win11');
    },
  );

  test('clears the persisted recent mirror list', () async {
    const service = RecentMirrorsService();
    await service.recordMirror('official-win11');
    await service.clear();

    expect(await service.load(), isEmpty);
  });
}
