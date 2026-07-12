import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'app/app.dart';
import 'app/elevated_task_app.dart';
import 'app/theme.dart';
import 'core/localization/strings.dart';
import 'core/services/elevation_service.dart';

void main(List<String> arguments) async {
  WidgetsFlutterBinding.ensureInitialized();

  final taskArgument = arguments.where(
    (argument) => argument.startsWith('--elevated-task='),
  );
  if (taskArgument.isNotEmpty) {
    final encoded = taskArgument.first.substring('--elevated-task='.length);
    final task = ElevatedTaskSpec.decode(encoded);
    await WindowStyleChannel.instance.initialize(
      (task.appearance ?? AppAppearanceSettings.defaults).copyWith(
        visualStyle: VisualStyle.win11,
      ),
    );
    runApp(ProviderScope(child: ElevatedTaskApp(task: task)));
    return;
  }

  final preferences = await SharedPreferences.getInstance();
  final appearance = AppAppearanceSettings.fromPreferences(
    preferences,
  ).copyWith(visualStyle: VisualStyle.win11);
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
