import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/recent_mirrors_service.dart';

/// Recent images resolved from the local preference store for Home.
///
/// Detail pages invalidate this provider after recording an image so an
/// already-mounted home screen immediately reflects the new ordering.
final recentMirrorEntriesProvider = FutureProvider<List<RecentMirrorEntry>>(
  (ref) => const RecentMirrorsService().load(),
);
