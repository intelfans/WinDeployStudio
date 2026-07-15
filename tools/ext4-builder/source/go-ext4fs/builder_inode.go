package ext4fs

import (
	"bytes"
	"encoding/binary"
	"fmt"
)

// makeDirectoryInode creates a new inode structure configured for a directory.
// Directory inodes have specific mode flags and initial link count of 2
// (accounting for "." and ".." entries). Timestamps are set to the filesystem creation time.
func (b *builder) makeDirectoryInode(mode, uid, gid uint16) inode {
	inode := inode{
		Mode:       s_IFDIR | mode,
		UID:        uid,
		GID:        gid,
		LinksCount: 2,
		Flags:      inodeFlagExtents,
		Atime:      b.layout.CreatedAt,
		Ctime:      b.layout.CreatedAt,
		Mtime:      b.layout.CreatedAt,
		Crtime:     b.layout.CreatedAt,
		ExtraIsize: 32,
	}
	b.initExtentHeader(&inode)

	return inode
}

// makeFileInode creates a new inode structure configured for a regular file.
// The inode is initialized with the specified size, ownership, and permissions.
// Regular files use extent trees for block mapping and have appropriate mode flags.
func (b *builder) makeFileInode(mode, uid, gid uint16, size uint64) inode {
	inode := inode{
		Mode:       s_IFREG | mode,
		UID:        uid,
		GID:        gid,
		SizeLo:     uint32(size & 0xFFFFFFFF),
		SizeHi:     uint32(size >> 32),
		LinksCount: 1,
		Flags:      inodeFlagExtents,
		Atime:      b.layout.CreatedAt,
		Ctime:      b.layout.CreatedAt,
		Mtime:      b.layout.CreatedAt,
		Crtime:     b.layout.CreatedAt,
		ExtraIsize: 32,
	}
	b.initExtentHeader(&inode)

	return inode
}

// initExtentHeader initializes the extent tree header in an inode's block array.
// The extent header is stored in the first 12 bytes of the inode's block field
// and contains metadata about the extent tree structure and depth.
func (b *builder) initExtentHeader(inode *inode) {
	for i := range inode.Block {
		inode.Block[i] = 0
	}

	binary.LittleEndian.PutUint16(inode.Block[0:2], extentMagic)
	binary.LittleEndian.PutUint16(inode.Block[2:4], 0)  // entries
	binary.LittleEndian.PutUint16(inode.Block[4:6], 4)  // max entries
	binary.LittleEndian.PutUint16(inode.Block[6:8], 0)  // depth
	binary.LittleEndian.PutUint32(inode.Block[8:12], 0) // generation
}

// setExtent sets a single extent mapping in an inode's extent tree.
// Maps a contiguous range of logical blocks to physical blocks on disk.
// Used for files that fit in a single extent or as part of a larger extent tree.
func (b *builder) setExtent(inode *inode, logicalBlock, physicalBlock uint32, length uint16) {
	binary.LittleEndian.PutUint16(inode.Block[2:4], 1)
	binary.LittleEndian.PutUint32(inode.Block[12:16], logicalBlock)
	binary.LittleEndian.PutUint16(inode.Block[16:18], length)
	binary.LittleEndian.PutUint16(inode.Block[18:20], 0)
	binary.LittleEndian.PutUint32(inode.Block[20:24], physicalBlock)
}

// extent represents a contiguous range of blocks in an extent tree.
type extent struct {
	logical  uint32
	physical uint32
	length   uint16
}

// Maximum extents per leaf block: (4096 - 12 header) / 12 bytes per extent = 340
const maxExtentsPerLeaf = (blockSize - 12) / 12

// buildExtentList converts a list of block numbers into contiguous extents.
func buildExtentList(blocks []uint32) []extent {
	if len(blocks) == 0 {
		return nil
	}

	var extents []extent
	current := extent{logical: 0, physical: blocks[0], length: 1}

	for i := 1; i < len(blocks); i++ {
		if blocks[i] == current.physical+uint32(current.length) && current.length < 32768 {
			current.length++
		} else {
			extents = append(extents, current)
			current = extent{logical: uint32(i), physical: blocks[i], length: 1}
		}
	}

	return append(extents, current)
}

// writeExtentToBuffer writes an extent entry at the specified offset in a buffer.
func writeExtentToBuffer(buf []byte, off int, ext extent) {
	binary.LittleEndian.PutUint32(buf[off:], ext.logical)
	binary.LittleEndian.PutUint16(buf[off+4:], ext.length)
	binary.LittleEndian.PutUint16(buf[off+6:], 0)
	binary.LittleEndian.PutUint32(buf[off+8:], ext.physical)
}

