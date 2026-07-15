package ext4fs

import (
	"bytes"
	"encoding/binary"
	"fmt"
	"path/filepath"
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// =============================================================================
// Helpers
// =============================================================================

// readSuperblock returns the 1024-byte primary superblock of an image.
func readSuperblock(t *testing.T, img *Image) []byte {
	t.Helper()

	buf := make([]byte, 1024)
	require.NoError(t, img.backend.readAt(buf, superblockOffset))

	return buf
}

// volumeLabel extracts the null-trimmed VolumeName (offset 0x78) from a superblock.
func volumeLabel(sb []byte) string {
	return string(bytes.TrimRight(sb[0x78:0x78+16], "\x00"))
}

// groupBlockBitmap reads the block bitmap of a group.
func groupBlockBitmap(t *testing.T, img *Image, g uint32) []byte {
	t.Helper()

	gl := img.builder.layout.GetGroupLayout(g)
	bm := make([]byte, blockSize)
	require.NoError(t, img.backend.readAt(bm, int64(img.builder.layout.BlockOffset(gl.BlockBitmapBlock))))

	return bm
}

func bitSet(bitmap []byte, i uint32) bool {
	return bitmap[i/8]&(1<<(i%8)) != 0
}

// readSmallFile reads the content of a single-extent (fast) file via its inode.
func readSmallFile(t *testing.T, b *builder, inodeNum uint32) []byte {
	t.Helper()

	ino, err := b.readInode(inodeNum)
	require.NoError(t, err)

	if ino.SizeLo == 0 {
		return nil
	}

	physical := binary.LittleEndian.Uint32(ino.Block[20:24])
	blk := make([]byte, blockSize)
	require.NoError(t, b.disk.readAt(blk, int64(b.layout.BlockOffset(physical))))

	return blk[:ino.SizeLo]
}

// newSyntheticBuilder builds a builder over a layout of groupCount full groups
// with a nil disk. minBlocks only reads layout/state, so no I/O occurs.
func newSyntheticBuilder(t *testing.T, groupCount uint32) *builder {
	t.Helper()

	layout, err := CalculateLayout(0, uint64(groupCount)*blocksPerGroup*blockSize, 1600000000)
	require.NoError(t, err)
	require.Equal(t, groupCount, layout.GroupCount)

	return newBuilder(nil, layout)
}

// =============================================================================
// Task 1 — Volume label
// =============================================================================

func TestWithLabel(t *testing.T) {
	t.Run("custom label", func(t *testing.T) {
		img, err := New(WithMemoryBackend(), WithSizeInMB(8), WithLabel("fixtures"))
		require.NoError(t, err)
		assert.Equal(t, "fixtures", volumeLabel(readSuperblock(t, img)))
	})

	t.Run("default label", func(t *testing.T) {
		img, err := New(WithMemoryBackend(), WithSizeInMB(8))
		require.NoError(t, err)
		assert.Equal(t, "ext4-go", volumeLabel(readSuperblock(t, img)))
	})

	t.Run("exactly 16 bytes", func(t *testing.T) {
		label := "0123456789abcdef" // 16 bytes
		img, err := New(WithMemoryBackend(), WithSizeInMB(8), WithLabel(label))
		require.NoError(t, err)
		assert.Equal(t, label, volumeLabel(readSuperblock(t, img)))
	})

	t.Run("too long is rejected", func(t *testing.T) {
		_, err := New(WithMemoryBackend(), WithSizeInMB(8), WithLabel("0123456789abcdefg")) // 17 bytes
		require.Error(t, err)
		assert.Contains(t, err.Error(), "label too long")
	})
}

// =============================================================================
// Task 3 — memoryBackend.truncate preserves data
// =============================================================================

func TestMemoryBackendTruncatePreserves(t *testing.T) {
	m := &memoryBackend{}
	require.NoError(t, m.truncate(100))

	pattern := bytes.Repeat([]byte{0xAB}, 100)
	require.NoError(t, m.writeAt(pattern, 0))

	// Grow: prefix intact, new tail zeroed.
	require.NoError(t, m.truncate(200))
	grown := make([]byte, 200)
	require.NoError(t, m.readAt(grown, 0))
	assert.Equal(t, pattern, grown[:100], "prefix preserved on grow")
	assert.Equal(t, make([]byte, 100), grown[100:], "new tail is zero")

	// Shrink: surviving prefix intact.
	require.NoError(t, m.truncate(50))
	shrunk := make([]byte, 50)
	require.NoError(t, m.readAt(shrunk, 0))
	assert.Equal(t, pattern[:50], shrunk, "prefix preserved on shrink")
}

// =============================================================================
// Task 2 — Zero-skip keeps unused inode slots zero on both backends
// =============================================================================

func TestUnusedInodeIsZero(t *testing.T) {
	makeMemory := func(t *testing.T) *Image {
		img, err := New(WithMemoryBackend(), WithSizeInMB(8))
		require.NoError(t, err)
		return img
	}
	makeFile := func(t *testing.T) *Image {
		path := filepath.Join(t.TempDir(), "test.img")
		img, err := New(WithImagePath(path), WithSizeInMB(8))
		require.NoError(t, err)
		return img
	}

	for _, tc := range []struct {
		name string
		make func(*testing.T) *Image
	}{
		{"memory", makeMemory},
		{"file", makeFile},
	} {
		t.Run(tc.name, func(t *testing.T) {
			img := tc.make(t)
			t.Cleanup(func() {
				assert.NoError(t, img.Close())
			})

			// Inode 12 is the first unallocated user inode after root (2) and
			// lost+found (11). Its table slot must read back as all zero.
			off := img.builder.layout.InodeOffset(12)
			buf := make([]byte, inodeSize)
			require.NoError(t, img.backend.readAt(buf, int64(off)))
			assert.Equal(t, make([]byte, inodeSize), buf, "unused inode slot must be zero")
		})
	}
}

func TestWithUUID(t *testing.T) {
	uuid := [16]byte{
		0x51, 0x90, 0x91, 0x2f, 0x3f, 0x64, 0x48, 0x0d,
		0xa4, 0x99, 0x0d, 0x7c, 0x47, 0x78, 0x34, 0x1f,
	}
	img, err := New(WithMemoryBackend(), WithSizeInMB(8), WithUUID(uuid))
	require.NoError(t, err)
	t.Cleanup(func() {
		assert.NoError(t, img.Close())
	})

	sb := readSuperblock(t, img)
	assert.Equal(t, uuid[:], sb[104:120])
}

// =============================================================================
// Task 4 — Size and MinSize
// =============================================================================

func TestSize(t *testing.T) {
	img, err := New(WithMemoryBackend(), WithSizeInMB(8))
	require.NoError(t, err)
	assert.Equal(t, uint64(8*1024*1024), img.Size())
}

func TestMemoryImageLifecycle(t *testing.T) {
	img, err := New(WithMemoryBackend(), WithSizeInMB(8))
	require.NoError(t, err)

	_, err = img.CreateFile(RootInode, "hello", []byte("world"), 0644, 0, 0)
	require.NoError(t, err)

	require.NoError(t, img.Save())
	require.NoError(t, img.Close())
}

func TestWithSize(t *testing.T) {
	img, err := New(WithMemoryBackend(), WithSize(8*1024*1024))
	require.NoError(t, err)
	assert.Equal(t, uint64(8*1024*1024), img.Size())
}

func TestLayoutString(t *testing.T) {
	img, err := New(WithMemoryBackend(), WithSizeInMB(8))
	require.NoError(t, err)

	s := img.builder.layout.String()
	assert.Contains(t, s, "Group count: 1")
	assert.Contains(t, s, fmt.Sprintf("Total blocks: %d", img.builder.layout.TotalBlocks))
}

func TestMinBlocksAlgorithm(t *testing.T) {
	t.Run("empty fs is bounded by group 0 metadata", func(t *testing.T) {
		b := newSyntheticBuilder(t, 128)
		assert.Equal(t, b.layout.GetGroupLayout(0).FirstDataBlock, b.minBlocks())
	})

	t.Run("data-bound", func(t *testing.T) {
		b := newSyntheticBuilder(t, 128)
		fdb := b.layout.GetGroupLayout(3).FirstDataBlock
		b.nextBlockPerGroup[3] = fdb + 1000
		assert.Equal(t, fdb+1000, b.minBlocks())
	})

	t.Run("inode-bound covers the inode group metadata", func(t *testing.T) {
		b := newSyntheticBuilder(t, 128)
		// Only group 0 has (minimal) data; inodes spill into group 3.
		b.nextBlockPerGroup[0] = b.layout.GetGroupLayout(0).FirstDataBlock + 5
		b.nextInode = 3*inodesPerGroup + 100 + 1
		assert.Equal(t, b.layout.GetGroupLayout(3).FirstDataBlock, b.minBlocks())
	})

	t.Run("inode group above data group dominates", func(t *testing.T) {
		b := newSyntheticBuilder(t, 128)
		b.nextBlockPerGroup[2] = b.layout.GetGroupLayout(2).FirstDataBlock + 10
		b.nextInode = 5*inodesPerGroup + 1 + 1
		assert.Equal(t, b.layout.GetGroupLayout(5).FirstDataBlock, b.minBlocks())
	})
}

// =============================================================================
// Task 5 — Shrink
// =============================================================================

func TestResizeShrinkSingleGroup(t *testing.T) {
	img, err := New(WithMemoryBackend(), WithSizeInMB(64), WithLabel("shrinkme"))
	require.NoError(t, err)

	dir, err := img.CreateDirectory(RootInode, "etc", 0o755, 0, 0)
	require.NoError(t, err)
	fileInode, err := img.CreateFile(dir, "hostname", []byte("host\n"), 0o644, 0, 0)
	require.NoError(t, err)

	minSize := img.MinSize()
	require.NoError(t, img.Resize(minSize))

	assert.Equal(t, minSize, img.Size(), "Resize(MinSize()) yields exactly MinSize bytes")
	require.NoError(t, img.Save())

	// Structural superblock reflects the shrunk geometry.
	sb := readSuperblock(t, img)
	assert.Equal(t, uint32(minSize/blockSize), binary.LittleEndian.Uint32(sb[0x04:0x08]), "BlocksCountLo")
	assert.Equal(t, img.builder.layout.GroupCount*inodesPerGroup, binary.LittleEndian.Uint32(sb[0x00:0x04]), "InodesCount")
	assert.Equal(t, "shrinkme", volumeLabel(sb), "label preserved by RMW")

	// Block bitmap padding: every block past the new last group's range is used.
	lastGroup := img.builder.layout.GroupCount - 1
	gl := img.builder.layout.GetGroupLayout(lastGroup)
	bm := groupBlockBitmap(t, img, lastGroup)
	for i := gl.BlocksInGroup; i < blocksPerGroup; i++ {
		require.Truef(t, bitSet(bm, i), "block %d beyond fs must be marked used", i)
	}

	// Content is intact.
	got, err := img.builder.findEntry(dir, "hostname")
	require.NoError(t, err)
	assert.Equal(t, fileInode, got)
	assert.Equal(t, []byte("host\n"), readSmallFile(t, img.builder, fileInode))
}

// =============================================================================
// Resize refusals
// =============================================================================

func TestResizeRefuses2BlockVolume(t *testing.T) {
	b := newSyntheticBuilder(t, 129) // 129 groups => 2-block GDT
	err := b.resize(uint64(b.layout.TotalBlocks) * blockSize / 2)
	require.Error(t, err)
	assert.Contains(t, err.Error(), "groups")
}

func TestResizeRefusesAbove16GiB(t *testing.T) {
	img, err := New(WithMemoryBackend(), WithSizeInMB(64))
	require.NoError(t, err)

	err = img.Resize(17 * 1024 * 1024 * 1024)
	require.Error(t, err)
	assert.Contains(t, err.Error(), "exceeds")
}

func TestResizeRefusesBelowMinSize(t *testing.T) {
	img, err := New(WithMemoryBackend(), WithSizeInMB(64))
	require.NoError(t, err)
	_, err = img.CreateFile(RootInode, "data", bytes.Repeat([]byte("x"), 4096), 0o644, 0, 0)
	require.NoError(t, err)

	err = img.Resize(img.MinSize() - blockSize)
	require.Error(t, err)
	assert.Contains(t, err.Error(), "below")
}

func TestResizeNoOp(t *testing.T) {
	img, err := New(WithMemoryBackend(), WithSizeInMB(64))
	require.NoError(t, err)

	before := img.Size()
	require.NoError(t, img.Resize(before))
	assert.Equal(t, before, img.Size())
}

// =============================================================================
// Task 4/5 — MinSize hole semantics (no compaction)
// =============================================================================

func TestMinSizeHoleNotReclaimed(t *testing.T) {
	img, err := New(WithMemoryBackend(), WithSizeInMB(64))
	require.NoError(t, err)

	// A then B (B sits at higher blocks). Each file is multi-block so deleting A
	// frees a real hole below B's high-water.
	_, err = img.CreateFile(RootInode, "a", bytes.Repeat([]byte("a"), 3*blockSize), 0o644, 0, 0)
	require.NoError(t, err)
	bInode, err := img.CreateFile(RootInode, "b", bytes.Repeat([]byte("b"), 3*blockSize), 0o644, 0, 0)
	require.NoError(t, err)

	minWithBoth := img.MinSize()
	require.NoError(t, img.Delete(RootInode, "a"))

	assert.Equal(t, minWithBoth, img.MinSize(), "MinSize is a high-water mark, deleting A must not shrink it")

	require.NoError(t, img.Resize(img.MinSize()))
	require.NoError(t, img.Save())

	got, err := img.builder.findEntry(RootInode, "b")
	require.NoError(t, err)
	assert.Equal(t, bInode, got)
}

// =============================================================================
// Task 5/6 — File-backend round trips (shrink, grow, grow-after-shrink)
// =============================================================================

// buildTree writes a small fixture tree and returns a verifier closure that
// asserts the tree is present and correct on a (possibly reopened) image.
func buildTree(t *testing.T, img *Image) func(t *testing.T, reopened *Image) {
	t.Helper()

	etc, err := img.CreateDirectory(RootInode, "etc", 0o755, 0, 0)
	require.NoError(t, err)
	_, err = img.CreateFile(etc, "hostname", []byte("resized-host\n"), 0o644, 0, 0)
	require.NoError(t, err)
	_, err = img.CreateSymlink(RootInode, "link", "etc/hostname", 0, 0)
	require.NoError(t, err)

	return func(t *testing.T, reopened *Image) {
		t.Helper()

		etcInode, err := reopened.builder.findEntry(RootInode, "etc")
		require.NoError(t, err)
		require.NotZero(t, etcInode)

		hostInode, err := reopened.builder.findEntry(etcInode, "hostname")
		require.NoError(t, err)
		require.NotZero(t, hostInode)
		assert.Equal(t, []byte("resized-host\n"), readSmallFile(t, reopened.builder, hostInode))

		linkInode, err := reopened.builder.findEntry(RootInode, "link")
		require.NoError(t, err)
		require.NotZero(t, linkInode)

		linkIno, err := reopened.builder.readInode(linkInode)
		require.NoError(t, err)
		assert.Equal(t, uint16(s_IFLNK), linkIno.Mode&0xF000, "entry is still a symlink")
		assert.Equal(t, "etc/hostname", string(linkIno.Block[:linkIno.SizeLo]), "symlink target preserved")
	}
}

func TestResizeShrinkMultiGroupRoundTrip(t *testing.T) {
	path := filepath.Join(t.TempDir(), "shrink.img")

	img, err := New(WithImagePath(path), WithSizeInMB(256), WithLabel("multigrp")) // 2 groups
	require.NoError(t, err)
	require.Equal(t, uint32(2), img.builder.layout.GroupCount)

	verify := buildTree(t, img)

	require.NoError(t, img.Resize(img.MinSize())) // collapses to 1 group
	assert.Equal(t, uint32(1), img.builder.layout.GroupCount)
	require.NoError(t, img.Save())
	require.NoError(t, img.Close())

	reopened, err := Open(WithExistingImagePath(path))
	require.NoError(t, err)
	defer func() { _ = reopened.Close() }()

	assert.Equal(t, "multigrp", volumeLabel(readSuperblock(t, reopened)))
	verify(t, reopened)
}

func TestResizeGrowMultiGroupRoundTrip(t *testing.T) {
	path := filepath.Join(t.TempDir(), "grow.img")

	img, err := New(WithImagePath(path), WithSizeInMB(100), WithLabel("growme")) // 1 group
	require.NoError(t, err)
	require.Equal(t, uint32(1), img.builder.layout.GroupCount)

	verify := buildTree(t, img)

	require.NoError(t, img.Resize(256*1024*1024)) // 2 groups
	assert.Equal(t, uint32(2), img.builder.layout.GroupCount)
	assert.Equal(t, uint64(256*1024*1024), img.Size())
	require.NoError(t, img.Save())
	require.NoError(t, img.Close())

	reopened, err := Open(WithExistingImagePath(path))
	require.NoError(t, err)
	defer func() { _ = reopened.Close() }()

	assert.Equal(t, "growme", volumeLabel(readSuperblock(t, reopened)))
	assert.Equal(t, uint32(2), reopened.builder.layout.GroupCount)

	// Backup superblock in sparse group 1 carries the grown geometry.
	gl1 := reopened.builder.layout.GetGroupLayout(1)
	backup := make([]byte, 1024)
	require.NoError(t, reopened.backend.readAt(backup, int64(reopened.builder.layout.BlockOffset(gl1.SuperblockBlock))))
	assert.Equal(t, uint32(2*blocksPerGroup), binary.LittleEndian.Uint32(backup[0x04:0x08]), "backup BlocksCountLo")

	verify(t, reopened)

	// The grown space is usable: allocating a file succeeds and stays within bounds.
	_, err = reopened.CreateFile(RootInode, "after-grow", []byte("ok"), 0o644, 0, 0)
	require.NoError(t, err)
	require.NoError(t, reopened.Save())
}

func TestResizeGrowAfterShrink(t *testing.T) {
	path := filepath.Join(t.TempDir(), "grow-after-shrink.img")

	img, err := New(WithImagePath(path), WithSizeInMB(256), WithLabel("gas")) // 2 groups
	require.NoError(t, err)

	verify := buildTree(t, img)

	require.NoError(t, img.Resize(img.MinSize())) // shrink to 1 group
	require.Equal(t, uint32(1), img.builder.layout.GroupCount)
	require.NoError(t, img.Resize(256*1024*1024)) // grow back to 2 groups
	require.Equal(t, uint32(2), img.builder.layout.GroupCount)
	require.NoError(t, img.Save())
	require.NoError(t, img.Close())

	reopened, err := Open(WithExistingImagePath(path))
	require.NoError(t, err)
	defer func() { _ = reopened.Close() }()

	require.Len(t, reopened.builder.nextBlockPerGroup, 2, "alloc slices match grown group count")
	verify(t, reopened)
}

// =============================================================================
// I/O error propagation (fault injection)
// =============================================================================

// faultBackend wraps a diskBackend and injects a failure on the Nth read, write,
// or truncate (1-based; 0 disables). It lets tests assert that resize surfaces an
// I/O error from every step rather than silently corrupting the image.
type faultBackend struct {
	inner     diskBackend
	failRead  int
	failWrite int
	failTrunc int
	reads     int
	writes    int
	truncs    int
}

var _ diskBackend = (*faultBackend)(nil)

func (f *faultBackend) truncate(size int64) error {
	f.truncs++
	if f.truncs == f.failTrunc {
		return fmt.Errorf("injected truncate failure #%d", f.truncs)
	}

	return f.inner.truncate(size)
}

func (f *faultBackend) readAt(p []byte, off int64) error {
	f.reads++
	if f.reads == f.failRead {
		return fmt.Errorf("injected read failure #%d", f.reads)
	}

	return f.inner.readAt(p, off)
}

func (f *faultBackend) writeAt(p []byte, off int64) error {
	f.writes++
	if f.writes == f.failWrite {
		return fmt.Errorf("injected write failure #%d", f.writes)
	}

	return f.inner.writeAt(p, off)
}

func (f *faultBackend) sync() error  { return f.inner.sync() }
func (f *faultBackend) close() error { return f.inner.close() }

// TestResizePropagatesIOErrors fails each individual read/write/truncate that a
// clean resize performs and asserts resize returns an error every time — every
// I/O error branch in the shrink and grow paths.
func TestResizePropagatesIOErrors(t *testing.T) {
	build := func(t *testing.T, sizeMB int) *Image {
		t.Helper()

		img, err := New(WithMemoryBackend(), WithSizeInMB(sizeMB))
		require.NoError(t, err)
		_ = buildTree(t, img)

		return img
	}

	cases := []struct {
		name   string
		sizeMB int
		target func(img *Image) uint64
	}{
		{"shrink", 256, func(img *Image) uint64 { return img.MinSize() }},
		{"grow", 64, func(img *Image) uint64 { return 256 * 1024 * 1024 }},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			// Count the I/O a clean resize performs.
			base := build(t, tc.sizeMB)
			counter := &faultBackend{inner: base.builder.disk}
			base.builder.disk = counter
			require.NoError(t, base.builder.resize(tc.target(base)))
			require.Positive(t, counter.writes)

			failAt := func(label string, setup func(fb *faultBackend)) {
				img := build(t, tc.sizeMB)
				target := tc.target(img)

				fb := &faultBackend{inner: img.builder.disk}
				setup(fb)
				img.builder.disk = fb

				err := img.builder.resize(target)
				require.Error(t, err, "resize must fail when %s", label)
				assert.Contains(t, err.Error(), "injected ", "resize must surface the injected backend failure when %s", label)
			}

			for i := 1; i <= counter.writes; i++ {
				i := i
				failAt(fmt.Sprintf("write #%d fails", i), func(fb *faultBackend) { fb.failWrite = i })
			}
			for i := 1; i <= counter.reads; i++ {
				i := i
				failAt(fmt.Sprintf("read #%d fails", i), func(fb *faultBackend) { fb.failRead = i })
			}
			for i := 1; i <= counter.truncs; i++ {
				i := i
				failAt(fmt.Sprintf("truncate #%d fails", i), func(fb *faultBackend) { fb.failTrunc = i })
			}
		})
	}
}

