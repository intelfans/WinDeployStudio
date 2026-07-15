package ext4fs

import (
	"bytes"
	"encoding/binary"
	"fmt"
)

// ============================================================================
// Resize constraints
// ============================================================================

const (
	// maxResizeGroups is the largest group count whose group descriptor table
	// still fits in a single block (ceil(GroupCount/128) == 1). Staying inside
	// this bracket keeps FirstDataBlock and every group's metadata offsets
	// invariant across all resize targets, so grow and shrink never relocate
	// existing data.
	maxResizeGroups = 128

	// maxResizeBlocks is the largest resizable volume (16 GiB) — the block count
	// of maxResizeGroups full groups.
	maxResizeBlocks = maxResizeGroups * blocksPerGroup
)

// ============================================================================
// Size queries
// ============================================================================

// size returns the current logical volume size in bytes (PartitionStart is 0).
func (b *builder) size() uint64 {
	return uint64(b.layout.TotalBlocks) * blockSize
}

// minSize returns the smallest volume size, in bytes and block-aligned, that
// still holds the current content. See minBlocks for the algorithm; it is a
// high-water mark (deleted-but-not-relocated blocks are not reclaimed), and it
// is a valid exact Resize target.
func (b *builder) minSize() uint64 {
	return uint64(b.minBlocks()) * blockSize
}

// minBlocks computes the tightest block count the current content fits in. It
// is bounded by BOTH the highest allocated data block AND the highest allocated
// inode: a volume full of empty files consumes inodes into higher groups while
// barely touching data blocks, and cutting those groups off would corrupt the
// image.
func (b *builder) minBlocks() uint32 {
	// Highest group that actually holds data: the last group whose high-water
	// cursor has advanced past its own metadata. Trailing empty groups sit at
	// their FirstDataBlock and must not be mistaken for full ones.
	gd := uint32(0)
	for g := uint32(0); g < b.layout.GroupCount; g++ {
		if b.nextBlockPerGroup[g] > b.layout.GetGroupLayout(g).FirstDataBlock {
			gd = g
		}
	}
	highestBlock := b.nextBlockPerGroup[gd] - 1

	// Highest group that holds an allocated inode. The highest used inode is
	// nextInode-1; inode N lives in group (N-1)/inodesPerGroup. Guard the
	// essentially-empty case so the arithmetic cannot underflow.
	var gi uint32
	if b.nextInode > firstNonResInode {
		gi = (b.nextInode - 2) / inodesPerGroup
	}

	minGroupCount := max(gd, gi) + 1

	// The binding group must be fully covered: when it holds inodes but no data,
	// the volume must still reach past its metadata (its inode table sits at the
	// front of the group).
	fdb := b.layout.GetGroupLayout(minGroupCount - 1).FirstDataBlock

	return max(highestBlock+1, fdb)
}

// ============================================================================
// Resize
// ============================================================================

// resize changes the volume to targetBytes, growing or shrinking as needed.
// targetBytes is rounded up to the next whole block. It updates structural
// metadata and b.layout but deliberately leaves free-count finalization to a
// following Save (finalizeMetadata); the supported flows always Save afterward.
// All rejections happen before any write, so on error the image is unchanged.
func (b *builder) resize(targetBytes uint64) error {
	targetBlocks, err := b.validateResize(targetBytes)
	if err != nil {
		return err
	}

	if targetBlocks == b.layout.TotalBlocks {
		return nil
	}

	newGroupCount := (targetBlocks + blocksPerGroup - 1) / blocksPerGroup

	if targetBlocks < b.layout.TotalBlocks {
		return b.shrink(targetBlocks, newGroupCount)
	}

	return b.grow(targetBlocks, newGroupCount)
}

// validateResize enforces the resize capability boundaries and returns the
// block-aligned target. It refuses volumes whose group descriptor table spans
// more than one block (>128 groups), targets above 16 GiB, and targets below
// the current content's minimum.
func (b *builder) validateResize(targetBytes uint64) (uint32, error) {
	if b.layout.GroupCount > maxResizeGroups {
		return 0, fmt.Errorf("resize: volume has %d groups (>%d); only single-GDT-block volumes ≤16 GiB are resizable", b.layout.GroupCount, maxResizeGroups)
	}

	targetBlocks := (targetBytes + blockSize - 1) / blockSize
	if targetBlocks > maxResizeBlocks {
		return 0, fmt.Errorf("resize: target %d bytes exceeds the 16 GiB resizable maximum", targetBytes)
	}

	minBlocks := uint64(b.minBlocks())
	if targetBlocks < minBlocks {
		return 0, fmt.Errorf("resize: target %d bytes is below the %d bytes required by current content", targetBytes, minBlocks*blockSize)
	}

	return uint32(targetBlocks), nil
}

// ============================================================================
// Shrink
// ============================================================================

