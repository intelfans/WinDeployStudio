import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:ui';

import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/mirror/models/mirror_models.dart';

typedef KnownImagesLoader = Future<List<KnownImage>> Function();

/// The successful result of checking a local file against the bundled image
/// catalog. Unknown files intentionally have no result.
class KnownIsoVerification {
  final KnownImage image;
  final String sha256;
  final String md5;

  const KnownIsoVerification({
    required this.image,
    required this.sha256,
    required this.md5,
  });
}

class _FileDigests {
  final String sha256;
  final String md5;

  const _FileDigests({required this.sha256, required this.md5});
}

class _DigestSink implements Sink<crypto.Digest> {
  crypto.Digest? value;

  @override
  void add(crypto.Digest data) {
    value = data;
  }

  @override
  void close() {}
}

/// Silently identifies a local ISO if either of its streamed checksums is
/// present in the bundled image catalog. Digesting runs in a worker isolate so
/// a multi-gigabyte ISO never blocks Flutter's UI isolate. It deliberately
/// does not treat an unknown image or an I/O error as a failed validation.
class KnownIsoVerificationService {
  final KnownImagesLoader? knownImagesLoader;
  Future<List<KnownImage>>? _knownImages;

  KnownIsoVerificationService({this.knownImagesLoader});

  Future<KnownIsoVerification?> verify(String filePath, Locale locale) async {
    try {
      final knownImages = await _loadKnownImages();
      final visibleImages = knownImages
          .where((image) => image.isVisibleInLocale(locale))
          .toList(growable: false);
      if (visibleImages.isEmpty) return null;

      final digests = await _readDigests(filePath);
      if (digests == null) return null;

      for (final image in visibleImages) {
        if (image.matches(sha256: digests.sha256, md5: digests.md5)) {
          return KnownIsoVerification(
            image: image,
            sha256: digests.sha256,
            md5: digests.md5,
          );
        }
      }
    } catch (_) {
      // Local image recognition must never interrupt an ISO selection flow.
    }
    return null;
  }

  Future<List<KnownImage>> _loadKnownImages() {
    return _knownImages ??= (knownImagesLoader ?? _loadBundledKnownImages)();
  }

  Future<List<KnownImage>> _loadBundledKnownImages() async {
    final raw = await rootBundle.loadString('data/mirrors.json');
    final decoded = jsonDecode(raw);
    if (decoded is! Map<String, dynamic>) return const [];
    return MirrorListData.fromJson(decoded).knownImages;
  }

  Future<_FileDigests?> _readDigests(String filePath) async {
    try {
      final values = await Isolate.run(() => _readDigestsInWorker(filePath));
      if (values == null) return null;
      return _FileDigests(sha256: values['sha256']!, md5: values['md5']!);
    } catch (_) {
      return null;
    }
  }
}

/// This must stay top-level so it can be run in a Dart worker isolate.
Future<Map<String, String>?> _readDigestsInWorker(String filePath) async {
  final file = File(filePath);
  if (!await file.exists()) return null;

  final sha256Sink = _DigestSink();
  final md5Sink = _DigestSink();
  final sha256Conversion = crypto.sha256.startChunkedConversion(sha256Sink);
  final md5Conversion = crypto.md5.startChunkedConversion(md5Sink);

  await for (final chunk in file.openRead()) {
    sha256Conversion.add(chunk);
    md5Conversion.add(chunk);
  }
  sha256Conversion.close();
  md5Conversion.close();

  final sha256 = sha256Sink.value?.toString();
  final md5 = md5Sink.value?.toString();
  if (sha256 == null || md5 == null) return null;
  return <String, String>{'sha256': sha256, 'md5': md5};
}

final knownIsoVerificationServiceProvider =
    Provider<KnownIsoVerificationService>((ref) {
      return KnownIsoVerificationService();
    });
