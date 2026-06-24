import 'package:flutter/material.dart';
import 'package:webview_windows/webview_windows.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/localization/strings.dart';
import 'in_app_webview.dart';

class WebviewHelper {
  static bool? _isAvailable;

  static Future<bool> isAvailable() async {
    if (_isAvailable != null) return _isAvailable!;
    try {
      final controller = WebviewController();
      await controller.initialize();
      controller.dispose();
      _isAvailable = true;
      return true;
    } catch (_) {
      _isAvailable = false;
      return false;
    }
  }

  static Future<void> openUrl(BuildContext context, String url, {String? title}) async {
    if (!context.mounted) return;

    final available = await isAvailable();
    if (!context.mounted) return;

    if (available) {
      Navigator.of(context, rootNavigator: true).push(
        MaterialPageRoute(
          builder: (_) => InAppWebview(url: url, title: title),
        ),
      );
    } else {
      showDownloadDialog(context, url);
    }
  }

  static void showDownloadDialog(BuildContext context, String url) {
    final downloadUrl = 'https://developer.microsoft.com/zh-cn/microsoft-edge/webview2/?form=MA13LH#download';
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr(ctx, 'webview_not_available')),
        content: Text(tr(ctx, 'webview_download_desc')),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              launchUrl(Uri.parse(url));
            },
            child: Text(tr(ctx, 'webview_open_in_browser')),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              launchUrl(Uri.parse(downloadUrl));
            },
            child: Text(tr(ctx, 'webview_download')),
          ),
        ],
      ),
    );
  }
}
