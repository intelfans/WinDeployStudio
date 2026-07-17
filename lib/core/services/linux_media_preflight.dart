import 'dart:io';
import 'dart:typed_data';

const int linuxRawVerificationMinimumBytesPerSecond = 4 * 1024 * 1024;
const int linuxRawWriteMinimumBytesPerSecond = 1024 * 1024;
const Duration linuxRawVerificationStartupAllowance = Duration(minutes: 2);

Duration linuxRawWriteTimeoutForBytes(int imageBytes) {
  if (imageBytes <= 0) return linuxRawVerificationStartupAllowance;
  final transferSeconds =
      (imageBytes + linuxRawWriteMinimumBytesPerSecond - 1) ~/
      linuxRawWriteMinimumBytesPerSecond;
  final calculated = Duration(
    seconds: linuxRawVerificationStartupAllowance.inSeconds + transferSeconds,
  );
  const maximum = Duration(hours: 24);
  return calculated > maximum ? maximum : calculated;
}

Duration linuxRawVerificationTimeoutForBytes(int imageBytes) {
  if (imageBytes <= 0) return linuxRawVerificationStartupAllowance;
  final transferSeconds =
      (imageBytes + linuxRawVerificationMinimumBytesPerSecond - 1) ~/
      linuxRawVerificationMinimumBytesPerSecond;
  final calculated = Duration(
    seconds: linuxRawVerificationStartupAllowance.inSeconds + transferSeconds,
  );
  const maximum = Duration(hours: 12);
  return calculated > maximum ? maximum : calculated;
}

Duration linuxRawWriteAndVerifyTimeoutForBytes(int imageBytes) {
  final calculated =
      linuxRawWriteTimeoutForBytes(imageBytes) +
      linuxRawVerificationTimeoutForBytes(imageBytes);
  const maximum = Duration(hours: 24);
  return calculated > maximum ? maximum : calculated;
}

/// Architectures advertised through the standard removable-media fallback
/// file names in an EFI El Torito FAT image. This is intentionally a report
/// of the image, not a promise about the firmware that will boot it.
enum LinuxEfiArchitecture { ia32, x64, arm32, arm64, riscv64, loongarch64 }

/// A cooperative cancellation signal for one read-only ISOHybrid inspection.
///
/// RandomAccessFile reads cannot be interrupted safely on every supported
/// filesystem, so callers must still discard a cancelled result. The inspector
/// checks this token between I/O operations and while scanning EFI payloads so
/// a superseded selection does not keep occupying the UI isolate.
class LinuxIsoHybridInspectionCancellationToken {
  bool _isCancelled = false;

  bool get isCancelled => _isCancelled;

  void cancel() {
    _isCancelled = true;
  }
}

class LinuxIsoHybridInspection {
  final bool isValid;
  final String? error;
  final bool wasCancelled;
  final int imageBytes;
  final int bootCatalogLba;
  final int efiImageLba;
  final bool hasHybridMbr;
  final bool hasLegacyBiosBoot;
  final bool hasUefiBoot;
  final Set<LinuxEfiArchitecture> efiArchitectures;

  const LinuxIsoHybridInspection._({
    required this.isValid,
    this.error,
    this.wasCancelled = false,
    this.imageBytes = 0,
    this.bootCatalogLba = 0,
    this.efiImageLba = 0,
    this.hasHybridMbr = false,
    this.hasLegacyBiosBoot = false,
    this.hasUefiBoot = false,
    this.efiArchitectures = const <LinuxEfiArchitecture>{},
  });

  const LinuxIsoHybridInspection.failure(String error)
    : this._(isValid: false, error: error);

  const LinuxIsoHybridInspection.cancelled()
    : this._(isValid: false, wasCancelled: true);

  const LinuxIsoHybridInspection.success({
    required int imageBytes,
    required int bootCatalogLba,
    required bool hasHybridMbr,
    required bool hasLegacyBiosBoot,
    required bool hasUefiBoot,
    int efiImageLba = 0,
    Set<LinuxEfiArchitecture> efiArchitectures = const <LinuxEfiArchitecture>{},
  }) : this._(
         isValid: true,
         imageBytes: imageBytes,
         bootCatalogLba: bootCatalogLba,
         efiImageLba: efiImageLba,
         hasHybridMbr: hasHybridMbr,
         hasLegacyBiosBoot: hasLegacyBiosBoot,
         hasUefiBoot: hasUefiBoot,
         efiArchitectures: efiArchitectures,
       );

