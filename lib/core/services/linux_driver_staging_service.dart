import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

typedef LinuxSourceDiskRelationResolver =
    Future<bool?> Function(String sourceDirectory, int targetDiskNumber);
typedef LinuxStagingDeploymentCheckpoint = Future<void> Function(String phase);

enum LinuxStagingPayloadKind {
  deb,
  rpm,
  archPackage,
  kernelModule,
  shellScript,
}

class LinuxStagingEntry {
  final String id;
  final String relativePath;
  final LinuxStagingPayloadKind kind;
  final int sizeBytes;
  final String sha256;

  const LinuxStagingEntry({
    required this.id,
    required this.relativePath,
    required this.kind,
    required this.sizeBytes,
    required this.sha256,
  });
}

class LinuxDriverStagingBundle {
  final String sourceRoot;
  final List<LinuxStagingEntry> entries;
  final int totalBytes;
  final String manifestJson;

  const LinuxDriverStagingBundle({
    required this.sourceRoot,
    required this.entries,
    required this.totalBytes,
    required this.manifestJson,
  });

  int get estimatedPersistenceBytes {
    final packageBytes = entries
        .where(
          (entry) =>
              entry.kind == LinuxStagingPayloadKind.deb ||
              entry.kind == LinuxStagingPayloadKind.rpm ||
              entry.kind == LinuxStagingPayloadKind.archPackage,
        )
        .fold<int>(0, (sum, entry) => sum + entry.sizeBytes);
    final otherBytes = totalBytes - packageBytes;
    return packageBytes * 4 + otherBytes * 2 + 512 * 1024 * 1024;
  }

  String get manifestSha256 =>
      sha256.convert(utf8.encode(manifestJson)).toString();
}

class LinuxDriverStagingPreparation {
  final LinuxDriverStagingBundle? bundle;
  final String? error;

  const LinuxDriverStagingPreparation._({this.bundle, this.error});

  const LinuxDriverStagingPreparation.disabled() : this._();

  const LinuxDriverStagingPreparation.success(LinuxDriverStagingBundle bundle)
    : this._(bundle: bundle);

  const LinuxDriverStagingPreparation.failure(String error)
    : this._(error: error);

  bool get success => error == null;
  bool get enabled => bundle != null;
}

class LinuxDriverStagingDeploymentResult {
  final bool success;
  final String? error;

  const LinuxDriverStagingDeploymentResult._({
    required this.success,
    this.error,
  });

  const LinuxDriverStagingDeploymentResult.success() : this._(success: true);

  const LinuxDriverStagingDeploymentResult.failure(String error)
    : this._(success: false, error: error);
}

class LinuxDriverStagingService {
  static const String seedRelativePath = 'windeploy-studio/linux-staging';
  static const String trustRelativePath =
      'windeploy-studio/linux-staging-trust';
  static const String serviceName = 'windeploy-linux-staging.service';
  static const String bootMarkerArgument = 'wds-linux-staging=1';
  static const String systemdWantsArgument =
      'systemd.wants=windeploy-linux-staging.service';
  static const String _archiveMarker = 'WDS-LTG-BOOTSTRAP-V1';
  static const int _maxEntries = 4096;

  final void Function(String message) log;
  final LinuxSourceDiskRelationResolver? sourceDiskRelationResolver;
  final LinuxStagingDeploymentCheckpoint? deploymentCheckpoint;

  const LinuxDriverStagingService({
    required this.log,
    this.sourceDiskRelationResolver,
    this.deploymentCheckpoint,
  });

