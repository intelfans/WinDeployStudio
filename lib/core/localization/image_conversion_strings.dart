Map<String, String> imageConversionStringsForCode(String code) {
  return switch (code) {
    'zh' => _imageConversionZh,
    'zh_TW' => _imageConversionZhTw,
    'fr' => _imageConversionFr,
    'de' => _imageConversionDe,
    'es' => _imageConversionEs,
    'pt' => _imageConversionPt,
    'ru' => _imageConversionRu,
    'ar' => _imageConversionAr,
    'ko' => _imageConversionKo,
    'ja' => _imageConversionJa,
    _ => _imageConversionEn,
  };
}

final _imageConversionEn = <String, String>{
  'disk_tools_title': 'Storage & image tools',
  'disk_tools_subtitle':
      'Read-only storage diagnostics, guarded boot repair, and verified image preparation.',
  'disk_tools_converter_title': 'Image format conversion',
  'disk_tools_converter_desc':
      'Prepare supported Windows sources as a bootable ISO without changing the original source.',
  'image_converter_title': 'Image format conversion',
  'image_converter_subtitle':
      'Turn a complete Windows Setup source, or a supported WIM/ESD/SWM image with matching base media, into a verified bootable ISO.',
  'image_converter_source': 'Source image or Setup folder',
  'image_converter_select_file': 'Choose image',
  'image_converter_select_folder': 'Choose Setup folder',
  'image_converter_base': 'Matching base Setup media',
  'image_converter_select_base': 'Choose base ISO / folder',
  'image_converter_output': 'Output ISO',
  'image_converter_select_output': 'Choose output',
  'image_converter_label': 'ISO volume label',
  'image_converter_label_hint':
      'Letters, numbers, spaces, hyphens, and underscores; up to 32 characters.',
  'image_converter_convert': 'Create verified ISO',
  'image_converter_cancel': 'Cancel conversion',
  'image_converter_use_creator': 'Use in installation media',
  'image_converter_use_wtg': 'Use in Windows To Go',
  'creator_convert_other_image': 'Other image format? Open the converter',
  'wtg_convert_other_image': 'Other image format? Open the converter',
  'image_converter_return_tools': 'Back to storage tools',
  'image_converter_notice':
      'The source is never overwritten. The result is rebuilt as a new ISO and mounted for a second validation before it is offered to another workflow.',
  'image_converter_linux_notice':
      'Linux Live USB and RAW/IMG images should be written directly. Converting them into ISO can remove their hybrid boot layout.',
  'image_converter_kind_setup_directory': 'Complete Windows Setup source',
  'image_converter_kind_wim': 'Windows WIM image',
  'image_converter_kind_esd': 'Windows ESD image',
  'image_converter_kind_swm': 'Split Windows SWM image',
  'image_converter_kind_vhd': 'Virtual hard disk (VHD)',
  'image_converter_kind_vhdx': 'Virtual hard disk (VHDX)',
  'image_converter_analysis_setup_directory':
      'The folder contains a valid Windows Setup layout.',
  'image_converter_analysis_invalid_setup_directory':
      'This folder does not contain a complete Windows Setup layout.',
  'image_converter_analysis_windows_image':
      'This image can replace install.wim/install.esd/install.swm in matching Setup media.',
  'image_converter_analysis_invalid_windows_image':
      'The selected file is not a valid WIM/ESD/SWM image.',
  'image_converter_analysis_already_iso':
      'This file is already an ISO. Use it directly in the installation workflow.',
  'image_converter_analysis_virtual_disk':
      'The virtual disk will be mounted read-only and converted only if it contains Windows Setup files.',
  'image_converter_analysis_raw_image':
      'RAW/IMG images are bootable disk images and should be written directly, not wrapped in ISO.',
  'image_converter_analysis_archive':
      'Archives must be extracted to a folder first so the Windows boot layout can be verified.',
  'image_converter_analysis_unsupported':
      'This format is not supported for verified ISO conversion.',
  'image_converter_source_missing': 'The selected source is unavailable.',
  'image_converter_windows_only':
      'Image conversion is available on Windows only.',
  'image_converter_step_preflight': 'Checking source and compatibility',
  'image_converter_step_preparing': 'Preparing image mastering',
  'image_converter_step_building': 'Building ISO file system',
  'image_converter_step_writing': 'Writing ISO output',
  'image_converter_step_verifying': 'Mounting and verifying output',
  'image_converter_step_hashing': 'Calculating SHA-256',
  'image_converter_step_complete': 'Conversion complete',
  'image_converter_label_required': 'Enter an ISO volume label.',
  'image_converter_label_too_long':
      'The ISO volume label must be 32 characters or fewer.',
  'image_converter_label_invalid':
      'The ISO volume label contains unsupported characters.',
  'image_converter_output_extension':
      'The output file must use the .iso extension.',
  'image_converter_output_directory_missing':
      'The output folder is unavailable.',
  'image_converter_output_matches_source':
      'The output ISO cannot overwrite the source.',
  'image_converter_helper_missing':
      'The built-in ISO conversion component is missing. Reinstall the application.',
  'image_converter_base_required':
      'Select matching Windows Setup media before continuing.',
  'image_converter_base_invalid':
      'The base media is not a valid Windows Setup source.',
  'image_converter_source_layout_invalid':
      'The source does not contain a valid Windows Setup layout.',
  'image_converter_virtual_disk_mount_failed':
      'The virtual disk could not be mounted read-only.',
  'image_converter_virtual_disk_no_setup':
      'The virtual disk contains no valid Windows Setup volume.',
  'image_converter_architecture_mismatch':
      'The image architecture does not match the Setup boot image.',
  'image_converter_generation_mismatch':
      'The Windows generation does not match the Setup boot image.',
  'image_converter_install_image_required':
      'Select an install image, not a Windows PE or Setup boot image.',
  'image_converter_metadata_failed':
      'The image metadata could not be read for a compatibility check.',
  'image_converter_builder_failed':
      'The ISO builder stopped before producing a verified result.',
  'image_converter_builder_invalid_result':
      'The ISO builder returned an incomplete result.',
  'image_converter_verification_failed':
      'The generated ISO did not pass Windows Setup validation.',
  'image_converter_timed_out':
      'The conversion exceeded the allowed time and was stopped.',
  'image_converter_failed': 'Image conversion failed.',
  'image_converter_virtual_disk_label': 'Read-only virtual disk source',
  'image_converter_output_placeholder': 'No output selected',
  'image_converter_source_placeholder': 'No source selected',
  'image_converter_base_placeholder':
      'Not required for a complete Setup folder',
  'image_converter_result_title': 'Verified ISO ready',
  'image_converter_result_size': 'Output size',
  'image_converter_result_sha256': 'SHA-256',
  'image_converter_result_bios': 'Legacy BIOS',
  'image_converter_result_uefi': 'UEFI',
  'image_converter_result_copy_hash': 'Copy SHA-256',
  'image_converter_hash_copied': 'SHA-256 copied.',
};

