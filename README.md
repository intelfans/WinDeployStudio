# WinDeploy Studio

Modern Windows deployment toolkit for Windows installation media, Windows To Go, image downloads, troubleshooting tools, logs, and AI-assisted deployment help.

![Platform](https://img.shields.io/badge/Platform-Windows-blue?logo=windows)
![License](https://img.shields.io/badge/License-MIT-green)
![Flutter](https://img.shields.io/badge/Flutter-Windows-02569B?logo=flutter)
![Version](https://img.shields.io/badge/Version-1.1.0-orange)

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
  - Separates **Official Microsoft** images from **Community Images**.
  - Official Windows 10 and Windows 11 entries open Microsoft's official download pages in the system browser.
  - Community images keep the existing mirror-based flow with China and Global mirror choices.
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

| Home | Image Center | Windows Installation Media |
|:---:|:---:|:---:|
| ![Home](screenshots/1.png) | ![Image Center](screenshots/2.png) | ![Creator](screenshots/3.png) |

| Windows To Go | Logs | AI Assistant |
|:---:|:---:|:---:|
| ![WTG](screenshots/4.png) | ![Logs](screenshots/5.png) | ![AI](screenshots/6.png) |

| Toolbox | Settings | Languages |
|:---:|:---:|:---:|
| ![Toolbox](screenshots/7.png) | ![Settings](screenshots/8.png) | ![Languages](screenshots/9.png) |

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
  - 区分 **Official Microsoft** 与 **Community Images**。
  - Windows 10 / Windows 11 官方条目始终跳转 Microsoft 官方网站，并使用系统默认浏览器打开。
  - 社区镜像继续保留中国镜像和全球镜像选择流程。
  - StarValleyX 仅在简体中文和繁体中文界面中显示。

- **工具箱**
  - 收录部署、诊断、恢复、硬件、网络、优化等工具。
  - 工具分为 Beginner、Advanced、Expert 三个安全等级。
  - 高级、专家级和激活相关工具打开前显示专业提示。
  - 新增 Microsoft Sysinternals Suite。

- **AI 助手**
  - 用于 Windows 部署问答、日志分析和排障建议。
  - 使用前显示 AI 内容提示。
  - 支持自定义 OpenAI-compatible 代理端点。

- **日志中心**
  - 汇总安装盘、WTG、镜像、下载、更新、AI 和错误日志。
  - 支持分类查看和快速打开日志目录。

- **多语言**
  - 支持 11 种界面语言：简体中文、繁体中文、英语、日语、韩语、德语、法语、西班牙语、葡萄牙语、俄语、阿拉伯语。

## 构建

```powershell
flutter pub get
flutter analyze --no-fatal-infos
flutter build windows --release
```

构建安装包：

```powershell
.\scripts\build_installer.ps1
```

## 许可与声明

WinDeploy Studio 基于 MIT License 分发。

本项目不提供 Windows 授权、产品密钥、激活服务或绕过授权机制。用户需自行确保遵守 Microsoft 及其他软件厂商的许可协议。

第三方软件、商标、Logo 和外部资源归其各自所有者所有。WinDeploy Studio 与 Microsoft Corporation 或 Intel Corporation 无官方隶属关系。
