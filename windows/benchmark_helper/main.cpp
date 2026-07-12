#include <windows.h>

#include <algorithm>
#include <atomic>
#include <chrono>
#include <cmath>
#include <cstdint>
#include <cstring>
#include <cwchar>
#include <iomanip>
#include <iostream>
#include <mutex>
#include <numeric>
#include <random>
#include <string>
#include <thread>
#include <utility>
#include <vector>

namespace {

constexpr DWORD kAlignment = 4096;
constexpr std::size_t kSequentialBufferSize = 8 * 1024 * 1024;
constexpr double kMegabyte = 1024.0 * 1024.0;
constexpr double kGigabyte = 1024.0 * kMegabyte;
constexpr int kProtocolVersion = 3;

std::mutex output_mutex;

class ParentLifetimeGuard {
public:
  ParentLifetimeGuard() = default;
  ParentLifetimeGuard(const ParentLifetimeGuard &) = delete;
  ParentLifetimeGuard &operator=(const ParentLifetimeGuard &) = delete;

  ~ParentLifetimeGuard() {
    if (stop_event_ != nullptr) {
      SetEvent(stop_event_);
    }
    if (monitor_.joinable()) {
      monitor_.join();
    }
    if (parent_ != nullptr) {
      CloseHandle(parent_);
    }
    if (stop_event_ != nullptr) {
      CloseHandle(stop_event_);
    }
  }

