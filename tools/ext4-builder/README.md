# Windows Ext4 Persistence Builder

`wds_ext4_builder.exe` is the narrow helper used by WinDeploy Studio to create
regular ext4 persistence image files for supported Linux To Go layouts. It does
not accept a disk number, a device namespace path, a network path, a source
directory, or arbitrary files. Its only optional content is the fixed Debian
`/persistence.conf` file containing `/ union`.

The helper writes to a randomized sibling temporary file, finalizes and closes
the filesystem, then atomically renames that file to the requested output. It
rejects an existing output path and any path outside a local drive letter.

## Source And Build

- Upstream: https://github.com/pilat/go-ext4fs
- Pinned commit: `ad8cccf4a20ceb956f2180ef5b3f728cbbc0b6d7`
- Pinned source archive: https://codeload.github.com/pilat/go-ext4fs/zip/ad8cccf4a20ceb956f2180ef5b3f728cbbc0b6d7
- Upstream archive SHA-256: `cc59f1c8a1b7bcc6013c8d656b1cbb2f8ac5221a7588082d72ed1fb6f0516ea3`
- Upstream license: MIT, copyright (c) 2025 Vladimir Urushev
- Wrapper source: `main.go`
- Vendored source: `source/go-ext4fs`
- Go toolchain used for this release: Go `1.21.13` windows/amd64
- Go SDK archive SHA-256: `924655193634bfcdf7ec7a34589e0d73458741998a59e4155a929ce85f81af2d`
- Bundled helper SHA-256: `85f4c3e74f6e005ecf94e0d688e1de6d35b715af21716151c4a23e9f52ab6184`

Build with Go 1.21 or newer:

```powershell
.\build.ps1 -GoExe C:\path\to\go.exe
```

The build disables cgo and links only the Go runtime and standard library. The
vendored production ext4 source imports only the Go standard library; entries
in the upstream `go.mod` beyond that are test-only dependencies.

## Format Scope

Images are valid ext4 filesystems with extents, file types, sparse-superblock,
large-file, and extra-inode-size features. The upstream library deliberately
does not implement journaling, metadata checksums, 64-bit block addressing,
flex_bg, or HTree indexing. These restrictions are suitable for the bounded
4 MiB to 4095 MiB Linux To Go persistence images, but actual boot and repeated
persistence tests remain required for each supported Linux profile.

License texts are in `LICENSES`. The full, modified upstream source and local
change record are included in this directory.
