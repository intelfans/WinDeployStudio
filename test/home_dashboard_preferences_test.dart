import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:win_deploy_studio/features/home/providers/home_dashboard_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('HomeDashboardPreferences', () {
    test('uses a complete, visible default dashboard', () {
      final preferences = HomeDashboardPreferences.defaults;

      expect(preferences.quickActionOrder, HomeQuickAction.values);
      expect(preferences.visibleQuickActions, HomeQuickAction.values);
      expect(
        preferences.isModuleVisible(HomeDashboardModule.recentImages),
        isTrue,
      );
      expect(
        preferences.isModuleVisible(HomeDashboardModule.storageOverview),
        isTrue,
      );
    });

    test('normalizes partial and obsolete persisted values', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        HomeDashboardPreferences.quickActionOrderPreferenceKey: <String>[
          HomeQuickAction.toGo.name,
          'removed_action',
          HomeQuickAction.imageLibrary.name,
          HomeQuickAction.toGo.name,
        ],
        HomeDashboardPreferences.hiddenQuickActionsPreferenceKey: <String>[
          HomeQuickAction.installMedia.name,
          'removed_action',
        ],
        HomeDashboardPreferences.hiddenModulesPreferenceKey: <String>[
          HomeDashboardModule.storageOverview.name,
          'removed_module',
        ],
      });

      final storage = await SharedPreferences.getInstance();
      final preferences = HomeDashboardPreferences.fromPreferences(storage);

      expect(preferences.isLoaded, isTrue);
      expect(preferences.quickActionOrder, <HomeQuickAction>[
        HomeQuickAction.toGo,
        HomeQuickAction.imageLibrary,
        HomeQuickAction.installMedia,
      ]);
      expect(preferences.visibleQuickActions, <HomeQuickAction>[
        HomeQuickAction.toGo,
        HomeQuickAction.imageLibrary,
      ]);
      expect(
        preferences.isModuleVisible(HomeDashboardModule.storageOverview),
        isFalse,
      );
    });
  });

  group('HomeDashboardPreferencesNotifier', () {
    setUp(() {
      SharedPreferences.setMockInitialValues(<String, Object>{});
    });

    test('persists action order and dashboard visibility choices', () async {
      final notifier = HomeDashboardPreferencesNotifier();
      addTearDown(notifier.dispose);
      await notifier.load();

      await notifier.setQuickActionOrder(<HomeQuickAction>[
        HomeQuickAction.toGo,
        HomeQuickAction.imageLibrary,
      ]);
      await notifier.setQuickActionVisible(HomeQuickAction.installMedia, false);
      await notifier.setModuleVisible(HomeDashboardModule.recentImages, false);

      expect(notifier.state.quickActionOrder, <HomeQuickAction>[
        HomeQuickAction.toGo,
        HomeQuickAction.imageLibrary,
        HomeQuickAction.installMedia,
      ]);
      expect(notifier.state.visibleQuickActions, <HomeQuickAction>[
        HomeQuickAction.toGo,
        HomeQuickAction.imageLibrary,
      ]);
      expect(
        notifier.state.isModuleVisible(HomeDashboardModule.recentImages),
        isFalse,
      );

      final storage = await SharedPreferences.getInstance();
      expect(
        storage.getStringList(
          HomeDashboardPreferences.quickActionOrderPreferenceKey,
        ),
        <String>[
          HomeQuickAction.toGo.name,
          HomeQuickAction.imageLibrary.name,
          HomeQuickAction.installMedia.name,
        ],
      );
      expect(
        storage.getStringList(
          HomeDashboardPreferences.hiddenQuickActionsPreferenceKey,
        ),
        <String>[HomeQuickAction.installMedia.name],
      );
      expect(
        storage.getStringList(
          HomeDashboardPreferences.hiddenModulesPreferenceKey,
        ),
        <String>[HomeDashboardModule.recentImages.name],
      );
    });

    test(
      'reset removes custom values and restores all dashboard content',
      () async {
        SharedPreferences.setMockInitialValues(<String, Object>{
          HomeDashboardPreferences.quickActionOrderPreferenceKey: <String>[
            HomeQuickAction.toGo.name,
          ],
          HomeDashboardPreferences.hiddenQuickActionsPreferenceKey: <String>[
            HomeQuickAction.imageLibrary.name,
          ],
          HomeDashboardPreferences.hiddenModulesPreferenceKey: <String>[
            HomeDashboardModule.storageOverview.name,
          ],
        });
        final notifier = HomeDashboardPreferencesNotifier();
        addTearDown(notifier.dispose);
        await notifier.load();

        await notifier.reset();

        expect(notifier.state.visibleQuickActions, HomeQuickAction.values);
        expect(
          notifier.state.isModuleVisible(HomeDashboardModule.recentImages),
          isTrue,
        );
        expect(
          notifier.state.isModuleVisible(HomeDashboardModule.storageOverview),
          isTrue,
        );

        final storage = await SharedPreferences.getInstance();
        expect(
          storage.containsKey(
            HomeDashboardPreferences.quickActionOrderPreferenceKey,
          ),
          isFalse,
        );
        expect(
          storage.containsKey(
            HomeDashboardPreferences.hiddenQuickActionsPreferenceKey,
          ),
          isFalse,
        );
        expect(
          storage.containsKey(
            HomeDashboardPreferences.hiddenModulesPreferenceKey,
          ),
          isFalse,
        );
      },
    );
  });
}
