import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:path/path.dart' as p;

import '../../../app/typography.dart';
import '../../../core/localization/strings.dart';
import '../services/image_conversion_service.dart';

class ImageConverterScreen extends StatefulWidget {
  final String? returnTarget;

  const ImageConverterScreen({super.key, this.returnTarget});

  @override
  State<ImageConverterScreen> createState() => _ImageConverterScreenState();
}

class _ImageConverterScreenState extends State<ImageConverterScreen> {
  final _service = const ImageConversionService();
  final _labelController = TextEditingController(text: 'WINDEPLOY');
  ImageConversionAnalysis? _analysis;
  ImageConversionAnalysis? _baseAnalysis;
  String? _sourcePath;
  String? _basePath;
  String? _outputPath;
  ImageConversionProgress? _progress;
  ImageConversionResult? _result;
  ImageConversionCancellationToken? _cancellation;
  bool _analyzing = false;
  bool _running = false;

  @override
  void dispose() {
    _cancellation?.cancel();
    _labelController.dispose();
    super.dispose();
  }

  Future<void> _chooseImage() async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: const [
        'wim',
        'esd',
        'swm',
        'iso',
        'vhd',
        'vhdx',
        'img',
        'raw',
        'dd',
        'zip',
        '7z',
        'rar',
      ],
      dialogTitle: tr(context, 'image_converter_select_file'),
    );
    final path = result?.files.single.path;
    if (path != null) await _setSource(path);
  }

  Future<void> _chooseSourceFolder() async {
    final path = await FilePicker.getDirectoryPath(
      dialogTitle: tr(context, 'image_converter_select_folder'),
    );
    if (path != null) await _setSource(path);
  }

  Future<void> _setSource(String path) async {
    if (!mounted) return;
    setState(() {
      _sourcePath = path;
      _basePath = null;
      _baseAnalysis = null;
      _outputPath = null;
      _result = null;
      _progress = null;
      _analyzing = true;
    });
    try {
      final analysis = await _service.analyze(path);
      if (!mounted) return;
      setState(() {
        _analysis = analysis;
        _analyzing = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _analysis = null;
        _analyzing = false;
      });
      _showMessage('${tr(context, 'image_converter_failed')} $error');
    }
  }

  Future<void> _chooseBaseFile() async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['iso'],
      dialogTitle: tr(context, 'image_converter_select_base'),
    );
    final path = result?.files.single.path;
    if (path != null) await _setBase(path);
  }

  Future<void> _chooseBaseFolder() async {
    final path = await FilePicker.getDirectoryPath(
      dialogTitle: tr(context, 'image_converter_select_base'),
    );
    if (path != null) await _setBase(path);
  }

  Future<void> _setBase(String path) async {
    if (!mounted) return;
    setState(() {
      _basePath = path;
      _baseAnalysis = null;
      _result = null;
    });
    try {
      final analysis = await _service.analyze(path);
      if (mounted) setState(() => _baseAnalysis = analysis);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _baseAnalysis = null;
      });
      _showMessage('${tr(context, 'image_converter_failed')} $error');
    }
  }

  Future<void> _chooseOutput() async {
    final source = _sourcePath;
    final defaultName = source == null
        ? 'WinDeployStudio_Converted.iso'
        : '${p.basenameWithoutExtension(source)}_Converted.iso';
    final path = await FilePicker.saveFile(
      dialogTitle: tr(context, 'image_converter_select_output'),
      fileName: defaultName,
      type: FileType.custom,
      allowedExtensions: const ['iso'],
    );
    if (path != null && mounted) {
      setState(() {
        _outputPath = p.extension(path).toLowerCase() == '.iso'
            ? path
            : '$path.iso';
        _result = null;
      });
    }
  }

  bool get _canConvert {
    final analysis = _analysis;
    if (_running || _analyzing || analysis == null || !analysis.supported) {
      return false;
    }
    if (_outputPath == null || _outputPath!.trim().isEmpty) return false;
    if (analysis.requiresBaseMedia &&
        (_basePath == null || _baseAnalysis?.supported != true)) {
      return false;
    }
    return ImageConversionService.validateVolumeLabel(_labelController.text) ==
        null;
  }

  Future<void> _convert() async {
    final analysis = _analysis;
    final source = _sourcePath;
    final output = _outputPath;
    if (analysis == null || source == null || output == null || !_canConvert) {
      return;
    }
    final cancellation = ImageConversionCancellationToken();
    setState(() {
      _running = true;
      _result = null;
      _cancellation = cancellation;
      _progress = const ImageConversionProgress(
        stepKey: 'image_converter_step_preflight',
        percent: 0,
      );
    });
    final result = await _service.convert(
      ImageConversionRequest(
        sourcePath: source,
        sourceKind: analysis.kind,
        baseMediaPath: _basePath,
        outputPath: output,
        volumeLabel: _labelController.text.trim(),
      ),
      cancellationToken: cancellation,
      onProgress: (progress) {
        if (mounted) setState(() => _progress = progress);
      },
    );
    if (!mounted) return;
    setState(() {
      _running = false;
      _cancellation = null;
      _result = result;
      if (result.success && result.outputPath != null) {
        _outputPath = result.outputPath;
      }
    });
    if (!result.success && !result.cancelled) {
      _showMessage(
        '${tr(context, result.errorKey ?? 'image_converter_failed')}'
        '${result.errorDetail == null || result.errorDetail!.trim().isEmpty ? '' : '\n${result.errorDetail}'}',
      );
    }
  }

  void _cancel() {
    _cancellation?.cancel();
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  void _copyHash() {
    final hash = _result?.sha256;
    if (hash == null || hash.isEmpty) return;
    unawaited(Clipboard.setData(ClipboardData(text: hash)));
    _showMessage(tr(context, 'image_converter_hash_copied'));
  }

  void _openTarget(String target) {
    final output = _result?.outputPath;
    if (output == null || output.isEmpty) return;
    context.go(Uri(path: target, queryParameters: {'iso': output}).toString());
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Text(tr(context, 'image_converter_title')),
        leading: IconButton(
          tooltip: tr(context, 'image_converter_return_tools'),
          onPressed: _running
              ? null
              : () => context.go(
                  widget.returnTarget == 'creator'
                      ? '/creator'
                      : widget.returnTarget == 'wtg'
                      ? '/wtg'
                      : '/disk-tools',
                ),
          icon: const Icon(Icons.arrow_back),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 980),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  tr(context, 'image_converter_title'),
                  style: AppTypography.pageTitleWith(colors.onSurface),
                ),
                const SizedBox(height: 6),
                Text(
                  tr(context, 'image_converter_subtitle'),
                  style: AppTypography.bodyWith(colors.onSurfaceVariant),
                ),
                const SizedBox(height: 18),
                _Notice(
                  icon: Icons.verified_user_outlined,
                  color: colors.primary,
                  text: tr(context, 'image_converter_notice'),
                ),
                const SizedBox(height: 10),
                _Notice(
                  icon: Icons.info_outline,
                  color: colors.tertiary,
                  text: tr(context, 'image_converter_linux_notice'),
                ),
                const SizedBox(height: 20),
                _buildSourceCard(colors),
                const SizedBox(height: 14),
                if (_analysis?.requiresBaseMedia == true) ...[
                  _buildBaseCard(colors),
                  const SizedBox(height: 14),
                ],
                _buildOutputCard(colors),
                const SizedBox(height: 14),
                _buildActionCard(colors),
                if (_result != null) ...[
                  const SizedBox(height: 14),
                  _buildResultCard(colors),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSourceCard(ColorScheme colors) {
    final analysis = _analysis;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              tr(context, 'image_converter_source'),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 10),
            Text(
              _sourcePath ?? tr(context, 'image_converter_source_placeholder'),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: _running ? null : _chooseImage,
                  icon: const Icon(Icons.insert_drive_file_outlined),
                  label: Text(tr(context, 'image_converter_select_file')),
                ),
                OutlinedButton.icon(
                  onPressed: _running ? null : _chooseSourceFolder,
                  icon: const Icon(Icons.folder_outlined),
                  label: Text(tr(context, 'image_converter_select_folder')),
                ),
              ],
            ),
            if (_analyzing) ...[
              const SizedBox(height: 14),
              const LinearProgressIndicator(),
            ],
            if (analysis != null && !_analyzing) ...[
              const SizedBox(height: 12),
              _StatusLine(
                icon: analysis.supported
                    ? Icons.check_circle_outline
                    : Icons.info_outline,
                color: analysis.supported ? colors.primary : colors.tertiary,
                text: tr(context, analysis.messageKey),
              ),
              const SizedBox(height: 6),
              Text(
                tr(context, _kindKey(analysis.kind)),
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant),
              ),
              if (analysis.detail != null &&
                  analysis.detail!.trim().isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  analysis.detail!,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildBaseCard(ColorScheme colors) {
    final analysis = _baseAnalysis;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              tr(context, 'image_converter_base'),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 6),
            Text(
              tr(context, 'image_converter_base_placeholder'),
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant),
            ),
            const SizedBox(height: 10),
            Text(
              _basePath ?? tr(context, 'image_converter_base_placeholder'),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: _running ? null : _chooseBaseFile,
                  icon: const Icon(Icons.album_outlined),
                  label: Text(tr(context, 'image_converter_select_file')),
                ),
                OutlinedButton.icon(
                  onPressed: _running ? null : _chooseBaseFolder,
                  icon: const Icon(Icons.folder_outlined),
                  label: Text(tr(context, 'image_converter_select_folder')),
                ),
              ],
            ),
            if (analysis != null) ...[
              const SizedBox(height: 10),
              _StatusLine(
                icon: analysis.supported
                    ? Icons.check_circle_outline
                    : Icons.error_outline,
                color: analysis.supported ? colors.primary : colors.error,
                text: tr(context, analysis.messageKey),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildOutputCard(ColorScheme colors) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              tr(context, 'image_converter_output'),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 10),
            Text(
              _outputPath ?? tr(context, 'image_converter_output_placeholder'),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 10),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: OutlinedButton.icon(
                onPressed: _running ? null : _chooseOutput,
                icon: const Icon(Icons.save_outlined),
                label: Text(tr(context, 'image_converter_select_output')),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _labelController,
              enabled: !_running,
              decoration: InputDecoration(
                labelText: tr(context, 'image_converter_label'),
                helperText: tr(context, 'image_converter_label_hint'),
                errorText:
                    ImageConversionService.validateVolumeLabel(
                          _labelController.text,
                        ) ==
                        null
                    ? null
                    : tr(
                        context,
                        ImageConversionService.validateVolumeLabel(
                          _labelController.text,
                        )!,
                      ),
              ),
              onChanged: (_) => setState(() {}),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionCard(ColorScheme colors) {
    final progress = _progress;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_running && progress != null) ...[
              Row(
                children: [
                  const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  const SizedBox(width: 10),
                  Expanded(child: Text(tr(context, progress.stepKey))),
                  Text('${progress.percent}%'),
                ],
              ),
              const SizedBox(height: 12),
              LinearProgressIndicator(
                value: progress.percent > 0 ? progress.percent / 100 : null,
              ),
              const SizedBox(height: 14),
            ],
            Row(
              children: [
                FilledButton.icon(
                  onPressed: _canConvert ? _convert : null,
                  icon: const Icon(Icons.auto_fix_high_outlined),
                  label: Text(tr(context, 'image_converter_convert')),
                ),
                if (_running) ...[
                  const SizedBox(width: 10),
                  OutlinedButton.icon(
                    onPressed: _cancel,
                    icon: const Icon(Icons.stop_circle_outlined),
                    label: Text(tr(context, 'image_converter_cancel')),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildResultCard(ColorScheme colors) {
    final result = _result!;
    if (result.cancelled) return const SizedBox.shrink();
    if (!result.success) {
      return Card(
        color: colors.errorContainer,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: _StatusLine(
            icon: Icons.error_outline,
            color: colors.onErrorContainer,
            text: tr(context, result.errorKey ?? 'image_converter_failed'),
          ),
        ),
      );
    }
    return Card(
      color: colors.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.verified_outlined, color: colors.onPrimaryContainer),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    tr(context, 'image_converter_result_title'),
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: colors.onPrimaryContainer,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Text(
              '${tr(context, 'image_converter_result_size')}: ${_formatBytes(result.outputBytes)}',
              style: TextStyle(color: colors.onPrimaryContainer),
            ),
            const SizedBox(height: 6),
            SelectableText(
              '${tr(context, 'image_converter_result_sha256')}: ${result.sha256}',
              style: TextStyle(color: colors.onPrimaryContainer),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              children: [
                if (result.hasBiosBoot)
                  Chip(label: Text(tr(context, 'image_converter_result_bios'))),
                if (result.hasUefiBoot)
                  Chip(label: Text(tr(context, 'image_converter_result_uefi'))),
              ],
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: _copyHash,
                  icon: const Icon(Icons.copy),
                  label: Text(tr(context, 'image_converter_result_copy_hash')),
                ),
                FilledButton.icon(
                  onPressed: () => _openTarget('/creator'),
                  icon: const Icon(Icons.usb_outlined),
                  label: Text(tr(context, 'image_converter_use_creator')),
                ),
                FilledButton.tonalIcon(
                  onPressed: () => _openTarget('/wtg'),
                  icon: const Icon(Icons.computer_outlined),
                  label: Text(tr(context, 'image_converter_use_wtg')),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  static String _kindKey(ImageConversionSourceKind kind) => switch (kind) {
    ImageConversionSourceKind.setupDirectory =>
      'image_converter_kind_setup_directory',
    ImageConversionSourceKind.wim => 'image_converter_kind_wim',
    ImageConversionSourceKind.esd => 'image_converter_kind_esd',
    ImageConversionSourceKind.swm => 'image_converter_kind_swm',
    ImageConversionSourceKind.vhd => 'image_converter_kind_vhd',
    ImageConversionSourceKind.vhdx => 'image_converter_kind_vhdx',
    _ => 'image_converter_kind_setup_directory',
  };

  static String _formatBytes(int bytes) {
    if (bytes >= 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
    }
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}

class _Notice extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String text;

  const _Notice({required this.icon, required this.color, required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        border: Border.all(color: color.withValues(alpha: 0.35)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color),
          const SizedBox(width: 10),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }
}

class _StatusLine extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String text;

  const _StatusLine({
    required this.icon,
    required this.color,
    required this.text,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(width: 8),
        Expanded(child: Text(text)),
      ],
    );
  }
}
