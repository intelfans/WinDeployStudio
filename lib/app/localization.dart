import 'package:flutter/widgets.dart';

const supportedAppLocales = <Locale>[
  Locale('zh'),
  Locale('zh', 'TW'),
  Locale('en'),
  Locale('fr'),
  Locale('de'),
  Locale('es'),
  Locale('pt'),
  Locale('ru'),
  Locale('ar'),
  Locale('ko'),
  Locale('ja'),
];

TextDirection textDirectionForLocale(Locale locale) {
  return locale.languageCode == 'ar' ? TextDirection.rtl : TextDirection.ltr;
}
