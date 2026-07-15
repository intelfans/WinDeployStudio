package ext4fs

import (
	"fmt"
)

var DEBUG = false

// freeRun represents a contiguous range of free blocks
type freeRun struct {
	start uint32
	count uint32
}

type builder struct {
	disk   diskBackend
	layout *Layout
	debug  bool // Enable debug output

	label        string // Volume label written to the superblock (New path only)
	uuid         [16]byte
	hasUUID      bool
	skipZeroInit bool   // Skip zeroing freshly-truncated inode tables (already zero)

	// Allocation state - per group
	nextBlockPerGroup   []uint32  // Next free block in each group
	freedBlocksPerGroup []uint32  // Blocks freed per group (for overwrites)
	freeRuns            []freeRun // Free block runs sorted by count (ascending) for best-fit
	nextInode           uint32    // Next free inode (global)
	freeInodeList       []uint32  // List of freed inodes available for reuse

	// Tracking
	usedDirsPerGroup []uint16 // Directory count per group
}

// newBuilder creates a new Builder instance with initialized allocation state.
// It sets up per-group tracking for block and inode allocation, preparing
// the builder for filesystem construction operations.
func newBuilder(disk diskBackend, layout *Layout) *builder {
	b := &builder{
		disk:                disk,
		layout:              layout,
		debug:               DEBUG,
		label:               "ext4-go",
		nextBlockPerGroup:   make([]uint32, layout.GroupCount),
		freedBlocksPerGroup: make([]uint32, layout.GroupCount),
		freeRuns:            nil,
		nextInode:           firstNonResInode,
		freeInodeList:       make([]uint32, 0),
		usedDirsPerGroup:    make([]uint16, layout.GroupCount),
	}

	// Initialize next free block for each group
	for g := uint32(0); g < layout.GroupCount; g++ {
		gl := layout.GetGroupLayout(g)
		b.nextBlockPerGroup[g] = gl.FirstDataBlock
	}

	return b
}

// loadBitmaps reads existing block and inode bitmaps from an opened ext4 image.
// It scans the bitmaps to determine which blocks and inodes are already allocated,
// enabling proper allocation state for modification operations.
//
// For each block group, it:
//   - Scans the block bitmap to find the first free block (sets nextBlockPerGroup)
//   - Scans the inode bitmap to find the highest allocated inode (sets nextInode)
//   - Reads the group descriptor to get the directory count (sets usedDirsPerGroup)
//
// This must be called after newBuilder when opening an existing image.
func (b *builder) loadBitmaps() error {
	highestInode := uint32(firstNonResInode - 1)

	for g := uint32(0); g < b.layout.GroupCount; g++ {
		gl := b.layout.GetGroupLayout(g)

		if err := b.loadBlockBitmap(g, gl); err != nil {
			return err
		}

		groupHighest, err := b.loadInodeBitmap(g, gl)
		if err != nil {
			return err
		}
		if groupHighest > highestInode {
			highestInode = groupHighest
		}

		if err := b.loadGroupDirCount(g); err != nil {
			return err
		}
	}

	b.nextInode = highestInode + 1

	if b.debug {
		fmt.Printf("Bitmaps loaded (next inode: %d)\n", b.nextInode)
	}

	return nil
}

// loadBlockBitmap scans a group's block bitmap to find allocation state and free holes.
func (b *builder) loadBlockBitmap(g uint32, gl GroupLayout) error {
	blockBitmap := make([]byte, blockSize)
	if err := b.disk.readAt(blockBitmap, int64(b.layout.BlockOffset(gl.BlockBitmapBlock))); err != nil {
		return fmt.Errorf("read block bitmap for group %d: %w", g, err)
	}

	// Find highest used block
	highestUsed := gl.FirstDataBlock - gl.GroupStart - 1
	dataStart := gl.FirstDataBlock - gl.GroupStart
	for i := dataStart; i < gl.BlocksInGroup; i++ {
		if blockBitmap[i/8]&(1<<(i%8)) != 0 {
			highestUsed = i
		}
	}
	b.nextBlockPerGroup[g] = gl.GroupStart + highestUsed + 1

	// Find free block runs (holes) below the high-water mark. They are reusable
	// (added to freeRuns) and also recorded as freed, so the free-block count is
	// correct on reopen of an image whose deleted files left holes below the mark.
	// For our own sequentially-written images (no holes) this is zero.
	var runStart, runCount, holes uint32
	for i := dataStart; i <= highestUsed; i++ {
		isFree := blockBitmap[i/8]&(1<<(i%8)) == 0
		if isFree {
			if runCount == 0 {
				runStart = gl.GroupStart + i
			}
			runCount++
		} else if runCount > 0 {
			b.addFreeRun(freeRun{start: runStart, count: runCount})
			holes += runCount
			runCount = 0
		}
	}
	if runCount > 0 {
		b.addFreeRun(freeRun{start: runStart, count: runCount})
		holes += runCount
	}
	b.freedBlocksPerGroup[g] = holes

	return nil
}

// loadInodeBitmap scans a group's inode bitmap and returns the highest allocated inode.
func (b *builder) loadInodeBitmap(g uint32, gl GroupLayout) (uint32, error) {
	inodeBitmap := make([]byte, blockSize)
	if err := b.disk.readAt(inodeBitmap, int64(b.layout.BlockOffset(gl.InodeBitmapBlock))); err != nil {
		return 0, fmt.Errorf("read inode bitmap for group %d: %w", g, err)
	}

	var highest uint32
	for i := uint32(0); i < b.layout.InodesPerGroup; i++ {
		if inodeBitmap[i/8]&(1<<(i%8)) != 0 {
			inodeNum := g*b.layout.InodesPerGroup + i + 1
			if inodeNum > highest {
				highest = inodeNum
			}
		}
	}
	return highest, nil
}

// loadGroupDirCount reads the directory count from a group descriptor.
func (b *builder) loadGroupDirCount(g uint32) error {
	gdtOffset := b.layout.BlockOffset(b.layout.GetGroupLayout(0).GDTStart) + uint64(g*32)
	gdData := make([]byte, 32)
	if err := b.disk.readAt(gdData, int64(gdtOffset)); err != nil {
		return fmt.Errorf("read group descriptor %d: %w", g, err)
	}
	b.usedDirsPerGroup[g] = uint16(gdData[16]) | uint16(gdData[17])<<8
	return nil
}

// prepareFilesystem initializes the complete ext4 filesystem structure.
// This includes writing the superblock, group descriptors, initializing
// bitmaps, zeroing inode tables, and creating essential directories like
// root and lost+found. This method must be called before any file operations.
func (b *builder) prepareFilesystem() error {
	if b.debug {
		fmt.Println(b.layout.String())
		fmt.Println()
	}

	if err := b.writeSuperblock(); err != nil {
		return err
	}

	if err := b.writeGroupDescriptors(); err != nil {
		return err
	}

	if err := b.initBitmaps(); err != nil {
		return err
	}

	if err := b.zeroInodeTables(0, b.layout.GroupCount); err != nil {
		return err
	}

	if err := b.createRootDirectory(); err != nil {
		return err
	}

	if err := b.createLostFound(); err != nil {
		return err
	}

	if DEBUG {
		fmt.Println("✓ Filesystem prepared successfully")
	}

	return nil
}
