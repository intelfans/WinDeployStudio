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

Map<String, String> aiBenchmarkStringsForCode(String code) {
  const english = <String, String>{
    AiBenchmarkKeys.recordsTitle: 'Select disk test records',
    AiBenchmarkKeys.recordsIntro:
        'Choose one or more saved disk test records to send with the USB analysis. Device identifiers, raw measurements, and metric explanations are sent as plain text.',
    AiBenchmarkKeys.recordsSelected: '{count} selected',
    AiBenchmarkKeys.recordsSend: 'Send selected data',
    AiBenchmarkKeys.recordsWithout: 'Analyze without test data',
    AiBenchmarkKeys.recordsNoneTitle: 'No saved disk test records',
    AiBenchmarkKeys.recordsNoneBody:
        'Run a Standard disk test before assessing a USB for a To Go workspace. It measures sequential speed, 4K random performance, latency, concurrency, and stability.',
    AiBenchmarkKeys.recordsRunStandard: 'Open Standard disk test',
    AiBenchmarkKeys.recordsLoadFailed: 'Could not load disk test records.',
    AiBenchmarkKeys.recordsPlainTextNotice:
        'Selected records will be sent as plain text.',
  };

  return switch (code) {
    'zh' => {
      ...english,
      AiBenchmarkKeys.recordsTitle: '选择磁盘测试记录',
      AiBenchmarkKeys.recordsIntro:
          '选择一条或多条已保存的磁盘测试记录，随 USB 分析一起发送。设备标识、原始测量值和指标说明将以纯文本发送。',
      AiBenchmarkKeys.recordsSelected: '已选择 {count} 条',
      AiBenchmarkKeys.recordsSend: '发送所选数据',
      AiBenchmarkKeys.recordsWithout: '不附带测试数据分析',
      AiBenchmarkKeys.recordsNoneTitle: '没有已保存的磁盘测试记录',
      AiBenchmarkKeys.recordsNoneBody:
          '建议先运行一次标准磁盘测试，再判断 USB 是否适合制作随身系统。标准测试会测量顺序速度、4K 随机性能、延迟、并发能力和稳定性。',
      AiBenchmarkKeys.recordsRunStandard: '打开标准磁盘测试',
      AiBenchmarkKeys.recordsLoadFailed: '无法加载磁盘测试记录。',
      AiBenchmarkKeys.recordsPlainTextNotice: '所选记录将以纯文本发送。',
    },
    'zh_TW' => {
      ...english,
      AiBenchmarkKeys.recordsTitle: '選擇磁碟測試記錄',
      AiBenchmarkKeys.recordsIntro:
          '選擇一筆或多筆已儲存的磁碟測試記錄，隨 USB 分析一起傳送。裝置識別、原始測量值和指標說明將以純文字傳送。',
      AiBenchmarkKeys.recordsSelected: '已選擇 {count} 筆',
      AiBenchmarkKeys.recordsSend: '傳送所選資料',
      AiBenchmarkKeys.recordsWithout: '不附帶測試資料分析',
      AiBenchmarkKeys.recordsNoneTitle: '沒有已儲存的磁碟測試記錄',
      AiBenchmarkKeys.recordsNoneBody:
          '建議先執行一次標準磁碟測試，再判斷 USB 是否適合製作隨身系統。標準測試會測量循序速度、4K 隨機效能、延遲、並發能力和穩定性。',
      AiBenchmarkKeys.recordsRunStandard: '開啟標準磁碟測試',
      AiBenchmarkKeys.recordsLoadFailed: '無法載入磁碟測試記錄。',
      AiBenchmarkKeys.recordsPlainTextNotice: '所選記錄將以純文字傳送。',
    },
    'fr' => {
      ...english,
      AiBenchmarkKeys.recordsTitle: 'Selectionner les tests de disque',
      AiBenchmarkKeys.recordsIntro:
          'Choisissez un ou plusieurs tests de disque enregistres a envoyer avec l analyse USB. Les identifiants, mesures brutes et explications seront envoyes en texte brut.',
      AiBenchmarkKeys.recordsSelected: '{count} selectionne(s)',
      AiBenchmarkKeys.recordsSend: 'Envoyer les donnees selectionnees',
      AiBenchmarkKeys.recordsWithout: 'Analyser sans donnees de test',
      AiBenchmarkKeys.recordsNoneTitle: 'Aucun test de disque enregistre',
      AiBenchmarkKeys.recordsNoneBody:
          'Executez un test de disque Standard avant d evaluer une cle USB pour un espace To Go.',
      AiBenchmarkKeys.recordsRunStandard: 'Ouvrir le test Standard',
      AiBenchmarkKeys.recordsLoadFailed:
          'Impossible de charger les tests de disque.',
      AiBenchmarkKeys.recordsPlainTextNotice:
          'Les tests selectionnes seront envoyes en texte brut.',
    },
    'de' => {
      ...english,
      AiBenchmarkKeys.recordsTitle: 'Datentraegertests auswaehlen',
      AiBenchmarkKeys.recordsIntro:
          'Waehlen Sie einen oder mehrere gespeicherte Datentraegertests fuer die USB-Analyse. Geraete-IDs, Rohmesswerte und Erklaerungen werden als Klartext gesendet.',
      AiBenchmarkKeys.recordsSelected: '{count} ausgewaehlt',
      AiBenchmarkKeys.recordsSend: 'Ausgewaehlte Daten senden',
      AiBenchmarkKeys.recordsWithout: 'Ohne Testdaten analysieren',
      AiBenchmarkKeys.recordsNoneTitle: 'Keine gespeicherten Datentraegertests',
      AiBenchmarkKeys.recordsNoneBody:
          'Fuehren Sie vor der Bewertung eines USB-Laufwerks fuer To Go einen Standard-Datentraegertest aus.',
      AiBenchmarkKeys.recordsRunStandard: 'Standardtest oeffnen',
      AiBenchmarkKeys.recordsLoadFailed:
          'Datentraegertests konnten nicht geladen werden.',
      AiBenchmarkKeys.recordsPlainTextNotice:
          'Ausgewaehlte Tests werden als Klartext gesendet.',
    },
    'es' => {
      ...english,
      AiBenchmarkKeys.recordsTitle: 'Seleccionar pruebas de disco',
      AiBenchmarkKeys.recordsIntro:
          'Elija una o mas pruebas guardadas para enviar con el analisis USB. Los identificadores, mediciones y explicaciones se enviaran como texto sin formato.',
      AiBenchmarkKeys.recordsSelected: '{count} seleccionada(s)',
      AiBenchmarkKeys.recordsSend: 'Enviar datos seleccionados',
      AiBenchmarkKeys.recordsWithout: 'Analizar sin datos de prueba',
      AiBenchmarkKeys.recordsNoneTitle: 'No hay pruebas de disco guardadas',
      AiBenchmarkKeys.recordsNoneBody:
          'Ejecute una prueba de disco estandar antes de evaluar una unidad USB para To Go.',
      AiBenchmarkKeys.recordsRunStandard: 'Abrir prueba estandar',
      AiBenchmarkKeys.recordsLoadFailed:
          'No se pudieron cargar las pruebas de disco.',
      AiBenchmarkKeys.recordsPlainTextNotice:
          'Las pruebas seleccionadas se enviaran como texto sin formato.',
    },
    'pt' => {
      ...english,
      AiBenchmarkKeys.recordsTitle: 'Selecionar testes de disco',
      AiBenchmarkKeys.recordsIntro:
          'Escolha um ou mais testes salvos para enviar com a analise USB. Identificadores, medicoes e explicacoes serao enviados como texto simples.',
      AiBenchmarkKeys.recordsSelected: '{count} selecionado(s)',
      AiBenchmarkKeys.recordsSend: 'Enviar dados selecionados',
      AiBenchmarkKeys.recordsWithout: 'Analisar sem dados de teste',
      AiBenchmarkKeys.recordsNoneTitle: 'Nenhum teste de disco salvo',
      AiBenchmarkKeys.recordsNoneBody:
          'Execute um teste de disco Padrao antes de avaliar uma unidade USB para To Go.',
      AiBenchmarkKeys.recordsRunStandard: 'Abrir teste Padrao',
      AiBenchmarkKeys.recordsLoadFailed:
          'Nao foi possivel carregar os testes de disco.',
      AiBenchmarkKeys.recordsPlainTextNotice:
          'Os testes selecionados serao enviados como texto simples.',
    },
    'ru' => {
      ...english,
      AiBenchmarkKeys.recordsTitle: 'Vyberite testy diska',
      AiBenchmarkKeys.recordsIntro:
          'Vyberite odin ili neskolko sokhranennykh testov dlya otpravki s analizom USB. Identifikatory, izmereniya i obyasneniya budut otpravleny prostym tekstom.',
      AiBenchmarkKeys.recordsSelected: 'Vybrano: {count}',
      AiBenchmarkKeys.recordsSend: 'Otpravit vybrannye dannye',
      AiBenchmarkKeys.recordsWithout: 'Analiz bez dannykh testa',
      AiBenchmarkKeys.recordsNoneTitle: 'Net sokhranennykh testov diska',
      AiBenchmarkKeys.recordsNoneBody:
          'Zapustite standartnyy test diska pered otsenkoy USB dlya To Go.',
      AiBenchmarkKeys.recordsRunStandard: 'Otkryt standartnyy test',
      AiBenchmarkKeys.recordsLoadFailed: 'Ne udalos zagruzit testy diska.',
      AiBenchmarkKeys.recordsPlainTextNotice:
          'Vybrannye testy budut otpravleny prostym tekstom.',
    },
    'ar' => {
      ...english,
      AiBenchmarkKeys.recordsTitle: 'Select disk test records',
      AiBenchmarkKeys.recordsIntro:
          'Choose saved disk tests to send with USB analysis as plain text.',
      AiBenchmarkKeys.recordsSelected: '{count} selected',
      AiBenchmarkKeys.recordsSend: 'Send selected data',
      AiBenchmarkKeys.recordsWithout: 'Analyze without test data',
      AiBenchmarkKeys.recordsNoneTitle: 'No saved disk test records',
      AiBenchmarkKeys.recordsNoneBody:
          'Run a Standard disk test before evaluating a USB drive for To Go.',
      AiBenchmarkKeys.recordsRunStandard: 'Open Standard disk test',
      AiBenchmarkKeys.recordsLoadFailed: 'Could not load disk test records.',
      AiBenchmarkKeys.recordsPlainTextNotice:
          'Selected records will be sent as plain text.',
    },
    'ko' => {
      ...english,
      AiBenchmarkKeys.recordsTitle: '디스크 테스트 기록 선택',
      AiBenchmarkKeys.recordsIntro:
          'USB 분석과 함께 보낼 저장된 디스크 테스트 기록을 하나 이상 선택하세요. 장치 식별자, 원시 측정값 및 설명이 일반 텍스트로 전송됩니다.',
      AiBenchmarkKeys.recordsSelected: '{count}개 선택됨',
      AiBenchmarkKeys.recordsSend: '선택한 데이터 전송',
      AiBenchmarkKeys.recordsWithout: '테스트 데이터 없이 분석',
      AiBenchmarkKeys.recordsNoneTitle: '저장된 디스크 테스트 기록 없음',
      AiBenchmarkKeys.recordsNoneBody: 'To Go용 USB를 평가하기 전에 표준 디스크 테스트를 실행하세요.',
      AiBenchmarkKeys.recordsRunStandard: '표준 디스크 테스트 열기',
      AiBenchmarkKeys.recordsLoadFailed: '디스크 테스트 기록을 불러올 수 없습니다.',
      AiBenchmarkKeys.recordsPlainTextNotice: '선택한 기록이 일반 텍스트로 전송됩니다.',
    },
    'ja' => {
      ...english,
      AiBenchmarkKeys.recordsTitle: 'ディスクテスト記録を選択',
      AiBenchmarkKeys.recordsIntro:
          'USB 分析とともに送信する保存済みディスクテスト記録を一つ以上選択します。デバイス識別子、生の測定値、指標の説明はプレーンテキストで送信されます。',
      AiBenchmarkKeys.recordsSelected: '{count} 件を選択',
      AiBenchmarkKeys.recordsSend: '選択したデータを送信',
      AiBenchmarkKeys.recordsWithout: 'テストデータなしで分析',
      AiBenchmarkKeys.recordsNoneTitle: '保存済みディスクテスト記録がありません',
      AiBenchmarkKeys.recordsNoneBody: 'To Go 用 USB を評価する前に標準ディスクテストを実行してください。',
      AiBenchmarkKeys.recordsRunStandard: '標準ディスクテストを開く',
      AiBenchmarkKeys.recordsLoadFailed: 'ディスクテスト記録を読み込めませんでした。',
      AiBenchmarkKeys.recordsPlainTextNotice: '選択した記録はプレーンテキストで送信されます。',
    },
    _ => english,
  };
}
