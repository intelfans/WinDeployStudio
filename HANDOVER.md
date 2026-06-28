# WinDeploy Studio 交接文档

最后更新：2026-06-28  
当前版本：1.1.0  
目标平台：Windows Desktop  
项目目录：`D:\Dev\WinDeployStudio`

本文档记录当前项目的真实状态、关键入口、已经完成的调整、构建方式和后续维护注意事项。旧交接文档中关于镜像源、AdBlock、工具数量、依赖版本和分析警告的部分已经过期，以本文件为准。

## 1. 项目概览

WinDeploy Studio 是一个 Flutter Windows 桌面工具，面向 Windows 部署、Windows 安装盘创建、Windows To Go、镜像下载、常用工具集合、日志、更新和 AI 助手场景。

技术栈：

| 项目 | 当前状态 |
| --- | --- |
| Flutter | 3.44.4 stable |
| Dart | 3.12.2 |
| UI | Material 3 |
| 状态管理 | Riverpod 3 |
| 路由 | GoRouter 17 |
| 数据文件 | `data/mirrors.json`, `data/tools.json` |
| 本地存储 | `shared_preferences`, `sqflite_common_ffi` |
| WebView | `webview_windows` |
| 外部浏览器 | `url_launcher` |
| Markdown | `flutter_markdown_plus`, `markdown` |

当前目录不是 git 仓库。维护时不能依赖 `git diff`、`git status` 或分支记录判断改动来源。

## 2. 版本号位置

| 文件 | 字段 | 当前值 |
| --- | --- | --- |
| `pubspec.yaml` | `version` | `1.1.0` |
| `lib/core/constants/app_constants.dart` | `appVersion` | `1.1.0` |
| `installer/windows/WinDeployStudio.iss` | 安装包版本字段 | 应与 `1.1.0` 同步 |
| `scripts/build_installer.ps1` | 输出安装包名 | 应与 `1.1.0` 同步 |

同步规则：

- Flutter 显示版本使用 `major.minor.patch+build`。
- 应用内显示版本使用 `major.minor.patch`。
- Inno Setup 版本通常使用 `major.minor.patch.build`。
- 修改版本时必须同时检查 `pubspec.yaml`、`app_constants.dart`、Inno 脚本和构建脚本输出文案。

## 3. 入口和目录地图

| 路径 | 作用 |
| --- | --- |
| `lib/main.dart` | 应用入口，初始化 Flutter、数据库和应用根组件 |
| `lib/app/app.dart` | `MaterialApp`、主题、语言选择和 `supportedLocales` |
| `lib/app/routes.dart` | GoRouter 路由、镜像详情路由和 StarValleyX 访问保护 |
| `lib/core/localization/strings.dart` | 11 种语言的应用 UI 文案 |
| `lib/core/constants/app_constants.dart` | 应用名、版本号、尺寸、安全确认文本 |
| `lib/features/home/` | 首页 |
| `lib/features/bootable_usb/` | Windows 安装盘制作 |
| `lib/features/wtg/` | Windows To Go |
| `lib/features/mirror/` | 镜像中心 |
| `lib/features/tools/` | 工具箱 |
| `lib/features/ai_assistant/` | AI 助手 |
| `lib/features/logs/` | 日志中心 |
| `lib/features/update/` | 自动更新 |
| `lib/features/settings/` | 设置 |
| `lib/shared/webview/` | 内嵌 WebView2 浏览器与下载辅助 |
| `data/mirrors.json` | 镜像中心数据 |
| `data/tools.json` | 工具箱数据 |
| `scripts/ensure_nuget.ps1` | NuGet 自动兜底 |
| `scripts/build_windows.ps1` | 分析并构建 Windows release，不生成安装包 |
| `scripts/build_installer.ps1` | 构建安装包 |

## 4. 当前功能状态

| 模块 | 当前状态 |
| --- | --- |
| Windows 安装盘创建 | 已实现，包含磁盘选择、格式化、ISO 写入等流程 |
| Windows To Go | 已实现，包含镜像应用、BCD/启动配置和进度展示 |
| 镜像中心 | 已重构为 Official Microsoft 和 Community Images 两类 |
| 工具箱 | 27 个工具，9 个分类，支持 Beginner/Advanced/Expert 安全等级 |
| AI 助手 | 已接入远程 API，并加入顶部免责声明 |
| 日志中心 | 记录下载、镜像源、官方跳转等操作 |
| 自动更新 | GitHub release 检查、下载和安装流程已实现 |
| 设置 | 语言、主题、镜像源策略等基础设置已实现 |
| AdBlock | 相关代码已删除，当前没有启用广告拦截功能 |

## 5. 镜像中心规则

镜像数据文件：`data/mirrors.json`  
当前条目数：8

