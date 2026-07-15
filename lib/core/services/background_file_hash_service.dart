import 'dart:io';
import 'dart:isolate';

import 'package:crypto/crypto.dart';

/// Computes file hashes without monopolizing Flutter's UI isolate.
///
/// Small files avoid isolate startup overhead. Installation media, squashfs
/// payloads, WIMs, and large driver packages are hashed in a worker isolate so
/// their integrity checks do not make the desktop window unresponsive.
class BackgroundFileHashService {
  static const int largeFileThresholdBytes = 1024 * 1024;

  const BackgroundFileHashService._();

  static Future<String> sha256File(File file) async {
    final size = await file.length();
    if (size < largeFileThresholdBytes) {
      return _sha256File(file.path);
    }
    return Isolate.run(() => _sha256File(file.path));
  }
}

/// Top-level worker entry point required by [Isolate.run].
Future<String> _sha256File(String path) async {
  final file = File(path);
  return (await sha256.bind(file.openRead()).first).toString();
}
