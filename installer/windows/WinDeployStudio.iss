#define MyAppName "WinDeploy Studio"
#define MyAppVersion "1.0.2.0"
#define MyAppPublisher "Bob Steve"
#define MyAppPublisherZH "Bob Steve"
#define MyAppExeName "win_deploy_studio.exe"
#define MyAppDescription "Windows Deployment Tool"
#define MyAppContact "bob_0910@qq.com"
#define MyAppURL "https://xueyanzhang.top/contact/"

[Setup]
AppId={{B7E5FC28-27A9-4D3F-B777-2C5F8B3D6E7C}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
AppContact={#MyAppContact}
AppSupportURL={#MyAppURL}
AppUpdatesURL={#MyAppURL}
AppCopyright=© 2026 {#MyAppPublisher}. All rights reserved.
DefaultDirName={autopf}\WinDeploy Studio
DefaultGroupName=WinDeploy Studio
OutputDir=..\..\dist\windows
OutputBaseFilename=WinDeployStudio_Setup_1.0.2
Compression=lzma2
SolidCompression=yes
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
UninstallDisplayName=WinDeploy Studio
WizardStyle=modern
DisableProgramGroupPage=yes
PrivilegesRequired=admin
LicenseFile=LICENSE_EN.txt
WizardImageFile=wizardimage.bmp
WizardSmallImageFile=wizardsmallimage.bmp
SetupIconFile=icon.ico
VersionInfoVersion=1.0.2.0
VersionInfoCompany={#MyAppPublisher}
VersionInfoDescription={#MyAppDescription}
VersionInfoCopyright=© 2026 {#MyAppPublisher}
VersionInfoProductName={#MyAppName}
VersionInfoProductVersion={#MyAppVersion}

[Languages]
Name: "chinesesimplified"; MessagesFile: "compiler:Languages\ChineseSimplified.isl"; LicenseFile: "LICENSE_ZH.txt"; InfoBeforeFile: "WELCOME_ZH.txt"; InfoAfterFile: "FINISH_ZH.txt"
Name: "chinesetraditional"; MessagesFile: "compiler:Languages\ChineseTraditional.isl"; LicenseFile: "LICENSE_ZH_TW.txt"; InfoBeforeFile: "WELCOME_ZH_TW.txt"; InfoAfterFile: "FINISH_ZH_TW.txt"
Name: "english"; MessagesFile: "compiler:Default.isl"; LicenseFile: "LICENSE_EN.txt"; InfoBeforeFile: "WELCOME_EN.txt"; InfoAfterFile: "FINISH_EN.txt"
Name: "french"; MessagesFile: "compiler:Languages\French.isl"; LicenseFile: "LICENSE_FR.txt"; InfoBeforeFile: "WELCOME_FR.txt"; InfoAfterFile: "FINISH_FR.txt"
Name: "german"; MessagesFile: "compiler:Languages\German.isl"; LicenseFile: "LICENSE_DE.txt"; InfoBeforeFile: "WELCOME_DE.txt"; InfoAfterFile: "FINISH_DE.txt"
Name: "spanish"; MessagesFile: "compiler:Languages\Spanish.isl"; LicenseFile: "LICENSE_ES.txt"; InfoBeforeFile: "WELCOME_ES.txt"; InfoAfterFile: "FINISH_ES.txt"
Name: "portuguese"; MessagesFile: "compiler:Languages\Portuguese.isl"; LicenseFile: "LICENSE_PT.txt"; InfoBeforeFile: "WELCOME_PT.txt"; InfoAfterFile: "FINISH_PT.txt"
Name: "russian"; MessagesFile: "compiler:Languages\Russian.isl"; LicenseFile: "LICENSE_RU.txt"; InfoBeforeFile: "WELCOME_RU.txt"; InfoAfterFile: "FINISH_RU.txt"
Name: "arabic"; MessagesFile: "compiler:Languages\Arabic.isl"; LicenseFile: "LICENSE_AR.txt"; InfoBeforeFile: "WELCOME_AR.txt"; InfoAfterFile: "FINISH_AR.txt"
Name: "korean"; MessagesFile: "compiler:Languages\Korean.isl"; LicenseFile: "LICENSE_KO.txt"; InfoBeforeFile: "WELCOME_KO.txt"; InfoAfterFile: "FINISH_KO.txt"
Name: "japanese"; MessagesFile: "compiler:Languages\Japanese.isl"; LicenseFile: "LICENSE_JA.txt"; InfoBeforeFile: "WELCOME_JA.txt"; InfoAfterFile: "FINISH_JA.txt"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"

[Files]
Source: "..\..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\WinDeploy Studio"; Filename: "{app}\{#MyAppExeName}"
Name: "{group}\{cm:UninstallProgram,WinDeploy Studio}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\WinDeploy Studio"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "{cm:LaunchProgram,WinDeploy Studio}"; Flags: nowait postinstall skipifsilent shellexec runasoriginaluser

[CustomMessages]
; Custom messages for both languages
english.CreateDesktopIcon=Create a &desktop shortcut
english.AdditionalIcons=Additional icons:
english.UninstallProgram=Uninstall %1
english.LaunchProgram=Launch %1

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
chinesetraditional.CreateDesktopIcon=建立桌面捷徑(&D)
chinesetraditional.AdditionalIcons=其他圖示：
chinesetraditional.UninstallProgram=解除安裝 %1
chinesetraditional.LaunchProgram=啟動 %1

; Russian
russian.CreateDesktopIcon=Создать &ярлык на рабочем столе
russian.AdditionalIcons=Дополнительные значки:
russian.UninstallProgram=Удалить %1
russian.LaunchProgram=Запустить %1

; French
french.CreateDesktopIcon=Créer un raccourci sur le &bureau
french.AdditionalIcons=Icônes supplémentaires :
french.UninstallProgram=Désinstaller %1
french.LaunchProgram=Lancer %1

; German
german.CreateDesktopIcon=Verknüpfung auf dem &Desktop erstellen
german.AdditionalIcons=Zusätzliche Symbole:
german.UninstallProgram=%1 deinstallieren
german.LaunchProgram=%1 starten

; Spanish
spanish.CreateDesktopIcon=Crear un acceso directo en el &escritorio
spanish.AdditionalIcons=Iconos adicionales:
spanish.UninstallProgram=Desinstalar %1
spanish.LaunchProgram=Ejecutar %1

; Portuguese
portuguese.CreateDesktopIcon=Criar atalho na &área de trabalho
portuguese.AdditionalIcons=Ícones adicionais:
portuguese.UninstallProgram=Desinstalar %1
portuguese.LaunchProgram=Executar %1

; Russian
russian.CreateDesktopIcon=Создать &ярлык на рабочем столе
russian.AdditionalIcons=Дополнительные значки:
russian.UninstallProgram=Удалить %1
russian.LaunchProgram=Запустить %1

; Arabic
arabic.CreateDesktopIcon=إنشاء اختصار على سطح المكتب(&D)
arabic.AdditionalIcons=أيقونات إضافية:
arabic.UninstallProgram=إلغاء تثبيت %1
arabic.LaunchProgram=تشغيل %1

; Korean
korean.CreateDesktopIcon=바탕 화면에 바로 가기 만들기(&D)
korean.AdditionalIcons=추가 아이콘:
korean.UninstallProgram=%1 제거
korean.LaunchProgram=%1 실행

; Japanese
japanese.CreateDesktopIcon=デスクトップにショートカットを作成(&D)
japanese.AdditionalIcons=追加のアイコン：
japanese.UninstallProgram=%1 をアンインストール
japanese.LaunchProgram=%1 を起動

[Messages]
; ── English messages ──
english.WelcomeLabel1=Welcome to the WinDeploy Studio Setup Wizard
english.WelcomeLabel2=This will install WinDeploy Studio %1 on your computer.%n%nWinDeploy Studio is a modern Windows deployment tool for creating bootable USB drives and Windows To Go workspaces.%n%nIt is recommended that you close all other applications before continuing.
english.FinishedLabel=Setup has successfully installed WinDeploy Studio on your computer. The application may be launched by selecting the installed icons.

; ── 简体中文消息 ──
chinesesimplified.WelcomeLabel1=欢迎使用 WinDeploy Studio 安装向导
chinesesimplified.WelcomeLabel2=安装程序将在您的计算机上安装 WinDeploy Studio %1。%n%nWinDeploy Studio 是一款现代化的 Windows 部署工具，用于创建启动盘和 Windows To Go 工作空间。%n%n建议您在继续之前关闭所有其他应用程序。
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
russian.WelcomeLabel2=Эта программа установит WinDeploy Studio %1 на ваш компьютер.%n%nWinDeploy Studio — современный инструмент развёртывания Windows для создания загрузочных USB-накопителей и рабочих пространств Windows To Go.%n%nРекомендуется закрыть все остальные приложения перед продолжением.
russian.FinishedLabel=Установка WinDeploy Studio на ваш компьютер успешно завершена. Приложение можно запустить, выбрав установленные значки.

; ── Messages français ──
french.WelcomeLabel1=Bienvenue dans l'assistant d'installation de WinDeploy Studio
french.WelcomeLabel2=Cette procédure va installer WinDeploy Studio %1 sur votre ordinateur.%n%nWinDeploy Studio est un outil moderne de déploiement Windows pour créer des clés USB amorçables et des espaces de travail Windows To Go.%n%nIl est recommandé de fermer toutes les autres applications avant de continuer.
french.FinishedLabel=L'installation de WinDeploy Studio sur votre ordinateur est terminée avec succès. L'application peut être lancée en sélectionnant les icônes installées.

; ── Mensagens em português ──
portuguese.WelcomeLabel1=Bem-vindo ao assistente de instalação do WinDeploy Studio
portuguese.WelcomeLabel2=Este procedimento instalará o WinDeploy Studio %1 no seu computador.%n%nO WinDeploy Studio é uma ferramenta moderna de implantação do Windows para criar memórias USB inicializáveis e espaços de trabalho Windows To Go.%n%nRecomenda-se fechar todos os outros aplicativos antes de continuar.
portuguese.FinishedLabel=A instalação do WinDeploy Studio no seu computador foi concluída com sucesso. O aplicativo pode ser iniciado selecionando os ícones instalados.

; ── 日本語メッセージ ──
japanese.WelcomeLabel1=WinDeploy Studio セットアップウィザードへようこそ
japanese.WelcomeLabel2=このプログラムは WinDeploy Studio %1 をお使いのコンピューターにインストールします。%n%nWinDeploy Studio は、起動可能USBドライブと Windows To Go ワークスペースを作成するための最新の Windows デプロイメントツールです。%n%n続行する前に、他のすべてのアプリケーションを閉じることをお勧めします。
japanese.FinishedLabel=WinDeploy Studio お使いのコンピューターへのインストールが正常に完了しました。インストールされたアイコンを選択してアプリケーションを起動できます。

; ── 繁體中文訊息 ──
chinesetraditional.WelcomeLabel1=歡迎使用 WinDeploy Studio 安裝精靈
chinesetraditional.WelcomeLabel2=安裝程式將在您的電腦上安裝 WinDeploy Studio %1。%n%nWinDeploy Studio 是一款現代化的 Windows 部署工具，用於建立開機碟和 Windows To Go 工作空間。%n%n建議您在繼續之前關閉所有其他應用程式。
chinesetraditional.FinishedLabel=安裝程式已成功將 WinDeploy Studio 安裝到您的電腦上。您可以透過選擇已安裝的圖示來啟動應用程式。

; ── Mensajes en español ──
spanish.WelcomeLabel1=Bienvenido al asistente de instalación de WinDeploy Studio
spanish.WelcomeLabel2=Este procedimiento instalará WinDeploy Studio %1 en su equipo.%n%nWinDeploy Studio es una herramienta moderna de despliegue de Windows para crear memorias USB booteables y espacios de trabajo Windows To Go.%n%nSe recomienda cerrar todas las demás aplicaciones antes de continuar.
spanish.FinishedLabel=La instalación de WinDeploy Studio en su equipo se ha completado correctamente. Puede iniciar la aplicación seleccionando los iconos instalados.

; ── رسائل عربية ──
arabic.WelcomeLabel1=مرحبًا بك في معالج تثبيت WinDeploy Studio
arabic.WelcomeLabel2=سيقوم هذا المثبت بتثبيت WinDeploy Studio %1 على جهازك.%n%nWinDeploy Studio هو أداة حديثة لنشر Windows لإنشاء أقراص USB قابلة للتشغيل وبيئات عمل Windows To Go.%n%nيُوصى بإغلاق جميع التطبيقات الأخرى قبل المتابعة.
arabic.FinishedLabel=تم تثبيت WinDeploy Studio على جهازك بنجاح. يمكنك تشغيل التطبيق من خلال اختيار الأيقونات المثبتة.

; ── 한국어 메시지 ──
korean.WelcomeLabel1=WinDeploy Studio 설치 마법사에 오신 것을 환영합니다
korean.WelcomeLabel2=이 프로그램은 WinDeploy Studio %1을(를) 컴퓨터에 설치합니다.%n%nWinDeploy Studio는 부팅 가능 USB 드라이브와 Windows To Go 작업 공간을 만들기 위한 최신 Windows 배포 도구입니다.%n%n계속하기 전에 다른 모든 애플리케이션을 닫는 것이 좋습니다.
korean.FinishedLabel=WinDeploy Studio가 컴퓨터에 성공적으로 설치되었습니다. 설치된 아이콘을 선택하여 애플리케이션을 시작할 수 있습니다.

; ── Deutsche Meldungen ──
german.WelcomeLabel1=Willkommen beim WinDeploy Studio-Installationsassistenten
german.WelcomeLabel2=Dies wird WinDeploy Studio %1 auf Ihrem Computer installieren.%n%nWinDeploy Studio ist ein modernes Windows-Bereitstellungstool zum Erstellen bootfähiger USB-Laufwerke und Windows To Go-Arbeitsbereiche.%n%nEs wird empfohlen, alle anderen Anwendungen zu schließen, bevor Sie fortfahren.
german.FinishedLabel=Die Installation von WinDeploy Studio auf Ihrem Computer wurde erfolgreich abgeschlossen. Die Anwendung kann über die installierten Symbole gestartet werden.
