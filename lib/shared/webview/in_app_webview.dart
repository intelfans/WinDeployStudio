import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_windows/webview_windows.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import '../../core/localization/strings.dart';
import '../../features/logs/services/log_center_service.dart';
import 'download_manager.dart';
import 'download_panel.dart';
import 'web_loading_overlay.dart';

const _chromeUA =
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/137.0.0.0 Safari/537.36';

// Mirror downloads are resolved by DownloadManager before reaching this
// widget. Keep Global Mirror pages in the embedded WebView for other links.
const _externalBrowserPreferredHosts = <String>{};

class InAppDownloadRequest {
  const InAppDownloadRequest({
    required this.url,
    required this.fileName,
    required this.imageName,
    required this.mirrorLabel,
  });

  final String url;
  final String fileName;
  final String imageName;
  final String mirrorLabel;
}

class InAppWebview extends StatefulWidget {
  final String url;
  final String? title;
  final InAppDownloadRequest? downloadRequest;

  const InAppWebview({
    super.key,
    required this.url,
    this.title,
    this.downloadRequest,
  });

  @override
  State<InAppWebview> createState() => _InAppWebviewState();
}

class _InAppWebviewState extends State<InAppWebview> {
  final _controller = WebviewController();
  final _downloadManager = DownloadManager();
  final GlobalKey _downloadBtnKey = GlobalKey();

  bool _isLoading = true;
  bool _hasError = false;
  String _errorCode = '';
  bool _timedOut = false;
  bool _isReloading = false;
  double? _loadProgress;
  Timer? _timeoutTimer;
  Timer? _downloadPoller;
  bool _downloadInjected = false;
  bool _navFixInjected = false;
  bool _checkingDownloads = false;
  String _currentUrl = '';
  String? _managedDownloadId;
  bool _managedDownloadStarted = false;

  int _consecutiveErrors = 0;
  static const _maxConsecutiveErrors = 2;

  static const _navigationFixScript = r'''
    (function() {
      if (window.__wds_nav_fixed) return 'injected';
      window.__wds_nav_fixed = true;
      function fixLinks() {
        var links = document.querySelectorAll('a[target="_blank"]');
        for (var i = 0; i < links.length; i++) {
          links[i].removeAttribute('target');
        }
      }
      fixLinks();
      var observer = new MutationObserver(function(mutations) { fixLinks(); });
      observer.observe(document.body, { childList: true, subtree: true });
      document.addEventListener('click', function(e) {
        var el = e.target;
        while (el && el.tagName !== 'A') el = el.parentElement;
        if (el && el.tagName === 'A') {
          var href = el.getAttribute('href') || '';
          if (href && href !== '#' && !href.startsWith('javascript:') && !href.startsWith('#')) {
            el.removeAttribute('target');
          }
        }
      }, true);
      return 'ok';
    })();
  ''';

  static const _downloadDetectScript = r'''
    (function() {
      if (window.__wds_download_injected) return 'injected';
      window.__wds_download_injected = true;
      window.__wds_pending_download = '';
      function isDownloadLink(el) {
        while (el && el.tagName) {
          if (el.tagName === 'A') {
            var href = el.getAttribute('href') || '';
            if (el.dataset.wdsDownload === 'true') return href;
            if (el.hasAttribute('download')) return href;
            if (/\.(iso|img|wim|esd|zip|rar|7z|exe|msi|cab|gz|tar|tgz)(\?|$)/i.test(href)) return href;
          }
          el = el.parentElement;
        }
        return null;
      }
      document.addEventListener('click', function(e) {
        var url = isDownloadLink(e.target);
          if (url && url !== '#' && !url.startsWith('javascript:')) {
            e.preventDefault();
            e.stopPropagation();
            url = new URL(url, window.location.href).href;
            window.__wds_pending_download = url;
          }
      }, true);
      return 'ok';
    })();
  ''';

  @override
  void initState() {
    super.initState();
    _currentUrl = widget.downloadRequest == null
        ? widget.url
        : 'win-deploy://global-mirror-download';
    _checkExternalPreferred();
  }

  bool _isExternalPreferred(String url) {
    try {
      final host = Uri.parse(url).host;
      return _externalBrowserPreferredHosts.contains(host);
    } catch (_) {
      return false;
    }
  }

