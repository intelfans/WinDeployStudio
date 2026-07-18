import '../benchmark/models/benchmark_models.dart';

abstract final class BenchmarkHistoryKeys {
  static const history = 'benchmark_history_title';
  static const historySubtitle = 'benchmark_history_subtitle';
  static const refresh = 'bench_refresh';
  static const filterDates = 'benchmark_history_filter_dates';
  static const clearDates = 'benchmark_history_clear_dates';
  static const compare = 'benchmark_history_compare';
  static const export = 'benchmark_history_export';
  static const exportCsv = 'benchmark_history_export_csv';
  static const exportJson = 'benchmark_history_export_json';
  static const exportHtml = 'benchmark_history_export_html';
  static const exportComplete = 'benchmark_history_export_complete';
  static const delete = 'benchmark_history_delete';
  static const deleteSelected = 'benchmark_history_delete_selected';
  static const deleteRange = 'benchmark_history_delete_range';
  static const deleteAll = 'benchmark_history_delete_all';
  static const deleteRecordTitle = 'benchmark_history_delete_record_title';
  static const deleteRangeTitle = 'benchmark_history_delete_range_title';
  static const deleteAllTitle = 'benchmark_history_delete_all_title';
  static const deleteRecordBody = 'benchmark_history_delete_record_body';
  static const deleteRangeBody = 'benchmark_history_delete_range_body';
  static const deleteAllBody = 'benchmark_history_delete_all_body';
  static const deleteSelectedTitle = 'benchmark_history_delete_selected_title';
  static const deleteSelectedBody = 'benchmark_history_delete_selected_body';
  static const cancel = 'detail_cancel';
  static const confirmDelete = 'benchmark_history_confirm_delete';
  static const empty = 'benchmark_history_empty';
  static const emptySubtitle = 'benchmark_history_empty_subtitle';
  static const loadFailed = 'benchmark_history_load_failed';
  static const actionFailed = 'benchmark_history_action_failed';
  static const selectTwo = 'benchmark_history_select_two';
  static const comparisonSelectTitle =
      'benchmark_history_comparison_select_title';
  static const comparisonSelectHint =
      'benchmark_history_comparison_select_hint';
  static const comparisonSelectionCount =
      'benchmark_history_comparison_selection_count';
  static const sameDeviceOnly = 'benchmark_history_same_device_only';
  static const selectionLimit = 'benchmark_history_selection_limit';
  static const selected = 'benchmark_history_selected';
  static const viewDetails = 'benchmark_history_view_details';
  static const resultDetails = 'benchmark_history_result_details';
  static const deviceIdentity = 'benchmark_history_device_identity';
  static const model = 'benchmark_history_model';
  static const serialNumber = 'benchmark_history_serial';
  static const uniqueId = 'benchmark_history_unique_id';
  static const vidPid = 'benchmark_history_vid_pid';
  static const bus = 'benchmark_history_bus';
  static const capacity = 'benchmark_history_capacity';
  static const completed = 'benchmark_history_completed';
  static const mode = 'benchmark_history_mode';
  static const duration = 'bench_duration';
  static const score = 'bench_score';
  static const sequentialRead = 'benchmark_history_sequential_read';
  static const sequentialWrite = 'bench_seq_write';
  static const randomRead = 'benchmark_history_random_read';
  static const randomWrite = 'benchmark_history_random_write';
  static const iops = 'benchmark_history_iops';
  static const latencyP50 = 'benchmark_history_latency_p50';
  static const latencyP95 = 'benchmark_history_latency_p95';
  static const latencyP99 = 'benchmark_history_latency_p99';
  static const randomReadLatencyP50 =
      'benchmark_history_random_read_latency_p50';
  static const randomReadLatencyP95 =
      'benchmark_history_random_read_latency_p95';
  static const randomReadLatencyP99 =
      'benchmark_history_random_read_latency_p99';
  static const randomWriteLatencyP50 =
      'benchmark_history_random_write_latency_p50';
  static const randomWriteLatencyP95 =
      'benchmark_history_random_write_latency_p95';
  static const randomWriteLatencyP99 =
      'benchmark_history_random_write_latency_p99';
  static const multiThreadPeak = 'benchmark_history_multi_thread_peak';
  static const multiThreadScale = 'benchmark_history_multi_thread_scale';
  static const slcInflection = 'benchmark_history_slc_inflection';
  static const postCacheStable = 'benchmark_history_post_cache';
  static const noCacheInflection = 'benchmark_history_no_cache_inflection';
  static const measurements = 'benchmark_history_measurements';
  static const throughput = 'benchmark_history_throughput';
  static const latency = 'benchmark_history_latency_curve';
  static const baseline = 'benchmark_history_baseline';
  static const candidate = 'benchmark_history_candidate';
  static const difference = 'benchmark_history_difference';
  static const comparison = 'benchmark_history_comparison';
  static const comparisonCurves = 'benchmark_history_comparison_curves';
  static const noSamples = 'benchmark_history_no_samples';
  static const unknown = 'benchmark_history_unknown';
  static const threads = 'benchmark_history_threads';
  static const workloadRandomMixed = 'benchmark_history_workload_random_mixed';
  static const workloadStartup = 'benchmark_history_workload_startup';
  static const workloadBrowser = 'benchmark_history_workload_browser';
  static const workloadWindowsUpdate =
      'benchmark_history_workload_windows_update';
  static const workloadSoftwareInstall =
      'benchmark_history_workload_software_install';
  static const workloadMultitasking = 'benchmark_history_workload_multitasking';
  static const workloadFullSequentialWrite =
      'benchmark_history_workload_full_sequential_write';
  static const fullWriteP10 = 'benchmark_history_full_write_p10';
  static const fullWriteScope = 'benchmark_full_write_scope';

