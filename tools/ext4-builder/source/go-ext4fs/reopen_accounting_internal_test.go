package ext4fs

import (
	"encoding/binary"
	"path/filepath"
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// assertGroupFreeCountsMatchBitmaps checks every group descriptor's free-block
// and free-inode counts against the authoritative on-disk bitmaps — exactly what
// e2fsck recomputes. Any mismatch is a dirty filesystem.
func assertGroupFreeCountsMatchBitmaps(t *testing.T, b *builder) {
	t.Helper()
	gdtStart := b.layout.GetGroupLayout(0).GDTStart
	for g := uint32(0); g < b.layout.GroupCount; g++ {
		gl := b.layout.GetGroupLayout(g)

		gd := make([]byte, 32)
		require.NoError(t, b.disk.readAt(gd, int64(b.layout.BlockOffset(gdtStart)+uint64(g*32))))
		descFreeBlocks := binary.LittleEndian.Uint16(gd[12:14])
		descFreeInodes := binary.LittleEndian.Uint16(gd[14:16])

		bb := make([]byte, blockSize)
		require.NoError(t, b.disk.readAt(bb, int64(b.layout.BlockOffset(gl.BlockBitmapBlock))))
		var freeBlocks uint16
		for i := uint32(0); i < gl.BlocksInGroup; i++ {
			if bb[i/8]&(1<<(i%8)) == 0 {
				freeBlocks++
			}
		}

		ib := make([]byte, blockSize)
		require.NoError(t, b.disk.readAt(ib, int64(b.layout.BlockOffset(gl.InodeBitmapBlock))))
		var freeInodes uint16
		for i := uint32(0); i < inodesPerGroup; i++ {
			if ib[i/8]&(1<<(i%8)) == 0 {
				freeInodes++
			}
		}

		assert.Equalf(t, freeBlocks, descFreeBlocks, "group %d free-block count vs bitmap", g)
		assert.Equalf(t, freeInodes, descFreeInodes, "group %d free-inode count vs bitmap", g)
	}
}

// Finding A: after reopening an image and re-saving, free-block and free-inode
// counts must match the bitmaps. The buggy accounting derives counts from the
// global next-inode/next-block cursors minus session-local "freed" counters,
// which are zero after reopen — so anything freed below the high-water mark
// (here: directory "b", with "c" allocated above it) is miscounted as used and
// e2fsck rejects the image.
func TestReopenFreeCountsMatchBitmaps(t *testing.T) {
	dir := t.TempDir()
	imgPath := filepath.Join(dir, "acct.img")

	img, err := New(WithImagePath(imgPath), WithSizeInMB(16))
	require.NoError(t, err)
	_, err = img.CreateDirectory(RootInode, "a", 0755, 0, 0)
	require.NoError(t, err)
	_, err = img.CreateDirectory(RootInode, "b", 0755, 0, 0)
	require.NoError(t, err)
	_, err = img.CreateDirectory(RootInode, "c", 0755, 0, 0)
	require.NoError(t, err)
	require.NoError(t, img.DeleteDirectory(RootInode, "b")) // freed below high-water (c is higher)
	require.NoError(t, img.Save())
	require.NoError(t, img.Close())

	img, err = Open(WithExistingImagePath(imgPath))
	require.NoError(t, err)
	require.NoError(t, img.Save())
	assertGroupFreeCountsMatchBitmaps(t, img.builder)
	require.NoError(t, img.Close())
}

// Same invariant for a freed file's data block below the high-water mark.
func TestReopenFreeCountsAfterFileDelete(t *testing.T) {
	dir := t.TempDir()
	imgPath := filepath.Join(dir, "acctfile.img")

	img, err := New(WithImagePath(imgPath), WithSizeInMB(16))
	require.NoError(t, err)
	_, err = img.CreateFile(RootInode, "low.bin", make([]byte, 4096), 0644, 0, 0)
	require.NoError(t, err)
	_, err = img.CreateFile(RootInode, "high.bin", make([]byte, 4096), 0644, 0, 0)
	require.NoError(t, err)
	require.NoError(t, img.Delete(RootInode, "low.bin")) // inode + block freed below high-water
	require.NoError(t, img.Save())
	require.NoError(t, img.Close())

	img, err = Open(WithExistingImagePath(imgPath))
	require.NoError(t, err)
	require.NoError(t, img.Save())
	assertGroupFreeCountsMatchBitmaps(t, img.builder)
	require.NoError(t, img.Close())
}

// Finding C: the directory-entry scanners (findEntry/removeDirEntry/listDirEntries)
// read name_len and slice the name with no bounds check, so a directory block with
// a corrupt rec_len/name_len (reachable on a damaged on-disk image) walks past the
// block end and panics instead of returning an error.
func TestFindEntryCorruptDirentDoesNotPanic(t *testing.T) {
	img, err := New(WithMemoryBackend(), WithSizeInMB(8))
	require.NoError(t, err)
	d, err := img.CreateDirectory(RootInode, "d", 0755, 0, 0)
	require.NoError(t, err)
	require.NoError(t, img.Save())

	b := img.builder
	dInode, err := b.readInode(d)
	require.NoError(t, err)
	blocks, err := b.getInodeBlocks(dInode)
	require.NoError(t, err)
	require.NotEmpty(t, blocks)

	// Poison the directory block: first entry's rec_len jumps the cursor to 4090,
	// and the bytes there form a non-zero rec_len, so the scanner then reads
	// name_len at offset 4096 — one past the block.
	block := make([]byte, blockSize)
	binary.LittleEndian.PutUint16(block[4:6], 4090)
	binary.LittleEndian.PutUint16(block[4094:4096], 100)
	require.NoError(t, b.disk.writeAt(block, int64(b.layout.BlockOffset(blocks[0]))))

	require.NotPanics(t, func() {
		_, _ = b.findEntry(d, "whatever")
	})
}
