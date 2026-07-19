# WinDeploy Studio 维护交接文档

最后核对：2026-07-19
版本：2.1.0
工作区：`D:\Dev\WinDeployStudio`
目标：Windows 10/11 x64 主机

本文只记录源码和配置中能够核实的事实。本轮没有修改业务代码、没有构建、没有提交或推送。任何涉及磁盘写入、启动文件、分区或镜像部署的修改，都必须以源码、日志和真机测试为准。

## 1. 维护边界

- Windows 安装盘、Linux 安装盘、Windows To Go（WTG）和 Linux To Go（LTG）是四条独立流程。
- 除 Windows/Linux 安装盘和 Windows/Linux To Go 外，其余功能已由用户完成当前轮验证并作为封存基线。后续验证与修复应优先限制在安装盘和 To Go 独立实现内；如确需修改公共底层，必须完整回归已封存模块，不能假设行为等价。
- 不为 Clash 或其他特定代理软件加入专用分支。AI 网络必须按通用 HTTPS、系统代理/PAC、环境变量和直连路径处理。
- 本文件中的“已实现”不等于“已通过所有硬件真机验证”。发布前应按第 12 节矩阵逐项验证。

## 2. 工作区与 Git

`D:\Dev\WinDeployStudio\.git` 当前是空目录，缺少 `HEAD`、`config` 和对象数据库，因此不是可用 Git 工作树。不要在 Dev 目录执行 `git init`、删除 `.git`、强制重置或覆盖用户改动。

本次只读核对确认 `D:\WinDeployStudio` 才是有效 Git 工作树：审计时位于 `main...origin/main`，`HEAD` 为 `f22159d`（`feat: improve AI configuration and benchmark history`），远端为 `https://github.com/intelfans/WinDeployStudio.git`。这只说明该仓库当时干净可用，**不说明它与 Dev 目录内容一致**；尚未进行两目录的逐文件比较。任何同步应先生成可审计差异清单，保留目标目录独立改动，并只在有效工作树中提交和推送。

## 3. 架构地图

| 路径 | 职责 |
| --- | --- |
| `lib/main.dart` | 普通入口和提权任务入口 |
| `lib/app/` | 应用根组件、路由、主题、部署任务界面 |
| `lib/core/localization/` | 11 种语言及部署扩展文案 |
| `lib/core/services/bootable_usb_service.dart` | Windows/Linux 安装盘写入和校验 |
| `lib/core/services/wtg_service.dart` | WTG 分区、部署、BCD、二次 ISO 预检和执行后验证 |
| `lib/core/services/linux_driver_staging_service.dart` | 受支持 LTG 的载荷暂存与校验 |
| `lib/core/services/linux_togo_image_preflight.dart` | LTG 结构识别、二次预检和源文件清单 |
| `lib/core/services/linux_media_preflight.dart` | Linux 安装盘 ISOHybrid/启动结构预检 |
| `lib/core/services/wim_info_service.dart` | WIM/ESD 元数据 helper 调用 |
| `lib/core/services/disk_safety_service.dart` | 外接盘筛选、物理身份确认和互斥 |
| `lib/core/services/known_iso_verification_service.dart` | 已知 ISO 的 SHA-256/MD5 静默识别 |
| `lib/core/services/global_mirror_download_resolver.dart` | Global Mirror HTTPS 主机与重定向白名单 |
| `lib/features/benchmark*` | 原生磁盘测试、历史、比较和导出 |
| `lib/features/disk_tools/` | 只读诊断和外接盘启动修复 |
| `lib/features/ai_assistant/` | 通用 OpenAI 兼容接口、隐私确认和 DPAPI |
| `lib/features/update/` | GitHub Release 检查、下载和安装校验 |
| `data/mirrors.json` | 镜像、语言、大小和已知哈希 |
| `windows/*_helper/` | WIM 元数据、磁盘测试、只读诊断原生 helper；Arch COW helper 目前未接入发布构建 |

主程序 manifest 使用 `requireAdministrator` 和 `PerMonitorV2`；取消 UAC 时主程序不会继续运行。

## 4. 版本与构建

