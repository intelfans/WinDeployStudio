## 🚀 WinDeploy Studio v1.1.0

### ✨ New Features
- Refactored **Image Center** into clear source categories
  - Added **Official Microsoft** category for Windows 10 and Windows 11
  - Added **Community Images** category for Tiny11, Tiny10, Windows X-Lite, and StarValleyX
  - Official Microsoft downloads now open Microsoft's website in the system browser
  - Community images continue using China Mirror and Global Mirror selection

- Added **Advanced Tool Safety Notices**
  - Introduced Beginner, Advanced, and Expert safety levels
  - Added notices for DISM++, Windhawk, expert tools, and activation-related utilities
  - Added Microsoft **Sysinternals Suite** to Toolbox

- Improved **Windows To Go** waiting experience
  - Keeps only reliable elapsed time during image application
  - Adds a small UI-only waiting game during long imaging operations
  - Improves external USB/NVMe disk compatibility display

### ⚙️ Improvements
- Improved trust and transparency for official and community image sources
- Hid StarValleyX for non-Chinese UI languages to avoid confusion
- Replaced restrictive installer EULA content with an MIT-friendly Open Source Notice
- Added Special Thanks section for community feedback and support
- Renamed the Windows installation media feature to a clearer beginner-friendly name
- Removed default download source settings and related UI leftovers
- Updated all app, Windows, installer, script, and documentation version references to **1.1.0**

### 🛠 Fixes
- Fixed external USB/NVMe disks showing `0 B`, `Unknown`, or `N/A` in WTG compatibility results
- Fixed misleading WTG image application metrics such as written size, write speed, and remaining size
- Fixed low-speed warning being triggered by unreliable synthetic progress data
- Fixed English navigation labels showing localization keys such as `nav_xxx`
- Fixed text clipping in recommendation and tool cards
- Fixed AI error messages displaying unreadable placeholder characters in some cases
- Fixed installer licensing text that conflicted with the MIT License

### 📌 Notes
This update focuses on trust, safety, clarity, and international usability.

Official Microsoft images now always redirect users to Microsoft's official download websites. Community images remain available through the existing mirror-based download flow.

WTG creation behavior remains stable. The progress display now avoids unreliable synthetic data and shows only dependable elapsed time during image application.

---

## 🚀 WinDeploy Studio v1.1.0

### ✨ 新增功能
- 重构 **镜像中心** 来源分类
  - 新增 **Official Microsoft** 分类，包含 Windows 10 与 Windows 11
  - 新增 **Community Images** 分类，包含 Tiny11、Tiny10、Windows X-Lite 和 StarValleyX
  - Microsoft 官方镜像下载现在会使用系统浏览器打开 Microsoft 官方网站
  - 社区镜像继续保留中国镜像与全球镜像选择流程

- 新增 **高级工具安全提示系统**
  - 引入 Beginner、Advanced、Expert 三个安全等级
  - 为 DISM++、Windhawk、专家级工具和激活相关工具增加专业提示
  - 工具箱新增 Microsoft **Sysinternals Suite**

- 改进 **Windows To Go** 等待体验
  - 应用镜像阶段只保留可靠的已用时间
  - 长时间写入时新增纯 UI 小游戏用于打发等待时间
  - 改进外接 USB/NVMe 磁盘的兼容性信息显示

### ⚙️ 优化改进
- 提升官方镜像与社区镜像来源的透明度和可信度
- 非中文界面下隐藏 StarValleyX，避免国际用户困惑
- 将安装包中限制性 EULA 替换为符合 MIT License 的开源说明
- 新增 Special Thanks 区域，感谢反馈、测试和社区支持
- 将 Windows 安装盘创建相关命名改得更适合新手理解
- 删除设置中的默认下载源选项及相关残留界面
- 将应用、Windows 元数据、安装包、脚本和文档中的版本号统一更新为 **1.1.0**

### 🛠 问题修复
- 修复外接 USB/NVMe 磁盘在 WTG 兼容性结果中显示 `0 B`、`Unknown` 或 `N/A` 的问题
- 修复 WTG 应用镜像阶段已写入大小、写入速度、剩余大小等指标误导用户的问题
- 修复低速警告被不可靠的合成进度数据误触发的问题
- 修复英文左侧导航显示 `nav_xxx` 等本地化键名的问题
- 修复推荐卡片和工具卡片文字显示不全的问题
- 修复部分情况下 AI 错误消息出现不可读占位字符的问题
- 修复安装包许可文本与 MIT License 冲突的问题

### 📌 更新说明
本次更新重点提升来源可信度、工具安全提示、界面清晰度与国际化体验。

Microsoft 官方镜像现在始终跳转至 Microsoft 官方下载网站。社区镜像继续保留原有基于镜像源选择的下载流程。

WTG 创建流程保持稳定。本次仅调整进度显示逻辑：应用镜像阶段不再展示不可靠的合成写入数据，而是只显示可信的已用时间。
