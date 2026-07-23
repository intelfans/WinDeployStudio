import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import '../../../core/services/in_memory_powershell.dart';
import '../../../core/services/wim_info_service.dart';
import '../../../core/services/windows_iso_mount_service.dart';
import '../../../core/services/windows_iso_preflight.dart';
import '../../../core/services/windows_system_environment.dart';

enum ImageConversionSourceKind {
  setupDirectory,
  wim,
  esd,
  swm,
  iso,
  vhd,
  vhdx,
  rawDiskImage,
  archive,
  unknown,
}

class ImageConversionAnalysis {
  final String sourcePath;
  final ImageConversionSourceKind kind;
  final bool supported;
  final bool requiresBaseMedia;
  final String messageKey;
  final String? detail;

  const ImageConversionAnalysis({
    required this.sourcePath,
    required this.kind,
    required this.supported,
    required this.requiresBaseMedia,
    required this.messageKey,
    this.detail,
  });
}

class ImageConversionReplacement {
  final String sourcePath;
  final String targetName;

  const ImageConversionReplacement({
    required this.sourcePath,
    required this.targetName,
  });
}

class ImageConversionRequest {
  final String sourcePath;
  final ImageConversionSourceKind sourceKind;
  final String? baseMediaPath;
  final String outputPath;
  final String volumeLabel;

  const ImageConversionRequest({
    required this.sourcePath,
    required this.sourceKind,
    required this.outputPath,
    required this.volumeLabel,
    this.baseMediaPath,
  });
}

class ImageConversionProgress {
  final String stepKey;
  final int percent;
  final int writtenBytes;
  final int totalBytes;

  const ImageConversionProgress({
    required this.stepKey,
    required this.percent,
    this.writtenBytes = 0,
    this.totalBytes = 0,
  });
}

class ImageConversionResult {
  final bool success;
  final bool cancelled;
  final String? outputPath;
  final String? sha256;
  final int outputBytes;
  final bool hasBiosBoot;
  final bool hasUefiBoot;
  final String? errorKey;
  final String? errorDetail;

  const ImageConversionResult._({
    required this.success,
    required this.cancelled,
    this.outputPath,
    this.sha256,
    this.outputBytes = 0,
    this.hasBiosBoot = false,
    this.hasUefiBoot = false,
    this.errorKey,
    this.errorDetail,
  });

  const ImageConversionResult.success({
    required String outputPath,
    required String sha256,
    required int outputBytes,
    required bool hasBiosBoot,
    required bool hasUefiBoot,
  }) : this._(
         success: true,
         cancelled: false,
         outputPath: outputPath,
         sha256: sha256,
         outputBytes: outputBytes,
         hasBiosBoot: hasBiosBoot,
         hasUefiBoot: hasUefiBoot,
       );

  const ImageConversionResult.failed(String errorKey, [String? detail])
    : this._(
        success: false,
        cancelled: false,
        errorKey: errorKey,
        errorDetail: detail,
      );

  const ImageConversionResult.cancelled()
    : this._(success: false, cancelled: true);
}

class ImageConversionCancellationToken {
  final Completer<void> _cancelled = Completer<void>();

  bool get isCancelled => _cancelled.isCompleted;
  Future<void> get whenCancelled => _cancelled.future;

  void cancel() {
    if (!_cancelled.isCompleted) _cancelled.complete();
  }
}

typedef ImageConversionProgressCallback =
    void Function(ImageConversionProgress progress);

class ImageConversionService {
  final String? helperPathOverride;

  const ImageConversionService({this.helperPathOverride});

  String get helperPath =>
      helperPathOverride ??
      p.join(
        p.dirname(Platform.resolvedExecutable),
        'wds_iso_builder_helper.exe',
      );

