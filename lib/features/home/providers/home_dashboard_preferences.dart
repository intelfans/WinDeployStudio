import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Stable identifiers for the actions shown in the home quick-start area.
///
/// The enum names are persisted, so rename an entry only with a migration.
enum HomeQuickAction {
  imageLibrary,
  installMedia,
  toGo;

  static HomeQuickAction? fromPreferenceValue(String value) {
    for (final action in values) {
      if (action.name == value) return action;
    }
    return null;
  }
}

/// Optional home dashboard sections that users can show or hide.
enum HomeDashboardModule {
  recentImages,
  storageOverview;

  static HomeDashboardModule? fromPreferenceValue(String value) {
    for (final module in values) {
      if (module.name == value) return module;
    }
    return null;
  }
}

/// User-controlled presentation preferences for the home dashboard.
@immutable
class HomeDashboardPreferences {
  HomeDashboardPreferences({
    Iterable<HomeQuickAction>? quickActionOrder,
    Iterable<HomeQuickAction>? hiddenQuickActions,
    Iterable<HomeDashboardModule>? hiddenModules,
    this.isLoaded = false,
  }) : quickActionOrder = List<HomeQuickAction>.unmodifiable(
         _normalizeQuickActionOrder(quickActionOrder ?? HomeQuickAction.values),
       ),
       hiddenQuickActions = Set<HomeQuickAction>.unmodifiable(
         hiddenQuickActions ?? const <HomeQuickAction>{},
       ),
       hiddenModules = Set<HomeDashboardModule>.unmodifiable(
         hiddenModules ?? const <HomeDashboardModule>{},
       );

  static const quickActionOrderPreferenceKey = 'home_quick_action_order';
  static const hiddenQuickActionsPreferenceKey = 'home_hidden_quick_actions';
  static const hiddenModulesPreferenceKey = 'home_hidden_modules';

  static final defaults = HomeDashboardPreferences();

  /// The complete order, including actions currently hidden from the dashboard.
  final List<HomeQuickAction> quickActionOrder;
  final Set<HomeQuickAction> hiddenQuickActions;
  final Set<HomeDashboardModule> hiddenModules;
  final bool isLoaded;

  /// Quick actions in their persisted order after hidden entries are removed.
  List<HomeQuickAction> get visibleQuickActions =>
      List<HomeQuickAction>.unmodifiable(
        quickActionOrder.where(
          (action) => !hiddenQuickActions.contains(action),
        ),
      );

  bool isQuickActionVisible(HomeQuickAction action) =>
      !hiddenQuickActions.contains(action);

  bool isModuleVisible(HomeDashboardModule module) =>
      !hiddenModules.contains(module);

  List<String> get quickActionOrderPreferenceValue =>
      quickActionOrder.map((action) => action.name).toList(growable: false);

  List<String> get hiddenQuickActionsPreferenceValue => HomeQuickAction.values
      .where(hiddenQuickActions.contains)
      .map((action) => action.name)
      .toList(growable: false);

  List<String> get hiddenModulesPreferenceValue => HomeDashboardModule.values
      .where(hiddenModules.contains)
      .map((module) => module.name)
      .toList(growable: false);

  factory HomeDashboardPreferences.fromPreferences(SharedPreferences prefs) {
    final storedOrder = prefs.getStringList(quickActionOrderPreferenceKey);
    final storedHiddenActions = prefs.getStringList(
      hiddenQuickActionsPreferenceKey,
    );
    final storedHiddenModules = prefs.getStringList(hiddenModulesPreferenceKey);

    return HomeDashboardPreferences(
      quickActionOrder: _quickActionsFromPreference(storedOrder),
      hiddenQuickActions: _quickActionsFromPreference(storedHiddenActions),
      hiddenModules: _modulesFromPreference(storedHiddenModules),
      isLoaded: true,
    );
  }

  HomeDashboardPreferences copyWith({
    Iterable<HomeQuickAction>? quickActionOrder,
    Iterable<HomeQuickAction>? hiddenQuickActions,
    Iterable<HomeDashboardModule>? hiddenModules,
    bool? isLoaded,
  }) {
    return HomeDashboardPreferences(
      quickActionOrder: quickActionOrder ?? this.quickActionOrder,
      hiddenQuickActions: hiddenQuickActions ?? this.hiddenQuickActions,
      hiddenModules: hiddenModules ?? this.hiddenModules,
      isLoaded: isLoaded ?? this.isLoaded,
    );
  }

