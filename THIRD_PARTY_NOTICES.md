# Third-Party Notices / 第三方声明

This document identifies third-party projects and license material relevant to
the source tree and distributed application. English license texts below
remain the authoritative license texts; the Chinese sections are explanatory
translations for readers of this project.

本文说明与源代码和所分发应用有关的第三方项目及许可材料。下方英文许可证
原文仍为具有约束力的许可证文本；中文内容仅为便于本项目读者理解的说明性翻译。

## CrystalDiskInfo / CrystalDiskInfo

Portions of the disk diagnostics bridge-compatibility logic were derived from
the public protocol layouts and compatibility behavior in CrystalDiskInfo.

- Upstream: https://github.com/hiyohiyo/CrystalDiskInfo
- Source revision: `fdc8bce73ab0355c513c758ebf0f0f22662830e2` (9.9.1)
- Referenced files: `AtaSmart.cpp`, `AtaSmart.h`
- Copyright (c) 2008-2023 hiyohiyo

The affected WinDeploy Studio code is independently implemented and only sends
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