// setExtentMultiple handles allocation of non-contiguous blocks by creating multiple extents.
// For small numbers of blocks, creates individual extents. For larger allocations,
// creates an indexed extent tree with multiple leaf blocks.
// Maximum supported: 1360 extents (4 leaf blocks × 340 extents per leaf).
func (b *builder) setExtentMultiple(inode *inode, blocks []uint32) error {
	if len(blocks) == 0 {
		return nil
	}

	extents := buildExtentList(blocks)

	// If fits in inode (max 4 extents), write directly
	if len(extents) <= 4 {
		binary.LittleEndian.PutUint16(inode.Block[2:4], uint16(len(extents)))
		for i, ext := range extents {
			writeExtentToBuffer(inode.Block[:], 12+i*12, ext)
		}
		return nil
	}

	return b.writeExtentTree(inode, extents)
}

// writeExtentTree creates an indexed extent tree for files with many extents.
func (b *builder) writeExtentTree(inode *inode, extents []extent) error {
	const maxIndexEntries = 4
	const maxTotalExtents = maxExtentsPerLeaf * maxIndexEntries // 1360

	if len(extents) > maxTotalExtents {
		return fmt.Errorf("too many extents (%d): maximum supported is %d", len(extents), maxTotalExtents)
	}

	numLeaves := (len(extents) + maxExtentsPerLeaf - 1) / maxExtentsPerLeaf

	leafBlocks, err := b.allocateLeafBlocks(numLeaves)
	if err != nil {
		return err
	}

	if err := b.writeExtentLeaves(leafBlocks, extents); err != nil {
		return err
	}

	b.setupIndexNode(inode, leafBlocks, extents, numLeaves)

	return nil
}

// allocateLeafBlocks allocates the specified number of blocks for extent leaves.
func (b *builder) allocateLeafBlocks(count int) ([]uint32, error) {
	blocks := make([]uint32, count)
	for i := 0; i < count; i++ {
		block, err := b.allocateBlock()
		if err != nil {
			return nil, fmt.Errorf("failed to allocate extent leaf block %d: %w", i, err)
		}
		blocks[i] = block
	}
	return blocks, nil
}

// writeExtentLeaves writes extent data to the allocated leaf blocks.
func (b *builder) writeExtentLeaves(leafBlocks []uint32, extents []extent) error {
	for leafIdx, leafBlock := range leafBlocks {
		startIdx := leafIdx * maxExtentsPerLeaf
		endIdx := startIdx + maxExtentsPerLeaf
		if endIdx > len(extents) {
			endIdx = len(extents)
		}
		leafExtents := extents[startIdx:endIdx]

		leaf := make([]byte, blockSize)
		binary.LittleEndian.PutUint16(leaf[0:2], extentMagic)
		binary.LittleEndian.PutUint16(leaf[2:4], uint16(len(leafExtents)))
		binary.LittleEndian.PutUint16(leaf[4:6], maxExtentsPerLeaf)
		binary.LittleEndian.PutUint16(leaf[6:8], 0) // depth 0

		for i, ext := range leafExtents {
			writeExtentToBuffer(leaf, 12+i*12, ext)
		}

		if err := b.disk.writeAt(leaf, int64(b.layout.BlockOffset(leafBlock))); err != nil {
			return fmt.Errorf("failed to write extent leaf block %d: %w", leafIdx, err)
		}
	}
	return nil
}

// setupIndexNode configures the inode as an extent index node pointing to leaf blocks.
func (b *builder) setupIndexNode(inode *inode, leafBlocks []uint32, extents []extent, numLeaves int) {
	for i := range inode.Block {
		inode.Block[i] = 0
	}

	binary.LittleEndian.PutUint16(inode.Block[0:2], extentMagic)
	binary.LittleEndian.PutUint16(inode.Block[2:4], uint16(numLeaves))
	binary.LittleEndian.PutUint16(inode.Block[4:6], 4) // max index entries
	binary.LittleEndian.PutUint16(inode.Block[6:8], 1) // depth 1

	for i, leafBlock := range leafBlocks {
		off := 12 + i*12
		firstLogical := extents[i*maxExtentsPerLeaf].logical
		binary.LittleEndian.PutUint32(inode.Block[off:], firstLogical)
		binary.LittleEndian.PutUint32(inode.Block[off+4:], leafBlock)
		binary.LittleEndian.PutUint16(inode.Block[off+8:], 0)
	}

	inode.BlocksLo += uint32(numLeaves) * (blockSize / 512)
}

