<!-- wds:lang=en -->

# 🚀 WinDeploy Studio v2.1.0

> ⚡ **Major update:** a broad reliability, deployment-safety, storage-tools, AI,
> download, localization, and guided-experience release spanning the 2.0 series.

This is the first public feature release after v1.1.2. It brings together the
cumulative work completed across the 2.0 development series: safer deployment,
native storage tools, a redesigned interface, a guided first-run experience,
stronger downloads and updates, and complete 11-language coverage.

## ✨ Highlights

- 🧰 Separate Windows and Linux installation-media workflows with stronger ISO
  validation and disk safety checks.
- 🪟 A rebuilt Windows To Go workflow with direct, VHD, and VHDX deployment modes.
- 💾 Native drive benchmarks, saved history, cross-drive comparison, and localized
  CSV, JSON, and HTML reports with charts.
- 🛡️ Read-only disk diagnostics and guarded BCD/EFI boot repair.
- 🏠 A customizable Home dashboard, recent images, storage overview, and persistent
  operation status when navigating between pages.
- 🧭 A production App Tour that can be replayed completely or by section.
- 🌐 A redesigned bilingual project website and improved Image Library downloads.

## 💿 Installation Media

- Windows media now validates real Setup layouts, WIM/ESD/SWM metadata,
  BIOS/UEFI files, EFI architecture, FAT32 limits, and ISO mount results before
  the target disk is changed.
- Windows installation media supports UEFI + GPT, UEFI + MBR, and Legacy BIOS,
  with validated drive letters, volume labels, and custom icons.
- Linux media validates ISOHybrid structure, writes the ISO directly to the
  whole device, supports cancellation and disk recovery, and performs a full
  byte-for-byte verification after writing.
- Linux media preserves the distribution image's own partition and boot layout.
  It does not add persistence or convert its firmware support.
- New guidance explains why some firmware shows one Linux USB as multiple
  similar boot entries and how to choose the entry that opens the normal
  installer.

## 🪟 Windows To Go

- The new guided workflow covers image selection, disk selection, deployment
  mode, compatible options, confirmation, execution, and result reporting.
- Supports direct deployment and compatible dynamic/fixed VHD or VHDX modes,
  including virtual-disk BCD binding and optional drive-letter repair.
- Adds guarded controls for local-disk visibility, simplified first run, UASP,
  CompactOS, WIMBoot, .NET Framework 3.5, driver injection, and deployment
  letters. Unsupported combinations are blocked before writing.
- Progress and independent elapsed time survive page navigation. A draggable,
  collapsible status panel can return directly to the active workflow.
- Windows 10 and Windows 11 are the currently verified normal creation scope.
  Windows 7/8/8.1 and Server are best-effort and may require matching drivers,
  updates, firmware settings, or recovery tools.
- Portable Linux workspaces are planned for a future release and are not
  available now. Linux Installation Media remains available for bootable
  installer devices.

## 💾 Drive Testing And Disk Tools

- Native unbuffered, write-through benchmarks now cover sequential and 4K I/O,
  multithread scaling, mixed workloads, latency, cache behavior, and sustained
  full-drive writing through Quick, Standard, Extreme, and Full Write modes.
- Results are saved automatically and can be filtered, multi-selected, compared
  across different drives, deleted, or exported as localized CSV, JSON, and
  self-contained HTML reports with device identity, complete data, and charts.
- Disk Diagnostics reads available Windows storage, ATA SMART, NVMe health, and
  supported USB bridge data without modifying the device. Unsupported bridge
  fields remain clearly marked Unknown/N/A.
- BCD/EFI repair is limited to revalidated external non-system Windows disks and
  includes confirmation, backup, rollback, and verification.

## 🌐 Images, Downloads, AI, And Updates

- Home now includes recent images, storage overview, clear-history controls,
  and customizable/reorderable modules.
- Image Library adds clearer source and experience levels, language notices,
  local ISO discovery, published SHA-256/MD5 values, and silent known-image
  identification in supported creation workflows.
- Downloads support Microsoft official pages, 123 Cloud options for Chinese
  users, and managed Global Mirror transfers with destination selection,
  progress, cancellation, resume checks, and trusted HTTPS boundaries.