// shrink reduces the volume to targetBlocks / newGroupCount. Because the GDT
// bracket is unchanged, every kept group's metadata layout is invariant; only
// the new last group becomes partial. Blocks above the cut are guaranteed free
// (targetBlocks > highestBlock), so nothing is relocated.
func (b *builder) shrink(targetBlocks, newGroupCount uint32) error {
	b.layout.TotalBlocks = targetBlocks
	b.layout.GroupCount = newGroupCount

	if err := b.padLastGroupBitmap(); err != nil {
		return err
	}

	if err := b.writeStructuralSuperblock(); err != nil {
		return err
	}

	if err := b.disk.truncate(int64(targetBlocks) * blockSize); err != nil {
		return fmt.Errorf("resize: failed to truncate image: %w", err)
	}

	return nil
}

// padLastGroupBitmap marks the blocks past the new last group's range as used
// ("beyond fs"). It is a read-modify-write on the existing bitmap so the group's
// allocated data bits are preserved.
func (b *builder) padLastGroupBitmap() error {
	gl := b.layout.GetGroupLayout(b.layout.GroupCount - 1)

	off := int64(b.layout.BlockOffset(gl.BlockBitmapBlock))
	bitmap := make([]byte, blockSize)
	if err := b.disk.readAt(bitmap, off); err != nil {
		return fmt.Errorf("resize: failed to read last group block bitmap: %w", err)
	}

	for i := gl.BlocksInGroup; i < blocksPerGroup; i++ {
		bitmap[i/8] |= 1 << (i % 8)
	}

	if err := b.disk.writeAt(bitmap, off); err != nil {
		return fmt.Errorf("resize: failed to write last group block bitmap: %w", err)
	}

	return nil
}

// ============================================================================
// Grow
// ============================================================================

// grow extends the volume to targetBlocks / newGroupCount, initializing the
// newly added groups and reopening the previously-last group's padded tail. The
// single-block GDT does not move, so existing data stays in place. Free counts
// are left to the following Save.
func (b *builder) grow(targetBlocks, newGroupCount uint32) error {
	oldGroupCount := b.layout.GroupCount
	oldLastBlocksInGroup := b.layout.GetGroupLayout(oldGroupCount - 1).BlocksInGroup

	if err := b.disk.truncate(int64(targetBlocks) * blockSize); err != nil {
		return fmt.Errorf("resize: failed to extend image: %w", err)
	}

	// Update geometry first so GetGroupLayout yields the new offsets and the new
	// last group's (possibly partial) BlocksInGroup for the writes below.
	b.layout.TotalBlocks = targetBlocks
	b.layout.GroupCount = newGroupCount
	b.extendAllocState(oldGroupCount)

	// The freshly truncate-extended region already reads as zero.
	b.skipZeroInit = true

	for g := oldGroupCount; g < newGroupCount; g++ {
		if err := b.writeNewGroupMetadata(g); err != nil {
			return err
		}
	}

	if err := b.zeroInodeTables(oldGroupCount, newGroupCount); err != nil {
		return err
	}

	// The previously-last group is now larger: free the tail blocks that were
	// padded as "beyond fs" up to its new (interior or still-partial) range.
	if err := b.reopenGroupTail(oldGroupCount-1, oldLastBlocksInGroup); err != nil {
		return err
	}

	// Rewrite structural superblock fields on the primary and every sparse
	// backup (including the ones just written) to the grown geometry. The
	// following Save propagates the new group descriptors to all backups.
	if err := b.writeStructuralSuperblock(); err != nil {
		return err
	}

	return nil
}

// extendAllocState resizes the per-group allocation slices to the new group
// count and initializes the entries for the newly added groups. It preserves
// the kept groups' state and overwrites any stale tail left by a prior shrink
// (shrink does not trim the slices).
func (b *builder) extendAllocState(oldGroupCount uint32) {
	n := int(b.layout.GroupCount)

	b.nextBlockPerGroup = fitSlice(b.nextBlockPerGroup, n)
	b.freedBlocksPerGroup = fitSlice(b.freedBlocksPerGroup, n)
	b.usedDirsPerGroup = fitSlice(b.usedDirsPerGroup, n)

	for g := oldGroupCount; g < b.layout.GroupCount; g++ {
		b.nextBlockPerGroup[g] = b.layout.GetGroupLayout(g).FirstDataBlock
		b.freedBlocksPerGroup[g] = 0
		b.usedDirsPerGroup[g] = 0
	}
}

// writeNewGroupMetadata initializes a single newly added group: its primary
// group descriptor, its bitmaps, and — for sparse-super groups — a fresh backup
// superblock. The backup GDT and all free counts are filled by the following
// Save (finalizeMetadata mirrors every descriptor to every sparse backup).
func (b *builder) writeNewGroupMetadata(g uint32) error {
	if err := b.writePrimaryGroupDescriptor(g); err != nil {
		return err
	}

	if err := b.initGroupBitmaps(g); err != nil {
		return err
	}

	if isSparseGroup(g) {
		if err := b.writeBackupSuperblock(g); err != nil {
			return err
		}
	}

	return nil
}

