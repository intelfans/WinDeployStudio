package ext4fs

import (
	"fmt"
)

// ============================================================================
// Free Runs (reusable contiguous blocks)
// ============================================================================

// freeBlockRun marks blocks as free and stores run for reuse.
func (b *builder) freeBlockRun(start, count uint32) error {
	for i := uint32(0); i < count; i++ {
		if err := b.clearBlockBit(start + i); err != nil {
			return err
		}
		group := (start + i) / blocksPerGroup
		b.freedBlocksPerGroup[group]++
	}
	b.addFreeRun(freeRun{start: start, count: count})
	return nil
}

// addFreeRun adds a free run to freeRuns, maintaining sorted order by count (ascending).
// This is used during Open() when scanning existing bitmaps for holes.
func (b *builder) addFreeRun(run freeRun) {
	pos := 0
	for pos < len(b.freeRuns) && b.freeRuns[pos].count < run.count {
		pos++
	}
	b.freeRuns = append(b.freeRuns, freeRun{})
	copy(b.freeRuns[pos+1:], b.freeRuns[pos:])
	b.freeRuns[pos] = run
}

// ============================================================================
// Block Allocation
// ============================================================================

// allocateBlocks allocates n contiguous blocks.
// First tries best-fit from freeRuns, then allocates fresh.
func (b *builder) allocateBlocks(n uint32) ([]uint32, error) {
	if n == 0 {
		return nil, nil
	}
	if run, idx := b.findBestFit(n); run != nil {
		return b.takeFromRun(idx, n)
	}
	return b.allocateFreshBlocks(n)
}

// allocateBlock allocates a single block.
func (b *builder) allocateBlock() (uint32, error) {
	blocks, err := b.allocateBlocks(1)
	if err != nil {
		return 0, err
	}
	return blocks[0], nil
}

// ============================================================================
// Block Allocation Helpers
// ============================================================================

// findBestFit finds smallest run >= n (best-fit algorithm).
// Returns nil if no suitable run exists.
func (b *builder) findBestFit(n uint32) (*freeRun, int) {
	for i, run := range b.freeRuns {
		if run.count >= n {
			return &b.freeRuns[i], i
		}
	}
	return nil, -1
}

// takeFromRun consumes n blocks from run, shrinks/removes it.
func (b *builder) takeFromRun(idx int, n uint32) ([]uint32, error) {
	run := b.freeRuns[idx]

	blocks := make([]uint32, n)
	for j := uint32(0); j < n; j++ {
		blocks[j] = run.start + j

		group := blocks[j] / blocksPerGroup
		b.freedBlocksPerGroup[group]--

		if err := b.setBlockBit(blocks[j]); err != nil {
			return nil, fmt.Errorf("failed to mark reused block as used: %w", err)
		}
	}

	// Remove this run from the list
	b.freeRuns = append(b.freeRuns[:idx], b.freeRuns[idx+1:]...)

	// If there's remainder, re-insert it sorted
	if run.count > n {
		b.addFreeRun(freeRun{start: run.start + n, count: run.count - n})
	}

	return blocks, nil
}

// allocateFreshBlocks allocates n consecutive new blocks from groups.
func (b *builder) allocateFreshBlocks(n uint32) ([]uint32, error) {
	blocks := make([]uint32, 0, n)

	for len(blocks) < int(n) {
		found := false

		for g := uint32(0); g < b.layout.GroupCount; g++ {
			gl := b.layout.GetGroupLayout(g)
			groupEnd := gl.GroupStart + gl.BlocksInGroup
			available := groupEnd - b.nextBlockPerGroup[g]
			needed := n - uint32(len(blocks))

			if available > 0 {
				toAlloc := available
				if toAlloc > needed {
					toAlloc = needed
				}

				for i := uint32(0); i < toAlloc; i++ {
					block := b.nextBlockPerGroup[g]
					b.nextBlockPerGroup[g]++

					if err := b.setBlockBit(block); err != nil {
						return nil, fmt.Errorf("failed to mark allocated block as used: %w", err)
					}

					blocks = append(blocks, block)
				}

				found = true
				if len(blocks) >= int(n) {
					break
				}
			}
		}

		if !found {
			return nil, fmt.Errorf("out of blocks: need %d more", n-uint32(len(blocks)))
		}
	}

	return blocks, nil
}

// ============================================================================
// Block Bitmap Operations
// ============================================================================

// setBlockBit marks the specified block as used in the bitmap.
func (b *builder) setBlockBit(blockNum uint32) error {
	group := blockNum / blocksPerGroup
	indexInGroup := blockNum % blocksPerGroup

	gl := b.layout.GetGroupLayout(group)
	offset := b.layout.BlockOffset(gl.BlockBitmapBlock) + uint64(indexInGroup/8)

	var buf [1]byte
	if err := b.disk.readAt(buf[:], int64(offset)); err != nil {
		return fmt.Errorf("read block bitmap for block %d: %w", blockNum, err)
	}

	buf[0] |= 1 << (indexInGroup % 8)

	if err := b.disk.writeAt(buf[:], int64(offset)); err != nil {
		return fmt.Errorf("write block bitmap for block %d: %w", blockNum, err)
	}

	return nil
}