版本变更至少核对：`pubspec.yaml`、`lib/core/constants/app_constants.dart`、`windows/runner/Runner.rc`、`installer/windows/WinDeployStudio.iss`、`scripts/build_installer.ps1`、README 徽章和 `CHANGELOG.md`。本次核对它们均为 `2.1.0`。本机可用工具版本为 Flutter `3.44.4 stable` / Dart `3.12.2`。

Release（不生成安装包）：

```powershell
.\scripts\build_windows.ps1
```

安装包：

```powershell
.\scripts\build_installer.ps1
```

Release 产物必须包含主 exe、`wds_benchmark_helper.exe`、`wds_wim_info_helper.exe`、`wds_disk_diagnostics_helper.exe`、`tools\ext4-builder\wds_ext4_builder.exe` 及其源码/许可证、Flutter 运行库、插件 DLL 和 `data\flutter_assets`。`windows/CMakeLists.txt` 会复制 `tools`，并显式排除 GPL `tools\e2fsprogs` 的 `mke2fs.exe`/DLL；不得将无关缓存、旧安装包或被排除的二进制重新放入发布目录。

`scripts\build_windows.ps1` 的顺序为 NuGet -> `flutter pub get` -> `flutter analyze --no-fatal-infos` -> `flutter build windows --release`，输出 `build\windows\x64\runner\Release\win_deploy_studio.exe`。`scripts\build_installer.ps1` 会先递归删除该 Release 目录和 `dist\windows`，再构建并调用 Inno Setup；不得把它当作非破坏性构建命令。审计时 `dist\windows` 为空；Release 目录存在，但其中 `data\app.so` 的生成时间早于最后的 AI 源文件改动，因此该目录不能作为“包含最新源码”的交付证据，修改后必须重新构建和测试。

## 5. 镜像、下载与更新

- `data/mirrors.json` 是镜像名称、语言、大小、下载地址和 SHA-256/MD5 的唯一数据源；原版镜像大小可留空并按实际下载结果处理。
- 官方 Windows 镜像通过 Microsoft 官方页面打开；社区/LTSC 镜像通过应用内 WebView/下载器处理。下载器只允许 HTTPS、可信主机和受控重定向，保留续传、长度和哈希校验。
- GitHub Release REST 是主元数据，Atom 为 GitHub 回退，SourceForge RSS/README 为第二元数据回退；更新说明按 `---` 分隔中文和英文，中文显示中文段，其他语言显示英文段。
- 下载源可选 SourceForge（默认）与 GitHub。SourceForge 文件在安装前仍需用 GitHub Release 中同一资产的长度和 SHA-256 绑定；SHA-256/长度是硬性完整性门槛。Authenticode 和发布者状态目前只写入诊断日志，**未签名或非受信发布者不会在已通过 Release SHA-256 时阻止安装**，不得在 UI/文档中把它写成强制阻断。
- 失败、取消和半成品更新必须关闭流并清理临时文件。任何网络源不可用都应给出可解释的错误，不伪造成功。

## 6. Windows/Linux 安装盘

Windows 安装盘解析 ISO/WIM/ESD、选择版本、分区、复制文件、写入 BCD 并进行完成验证；支持 UEFI+GPT、UEFI+MBR 和 Legacy BIOS。Linux 安装盘仅对通过 ISOHybrid/启动结构预检的镜像执行原始写入，并在完成后逐块比较 ISO 内容。两条流程都必须在清盘前重新确认物理磁盘身份、容量、型号和总线类型。

不要把 To Go 的选项验证或失败提示复制到安装盘路径；公共磁盘安全服务变更后必须同时做安装盘回归。

## 7. WTG 兼容性与选项

WTG 在清盘前会重新挂载 ISO、读取 WIM/ESD 元数据、重新计算有效计划、验证源盘不等于目标盘，并再次验证目标物理磁盘身份。它接受 `install.wim`/`install.esd`，明确拒绝分卷 `install.swm`。当前代码路径覆盖 Direct、VHD、VHDX 和 UEFI+GPT、UEFI+MBR、Legacy BIOS，但“覆盖”不代表每种系统、固件、USB 桥接器均已实机验证。

