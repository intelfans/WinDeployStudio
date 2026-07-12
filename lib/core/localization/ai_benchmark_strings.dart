abstract final class AiBenchmarkKeys {
  static const recordsTitle = 'ai_benchmark_records_title';
  static const recordsIntro = 'ai_benchmark_records_intro';
  static const recordsSelected = 'ai_benchmark_records_selected';
  static const recordsSend = 'ai_benchmark_records_send';
  static const recordsWithout = 'ai_benchmark_records_without';
  static const recordsNoneTitle = 'ai_benchmark_records_none_title';
  static const recordsNoneBody = 'ai_benchmark_records_none_body';
  static const recordsRunStandard = 'ai_benchmark_records_run_standard';
  static const recordsLoadFailed = 'ai_benchmark_records_load_failed';
  static const recordsPlainTextNotice =
      'ai_benchmark_records_plain_text_notice';
}

const _aiBenchmarkLocaleCodes = <String>[
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

typedef _AiBenchmarkTranslations = List<String>;

final Map<String, Map<String, String>> _aiBenchmarkStrings =
    _buildAiBenchmarkStrings();

Map<String, String> aiBenchmarkStringsForCode(String code) =>
    _aiBenchmarkStrings[code] ?? _aiBenchmarkStrings['en']!;

Map<String, Map<String, String>> _buildAiBenchmarkStrings() {
  final result = <String, Map<String, String>>{
    for (final code in _aiBenchmarkLocaleCodes) code: <String, String>{},
  };
  for (final entry in _aiBenchmarkRows.entries) {
    assert(
      entry.value.length == _aiBenchmarkLocaleCodes.length,
      '${entry.key} must define all AI benchmark locales',
    );
    for (var index = 0; index < _aiBenchmarkLocaleCodes.length; index++) {
      result[_aiBenchmarkLocaleCodes[index]]![entry.key] = entry.value[index];
    }
  }
  return Map<String, Map<String, String>>.unmodifiable({
    for (final entry in result.entries)
      entry.key: Map<String, String>.unmodifiable(entry.value),
  });
}

// Value order: zh, zh_TW, en, fr, de, es, pt, ru, ar, ko, ja.
const Map<String, _AiBenchmarkTranslations> _aiBenchmarkRows = {
  AiBenchmarkKeys.recordsTitle: [
    '选择磁盘测试记录',
    '選擇磁碟測試記錄',
    'Select disk test records',
    'Sélectionner les résultats des tests de disque',
    'Datenträgertestergebnisse auswählen',
    'Seleccionar resultados de pruebas de disco',
    'Selecionar resultados de testes de disco',
    'Выберите результаты тестов диска',
    'اختيار سجلات اختبار القرص',
    '디스크 테스트 기록 선택',
    'ディスクテスト記録を選択',
  ],
  AiBenchmarkKeys.recordsIntro: [
    '选择一条或多条已保存的磁盘测试记录，随 USB 分析一起发送。设备标识、原始测量值和指标说明将以纯文本发送。',
    '選擇一筆或多筆已儲存的磁碟測試記錄，隨 USB 分析一起傳送。裝置識別、原始測量值和指標說明將以純文字傳送。',
    'Choose one or more saved disk test records to send with the USB analysis. Device identifiers, raw measurements, and metric explanations are sent as plain text.',
    'Choisissez un ou plusieurs résultats de tests de disque enregistrés à envoyer avec l’analyse USB. Les identifiants de l’appareil, les mesures brutes et les explications des indicateurs seront envoyés en texte brut.',
    'Wählen Sie einen oder mehrere gespeicherte Datenträgertestergebnisse für die USB-Analyse aus. Gerätekennungen, Rohmesswerte und Erklärungen der Messgrößen werden als Klartext gesendet.',
    'Elija uno o más resultados guardados de pruebas de disco para enviarlos con el análisis USB. Los identificadores del dispositivo, las mediciones sin procesar y las explicaciones de las métricas se enviarán como texto sin formato.',
    'Escolha um ou mais resultados salvos de testes de disco para enviar com a análise USB. Identificadores do dispositivo, medições brutas e explicações das métricas serão enviados como texto simples.',
    'Выберите один или несколько сохранённых результатов тестов диска для отправки вместе с анализом USB. Идентификаторы устройства, исходные измерения и пояснения метрик будут отправлены обычным текстом.',
    'اختر سجلاً واحداً أو أكثر من سجلات اختبار القرص المحفوظة لإرسالها مع تحليل USB. ستُرسل معرّفات الجهاز والقياسات الخام وشروحات المقاييس كنص عادي.',
    'USB 분석과 함께 보낼 저장된 디스크 테스트 기록을 하나 이상 선택하세요. 장치 식별자, 원시 측정값 및 지표 설명이 일반 텍스트로 전송됩니다.',
    'USB 分析とともに送信する保存済みディスクテスト記録を一つ以上選択します。デバイス識別子、生の測定値、指標の説明はプレーンテキストで送信されます。',
  ],
  AiBenchmarkKeys.recordsSelected: [
    '已选择 {count} 条',
    '已選擇 {count} 筆',
    '{count} selected',
    '{count} sélectionné(s)',
    '{count} ausgewählt',
    '{count} seleccionado(s)',
    '{count} selecionado(s)',
    'Выбрано: {count}',
    'تم تحديد {count}',
    '{count}개 선택됨',
    '{count} 件を選択',
  ],
  AiBenchmarkKeys.recordsSend: [
    '发送所选数据',
    '傳送所選資料',
    'Send selected data',
    'Envoyer les données sélectionnées',
    'Ausgewählte Daten senden',
    'Enviar datos seleccionados',
    'Enviar dados selecionados',
    'Отправить выбранные данные',
    'إرسال البيانات المحددة',
    '선택한 데이터 전송',
    '選択したデータを送信',
  ],
  AiBenchmarkKeys.recordsWithout: [
    '不附带测试数据分析',
    '不附帶測試資料分析',
    'Analyze without test data',
    'Analyser sans données de test',
    'Ohne Testdaten analysieren',
    'Analizar sin datos de prueba',
    'Analisar sem dados de teste',
    'Анализировать без данных теста',
    'تحليل بدون بيانات اختبار',
    '테스트 데이터 없이 분석',
    'テストデータなしで分析',
  ],
  AiBenchmarkKeys.recordsNoneTitle: [
    '没有已保存的磁盘测试记录',
    '沒有已儲存的磁碟測試記錄',
    'No saved disk test records',
    'Aucun résultat de test de disque enregistré',
    'Keine gespeicherten Datenträgertestergebnisse',
    'No hay resultados guardados de pruebas de disco',
    'Não há resultados salvos de testes de disco',
    'Нет сохранённых результатов тестов диска',
    'لا توجد سجلات اختبار قرص محفوظة',
    '저장된 디스크 테스트 기록 없음',
    '保存済みのディスクテスト記録がありません',
  ],
  AiBenchmarkKeys.recordsNoneBody: [
    '建议先运行一次标准磁盘测试，再判断 USB 是否适合制作随身系统。标准测试会测量顺序速度、4K 随机性能、延迟、并发能力和稳定性。',
    '建議先執行一次標準磁碟測試，再判斷 USB 是否適合製作隨身系統。標準測試會測量循序速度、4K 隨機效能、延遲、並發能力和穩定性。',
    'Run a Standard disk test before assessing a USB for a To Go workspace. It measures sequential speed, 4K random performance, latency, concurrency, and stability.',
    'Exécutez un test de disque standard avant d’évaluer une clé USB pour un espace de travail To Go. Il mesure la vitesse séquentielle, les performances aléatoires 4K, la latence, la concurrence et la stabilité.',
    'Führen Sie vor der Bewertung eines USB-Laufwerks für einen To-Go-Arbeitsbereich einen Standard-Datenträgertest aus. Er misst sequenzielle Geschwindigkeit, zufällige 4K-Leistung, Latenz, Parallelität und Stabilität.',
    'Ejecute una prueba de disco estándar antes de evaluar una unidad USB para un espacio de trabajo To Go. Mide la velocidad secuencial, el rendimiento aleatorio 4K, la latencia, la simultaneidad y la estabilidad.',
    'Execute um teste de disco padrão antes de avaliar uma unidade USB para um espaço de trabalho To Go. Ele mede velocidade sequencial, desempenho aleatório 4K, latência, concorrência e estabilidade.',
    'Перед оценкой USB-накопителя для рабочего пространства To Go запустите стандартный тест диска. Он измеряет последовательную скорость, случайную производительность 4K, задержку, параллельность и стабильность.',
    'شغّل اختبار القرص القياسي قبل تقييم وحدة USB لمساحة عمل To Go. يقيس السرعة التسلسلية وأداء 4K العشوائي والكمون والتزامن والاستقرار.',
    'To Go 작업 환경에 맞는 USB인지 평가하기 전에 표준 디스크 테스트를 실행하세요. 이 테스트는 순차 속도, 4K 무작위 성능, 지연 시간, 동시성 및 안정성을 측정합니다.',
    'To Go ワークスペースに適した USB か評価する前に、標準ディスクテストを実行してください。順次速度、4K ランダム性能、遅延、並行性、安定性を測定します。',
  ],
  AiBenchmarkKeys.recordsRunStandard: [
    '打开标准磁盘测试',
    '開啟標準磁碟測試',
    'Open Standard disk test',
    'Ouvrir le test de disque standard',
    'Standard-Datenträgertest öffnen',
    'Abrir prueba de disco estándar',
    'Abrir teste de disco padrão',
    'Открыть стандартный тест диска',
    'فتح اختبار القرص القياسي',
    '표준 디스크 테스트 열기',
    '標準ディスクテストを開く',
  ],
  AiBenchmarkKeys.recordsLoadFailed: [
    '无法加载磁盘测试记录。',
    '無法載入磁碟測試記錄。',
    'Could not load disk test records.',
    'Impossible de charger les résultats des tests de disque.',
    'Datenträgertestergebnisse konnten nicht geladen werden.',
    'No se pudieron cargar los resultados de las pruebas de disco.',
    'Não foi possível carregar os resultados dos testes de disco.',
    'Не удалось загрузить результаты тестов диска.',
    'تعذر تحميل سجلات اختبار القرص.',
    '디스크 테스트 기록을 불러올 수 없습니다.',
    'ディスクテスト記録を読み込めませんでした。',
  ],
  AiBenchmarkKeys.recordsPlainTextNotice: [
    '所选记录将以纯文本发送。',
    '所選記錄將以純文字傳送。',
    'Selected records will be sent as plain text.',
    'Les résultats sélectionnés seront envoyés en texte brut.',
    'Ausgewählte Ergebnisse werden als Klartext gesendet.',
    'Los resultados seleccionados se enviarán como texto sin formato.',
    'Os resultados selecionados serão enviados como texto simples.',
    'Выбранные результаты будут отправлены обычным текстом.',
    'سيتم إرسال السجلات المحددة كنص عادي.',
    '선택한 기록이 일반 텍스트로 전송됩니다.',
    '選択した記録はプレーンテキストで送信されます。',
  ],
};
