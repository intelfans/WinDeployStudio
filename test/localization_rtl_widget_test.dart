import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:win_deploy_studio/app/app.dart';
import 'package:win_deploy_studio/app/localization.dart';
import 'package:win_deploy_studio/core/localization/strings.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('first language selection previews Arabic as RTL immediately', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    L.currentLocale = 'en';

    await tester.pumpWidget(
      const ProviderScope(child: MaterialApp(home: LanguageSelectPage())),
    );

    final arabicOption = find.text('العربية');
    expect(arabicOption, findsOneWidget);
    expect(Directionality.of(tester.element(arabicOption)), TextDirection.ltr);

    await tester.ensureVisible(arabicOption);
    await tester.pump();
    await tester.tap(arabicOption);
    await tester.pump();

    expect(Directionality.of(tester.element(arabicOption)), TextDirection.rtl);
    expect(textDirectionForLocale(const Locale('ar')), TextDirection.rtl);
    expect(textDirectionForLocale(const Locale('zh')), TextDirection.ltr);
  });
}
