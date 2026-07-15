import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:win_deploy_studio/core/localization/strings.dart';
import 'package:win_deploy_studio/core/services/iso_parse_service.dart';
import 'package:win_deploy_studio/core/services/known_iso_verification_service.dart';
import 'package:win_deploy_studio/features/mirror/models/mirror_models.dart';
import 'package:win_deploy_studio/shared/widgets/known_iso_verification_panel.dart';

void main() {
  const verificationKeys = <String>[
    'known_iso_verified',
    'known_iso_system',
    'known_iso_language',
    'known_iso_language_english',
    'known_iso_language_simplified_chinese',
    'known_iso_language_traditional_chinese',
    'known_iso_language_not_specified',
  ];

  test('verification labels are translated for every supported locale', () {
    for (final locale in supportedLocaleCodes) {
      for (final key in verificationKeys) {
        expect(
          trByCode(locale, key),
          isNotEmpty,
          reason: '$key must be localized for $locale',
        );
        expect(
          trByCode(locale, key),
          isNot(trByCode(locale, 'translation_missing')),
          reason:
              '$key must not fall back to the missing-text message for $locale',
        );
      }
    }
  });

  testWidgets('shows a verified image name, system, and language', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        locale: const Locale('zh'),
        verification: _tiny10Verification(),
        iso: const IsoMetadata(
          filePath: 'C:/Images/Tiny10.iso',
          fileName: 'Tiny10.iso',
          fileSize: 1,
          windowsVersion: 'Windows 10',
          edition: 'Windows 10 Pro',
          buildNumber: '22H2',
          architecture: 'x64',
        ),
      ),
    );

    expect(
      find.byKey(const Key('known-iso-verification-panel')),
      findsOneWidget,
    );
    expect(
      find.text('${trByCode('zh', 'known_iso_verified')}: Tiny10'),
      findsOneWidget,
    );
    expect(
      find.text(
        '${trByCode('zh', 'known_iso_system')}: '
        'Windows 10 • Windows 10 Pro • '
        '${trByCode('zh', 'creator_build_prefix')} 22H2 • x64',
      ),
      findsOneWidget,
    );
    expect(
      find.text(
        '${trByCode('zh', 'known_iso_language')}: '
        '${trByCode('zh', 'known_iso_language_english')}',
      ),
      findsOneWidget,
    );
  });

  testWidgets('renders nothing for an unknown or mismatched image', (
    tester,
  ) async {
    await tester.pumpWidget(_host());

    expect(find.byKey(const Key('known-iso-verification-panel')), findsNothing);
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.byType(SnackBar), findsNothing);
  });
}

Widget _host({
  Locale locale = const Locale('en'),
  KnownIsoVerification? verification,
  IsoMetadata? iso,
}) {
  return MaterialApp(
    locale: locale,
    supportedLocales: supportedLocaleCodes.map(localeFromCode).toList(),
    localizationsDelegates: GlobalMaterialLocalizations.delegates,
    home: Scaffold(
      body: KnownIsoVerificationPanel(verification: verification, iso: iso),
    ),
  );
}

KnownIsoVerification _tiny10Verification() {
  return KnownIsoVerification(
    image: KnownImage.fromJson(<String, dynamic>{
      'id': 'tiny10',
      'name': <String, String>{'zh': 'Tiny10', 'en': 'Tiny10'},
      'sha256':
          'a11116c0645d892d6a5a7c585ecc1fa13aa66f8c7cc6b03bf1f27bd16860cc35',
      'md5': '893f0df3bb42f3a4d63ed3632ac47d59',
    }),
    sha256: 'a11116c0645d892d6a5a7c585ecc1fa13aa66f8c7cc6b03bf1f27bd16860cc35',
    md5: '893f0df3bb42f3a4d63ed3632ac47d59',
  );
}