// TestZeroInodeTablesFallback covers the actual zeroing loop (the safety fallback
// when skipZeroInit is not set), which the New and grow paths always skip.
func TestZeroInodeTablesFallback(t *testing.T) {
	img, err := New(WithMemoryBackend(), WithSizeInMB(8))
	require.NoError(t, err)

	b := img.builder
	gl := b.layout.GetGroupLayout(0)
	off := int64(b.layout.BlockOffset(gl.InodeTableStart))

	require.NoError(t, b.disk.writeAt(bytes.Repeat([]byte{0xFF}, blockSize), off))

	b.skipZeroInit = false
	require.NoError(t, b.zeroInodeTables(0, 1))

	got := make([]byte, blockSize)
	require.NoError(t, b.disk.readAt(got, off))
	assert.Equal(t, make([]byte, blockSize), got, "fallback zeroing clears the inode table block")
}

// =============================================================================
// Label preservation across Open + Resize
// =============================================================================

func TestLabelPreservedThroughResize(t *testing.T) {
	path := filepath.Join(t.TempDir(), "label.img")

	img, err := New(WithImagePath(path), WithSizeInMB(256), WithLabel("persist"))
	require.NoError(t, err)
	_ = buildTree(t, img)
	require.NoError(t, img.Save())
	require.NoError(t, img.Close())

	reopened, err := Open(WithExistingImagePath(path))
	require.NoError(t, err)
	require.NoError(t, reopened.Resize(reopened.MinSize()))
	require.NoError(t, reopened.Save())
	require.NoError(t, reopened.Close())

	final, err := Open(WithExistingImagePath(path))
	require.NoError(t, err)
	defer func() { _ = final.Close() }()

	assert.Equal(t, "persist", volumeLabel(readSuperblock(t, final)))
}
