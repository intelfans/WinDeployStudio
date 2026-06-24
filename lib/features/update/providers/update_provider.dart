import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/update_models.dart';
import '../services/update_service.dart';

class UpdateNotifier extends StateNotifier<UpdateState> {
  final UpdateService _service;
  CancelToken? _cancelToken;
  String? _downloadedFilePath;

  UpdateNotifier(this._service) : super(const UpdateState()) {
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final autoCheck = await _service.getAutoCheckEnabled();
    final lastCheck = await _service.getLastCheckTime();
    final channel = await _service.getChannel();
    final ignored = await _service.getIgnoredVersion();

    state = state.copyWith(
      autoCheckEnabled: autoCheck,
      lastCheckTime: lastCheck,
      channel: channel,
      ignoredVersion: ignored,
    );
  }

  Future<void> checkForUpdate({bool forceRefresh = false}) async {
    if (state.status == UpdateStatus.checking ||
        state.status == UpdateStatus.downloading) {
      return;
    }

    state = state.copyWith(status: UpdateStatus.checking);

    final info = await _service.checkForUpdate(forceRefresh: forceRefresh);
    final lastCheck = await _service.getLastCheckTime();

    if (info == null) {
      state = state.copyWith(
        status: UpdateStatus.error,
        error: 'Failed to check for updates',
        lastCheckTime: lastCheck,
      );
      await Future.delayed(const Duration(seconds: 3));
      if (state.status == UpdateStatus.error) {
        state = state.copyWith(status: UpdateStatus.idle);
      }
      return;
    }

    if (_service.isUpdateAvailable(info)) {
      final ignored = await _service.isIgnored(info);
      if (ignored) {
        state = state.copyWith(
          status: UpdateStatus.upToDate,
          info: info,
          lastCheckTime: lastCheck,
        );
      } else {
        state = state.copyWith(
          status: UpdateStatus.available,
          info: info,
          lastCheckTime: lastCheck,
        );
      }
    } else {
      state = state.copyWith(
        status: UpdateStatus.upToDate,
        info: info,
        lastCheckTime: lastCheck,
      );
    }
  }

  Future<void> startDownload() async {
    if (state.info == null) return;

    state = state.copyWith(
      status: UpdateStatus.downloading,
      downloadProgress: 0.0,
      downloadSpeed: '',
    );

    _cancelToken = CancelToken();

    final filePath = await _service.downloadUpdate(
      state.info!,
      (progress, speed) {
        state = state.copyWith(
          downloadProgress: progress,
          downloadSpeed: speed,
        );
      },
      _cancelToken!,
    );

    if (filePath != null) {
      _downloadedFilePath = filePath;
      state = state.copyWith(
        status: UpdateStatus.downloaded,
        downloadProgress: 1.0,
      );
    } else {
      if (_cancelToken!.cancelled) {
        state = state.copyWith(status: UpdateStatus.available);
      } else {
        state = state.copyWith(
          status: UpdateStatus.error,
          error: 'Download failed',
        );
      }
    }
  }

  void cancelDownload() {
    _cancelToken?.cancel();
    state = state.copyWith(status: UpdateStatus.available);
  }

  Future<bool> installUpdate() async {
    if (_downloadedFilePath == null) return false;

    state = state.copyWith(status: UpdateStatus.installing);
    return await _service.installUpdate(_downloadedFilePath!);
  }

  Future<void> ignoreVersion(String tagName) async {
    await _service.setIgnoredVersion(tagName);
    state = state.copyWith(
      ignoredVersion: tagName,
      status: UpdateStatus.idle,
    );
  }

  Future<void> setAutoCheck(bool enabled) async {
    await _service.setAutoCheckEnabled(enabled);
    state = state.copyWith(autoCheckEnabled: enabled);
  }

  Future<void> setChannel(UpdateChannel channel) async {
    await _service.setChannel(channel);
    state = state.copyWith(channel: channel);
  }

  String get currentVersion => _service.getCurrentVersion().toString();

  String? get lastCheckFormatted {
    if (state.lastCheckTime == null) return null;
    final dt = state.lastCheckTime!;
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} '
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  String get releasePageUrl => _service.releasePageUrl;
}

final updateProvider = StateNotifierProvider<UpdateNotifier, UpdateState>((ref) {
  return UpdateNotifier(UpdateService());
});