  static ImageConversionSourceKind classifyPath(
    String path, {
    bool isDirectory = false,
  }) {
    if (isDirectory) return ImageConversionSourceKind.setupDirectory;
    return switch (p.extension(path).toLowerCase()) {
      '.wim' => ImageConversionSourceKind.wim,
      '.esd' => ImageConversionSourceKind.esd,
      '.swm' => ImageConversionSourceKind.swm,
      '.iso' => ImageConversionSourceKind.iso,
      '.vhd' => ImageConversionSourceKind.vhd,
      '.vhdx' => ImageConversionSourceKind.vhdx,
      '.img' || '.raw' || '.dd' => ImageConversionSourceKind.rawDiskImage,
      '.zip' ||
      '.7z' ||
      '.rar' ||
      '.tar' ||
      '.gz' => ImageConversionSourceKind.archive,
      _ => ImageConversionSourceKind.unknown,
    };
  }

  static String? validateVolumeLabel(String value) {
    final normalized = value.trim();
    if (normalized.isEmpty) return 'image_converter_label_required';
    if (normalized.length > 32) return 'image_converter_label_too_long';
    if (!RegExp(r'^[A-Za-z0-9][A-Za-z0-9 _-]*$').hasMatch(normalized)) {
      return 'image_converter_label_invalid';
    }
    return null;
  }

  Future<ImageConversionAnalysis> analyze(String sourcePath) async {
    if (!Platform.isWindows) {
      return ImageConversionAnalysis(
        sourcePath: sourcePath,
        kind: ImageConversionSourceKind.unknown,
        supported: false,
        requiresBaseMedia: false,
        messageKey: 'image_converter_windows_only',
      );
    }
    final normalized = p.normalize(p.absolute(sourcePath));
    final entityType = await FileSystemEntity.type(
      normalized,
      followLinks: false,
    );
    if (entityType == FileSystemEntityType.directory) {
      final inspection = await WindowsIsoLayoutInspector.inspectMountedRoot(
        normalized,
        scanFiles: false,
      );
      return ImageConversionAnalysis(
        sourcePath: normalized,
        kind: ImageConversionSourceKind.setupDirectory,
        supported: inspection.isValid,
        requiresBaseMedia: false,
        messageKey: inspection.isValid
            ? 'image_converter_analysis_setup_directory'
            : 'image_converter_analysis_invalid_setup_directory',
        detail: inspection.error,
      );
    }
    if (entityType != FileSystemEntityType.file) {
      return ImageConversionAnalysis(
        sourcePath: normalized,
        kind: ImageConversionSourceKind.unknown,
        supported: false,
        requiresBaseMedia: false,
        messageKey: 'image_converter_source_missing',
      );
    }

    final kind = classifyPath(normalized);
    if (kind == ImageConversionSourceKind.wim ||
        kind == ImageConversionSourceKind.esd ||
        kind == ImageConversionSourceKind.swm) {
      final validHeader = await _hasWimHeader(normalized);
      return ImageConversionAnalysis(
        sourcePath: normalized,
        kind: kind,
        supported: validHeader,
        requiresBaseMedia: validHeader,
        messageKey: validHeader
            ? 'image_converter_analysis_windows_image'
            : 'image_converter_analysis_invalid_windows_image',
      );
    }
    return switch (kind) {
      ImageConversionSourceKind.iso => ImageConversionAnalysis(
        sourcePath: normalized,
        kind: kind,
        supported: false,
        requiresBaseMedia: false,
        messageKey: 'image_converter_analysis_already_iso',
      ),
      ImageConversionSourceKind.vhd ||
      ImageConversionSourceKind.vhdx => ImageConversionAnalysis(
        sourcePath: normalized,
        kind: kind,
        supported: true,
        requiresBaseMedia: false,
        messageKey: 'image_converter_analysis_virtual_disk',
      ),
      ImageConversionSourceKind.rawDiskImage => ImageConversionAnalysis(
        sourcePath: normalized,
        kind: kind,
        supported: false,
        requiresBaseMedia: false,
        messageKey: 'image_converter_analysis_raw_image',
      ),
      ImageConversionSourceKind.archive => ImageConversionAnalysis(
        sourcePath: normalized,
        kind: kind,
        supported: false,
        requiresBaseMedia: false,
        messageKey: 'image_converter_analysis_archive',
      ),
      _ => ImageConversionAnalysis(
        sourcePath: normalized,
        kind: kind,
        supported: false,
        requiresBaseMedia: false,
        messageKey: 'image_converter_analysis_unsupported',
      ),
    };
  }

