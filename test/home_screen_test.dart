import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:win_deploy_studio/app/theme.dart';
import 'package:win_deploy_studio/core/localization/strings.dart';
import 'package:win_deploy_studio/features/home/home_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'language_code': 'en',
      'update_auto_check': false,
    });
    L.currentLocale = 'en';
  });

  testWidgets(
    'uses an ordered three-column quick-start layout in a desktop content pane',
    (tester) async {
      // This is the usable home width after an expanded navigation pane has
      // claimed its space in a normally sized desktop window.
      await tester.binding.setSurfaceSize(const Size(884, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: AppTheme.light(
              const Color(0xFF0071C5),
              'HarmonyOSSans',
              style: VisualStyle.win11,
            ),
            home: const HomeScreen(),
          ),
        ),
      );
      await tester.pump();

      expect(find.text(trCurrent('home_quick_start')), findsOneWidget);
      expect(find.text(trCurrent('home_about')), findsOneWidget);
      expect(find.text(trCurrent('home_bootable_usb')), findsOneWidget);
      expect(find.text(trCurrent('home_wtg')), findsOneWidget);
      expect(find.text(trCurrent('home_image_library')), findsOneWidget);
      expect(find.byIcon(Icons.refresh_rounded), findsNothing);
      expect(find.byIcon(Icons.arrow_forward_rounded), findsNothing);

      final imageCard = find.byKey(
        const ValueKey('home-quick-action-image-library'),
      );
      final installMediaCard = find.byKey(
        const ValueKey('home-quick-action-install-media'),
      );
      final toGoCard = find.byKey(const ValueKey('home-quick-action-to-go'));
      final imagePosition = tester.getTopLeft(imageCard);
      final installMediaPosition = tester.getTopLeft(installMediaCard);
      final toGoPosition = tester.getTopLeft(toGoCard);

      expect(imagePosition.dx, lessThan(installMediaPosition.dx));
      expect(installMediaPosition.dx, lessThan(toGoPosition.dx));
      expect(imagePosition.dy, closeTo(installMediaPosition.dy, 0.1));
      expect(installMediaPosition.dy, closeTo(toGoPosition.dy, 0.1));
      expect(tester.getSize(imageCard).height, lessThanOrEqualTo(120));
    },
  );

  testWidgets('stacks quick actions only in a genuinely narrow content pane', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(460, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: AppTheme.light(
            const Color(0xFF0071C5),
            'HarmonyOSSans',
            style: VisualStyle.win11,
          ),
          home: const HomeScreen(),
        ),
      ),
    );
    await tester.pump();

    final imagePosition = tester.getTopLeft(
      find.byKey(const ValueKey('home-quick-action-image-library')),
    );
    final installMediaPosition = tester.getTopLeft(
      find.byKey(const ValueKey('home-quick-action-install-media')),
    );
    final toGoPosition = tester.getTopLeft(
      find.byKey(const ValueKey('home-quick-action-to-go')),
    );

    expect(imagePosition.dy, lessThan(installMediaPosition.dy));
    expect(installMediaPosition.dy, lessThan(toGoPosition.dy));
  });
}
