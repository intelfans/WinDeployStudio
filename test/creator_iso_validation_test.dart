import 'package:file_picker/file_picker.dart';
// ignore: implementation_imports
import 'package:file_picker/src/platform/file_picker_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
// ignore: implementation_imports
import 'package:flutter_riverpod/src/internals.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:win_deploy_studio/app/theme.dart';
import 'package:win_deploy_studio/core/localization/strings.dart';
import 'package:win_deploy_studio/core/services/disk_safety_service.dart';
import 'package:win_deploy_studio/core/services/iso_parse_service.dart';
import 'package:win_deploy_studio/features/creator/screens/creator_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Windows creator rejects a Linux ISO before USB selection', (
    tester,
  ) async {
    final originalPicker = FilePickerPlatform.instance;
    FilePickerPlatform.instance = _SingleFilePicker(r'C:\test\ubuntu.iso');
    addTearDown(() => FilePickerPlatform.instance = originalPicker);

    await _pumpCreator(
      tester,
      overrides: [
        diskSafetyServiceProvider.overrideWithValue(_NoDisksService()),
        isoParseServiceProvider.overrideWithValue(
          _StaticIsoParseService(
            const IsoMetadata(
              filePath: r'C:\test\ubuntu.iso',
              fileName: 'ubuntu.iso',
              fileSize: 1024,
            ),
          ),
        ),
      ],
    );

    await tester.tap(find.text(trByCode('zh', 'creator_select_btn')));
    await tester.pumpAndSettle();

    expect(
      find.text(trByCode('zh', 'creator_invalid_windows_iso')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('creator-iso-selection-error')),
      findsOneWidget,
    );
    expect(find.byType(SnackBar), findsNothing);
    expect(find.text('ubuntu.iso'), findsNothing);
  });

  testWidgets('Linux creator rejects a Windows ISO before USB selection', (
    tester,
  ) async {
    final originalPicker = FilePickerPlatform.instance;
    FilePickerPlatform.instance = _SingleFilePicker(r'C:\test\win11.iso');
    addTearDown(() => FilePickerPlatform.instance = originalPicker);

    await _pumpCreator(
      tester,
      overrides: [
        diskSafetyServiceProvider.overrideWithValue(_NoDisksService()),
        isoParseServiceProvider.overrideWithValue(
          _StaticIsoParseService(
            const IsoMetadata(
              filePath: r'C:\test\win11.iso',
              fileName: 'win11.iso',
              fileSize: 1024,
              isValidWindowsIso: true,
            ),
          ),
        ),
      ],
    );

    await tester.tap(find.text(trByCode('zh', 'creator_platform_linux')));
    await tester.pumpAndSettle();
    await tester.tap(find.text(trByCode('zh', 'creator_select_btn')));
    await tester.pumpAndSettle();

    expect(
      find.text(trByCode('zh', 'creator_windows_iso_in_linux_mode')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('creator-iso-selection-error')),
      findsOneWidget,
    );
    expect(find.byType(SnackBar), findsNothing);
    expect(find.text('win11.iso'), findsNothing);
  });

  testWidgets('ISO parsing error stays in the selection area', (tester) async {
    final originalPicker = FilePickerPlatform.instance;
    FilePickerPlatform.instance = _SingleFilePicker(r'C:\test\broken.iso');
    addTearDown(() => FilePickerPlatform.instance = originalPicker);

    await _pumpCreator(
      tester,
      overrides: [
        diskSafetyServiceProvider.overrideWithValue(_NoDisksService()),
        isoParseServiceProvider.overrideWithValue(_StaticIsoParseService(null)),
      ],
    );

    await tester.tap(find.text(trByCode('zh', 'creator_select_btn')));
    await tester.pumpAndSettle();

    expect(find.text(trByCode('zh', 'creator_parse_error')), findsOneWidget);
    expect(
      find.byKey(const Key('creator-iso-selection-error')),
      findsOneWidget,
    );
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('ISO mount failure is not reported as an invalid image', (
    tester,
  ) async {
    final originalPicker = FilePickerPlatform.instance;
    FilePickerPlatform.instance = _SingleFilePicker(r'C:\test\windows 7.iso');
    addTearDown(() => FilePickerPlatform.instance = originalPicker);

    await _pumpCreator(
      tester,
      overrides: [
        diskSafetyServiceProvider.overrideWithValue(_NoDisksService()),
        isoParseServiceProvider.overrideWithValue(
          _StaticIsoParseService(
            const IsoMetadata(
              filePath: r'C:\test\windows 7.iso',
              fileName: 'windows 7.iso',
              fileSize: 1024,
              windowsVersion: 'Windows 7',
              validationErrorKey: 'creator_iso_mount_failed',
              validationErrorDetail: 'Mount-DiskImage timed out.',
            ),
          ),
        ),
      ],
    );

    await tester.tap(find.text(trByCode('zh', 'creator_select_btn')));
    await tester.pumpAndSettle();

    expect(
      find.text(trByCode('zh', 'creator_iso_mount_failed')),
      findsOneWidget,
    );
    expect(
      find.text(trByCode('zh', 'creator_invalid_windows_iso')),
      findsNothing,
    );
    expect(
      find.byKey(const Key('creator-iso-selection-error')),
      findsOneWidget,
    );
  });

  testWidgets(
    'Windows creator can clear a selected drive icon and restore the default',
    (tester) async {
      final originalPicker = FilePickerPlatform.instance;
      FilePickerPlatform.instance = _QueuedFilePicker(const [
        r'C:\test\win11.iso',
        r'C:\test\portable.ico',
      ]);
      addTearDown(() => FilePickerPlatform.instance = originalPicker);

      await _pumpCreator(
        tester,
        overrides: [
          diskSafetyServiceProvider.overrideWithValue(_SafeDiskService()),
          isoParseServiceProvider.overrideWithValue(
            _StaticIsoParseService(
              const IsoMetadata(
                filePath: r'C:\test\win11.iso',
                fileName: 'win11.iso',
                fileSize: 1024,
                isValidWindowsIso: true,
              ),
            ),
          ),
        ],
      );

      await tester.tap(find.text(trByCode('zh', 'creator_select_btn')));
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('Test USB').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text(trByCode('zh', 'creator_next_confirm')));
      await tester.pumpAndSettle();

      final installOptions = find.text(
        trByCode('zh', 'deploy_install_options'),
      );
      await tester.ensureVisible(installOptions);
      await tester.tap(installOptions);
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('creator-volume-label')), findsOneWidget);
      expect(
        find.text(trByCode('zh', 'deploy_custom_icon_default')),
        findsOneWidget,
      );

      final picker = find.byKey(const Key('creator-icon-picker'));
      await tester.ensureVisible(picker);
      await tester.tap(picker);
      await tester.pumpAndSettle();

      expect(find.text(r'C:\test\portable.ico'), findsOneWidget);
      expect(find.byKey(const Key('creator-icon-clear')), findsOneWidget);

      await tester.tap(find.byKey(const Key('creator-icon-clear')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('creator-icon-clear')), findsNothing);
      expect(
        find.text(trByCode('zh', 'deploy_custom_icon_default')),
        findsOneWidget,
      );
    },
  );

  test('creator ISO validation strings exist in every supported locale', () {
    for (final locale in supportedLocaleCodes) {
      final missing = trByCode(locale, 'translation_missing');
      for (final key in const [
        'creator_select_iso_desc',
        'creator_parse_error',
        'creator_iso_mount_failed',
        'creator_invalid_windows_iso',
        'creator_windows_iso_in_linux_mode',
      ]) {
        final value = trByCode(locale, key);
        expect(value, isNotEmpty, reason: '$locale/$key is empty');
        expect(value, isNot(missing), reason: '$locale/$key is missing');
      }
    }
  });
}