  Future<ImageConversionResult> convert(
    ImageConversionRequest request, {
    ImageConversionCancellationToken? cancellationToken,
    ImageConversionProgressCallback? onProgress,
  }) async {
    if (!Platform.isWindows) {
      return const ImageConversionResult.failed('image_converter_windows_only');
    }
    final labelError = validateVolumeLabel(request.volumeLabel);
    if (labelError != null) return ImageConversionResult.failed(labelError);
    if (cancellationToken?.isCancelled == true) {
      return const ImageConversionResult.cancelled();
    }

    final sourcePath = p.normalize(p.absolute(request.sourcePath));
    final outputPath = p.normalize(p.absolute(request.outputPath));
    if (p.extension(outputPath).toLowerCase() != '.iso') {
      return const ImageConversionResult.failed(
        'image_converter_output_extension',
      );
    }
    final outputParent = Directory(p.dirname(outputPath));
    if (!await outputParent.exists()) {
      return const ImageConversionResult.failed(
        'image_converter_output_directory_missing',
      );
    }
    if (p.equals(sourcePath, outputPath)) {
      return const ImageConversionResult.failed(
        'image_converter_output_matches_source',
      );
    }
    final helper = File(helperPath);
    if (!await helper.exists()) {
      return const ImageConversionResult.failed(
        'image_converter_helper_missing',
      );
    }

    WindowsIsoMountLease? isoLease;
    _VirtualDiskMountLease? virtualDiskLease;
    try {
      onProgress?.call(
        const ImageConversionProgress(
          stepKey: 'image_converter_step_preflight',
          percent: 2,
        ),
      );
      String sourceRoot;
      var replacements = const <ImageConversionReplacement>[];
      switch (request.sourceKind) {
        case ImageConversionSourceKind.setupDirectory:
          sourceRoot = sourcePath;
          break;
        case ImageConversionSourceKind.wim:
        case ImageConversionSourceKind.esd:
        case ImageConversionSourceKind.swm:
          final basePath = request.baseMediaPath?.trim() ?? '';
          if (basePath.isEmpty) {
            return const ImageConversionResult.failed(
              'image_converter_base_required',
            );
          }
          final resolvedBase = await _resolveBaseMediaRoot(basePath);
          if (resolvedBase == null) {
            return ImageConversionResult.failed(
              'image_converter_base_invalid',
              WindowsIsoMountService.instance.lastDiagnostic,
            );
          }
          sourceRoot = resolvedBase.root;
          isoLease = resolvedBase.lease;
          replacements = await _replacementFiles(
            sourcePath,
            request.sourceKind,
          );
          final compatibility = await _validateReplacementCompatibility(
            sourceRoot,
            sourcePath,
            request.sourceKind,
          );
          if (compatibility != null) return compatibility;
          break;
        case ImageConversionSourceKind.vhd:
        case ImageConversionSourceKind.vhdx:
          virtualDiskLease = await _mountVirtualDisk(sourcePath);
          if (virtualDiskLease == null) {
            return const ImageConversionResult.failed(
              'image_converter_virtual_disk_mount_failed',
            );
          }
          final validRoot = await _findValidSetupRoot(virtualDiskLease.roots);
          if (validRoot == null) {
            return const ImageConversionResult.failed(
              'image_converter_virtual_disk_no_setup',
            );
          }
          sourceRoot = validRoot;
          break;
        default:
          return const ImageConversionResult.failed(
            'image_converter_analysis_unsupported',
          );
      }

      final sourceInspection =
          await WindowsIsoLayoutInspector.inspectMountedRoot(
            sourceRoot,
            scanFiles: false,
          );
      if (!sourceInspection.isValid) {
        return ImageConversionResult.failed(
          'image_converter_source_layout_invalid',
          sourceInspection.error,
        );
      }
      if (cancellationToken?.isCancelled == true) {
        return const ImageConversionResult.cancelled();
      }

      final result = await _runBuilder(
        sourceRoot: sourceRoot,
        outputPath: outputPath,
        volumeLabel: request.volumeLabel.trim(),
        replacements: replacements,
        cancellationToken: cancellationToken,
        onProgress: onProgress,
      );
      if (!result.success) return result;

      onProgress?.call(
        const ImageConversionProgress(
          stepKey: 'image_converter_step_verifying',
          percent: 96,
        ),
      );
      final verification = await const WindowsIsoPreflightService().inspect(
        outputPath,
      );
      if (!verification.isValid) {
        await _deleteIfPresent(outputPath);
        return ImageConversionResult.failed(
          'image_converter_verification_failed',
          verification.error,
        );
      }
      if (cancellationToken?.isCancelled == true) {
        await _deleteIfPresent(outputPath);
        return const ImageConversionResult.cancelled();
      }

      onProgress?.call(
        const ImageConversionProgress(
          stepKey: 'image_converter_step_hashing',
          percent: 98,
        ),
      );
      final outputFile = File(outputPath);
      final digest = await sha256.bind(outputFile.openRead()).first;
      final outputBytes = await outputFile.length();
      onProgress?.call(
        const ImageConversionProgress(
          stepKey: 'image_converter_step_complete',
          percent: 100,
        ),
      );
      return ImageConversionResult.success(
        outputPath: outputPath,
        sha256: digest.toString().toUpperCase(),
        outputBytes: outputBytes,
        hasBiosBoot: verification.hasBiosBootManager && verification.hasBiosBcd,
        hasUefiBoot:
            verification.hasEfiBcd &&
            verification.efiBootArchitectures.isNotEmpty,
      );
    } on TimeoutException catch (error) {
      await _deleteIfPresent('$outputPath.wds-part');
      return ImageConversionResult.failed(
        'image_converter_timed_out',
        error.toString(),
      );
    } catch (error) {
      await _deleteIfPresent('$outputPath.wds-part');
      return ImageConversionResult.failed(
        'image_converter_failed',
        error.toString(),
      );
    } finally {
      await isoLease?.release();
      await virtualDiskLease?.release();
    }
  }