| 项目 | 当前代码规则 | 维护要求 |
| --- | --- | --- |
| Windows 7 | 禁止 VHDX；x86 仅 Legacy BIOS；客户端原生 VHD 仅 Enterprise/Ultimate | 用真实 ISO 验证版本元数据和三种启动组合；不要把 Win7 的限制泛化到较新系统 |
| Windows 8/8.1 | WIM 元数据路径会识别；WIMBoot 仅 8.1 客户端、Direct，且必须使用 `install.wim` | WIMBoot 必须验证持久源复制、启动和重启，不能只以 DISM 成功作为完成 |
| Windows 10/11 | CompactOS 仅允许客户端 10/11；ARM64 仅 UEFI+GPT | CompactOS 要单独覆盖启动、性能和空间回归，不与其他高级项一起默认放行 |
| Windows Server | 从 `InstallationType`/Edition/名称识别；客户端专属 CompactOS/WIMBoot 会被排除 | 支持边界以实际 WIM 元数据为准，尚未完成完整 Server 真机矩阵 |
| VHD/VHDX | 虚拟磁盘最小 32 GB；文件名和扩展名受校验 | Direct、VHD、VHDX 必须分别验证分区、BCD、首启和断电恢复 |
| .NET 3.5 | 只在 `sources\sxs` 内存在已验证 NetFx3 负载时继续，否则在写盘前失败 | 不得将“可选 .NET”宣传为在线下载或适用于任何 ISO |
| 跳过 OOBE | 离线 unattended 配置仅隐藏一部分首次设置页面，并有离线验证路径 | 不承诺跳过全部 OOBE，也不进入 Audit Mode；文案必须使用“简化首次设置/隐藏部分页面”这一边界 |
| 禁用 WinRE | **WTG 兼容层直接报 `offline_winre_unsupported` 并拒绝计划**；服务层若被直接调用也只记录“保留 WinRE” | 这不是可用优化项。UI 必须默认关闭并说明离线部署不支持，不能在发布说明中写成已实现 |
| 禁用 UASP | 属于离线注册表/配置路径，需要执行后验证 | 可能影响 USB 3 性能和设备兼容性；只在明确故障排查场景使用，需做桥接器回归 |
| SAN / 本地盘隔离 | 默认 `blockLocalDisks`，离线 SAN Policy 使用 4；关闭时使用 1 | 开启/关闭都应在首启后验证本机盘可见性，避免本地盘误挂载或不可见 |

高级项失败必须带出具体选项、镜像版本、架构、启动模式、DISM/PowerShell/helper 输出和目标盘身份快照。不得为了绕过兼容层而修改 Windows 安装盘专区；安装盘与 To Go 是独立流程。

## 8. LTG 支持范围

LTG 不是任意 Linux 发行版转换器。当前实际创建入口只接入 x64 Ubuntu/casper、Debian Live/Kali，以及经过严格布局检查的 Deepin Live；其他发行版应使用 Linux 安装盘原始写入。Arch、openSUSE/KIWI 目前只有独立预检/实验代码和测试，未接入 LTG 创建入口，`wds_arch_cow_helper.exe` 也未接入 Windows 构建，因此不得宣传为支持 Arch 或 KIWI。实验性 ext4 helper 仅允许受限参数，必须随源码、许可证和哈希发布。首次和二次启动持久化仍是发布门槛，不能宣传为已支持所有发行版或任意驱动注入。

## 9. 磁盘测试与磁盘工具

原生测试 helper 使用无缓冲/写穿透模式；Full Write 会覆盖目标卷的可用空间（保留空间后），必须明确提示。历史支持多选、跨磁盘比较、范围/全部删除及 CSV/JSON/HTML 导出；跨盘比较仍要求协议、模式和测试参数一致。诊断启动 `wds_disk_diagnostics_helper.exe --inventory`，Flutter 层总超时为 24 秒，helper 还为每块盘隔离 worker 并设单盘/总量时限。它可利用 Windows Storage、NVMe、ATA SMART/SAT、Intel RST/VROC、JMicron/Realtek USB-NVMe bridge 及部分 USB-ATA bridge 路径；桥接器或驱动未暴露数据时显示“不可用”，不得猜测健康度。启动修复仅面向外接、在线、非系统磁盘，必须备份 BCD、二次核验并验证结果。

## 10. AI 与网络