  bool get hasKnownEfiArchitecture => efiArchitectures.isNotEmpty;
}

/// Performs a bounded structural inspection before an ISOHybrid image is
/// copied byte-for-byte to an external disk. It never mounts or modifies the
/// source image. A valid result means that raw writing is structurally safe;
/// it does not assert Secure Boot support, a particular distribution, or that
/// a target firmware implements the image's advertised boot path.
class LinuxIsoHybridInspector {
  static const int _isoSectorBytes = 2048;
  static const int _firstVolumeDescriptorLba = 16;
  static const int _maxVolumeDescriptors = 128;
  static const int _maxCatalogBytes = 32 * 1024;
  // A standard removable-media fallback directory is near the beginning of a
  // FAT image. Keeping this bounded prevents selection-time inspection from
  // becoming a multi-second scan of a large Secure Boot image.
  static const int _maxEfiArchitectureProbeBytes = 4 * 1024 * 1024;

  const LinuxIsoHybridInspector._();

  static Future<LinuxIsoHybridInspection> inspect(
    String imagePath, {
    LinuxIsoHybridInspectionCancellationToken? cancellationToken,
  }) async {
    if (_isCancelled(cancellationToken)) {
      return const LinuxIsoHybridInspection.cancelled();
    }
    final file = File(imagePath);
    try {
      if (!await file.exists()) {
        return const LinuxIsoHybridInspection.failure(
          'ISOHybrid image does not exist.',
        );
      }
      if (_isCancelled(cancellationToken)) {
        return const LinuxIsoHybridInspection.cancelled();
      }
      if (await FileSystemEntity.type(file.path, followLinks: false) !=
          FileSystemEntityType.file) {
        return const LinuxIsoHybridInspection.failure(
          'ISOHybrid source must be a regular file.',
        );
      }

      final length = await file.length();
      if (_isCancelled(cancellationToken)) {
        return const LinuxIsoHybridInspection.cancelled();
      }
      if (length < (_firstVolumeDescriptorLba + 4) * _isoSectorBytes) {
        return const LinuxIsoHybridInspection.failure(
          'Image is too small to contain ISO9660 boot structures.',
        );
      }

      final handle = await file.open();
      try {
        final systemArea = await _readAt(handle, 0, 4096);
        if (_isCancelled(cancellationToken)) {
          return const LinuxIsoHybridInspection.cancelled();
        }
        if (systemArea[510] != 0x55 || systemArea[511] != 0xaa) {
          return const LinuxIsoHybridInspection.failure(
            'ISOHybrid MBR boot signature is missing.',
          );
        }
        var hasHybridMbr = false;
        for (var index = 0; index < 4; index++) {
          final entryOffset = 446 + index * 16;
          final type = systemArea[entryOffset + 4];
          final sectors = _uint32(systemArea, entryOffset + 12);
          if (type != 0 && sectors != 0) {
            hasHybridMbr = true;
            break;
          }
        }
        if (!hasHybridMbr) {
          return const LinuxIsoHybridInspection.failure(
            'ISOHybrid MBR has no usable partition entry.',
          );
        }

        var hasPrimaryVolume = false;
        var hasTerminator = false;
        var bootCatalogLba = 0;
        for (var index = 0; index < _maxVolumeDescriptors; index++) {
          final offset = (_firstVolumeDescriptorLba + index) * _isoSectorBytes;
          if (offset + _isoSectorBytes > length) break;
          final descriptor = await _readAt(handle, offset, _isoSectorBytes);
          if (_isCancelled(cancellationToken)) {
            return const LinuxIsoHybridInspection.cancelled();
          }
          if (_ascii(descriptor, 1, 5) != 'CD001' || descriptor[6] != 1) {
            return LinuxIsoHybridInspection.failure(
              'Invalid ISO9660 volume descriptor at LBA '
              '${_firstVolumeDescriptorLba + index}.',
            );
          }

          final type = descriptor[0];
          if (type == 1) {
            final littleBlockSize = _uint16(descriptor, 128);
            final bigBlockSize = _uint16BigEndian(descriptor, 130);
            final volumeSectors = _uint32(descriptor, 80);
            if (littleBlockSize != _isoSectorBytes ||
                bigBlockSize != _isoSectorBytes ||
                volumeSectors == 0 ||
                volumeSectors * _isoSectorBytes > length) {
              return const LinuxIsoHybridInspection.failure(
                'ISO9660 primary volume descriptor is inconsistent.',
              );
            }
            hasPrimaryVolume = true;
          } else if (type == 0) {
            final bootSystem = _ascii(
              descriptor,
              7,
              32,
            ).replaceFirst(RegExp(r'[\x00 ]+$'), '');
            if (bootSystem == 'EL TORITO SPECIFICATION') {
              bootCatalogLba = _uint32(descriptor, 71);
            }
          } else if (type == 255) {
            hasTerminator = true;
            break;
          }
        }

        if (!hasPrimaryVolume || !hasTerminator) {
          return const LinuxIsoHybridInspection.failure(
            'Complete ISO9660 volume descriptors were not found.',
          );
        }
        if (bootCatalogLba <= 0 ||
            bootCatalogLba * _isoSectorBytes + 64 > length) {
          return const LinuxIsoHybridInspection.failure(
            'El Torito boot catalog is missing or outside the image.',
          );
        }

        final catalogOffset = bootCatalogLba * _isoSectorBytes;
        final catalogLength = _min(_maxCatalogBytes, length - catalogOffset);
        final catalog = await _readAt(handle, catalogOffset, catalogLength);
        if (_isCancelled(cancellationToken)) {
          return const LinuxIsoHybridInspection.cancelled();
        }
        final validationError = _validateCatalogHeader(catalog);
        if (validationError != null) {
          return LinuxIsoHybridInspection.failure(validationError);
        }

        var hasBootableEntry = false;
        var hasLegacyBiosBoot = false;
        var efiImageLba = 0;
        final validationPlatform = catalog[1];

        void inspectBootEntry(int entryOffset, int platform) {
          if (!_isBootableCatalogEntry(catalog, entryOffset)) return;
          hasBootableEntry = true;
          if (platform == 0xef) {
            if (efiImageLba == 0) {
              efiImageLba = _uint32(catalog, entryOffset + 8);
            }
          } else if (platform == 0x00) {
            // An El Torito x86/default entry paired with a valid hybrid MBR is
            // the strongest non-invasive indication that this image publishes
            // a Legacy BIOS path after raw writing.
            hasLegacyBiosBoot = true;
          }
        }

        inspectBootEntry(32, validationPlatform);
        var offset = 64;
        while (offset + 32 <= catalog.length) {
          final indicator = catalog[offset];
          if (indicator == 0x00) {
            offset += 32;
            continue;
          }
          if (indicator != 0x90 && indicator != 0x91) break;
          final platform = catalog[offset + 1];
          final entryCount = _uint16(catalog, offset + 2);
          if (entryCount <= 0 || entryCount > 256) {
            return const LinuxIsoHybridInspection.failure(
              'El Torito section contains an invalid entry count.',
            );
          }
          offset += 32;
          for (var index = 0; index < entryCount; index++) {
            if (offset + 32 > catalog.length) {
              return const LinuxIsoHybridInspection.failure(
                'El Torito section extends beyond the boot catalog.',
              );
            }
            inspectBootEntry(offset, platform);
            offset += 32;
          }
          if (indicator == 0x91) break;
        }

        if (!hasBootableEntry) {
          return const LinuxIsoHybridInspection.failure(
            'El Torito catalog has no bootable entry.',
          );
        }

        final hasUefiBoot = efiImageLba > 0;
        var efiArchitectures = const <LinuxEfiArchitecture>{};
        if (hasUefiBoot) {
          if (efiImageLba * _isoSectorBytes + 512 > length) {
            return const LinuxIsoHybridInspection.failure(
              'El Torito catalog has an EFI boot image outside the source image.',
            );
          }
          final efiBootSector = await _readAt(
            handle,
            efiImageLba * _isoSectorBytes,
            512,
          );
          if (_isCancelled(cancellationToken)) {
            return const LinuxIsoHybridInspection.cancelled();
          }
          if (!_isFatBootSector(efiBootSector)) {
            return const LinuxIsoHybridInspection.failure(
              'EFI El Torito entry does not reference a FAT boot image.',
            );
          }
          final efiImageBytes = _fatVolumeByteLength(efiBootSector);
          if (efiImageBytes == null ||
              efiImageLba * _isoSectorBytes + efiImageBytes > length) {
            return const LinuxIsoHybridInspection.failure(
              'EFI El Torito FAT volume is outside the source image.',
            );
          }
          efiArchitectures = await _inspectStandardEfiFallbackArchitectures(
            handle,
            efiImageLba: efiImageLba,
            efiImageBytes: efiImageBytes,
            cancellationToken: cancellationToken,
          );
          if (_isCancelled(cancellationToken)) {
            return const LinuxIsoHybridInspection.cancelled();
          }
        }

        if (!hasLegacyBiosBoot && !hasUefiBoot) {
          return const LinuxIsoHybridInspection.failure(
            'El Torito catalog has no x86 Legacy BIOS or UEFI boot entry.',
          );
        }

        return LinuxIsoHybridInspection.success(
          imageBytes: length,
          bootCatalogLba: bootCatalogLba,
          efiImageLba: efiImageLba,
          hasHybridMbr: hasHybridMbr,
          hasLegacyBiosBoot: hasLegacyBiosBoot,
          hasUefiBoot: hasUefiBoot,
          efiArchitectures: efiArchitectures,
        );
      } finally {
        await handle.close();
      }
    } catch (error) {
      if (_isCancelled(cancellationToken)) {
        return const LinuxIsoHybridInspection.cancelled();
      }
      return LinuxIsoHybridInspection.failure(
        'ISOHybrid structure inspection failed: $error',
      );
    }
  }

