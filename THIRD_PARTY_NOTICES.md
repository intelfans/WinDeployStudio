# Third-Party Notices

## e2fsprogs Status

This release does **not** redistribute e2fsprogs, `mke2fs.exe`, Cygwin, or an
ext4-creation component. Linux To Go persistence is disabled until the project
can ship a reproducible component together with its complete corresponding
source and all required notices.

The source tree retains the protocol implementation and a compliance checklist
only. It contains no e2fsprogs code. See
[`tools/e2fsprogs/README.md`](tools/e2fsprogs/README.md) for the release gate.

For reference, the e2fsprogs `mke2fs` utility is GPL-2.0-only. Any future
binary distribution must include the exact GPLv2 obligations; a generic AOSP or
upstream URL is not a substitute for complete corresponding source.

## CrystalDiskInfo

Portions of the disk diagnostics bridge-compatibility logic were derived from
the public protocol layouts and compatibility behavior in CrystalDiskInfo.

- Upstream: https://github.com/hiyohiyo/CrystalDiskInfo
- Source revision: `fdc8bce73ab0355c513c758ebf0f0f22662830e2` (9.9.1)
- Referenced files: `AtaSmart.cpp`, `AtaSmart.h`
- Copyright (c) 2008-2023 hiyohiyo

The affected WinDeployStudio code is independently implemented and only sends
read-only SMART, ATA identify, or NVMe health-log requests. It does not include
or redistribute CrystalDiskInfo binaries or its optional bridge DLLs.

CrystalDiskInfo is distributed under the following MIT License:

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
