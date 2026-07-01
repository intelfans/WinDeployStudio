## WinDeploy Studio v1.1.2

### New Features

- Added clearer community image download logging
  - Logs community image downloads using the `[CommunityDownload]` format
  - Records product names such as `Tiny11`, `Tiny10`, and LTSC entries
  - Records selected mirrors such as `123` and `GoFile`

### Improvements

- Improved disk detection and diagnostics
  - Disk enumeration now uses structured PowerShell JSON parsing
  - Partition metadata is now populated correctly
  - Drive letters are read from both partition data and disk metadata

- Improved Windows To Go reliability
  - Temporary EFI and Windows drive letters are selected from actually available letters
  - Existing volumes and file-system PSDrives are both checked before assigning letters
  - Reduces the chance of conflicting with hidden, mapped, or special drive letters

- Improved Image Center warning flow
  - Enterprise/LTSC expert notice now appears only before download
  - Browsing categories and detail pages no longer triggers repeated warnings

- Updated project metadata to v1.1.2
  - App version
  - Windows executable metadata
  - Installer metadata
  - README, Changelog, handover notes, and release notes

### Fixes

- Fixed removable disk diagnostics showing partition count as `0`
- Fixed fragile hand-written disk JSON parsing
- Fixed WTG drive-letter reservation relying on filesystem existence checks only
- Fixed the in-app updater blocking unsigned WinDeploy Studio project installers while still logging signature status
- Fixed duplicate Russian installer messages
- Fixed Windows build script analysis behavior to match the installer build script

### Notes

This release focuses on reliability and polish. Windows To Go and Windows installation media creation workflows are unchanged except for safer temporary drive-letter handling and more accurate disk metadata.

---

## WinDeploy Studio v1.1.2

### 新增功能

- 新增更清晰的社区镜像下载日志
  - 社区镜像下载会按 `[CommunityDownload]` 格式记录
  - 记录 `Tiny11`、`Tiny10`、LTSC 等产品名称
  - 记录所选镜像源，例如 `123` 和 `GoFile`

### 优化改进

- 改进磁盘识别与诊断
  - 磁盘枚举改为使用结构化 PowerShell JSON 解析
  - 分区信息现在会被正确填充
  - 盘符会同时从分区数据和磁盘元数据读取

- 改进 Windows To Go 可靠性
  - 临时 EFI 分区盘符和 Windows 分区盘符会从实际可用盘符中选择
  - 分配前会同时检查现有卷和文件系统 PSDrive
  - 降低与隐藏盘符、映射盘符或特殊盘符冲突的概率

- 改进镜像中心提示流程
  - Enterprise/LTSC 专家提示现在只在下载前显示
  - 浏览分类和详情页不再触发重复提示

- 更新项目元数据到 v1.1.2
  - 应用版本
  - Windows 可执行文件元数据
  - 安装包元数据
  - README、Changelog、交接文档和 Release 文档

### 问题修复

- 修复可移动磁盘诊断中分区数量始终显示为 `0` 的问题
- 修复磁盘检测中手写 JSON 解析不可靠的问题
- 修复 WTG 临时盘符选择只依赖文件系统存在性检查的问题
- 修复应用内更新器会阻止未签名 WinDeploy Studio 项目安装包启动的问题，同时保留签名状态日志
- 修复安装包中重复的俄语自定义消息
- 修复 Windows 构建脚本的分析行为，使其与安装包构建脚本保持一致

### 更新说明

本版本以可靠性和细节修复为主。Windows To Go 和 Windows 安装盘创建流程保持不变，仅改进临时盘符选择安全性和磁盘元数据准确性。
