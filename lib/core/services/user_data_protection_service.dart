import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

final class _DataBlob extends Struct {
  @Uint32()
  external int length;

  external Pointer<Uint8> data;
}

typedef _CryptProtectDataNative =
    Int32 Function(
      Pointer<_DataBlob> dataIn,
      Pointer<Uint16> description,
      Pointer<_DataBlob> optionalEntropy,
      Pointer<Void> reserved,
      Pointer<Void> prompt,
      Uint32 flags,
      Pointer<_DataBlob> dataOut,
    );
typedef _CryptProtectDataDart =
    int Function(
      Pointer<_DataBlob> dataIn,
      Pointer<Uint16> description,
      Pointer<_DataBlob> optionalEntropy,
      Pointer<Void> reserved,
      Pointer<Void> prompt,
      int flags,
      Pointer<_DataBlob> dataOut,
    );

typedef _CryptUnprotectDataNative =
    Int32 Function(
      Pointer<_DataBlob> dataIn,
      Pointer<Pointer<Uint16>> description,
      Pointer<_DataBlob> optionalEntropy,
      Pointer<Void> reserved,
      Pointer<Void> prompt,
      Uint32 flags,
      Pointer<_DataBlob> dataOut,
    );
typedef _CryptUnprotectDataDart =
    int Function(
      Pointer<_DataBlob> dataIn,
      Pointer<Pointer<Uint16>> description,
      Pointer<_DataBlob> optionalEntropy,
      Pointer<Void> reserved,
      Pointer<Void> prompt,
      int flags,
      Pointer<_DataBlob> dataOut,
    );

typedef _LocalAllocNative = Pointer<Void> Function(Uint32 flags, IntPtr size);
typedef _LocalAllocDart = Pointer<Void> Function(int flags, int size);
typedef _LocalFreeNative = Pointer<Void> Function(Pointer<Void> memory);
typedef _LocalFreeDart = Pointer<Void> Function(Pointer<Void> memory);
typedef _GetLastErrorNative = Uint32 Function();
typedef _GetLastErrorDart = int Function();

class UserDataProtectionService {
  const UserDataProtectionService._();

  static const _cryptProtectUiForbidden = 0x1;
  static const _localAllocZeroInitialized = 0x40;

  static final _crypt32 = DynamicLibrary.open('crypt32.dll');
  static final _kernel32 = DynamicLibrary.open('kernel32.dll');
  static final _cryptProtectData = _crypt32
      .lookupFunction<_CryptProtectDataNative, _CryptProtectDataDart>(
        'CryptProtectData',
      );
  static final _cryptUnprotectData = _crypt32
      .lookupFunction<_CryptUnprotectDataNative, _CryptUnprotectDataDart>(
        'CryptUnprotectData',
      );
  static final _localAlloc = _kernel32
      .lookupFunction<_LocalAllocNative, _LocalAllocDart>('LocalAlloc');
  static final _localFree = _kernel32
      .lookupFunction<_LocalFreeNative, _LocalFreeDart>('LocalFree');
  static final _getLastError = _kernel32
      .lookupFunction<_GetLastErrorNative, _GetLastErrorDart>('GetLastError');

  static Future<String> protect(String plaintext) async {
    _ensureWindows();
    final plaintextBytes = Uint8List.fromList(utf8.encode(plaintext));
    try {
      final protectedBytes = _transform(plaintextBytes, protect: true);
      try {
        return base64Encode(protectedBytes);
      } finally {
        protectedBytes.fillRange(0, protectedBytes.length, 0);
      }
    } finally {
      plaintextBytes.fillRange(0, plaintextBytes.length, 0);
    }
  }

  static Future<String> unprotect(String ciphertext) async {
    _ensureWindows();
    final protectedBytes = Uint8List.fromList(base64Decode(ciphertext.trim()));
    if (protectedBytes.isEmpty) {
      throw const FormatException('Protected user data is empty.');
    }
    try {
      final plaintextBytes = _transform(protectedBytes, protect: false);
      try {
        return utf8.decode(plaintextBytes);
      } finally {
        plaintextBytes.fillRange(0, plaintextBytes.length, 0);
      }
    } finally {
      protectedBytes.fillRange(0, protectedBytes.length, 0);
    }
  }

  static Uint8List _transform(Uint8List input, {required bool protect}) {
    var inputBlob = nullptr.cast<_DataBlob>();
    var outputBlob = nullptr.cast<_DataBlob>();
    var inputData = nullptr.cast<Uint8>();

    try {
      inputBlob = _allocate<_DataBlob>(sizeOf<_DataBlob>());
      outputBlob = _allocate<_DataBlob>(sizeOf<_DataBlob>());
      inputData = _allocate<Uint8>(input.isEmpty ? 1 : input.length);

      inputBlob.ref
        ..length = input.length
        ..data = inputData;
      outputBlob.ref
        ..length = 0
        ..data = nullptr.cast<Uint8>();
      if (input.isNotEmpty) {
        inputData.asTypedList(input.length).setAll(0, input);
      }

      final succeeded = protect
          ? _cryptProtectData(
              inputBlob,
              nullptr.cast<Uint16>(),
              nullptr.cast<_DataBlob>(),
              nullptr.cast<Void>(),
              nullptr.cast<Void>(),
              _cryptProtectUiForbidden,
              outputBlob,
            )
          : _cryptUnprotectData(
              inputBlob,
              nullptr.cast<Pointer<Uint16>>(),
              nullptr.cast<_DataBlob>(),
              nullptr.cast<Void>(),
              nullptr.cast<Void>(),
              _cryptProtectUiForbidden,
              outputBlob,
            );
      if (succeeded == 0) {
        final errorCode = _getLastError();
        throw StateError(
          'Unable to ${protect ? 'protect' : 'decrypt'} local user data '
          '(Windows error $errorCode).',
        );
      }

      final outputLength = outputBlob.ref.length;
      final outputData = outputBlob.ref.data;
      if (outputLength > 0 && outputData.address == 0) {
        throw StateError('Windows returned invalid protected user data.');
      }
      return outputLength == 0
          ? Uint8List(0)
          : Uint8List.fromList(outputData.asTypedList(outputLength));
    } finally {
      _free(inputData.cast<Void>(), input.length);
      if (outputBlob.address != 0) {
        final outputData = outputBlob.ref.data;
        if (outputData.address != 0) {
          _free(outputData.cast<Void>(), outputBlob.ref.length);
        }
      }
      _free(inputBlob.cast<Void>(), sizeOf<_DataBlob>());
      _free(outputBlob.cast<Void>(), sizeOf<_DataBlob>());
    }
  }

  static Pointer<T> _allocate<T extends NativeType>(int size) {
    final pointer = _localAlloc(_localAllocZeroInitialized, size);
    if (pointer.address == 0) {
      throw StateError('Unable to allocate memory for local data protection.');
    }
    return pointer.cast<T>();
  }

  static void _free(Pointer<Void> pointer, int size) {
    if (pointer.address == 0) return;
    if (size > 0) {
      pointer.cast<Uint8>().asTypedList(size).fillRange(0, size, 0);
    }
    _localFree(pointer);
  }

  static void _ensureWindows() {
    if (!Platform.isWindows) {
      throw UnsupportedError('Local user data protection requires Windows.');
    }
  }
}
