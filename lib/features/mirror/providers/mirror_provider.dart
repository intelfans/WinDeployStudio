import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/mirror_models.dart';

enum MirrorLoadStatus { initial, loading, loaded, error }

class MirrorState {
  final MirrorLoadStatus status;
  final MirrorListData? data;
  final String? error;
  final List<LocalIsoInfo> localIsos;

  const MirrorState({
    this.status = MirrorLoadStatus.initial,
    this.data,
    this.error,
    this.localIsos = const [],
  });

  MirrorState copyWith({
    MirrorLoadStatus? status,
    MirrorListData? data,
    String? error,
    List<LocalIsoInfo>? localIsos,
  }) {
    return MirrorState(
      status: status ?? this.status,
      data: data ?? this.data,
      error: error ?? this.error,
      localIsos: localIsos ?? this.localIsos,
    );
  }
}

final mirrorProvider = StateNotifierProvider<MirrorNotifier, MirrorState>(
  (ref) => MirrorNotifier(),
);

class MirrorNotifier extends StateNotifier<MirrorState> {
  MirrorNotifier() : super(const MirrorState());

  Future<void> loadBuiltInMirrors({bool force = false}) async {
    if (!force && state.status == MirrorLoadStatus.loaded) return;

    state = state.copyWith(status: MirrorLoadStatus.loading);

    try {
      final jsonStr = await rootBundle.loadString('data/mirrors.json');
      final json = jsonDecode(jsonStr) as Map<String, dynamic>;
      final data = MirrorListData.fromJson(json);

      debugPrint('Built-in mirrors loaded: ${data.items.length} items');
      state = state.copyWith(
        status: MirrorLoadStatus.loaded,
        data: data,
      );
    } catch (e) {
      debugPrint('Failed to load built-in mirrors: $e');
      state = state.copyWith(
        status: MirrorLoadStatus.error,
        error: 'Failed to load mirror list: $e',
      );
    }
  }

  Future<void> scanLocalDirectory(String dirPath) async {
    try {
      final dir = Directory(dirPath);
      if (!await dir.exists()) return;

      final isos = <LocalIsoInfo>[];
      await for (final entity in dir.list(recursive: true)) {
        if (entity is File && entity.path.toLowerCase().endsWith('.iso')) {
          final fileSize = await entity.length();
          final fileName = entity.path.split(Platform.pathSeparator).last;
          isos.add(LocalIsoInfo(
            filePath: entity.path,
            fileName: fileName,
            fileSize: fileSize,
          ));
        }
      }

      debugPrint('Local ISOs found: ${isos.length} in $dirPath');
      state = state.copyWith(localIsos: isos);
    } catch (e) {
      debugPrint('Failed to scan local directory: $e');
    }
  }

  void clearLocalIsos() {
    state = state.copyWith(localIsos: []);
  }
}