AI 是通用 OpenAI 兼容 HTTPS 服务：支持端点、API Key、模型配置及 `/chat/completions`、`/responses`、`/models`。内置端点默认不接收用户 API Key；只有用户配置的 HTTPS 端点可保存 Key。Key 以 Windows DPAPI CurrentUser 加密并与端点绑定；切换或重置端点会清理旧 Key 和模型。连接路径应依次考虑环境代理/`NO_PROXY`、Windows 系统代理/PAC/WPAD 和直连，不得硬编码某个代理软件或第三方服务。

Cloudflare Worker 若先 `await response.text()` 再返回，会缓冲上游响应，可能造成流式输出延迟或超时；这是部署端风险，不能仅靠客户端重试掩盖。AI、日志、ISO/USB 分析发送前必须取得隐私确认，且不发送 USB 序列号和完整本地路径。

## 11. 本地化与文档

支持 `zh`、`zh_TW`、`en`、`fr`、`de`、`es`、`pt`、`ru`、`ar`、`ko`、`ja`。新增 UI 键必须同步基础和部署扩展表；缺失键显示该语言的缺失提示，不回退成英文。中文专属字体包、StarValleyX 等功能由资源/路由门控，不由翻译键决定。README、`THIRD_PARTY_NOTICES.md` 和安装器文案必须与实际支持范围一致，并提供中英双语许可证说明。

## 12. 日志、验证与发布检查

日志目录为 `%APPDATA%\WinDeployStudio\logs`。每次部署失败先保留任务日志、PowerShell/helper 输出和目标盘身份快照，再判断是镜像、分区、权限、文件系统、启动模式还是设备 I/O 问题。先复制出需要的日志，再讨论清理构建、缓存或临时文件；当前 `.gitignore` 只明确忽略 `.dart_tool/`、`build/` 和 `dist/`，并不自动证明 `build_ninja/`、`build_rebuild/`、根构建日志、`.exe` 或 `.pdb` 是无用文件。

发布前至少验证：Windows 7/8/8.1/10/11 及 Server 镜像识别；UEFI+GPT、UEFI+MBR、Legacy；NTFS/exFAT 目标限制；CompactOS、.NET、简化 OOBE、UASP、SAN 各组合；WinRE 选项保持不可选/被明确拒绝；Tiny/官方 WIM/ESD；Ubuntu、Debian/Kali、Deepin LTG 预检；USB 桥接器诊断；代理开启/关闭时 AI；11 语言关键页面和下载/更新说明。

## 13. 当前待办与未闭环事项

状态定义：`待实现` 表示源码仍需修改；`待端到端验证` 表示局部代码和测试存在，但尚不能作为真实环境已解决；`发布阻塞` 表示未完成前不应对外宣称功能稳定。

| 优先级 | 状态 | 事项 | 完成标准 |
| --- | --- | --- | --- |
| P0 | 待端到端验证 / 发布阻塞 | AI 在代理开启、代理关闭、系统代理残留、PAC/WPAD、环境代理和纯直连网络间切换时仍可能间歇失败 | 在同一安装包中连续切换网络路径，默认端点和自定义 OpenAI 兼容端点均完成多轮对话；失败日志能区分 DNS、TCP、TLS、代理、HTTP、协议和上游超时；不得加入特定代理软件分支 |
| P0 | 待实现并验证 | 默认 Cloudflare Worker/上游的流式转发尚未闭环 | Worker 直接透传上游状态码、响应头和流，不使用 `await response.text()` 缓冲完整响应；客户端分别验证 SSE、普通 JSON、非流式回退、取消和空响应 |
| P0 | 待端到端验证 | OpenAI 兼容协议覆盖仍不完整 | 使用真实服务分别验证 `/chat/completions` 流式/非流式、`/responses`、`/models`、标准 tool calls、原始 `<tool_call>` 兼容输出、2xx 非 200 状态和结构化错误；不支持的可选协议应自动回退且不重复探测 |
| P0 | 待端到端验证 | 联网搜索的真实性和失败语义 | Auto/Force/Off 三种模式分别验证原生 Responses 搜索、function tool 两轮调用、Bing RSS/DuckDuckGo 公共回退；只有确实取得结果时显示“已使用联网搜索”，失败不得阻断普通问答或伪造引用 |
| P1 | 源码已修复 / 待端到端验证 | AI 来源过滤和输出格式清洗 | 已拒绝搜索引擎根主页、搜索入口和常见重定向地址；仍需验证真实 Bing/DuckDuckGo/兼容服务返回的来源不会出现通用搜索主页，并继续验证分块 SSE 跨 chunk 的 `<br>`、转义 `&lt;br&gt;`、Markdown 表格、代码块、原始工具标签和多语言文本 |
| P1 | 待端到端验证 | AI 配置、密钥和模型生命周期 | 验证默认端点不接收用户 API Key；自定义端点的密钥使用 DPAPI CurrentUser 并绑定端点；切换/重置端点清除旧密钥与模型；`/models` 超时、空列表和异常结构有本地化提示 |
| P1 | 待实现或补测 | AI 可观测性与隐私审计 | 日志仅记录默认/自定义端点类别、协议、路由来源和错误分类，不记录 API Key、完整用户内容、USB 序列号、私有路径或完整自定义域名；为日志脱敏和取消请求补测试 |