  Future<LinuxDriverStagingPreparation> prepare({
    required String sourceDirectory,
    required int targetDiskNumber,
  }) async {
    final requestedPath = sourceDirectory.trim();
    if (requestedPath.isEmpty) {
      return const LinuxDriverStagingPreparation.disabled();
    }

    try {
      final source = Directory(p.normalize(p.absolute(requestedPath)));
      if (!await source.exists()) {
        return LinuxDriverStagingPreparation.failure(
          'The Linux staging directory does not exist: ${source.path}',
        );
      }
      if (await FileSystemEntity.type(source.path, followLinks: false) ==
          FileSystemEntityType.link) {
        return const LinuxDriverStagingPreparation.failure(
          'The Linux staging directory cannot be a symbolic link or junction.',
        );
      }

      final sameTarget = sourceDiskRelationResolver == null
          ? await _isDirectoryOnTargetDisk(source.path, targetDiskNumber)
          : await sourceDiskRelationResolver!(source.path, targetDiskNumber);
      if (sameTarget == null) {
        return const LinuxDriverStagingPreparation.failure(
          'The physical disk containing the Linux staging directory could not be verified.',
        );
      }
      if (sameTarget) {
        return const LinuxDriverStagingPreparation.failure(
          'The Linux staging directory is stored on the target disk and would be erased.',
        );
      }

      final canonicalRoot = await source.resolveSymbolicLinks();
      final entries = <LinuxStagingEntry>[];
      var totalBytes = 0;
      final moduleNames = <String>{};

      await for (final entity in source.list(
        recursive: true,
        followLinks: false,
      )) {
        if (entries.length >= _maxEntries) {
          return const LinuxDriverStagingPreparation.failure(
            'The Linux staging directory contains more than 4096 files.',
          );
        }

        final entityType = await FileSystemEntity.type(
          entity.path,
          followLinks: false,
        );
        if (entityType == FileSystemEntityType.link) {
          return LinuxDriverStagingPreparation.failure(
            'Symbolic links and junctions are not allowed in Linux staging: ${entity.path}',
          );
        }
        if (entityType == FileSystemEntityType.directory) continue;
        if (entityType != FileSystemEntityType.file || entity is! File) {
          return LinuxDriverStagingPreparation.failure(
            'Only regular files are allowed in Linux staging: ${entity.path}',
          );
        }

        final resolvedPath = await entity.resolveSymbolicLinks();
        if (!_isWithinRoot(canonicalRoot, resolvedPath)) {
          return LinuxDriverStagingPreparation.failure(
            'A Linux staging file resolves outside the selected directory: ${entity.path}',
          );
        }

        final relativePath = p
            .relative(entity.path, from: source.path)
            .replaceAll('\\', '/');
        final pathError = _validateRelativePath(relativePath);
        if (pathError != null) {
          return LinuxDriverStagingPreparation.failure(pathError);
        }

        final kind = _classify(relativePath);
        if (kind == null) {
          return LinuxDriverStagingPreparation.failure(
            _unsupportedFileMessage(relativePath),
          );
        }
        if (kind == LinuxStagingPayloadKind.kernelModule) {
          final moduleName = _moduleFileName(relativePath).toLowerCase();
          if (!moduleNames.add(moduleName)) {
            return LinuxDriverStagingPreparation.failure(
              'Linux staging contains duplicate kernel module names: $moduleName',
            );
          }
        }

        final sizeBytes = await entity.length();
        if (sizeBytes <= 0) {
          return LinuxDriverStagingPreparation.failure(
            'Empty Linux staging files are not allowed: $relativePath',
          );
        }
        final digest = (await sha256.bind(entity.openRead()).first).toString();
        final id = sha256
            .convert(
              utf8.encode('${kind.name}\u0000$relativePath\u0000$digest'),
            )
            .toString()
            .substring(0, 24);
        entries.add(
          LinuxStagingEntry(
            id: id,
            relativePath: relativePath,
            kind: kind,
            sizeBytes: sizeBytes,
            sha256: digest,
          ),
        );
        totalBytes += sizeBytes;
      }

      if (entries.isEmpty) {
        return const LinuxDriverStagingPreparation.failure(
          'The Linux staging directory contains no supported packages, modules, or .sh scripts.',
        );
      }
      entries.sort(
        (left, right) => left.relativePath.compareTo(right.relativePath),
      );

      final manifest = const JsonEncoder.withIndent('  ').convert({
        'schemaVersion': 1,
        'source': 'user-selected Linux staging directory',
        'scope': 'Ubuntu/casper persistent live systems',
        'installTiming': 'First boot after the persistent overlay is mounted',
        'entries': entries
            .map(
              (entry) => {
                'id': entry.id,
                'sourceRelativePath': entry.relativePath,
                'stagedPath': 'payload/${entry.relativePath}',
                'kind': entry.kind.name,
                'sizeBytes': entry.sizeBytes,
                'sha256': entry.sha256,
              },
            )
            .toList(growable: false),
      });
      log(
        'Linux first-boot staging validated: ${entries.length} files, '
        '$totalBytes bytes. Installation remains deferred until Linux boots.',
      );
      return LinuxDriverStagingPreparation.success(
        LinuxDriverStagingBundle(
          sourceRoot: source.path,
          entries: List.unmodifiable(entries),
          totalBytes: totalBytes,
          manifestJson: '$manifest\n',
        ),
      );
    } catch (error) {
      return LinuxDriverStagingPreparation.failure(
        'Linux staging validation failed: $error',
      );
    }
  }

