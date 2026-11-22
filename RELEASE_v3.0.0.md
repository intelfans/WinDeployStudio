<!-- wds:lang=en -->

# 🚀 WinDeploy Studio v3.0.0

> ⚡ **Major update:** a new AI platform, a stricter trust model for updates and
> downloads, verified disk writes, and a selectable Windows appearance.

This release replaces the retired AI model, moves web search behind the
project's own gateway, adds explicit consent wherever data leaves the machine,
and closes a set of defects found during a full audit of the deployment and
update paths.

## ✨ Highlights

- 🤖 AI Assistant runs on the current provider model, and retired model names
  are migrated automatically.
- 🔎 Web search is served by the project gateway with a server-side credential,
  a per-hour allowance, and automatic fallback when it is unavailable.
- 🙋 Every web search now shows the exact text that will be sent, and the
  service that will receive it, before anything leaves the device.
- 🛡️ Updates keep the release digest as a hard requirement and ask the user
  explicitly before running an installer that carries no publisher signature.
- 💽 Linux installation media verifies the written device after the disk is
  brought back online, not only while the write handle is still open.
- 🎨 All four Windows appearance skins (Auto, Windows 11, Windows 10, Windows 7)
  can now be selected in Settings.

## 🤖 AI Assistant

- The bundled default model is now `mimo-v2.6-pro`. Retired identifiers
  (`mimo-v2.5-pro`, `mimo-v2.5`, `mimo-v2-pro`, `mimo-v2-omni`,
  `mimo-v2-flash`) are rewritten to their replacements both in the application
  and at the gateway, so an installed build keeps working without a manual
  setting change.
- Web search prefers the project gateway, which holds the search credential
  server-side; the client never ships a search key. Keyless sources remain as
  fallback.
- A rolling hourly allowance bounds the gateway search cost. When it is spent,
  search continues through the fallback sources instead of failing.
- The search confirmation dialog names the recipient and prints the exact query
  text. Declining drops the search rather than rerouting it.

## 🔐 Trust And Privacy

- The release SHA-256 digest and file size remain hard requirements before an
  installer may run.
- Published installers are not Authenticode-signed. Rather than failing
  silently, the application now reports that the publisher cannot be verified
  and asks for explicit consent. Consent waives publisher identity only; the
  digest check still applies.
- Download requests enforce HTTPS and refuse loopback, link-local, and RFC1918
  targets on every redirect hop, not only for the download's first host.
- Image identity is decided by SHA-256 alone. A matching MD5 no longer
  identifies an image, which removes a practical collision shortcut.
- The installer privacy option is honoured through a machine-wide policy, and
  it now also covers the geolocation request used for mirror selection.

## 💿 Installation Media

- Linux raw writes exclude the GPT header from the byte comparison: Windows
  rewrites that header with the physical disk geometry when the disk comes back
  online, and the old comparison could never succeed on a disk larger than the
  image.
- The written device is compared again after it is online, from a fresh read
  handle, so a completion result describes the media the user actually keeps.
- The disk safety check now fails closed: an unknown system-disk flag is treated
  as a system disk instead of a safe external target.

## 🎨 Interface

- Settings offers the four appearance skins. Default behaviour follows the
  operating system; the Windows 11 skin remains the default on unsupported
  systems.
- The first-run tour no longer throws on a short window.
- The Tools page shows a loading failure instead of an endless spinner.

## 🧭 Localization And Logs

- Benchmark result labels are translated in all 11 languages instead of
  branching on Chinese versus everything else.
- Diagnostic logs are written as structured `key=value` records. They no longer
  depend on the interface language, so exported support logs and AI analysis
  stay consistent for every user.

## 🛠️ Build And Packaging

- The installer records a machine-wide AI opt-out policy, removes its own data
  on uninstall, installs only the application payload instead of the whole
  build directory, and requires Windows 10 1809 or later.
- The release script runs the automated test suite before packaging and refuses
  to delete directories outside the repository.

## 📦 Installer Integrity

- File: `WinDeployStudio_Setup_3.0.0.exe`
- Size: `48.38 MB`
- SHA-256: `9337FB02777FFF9347CC032377640909146078E229D0F9137213ECDE59FB12BF`
- Publisher signature: not signed. The application verifies the release digest
  and asks for explicit confirmation before running it.

## ⚠️ Important Notes

- Installation Media and Windows To Go can erase the selected target disk.
  Verify the physical device and back up important data before continuing.
- Linux Installation Media writes ISOHybrid images as provided. Secure Boot and
  firmware compatibility depend on the distribution image and target computer.
- Image availability, licensing, language, and redistribution terms remain the
  responsibility of each image publisher and the user.

---

<!-- wds:lang=zh -->

# 🚀 WinDeploy Studio v3.0.0