  static Future<Set<LinuxEfiArchitecture>>
  _inspectStandardEfiFallbackArchitectures(
    RandomAccessFile handle, {
    required int efiImageLba,
    required int efiImageBytes,
    LinuxIsoHybridInspectionCancellationToken? cancellationToken,
  }) async {
    final offset = efiImageLba * _isoSectorBytes;
    final probeBytes = _min(_maxEfiArchitectureProbeBytes, efiImageBytes);
    if (probeBytes < 512) return const <LinuxEfiArchitecture>{};

    // FAT directory entries use the 8.3 spelling (BOOTX64 EFI), while a
    // long-file-name entry may retain the dotted spelling. Checking both
    // means we do not have to rewrite or mount the EFI image merely to report
    // standard removable-media fallback architectures.
    final bytes = await _readAt(handle, offset, probeBytes);
    if (_isCancelled(cancellationToken)) {
      return const <LinuxEfiArchitecture>{};
    }
    final upper = Uint8List.fromList(bytes);
    for (var index = 0; index < upper.length; index++) {
      final value = upper[index];
      if (value >= 0x61 && value <= 0x7a) upper[index] = value - 0x20;
      if (index % _scanYieldInterval == 0) {
        if (_isCancelled(cancellationToken)) {
          return const <LinuxEfiArchitecture>{};
        }
        await Future<void>.delayed(Duration.zero);
      }
    }
    final found = <LinuxEfiArchitecture>{};
    if (await _containsAnyAscii(upper, const [
      'BOOTIA32.EFI',
      'BOOTIA32 EFI',
    ], cancellationToken: cancellationToken)) {
      found.add(LinuxEfiArchitecture.ia32);
    }
    if (_isCancelled(cancellationToken)) return const <LinuxEfiArchitecture>{};
    if (await _containsAnyAscii(upper, const [
      'BOOTX64.EFI',
      'BOOTX64 EFI',
    ], cancellationToken: cancellationToken)) {
      found.add(LinuxEfiArchitecture.x64);
    }
    if (_isCancelled(cancellationToken)) return const <LinuxEfiArchitecture>{};
    if (await _containsAnyAscii(upper, const [
      'BOOTARM.EFI',
      'BOOTARM EFI',
    ], cancellationToken: cancellationToken)) {
      found.add(LinuxEfiArchitecture.arm32);
    }
    if (_isCancelled(cancellationToken)) return const <LinuxEfiArchitecture>{};
    if (await _containsAnyAscii(upper, const [
      'BOOTAA64.EFI',
      'BOOTAA64 EFI',
    ], cancellationToken: cancellationToken)) {
      found.add(LinuxEfiArchitecture.arm64);
    }
    if (_isCancelled(cancellationToken)) return const <LinuxEfiArchitecture>{};
    if (await _containsAnyAscii(upper, const [
      'BOOTRISCV64.EFI',
      'BOOTRISCV64 EFI',
    ], cancellationToken: cancellationToken)) {
      found.add(LinuxEfiArchitecture.riscv64);
    }
    if (_isCancelled(cancellationToken)) return const <LinuxEfiArchitecture>{};
    if (await _containsAnyAscii(upper, const [
      'BOOTLOONGARCH64.EFI',
      'BOOTLOONGARCH64 EFI',
    ], cancellationToken: cancellationToken)) {
      found.add(LinuxEfiArchitecture.loongarch64);
    }
    return found;
  }