  Future<_ResolvedBaseMedia?> _resolveBaseMediaRoot(String path) async {
    final normalized = p.normalize(p.absolute(path));
    final type = await FileSystemEntity.type(normalized, followLinks: false);
    if (type == FileSystemEntityType.directory) {
      final inspection = await WindowsIsoLayoutInspector.inspectMountedRoot(
        normalized,
        scanFiles: false,
      );
      return inspection.isValid ? _ResolvedBaseMedia(root: normalized) : null;
    }
    if (type != FileSystemEntityType.file ||
        p.extension(normalized).toLowerCase() != '.iso') {
      return null;
    }
    final lease = await WindowsIsoMountService.instance.acquire(normalized);
    if (lease == null) return null;
    final inspection = await WindowsIsoLayoutInspector.inspectMountedRoot(
      lease.mountPoint,
      scanFiles: false,
    );
    if (!inspection.isValid) {
      await lease.release();
      return null;
    }
    return _ResolvedBaseMedia(root: lease.mountPoint, lease: lease);
  }

  Future<ImageConversionResult?> _validateReplacementCompatibility(
    String sourceRoot,
    String replacementPath,
    ImageConversionSourceKind kind,
  ) async {
    if (!await _hasWimHeader(replacementPath)) {
      return const ImageConversionResult.failed(
        'image_converter_analysis_invalid_windows_image',
      );
    }
    if (kind == ImageConversionSourceKind.swm) return null;
    try {
      final sourceImages = await WimInfoService.readImages(replacementPath);
      final bootImages = await WimInfoService.readImages(
        p.join(sourceRoot, 'sources', 'boot.wim'),
      );
      final sourceArchitectures = sourceImages
          .map((image) => image.architecture.trim().toLowerCase())
          .where((value) => value.isNotEmpty)
          .toSet();
      final bootArchitectures = bootImages
          .map((image) => image.architecture.trim().toLowerCase())
          .where((value) => value.isNotEmpty)
          .toSet();
      if (sourceArchitectures.isNotEmpty &&
          bootArchitectures.isNotEmpty &&
          sourceArchitectures.intersection(bootArchitectures).isEmpty) {
        return ImageConversionResult.failed(
          'image_converter_architecture_mismatch',
          '${sourceArchitectures.join(', ')} / ${bootArchitectures.join(', ')}',
        );
      }
      final sourceBuild = sourceImages
          .map((image) => int.tryParse(image.build) ?? 0)
          .firstWhere((build) => build > 0, orElse: () => 0);
      final bootBuild = bootImages
          .map((image) => int.tryParse(image.build) ?? 0)
          .firstWhere((build) => build > 0, orElse: () => 0);
      if (sourceBuild > 0 &&
          bootBuild > 0 &&
          _windowsGeneration(sourceBuild) != _windowsGeneration(bootBuild)) {
        return ImageConversionResult.failed(
          'image_converter_generation_mismatch',
          '$sourceBuild / $bootBuild',
        );
      }
      final onlyWinPe = sourceImages.every((image) {
        final text = '${image.name} ${image.description}'.toLowerCase();
        return text.contains('windows pe') || text.contains('windows setup');
      });
      if (onlyWinPe) {
        return const ImageConversionResult.failed(
          'image_converter_install_image_required',
        );
      }
      return null;
    } catch (error) {
      return ImageConversionResult.failed(
        'image_converter_metadata_failed',
        error.toString(),
      );
    }
  }

