import 'dart:io';

import 'package:path/path.dart' as p;

/// Immutable identity for the dedicated Arch Linux To Go COW partition.
///
/// This deliberately contains no path and no arbitrary formatter options. The
/// native helper independently verifies every value against the current GPT
/// layout before it permits a write.
class ArchCowPartitionTarget {
  static const int minimumPartitionBytes = 4 * 1024 * 1024;
  static const int maximumPartitionBytes = 16 * 1024 * 1024 * 1024;
  static const int requiredAlignmentBytes = 4096;
  static const int maximumDiskNumber = 9999;
  static const String volumeLabel = 'WDS_ARCH_COW';
  static const String cowDirectory = 'wds-arch';

  static final RegExp _guidExpression = RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
  );

  final int diskNumber;
  final String diskGuid;
  final int partitionNumber;
  final String partitionGuid;
  final int offsetBytes;
  final int sizeBytes;

  ArchCowPartitionTarget({
    required this.diskNumber,
    required String diskGuid,
    required this.partitionNumber,
    required String partitionGuid,
    required this.offsetBytes,
    required this.sizeBytes,
  }) : diskGuid = _normalizeGuid(diskGuid, 'diskGuid'),
       partitionGuid = _normalizeGuid(partitionGuid, 'partitionGuid') {
    if (diskNumber < 0 || diskNumber > maximumDiskNumber) {
      throw ArgumentError.value(diskNumber, 'diskNumber');
    }
    if (partitionNumber <= 0 || partitionNumber > 0xffffffff) {
      throw ArgumentError.value(partitionNumber, 'partitionNumber');
    }
    if (offsetBytes < 1024 * 1024 ||
        offsetBytes % requiredAlignmentBytes != 0) {
      throw ArgumentError.value(offsetBytes, 'offsetBytes');
    }
    if (sizeBytes < minimumPartitionBytes ||
        sizeBytes > maximumPartitionBytes ||
        sizeBytes % requiredAlignmentBytes != 0) {
      throw ArgumentError.value(sizeBytes, 'sizeBytes');
    }
  }

  static String _normalizeGuid(String value, String name) {
    final normalized = value.trim();
    if (!_guidExpression.hasMatch(normalized) ||
        normalized == '00000000-0000-0000-0000-000000000000') {
      throw ArgumentError.value(value, name);
    }
    return normalized.toLowerCase();
  }

  List<String> helperArguments({required int parentPid}) {
    if (parentPid <= 0 || parentPid > 0xffffffff) {
      throw ArgumentError.value(parentPid, 'parentPid');
    }
    return [
      '--disk-number',
      '$diskNumber',
      '--disk-guid',
      diskGuid,
      '--partition-number',
      '$partitionNumber',
      '--partition-guid',
      partitionGuid,
      '--partition-offset-bytes',
      '$offsetBytes',
      '--partition-size-bytes',
      '$sizeBytes',
      '--parent-pid',
      '$parentPid',
    ];
  }
}

typedef ArchCowProcessRunner =
    Future<ProcessResult> Function(String executable, List<String> arguments);

typedef ArchCowHelperResolver = Future<String?> Function();

class ArchCowFormatResult {
  final bool started;
  final int? exitCode;
  final String stdout;
  final String stderr;
  final String? uuid;
  final String? failure;

  const ArchCowFormatResult({
    required this.started,
    this.exitCode,
    this.stdout = '',
    this.stderr = '',
    this.uuid,
    this.failure,
  });

  bool get succeeded => started && exitCode == 0 && uuid != null;
}

/// Launches the bundled, native-only Arch COW formatter.
///
/// Callers are responsible for the user-facing destructive-operation
/// confirmation and for creating the GPT partition. This service does not use
/// a shell, PowerShell, drive letter, or raw disk path.
class ArchCowPartitionService {
  static const String helperExecutableName = 'wds_arch_cow_helper.exe';

  final ArchCowProcessRunner _processRunner;
  final ArchCowHelperResolver _helperResolver;

  ArchCowPartitionService({
    ArchCowProcessRunner? processRunner,
    ArchCowHelperResolver? helperResolver,
  }) : _processRunner = processRunner ?? _runProcess,
       _helperResolver = helperResolver ?? resolveBundledHelperPath;

  static Future<ProcessResult> _runProcess(
    String executable,
    List<String> arguments,
  ) => Process.run(executable, arguments, runInShell: false);

  /// Resolves only the helper compiled beside the running Windows executable.
  /// It intentionally does not search PATH, the current directory, or a
  /// user-controlled tools folder.
  static Future<String?> resolveBundledHelperPath() async {
    if (!Platform.isWindows) return null;
    final helper = File(
      p.join(p.dirname(Platform.resolvedExecutable), helperExecutableName),
    );
    return await helper.exists() ? helper.path : null;
  }

  Future<ArchCowFormatResult> format({
    required ArchCowPartitionTarget target,
    required int parentPid,
  }) async {
    if (!Platform.isWindows) {
      return const ArchCowFormatResult(
        started: false,
        failure: 'Arch COW formatting is available only on Windows.',
      );
    }
    final helperPath = await _helperResolver();
    if (helperPath == null) {
      return const ArchCowFormatResult(
        started: false,
        failure:
            'The Arch COW formatter is missing from this application build.',
      );
    }
    try {
      final result = await _processRunner(
        helperPath,
        target.helperArguments(parentPid: parentPid),
      );
      final stdout = result.stdout.toString();
      final stderr = result.stderr.toString();
      final uuid = _readSuccessfulUuid(stdout);
      return ArchCowFormatResult(
        started: true,
        exitCode: result.exitCode,
        stdout: stdout,
        stderr: stderr,
        uuid: uuid,
        failure: result.exitCode == 0 && uuid != null
            ? null
            : 'The Arch COW formatter rejected or failed the selected partition.',
      );
    } on ProcessException catch (error) {
      return ArchCowFormatResult(
        started: false,
        failure: 'Could not start the Arch COW formatter: ${error.message}',
      );
    }
  }

  static String? _readSuccessfulUuid(String stdout) {
    for (final line in stdout.split(RegExp(r'\r?\n'))) {
      final fields = line.trim().split('|');
      if (fields.length == 4 &&
          fields[0] == 'RESULT' &&
          fields[1] == 'ok' &&
          fields[3] == ArchCowPartitionTarget.volumeLabel &&
          RegExp(
            r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
          ).hasMatch(fields[2])) {
        return fields[2];
      }
    }
    return null;
  }
}
