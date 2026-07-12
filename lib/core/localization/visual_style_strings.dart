Map<String, String> visualStyleStringsForCode(String code) {
  const en = {
    'visual_style_title': 'Visual style',
    'visual_style_description':
        'Choose the interface style that best matches your Windows version',
    'visual_style_auto_label': 'Automatic',
    'visual_style_auto_description':
        'Match the interface style to the Windows version',
    'visual_style_win11_label': 'Windows 11',
    'visual_style_win11_description':
        'Rounded surfaces, soft shadows, and modern spacing',
    'visual_style_win10_label': 'Windows 10',
    'visual_style_win10_description':
        'Compact controls and restrained rounding',
    'visual_style_win7_label': 'Windows 7',
    'visual_style_win7_description':
        'Compact layout, borders, and classic shadows',
  };

  final localized = switch (code) {
    'zh' => {
      ...en,
      'visual_style_title': '界面风格',
      'visual_style_auto_label': '自动',
      'visual_style_auto_description': '根据 Windows 版本选择匹配的界面风格',
      'visual_style_win11_description': '圆角、轻量阴影和现代间距',
      'visual_style_win10_description': '紧凑控件和克制的圆角',
      'visual_style_win7_description': '紧凑布局、边框和经典阴影',
    },
    'zh_TW' => {
      ...en,
      'visual_style_title': '介面風格',
      'visual_style_auto_label': '自動',
      'visual_style_auto_description': '依 Windows 版本選擇相符的介面風格',
      'visual_style_win11_description': '圓角、輕量陰影和現代間距',
      'visual_style_win10_description': '緊湊控制項和克制的圓角',
      'visual_style_win7_description': '緊湊版面、邊框和經典陰影',
    },
    'fr' => {...en, 'visual_style_title': 'Style visuel'},
    'de' => {...en, 'visual_style_title': 'Darstellung'},
    'es' => {...en, 'visual_style_title': 'Estilo visual'},
    'pt' => {...en, 'visual_style_title': 'Estilo visual'},
    'ru' => {...en, 'visual_style_title': 'Стиль интерфейса'},
    'ar' => {...en, 'visual_style_title': 'نمط الواجهة'},
    'ko' => {...en, 'visual_style_title': '인터페이스 스타일'},
    'ja' => {...en, 'visual_style_title': 'インターフェース スタイル'},
    _ => en,
  };

  // VisualStyleLocalizationKeys predates the canonical visual_style_* names.
  // Keep aliases synchronized with localized values so all locales expose the
  // same complete key set without duplicating translations in each branch.
  return {
    ...localized,
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
  };
}