// writeInode writes an inode structure to its designated location in the inode table.
// Inodes are stored in inode tables within their respective block groups.
// The inode number determines which group and offset within the table to use.
func (b *builder) writeInode(inodeNum uint32, inode *inode) error {
	var buf bytes.Buffer
	if err := binary.Write(&buf, binary.LittleEndian, inode); err != nil {
		return fmt.Errorf("failed to encode inode %d: %w", inodeNum, err)
	}

	if err := b.disk.writeAt(buf.Bytes(), int64(b.layout.InodeOffset(inodeNum))); err != nil {
		return fmt.Errorf("failed to write inode %d: %w", inodeNum, err)
	}

	return nil
}

// readInode reads an inode structure from its location in the inode table.
// Returns a pointer to the inode data, which can be used for reading file metadata
// or modifying inode attributes. The inode number determines the group and offset.
func (b *builder) readInode(inodeNum uint32) (*inode, error) {
	buf := make([]byte, inodeSize)
	if err := b.disk.readAt(buf, int64(b.layout.InodeOffset(inodeNum))); err != nil {
		return nil, fmt.Errorf("failed to read inode %d: %w", inodeNum, err)
	}

	inode := &inode{}
	if err := binary.Read(bytes.NewReader(buf), binary.LittleEndian, inode); err != nil {
		return nil, fmt.Errorf("failed to decode inode %d: %w", inodeNum, err)
	}

	return inode, nil
}

// readLiveInode reads an inode, rejecting numbers that are out of range or
// not allocated in the inode bitmap. Without this check, operations against
// freed or stale inode numbers would write into unrelated blocks once the
// number is reused — including directory cycles when an inode is reallocated
// inside its own former subtree (found by FuzzOps: stack overflow in
// deleteDirectory).
func (b *builder) readLiveInode(inodeNum uint32) (*inode, error) {
	allocated, err := b.isInodeAllocated(inodeNum)
	if err != nil {
		return nil, err
	}
	if !allocated {
		return nil, fmt.Errorf("inode %d is not allocated", inodeNum)
	}

	return b.readInode(inodeNum)
}

// readLiveDirInode reads an allocated inode and verifies it is a directory.
func (b *builder) readLiveDirInode(inodeNum uint32) (*inode, error) {
	ino, err := b.readLiveInode(inodeNum)
	if err != nil {
		return nil, err
	}
	if ino.Mode&0xF000 != s_IFDIR {
		return nil, fmt.Errorf("inode %d is not a directory", inodeNum)
	}

	return ino, nil
}

// incrementLinkCount increases the hard link count for the specified inode.
// This is called when a directory entry is added that references the inode,
// ensuring the link count accurately reflects the number of directory references.
func (b *builder) incrementLinkCount(inodeNum uint32) error {
	inode, err := b.readInode(inodeNum)
	if err != nil {
		return fmt.Errorf("failed to read inode for link count increment: %w", err)
	}

	if inode.LinksCount >= 65000 {
		return fmt.Errorf("too many links to inode %d (maximum 65000)", inodeNum)
	}
	inode.LinksCount++
	if err := b.writeInode(inodeNum, inode); err != nil {
		return fmt.Errorf("failed to write inode after incrementing link count: %w", err)
	}

	return nil
}

// decrementLinkCount decreases the hard link count for the specified inode.
// Returns the new link count after decrementing.
// This is called when a directory entry referencing the inode is removed.
func (b *builder) decrementLinkCount(inodeNum uint32) (uint16, error) {
	inode, err := b.readInode(inodeNum)
	if err != nil {
		return 0, fmt.Errorf("failed to read inode for link count decrement: %w", err)
	}

	if inode.LinksCount > 0 {
		inode.LinksCount--
	}

	if err := b.writeInode(inodeNum, inode); err != nil {
		return 0, fmt.Errorf("failed to write inode after decrementing link count: %w", err)
	}

	return inode.LinksCount, nil
}

