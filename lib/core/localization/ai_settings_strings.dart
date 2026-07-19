/// Localized copy for the configurable OpenAI-compatible AI connection.
///
/// Kept separate from the large base dictionary so the credential/model
/// controls stay in sync across every supported locale.
Map<String, String> aiSettingsStringsForCode(String code) {
  return switch (code) {
    'zh' => const {
      'ai_api_key': 'API Key',
      'ai_default': '默认',
      'ai_api_key_desc': '仅发送到当前明确配置的 AI 服务端点。应用不会记录或显示完整密钥。',
      'ai_api_key_saved': '已保存（密钥已加密）',
      'ai_api_key_not_set': '未设置',
      'ai_api_key_endpoint_required': '请先设置自定义 AI 服务端点，再保存 API Key',
      'ai_api_key_invalid': '请输入不含空格或换行的有效 API Key',
      'ai_api_key_clear': '清除 API Key',
      'ai_api_key_show': '显示 API Key',
      'ai_api_key_hide': '隐藏 API Key',
      'ai_model': '模型',
      'ai_model_not_set': '未设置',
      'ai_model_desc': '选择或输入服务端点支持的模型 ID。',
      'ai_model_loading': '正在加载模型...',
      'ai_models_refresh': '从服务端点获取模型',
      'ai_models_load_failed': '无法获取模型列表，请检查端点和 API Key。你仍可以手动输入模型 ID。',
      'ai_model_invalid': '请输入有效的模型 ID',
      'ai_model_select': '可用模型',
      'ai_api_key_required_for_models': '获取模型列表需要 API Key。',
    },
    'zh_TW' => const {
      'ai_api_key': 'API Key',
      'ai_default': '預設',
      'ai_api_key_desc': '僅傳送至目前明確設定的 AI 服務端點。應用程式不會記錄或顯示完整金鑰。',
      'ai_api_key_saved': '已儲存（金鑰已加密）',
      'ai_api_key_not_set': '未設定',
      'ai_api_key_endpoint_required': '請先設定自訂 AI 服務端點，再儲存 API Key',
      'ai_api_key_invalid': '請輸入不含空格或換行的有效 API Key',
      'ai_api_key_clear': '清除 API Key',
      'ai_api_key_show': '顯示 API Key',
      'ai_api_key_hide': '隱藏 API Key',
      'ai_model': '模型',
      'ai_model_not_set': '未設定',
      'ai_model_desc': '選擇或輸入服務端點支援的模型 ID。',
      'ai_model_loading': '正在載入模型...',
      'ai_models_refresh': '從服務端點取得模型',
      'ai_models_load_failed': '無法取得模型清單，請檢查端點與 API Key。仍可手動輸入模型 ID。',
      'ai_model_invalid': '請輸入有效的模型 ID',
      'ai_model_select': '可用模型',
      'ai_api_key_required_for_models': '取得模型清單需要 API Key。',
    },
    'ru' => const {
      'ai_api_key': 'API Key',
      'ai_default': 'По умолчанию',
      'ai_api_key_desc':
          'Ключ отправляется только на явно настроенную конечную точку AI. Полный ключ не сохраняется в журналах и не отображается.',
      'ai_api_key_saved': 'Сохранён (зашифрован)',
      'ai_api_key_not_set': 'Не задан',
      'ai_api_key_endpoint_required':
          'Сначала настройте пользовательскую конечную точку AI, затем сохраните API Key',
      'ai_api_key_invalid':
          'Введите действительный API Key без пробелов и переводов строк',
      'ai_api_key_clear': 'Очистить API Key',
      'ai_api_key_show': 'Показать API Key',
      'ai_api_key_hide': 'Скрыть API Key',
      'ai_model': 'Модель',
      'ai_model_not_set': 'Не задана',
      'ai_model_desc':
          'Выберите или введите ID модели, поддерживаемой конечной точкой.',
      'ai_model_loading': 'Загрузка моделей...',
      'ai_models_refresh': 'Получить модели с конечной точки',
      'ai_models_load_failed':
          'Не удалось получить список моделей. Проверьте конечную точку и API Key. ID можно ввести вручную.',
      'ai_model_invalid': 'Введите действительный ID модели',
      'ai_model_select': 'Доступные модели',
      'ai_api_key_required_for_models':
          'Для получения списка моделей нужен API Key.',
    },
    'fr' => const {
      'ai_api_key': 'API Key',
      'ai_default': 'Par défaut',
      'ai_api_key_desc':
          'La clé est envoyée uniquement au point de terminaison IA configuré. La clé complète n’est ni journalisée ni affichée.',
      'ai_api_key_saved': 'Enregistrée (chiffrée)',
      'ai_api_key_not_set': 'Non définie',
      'ai_api_key_endpoint_required':
          'Configurez d’abord un point de terminaison IA personnalisé avant d’enregistrer l’API Key',
      'ai_api_key_invalid':
          'Saisissez une API Key valide sans espaces ni retours à la ligne',
      'ai_api_key_clear': 'Effacer l’API Key',
      'ai_api_key_show': 'Afficher l’API Key',
      'ai_api_key_hide': 'Masquer l’API Key',
      'ai_model': 'Modèle',
      'ai_model_not_set': 'Non défini',
      'ai_model_desc':
          'Choisissez ou saisissez l’identifiant d’un modèle pris en charge.',
      'ai_model_loading': 'Chargement des modèles...',
      'ai_models_refresh': 'Obtenir les modèles du service',
      'ai_models_load_failed':
          'Impossible de récupérer les modèles. Vérifiez le point de terminaison et l’API Key. Vous pouvez saisir un identifiant manuellement.',
      'ai_model_invalid': 'Saisissez un identifiant de modèle valide',
      'ai_model_select': 'Modèles disponibles',
      'ai_api_key_required_for_models':
          'Une API Key est nécessaire pour obtenir les modèles.',
    },
    'de' => const {
      'ai_api_key': 'API Key',
      'ai_default': 'Standard',
      'ai_api_key_desc':
          'Der Schlüssel wird nur an den ausdrücklich konfigurierten KI-Endpunkt gesendet. Der vollständige Schlüssel wird weder protokolliert noch angezeigt.',
      'ai_api_key_saved': 'Gespeichert (verschlüsselt)',
      'ai_api_key_not_set': 'Nicht festgelegt',
      'ai_api_key_endpoint_required':
          'Richten Sie zuerst einen eigenen KI-Endpunkt ein und speichern Sie dann den API Key',
      'ai_api_key_invalid':
          'Geben Sie einen gültigen API Key ohne Leer- oder Zeilenumbrüche ein',
      'ai_api_key_clear': 'API Key löschen',
      'ai_api_key_show': 'API Key anzeigen',
      'ai_api_key_hide': 'API Key ausblenden',
      'ai_model': 'Modell',
      'ai_model_not_set': 'Nicht festgelegt',
      'ai_model_desc':
          'Wählen Sie eine unterstützte Modell-ID oder geben Sie sie ein.',
      'ai_model_loading': 'Modelle werden geladen...',
      'ai_models_refresh': 'Modelle vom Endpunkt abrufen',
      'ai_models_load_failed':
          'Modelle konnten nicht abgerufen werden. Prüfen Sie Endpunkt und API Key. Eine Modell-ID kann manuell eingegeben werden.',
      'ai_model_invalid': 'Geben Sie eine gültige Modell-ID ein',
      'ai_model_select': 'Verfügbare Modelle',
      'ai_api_key_required_for_models':
          'Zum Abrufen der Modelle ist ein API Key erforderlich.',
    },
    'es' => const {
      'ai_api_key': 'API Key',
      'ai_default': 'Predeterminado',
      'ai_api_key_desc':
          'La clave solo se envía al punto de conexión de IA configurado explícitamente. La clave completa no se registra ni se muestra.',
      'ai_api_key_saved': 'Guardada (cifrada)',
      'ai_api_key_not_set': 'No configurada',
      'ai_api_key_endpoint_required':
          'Primero configura un punto de conexión de IA personalizado y después guarda la API Key',
      'ai_api_key_invalid':
          'Introduce una API Key válida sin espacios ni saltos de línea',
      'ai_api_key_clear': 'Borrar API Key',
      'ai_api_key_show': 'Mostrar API Key',
      'ai_api_key_hide': 'Ocultar API Key',
      'ai_model': 'Modelo',
      'ai_model_not_set': 'No establecido',
      'ai_model_desc':
          'Elige o introduce el ID de un modelo compatible con el servicio.',
      'ai_model_loading': 'Cargando modelos...',
      'ai_models_refresh': 'Obtener modelos del servicio',
      'ai_models_load_failed':
          'No se pudo obtener la lista de modelos. Comprueba el punto de conexión y la API Key. También puedes introducir el ID manualmente.',
      'ai_model_invalid': 'Introduce un ID de modelo válido',
      'ai_model_select': 'Modelos disponibles',
      'ai_api_key_required_for_models':
          'Se necesita una API Key para obtener los modelos.',
    },
    'pt' => const {
      'ai_api_key': 'API Key',
      'ai_default': 'Predefinido',
      'ai_api_key_desc':
          'A chave só é enviada para o endpoint de IA configurado explicitamente. A chave completa não é registada nem apresentada.',
      'ai_api_key_saved': 'Guardada (encriptada)',
      'ai_api_key_not_set': 'Não definida',
      'ai_api_key_endpoint_required':
          'Configure primeiro um endpoint de IA personalizado e depois guarde a API Key',
      'ai_api_key_invalid':
          'Introduza uma API Key válida sem espaços nem quebras de linha',
      'ai_api_key_clear': 'Limpar API Key',
      'ai_api_key_show': 'Mostrar API Key',
      'ai_api_key_hide': 'Ocultar API Key',
      'ai_model': 'Modelo',
      'ai_model_not_set': 'Não definido',
      'ai_model_desc':
          'Escolha ou introduza o ID de um modelo suportado pelo endpoint.',
      'ai_model_loading': 'A carregar modelos...',
      'ai_models_refresh': 'Obter modelos do serviço',
      'ai_models_load_failed':
          'Não foi possível obter os modelos. Verifique o endpoint e a API Key. Pode introduzir o ID manualmente.',
      'ai_model_invalid': 'Introduza um ID de modelo válido',
      'ai_model_select': 'Modelos disponíveis',
      'ai_api_key_required_for_models':
          'É necessária uma API Key para obter os modelos.',
    },
    'ar' => const {
      'ai_api_key': 'مفتاح API',
      'ai_default': 'افتراضي',
      'ai_api_key_desc':
          'يُرسل المفتاح فقط إلى نقطة خدمة الذكاء الاصطناعي التي ضبطتها صراحةً. لا يتم تسجيل المفتاح الكامل أو عرضه.',
      'ai_api_key_saved': 'محفوظ (مشفّر)',
      'ai_api_key_not_set': 'غير مضبوط',
      'ai_api_key_endpoint_required':
          'اضبط أولاً نقطة خدمة ذكاء اصطناعي مخصصة ثم احفظ مفتاح API',
      'ai_api_key_invalid': 'أدخل مفتاح API صالحاً بلا مسافات أو أسطر جديدة',
      'ai_api_key_clear': 'مسح مفتاح API',
      'ai_api_key_show': 'إظهار مفتاح API',
      'ai_api_key_hide': 'إخفاء مفتاح API',
      'ai_model': 'النموذج',
      'ai_model_not_set': 'غير مضبوط',
      'ai_model_desc': 'اختر أو أدخل معرّف نموذج يدعمه الطرف المقصود.',
      'ai_model_loading': 'جارٍ تحميل النماذج...',
      'ai_models_refresh': 'جلب النماذج من الخدمة',
      'ai_models_load_failed':
          'تعذر جلب قائمة النماذج. تحقق من الطرف المقصود ومفتاح API، أو أدخل المعرّف يدوياً.',
      'ai_model_invalid': 'أدخل معرّف نموذج صالحاً',
      'ai_model_select': 'النماذج المتاحة',
      'ai_api_key_required_for_models': 'يلزم مفتاح API لجلب قائمة النماذج.',
    },
    'ko' => const {
      'ai_api_key': 'API 키',
      'ai_default': '기본값',
      'ai_api_key_desc':
          '키는 명시적으로 설정한 AI 서비스 엔드포인트로만 전송됩니다. 전체 키는 기록하거나 표시하지 않습니다.',
      'ai_api_key_saved': '저장됨(암호화됨)',
      'ai_api_key_not_set': '설정되지 않음',
      'ai_api_key_endpoint_required':
          '먼저 사용자 지정 AI 서비스 엔드포인트를 설정한 뒤 API 키를 저장하세요',
      'ai_api_key_invalid': '공백이나 줄바꿈이 없는 유효한 API 키를 입력하세요',
      'ai_api_key_clear': 'API 키 지우기',
      'ai_api_key_show': 'API 키 표시',
      'ai_api_key_hide': 'API 키 숨기기',
      'ai_model': '모델',
      'ai_model_not_set': '설정되지 않음',
      'ai_model_desc': '서비스 엔드포인트가 지원하는 모델 ID를 선택하거나 입력하세요.',
      'ai_model_loading': '모델 로드 중...',
      'ai_models_refresh': '서비스에서 모델 가져오기',
      'ai_models_load_failed':
          '모델 목록을 가져오지 못했습니다. 엔드포인트와 API 키를 확인하거나 모델 ID를 직접 입력하세요.',
      'ai_model_invalid': '유효한 모델 ID를 입력하세요',
      'ai_model_select': '사용 가능한 모델',
      'ai_api_key_required_for_models': '모델 목록을 가져오려면 API 키가 필요합니다.',
    },
    'ja' => const {
      'ai_api_key': 'API キー',
      'ai_default': 'デフォルト',
      'ai_api_key_desc':
          'キーは明示的に設定した AI サービスエンドポイントにのみ送信されます。完全なキーを記録・表示することはありません。',
      'ai_api_key_saved': '保存済み（暗号化）',
      'ai_api_key_not_set': '未設定',
      'ai_api_key_endpoint_required':
          '先にカスタム AI サービスエンドポイントを設定してから API キーを保存してください',
      'ai_api_key_invalid': '空白や改行を含まない有効な API キーを入力してください',
      'ai_api_key_clear': 'API キーを消去',
      'ai_api_key_show': 'API キーを表示',
      'ai_api_key_hide': 'API キーを非表示',
      'ai_model': 'モデル',
      'ai_model_not_set': '未設定',
      'ai_model_desc': 'エンドポイントが対応するモデル ID を選択または入力します。',
      'ai_model_loading': 'モデルを読み込み中...',
      'ai_models_refresh': 'サービスからモデルを取得',
      'ai_models_load_failed':
          'モデル一覧を取得できません。エンドポイントと API キーを確認するか、モデル ID を手動で入力してください。',
      'ai_model_invalid': '有効なモデル ID を入力してください',
      'ai_model_select': '利用可能なモデル',
      'ai_api_key_required_for_models': 'モデル一覧の取得には API キーが必要です。',
    },
    _ => const {
      'ai_api_key': 'API Key',
      'ai_default': 'Default',
      'ai_api_key_desc':
          'The key is sent only to the explicitly configured AI service endpoint. The full key is never logged or displayed.',
      'ai_api_key_saved': 'Saved (encrypted)',
      'ai_api_key_not_set': 'Not set',
      'ai_api_key_endpoint_required':
          'Set a custom AI service endpoint before saving an API Key',
      'ai_api_key_invalid':
          'Enter a valid API Key without spaces or line breaks',
      'ai_api_key_clear': 'Clear API Key',
      'ai_api_key_show': 'Show API Key',
      'ai_api_key_hide': 'Hide API Key',
      'ai_model': 'Model',
      'ai_model_not_set': 'Not set',
      'ai_model_desc':
          'Choose or enter a model ID supported by the service endpoint.',
      'ai_model_loading': 'Loading models...',
      'ai_models_refresh': 'Get models from endpoint',
      'ai_models_load_failed':
          'Could not load models. Check the endpoint and API Key, or enter a model ID manually.',
      'ai_model_invalid': 'Enter a valid model ID',
      'ai_model_select': 'Available models',
      'ai_api_key_required_for_models':
          'An API Key is required to load models.',
    },
  };
}
