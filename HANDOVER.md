# WinDeploy Studio 交接文档

最后更新：2026-07-12  
当前版本：2.0.0  
目标平台：Windows 10/11 x64  
主工作区：`D:\Dev\WinDeployStudio`

本文档记录当前代码的真实状态。维护时仍应以源码、数据文件和实际构建结果为准，不要仅凭本文件推断磁盘写入行为。

## 1. 技术栈

| 项目 | 当前状态 |
| --- | --- |
| Flutter / Dart | Flutter 3.44.4 stable / Dart 3.12.2 |
| UI | Material 3 |
| 状态管理 | Riverpod 3 |
| 路由 | GoRouter 17 |
| 本地偏好 | `shared_preferences` |
| HTTP | `http` |
| WebView | `webview_windows` |
| Markdown | `flutter_markdown_plus` |
| WIM 元数据 | 原生 `wds_wim_info_helper.exe` + WIMGAPI + `xml` |
| 磁盘测试 | 原生 `wds_benchmark_helper.exe` |
| 磁盘诊断 | 原生只读 `wds_disk_diagnostics_helper.exe` + Windows Storage API |

主程序 manifest 为 `asInvoker`。只有清盘、分区、写镜像和启动配置等高权限任务会启动独立 UAC 子进程；AI、设置、WebView 和普通 UI 不在管理员进程中运行。

当前工作区不是 Git 仓库。用于发布的 Git 仓库位于 `D:\WinDeployStudio`，同步前必须保留用户在该目录中的独立改动。

## 2. 版本位置

发布版本必须同步检查：

| 文件 | 当前值 |
| --- | --- |
| `pubspec.yaml` | `2.0.0` |
| `lib/core/constants/app_constants.dart` | `2.0.0` |
| `windows/runner/Runner.rc` | `2.0.0` / `2,0,0,0` |
| `installer/windows/WinDeployStudio.iss` | `2.0.0` / `2.0.0.0` |
| `scripts/build_installer.ps1` | `WinDeployStudio_Setup_2.0.0.exe` |
| `README.md` | 版本徽章 `2.0.0` |

## 3. 目录与入口

| 路径 | 作用 |
| --- | --- |
| `lib/main.dart` | 普通主程序和提权任务模式入口 |
| `lib/app/app.dart` | 应用根组件、主题、首次语言选择 |
| `lib/app/routes.dart` | 10 个主页面与镜像详情路由 |
| `lib/app/elevated_task_app.dart` | UAC 子进程任务界面 |
| `lib/app/visual_style.dart` | 固定 Windows 11 风格的外观设置与原生标题栏同步 |
| `lib/core/localization/strings.dart`、`deployment_strings.dart` | 11 种界面语言，基础与部署扩展键显式合并 |
| `lib/core/services/disk_safety_service.dart` | 磁盘枚举、外接盘过滤与清盘前身份核验 |
| `lib/core/services/bootable_usb_service.dart` | Windows/Linux 安装盘与持久化 LTG |
| `lib/core/services/wtg_service.dart` | Windows To Go 部署、分区、BCD 与验证 |
| `lib/core/services/linux_driver_staging_service.dart` | 受支持 LTG 的 Linux 首次启动载荷暂存与校验 |
| `lib/core/services/elevation_service.dart` | UAC 子进程启动和进度桥接 |
| `lib/core/services/wim_info_service.dart` | 调用 WIM 原生 helper 并解析 XML |
| `lib/features/benchmark/` | 原生磁盘测试、评级与折线图 |
| `lib/features/benchmark_history/` | 测试历史、详情、比较与 CSV/JSON 导出 |
| `lib/features/creator/` | Windows/Linux 安装盘 UI |
| `lib/features/deployment/` | 部署计划、兼容性矩阵与离线 Windows 策略 |
| `lib/features/disk_tools/` | 只读磁盘诊断与外接盘启动修复 |
| `lib/features/wtg/` | Windows/Linux To Go UI |
| `lib/features/mirror/` | 镜像中心 |
| `lib/features/ai_assistant/` | AI、隐私确认与加密会话 |
| `lib/features/logs/` | 日志中心 |
| `lib/features/tools/` | 工具箱和安全提示 |
| `lib/features/update/` | GitHub 更新检查、下载与安装 |
| `lib/shared/widgets/deployment_shell/` | 响应式多层部署导航与共享控件 |
| `lib/shared/webview/` | WebView2 和断点下载 |
| `windows/benchmark_helper/main.cpp` | 无缓冲、写穿透磁盘测试 helper |
| `windows/disk_diagnostics_helper/main.cpp` | 只读 NVMe 健康查询 helper |
| `windows/wim_info_helper/main.cpp` | WIMGAPI 只读元数据 helper |
| `data/mirrors.json` | 12 个镜像中心资源 |
| `data/tools.json` | 27 个工具、9 个分类 |