| 类别 | 条目 |
| --- | --- |
| Official Microsoft | `official-win10`, `official-win11` |
| Community Images | `tiny10`, `tiny11`, `xlite10`, `xlite11`, `starvalleyx` |
| Tools | `font-pack` |

### Official Microsoft

官方条目只跳转 Microsoft 官方网页：

| 条目 | URL |
| --- | --- |
| Windows 10 | `https://www.microsoft.com/en-us/software-download/windows10` |
| Windows 11 | `https://www.microsoft.com/en-au/software-download/windows11` |

点击下载时：

- 显示确认弹窗：`Official Microsoft Download`。
- 不显示镜像选择弹窗。
- 不使用 123 Cloud。
- 不使用 GoFile。
- 不在 WebView2 内打开。
- 确认后使用系统默认浏览器打开 Microsoft 网站。
- 写入日志：

```text
[OfficialDownload]
Product=Windows11
Source=Microsoft
Method=SystemBrowser
```

或：

```text
[OfficialDownload]
Product=Windows10
Source=Microsoft
Method=SystemBrowser
```

### Community Images

社区镜像保持当前镜像选择流程：

- 弹出镜像选择对话框。
- China Mirror 对应 123 Cloud。
- Global Mirror 对应 GoFile。
- 选择后通过 WebView2 下载页打开。
- 写入日志：

```text
[CommunityDownload]
Product=Tiny11
Mirror=123
```

或：

```text
[CommunityDownload]
Product=Tiny11
Mirror=GoFile
```

### StarValleyX 语言过滤

StarValleyX 是中文项目，只在中文界面显示。

| 当前语言 | StarValleyX |
| --- | --- |
| 简体中文 `zh` | 显示 |
| 繁体中文 `zh_TW` | 显示 |
| 英文、日文、韩文、德文、法文、西班牙文、葡萄牙文、俄文、阿拉伯文 | 完全隐藏 |

隐藏范围包括：

- 镜像卡片。
- 分类入口。
- 搜索结果。
- 直接访问 `/mirror/starvalleyx` 的路由。

相关实现：

- `lib/features/mirror/models/mirror_models.dart`
- `lib/features/mirror/screens/mirror_screen.dart`
- `lib/features/mirror/screens/mirror_detail_screen.dart`
- `lib/app/routes.dart`

## 6. 工具箱安全提示

数据文件：`data/tools.json`  
当前工具数：27  
当前分类数：9

分类：

| 分类 key | 工具数 |
| --- | ---: |
| `tools_cat_deploy` | 4 |
| `tools_cat_disk` | 4 |
| `tools_cat_hardware` | 4 |
| `tools_cat_network` | 3 |
| `tools_cat_optimize` | 3 |
| `tools_cat_rescue` | 3 |
| `tools_cat_file` | 3 |
| `tools_cat_advanced` | 1 |
| `tools_cat_activation` | 2 |

安全等级：

| 等级 | 数量 | 工具 |
| --- | ---: | --- |
| Beginner | 13 | CrystalDiskInfo, CrystalDiskMark, WizTree, CPU-Z, GPU-Z, HWiNFO, AIDA64, WinSCP, PuTTY, MemTest86, 7-Zip, Everything, TeraCopy |
| Advanced | 10 | Rufus, Ventoy, Dism++, Wireshark, Windhawk, ExplorerPatcher, StartAllBack, Hiren's BootCD PE, Sysinternals Suite, Office Tool Plus |
| Expert | 4 | WinNTSetup, Victoria, GParted Live, HEU KMS Activator |

UI 行为：

- 工具卡片和详情页显示安全等级 badge。
- Dism++ 打开前显示专属 Advanced 提示。
- Windhawk 打开前显示专属 Advanced 提示。
- Expert 工具打开前显示通用 Expert 提示。
- 提示只做风险说明，不阻止用户继续使用。

新增工具：

| 字段 | 内容 |
| --- | --- |
| Name | Sysinternals Suite |
| Developer | Microsoft |
| Category | Advanced Tools |
| Official Website | `https://learn.microsoft.com/sysinternals/` |
| Download | `https://learn.microsoft.com/sysinternals/downloads/` |
| Safety Level | Advanced |

相关实现：

- `lib/features/tools/models/tool_models.dart`
- `lib/features/tools/screens/tools_screen.dart`
- `data/tools.json`
- `lib/core/localization/strings.dart`

## 7. AI 助手

AI 助手页面顶部有免责声明：

- 标题：`AI Assistant Notice`
- 说明 AI 生成内容可能不准确或不完整。
- 提醒用户在应用到系统前自行检查重要操作。
- 按钮：`Got it`、`Do not show again`。
- 本地偏好 key：`ai_assistant_notice_hidden`。

当前 AI API 相关文件：