// addBlockToInode adds a new block to a directory inode's extent tree.
// Used when a directory grows beyond its current block allocation.
// May convert from simple extents to indexed extents for large directories.
func (b *builder) addBlockToInode(inodeNum, newBlock uint32) error {
	inode, err := b.readInode(inodeNum)
	if err != nil {
		return fmt.Errorf("failed to read inode for block addition: %w", err)
	}

	entries := binary.LittleEndian.Uint16(inode.Block[2:4])
	maxEntries := binary.LittleEndian.Uint16(inode.Block[4:6])
	depth := binary.LittleEndian.Uint16(inode.Block[6:8])

	if depth != 0 {
		return b.addBlockToIndexedInode(inodeNum, newBlock)
	}

	if entries == 0 {
		binary.LittleEndian.PutUint16(inode.Block[2:4], 1)
		binary.LittleEndian.PutUint32(inode.Block[12:], 0)
		binary.LittleEndian.PutUint16(inode.Block[16:], 1)
		binary.LittleEndian.PutUint16(inode.Block[18:], 0)
		binary.LittleEndian.PutUint32(inode.Block[20:], newBlock)

		if err := b.writeInode(inodeNum, inode); err != nil {
			return fmt.Errorf("failed to write inode after initializing extent: %w", err)
		}

		return nil
	}

	lastOff := 12 + (entries-1)*12
	lastLogical := binary.LittleEndian.Uint32(inode.Block[lastOff:])
	lastLen := binary.LittleEndian.Uint16(inode.Block[lastOff+4:])
	lastStart := binary.LittleEndian.Uint32(inode.Block[lastOff+8:])

	if lastStart+uint32(lastLen) == newBlock && lastLen < 32768 {
		binary.LittleEndian.PutUint16(inode.Block[lastOff+4:], lastLen+1)

		if err := b.writeInode(inodeNum, inode); err != nil {
			return fmt.Errorf("failed to write inode after extending extent: %w", err)
		}

		return nil
	}

	if entries >= maxEntries {
		return b.convertToIndexedExtents(inodeNum, newBlock)
	}

	newOff := 12 + entries*12
	nextLogical := lastLogical + uint32(lastLen)

	binary.LittleEndian.PutUint32(inode.Block[newOff:], nextLogical)
	binary.LittleEndian.PutUint16(inode.Block[newOff+4:], 1)
	binary.LittleEndian.PutUint16(inode.Block[newOff+6:], 0)
	binary.LittleEndian.PutUint32(inode.Block[newOff+8:], newBlock)

	binary.LittleEndian.PutUint16(inode.Block[2:4], entries+1)

	if err := b.writeInode(inodeNum, inode); err != nil {
		return fmt.Errorf("failed to write inode after adding extent entry: %w", err)
	}

	return nil
}

// convertToIndexedExtents converts a simple extent inode to use indexed extents.
// Creates an extent index block to manage multiple extents efficiently.
// Required when a file or directory exceeds the capacity of inline extent storage.
func (b *builder) convertToIndexedExtents(inodeNum, newBlock uint32) error {
	inode, err := b.readInode(inodeNum)
	if err != nil {
		return fmt.Errorf("failed to read inode for extent conversion: %w", err)
	}

	entries := binary.LittleEndian.Uint16(inode.Block[2:4])

	leafBlock, err := b.allocateBlock()
	if err != nil {
		return err
	}

	leaf := make([]byte, blockSize)
	binary.LittleEndian.PutUint16(leaf[0:], extentMagic)
	binary.LittleEndian.PutUint16(leaf[2:], entries+1)
	binary.LittleEndian.PutUint16(leaf[4:], (blockSize-12)/12)
	binary.LittleEndian.PutUint16(leaf[6:], 0)

	copy(leaf[12:], inode.Block[12:12+entries*12])

	lastOff := 12 + (entries-1)*12
	lastLogical := binary.LittleEndian.Uint32(leaf[lastOff:])
	lastLen := binary.LittleEndian.Uint16(leaf[lastOff+4:])
	nextLogical := lastLogical + uint32(lastLen)

	newOff := 12 + entries*12
	binary.LittleEndian.PutUint32(leaf[newOff:], nextLogical)
	binary.LittleEndian.PutUint16(leaf[newOff+4:], 1)
	binary.LittleEndian.PutUint16(leaf[newOff+6:], 0)
	binary.LittleEndian.PutUint32(leaf[newOff+8:], newBlock)

	if err := b.disk.writeAt(leaf, int64(b.layout.BlockOffset(leafBlock))); err != nil {
		return fmt.Errorf("failed to write extent leaf block: %w", err)
	}

	for i := range inode.Block {
		inode.Block[i] = 0
	}

	binary.LittleEndian.PutUint16(inode.Block[0:], extentMagic)
	binary.LittleEndian.PutUint16(inode.Block[2:], 1)
	binary.LittleEndian.PutUint16(inode.Block[4:], 4)
	binary.LittleEndian.PutUint16(inode.Block[6:], 1)

	binary.LittleEndian.PutUint32(inode.Block[12:], 0)
	binary.LittleEndian.PutUint32(inode.Block[16:], leafBlock)
	binary.LittleEndian.PutUint16(inode.Block[20:], 0)

	inode.BlocksLo += blockSize / 512

	if err := b.writeInode(inodeNum, inode); err != nil {
		return fmt.Errorf("failed to write inode after converting to indexed extents: %w", err)
	}

	return nil
}

