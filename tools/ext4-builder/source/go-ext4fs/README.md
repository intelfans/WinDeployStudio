# go-ext4fs

**Create ext4 filesystem images in pure Go — no root, no loop devices, no mke2fs.**

[![Go Reference](https://pkg.go.dev/badge/github.com/pilat/go-ext4fs.svg)](https://pkg.go.dev/github.com/pilat/go-ext4fs)
[![Go Report Card](https://goreportcard.com/badge/github.com/pilat/go-ext4fs)](https://goreportcard.com/report/github.com/pilat/go-ext4fs)
[![CI](https://github.com/pilat/go-ext4fs/actions/workflows/ci.yml/badge.svg)](https://github.com/pilat/go-ext4fs/actions/workflows/ci.yml)
[![Coverage](https://codecov.io/github/pilat/go-ext4fs/graph/badge.svg)](https://codecov.io/github/pilat/go-ext4fs)
[![Go Version](https://img.shields.io/github/go-mod/go-version/pilat/go-ext4fs)](https://github.com/pilat/go-ext4fs)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

go-ext4fs writes ext4 images entirely in userspace, on any OS Go runs on. It started
on macOS, where a microVM needs an ext4 root filesystem and the host can't make one:
no loop devices, no kernel ext4 driver, no `mkfs.ext4`. So the library builds the
bytes itself, with no system calls and no privileges.

```go
package main

import "github.com/pilat/go-ext4fs"

func main() {
	img, err := ext4fs.New(
		ext4fs.WithImagePath("disk.img"),
		ext4fs.WithSizeInMB(64),
	)
	if err != nil {
		panic(err)
	}
	defer img.Close()

	etc, _ := img.CreateDirectory(ext4fs.RootInode, "etc", 0755, 0, 0)
	img.CreateFile(etc, "hostname", []byte("myhost\n"), 0644, 0, 0)
	img.CreateSymlink(etc, "hosts", "/etc/hostname", 0, 0)
	img.SetXattr(etc, "security.selinux", []byte("system_u:object_r:etc_t:s0"))

	if err := img.Save(); err != nil {
		panic(err)
	}
}
```

Mount the result on any Linux kernel since 2.6.28.

## Why

The usual ways to build an ext4 image all want something your build host may not have:
`mkfs.ext4 -d` wants e2fsprogs installed, loop mounts want root and a Linux kernel,
Docker wants a daemon. That's fine on a Linux workstation and miserable everywhere
else — macOS laptops, Windows CI runners, hermetic build systems.

go-ext4fs needs none of it. It is a single Go dependency that turns a directory of
your bytes into a valid ext4 image, the same way on every platform. It exists because
two real systems needed it: a macOS container runtime that packs OCI layers into
microVM root filesystems, and [fleetbox](https://github.com/pilat/fleetbox), which
packs test fixtures into block devices for real Linux VMs.

## Installation

```bash
go get github.com/pilat/go-ext4fs
```

## Features

- **Pure Go** — no cgo, no external tools, no runtime dependencies
- **Modern ext4** — extent trees, including depth-1 indexed trees for fragmented files
- **Extended attributes** — SELinux labels, POSIX ACLs, file capabilities, user xattrs
- **Symlinks and hardlinks** — fast (inline) and block-based symlinks, POSIX-correct link counts
- **Two-way resize** — build on a roomy canvas, then shrink to fit (or grow later)
- **Reproducible images** — fixed timestamp in, identical bytes out
- **Custom volume label** — mount by `LABEL=` from the guest
- **Modify your own images** — reopen, replace files, save again
- **Defensive API** — stale inode handles, duplicate names, and type-confused
  overwrites are rejected instead of corrupting the image

## Shrink to fit

You rarely know the payload size up front. Create a sparse canvas bigger than you'll
ever need, fill it, then cut it down to its high-water mark:

```go
img, _ := ext4fs.New(
	ext4fs.WithImagePath("fixture.img"),
	ext4fs.WithSizeInMB(16384), // 16 GiB canvas, sparse on disk
	ext4fs.WithLabel("fixtures"),
)
// ... create files ...
img.Resize(img.MinSize()) // typically lands at a few MiB
img.Save()
img.Close()
```

`Resize` works both ways within a 16 GiB / 128-group bracket and never relocates data.
It's a pure metadata operation, so it's fast and can't corrupt file contents.

## Reproducible images

All timestamps, the volume UUID and the directory-hash seeds derive from one creation
timestamp. Pin it and the output is byte-for-byte identical on every run, on every
platform. Content-addressable caching and supply-chain attestation come for free:

```go
img, _ := ext4fs.New(
	ext4fs.WithImagePath("disk.img"),
	ext4fs.WithSizeInMB(64),
	ext4fs.WithCreatedAt(1700000000),
)
```

A golden-hash test in CI holds the library to this promise: a full-featured image
(files, directories, symlinks, hardlinks, xattrs, resize) must reproduce an exact
SHA-256, or the build fails.

## How it's tested

A filesystem writer has exactly one correctness oracle: the Linux kernel. Every CI
run boots a privileged container and validates **83 end-to-end scenarios** against
the real thing. Every image must survive `e2fsck -n -f`, mount cleanly, and read
back byte-identical content:

- **Kernel verification** — files, directories, symlinks, hardlinks, xattrs, ACLs,
  capabilities are read back through a real mounted filesystem and compared
- **Extent trees pinned by `filefrag`** — the multi-group extent test asserts the
  actual on-disk extent count through the kernel's FIEMAP, so it cannot silently
  degrade into testing a trivial single-extent file
- **Byte-level unit tests** — extent-tree paths unreachable in CI-sized images
  (multi-leaf splits at 340+ extents) are asserted against the ext4 on-disk format
- **Fuzzing** — a property-based fuzz target drives the public API with arbitrary
  operation sequences; any input may fail, none may corrupt the image. Its first
  outing found a real stack overflow (stale inode handle → directory cycle), now a
  committed regression case. Run it with `make fuzz`
- **Determinism** — the golden-hash fixture test above

Coverage sits at ~83% of statements; the error paths that remain are mostly I/O
failures on the backing file.

## Modifying an existing image

Images created by this library can be reopened and edited — handy for swapping an
`/init` into a prebuilt rootfs:

```go
img, _ := ext4fs.Open(ext4fs.WithExistingImagePath("disk.img"))
img.Delete(ext4fs.RootInode, "init")
img.CreateFile(ext4fs.RootInode, "init", newInit, 0755, 0, 0)
img.Save()
img.Close()
```

Filesystems produced by `mke2fs` cannot be opened: they carry features this library
deliberately does not implement (journaling, 64-bit, flex_bg).

## Limitations

Optimized for boot disks, rootfs images and fixtures — not a general-purpose mkfs:

| Feature | Impact |
|---------|--------|
| Journaling | None for image creation; images mount in writeback mode |
| 64-bit block addresses | Maximum filesystem size ~16 TB |
| Extent tree depth > 1 | Up to 1,360 extents per file — contiguous files up to ~170 GiB |
| HTree directory indexing | Linear directory scan; fine below a few thousand entries |
| Inline data | Small files occupy one full block |
| Encryption, quotas | Not implemented |
| Resize beyond 16 GiB | Larger images can be created, not resized |
| Opening foreign images | `Open` only accepts images created by this library; `mke2fs` output is rejected |

If you need to *read* arbitrary ext4 filesystems instead of writing them, look at
dsoprea/go-ext4 or masahiro331/go-ext4-filesystem — that's the half of the problem
this library deliberately skips.

## Verification

```bash
e2fsck -n -f disk.img          # filesystem integrity
sudo mount -o loop disk.img /mnt
dumpe2fs -h disk.img           # superblock, label, UUID
```

## License

MIT — see [LICENSE](LICENSE).