// writePrimaryGroupDescriptor writes a group's structural descriptor into the
// single-block primary GDT (which never moves within the bracket). It overwrites
// the full 32 bytes so any stale descriptor from a prior larger geometry is
// cleared; free counts are recomputed by the following Save.
func (b *builder) writePrimaryGroupDescriptor(g uint32) error {
	gd := b.groupDescriptorFor(g)

	var buf bytes.Buffer
	if err := binary.Write(&buf, binary.LittleEndian, gd); err != nil {
		return fmt.Errorf("resize: failed to encode group descriptor for group %d: %w", g, err)
	}

	off := int64(b.layout.BlockOffset(b.layout.GetGroupLayout(0).GDTStart)) + int64(g)*32
	if err := b.disk.writeAt(buf.Bytes(), off); err != nil {
		return fmt.Errorf("resize: failed to write group descriptor for group %d: %w", g, err)
	}

	return nil
}

// writeBackupSuperblock writes a fresh backup superblock for a new sparse group
// by copying the primary and stamping its group number. The structural geometry
// fields are corrected afterward by writeStructuralSuperblock.
func (b *builder) writeBackupSuperblock(g uint32) error {
	buf := make([]byte, 1024)
	if err := b.disk.readAt(buf, int64(b.layout.PartitionStart+superblockOffset)); err != nil {
		return fmt.Errorf("resize: failed to read primary superblock for backup %d: %w", g, err)
	}

	binary.LittleEndian.PutUint16(buf[0x5A:0x5C], uint16(g)) // BlockGroupNr

	gl := b.layout.GetGroupLayout(g)
	if err := b.disk.writeAt(buf, int64(b.layout.BlockOffset(gl.SuperblockBlock))); err != nil {
		return fmt.Errorf("resize: failed to write backup superblock for group %d: %w", g, err)
	}

	return nil
}

// reopenGroupTail clears the block-bitmap bits in group g between its old and
// new BlocksInGroup, making the tail blocks usable again after the group grew
// from the last (padded) group into a larger one. It is a no-op when the group
// was already full.
func (b *builder) reopenGroupTail(g, oldBlocksInGroup uint32) error {
	gl := b.layout.GetGroupLayout(g)
	if oldBlocksInGroup >= gl.BlocksInGroup {
		return nil
	}

	off := int64(b.layout.BlockOffset(gl.BlockBitmapBlock))
	bitmap := make([]byte, blockSize)
	if err := b.disk.readAt(bitmap, off); err != nil {
		return fmt.Errorf("resize: failed to read group %d block bitmap: %w", g, err)
	}

	for i := oldBlocksInGroup; i < gl.BlocksInGroup; i++ {
		bitmap[i/8] &^= 1 << (i % 8)
	}

	if err := b.disk.writeAt(bitmap, off); err != nil {
		return fmt.Errorf("resize: failed to write group %d block bitmap: %w", g, err)
	}

	return nil
}

// ============================================================================
// Structural superblock rewrite
// ============================================================================

// writeStructuralSuperblock rewrites the structural geometry fields
// (InodesCount, BlocksCountLo, RBlocksCountLo) on the primary superblock and
// every sparse backup, via read-modify-write so VolumeName and all other fields
// are preserved. It must be called after b.layout has been updated.
func (b *builder) writeStructuralSuperblock() error {
	if err := b.patchStructuralSuperblock(int64(b.layout.PartitionStart + superblockOffset)); err != nil {
		return fmt.Errorf("resize: failed to patch primary superblock: %w", err)
	}

	for g := uint32(1); g < b.layout.GroupCount; g++ {
		if !isSparseGroup(g) {
			continue
		}

		gl := b.layout.GetGroupLayout(g)
		if err := b.patchStructuralSuperblock(int64(b.layout.BlockOffset(gl.SuperblockBlock))); err != nil {
			return fmt.Errorf("resize: failed to patch backup superblock for group %d: %w", g, err)
		}
	}

	return nil
}

// patchStructuralSuperblock reads the 1024-byte superblock at off, updates the
// structural geometry fields from the current layout, and writes it back.
func (b *builder) patchStructuralSuperblock(off int64) error {
	buf := make([]byte, 1024)
	if err := b.disk.readAt(buf, off); err != nil {
		return fmt.Errorf("read superblock: %w", err)
	}

	binary.LittleEndian.PutUint32(buf[0x00:0x04], b.layout.TotalInodes())
	binary.LittleEndian.PutUint32(buf[0x04:0x08], b.layout.TotalBlocks)
	binary.LittleEndian.PutUint32(buf[0x08:0x0C], b.layout.TotalBlocks/20)

	if err := b.disk.writeAt(buf, off); err != nil {
		return fmt.Errorf("write superblock: %w", err)
	}

	return nil
}

// ============================================================================
// Helpers
// ============================================================================

// fitSlice returns s adjusted to length n, preserving the leading min(len(s), n)
// elements. Growing appends zero values; shrinking reslices in place (any stale
// values past n are left in the backing array, unused).
func fitSlice[T any](s []T, n int) []T {
	if len(s) >= n {
		return s[:n]
	}

	return append(s, make([]T, n-len(s))...)
}
