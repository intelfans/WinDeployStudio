import 'dart:async';
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
// widget. Keep SourceForge pages in the embedded WebView for other links.
const _externalBrowserPreferredHosts = <String>{};

class InAppWebview extends StatefulWidget {
  final String url;
  final String? title;

  const InAppWebview({super.key, required this.url, this.title});

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
  String _currentUrl = '';

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
    _currentUrl = widget.url;
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

      await _controller.loadUrl(widget.url);
      _startDownloadPolling();
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
  }

  void _startDownloadPolling() {
    _downloadPoller = Timer.periodic(const Duration(milliseconds: 500), (
      _,
    ) async {
      if (!mounted) return;
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
      } catch (_) {}
    });
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
  }

  void _reload() {
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
          else ...[
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