- AI Assistant now supports a provider-neutral custom OpenAI-compatible HTTPS
  endpoint, protected API key, and model selection. Streaming, tool calls,
  bounded web search, source filtering, Markdown, cancellation, and network
  handling have been strengthened.
- The built-in AI product guide reflects the current app, recommends relevant
  WinDeploy Studio workflows first, and does not claim unavailable features.
- Update checks use GitHub Release metadata with Global Mirror and GitHub
  download choices, bilingual release notes, SHA-256 and file-size validation,
  Authenticode status checks, and resilient download progress.

## 🧭 Experience, Localization, And Safety

- The production App Tour starts on first launch and after an app-version
  update, supports complete or single-section replay, and leaves time to use
  the real interface during each section.
- The responsive Windows 11-inspired interface, navigation, typography, card
  density, title bar, animations, narrow layouts, and waiting views have been
  refined throughout the application.
- All application and installer text covers 11 languages: Simplified Chinese,
  Traditional Chinese, English, French, German, Spanish, Portuguese, Russian,
  Arabic, Korean, and Japanese.
- Settings and genuine failed creation results can open the GitHub Issue form;
  no logs or private data are uploaded automatically.
- Deployment safety now includes physical-disk identity revalidation, per-disk
  locks, in-memory PowerShell, explicit Windows environments, bounded timeouts,
  cancellation, recovery, structured logs, and safer cleanup.
- The application requests administrator approval at startup so disk operations
  no longer depend on scattered elevation controls.

## ⚠️ Important Notes

- Installation Media and Windows To Go can erase the selected target disk.
  Verify the physical device and back up important data before continuing.
- Linux Installation Media writes ISOHybrid images as provided. Secure Boot and
  firmware compatibility depend on the selected distribution image and target
  computer.
- Image availability, licensing, language, and redistribution terms remain the
  responsibility of each image publisher and the user.

---

<!-- wds:lang=zh -->

# 🚀 WinDeploy Studio v2.1.0

> ⚡ **重大更新：** 汇总 2.0 系列在可靠性、部署安全、磁盘工具、AI、下载、
> 多语言和首次导览方面的大量改进。

这是继 v1.1.2 之后的首个公开功能版本，汇总了 2.0 开发阶段的大量更新：更安全的
系统部署、原生磁盘工具、重新设计的界面、正式版首次导览、更可靠的下载与更新，
以及完整的 11 语言支持。

## ✨ 主要更新

- 🧰 Windows 与 Linux 安装盘采用独立流程，并加入更完整的 ISO 校验和磁盘安全检查。
- 🪟 重做 Windows To Go，支持直接部署及兼容的 VHD、VHDX 部署方式。
- 💾 新增原生磁盘测试、测试历史、跨磁盘对比，以及带折线图的本地化报告导出。
- 🛡️ 新增只读磁盘诊断和受保护的 BCD/EFI 启动修复。
- 🏠 首页支持最近镜像、存储设备概览和模块自定义；切换页面后仍可查看正在进行的任务。
- 🧭 新增可完整回看或按栏目回看的正式版应用导览。
- 🌐 重做中英文项目网站，并完善镜像库下载体验。

## 💿 安装盘

- Windows 安装盘会在修改目标磁盘前检查标准 Setup 布局、WIM/ESD/SWM 元数据、
  BIOS/UEFI 启动文件、EFI 架构、FAT32 限制和 ISO 挂载结果。
- Windows 安装盘支持 UEFI + GPT、UEFI + MBR 和 Legacy BIOS，并会校验盘符、
  磁盘名称和自定义图标。
- Linux 安装盘会检查 ISOHybrid 结构，将镜像原样写入整个设备，支持取消与磁盘
  恢复，并在写入后执行完整的逐字节校验。
- Linux 安装盘保留发行版镜像自身的分区和启动结构，不会添加持久化，也不会转换
  镜像原有的固件启动能力。
- 新增通用提示，解释为什么部分固件会为同一个 Linux U 盘显示多个相近启动项，
  并指导用户选择能够进入正常安装界面的项目。

## 🪟 Windows To Go