final _imageConversionZh = <String, String>{
  ..._imageConversionEn,
  'disk_tools_title': '磁盘与镜像工具',
  'disk_tools_subtitle': '只读存储诊断、受保护的启动修复和经过验证的镜像处理。',
  'disk_tools_converter_title': '镜像格式转换',
  'disk_tools_converter_desc': '将受支持的 Windows 安装源整理为可启动 ISO，不会修改原始文件。',
  'image_converter_title': '镜像格式转换',
  'image_converter_subtitle':
      '将完整 Windows 安装源，或配套基础介质的 WIM/ESD/SWM 镜像，转换为经过验证的可启动 ISO。',
  'image_converter_source': '源镜像或安装源文件夹',
  'image_converter_select_file': '选择镜像',
  'image_converter_select_folder': '选择安装源文件夹',
  'image_converter_base': '匹配的基础安装介质',
  'image_converter_select_base': '选择基础 ISO / 文件夹',
  'image_converter_output': '输出 ISO',
  'image_converter_select_output': '选择输出位置',
  'image_converter_label': 'ISO 卷标',
  'image_converter_label_hint': '仅支持字母、数字、空格、连字符和下划线，最多 32 个字符。',
  'image_converter_convert': '创建并验证 ISO',
  'image_converter_cancel': '取消转换',
  'image_converter_use_creator': '用于安装盘',
  'image_converter_use_wtg': '用于 Windows To Go',
  'creator_convert_other_image': '其他镜像格式？打开转换助手',
  'wtg_convert_other_image': '其他镜像格式？打开转换助手',
  'image_converter_return_tools': '返回磁盘与镜像工具',
  'image_converter_notice': '不会覆盖源文件。转换结果会写入新的 ISO，并在交给其他流程前重新挂载验证。',
  'image_converter_linux_notice':
      'Linux Live USB 和 RAW/IMG 镜像应直接写入。转换为 ISO 可能破坏其混合启动布局。',
  'image_converter_kind_setup_directory': '完整 Windows 安装源',
  'image_converter_kind_wim': 'Windows WIM 镜像',
  'image_converter_kind_esd': 'Windows ESD 镜像',
  'image_converter_kind_swm': '分卷 Windows SWM 镜像',
  'image_converter_kind_vhd': '虚拟硬盘（VHD）',
  'image_converter_kind_vhdx': '虚拟硬盘（VHDX）',
  'image_converter_analysis_setup_directory': '该文件夹包含有效的 Windows 安装布局。',
  'image_converter_analysis_invalid_setup_directory':
      '该文件夹不包含完整的 Windows 安装布局。',
  'image_converter_analysis_windows_image':
      '该镜像可以替换匹配安装介质中的 install.wim/install.esd/install.swm。',
  'image_converter_analysis_invalid_windows_image': '所选文件不是有效的 WIM/ESD/SWM 镜像。',
  'image_converter_analysis_already_iso': '该文件已经是 ISO，可直接在安装流程中使用。',
  'image_converter_analysis_virtual_disk':
      '将以只读方式挂载虚拟磁盘，仅在检测到 Windows 安装文件时转换。',
  'image_converter_analysis_raw_image': 'RAW/IMG 是可启动磁盘镜像，应直接写入，不应封装成 ISO。',
  'image_converter_analysis_archive': '请先将压缩包解压到文件夹，以便验证 Windows 启动布局。',
  'image_converter_analysis_unsupported': '不支持将此格式转换为经过验证的 ISO。',
  'image_converter_source_missing': '所选源不可用。',
  'image_converter_windows_only': '镜像转换仅支持 Windows。',
  'image_converter_step_preflight': '检查源文件和兼容性',
  'image_converter_step_preparing': '准备镜像制作',
  'image_converter_step_building': '构建 ISO 文件系统',
  'image_converter_step_writing': '写入 ISO 输出',
  'image_converter_step_verifying': '挂载并验证输出',
  'image_converter_step_hashing': '计算 SHA-256',
  'image_converter_step_complete': '转换完成',
  'image_converter_label_required': '请输入 ISO 卷标。',
  'image_converter_label_too_long': 'ISO 卷标不能超过 32 个字符。',
  'image_converter_label_invalid': 'ISO 卷标包含不支持的字符。',
  'image_converter_output_extension': '输出文件必须使用 .iso 扩展名。',
  'image_converter_output_directory_missing': '输出文件夹不可用。',
  'image_converter_output_matches_source': '输出 ISO 不能覆盖源文件。',
  'image_converter_helper_missing': '内置 ISO 转换组件缺失，请重新安装应用。',
  'image_converter_base_required': '请先选择匹配的 Windows 安装介质。',
  'image_converter_base_invalid': '基础介质不是有效的 Windows 安装源。',
  'image_converter_source_layout_invalid': '源文件不包含有效的 Windows 安装布局。',
  'image_converter_virtual_disk_mount_failed': '无法以只读方式挂载虚拟磁盘。',
  'image_converter_virtual_disk_no_setup': '虚拟磁盘中没有有效的 Windows 安装卷。',
  'image_converter_architecture_mismatch': '镜像架构与安装启动镜像不匹配。',
  'image_converter_generation_mismatch': 'Windows 版本代际与安装启动镜像不匹配。',
  'image_converter_install_image_required': '请选择安装镜像，不要选择 Windows PE 或启动镜像。',
  'image_converter_metadata_failed': '无法读取镜像元数据进行兼容性检查。',
  'image_converter_builder_failed': 'ISO 构建器在生成经过验证的结果前停止了。',
  'image_converter_builder_invalid_result': 'ISO 构建器返回了不完整的结果。',
  'image_converter_verification_failed': '生成的 ISO 未通过 Windows 安装布局验证。',
  'image_converter_timed_out': '转换超过允许时间，已停止。',
  'image_converter_failed': '镜像转换失败。',
  'image_converter_output_placeholder': '尚未选择输出位置',
  'image_converter_source_placeholder': '尚未选择源',
  'image_converter_base_placeholder': '完整安装源无需基础介质',
  'image_converter_result_title': '已准备好经过验证的 ISO',
  'image_converter_result_size': '输出大小',
  'image_converter_result_sha256': 'SHA-256',
  'image_converter_result_bios': 'Legacy BIOS',
  'image_converter_result_uefi': 'UEFI',
  'image_converter_result_copy_hash': '复制 SHA-256',
  'image_converter_hash_copied': 'SHA-256 已复制。',
};

