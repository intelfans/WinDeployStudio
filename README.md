# WinDeploy Studio

Modern Windows deployment toolkit for Windows installation media, Windows To Go, image downloads, troubleshooting tools, logs, and AI-assisted deployment help.

![Platform](https://img.shields.io/badge/Platform-Windows-blue?logo=windows)
![License](https://img.shields.io/badge/License-MIT-green)
![Flutter](https://img.shields.io/badge/Flutter-Windows-02569B?logo=flutter)
![Version](https://img.shields.io/badge/Version-1.1.2-orange)

## Overview

WinDeploy Studio is a Flutter-based Windows desktop app designed for practical Windows deployment workflows. It focuses on installation media creation, Windows To Go creation, trusted image source navigation, deployment utilities, logs, and clear safety notices for advanced tools.

The project is distributed under the MIT License.

## Highlights

- **Windows Installation Media Creator**
  - Create Windows installation USB drives from ISO files.
  - Parse Windows ISO images and list available editions.
  - Prepare USB partitions and boot files automatically.

- **Windows To Go Creator**
  - Create portable Windows To Go workspaces.
  - Detect removable target disks and show compatibility information.
  - Uses selected disk metadata as a fallback to avoid false `0 B` or `Unknown` compatibility results.
  - During image application, the progress panel shows reliable elapsed time only.
  - Includes a small UI-only waiting game during long image application steps.

- **Image Center**
  - Separates **Official Microsoft Images**, **Community Editions**, and **Enterprise & LTSC Builds**.
  - Official Windows 10 and Windows 11 entries open Microsoft's official download pages in the system browser.
  - Community images keep the existing mirror-based flow with China and Global mirror choices.
  - Enterprise and LTSC entries are marked as expert-level deployment resources with clear source and language notices.
  - StarValleyX is shown only for Simplified Chinese and Traditional Chinese UI languages.

- **Toolbox**
  - Curated deployment, diagnostics, recovery, hardware, network, and optimization utilities.
  - Tool safety levels: Beginner, Advanced, and Expert.
  - Professional notices before opening advanced, expert, or activation-related utilities.
  - Includes Microsoft Sysinternals Suite.

- **AI Assistant**
  - Built-in AI assistant for Windows deployment questions, log analysis, and troubleshooting suggestions.
  - Displays a clear AI-generated content notice before use.
  - Supports custom OpenAI-compatible proxy endpoints.

- **Log Center**
  - Centralized logs for installation media creation, WTG, image operations, downloads, updates, AI, and errors.
  - Quick log browsing and folder access.

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

The screenshots are arranged in the same order as the main workspace, so new users can understand the app from the first dashboard to advanced tools and settings. Each group explains what the area is for and what the screenshots highlight.

### 1. Home

The Home area is the starting point of WinDeploy Studio. It gives users a quick overview of the app, exposes the most common workflows, and keeps important project information easy to find.

<table>
  <tr>
    <td width="50%"><img src="screenshots/1.png" alt="Home dashboard"><br><sub><b>1. Main Dashboard</b> - Entry cards for installation media, Windows To Go, Image Center, logs, tools, and AI assistance.</sub></td>
    <td width="50%"><img src="screenshots/2.png" alt="Home overview"><br><sub><b>2. Overview Panel</b> - Version, platform, license, repository, and project acknowledgement information.</sub></td>
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

The Windows Installation Media creator focuses on turning a Windows ISO into an installer USB drive. The screen keeps ISO selection, target disk selection, edition detection, and destructive-operation awareness in one workflow.

<table>
  <tr>
    <td><img src="screenshots/6.png" alt="Windows installation media creator"><br><sub><b>6. Install Media Creator</b> - Select an ISO, review detected editions, choose the target USB device, and prepare boot files for Windows setup.</sub></td>
  </tr>
</table>

### 4. Windows To Go

The Windows To Go area creates portable Windows workspaces on external drives. It emphasizes safer disk selection, compatibility information, reliable elapsed-time progress, and a lightweight waiting game during long image-application steps.

<table>
  <tr>
    <td><img src="screenshots/7.png" alt="Windows To Go creator"><br><sub><b>7. WTG Creator</b> - Review the selected external disk, apply a Windows image, create the boot layout, and monitor the process without misleading ETA values.</sub></td>
  </tr>
</table>

### 5. Logs

The Logs area collects operation output from installation media creation, WTG, image downloads, update checks, AI requests, and errors. It helps users review what happened without searching through scattered files.

<table>
  <tr>
    <td width="33%"><img src="screenshots/8.png" alt="Log center"><br><sub><b>8. Log Center</b> - Browse logs by category, source, and recent activity.</sub></td>
    <td width="33%"><img src="screenshots/9.png" alt="Log details"><br><sub><b>9. Log Details</b> - Read structured messages, timestamps, warnings, and operation results.</sub></td>
    <td width="33%"><img src="screenshots/10.png" alt="Log actions"><br><sub><b>10. Log Actions</b> - Filter entries, inspect important events, and open the log folder when manual review is needed.</sub></td>
  </tr>
</table>

### 6. AI Assistant

The AI Assistant provides deployment guidance, troubleshooting suggestions, and log-analysis help. It includes an explicit AI notice and supports custom OpenAI-compatible endpoints for users who host their own proxy.

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

Administrative privileges are required for disk partitioning, boot file writing, Windows To Go creation, and some advanced tools.

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
    database/           Local SQLite support
    localization/       11-language UI strings
    services/           Disk, ISO, WTG, update, and mirror services
    utils/              Shared helpers
  features/
    ai_assistant/       AI assistant UI and services
    creator/            Windows installation media creator
    home/               Home dashboard
    logs/               Log center
    mirror/             Image center
    settings/           App settings
    tools/              Toolbox
    update/             Update flow
    wtg/                Windows To Go creator
  shared/
    webview/            Built-in web view and download UI
```

## Safety And Licensing

WinDeploy Studio does not provide Windows licenses, product keys, activation services, or authorization bypass mechanisms. Users are responsible for complying with all applicable software license agreements.

Activation-related utilities are presented as third-party resources for educational, testing, troubleshooting, research, and system administration purposes. For production, commercial use, or long-term deployment, use valid licenses from the software vendor.

Windows, Microsoft, Sysinternals, Intel, and other product names, trademarks, logos, and external resources remain the property of their respective owners. WinDeploy Studio is not affiliated with Microsoft Corporation or Intel Corporation.

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

WinDeploy Studio 是一个现代化 Windows 部署工具，面向 Windows 安装盘制作、Windows To Go、镜像下载、工具箱、日志查看和 AI 辅助排障等常见场景。

## 核心功能

- **Windows 安装盘创建工具**
  - 从 ISO 创建 Windows 安装 U 盘。
  - 自动解析 Windows ISO，列出可安装版本。
  - 自动完成分区、格式化和启动文件写入。

- **Windows To Go 创建工具**
  - 创建便携式 Windows To Go 工作空间。
  - 自动识别外接磁盘并显示兼容性信息。
  - 兼容性检测会继承已选磁盘的真实容量、总线类型和型号，避免误显示 `0 B` 或 `Unknown`。
  - 应用镜像阶段只显示可靠的已用时间。
  - 长时间写入时提供一个纯 UI 小游戏用于打发等待时间，不影响创建流程。

- **镜像中心**
  - 区分 **Microsoft 官方镜像**、**社区版本** 与 **企业版 / LTSC 构建**。
  - Windows 10 / Windows 11 官方条目始终跳转 Microsoft 官方网站，并使用系统默认浏览器打开。
  - 社区镜像继续保留中国镜像和全球镜像选择流程。
  - 企业版与 LTSC 镜像标记为专家级部署资源，并提供清晰的来源与语言提示。
  - StarValleyX 仅在简体中文和繁体中文界面中显示。

- **工具箱**
  - 收录部署、诊断、恢复、硬件、网络、优化等工具。
  - 工具分为入门、高级、专家级三个安全等级。
  - 高级、专家级和激活相关工具打开前显示专业提示。
  - 新增 Microsoft Sysinternals Suite。

- **AI 助手**
  - 用于 Windows 部署问答、日志分析和排障建议。
  - 使用前显示 AI 内容提示。
  - 支持自定义 OpenAI 兼容代理端点。

- **日志中心**
  - 汇总安装盘、WTG、镜像、下载、更新、AI 和错误日志。
  - 支持分类查看和快速打开日志目录。

- **多语言**
  - 支持 11 种界面语言：简体中文、繁体中文、英语、日语、韩语、德语、法语、西班牙语、葡萄牙语、俄语、阿拉伯语。

## 界面截图

以下截图按主界面的使用顺序排列，从首页、镜像中心到高级工具和设置页逐步介绍。每个区域都说明它的用途，以及截图中重点展示的内容。

### 1. 首页

首页是 WinDeploy Studio 的起点，用来集中展示常用入口、项目状态和基础信息。新用户可以从这里快速进入安装盘制作、Windows To Go、镜像中心、日志、工具箱和 AI 助手。

<table>
  <tr>
    <td width="50%"><img src="screenshots/1.png" alt="首页仪表盘"><br><sub><b>1. 主仪表盘</b> - 集中展示安装盘、WTG、镜像中心、日志、工具箱和 AI 助手等核心功能入口。</sub></td>
    <td width="50%"><img src="screenshots/2.png" alt="首页概览"><br><sub><b>2. 概览信息</b> - 展示版本、平台、许可证、GitHub 仓库和项目鸣谢等信息。</sub></td>
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

### 3. Windows 安装盘创建工具

Windows 安装盘创建工具用于把 Windows ISO 写入 U 盘并制作成安装介质。界面把 ISO 选择、目标磁盘选择、版本识别和高风险操作提示放在同一流程里，方便用户逐步确认。

<table>
  <tr>
    <td><img src="screenshots/6.png" alt="Windows 安装盘创建工具"><br><sub><b>6. 安装盘创建</b> - 选择 ISO，查看识别出的 Windows 版本，选择目标 U 盘，并自动准备 Windows 安装所需的启动文件。</sub></td>
  </tr>
</table>

### 4. Windows To Go

Windows To Go 区域用于在外接磁盘上创建可随身携带的 Windows 工作空间。它强调更安全的磁盘选择、兼容性信息、可靠的已用时间进度，以及在长时间应用镜像时用于等待的小型 UI 游戏。

<table>
  <tr>
    <td><img src="screenshots/7.png" alt="Windows To Go 创建工具"><br><sub><b>7. WTG 创建</b> - 检查已选外接磁盘，应用 Windows 镜像，创建启动布局，并用可靠进度信息替代容易误导的剩余时间估算。</sub></td>
  </tr>
</table>

### 5. 日志中心

日志中心汇总安装盘制作、WTG、镜像下载、更新检查、AI 请求和错误信息等输出。用户可以在一个地方回看操作过程，不需要到多个目录里手动找日志。

<table>
  <tr>
    <td width="33%"><img src="screenshots/8.png" alt="日志中心"><br><sub><b>8. 日志中心</b> - 按类别、来源和最近活动浏览日志。</sub></td>
    <td width="33%"><img src="screenshots/9.png" alt="日志详情"><br><sub><b>9. 日志详情</b> - 查看结构化消息、时间戳、警告和操作结果。</sub></td>
    <td width="33%"><img src="screenshots/10.png" alt="日志操作"><br><sub><b>10. 日志操作</b> - 筛选条目、检查关键事件，并在需要时快速打开日志目录。</sub></td>
  </tr>
</table>

### 6. AI 助手

AI 助手用于部署问答、排障建议和日志分析。界面包含明确的 AI 内容提示，并支持自定义 OpenAI 兼容代理端点，适合使用自建代理或兼容服务的用户。

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

磁盘分区、启动文件写入、Windows To Go 创建以及部分高级工具需要管理员权限。

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
    database/           本地 SQLite 支持
    localization/       11 种界面语言
    services/           磁盘、ISO、WTG、更新和镜像服务
    utils/              通用工具函数
  features/
    ai_assistant/       AI 助手界面与服务
    creator/            Windows 安装盘创建工具
    home/               首页仪表盘
    logs/               日志中心
    mirror/             镜像中心
    settings/           应用设置
    tools/              工具箱
    update/             更新流程
    wtg/                Windows To Go 创建工具
  shared/
    webview/            内置网页和下载界面
```

## 安全与许可声明

WinDeploy Studio 基于 MIT License 分发。

本项目不提供 Windows 授权、产品密钥、激活服务或绕过授权机制。用户需自行确保遵守 Microsoft 及其他软件厂商的许可协议。

第三方软件、商标、Logo 和外部资源归其各自所有者所有。WinDeploy Studio 与 Microsoft Corporation 或 Intel Corporation 无官方隶属关系。

## 特别鸣谢

WinDeploy Studio 感谢以下个人和社区提供的反馈、测试、想法、灵感与支持。

- **Star__P** - 早期反馈、测试和项目讨论
- **Timme** - 细致的国际用户反馈、信任与易用性建议、Microsoft 官方来源建议和社区审阅
- **Microsoft Sysinternals Team** - 来自 Microsoft 诊断与故障排查工具的启发
- **Open Source Community** - 文档、错误报告、测试、翻译和建议

## 许可证

MIT License，详见 [LICENSE](LICENSE)。