  Future<LinuxDriverStagingDeploymentResult> deploy({
    required LinuxDriverStagingBundle bundle,
    required String liveDrive,
    required String bootDrive,
  }) async {
    final liveRoot = _driveRoot(liveDrive);
    final bootRoot = _driveRoot(bootDrive);
    final seedRoot = Directory(_joinPosix(liveRoot, seedRelativePath));
    final trustRoot = Directory(_joinPosix(bootRoot, trustRelativePath));
    final seedParent = seedRoot.parent;
    final trustParent = trustRoot.parent;
    final token = DateTime.now().microsecondsSinceEpoch;
    final temporarySeedRoot = Directory(
      p.join(seedParent.path, '.linux-staging-$token.tmp'),
    );
    final temporaryTrustRoot = Directory(
      p.join(trustParent.path, '.linux-staging-trust-$token.tmp'),
    );
    final layout = _buildDeploymentLayout(bundle);
    final bootstrapArchive = _buildBootstrapArchive(layout.trustRootDigest);
    final bootInitrd = File(p.join(bootRoot, 'casper', 'initrd'));
    final liveInitrd = File(p.join(liveRoot, 'casper', 'initrd'));
    int? originalBootInitrdBytes;
    int? originalLiveInitrdBytes;
    var seedRenamed = false;
    var trustRenamed = false;
    var committed = false;

    try {
      if (await seedRoot.exists() || await trustRoot.exists()) {
        return const LinuxDriverStagingDeploymentResult.failure(
          'The Linux image already contains a reserved WinDeploy staging or trust directory.',
        );
      }
      if (!await bootInitrd.exists() || !await liveInitrd.exists()) {
        return const LinuxDriverStagingDeploymentResult.failure(
          'Both FAT32 and NTFS casper initrd copies are required for Linux staging.',
        );
      }
      if (await _hasArchiveTail(bootInitrd, bootstrapArchive) ||
          await _hasArchiveTail(liveInitrd, bootstrapArchive)) {
        return const LinuxDriverStagingDeploymentResult.failure(
          'The Linux image already contains this WinDeploy staging hook.',
        );
      }
      originalBootInitrdBytes = await bootInitrd.length();
      originalLiveInitrdBytes = await liveInitrd.length();

      await seedParent.create(recursive: true);
      await trustParent.create(recursive: true);
      await temporarySeedRoot.create(recursive: true);
      await temporaryTrustRoot.create(recursive: true);

      await _writeText(temporarySeedRoot, 'manifest.json', bundle.manifestJson);

      for (final entry in bundle.entries) {
        final source = File(_joinPosix(bundle.sourceRoot, entry.relativePath));
        final sourceType = await FileSystemEntity.type(
          source.path,
          followLinks: false,
        );
        if (sourceType != FileSystemEntityType.file) {
          return LinuxDriverStagingDeploymentResult.failure(
            'A Linux staging source changed before copying: ${entry.relativePath}',
          );
        }
        final destination = File(
          _joinPosix(temporarySeedRoot.path, 'payload/${entry.relativePath}'),
        );
        await destination.parent.create(recursive: true);
        await source.openRead().pipe(
          destination.openWrite(mode: FileMode.write),
        );
        final copiedSize = await destination.length();
        final copiedDigest = (await sha256.bind(destination.openRead()).first)
            .toString();
        if (copiedSize != entry.sizeBytes || copiedDigest != entry.sha256) {
          return LinuxDriverStagingDeploymentResult.failure(
            'A Linux staging source changed while copying: ${entry.relativePath}',
          );
        }
      }

      for (final entry in layout.trustFiles.entries) {
        await _writeText(temporaryTrustRoot, entry.key, entry.value);
      }
      if (!await _verifyBundleAndTrustRoots(
        bundle: bundle,
        layout: layout,
        seedRoot: temporarySeedRoot,
        trustRoot: temporaryTrustRoot,
        requireProtectedTrust: false,
      )) {
        return const LinuxDriverStagingDeploymentResult.failure(
          'Linux staging temporary roots failed content verification.',
        );
      }

      await temporarySeedRoot.rename(seedRoot.path);
      seedRenamed = true;
      await temporaryTrustRoot.rename(trustRoot.path);
      trustRenamed = true;
      await deploymentCheckpoint?.call('rootsRenamed');
      await _appendArchive(bootInitrd, bootstrapArchive);
      await deploymentCheckpoint?.call('bootInitrdAppended');
      await _appendArchive(liveInitrd, bootstrapArchive);
      await deploymentCheckpoint?.call('initrdsAppended');
      await _protectTrustRoot(
        trustRoot,
        additionalPaths: [bootInitrd.path, liveInitrd.path],
      );
      await deploymentCheckpoint?.call('trustProtected');

      final verified = await verifyDeployment(
        bundle: bundle,
        liveDrive: liveDrive,
        bootDrive: bootDrive,
      );
      if (!verified) {
        return const LinuxDriverStagingDeploymentResult.failure(
          'Linux first-boot staging did not pass post-write verification.',
        );
      }

      committed = true;
      log(
        'Linux payload staged and verified. The NTFS bundle contains no '
        'execution entry; the read-only FAT32 trust root and initrd-anchored '
        'digest gate first-boot installation.',
      );
      return const LinuxDriverStagingDeploymentResult.success();
    } catch (error) {
      return LinuxDriverStagingDeploymentResult.failure(
        'Linux first-boot staging failed: $error',
      );
    } finally {
      if (!committed) {
        if (originalBootInitrdBytes != null) {
          await _restoreFileLength(bootInitrd, originalBootInitrdBytes);
        }
        if (originalLiveInitrdBytes != null) {
          await _restoreFileLength(liveInitrd, originalLiveInitrdBytes);
        }
        if (trustRenamed) await _deleteDeploymentTree(trustRoot);
        if (seedRenamed) await _deleteDeploymentTree(seedRoot);
      }
      await _deleteDeploymentTree(temporaryTrustRoot);
      await _deleteDeploymentTree(temporarySeedRoot);
    }
  }

  Future<bool> verifyDeployment({
    required LinuxDriverStagingBundle bundle,
    required String liveDrive,
    required String bootDrive,
  }) async {
    try {
      final seedRoot = Directory(
        _joinPosix(_driveRoot(liveDrive), seedRelativePath),
      );
      final trustRoot = Directory(
        _joinPosix(_driveRoot(bootDrive), trustRelativePath),
      );
      final layout = _buildDeploymentLayout(bundle);
      if (!await _verifyBundleAndTrustRoots(
        bundle: bundle,
        layout: layout,
        seedRoot: seedRoot,
        trustRoot: trustRoot,
        requireProtectedTrust: Platform.isWindows,
      )) {
        return false;
      }

      final archive = _buildBootstrapArchive(layout.trustRootDigest);
      final bootInitrd = File(
        p.join(_driveRoot(bootDrive), 'casper', 'initrd'),
      );
      final liveInitrd = File(
        p.join(_driveRoot(liveDrive), 'casper', 'initrd'),
      );
      if (!await _hasArchiveTail(bootInitrd, archive) ||
          !await _hasArchiveTail(liveInitrd, archive)) {
        log('Linux staging verification failed: casper hook is missing.');
        return false;
      }
      if (Platform.isWindows &&
          (!await _windowsPathIsProtected(bootInitrd.path) ||
              !await _windowsPathIsProtected(liveInitrd.path))) {
        log(
          'Linux staging verification failed: initrd trust hooks are writable.',
        );
        return false;
      }
      return true;
    } catch (error) {
      log('Linux staging verification error: $error');
      return false;
    }
  }

