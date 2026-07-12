import 'package:flutter/material.dart';

class WebLoadingOverlay extends StatelessWidget {
  final String title;
  final String url;
  final double? progress;
  final bool timedOut;
  final VoidCallback? onRetry;
  final VoidCallback? onOpenExternal;
  final String? errorCode;
  final bool isError;
  final String? Function(String)? localizer;

  const WebLoadingOverlay({
    super.key,
    required this.title,
    required this.url,
    this.progress,
    this.timedOut = false,
    this.onRetry,
    this.onOpenExternal,
    this.errorCode,
    this.isError = false,
    this.localizer,
  });

  String _t(BuildContext context, String key) {
    if (localizer != null) return localizer!(key) ?? key;
    return key;
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      color: colorScheme.surface,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (isError) ...[
                Icon(
                  Icons.error_outline_rounded,
                  size: 56,
                  color: colorScheme.error,
                ),
                const SizedBox(height: 20),
                Text(
                  _t(context, 'webview_error_title'),
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 14,
                    color: colorScheme.onSurfaceVariant,
                  ),
                  textAlign: TextAlign.center,
                ),
                if (errorCode != null) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: colorScheme.errorContainer,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      errorCode!,
                      style: TextStyle(
                        fontSize: 12,
                        fontFamily: 'monospace',
                        color: colorScheme.onErrorContainer,
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    OutlinedButton.icon(
                      icon: const Icon(Icons.refresh_rounded, size: 18),
                      label: Text(_t(context, 'webview_retry')),
                      onPressed: onRetry,
                    ),
                    const SizedBox(width: 12),
                    FilledButton.icon(
                      icon: const Icon(Icons.open_in_browser_rounded, size: 18),
                      label: Text(_t(context, 'webview_open_external')),
                      onPressed: onOpenExternal,
                    ),
                  ],
                ),
              ] else ...[
                _AnimatedGlobe(color: colorScheme.primary),
                const SizedBox(height: 24),
                Text(
                  _t(context, 'webview_loading_title'),
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 14,
                    color: colorScheme.primary,
                    fontWeight: FontWeight.w500,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: 240,
                  child: Column(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: progress,
                          minHeight: 4,
                          backgroundColor: colorScheme.surfaceContainerHighest,
                          color: colorScheme.primary,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        timedOut
                            ? _t(context, 'webview_slow')
                            : _t(context, 'webview_connecting'),
                        style: TextStyle(
                          fontSize: 13,
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                      if (!timedOut)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            _t(context, 'webview_wait_hint'),
                            style: TextStyle(
                              fontSize: 12,
                              color: colorScheme.onSurfaceVariant.withValues(
                                alpha: 0.6,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                if (timedOut) ...[
                  const SizedBox(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      OutlinedButton.icon(
                        icon: const Icon(Icons.refresh_rounded, size: 18),
                        label: Text(_t(context, 'webview_reload')),
                        onPressed: onRetry,
                      ),
                      const SizedBox(width: 12),
                      FilledButton.icon(
                        icon: const Icon(
                          Icons.open_in_browser_rounded,
                          size: 18,
                        ),
                        label: Text(_t(context, 'webview_open_external')),
                        onPressed: onOpenExternal,
                      ),
                    ],
                  ),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _AnimatedGlobe extends StatefulWidget {
  final Color color;
  const _AnimatedGlobe({required this.color});

  @override
  State<_AnimatedGlobe> createState() => _AnimatedGlobeState();
}

class _AnimatedGlobeState extends State<_AnimatedGlobe>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Transform.rotate(
          angle: _controller.value * 2 * 3.14159,
          child: Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: SweepGradient(
                colors: [
                  widget.color.withValues(alpha: 0.1),
                  widget.color.withValues(alpha: 0.3),
                  widget.color,
                  widget.color.withValues(alpha: 0.3),
                  widget.color.withValues(alpha: 0.1),
                ],
                stops: const [0.0, 0.2, 0.5, 0.8, 1.0],
              ),
            ),
            child: Center(
              child: Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Theme.of(context).colorScheme.surface,
                ),
                child: Icon(
                  Icons.language_rounded,
                  size: 28,
                  color: widget.color,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
