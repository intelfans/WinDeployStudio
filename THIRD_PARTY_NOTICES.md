# Third-Party Notices / 第三方声明

This document identifies third-party projects and license material relevant to
the source tree and distributed helpers. English license texts below remain
the authoritative license texts; the Chinese sections are explanatory
translations for readers of this project.

本文说明与源代码和随附辅助工具有关的第三方项目及许可材料。下方英文许可证
原文仍为具有约束力的许可证文本；中文内容仅为便于本项目读者理解的说明性翻译。

## ArchISO And KIWI Interoperability / ArchISO 与 KIWI 互操作性

ArchISO and KIWI are separate GPLv3-licensed upstream projects. The source
tree contains independently written interoperability research and structural
preflight components for public on-disk layouts, documented boot parameters,
and the observable behavior of normal ArchISO- and KIWI-produced ISO images.
They are not bundled ArchISO or KIWI dependencies, and they do not incorporate
upstream source code.

No ArchISO or KIWI source code, binaries, scripts, initrd components,
libraries, headers, generated files, or patches are copied into, linked by,
bundled with, or distributed by WinDeploy Studio. In particular, the app does
not ship an ArchISO/KIWI executable or modify either project's source.

This is an interoperability notice, not a notice for bundled GPL code. The
licenses for ArchISO, KIWI, and each distribution ISO remain with their
respective upstream projects and apply to the copies obtained by the user.
Users remain responsible for complying with those licenses when downloading,
using, or redistributing an ISO.

### 中文说明

ArchISO 与 KIWI 是分别采用 GPLv3 许可的上游项目。本项目源代码中包含独立
编写的互操作性研究和结构预检组件，用于理解公开的磁盘布局、已文档化的启动
参数，以及常规 ArchISO、KIWI 生成 ISO 的可观察行为。这些组件不是随附的
ArchISO 或 KIWI 依赖项，也未包含上游源码。

WinDeploy Studio 不复制、链接、捆绑或分发 ArchISO/KIWI 的源码、二进制文件、
脚本、initrd 组件、库、头文件、生成文件或补丁，亦不会随应用提供 ArchISO/
KIWI 可执行程序或修改其上游源码。用户提供的 ISO 只有在通过严格结构检查后
才会被相关代码处理。

本节是互操作性说明，不代表项目分发了 GPL 代码。ArchISO、KIWI 及各发行版
ISO 的许可仍由相应上游项目决定，并适用于用户获取的副本。下载、使用或再
分发 ISO 时，用户仍需自行遵守相应许可。

- ArchISO upstream: https://gitlab.archlinux.org/archlinux/archiso
- KIWI upstream: https://github.com/OSInside/kiwi

## Linux To Go Ext4 Persistence Builder / Linux To Go Ext4 持久化镜像工具

Linux To Go persistence uses `wds_ext4_builder.exe`, a narrow helper built
from the vendored `go-ext4fs` source. It only creates a regular image file on
an existing local drive. It rejects physical-device, network, existing-output,
and arbitrary-content inputs; Debian mode can write only `/persistence.conf`
with `/ union`.

- Upstream: https://github.com/pilat/go-ext4fs
- Pinned source commit: `ad8cccf4a20ceb956f2180ef5b3f728cbbc0b6d7`
- Upstream source archive:
  https://codeload.github.com/pilat/go-ext4fs/zip/ad8cccf4a20ceb956f2180ef5b3f728cbbc0b6d7
- Upstream archive SHA-256:
  `cc59f1c8a1b7bcc6013c8d656b1cbb2f8ac5221a7588082d72ed1fb6f0516ea3`
- Bundled helper SHA-256:
  `85f4c3e74f6e005ecf94e0d688e1de6d35b715af21716151c4a23e9f52ab6184`
- Source, local changes, build script, and license texts:
  [`tools/ext4-builder`](tools/ext4-builder)

WinDeploy Studio adds a backward-compatible `WithUUID` option to the vendored
source so each persistence image receives a cryptographically random RFC 4122
v4 UUID. The full local change record is in
[`tools/ext4-builder/PATCHES.md`](tools/ext4-builder/PATCHES.md). The
application verifies the helper SHA-256 before any Linux To Go target-disk
operation.

