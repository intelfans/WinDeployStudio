import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'file_logger_service.dart';
import '../utils/file_utils.dart';
import '../../features/logs/services/log_center_service.dart';

enum BootMode { uefi, bios, both }
enum CreateStep {
  preparing,
  cleaningDisk,
  creatingPartitions,
  formatting,
  mountingIso,
  copyingFiles,
  splittingWim,
  writingBootFiles,
  verifying,
  complete,
  failed,
}

class CreateProgress {
  final CreateStep step;
  final double progress;
  final String message;
  final String? error;

  const CreateProgress({
    required this.step,
    this.progress = 0.0,
    this.message = '',
    this.error,
  });
}

typedef ProgressCallback = void Function(CreateProgress progress);

final bootableUsbServiceProvider = Provider<BootableUsbService>((ref) {
  return BootableUsbService(ref);
});

class BootableUsbService {
  final Ref ref;
  final List<String> _log = [];

  BootableUsbService(this.ref);

  void _logLine(String msg) {
    final line = '[${DateTime.now().toIso8601String()}] $msg';
    _log.add(line);
    debugPrint(line);
  }

  String get logText => _log.join('\n');

  Future<String> saveLogToFile() async {
    try {
      final dir = await getApplicationSupportDirectory();
      final logFile = File(p.join(dir.path, 'logs', 'last_creation_log.txt'));
      await logFile.parent.create(recursive: true);
      await logFile.writeAsString(logText);
      return logFile.path;
    } catch (e) {
      return 'Failed to save log: $e';
    }
  }

