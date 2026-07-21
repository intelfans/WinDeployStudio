import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:win_deploy_studio/features/update/models/update_models.dart';
import 'package:win_deploy_studio/features/update/providers/update_provider.dart';
import 'package:win_deploy_studio/features/update/services/update_service.dart';

void main() {
  test(
    'cancelled download settles before retry and stale callbacks are ignored',
    () async {
      final service = _ControlledUpdateService();
      final notifier = _TestUpdateNotifier(service)..showAvailable(_updateInfo);
      addTearDown(notifier.dispose);

      final first = notifier.startDownload();
      expect(service.attempts, hasLength(1));
      final firstAttempt = service.attempts.single;

      notifier.cancelDownload();
      expect(firstAttempt.cancelToken.cancelled, isTrue);
      expect(notifier.state.status, UpdateStatus.downloading);

      await notifier.startDownload(source: UpdateDownloadSource.github);
      expect(service.attempts, hasLength(1));

      firstAttempt.result.complete(null);
      await first;
      expect(notifier.state.status, UpdateStatus.available);

      final second = notifier.startDownload(
        source: UpdateDownloadSource.github,
      );
      expect(service.attempts, hasLength(2));
      final secondAttempt = service.attempts.last;
      secondAttempt.onProgress(0.5, '1 MB/s', '10s', DownloadPhase.stable);
      expect(notifier.state.downloadProgress, 0.5);

      firstAttempt.onProgress(0.9, '9 MB/s', '1s', DownloadPhase.stable);
      expect(notifier.state.downloadProgress, 0.5);

      secondAttempt.result.complete(r'C:\Temp\WinDeployStudio.exe');
      await second;
      expect(notifier.state.status, UpdateStatus.downloaded);
      expect(notifier.state.downloadProgress, 1);
    },
  );
}

final _updateInfo = UpdateInfo(
  version: const AppVersion(2, 1, 1),
  tagName: 'v2.1.1',
  name: 'Test update',
  body: '',
  publishedAt: DateTime.utc(2026, 7, 21),
  assets: const [],
);

class _TestUpdateNotifier extends UpdateNotifier {
  _TestUpdateNotifier(super.service);

  void showAvailable(UpdateInfo info) {
    state = state.copyWith(status: UpdateStatus.available, info: info);
  }
}

class _ControlledUpdateService extends UpdateService {
  _ControlledUpdateService() : super.forTesting();

  final List<_DownloadAttempt> attempts = [];

  @override
  Future<bool> getAutoCheckEnabled() async => true;

  @override
  Future<DateTime?> getLastCheckTime() async => null;

  @override
  Future<UpdateChannel> getChannel() async => UpdateChannel.stable;

  @override
  Future<String?> getIgnoredVersion() async => null;

  @override
  Future<String?> downloadUpdate(
    UpdateInfo info,
    void Function(
      double progress,
      String speed,
      String remaining,
      DownloadPhase phase,
    )
    onProgress,
    CancelToken cancelToken, {
    UpdateDownloadSource source = UpdateDownloadSource.sourceForge,
  }) {
    final attempt = _DownloadAttempt(onProgress, cancelToken);
    attempts.add(attempt);
    return attempt.result.future;
  }
}

class _DownloadAttempt {
  final void Function(
    double progress,
    String speed,
    String remaining,
    DownloadPhase phase,
  )
  onProgress;
  final CancelToken cancelToken;
  final Completer<String?> result = Completer<String?>();

  _DownloadAttempt(this.onProgress, this.cancelToken);
}
