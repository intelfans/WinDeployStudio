import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'app/app.dart';
import 'app/theme.dart';
import 'core/localization/strings.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final preferences = await SharedPreferences.getInstance();
  // Honour the saved skin. Forcing Windows 11 here made the other three skins
  // unreachable and their translations dead.
  final appearance = AppAppearanceSettings.fromPreferences(preferences);
  final languageCode = preferences.getString('language_code');
  final startupLocale = languageCode == null || languageCode.isEmpty
      ? null
      : localeFromCode(languageCode);
  await WindowStyleChannel.instance.initialize(appearance);

  runApp(
    ProviderScope(
      overrides: [initialAppearanceProvider.overrideWithValue(appearance)],
      child: WinDeployStudioApp(
        hasSelectedLanguage: languageCode != null && languageCode.isNotEmpty,
        startupLocale: startupLocale,
      ),
    ),
  );
}
