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
import 'package:win_deploy_studio/core/services/linux_togo_image_preflight.dart';
import 'package:win_deploy_studio/core/services/wtg_service.dart';
import 'package:win_deploy_studio/core/services/windows_iso_preflight.dart';
import 'package:win_deploy_studio/features/mirror/screens/mirror_screen.dart';
import 'package:win_deploy_studio/features/wtg/screens/wtg_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('To Go platform selector is prominent and equal width narrowly', (
    tester,
  ) async {
    final oldError = FlutterError.onError;
    final details = <FlutterErrorDetails>[];
    FlutterError.onError = (value) {
      details.add(value);
      debugPrint(value.toString(minLevel: DiagnosticLevel.debug));
    };
    addTearDown(() => FlutterError.onError = oldError);
    await _setSurface(tester, const Size(320, 720));
    await _pumpApp(
      tester,
      const WtgScreen(),
      overrides: [
        diskSafetyServiceProvider.overrideWithValue(_NoDisksService()),
      ],
    );

    final selector = find.byKey(const Key('wtg-platform-selector'));
    expect(selector, findsOneWidget);

    final segments = find.descendant(
      of: selector,
      matching: find.byType(TextButton),
    );
    expect(segments, findsNWidgets(2));
    expect(
      tester.getSize(segments.at(0)).width,
      closeTo(tester.getSize(segments.at(1)).width, 0.01),
    );

    final subtitle = find.text(trByCode('en', 'wtg_subtitle'));
    final stepTitle = find.text(trByCode('en', 'deploy_image_title'));
    expect(
      tester.getTopLeft(selector).dy,
      greaterThan(tester.getBottomLeft(subtitle).dy),
    );
    expect(
      tester.getBottomLeft(selector).dy,
      lessThan(tester.getTopLeft(stepTitle).dy),
    );

    await tester.tap(find.byKey(const Key('wtg-platform-linux-label')));
    await tester.pumpAndSettle();
    expect(find.text(trByCode('en', 'wtg_linux_title')), findsOneWidget);
    debugPrint('Captured errors: ${details.length}');
  });

  testWidgets('invalid Windows ISO uses the explicit localized error', (
    tester,
  ) async {
    await _setSurface(tester, const Size(1000, 760));
    final originalPicker = FilePickerPlatform.instance;
    FilePickerPlatform.instance = _SingleFilePicker(r'C:\test\ubuntu.iso');
    addTearDown(() => FilePickerPlatform.instance = originalPicker);

    await _pumpApp(
      tester,
      const WtgScreen(),
      locale: const Locale('zh'),
      overrides: [
        diskSafetyServiceProvider.overrideWithValue(_NoDisksService()),
        isoParseServiceProvider.overrideWithValue(_ParsedIsoService()),
        wtgServiceProvider.overrideWithValue(_EmptyWimService()),
        windowsIsoPreflightProvider.overrideWithValue(
          _StaticWindowsIsoPreflight(
            const WindowsIsoLayoutInspection.invalid('Linux layout'),
          ),
        ),
      ],
    );

    await tester.tap(find.text(trByCode('zh', 'creator_select_btn')));
    await tester.pumpAndSettle();

    expect(
      find.text(trByCode('zh', 'wtg_invalid_windows_iso')),
      findsOneWidget,
    );
    expect(find.text(trByCode('zh', 'translation_missing')), findsNothing);
    expect(find.text('wtg_no_images'), findsNothing);
    _expectNoFlutterExceptions(tester);
  });

  testWidgets('Linux To Go rejects a Windows ISO before configuration', (
    tester,
  ) async {
    await _setSurface(tester, const Size(1000, 760));
    final originalPicker = FilePickerPlatform.instance;
    FilePickerPlatform.instance = _SingleFilePicker(r'C:\test\win11.iso');
    addTearDown(() => FilePickerPlatform.instance = originalPicker);

    await _pumpApp(
      tester,
      const WtgScreen(),
      locale: const Locale('zh'),
      overrides: [
        diskSafetyServiceProvider.overrideWithValue(_NoDisksService()),
        windowsIsoPreflightProvider.overrideWithValue(
          _StaticWindowsIsoPreflight(
            const WindowsIsoLayoutInspection.valid(
              imageFormat: WindowsInstallImageFormat.wim,
              imagePath: r'X:\sources\install.wim',
            ),
          ),
        ),
      ],
    );

    await tester.tap(find.byKey(const Key('wtg-platform-linux-label')));
    await tester.pumpAndSettle();
    await tester.tap(find.text(trByCode('zh', 'creator_select_btn')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(
      find.text(trByCode('zh', 'wtg_windows_iso_in_linux_mode')),
      findsOneWidget,
    );
    expect(find.text('win11.iso'), findsNothing);
    _expectNoFlutterExceptions(tester);
  });

  testWidgets(
    'Linux To Go explains an unsafe Debian Live image before Next is enabled',
    (tester) async {
      await _setSurface(tester, const Size(1000, 760));
      final originalPicker = FilePickerPlatform.instance;
      FilePickerPlatform.instance = _SingleFilePicker(
        r'C:\test\debian-live.iso',
      );
      addTearDown(() => FilePickerPlatform.instance = originalPicker);

      await _pumpApp(
        tester,
        const WtgScreen(),
        locale: const Locale('zh'),
        overrides: [
          diskSafetyServiceProvider.overrideWithValue(_NoDisksService()),
          windowsIsoPreflightProvider.overrideWithValue(
            _StaticWindowsIsoPreflight(
              const WindowsIsoLayoutInspection.invalid('Linux layout'),
            ),
          ),
          linuxToGoImagePreflightProvider.overrideWithValue(
            const _StaticLinuxToGoImagePreflight(
              LinuxToGoImageInspection.unsupported(
                LinuxToGoImageIssue.debianLiveMissingNtfsSupport,
              ),
            ),
          ),
        ],
      );

      await tester.tap(find.byKey(const Key('wtg-platform-linux-label')));
      await tester.pumpAndSettle();
      await tester.tap(find.text(trByCode('zh', 'creator_select_btn')));
      await _pumpUntilFound(
        tester,
        find.byKey(const Key('ltg-image-inspection')),
      );

      expect(find.byKey(const Key('ltg-image-inspection')), findsOneWidget);
      expect(
        find.text(
          trByCode('zh', 'linux_togo_debian_live_missing_ntfs_support'),
        ),
        findsWidgets,
      );
      final next = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, trByCode('zh', 'creator_next')),
      );
      expect(next.onPressed, isNull);
      _expectNoFlutterExceptions(tester);
    },
  );

  test('To Go ISO mismatch keys exist in every supported locale', () {
    for (final code in supportedLocaleCodes) {
      final missing = trByCode(code, 'translation_missing');
      for (final key in const [
        'wtg_invalid_windows_iso',
        'wtg_windows_iso_in_linux_mode',
        'linux_togo_unsupported_iso',
        'linux_togo_image_supported',
        'linux_togo_source_not_regular_file',
        'linux_togo_missing_x64_efi',
        'linux_togo_missing_live_kernel',
        'linux_togo_missing_live_initrd',
        'linux_togo_missing_live_payload',
        'linux_togo_debian_live_missing_ntfs_support',
        'linux_togo_debian_image_supported',
        'linux_togo_driver_staging_unsupported',
      ]) {
        final localized = trByCode(code, key);
        expect(localized, isNotEmpty, reason: '$code/$key is empty');
        expect(localized, isNot(missing), reason: '$code/$key is missing');
      }
    }
  });

  testWidgets('font pack list and category use the detail wrench icon', (
    tester,
  ) async {
    await _setSurface(tester, const Size(1100, 800));
    await _pumpApp(tester, const MirrorScreen(), locale: const Locale('zh'));

    final toolsLabel = find.text(trByCode('zh', 'tools_title'));
    await _pumpUntilFound(tester, toolsLabel);
    final toolsTile = find.ancestor(
      of: toolsLabel,
      matching: find.byType(ListTile),
    );
    expect(toolsTile, findsOneWidget);
    expect(
      find.descendant(of: toolsTile, matching: find.byIcon(Icons.build)),
      findsOneWidget,
    );

    await tester.tap(toolsLabel);
    await tester.pumpAndSettle();
    final fontPackName = find.text('CJK 字体包');
    expect(fontPackName, findsOneWidget);
    final fontPackCard = find.ancestor(
      of: fontPackName,
      matching: find.byType(Card),
    );
    expect(
      find.descendant(of: fontPackCard, matching: find.byIcon(Icons.build)),
      findsOneWidget,
    );
    _expectNoFlutterExceptions(tester);
  });

  testWidgets('font pack remains hidden outside Chinese locales', (
    tester,
  ) async {
    await _setSurface(tester, const Size(1100, 800));
    await _pumpApp(tester, const MirrorScreen());
    await _pumpUntilFound(
      tester,
      find.text(trByCode('en', 'images_category_all')),
    );

    expect(find.text('CJK 字体包'), findsNothing);
    expect(find.text(trByCode('en', 'tools_title')), findsNothing);
    _expectNoFlutterExceptions(tester);
  });
}