  static int _windowsGeneration(int build) {
    if (build >= 22000) return 11;
    if (build >= 10240) return 10;
    if (build >= 9600) return 81;
    if (build >= 9200) return 8;
    if (build >= 7600) return 7;
    return build;
  }

  Future<List<ImageConversionReplacement>> _replacementFiles(
    String sourcePath,
    ImageConversionSourceKind kind,
  ) async {
    if (kind == ImageConversionSourceKind.wim) {
      return [
        ImageConversionReplacement(
          sourcePath: sourcePath,
          targetName: 'install.wim',
        ),
      ];
    }
    if (kind == ImageConversionSourceKind.esd) {
      return [
        ImageConversionReplacement(
          sourcePath: sourcePath,
          targetName: 'install.esd',
        ),
      ];
    }
    final selectedName = p.basenameWithoutExtension(sourcePath);
    final prefix = selectedName.replaceFirst(RegExp(r'\d+$'), '');
    final matcher = RegExp(
      '^${RegExp.escape(prefix)}(\\d*)\\.swm\$',
      caseSensitive: false,
    );
    final matches = <(File, int)>[];
    await for (final entity in Directory(p.dirname(sourcePath)).list()) {
      if (entity is! File) continue;
      final match = matcher.firstMatch(p.basename(entity.path));
      if (match == null || !await _hasWimHeader(entity.path)) continue;
      matches.add((entity, int.tryParse(match.group(1) ?? '') ?? 1));
    }
    matches.sort((left, right) => left.$2.compareTo(right.$2));
    if (matches.isEmpty) {
      throw StateError('No valid split WIM parts were found.');
    }
    return [
      for (var index = 0; index < matches.length; index++)
        ImageConversionReplacement(
          sourcePath: matches[index].$1.path,
          targetName: index == 0 ? 'install.swm' : 'install${index + 1}.swm',
        ),
    ];
  }

