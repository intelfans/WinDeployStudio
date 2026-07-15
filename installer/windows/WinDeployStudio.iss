#define MyAppName "WinDeploy Studio"
#define MyAppVersion "2.0.6"
#define MyAppFileVersion "2.0.6.0"
#define MyAppPublisher "Bob Steve"
#define MyAppPublisherZH "Bob Steve"
#define MyAppExeName "win_deploy_studio.exe"
#define MyAppDescription "Windows and Linux Deployment Toolkit"
#define MyAppContact "https://github.com/intelfans"
#define MyAppURL "https://github.com/intelfans"
#define MyAppGitHub "https://github.com/intelfans/WinDeployStudio"

[Setup]
AppId={{B7E5FC28-27A9-4D3F-B777-2C5F8B3D6E7C}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
AppContact={#MyAppContact}
AppSupportURL={#MyAppURL}
AppUpdatesURL={#MyAppURL}
AppCopyright=© 2026 {#MyAppPublisher}. Released under the MIT License.
DefaultDirName={autopf}\WinDeploy Studio
DefaultGroupName=WinDeploy Studio
OutputDir=..\..\dist\windows
OutputBaseFilename=WinDeployStudio_Setup_2.0.6
Compression=lzma2
SolidCompression=yes
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
UninstallDisplayName=WinDeploy Studio
WizardStyle=modern
DisableProgramGroupPage=yes
PrivilegesRequired=admin
WizardImageFile=wizardimage.bmp
WizardSmallImageFile=wizardsmallimage.bmp
SetupIconFile=icon.ico
VersionInfoVersion={#MyAppFileVersion}
VersionInfoCompany={#MyAppPublisher}
VersionInfoDescription={#MyAppDescription}
VersionInfoCopyright=© 2026 {#MyAppPublisher}. MIT License.
VersionInfoProductName={#MyAppName}
VersionInfoProductVersion={#MyAppVersion}

[Languages]
Name: "chinesesimplified"; MessagesFile: "compiler:Languages\ChineseSimplified.isl"; InfoBeforeFile: "WELCOME_ZH.txt"; InfoAfterFile: "FINISH_ZH.txt"
Name: "chinesetraditional"; MessagesFile: "compiler:Languages\ChineseTraditional.isl"; InfoBeforeFile: "WELCOME_ZH_TW.txt"; InfoAfterFile: "FINISH_ZH_TW.txt"
Name: "english"; MessagesFile: "compiler:Default.isl"; InfoBeforeFile: "WELCOME_EN.txt"; InfoAfterFile: "FINISH_EN.txt"
Name: "french"; MessagesFile: "compiler:Languages\French.isl"; InfoBeforeFile: "WELCOME_FR.txt"; InfoAfterFile: "FINISH_FR.txt"
Name: "german"; MessagesFile: "compiler:Languages\German.isl"; InfoBeforeFile: "WELCOME_DE.txt"; InfoAfterFile: "FINISH_DE.txt"
Name: "spanish"; MessagesFile: "compiler:Languages\Spanish.isl"; InfoBeforeFile: "WELCOME_ES.txt"; InfoAfterFile: "FINISH_ES.txt"
Name: "portuguese"; MessagesFile: "compiler:Languages\Portuguese.isl"; InfoBeforeFile: "WELCOME_PT.txt"; InfoAfterFile: "FINISH_PT.txt"
Name: "russian"; MessagesFile: "compiler:Languages\Russian.isl"; InfoBeforeFile: "WELCOME_RU.txt"; InfoAfterFile: "FINISH_RU.txt"
Name: "arabic"; MessagesFile: "compiler:Languages\Arabic.isl"; InfoBeforeFile: "WELCOME_AR.txt"; InfoAfterFile: "FINISH_AR.txt"
Name: "korean"; MessagesFile: "compiler:Languages\Korean.isl"; InfoBeforeFile: "WELCOME_KO.txt"; InfoAfterFile: "FINISH_KO.txt"
Name: "japanese"; MessagesFile: "compiler:Languages\Japanese.isl"; InfoBeforeFile: "WELCOME_JA.txt"; InfoAfterFile: "FINISH_JA.txt"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"

[Files]
Source: "MIT_LICENSE.txt"; Flags: dontcopy
Source: "MIT_LICENSE.txt"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\WinDeploy Studio"; Filename: "{app}\{#MyAppExeName}"
Name: "{group}\{cm:UninstallProgram,WinDeploy Studio}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\WinDeploy Studio"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "{cm:LaunchProgram,WinDeploy Studio}"; Flags: nowait postinstall skipifsilent shellexec runasoriginaluser

[CustomMessages]
; Custom messages for both languages
english.OpenSourceNoticeTitle=Open Source Notice
english.OpenSourceNoticeSubTitle=License and third-party acknowledgement
english.OpenSourceNoticeText=WinDeploy Studio is distributed under the MIT License.%n%nThird-party software, trademarks, logos, and external resources remain the property of their respective owners.%n%nUse of this software is at your own risk.%n%nNo warranty is provided.%n%nThis release bundles wds_ext4_builder, a limited ext4 persistence-image helper built from pinned MIT-licensed go-ext4fs source. Linux To Go persistence is experimental: only structurally preflighted x64 Ubuntu/casper, Debian Live/Kali, and Deepin Live profiles are eligible, and each profile still requires real boot and reboot-persistence verification. See THIRD_PARTY_NOTICES.md and tools\ext4-builder\README.md after installation.
english.ViewMITLicense=View MIT License
english.CreateDesktopIcon=Create a &desktop shortcut
english.AdditionalIcons=Additional icons:
english.UninstallProgram=Uninstall %1
english.LaunchProgram=Launch %1

chinesesimplified.OpenSourceNoticeTitle=开源说明
chinesesimplified.OpenSourceNoticeSubTitle=许可证与第三方致谢
chinesesimplified.OpenSourceNoticeText=WinDeploy Studio 基于 MIT License 分发。%n%n第三方软件、商标、标志和外部资源仍归其各自所有者所有。%n%n使用本软件风险自负。%n%n本软件不提供任何担保。%n%n本发行版内置 wds_ext4_builder，这是由固定版本、MIT 许可的 go-ext4fs 源码构建的受限 ext4 持久化镜像工具。Linux To Go 持久化目前仅属实验性功能：只允许通过结构预检的 x64 Ubuntu/casper、Debian Live/Kali 和 Deepin Live 配置，且每个配置仍需经过真实启动和重启后持久化验证。安装后请查看 THIRD_PARTY_NOTICES.md 和 tools\ext4-builder\README.md。
chinesesimplified.ViewMITLicense=查看 MIT License
chinesesimplified.CreateDesktopIcon=创建桌面快捷方式(&D)
chinesesimplified.AdditionalIcons=其他图标：
chinesesimplified.UninstallProgram=卸载 %1
chinesesimplified.LaunchProgram=启动 %1
chinesesimplified.NameAndVersion=%1 版本 %2
chinesesimplified.CreateQuickLaunchIcon=创建快速启动图标(&Q)
chinesesimplified.ProgramOnTheWeb=%1 的网站
chinesesimplified.AssocFileExtension=将 %1 与 %2 文件扩展名关联(&A)
chinesesimplified.AssocingFileExtension=正在将 %1 与 %2 文件扩展名关联...
chinesesimplified.AutoStartProgramGroupDescription=启动：
chinesesimplified.AutoStartProgram=安装完成后自动运行 %1(&R)
chinesesimplified.AddonHostProgramNotFound=%1 无法找到您选择的文件夹。%n%n您是否仍要继续？

; Traditional Chinese
chinesetraditional.OpenSourceNoticeTitle=開源說明
chinesetraditional.OpenSourceNoticeSubTitle=授權與第三方致謝
chinesetraditional.OpenSourceNoticeText=WinDeploy Studio 基於 MIT License 發行。%n%n第三方軟體、商標、標誌和外部資源仍歸其各自所有者所有。%n%n使用本軟體風險自負。%n%n本軟體不提供任何擔保。%n%n本發行版內建 wds_ext4_builder，這是由固定版本、MIT 授權的 go-ext4fs 原始碼建置的受限 ext4 持久化映像工具。Linux To Go 持久化目前僅屬實驗性功能：只允許通過結構預檢的 x64 Ubuntu/casper、Debian Live/Kali 和 Deepin Live 配置，且每個配置仍需經過實際啟動和重新啟動後持久化驗證。安裝後請查看 THIRD_PARTY_NOTICES.md 和 tools\ext4-builder\README.md。
chinesetraditional.ViewMITLicense=檢視 MIT License
chinesetraditional.CreateDesktopIcon=建立桌面捷徑(&D)
chinesetraditional.AdditionalIcons=其他圖示：
chinesetraditional.UninstallProgram=解除安裝 %1
chinesetraditional.LaunchProgram=啟動 %1

; Russian
russian.OpenSourceNoticeTitle=Уведомление об открытом коде
russian.OpenSourceNoticeSubTitle=Лицензия и сторонние ресурсы
russian.OpenSourceNoticeText=WinDeploy Studio распространяется по лицензии MIT.%n%nСтороннее ПО, товарные знаки, логотипы и внешние ресурсы остаются собственностью соответствующих владельцев.%n%nВы используете это ПО на свой риск.%n%nГарантии не предоставляются.%n%nЭта версия включает wds_ext4_builder, ограниченный помощник создания ext4-образов постоянного хранения, собранный из закреплённого исходного кода go-ext4fs по лицензии MIT. Постоянный Linux To Go пока экспериментален: допустимы только прошедшие структурную предварительную проверку профили x64 Ubuntu/casper, Debian Live/Kali и Deepin Live, и для каждого профиля всё ещё необходима проверка реальной загрузки и сохранения данных после перезагрузки. После установки см. THIRD_PARTY_NOTICES.md и tools\ext4-builder\README.md.
russian.ViewMITLicense=Открыть лицензию MIT
russian.CreateDesktopIcon=Создать &ярлык на рабочем столе
russian.AdditionalIcons=Дополнительные значки:
russian.UninstallProgram=Удалить %1
russian.LaunchProgram=Запустить %1

; French
french.OpenSourceNoticeTitle=Avis open source
french.OpenSourceNoticeSubTitle=Licence et ressources tierces
french.OpenSourceNoticeText=WinDeploy Studio est distribué sous licence MIT.%n%nLes logiciels tiers, marques, logos et ressources externes restent la propriété de leurs détenteurs respectifs.%n%nVous utilisez ce logiciel à vos propres risques.%n%nAucune garantie n'est fournie.%n%nCette version inclut wds_ext4_builder, un composant restreint d'image de persistance ext4 compilé depuis le code source go-ext4fs épinglé sous licence MIT. La persistance Linux To Go reste expérimentale : seuls les profils x64 Ubuntu/casper, Debian Live/Kali et Deepin Live ayant passé la prévalidation structurelle sont admis, et chacun doit encore être vérifié par un démarrage réel et une persistance après redémarrage. Consultez THIRD_PARTY_NOTICES.md et tools\ext4-builder\README.md après l'installation.
french.ViewMITLicense=Voir la licence MIT
french.CreateDesktopIcon=Créer un raccourci sur le &bureau
french.AdditionalIcons=Icônes supplémentaires :
french.UninstallProgram=Désinstaller %1
french.LaunchProgram=Lancer %1

; German
german.OpenSourceNoticeTitle=Open-Source-Hinweis
german.OpenSourceNoticeSubTitle=Lizenz und Drittanbieterressourcen
german.OpenSourceNoticeText=WinDeploy Studio wird unter der MIT-Lizenz verteilt.%n%nSoftware, Marken, Logos und externe Ressourcen Dritter bleiben Eigentum der jeweiligen Rechteinhaber.%n%nDie Nutzung dieser Software erfolgt auf eigenes Risiko.%n%nEs wird keine Gewährleistung übernommen.%n%nDiese Version enthält wds_ext4_builder, einen eingeschränkten Ext4-Persistenzabbild-Helfer aus festgeschriebenem, MIT-lizenziertem go-ext4fs-Quellcode. Die Linux-To-Go-Persistenz ist experimentell: Nur strukturell vorgeprüfte x64 Ubuntu/casper, Debian Live/Kali und Deepin Live Profile sind zugelassen, und jedes Profil benötigt weiterhin eine Prüfung durch echten Bootvorgang und Persistenz nach einem Neustart. Lesen Sie nach der Installation THIRD_PARTY_NOTICES.md und tools\ext4-builder\README.md.
german.ViewMITLicense=MIT-Lizenz anzeigen
german.CreateDesktopIcon=Verknüpfung auf dem &Desktop erstellen
german.AdditionalIcons=Zusätzliche Symbole:
german.UninstallProgram=%1 deinstallieren
german.LaunchProgram=%1 starten

; Spanish
spanish.OpenSourceNoticeTitle=Aviso de código abierto
spanish.OpenSourceNoticeSubTitle=Licencia y recursos de terceros
spanish.OpenSourceNoticeText=WinDeploy Studio se distribuye bajo la licencia MIT.%n%nEl software de terceros, las marcas, los logotipos y los recursos externos siguen siendo propiedad de sus respectivos propietarios.%n%nEl uso de este software es bajo su propio riesgo.%n%nNo se proporciona garantía.%n%nEsta versión incluye wds_ext4_builder, un componente limitado de imagen de persistencia ext4 compilado desde código fuente go-ext4fs fijado bajo licencia MIT. La persistencia Linux To Go sigue siendo experimental: solo se admiten perfiles x64 Ubuntu/casper, Debian Live/Kali y Deepin Live que superen la comprobación estructural previa, y cada perfil aún necesita verificación mediante arranque real y persistencia tras reiniciar. Consulta THIRD_PARTY_NOTICES.md y tools\ext4-builder\README.md tras la instalación.
spanish.ViewMITLicense=Ver licencia MIT
spanish.CreateDesktopIcon=Crear un acceso directo en el &escritorio
spanish.AdditionalIcons=Iconos adicionales:
spanish.UninstallProgram=Desinstalar %1
spanish.LaunchProgram=Ejecutar %1

; Portuguese
portuguese.OpenSourceNoticeTitle=Aviso de código aberto
portuguese.OpenSourceNoticeSubTitle=Licença e recursos de terceiros
portuguese.OpenSourceNoticeText=O WinDeploy Studio é distribuído sob a Licença MIT.%n%nSoftwares de terceiros, marcas, logotipos e recursos externos permanecem propriedade de seus respectivos proprietários.%n%nO uso deste software é por sua conta e risco.%n%nNenhuma garantia é fornecida.%n%nEsta versão inclui wds_ext4_builder, um componente limitado de imagem de persistência ext4 compilado do código-fonte go-ext4fs fixado sob licença MIT. A persistência Linux To Go continua experimental: somente perfis x64 Ubuntu/casper, Debian Live/Kali e Deepin Live aprovados na pré-verificação estrutural são aceitos, e cada perfil ainda precisa de validação por inicialização real e persistência após reiniciar. Consulte THIRD_PARTY_NOTICES.md e tools\ext4-builder\README.md após a instalação.
portuguese.ViewMITLicense=Ver Licença MIT
portuguese.CreateDesktopIcon=Criar atalho na &área de trabalho
portuguese.AdditionalIcons=Ícones adicionais:
portuguese.UninstallProgram=Desinstalar %1
portuguese.LaunchProgram=Executar %1

; Arabic
arabic.OpenSourceNoticeTitle=تنبيه مفتوح المصدر
arabic.OpenSourceNoticeSubTitle=الترخيص وموارد الجهات الخارجية
arabic.OpenSourceNoticeText=يُوزَّع WinDeploy Studio بموجب ترخيص MIT.%n%nتبقى البرامج والعلامات التجارية والشعارات والموارد الخارجية التابعة لجهات خارجية ملكًا لأصحابها المعنيين.%n%nاستخدام هذا البرنامج يكون على مسؤوليتك الخاصة.%n%nلا يتم تقديم أي ضمان.%n%nيتضمن هذا الإصدار wds_ext4_builder، وهو مساعد محدود لإنشاء صور استمرارية ext4 مبني من مصدر go-ext4fs مثبت بترخيص MIT. استمرارية Linux To Go ما زالت تجريبية: لا تُقبل إلا إعدادات x64 Ubuntu/casper وDebian Live/Kali وDeepin Live التي اجتازت الفحص البنيوي المسبق، ويظل كل إعداد بحاجة إلى التحقق من الإقلاع الحقيقي ومن بقاء البيانات بعد إعادة التشغيل. راجع THIRD_PARTY_NOTICES.md وtools\ext4-builder\README.md بعد التثبيت.
arabic.ViewMITLicense=عرض ترخيص MIT
arabic.CreateDesktopIcon=إنشاء اختصار على سطح المكتب(&D)
arabic.AdditionalIcons=أيقونات إضافية:
arabic.UninstallProgram=إلغاء تثبيت %1
arabic.LaunchProgram=تشغيل %1

; Korean
korean.OpenSourceNoticeTitle=오픈 소스 안내
korean.OpenSourceNoticeSubTitle=라이선스 및 타사 리소스
korean.OpenSourceNoticeText=WinDeploy Studio는 MIT License에 따라 배포됩니다.%n%n타사 소프트웨어, 상표, 로고 및 외부 리소스는 각 소유자의 자산입니다.%n%n이 소프트웨어의 사용은 사용자 책임입니다.%n%n어떠한 보증도 제공되지 않습니다.%n%n이 릴리스에는 고정된 MIT 라이선스 go-ext4fs 소스에서 빌드한 제한된 ext4 영구 저장 이미지 도우미 wds_ext4_builder가 포함됩니다. Linux To Go 영구 저장은 아직 실험적입니다. 구조 사전 검사를 통과한 x64 Ubuntu/casper, Debian Live/Kali 및 Deepin Live 프로필만 허용되며, 각 프로필은 실제 부팅과 재부팅 후 영구 저장 검증이 여전히 필요합니다. 설치 후 THIRD_PARTY_NOTICES.md와 tools\ext4-builder\README.md를 확인하세요.
korean.ViewMITLicense=MIT License 보기
korean.CreateDesktopIcon=바탕 화면에 바로 가기 만들기(&D)
korean.AdditionalIcons=추가 아이콘:
korean.UninstallProgram=%1 제거
korean.LaunchProgram=%1 실행

; Japanese
japanese.OpenSourceNoticeTitle=オープンソースに関するお知らせ
japanese.OpenSourceNoticeSubTitle=ライセンスと第三者リソース
japanese.OpenSourceNoticeText=WinDeploy Studio は MIT License の下で配布されています。%n%n第三者のソフトウェア、商標、ロゴ、外部リソースは、それぞれの所有者に帰属します。%n%n本ソフトウェアの使用は自己責任です。%n%nいかなる保証も提供されません。%n%nこのリリースには、固定された MIT ライセンスの go-ext4fs ソースから構築した制限付き ext4 永続化イメージヘルパー wds_ext4_builder が含まれます。Linux To Go の永続化はまだ実験的です。構造事前検査を通過した x64 Ubuntu/casper、Debian Live/Kali、Deepin Live プロファイルのみを対象とし、各プロファイルで実機起動と再起動後の永続化を検証する必要があります。インストール後に THIRD_PARTY_NOTICES.md と tools\ext4-builder\README.md を参照してください。
japanese.ViewMITLicense=MIT License を表示
japanese.CreateDesktopIcon=デスクトップにショートカットを作成(&D)
japanese.AdditionalIcons=追加のアイコン：
japanese.UninstallProgram=%1 をアンインストール
japanese.LaunchProgram=%1 を起動

[Messages]
; ── English messages ──
english.WelcomeLabel1=Welcome to the WinDeploy Studio Setup Wizard
english.WelcomeLabel2=This will install WinDeploy Studio %1 on your computer.%n%nWinDeploy Studio creates Windows installation media, writes bootable Linux ISOHybrid images, builds portable Windows To Go workspaces, validates supported x64 Ubuntu/casper, Debian Live/Kali, and Deepin Live layouts, and includes native drive testing. This release includes a limited ext4 persistence helper for experimental Linux To Go; only structurally preflighted x64 Ubuntu/casper, Debian Live/Kali, and Deepin Live profiles are eligible, and each still needs real boot and reboot-persistence verification.%n%nIt is recommended that you close all other applications before continuing.
english.FinishedLabel=Setup has successfully installed WinDeploy Studio on your computer. The application may be launched by selecting the installed icons.

; ── 简体中文消息 ──
chinesesimplified.WelcomeLabel1=欢迎使用 WinDeploy Studio 安装向导
chinesesimplified.WelcomeLabel2=安装程序将在您的计算机上安装 WinDeploy Studio %1。%n%nWinDeploy Studio 支持创建 Windows 安装盘、写入可启动的 Linux ISOHybrid 镜像、创建 Windows To Go、验证受支持的 x64 Ubuntu/casper、Debian Live/Kali 和 Deepin Live 布局，并提供原生磁盘测试。本发行版内置一个用于实验性 Linux To Go 的受限 ext4 持久化工具；仅允许通过结构预检的 x64 Ubuntu/casper、Debian Live/Kali 和 Deepin Live 配置，每个配置仍需真实启动及重启后持久化验证。%n%n建议您在继续之前关闭所有其他应用程序。
chinesesimplified.FinishedLabel=安装程序已成功将 WinDeploy Studio 安装到您的计算机上。您可以通过选择已安装的图标来启动应用程序。
chinesesimplified.SetupAppTitle=WinDeploy Studio 安装程序
chinesesimplified.SetupWindowTitle=WinDeploy Studio 安装程序
chinesesimplified.UninstallAppTitle=WinDeploy Studio 卸载程序
chinesesimplified.UninstallStatusLabel=正在从您的计算机中移除 %1，请稍候...
chinesesimplified.UninstallDisplayNameMarkAllUsers=(所有用户)
chinesesimplified.UninstallDisplayNameMarkCurrentUser=(当前用户)
chinesesimplified.ClickNext=点击"下一步"继续，或点击"取消"退出安装程序。
chinesesimplified.BeveledLabel=WinDeploy Studio 安装程序
chinesesimplified.PathLabel=安装路径：
chinesesimplified.InvalidPath=请输入完整的路径，包括盘符。%n%n例如：C:\Program Files\%1
chinesesimplified.InvalidDrive=您选择的磁盘不存在或不可用。请选择其他磁盘。
chinesesimplified.DirExists=该目录已存在：%n%n%1%n%n是否仍要使用该目录？
chinesesimplified.DirDoesntExist=目录不存在：%n%n%1%n%n是否要创建该目录？
chinesesimplified.ExitSetupTitle=退出安装程序
chinesesimplified.ExitSetupMessage=安装尚未完成。如果现在退出，程序将不会被安装。%n%n您可以稍后再次运行安装程序完成安装。%n%n确定要退出吗？
chinesesimplified.StatusCreateDirs=正在创建目录...
chinesesimplified.StatusExtractFiles=正在释放文件...
chinesesimplified.StatusCreateIcons=正在创建快捷方式...
chinesesimplified.StatusCreateIniEntries=正在创建 INI 条目...
chinesesimplified.StatusCreateRegistryEntries=正在创建注册表项...
chinesesimplified.StatusSavingUninstall=正在保存卸载信息...
chinesesimplified.StatusRunProgram=正在完成安装...
chinesesimplified.StatusRollback=正在回滚更改...
chinesesimplified.WizardPreparing=正在准备安装...
chinesesimplified.PreparingDesc=安装程序正在准备安装 %1 到您的计算机上。
chinesesimplified.CannotContinue=无法继续安装。请点击"取消"退出。
chinesesimplified.ErrorDownloadFailed=下载失败：%1 %2
chinesesimplified.VerificationSignatureDoesntExist=文件签名验证
chinesesimplified.VerificationSignatureInvalid=文件签名无效！
chinesesimplified.VerificationFileHashIncorrect=文件哈希值不正确！
chinesesimplified.VerificationFileNameIncorrect=文件名不正确！
chinesesimplified.VerificationFileSizeIncorrect=文件大小不正确！
chinesesimplified.VerificationFileTagIncorrect=文件标签不正确！
chinesesimplified.VerificationKeyNotFound=未找到验证密钥！
chinesesimplified.PrivilegesRequiredOverrideCurrentUser=仅为当前用户安装(&U)
chinesesimplified.PrivilegesRequiredOverrideCurrentUserRecommended=仅为当前用户安装（推荐）(&U)
chinesesimplified.RetryCancelCancel=取消(&C)
chinesesimplified.RetryCancelRetry=重试(&R)
chinesesimplified.RetryCancelSelectAction=选择操作(&S)
chinesesimplified.SelectDiskLabel2=选择安装位置：
chinesesimplified.SourceVerificationFailed=源文件验证失败！
chinesesimplified.StatusDownloadFiles=正在下载文件...
chinesesimplified.StatusRegisterFiles=正在注册文件...
chinesesimplified.StopDownload=停止下载(&S)
chinesesimplified.StopExtraction=停止释放(&S)
chinesesimplified.UninstallDisplayNameMark=
chinesesimplified.UninstallDisplayNameMarks=
chinesesimplified.UninstallDisplayNameMark32Bit=(32 位)
chinesesimplified.UninstallDisplayNameMark64Bit=(64 位)
chinesesimplified.ArchiveIncorrectPassword=压缩包密码不正确。
chinesesimplified.ArchiveIsCorrupted=压缩包已损坏。
chinesesimplified.ArchiveUnsupportedFormat=压缩包格式不支持。
chinesesimplified.BadGroupName=安装程序中存在无效的组名：%1
chinesesimplified.ButtonStopDownload=停止下载
chinesesimplified.ButtonStopExtraction=停止释放
chinesesimplified.CannotInstallToNetworkDrive=安装程序无法安装到网络驱动器。
chinesesimplified.CannotInstallToUNCPath=安装程序无法安装到 UNC 路径。
chinesesimplified.ComponentsDiskSpaceGBLabel=所需磁盘空间（至少）：%1 GB 可用磁盘空间（实际需要更多）
chinesesimplified.DiskSpaceGBLabel=所需磁盘空间（至少）：%1 GB 可用磁盘空间。
chinesesimplified.DownloadingLabel2=正在从 %1 下载文件...
chinesesimplified.ErrorDownloadAborted=下载已中止。
chinesesimplified.ErrorDownloading=下载文件时出错：%1
chinesesimplified.ErrorDownloadSizeFailed=获取文件大小失败。
chinesesimplified.ErrorExtracting=释放文件时出错。
chinesesimplified.ErrorExtractionAborted=释放已中止。
chinesesimplified.ErrorExtractionFailed=释放文件失败：%1
chinesesimplified.ErrorFileSize=文件大小不正确：%1，期望 %2 字节。
chinesesimplified.ErrorProgress=进度值无效。
chinesesimplified.ErrorRegSvr32Failed=注册 %1 失败。
chinesesimplified.ExistingFileNewer2=目标目录中已存在较新版本的 %1。%n%n建议保留现有文件。%n%n您要如何操作？
chinesesimplified.ExistingFileNewerKeepExisting=保留现有文件(&K)
chinesesimplified.ExistingFileNewerOverwriteExisting=覆盖现有文件(&O)
chinesesimplified.ExistingFileNewerOverwriteOrKeepAll=对所有冲突文件执行相同操作(&A)
chinesesimplified.ExistingFileNewerSelectAction=选择操作(&S)
chinesesimplified.ExtractingLabel=正在释放文件...
chinesesimplified.FileExistsKeepExisting=保留现有文件(&K)
chinesesimplified.OnlyAdminCanUninstall=只有管理员才能卸载此程序。
chinesesimplified.PrivilegesRequiredOverrideAllUsers=为所有用户安装(&A)
chinesesimplified.PrivilegesRequiredOverrideAllUsersRecommended=为所有用户安装（推荐）(&A)
chinesesimplified.PrivilegesRequiredOverrideInstruction=选择安装方式
chinesesimplified.PrivilegesRequiredOverrideText1=WinDeploy Studio 可以为所有用户或仅为您安装。
chinesesimplified.PrivilegesRequiredOverrideText2=WinDeploy Studio 可以为您安装，也可以为这台计算机上的所有用户安装。%n%n请选择安装方式：
chinesesimplified.PrivilegesRequiredOverrideTitle=选择安装范围

; ── Русские сообщения ──
russian.WelcomeLabel1=Добро пожаловать в мастер установки WinDeploy Studio
russian.WelcomeLabel2=Эта программа установит WinDeploy Studio %1 на ваш компьютер.%n%nWinDeploy Studio создаёт установочные носители Windows, записывает загрузочные Linux ISOHybrid-образы, создаёт переносные среды Windows To Go, проверяет поддерживаемые x64-разметки Ubuntu/casper, Debian Live/Kali и Deepin Live, а также тестирует накопители. Эта версия включает ограниченный ext4-помощник для экспериментального Linux To Go; допустимы только прошедшие структурную предварительную проверку профили x64 Ubuntu/casper, Debian Live/Kali и Deepin Live, и каждый всё ещё требует проверки реальной загрузки и сохранения данных после перезагрузки.%n%nРекомендуется закрыть все остальные приложения перед продолжением.
russian.FinishedLabel=Установка WinDeploy Studio на ваш компьютер успешно завершена. Приложение можно запустить, выбрав установленные значки.

; ── Messages français ──
french.WelcomeLabel1=Bienvenue dans l'assistant d'installation de WinDeploy Studio
french.WelcomeLabel2=Cette procédure va installer WinDeploy Studio %1 sur votre ordinateur.%n%nWinDeploy Studio crée des supports d’installation Windows, écrit des images Linux ISOHybrid amorçables, crée des environnements Windows To Go portables, vérifie les dispositions x64 Ubuntu/casper, Debian Live/Kali et Deepin Live prises en charge, et propose un test natif des disques. Cette version inclut un composant ext4 restreint pour Linux To Go expérimental ; seuls les profils x64 Ubuntu/casper, Debian Live/Kali et Deepin Live ayant passé la prévalidation structurelle sont admis, et chacun doit encore être vérifié par un démarrage réel et une persistance après redémarrage.%n%nIl est recommandé de fermer toutes les autres applications avant de continuer.
french.FinishedLabel=L'installation de WinDeploy Studio sur votre ordinateur est terminée avec succès. L'application peut être lancée en sélectionnant les icônes installées.

; ── Mensagens em português ──
portuguese.WelcomeLabel1=Bem-vindo ao assistente de instalação do WinDeploy Studio
portuguese.WelcomeLabel2=Este procedimento instalará o WinDeploy Studio %1 no seu computador.%n%nO WinDeploy Studio cria mídias de instalação do Windows, grava imagens Linux ISOHybrid inicializáveis, cria ambientes Windows To Go portáteis, valida layouts x64 compatíveis Ubuntu/casper, Debian Live/Kali e Deepin Live e oferece teste nativo de unidades. Esta versão inclui um componente ext4 limitado para Linux To Go experimental; somente perfis x64 Ubuntu/casper, Debian Live/Kali e Deepin Live aprovados na pré-verificação estrutural são aceitos, e cada perfil ainda precisa de validação por inicialização real e persistência após reiniciar.%n%nRecomenda-se fechar todos os outros aplicativos antes de continuar.
portuguese.FinishedLabel=A instalação do WinDeploy Studio no seu computador foi concluída com sucesso. O aplicativo pode ser iniciado selecionando os ícones instalados.

; ── 日本語メッセージ ──
japanese.WelcomeLabel1=WinDeploy Studio セットアップウィザードへようこそ
japanese.WelcomeLabel2=このプログラムは WinDeploy Studio %1 をお使いのコンピューターにインストールします。%n%nWinDeploy Studio は Windows インストールメディアの作成、起動可能な Linux ISOHybrid の書き込み、ポータブルな Windows To Go、対応する x64 Ubuntu/casper、Debian Live/Kali、Deepin Live レイアウトの検証、ネイティブなドライブテストを提供します。このリリースには実験的な Linux To Go 向けの制限付き ext4 ヘルパーが含まれます。構造事前検査を通過した x64 Ubuntu/casper、Debian Live/Kali、Deepin Live プロファイルのみを対象とし、各プロファイルで実機起動と再起動後の永続化を検証する必要があります。%n%n続行する前に、他のすべてのアプリケーションを閉じることをお勧めします。
japanese.FinishedLabel=WinDeploy Studio お使いのコンピューターへのインストールが正常に完了しました。インストールされたアイコンを選択してアプリケーションを起動できます。

; ── 繁體中文訊息 ──
chinesetraditional.WelcomeLabel1=歡迎使用 WinDeploy Studio 安裝精靈
chinesetraditional.WelcomeLabel2=安裝程式將在您的電腦上安裝 WinDeploy Studio %1。%n%nWinDeploy Studio 支援建立 Windows 安裝碟、寫入可啟動的 Linux ISOHybrid 映像、建立 Windows To Go、驗證受支援的 x64 Ubuntu/casper、Debian Live/Kali 和 Deepin Live 配置，並提供原生磁碟測試。本發行版內建一個用於實驗性 Linux To Go 的受限 ext4 持久化工具；只允許通過結構預檢的 x64 Ubuntu/casper、Debian Live/Kali 和 Deepin Live 配置，每個配置仍需實際啟動及重新啟動後持久化驗證。%n%n建議您在繼續之前關閉所有其他應用程式。
chinesetraditional.FinishedLabel=安裝程式已成功將 WinDeploy Studio 安裝到您的電腦上。您可以透過選擇已安裝的圖示來啟動應用程式。

; ── Mensajes en español ──
spanish.WelcomeLabel1=Bienvenido al asistente de instalación de WinDeploy Studio
spanish.WelcomeLabel2=Este procedimiento instalará WinDeploy Studio %1 en su equipo.%n%nWinDeploy Studio crea medios de instalación de Windows, escribe imágenes Linux ISOHybrid arrancables, crea entornos Windows To Go portátiles, valida diseños x64 compatibles Ubuntu/casper, Debian Live/Kali y Deepin Live e incluye pruebas nativas de unidades. Esta versión incluye un componente ext4 limitado para Linux To Go experimental; solo se admiten perfiles x64 Ubuntu/casper, Debian Live/Kali y Deepin Live que superen la comprobación estructural previa, y cada perfil aún necesita verificación mediante arranque real y persistencia tras reiniciar.%n%nSe recomienda cerrar todas las demás aplicaciones antes de continuar.
spanish.FinishedLabel=La instalación de WinDeploy Studio en su equipo se ha completado correctamente. Puede iniciar la aplicación seleccionando los iconos instalados.

; ── رسائل عربية ──
arabic.WelcomeLabel1=مرحبًا بك في معالج تثبيت WinDeploy Studio
arabic.WelcomeLabel2=سيقوم هذا المثبت بتثبيت WinDeploy Studio %1 على جهازك.%n%nينشئ WinDeploy Studio وسائط تثبيت Windows، ويكتب صور Linux ISOHybrid قابلة للإقلاع، وينشئ بيئات Windows To Go محمولة، ويتحقق من تخطيطات x64 Ubuntu/casper وDebian Live/Kali وDeepin Live المدعومة، ويوفر اختباراً أصلياً لمحركات الأقراص. يتضمن هذا الإصدار مساعد ext4 محدوداً لـ Linux To Go التجريبي؛ لا تُقبل إلا إعدادات x64 Ubuntu/casper وDebian Live/Kali وDeepin Live التي اجتازت الفحص البنيوي المسبق، ويظل كل إعداد بحاجة إلى التحقق من الإقلاع الحقيقي ومن بقاء البيانات بعد إعادة التشغيل.%n%nيُوصى بإغلاق جميع التطبيقات الأخرى قبل المتابعة.
arabic.FinishedLabel=تم تثبيت WinDeploy Studio على جهازك بنجاح. يمكنك تشغيل التطبيق من خلال اختيار الأيقونات المثبتة.

; ── 한국어 메시지 ──
korean.WelcomeLabel1=WinDeploy Studio 설치 마법사에 오신 것을 환영합니다
korean.WelcomeLabel2=이 프로그램은 WinDeploy Studio %1을(를) 컴퓨터에 설치합니다.%n%nWinDeploy Studio는 Windows 설치 미디어를 만들고 부팅 가능한 Linux ISOHybrid 이미지를 쓰며, 휴대용 Windows To Go, 지원되는 x64 Ubuntu/casper, Debian Live/Kali 및 Deepin Live 레이아웃 검증, 네이티브 드라이브 테스트를 제공합니다. 이 릴리스에는 실험적 Linux To Go용 제한된 ext4 도우미가 포함됩니다. 구조 사전 검사를 통과한 x64 Ubuntu/casper, Debian Live/Kali 및 Deepin Live 프로필만 허용되며, 각 프로필은 실제 부팅과 재부팅 후 영구 저장 검증이 여전히 필요합니다.%n%n계속하기 전에 다른 모든 애플리케이션을 닫는 것이 좋습니다.
korean.FinishedLabel=WinDeploy Studio가 컴퓨터에 성공적으로 설치되었습니다. 설치된 아이콘을 선택하여 애플리케이션을 시작할 수 있습니다.

; ── Deutsche Meldungen ──
german.WelcomeLabel1=Willkommen beim WinDeploy Studio-Installationsassistenten
german.WelcomeLabel2=Dies wird WinDeploy Studio %1 auf Ihrem Computer installieren.%n%nWinDeploy Studio erstellt Windows-Installationsmedien, schreibt bootfähige Linux-ISOHybrid-Images, erstellt portable Windows-To-Go-Umgebungen, prüft unterstützte x64 Ubuntu/casper, Debian Live/Kali und Deepin Live Layouts und bietet native Laufwerkstests. Diese Version enthält einen eingeschränkten Ext4-Helfer für experimentelles Linux To Go; nur strukturell vorgeprüfte x64 Ubuntu/casper, Debian Live/Kali und Deepin Live Profile sind zugelassen, und jedes benötigt weiterhin eine Prüfung durch echten Bootvorgang und Persistenz nach einem Neustart.%n%nEs wird empfohlen, alle anderen Anwendungen zu schließen, bevor Sie fortfahren.
german.FinishedLabel=Die Installation von WinDeploy Studio auf Ihrem Computer wurde erfolgreich abgeschlossen. Die Anwendung kann über die installierten Symbole gestartet werden.

[Code]
var
  OpenSourceNoticePage: TWizardPage;
  OpenSourceNoticeMemo: TMemo;
  ViewMITLicenseButton: TNewButton;

function MessageText(const Key: string): string;
var
  Text: string;
begin
  Text := CustomMessage(Key);
  StringChangeEx(Text, '%n', #13#10, True);
  Result := Text;
end;

procedure ViewMITLicenseButtonClick(Sender: TObject);
var
  ResultCode: Integer;
  LicensePath: string;
begin
  ExtractTemporaryFile('MIT_LICENSE.txt');
  LicensePath := ExpandConstant('{tmp}\MIT_LICENSE.txt');
  ShellExec('', LicensePath, '', '', SW_SHOWNORMAL, ewNoWait, ResultCode);
end;

procedure InitializeWizard;
begin
  OpenSourceNoticePage :=
    CreateCustomPage(
      wpWelcome,
      CustomMessage('OpenSourceNoticeTitle'),
      CustomMessage('OpenSourceNoticeSubTitle')
    );

  OpenSourceNoticeMemo := TMemo.Create(OpenSourceNoticePage);
  OpenSourceNoticeMemo.Parent := OpenSourceNoticePage.Surface;
  OpenSourceNoticeMemo.Left := 0;
  OpenSourceNoticeMemo.Top := 0;
  OpenSourceNoticeMemo.Width := OpenSourceNoticePage.SurfaceWidth;
  OpenSourceNoticeMemo.Height := OpenSourceNoticePage.SurfaceHeight - ScaleY(40);
  OpenSourceNoticeMemo.ReadOnly := True;
  OpenSourceNoticeMemo.ScrollBars := ssVertical;
  OpenSourceNoticeMemo.WordWrap := True;
  OpenSourceNoticeMemo.Text := MessageText('OpenSourceNoticeText');

  ViewMITLicenseButton := TNewButton.Create(OpenSourceNoticePage);
  ViewMITLicenseButton.Parent := OpenSourceNoticePage.Surface;
  ViewMITLicenseButton.Left := 0;
  ViewMITLicenseButton.Top := OpenSourceNoticeMemo.Top + OpenSourceNoticeMemo.Height + ScaleY(8);
  ViewMITLicenseButton.Width := ScaleX(140);
  ViewMITLicenseButton.Height := ScaleY(24);
  ViewMITLicenseButton.Caption := CustomMessage('ViewMITLicense');
  ViewMITLicenseButton.OnClick := @ViewMITLicenseButtonClick;
end;
