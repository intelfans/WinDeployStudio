import 'package:flutter_riverpod/legacy.dart';
import '../../../core/localization/strings.dart';
import '../../../core/services/geo_service.dart';
import '../models/mirror_models.dart';
import '../../logs/services/log_center_service.dart';

class MirrorSourceState {
  final GeoResult? geo;
  final bool loading;

  const MirrorSourceState({this.geo, this.loading = false});

  bool get isChina => geo?.isChina ?? false;

  String get sourceLabel =>
      trCurrent(isChina ? 'mirror_china_title' : 'mirror_global_title');
}

class MirrorSourceNotifier extends StateNotifier<MirrorSourceState> {
  MirrorSourceNotifier() : super(const MirrorSourceState());

  Future<void> detectGeo() async {
    if (state.loading) return;
    state = MirrorSourceState(geo: state.geo, loading: true);

    final geo = await GeoService.getCountry();
    state = MirrorSourceState(geo: geo);

    LogCenterService().logSystem(
      '[MirrorSource] Country=${geo?.countryCode ?? "UNKNOWN"} '
      'Selected=${state.sourceLabel}',
    );
  }

  String resolveUrl(MirrorItem item) {
    final useChinaMirror =
        item.hasChinaMirror && (state.isChina || !item.hasGlobalMirror);
    final url = useChinaMirror
        ? (item.chinaUrl ?? item.downloadUrl)
        : (item.globalUrl ?? item.chinaUrl ?? item.downloadUrl);
    final sourceLabel = trCurrent(
      useChinaMirror ? 'mirror_china_title' : 'mirror_global_title',
    );

    LogCenterService().logSystem(
      '[MirrorSource] Mirror=${item.id} '
      'Country=${state.geo?.countryCode ?? "N/A"} '
      'Selected=$sourceLabel '
      'URL=$url',
    );

    return url;
  }
}

final mirrorSourceProvider =
    StateNotifierProvider<MirrorSourceNotifier, MirrorSourceState>(
      (ref) => MirrorSourceNotifier(),
    );
