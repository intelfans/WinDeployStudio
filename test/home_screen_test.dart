import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:win_deploy_studio/app/theme.dart';
import 'package:win_deploy_studio/core/localization/strings.dart';
import 'package:win_deploy_studio/features/home/home_screen.dart';
import 'package:win_deploy_studio/features/home/models/home_storage_overview.dart';
import 'package:win_deploy_studio/features/home/providers/home_storage_overview_provider.dart';
import 'package:win_deploy_studio/features/mirror/models/mirror_models.dart';
import 'package:win_deploy_studio/features/mirror/providers/mirror_provider.dart';
import 'package:win_deploy_studio/features/mirror/providers/recent_mirrors_provider.dart';
import 'package:win_deploy_studio/features/mirror/services/recent_mirrors_service.dart';

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
          overrides: [
            homeStorageOverviewProvider.overrideWith(
              (ref) async => const HomeStorageOverview.empty(),
            ),
          ],
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
        overrides: [
          homeStorageOverviewProvider.overrideWith(
            (ref) async => const HomeStorageOverview.empty(),
          ),
        ],
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

  testWidgets(
    'shows resolved recent images and the connected storage summary',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1000, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final mirrors = <MirrorItem>[
        _testMirror('test-win11', 'Test Windows 11'),
        _testMirror('test-win10', 'Test Windows 10'),
        _testMirror('test-server', 'Test Windows Server'),
      ];

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            mirrorProvider.overrideWith(
              (ref) => _LoadedMirrorNotifier(
                MirrorListData(lastUpdate: '', items: mirrors),
              ),
            ),
            recentMirrorEntriesProvider.overrideWith(
              (ref) async => <RecentMirrorEntry>[
                for (var index = 0; index < mirrors.length; index++)
                  RecentMirrorEntry(
                    mirrorId: mirrors[index].id,
                    lastOpenedAt: DateTime(2026, 7, 13, index),
                  ),
              ],
            ),
            homeStorageOverviewProvider.overrideWith(
              (ref) async => const HomeStorageOverview(
                devices: [
                  HomeStorageDeviceOverview(
                    diskNumber: 1,
                    name: 'Portable SSD',
                    capacityBytes: 1_000_204_886_016,
                    capacityLabel: '931 GB',
                    busType: 'USB',
                    driveLetters: ['E'],
                    isAvailable: true,
                  ),
                  HomeStorageDeviceOverview(
                    diskNumber: 4,
                    name: 'USB Flash Disk',
                    capacityBytes: 64_000_000_000,
                    capacityLabel: '59.6 GB',
                    busType: 'USB',
                    driveLetters: ['F'],
                    isAvailable: true,
                  ),
                ],
              ),
            ),
          ],
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
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('home-recent-images-panel')),
        findsOneWidget,
      );
      expect(find.text('Test Windows 11'), findsOneWidget);
      expect(find.text('Test Windows 10'), findsOneWidget);
      expect(find.text('Test Windows Server'), findsOneWidget);
      expect(find.text('Windows · 24H2'), findsNWidgets(3));
      expect(
        tester.getBottomRight(find.text('Test Windows Server')).dy,
        lessThanOrEqualTo(
          tester
              .getBottomRight(
                find.byKey(const ValueKey('home-recent-images-panel')),
              )
              .dy,
        ),
      );
      expect(
        find.byKey(const ValueKey('home-storage-overview-panel')),
        findsOneWidget,
      );
      final recentPanelPosition = tester.getTopLeft(
        find.byKey(const ValueKey('home-recent-images-panel')),
      );
      final storagePanelPosition = tester.getTopLeft(
        find.byKey(const ValueKey('home-storage-overview-panel')),
      );
      expect(recentPanelPosition.dx, lessThan(storagePanelPosition.dx));
      expect(recentPanelPosition.dy, closeTo(storagePanelPosition.dy, 0.1));
      expect(find.text('Portable SSD'), findsOneWidget);
      expect(find.text('931 GB · USB · E'), findsOneWidget);
      expect(find.text('USB Flash Disk'), findsOneWidget);
      expect(find.text('59.6 GB · USB · F'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('home-storage-device-1')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('home-storage-device-4')),
        findsOneWidget,
      );
      expect(
        tester.getBottomRight(find.text('USB Flash Disk')).dy,
        lessThanOrEqualTo(
          tester
              .getBottomRight(
                find.byKey(const ValueKey('home-storage-overview-panel')),
              )
              .dy,
        ),
      );
      expect(
        find.text(trCurrent('home_storage_devices').replaceAll('{count}', '2')),
        findsOneWidget,
      );
    },
  );

  testWidgets('keeps recent images scrollable inside its fixed-height panel', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1000, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final mirrors = <MirrorItem>[
      _testMirror('recent-1', 'Recent image 1'),
      _testMirror('recent-2', 'Recent image 2'),
      _testMirror('recent-3', 'Recent image 3'),
      _testMirror('recent-4', 'Recent image 4'),
    ];

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          mirrorProvider.overrideWith(
            (ref) => _LoadedMirrorNotifier(
              MirrorListData(lastUpdate: '', items: mirrors),
            ),
          ),
          recentMirrorEntriesProvider.overrideWith(
            (ref) async => <RecentMirrorEntry>[
              for (var index = 0; index < mirrors.length; index++)
                RecentMirrorEntry(
                  mirrorId: mirrors[index].id,
                  lastOpenedAt: DateTime(2026, 7, 13, index),
                ),
            ],
          ),
          homeStorageOverviewProvider.overrideWith(
            (ref) async => const HomeStorageOverview.empty(),
          ),
        ],
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
    await tester.pumpAndSettle();

    final listFinder = find.byKey(const ValueKey('home-recent-images-list'));
    final scrollbarFinder = find.byKey(
      const ValueKey('home-recent-images-scrollbar'),
    );
    final scrollableFinder = find.descendant(
      of: listFinder,
      matching: find.byType(Scrollable),
    );
    final list = tester.widget<ListView>(listFinder);
    final scrollbar = tester.widget<Scrollbar>(scrollbarFinder);
    final scrollable = tester.state<ScrollableState>(scrollableFinder);

    expect(list.controller, isNotNull);
    expect(list.primary, isFalse);
    expect(list.physics, isA<ClampingScrollPhysics>());
    expect(scrollbar.controller, same(list.controller));
    expect(scrollbar.thumbVisibility, isTrue);
    expect(scrollbar.interactive, isTrue);
    expect(scrollable.position.maxScrollExtent, greaterThan(0));

    await tester.drag(listFinder, const Offset(0, -240));
    await tester.pumpAndSettle();

    expect(scrollable.position.pixels, greaterThan(0));
    expect(
      tester.getBottomRight(find.text('Recent image 4')).dy,
      lessThanOrEqualTo(tester.getBottomRight(listFinder).dy),
    );
  });

  testWidgets('scrolls storage devices when the compact panel overflows', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1000, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          homeStorageOverviewProvider.overrideWith(
            (ref) async => const HomeStorageOverview(
              devices: [
                HomeStorageDeviceOverview(
                  diskNumber: 1,
                  name: 'USB device 1',
                  capacityBytes: 64_000_000_000,
                  capacityLabel: '59.6 GB',
                  busType: 'USB',
                  driveLetters: ['E'],
                  isAvailable: true,
                ),
                HomeStorageDeviceOverview(
                  diskNumber: 2,
                  name: 'USB device 2',
                  capacityBytes: 64_000_000_000,
                  capacityLabel: '59.6 GB',
                  busType: 'USB',
                  driveLetters: ['F'],
                  isAvailable: true,
                ),
                HomeStorageDeviceOverview(
                  diskNumber: 3,
                  name: 'USB device 3',
                  capacityBytes: 64_000_000_000,
                  capacityLabel: '59.6 GB',
                  busType: 'USB',
                  driveLetters: ['G'],
                  isAvailable: true,
                ),
                HomeStorageDeviceOverview(
                  diskNumber: 4,
                  name: 'USB device 4',
                  capacityBytes: 64_000_000_000,
                  capacityLabel: '59.6 GB',
                  busType: 'USB',
                  driveLetters: ['H'],
                  isAvailable: true,
                ),
              ],
            ),
          ),
        ],
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
    await tester.pumpAndSettle();

    final list = find.byKey(const ValueKey('home-storage-devices-list'));
    final scrollable = tester.state<ScrollableState>(
      find.descendant(of: list, matching: find.byType(Scrollable)),
    );

    await tester.drag(list, const Offset(0, -100));
    await tester.pumpAndSettle();

    expect(scrollable.position.pixels, greaterThan(0));
    expect(find.text('USB device 4'), findsOneWidget);
    expect(
      tester.getBottomRight(find.text('USB device 4')).dy,
      lessThanOrEqualTo(
        tester
            .getBottomRight(
              find.byKey(const ValueKey('home-storage-overview-panel')),
            )
            .dy,
      ),
    );
  });

  testWidgets('clears recent images from the workspace header', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final mirror = _testMirror('test-win11', 'Test Windows 11');
    await const RecentMirrorsService().recordMirror(mirror.id);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          mirrorProvider.overrideWith(
            (ref) => _LoadedMirrorNotifier(
              MirrorListData(lastUpdate: '', items: [mirror]),
            ),
          ),
          homeStorageOverviewProvider.overrideWith(
            (ref) async => const HomeStorageOverview.empty(),
          ),
        ],
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
    await tester.pumpAndSettle();

    final clearButton = find.byKey(const ValueKey('home-clear-recent-images'));
    expect(clearButton, findsOneWidget);
    expect(
      find.byTooltip(trCurrent('home_recent_images_clear')),
      findsOneWidget,
    );
    expect(find.text('Test Windows 11'), findsOneWidget);

    await tester.tap(clearButton);
    await tester.pumpAndSettle();

    expect(await const RecentMirrorsService().load(), isEmpty);
    expect(find.text('Test Windows 11'), findsNothing);
    expect(find.text(trCurrent('home_recent_images_empty')), findsOneWidget);
    expect(tester.widget<IconButton>(clearButton).onPressed, isNull);
  });

  testWidgets('home editor hides workspace modules immediately', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1000, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          homeStorageOverviewProvider.overrideWith(
            (ref) async => const HomeStorageOverview.empty(),
          ),
        ],
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
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('home-recent-images-panel')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('home-storage-overview-panel')),
      findsOneWidget,
    );

    await tester.tap(find.byIcon(Icons.tune_rounded));
    await tester.pumpAndSettle();
    expect(
      tester.getSize(find.byKey(const ValueKey('home-editor-sheet'))).height,
      greaterThanOrEqualTo(400),
    );
    await tester.tap(
      find.byKey(const ValueKey('home-editor-module-recentImages-switch')),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('home-recent-images-panel')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('home-storage-overview-panel')),
      findsOneWidget,
    );
  });
}

class _LoadedMirrorNotifier extends MirrorNotifier {
  _LoadedMirrorNotifier(MirrorListData data) {
    state = MirrorState(status: MirrorLoadStatus.loaded, data: data);
  }
  @override
  Future<void> loadBuiltInMirrors({bool force = false}) async {}
}

MirrorItem _testMirror(String id, String name) {
  return MirrorItem.fromJson(<String, dynamic>{
    'id': id,
    'name': <String, String>{'en': name},
    'category': 'Official Microsoft Images',
    'type': <String, String>{'en': 'Windows'},
    'version': '24H2',
    'downloadUrl': 'https://example.invalid/$id',
  });
}
