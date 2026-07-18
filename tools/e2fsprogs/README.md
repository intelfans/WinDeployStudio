# e2fsprogs Compliance Gate

This release deliberately contains no `mke2fs.exe`, e2fsprogs binary, or
Cygwin runtime. Linux To Go does not use e2fsprogs: its narrowly scoped,
verified persistence path uses the separately documented `wds_ext4_builder.exe`
helper built from pinned MIT-licensed `go-ext4fs` source. That helper is only
used after a supported x64 UEFI + GPT Ubuntu/casper, Debian Live, or Deepin
Live profile passes structural preflight; it is not a general Linux To Go or
ext4 formatting tool.

中文说明：本版本不包含 `mke2fs.exe`、e2fsprogs 二进制文件或 Cygwin 运行时。
Linux To Go 不会调用 e2fsprogs；其受限且已校验的持久化路径使用另行说明的
`wds_ext4_builder.exe`，该工具由固定版本、MIT 许可的 `go-ext4fs` 源码构建。
只有通过结构预检的 x64 UEFI + GPT Ubuntu/casper、Debian Live 或 Deepin Live
配置才会使用该工具；它不是通用的 Linux To Go 或 ext4 格式化工具。

The previously evaluated binary was a Google-signed Windows x86 Android SDK
build reporting `mke2fs 1.47.2 (1-Jan-2025)` and
`android-platform-15.0.0_r5-314-ga1f793f6b`. It was removed because the project
did not possess the complete corresponding source required for GPLv2
redistribution, including its exact build scripts and all statically linked
components.

`mke2fs` is GPL-2.0-only. A future release may include it only as a separate
command-line component, never linked into the Flutter application, and only if
all of the following are shipped together:

1. The exact tool binary and SHA-256.
2. The full GPLv2 text and all notices for every linked component.
3. Complete corresponding source for that exact binary, including patches,
   configuration, build scripts, toolchain inputs, and static dependencies.
4. A stable, immutable release URL for that source plus a real three-year
   written source offer from the project publisher.
5. Automated build and packaging checks that fail when any required item is
   absent.

References for audit only, not as a substitute for corresponding source:

- e2fsprogs project: https://e2fsprogs.sourceforge.net/
- AOSP commit: https://android.googlesource.com/platform/external/e2fsprogs/+/a1f793f6b1d0d063c7252704e11c475d3040ce85
- GPLv2 section 3: https://www.gnu.org/licenses/old-licenses/gpl-2.0.en.html