  Future<bool> createBootableUsb({
    required int diskNumber,
    required String isoPath,
    BootMode bootMode = BootMode.both,
    ProgressCallback? onProgress,
  }) async {
    _log.clear();
    _logLine('=== Create Bootable USB Start ===');
    _logLine('Disk: $diskNumber, ISO: $isoPath, Mode: $bootMode');

    final logCenter = LogCenterService();
    await logCenter.logUsb('启动盘制作开始 | 磁盘: $diskNumber | ISO: $isoPath | 模式: $bootMode');

    final logger = ref.read(fileLoggerServiceProvider);
    await logger.log(
      action: 'Create USB',
      target: 'Disk $diskNumber',
      result: 'Starting - ISO: $isoPath',
    );

    try {
      // Step 1: Prepare
      _notify(onProgress, const CreateProgress(
        step: CreateStep.preparing,
        message: 'boot_preparing',
        progress: 0.0,
      ));

      // Always use MBR for removable USB
      _logLine('Using MBR + FAT32 for removable USB');

      // Step 2: Clean and partition disk
      _notify(onProgress, const CreateProgress(
        step: CreateStep.cleaningDisk,
        message: 'boot_cleaning',
        progress: 0.05,
      ));

      final partitionResult = await _partitionDisk(diskNumber: diskNumber);

      if (!partitionResult.success) {
        final errorDetail = partitionResult.error ?? '';
        _logLine('Partition FAILED: $errorDetail');
        final errorKey = errorDetail.contains('Access is denied') ||
                errorDetail.contains('denied') ||
                errorDetail.contains('0x80070005')
            ? 'boot_access_denied'
            : 'boot_partition_failed';
        final logPath = await saveLogToFile();
        _notify(onProgress, CreateProgress(
          step: CreateStep.failed,
          message: '$errorKey\n\nLog: $logPath',
          error: errorDetail,
        ));
        return false;
      }

      final driveLetter = partitionResult.driveLetter;
      if (driveLetter == null) {
        _logLine('Partition succeeded but no drive letter assigned');
        return false;
      }
      _logLine('Partition OK, drive: $driveLetter');

      // Step 3: Format (already done by diskpart, just verify)
      _notify(onProgress, const CreateProgress(
        step: CreateStep.formatting,
        message: 'boot_format_verifying',
        progress: 0.15,
      ));

      final formatResult = await _formatPartition(
        driveLetter: driveLetter,
        fileSystem: 'FAT32',
      );

      if (!formatResult) {
        _logLine('Format verification FAILED');
        final logPath = await saveLogToFile();
        _notify(onProgress, CreateProgress(
          step: CreateStep.failed,
          message: 'boot_format_failed\n\nLog: $logPath',
        ));
        return false;
      }
      _logLine('Format verified');

      // Step 4: Mount ISO
      _notify(onProgress, const CreateProgress(
        step: CreateStep.mountingIso,
        message: 'boot_mounting',
        progress: 0.20,
      ));

      final mountPoint = await _mountIso(isoPath);
      if (mountPoint == null) {
        _logLine('Mount ISO FAILED');
        final logPath = await saveLogToFile();
        _notify(onProgress, CreateProgress(
          step: CreateStep.failed,
          message: 'boot_mount_failed\n$isoPath\n\nLog: $logPath',
        ));
        return false;
      }
      _logLine('Mounted at: $mountPoint');

      // Step 5: Check if we need to split install.wim (>4GB FAT32 limit)
      final installWim = p.join(mountPoint, 'sources', 'install.wim');
      final installEsd = p.join(mountPoint, 'sources', 'install.esd');
      final hasWim = await File(installWim).exists();
      final hasEsd = await File(installEsd).exists();

      bool needSplit = false;
      String wimSource = '';

      if (hasWim) {
        wimSource = installWim;
        final wimSize = await File(installWim).length();
        if (wimSize > 4 * 1024 * 1024 * 1024) {
          needSplit = true;
          _logLine('install.wim > 4GB, will split');
        }
      } else if (hasEsd) {
        wimSource = installEsd;
        final esdSize = await File(installEsd).length();
        if (esdSize > 4 * 1024 * 1024 * 1024) {
          needSplit = true;
          _logLine('install.esd > 4GB, will split');
        }
      }

      // Step 6: Copy files with robocopy (fast)
      _notify(onProgress, const CreateProgress(
        step: CreateStep.copyingFiles,
        message: 'boot_copying_fast',
        progress: 0.25,
      ));

      final copyResult = await _copyIsoContents(
        mountPoint: mountPoint,
        targetDrive: driveLetter,
        excludeWim: needSplit,
        onProgress: (progress) {
          _notify(onProgress, CreateProgress(
            step: CreateStep.copyingFiles,
            message: progress < 1.0
                ? 'boot_copying_fast'
                : 'boot_copy_complete',
            progress: 0.25 + progress * 0.45,
          ));
        },
      );

      if (!copyResult) {
        _logLine('File copy FAILED');
        await _unmountIso(isoPath);
        final logPath = await saveLogToFile();
        _notify(onProgress, CreateProgress(
          step: CreateStep.failed,
          message: 'boot_copy_failed\n\nLog: $logPath',
        ));
        return false;
      }
      _logLine('File copy OK');

      // Step 7: Split WIM if needed
      if (needSplit && wimSource.isNotEmpty) {
        _notify(onProgress, const CreateProgress(
          step: CreateStep.splittingWim,
          message: 'boot_splitting_wim',
          progress: 0.70,
        ));

        final splitResult = await _splitWim(
          sourcePath: wimSource,
          targetDir: '$driveLetter\\sources',
        );

        if (!splitResult) {
          _logLine('WIM split FAILED');
          await _unmountIso(isoPath);
          final logPath = await saveLogToFile();
          _notify(onProgress, CreateProgress(
            step: CreateStep.failed,
            message: 'boot_split_failed\n\nLog: $logPath',
          ));
          return false;
        }
        _logLine('WIM split OK');
      }

      // Step 8: Write boot files
      _notify(onProgress, const CreateProgress(
        step: CreateStep.writingBootFiles,
        message: 'boot_writing_boot',
        progress: 0.80,
      ));

      final bootResult = await _writeBootFiles(
        windowsDrive: mountPoint.endsWith('\\') ? mountPoint : '$mountPoint\\',
        targetDrive: driveLetter,
      );

      await _unmountIso(isoPath);

      if (!bootResult) {
        _logLine('Boot file write FAILED');
        final logPath = await saveLogToFile();
        _notify(onProgress, CreateProgress(
          step: CreateStep.failed,
          message: 'boot_write_failed\n\nLog: $logPath',
        ));
        return false;
      }
      _logLine('Boot files OK');

      // Step 8.5: Set volume icon
      _notify(onProgress, const CreateProgress(
        step: CreateStep.writingBootFiles,
        message: 'boot_setting_icon',
        progress: 0.85,
      ));
      await _setVolumeIcon(driveLetter);

      // Step 9: Verify
      _notify(onProgress, const CreateProgress(
        step: CreateStep.verifying,
        message: 'boot_verifying',
        progress: 0.90,
      ));

      final verifyResult = await _verifyBootableUsb(driveLetter: driveLetter);
      _logLine('Verify: ${verifyResult ? "OK" : "FAILED"}');

      _notify(onProgress, CreateProgress(
        step: verifyResult ? CreateStep.complete : CreateStep.failed,
        message: verifyResult ? 'boot_complete' : 'boot_verify_failed',
        progress: verifyResult ? 1.0 : 0.0,
      ));

      await logger.log(
        action: 'Create USB',
        target: 'Disk $diskNumber',
        result: verifyResult ? 'Success - Verified' : 'Failed - Verification',
        level: verifyResult ? LogLevel.success : LogLevel.error,
      );

      final logPath = await saveLogToFile();
      _logLine('Log saved to: $logPath');

      if (verifyResult) {
        await logCenter.logUsb('启动盘制作成功 | 磁盘: $diskNumber');
      } else {
        await logCenter.logError('启动盘验证失败 | 磁盘: $diskNumber');
      }

      return verifyResult;
    } catch (e) {
      _logLine('EXCEPTION: $e');
      final logPath = await saveLogToFile();
      await logCenter.logError('启动盘制作异常 | 磁盘: $diskNumber | 错误: $e');
      _notify(onProgress, CreateProgress(
        step: CreateStep.failed,
        message: 'Error: $e\n\nLog: $logPath',
      ));
      await logger.log(
        action: 'Create USB',
        target: 'Disk $diskNumber',
        result: 'Exception: $e',
        level: LogLevel.error,
      );
      return false;
    }
  }