Future<void> _setSurface(WidgetTester tester, Size size) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
}

Future<void> _pumpApp(
  WidgetTester tester,
  Widget home, {
  Locale locale = const Locale('en'),
  List<Override> overrides = const [],
}) async {
  L.currentLocale = localeCodeFromLocale(locale);
  await tester.pumpWidget(
    ProviderScope(
      overrides: overrides,
      child: MaterialApp(
        locale: locale,
        supportedLocales: [locale],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        theme: AppTheme.light(const Color(0xFF0071C5), 'HarmonyOSSans'),
        home: home,
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
}

Future<void> _pumpUntilFound(WidgetTester tester, Finder finder) async {
  for (var index = 0; index < 50 && finder.evaluate().isEmpty; index++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  expect(finder, findsWidgets);
}

void _expectNoFlutterExceptions(WidgetTester tester) {
  final exceptions = <Object>[];
  Object? exception;
  while ((exception = tester.takeException()) != null) {
    exceptions.add(exception!);
  }
  expect(exceptions, isEmpty, reason: exceptions.join('\n\n'));
}

class _NoDisksService extends DiskSafetyService {
  @override
  Future<List<DiskInfo>> getRemovableDisks() async => const [];
}

class _ParsedIsoService extends IsoParseService {
  @override
  Future<IsoMetadata?> parseIso(
    String isoPath, {
    ProgressCallback? onProgress,
  }) async {
    return IsoMetadata(
      filePath: isoPath,
      fileName: 'ubuntu.iso',
      fileSize: 1024,
    );
  }
}

class _EmptyWimService implements WtgService {
  @override
  Future<List<Map<String, dynamic>>> getWimImages(String isoPath) async =>
      const [];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _StaticWindowsIsoPreflight implements WindowsIsoPreflight {
  const _StaticWindowsIsoPreflight(this.inspection);

  final WindowsIsoLayoutInspection inspection;

  @override
  Future<WindowsIsoLayoutInspection> inspect(String isoPath) async =>
      inspection;
}

class _StaticLinuxToGoImagePreflight implements LinuxToGoImagePreflight {
  const _StaticLinuxToGoImagePreflight(this.inspection);

  final LinuxToGoImageInspection inspection;

  @override
  Future<LinuxToGoImageInspection> inspect(String isoPath) async => inspection;
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