final _imageConversionZhTw = <String, String>{
  ..._imageConversionZh,
  'disk_tools_title': '磁碟與映像工具',
  'disk_tools_subtitle': '唯讀儲存診斷、受保護的啟動修復與經驗證的映像處理。',
  'image_converter_title': '映像格式轉換',
  'image_converter_subtitle':
      '將完整 Windows 安裝來源，或搭配基礎媒體的 WIM/ESD/SWM 映像，轉換為經驗證的可啟動 ISO。',
  'image_converter_source': '來源映像或安裝來源資料夾',
  'image_converter_select_file': '選擇映像',
  'image_converter_select_folder': '選擇安裝來源資料夾',
  'image_converter_base': '相符的基礎安裝媒體',
  'image_converter_select_base': '選擇基礎 ISO / 資料夾',
  'image_converter_output': '輸出 ISO',
  'image_converter_select_output': '選擇輸出位置',
  'image_converter_convert': '建立並驗證 ISO',
  'image_converter_cancel': '取消轉換',
  'image_converter_use_creator': '用於安裝碟',
  'image_converter_use_wtg': '用於 Windows To Go',
  'creator_convert_other_image': '其他映像格式？開啟轉換助手',
  'wtg_convert_other_image': '其他映像格式？開啟轉換助手',
  'image_converter_return_tools': '返回磁碟與映像工具',
  'image_converter_notice': '不會覆寫來源檔案。轉換結果會寫入新的 ISO，並在交給其他流程前重新掛載驗證。',
  'image_converter_linux_notice':
      'Linux Live USB 與 RAW/IMG 映像應直接寫入。轉換為 ISO 可能破壞其混合啟動結構。',
  'image_converter_label': 'ISO 卷標',
  'image_converter_label_hint': '僅支援字母、數字、空格、連字號與底線，最多 32 個字元。',
  'image_converter_result_title': '已準備好經驗證的 ISO',
  'image_converter_result_copy_hash': '複製 SHA-256',
  'image_converter_hash_copied': 'SHA-256 已複製。',
};