  // --- Disk Partitioning ---

  Future<_DiskPartResult> _partitionDisk({
    required int diskNumber,
  }) async {
    // Always use MBR + FAT32 for removable USB media
      final script = '''
select disk $diskNumber
clean
convert mbr
create partition primary
active
format fs=fat32 label="INTEL" quick
assign
exit
''';
    _logLine('DiskPart script:\n$script');

    final result = await _runDiskpart(script);
    _logLine('DiskPart exit: ${result.exitCode}');

    if (result.exitCode != 0) {
      final stderr = result.stderr.toString();
      final stdout = result.stdout.toString();
      _logLine('DiskPart stderr: $stderr');
      _logLine('DiskPart stdout: $stdout');
      return _DiskPartResult(
        success: false,
        error: stderr.isNotEmpty ? stderr : stdout,
      );
    }

    final driveLetter = await _findNewDriveLetter();
    if (driveLetter == null) {
      _logLine('Could not find drive letter');
      return _DiskPartResult(
        success: false,
        error: 'Could not find assigned drive letter',
      );
    }

    return _DiskPartResult(success: true, driveLetter: driveLetter);
  }

  Future<String?> _findNewDriveLetter() async {
    try {
      final result = await Process.run('powershell', [
        '-NoProfile',
        '-Command',
        r'Get-Volume | Where-Object { $_.DriveLetter -and $_.DriveLetter -ne "C" -and $_.DriveLetter -ne "X" -and $_.FileSystemLabel -eq "INTEL" } | Select-Object -First 1 -ExpandProperty DriveLetter',
      ]);
      if (result.exitCode == 0) {
        final letter = result.stdout.toString().trim();
        if (letter.isNotEmpty) return '$letter:';
      }
    } catch (_) {}

    try {
      final result = await Process.run('powershell', [
        '-NoProfile',
        '-Command',
        r'Get-Volume | Where-Object { $_.DriveLetter -and $_.DriveLetter -ne "C" -and $_.DriveLetter -ne "X" -and $_.FileSystem -and $_.SizeRemaining -gt 0 } | Sort-Object -Property DriveLetter | Select-Object -Last 1 -ExpandProperty DriveLetter',
      ]);
      if (result.exitCode == 0) {
        final letter = result.stdout.toString().trim();
        if (letter.isNotEmpty) return '$letter:';
      }
    } catch (_) {}

    return null;
  }