- 新流程覆盖镜像、目标磁盘、部署方式、兼容选项、确认、执行和结果反馈。
- 支持直接部署及兼容的动态/固定 VHD、VHDX，并完善虚拟磁盘 BCD 绑定和盘符修复。
- 增加本地磁盘可见性、简化首次设置、UASP、CompactOS、WIMBoot、.NET Framework
  3.5、驱动注入和部署盘符等受保护选项；不兼容组合会在写入前阻止。
- 切换页面后仍会保留进度和独立计时；可拖动、可收起的全局状态面板可以直接返回
  正在执行的功能。
- 当前经过正常制作验证的范围为 Windows 10 和 Windows 11。Windows 7/8/8.1
  与 Server 属于尽力支持，可能需要匹配的驱动、补丁、固件设置或修复工具。
- Linux 便携工作环境计划在未来版本中提供，当前暂不可用；Linux 安装盘仍可用于
  创建可启动安装设备。

## 💾 磁盘测试与磁盘工具

- 原生无缓冲、写穿透测试现已覆盖顺序与 4K I/O、多线程扩展、混合负载、延迟、
  缓存行为和全盘持续写入，并提供快速、标准、极限和全盘写入模式。
- 测试结果会自动保存，可按日期筛选、多选、跨不同磁盘对比、删除，并可导出为
  本地化 CSV、JSON 或独立 HTML 报告；HTML 包含设备身份、完整数据和折线图。
- 磁盘诊断以只读方式获取 Windows 存储、ATA SMART、NVMe 健康信息及受支持的
  USB 桥接数据；控制器无法提供的字段会明确显示为未知或 N/A。
- BCD/EFI 修复仅用于重新核验过的外接非系统 Windows 磁盘，并包含确认、备份、
  回滚和修复后验证。

## 🌐 镜像、下载、AI 与更新

- 首页新增最近镜像、存储设备概览、清除历史和可显示/隐藏、重新排序的模块。
- 镜像库增加更清晰的来源与使用等级、语言提示、本地 ISO 搜索、已发布的
  SHA-256/MD5，以及安装盘和 Windows To Go 中的静默已知镜像识别。
- 下载支持 Microsoft 官方页面、面向中文用户的 123 云盘，以及带保存位置选择、
  进度、取消、续传检查和 HTTPS 信任边界的 Global Mirror 下载。
- AI 助手支持通用 OpenAI 兼容 HTTPS 地址、受保护的 API Key 和模型选择，并改进
  流式响应、工具调用、受限联网搜索、来源过滤、Markdown、取消和网络兼容性。
- 内置 AI 已按应用当前功能更新，会优先推荐对应的 WinDeploy Studio 流程，并且
  不会把尚未提供的功能描述为可用。
- 更新检查使用 GitHub Release 元数据，提供 Global Mirror 与 GitHub 两种下载方式，
  支持中英文更新说明、SHA-256 与文件大小校验、Authenticode 状态检查和可靠进度。

## 🧭 体验、多语言与安全

- 正式版应用导览会在首次打开及应用版本更新后启动，可回看完整导览或单独栏目，
  并允许用户在每个栏目中实际体验界面。
- 全面优化 Windows 11 风格的响应式界面、导航、字体、卡片密度、标题栏、动画、
  窄屏布局和长时间操作等待界面。
- 应用和安装器完整覆盖 11 种语言：简体中文、繁体中文、英语、法语、德语、
  西班牙语、葡萄牙语、俄语、阿拉伯语、韩语和日语。
- 设置和确实失败的制作结果可直接打开 GitHub Issue 页面；应用不会自动上传日志
  或隐私数据。
- 部署安全新增物理磁盘身份复核、单磁盘操作锁、内存 PowerShell、明确的 Windows
  系统环境、受控超时、取消、恢复、结构化日志和更安全的清理流程。
- 应用会在启动时统一申请管理员权限，磁盘操作不再依赖分散的提权按钮。

## ⚠️ 重要说明

- 安装盘和 Windows To Go 会清除所选目标磁盘，请确认物理设备并提前备份重要数据。
- Linux 安装盘按发行版提供的 ISOHybrid 镜像原样写入；Secure Boot 和固件兼容性
  取决于所选镜像及目标电脑。
- 镜像的可用性、许可证、语言及再分发条款仍由镜像发布者和用户自行确认。