  static List<HomeQuickAction> _normalizeQuickActionOrder(
    Iterable<HomeQuickAction> order,
  ) {
    final seen = <HomeQuickAction>{};
    final normalized = <HomeQuickAction>[];

    for (final action in order) {
      if (seen.add(action)) normalized.add(action);
    }
    for (final action in HomeQuickAction.values) {
      if (seen.add(action)) normalized.add(action);
    }

    return normalized;
  }

  static Iterable<HomeQuickAction> _quickActionsFromPreference(
    List<String>? values,
  ) {
    return values
            ?.map(HomeQuickAction.fromPreferenceValue)
            .whereType<HomeQuickAction>() ??
        const <HomeQuickAction>[];
  }

  static Iterable<HomeDashboardModule> _modulesFromPreference(
    List<String>? values,
  ) {
    return values
            ?.map(HomeDashboardModule.fromPreferenceValue)
            .whereType<HomeDashboardModule>() ??
        const <HomeDashboardModule>[];
  }
}

typedef HomeDashboardPreferencesLoader = Future<SharedPreferences> Function();

/// Loads and persists [HomeDashboardPreferences] for the home screen.
class HomeDashboardPreferencesNotifier
    extends StateNotifier<HomeDashboardPreferences> {
  HomeDashboardPreferencesNotifier({
    HomeDashboardPreferencesLoader? preferencesLoader,
  }) : _preferencesLoader = preferencesLoader ?? SharedPreferences.getInstance,
       super(HomeDashboardPreferences.defaults) {
    unawaited(load());
  }

  final HomeDashboardPreferencesLoader _preferencesLoader;
  Future<void>? _loadFuture;

  /// Completes once the stored preferences have been read, or defaults were
  /// retained when the local store was unavailable.
  Future<void> load() => _loadFuture ??= _load();

  Future<void> _load() async {
    try {
      final preferences = await _preferencesLoader();
      state = HomeDashboardPreferences.fromPreferences(preferences);
    } catch (_) {
      state = state.copyWith(isLoaded: true);
    }
  }

  Future<void> setQuickActionOrder(Iterable<HomeQuickAction> order) async {
    await load();
    final next = state.copyWith(quickActionOrder: order);
    state = next;
    await _persist(next);
  }

  Future<void> setQuickActionVisible(
    HomeQuickAction action,
    bool visible,
  ) async {
    await load();
    final hidden = Set<HomeQuickAction>.of(state.hiddenQuickActions);
    if (visible) {
      hidden.remove(action);
    } else {
      hidden.add(action);
    }

    final next = state.copyWith(hiddenQuickActions: hidden);
    state = next;
    await _persist(next);
  }

  Future<void> setModuleVisible(
    HomeDashboardModule module,
    bool visible,
  ) async {
    await load();
    final hidden = Set<HomeDashboardModule>.of(state.hiddenModules);
    if (visible) {
      hidden.remove(module);
    } else {
      hidden.add(module);
    }

    final next = state.copyWith(hiddenModules: hidden);
    state = next;
    await _persist(next);
  }

  /// Restores the full quick-start list and all optional dashboard modules.
  Future<void> reset() async {
    await load();
    final next = HomeDashboardPreferences(isLoaded: true);
    state = next;

    try {
      final preferences = await _preferencesLoader();
      await Future.wait(<Future<bool>>[
        preferences.remove(
          HomeDashboardPreferences.quickActionOrderPreferenceKey,
        ),
        preferences.remove(
          HomeDashboardPreferences.hiddenQuickActionsPreferenceKey,
        ),
        preferences.remove(HomeDashboardPreferences.hiddenModulesPreferenceKey),
      ]);
    } catch (_) {
      // The in-memory defaults remain useful if local persistence is unavailable.
    }
  }

  Future<void> _persist(HomeDashboardPreferences preferences) async {
    try {
      final storage = await _preferencesLoader();
      await Future.wait(<Future<bool>>[
        storage.setStringList(
          HomeDashboardPreferences.quickActionOrderPreferenceKey,
          preferences.quickActionOrderPreferenceValue,
        ),
        storage.setStringList(
          HomeDashboardPreferences.hiddenQuickActionsPreferenceKey,
          preferences.hiddenQuickActionsPreferenceValue,
        ),
        storage.setStringList(
          HomeDashboardPreferences.hiddenModulesPreferenceKey,
          preferences.hiddenModulesPreferenceValue,
        ),
      ]);
    } catch (_) {
      // Keep the current session responsive even if SharedPreferences fails.
    }
  }
}

final homeDashboardPreferencesProvider =
    StateNotifierProvider<
      HomeDashboardPreferencesNotifier,
      HomeDashboardPreferences
    >((ref) => HomeDashboardPreferencesNotifier());