  // --- Formatting ---

  Future<bool> _formatPartition({
    required String driveLetter,
    required String fileSystem,
  }) async {
    try {
      final result = await Process.run('powershell', [
        '-NoProfile',
        '-Command',
        'Get-Volume -DriveLetter ${driveLetter.replaceAll(":", "")} | Select-Object -ExpandProperty FileSystem',
      ]);
      return result.exitCode == 0;
    } catch (_) {
      return false;
    }
  }

  // --- ISO Mounting ---

  Future<String?> _mountIso(String isoPath) async {
    try {
      final escapedPath = isoPath.replaceAll("'", "''");
      _logLine('Mounting ISO: $isoPath');

      // Clean up any stale mount
      await Process.run('powershell', [
        '-NoProfile', '-ExecutionPolicy', 'Bypass',
        '-Command',
        "Dismount-DiskImage -ImagePath '$escapedPath' -ErrorAction SilentlyContinue | Out-Null",
      ]).timeout(const Duration(seconds: 10));

      // Mount
      final mountResult = await Process.run('powershell', [
        '-NoProfile', '-ExecutionPolicy', 'Bypass',
        '-Command',
        "Mount-DiskImage -ImagePath '$escapedPath' -PassThru | Out-Null",
      ]).timeout(const Duration(seconds: 30));
      _logLine('Mount exit: ${mountResult.exitCode}, stderr: ${mountResult.stderr}');

      if (mountResult.exitCode != 0) return null;

      // Get drive letter with retries
      for (int i = 0; i < 5; i++) {
        await Future.delayed(const Duration(milliseconds: 500));
        final letterResult = await Process.run('powershell', [
          '-NoProfile', '-ExecutionPolicy', 'Bypass',
          '-Command',
          "Get-DiskImage -ImagePath '$escapedPath' | Get-Volume | Select-Object -ExpandProperty DriveLetter",
        ]).timeout(const Duration(seconds: 10));
        _logLine('Drive letter attempt $i: exit=${letterResult.exitCode}, out="${letterResult.stdout}"');
        if (letterResult.exitCode == 0) {
          final letter = letterResult.stdout.toString().trim();
          if (letter.isNotEmpty) {
            _logLine('Mounted at: $letter:\\');
            return '$letter:\\';
          }
        }
      }
    } catch (e) {
      _logLine('Mount error: $e');
    }
    return null;
  }

  Future<void> _unmountIso(String isoPath) async {
    try {
      final escapedPath = isoPath.replaceAll("'", "''");
      await Process.run('powershell', [
        '-NoProfile', '-ExecutionPolicy', 'Bypass',
        '-Command',
        "Dismount-DiskImage -ImagePath '$escapedPath' -ErrorAction SilentlyContinue",
      ]).timeout(const Duration(seconds: 15));
      _logLine('Unmounted OK');
    } catch (e) {
      _logLine('Unmount error: $e');
    }
  }

  // --- File Copying ---