final _imageConversionFr = <String, String>{
  ..._imageConversionEn,
  'disk_tools_title': 'Outils de stockage et d’images',
  'disk_tools_converter_title': 'Conversion de format d’image',
  'disk_tools_converter_desc':
      'Préparez une source Windows prise en charge en ISO amorçable sans modifier la source.',
  'image_converter_title': 'Conversion de format d’image',
  'image_converter_subtitle':
      'Transformez une source d’installation Windows complète, ou une image WIM/ESD/SWM avec un média de base compatible, en ISO amorçable vérifiée.',
  'image_converter_source': 'Image source ou dossier d’installation',
  'image_converter_select_file': 'Choisir une image',
  'image_converter_select_folder': 'Choisir le dossier d’installation',
  'image_converter_base': 'Média d’installation de base correspondant',
  'image_converter_select_base': 'Choisir l’ISO / le dossier de base',
  'image_converter_output': 'ISO de sortie',
  'image_converter_select_output': 'Choisir la sortie',
  'image_converter_convert': 'Créer une ISO vérifiée',
  'image_converter_cancel': 'Annuler la conversion',
  'image_converter_use_creator': 'Utiliser pour le support d’installation',
  'image_converter_use_wtg': 'Utiliser dans Windows To Go',
  'creator_convert_other_image':
      'Autre format d’image ? Ouvrir le convertisseur',
  'wtg_convert_other_image': 'Autre format d’image ? Ouvrir le convertisseur',
  'image_converter_result_title': 'ISO vérifiée prête',
  'image_converter_result_size': 'Taille de sortie',
  'image_converter_result_copy_hash': 'Copier le SHA-256',
  'image_converter_hash_copied': 'SHA-256 copié.',
};