  bool Start(DWORD parent_pid) {
    if (parent_pid == 0 || parent_pid == GetCurrentProcessId()) {
      return false;
    }
    parent_ = OpenProcess(SYNCHRONIZE | PROCESS_QUERY_LIMITED_INFORMATION,
                          FALSE, parent_pid);
    if (parent_ == nullptr || WaitForSingleObject(parent_, 0) != WAIT_TIMEOUT) {
      return false;
    }
    stop_event_ = CreateEventW(nullptr, TRUE, FALSE, nullptr);
    if (stop_event_ == nullptr) {
      return false;
    }
    monitor_ = std::thread([this]() {
      HANDLE handles[] = {parent_, stop_event_};
      const DWORD result = WaitForMultipleObjects(2, handles, FALSE, INFINITE);
      if (result == WAIT_OBJECT_0) {
        TerminateProcess(GetCurrentProcess(), ERROR_PROCESS_ABORTED);
      }
    });
    return true;
  }

private:
  HANDLE parent_ = nullptr;
  HANDLE stop_event_ = nullptr;
  std::thread monitor_;
};

struct LatencyPercentiles {
  double p50_ms = 0.0;
  double p95_ms = 0.0;
  double p99_ms = 0.0;
};

enum class CacheStatus {
  kNotRun,
  kInsufficientRange,
  kNoInflection,
  kDetected,
};

const char *CacheStatusName(CacheStatus status) {
  switch (status) {
  case CacheStatus::kNotRun:
    return "notRun";
  case CacheStatus::kInsufficientRange:
    return "insufficientRange";
  case CacheStatus::kNoInflection:
    return "noInflection";
  case CacheStatus::kDetected:
    return "detected";
  }
  return "notRun";
}

struct CacheAnalysis {
  CacheStatus status = CacheStatus::kNotRun;
  double inflection_gb = 0.0;
  double stable_mbps = 0.0;
  double confidence = 0.0;
};

struct WorkloadProfile {
  int read_percent = 0;
  std::vector<std::pair<std::size_t, int>> block_distribution;
};

void EmitProtocol() {
  std::lock_guard<std::mutex> lock(output_mutex);
  std::cout << "PROTO|" << kProtocolVersion << std::endl;
}

void EmitState(const char *state, int duration_ms = 0) {
  std::lock_guard<std::mutex> lock(output_mutex);
  std::cout << "STATE|" << state << "|" << duration_ms << std::endl;
}

void EmitProfile(const std::string &name, const WorkloadProfile &profile,
                 int thread_count) {
  std::lock_guard<std::mutex> lock(output_mutex);
  std::cout << "PROFILE|" << name << "|" << profile.read_percent << "|"
            << thread_count << std::endl;
}

void EmitSample(double x_value, double speed_mbps, double iops,
                double read_mbps, double write_mbps,
                const LatencyPercentiles &latency) {
  std::lock_guard<std::mutex> lock(output_mutex);
  std::cout << std::fixed << std::setprecision(6) << "SAMPLE|" << x_value << "|"
            << speed_mbps << "|" << iops << "|" << read_mbps << "|"
            << write_mbps << "|" << latency.p50_ms << "|" << latency.p95_ms
            << "|" << latency.p99_ms << std::endl;
}

void EmitResult(double average_mbps, double low_mbps, double stability,
                std::uint64_t bytes, double iops, double read_mbps,
                double write_mbps, const LatencyPercentiles &latency,
                const CacheAnalysis &cache = {}) {
  std::lock_guard<std::mutex> lock(output_mutex);
  std::cout << std::fixed << std::setprecision(6) << "RESULT|" << average_mbps
            << "|" << low_mbps << "|" << stability << "|" << bytes << "|"
            << iops << "|" << read_mbps << "|" << write_mbps << "|"
            << latency.p50_ms << "|" << latency.p95_ms << "|" << latency.p99_ms
            << "|" << CacheStatusName(cache.status) << "|"
            << cache.inflection_gb << "|" << cache.stable_mbps << "|"
            << cache.confidence << std::endl;
}

void EmitCache(const CacheAnalysis &cache) {
  std::lock_guard<std::mutex> lock(output_mutex);
  std::cout << std::fixed << std::setprecision(6) << "CACHE|"
            << CacheStatusName(cache.status) << "|" << cache.inflection_gb
            << "|" << cache.stable_mbps << "|" << cache.confidence << std::endl;
}

void EmitError(const std::string &message, DWORD error = GetLastError()) {
  std::lock_guard<std::mutex> lock(output_mutex);
  std::cerr << message << " (Win32=" << error << ")" << std::endl;
}

std::uint64_t AlignDown(std::uint64_t value) {
  return value - (value % kAlignment);
}

void *AllocateBuffer(std::size_t length, std::uint32_t seed) {
  auto *buffer = static_cast<std::uint8_t *>(
      VirtualAlloc(nullptr, length, MEM_COMMIT | MEM_RESERVE, PAGE_READWRITE));
  if (buffer == nullptr) {
    return nullptr;
  }
  std::mt19937 generator(seed);
  for (std::size_t offset = 0; offset < length;
       offset += sizeof(std::uint32_t)) {
    const auto value = generator();
    const std::size_t copy_length =
        std::min(sizeof(value), static_cast<std::size_t>(length - offset));
    std::memcpy(buffer + offset, &value, copy_length);
  }
  return buffer;
}

HANDLE OpenUnbufferedFile(const std::wstring &path, DWORD creation,
                          DWORD desired_access, DWORD access_flags) {
  // Read-only stages must remain usable on volumes where the caller cannot
  // obtain write access. Write-through is only meaningful for write handles.
  DWORD attributes = FILE_ATTRIBUTE_NORMAL | FILE_FLAG_NO_BUFFERING |
                     access_flags;
  if ((desired_access & GENERIC_WRITE) != 0) {
    attributes |= FILE_FLAG_WRITE_THROUGH;
  }
  return CreateFileW(path.c_str(), desired_access,
                     FILE_SHARE_READ | FILE_SHARE_WRITE, nullptr, creation,
                     attributes,
                     nullptr);
}

bool SeekFile(HANDLE file, std::uint64_t offset) {
  LARGE_INTEGER position{};
  position.QuadPart = static_cast<LONGLONG>(offset);
  return SetFilePointerEx(file, position, nullptr, FILE_BEGIN) != FALSE;
}

double Average(const std::vector<double> &values) {
  if (values.empty()) {
    return 0.0;
  }
  return std::accumulate(values.begin(), values.end(), 0.0) /
         static_cast<double>(values.size());
}

double Percentile(std::vector<double> values, double percentile) {
  if (values.empty()) {
    return 0.0;
  }
  std::sort(values.begin(), values.end());
  const double position =
      static_cast<double>(values.size() - 1) * std::clamp(percentile, 0.0, 1.0);
  const auto lower = static_cast<std::size_t>(std::floor(position));
  const auto upper = static_cast<std::size_t>(std::ceil(position));
  if (lower == upper) {
    return values[lower];
  }
  const double fraction = position - static_cast<double>(lower);
  return values[lower] + (values[upper] - values[lower]) * fraction;
}

LatencyPercentiles CalculateLatency(const std::vector<double> &values) {
  return {Percentile(values, 0.50), Percentile(values, 0.95),
          Percentile(values, 0.99)};
}

CacheAnalysis AnalyzeCache(const std::vector<double> &x_values,
                           const std::vector<double> &speeds) {
  CacheAnalysis analysis{CacheStatus::kInsufficientRange};
  if (speeds.size() < 16 || x_values.size() != speeds.size() ||
      x_values.empty() || x_values.back() < 4.0) {
    const double range_evidence =
        x_values.empty() ? 0.0 : std::clamp(x_values.back() / 4.0, 0.0, 1.0);
    const double sample_evidence =
        std::clamp(static_cast<double>(speeds.size()) / 16.0, 0.0, 1.0);
    analysis.confidence = std::min(range_evidence, sample_evidence) * 0.45;
    return analysis;
  }
  const std::size_t baseline_count =
      std::min<std::size_t>(6, std::max<std::size_t>(4, speeds.size() / 8));
  std::vector<double> baseline_values(speeds.begin(),
                                      speeds.begin() + baseline_count);
  const double baseline = Percentile(baseline_values, 0.50);
  if (baseline <= 0.0) {
    return analysis;
  }
  constexpr std::size_t kPostWindow = 6;
  for (std::size_t index = baseline_count; index + kPostWindow <= speeds.size();
       ++index) {
    std::vector<double> post_window(speeds.begin() + index,
                                    speeds.begin() + index + kPostWindow);
    const double post_median = Percentile(post_window, 0.50);
    const double drop = baseline - post_median;
    const double drop_ratio = drop / baseline;
    const auto sustained_low = static_cast<std::size_t>(std::count_if(
        post_window.begin(), post_window.end(),
        [baseline](double speed) { return speed <= baseline * 0.72; }));
    if (drop < std::max(25.0, baseline * 0.25) || drop_ratio < 0.28 ||
        speeds[index] > baseline * 0.72 || sustained_low < kPostWindow - 1) {
      continue;
    }

    std::vector<double> post_cache(speeds.begin() + index + 1, speeds.end());
    const double stable = Percentile(post_cache, 0.50);
    std::vector<double> deviations;
    deviations.reserve(post_cache.size());
    for (const double speed : post_cache) {
      deviations.push_back(std::abs(speed - stable));
    }
    const double relative_mad =
        stable <= 0.0 ? 1.0 : Percentile(deviations, 0.50) / stable;
    const double drop_evidence =
        std::clamp((drop_ratio - 0.25) / 0.40, 0.0, 1.0);
    const double persistence_evidence =
        std::clamp(static_cast<double>(post_cache.size()) / 16.0, 0.0, 1.0);
    const double stability_evidence =
        std::clamp(1.0 - relative_mad * 2.0, 0.0, 1.0);
    const double confidence = drop_evidence * 0.55 +
                              persistence_evidence * 0.25 +
                              stability_evidence * 0.20;
    if (confidence >= 0.55) {
      return {CacheStatus::kDetected, x_values[index], stable,
              std::clamp(confidence, 0.0, 1.0)};
    }
  }

  std::vector<double> deviations;
  deviations.reserve(baseline_values.size());
  for (const double speed : baseline_values) {
    deviations.push_back(std::abs(speed - baseline));
  }
  const double baseline_mad = Percentile(deviations, 0.50);
  const double stability_evidence =
      std::clamp(1.0 - (baseline_mad / baseline) * 2.0, 0.0, 1.0);
  const double coverage_evidence =
      std::clamp(x_values.back() / 16.0, 0.25, 1.0);
  return {
      CacheStatus::kNoInflection, 0.0, 0.0,
      std::clamp(0.55 + stability_evidence * 0.25 + coverage_evidence * 0.20,
                 0.0, 1.0)};
}

bool SleepChecked(int duration_ms, const std::atomic<bool> *failed = nullptr) {
  int remaining = std::max(0, duration_ms);
  while (remaining > 0) {
    if (failed != nullptr && failed->load(std::memory_order_relaxed)) {
      return false;
    }
    const int interval = std::min(remaining, 50);
    Sleep(static_cast<DWORD>(interval));
    remaining -= interval;
  }
  return failed == nullptr || !failed->load(std::memory_order_relaxed);
}

bool EnsurePreparedFile(const std::wstring &path, std::uint64_t size) {
  size = AlignDown(size);
  HANDLE existing =
      OpenUnbufferedFile(path, OPEN_EXISTING, GENERIC_READ,
                         FILE_FLAG_RANDOM_ACCESS);
  if (existing != INVALID_HANDLE_VALUE) {
    LARGE_INTEGER existing_size{};
    const bool ready =
        GetFileSizeEx(existing, &existing_size) != FALSE &&
        static_cast<std::uint64_t>(existing_size.QuadPart) >= size;
    CloseHandle(existing);
    if (ready) {
      return true;
    }
  }

  EmitState("PREPARING");
  HANDLE file =
      OpenUnbufferedFile(path, CREATE_ALWAYS, GENERIC_READ | GENERIC_WRITE,
                         FILE_FLAG_SEQUENTIAL_SCAN);
  if (file == INVALID_HANDLE_VALUE) {
    EmitError("Unable to create benchmark data file");
    return false;
  }
  void *buffer = AllocateBuffer(kSequentialBufferSize, GetTickCount());
  if (buffer == nullptr) {
    EmitError("Unable to allocate aligned preparation buffer");
    CloseHandle(file);
    return false;
  }

  bool success = true;
  std::uint64_t written = 0;
  while (written < size) {
    const DWORD chunk = static_cast<DWORD>(
        std::min<std::uint64_t>(kSequentialBufferSize, size - written));
    DWORD bytes_written = 0;
    if (!WriteFile(file, buffer, chunk, &bytes_written, nullptr) ||
        bytes_written != chunk) {
      EmitError("Unable to initialize benchmark data file");
      success = false;
      break;
    }
    written += bytes_written;
  }
  if (success && !FlushFileBuffers(file)) {
    EmitError("Unable to flush benchmark data file");
    success = false;
  }
  VirtualFree(buffer, 0, MEM_RELEASE);
  CloseHandle(file);
  return success;
}

int RunSequentialV3(const std::wstring &path, bool read_test, int seconds,
                    std::uint64_t max_bytes, int warmup_ms, int cooldown_ms,
                    bool full_write) {
  max_bytes -= max_bytes % kSequentialBufferSize;
  if ((!full_write && seconds <= 0) || max_bytes < kSequentialBufferSize ||
      (full_write && read_test)) {
    std::cerr << "Invalid sequential test limits." << std::endl;
    return 2;
  }

  HANDLE file =
      OpenUnbufferedFile(
          path, read_test ? OPEN_EXISTING : CREATE_ALWAYS,
          read_test ? GENERIC_READ : GENERIC_READ | GENERIC_WRITE,
          FILE_FLAG_SEQUENTIAL_SCAN);
  if (file == INVALID_HANDLE_VALUE) {
    EmitError(read_test ? "Unable to open sequential read file"
                        : "Unable to create sequential write file");
    return 3;
  }

  if (read_test) {
    LARGE_INTEGER file_size{};
    if (!GetFileSizeEx(file, &file_size)) {
      EmitError("Unable to query sequential read file size");
      CloseHandle(file);
      return 3;
    }
    max_bytes = std::min(
        max_bytes, AlignDown(static_cast<std::uint64_t>(file_size.QuadPart)));
    if (max_bytes < kSequentialBufferSize) {
      std::cerr << "Sequential read source is too small." << std::endl;
      CloseHandle(file);
      return 2;
    }
  }

  void *buffer = AllocateBuffer(kSequentialBufferSize, GetTickCount());
  if (buffer == nullptr) {
    EmitError("Unable to allocate aligned sequential buffer");
    CloseHandle(file);
    return 4;
  }

  auto perform_io = [&](std::uint64_t &position, double *latency_ms) {
    if (position + kSequentialBufferSize > max_bytes) {
      position = 0;
      if (!SeekFile(file, 0)) {
        return false;
      }
    }
    DWORD transferred = 0;
    const auto operation_started = std::chrono::steady_clock::now();
    const bool success =
        read_test
            ? ReadFile(file, buffer, static_cast<DWORD>(kSequentialBufferSize),
                       &transferred, nullptr) != FALSE
            : WriteFile(file, buffer, static_cast<DWORD>(kSequentialBufferSize),
                        &transferred, nullptr) != FALSE;
    const auto operation_finished = std::chrono::steady_clock::now();
    if (latency_ms != nullptr) {
      *latency_ms = std::chrono::duration<double, std::milli>(
                        operation_finished - operation_started)
                        .count();
    }
    if (!success || transferred != kSequentialBufferSize) {
      return false;
    }
    position += transferred;
    return true;
  };

  bool success = true;
  std::uint64_t position = 0;
  if (warmup_ms > 0) {
    EmitState("WARMUP", warmup_ms);
    const auto warmup_started = std::chrono::steady_clock::now();
    while (std::chrono::duration<double, std::milli>(
               std::chrono::steady_clock::now() - warmup_started)
               .count() < warmup_ms) {
      if (!perform_io(position, nullptr)) {
        EmitError(read_test ? "Sequential read warmup failed"
                            : "Sequential write warmup failed");
        success = false;
        break;
      }
    }
  }
  if (!success || !SeekFile(file, 0)) {
    if (success) {
      EmitError("Unable to reset sequential benchmark position");
    }
    VirtualFree(buffer, 0, MEM_RELEASE);
    CloseHandle(file);
    return 5;
  }
  position = 0;

  EmitState("MEASURE");
  const auto started = std::chrono::steady_clock::now();
  auto sample_started = started;
  std::uint64_t processed = 0;
  std::uint64_t sample_bytes = 0;
  std::uint64_t operations = 0;
  std::uint64_t sample_operations = 0;
  std::uint64_t next_full_sample = 128ULL * 1024ULL * 1024ULL;
  std::vector<double> samples;
  std::vector<double> sample_x_values;
  std::vector<double> all_latencies;
  std::vector<double> sample_latencies;

  while (success && (!full_write || processed < max_bytes)) {
    double latency_ms = 0.0;
    if (!perform_io(position, &latency_ms)) {
      EmitError(read_test ? "Unbuffered sequential read failed"
                          : "Unbuffered sequential write failed");
      success = false;
      break;
    }
    processed += kSequentialBufferSize;
    sample_bytes += kSequentialBufferSize;
    ++operations;
    ++sample_operations;
    all_latencies.push_back(latency_ms);
    sample_latencies.push_back(latency_ms);

    const auto now = std::chrono::steady_clock::now();
    const double total_seconds =
        std::chrono::duration<double>(now - started).count();
    const double sample_seconds =
        std::chrono::duration<double>(now - sample_started).count();
    const bool sample_due =
        full_write ? processed >= next_full_sample : sample_seconds >= 0.5;
    const bool test_due =
        !full_write && total_seconds >= static_cast<double>(seconds);
    const bool full_done = full_write && processed >= max_bytes;
    if (sample_due || test_due || full_done) {
      const double speed = sample_seconds > 0.0
                               ? sample_bytes / kMegabyte / sample_seconds
                               : 0.0;
      const double sample_iops =
          sample_seconds > 0.0 ? sample_operations / sample_seconds : 0.0;
      const double x_value = full_write ? processed / kGigabyte : total_seconds;
      samples.push_back(speed);
      sample_x_values.push_back(x_value);
      EmitSample(x_value, speed, sample_iops, read_test ? speed : 0.0,
                 read_test ? 0.0 : speed, CalculateLatency(sample_latencies));
      sample_started = now;
      sample_bytes = 0;
      sample_operations = 0;
      sample_latencies.clear();
      while (next_full_sample <= processed) {
        next_full_sample += 128ULL * 1024ULL * 1024ULL;
      }
    }
    if (test_due) {
      break;
    }
  }

  if (!read_test && !FlushFileBuffers(file)) {
    EmitError("FlushFileBuffers failed after sequential write");
    success = false;
  }
  const auto finished = std::chrono::steady_clock::now();
  const double elapsed =
      std::chrono::duration<double>(finished - started).count();
  const double average = elapsed > 0.0 ? processed / kMegabyte / elapsed : 0.0;
  const double low = Percentile(samples, 0.10);
  const double stability = average > 0.0 ? low / average : 0.0;
  const double iops = elapsed > 0.0 ? operations / elapsed : 0.0;
  const CacheAnalysis cache =
      full_write ? AnalyzeCache(sample_x_values, samples) : CacheAnalysis{};

  VirtualFree(buffer, 0, MEM_RELEASE);
  CloseHandle(file);
  if (!success || samples.empty()) {
    return 5;
  }

  if (cooldown_ms > 0) {
    EmitState("COOLDOWN", cooldown_ms);
    SleepChecked(cooldown_ms);
  }
  if (full_write) {
    EmitCache(cache);
  }
  EmitResult(average, low, std::clamp(stability, 0.0, 1.0), processed, iops,
             read_test ? average : 0.0, read_test ? 0.0 : average,
             CalculateLatency(all_latencies), cache);
  return 0;
}

class LatencyCollector {
public:
  void Add(const std::vector<double> &values) {
    if (values.empty()) {
      return;
    }
    std::lock_guard<std::mutex> lock(mutex_);
    all_.insert(all_.end(), values.begin(), values.end());
    window_.insert(window_.end(), values.begin(), values.end());
  }

