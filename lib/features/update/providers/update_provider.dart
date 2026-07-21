import 'package:flutter_riverpod/legacy.dart';
import '../../../core/localization/strings.dart';
import '../models/update_models.dart';
import '../services/update_service.dart';

class UpdateNotifier extends StateNotifier<UpdateState> {
  final UpdateService _service;
  CancelToken? _cancelToken;
  String? _downloadedFilePath;
  int _downloadRequest = 0;
  bool _disposed = false;

  UpdateNotifier(this._service) : super(const UpdateState()) {
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    try {
      final autoCheck = await _service.getAutoCheckEnabled();
      final lastCheck = await _service.getLastCheckTime();
      final channel = await _service.getChannel();
      final ignored = await _service.getIgnoredVersion();
      if (_disposed) return;

      state = state.copyWith(
        autoCheckEnabled: autoCheck,
        lastCheckTime: lastCheck,
        channel: channel,
        ignoredVersion: ignored,
      );
    } catch (_) {
      // Keep the in-memory defaults when local settings are unavailable.
    }
  }

  Future<void> checkForUpdate({bool forceRefresh = false}) async {
    if (_disposed) return;
    if (state.status == UpdateStatus.checking ||
        state.status == UpdateStatus.downloading) {
      return;
    }

    state = state.copyWith(status: UpdateStatus.checking);

    UpdateInfo? info;
    DateTime? lastCheck;
    try {
      info = await _service.checkForUpdate(forceRefresh: forceRefresh);
      lastCheck = await _service.getLastCheckTime();
    } catch (_) {
      if (!_disposed) {
        state = state.copyWith(
          status: UpdateStatus.error,
          error: trCurrent('update_check_failed'),
        );
      }
      return;
    }
    if (_disposed) return;

    if (info == null) {
      state = state.copyWith(
        status: UpdateStatus.error,
        error: trCurrent('update_check_failed'),
        lastCheckTime: lastCheck,
      );
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

  Future<void> startDownload({
    UpdateDownloadSource source = UpdateDownloadSource.sourceForge,
  }) async {
    if (_disposed ||
        state.info == null ||
        state.status == UpdateStatus.downloading ||
        state.status == UpdateStatus.installing) {
      return;
    }

    _downloadedFilePath = null;
    final info = state.info!;
    final request = ++_downloadRequest;
    final cancelToken = CancelToken();
    _cancelToken = cancelToken;

    state = state.copyWith(
      status: UpdateStatus.downloading,
      downloadProgress: 0.0,
      downloadSpeed: '0 KB/s',
      downloadRemaining: '--',
      downloadPhase: DownloadPhase.connecting,
      retryCount: 0,
      error: '',
      downloadSource: source,
    );

    try {
      final filePath = await _service.downloadUpdate(
        info,
        (progress, speed, remaining, phase) {
          if (!_isCurrentDownload(request, cancelToken) ||
              cancelToken.cancelled) {
            return;
          }
          state = state.copyWith(
            downloadProgress: progress,
            downloadSpeed: speed,
            downloadRemaining: remaining,
            downloadPhase: phase,
          );
        },
        cancelToken,
        source: source,
      );
      if (!_isCurrentDownload(request, cancelToken)) return;

      if (cancelToken.cancelled) {
        state = state.copyWith(
          status: UpdateStatus.available,
          downloadSpeed: '',
          downloadRemaining: '',
          error: '',
        );
      } else if (filePath != null) {
        _downloadedFilePath = filePath;
        state = state.copyWith(
          status: UpdateStatus.downloaded,
          downloadProgress: 1.0,
          error: '',
        );
      } else {
        final errorKey = _service.lastDownloadErrorKey;
        state = state.copyWith(
          status: UpdateStatus.error,
          error: trCurrent(errorKey ?? 'webview_download_failed'),
        );
      }
    } catch (_) {
      if (_isCurrentDownload(request, cancelToken)) {
        state = state.copyWith(
          status: cancelToken.cancelled
              ? UpdateStatus.available
              : UpdateStatus.error,
          error: cancelToken.cancelled
              ? ''
              : trCurrent('webview_download_failed'),
        );
      }
    } finally {
      if (_isCurrentDownload(request, cancelToken)) {
        _cancelToken = null;
      }
    }
  }

  void cancelDownload() {
    if (_disposed || state.status != UpdateStatus.downloading) return;
    _cancelToken?.cancel();
  }

  bool _isCurrentDownload(int request, CancelToken cancelToken) =>
      !_disposed &&
      request == _downloadRequest &&
      identical(_cancelToken, cancelToken);

  Future<bool> installUpdate() async {
    if (_disposed || _downloadedFilePath == null) return false;

    state = state.copyWith(status: UpdateStatus.installing);
    bool success;
    try {
      success = await _service.installUpdate(_downloadedFilePath!);
    } catch (_) {
      success = false;
    }
    if (_disposed) return false;
    if (!success) {
      state = state.copyWith(
        status: UpdateStatus.downloaded,
        error: trCurrent('update_install_verification_failed'),
      );
    }
    return success;
  }

  Future<void> ignoreVersion(String tagName) async {
    await _service.setIgnoredVersion(tagName);
    if (_disposed) return;
    state = state.copyWith(ignoredVersion: tagName, status: UpdateStatus.idle);
  }

  Future<void> setAutoCheck(bool enabled) async {
    await _service.setAutoCheckEnabled(enabled);
    if (_disposed) return;
    state = state.copyWith(autoCheckEnabled: enabled);
  }

  Future<void> setChannel(UpdateChannel channel) async {
    await _service.setChannel(channel);
    if (_disposed) return;
    state = state.copyWith(channel: channel);
  }

  @override
  void dispose() {
    _disposed = true;
    _downloadRequest++;
    _cancelToken?.cancel();
    _cancelToken = null;
    super.dispose();
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

final updateProvider = StateNotifierProvider<UpdateNotifier, UpdateState>((
  ref,
) {
  return UpdateNotifier(UpdateService());
});