  _LinuxStagingDeploymentLayout _buildDeploymentLayout(
    LinuxDriverStagingBundle bundle,
  ) {
    final bundleChecksums = StringBuffer()
      ..writeln('${bundle.manifestSha256}  manifest.json');
    final installPlan = StringBuffer();
    for (final entry in bundle.entries) {
      bundleChecksums.writeln('${entry.sha256}  payload/${entry.relativePath}');
      installPlan.writeln(
        '${entry.id}\t${entry.kind.name}\t${entry.relativePath}',
      );
    }
    final bundleChecksumText = bundleChecksums.toString();
    final bundleDigest = sha256
        .convert(utf8.encode(bundleChecksumText))
        .toString();
    final protectedFiles = <String, String>{
      'bundle.sha256': bundleChecksumText,
      '.prepared': '$bundleDigest\n',
      'install-plan.tsv': installPlan.toString(),
      'install.sh': _installerScript,
      serviceName: _systemdService,
      'README.txt': _trustReadme,
    };
    final trustChecksums = StringBuffer();
    for (final entry in protectedFiles.entries) {
      trustChecksums.writeln(
        '${sha256.convert(utf8.encode(entry.value))}  ${entry.key}',
      );
    }
    final trustChecksumText = trustChecksums.toString();
    final trustRootDigest = sha256
        .convert(utf8.encode(trustChecksumText))
        .toString();
    return _LinuxStagingDeploymentLayout(
      bundleChecksums: bundleChecksumText,
      bundleDigest: bundleDigest,
      trustRootDigest: trustRootDigest,
      trustFiles: {
        ...protectedFiles,
        'trust.sha256': trustChecksumText,
        '.trust-root': '$trustRootDigest\n',
      },
    );
  }

  Future<bool> _verifyBundleAndTrustRoots({
    required LinuxDriverStagingBundle bundle,
    required _LinuxStagingDeploymentLayout layout,
    required Directory seedRoot,
    required Directory trustRoot,
    required bool requireProtectedTrust,
  }) async {
    if (!await seedRoot.exists() || !await trustRoot.exists()) {
      log(
        'Linux staging verification failed: bundle or trust root is missing.',
      );
      return false;
    }

    final expectedBundlePaths = <String>{'manifest.json'};
    final manifestFile = File(p.join(seedRoot.path, 'manifest.json'));
    if (!await manifestFile.exists() ||
        await _fileDigest(manifestFile) != bundle.manifestSha256) {
      log('Linux staging verification failed: manifest digest mismatch.');
      return false;
    }
    final manifest = jsonDecode(await manifestFile.readAsString());
    if (manifest is! Map ||
        manifest['schemaVersion'] != 1 ||
        manifest['entries'] is! List ||
        (manifest['entries'] as List).length != bundle.entries.length) {
      log('Linux staging verification failed: manifest is invalid.');
      return false;
    }

    for (final entry in bundle.entries) {
      final relativePath = 'payload/${entry.relativePath}';
      expectedBundlePaths.add(relativePath);
      final staged = File(_joinPosix(seedRoot.path, relativePath));
      if (!await staged.exists() ||
          await staged.length() != entry.sizeBytes ||
          await _fileDigest(staged) != entry.sha256) {
        log(
          'Linux staging verification failed: payload mismatch for '
          '${entry.relativePath}.',
        );
        return false;
      }
    }
    if (!await _treeContainsExactly(seedRoot, expectedBundlePaths)) {
      log('Linux staging verification failed: NTFS bundle has extra files.');
      return false;
    }

    for (final entry in layout.trustFiles.entries) {
      final file = File(_joinPosix(trustRoot.path, entry.key));
      if (!await file.exists() ||
          await _fileDigest(file) !=
              sha256.convert(utf8.encode(entry.value)).toString()) {
        log(
          'Linux staging verification failed: FAT32 trust file changed: '
          '${entry.key}.',
        );
        return false;
      }
    }
    if (!await _treeContainsExactly(
      trustRoot,
      layout.trustFiles.keys.toSet(),
    )) {
      log(
        'Linux staging verification failed: FAT32 trust root has extra files.',
      );
      return false;
    }
    if ((await File(
              p.join(trustRoot.path, '.prepared'),
            ).readAsString()).trim() !=
            layout.bundleDigest ||
        (await File(
              p.join(trustRoot.path, '.trust-root'),
            ).readAsString()).trim() !=
            layout.trustRootDigest ||
        await File(p.join(trustRoot.path, 'bundle.sha256')).readAsString() !=
            layout.bundleChecksums) {
      log('Linux staging verification failed: trust root digest mismatch.');
      return false;
    }
    if (requireProtectedTrust && !await _trustRootIsProtected(trustRoot)) {
      log('Linux staging verification failed: FAT32 trust root is writable.');
      return false;
    }
    return true;
  }

  static String? _validateRelativePath(String relativePath) {
    if (relativePath.isEmpty ||
        relativePath.startsWith('/') ||
        p.posix.isAbsolute(relativePath)) {
      return 'Linux staging contains an invalid absolute path: $relativePath';
    }
    final components = p.posix.split(relativePath);
    if (components.any(
      (component) => component.isEmpty || component == '.' || component == '..',
    )) {
      return 'Linux staging path traversal is not allowed: $relativePath';
    }
    if (relativePath.codeUnits.any((unit) => unit < 0x20 || unit == 0x7f)) {
      return 'Linux staging paths cannot contain control characters.';
    }
    if (relativePath.length > 1000) {
      return 'Linux staging contains an excessively long path: $relativePath';
    }
    return null;
  }

  static LinuxStagingPayloadKind? _classify(String path) {
    final lower = path.toLowerCase();
    if (lower.endsWith('.deb')) return LinuxStagingPayloadKind.deb;
    if (lower.endsWith('.rpm')) return LinuxStagingPayloadKind.rpm;
    if (RegExp(
      r'\.pkg\.tar(?:\.(?:gz|xz|zst|bz2|lz4|lrz|lzo|z))?$',
      caseSensitive: false,
    ).hasMatch(lower)) {
      return LinuxStagingPayloadKind.archPackage;
    }
    if (lower.endsWith('.ko') || lower.endsWith('.ko.xz')) {
      return LinuxStagingPayloadKind.kernelModule;
    }
    if (lower.endsWith('.sh')) return LinuxStagingPayloadKind.shellScript;
    return null;
  }