// addBlockToIndexedInode adds a new block to an inode that uses indexed extents.
// Updates the extent index structure to include the new extent mapping.
// Handles the complexity of maintaining sorted extent indices.
func (b *builder) addBlockToIndexedInode(inodeNum, newBlock uint32) error {
	inode, err := b.readInode(inodeNum)
	if err != nil {
		return fmt.Errorf("failed to read indexed inode: %w", err)
	}

	leafBlock := binary.LittleEndian.Uint32(inode.Block[16:])

	leaf := make([]byte, blockSize)
	if err := b.disk.readAt(leaf, int64(b.layout.BlockOffset(leafBlock))); err != nil {
		return fmt.Errorf("failed to read extent leaf block: %w", err)
	}

	entries := binary.LittleEndian.Uint16(leaf[2:4])
	maxEntries := binary.LittleEndian.Uint16(leaf[4:6])

	lastOff := 12 + (entries-1)*12
	lastLogical := binary.LittleEndian.Uint32(leaf[lastOff:])
	lastLen := binary.LittleEndian.Uint16(leaf[lastOff+4:])
	lastStart := binary.LittleEndian.Uint32(leaf[lastOff+8:])

	if lastStart+uint32(lastLen) == newBlock && lastLen < 32768 {
		binary.LittleEndian.PutUint16(leaf[lastOff+4:], lastLen+1)

		if err := b.disk.writeAt(leaf, int64(b.layout.BlockOffset(leafBlock))); err != nil {
			return fmt.Errorf("failed to write updated extent leaf: %w", err)
		}

		return nil
	}

	if entries >= maxEntries {
		return fmt.Errorf("extent tree depth > 1 not implemented")
	}

	nextLogical := lastLogical + uint32(lastLen)
	newOff := 12 + entries*12

	binary.LittleEndian.PutUint32(leaf[newOff:], nextLogical)
	binary.LittleEndian.PutUint16(leaf[newOff+4:], 1)
	binary.LittleEndian.PutUint16(leaf[newOff+6:], 0)
	binary.LittleEndian.PutUint32(leaf[newOff+8:], newBlock)

	binary.LittleEndian.PutUint16(leaf[2:4], entries+1)

	if err := b.disk.writeAt(leaf, int64(b.layout.BlockOffset(leafBlock))); err != nil {
		return fmt.Errorf("failed to write new extent leaf: %w", err)
	}

	return nil
}

// getInodeBlocks extracts all block numbers referenced by an inode's extent tree.
// Parses the extent structures to return a complete list of data blocks allocated
// to the file or directory. Supports both simple extents and complex extent trees.
func (b *builder) getInodeBlocks(inode *inode) ([]uint32, error) {
	if (inode.Flags & inodeFlagExtents) == 0 {
		return nil, nil
	}

	entries := binary.LittleEndian.Uint16(inode.Block[2:4])
	depth := binary.LittleEndian.Uint16(inode.Block[6:8])

	if entries == 0 {
		return nil, nil
	}

	var blocks []uint32

	if depth == 0 {
		for i := uint16(0); i < entries && i < 4; i++ {
			off := 12 + i*12
			length := binary.LittleEndian.Uint16(inode.Block[off+4:])
			startLo := binary.LittleEndian.Uint32(inode.Block[off+8:])

			for j := uint16(0); j < length; j++ {
				blocks = append(blocks, startLo+uint32(j))
			}
		}
	} else {
		for i := uint16(0); i < entries && i < 4; i++ {
			off := 12 + i*12
			leafBlock := binary.LittleEndian.Uint32(inode.Block[off+4:])

			leafData := make([]byte, blockSize)
			if err := b.disk.readAt(leafData, int64(b.layout.BlockOffset(leafBlock))); err != nil {
				return nil, fmt.Errorf("failed to read extent leaf block %d: %w", leafBlock, err)
			}

			leafEntries := binary.LittleEndian.Uint16(leafData[2:4])
			for j := uint16(0); j < leafEntries; j++ {
				extOff := 12 + j*12
				length := binary.LittleEndian.Uint16(leafData[extOff+4:])
				startLo := binary.LittleEndian.Uint32(leafData[extOff+8:])

				for k := uint16(0); k < length; k++ {
					blocks = append(blocks, startLo+uint32(k))
				}
			}
		}
	}

	return blocks, nil
}