- `lib/core/config/ai_config.dart`
- `lib/features/ai_assistant/screens/ai_assistant_screen.dart`
- `lib/features/ai_assistant/services/ai_service.dart`

注意事项：

- AI 错误信息必须走本地化字符串，不能拼接未编码或未翻译的中文。
- 如果再次出现连续问号占位符，优先检查响应解码、异常字符串和 PowerShell 输出编码。
- 远程 API 域名或 Worker 出现超时，不等同于本地代码一定错误，需要分别排查网络、域名、TLS 和服务端状态。

## 8. 多语言和编码硬约束

项目支持且只支持 11 种应用语言：

| 代码 | 语言 |
| --- | --- |
| `zh` | 简体中文 |
| `zh_TW` | 繁体中文 |
| `en` | English |
| `fr` | Français |
| `de` | Deutsch |
| `es` | Español |
| `pt` | Português |
| `ru` | Русский |
| `ar` | العربية |
| `ko` | 한국어 |
| `ja` | 日本語 |

当前 `lib/core/localization/strings.dart` 中 11 个语言表均为 588 个 key，覆盖一致。

维护原则：

- 不允许 UI 显示导航、工具分类或镜像文案的原始 key。
- 不允许出现连续问号占位符或 Unicode replacement character。
- 不允许一个语言页面混入另一种语言的普通 UI 文案。
- 专有名词可保留原文，例如 Windows、ISO、USB、Microsoft、WebView2、GoFile、123 Cloud、PowerShell、DISM、NuGet。
- 新增字符串时必须同步补齐 11 个语言表。
- 不要依赖英文 fallback 掩盖缺失翻译；缺 key 应视为问题。
- 翻译要自然，避免逐词机翻，尤其是按钮、警告、错误提示和系统操作文案。

建议每次修改翻译后运行：

```powershell
$env:PYTHONIOENCODING='utf-8'; @'
import pathlib,re
s=pathlib.Path('lib/core/localization/strings.dart').read_text(encoding='utf-8')
langs=['en','zh','zhTW','fr','de','es','pt','ru','ar','ko','ja']
sets={}
for lang in langs:
    m=re.search(r"const _%s = <String, String>\{([\s\S]*?)\n\};"%lang,s)
    keys=re.findall(r"\n\s*'([^']+)'\s*:",m.group(1))
    sets[lang]=set(keys)
print({k:len(v) for k,v in sets.items()})
print('coverage_equal', all(v==sets['en'] for v in sets.values()))
bad_question_marker='?' * 4
replacement_marker=chr(0xfffd)
for path in ['lib/core/localization/strings.dart','data/tools.json','data/mirrors.json']:
    text=pathlib.Path(path).read_text(encoding='utf-8')
    print(path, text.count(bad_question_marker), text.count(replacement_marker))
'@ | python -
```

## 9. PowerShell 和乱码防护

本机已安装 PowerShell 7.6.3，并已设置为默认打开方式。用户 profile 位于：

```text
C:\Users\bob_0\Documents\PowerShell\Microsoft.PowerShell_profile.ps1
```

维护编码规则：

- Dart、JSON、Markdown、PowerShell 脚本默认使用 UTF-8。
- 不要用 Windows PowerShell 5.1 的默认重定向写入中文文件。
- 不要用 `Set-Content`、`Out-File`、`>` 写入非 ASCII 文本，除非明确指定 UTF-8。
- 大段文件编辑优先使用 `apply_patch`。
- 用 Python 读取验证编码可以，但不要用 Python 随手重写源文件。
- 终端输出乱码不一定代表文件已损坏，必须用 UTF-8 读取文件验证。

快速检查乱码：

```powershell
$env:PYTHONIOENCODING='utf-8'; @'
import pathlib
for path in ['HANDOVER.md','lib/core/localization/strings.dart','data/tools.json','data/mirrors.json']:
    text=pathlib.Path(path).read_text(encoding='utf-8')
    bad_question_marker='?' * 4
    replacement_marker=chr(0xfffd)
    print(path, 'question_marker=', text.count(bad_question_marker), 'replacement_marker=', text.count(replacement_marker))
'@ | python -
```

## 10. NuGet 构建兜底

Flutter Windows native asset 构建依赖 `nuget.exe`。当前项目已加入本地兜底脚本：

- `scripts/ensure_nuget.ps1`
- `scripts/build_windows.ps1`
- `scripts/build_installer.ps1`

行为：

- 如果 PATH 中已有 `nuget.exe`，直接使用。
- 如果没有，则下载官方 `https://dist.nuget.org/win-x86-commandline/latest/nuget.exe`。
- 下载后校验 Authenticode 签名。
- 保存到 `.tools\nuget\nuget.exe`。
- 当前进程 PATH 自动加入 `.tools\nuget`。
- 可通过 `-AddToUserPath` 写入用户 PATH 并广播环境变量变化。