## 4. 已实现功能

### 安装盘

- Windows 安装盘：解析 ISO、选择版本、分区、复制文件并写启动文件。
- Windows 安装盘可选择 UEFI + GPT、UEFI + MBR、Legacy BIOS，支持 D: 到 Z: 的目标分区盘符及自定义卷标/ICO 图标。
- Linux 安装盘：支持可启动 ISOHybrid 原始写入，清盘前验证 ISOHybrid 结构。
- 目标盘必须是已验证的 USB、SD、MMC 或系统报告为 removable 的外接磁盘。
- 清盘前重新核验磁盘号、容量、型号和总线类型，并按“可靠序列号、设备路径、UniqueId”的顺序确认物理身份；缺少可靠身份时拒绝清盘。
- 安装盘、To Go 与磁盘测试使用按物理磁盘号加锁的跨进程互斥，同一块盘不能被多个任务并发操作。
- Linux 原始写入完成后逐块比较完整 ISO 内容，不只检查文件头。

### To Go

- Windows To Go 使用镜像、磁盘、部署方式、高级选项、配置摘要五步流程；摘要明确显示镜像、目标盘、启动模式、部署方式、驱动目录和已启用策略。
- 启动布局可选 UEFI + GPT、UEFI + MBR、Legacy BIOS；Windows 可直接部署，也可部署到动态/固定 VHD 或 VHDX。Windows 7 禁止 VHDX，x86 Windows 7 仅允许 Legacy BIOS。
- 兼容性校验会阻止无效组合：安装盘和 Linux 只允许直接部署；Windows 7 禁止 VHDX，且原生 VHD 仅限 Enterprise/Ultimate；WIMBoot 仅限 Windows 8.1 直接部署；CompactOS 仅限 Windows 10/11；虚拟磁盘不得小于 32 GB。
- 本地磁盘 SAN policy、启动到 Audit 模式（跳过 OOBE）、禁用 WinRE、禁用 UASP、CompactOS、WIMBoot、VHD/VHDX 启动后盘符修复和 .NET Framework 3.5 均为可配置项，服务侧执行后会验证。UEFI 模式自动采用 NTFS Windows 卷与独立 FAT32 EFI 分区，不提供无实际差异的开关。
- Windows 可从所选目录离线注入 INF 驱动；可选择系统/启动分区盘符、自定义卷标和 ICO 图标。
- 启动分区与 Windows 存储必须保持独立；BCD、默认设备、虚拟磁盘绑定和 UEFI fallback 文件均会验证。
- Linux To Go：只支持 x64 Ubuntu 或兼容的 casper Live ISO。
- LTG 使用独立 FAT32 启动/持久化分区与 NTFS Live 数据分区。GRUB 会加入 `persistent` 和明确的 `live-media` 参数，现代 Ubuntu 中超过 4 GiB 的 squashfs 层存放在 NTFS，最大约 4 GB 的 ext4 `writable` 持久化镜像存放在 FAT32。
- 受支持 LTG 可选暂存 `.deb`/`.rpm`/Arch 包、匹配运行内核的 `.ko`/`.ko.xz` 模块或显式 `.sh` 脚本，并通过 manifest、SHA-256、casper hook 和一次性 systemd 服务在首次启动处理；这不会扩大 LTG 发行版范围。
- 不支持的发行版会在清盘前拒绝；其他 Linux 发行版可使用“安装盘”原始写入模式。
- To Go UI 只显示可靠的已用时间，并提供不影响部署进程的等待小游戏。

