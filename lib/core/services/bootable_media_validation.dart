import 'dart:typed_data';

bool isAcceptedRobocopyExitCode(int exitCode) => exitCode >= 0 && exitCode <= 3;

String? validateIcoBytes(Uint8List bytes) {
  if (bytes.length < 22) return 'ICO file is truncated.';
  int uint16(int offset) => bytes[offset] | (bytes[offset + 1] << 8);
  int uint32(int offset) =>
      bytes[offset] |
      (bytes[offset + 1] << 8) |
      (bytes[offset + 2] << 16) |
      (bytes[offset + 3] << 24);

  if (uint16(0) != 0 || uint16(2) != 1) {
    return 'ICO header is invalid.';
  }
  final count = uint16(4);
  if (count <= 0 || count > 256 || 6 + count * 16 > bytes.length) {
    return 'ICO image directory is invalid.';
  }
  final dataFloor = 6 + count * 16;
  for (var index = 0; index < count; index++) {
    final entry = 6 + index * 16;
    final imageBytes = uint32(entry + 8);
    final imageOffset = uint32(entry + 12);
    if (imageBytes <= 0 ||
        imageOffset < dataFloor ||
        imageOffset > bytes.length - imageBytes) {
      return 'ICO image entry ${index + 1} is outside the file.';
    }
    final isPng =
        imageBytes >= 8 &&
        bytes[imageOffset] == 0x89 &&
        bytes[imageOffset + 1] == 0x50 &&
        bytes[imageOffset + 2] == 0x4e &&
        bytes[imageOffset + 3] == 0x47 &&
        bytes[imageOffset + 4] == 0x0d &&
        bytes[imageOffset + 5] == 0x0a &&
        bytes[imageOffset + 6] == 0x1a &&
        bytes[imageOffset + 7] == 0x0a;
    final dibHeaderBytes = imageBytes >= 4 ? uint32(imageOffset) : 0;
    if (!isPng && !const {12, 40, 52, 56, 108, 124}.contains(dibHeaderBytes)) {
      return 'ICO image entry ${index + 1} has an unsupported bitmap header.';
    }
  }
  return null;
}