普通构建推荐使用：

```powershell
.\scripts\build_windows.ps1
```

只补 NuGet：

```powershell
.\scripts\ensure_nuget.ps1 -AddToUserPath
```

## 11. 构建和验证

获取依赖：

```powershell
flutter pub get
```

静态分析：

```powershell
flutter analyze
```

构建 Windows release，不生成安装包：

```powershell
flutter build windows --release
```

推荐一键流程：

```powershell
.\scripts\build_windows.ps1
```

当前 release exe：

```text
D:\Dev\WinDeployStudio\build\windows\x64\runner\Release\win_deploy_studio.exe
```

最近验证状态：

| 命令 | 状态 |
| --- | --- |
| `flutter analyze` | No issues found |
| `flutter build windows --release` | 成功 |

已知构建提示：

- `webview_windows` 可能产生 CMake developer warning，内容与 `add_custom_command(TARGET): DEPENDS` 有关。
- 该提示来自依赖插件 CMake 配置，当前不影响 release 构建。

## 12. 安装包

构建安装包：

```powershell
.\scripts\build_installer.ps1
```

输出目录：

```text
D:\Dev\WinDeployStudio\dist\windows
```

注意：

- 用户上次明确要求“构建但不构建安装包”，除非再次要求，不要自动生成安装包。
- Inno Setup 脚本内版本和输出文件名必须与应用版本同步。
- 安装包文本文件涉及多语言和编码，修改前必须确认 Inno Setup 对对应语言文件的编码要求。

## 13. 重要风险和后续待办

| 风险 | 等级 | 说明 |
| --- | --- | --- |
| 磁盘操作误选盘 | 高 | Windows 安装盘和 WTG 都涉及清盘、分区、格式化和启动配置，任何磁盘筛选或盘符绑定改动都必须谨慎验证 |
| WTG 分区和盘符 | 高 | 需要确保 DISM 应用目标始终绑定到正确磁盘和正确 Windows 分区，不能依赖“第一个有盘符的分区”这类脆弱规则 |
| 下载校验 | 中 | 多数镜像 `sha256` 仍为空，下载后的完整性校验闭环仍不完整 |
| 更新器安全 | 中 | 更新包下载流程应持续关注签名、哈希和来源校验 |
| WebView 下载 | 中 | WebView 下载页依赖第三方站点行为，GoFile、123 Cloud、Cloudflare 或区域网络变化可能影响体验 |
| AI 远程服务 | 中 | Worker 或上游 API 超时会导致 AI 不可用，需要服务端和客户端分别排查 |
| 多语言回退 | 中 | 新增 UI 字符串必须同步 11 种语言，否则可能出现 key 直出或混语言 |
| 依赖升级 | 低 | Flutter 和依赖已更新到当前可用范围，后续升级仍需跑分析和 Windows 构建 |

## 14. 修改前检查清单

改 UI 文案：

- 检查 `strings.dart` 是否 11 语言全补齐。
- 检查是否有 key 直出。
- 检查是否引入连续问号占位符或 Unicode replacement character。

改镜像中心：

- Official Microsoft 不得走镜像选择和 WebView2。
- Community Images 必须保留 123 Cloud / GoFile 选择。
- StarValleyX 非中文必须隐藏，包括搜索和直达路由。
- `font-pack` 属于 Tools，不属于 Official Microsoft 或 Community Images。

改工具箱：

- 新工具必须设置 `safetyLevel`。
- Advanced 和 Expert 文案必须专业、克制，不把工具标记成“不安全”。
- Dism++、Windhawk、Expert 工具打开前必须继续显示提示。

改构建脚本：

- 不要破坏 `ensure_nuget.ps1`。
- 不要硬编码过期版本号。
- 构建脚本应能在没有全局 NuGet 的环境下工作。

改磁盘/部署流程：

- 必须优先保护系统盘、启动盘和内置数据盘。
- 盘符必须绑定到明确磁盘/分区，不能依赖全局最后一个盘符。
- 清盘、格式化、DISM、BCD 操作前必须有明确确认和日志。

## 15. 快速事实

| 项目 | 当前值 |
| --- | --- |
| 应用名 | WinDeploy Studio |
| 版本 | 1.1.0 |
| Flutter | 3.44.4 stable |
| Dart | 3.12.2 |
| 支持语言 | 11 |
| 本地化 key 数 | 588/语言 |
| 镜像条目 | 8 |
| 工具条目 | 27 |
| 工具分类 | 9 |
| AdBlock | 已删除，未启用 |
| 默认构建脚本 | `scripts/build_windows.ps1` |
| release exe | `build\windows\x64\runner\Release\win_deploy_studio.exe` |
