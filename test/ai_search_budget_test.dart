import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:win_deploy_studio/core/services/ai_search_budget.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await AiSearchBudget.reset();
  });

  test('allows exactly ten searches in one hour', () async {
    final now = DateTime(2026, 1, 1, 12);
    for (var i = 0; i < AiSearchBudget.maxPerWindow; i++) {
      expect(await AiSearchBudget.tryConsume(now: now), isTrue, reason: 'search $i');
    }
    expect(await AiSearchBudget.tryConsume(now: now), isFalse);
    expect(await AiSearchBudget.remaining(now: now), 0);
  });

  test('reports the remaining allowance', () async {
    final now = DateTime(2026, 1, 1, 12);
    expect(await AiSearchBudget.remaining(now: now), 10);
    await AiSearchBudget.tryConsume(now: now);
    await AiSearchBudget.tryConsume(now: now);
    expect(await AiSearchBudget.remaining(now: now), 8);
  });

  test('slots age out after the window', () async {
    final start = DateTime(2026, 1, 1, 12);
    for (var i = 0; i < AiSearchBudget.maxPerWindow; i++) {
      expect(await AiSearchBudget.tryConsume(now: start), isTrue);
    }
    expect(await AiSearchBudget.tryConsume(now: start), isFalse);

    // One minute short of an hour: still blocked.
    final almost = start.add(const Duration(minutes: 59));
    expect(await AiSearchBudget.tryConsume(now: almost), isFalse);

    // Past the window: the oldest slots have expired.
    final later = start.add(const Duration(minutes: 61));
    expect(await AiSearchBudget.tryConsume(now: later), isTrue);
  });

  test('refund releases the most recent slot', () async {
    final now = DateTime(2026, 1, 1, 12);
    for (var i = 0; i < AiSearchBudget.maxPerWindow; i++) {
      await AiSearchBudget.tryConsume(now: now);
    }
    expect(await AiSearchBudget.remaining(now: now), 0);
    await AiSearchBudget.refund(now: now);
    expect(await AiSearchBudget.remaining(now: now), 1);
    expect(await AiSearchBudget.tryConsume(now: now), isTrue);
  });

  test('refund on an empty budget is harmless', () async {
    await AiSearchBudget.refund();
    expect(await AiSearchBudget.remaining(), 10);
  });

  test('concurrent claims never exceed the allowance', () async {
    final now = DateTime(2026, 1, 1, 12);
    final results = await Future.wait(List.generate(
      25,
      (_) => AiSearchBudget.tryConsume(now: now),
    ));
    expect(results.where((allowed) => allowed).length, AiSearchBudget.maxPerWindow);
  });

  test('reset clears the stored allowance', () async {
    final now = DateTime(2026, 1, 1, 12);
    for (var i = 0; i < 4; i++) {
      await AiSearchBudget.tryConsume(now: now);
    }
    await AiSearchBudget.reset();
    expect(await AiSearchBudget.remaining(now: now), 10);
  });
}