  std::vector<double> TakeWindow() {
    std::lock_guard<std::mutex> lock(mutex_);
    std::vector<double> values;
    values.swap(window_);
    return values;
  }

  std::vector<double> All() const {
    std::lock_guard<std::mutex> lock(mutex_);
    return all_;
  }

private:
  mutable std::mutex mutex_;
  std::vector<double> all_;
  std::vector<double> window_;
};

enum class WorkerPhase { kWarmup, kMeasure, kStop };

struct RandomSharedState {
  std::atomic<WorkerPhase> phase{WorkerPhase::kWarmup};
  std::atomic<bool> failed{false};
  std::atomic<DWORD> error{ERROR_SUCCESS};
  std::atomic<std::uint64_t> read_bytes{0};
  std::atomic<std::uint64_t> write_bytes{0};
  std::atomic<std::uint64_t> operations{0};
  LatencyCollector latencies;
};

struct RandomWorker {
  std::wstring path;
  std::uint64_t file_size;
  WorkloadProfile profile;
  RandomSharedState *shared = nullptr;
  std::uint32_t seed = 0;
};

std::size_t ChooseBlockSize(const WorkloadProfile &profile,
                            std::mt19937 &generator) {
  const int roll = static_cast<int>(generator() % 100);
  int cumulative = 0;
  for (const auto &entry : profile.block_distribution) {
    cumulative += entry.second;
    if (roll < cumulative) {
      return entry.first;
    }
  }
  return profile.block_distribution.back().first;
}

void RunRandomWorker(RandomWorker worker) {
  const std::size_t max_block =
      std::max_element(worker.profile.block_distribution.begin(),
                       worker.profile.block_distribution.end(),
                       [](const auto &left, const auto &right) {
                         return left.first < right.first;
                       })
          ->first;
  HANDLE file =
      OpenUnbufferedFile(
          worker.path, OPEN_EXISTING,
          worker.profile.read_percent == 100
              ? GENERIC_READ
              : GENERIC_READ | GENERIC_WRITE,
          FILE_FLAG_RANDOM_ACCESS);
  if (file == INVALID_HANDLE_VALUE) {
    worker.shared->error.store(GetLastError());
    worker.shared->failed.store(true);
    return;
  }
  void *buffer = AllocateBuffer(max_block, worker.seed);
  if (buffer == nullptr) {
    worker.shared->error.store(GetLastError());
    worker.shared->failed.store(true);
    CloseHandle(file);
    return;
  }

  std::mt19937 generator(worker.seed);
  std::vector<double> latency_batch;
  latency_batch.reserve(16);
  auto latency_batch_started = std::chrono::steady_clock::now();
  while (!worker.shared->failed.load(std::memory_order_relaxed)) {
    const WorkerPhase phase =
        worker.shared->phase.load(std::memory_order_relaxed);
    if (phase == WorkerPhase::kStop) {
      break;
    }
    const std::size_t block_size = ChooseBlockSize(worker.profile, generator);
    const bool read_operation =
        static_cast<int>(generator() % 100) < worker.profile.read_percent;
    const std::uint64_t available_blocks =
        (worker.file_size - block_size) / kAlignment + 1;
    const std::uint64_t offset =
        (static_cast<std::uint64_t>(generator()) % available_blocks) *
        kAlignment;
    if (!SeekFile(file, offset)) {
      worker.shared->error.store(GetLastError());
      worker.shared->failed.store(true);
      break;
    }

    DWORD transferred = 0;
    const auto operation_started = std::chrono::steady_clock::now();
    const bool success =
        read_operation ? ReadFile(file, buffer, static_cast<DWORD>(block_size),
                                  &transferred, nullptr) != FALSE
                       : WriteFile(file, buffer, static_cast<DWORD>(block_size),
                                   &transferred, nullptr) != FALSE;
    const auto operation_finished = std::chrono::steady_clock::now();
    if (!success || transferred != block_size) {
      worker.shared->error.store(GetLastError());
      worker.shared->failed.store(true);
      break;
    }

    if (phase == WorkerPhase::kMeasure &&
        worker.shared->phase.load(std::memory_order_relaxed) ==
            WorkerPhase::kMeasure) {
      if (read_operation) {
        worker.shared->read_bytes.fetch_add(transferred,
                                            std::memory_order_relaxed);
      } else {
        worker.shared->write_bytes.fetch_add(transferred,
                                             std::memory_order_relaxed);
      }
      worker.shared->operations.fetch_add(1, std::memory_order_relaxed);
      latency_batch.push_back(std::chrono::duration<double, std::milli>(
                                  operation_finished - operation_started)
                                  .count());
      const auto now = std::chrono::steady_clock::now();
      if (latency_batch.size() >= 16 ||
          std::chrono::duration<double, std::milli>(now - latency_batch_started)
                  .count() >= 100.0) {
        worker.shared->latencies.Add(latency_batch);
        latency_batch.clear();
        latency_batch_started = now;
      }
    }
  }
  worker.shared->latencies.Add(latency_batch);
  FlushFileBuffers(file);
  VirtualFree(buffer, 0, MEM_RELEASE);
  CloseHandle(file);
}

int RunRandomV3(const std::wstring &path, int seconds, std::uint64_t file_size,
                int thread_count, const WorkloadProfile &profile, int warmup_ms,
                int cooldown_ms, const std::string &profile_name) {
  file_size = AlignDown(file_size);
  if (seconds <= 0 || file_size < kAlignment || thread_count < 1 ||
      thread_count > 64 || profile.read_percent < 0 ||
      profile.read_percent > 100 || profile.block_distribution.empty()) {
    std::cerr << "Invalid random test limits." << std::endl;
    return 2;
  }
  const auto max_block =
      std::max_element(profile.block_distribution.begin(),
                       profile.block_distribution.end(),
                       [](const auto &left, const auto &right) {
                         return left.first < right.first;
                       })
          ->first;
  if (file_size < max_block || !EnsurePreparedFile(path, file_size)) {
    return 3;
  }

  EmitProfile(profile_name, profile, thread_count);
  RandomSharedState shared;
  std::vector<std::thread> workers;
  workers.reserve(static_cast<std::size_t>(thread_count));
  for (int index = 0; index < thread_count; ++index) {
    workers.emplace_back(RunRandomWorker,
                         RandomWorker{path, file_size, profile, &shared,
                                      static_cast<std::uint32_t>(
                                          GetTickCount() + index * 7919)});
  }

  if (warmup_ms > 0) {
    EmitState("WARMUP", warmup_ms);
    if (!SleepChecked(warmup_ms, &shared.failed)) {
      shared.phase.store(WorkerPhase::kStop);
    }
  }
  if (shared.failed.load()) {
    shared.phase.store(WorkerPhase::kStop);
    for (auto &worker : workers) {
      worker.join();
    }
    EmitError("Random workload warmup failed", shared.error.load());
    return 4;
  }

  EmitState("MEASURE");
  shared.phase.store(WorkerPhase::kMeasure);
  const auto started = std::chrono::steady_clock::now();
  auto sample_started = started;
  std::uint64_t previous_read = 0;
  std::uint64_t previous_write = 0;
  std::uint64_t previous_operations = 0;
  std::vector<double> samples;

  while (!shared.failed.load(std::memory_order_relaxed)) {
    const double elapsed_before_sleep =
        std::chrono::duration<double>(std::chrono::steady_clock::now() -
                                      started)
            .count();
    const double remaining_seconds =
        std::max(0.0, static_cast<double>(seconds) - elapsed_before_sleep);
    const DWORD sleep_ms = static_cast<DWORD>(std::clamp(
        static_cast<int>(std::ceil(remaining_seconds * 1000.0)), 1, 500));
    Sleep(sleep_ms);
    const auto now = std::chrono::steady_clock::now();
    const double elapsed = std::chrono::duration<double>(now - started).count();
    const double sample_elapsed =
        std::chrono::duration<double>(now - sample_started).count();
    const std::uint64_t current_read = shared.read_bytes.load();
    const std::uint64_t current_write = shared.write_bytes.load();
    const std::uint64_t current_operations = shared.operations.load();
    const std::uint64_t delta_read = current_read - previous_read;
    const std::uint64_t delta_write = current_write - previous_write;
    const std::uint64_t delta_operations =
        current_operations - previous_operations;
    const double read_mbps =
        sample_elapsed > 0.0 ? delta_read / kMegabyte / sample_elapsed : 0.0;
    const double write_mbps =
        sample_elapsed > 0.0 ? delta_write / kMegabyte / sample_elapsed : 0.0;
    const double sample_iops =
        sample_elapsed > 0.0 ? delta_operations / sample_elapsed : 0.0;
    const double speed = read_mbps + write_mbps;
    samples.push_back(speed);
    EmitSample(elapsed, speed, sample_iops, read_mbps, write_mbps,
               CalculateLatency(shared.latencies.TakeWindow()));
    previous_read = current_read;
    previous_write = current_write;
    previous_operations = current_operations;
    sample_started = now;
    if (elapsed >= static_cast<double>(seconds)) {
      break;
    }
  }

  // Capture the counters at the measurement boundary. Workers may finish an
  // in-flight I/O while they are being joined; including those completions in
  // the totals while keeping the pre-join elapsed time would overstate speed.
  const auto measurement_finished = std::chrono::steady_clock::now();
  const std::uint64_t measured_read_bytes = shared.read_bytes.load();
  const std::uint64_t measured_write_bytes = shared.write_bytes.load();
  const std::uint64_t measured_operations = shared.operations.load();
  shared.phase.store(WorkerPhase::kStop);
  for (auto &worker : workers) {
    if (worker.joinable()) {
      worker.join();
    }
  }
  if (shared.failed.load()) {
    EmitError("Unbuffered random workload failed", shared.error.load());
    return 5;
  }

  const double elapsed =
      std::chrono::duration<double>(measurement_finished - started).count();
  const std::uint64_t read_bytes = measured_read_bytes;
  const std::uint64_t write_bytes = measured_write_bytes;
  const std::uint64_t operations = measured_operations;
  const std::uint64_t total_bytes = read_bytes + write_bytes;
  const double average =
      elapsed > 0.0 ? total_bytes / kMegabyte / elapsed : 0.0;
  const double read_mbps =
      elapsed > 0.0 ? read_bytes / kMegabyte / elapsed : 0.0;
  const double write_mbps =
      elapsed > 0.0 ? write_bytes / kMegabyte / elapsed : 0.0;
  const double iops = elapsed > 0.0 ? operations / elapsed : 0.0;
  const double low = Percentile(samples, 0.10);
  const double stability = average > 0.0 ? low / average : 0.0;

  if (cooldown_ms > 0) {
    EmitState("COOLDOWN", cooldown_ms);
    SleepChecked(cooldown_ms);
  }
  EmitResult(average, low, std::clamp(stability, 0.0, 1.0), total_bytes, iops,
             read_mbps, write_mbps, CalculateLatency(shared.latencies.All()));
  return 0;
}

bool ScenarioProfile(const std::wstring &name, WorkloadProfile *profile,
                     int *thread_count, std::string *profile_name) {
  if (name == L"startup") {
    *profile = {90, {{4096, 65}, {16384, 20}, {65536, 15}}};
    *thread_count = 4;
    *profile_name = "startup";
    return true;
  }
  if (name == L"browser") {
    *profile = {75, {{4096, 85}, {16384, 15}}};
    *thread_count = 2;
    *profile_name = "browser";
    return true;
  }
  if (name == L"windows_update") {
    *profile = {45, {{4096, 45}, {65536, 40}, {262144, 15}}};
    *thread_count = 4;
    *profile_name = "windows_update";
    return true;
  }
  if (name == L"software_install") {
    *profile = {35, {{4096, 35}, {65536, 35}, {1048576, 30}}};
    *thread_count = 4;
    *profile_name = "software_install";
    return true;
  }
  if (name == L"multitasking") {
    *profile = {60, {{4096, 60}, {16384, 20}, {65536, 15}, {262144, 5}}};
    *thread_count = 8;
    *profile_name = "multitasking";
    return true;
  }
  return false;
}

std::uint64_t ParseUnsigned(const wchar_t *value) {
  wchar_t *end = nullptr;
  const unsigned long long parsed = std::wcstoull(value, &end, 10);
  return end == value || *end != L'\0' ? 0 : static_cast<std::uint64_t>(parsed);
}

int ParseInteger(const wchar_t *value) {
  wchar_t *end = nullptr;
  const long parsed = std::wcstol(value, &end, 10);
  return end == value || *end != L'\0' ? 0 : static_cast<int>(parsed);
}

} // namespace