The helper is built with Go 1.21.13, `CGO_ENABLED=0`, and links the Go runtime
and standard library statically. It does not redistribute e2fsprogs, Cygwin,
or `mke2fs.exe`. The earlier Google/AOSP e2fsprogs binary remains excluded
because its GPLv2 corresponding-source and static-dependency inputs were not
available to this project.

### 中文说明

Linux To Go 的持久化功能使用 `wds_ext4_builder.exe`。这是一个功能受限的
辅助工具，基于随仓库提供的 `go-ext4fs` 固定版本源码构建，只会在既有本地
驱动器上创建普通镜像文件；它会拒绝物理设备、网络位置、已存在的输出文件和
任意内容输入。Debian 兼容模式只会写入 `/persistence.conf` 中的 `/ union`。

项目在 vendored 源码中加入向后兼容的 `WithUUID` 选项，使每个持久化镜像都
拥有加密随机的 RFC 4122 v4 UUID；完整本地改动记录见
[`tools/ext4-builder/PATCHES.md`](tools/ext4-builder/PATCHES.md)。在任何 Linux
To Go 目标磁盘操作前，应用都会校验该辅助工具的 SHA-256。

该工具使用 Go 1.21.13、`CGO_ENABLED=0` 构建，并静态链接 Go 运行时和标准库。
项目不再分发 e2fsprogs、Cygwin 或 `mke2fs.exe`；此前的 Google/AOSP e2fsprogs
二进制文件同样未被包含，因为项目无法取得其 GPLv2 完整对应源码及静态依赖输入。

英文 MIT 许可证原文如下：

```text
MIT License

Copyright (c) 2025 Vladimir Urushev

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in
all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
THE SOFTWARE.
```

## Go Runtime And Standard Library / Go 运行时与标准库

The statically linked Go runtime and standard library in
`wds_ext4_builder.exe` are distributed under the following BSD-style license.
The complete text is also included at
[`tools/ext4-builder/LICENSES/GO_LICENSE`](tools/ext4-builder/LICENSES/GO_LICENSE).

### 中文说明

`wds_ext4_builder.exe` 中静态链接的 Go 运行时和标准库采用下列 BSD 风格许可。
完整英文许可证文本也保存在
[`tools/ext4-builder/LICENSES/GO_LICENSE`](tools/ext4-builder/LICENSES/GO_LICENSE)。
英文许可证原文如下：

```text
Copyright (c) 2009 The Go Authors. All rights reserved.

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are met:

   * Redistributions of source code must retain the above copyright
notice, this list of conditions and the following disclaimer.
   * Redistributions in binary form must reproduce the above
copyright notice, this list of conditions and the following disclaimer
in the documentation and/or other materials provided with the
distribution.
   * Neither the name of Google Inc. nor the names of its
contributors may be used to endorse or promote products derived from
this software without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
"AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
(INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
```

## CrystalDiskInfo / CrystalDiskInfo

Portions of the disk diagnostics bridge-compatibility logic were derived from
the public protocol layouts and compatibility behavior in CrystalDiskInfo.

- Upstream: https://github.com/hiyohiyo/CrystalDiskInfo
- Source revision: `fdc8bce73ab0355c513c758ebf0f0f22662830e2` (9.9.1)
- Referenced files: `AtaSmart.cpp`, `AtaSmart.h`
- Copyright (c) 2008-2023 hiyohiyo

The affected WinDeployStudio code is independently implemented and only sends
read-only SMART, ATA identify, or NVMe health-log requests. It does not include
or redistribute CrystalDiskInfo binaries or its optional bridge DLLs.

### 中文说明

磁盘诊断桥接兼容逻辑参考了 CrystalDiskInfo 公开的协议布局和兼容性行为，相关
上游仓库、版本和文件见上方列表。受影响的 WinDeploy Studio 代码为独立实现，
只发送只读 SMART、ATA identify 或 NVMe 健康日志请求；项目不包含也不再分发
CrystalDiskInfo 二进制文件及其可选桥接 DLL。

CrystalDiskInfo is distributed under the following MIT License:

CrystalDiskInfo 采用 MIT 许可证，英文许可证原文如下：

```text
MIT License

Copyright (c) 2008-2023 hiyohiyo

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```