  Future<ImageConversionResult> _runBuilder({
    required String sourceRoot,
    required String outputPath,
    required String volumeLabel,
    required List<ImageConversionReplacement> replacements,
    ImageConversionCancellationToken? cancellationToken,
    ImageConversionProgressCallback? onProgress,
  }) async {
    final cancelPath = p.join(
      Directory.systemTemp.path,
      'wds_iso_${pid}_${DateTime.now().microsecondsSinceEpoch}_${Random.secure().nextInt(1 << 31)}.cancel',
    );
    await _deleteIfPresent(cancelPath);
    final arguments = <String>[
      '--parent-pid',
      '$pid',
      '--source-root',
      sourceRoot,
      '--output',
      outputPath,
      '--volume-label',
      volumeLabel,
      '--cancel',
      cancelPath,
      for (final replacement in replacements) ...[
        '--replace-file',
        replacement.sourcePath,
        replacement.targetName,
      ],
    ];
    final process = await Process.start(
      helperPath,
      arguments,
      environment: WindowsSystemEnvironment.withSystemRoot(),
    );
    final errors = StringBuffer();
    var protocolSeen = false;
    var resultSeen = false;
    var builderBytes = 0;
    var builderHasBios = false;
    var builderHasUefi = false;
    final stdoutDone = process.stdout
        .transform(const SystemEncoding().decoder)
        .transform(const LineSplitter())
        .listen((line) {
          final parts = line.trim().split('|');
          if (parts.length == 2 && parts[0] == 'PROTO') {
            protocolSeen = parts[1] == '1';
          } else if (parts.length >= 3 && parts[0] == 'STATE') {
            onProgress?.call(
              ImageConversionProgress(
                stepKey: _stepKeyForBuilderState(parts[1]),
                percent: int.tryParse(parts[2]) ?? 0,
              ),
            );
          } else if (parts.length >= 5 && parts[0] == 'PROGRESS') {
            onProgress?.call(
              ImageConversionProgress(
                stepKey: _stepKeyForBuilderState(parts[1]),
                percent: int.tryParse(parts[2]) ?? 0,
                writtenBytes: int.tryParse(parts[3]) ?? 0,
                totalBytes: int.tryParse(parts[4]) ?? 0,
              ),
            );
          } else if (parts.length >= 4 && parts[0] == 'RESULT') {
            resultSeen = true;
            builderBytes = int.tryParse(parts[1]) ?? 0;
            builderHasBios = parts[2] == '1';
            builderHasUefi = parts[3] == '1';
          }
        })
        .asFuture<void>();
    final stderrDone = process.stderr
        .transform(const SystemEncoding().decoder)
        .transform(const LineSplitter())
        .listen((line) {
          if (errors.length < 4000 && line.trim().isNotEmpty) {
            errors.writeln(line.trim());
          }
        })
        .asFuture<void>();

    var processHasExited = false;
    final exitCodeFuture = process.exitCode.then((code) {
      processHasExited = true;
      return code;
    });
    final cancellation = cancellationToken?.whenCancelled.then<Object>((
      _,
    ) async {
      try {
        await File(cancelPath).writeAsString('cancel', flush: true);
      } catch (_) {}
      // IMAPI2 can spend time inside CreateResultImage without returning to
      // Dart. Give it a short grace period to observe the marker, then stop
      // the helper tree so cancellation never leaves the UI waiting forever.
      await Future<void>.delayed(const Duration(seconds: 5));
      if (!processHasExited) {
        await _terminateProcessTree(process.pid);
      }
      return const _BuilderCancelled();
    });
    final outcome = await Future.any<Object>([
      exitCodeFuture,
      Future<void>.delayed(
        const Duration(hours: 8),
      ).then<Object>((_) => const _BuilderTimeout()),
    ]);
    if (outcome is _BuilderTimeout) {
      await _terminateProcessTree(process.pid);
      throw TimeoutException('The ISO builder exceeded the eight-hour limit.');
    }
    if (outcome is _BuilderCancelled) {
      processHasExited = true;
      try {
        await exitCodeFuture.timeout(const Duration(seconds: 10));
      } catch (_) {}
      await Future.wait([stdoutDone, stderrDone]);
      await _deleteIfPresent(cancelPath);
      await _deleteIfPresent(outputPath);
      await _deleteIfPresent('$outputPath.wds-part');
      return const ImageConversionResult.cancelled();
    }
    processHasExited = true;
    final exitCode = outcome as int;
    await Future.wait([stdoutDone, stderrDone]);
    if (cancellation != null) unawaited(cancellation);
    await _deleteIfPresent(cancelPath);

    if (cancellationToken?.isCancelled == true) {
      await _deleteIfPresent(outputPath);
      await _deleteIfPresent('$outputPath.wds-part');
      return const ImageConversionResult.cancelled();
    }
    if (exitCode != 0 || !protocolSeen || !resultSeen) {
      await _deleteIfPresent(outputPath);
      await _deleteIfPresent('$outputPath.wds-part');
      return ImageConversionResult.failed(
        'image_converter_builder_failed',
        errors.toString().trim(),
      );
    }
    if (builderBytes <= 0 || !builderHasBios && !builderHasUefi) {
      await _deleteIfPresent(outputPath);
      return const ImageConversionResult.failed(
        'image_converter_builder_invalid_result',
      );
    }
    return ImageConversionResult.success(
      outputPath: outputPath,
      sha256: '',
      outputBytes: builderBytes,
      hasBiosBoot: builderHasBios,
      hasUefiBoot: builderHasUefi,
    );
  }