int wmain(int argc, wchar_t *argv[]) {
  if (argc < 4 || std::wstring(argv[1]) != L"--parent-pid") {
    std::cerr << "Parent PID and benchmark mode are required." << std::endl;
    return 1;
  }
  const std::uint64_t parsed_parent_pid = ParseUnsigned(argv[2]);
  if (parsed_parent_pid == 0 || parsed_parent_pid > MAXDWORD) {
    std::cerr << "Invalid parent PID." << std::endl;
    return 1;
  }
  ParentLifetimeGuard parent_guard;
  if (!parent_guard.Start(static_cast<DWORD>(parsed_parent_pid))) {
    EmitError("Unable to bind benchmark helper to parent process");
    return 1;
  }
  EmitProtocol();
  const std::wstring mode = argv[3];

  if (mode == L"sequential-v3" && argc == 11) {
    const std::wstring operation = argv[4];
    if (operation != L"read" && operation != L"write") {
      std::cerr << "Invalid sequential operation." << std::endl;
      return 1;
    }
    return RunSequentialV3(argv[5], operation == L"read", ParseInteger(argv[6]),
                           ParseUnsigned(argv[7]), ParseInteger(argv[8]),
                           ParseInteger(argv[9]), ParseInteger(argv[10]) != 0);
  }
  if (mode == L"random-v3" && argc == 11) {
    WorkloadProfile profile{ParseInteger(argv[8]), {{kAlignment, 100}}};
    return RunRandomV3(argv[4], ParseInteger(argv[5]), ParseUnsigned(argv[6]),
                       ParseInteger(argv[7]), profile, ParseInteger(argv[9]),
                       ParseInteger(argv[10]), "random4k");
  }
  if (mode == L"scenario-v3" && argc == 10) {
    WorkloadProfile profile;
    int thread_count = 0;
    std::string profile_name;
    if (!ScenarioProfile(argv[4], &profile, &thread_count, &profile_name)) {
      std::cerr << "Unknown mixed workload scenario." << std::endl;
      return 1;
    }
    return RunRandomV3(argv[5], ParseInteger(argv[6]), ParseUnsigned(argv[7]),
                       thread_count, profile, ParseInteger(argv[8]),
                       ParseInteger(argv[9]), profile_name);
  }

  std::cerr << "Invalid benchmark arguments." << std::endl;
  return 1;
}
