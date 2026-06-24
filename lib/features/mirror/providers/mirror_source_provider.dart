import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/services/geo_service.dart';
import '../models/mirror_models.dart';
import '../../logs/services/log_center_service.dart';

enum MirrorSourceStrategy { auto, china, global }

class MirrorSourceState {
  final GeoResult? geo;
  final MirrorSourceStrategy strategy;
  final bool loading;

  const MirrorSourceState({
    this.geo,
    this.strategy = MirrorSourceStrategy.auto,
    this.loading = false,
  });

  bool get isChina {
    if (strategy == MirrorSourceStrategy.china) return true;
    if (strategy == MirrorSourceStrategy.global) return false;
    return geo?.isChina ?? false;
  }

  String get sourceLabel => isChina ? 'China Mirror' : 'Global Mirror';
  String get sourceEmoji => isChina ? '🇨🇳' : '🌍';
}

class MirrorSourceNotifier extends StateNotifier<MirrorSourceState> {
  MirrorSourceNotifier() : super(const MirrorSourceState()) {
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final strategyIndex = prefs.getInt('mirror_source_strategy') ?? 0;
    state = MirrorSourceState(
      strategy: MirrorSourceStrategy.values[strategyIndex],
    );
  }

  Future<void> setStrategy(MirrorSourceStrategy strategy) async {
    state = MirrorSourceState(strategy: strategy, geo: state.geo);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('mirror_source_strategy', strategy.index);
  }

  Future<void> detectGeo() async {
    if (state.loading) return;
    state = MirrorSourceState(
      strategy: state.strategy,
      geo: state.geo,
      loading: true,
    );

    final geo = await GeoService.getCountry();
    state = MirrorSourceState(
      strategy: state.strategy,
      geo: geo,
      loading: false,
    );

    LogCenterService().logSystem(
      '[MirrorSource] Country=${geo?.countryCode ?? "UNKNOWN"} '
      'Selected=${state.sourceLabel}',
    );
  }

  String resolveUrl(MirrorItem item) {
    final url = state.isChina
        ? (item.chinaUrl ?? item.downloadUrl)
        : (item.globalUrl ?? item.downloadUrl);

    LogCenterService().logSystem(
      '[MirrorSource] Mirror=${item.id} '
      'Country=${state.geo?.countryCode ?? "N/A"} '
      'Selected=${state.sourceLabel} '
      'URL=$url',
    );

    return url;
  }
}

final mirrorSourceProvider =
    StateNotifierProvider<MirrorSourceNotifier, MirrorSourceState>(
  (ref) => MirrorSourceNotifier(),
);
