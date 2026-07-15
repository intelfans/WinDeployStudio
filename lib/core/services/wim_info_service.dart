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

  static Future<List<WimImageInfo>> readImages(String imagePath) async {
    final helperPath = p.join(
      p.dirname(Platform.resolvedExecutable),
      'wds_wim_info_helper.exe',
    );
    if (!await File(helperPath).exists()) {
      throw StateError('WIM metadata helper is missing.');
    }
    final result = await Process.run(
      helperPath,
      [imagePath],
      environment: WindowsSystemEnvironment.withSystemRoot(),
    ).timeout(const Duration(seconds: 60));
    if (result.exitCode != 0) {
      throw StateError(result.stderr.toString().trim());
    }

    return parseHelperOutput(result.stdout.toString());
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
