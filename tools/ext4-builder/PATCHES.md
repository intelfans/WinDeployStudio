# Local Changes To go-ext4fs

The vendored upstream source is pinned to commit
`ad8cccf4a20ceb956f2180ef5b3f728cbbc0b6d7`.

WinDeploy Studio adds one backwards-compatible option:

- `WithUUID([16]byte)` lets the narrow Windows helper provide a
  cryptographically random RFC 4122 v4 UUID for every persistence image.
- A Windows cleanup regression in `TestUnusedInodeIsZero` is fixed by closing
  the file-backed image before `t.TempDir` removes its parent directory.

Without this option, upstream derives its UUID from a seconds-resolution
creation time. That preserves upstream deterministic-image behavior but can
collide when two independent persistence images are created in the same
second. The application helper always calls `WithUUID`; the upstream default
remains unchanged for callers that rely on reproducible output.