final _imageConversionDe = <String, String>{
  ..._imageConversionEn,
  'disk_tools_title': 'Speicher- und Abbildwerkzeuge',
  'disk_tools_converter_title': 'Abbildformat konvertieren',
  'disk_tools_converter_desc':
      'Unterstützte Windows-Quellen als startfähige ISO vorbereiten, ohne die Quelle zu ändern.',
  'image_converter_title': 'Abbildformat konvertieren',
  'image_converter_subtitle':
      'Eine vollständige Windows-Setup-Quelle oder ein passendes WIM/ESD/SWM-Abbild in eine geprüfte startfähige ISO umwandeln.',
  'image_converter_source': 'Quellabbild oder Setup-Ordner',
  'image_converter_select_file': 'Abbild auswählen',
  'image_converter_select_folder': 'Setup-Ordner auswählen',
  'image_converter_base': 'Passendes Basis-Setup-Medium',
  'image_converter_select_base': 'Basis-ISO / Ordner auswählen',
  'image_converter_output': 'Ausgabe-ISO',
  'image_converter_select_output': 'Ausgabe auswählen',
  'image_converter_convert': 'Geprüfte ISO erstellen',
  'image_converter_cancel': 'Konvertierung abbrechen',
  'image_converter_use_creator': 'Für Installationsmedium verwenden',
  'image_converter_use_wtg': 'In Windows To Go verwenden',
  'creator_convert_other_image': 'Anderes Abbildformat? Konverter öffnen',
  'wtg_convert_other_image': 'Anderes Abbildformat? Konverter öffnen',
  'image_converter_result_title': 'Geprüfte ISO ist bereit',
  'image_converter_result_size': 'Ausgabegröße',
  'image_converter_result_copy_hash': 'SHA-256 kopieren',
  'image_converter_hash_copied': 'SHA-256 kopiert.',
};

final _imageConversionEs = <String, String>{
  ..._imageConversionEn,
  'disk_tools_title': 'Herramientas de almacenamiento e imágenes',
  'disk_tools_converter_title': 'Conversión de formato de imagen',
  'disk_tools_converter_desc':
      'Prepare fuentes de Windows compatibles como ISO arrancable sin modificar la fuente.',
  'image_converter_title': 'Conversión de formato de imagen',
  'image_converter_subtitle':
      'Convierta una fuente de instalación de Windows completa o una imagen WIM/ESD/SWM compatible en una ISO arrancable verificada.',
  'image_converter_source': 'Imagen de origen o carpeta de instalación',
  'image_converter_select_file': 'Elegir imagen',
  'image_converter_select_folder': 'Elegir carpeta de instalación',
  'image_converter_base': 'Medio de instalación base compatible',
  'image_converter_select_base': 'Elegir ISO / carpeta base',
  'image_converter_output': 'ISO de salida',
  'image_converter_select_output': 'Elegir salida',
  'image_converter_convert': 'Crear ISO verificada',
  'image_converter_cancel': 'Cancelar conversión',
  'image_converter_use_creator': 'Usar en medios de instalación',
  'image_converter_use_wtg': 'Usar en Windows To Go',
  'creator_convert_other_image': '¿Otro formato? Abrir convertidor',
  'wtg_convert_other_image': '¿Otro formato? Abrir convertidor',
  'image_converter_result_title': 'ISO verificada lista',
  'image_converter_result_size': 'Tamaño de salida',
  'image_converter_result_copy_hash': 'Copiar SHA-256',
  'image_converter_hash_copied': 'SHA-256 copiado.',
};

