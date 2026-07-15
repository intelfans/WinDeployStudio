# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.2] - 2026-06-15

### Fixed

- Reopening an image and deleting an entry no longer corrupts the free-block and
  free-inode counts. The old accounting derived them from the in-session
  allocation cursors, which reset on reopen, so anything freed below the
  high-water mark was miscounted as used and `e2fsck` rejected the image; the
  counts now come straight from the bitmaps.
- The linear directory scanners reject a corrupt `rec_len`/`name_len` instead of
  slicing past the directory block and panicking.

## [1.0.1] - 2026-06-10

### Added

- Fuzz target (`FuzzOps`) driving the public API with arbitrary operation
  sequences, plus a `make fuzz` target and a committed regression corpus.
- Kernel-verified extent-tree e2e test: a file spanning five block groups must
  produce a depth-1 extent tree, with the extent count pinned via `filefrag`.
- Byte-level unit tests for multi-leaf extent-tree splitting (340+ extents),
  unreachable through the public API in CI-sized images.
- Superblock geometry validation on `Open`: blocks-per-group and
  inodes-per-group must match the library's fixed layout.

### Fixed

- Operations against freed (stale) inode numbers are now rejected instead of
  corrupting the filesystem. Reallocating a freed directory inode inside its
  own former subtree could create a self-referencing directory and crash
  `DeleteDirectory` with a stack overflow (found by fuzzing).
- `CreateDirectory` and `CreateSymlink` now reject names that already exist in
  the parent directory; previously they appended a duplicate directory entry.
- `CreateFile` now refuses to overwrite an existing directory or symlink;
  previously it silently morphed the inode into a regular file, orphaning any
  subtree and leaving a stale file type in the parent directory entry.
- Unit tests, the fuzz corpus and benchmarks now run without Docker; only the
  kernel-backed e2e tests are skipped (previously the whole test binary
  silently exited green).

### Changed

- Renamed three e2e tests whose names promised extent-tree coverage they no
  longer delivered after the v1.0.0 allocator rework: `ExtentTreeConversion` →
  `ManySmallFiles`, `ExtentTreeLeafAllocation` → `FreedBlockRunReuse`,
  `ExtentTreeManyExtents` → `LargeFileAfterFragmentation`.

## [1.0.0] - 2026-06-08

### Added

- Initial stable release: pure Go ext4 image writer with extent-based mapping,
  extended attributes (SELinux, POSIX ACLs, capabilities), fast and slow
  symlinks, hardlinks, custom volume labels, two-way resize within a 16 GiB
  bracket, reproducible images via `WithCreatedAt`, and `Open` support for
  images created by this library.

[1.0.2]: https://github.com/pilat/go-ext4fs/compare/v1.0.1...v1.0.2
[1.0.1]: https://github.com/pilat/go-ext4fs/compare/v1.0.0...v1.0.1
[1.0.0]: https://github.com/pilat/go-ext4fs/releases/tag/v1.0.0