  static String _unsupportedFileMessage(String relativePath) {
    final lower = relativePath.toLowerCase();
    if (lower.endsWith('.inf') ||
        lower.endsWith('.sys') ||
        lower.endsWith('.cat')) {
      return 'Windows INF/SYS/CAT drivers cannot be injected into Linux: $relativePath';
    }
    const dangerousExtensions = <String>[
      '.exe',
      '.dll',
      '.msi',
      '.bat',
      '.cmd',
      '.ps1',
      '.vbs',
      '.js',
      '.com',
      '.scr',
      '.reg',
      '.lnk',
      '.url',
    ];
    if (dangerousExtensions.any(lower.endsWith)) {
      return 'A dangerous or non-Linux executable type was rejected: $relativePath';
    }
    return 'Unsupported Linux staging file. Use deb/rpm/pkg.tar packages, '
        '.ko/.ko.xz modules, or explicit .sh scripts: $relativePath';
  }

  static String _moduleFileName(String relativePath) {
    final fileName = p.posix.basename(relativePath);
    return fileName.toLowerCase().endsWith('.ko.xz')
        ? fileName.substring(0, fileName.length - 6)
        : fileName.substring(0, fileName.length - 3);
  }

  static bool _isWithinRoot(String root, String candidate) {
    final normalizedRoot = p.normalize(root).toLowerCase();
    final normalizedCandidate = p.normalize(candidate).toLowerCase();
    return normalizedCandidate == normalizedRoot ||
        p.isWithin(normalizedRoot, normalizedCandidate);
  }

  Future<bool?> _isDirectoryOnTargetDisk(
    String directory,
    int targetDiskNumber,
  ) async {
    try {
      final result = await Process.run(
        'powershell',
        const [
          '-NoProfile',
          '-NonInteractive',
          '-ExecutionPolicy',
          'Bypass',
          '-Command',
          r'''$volume = Get-Volume -FilePath $env:WDS_SOURCE_PATH -ErrorAction Stop
$partitions = @(Get-Partition -Volume $volume -ErrorAction Stop)
if ($partitions.Count -ne 1) {
  throw "Source path did not resolve to exactly one physical partition."
}
[int]$partitions[0].DiskNumber''',
        ],
        environment: {...Platform.environment, 'WDS_SOURCE_PATH': directory},
      ).timeout(const Duration(seconds: 10));
      if (result.exitCode != 0) return null;
      final sourceDisk = int.tryParse(result.stdout.toString().trim());
      return sourceDisk == null ? null : sourceDisk == targetDiskNumber;
    } catch (_) {
      return null;
    }
  }