final _imageConversionPt = <String, String>{
  ..._imageConversionEn,
  'disk_tools_title': 'Ferramentas de armazenamento e imagens',
  'disk_tools_converter_title': 'Conversão de formato de imagem',
  'disk_tools_converter_desc':
      'Prepare fontes Windows compatíveis como ISO inicializável sem alterar a fonte.',
  'image_converter_title': 'Conversão de formato de imagem',
  'image_converter_subtitle':
      'Converta uma fonte de instalação Windows completa ou uma imagem WIM/ESD/SWM compatível em uma ISO inicializável verificada.',
  'image_converter_source': 'Imagem de origem ou pasta de instalação',
  'image_converter_select_file': 'Escolher imagem',
  'image_converter_select_folder': 'Escolher pasta de instalação',
  'image_converter_base': 'Mídia de instalação base compatível',
  'image_converter_select_base': 'Escolher ISO / pasta base',
  'image_converter_output': 'ISO de saída',
  'image_converter_select_output': 'Escolher saída',
  'image_converter_convert': 'Criar ISO verificada',
  'image_converter_cancel': 'Cancelar conversão',
  'image_converter_use_creator': 'Usar na mídia de instalação',
  'image_converter_use_wtg': 'Usar no Windows To Go',
  'creator_convert_other_image': 'Outro formato? Abrir conversor',
  'wtg_convert_other_image': 'Outro formato? Abrir conversor',
  'image_converter_result_title': 'ISO verificada pronta',
  'image_converter_result_size': 'Tamanho da saída',
  'image_converter_result_copy_hash': 'Copiar SHA-256',
  'image_converter_hash_copied': 'SHA-256 copiado.',
};

final _imageConversionRu = <String, String>{
  ..._imageConversionEn,
  'disk_tools_title': 'Инструменты накопителей и образов',
  'disk_tools_converter_title': 'Преобразование формата образа',
  'disk_tools_converter_desc':
      'Подготовка поддерживаемых источников Windows в загрузочный ISO без изменения исходных файлов.',
  'image_converter_title': 'Преобразование формата образа',
  'image_converter_subtitle':
      'Преобразуйте полный источник Windows Setup или совместимый образ WIM/ESD/SWM в проверенный загрузочный ISO.',
  'image_converter_source': 'Исходный образ или папка Setup',
  'image_converter_select_file': 'Выбрать образ',
  'image_converter_select_folder': 'Выбрать папку Setup',
  'image_converter_base': 'Совместимый базовый носитель Setup',
  'image_converter_select_base': 'Выбрать базовый ISO / папку',
  'image_converter_output': 'Выходной ISO',
  'image_converter_select_output': 'Выбрать выходной файл',
  'image_converter_convert': 'Создать проверенный ISO',
  'image_converter_cancel': 'Отменить преобразование',
  'image_converter_use_creator': 'Использовать для установочного носителя',
  'image_converter_use_wtg': 'Использовать в Windows To Go',
  'creator_convert_other_image': 'Другой формат? Открыть конвертер',
  'wtg_convert_other_image': 'Другой формат? Открыть конвертер',
  'image_converter_result_title': 'Проверенный ISO готов',
  'image_converter_result_size': 'Размер результата',
  'image_converter_result_copy_hash': 'Копировать SHA-256',
  'image_converter_hash_copied': 'SHA-256 скопирован.',
};

final _imageConversionAr = <String, String>{
  ..._imageConversionEn,
  'disk_tools_title': 'أدوات التخزين والصور',
  'disk_tools_converter_title': 'تحويل تنسيق الصورة',
  'disk_tools_converter_desc':
      'إعداد مصادر Windows المدعومة كملف ISO قابل للإقلاع دون تغيير المصدر.',
  'image_converter_title': 'تحويل تنسيق الصورة',
  'image_converter_subtitle':
      'حوّل مصدر إعداد Windows كاملاً أو صورة WIM/ESD/SWM متوافقة إلى ISO قابلة للإقلاع وتم التحقق منها.',
  'image_converter_source': 'الصورة المصدر أو مجلد الإعداد',
  'image_converter_select_file': 'اختيار صورة',
  'image_converter_select_folder': 'اختيار مجلد الإعداد',
  'image_converter_base': 'وسائط إعداد أساسية مطابقة',
  'image_converter_select_base': 'اختيار ISO / مجلد أساسي',
  'image_converter_output': 'ISO الناتج',
  'image_converter_select_output': 'اختيار الناتج',
  'image_converter_convert': 'إنشاء ISO تم التحقق منها',
  'image_converter_cancel': 'إلغاء التحويل',
  'image_converter_use_creator': 'استخدام في وسائط التثبيت',
  'image_converter_use_wtg': 'استخدام في Windows To Go',
  'creator_convert_other_image': 'تنسيق صورة آخر؟ افتح المحوّل',
  'wtg_convert_other_image': 'تنسيق صورة آخر؟ افتح المحوّل',
  'image_converter_result_title': 'ISO موثوقة جاهزة',
  'image_converter_result_size': 'حجم الناتج',
  'image_converter_result_copy_hash': 'نسخ SHA-256',
  'image_converter_hash_copied': 'تم نسخ SHA-256.',
};

