import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:win_deploy_studio/app/theme.dart';
import 'package:win_deploy_studio/core/localization/ai_benchmark_strings.dart';
import 'package:win_deploy_studio/core/localization/strings.dart';
import 'package:win_deploy_studio/features/ai_assistant/screens/ai_assistant_screen.dart';
import 'package:win_deploy_studio/features/benchmark/models/benchmark_models.dart';
import 'package:win_deploy_studio/features/benchmark_history/models/benchmark_history_models.dart';
import 'package:win_deploy_studio/features/benchmark_history/services/benchmark_history_service.dart';

import 'benchmark_test_fixtures.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'language_code': 'en',
      'ai_assistant_notice_hidden': true,
    });
    L.currentLocale = 'en';
  });

  testWidgets('USB analysis lets the user select multiple saved test records', (
    tester,
  ) async {
    final service = _FixedHistoryService([
      benchmarkTestRecord(
        benchmarkTestResult(model: 'First USB'),
        id: 'first-record',
      ),
      benchmarkTestRecord(
        benchmarkTestResult(model: 'Second USB'),
        id: 'second-record',
      ),
    ]);

    await _pumpAssistant(tester, service);
    await tester.tap(find.text(trCurrent('ai_action_analyze_usb')));
    await _pumpDialog(tester);

    expect(find.text(trCurrent(AiBenchmarkKeys.recordsTitle)), findsOneWidget);
    final checkboxes = find.byType(Checkbox);
    expect(checkboxes, findsNWidgets(2));
    await tester.tap(checkboxes.at(0));
    await tester.pump();
    await tester.tap(checkboxes.at(1));
    await tester.pump();
    expect(find.text('2 selected'), findsOneWidget);

    await tester.tap(find.text(trCurrent(AiBenchmarkKeys.recordsSend)));
    await _pumpDialog(tester);
    expect(find.text(trCurrent('ai_privacy_title')), findsOneWidget);
    final privacyDialog = find.ancestor(
      of: find.text(trCurrent('ai_privacy_title')),
      matching: find.byType(AlertDialog),
    );
    await tester.tap(
      find.descendant(
        of: privacyDialog,
        matching: find.text(trCurrent('detail_cancel')),
      ),
    );
    await _pumpDialog(tester);
  });

  testWidgets(
    'USB analysis recommends Standard testing when history is empty',
    (tester) async {
      final service = _FixedHistoryService(const []);

      await _pumpAssistant(tester, service);
      await tester.tap(find.text(trCurrent('ai_action_analyze_usb')));
      await _pumpDialog(tester);

      expect(
        find.text(trCurrent(AiBenchmarkKeys.recordsNoneTitle)),
        findsOneWidget,
      );
      expect(
        find.text(trCurrent(AiBenchmarkKeys.recordsRunStandard)),
        findsOneWidget,
      );
      await tester.tap(find.text(trCurrent('detail_cancel')));
      await _pumpDialog(tester);
    },
  );
}

Future<void> _pumpAssistant(
  WidgetTester tester,
  BenchmarkHistoryService service,
) async {
  await tester.binding.setSurfaceSize(const Size(1000, 800));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    ProviderScope(
      overrides: [benchmarkHistoryServiceProvider.overrideWithValue(service)],
      child: MaterialApp(
        theme: AppTheme.light(
          const Color(0xFF0071C5),
          'HarmonyOSSans',
          style: VisualStyle.win11,
        ),
        home: const AiAssistantScreen(),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
}

Future<void> _pumpDialog(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
}

class _FixedHistoryService extends BenchmarkHistoryService {
  _FixedHistoryService(this.records);

  final List<BenchmarkHistoryRecord> records;

  @override
  Future<List<BenchmarkHistoryRecord>> list({
    DateTime? from,
    DateTime? to,
    BenchmarkDeviceIdentity? device,
    String? model,
    String? serialNumber,
    String? vid,
    String? pid,
  }) async {
    return records;
  }
}
