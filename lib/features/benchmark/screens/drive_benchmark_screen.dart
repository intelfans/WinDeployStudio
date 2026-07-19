import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/localization/strings.dart';
import '../../../core/services/disk_safety_service.dart';
import '../../logs/services/log_center_service.dart';
import '../../benchmark_history/benchmark_history_copy.dart';
import '../../benchmark_history/widgets/benchmark_workload_chart.dart';
import '../../../shared/widgets/app_navigation_shell.dart';
import '../models/benchmark_models.dart';
import '../services/benchmark_error_localization.dart';
import '../services/native_drive_benchmark_service.dart';

class DriveBenchmarkScreen extends ConsumerStatefulWidget {
  const DriveBenchmarkScreen({super.key});

  @override
  ConsumerState<DriveBenchmarkScreen> createState() =>
      _DriveBenchmarkScreenState();
}

class _DriveBenchmarkScreenState extends ConsumerState<DriveBenchmarkScreen> {
  final _logCenter = LogCenterService();
  List<DiskInfo> _disks = [];
  DiskInfo? _selectedDisk;
  BenchmarkMode _mode = BenchmarkMode.standard;
  BenchmarkProgress? _progress;
  BenchmarkResult? _result;
  BenchmarkCancelToken? _cancelToken;
  bool _isDetecting = true;
  bool _isRunning = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _detectDisks();
  }

  @override
  void dispose() {
    _cancelToken?.cancel();
    super.dispose();
  }

  Future<void> _detectDisks() async {
    setState(() {
      _isDetecting = true;
      _error = null;
    });
    try {
      final disks = await ref
          .read(diskSafetyServiceProvider)
          .getRemovableDisks();
      if (!mounted) return;
      setState(() {
        _disks = disks;
        if (_selectedDisk == null && disks.isNotEmpty) {
          _selectedDisk = disks.first;
        } else if (_selectedDisk != null &&
            !disks.any((d) => d.diskNumber == _selectedDisk!.diskNumber)) {
          _selectedDisk = disks.isEmpty ? null : disks.first;
        }
        _isDetecting = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isDetecting = false;
        _error = e.toString();
      });
    }
  }

  Future<void> _startBenchmark() async {
    final disk = _selectedDisk;
    if (disk == null || _isRunning) return;
    if (_driveRoot(disk) == null) {
      setState(() => _error = 'bench_error_no_drive_letter');
      return;
    }
    if (_mode == BenchmarkMode.fullWrite) {
      final confirmed = await _confirmFullWrite();
      if (confirmed != true) return;
    }

    final token = BenchmarkCancelToken();
    setState(() {
      _cancelToken = token;
      _isRunning = true;
      _progress = null;
      _result = null;
      _error = null;
    });

    await _logCenter.logBenchmark(
      '[DriveBenchmark]\nDisk=${disk.diskNumber}\nMode=${_mode.name}\nStatus=Started',
    );

    try {
      final result = await ref
          .read(driveBenchmarkServiceProvider)
          .run(
            disk: disk,
            mode: _mode,
            cancelToken: token,
            onProgress: (progress) {
              if (!mounted) return;
              setState(() => _progress = progress);
            },
          );
      if (!mounted) return;
      setState(() {
        _result = result;
        _isRunning = false;
        _cancelToken = null;
        _error = result.historySaveFailed
            ? _historySaveFailureText(context)
            : null;
      });
      await _logCenter.logBenchmark(_buildReport(result));
    } on BenchmarkCancelledException {
      if (!mounted) return;
      setState(() {
        _isRunning = false;
        _cancelToken = null;
        _progress = const BenchmarkProgress(
          phase: BenchmarkPhase.cancelled,
          progress: 0,
          elapsed: Duration.zero,
          messageKey: 'bench_msg_cancelled',
        );
      });
      await _logCenter.logBenchmark(
        '[DriveBenchmark]\nDisk=${disk.diskNumber}\nMode=${_mode.name}\nStatus=Cancelled',
      );
    } catch (e) {
      if (!mounted) return;
      final text = e is StateError ? e.message : e.toString();
      setState(() {
        _isRunning = false;
        _cancelToken = null;
        _error = text;
      });
      await _logCenter.logBenchmark(
        '[DriveBenchmark]\nDisk=${disk.diskNumber}\nMode=${_mode.name}\nStatus=Failed\nError=$text',
      );
    }
  }

  void _cancelBenchmark() {
    _cancelToken?.cancel();
  }

  Future<bool?> _confirmFullWrite() {
    final root = _selectedDisk == null ? '' : _driveRoot(_selectedDisk!);
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(tr(context, 'bench_full_confirm_title')),
        content: Text(
          '${tr(context, 'bench_full_confirm_desc')}\n\n'
          '${_fullWriteScopeText(context, root ?? '')}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(tr(context, 'detail_cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(tr(context, 'bench_full_confirm_start')),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      body: LayoutBuilder(
        builder: (context, constraints) {
          final isWide = constraints.maxWidth >= 1180;
          return SingleChildScrollView(
            padding: EdgeInsets.all(isWide ? 32 : 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildHeader(context, colorScheme),
                const SizedBox(height: 24),
                if (isWide)
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(width: 380, child: _buildControlColumn(context)),
                      const SizedBox(width: 24),
                      Expanded(child: _buildResultColumn(context)),
                    ],
                  )
                else
                  Column(
                    children: [
                      _buildControlColumn(context),
                      const SizedBox(height: 20),
                      _buildResultColumn(context),
                    ],
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildHeader(BuildContext context, ColorScheme colorScheme) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 58,
          height: 58,
          decoration: BoxDecoration(
            color: colorScheme.primaryContainer.withValues(alpha: 0.72),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: colorScheme.outlineVariant),
          ),
          child: Icon(
            Icons.monitor_heart_outlined,
            color: colorScheme.onPrimaryContainer,
            size: 31,
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                tr(context, 'bench_title'),
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                tr(context, 'bench_subtitle'),
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          alignment: WrapAlignment.end,
          children: [
            OutlinedButton.icon(
              key: AppNavigationKeys.benchmarkHistoryKey,
              onPressed: () => context.go('/benchmark/history'),
              icon: const Icon(Icons.history_rounded),
              label: Text(tr(context, BenchmarkHistoryKeys.history)),
            ),
            OutlinedButton.icon(
              onPressed: _isRunning ? null : _detectDisks,
              icon: const Icon(Icons.refresh_rounded),
              label: Text(tr(context, 'bench_refresh')),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildControlColumn(BuildContext context) {
    return Column(
      children: [
        _Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _SectionHeader(
                icon: Icons.storage_rounded,
                title: tr(context, 'bench_target_disk'),
                trailing: _isDetecting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : null,
              ),
              const SizedBox(height: 14),
              if (_isDetecting)
                _EmptyState(
                  icon: Icons.usb_rounded,
                  title: tr(context, 'bench_detecting'),
                )
              else if (_disks.isEmpty)
                _EmptyState(
                  icon: Icons.usb_off_rounded,
                  title: tr(context, 'bench_no_disk'),
                  subtitle: tr(context, 'bench_no_disk_desc'),
                )
              else
                ..._disks.map(_buildDiskTile),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _SectionHeader(
                icon: Icons.tune_rounded,
                title: tr(context, 'bench_test_mode'),
              ),
              const SizedBox(height: 14),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: SegmentedButton<BenchmarkMode>(
                  showSelectedIcon: false,
                  segments: BenchmarkMode.values
                      .map(
                        (mode) => ButtonSegment(
                          value: mode,
                          label: Text(
                            tr(context, mode.titleKey),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      )
                      .toList(),
                  selected: {_mode},
                  onSelectionChanged: _isRunning
                      ? null
                      : (value) => setState(() => _mode = value.first),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                tr(context, _mode.descriptionKey),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              if (_mode == BenchmarkMode.fullWrite) ...[
                const SizedBox(height: 12),
                _Notice(
                  icon: Icons.warning_amber_rounded,
                  text: tr(context, 'bench_full_warning'),
                  color: Theme.of(context).colorScheme.error,
                ),
                const SizedBox(height: 8),
                Text(
                  _fullWriteScopeText(
                    context,
                    _selectedDisk == null
                        ? ''
                        : _driveRoot(_selectedDisk!) ?? '',
                  ),
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w700),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 16),
        _Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_error != null) ...[
                _Notice(
                  icon: Icons.error_outline_rounded,
                  text: _localizedError(context, _error!),
                  color: Theme.of(context).colorScheme.error,
                ),
                const SizedBox(height: 12),
              ],
              if (_isRunning)
                FilledButton.icon(
                  onPressed: _cancelBenchmark,
                  icon: const Icon(Icons.stop_rounded),
                  label: Text(tr(context, 'bench_stop')),
                )
              else
                FilledButton.icon(
                  onPressed: _selectedDisk == null ? null : _startBenchmark,
                  icon: const Icon(Icons.play_arrow_rounded),
                  label: Text(tr(context, 'bench_start')),
                ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: () => context.go('/wtg'),
                icon: const Icon(Icons.computer_rounded),
                label: Text(tr(context, 'bench_open_togo')),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildDiskTile(DiskInfo disk) {
    final selected = _selectedDisk?.diskNumber == disk.diskNumber;
    final colorScheme = Theme.of(context).colorScheme;
    final drive = _driveRoot(disk);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: _isRunning ? null : () => setState(() => _selectedDisk = disk),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: selected
                ? colorScheme.primaryContainer.withValues(alpha: 0.24)
                : colorScheme.surfaceContainerHighest.withValues(alpha: 0.38),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: selected
                  ? colorScheme.primary
                  : colorScheme.outlineVariant,
            ),
          ),
          child: Row(
            children: [
              Icon(
                Icons.usb_rounded,
                color: selected
                    ? colorScheme.primary
                    : colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      disk.friendlyName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '${disk.sizeFormatted} • ${disk.busType} • ${drive ?? tr(context, 'bench_no_drive_letter')}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              if (selected)
                Icon(Icons.check_circle_rounded, color: colorScheme.primary),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildResultColumn(BuildContext context) {
    final progress = _progress;
    final result = _result;
    return Column(
      children: [
        _Panel(
          child: result != null
              ? _buildResultSummary(context, result)
              : _buildLiveSummary(context, progress),
        ),
        const SizedBox(height: 16),
        _buildCharts(context, result, progress),
      ],
    );
  }

  Widget _buildLiveSummary(BuildContext context, BenchmarkProgress? progress) {
    final colorScheme = Theme.of(context).colorScheme;
    final phase = progress?.phase ?? BenchmarkPhase.idle;
    final titleKey = progress?.workload?.livePhaseTitleKey ?? phase.titleKey;
    final progressValue = progress?.progress ?? 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            SizedBox(
              width: 72,
              height: 72,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  CircularProgressIndicator(
                    value: _isRunning ? progressValue : 0,
                    strokeWidth: 7,
                    backgroundColor: colorScheme.surfaceContainerHighest,
                  ),
                  Icon(
                    _isRunning
                        ? Icons.speed_rounded
                        : Icons.monitor_heart_outlined,
                    color: colorScheme.primary,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 18),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    tr(context, titleKey),
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    tr(context, progress?.messageKey ?? 'bench_msg_ready'),
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 22),
        Row(
          children: [
            Expanded(
              child: _MetricTile(
                label: tr(context, 'bench_elapsed'),
                value: _formatDuration(progress?.elapsed ?? Duration.zero),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _MetricTile(
                label: tr(context, 'bench_current_speed'),
                value: _formatSpeed(progress?.currentSpeedMBps ?? 0),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _MetricTile(
                label: tr(context, 'bench_progress'),
                value: '${(progressValue * 100).round()}%',
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildResultInsight(
    BuildContext context,
    BenchmarkResult result,
    Color color,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Divider(color: Theme.of(context).colorScheme.outlineVariant),
        const SizedBox(height: 14),
        Wrap(
          spacing: 28,
          runSpacing: 14,
          children: [
            _InsightValue(
              label: tr(context, 'bench_result_overall'),
              value: tr(context, result.suitability.titleKey),
              color: color,
            ),
            _InsightValue(
              label: tr(context, 'bench_result_recommendation'),
              value: tr(context, _recommendationKey(result.suitability)),
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ],
        ),
        const SizedBox(height: 18),
        _InsightList(
          title: tr(context, 'bench_result_reasons'),
          icon: Icons.check_circle_rounded,
          color: color,
          items: _resultReasonKeys(
            result,
          ).map((key) => tr(context, key)).toList(growable: false),
        ),
        const SizedBox(height: 14),
        _InsightList(
          title: tr(context, 'bench_result_notes'),
          icon: Icons.info_rounded,
          color: Theme.of(context).colorScheme.primary,
          items: _resultNoteKeys(
            result,
          ).map((key) => tr(context, key)).toList(growable: false),
        ),
      ],
    );
  }

  Widget _buildResultSummary(BuildContext context, BenchmarkResult result) {
    final color = _ratingColor(result.suitability);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 74,
              height: 74,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: color.withValues(alpha: 0.34)),
              ),
              child: Icon(Icons.verified_rounded, color: color, size: 34),
            ),
            const SizedBox(width: 18),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    tr(context, result.suitability.titleKey),
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w900,
                      color: color,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    tr(context, result.suitability.descriptionKey),
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            OutlinedButton.icon(
              onPressed: () async {
                await Clipboard.setData(
                  ClipboardData(text: _buildReport(result)),
                );
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(tr(context, 'bench_report_copied'))),
                );
              },
              icon: const Icon(Icons.copy_rounded),
              label: Text(tr(context, 'bench_copy_report')),
            ),
          ],
        ),
        const SizedBox(height: 22),
        Row(
          children: [
            Expanded(
              child: _MetricTile(
                label: tr(context, 'bench_score'),
                value: result.score.toStringAsFixed(0),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _MetricTile(
                label: tr(context, 'bench_4k_adjusted'),
                value: _formatSpeed(result.random4kAdjustedMBps),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _MetricTile(
                label: tr(context, 'bench_seq_write'),
                value: _formatSpeed(result.sequentialWriteMBps),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _MetricTile(
                label: tr(context, 'bench_duration'),
                value: result.durationText,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _MetricTile(
                label: tr(context, BenchmarkHistoryKeys.sequentialRead),
                value: _formatSpeed(result.sequentialReadMBps),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _MetricTile(
                label: tr(context, BenchmarkHistoryKeys.randomRead),
                value: '${result.random4kReadIops.toStringAsFixed(0)} IOPS',
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _MetricTile(
                label: tr(context, BenchmarkHistoryKeys.randomWrite),
                value: '${result.random4kWriteIops.toStringAsFixed(0)} IOPS',
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _MetricTile(
                label: tr(context, BenchmarkHistoryKeys.slcInflection),
                value: _slcStatusText(context, result),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _MetricTile(
                label: _threadMetricLabel(context, 'multiplier'),
                value: '${result.multiThreadMultiplier.toStringAsFixed(2)}x',
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _MetricTile(
                label: _threadMetricLabel(context, 'retention'),
                value:
                    '${(result.multiThreadRetention * 100).toStringAsFixed(0)}%',
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _MetricTile(
                label: _threadMetricLabel(context, 'efficiency'),
                value:
                    '${(result.multiThreadNormalizedEfficiency * 100).toStringAsFixed(0)}%',
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _MetricTile(
                label: tr(context, BenchmarkHistoryKeys.fullWriteP10),
                value:
                    result.fullWriteStatus == BenchmarkFullWriteStatus.completed
                    ? _formatSpeed(result.fullWriteP10MBps)
                    : 'N/A',
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        _buildResultInsight(context, result, color),
      ],
    );
  }

  Widget _buildCharts(
    BuildContext context,
    BenchmarkResult? result,
    BenchmarkProgress? progress,
  ) {
    final series = result?.sampleSeries ?? progress?.sampleSeries ?? const [];
    return _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _SectionHeader(
            icon: Icons.query_stats_rounded,
            title: tr(context, BenchmarkHistoryKeys.measurements),
          ),
          const SizedBox(height: 14),
          BenchmarkWorkloadChart(
            primarySeries: series,
            activeWorkload: _isRunning ? progress?.workload : null,
            primarySlcMarkerGB: result?.slcStatus == BenchmarkSlcStatus.detected
                ? result!.slcCacheInflectionGB
                : 0,
          ),
        ],
      ),
    );
  }

  String? _driveRoot(DiskInfo disk) {
    final letter = disk.preferredDriveLetter;
    if (letter == null || letter.isEmpty) return null;
    if (letter.length == 1) return '${letter.toUpperCase()}:\\';
    if (letter.endsWith(':')) return '${letter.toUpperCase()}\\';
    if (letter.endsWith('\\')) return letter;
    return '$letter\\';
  }

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds.remainder(60);
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  String _formatSpeed(double speed) {
    if (speed <= 0) return '--';
    if (speed >= 100) return '${speed.toStringAsFixed(0)} MB/s';
    if (speed >= 10) return '${speed.toStringAsFixed(1)} MB/s';
    return '${speed.toStringAsFixed(2)} MB/s';
  }

  String _fullWriteScopeText(BuildContext context, String driveRoot) {
    final volume = driveRoot.isEmpty ? '--' : driveRoot;
    return tr(
      context,
      BenchmarkHistoryKeys.fullWriteScope,
    ).replaceAll('{volume}', volume);
  }

  String _historySaveFailureText(BuildContext context) {
    if (Localizations.localeOf(context).languageCode == 'zh') {
      return '测试已完成，但历史记录保存失败。';
    }
    return 'The benchmark completed, but its history record could not be saved.';
  }

  String _threadMetricLabel(BuildContext context, String metric) {
    final chinese = Localizations.localeOf(context).languageCode == 'zh';
    return switch (metric) {
      'multiplier' => chinese ? '多线程倍率' : 'Thread multiplier',
      'retention' => chinese ? '峰值保持率' : 'Peak retention',
      _ => chinese ? '归一化效率' : 'Normalized efficiency',
    };
  }

  String _slcStatusText(BuildContext context, BenchmarkResult result) {
    return switch (result.slcStatus) {
      BenchmarkSlcStatus.detected =>
        '${result.slcCacheInflectionGB.toStringAsFixed(2)} GB '
            '(${(result.slcConfidence * 100).toStringAsFixed(0)}%)',
      BenchmarkSlcStatus.noInflection => tr(
        context,
        BenchmarkHistoryKeys.noCacheInflection,
      ),
      BenchmarkSlcStatus.insufficientRange =>
        'N/A (${tr(context, BenchmarkHistoryKeys.noSamples)})',
      BenchmarkSlcStatus.notRun => 'N/A',
    };
  }

  String _localizedError(BuildContext context, String error) {
    return localizeBenchmarkError(
      localeCodeFromLocale(Localizations.localeOf(context)),
      error,
    );
  }

  Color _ratingColor(BenchmarkSuitability suitability) {
    return switch (suitability) {
      BenchmarkSuitability.excellent => const Color(0xFF30D158),
      BenchmarkSuitability.good => const Color(0xFF64D2FF),
      BenchmarkSuitability.usable => const Color(0xFFFFD60A),
      BenchmarkSuitability.limited => const Color(0xFFFF9F0A),
      BenchmarkSuitability.notRecommended => const Color(0xFFFF453A),
      BenchmarkSuitability.unmeasured => Colors.grey,
    };
  }

  String _recommendationKey(BenchmarkSuitability suitability) {
    return switch (suitability) {
      BenchmarkSuitability.excellent => 'bench_recommend_excellent',
      BenchmarkSuitability.good => 'bench_recommend_good',
      BenchmarkSuitability.usable => 'bench_recommend_usable',
      BenchmarkSuitability.limited => 'bench_recommend_limited',
      BenchmarkSuitability.notRecommended => 'bench_recommend_not_recommended',
      BenchmarkSuitability.unmeasured => 'bench_recommend_unmeasured',
    };
  }

  List<String> _resultReasonKeys(BenchmarkResult result) {
    final reasons = <String>[];

    if (result.random4kAdjustedMBps >= 20) {
      reasons.add('bench_reason_4k_strong');
    } else if (result.random4kAdjustedMBps >= 8) {
      reasons.add('bench_reason_4k_stable');
    } else if (result.random4kAdjustedMBps >= 2) {
      reasons.add('bench_reason_4k_limited');
    } else {
      reasons.add('bench_reason_4k_weak');
    }

    final threadHealthy =
        result.multiThreadRetention >= 0.85 &&
        result.multiThreadMultiplier >= 1.25 &&
        result.multiThreadNormalizedEfficiency >= 0.20;
    reasons.add(
      threadHealthy
          ? 'bench_reason_thread_good'
          : 'bench_reason_thread_limited',
    );

    if (result.sequentialWriteMBps >= 150) {
      reasons.add('bench_reason_seq_good');
    } else if (result.sequentialWriteMBps >= 60) {
      reasons.add('bench_reason_seq_acceptable');
    } else {
      reasons.add('bench_reason_seq_slow');
    }

    if (result.fullWriteStatus == BenchmarkFullWriteStatus.completed) {
      reasons.add(
        result.fullWriteDropRatio > 0.55
            ? 'bench_reason_full_drop'
            : 'bench_reason_full_stable',
      );
    }

    return reasons;
  }

  List<String> _resultNoteKeys(BenchmarkResult result) {
    if (result.fullWriteStatus == BenchmarkFullWriteStatus.notRun) {
      return const ['bench_note_full_not_run'];
    }
    if (result.fullWriteStatus == BenchmarkFullWriteStatus.insufficientSpace) {
      return const ['bench_note_full_skipped_low_space'];
    }
    return const ['bench_note_full_ran'];
  }

  String _buildReport(BenchmarkResult result) {
    return '''
[DriveBenchmark]
Disk=${result.disk.diskNumber}
Model=${result.disk.friendlyName}
Drive=${result.driveRoot}
Mode=${result.mode.name}
Rating=${result.suitability.name}
Score=${result.score.toStringAsFixed(1)}
SequentialWrite=${result.sequentialWriteMBps.toStringAsFixed(2)} MB/s
Random4KAverage=${result.random4kAverageMBps.toStringAsFixed(2)} MB/s
Random4KAdjusted=${result.random4kAdjustedMBps.toStringAsFixed(2)} MB/s
Random4KLow=${result.random4kLowMBps.toStringAsFixed(2)} MB/s
Random4KStability=${(result.random4kStability * 100).toStringAsFixed(1)}%
MultiThreadPeak=${result.multiThreadPeakMBps.toStringAsFixed(2)} MB/s
MultiThreadMultiplier=${result.multiThreadMultiplier.toStringAsFixed(2)}x
MultiThreadRetention=${(result.multiThreadRetention * 100).toStringAsFixed(1)}%
MultiThreadNormalizedEfficiency=${(result.multiThreadNormalizedEfficiency * 100).toStringAsFixed(1)}%
FullWriteStatus=${result.fullWriteStatus.name}
FullWriteTargetBytes=${result.fullWriteTargetBytes}
FullWriteP10=${result.fullWriteP10MBps.toStringAsFixed(2)} MB/s
FullWriteEnd=${result.fullWriteEndMBps.toStringAsFixed(2)} MB/s
FullWriteDrop=${(result.fullWriteDropRatio * 100).toStringAsFixed(1)}%
SlcStatus=${result.slcStatus.name}
SlcConfidence=${(result.slcConfidence * 100).toStringAsFixed(1)}%
Duration=${result.durationText}
CompletedAt=${result.completedAt.toIso8601String()}
''';
  }
}

class _Panel extends StatelessWidget {
  final Widget child;

  const _Panel({required this.child});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: child,
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final IconData icon;
  final String title;
  final Widget? trailing;

  const _SectionHeader({
    required this.icon,
    required this.title,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        Icon(icon, size: 20, color: colorScheme.primary),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            title,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
          ),
        ),
        ?trailing,
      ],
    );
  }
}

class _Notice extends StatelessWidget {
  final IconData icon;
  final String text;
  final Color color;

  const _Notice({required this.icon, required this.text, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: color,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;

  const _EmptyState({required this.icon, required this.title, this.subtitle});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 22),
      child: Column(
        children: [
          Icon(icon, size: 42, color: colorScheme.onSurfaceVariant),
          const SizedBox(height: 12),
          Text(
            title,
            textAlign: TextAlign.center,
            style: Theme.of(
              context,
            ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 6),
            Text(
              subtitle!,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _InsightValue extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _InsightValue({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 220, maxWidth: 420),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
              color: color,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class _InsightList extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color color;
  final List<String> items;

  const _InsightList({
    required this.title,
    required this.icon,
    required this.color,
    required this.items,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: theme.textTheme.labelLarge?.copyWith(
            color: colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 8),
        for (final item in items) ...[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: 17, color: color),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  item,
                  style: theme.textTheme.bodyMedium?.copyWith(height: 1.35),
                ),
              ),
            ],
          ),
          if (item != items.last) const SizedBox(height: 6),
        ],
      ],
    );
  }
}

class _MetricTile extends StatelessWidget {
  final String label;
  final String value;

  const _MetricTile({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      constraints: const BoxConstraints(minHeight: 74),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 5),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
            ),
          ),
        ],
      ),
    );
  }
}