  static String? _validateCatalogHeader(Uint8List catalog) {
    if (catalog.length < 64 || catalog[0] != 1) {
      return 'El Torito validation entry is missing.';
    }
    if (catalog[30] != 0x55 || catalog[31] != 0xaa) {
      return 'El Torito validation entry key is invalid.';
    }
    var checksum = 0;
    for (var offset = 0; offset < 32; offset += 2) {
      checksum = (checksum + _uint16(catalog, offset)) & 0xffff;
    }
    if (checksum != 0) {
      return 'El Torito validation entry checksum is invalid.';
    }
    return null;
  }

  static bool _isBootableCatalogEntry(Uint8List catalog, int offset) {
    if (offset + 32 > catalog.length || catalog[offset] != 0x88) {
      return false;
    }
    return _uint32(catalog, offset + 8) > 0;
  }

  static bool _isFatBootSector(Uint8List sector) {
    if (sector.length < 512 || sector[510] != 0x55 || sector[511] != 0xaa) {
      return false;
    }
    if (sector[0] != 0xeb && sector[0] != 0xe9) return false;
    final bytesPerSector = _uint16(sector, 11);
    if (!const {512, 1024, 2048, 4096}.contains(bytesPerSector)) {
      return false;
    }
    final sectorsPerCluster = sector[13];
    if (sectorsPerCluster == 0 ||
        (sectorsPerCluster & (sectorsPerCluster - 1)) != 0) {
      return false;
    }
    final fat16Marker = _ascii(sector, 54, 8).trimRight();
    final fat32Marker = _ascii(sector, 82, 8).trimRight();
    return fat16Marker.startsWith('FAT') || fat32Marker.startsWith('FAT');
  }

