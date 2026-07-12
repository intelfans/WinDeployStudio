import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:win_deploy_studio/app/theme.dart';
import 'package:win_deploy_studio/core/localization/strings.dart';
import 'package:win_deploy_studio/features/tools/models/tool_models.dart';
import 'package:win_deploy_studio/features/tools/screens/tools_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'language_code': 'en',
    });
    L.currentLocale = 'en';
  });

  testWidgets('uses a compact three-by-two featured grid on desktop', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(
          const Color(0xFF0071C5),
          'HarmonyOSSans',
          style: VisualStyle.win11,
        ),
        home: ToolsScreen(dataLoader: () async => _featuredToolsData),
      ),
    );

    final featuredGrid = find.byKey(const ValueKey('tools-featured-grid'));
    for (
      var attempt = 0;
      attempt < 20 && featuredGrid.evaluate().isEmpty;
      attempt++
    ) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    expect(featuredGrid, findsOneWidget);
    final grid = tester.widget<GridView>(featuredGrid);
    final delegate =
        grid.gridDelegate as SliverGridDelegateWithFixedCrossAxisCount;
    expect(delegate.crossAxisCount, 3);

    final featuredCards = find.descendant(
      of: featuredGrid,
      matching: find.byType(Card),
    );
    expect(featuredCards, findsNWidgets(6));
    expect(tester.getSize(featuredCards.first).height, closeTo(136, 0.1));

    final positions = List<Offset>.generate(
      6,
      (index) => tester.getTopLeft(featuredCards.at(index)),
    );
    expect(
      positions.map((position) => position.dx.round()).toSet(),
      hasLength(3),
    );
    expect(
      positions.map((position) => position.dy.round()).toSet(),
      hasLength(2),
    );
  });
}

const _featuredToolsData = ToolsData(
  categories: [
    ToolCategory(
      nameKey: 'tools_cat_system',
      color: '#0071C5',
      tools: [
        ToolItem(
          name: 'Tool 1',
          desc: 'A compact featured tool description.',
          icon: 'system',
          url: 'https://example.com/1',
          featured: true,
        ),
        ToolItem(
          name: 'Tool 2',
          desc: 'A compact featured tool description.',
          icon: 'system',
          url: 'https://example.com/2',
          featured: true,
        ),
        ToolItem(
          name: 'Tool 3',
          desc: 'A compact featured tool description.',
          icon: 'system',
          url: 'https://example.com/3',
          featured: true,
        ),
        ToolItem(
          name: 'Tool 4',
          desc: 'A compact featured tool description.',
          icon: 'system',
          url: 'https://example.com/4',
          featured: true,
        ),
        ToolItem(
          name: 'Tool 5',
          desc: 'A compact featured tool description.',
          icon: 'system',
          url: 'https://example.com/5',
          featured: true,
        ),
        ToolItem(
          name: 'Tool 6',
          desc: 'A compact featured tool description.',
          icon: 'system',
          url: 'https://example.com/6',
          featured: true,
        ),
        ToolItem(
          name: 'Tool 7',
          desc: 'A compact featured tool description.',
          icon: 'system',
          url: 'https://example.com/7',
          featured: true,
        ),
        ToolItem(
          name: 'Tool 8',
          desc: 'A compact featured tool description.',
          icon: 'system',
          url: 'https://example.com/8',
          featured: true,
        ),
        ToolItem(
          name: 'Tool 9',
          desc: 'A compact featured tool description.',
          icon: 'system',
          url: 'https://example.com/9',
          featured: true,
        ),
      ],
    ),
  ],
);
