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

class LinuxIsoHybridInspection {
  final bool isValid;
  final String? error;
  final int imageBytes;
  final int bootCatalogLba;
  final int efiImageLba;

  const LinuxIsoHybridInspection._({
    required this.isValid,
    this.error,
    this.imageBytes = 0,
    this.bootCatalogLba = 0,
    this.efiImageLba = 0,
  });

  const LinuxIsoHybridInspection.failure(String error)
    : this._(isValid: false, error: error);

  const LinuxIsoHybridInspection.success({
    required int imageBytes,
    required int bootCatalogLba,
    required int efiImageLba,
  }) : this._(
         isValid: true,
         imageBytes: imageBytes,
         bootCatalogLba: bootCatalogLba,
         efiImageLba: efiImageLba,
       );
}

class LinuxIsoHybridInspector {
  static const int _isoSectorBytes = 2048;
  static const int _firstVolumeDescriptorLba = 16;
  static const int _maxVolumeDescriptors = 128;
  static const int _maxCatalogBytes = 32 * 1024;

  const LinuxIsoHybridInspector._();

  static Future<LinuxIsoHybridInspection> inspect(String imagePath) async {
    final file = File(imagePath);
    try {
      if (!await file.exists()) {
        return const LinuxIsoHybridInspection.failure(
          'ISOHybrid image does not exist.',
        );
      }
      if (await FileSystemEntity.type(file.path, followLinks: false) !=
          FileSystemEntityType.file) {
        return const LinuxIsoHybridInspection.failure(
          'ISOHybrid source must be a regular file.',
        );
      }

      final length = await file.length();
      if (length < (_firstVolumeDescriptorLba + 4) * _isoSectorBytes) {
        return const LinuxIsoHybridInspection.failure(
          'Image is too small to contain ISO9660 boot structures.',
        );
      }

      final handle = await file.open();
      try {
        final systemArea = await _readAt(handle, 0, 4096);
        if (systemArea[510] != 0x55 || systemArea[511] != 0xaa) {
          return const LinuxIsoHybridInspection.failure(
            'ISOHybrid MBR boot signature is missing.',
          );
        }
        var hasHybridPartition = false;
        for (var index = 0; index < 4; index++) {
          final entryOffset = 446 + index * 16;
          final type = systemArea[entryOffset + 4];
          final sectors = _uint32(systemArea, entryOffset + 12);
          if (type != 0 && sectors != 0) {
            hasHybridPartition = true;
            break;
          }
        }
        if (!hasHybridPartition) {
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
        final validationError = _validateCatalogHeader(catalog);
        if (validationError != null) {
          return LinuxIsoHybridInspection.failure(validationError);
        }

        var hasBootableEntry = false;
        var efiImageLba = 0;
        final validationPlatform = catalog[1];
        if (_isBootableCatalogEntry(catalog, 32)) {
          hasBootableEntry = true;
          if (validationPlatform == 0xef) {
            efiImageLba = _uint32(catalog, 40);
          }
        }

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
            if (_isBootableCatalogEntry(catalog, offset)) {
              hasBootableEntry = true;
              if (platform == 0xef && efiImageLba == 0) {
                efiImageLba = _uint32(catalog, offset + 8);
              }
            }
            offset += 32;
          }
          if (indicator == 0x91) break;
        }

        if (!hasBootableEntry) {
          return const LinuxIsoHybridInspection.failure(
            'El Torito catalog has no bootable entry.',
          );
        }
        if (efiImageLba <= 0 || efiImageLba * _isoSectorBytes + 512 > length) {
          return const LinuxIsoHybridInspection.failure(
            'El Torito catalog has no valid EFI boot image.',
          );
        }

        final efiBootSector = await _readAt(
          handle,
          efiImageLba * _isoSectorBytes,
          512,
        );
        if (!_isFatBootSector(efiBootSector)) {
          return const LinuxIsoHybridInspection.failure(
            'EFI El Torito entry does not reference a FAT boot image.',
          );
        }

        return LinuxIsoHybridInspection.success(
          imageBytes: length,
          bootCatalogLba: bootCatalogLba,
          efiImageLba: efiImageLba,
        );
      } finally {
        await handle.close();
      }
    } catch (error) {
      return LinuxIsoHybridInspection.failure(
        'ISOHybrid structure inspection failed: $error',
      );
    }
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
    final fat16Marker = _ascii(sector, 54, 8).trimRight();
    final fat32Marker = _ascii(sector, 82, 8).trimRight();
    return fat16Marker.startsWith('FAT') || fat32Marker.startsWith('FAT');
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