final _imageConversionKo = <String, String>{
  ..._imageConversionEn,
  'disk_tools_title': '저장 장치 및 이미지 도구',
  'disk_tools_converter_title': '이미지 형식 변환',
  'disk_tools_converter_desc':
      '원본을 변경하지 않고 지원되는 Windows 원본을 부팅 가능한 ISO로 준비합니다.',
  'image_converter_title': '이미지 형식 변환',
  'image_converter_subtitle':
      '완전한 Windows 설치 원본 또는 호환되는 WIM/ESD/SWM 이미지를 검증된 부팅 ISO로 변환합니다.',
  'image_converter_source': '원본 이미지 또는 설치 폴더',
  'image_converter_select_file': '이미지 선택',
  'image_converter_select_folder': '설치 폴더 선택',
  'image_converter_base': '호환되는 기본 설치 미디어',
  'image_converter_select_base': '기본 ISO / 폴더 선택',
  'image_converter_output': '출력 ISO',
  'image_converter_select_output': '출력 선택',
  'image_converter_convert': '검증된 ISO 만들기',
  'image_converter_cancel': '변환 취소',
  'image_converter_use_creator': '설치 미디어에서 사용',
  'image_converter_use_wtg': 'Windows To Go에서 사용',
  'creator_convert_other_image': '다른 이미지 형식? 변환기 열기',
  'wtg_convert_other_image': '다른 이미지 형식? 변환기 열기',
  'image_converter_result_title': '검증된 ISO 준비 완료',
  'image_converter_result_size': '출력 크기',
  'image_converter_result_copy_hash': 'SHA-256 복사',
  'image_converter_hash_copied': 'SHA-256을 복사했습니다.',
};

final _imageConversionJa = <String, String>{
  ..._imageConversionEn,
  'disk_tools_title': 'ストレージとイメージツール',
  'disk_tools_converter_title': 'イメージ形式の変換',
  'disk_tools_converter_desc':
      '元のファイルを変更せず、対応する Windows ソースから起動可能な ISO を作成します。',
  'image_converter_title': 'イメージ形式の変換',
  'image_converter_subtitle':
      '完全な Windows セットアップソース、または互換性のある WIM/ESD/SWM イメージを検証済みの起動 ISO に変換します。',
  'image_converter_source': 'ソースイメージまたはセットアップフォルダー',
  'image_converter_select_file': 'イメージを選択',
  'image_converter_select_folder': 'セットアップフォルダーを選択',
  'image_converter_base': '一致するベースセットアップメディア',
  'image_converter_select_base': 'ベース ISO / フォルダーを選択',
  'image_converter_output': '出力 ISO',
  'image_converter_select_output': '出力先を選択',
  'image_converter_convert': '検証済み ISO を作成',
  'image_converter_cancel': '変換をキャンセル',
  'image_converter_use_creator': 'インストールメディアで使用',
  'image_converter_use_wtg': 'Windows To Go で使用',
  'creator_convert_other_image': '他の形式？変換ツールを開く',
  'wtg_convert_other_image': '他の形式？変換ツールを開く',
  'image_converter_result_title': '検証済み ISO の準備完了',
  'image_converter_result_size': '出力サイズ',
  'image_converter_result_copy_hash': 'SHA-256 をコピー',
  'image_converter_hash_copied': 'SHA-256 をコピーしました。',
};
