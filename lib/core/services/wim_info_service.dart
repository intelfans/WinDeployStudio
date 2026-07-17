import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:xml/xml.dart';

import 'windows_system_environment.dart';

class WimImageInfo {
  final int index;
  final String name;
  final String description;
  final int sizeBytes;
  final String architecture;
  final String edition;
  final String version;
  final String build;
  final String installationType;
  final String language;

  const WimImageInfo({
    required this.index,
    required this.name,
    required this.description,
    required this.sizeBytes,
    required this.architecture,
    required this.edition,
    required this.version,
    required this.build,
    required this.installationType,
    required this.language,
  });

  Map<String, dynamic> toMap() => {
    'index': index,
    'name': name,
    'description': description,
    'size': sizeBytes > 0 ? _formatSize(sizeBytes) : '',
    'architecture': architecture,
    'edition': edition,
    'version': version,
    'build': build,
    'installationType': installationType,
    'language': language,
  };

  static String _formatSize(int bytes) {
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(0)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }
}

class WimInfoService {
  const WimInfoService._();

  /// Reads image metadata without leaving an untracked helper process behind.
  ///
  /// [cancellationSignal] is optional so deployment paths keep their existing
  /// behavior. ISO-selection callers provide it to stop the helper before an
  /// older ISO is dismounted for a newer selection.
  static Future<List<WimImageInfo>> readImages(
    String imagePath, {
    Future<void>? cancellationSignal,
  }) async {
    final helperPath = p.join(
      p.dirname(Platform.resolvedExecutable),
      'wds_wim_info_helper.exe',
    );
    if (!await File(helperPath).exists()) {
      throw StateError('WIM metadata helper is missing.');
    }

    final process = await Process.start(helperPath, [
      imagePath,
    ], environment: WindowsSystemEnvironment.withSystemRoot());
    final stdout = process.stdout
        .transform(const SystemEncoding().decoder)
        .join();
    final stderr = process.stderr
        .transform(const SystemEncoding().decoder)
        .join();
    final exitCode = process.exitCode;
    final outcome = await Future.any<_WimProcessOutcome>([
      exitCode.then(_WimProcessOutcome.exited),
      Future<_WimProcessOutcome>.delayed(
        const Duration(seconds: 60),
        _WimProcessOutcome.timedOut,
      ),
      if (cancellationSignal != null)
        cancellationSignal.then((_) => const _WimProcessOutcome.cancelled()),
    ]);

    if (!outcome.didExit) {
      await _terminateHelper(process);
      try {
        await exitCode.timeout(const Duration(seconds: 5));
      } catch (_) {
        // Preserve a bounded selection path even if a third-party helper
        // does not acknowledge normal process termination promptly.
      }
      await stdout.timeout(const Duration(seconds: 2), onTimeout: () => '');
      await stderr.timeout(const Duration(seconds: 2), onTimeout: () => '');
      if (outcome.cancelled) {
        throw const _WimInfoReadCancelled();
      }
      throw StateError('WIM metadata helper timed out.');
    }

    final output = await stdout;
    final error = await stderr;
    if (outcome.exitCode != 0) {
      throw StateError(error.trim());
    }
    return parseHelperOutput(output);
  }

  static Future<void> _terminateHelper(Process process) async {
    try {
      await Process.run(
        WindowsSystemEnvironment.taskkillExecutable,
        ['/F', '/T', '/PID', '${process.pid}'],
        environment: WindowsSystemEnvironment.withSystemRoot(),
      ).timeout(const Duration(seconds: 5));
    } catch (_) {
      process.kill();
    }
  }

  /// Parses the line-oriented output emitted by the native WIMGAPI helper.
  ///
  /// Keeping this separate from process execution gives ESD-backed Windows
  /// images the same metadata parsing path as regular WIM installers.
  static List<WimImageInfo> parseHelperOutput(String output) {
    final images = <WimImageInfo>[];
    for (final line in const LineSplitter().convert(output)) {
      final parts = line.trim().split('|');
      if (parts.length != 3 || parts.first != 'IMAGE') continue;
      final index = int.tryParse(parts[1]);
      if (index == null) continue;
      final xmlText = utf8.decode(base64Decode(parts[2]));
      images.add(_parseImage(index, XmlDocument.parse(xmlText)));
    }
    if (images.isEmpty) throw StateError('No WIM image metadata was returned.');
    return images;
  }

  static WimImageInfo _parseImage(int index, XmlDocument document) {
    String value(String name) {
      final matches = document.descendants.whereType<XmlElement>().where(
        (element) => element.name.local.toUpperCase() == name,
      );
      return matches.isEmpty ? '' : matches.first.innerText.trim();
    }

    final major = value('MAJOR');
    final minor = value('MINOR');
    final build = value('BUILD');
    final spBuild = value('SPBUILD');
    final version = [
      major,
      minor,
      build,
      spBuild,
    ].where((part) => part.isNotEmpty).join('.');
    return WimImageInfo(
      index: index,
      name: value('NAME'),
      description: value('DESCRIPTION'),
      sizeBytes: int.tryParse(value('TOTALBYTES')) ?? 0,
      architecture: _architectureName(value('ARCH')),
      edition: value('EDITIONID'),
      version: version,
      build: build,
      installationType: value('INSTALLATIONTYPE'),
      language: value('LANGUAGE'),
    );
  }

  static String _architectureName(String value) => switch (value) {
    '0' => 'x86',
    '5' => 'ARM',
    '9' => 'x64',
    '12' => 'ARM64',
    _ => value,
  };
}

class _WimInfoReadCancelled implements Exception {
  const _WimInfoReadCancelled();
}

class _WimProcessOutcome {
  final int? exitCode;
  final bool timedOut;

  const _WimProcessOutcome._({this.exitCode, this.timedOut = false});

  const _WimProcessOutcome.cancelled() : this._();
  const _WimProcessOutcome.timedOut() : this._(timedOut: true);
  _WimProcessOutcome.exited(int exitCode) : this._(exitCode: exitCode);

  bool get didExit => exitCode != null;
  bool get cancelled => !didExit && !timedOut;
}