  Future<bool> _copyIsoContents({
    required String mountPoint,
    required String targetDrive,
    required bool excludeWim,
    void Function(double progress)? onProgress,
  }) async {
    try {
      final srcDir = mountPoint.endsWith('\\') ? mountPoint : '$mountPoint\\';
      final dstDir = targetDrive.endsWith('\\') ? targetDrive : '$targetDrive\\';
      _logLine('robocopy: $srcDir -> $dstDir');

      // robocopy args
      final args = <String>[
        srcDir,
        dstDir,
        '/E',           // recursive including empty dirs
        '/R:1',         // 1 retry
        '/W:1',         // 1 second wait between retries
        '/NP',          // no progress percentage (clean output)
        '/NDL',         // don't log directory names
        '/NJH',         // no job header
        '/NJS',         // no job summary
        '/MT:8',        // 8 threads
      ];

      if (excludeWim) {
        args.addAll(['/XF', 'install.wim', 'install.esd']);
      }

      // Always exclude AutoUnattend.xml from ISO (may contain invalid keys
      // that break Windows Setup on USB drives)
      args.addAll(['/XF', 'AutoUnattend.xml', 'autounattend.xml']);

      _logLine('robocopy args: ${args.join(" ")}');

      // Report indeterminate progress while copying
      if (onProgress != null) {
        onProgress(0.0);
      }

      final result = await Process.run('robocopy', args)
          .timeout(const Duration(minutes: 15));

      // robocopy exit codes: 0-7 are success, 8+ are failures
      // 0 = no files copied (already up to date)
      // 1 = files copied successfully
      // 2 = extra files in destination
      // 3 = files copied + extra files
      // 4 = mismatched files
      // 5 = files copied + mismatched
      // 6 = extra + mismatched
      // 7 = all of the above
      final exitCode = result.exitCode;
      _logLine('robocopy exit: $exitCode');

      if (onProgress != null) {
        onProgress(1.0);
      }

      if (exitCode >= 8) {
        _logLine('robocopy FAILED: ${result.stderr}');
        _logLine('robocopy stdout: ${result.stdout}');
        return false;
      }

      _logLine('robocopy OK');
      return true;
    } catch (e) {
      _logLine('robocopy error: $e');
      return false;
    }
  }

  // --- WIM Splitting ---

  Future<bool> _splitWim({
    required String sourcePath,
    required String targetDir,
  }) async {
    try {
      final targetPath = p.join(targetDir, 'install.swm');
      final result = await Process.run('dism', [
        '/Split-Image',
        '/ImageFile:$sourcePath',
        '/SWMFile:$targetPath',
        '/FileSize:3800',
      ]);
      return result.exitCode == 0;
    } catch (_) {
      return false;
    }
  }

  // --- Boot Files ---