  static String _stepKeyForBuilderState(String state) => switch (state) {
    'preparing' => 'image_converter_step_preparing',
    'building' => 'image_converter_step_building',
    'writing' => 'image_converter_step_writing',
    'complete' => 'image_converter_step_complete',
    _ => 'image_converter_step_preparing',
  };

  Future<_VirtualDiskMountLease?> _mountVirtualDisk(String imagePath) async {
    final result = await _runPowerShell(
      script: _mountVirtualDiskScript,
      parameters: {'ImagePath': imagePath},
      timeout: const Duration(seconds: 90),
    );
    if (result == null || result.exitCode != 0) return null;
    var owned = false;
    final roots = <String>[];
    for (final rawLine in result.stdout.toString().split(RegExp(r'\r?\n'))) {
      final line = rawLine.trim();
      if (line == 'WDS_OWNED:1') owned = true;
      if (line.startsWith('WDS_ROOT:')) {
        final root = line.substring('WDS_ROOT:'.length).trim();
        if (RegExp(r'^[A-Za-z]:\\$').hasMatch(root)) roots.add(root);
      }
    }
    if (roots.isEmpty) {
      if (owned) await _dismountVirtualDisk(imagePath);
      return null;
    }
    return _VirtualDiskMountLease(
      roots: List.unmodifiable(roots),
      releaseCallback: owned
          ? () => _dismountVirtualDisk(imagePath)
          : () async {},
    );
  }

  Future<void> _dismountVirtualDisk(String imagePath) async {
    await _runPowerShell(
      script: _dismountVirtualDiskScript,
      parameters: {'ImagePath': imagePath},
      timeout: const Duration(seconds: 45),
    );
  }

  Future<ProcessResult?> _runPowerShell({
    required String script,
    required Map<String, String> parameters,
    required Duration timeout,
  }) async {
    try {
      final command = InMemoryPowerShell.build(
        script: script,
        parameters: parameters,
      );
      return await Process.run(
        command.executable,
        command.arguments,
        environment: command.environment,
      ).timeout(timeout);
    } catch (_) {
      return null;
    }
  }