  static String workload(BenchmarkWorkload workload) {
    return switch (workload) {
      BenchmarkWorkload.sequentialRead => sequentialRead,
      BenchmarkWorkload.sequentialWrite => sequentialWrite,
      BenchmarkWorkload.random4kRead => randomRead,
      BenchmarkWorkload.random4kWrite => randomWrite,
      BenchmarkWorkload.random4kMultiThread => workloadRandomMixed,
      BenchmarkWorkload.startup => workloadStartup,
      BenchmarkWorkload.browser => workloadBrowser,
      BenchmarkWorkload.windowsUpdate => workloadWindowsUpdate,
      BenchmarkWorkload.softwareInstall => workloadSoftwareInstall,
      BenchmarkWorkload.multitasking => workloadMultitasking,
      BenchmarkWorkload.fullSequentialWrite => workloadFullSequentialWrite,
    };
  }
}

const benchmarkHistoryLocalizationKeys = <String>[
  BenchmarkHistoryKeys.history,
  BenchmarkHistoryKeys.historySubtitle,
  BenchmarkHistoryKeys.filterDates,
  BenchmarkHistoryKeys.clearDates,
  BenchmarkHistoryKeys.compare,
  BenchmarkHistoryKeys.export,
  BenchmarkHistoryKeys.exportCsv,
  BenchmarkHistoryKeys.exportJson,
  BenchmarkHistoryKeys.exportHtml,
  BenchmarkHistoryKeys.exportComplete,
  BenchmarkHistoryKeys.delete,
  BenchmarkHistoryKeys.deleteSelected,
  BenchmarkHistoryKeys.deleteRange,
  BenchmarkHistoryKeys.deleteAll,
  BenchmarkHistoryKeys.deleteRecordTitle,
  BenchmarkHistoryKeys.deleteRangeTitle,
  BenchmarkHistoryKeys.deleteAllTitle,
  BenchmarkHistoryKeys.deleteRecordBody,
  BenchmarkHistoryKeys.deleteRangeBody,
  BenchmarkHistoryKeys.deleteAllBody,
  BenchmarkHistoryKeys.deleteSelectedTitle,
  BenchmarkHistoryKeys.deleteSelectedBody,
  BenchmarkHistoryKeys.confirmDelete,
  BenchmarkHistoryKeys.empty,
  BenchmarkHistoryKeys.emptySubtitle,
  BenchmarkHistoryKeys.loadFailed,
  BenchmarkHistoryKeys.actionFailed,
  BenchmarkHistoryKeys.selectTwo,
  BenchmarkHistoryKeys.comparisonSelectTitle,
  BenchmarkHistoryKeys.comparisonSelectHint,
  BenchmarkHistoryKeys.comparisonSelectionCount,
  BenchmarkHistoryKeys.sameDeviceOnly,
  BenchmarkHistoryKeys.selectionLimit,
  BenchmarkHistoryKeys.selected,
  BenchmarkHistoryKeys.viewDetails,
  BenchmarkHistoryKeys.resultDetails,
  BenchmarkHistoryKeys.deviceIdentity,
  BenchmarkHistoryKeys.model,
  BenchmarkHistoryKeys.serialNumber,
  BenchmarkHistoryKeys.uniqueId,
  BenchmarkHistoryKeys.vidPid,
  BenchmarkHistoryKeys.bus,
  BenchmarkHistoryKeys.capacity,
  BenchmarkHistoryKeys.completed,
  BenchmarkHistoryKeys.mode,
  BenchmarkHistoryKeys.sequentialRead,
  BenchmarkHistoryKeys.randomRead,
  BenchmarkHistoryKeys.randomWrite,
  BenchmarkHistoryKeys.iops,
  BenchmarkHistoryKeys.latencyP50,
  BenchmarkHistoryKeys.latencyP95,
  BenchmarkHistoryKeys.latencyP99,
  BenchmarkHistoryKeys.randomReadLatencyP50,
  BenchmarkHistoryKeys.randomReadLatencyP95,
  BenchmarkHistoryKeys.randomReadLatencyP99,
  BenchmarkHistoryKeys.randomWriteLatencyP50,
  BenchmarkHistoryKeys.randomWriteLatencyP95,
  BenchmarkHistoryKeys.randomWriteLatencyP99,
  BenchmarkHistoryKeys.multiThreadPeak,
  BenchmarkHistoryKeys.multiThreadScale,
  BenchmarkHistoryKeys.slcInflection,
  BenchmarkHistoryKeys.postCacheStable,
  BenchmarkHistoryKeys.noCacheInflection,
  BenchmarkHistoryKeys.measurements,
  BenchmarkHistoryKeys.throughput,
  BenchmarkHistoryKeys.latency,
  BenchmarkHistoryKeys.baseline,
  BenchmarkHistoryKeys.candidate,
  BenchmarkHistoryKeys.difference,
  BenchmarkHistoryKeys.comparison,
  BenchmarkHistoryKeys.comparisonCurves,
  BenchmarkHistoryKeys.noSamples,
  BenchmarkHistoryKeys.unknown,
  BenchmarkHistoryKeys.threads,
  BenchmarkHistoryKeys.workloadRandomMixed,
  BenchmarkHistoryKeys.workloadStartup,
  BenchmarkHistoryKeys.workloadBrowser,
  BenchmarkHistoryKeys.workloadWindowsUpdate,
  BenchmarkHistoryKeys.workloadSoftwareInstall,
  BenchmarkHistoryKeys.workloadMultitasking,
  BenchmarkHistoryKeys.workloadFullSequentialWrite,
  BenchmarkHistoryKeys.fullWriteP10,
  BenchmarkHistoryKeys.fullWriteScope,
];