  static int? _fatVolumeByteLength(Uint8List sector) {
    final bytesPerSector = _uint16(sector, 11);
    final totalSectors16 = _uint16(sector, 19);
    final totalSectors = totalSectors16 == 0
        ? _uint32(sector, 32)
        : totalSectors16;
    if (totalSectors <= 0) return null;
    final totalBytes = totalSectors * bytesPerSector;
    return totalBytes >= 512 ? totalBytes : null;
  }

  static const int _scanYieldInterval = 64 * 1024;

  static bool _isCancelled(
    LinuxIsoHybridInspectionCancellationToken? cancellationToken,
  ) => cancellationToken?.isCancelled ?? false;

  static Future<bool> _containsAnyAscii(
    Uint8List bytes,
    List<String> values, {
    LinuxIsoHybridInspectionCancellationToken? cancellationToken,
  }) async {
    final needles = values.map((value) => value.codeUnits).toList();
    if (needles.every((needle) => needle.length > bytes.length)) return false;

    for (var start = 0; start < bytes.length; start++) {
      if (start % _scanYieldInterval == 0) {
        if (_isCancelled(cancellationToken)) return false;
        await Future<void>.delayed(Duration.zero);
      }
      for (final needle in needles) {
        if (start + needle.length > bytes.length || bytes[start] != needle[0]) {
          continue;
        }
        var matches = true;
        for (var index = 1; index < needle.length; index++) {
          if (bytes[start + index] != needle[index]) {
            matches = false;
            break;
          }
        }
        if (matches) return true;
      }
    }
    return false;
  }

  static Future<Uint8List> _readAt(
    RandomAccessFile handle,
    int offset,
    int length,
  ) async {
    await handle.setPosition(offset);
    final bytes = await handle.read(length);
    if (bytes.length != length) {
      throw FileSystemException('Short read at offset $offset');
    }
    return Uint8List.fromList(bytes);
  }

  static String _ascii(Uint8List bytes, int offset, int length) =>
      String.fromCharCodes(bytes.sublist(offset, offset + length));

  static int _uint16(Uint8List bytes, int offset) =>
      bytes[offset] | (bytes[offset + 1] << 8);

  static int _uint16BigEndian(Uint8List bytes, int offset) =>
      (bytes[offset] << 8) | bytes[offset + 1];

  static int _uint32(Uint8List bytes, int offset) =>
      bytes[offset] |
      (bytes[offset + 1] << 8) |
      (bytes[offset + 2] << 16) |
      (bytes[offset + 3] << 24);

  static int _min(int left, int right) => left < right ? left : right;
}
