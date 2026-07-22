// Debug dialog strings are kept separate so every supported locale has the
// same explicit key set. Do not add locale fallbacks here.

const _debugDialogLocaleCodes = <String>[
  'zh',
  'zh_TW',
  'en',
  'fr',
  'de',
  'es',
  'pt',
  'ru',
  'ar',
  'ko',
  'ja',
];

typedef _Translations = List<String>;

Map<String, String> debugDialogStringsForCode(String code) =>
    _debugDialogStrings[code] ?? const <String, String>{};

final Map<String, Map<String, String>> _debugDialogStrings =
    _buildDebugDialogStrings();

Map<String, Map<String, String>> _buildDebugDialogStrings() {
  final result = <String, Map<String, String>>{
    for (final code in _debugDialogLocaleCodes) code: <String, String>{},
  };
  for (final entry in _debugDialogRows.entries) {
    assert(
      entry.value.length == _debugDialogLocaleCodes.length,
      '${entry.key} must define all debug dialog locales',
    );
    for (var index = 0; index < _debugDialogLocaleCodes.length; index++) {
      result[_debugDialogLocaleCodes[index]]![entry.key] = entry.value[index];
    }
  }
  return result;
}

// Value order: zh, zh_TW, en, fr, de, es, pt, ru, ar, ko, ja.
const Map<String, _Translations> _debugDialogRows = {
  'intel_operating_system': [
    '操作系统',
    '作业系统',
    'Operating system',
    'Systeme d\'exploitation',
    'Betriebssystem',
    'Sistema operativo',
    'Sistema operacional',
    'Операционная система',
    'نظام التشغيل',
    '운영 체제',
    'オペレーティング システム',
  ],
  'intel_framework': [
    'Flutter',
    'Flutter',
    'Flutter',
    'Flutter',
    'Flutter',
    'Flutter',
    'Flutter',
    'Flutter',
    'Flutter',
    'Flutter',
    'Flutter',
  ],
  'intel_unknown_cpu': [
    '未知 CPU',
    '未知 CPU',
    'Unknown CPU',
    'Processeur inconnu',
    'Unbekannte CPU',
    'CPU desconocida',
    'CPU desconhecida',
    'Неизвестный ЦП',
    'وحدة معالجة مركزية غير معروفة',
    '알 수 없는 CPU',
    '不明な CPU',
  ],
  'intel_unknown_gpu': [
    '未知 GPU',
    '未知 GPU',
    'Unknown GPU',
    'GPU inconnue',
    'Unbekannte GPU',
    'GPU desconocida',
    'GPU desconhecida',
    'Неизвестный графический процессор',
    'وحدة معالجة رسومية غير معروفة',
    '알 수 없는 GPU',
    '不明な GPU',
  ],
  'intel_unknown_value': [
    '未知',
    '未知',
    'Unknown',
    'Inconnu',
    'Unbekannt',
    'Desconocido',
    'Desconhecido',
    'Неизвестно',
    'غير معروف',
    '알 수 없음',
    '不明',
  ],
};
