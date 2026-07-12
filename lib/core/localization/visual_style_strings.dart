const _visualStyleLocaleCodes = <String>[
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

typedef _VisualStyleTranslations = List<String>;

final Map<String, Map<String, String>> _visualStyleStrings =
    _buildVisualStyleStrings();

Map<String, String> visualStyleStringsForCode(String code) {
  final localized = _visualStyleStrings[code] ?? _visualStyleStrings['en']!;
  return Map.unmodifiable({
    ...localized,
    // VisualStyleLocalizationKeys predates the canonical visual_style_* names.
    // Keep aliases synchronized with each locale's explicit translations.
    'settings_visual_style': localized['visual_style_title']!,
    'settings_visual_style_desc': localized['visual_style_description']!,
    'settings_visual_style_auto': localized['visual_style_auto_label']!,
    'settings_visual_style_auto_desc':
        localized['visual_style_auto_description']!,
    'settings_visual_style_win11': localized['visual_style_win11_label']!,
    'settings_visual_style_win11_desc':
        localized['visual_style_win11_description']!,
    'settings_visual_style_win10': localized['visual_style_win10_label']!,
    'settings_visual_style_win10_desc':
        localized['visual_style_win10_description']!,
    'settings_visual_style_win7': localized['visual_style_win7_label']!,
    'settings_visual_style_win7_desc':
        localized['visual_style_win7_description']!,
  });
}

Map<String, Map<String, String>> _buildVisualStyleStrings() {
  final result = <String, Map<String, String>>{
    for (final code in _visualStyleLocaleCodes) code: <String, String>{},
  };
  for (final entry in _visualStyleRows.entries) {
    assert(
      entry.value.length == _visualStyleLocaleCodes.length,
      '${entry.key} must define all visual-style locales',
    );
    for (var index = 0; index < _visualStyleLocaleCodes.length; index++) {
      result[_visualStyleLocaleCodes[index]]![entry.key] = entry.value[index];
    }
  }
  return Map<String, Map<String, String>>.unmodifiable({
    for (final entry in result.entries)
      entry.key: Map<String, String>.unmodifiable(entry.value),
  });
}

// Value order: zh, zh_TW, en, fr, de, es, pt, ru, ar, ko, ja.
const Map<String, _VisualStyleTranslations> _visualStyleRows = {
  'visual_style_title': [
    '界面风格',
    '介面風格',
    'Visual style',
    'Style visuel',
    'Darstellungsstil',
    'Estilo visual',
    'Estilo visual',
    'Стиль интерфейса',
    'نمط الواجهة',
    '인터페이스 스타일',
    'インターフェース スタイル',
  ],
  'visual_style_description': [
    '选择最适合当前 Windows 版本的界面风格',
    '選擇最符合目前 Windows 版本的介面風格',
    'Choose the interface style that best matches your Windows version',
    'Choisissez le style d’interface qui correspond le mieux à votre version de Windows',
    'Wählen Sie den Oberflächenstil, der am besten zu Ihrer Windows-Version passt',
    'Elija el estilo de interfaz que mejor se adapte a su versión de Windows',
    'Escolha o estilo de interface que melhor combina com sua versão do Windows',
    'Выберите стиль интерфейса, который лучше всего соответствует вашей версии Windows',
    'اختر نمط الواجهة الأنسب لإصدار Windows لديك',
    'Windows 버전에 가장 잘 맞는 인터페이스 스타일을 선택하세요',
    'お使いの Windows バージョンに最も合うインターフェース スタイルを選択します',
  ],
  'visual_style_auto_label': [
    '自动',
    '自動',
    'Automatic',
    'Automatique',
    'Automatisch',
    'Automático',
    'Automático',
    'Автоматически',
    'تلقائي',
    '자동',
    '自動',
  ],
  'visual_style_auto_description': [
    '根据 Windows 版本选择匹配的界面风格',
    '依 Windows 版本選擇相符的介面風格',
    'Match the interface style to the Windows version',
    'Adapte le style d’interface à la version de Windows',
    'Passt den Oberflächenstil an die Windows-Version an',
    'Adapta el estilo de interfaz a la versión de Windows',
    'Adapta o estilo de interface à versão do Windows',
    'Подбирает стиль интерфейса по версии Windows',
    'يطابق نمط الواجهة مع إصدار Windows',
    'Windows 버전에 맞춰 인터페이스 스타일을 선택합니다',
    'Windows のバージョンに合わせてインターフェース スタイルを選択します',
  ],
  'visual_style_win11_label': [
    'Windows 11',
    'Windows 11',
    'Windows 11',
    'Windows 11',
    'Windows 11',
    'Windows 11',
    'Windows 11',
    'Windows 11',
    'Windows 11',
    'Windows 11',
    'Windows 11',
  ],
  'visual_style_win11_description': [
    '圆角、轻量阴影和现代间距',
    '圓角、輕量陰影和現代間距',
    'Rounded surfaces, soft shadows, and modern spacing',
    'Surfaces arrondies, ombres douces et espacement moderne',
    'Abgerundete Flächen, weiche Schatten und moderne Abstände',
    'Superficies redondeadas, sombras suaves y espaciado moderno',
    'Superfícies arredondadas, sombras suaves e espaçamento moderno',
    'Скруглённые поверхности, мягкие тени и современные интервалы',
    'أسطح مستديرة وظلال ناعمة ومسافات حديثة',
    '둥근 표면, 부드러운 그림자, 현대적인 간격',
    '角丸のサーフェス、柔らかな影、モダンな余白',
  ],
  'visual_style_win10_label': [
    'Windows 10',
    'Windows 10',
    'Windows 10',
    'Windows 10',
    'Windows 10',
    'Windows 10',
    'Windows 10',
    'Windows 10',
    'Windows 10',
    'Windows 10',
    'Windows 10',
  ],
  'visual_style_win10_description': [
    '紧凑控件和克制的圆角',
    '緊湊控制項和克制的圓角',
    'Compact controls and restrained rounding',
    'Contrôles compacts et coins légèrement arrondis',
    'Kompakte Steuerelemente und dezente Abrundungen',
    'Controles compactos y esquinas discretamente redondeadas',
    'Controles compactos e cantos discretamente arredondados',
    'Компактные элементы управления и сдержанные скругления',
    'عناصر تحكم مدمجة وزوايا مستديرة باعتدال',
    '간결한 컨트롤과 절제된 모서리 둥글림',
    'コンパクトなコントロールと控えめな角丸',
  ],
  'visual_style_win7_label': [
    'Windows 7',
    'Windows 7',
    'Windows 7',
    'Windows 7',
    'Windows 7',
    'Windows 7',
    'Windows 7',
    'Windows 7',
    'Windows 7',
    'Windows 7',
    'Windows 7',
  ],
  'visual_style_win7_description': [
    '紧凑布局、边框和经典阴影',
    '緊湊版面、邊框和經典陰影',
    'Compact layout, borders, and classic shadows',
    'Disposition compacte, bordures et ombres classiques',
    'Kompaktes Layout, Rahmen und klassische Schatten',
    'Diseño compacto, bordes y sombras clásicas',
    'Layout compacto, bordas e sombras clássicas',
    'Компактная компоновка, рамки и классические тени',
    'تخطيط مدمج وحدود وظلال كلاسيكية',
    '간결한 레이아웃, 테두리, 고전적인 그림자',
    'コンパクトなレイアウト、枠線、クラシックな影',
  ],
};