  Future<void> _checkExternalPreferred() async {
    if (widget.downloadRequest != null) {
      await _initWebview();
      return;
    }
    if (_isExternalPreferred(widget.url)) {
      _log('ExternalBrowserPreferred', url: widget.url);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _openExternal(widget.url);
        if (mounted) Navigator.of(context).pop();
      });
      return;
    }
    _initWebview();
  }

  void _log(String event, {String? url, bool? success, String? error}) {
    final buffer = StringBuffer('[WebView]\nEvent=$event');
    if (url != null) buffer.write('\nUrl=$url');
    if (success != null) buffer.write('\nSuccess=$success');
    if (error != null) buffer.write('\nWebErrorStatus=$error');
    LogCenterService().logSystem(buffer.toString());
  }

  Future<void> _initWebview() async {
    _startTimeout();
    try {
      await _controller.initialize();

      await _controller.setPopupWindowPolicy(
        WebviewPopupWindowPolicy.sameWindow,
      );
      await _controller.setUserAgent(_chromeUA);

      _controller.url.listen((url) {
        if (mounted) {
          _log('SourceChanged', url: url);
          setState(() {
            _currentUrl = url;
            _downloadInjected = false;
            _navFixInjected = false;
          });
        }
      });

      _controller.loadingState.listen((state) {
        if (!mounted) return;
        if (state == LoadingState.loading) {
          _log('NavigationStarting', url: _currentUrl);
          setState(() {
            _isLoading = true;
            _hasError = false;
            _loadProgress = null;
          });
          _isReloading = false;
          _startTimeout();
        } else if (state == LoadingState.navigationCompleted) {
          _log('NavigationCompleted', url: _currentUrl, success: true);
          _onLoadComplete();
        }
      });

      _controller.onLoadError.listen((error) {
        if (!mounted || _isReloading) return;
        final errorName = error.name;
        _log(
          'NavigationCompleted',
          url: _currentUrl,
          success: false,
          error: errorName,
        );
        setState(() {
          _hasError = true;
          _errorCode = 'ERR_$errorName';
          _isLoading = false;
        });
        _timeoutTimer?.cancel();
        _consecutiveErrors++;
        if (_consecutiveErrors >= _maxConsecutiveErrors) {
          _showDowngradeDialog();
        }
      });

      _controller.webMessage.listen((message) {
        _log('WebMessageReceived', url: _currentUrl);
      });

      final request = widget.downloadRequest;
      if (request != null) {
        await _controller.loadStringContent(
          _buildDownloadProgressPage(request),
        );
        _onLoadComplete();
        unawaited(_beginManagedDownload(request));
      } else {
        await _controller.loadUrl(widget.url);
        _startDownloadPolling();
      }
    } catch (e) {
      _log('ProcessFailed', url: widget.url, error: e.toString());
      if (mounted) {
        setState(() {
          _hasError = true;
          _errorCode = e.toString();
          _isLoading = false;
        });
        _timeoutTimer?.cancel();
        _consecutiveErrors++;
        if (_consecutiveErrors >= _maxConsecutiveErrors) {
          _showDowngradeDialog();
        }
      }
    }
  }

  void _startTimeout() {
    _timeoutTimer?.cancel();
    _timedOut = false;
    _timeoutTimer = Timer(const Duration(seconds: 8), () {
      if (mounted && _isLoading) setState(() => _timedOut = true);
    });
  }

  void _onLoadComplete() {
    _timeoutTimer?.cancel();
    _consecutiveErrors = 0;
    if (!mounted) return;
    setState(() {
      _loadProgress = 1.0;
      _isLoading = false;
    });
    // Install interception before the user can activate a download link.
    unawaited(_checkForDownloadLink());
  }

  void _startDownloadPolling() {
    _downloadPoller = Timer.periodic(const Duration(milliseconds: 500), (_) {
      unawaited(_checkForDownloadLink());
    });
  }

  Future<void> _checkForDownloadLink() async {
    if (!mounted || _checkingDownloads) return;
    _checkingDownloads = true;
    try {
      if (!_navFixInjected) {
        final result = await _controller.executeScript(_navigationFixScript);
        if (result == 'ok' || result == 'injected') _navFixInjected = true;
      }
      if (!_downloadInjected) {
        final result = await _controller.executeScript(_downloadDetectScript);
        if (result == 'ok' || result == 'injected') _downloadInjected = true;
      }
      if (_downloadInjected) {
        final result = await _controller.executeScript(
          '(function(){ var u = window.__wds_pending_download; window.__wds_pending_download = ""; return u || ""; })()',
        );
        if (result is String &&
            result.isNotEmpty &&
            result.startsWith('http')) {
          _handleDownloadUrl(result);
        }
      }
    } catch (_) {
      // A page may be navigating while the script is injected; polling retries.
    } finally {
      _checkingDownloads = false;
    }
  }

  void _handleDownloadUrl(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    _startDownload(url, _guessFileName(uri));
  }

  String _guessFileName(Uri uri) {
    if (uri.pathSegments.isNotEmpty) {
      final last = uri.pathSegments.last;
      if (last.contains('.') && !last.endsWith('.')) {
        final name = last.split('?').first;
        if (name.isNotEmpty) return name;
      }
    }
    for (final key in ['file', 'filename', 'name', 'fname']) {
      final val = uri.queryParameters[key];
      if (val != null && val.isNotEmpty) return val;
    }
    return 'download';
  }

  Future<void> _startDownload(String url, String defaultName) async {
    final savePath = await FilePicker.saveFile(
      dialogTitle: tr(context, 'webview_save_title'),
      fileName: defaultName,
      type: FileType.any,
    );
    if (savePath == null) return;
    await _downloadManager.startDownload(
      url: url,
      fileName: p.basename(savePath),
      savePath: savePath,
    );
    if (mounted) _showDownloadPanel();
  }

  Future<void> _beginManagedDownload(InAppDownloadRequest request) async {
    if (_managedDownloadStarted) return;
    _managedDownloadStarted = true;
    await Future<void>.delayed(const Duration(milliseconds: 180));
    if (!mounted) return;

    await _setManagedDownloadState(
      phase: _managedPrepareLabel(),
      detail: _managedPrepareDetail(),
      progress: 0,
      indeterminate: true,
    );
    if (!mounted) return;
    final savePath = await FilePicker.saveFile(
      dialogTitle: tr(context, 'webview_save_title'),
      fileName: request.fileName,
      type: FileType.any,
    );
    if (!mounted) return;
    if (savePath == null) {
      await _setManagedDownloadState(
        phase: tr(context, 'dl_cancelled'),
        detail: _managedCancelledDetail(),
        progress: 0,
      );
      return;
    }

    final item = await _downloadManager.startDownload(
      url: request.url,
      fileName: p.basename(savePath),
      savePath: savePath,
    );
    _managedDownloadId = item.id;
    _downloadManager.addListener(_onManagedDownloadChanged);
    await _syncManagedDownloadState();
    if (mounted) _showDownloadPanel();
  }

  void _onManagedDownloadChanged() {
    unawaited(_syncManagedDownloadState());
  }

  Future<void> _syncManagedDownloadState() async {
    final id = _managedDownloadId;
    if (!mounted || id == null) return;
    final item = _downloadManager.items
        .where((entry) => entry.id == id)
        .firstOrNull;
    if (item == null) return;

    final detail = item.totalBytes > 0
        ? '${_formatDownloadBytes(item.receivedBytes)} / ${_formatDownloadBytes(item.totalBytes)}${item.speed.isEmpty ? '' : ' · ${item.speed}'}'
        : _managedKeepOpenDetail();
    final phase = switch (item.status) {
      DownloadStatus.downloading => tr(context, 'webview_downloading'),
      DownloadStatus.paused => tr(context, 'dl_paused'),
      DownloadStatus.completed => tr(context, 'dl_done'),
      DownloadStatus.cancelled => tr(context, 'dl_cancelled'),
      DownloadStatus.error => tr(context, 'dl_failed'),
    };
    await _setManagedDownloadState(
      phase: phase,
      detail: item.status == DownloadStatus.error && item.error != null
          ? item.error!
          : detail,
      progress: item.progress * 100,
      indeterminate:
          item.status == DownloadStatus.downloading && item.totalBytes <= 0,
    );
  }

  Future<void> _setManagedDownloadState({
    required String phase,
    required String detail,
    required double progress,
    bool indeterminate = false,
  }) async {
    if (!mounted || widget.downloadRequest == null) return;
    final payload = jsonEncode({
      'phase': phase,
      'detail': detail,
      'progress': progress.clamp(0, 100),
      'indeterminate': indeterminate,
    });
    try {
      await _controller.executeScript(
        'window.WDSDownload && window.WDSDownload.update($payload);',
      );
    } catch (_) {
      // The page is still initializing or has already been closed.
    }
  }

  String _formatDownloadBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  String _managedPrepareLabel() =>
      tr(context, 'webview_managed_download_preparing');

  String _managedPrepareDetail() =>
      tr(context, 'webview_managed_download_choose_location');

  String _managedKeepOpenDetail() =>
      tr(context, 'webview_managed_download_tracking');

  String _managedCancelledDetail() =>
      tr(context, 'webview_managed_download_no_location');

  String _buildDownloadProgressPage(InAppDownloadRequest request) {
    final escape = const HtmlEscape();
    final locale = Localizations.localeOf(context);
    final htmlLanguage = localeCodeFromLocale(locale).replaceAll('_', '-');
    final isRtl = locale.languageCode == 'ar';
    final title = tr(context, 'webview_managed_download_title');
    final message = tr(context, 'webview_managed_download_message');
    final keepOpen = tr(context, 'webview_managed_download_keep_open');
    final fileLabel = tr(context, 'webview_managed_download_file_label');
    final sourceLabel = tr(context, 'webview_managed_download_channel_label');
    final initialState = tr(
      context,
      'webview_managed_download_waiting_location',
    );
    return '''<!doctype html>
<html lang="$htmlLanguage" dir="${isRtl ? 'rtl' : 'ltr'}">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<style>
  :root { color-scheme: light; font-family: "Segoe UI", "Microsoft YaHei UI", sans-serif; }
  * { box-sizing: border-box; }
  body { margin: 0; min-height: 100vh; background: #f4f7fb; color: #172033; display: grid; place-items: center; padding: 32px; }
  main { width: min(720px, 100%); }
  .surface { border: 1px solid #d8e0eb; border-radius: 18px; background: #ffffff; box-shadow: 0 18px 46px rgba(33, 51, 78, 0.12); overflow: hidden; }
  .accent { height: 5px; background: #2e6ba7; }
  .content { padding: clamp(32px, 7vw, 58px); text-align: center; }
  .mark { width: 76px; height: 76px; margin: 0 auto 24px; border-radius: 22px; background: #dbeafe; color: #24578b; display: grid; place-items: center; font-size: 38px; font-weight: 300; }
  .eyebrow { margin: 0 0 10px; color: #416b99; font-size: 13px; font-weight: 700; letter-spacing: 0; }
  h1 { margin: 0; font-size: clamp(26px, 4vw, 34px); letter-spacing: 0; }
  .lead { max-width: 510px; margin: 14px auto 30px; color: #59677b; font-size: 16px; line-height: 1.65; }
  .file { display: grid; grid-template-columns: 1fr auto; gap: 16px; text-align: start; padding: 16px 18px; border: 1px solid #dce4ee; border-radius: 12px; background: #fbfcfe; }
  .file-label { display: block; margin-bottom: 5px; color: #66758a; font-size: 12px; }
  .file-name { display: block; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; font-weight: 650; }
  .channel { align-self: center; color: #24578b; font-size: 13px; font-weight: 700; white-space: nowrap; }
  .progress { height: 8px; margin: 30px 0 12px; overflow: hidden; border-radius: 999px; background: #e4eaf2; }
  .progress > span { display: block; width: 0%; height: 100%; border-radius: inherit; background: #2e6ba7; transition: width 220ms ease; }
  .progress > span.indeterminate { width: 36%; animation: travel 1.15s ease-in-out infinite; }
  @keyframes travel { 0% { transform: translateX(-120%); } 100% { transform: translateX(310%); } }
  .status { display: flex; gap: 16px; justify-content: space-between; text-align: start; color: #526176; font-size: 14px; }
  .status strong { color: #1c2b40; font-weight: 700; }
  .notice { margin: 30px 0 0; padding-top: 22px; border-top: 1px solid #e2e8f0; color: #5d6c80; font-size: 13px; line-height: 1.6; }
  @media (max-width: 540px) { body { padding: 16px; } .content { padding: 30px 22px; } .file { grid-template-columns: 1fr; gap: 8px; } .channel { justify-self: start; } .status { display: block; } .status strong { display: block; margin-top: 5px; } }
</style>
</head>
<body>
<main>
  <section class="surface" aria-live="polite">
    <div class="accent"></div>
    <div class="content">
      <div class="mark" aria-hidden="true">&#8595;</div>
      <p class="eyebrow">${escape.convert(request.mirrorLabel)}</p>
      <h1 id="phase">${escape.convert(title)}</h1>
      <p class="lead">${escape.convert(message)}</p>
      <div class="file">
        <div><span class="file-label">${escape.convert(fileLabel)}</span><span class="file-name">${escape.convert(request.imageName)}</span></div>
        <span class="channel">${escape.convert(sourceLabel)} · ${escape.convert(request.mirrorLabel)}</span>
      </div>
      <div class="progress"><span id="bar" class="indeterminate"></span></div>
      <div class="status"><span id="detail">${escape.convert(initialState)}</span><strong id="percent">0%</strong></div>
      <p class="notice">${escape.convert(keepOpen)}</p>
    </div>
  </section>
</main>
<script>
  window.WDSDownload = {
    update: function (data) {
      var phase = document.getElementById('phase');
      var detail = document.getElementById('detail');
      var percent = document.getElementById('percent');
      var bar = document.getElementById('bar');
      phase.textContent = data.phase || '';
      detail.textContent = data.detail || '';
      var value = Math.max(0, Math.min(100, Number(data.progress) || 0));
      percent.textContent = Math.round(value) + '%';
      bar.style.width = value + '%';
      bar.classList.toggle('indeterminate', Boolean(data.indeterminate));
    }
  };
</script>
</body>
</html>''';
  }

  void _reload() {
    if (widget.downloadRequest != null) {
      unawaited(
        _setManagedDownloadState(
          phase: _managedPrepareLabel(),
          detail: _managedPrepareDetail(),
          progress: 0,
          indeterminate: true,
        ),
      );
      return;
    }
    _isReloading = true;
    setState(() {
      _isLoading = true;
      _hasError = false;
      _errorCode = '';
      _timedOut = false;
      _loadProgress = null;
      _downloadInjected = false;
      _navFixInjected = false;
    });
    _startTimeout();
    _controller.reload().catchError((e) {
      _isReloading = false;
      _log('ProcessFailed', url: _currentUrl, error: e.toString());
      if (mounted) {
        setState(() {
          _hasError = true;
          _errorCode = e.toString();
          _isLoading = false;
        });
        _timeoutTimer?.cancel();
      }
    });
  }

  Future<void> _openExternal(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${tr(context, 'detail_open_failed')}: $e')),
        );
      }
    }
  }

  void _showDowngradeDialog() {
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr(ctx, 'webview_downgrade_title')),
        content: Text(tr(ctx, 'webview_downgrade_desc')),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(tr(ctx, 'detail_cancel')),
          ),
          OutlinedButton.icon(
            icon: const Icon(Icons.copy, size: 16),
            label: Text(tr(ctx, 'detail_copy_link')),
            onPressed: () {
              Navigator.of(ctx).pop();
              _copyLink(_currentUrl);
            },
          ),
          FilledButton.icon(
            icon: const Icon(Icons.open_in_browser, size: 16),
            label: Text(tr(ctx, 'webview_open_external')),
            onPressed: () {
              Navigator.of(ctx).pop();
              _openExternal(_currentUrl);
            },
          ),
        ],
      ),
    );
  }

  void _copyLink(String url) {
    final data = ClipboardData(text: url);
    Clipboard.setData(data);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(tr(context, 'detail_link_copied'))),
      );
    }
  }

  Future<void> _runNetworkDiag() async {
    if (!mounted) return;
    final uri = Uri.tryParse(_currentUrl);
    if (uri == null) return;

    final host = uri.host;
    final results = <String>[];
    results.add('[Network] Host=$host');

    try {
      final dnsResult = await _controller.executeScript(
        '(function(){ return document.location.hostname || "FAIL"; })()',
      );
      results.add('[Network] DNS=${dnsResult != null ? "OK" : "FAIL"}');
    } catch (_) {
      results.add('[Network] DNS=FAIL');
    }

    try {
      final tlsResult = await _controller.executeScript(
        '(function(){ return window.location.protocol || "unknown"; })()',
      );
      results.add('[Network] TLS=$tlsResult');
    } catch (_) {
      results.add('[Network] TLS=FAIL');
    }

    try {
      final finalUrl = await _controller.executeScript(
        '(function(){ return window.location.href || ""; })()',
      );
      results.add('[Network] FinalUrl=$finalUrl');
    } catch (_) {
      results.add('[Network] FinalUrl=FAIL');
    }

    final logMsg = results.join('\n');
    LogCenterService().logSystem(logMsg);

    if (mounted) {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(tr(ctx, 'webview_diag_title')),
          content: SelectableText(
            logMsg,
            style: const TextStyle(fontFamily: 'Consolas', fontSize: 12),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text(tr(ctx, 'close')),
            ),
          ],
        ),
      );
    }
  }

  void _showDownloadPanel() {
    final RenderBox? button =
        _downloadBtnKey.currentContext?.findRenderObject() as RenderBox?;
    if (button == null) return;
    final offset = button.localToGlobal(Offset.zero);
    final size = button.size;

    showMenu(
      context: context,
      position: RelativeRect.fromLTRB(
        offset.dx - 380 + size.width,
        offset.dy + size.height + 4,
        offset.dx,
        offset.dy + size.height + 4 + 420,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      constraints: const BoxConstraints(maxWidth: 380, maxHeight: 420),
      items: [
        PopupMenuItem(
          enabled: false,
          padding: EdgeInsets.zero,
          child: DownloadPanel(
            onDownloadCurrentPage: () {
              Navigator.pop(context);
            },
          ),
        ),
      ],
    );
  }

  @override
  void dispose() {
    _timeoutTimer?.cancel();
    _downloadPoller?.cancel();
    _downloadManager.removeListener(_onManagedDownloadChanged);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final displayTitle = widget.title ?? _currentUrl;

    return Scaffold(
      appBar: AppBar(
        title: Text(displayTitle, maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          if (_isLoading && !_hasError)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Center(
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: colorScheme.primary,
                  ),
                ),
              ),
            )
          else if (widget.downloadRequest != null) ...[
            ListenableBuilder(
              listenable: _downloadManager,
              builder: (context, _) {
                final activeCount = _downloadManager.items
                    .where((i) => i.status == DownloadStatus.downloading)
                    .length;
                return IconButton(
                  key: _downloadBtnKey,
                  icon: Badge(
                    isLabelVisible: activeCount > 0,
                    label: Text(
                      '$activeCount',
                      style: const TextStyle(fontSize: 10),
                    ),
                    child: const Icon(Icons.download_rounded),
                  ),
                  onPressed: _showDownloadPanel,
                  tooltip: tr(context, 'webview_download_file'),
                );
              },
            ),
          ] else ...[
            IconButton(
              icon: const Icon(Icons.network_check_rounded),
              onPressed: _runNetworkDiag,
              tooltip: tr(context, 'webview_diag'),
            ),
            ListenableBuilder(
              listenable: _downloadManager,
              builder: (context, _) {
                final activeCount = _downloadManager.items
                    .where((i) => i.status == DownloadStatus.downloading)
                    .length;
                return IconButton(
                  key: _downloadBtnKey,
                  icon: Badge(
                    isLabelVisible: activeCount > 0,
                    label: Text(
                      '$activeCount',
                      style: const TextStyle(fontSize: 10),
                    ),
                    child: const Icon(Icons.download_rounded),
                  ),
                  onPressed: _showDownloadPanel,
                  tooltip: tr(context, 'webview_download_file'),
                );
              },
            ),
            IconButton(
              icon: const Icon(Icons.refresh_rounded),
              onPressed: _reload,
              tooltip: tr(context, 'webview_refresh'),
            ),
            IconButton(
              icon: const Icon(Icons.open_in_browser_rounded),
              onPressed: () => _openExternal(_currentUrl),
              tooltip: tr(context, 'webview_open_external'),
            ),
          ],
        ],
      ),
      body: Stack(
        children: [
          Positioned.fill(child: Webview(_controller)),
          if (_isLoading || _hasError)
            WebLoadingOverlay(
              title: displayTitle,
              url: _currentUrl,
              progress: _loadProgress,
              timedOut: _timedOut,
              isError: _hasError,
              errorCode: _hasError ? _errorCode : null,
              onRetry: _reload,
              onOpenExternal: () =>
                  _openExternal(_hasError ? widget.url : _currentUrl),
              localizer: (key) => tr(context, key),
            ),
        ],
      ),
    );
  }
}
