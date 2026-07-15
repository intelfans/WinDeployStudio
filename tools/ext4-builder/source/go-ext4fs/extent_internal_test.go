package ext4fs

import (
	"encoding/binary"
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// These tests cover the depth-1 extent tree writer with synthetic extent
// lists. The multi-leaf paths (>340 extents) cannot be reached through the
// public API in a CI-sized test: the allocator never splits an allocation
// (PR #4), so a file needs to span >340 block groups (~43 GiB of data) to
// collect that many extents. The on-disk format is asserted byte-by-byte
// against the ext4 layout instead; the single-leaf path is additionally
// kernel-verified by the ExtentTreeMultiGroup e2e test.

// =============================================================================
// Helpers
// =============================================================================

// newExtentTestBuilder returns the internal builder of a fresh in-memory image.
func newExtentTestBuilder(t *testing.T) *builder {
	t.Helper()

	img, err := New(WithMemoryBackend(), WithSizeInMB(8))
	require.NoError(t, err)
	t.Cleanup(func() { _ = img.Close() })

	return img.builder
}

// syntheticExtents builds n single-block extents with non-contiguous physical
// blocks so buildExtentList could never have merged them.
func syntheticExtents(n int) []extent {
	exts := make([]extent, n)
	for i := range exts {
		exts[i] = extent{logical: uint32(i), physical: uint32(10000 + 2*i), length: 1}
	}
	return exts
}

// readBlock reads one filesystem block from the builder's backend.
func readBlock(t *testing.T, b *builder, block uint32) []byte {
	t.Helper()

	buf := make([]byte, blockSize)
	require.NoError(t, b.disk.readAt(buf, int64(b.layout.BlockOffset(block))))

	return buf
}

// extentAt decodes the extent entry at index i of an extent node buffer.
func extentAt(buf []byte, i int) extent {
	off := 12 + i*12
	return extent{
		logical:  binary.LittleEndian.Uint32(buf[off:]),
		length:   binary.LittleEndian.Uint16(buf[off+4:]),
		physical: binary.LittleEndian.Uint32(buf[off+8:]),
	}
}

// =============================================================================
// Inline / tree boundary
// =============================================================================

func TestSetExtentMultipleBoundary(t *testing.T) {
	t.Run("4 discontiguous blocks stay inline", func(t *testing.T) {
		b := newExtentTestBuilder(t)
		ino := &inode{}

		require.NoError(t, b.setExtentMultiple(ino, []uint32{10, 12, 14, 16}))

		assert.Equal(t, uint16(4), binary.LittleEndian.Uint16(ino.Block[2:4]), "extent count")
		for i := 0; i < 4; i++ {
			got := extentAt(ino.Block[:], i)
			assert.Equal(t, extent{logical: uint32(i), physical: uint32(10 + 2*i), length: 1}, got)
		}
		assert.Zero(t, ino.BlocksLo, "inline extents must not consume leaf blocks")
	})

	t.Run("5 discontiguous blocks build a depth-1 tree", func(t *testing.T) {
		b := newExtentTestBuilder(t)
		ino := &inode{}

		require.NoError(t, b.setExtentMultiple(ino, []uint32{10, 12, 14, 16, 18}))

		assert.Equal(t, uint16(extentMagic), binary.LittleEndian.Uint16(ino.Block[0:2]), "header magic")
		assert.Equal(t, uint16(1), binary.LittleEndian.Uint16(ino.Block[2:4]), "index entries")
		assert.Equal(t, uint16(1), binary.LittleEndian.Uint16(ino.Block[6:8]), "tree depth")
		assert.Equal(t, uint32(blockSize/512), ino.BlocksLo, "one leaf block accounted")

		leafBlock := binary.LittleEndian.Uint32(ino.Block[16:20])
		require.Less(t, leafBlock, b.layout.TotalBlocks, "leaf block must be inside the volume")

		leaf := readBlock(t, b, leafBlock)
		assert.Equal(t, uint16(extentMagic), binary.LittleEndian.Uint16(leaf[0:2]), "leaf magic")
		assert.Equal(t, uint16(5), binary.LittleEndian.Uint16(leaf[2:4]), "leaf extent count")
		assert.Equal(t, uint16(maxExtentsPerLeaf), binary.LittleEndian.Uint16(leaf[4:6]), "leaf max entries")
		assert.Equal(t, uint16(0), binary.LittleEndian.Uint16(leaf[6:8]), "leaf depth")
		for i := 0; i < 5; i++ {
			got := extentAt(leaf, i)
			assert.Equal(t, extent{logical: uint32(i), physical: uint32(10 + 2*i), length: 1}, got)
		}
	})
}

// =============================================================================
// Multi-leaf splitting
// =============================================================================

func TestWriteExtentTreeLeafSplit(t *testing.T) {
	tests := []struct {
		name       string
		numExtents int
		wantLeaves int
	}{
		{"340 extents fill one leaf", maxExtentsPerLeaf, 1},
		{"341 extents spill into a second leaf", maxExtentsPerLeaf + 1, 2},
		{"1360 extents fill all four leaves", maxExtentsPerLeaf * 4, 4},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			b := newExtentTestBuilder(t)
			ino := &inode{}
			extents := syntheticExtents(tt.numExtents)

			require.NoError(t, b.writeExtentTree(ino, extents))

			assert.Equal(t, uint16(extentMagic), binary.LittleEndian.Uint16(ino.Block[0:2]), "header magic")
			assert.Equal(t, uint16(tt.wantLeaves), binary.LittleEndian.Uint16(ino.Block[2:4]), "index entries")
			assert.Equal(t, uint16(4), binary.LittleEndian.Uint16(ino.Block[4:6]), "max index entries")
			assert.Equal(t, uint16(1), binary.LittleEndian.Uint16(ino.Block[6:8]), "tree depth")
			assert.Equal(t, uint32(tt.wantLeaves)*(blockSize/512), ino.BlocksLo, "leaf blocks accounted")

			remaining := tt.numExtents
			for leafIdx := 0; leafIdx < tt.wantLeaves; leafIdx++ {
				off := 12 + leafIdx*12
				firstLogical := binary.LittleEndian.Uint32(ino.Block[off:])
				leafBlock := binary.LittleEndian.Uint32(ino.Block[off+4:])
				assert.Equal(t, uint32(leafIdx*maxExtentsPerLeaf), firstLogical, "index entry %d logical start", leafIdx)
				require.Less(t, leafBlock, b.layout.TotalBlocks, "leaf %d block must be inside the volume", leafIdx)

				wantCount := remaining
				if wantCount > maxExtentsPerLeaf {
					wantCount = maxExtentsPerLeaf
				}
				remaining -= wantCount

				leaf := readBlock(t, b, leafBlock)
				assert.Equal(t, uint16(extentMagic), binary.LittleEndian.Uint16(leaf[0:2]), "leaf %d magic", leafIdx)
				assert.Equal(t, uint16(wantCount), binary.LittleEndian.Uint16(leaf[2:4]), "leaf %d extent count", leafIdx)
				assert.Equal(t, uint16(0), binary.LittleEndian.Uint16(leaf[6:8]), "leaf %d depth", leafIdx)

				first := extentAt(leaf, 0)
				last := extentAt(leaf, wantCount-1)
				assert.Equal(t, extents[leafIdx*maxExtentsPerLeaf], first, "leaf %d first extent", leafIdx)
				assert.Equal(t, extents[leafIdx*maxExtentsPerLeaf+wantCount-1], last, "leaf %d last extent", leafIdx)
			}
		})
	}
}

func TestWriteExtentTreeTooManyExtents(t *testing.T) {
	b := newExtentTestBuilder(t)
	ino := &inode{}

	err := b.writeExtentTree(ino, syntheticExtents(maxExtentsPerLeaf*4+1))

	require.Error(t, err)
	assert.Contains(t, err.Error(), "too many extents")
}
