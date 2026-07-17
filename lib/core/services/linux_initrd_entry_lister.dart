import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

/// Bounded, read-only initrd archive listing result.
///
/// Windows ships libarchive as `System32\\tar.exe`. Calling it with a fixed
/// argument vector lets the preflight inspect compressed CPIO initrds without
/// extracting files or accepting an unbounded tool response.
class LinuxInitrdEntryListing {
  final bool success;
  final Set<String> entries;
  final String? diagnostic;

  const LinuxInitrdEntryListing._({
    required this.success,
    required this.entries,
    this.diagnostic,
  });

  const LinuxInitrdEntryListing.success(Set<String> entries)
    : this._(success: true, entries: entries);

  const LinuxInitrdEntryListing.failure(String diagnostic)
    : this._(success: false, entries: const {}, diagnostic: diagnostic);
}

abstract interface class LinuxInitrdEntryLister {
  Future<LinuxInitrdEntryListing> list(File initrd);
}

/// Lists archive entries through the system-owned libarchive binary.
///
/// No archive contents are extracted. Any malformed archive, unavailable
/// system tool, timeout, non-zero exit, or output limit is a failed-closed
/// result and must not make an image eligible for a destructive operation.
class LinuxInitrdEntryListerService implements LinuxInitrdEntryLister {
  static const _maxStdoutBytes = 8 * 1024 * 1024;
  static const _maxStderrBytes = 256 * 1024;
  static const _maxEntries = 100000;
  static const _timeout = Duration(seconds: 30);

  const LinuxInitrdEntryListerService();

  @override
  Future<LinuxInitrdEntryListing> list(File initrd) async {
    if (await FileSystemEntity.type(initrd.path, followLinks: false) !=
        FileSystemEntityType.file) {
      return const LinuxInitrdEntryListing.failure(
        'The initrd is not a regular file.',
      );
    }

    final tar = await _systemTarPath();
    if (tar == null) {
      return const LinuxInitrdEntryListing.failure(
        'The system archive inspector is unavailable.',
      );
    }

    Process? process;
    var processExited = false;
    try {
      final activeProcess = await Process.start(tar, [
        '-tf',
        initrd.path,
      ], runInShell: false);
      process = activeProcess;
      var overflow = false;
      void stopForOverflow() {
        overflow = true;
        activeProcess.kill(ProcessSignal.sigkill);
      }

      final stdoutFuture = _readBounded(
        activeProcess.stdout,
        maximumBytes: _maxStdoutBytes,
        onOverflow: stopForOverflow,
      );
      final stderrFuture = _readBounded(
        activeProcess.stderr,
        maximumBytes: _maxStderrBytes,
        onOverflow: stopForOverflow,
      );

      int exitCode;
      try {
        exitCode = await activeProcess.exitCode.timeout(_timeout);
        processExited = true;
      } on TimeoutException {
        activeProcess.kill(ProcessSignal.sigkill);
        await Future.wait([stdoutFuture, stderrFuture]);
        processExited = true;
        return const LinuxInitrdEntryListing.failure(
          'The initrd archive inspection timed out.',
        );
      }

      final output = await stdoutFuture;
      final error = await stderrFuture;
      if (overflow) {
        return const LinuxInitrdEntryListing.failure(
          'The initrd archive listing exceeded its safety limit.',
        );
      }
      if (exitCode != 0) {
        final detail = utf8.decode(error, allowMalformed: true).trim();
        return LinuxInitrdEntryListing.failure(
          detail.isEmpty
              ? 'The initrd archive inspector rejected the image.'
              : 'The initrd archive inspector rejected the image: $detail',
        );
      }

      final entries = <String>{};
      for (final rawLine
          in utf8.decode(output, allowMalformed: true).split('\n')) {
        final normalized = _normalizeEntry(rawLine);
        if (normalized == null) continue;
        entries.add(normalized);
        if (entries.length > _maxEntries) {
          return const LinuxInitrdEntryListing.failure(
            'The initrd archive contains too many entries to inspect safely.',
          );
        }
      }
      if (entries.isEmpty) {
        return const LinuxInitrdEntryListing.failure(
          'The initrd archive contains no usable entries.',
        );
      }
      return LinuxInitrdEntryListing.success(entries);
    } catch (error) {
      process?.kill(ProcessSignal.sigkill);
      return LinuxInitrdEntryListing.failure(
        'The initrd archive inspection failed: $error',
      );
    } finally {
      if (process != null && !processExited) {
        process.kill(ProcessSignal.sigkill);
      }
    }
  }

  Future<String?> _systemTarPath() async {
    if (!Platform.isWindows) return null;
    final windowsRoot =
        Platform.environment['SystemRoot'] ?? Platform.environment['WINDIR'];
    if (windowsRoot == null || windowsRoot.isEmpty) return null;
    final path = p.join(windowsRoot, 'System32', 'tar.exe');
    return await File(path).exists() ? path : null;
  }

  static Future<List<int>> _readBounded(
    Stream<List<int>> stream, {
    required int maximumBytes,
    required void Function() onOverflow,
  }) async {
    final bytes = BytesBuilder(copy: false);
    await for (final chunk in stream) {
      if (bytes.length + chunk.length > maximumBytes) {
        onOverflow();
        break;
      }
      bytes.add(chunk);
    }
    return bytes.takeBytes();
  }

  static String? _normalizeEntry(String raw) {
    final value = raw.trim().replaceAll('\\', '/');
    if (value.isEmpty || value.contains('\u0000')) return null;
    final withoutPrefix = value.replaceFirst(RegExp(r'^(?:\./)+'), '');
    if (withoutPrefix.isEmpty ||
        withoutPrefix.startsWith('/') ||
        withoutPrefix.split('/').any((segment) => segment == '..')) {
      return null;
    }
    return withoutPrefix.toLowerCase();
  }
}