> ⚡ **重大更新：** 全新 AI 平台、更严格的更新与下载信任模型、经过验证的磁盘
> 写入，以及可选择的 Windows 外观。

本版本替换了已下线的 AI 模型，把联网搜索移到项目自己的网关，在任何数据离开
本机之前加入明确确认，并修复了完整审计中发现的一批部署与更新缺陷。

## ✨ 主要更新

- 🤖 AI 助手使用当前供应商模型，已下线的模型名会自动迁移。
- 🔎 联网搜索由项目网关提供，密钥保存在服务端，带每小时额度，不可用时自动回退。
- 🙋 每次联网搜索都会先显示将要发送的确切文字和接收方，用户确认后才会发出。
- 🛡️ 更新仍然强制校验发布哈希，并在安装未签名安装包前明确询问用户。
- 💽 Linux 安装盘会在磁盘恢复联机之后再次校验，而不只是在写句柄仍打开时校验。
- 🎨 设置中可以选择全部四套 Windows 外观（自动、Windows 11、Windows 10、
  Windows 7）。

## 🤖 AI 助手

- 内置默认模型改为 `mimo-v2.6-pro`。已下线的名称（`mimo-v2.5-pro`、
  `mimo-v2.5`、`mimo-v2-pro`、`mimo-v2-omni`、`mimo-v2-flash`）会在应用内和
  网关处同时改写为对应新模型，已安装的版本无需手动改设置即可继续使用。
- 联网搜索优先使用项目网关，搜索密钥只保存在服务端，客户端不下发任何搜索密钥；
  仍然保留无需密钥的来源作为回退。
- 滚动的一小时额度限制网关搜索成本。额度用尽后，搜索改走回退来源，而不是直接失败。
- 搜索确认框会显示接收方和将要发送的确切查询文字。用户取消时，搜索会被放弃，
  不会改走其他来源。

## 🔐 信任与隐私

- 安装包运行前仍然强制校验发布 SHA-256 与文件大小。
- 公开发布的安装包没有 Authenticode 签名。应用不再静默失败，而是说明无法验证
  发布者并请求用户明确同意。同意只豁免发布者身份，哈希校验依然生效。
- 下载请求对每一跳都强制 HTTPS，并拒绝环回、链路本地和 RFC1918 地址，不再只
  保护下载的起始地址。
- 镜像身份只由 SHA-256 决定。仅有相同的 MD5 不再认定镜像，消除了实际的碰撞捷径。
- 安装程序的隐私选项通过计算机级策略生效，并且现在也覆盖镜像选择所用的地理位置
  请求。

## 💿 安装盘

- Linux 原始写入在逐字节比对时排除 GPT 头：磁盘恢复联机时 Windows 会按物理磁盘
  几何尺寸重写该头部，旧逻辑在比镜像更大的磁盘上永远不可能通过。
- 磁盘联机之后会重新打开设备再做一次比对，因此完成结果描述的是用户最终拿到的那块
  磁盘。
- 磁盘安全检查改为失败即拒绝：无法确认的系统盘标记按系统盘处理，而不是当作安全的
  外接目标。

## 🎨 界面

- 设置中提供四套外观。默认跟随操作系统；系统不支持时仍然使用 Windows 11 外观。
- 首次启动导览在窗口较小时不再抛出异常。
- 工具页面在加载失败时显示错误状态，而不是一直转圈。

## 🧭 多语言与日志

- 磁盘测试的结果标签在全部 11 种语言中都有翻译，不再只按中文与其他语言二分。
- 诊断日志改为结构化的 `key=value` 记录，不再依赖界面语言，因此导出的支持日志
  和 AI 分析对所有用户保持一致。

## 🛠️ 构建与打包

- 安装程序写入计算机级的 AI 禁用策略，卸载时清理自身数据，只安装应用本体而不是
  整个构建目录，并要求 Windows 10 1809 或更高版本。
- 发布脚本在打包前运行自动化测试，并拒绝删除仓库之外的目录。

## 📦 安装包完整性

- 文件：`WinDeployStudio_Setup_3.0.0.exe`
- 大小：`48.38 MB`
- SHA-256：`9337FB02777FFF9347CC032377640909146078E229D0F9137213ECDE59FB12BF`
- 发布者签名：未签名。应用会校验发布哈希，并在运行前请求用户明确确认。

## ⚠️ 重要说明

- 安装盘和 Windows To Go 会清除所选目标磁盘，请确认物理设备并提前备份重要数据。
- Linux 安装盘按发行版提供的 ISOHybrid 镜像原样写入；Secure Boot 和固件兼容性
  取决于所选镜像及目标电脑。
- 镜像的可用性、许可证、语言及再分发条款仍由镜像发布者和用户自行确认。