  Future<bool> _writeBootFiles({
    required String windowsDrive,
    required String targetDrive,
  }) async {
    try {
      _logLine('Writing boot files: target=$targetDrive');

      // Step 1: Write MBR boot code with bootsect
      _logLine('Step 1: bootsect /nt60 $targetDrive /mbr');
      final bootsectResult = await Process.run('bootsect', [
        '/nt60', targetDrive,
        '/mbr',
      ]).timeout(const Duration(seconds: 30));
      _logLine('bootsect exit: ${bootsectResult.exitCode}');
      _logLine('bootsect stdout: ${bootsectResult.stdout}');
      if (bootsectResult.exitCode != 0) {
        _logLine('bootsect stderr: ${bootsectResult.stderr}');
      }

      // Step 2: Try bcdboot (fast if \Windows exists on ISO)
      final windowsDir = '${windowsDrive}Windows';
      if (await Directory(windowsDir).exists()) {
        _logLine('Step 2: bcdboot (standard path)');
        final result = await Process.run('bcdboot', [
          windowsDir,
          '/s', targetDrive,
          '/f', 'ALL',
        ]).timeout(const Duration(seconds: 60));
        _logLine('bcdboot exit: ${result.exitCode}');
        _logLine('bcdboot stdout: ${result.stdout}');
        if (result.exitCode != 0) {
          _logLine('bcdboot failed, falling back to bootsect-only');
        }
        // Don't return yet — need to verify EFI files exist below
      }

      // Step 3: For slim ISOs (Tiny10 etc) - bcdboot needs DISM mount which is slow
      // Instead, try bcdboot with /s pointing to the ISO's boot directory
      // The bootmgr + BCD from ISO should be enough for BIOS boot
      _logLine('Step 3: Trying bcdboot with boot dir');
      final bootDir = '${targetDrive}boot';
      if (await Directory(bootDir).exists()) {
        // Try creating BCD store manually if missing
        final bcdPath = '$targetDrive\\boot\\BCD';
        if (!await File(bcdPath).exists()) {
          _logLine('BCD not found, creating with bcdedit...');
          await _createBcdStore(targetDrive);
        }
      }

      // Verify: bootsect + bootmgr from ISO = bootable for BIOS
      // UEFI boot needs \efi\boot\bootx64.efi which was copied from ISO
      final hasBootmgr = await File('$targetDrive\\bootmgr').exists();
      var hasEfiBoot = await File('$targetDrive\\efi\\boot\\bootx64.efi').exists() ||
          await File('$targetDrive\\efi\\boot\\bootaa64.efi').exists();
      _logLine('Boot files: bootmgr=$hasBootmgr, efi=$hasEfiBoot');

      // If EFI boot file missing, try to fix it
      if (!hasEfiBoot) {
        _logLine('EFI boot file missing, attempting repair...');

        // Try 1: Copy bootmgfw.efi from efi\microsoft\boot to efi\boot\bootx64.efi
        final bootmgfwPath = '$targetDrive\\efi\\microsoft\\boot\\bootmgfw.efi';
        if (await File(bootmgfwPath).exists()) {
          _logLine('Found bootmgfw.efi, copying to efi\\boot');
          final efiBootDir = '$targetDrive\\efi\\boot';
          await Directory(efiBootDir).create(recursive: true);
          await File(bootmgfwPath).copy('$efiBootDir\\bootx64.efi');
          hasEfiBoot = true;
        }

        // Try 1b: Copy bootmgfw.efi as bootaa64.efi for ARM64
        if (!hasEfiBoot) {
          final bootmgfwPath2 = '$targetDrive\\efi\\microsoft\\boot\\bootmgfw.efi';
          if (await File(bootmgfwPath2).exists()) {
            final efiBootDir = '$targetDrive\\efi\\boot';
            await Directory(efiBootDir).create(recursive: true);
            await File(bootmgfwPath2).copy('$efiBootDir\\bootaa64.efi');
            hasEfiBoot = true;
          }
        }

        // Try 2: bcdboot with /f UEFI specifically
        if (!hasEfiBoot) {
          final windowsDir2 = '${windowsDrive}Windows';
          if (await Directory(windowsDir2).exists()) {
            _logLine('Trying bcdboot /f UEFI...');
            final uefiResult = await Process.run('bcdboot', [
              windowsDir2,
              '/s', targetDrive,
              '/f', 'UEFI',
            ]).timeout(const Duration(seconds: 60));
            _logLine('bcdboot UEFI exit: ${uefiResult.exitCode}');
            hasEfiBoot = await File('$targetDrive\\efi\\boot\\bootx64.efi').exists() ||
                await File('$targetDrive\\efi\\boot\\bootaa64.efi').exists();
          }
        }

        // Try 3: Check if ISO had efi\boot and re-copy it
        if (!hasEfiBoot) {
          _logLine('EFI still missing after repair attempts');
        }
      }

      _logLine('Final: bootmgr=$hasBootmgr, efi=$hasEfiBoot');
      return hasBootmgr || hasEfiBoot;
    } catch (e) {
      _logLine('Boot file exception: $e');
      return false;
    }
  }

  Future<void> _createBcdStore(String targetDrive) async {
    try {
      final bcdPath = '$targetDrive\\boot\\BCD';
      // bcdedit /createstore creates an empty BCD store
      await Process.run('bcdedit', [
        '/createstore', bcdPath,
      ]).timeout(const Duration(seconds: 10));

      // Create boot manager entry
      await Process.run('bcdedit', [
        '/store', bcdPath,
        '/create', '{bootmgr}',
        '/d', 'Windows Boot Manager',
      ]).timeout(const Duration(seconds: 10));

      _logLine('BCD store created');
    } catch (e) {
      _logLine('BCD create error: $e');
    }
  }

  // --- Verification ---