Future<void> _pumpCreator(
  WidgetTester tester, {
  required List<Override> overrides,
}) async {
  L.currentLocale = 'zh';
  await tester.pumpWidget(
    ProviderScope(
      overrides: overrides,
      child: MaterialApp(
        locale: const Locale('zh'),
        supportedLocales: const [Locale('zh')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        theme: AppTheme.light(const Color(0xFF0071C5), 'HarmonyOSSans'),
        home: const CreatorScreen(),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
}

class _NoDisksService extends DiskSafetyService {
  @override
  Future<List<DiskInfo>> getRemovableDisks() async => const [];
}

class _SafeDiskService extends DiskSafetyService {
  static const _disk = DiskInfo(
    diskNumber: 7,
    model: 'Test USB',
    friendlyName: 'Test USB',
    sizeBytes: 64 * 1024 * 1024 * 1024,
    sizeFormatted: '64 GB',
    busType: 'USB',
    isRemovable: true,
  );

  @override
  Future<List<DiskInfo>> getRemovableDisks() async => const [_disk];

  @override
  Future<SafetyCheckResult> checkDiskSafety(DiskInfo disk) async =>
      const SafetyCheckResult(isSafe: true);
}

class _StaticIsoParseService extends IsoParseService {
  _StaticIsoParseService(this.metadata);

  final IsoMetadata? metadata;

  @override
  Future<IsoMetadata?> parseIso(
    String isoPath, {
    ProgressCallback? onProgress,
  }) async => metadata;
}

class _SingleFilePicker extends FilePickerPlatform {
  _SingleFilePicker(this.path);

  final String path;

  @override
  Future<FilePickerResult?> pickFiles({
    String? dialogTitle,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Function(FilePickerStatus)? onFileLoading,
    int compressionQuality = 0,
    bool allowMultiple = false,
    bool withData = false,
    bool withReadStream = false,
    bool lockParentWindow = false,
    bool readSequential = false,
    bool cancelUploadOnWindowBlur = true,
  }) async {
    return FilePickerResult([
      PlatformFile(name: path.split('\\').last, size: 1024, path: path),
    ]);
  }
}

class _QueuedFilePicker extends FilePickerPlatform {
  _QueuedFilePicker(this.paths);

  final List<String> paths;
  var _index = 0;

  @override
  Future<FilePickerResult?> pickFiles({
    String? dialogTitle,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Function(FilePickerStatus)? onFileLoading,
    int compressionQuality = 0,
    bool allowMultiple = false,
    bool withData = false,
    bool withReadStream = false,
    bool lockParentWindow = false,
    bool readSequential = false,
    bool cancelUploadOnWindowBlur = true,
  }) async {
    final path = paths[_index++];
    return FilePickerResult([
      PlatformFile(name: path.split('\\').last, size: 1024, path: path),
    ]);
  }
}
