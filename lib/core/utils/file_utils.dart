import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class FileUtils {
  FileUtils._();

  static Future<String> getDownloadDirectory() async {
    final dir = await getApplicationSupportDirectory();
    final downloadDir = Directory(p.join(dir.path, 'downloads'));
    if (!await downloadDir.exists()) {
      await downloadDir.create(recursive: true);
    }
    return downloadDir.path;
  }

  static Future<String> getTempDirectory() async {
    final dir = await getTemporaryDirectory();
    return dir.path;
  }

  static String formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  static String getFileName(String path) {
    return p.basename(path);
  }

  static String getFileExtension(String path) {
    return p.extension(path).toLowerCase();
  }

  static bool isIsoFile(String path) {
    return getFileExtension(path) == '.iso';
  }

  static Future<bool> fileExists(String path) async {
    return File(path).exists();
  }

  static Future<int> getFileSize(String path) async {
    final file = File(path);
    if (await file.exists()) {
      return await file.length();
    }
    return 0;
  }

  static Future<void> deleteFile(String path) async {
    final file = File(path);
    if (await file.exists()) {
      await file.delete();
    }
  }
}