  Future<String?> _findValidSetupRoot(Iterable<String> roots) async {
    for (final root in roots) {
      final inspection = await WindowsIsoLayoutInspector.inspectMountedRoot(
        root,
        scanFiles: false,
      );
      if (inspection.isValid) return root;
    }
    return null;
  }

  static Future<bool> _hasWimHeader(String path) async {
    final file = File(path);
    if (await FileSystemEntity.type(path, followLinks: false) !=
        FileSystemEntityType.file) {
      return false;
    }
    if (await file.length() < 0xD0) return false;
    RandomAccessFile? handle;
    try {
      handle = await file.open();
      final header = await handle.read(0xD0);
      const magic = <int>[0x4d, 0x53, 0x57, 0x49, 0x4d, 0, 0, 0];
      if (header.length < 0xD0) return false;
      for (var index = 0; index < magic.length; index++) {
        if (header[index] != magic[index]) return false;
      }
      final headerSize = _uint32(header, 8);
      return headerSize >= 0xD0 && headerSize <= await file.length();
    } catch (_) {
      return false;
    } finally {
      await handle?.close();
    }
  }

  static int _uint32(Uint8List bytes, int offset) =>
      bytes[offset] |
      (bytes[offset + 1] << 8) |
      (bytes[offset + 2] << 16) |
      (bytes[offset + 3] << 24);

  static Future<void> _terminateProcessTree(int processId) async {
    try {
      await Process.run(
        WindowsSystemEnvironment.taskkillExecutable,
        ['/F', '/T', '/PID', '$processId'],
        environment: WindowsSystemEnvironment.withSystemRoot(),
      ).timeout(const Duration(seconds: 10));
    } catch (_) {}
  }

  static Future<void> _deleteIfPresent(String path) async {
    try {
      final file = File(path);
      if (await file.exists()) await file.delete();
    } catch (_) {}
  }

  static const _mountVirtualDiskScript = r'''
param([string]$ImagePath)
$ErrorActionPreference = 'Stop'
$image = Get-DiskImage -ImagePath $ImagePath -ErrorAction SilentlyContinue
$owned = $null -eq $image -or -not [bool]$image.Attached
if ($owned) {
  Mount-DiskImage -ImagePath $ImagePath -Access ReadOnly -ErrorAction Stop | Out-Null
}
$deadline = [DateTime]::UtcNow.AddSeconds(60)
$roots = @()
while ([DateTime]::UtcNow -lt $deadline) {
  $image = Get-DiskImage -ImagePath $ImagePath -ErrorAction Stop
  $roots = @(
    $image | Get-Disk -ErrorAction SilentlyContinue |
      Get-Partition -ErrorAction SilentlyContinue |
      Get-Volume -ErrorAction SilentlyContinue |
      Where-Object DriveLetter |
      ForEach-Object { '{0}:\' -f $_.DriveLetter }
  )
  if ($roots.Count -gt 0) { break }
  Start-Sleep -Milliseconds 400
}
Write-Output ('WDS_OWNED:{0}' -f $(if ($owned) { 1 } else { 0 }))
$roots | Sort-Object -Unique | ForEach-Object { Write-Output ('WDS_ROOT:{0}' -f $_) }
''';

  static const _dismountVirtualDiskScript = r'''
param([string]$ImagePath)
Dismount-DiskImage -ImagePath $ImagePath -ErrorAction SilentlyContinue | Out-Null
''';
}

class _ResolvedBaseMedia {
  final String root;
  final WindowsIsoMountLease? lease;

  const _ResolvedBaseMedia({required this.root, this.lease});
}

class _VirtualDiskMountLease {
  final List<String> roots;
  final Future<void> Function() releaseCallback;
  bool _released = false;

  _VirtualDiskMountLease({required this.roots, required this.releaseCallback});

  Future<void> release() async {
    if (_released) return;
    _released = true;
    await releaseCallback();
  }
}

class _BuilderTimeout {
  const _BuilderTimeout();
}

class _BuilderCancelled {
  const _BuilderCancelled();
}
