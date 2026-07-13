import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/disk_safety_service.dart';
import '../models/home_storage_overview.dart';

final homeStorageOverviewServiceProvider = Provider<HomeStorageOverviewService>(
  (ref) => HomeStorageOverviewService(ref.watch(diskSafetyServiceProvider)),
);

/// Loads the compact, read-only external-storage summary used by Home.
///
/// The underlying service only enumerates disks. It does not open a volume for
/// writing and it does not alter the stricter safety gates used by deployment.
final homeStorageOverviewProvider =
    FutureProvider.autoDispose<HomeStorageOverview>((ref) {
      return ref.watch(homeStorageOverviewServiceProvider).load();
    });

class HomeStorageOverviewService {
  final DiskSafetyService _diskSafetyService;

  HomeStorageOverviewService(this._diskSafetyService);

  Future<HomeStorageOverview> load() async {
    final disks = await _diskSafetyService.getRemovableDisks();
    return HomeStorageOverview.fromDisks(disks);
  }
}