  static String _driveRoot(String drive) =>
      drive.endsWith(r'\') ? drive : '$drive\\';

  static String _joinPosix(String root, String relativePath) =>
      p.joinAll([root, ...p.posix.split(relativePath)]);

  static Future<void> _writeText(
    Directory root,
    String relativePath,
    String content,
  ) async {
    final file = File(_joinPosix(root.path, relativePath));
    await file.parent.create(recursive: true);
    await file.writeAsString(content, encoding: utf8, flush: true);
  }

  static Future<String> _fileDigest(File file) async =>
      (await sha256.bind(file.openRead()).first).toString();

  static Future<bool> _treeContainsExactly(
    Directory root,
    Set<String> expectedPaths,
  ) async {
    final actualPaths = <String>{};
    await for (final entity in root.list(recursive: true, followLinks: false)) {
      final type = await FileSystemEntity.type(entity.path, followLinks: false);
      if (type == FileSystemEntityType.directory) continue;
      if (type != FileSystemEntityType.file || entity is! File) return false;
      actualPaths.add(
        p.relative(entity.path, from: root.path).replaceAll('\\', '/'),
      );
    }
    return actualPaths.length == expectedPaths.length &&
        actualPaths.containsAll(expectedPaths);
  }

  Future<void> _protectTrustRoot(
    Directory trustRoot, {
    List<String> additionalPaths = const [],
  }) async {
    if (!Platform.isWindows) return;
    final paths = <String>[];
    await for (final entity in trustRoot.list(
      recursive: true,
      followLinks: false,
    )) {
      paths.add(entity.path);
    }
    paths.sort((left, right) => right.length.compareTo(left.length));
    paths
      ..add(trustRoot.path)
      ..addAll(additionalPaths);
    for (final path in paths) {
      final result = await Process.run('attrib', [
        '+R',
        '+H',
        '+S',
        path,
      ]).timeout(const Duration(seconds: 10));
      if (result.exitCode != 0) {
        throw StateError(
          'Failed to protect FAT32 trust root path: $path (${result.stderr})',
        );
      }
    }
  }

  Future<bool> _trustRootIsProtected(Directory trustRoot) async {
    if (!Platform.isWindows) return true;
    final paths = <String>[trustRoot.path];
    await for (final entity in trustRoot.list(
      recursive: true,
      followLinks: false,
    )) {
      paths.add(entity.path);
    }
    for (final path in paths) {
      if (!await _windowsPathIsProtected(path)) return false;
    }
    return true;
  }

  Future<bool> _windowsPathIsProtected(String path) async {
    try {
      final result = await Process.run('attrib', [
        path,
      ]).timeout(const Duration(seconds: 10));
      if (result.exitCode != 0) return false;
      final prefix = result.stdout
          .toString()
          .split(RegExp(r'\r?\n'))
          .first
          .padRight(20)
          .substring(0, 20)
          .toUpperCase();
      return prefix.contains('R') &&
          prefix.contains('H') &&
          prefix.contains('S');
    } catch (_) {
      return false;
    }
  }

  Future<void> _restoreFileLength(File file, int originalBytes) async {
    try {
      if (!await file.exists()) return;
      if (Platform.isWindows) {
        await Process.run('attrib', ['-R', '-H', '-S', file.path]).timeout(
          const Duration(seconds: 10),
          onTimeout: () => ProcessResult(0, -1, '', 'attrib timeout'),
        );
      }
      final currentBytes = await file.length();
      if (currentBytes < originalBytes) {
        log(
          'Linux staging rollback could not restore truncated initrd: '
          '${file.path}',
        );
        return;
      }
      if (currentBytes == originalBytes) return;
      final handle = await file.open(mode: FileMode.append);
      try {
        await handle.truncate(originalBytes);
      } finally {
        await handle.close();
      }
      log('Linux staging rollback restored initrd: ${file.path}');
    } catch (error) {
      log('Linux staging rollback failed for ${file.path}: $error');
    }
  }

  Future<void> _deleteDeploymentTree(Directory root) async {
    try {
      if (!await root.exists()) return;
      if (Platform.isWindows) {
        final paths = <String>[];
        await for (final entity in root.list(
          recursive: true,
          followLinks: false,
        )) {
          paths.add(entity.path);
        }
        paths.sort((left, right) => right.length.compareTo(left.length));
        paths.add(root.path);
        for (final path in paths) {
          await Process.run('attrib', ['-R', '-H', '-S', path]).timeout(
            const Duration(seconds: 10),
            onTimeout: () => ProcessResult(0, -1, '', 'attrib timeout'),
          );
        }
      }
      await root.delete(recursive: true);
    } catch (error) {
      log('Linux staging rollback could not remove ${root.path}: $error');
    }
  }

  Future<void> _appendArchive(File initrd, Uint8List archive) async {
    if (!await initrd.exists()) {
      throw StateError('casper initrd not found: ${initrd.path}');
    }
    await Process.run('attrib', ['-R', initrd.path]).timeout(
      const Duration(seconds: 10),
      onTimeout: () => ProcessResult(0, -1, '', 'attrib timeout'),
    );
    final output = initrd.openWrite(mode: FileMode.append);
    output.add(archive);
    await output.flush();
    await output.close();
    if (!await _hasArchiveTail(initrd, archive)) {
      throw StateError('The casper bootstrap archive could not be verified.');
    }
  }

  static Future<bool> _hasArchiveTail(File file, Uint8List archive) async {
    if (!await file.exists() || await file.length() < archive.length) {
      return false;
    }
    final randomAccess = await file.open();
    try {
      await randomAccess.setPosition(await file.length() - archive.length);
      final tail = await randomAccess.read(archive.length);
      if (tail.length != archive.length) return false;
      for (var index = 0; index < archive.length; index++) {
        if (tail[index] != archive[index]) return false;
      }
      return true;
    } finally {
      await randomAccess.close();
    }
  }

  static Uint8List _buildBootstrapArchive(String trustRootDigest) {
    final builder = BytesBuilder(copy: false);
    var inode = 1;
    void addEntry(String name, int mode, List<int> data) {
      final nameBytes = utf8.encode(name);
      final header = StringBuffer('070701')
        ..write(_cpioHex(inode++))
        ..write(_cpioHex(mode))
        ..write(_cpioHex(0))
        ..write(_cpioHex(0))
        ..write(_cpioHex(1))
        ..write(_cpioHex(0))
        ..write(_cpioHex(data.length))
        ..write(_cpioHex(0))
        ..write(_cpioHex(0))
        ..write(_cpioHex(0))
        ..write(_cpioHex(0))
        ..write(_cpioHex(nameBytes.length + 1))
        ..write(_cpioHex(0));
      builder.add(ascii.encode(header.toString()));
      builder.add(nameBytes);
      builder.addByte(0);
      _padCpio(builder);
      builder.add(data);
      _padCpio(builder);
    }

    addEntry('scripts', 0x41ed, const []);
    addEntry('scripts/casper-bottom', 0x41ed, const []);
    addEntry(
      'scripts/casper-bottom/99windeploy-linux-staging',
      0x81ed,
      utf8.encode(_casperBootstrapScript(trustRootDigest)),
    );
    addEntry('TRAILER!!!', 0, const []);
    while (builder.length % 512 != 0) {
      builder.addByte(0);
    }
    final archive = builder.takeBytes();
    if (!ascii.decode(archive, allowInvalid: true).contains(_archiveMarker)) {
      throw StateError('The generated casper bootstrap archive is invalid.');
    }
    return archive;
  }

  static String _cpioHex(int value) =>
      value.toRadixString(16).padLeft(8, '0').substring(0, 8);

  static void _padCpio(BytesBuilder builder) {
    while (builder.length % 4 != 0) {
      builder.addByte(0);
    }
  }

  static String _casperBootstrapScript(String trustRootDigest) =>
      _casperBootstrapScriptTemplate.replaceAll(
        '@TRUST_ROOT_SHA256@',
        trustRootDigest,
      );

  static const String _casperBootstrapScriptTemplate = r'''#!/bin/sh
# WDS-LTG-BOOTSTRAP-V1
set -u

PREREQ=""
prereqs() { echo "$PREREQ"; }
case "${1:-}" in
  prereqs) prereqs; exit 0 ;;
esac

SOURCE="/cdrom/windeploy-studio/linux-staging"
TRUST_DEVICE="/dev/disk/by-label/WDS_LTG"
TRUST_MOUNT="/run/windeploy-staging-trust"
TRUST="$TRUST_MOUNT/windeploy-studio/linux-staging-trust"
TARGET="/root/var/lib/windeploy-studio/linux-staging"
LOG="/root/var/log/windeploy-linux-staging-bootstrap.log"
INCOMING="${TARGET}.incoming"
UNIT="windeploy-linux-staging.service"
EXPECTED_TRUST_ROOT="@TRUST_ROOT_SHA256@"

mkdir -p /root/var/log /root/var/lib/windeploy-studio "$TRUST_MOUNT"
{
  echo "[$(date -u 2>/dev/null || echo boot)] WinDeploy Linux staging bootstrap"
  if ! command -v sha256sum >/dev/null 2>&1; then
    echo "sha256sum is unavailable; refusing first-boot staging"
    exit 0
  fi
  if [ ! -e "$TRUST_DEVICE" ] || \
     ! mount -o ro "$TRUST_DEVICE" "$TRUST_MOUNT"; then
    echo "FAT32 trust partition could not be mounted read-only"
    exit 0
  fi
  trap 'umount "$TRUST_MOUNT" >/dev/null 2>&1 || true' EXIT
  if [ ! -f "$SOURCE/manifest.json" ] || \
     [ ! -f "$TRUST/trust.sha256" ] || \
     [ ! -f "$TRUST/bundle.sha256" ] || \
     [ ! -f "$TRUST/install.sh" ] || \
     [ ! -f "$TRUST/$UNIT" ]; then
    echo "The NTFS bundle or FAT32 trust root is incomplete"
    exit 0
  fi
  actual_trust="$(sha256sum "$TRUST/trust.sha256" | awk '{print $1}')"
  if [ "$actual_trust" != "$EXPECTED_TRUST_ROOT" ]; then
    echo "FAT32 trust index does not match the initrd trust anchor"
    exit 0
  fi
  if ! (cd "$TRUST" && sha256sum -c trust.sha256); then
    echo "FAT32 trust root content verification failed"
    exit 0
  fi
  if ! (cd "$SOURCE" && sha256sum -c "$TRUST/bundle.sha256"); then
    echo "NTFS staging bundle verification failed before persistence copy"
    exit 0
  fi

  if [ -f "$TARGET/trust/.trust-root" ] && \
     cmp -s "$TRUST/.trust-root" "$TARGET/trust/.trust-root" && \
     (cd "$TARGET/trust" && sha256sum -c trust.sha256) && \
     (cd "$TARGET/bundle" && sha256sum -c "$TARGET/trust/bundle.sha256"); then
    echo "Matching staging seed is already present in writable persistence"
  else
    rm -rf "$INCOMING"
    mkdir -p "$INCOMING/bundle" "$INCOMING/trust"
    if ! cp -a "$SOURCE/." "$INCOMING/bundle/" || \
       ! cp -a "$TRUST/." "$INCOMING/trust/" || \
       ! (cd "$INCOMING/trust" && sha256sum -c trust.sha256) || \
       ! (cd "$INCOMING/bundle" && sha256sum -c "$INCOMING/trust/bundle.sha256"); then
      echo "Failed to copy and verify staging roots in writable persistence"
      rm -rf "$INCOMING"
      exit 0
    fi
    rm -rf "$TARGET"
    mv "$INCOMING" "$TARGET"
    mkdir -p "$TARGET/state"
    date -u > "$TARGET/state/bootstrapped"
    echo "Staging seed copied into writable persistence"
  fi

  chmod 0700 "$TARGET/trust/install.sh"
  chmod 0600 "$TARGET/trust/.prepared" "$TARGET/trust/.trust-root" \
    "$TARGET/trust/bundle.sha256" "$TARGET/trust/trust.sha256"
  if [ ! -f "$TARGET/state/complete" ]; then
    mkdir -p /root/etc/systemd/system/multi-user.target.wants
    cp "$TARGET/trust/$UNIT" "/root/etc/systemd/system/$UNIT"
    chmod 0644 "/root/etc/systemd/system/$UNIT"
    ln -sf "/etc/systemd/system/$UNIT" \
      "/root/etc/systemd/system/multi-user.target.wants/$UNIT"
    echo "First-boot systemd service enabled"
  else
    echo "Staging installation was already completed"
  fi
} >> "$LOG" 2>&1

exit 0
''';

  static const String _systemdService = r'''[Unit]
Description=WinDeploy Studio Linux first-boot staging installer
Documentation=file:/var/lib/windeploy-studio/linux-staging/trust/README.txt
After=local-fs.target
ConditionPathExists=/var/lib/windeploy-studio/linux-staging/trust/.trust-root
ConditionPathExists=!/var/lib/windeploy-studio/linux-staging/state/complete

[Service]
Type=oneshot
ExecStart=/bin/sh /var/lib/windeploy-studio/linux-staging/trust/install.sh
RemainAfterExit=yes
StandardOutput=append:/var/log/windeploy-linux-staging.log
StandardError=append:/var/log/windeploy-linux-staging.log

[Install]
WantedBy=multi-user.target
''';

  static const String _installerScript = r'''#!/bin/sh
set -u
umask 077

ROOT="/var/lib/windeploy-studio/linux-staging"
TRUST="$ROOT/trust"
BUNDLE="$ROOT/bundle"
STATE="$ROOT/state"
ITEM_STATE="$STATE/items"
LOG="/var/log/windeploy-linux-staging.log"
UNIT="windeploy-linux-staging.service"

mkdir -p "$ITEM_STATE" /var/log
exec >> "$LOG" 2>&1
echo "[$(date -u)] WinDeploy Linux staging installer started"

if ! command -v sha256sum >/dev/null 2>&1; then
  echo "sha256sum is unavailable; refusing to execute staged root content"
  echo "sha256sum unavailable" > "$STATE/last-failure"
  exit 1
fi

expected_trust="$(cat "$TRUST/.trust-root" 2>/dev/null || true)"
actual_trust="$(sha256sum "$TRUST/trust.sha256" 2>/dev/null | awk '{print $1}')"
if [ -z "$expected_trust" ] || [ "$expected_trust" != "$actual_trust" ] || \
   ! (cd "$TRUST" && sha256sum -c trust.sha256); then
  echo "FAT32-derived trust root integrity check failed"
  echo "trust root integrity failure" > "$STATE/last-failure"
  exit 1
fi

expected_bundle="$(cat "$TRUST/.prepared" 2>/dev/null || true)"
actual_bundle="$(sha256sum "$TRUST/bundle.sha256" 2>/dev/null | awk '{print $1}')"
if [ -z "$expected_bundle" ] || [ "$expected_bundle" != "$actual_bundle" ]; then
  echo "Bundle index integrity check failed"
  echo "bundle index integrity failure" > "$STATE/last-failure"
  exit 1
fi

if ! (cd "$BUNDLE" && sha256sum -c "$TRUST/bundle.sha256"); then
  echo "Staged payload integrity check failed"
  echo "payload integrity failure" > "$STATE/last-failure"
  exit 1
fi

install_package() {
  package_kind="$1"
  package_file="$2"
  case "$package_kind" in
    deb)
      command -v dpkg >/dev/null 2>&1 || return 20
      DEBIAN_FRONTEND=noninteractive dpkg --install "$package_file"
      ;;
    rpm)
      command -v rpm >/dev/null 2>&1 || return 21
      rpm -Uvh --replacepkgs "$package_file"
      ;;
    archPackage)
      command -v pacman >/dev/null 2>&1 || return 22
      pacman -U --noconfirm "$package_file"
      ;;
    *) return 23 ;;
  esac
}

install_module() {
  module_file="$1"
  if ! command -v modinfo >/dev/null 2>&1 || \
     ! command -v depmod >/dev/null 2>&1; then
    return 30
  fi
  running_kernel="$(uname -r)"
  vermagic="$(modinfo -F vermagic "$module_file" 2>/dev/null || true)"
  module_kernel="${vermagic%% *}"
  if [ -z "$module_kernel" ] || [ "$module_kernel" != "$running_kernel" ]; then
    echo "Kernel module does not match running kernel: $module_file ($module_kernel != $running_kernel)"
    return 31
  fi
  module_name="$(modinfo -F name "$module_file" 2>/dev/null || true)"
  [ -n "$module_name" ] || return 32
  module_dir="/lib/modules/$running_kernel/extra/windeploy-studio"
  mkdir -p "$module_dir" /etc/modules-load.d
  module_target="$module_dir/$(basename "$module_file")"
  cp "$module_file" "$module_target" || return 33
  chmod 0644 "$module_target"
  depmod -a "$running_kernel" || return 34
  if ! grep -Fqx "$module_name" /etc/modules-load.d/windeploy-studio.conf 2>/dev/null; then
    echo "$module_name" >> /etc/modules-load.d/windeploy-studio.conf
  fi
  modprobe "$module_name" 2>/dev/null || \
    echo "Module installed; loading is deferred until compatible hardware is available: $module_name"
}

run_item() {
  item_kind="$1"
  item_file="$2"
  case "$item_kind" in
    deb|rpm|archPackage) install_package "$item_kind" "$item_file" ;;
    kernelModule) install_module "$item_file" ;;
    shellScript) /bin/sh "$item_file" ;;
    *) return 40 ;;
  esac
}

failures=0
tab="$(printf '\t')"
while IFS="$tab" read -r item_id item_kind relative_path; do
  [ -n "$item_id" ] || continue
  item_file="$BUNDLE/payload/$relative_path"
  done_marker="$ITEM_STATE/$item_id.done"
  failed_marker="$ITEM_STATE/$item_id.failed"
  if [ -f "$done_marker" ]; then
    echo "Already completed: $relative_path"
    continue
  fi
  echo "Installing $item_kind: $relative_path"
  if run_item "$item_kind" "$item_file"; then
    date -u > "$done_marker"
    rm -f "$failed_marker"
  else
    status=$?
    failures=$((failures + 1))
    echo "Exit $status while installing $relative_path" | tee "$failed_marker"
  fi
done < "$TRUST/install-plan.tsv"

if [ "$failures" -eq 0 ]; then
  date -u > "$STATE/complete"
  rm -f "$STATE/last-failure"
  systemctl disable "$UNIT" >/dev/null 2>&1 || true
  echo "All staged Linux content installed successfully"
  exit 0
fi

echo "$failures staged item(s) failed; successful items will not repeat" | \
  tee "$STATE/last-failure"
exit 1
''';

  static const String _trustReadme =
      '''WinDeploy Studio Linux staging trust root

This read-only directory is created on the FAT32 WDS_LTG boot partition. The
NTFS WDS_LIVE partition contains only manifest.json and payload data; it has no
installer, systemd unit, install plan, or checksum authority.

The initrd hook contains the SHA-256 of trust.sha256. It mounts WDS_LTG
read-only, validates this trust root, and validates the NTFS bundle before any
content is copied into persistent storage. The trusted install.sh repeats both
checks before running staged content as root. Successful items receive
individual state markers and are not repeated. Failed items are retried on a
later boot. Logs are written to:

  /var/log/windeploy-linux-staging-bootstrap.log
  /var/log/windeploy-linux-staging.log

Kernel modules are installed only when their vermagic matches the running
kernel. RPM and Arch packages require their native package manager; the current
Linux To Go implementation remains limited to Ubuntu/casper images.
''';
}

class _LinuxStagingDeploymentLayout {
  final String bundleChecksums;
  final String bundleDigest;
  final String trustRootDigest;
  final Map<String, String> trustFiles;

  const _LinuxStagingDeploymentLayout({
    required this.bundleChecksums,
    required this.bundleDigest,
    required this.trustRootDigest,
    required this.trustFiles,
  });
}