本轮运行 `ai_service_protocol_compatibility_test.dart`、`ai_service_error_test.dart`、`chat_content_normalizer_test.dart` 和 `ai_system_proxy_resolver_test.dart` 共 33 项通过；此前 `ai_config_test.dart` 等测试曾使局部总数达到 39 项。这些只能作为局部回归证据，不能关闭以上端到端待办。后续维护者应在实际变更后重新运行并记录命令、日期、环境和完整输出。

其他遗漏和发布前待办：

| 优先级 | 状态 | 事项 |
| --- | --- | --- |
| P0 | 发布阻塞 | Dev 目录不是可提交工作树；必须在 `D:\WinDeployStudio` 进行逐文件差异核对、同步、提交和推送，禁止初始化或重置 Dev 目录 |
| P0 | 待真机验证 | WTG 对 Windows 7/8/8.1/10/11/Server、三种启动模式、WIM/ESD、直接/VHD/VHDX 和高级选项组合的完整矩阵 |
| P0 | 待真机验证 | LTG 在 Ubuntu/casper、Debian/Kali、Deepin 上的首次启动、持久化写入、重启后二次读取和安全失败路径 |
| P0 | 待实现 | 将 Arch/openSUSE/KIWI 从“预检/实验代码”接入实际 LTG 创建、分区、启动参数、持久化和二次启动验证；在完成前保持 UI 明确拒绝，不得仅因预检测试通过就放行 |
| P0 | 待回归验证 | 公共磁盘服务或分区逻辑有变更时，Windows/Linux 安装盘必须单独真机回归；用户已确认的安装盘业务代码不得被 WTG/LTG 修复顺带改写 |
| P1 | 待真机验证 | USB-SATA/NVMe 桥接器诊断数据覆盖；桥接器不提供的数据继续显示“不可用” |
| P1 | 待发布验证 | GitHub/SourceForge 更新信息、双下载源选择、资产文件名、SHA-256、失败清理和安装流程；明确验证签名/发布者仅诊断记录，或另行实现并测试真正的阻断策略 |
| P1 | 待数据复核 | `data/mirrors.json` 的镜像语言、大小、下载地址和所有已知哈希应与实际发布文件重新计算比对 |
| P1 | 待界面回归 | 11 种语言下的关键页面、RTL、长文本、下载/更新说明、错误信息和窄屏布局；不得只依靠键完整性测试 |
| P2 | 待发布整理 | 清理旧构建和缓存前先确认没有诊断价值；核对 README、第三方声明、安装器文案和网站与 2.1.0 实际功能一致 |

## 14. 禁止操作

- 不在未确认物理身份的磁盘上清盘或分区。
- 不绕过 HTTPS/主机白名单、长度和 Release SHA-256 校验；不得把当前仅诊断的 Authenticode/发布者状态伪装成阻断校验。
- 不把实验性 LTG 或未真机验证功能写成普遍支持。
- 不删除用户已有改动、构建日志或许可证文件来“清理”问题。
- 不在 Dev 工作区直接初始化或重置 Git 仓库。
