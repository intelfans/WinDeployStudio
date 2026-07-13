# WinDeploy Studio

Windows desktop toolkit for Windows/Linux installation media, portable To Go workspaces, native drive benchmarks, image resources, diagnostics, logs, and AI-assisted deployment help.

![Platform](https://img.shields.io/badge/Platform-Windows-blue?logo=windows)
![License](https://img.shields.io/badge/License-MIT-green)
![Flutter](https://img.shields.io/badge/Flutter-Windows-02569B?logo=flutter)
![Version](https://img.shields.io/badge/Version-2.0.0-orange)

## Overview

WinDeploy Studio is a Flutter-based Windows desktop app for practical Windows and Linux deployment workflows. It combines Windows installation media creation, Linux ISOHybrid writing, Windows To Go, persistent Linux To Go for x64 Ubuntu/casper-compatible Live images, native drive testing, trusted image source navigation, deployment utilities, logs, and clear safety notices for advanced tools.

The project is distributed under the MIT License.

## Highlights

- **Installation Media Creator**
  - Create Windows installation USB drives and write bootable Linux ISOHybrid images.
  - Parse Windows ISO images and list available editions.
  - Select UEFI + GPT, UEFI + MBR, or Legacy BIOS for Windows media, with a preferred partition drive letter and custom volume label/icon.
  - Validate Linux ISOHybrid images before erasing the target disk.
  - Bind every destructive operation to the selected external disk and revalidate it immediately before writing.

- **To Go Workspace Creator**
  - Create portable Windows To Go workspaces.
  - Create persistent Linux To Go workspaces from x64 Ubuntu and compatible casper-based Live ISOs.
  - Classify Linux To Go images when selected and again immediately before erasing the target. The accepted layout requires x64 UEFI, casper kernel/initrd and Live payloads, plus a GRUB entry that can safely receive the persistence arguments.
  - Recognize Debian Live separately and direct it to Linux installation media until its distinct persistence protocol is implemented; other unsupported distributions are never presented as compatible Linux To Go images.
  - Use a five-step image, disk, deployment, advanced-options, and summary workflow before execution.
  - Select UEFI + GPT, UEFI + MBR, or Legacy BIOS and deploy Windows directly or into dynamic/fixed VHD/VHDX files; incompatible image and mode combinations are blocked before writing.
  - Configure local-disk visibility, OOBE/Audit behavior, WinRE, UASP, CompactOS, WIMBoot, VHD/VHDX drive-letter repair, .NET Framework 3.5, and deployment drive letters where supported. UEFI deployments automatically use an NTFS Windows volume with a separate FAT32 EFI partition.
  - Optionally inject Windows INF drivers offline. Supported Ubuntu/casper Linux To Go images can stage vetted Linux packages, matching kernel modules, or explicit scripts for first boot; this does not add support for arbitrary distributions.
  - Build a separate Windows boot partition and verify BCD, virtual-disk binding, and fallback UEFI boot files.
  - Revalidate disk identity, capacity, model, and bus type before destructive operations, preferring a reliable hardware serial number and failing closed when no stable identity is available.
  - During image application, the progress panel shows reliable elapsed time only.
  - Includes a small UI-only waiting game during long image application steps.

- **Native Drive Benchmark**
  - Uses unbuffered, write-through native Windows I/O instead of cached file-copy estimates.
  - Measures sequential read/write, 4K random read/write, real multi-thread scaling, mixed workloads, latency percentiles, and optional full-write stability.
  - Provides Quick, Standard, Extreme, and Full Write modes with live line charts, cache-behavior analysis, and practical To Go suitability guidance.
  - Automatically saves successful results for detail review, date filtering, two-run comparison, deletion, and CSV/JSON export.
  - Lets users choose one or more saved records when asking the AI whether a USB is suitable for a To Go workspace; selected metrics and their meanings are sent as reviewable plain text.
  - When no saved record is selected, the AI request recommends a Standard disk test before reaching a confident To Go suitability conclusion.
  - Uses an ownership marker for temporary data and removes only files created by the current test.

- **Disk Tools**
  - Collect read-only disk identity, health, reliability, lifetime, temperature, wear, and NVMe telemetry through a bounded native helper. Slow or unsupported storage queries become explicit unavailable values or collection warnings instead of blocking the whole scan.
  - Runs the bounded native helper from the elevated application process, so an unresponsive device produces a bounded failure instead of leaving the diagnostic screen stuck.
  - Repair UEFI or BIOS boot files only on a revalidated external, non-system disk, with preflight checks, a typed confirmation, BCD backup, no formatting, post-repair verification, and technical logs.

- **Image Center**
  - Separates **Official Microsoft Images**, **Community Editions**, and **Enterprise & LTSC Builds**.
  - Official Windows 10 and Windows 11 entries open Microsoft's official download pages in the system browser.
  - Community images keep the existing mirror-based flow with China and Global mirror choices.
  - Enterprise and LTSC entries are marked as expert-level deployment resources with clear source and language notices.
  - StarValleyX is shown only for Simplified Chinese and Traditional Chinese UI languages.
  - The CJK font pack is also Chinese-only. It is offered for Tiny10, Tiny11, and Windows X-Lite, never for StarValleyX.

- **Toolbox**
  - Curated deployment, diagnostics, recovery, hardware, network, and optimization utilities.
  - Tool safety levels: Beginner, Advanced, and Expert.
  - Professional notices before opening advanced, expert, or activation-related utilities.
  - Includes Microsoft Sysinternals Suite.

- **AI Assistant**
  - Built-in AI assistant for Windows deployment questions, log analysis, and troubleshooting suggestions.
  - For USB suitability questions and USB analysis, users can select multiple saved disk-test records. The request includes device data, run parameters, workload measurements, raw sample points, and metric definitions in plain text.
  - Displays a clear AI-generated content notice before use.
  - Supports custom OpenAI-compatible proxy endpoints.

- **Log Center**
  - Centralized logs for installation media creation, To Go workspaces, image operations, downloads, updates, AI, and errors.
  - Quick log browsing and folder access.

- **Windows 11 Interface And Navigation**
  - Uses one consistent Windows 11-inspired interface across supported Windows 10 and Windows 11 hosts.
  - Keeps the Flutter theme, native title bar, and responsive deployment navigation visually aligned without exposing redundant style selectors.
  - Groups primary navigation with clear visual dividers; choosing a primary destination from Disk Tools or test-history secondary pages opens that destination rather than retaining the previous subpage.

- **International UI**
  - Supports 11 languages:
    - Simplified Chinese
    - Traditional Chinese
    - English
    - Japanese
    - Korean
    - German
    - French
    - Spanish
    - Portuguese
    - Russian
    - Arabic

## Screenshots

The screenshots are arranged in the same order as the main workspace, so new users can understand the app from the quick-start page to advanced tools and settings. Each group explains what the area is for and what the screenshots highlight.

### 1. Home

The Home area is the starting point of WinDeploy Studio. It restores the focused Quick Start layout: the three primary workflows are immediately available, followed by version, platform, license, repository, and acknowledgement information.

<table>
  <tr>
    <td width="50%"><img src="screenshots/1.png" alt="Home quick start"><br><sub><b>1. Quick Start</b> - Entry cards for installation media, To Go workspaces, and Image Center.</sub></td>
    <td width="50%"><img src="screenshots/2.png" alt="Home about"><br><sub><b>2. About</b> - Version, platform, license, repository, and project acknowledgement information.</sub></td>
  </tr>
</table>

### 2. Image Center

The Image Center separates official Microsoft downloads from community-maintained images and expert-level deployment resources. It is designed to make the source, purpose, language support, and download path clear before the user opens a link.

<table>
  <tr>
    <td width="33%"><img src="screenshots/3.png" alt="Image categories"><br><sub><b>3. Source Categories</b> - Official Microsoft images, community editions, and Enterprise/LTSC builds are separated for clarity.</sub></td>
    <td width="33%"><img src="screenshots/4.png" alt="Image details"><br><sub><b>4. Image Details</b> - Cards show edition notes, source type, language information, and whether a resource is community or expert-oriented.</sub></td>
    <td width="33%"><img src="screenshots/5.png" alt="Image download flow"><br><sub><b>5. Download Flow</b> - Official entries open Microsoft in the system browser, while community images keep mirror selection and WebView2 pages.</sub></td>
  </tr>
</table>

### 3. Windows Installation Media

The Installation Media creator supports both Windows installation media and raw Linux ISOHybrid writing. The screen keeps platform selection, ISO validation, target disk selection, edition detection, and destructive-operation awareness in one workflow.

<table>
  <tr>
    <td><img src="screenshots/6.png" alt="Installation media creator"><br><sub><b>6. Install Media Creator</b> - Choose Windows or Linux, validate the ISO, review the selected external disk, and create bootable installation media.</sub></td>
  </tr>
</table>

### 4. To Go Workspaces

The To Go area creates portable Windows workspaces or persistent Ubuntu/casper Live environments on external drives. It emphasizes safer disk selection, an explicit confirmation summary, reliable elapsed-time progress, and a lightweight waiting game during long image-application steps.

<table>
  <tr>
    <td><img src="screenshots/7.png" alt="To Go workspace creator"><br><sub><b>7. To Go Creator</b> - Choose Windows or supported Linux, review the ISO and target disk, create the boot layout, and monitor the process without misleading ETA values.</sub></td>
  </tr>
</table>

### 5. Logs

The Logs area collects operation output from installation media creation, To Go workspace creation, image downloads, update checks, AI requests, and errors. It helps users review what happened without searching through scattered files.

<table>
  <tr>
    <td width="33%"><img src="screenshots/8.png" alt="Log center"><br><sub><b>8. Log Center</b> - Browse logs by category, source, and recent activity.</sub></td>
    <td width="33%"><img src="screenshots/9.png" alt="Log details"><br><sub><b>9. Log Details</b> - Read structured messages, timestamps, warnings, and operation results.</sub></td>
    <td width="33%"><img src="screenshots/10.png" alt="Log actions"><br><sub><b>10. Log Actions</b> - Filter entries, inspect important events, and open the log folder when manual review is needed.</sub></td>
  </tr>
</table>

### 6. AI Assistant

The AI Assistant provides deployment guidance, troubleshooting suggestions, and log-analysis help. For USB analysis and To Go suitability questions, users can select multiple saved disk-test records; the sent plain-text context includes the device, test configuration, measurements, raw sample points, and metric definitions. If no record is available, the request recommends a Standard test. It includes an explicit AI notice and supports custom OpenAI-compatible endpoints for users who host their own proxy.

<table>
  <tr>
    <td width="50%"><img src="screenshots/11.png" alt="AI assistant chat"><br><sub><b>11. Assistant Chat</b> - Ask deployment questions, summarize errors, and get practical troubleshooting suggestions.</sub></td>
    <td width="50%"><img src="screenshots/12.png" alt="AI assistant settings"><br><sub><b>12. AI Configuration</b> - Configure proxy endpoints and review the notice that AI output should be verified before important operations.</sub></td>
  </tr>
</table>

### 7. Toolbox

The Toolbox groups useful Windows deployment, recovery, diagnostics, hardware, network, and optimization utilities. Tool cards include safety levels and professional notices for advanced, expert, or activation-related utilities.

<table>
  <tr>
    <td><img src="screenshots/13.png" alt="Toolbox"><br><sub><b>13. Tool Cards</b> - Browse curated utilities, check developer/source information, and see Beginner, Advanced, or Expert safety badges before opening tools.</sub></td>
  </tr>
</table>

### 8. Settings

Settings centralizes app preferences, localization, local paths, version information, license details, and acknowledgements. It is also where users can confirm the project source and open-source status.

<table>
  <tr>
    <td width="33%"><img src="screenshots/14.png" alt="Settings preferences"><br><sub><b>14. Preferences</b> - Adjust appearance, language, and local ISO/library paths.</sub></td>
    <td width="33%"><img src="screenshots/15.png" alt="Settings language"><br><sub><b>15. Localization</b> - Switch between eleven supported UI languages without mixing fallback text.</sub></td>
    <td width="33%"><img src="screenshots/16.png" alt="About and acknowledgements"><br><sub><b>16. About</b> - View version, license, GitHub repository, and Special Thanks information.</sub></td>
  </tr>
</table>

### 9. Built-in Website

The built-in website page is used for web-based resources such as community mirror pages and download flows. It keeps loading status visible and separates external web content from local disk operations.

<table>
  <tr>
    <td><img src="screenshots/17.png" alt="Built-in website loading page"><br><sub><b>17. WebView2 Page</b> - Displays embedded web resources, loading state, and download pages while keeping official Microsoft downloads in the system browser.</sub></td>
  </tr>
</table>

## System Requirements

| Item | Minimum | Recommended |
|:---|:---|:---|
| OS | Windows 10 1809 | Windows 11 |
| Architecture | x64 | x64 |
| RAM | 4 GB | 8 GB or more |
| Storage | 500 MB for app | Extra space for ISO files and deployment media |
| Runtime | WebView2 for built-in web pages | Latest WebView2 Runtime |

WinDeploy Studio requests administrator privileges when it starts. This gives all deployment, disk, and boot operations one elevated process and avoids opening separate elevation windows. If UAC is cancelled, the application does not start.

## Download

Download releases from:

[https://github.com/intelfans/WinDeployStudio/releases](https://github.com/intelfans/WinDeployStudio/releases)

## Build From Source

Prerequisites:

- Flutter SDK with Windows desktop support enabled
- Visual Studio Build Tools with C++ desktop workload
- Inno Setup 6 or 7 for installer builds
- PowerShell 7 recommended

Commands:

```powershell
flutter pub get
flutter analyze --no-fatal-infos
flutter build windows --release
```

Build the installer:

```powershell
.\scripts\build_installer.ps1
```

The installer output is created under:

```text
dist\windows\
```

## Project Structure

```text
lib/
  app/                  App shell, routing, theme
  core/
    config/             AI and app configuration
    constants/          App constants
    localization/       11-language UI strings
    services/           Disk safety, ISO, To Go, update, and mirror services
    utils/              Shared helpers
  features/
    ai_assistant/       AI assistant UI and services
    benchmark/          Native drive benchmark and charts
    benchmark_history/  Saved results, comparison, and export
    creator/            Windows/Linux installation media creator
    deployment/         Deployment plans, compatibility, Windows policies
    disk_tools/         Read-only diagnostics and guarded boot repair
    home/               Quick Start and project information
    logs/               Log center
    mirror/             Image center
    settings/           App settings
    tools/              Toolbox
    update/             Update flow
    wtg/                Windows/Linux To Go creator
  shared/
    webview/            Built-in web view and download UI
    widgets/            Responsive deployment shell and shared controls
```

## Safety And Licensing

WinDeploy Studio does not provide Windows licenses, product keys, activation services, or authorization bypass mechanisms. Users are responsible for complying with all applicable software license agreements.

Activation-related utilities are presented as third-party resources for educational, testing, troubleshooting, research, and system administration purposes. For production, commercial use, or long-term deployment, use valid licenses from the software vendor.

Windows, Microsoft, Sysinternals, Intel, and other product names, trademarks, logos, and external resources remain the property of their respective owners. WinDeploy Studio is not affiliated with Microsoft Corporation or Intel Corporation.

## Third-Party Tools

Linux To Go uses the bundled `mke2fs.exe` command-line utility to create the ext4 `writable` persistence image. The bundled binary is from e2fsprogs / Android Open Source Project references, reports `mke2fs 1.47.2 (1-Jan-2025)` and `android-platform-15.0.0_r5-314-ga1f793f6b`, and has SHA-256 `BE42ABB5D1651C8766E230E7AF834BD8E0F2085857CCB483463F58BA5AD65E1A`.

For modern Ubuntu images, Linux To Go uses a separate FAT32 boot/persistence partition and an NTFS Live-data partition. GRUB loads the signed Ubuntu boot files from FAT32, then casper opens the complete Live image from the NTFS volume. This supports individual squashfs files larger than 4 GiB while keeping the ext4 `writable` persistence image on FAT32 where casper can discover it reliably. WinDeploy Studio classifies the selected image and repeats the check immediately before erasing the target: a compatible LTG image must provide x64 UEFI, casper kernel/initrd, Live filesystem payloads, and a patchable GRUB entry. Debian Live is recognized but deliberately kept on the Linux-install-media path until its separate `persistence` / `persistence.conf` protocol is fully implemented.

`mke2fs.exe` is invoked as a separate executable and is not linked into the MIT-licensed WinDeploy Studio application binary. See [tools/e2fsprogs/README.md](tools/e2fsprogs/README.md) for details.

## Roadmap

The implemented portions of the original items 4-9 are documented above and are no longer roadmap promises. The remaining work is:

- Extend persistent Linux To Go beyond the currently validated x64 Ubuntu/casper-compatible Live images. WinDeploy Studio does not yet support arbitrary distributions for Linux To Go.
- Expand offline Windows optional-feature selection beyond the currently implemented .NET Framework 3.5 path.
- Add update-source selection with Oracle Cloud as the recommended high-speed source and GitHub Releases as the fallback. GitHub is currently the only update source.

## Special Thanks

WinDeploy Studio would like to thank the following people and communities for their valuable feedback, testing, ideas, inspiration, and support.

- **Star__P** - Early feedback, testing, and project discussions
- **Timme** - Detailed international user feedback, trust and usability recommendations, Microsoft source suggestions, and community review
- **Microsoft Sysinternals Team** - Inspiration from Microsoft's diagnostic and troubleshooting tools
- **Open Source Community** - Documentation, bug reports, testing, translations, and suggestions

## License

MIT License. See [LICENSE](LICENSE).

---

# WinDeploy Studio 中文说明

WinDeploy Studio 是一款运行于 Windows 的现代化部署工具，面向 Windows 安装盘、Linux ISOHybrid 写盘、Windows To Go、基于 x64 Ubuntu / casper 兼容 Live 镜像的持久化 Linux To Go、原生磁盘测试、镜像资源、工具箱、日志查看和 AI 辅助排障等场景。

## 核心功能

- **安装盘创建工具**
  - 从 ISO 创建 Windows 安装 U 盘，或写入可启动的 Linux ISOHybrid 镜像。
  - 自动解析 Windows ISO，列出可安装版本。
  - Windows 安装盘可选择 UEFI + GPT、UEFI + MBR 或 Legacy BIOS，并可指定分区盘符、自定义卷标和图标。
  - 在擦除目标磁盘前验证 Linux ISOHybrid 结构。
  - 每次破坏性操作都绑定到用户选择的外接磁盘，并在写入前再次核验。

- **To Go 工作环境创建工具**
  - 创建便携式 Windows To Go 工作空间。
  - 使用 x64 Ubuntu 或兼容的 casper Live ISO 创建持久化 Linux To Go。
  - 选择镜像时及擦除目标磁盘前都会分类检查 LTG 镜像；受支持布局必须同时具备 x64 UEFI、casper 内核/initrd、Live 文件系统和可安全注入持久化参数的 GRUB 启动项。
  - Debian Live 会被单独识别，在其独立持久化协议完成前引导至 Linux 安装盘；其他不受支持发行版绝不会被标示为可用的 Linux To Go 镜像。
  - 执行前经过镜像、磁盘、部署方式、高级选项和配置摘要五步流程。
  - 可选择 UEFI + GPT、UEFI + MBR 或 Legacy BIOS，并将 Windows 直接部署到分区或动态/固定 VHD、VHDX；不兼容的镜像与模式组合会在写盘前阻止。
  - 在支持的组合中配置本地磁盘可见性、OOBE/Audit、WinRE、UASP、CompactOS、WIMBoot、VHD/VHDX 盘符修复、.NET Framework 3.5 和部署盘符。UEFI 部署会自动采用 NTFS Windows 卷与独立 FAT32 EFI 分区。
  - 可选离线注入 Windows INF 驱动。受支持的 Ubuntu/casper Linux To Go 可暂存经过校验的 Linux 软件包、匹配内核模块或显式脚本，在首次启动时处理；这不代表支持任意发行版。
  - 为 Windows To Go 创建独立启动分区，并验证 BCD、虚拟磁盘绑定和 UEFI 回退启动文件。
  - 在清盘前重新核验磁盘号、容量、型号与总线类型，优先使用可靠硬件序列号；无法建立稳定物理身份时拒绝清盘。
  - 应用镜像阶段只显示可靠的已用时间。
  - 长时间写入时提供一个纯 UI 小游戏用于打发等待时间，不影响创建流程。

- **原生磁盘测试**
  - 使用 Windows 原生无缓冲、写穿透 I/O，而不是容易受缓存影响的文件复制测速。
  - 测量顺序读写、4K 随机读写、真实多线程扩展、混合负载、延迟分位数，并可选测试全盘写入稳定性。
  - 提供快速、标准、极限、全盘写入四种模式，配合实时折线图、缓存行为分析和面向 To Go 的实用评级建议。
  - 成功结果会自动保存，可查看详情、按日期筛选、比较两次结果、删除并导出 CSV/JSON。
  - 在询问 AI 某个 USB 是否适合做随身系统，或使用“分析 USB”时，可选择一条或多条保存的记录；设备信息、测试参数、测量数据和指标含义会以纯文本一并发送。
  - 未选择已保存记录时，发给 AI 的请求会建议先完成一次标准磁盘测试，再对随身系统适用性作出有把握的判断。
  - 测试文件带独立所有权标记，仅清理由本次测试创建的数据。

- **磁盘工具**
  - 通过带超时边界的原生 helper 以只读方式收集磁盘身份、健康、可靠性、寿命、温度、磨损和 NVMe 遥测；慢速或不受支持的查询会明确显示为不可用或采集警告，不会阻塞整个扫描。
  - 从已提升权限的应用进程中运行带超时边界的原生 helper；设备无响应时会给出受限失败结果，不会让诊断界面一直卡住。
  - 仅对重新核验后的外接非系统磁盘修复 UEFI/BIOS 启动文件，执行前经过预检、输入确认和 BCD 备份；不格式化磁盘，并在完成后验证结果和保存技术日志。

- **镜像中心**
  - 区分 **Microsoft 官方镜像**、**社区版本** 与 **企业版 / LTSC 构建**。
  - Windows 10 / Windows 11 官方条目始终跳转 Microsoft 官方网站，并使用系统默认浏览器打开。
  - 社区镜像继续保留中国镜像和全球镜像选择流程。
  - 企业版与 LTSC 镜像标记为专家级部署资源，并提供清晰的来源与语言提示。
  - StarValleyX 仅在简体中文和繁体中文界面中显示。
  - CJK 字体包同样只在简体中文和繁体中文界面显示，仅向 Tiny10、Tiny11 和 Windows X-Lite 提供，不向 StarValleyX 提示。

- **工具箱**
  - 收录部署、诊断、恢复、硬件、网络、优化等工具。
  - 工具分为入门、高级、专家级三个安全等级。
  - 高级、专家级和激活相关工具打开前显示专业提示。
  - 新增 Microsoft Sysinternals Suite。

- **AI 助手**
  - 用于 Windows 部署问答、日志分析和排障建议。
  - 对“这个 USB 适合制作随身系统吗？”和“分析 USB”支持多选已保存的磁盘测试记录，以纯文本发送设备数据、运行参数、工作负载、采样点和指标解释。
  - 使用前显示 AI 内容提示。
  - 支持自定义 OpenAI 兼容代理端点。

- **日志中心**
  - 汇总安装盘、随身系统、镜像、下载、更新、AI 和错误日志。
  - 支持分类查看和快速打开日志目录。

- **Windows 11 界面与导航**
  - 在受支持的 Windows 10/11 主机上统一使用 Windows 11 风格界面。
  - Flutter 主题、原生标题栏和响应式部署导航保持一致，不再提供没有必要的外观模式切换。
  - 左侧主导航用清晰的分隔线分组；从磁盘工具或测试历史等二级页面选择主导航时，会直接打开所选目标页，不再保留之前的二级页面。

- **多语言**
  - 支持 11 种界面语言：简体中文、繁体中文、英语、日语、韩语、德语、法语、西班牙语、葡萄牙语、俄语、阿拉伯语。

## 界面截图

以下截图按主界面的使用顺序排列，从快速入口、镜像中心到高级工具和设置页逐步介绍。每个区域都说明它的用途，以及截图中重点展示的内容。

### 1. 首页

首页是 WinDeploy Studio 的起点，恢复为聚焦的“快速开始 + 关于”布局。用户可立即进入安装盘制作、随身系统和镜像中心，再查看版本、平台、许可证、仓库和项目鸣谢信息。

<table>
  <tr>
    <td width="50%"><img src="screenshots/1.png" alt="首页快速开始"><br><sub><b>1. 快速开始</b> - 提供安装盘、随身系统和镜像中心三个主要工作流入口。</sub></td>
    <td width="50%"><img src="screenshots/2.png" alt="首页关于"><br><sub><b>2. 关于</b> - 展示版本、平台、许可证、GitHub 仓库和项目鸣谢等信息。</sub></td>
  </tr>
</table>

### 2. 镜像中心

镜像中心把 Microsoft 官方下载、社区维护镜像和专家级部署资源分开呈现。用户在打开链接前可以先确认来源、用途、语言支持和下载方式，避免把官方镜像与第三方资源混在一起。

<table>
  <tr>
    <td width="33%"><img src="screenshots/3.png" alt="镜像分类"><br><sub><b>3. 来源分类</b> - 将 Microsoft 官方镜像、社区版本和企业版 / LTSC 构建分组显示，来源更清楚。</sub></td>
    <td width="33%"><img src="screenshots/4.png" alt="镜像详情"><br><sub><b>4. 镜像详情</b> - 卡片展示版本说明、来源类型、语言信息，以及是否属于社区或专家级资源。</sub></td>
    <td width="33%"><img src="screenshots/5.png" alt="镜像下载流程"><br><sub><b>5. 下载流程</b> - 官方条目使用系统浏览器打开 Microsoft 页面，社区镜像保留镜像源选择和 WebView2 页面。</sub></td>
  </tr>
</table>

### 3. 安装盘创建工具

安装盘创建工具同时支持 Windows 安装介质和 Linux ISOHybrid 原始写入。界面把平台选择、ISO 验证、目标磁盘选择、版本识别和高风险操作提示放在同一流程里，方便用户逐步确认。

<table>
  <tr>
    <td><img src="screenshots/6.png" alt="安装盘创建工具"><br><sub><b>6. 安装盘创建</b> - 选择 Windows 或 Linux，验证 ISO，核对外接目标磁盘，并创建可启动安装介质。</sub></td>
  </tr>
</table>

### 4. To Go 工作环境

To Go 区域用于在外接磁盘上创建 Windows 工作空间，或创建可保存更改的 Ubuntu/casper Live 环境。它强调更安全的磁盘选择、写入前摘要、可靠的已用时间进度，以及在长时间应用镜像时用于等待的小型 UI 游戏。

<table>
  <tr>
    <td><img src="screenshots/7.png" alt="To Go 工作环境创建工具"><br><sub><b>7. 随身系统创建</b> - 选择 Windows 或受支持的 Linux，核对 ISO 与目标磁盘，创建启动布局，并用可靠进度信息替代容易误导的剩余时间估算。</sub></td>
  </tr>
</table>

### 5. 日志中心

日志中心汇总安装盘制作、随身系统、镜像下载、更新检查、AI 请求和错误信息等输出。用户可以在一个地方回看操作过程，不需要到多个目录里手动找日志。

<table>
  <tr>
    <td width="33%"><img src="screenshots/8.png" alt="日志中心"><br><sub><b>8. 日志中心</b> - 按类别、来源和最近活动浏览日志。</sub></td>
    <td width="33%"><img src="screenshots/9.png" alt="日志详情"><br><sub><b>9. 日志详情</b> - 查看结构化消息、时间戳、警告和操作结果。</sub></td>
    <td width="33%"><img src="screenshots/10.png" alt="日志操作"><br><sub><b>10. 日志操作</b> - 筛选条目、检查关键事件，并在需要时快速打开日志目录。</sub></td>
  </tr>
</table>

### 6. AI 助手

AI 助手用于部署问答、排障建议和日志分析。对 USB 分析和随身系统适用性问题，用户可多选已保存的磁盘测试记录；发送的纯文本上下文包括设备信息、测试配置、测量结果、原始采样点和指标解释。没有可用记录时，请求会建议先运行一次标准测试。界面包含明确的 AI 内容提示，并支持自定义 OpenAI 兼容代理端点，适合使用自建代理或兼容服务的用户。

<table>
  <tr>
    <td width="50%"><img src="screenshots/11.png" alt="AI 助手对话"><br><sub><b>11. 助手对话</b> - 提问部署问题、总结错误信息，并获得面向实际操作的排障建议。</sub></td>
    <td width="50%"><img src="screenshots/12.png" alt="AI 助手设置"><br><sub><b>12. AI 配置</b> - 配置代理端点，并提醒用户在执行重要操作前核实 AI 输出。</sub></td>
  </tr>
</table>

### 7. 工具箱

工具箱收录部署、恢复、诊断、硬件、网络和优化等常用工具。工具卡片会显示安全等级，并在打开高级、专家级或激活相关工具前给出专业提示。

<table>
  <tr>
    <td><img src="screenshots/13.png" alt="工具箱"><br><sub><b>13. 工具卡片</b> - 浏览精选工具，查看开发者和来源信息，并在打开前识别入门、高级或专家级安全等级。</sub></td>
  </tr>
</table>

### 8. 设置

设置页集中管理应用偏好、本地化、路径、版本信息、许可证和鸣谢内容。用户也可以在这里确认项目来源和开源状态。

<table>
  <tr>
    <td width="33%"><img src="screenshots/14.png" alt="设置偏好"><br><sub><b>14. 偏好设置</b> - 调整外观、语言和本地 ISO/镜像库路径。</sub></td>
    <td width="33%"><img src="screenshots/15.png" alt="语言设置"><br><sub><b>15. 本地化</b> - 在 11 种界面语言之间切换，并避免混入回退文字。</sub></td>
    <td width="33%"><img src="screenshots/16.png" alt="关于与鸣谢"><br><sub><b>16. 关于页面</b> - 查看版本、许可证、GitHub 仓库和特别鸣谢信息。</sub></td>
  </tr>
</table>

### 9. 内置网站页面

内置网站页面用于承载社区镜像页和下载流程等 Web 资源。它会显示加载状态，并把外部网页内容与本地磁盘操作分开；Microsoft 官方下载仍会使用系统浏览器打开。

<table>
  <tr>
    <td><img src="screenshots/17.png" alt="内置网站加载页面"><br><sub><b>17. WebView2 页面</b> - 展示内置网页资源、加载状态和下载页面，同时让 Microsoft 官方下载保持在系统浏览器中打开。</sub></td>
  </tr>
</table>

## 系统要求

| 项目 | 最低要求 | 建议配置 |
|:---|:---|:---|
| 操作系统 | Windows 10 1809 | Windows 11 |
| 架构 | x64 | x64 |
| 内存 | 4 GB | 8 GB 或更高 |
| 存储空间 | 应用本体约 500 MB | 为 ISO 文件和部署介质预留额外空间 |
| 运行时 | 内置网页需要 WebView2 | 最新版 WebView2 Runtime |

WinDeploy Studio 会在启动时请求管理员权限。这样部署、磁盘和启动修复操作都在同一个已提升权限的进程内执行，不会再打开单独的提权窗口。若取消 UAC 授权，应用不会启动。

## 下载

请从 GitHub Releases 下载：

[https://github.com/intelfans/WinDeployStudio/releases](https://github.com/intelfans/WinDeployStudio/releases)

## 从源码构建

前置要求：

- 已启用 Windows 桌面支持的 Flutter SDK
- 安装带 C++ 桌面开发工作负载的 Visual Studio Build Tools
- 构建安装包需要 Inno Setup 6 或 7
- 建议使用 PowerShell 7

```powershell
flutter pub get
flutter analyze --no-fatal-infos
flutter build windows --release
```

构建安装包：

```powershell
.\scripts\build_installer.ps1
```

安装包输出目录：

```text
dist\windows\
```

## 项目结构

```text
lib/
  app/                  应用外壳、路由和主题
  core/
    config/             AI 与应用配置
    constants/          应用常量
    localization/       11 种界面语言
    services/           磁盘安全、ISO、随身系统、更新和镜像服务
    utils/              通用工具函数
  features/
    ai_assistant/       AI 助手界面与服务
    benchmark/          原生磁盘测试与折线图
    benchmark_history/  测试历史、比较与导出
    creator/            Windows / Linux 安装盘创建工具
    deployment/         部署计划、兼容性和 Windows 策略
    disk_tools/         只读诊断和受保护的启动修复
    home/               快速开始与项目信息
    logs/               日志中心
    mirror/             镜像中心
    settings/           应用设置
    tools/              工具箱
    update/             更新流程
    wtg/                Windows / Linux To Go 创建工具
  shared/
    webview/            内置网页和下载界面
    widgets/            响应式部署外壳和共享控件
```

## 安全与许可声明

WinDeploy Studio 基于 MIT License 分发。

本项目不提供 Windows 授权、产品密钥、激活服务或绕过授权机制。用户需自行确保遵守 Microsoft 及其他软件厂商的许可协议。

第三方软件、商标、Logo 和外部资源归其各自所有者所有。WinDeploy Studio 与 Microsoft Corporation 或 Intel Corporation 无官方隶属关系。

## 第三方工具说明

Linux To Go 使用随程序内置的 `mke2fs.exe` 命令行工具创建 ext4 `writable` 持久化镜像。该二进制文件来源参考 e2fsprogs / Android Open Source Project，版本信息为 `mke2fs 1.47.2 (1-Jan-2025)` 和 `android-platform-15.0.0_r5-314-ga1f793f6b`，SHA-256 为 `BE42ABB5D1651C8766E230E7AF834BD8E0F2085857CCB483463F58BA5AD65E1A`。

针对现代 Ubuntu 镜像，Linux To Go 采用独立的 FAT32 启动/持久化分区和 NTFS Live 数据分区。GRUB 从 FAT32 加载 Ubuntu 的签名启动文件，随后由 casper 从 NTFS 卷读取完整 Live 镜像，因此可以容纳超过 4 GiB 的单个 squashfs 文件；ext4 `writable` 持久化镜像仍保存在 FAT32 上，确保 casper 能够可靠识别。WinDeploy Studio 会在选择镜像时分类检查，并在清除目标磁盘前再次复核：兼容 LTG 必须具备 x64 UEFI、casper 内核/initrd、Live 文件系统和可修改的 GRUB 启动项。Debian Live 会被明确识别，但在其独立的 `persistence` / `persistence.conf` 协议完整实现前，仍会引导至 Linux 安装盘。

WinDeploy Studio 以独立进程调用 `mke2fs.exe`，并未将其链接进基于 MIT License 授权的主程序二进制文件。详见 [tools/e2fsprogs/README.md](tools/e2fsprogs/README.md)。

## 未来规划

原规划④-⑨中已经落地的部分已写入上方“核心功能”，不再作为未来承诺。当前真实未完成项为：

- 将持久化 Linux To Go 扩展到目前已验证的 x64 Ubuntu / casper 兼容 Live 镜像之外；WinDeploy Studio 当前不支持任意发行版的 Linux To Go。
- 将离线 Windows 可选功能扩展到当前已实现的 .NET Framework 3.5 之外。
- 加入更新源选择：甲骨文云作为推荐高速源，GitHub Releases 作为备用源；当前只有 GitHub 更新源。

## 特别鸣谢

WinDeploy Studio 感谢以下个人和社区提供的反馈、测试、想法、灵感与支持。

- **Star__P** - 早期反馈、测试和项目讨论
- **Timme** - 细致的国际用户反馈、信任与易用性建议、Microsoft 官方来源建议和社区审阅
- **Microsoft Sysinternals Team** - 来自 Microsoft 诊断与故障排查工具的启发
- **Open Source Community** - 文档、错误报告、测试、翻译和建议

## 许可证

MIT License，详见 [LICENSE](LICENSE)。