### 原生磁盘测试

- 模式：Quick、Standard、Extreme、Full Write。
- 测试：顺序读写、4K 随机读写、真实多线程扩展、混合读写场景、延迟分位数、缓存拐点/稳定速度和可选全盘写入。
- helper 使用 `FILE_FLAG_NO_BUFFERING` 与 `FILE_FLAG_WRITE_THROUGH`。
- UI 提供全过程折线图、综合分数、实用等级、关键原因和未运行测试说明。
- 成功结果自动写入本地 JSON 历史；支持详情曲线、日期筛选、两条记录比较、单条/范围/全部删除，以及 CSV/JSON 导出。
- 临时目录带随机所有权标记，仅删除当前测试创建的文件；成功、取消和失败都会清理。

### 磁盘工具与信息架构

- 主导航现有 10 个页面，新增“磁盘工具”；Windows To Go 使用响应式 `DeploymentShell` 二级导航，宽屏显示侧栏，窄屏显示横向步骤条。
- 应用在受支持的 Windows 10/11 主机上统一使用 Windows 11 风格；Flutter 主题、原生标题栏和部署导航保持同步，不再提供 Win10/Win7/自动外观选项。
- 磁盘诊断只读收集 CIM、Storage Reliability Counter 与 NVMe helper 数据；健康、温度、寿命、磨损等未由设备或驱动提供时必须显示“不可用”，不能推测。
- 启动修复只发现外接、在线、非系统、非启动磁盘上的 Windows；预检绑定物理身份与分区，要求复核摘要并输入 `REPAIR`，提权后再次校验，不执行格式化。
- 修复会锁定目标物理盘、备份现有 BCD、调用系统 `bcdboot`、补齐 UEFI fallback（如适用），验证 BCD/启动管理器后写技术日志，并移除临时盘符。

## 5. 镜像中心

当前共 12 个条目：

| 分类 | 条目 |
| --- | --- |
| Official Microsoft Images | `official-win10`, `official-win11` |
| Community Editions | `tiny10`, `tiny11`, `xlite10`, `xlite11`, `starvalleyx` |
| Enterprise & LTSC Builds | 4 个 Windows 10/11 Enterprise / IoT LTSC 条目 |
| Tools | `font-pack` |

规则：

- Windows 10/11 官方条目只显示确认框，随后用系统浏览器打开 Microsoft 官方网站；不走 WebView 和镜像选择。
- 社区与 LTSC 条目保留 123 Cloud / GoFile 选择，并在 WebView2 中打开页面。
- StarValleyX 只在 `zh` 和 `zh_TW` 中显示；列表和 `/mirror/starvalleyx` 直达路由都受保护。
- CJK 字体包也只在 `zh` 和 `zh_TW` 中显示；非中文列表和 `/mirror/font-pack` 直达路由都受保护。
- Tiny10、Tiny11、Windows X-Lite 10/11 在中文详情页显示字体包提示。
- StarValleyX 明确不需要字体包，不能显示字体包提示。
- 首页字体包快捷卡片已删除，下载入口位于镜像中心。

日志格式包括：

```text
[OfficialDownload]
Product=Windows11
Source=Microsoft
Method=SystemBrowser
```

```text
[CommunityDownload]
Product=Tiny11
Mirror=123
```

## 6. 下载与更新