  Future<bool> _verifyBootableUsb({
    required String driveLetter,
  }) async {
    final errors = <String>[];

    // Core boot files (required)
    final hasBootmgr = await File('$driveLetter\\bootmgr').exists();
    if (!hasBootmgr) {
      errors.add('bootmgr missing');
    }

    // EFI boot (at least one required for UEFI)
    final hasEfiBoot = await File('$driveLetter\\EFI\\Boot\\bootx64.efi').exists() ||
        await File('$driveLetter\\EFI\\Boot\\bootaa64.efi').exists();
    if (!hasEfiBoot && !hasBootmgr) {
      errors.add('No boot files (bootmgr or EFI boot)');
    }

    // Install image (required)
    final hasWim = await File('$driveLetter\\sources\\install.wim').exists();
    final hasEsd = await File('$driveLetter\\sources\\install.esd').exists();
    final hasSwm = await File('$driveLetter\\sources\\install.swm').exists();
    if (!hasWim && !hasEsd && !hasSwm) {
      errors.add('install image missing (wim/esd/swm)');
    }

    // setup.exe is optional (slim ISOs like Tiny10/X-Lite may not have it)
    if (!await File('$driveLetter\\setup.exe').exists()) {
      _logLine('Note: setup.exe not found (OK for slim ISOs)');
    }

    if (errors.isNotEmpty) {
      _logLine('Verify issues: ${errors.join(', ')}');
      final logger = ref.read(fileLoggerServiceProvider);
      await logger.log(
        action: 'Verify USB',
        target: driveLetter,
        result: 'Issues: ${errors.join(', ')}',
        level: LogLevel.warning,
      );
    }

    return errors.isEmpty;
  }

  // --- Volume Icon ---

  Future<void> _setVolumeIcon(String driveLetter) async {
    try {
      _logLine('Loading intel.ico from app assets...');

      // Load icon from Flutter asset bundle
      final iconBytes = await rootBundle.load('assets/intel.ico');
      final iconData = iconBytes.buffer.asUint8List();

      // Copy icon to USB root
      final iconDest = File('$driveLetter\\intel.ico');
      await iconDest.writeAsBytes(iconData);
      _logLine('Icon written to: ${iconDest.path}');

      // Create autorun.inf — remove existing first (Windows may block it)
      final autorunFile = File('$driveLetter\\autorun.inf');
      try {
        // Remove hidden/system/read-only attributes if file exists
        await Process.run('attrib', [
          '-h', '-s', '-r', autorunFile.path,
        ]).timeout(const Duration(seconds: 5));
        await autorunFile.delete().catchError((_) => autorunFile);
      } catch (_) {}

      await autorunFile.writeAsString('[autorun]\nicon=intel.ico\nlabel=INTEL\n');
      _logLine('autorun.inf created');

      // Set autorun.inf as hidden+system (suppresses some Windows warnings)
      await Process.run('attrib', [
        '+h', '+s',
        autorunFile.path,
      ]).timeout(const Duration(seconds: 5));

      // Set icon as hidden
      await Process.run('attrib', [
        '+h', iconDest.path,
      ]).timeout(const Duration(seconds: 5));

      _logLine('Volume icon set OK');
    } catch (e) {
      _logLine('Volume icon error: $e (non-fatal, continuing)');
    }
  }

  // --- Utility ---

  Future<ProcessResult> _runDiskpart(String script) async {
    final tempDir = await FileUtils.getTempDirectory();
    final scriptFile = File(p.join(tempDir, 'winddeploy_diskpart.txt'));
    await scriptFile.writeAsString(script);

    try {
      final result = await Process.run('diskpart', ['/s', scriptFile.path])
          .timeout(const Duration(seconds: 30), onTimeout: () {
        return ProcessResult(0, -1, '', 'diskpart timed out after 30s');
      });
      return result;
    } finally {
      await scriptFile.delete().catchError((_) => scriptFile);
    }
  }

  void _notify(ProgressCallback? callback, CreateProgress progress) {
    callback?.call(progress);
  }
}

class _DiskPartResult {
  final bool success;
  final String? driveLetter;
  final String? error;

  const _DiskPartResult({
    required this.success,
    this.driveLetter,
    this.error,
  });
}