// clearBlockBit marks the specified block as free in the bitmap.
func (b *builder) clearBlockBit(blockNum uint32) error {
	group := blockNum / blocksPerGroup
	indexInGroup := blockNum % blocksPerGroup

	gl := b.layout.GetGroupLayout(group)
	offset := b.layout.BlockOffset(gl.BlockBitmapBlock) + uint64(indexInGroup/8)

	var buf [1]byte
	if err := b.disk.readAt(buf[:], int64(offset)); err != nil {
		return fmt.Errorf("read block bitmap for freeing block %d: %w", blockNum, err)
	}

	buf[0] &^= 1 << (indexInGroup % 8)

	if err := b.disk.writeAt(buf[:], int64(offset)); err != nil {
		return fmt.Errorf("write block bitmap for freeing block %d: %w", blockNum, err)
	}

	return nil
}

// ============================================================================
// Inode Allocation
// ============================================================================

// allocateInode allocates the next available inode number.
// First tries to reuse freed inodes, then allocates sequentially.
func (b *builder) allocateInode() (uint32, error) {
	if len(b.freeInodeList) > 0 {
		inodeNum := b.freeInodeList[len(b.freeInodeList)-1]
		b.freeInodeList = b.freeInodeList[:len(b.freeInodeList)-1]

		if err := b.setInodeBit(inodeNum); err != nil {
			return 0, fmt.Errorf("failed to mark reused inode as used: %w", err)
		}

		return inodeNum, nil
	}

	if b.nextInode > b.layout.TotalInodes() {
		return 0, fmt.Errorf("out of inodes: %d", b.nextInode)
	}

	inodeNum := b.nextInode
	b.nextInode++

	if err := b.setInodeBit(inodeNum); err != nil {
		return 0, fmt.Errorf("failed to mark allocated inode as used: %w", err)
	}

	return inodeNum, nil
}

// freeInode marks the specified inode as free for reuse.
func (b *builder) freeInode(inodeNum uint32) error {
	if inodeNum < 1 {
		return nil
	}

	if err := b.clearInodeBit(inodeNum); err != nil {
		return err
	}

	b.freeInodeList = append(b.freeInodeList, inodeNum)

	return nil
}

// ============================================================================
// Inode Bitmap Operations
// ============================================================================

// setInodeBit marks the specified inode as used in the bitmap.
func (b *builder) setInodeBit(inodeNum uint32) error {
	if inodeNum < 1 {
		return nil
	}

	group := (inodeNum - 1) / inodesPerGroup
	indexInGroup := (inodeNum - 1) % inodesPerGroup

	gl := b.layout.GetGroupLayout(group)
	offset := b.layout.BlockOffset(gl.InodeBitmapBlock) + uint64(indexInGroup/8)

	var buf [1]byte
	if err := b.disk.readAt(buf[:], int64(offset)); err != nil {
		return fmt.Errorf("read inode bitmap for inode %d: %w", inodeNum, err)
	}

	buf[0] |= 1 << (indexInGroup % 8)

	if err := b.disk.writeAt(buf[:], int64(offset)); err != nil {
		return fmt.Errorf("write inode bitmap for inode %d: %w", inodeNum, err)
	}

	return nil
}

// isInodeAllocated reports whether the inode is marked used in the inode bitmap.
func (b *builder) isInodeAllocated(inodeNum uint32) (bool, error) {
	if inodeNum < 1 || inodeNum > b.layout.TotalInodes() {
		return false, nil
	}

	group := (inodeNum - 1) / inodesPerGroup
	indexInGroup := (inodeNum - 1) % inodesPerGroup

	gl := b.layout.GetGroupLayout(group)
	offset := b.layout.BlockOffset(gl.InodeBitmapBlock) + uint64(indexInGroup/8)

	var buf [1]byte
	if err := b.disk.readAt(buf[:], int64(offset)); err != nil {
		return false, fmt.Errorf("read inode bitmap for inode %d: %w", inodeNum, err)
	}

	return buf[0]&(1<<(indexInGroup%8)) != 0, nil
}

// clearInodeBit marks the specified inode as free in the bitmap.
func (b *builder) clearInodeBit(inodeNum uint32) error {
	if inodeNum < 1 {
		return nil
	}

	group := (inodeNum - 1) / inodesPerGroup
	indexInGroup := (inodeNum - 1) % inodesPerGroup

	gl := b.layout.GetGroupLayout(group)
	offset := b.layout.BlockOffset(gl.InodeBitmapBlock) + uint64(indexInGroup/8)

	var buf [1]byte
	if err := b.disk.readAt(buf[:], int64(offset)); err != nil {
		return fmt.Errorf("read inode bitmap for freeing inode %d: %w", inodeNum, err)
	}

	buf[0] &^= 1 << (indexInGroup % 8)

	if err := b.disk.writeAt(buf[:], int64(offset)); err != nil {
		return fmt.Errorf("write inode bitmap for freeing inode %d: %w", inodeNum, err)
	}

	return nil
}