- WebView 下载支持基于 `Range` 的暂停/继续，并验证 ETag、Last-Modified、Content-Range 和最终长度。
- 用户确认的保存路径不会被服务器 `Content-Disposition` 改写。
- 下载失败、取消和异常路径会关闭流、文件句柄和 HTTP 客户端；失败的更新半成品会删除。
- 更新通道 Stable / Beta / Nightly 会按 GitHub Release 类型筛选。
- 更新下载仅允许 GitHub 与 GitHub Release 资源的 HTTPS 主机及受控重定向。
- 更新下载前重新读取指定标签的 GitHub Release 元数据；资产必须提供 GitHub 发布摘要与准确长度。
- 下载后重新计算 SHA-256，并同时验证 Authenticode `Status=Valid` 与允许的发布者 CN；任一验证失败都不会执行安装包。
- 未签名、签名无效、发布者不匹配或哈希不匹配的安装包不会自动执行。
- 更新按钮文案为“安装更新”；实际行为是关闭应用并启动安装器，不承诺无条件自动重启。
- 目前只有 GitHub 更新源；Oracle Cloud 更新源仍在未来规划中。

## 7. AI、隐私与日志

- AI 代理地址必须使用 HTTPS。
- 首次使用先显示 AI 内容免责声明；未确认前不会发送初始提示。
- 日志、ISO 或 USB 快捷分析会先说明数据将发送到远程服务并请求确认。
- USB 序列号和完整本地日志路径不会发送给 AI。
- 聊天会话使用 Windows DPAPI CurrentUser 加密；旧明文 JSON 会自动迁移。
- AI 超时可能来自本机网络、Worker、TLS 或上游 API，不能只按客户端代码问题处理。
- 日志按 30 天和每类最多 30 个文件清理。

## 8. 工具安全提示

- 工具共 27 个、9 个分类：Beginner 13、Advanced 11、Expert 3。
- Dism++、Windhawk 有专属 Advanced 提示。
- Expert 工具有通用专家提示。
- 激活相关工具使用统一的 Activation Tool Notice，并支持“不再显示”；HEU 不再叠加旧弹窗。
- 设置/关于页包含 MIT、项目仓库、免责声明和 Special Thanks。

## 9. 本地化硬约束

支持代码：`zh`, `zh_TW`, `en`, `fr`, `de`, `es`, `pt`, `ru`, `ar`, `ko`, `ja`。

- 基础表与部署扩展表的完整键集合由本地化契约测试动态校验；通用 UI 修改必须同步全部 11 种语言，部署、测试历史和磁盘工具文本主要位于 `deployment_strings.dart`。
- 字体包是否可见由资源和路由的中文语言门控决定，不由翻译键是否存在决定；只允许 `zh`、`zh_TW` 显示和进入字体包条目。
- 支持语言缺少键时返回该语言自己的 `translation_missing`，不能回退成英文或中文。
- `data/tools.json` 和 `data/mirrors.json` 对支持语言缺失字段时返回空值，不回退其他语言。
- 专有名词如 Windows、ISO、USB、Microsoft、WebView2、GoFile、PowerShell、DISM 可保留原文。
- 不允许普通 UI 出现原始 key、连续问号、Unicode replacement character 或其他语言的硬编码提示。
- 日志可使用稳定的英文结构化字段，避免本地化文本破坏机器检索。

## 10. 构建

PowerShell 7 推荐，但运行时仍调用系统 `powershell`，因为 Windows PowerShell 是受支持 Windows 的系统组件。所有脚本均显式传递参数和 UTF-8 数据，不依赖控制台代码页解析结构化结果。

NuGet 兜底：

- `scripts/ensure_nuget.ps1` 优先使用 PATH 中的 `nuget.exe`。
- 缺失时从 NuGet 官方地址下载并校验 Authenticode 签名。
- 本地副本保存在 `.tools/nuget/nuget.exe`，CMake 会显式使用该路径。

Release 构建（不生成安装包）：

```powershell
.\scripts\build_windows.ps1
```

安装包构建：

```powershell
.\scripts\build_installer.ps1
```

Release 目录必须至少包含：

- `win_deploy_studio.exe`
- `wds_benchmark_helper.exe`
- `wds_disk_diagnostics_helper.exe`
- `wds_wim_info_helper.exe`
- `tools\e2fsprogs\mke2fs.exe`
- `tools\e2fsprogs\README.md`
- Flutter DLL、插件 DLL 与 `data\flutter_assets`

## 11. 已知边界

| 项目 | 说明 |
| --- | --- |
| 更新签名 | 安全策略要求有效 Authenticode；发布流程必须给安装包签名，否则应用内安装会被拒绝 |
| Linux 安装盘范围 | 支持可启动 ISOHybrid 镜像的原始写入，不宣称任意 Linux ISO 都可直接启动 |
| LTG 范围 | 只支持 x64 Ubuntu / casper 持久化布局，不宣称支持所有 Linux 发行版 |
| LTG 首启载荷 | 只在上述受支持 LTG 中暂存受控 Linux 包、匹配内核模块或显式脚本，不等同于跨发行版驱动注入 |
| Windows 部署兼容性 | WIMBoot 仅限 Windows 8.1 直接部署；CompactOS 仅限 Windows 10/11；Windows 7 不支持 VHDX，原生 VHD 仅限 Enterprise/Ultimate，x86 Windows 7 仅支持 Legacy BIOS |
| NTFS UEFI | UEFI 模式自动使用 NTFS Windows 存储配合独立 FAT32 EFI 分区，不提供假开关，也不宣称固件可直接从任意 NTFS 卷启动 |
| 启动修复 | 只修改通过身份与分区复核的外接非系统磁盘，不格式化，但仍会改写 BCD 和启动文件，必须保留双重确认与备份 |
| 全盘测试 | 会覆盖目标卷可用空间并产生高写入量，必须保持明确警告和主动选择 |
| WebView 下载 | 第三方站点、Cloudflare 或区域网络变化仍可能影响页面和下载体验 |

## 12. 未来规划

原计划④-⑨中已经完成的策略、启动/部署模式、摘要流程、统一界面和分层导航已移入“已实现功能”。这里只保留真实未完成项：

- 将持久化 Linux To Go 扩展到 x64 Ubuntu / casper 兼容 Live 镜像之外；任意发行版 Linux To Go 尚未实现，不能在文档或安装器中作此承诺。
- 将离线 Windows 可选功能扩展到当前已实现的 .NET Framework 3.5 之外。原计划④中的“其他功能”仍属未来工作。
- 原计划⑩：加入更新源选择，甲骨文云为推荐高速源，GitHub Releases 为备用源；当前只有 GitHub 更新源。

## 13. 修改检查清单

- 磁盘：不得放宽外接盘过滤；清盘前必须复核物理身份。
- Windows To Go：EFI 与 Windows 分区必须独立；不能用“第一个盘符”或固定 `S:` / `W:`。
- 部署计划：兼容性错误必须在清盘前阻止；新增选项必须同时接入摘要、UAC 任务序列化、服务执行和执行后验证。
- Linux：安装盘先验 ISOHybrid；LTG 在清盘前检查 x64 casper 结构、可修改的 GRUB 启动项、内置 `mke2fs.exe`、FAT32 启动文件上限和目标磁盘空间。
- 磁盘工具：诊断保持只读；启动修复不得放宽外接非系统盘限制、双重确认、BCD 备份和执行后验证。
- 镜像：Official Microsoft 不进 WebView；StarValleyX 与字体包保持中文专属。
- 字体包：仅 Tiny / X-Lite 提示，StarValleyX 永不提示，首页不恢复快捷卡片。
- 本地化：通用 UI 同步 11 语；中文专属功能只在简繁中文保留键和数据。
- 安装器：11 种欢迎文案都应覆盖 Windows/Linux 安装盘、Windows To Go、受支持的 Ubuntu/casper Linux To Go 和原生磁盘测试，且不得暗示支持任意 LTG 发行版。
- 更新：不能绕过 HTTPS 主机限制、哈希、Authenticode 或发布者检查。
- 构建：静态分析后构建 Release，并确认三个 helper 与 `mke2fs.exe` 均在产物中。
