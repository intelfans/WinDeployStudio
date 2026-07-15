// Package ext4fs provides a pure Go implementation for creating ext4 filesystem images.
// It allows building ext4 filesystems programmatically without external dependencies,
// suitable for creating disk images for virtual machines, containers, or embedded systems.
//
// The main entry point is Ext4ImageBuilder in disk.go, which provides a high-level API
// for creating and managing ext4 images. The internal Builder handles the low-level
// filesystem construction details.
package ext4fs

import (
	"encoding/binary"
	"fmt"
)

// ============================================================================
// Public API
// ============================================================================

// createDirectory creates a new directory with the specified name under the given parent directory.
// It allocates a new inode and data block, initializes the directory with "." and ".." entries,
// and adds the new directory entry to the parent. Returns the inode number of the created directory.
func (b *builder) createDirectory(parentInode uint32, name string, mode, uid, gid uint16) (uint32, error) {
	if err := validateName(name); err != nil {
		return 0, fmt.Errorf("invalid directory name: %w", err)
	}

	existingInode, err := b.findEntry(parentInode, name)
	if err != nil {
		return 0, fmt.Errorf("failed to check for existing entry: %w", err)
	}
	if existingInode != 0 {
		return 0, fmt.Errorf("entry %q already exists", name)
	}

	inodeNum, err := b.allocateInode()
	if err != nil {
		return 0, err
	}

	dataBlock, err := b.allocateBlock()
	if err != nil {
		return 0, err
	}

	inode := b.makeDirectoryInode(mode, uid, gid)
	inode.LinksCount = 2
	inode.SizeLo = blockSize
	inode.BlocksLo = blockSize / 512
	b.setExtent(&inode, 0, dataBlock, 1)

	if err := b.writeInode(inodeNum, &inode); err != nil {
		return 0, err
	}

	entries := []dirEntry{
		{Inode: inodeNum, Type: ftDir, Name: []byte(".")},
		{Inode: parentInode, Type: ftDir, Name: []byte("..")},
	}
	if err := b.writeDirBlock(dataBlock, entries); err != nil {
		return 0, err
	}

	if err := b.addDirEntry(parentInode, dirEntry{
		Inode: inodeNum,
		Type:  ftDir,
		Name:  []byte(name),
	}); err != nil {
		return 0, err
	}

	if err := b.incrementLinkCount(parentInode); err != nil {
		return 0, err
	}

	// Track directory in correct group
	group := (inodeNum - 1) / inodesPerGroup
	b.usedDirsPerGroup[group]++

	if b.debug {
		fmt.Printf("✓ Created directory: %s (inode %d)\n", name, inodeNum)
	}

	return inodeNum, nil
}

// createFile creates a new regular file with the specified content under the given parent directory.
// If a file with the same name already exists, it overwrites the existing file.
// The file content is written across one or more allocated blocks using extent mapping.
// Returns the inode number of the created or overwritten file.
func (b *builder) createFile(parentInode uint32, name string, content []byte, mode, uid, gid uint16) (uint32, error) {
	if err := validateName(name); err != nil {
		return 0, fmt.Errorf("invalid file name: %w", err)
	}

	existingInode, err := b.findEntry(parentInode, name)
	if err != nil {
		return 0, fmt.Errorf("failed to check for existing file: %w", err)
	}

	if existingInode != 0 {
		existing, err := b.readInode(existingInode)
		if err != nil {
			return 0, fmt.Errorf("failed to read existing inode: %w", err)
		}
		// Overwrite is defined for regular files only; silently turning a
		// directory or symlink into a file would orphan its subtree and
		// leave the parent dirent with a stale file type.
		if existing.Mode&0xF000 != s_IFREG {
			return 0, fmt.Errorf("entry %q exists and is not a regular file", name)
		}
		return b.overwriteFile(existingInode, content, mode, uid, gid)
	}

	inodeNum, err := b.allocateInode()
	if err != nil {
		return 0, err
	}

	inode := b.makeFileInode(mode, uid, gid, uint64(len(content)))

	inode, _, err = b.allocateAndWriteFileContent(inode, content)
	if err != nil {
		return 0, err
	}

	if err := b.writeInode(inodeNum, &inode); err != nil {
		return 0, err
	}

	if err := b.addDirEntry(parentInode, dirEntry{
		Inode: inodeNum,
		Type:  ftRegFile,
		Name:  []byte(name),
	}); err != nil {
		return 0, err
	}

	if b.debug {
		fmt.Printf("✓ Created file: %s (inode %d, size %d)\n", name, inodeNum, len(content))
	}

	return inodeNum, nil
}

// allocateAndWriteFileContent allocates blocks for file content, sets extents, and writes the content.
// Returns the modified inode and allocated blocks.
func (b *builder) allocateAndWriteFileContent(inode inode, content []byte) (inode, []uint32, error) {
	size := uint64(len(content))

	blocksNeeded := uint32((size + blockSize - 1) / blockSize)
	if blocksNeeded == 0 {
		blocksNeeded = 1
	}

	inode.SizeLo = uint32(size)
	inode.SizeHi = uint32(size >> 32)
	inode.BlocksLo = blocksNeeded * (blockSize / 512)

	blocks, err := b.allocateBlocks(blocksNeeded)
	if err != nil {
		return inode, nil, err
	}

	if blocksNeeded == 1 {
		b.setExtent(&inode, 0, blocks[0], 1)
	} else {
		if err := b.setExtentMultiple(&inode, blocks); err != nil {
			return inode, nil, err
		}
	}

	// Write content
	for i, blk := range blocks {
		block := make([]byte, blockSize)
		start := uint64(i) * blockSize

		end := start + blockSize
		if end > size {
			end = size
		}

		if start < size {
			copy(block, content[start:end])
		}

		if err := b.disk.writeAt(block, int64(b.layout.BlockOffset(blk))); err != nil {
			return inode, nil, fmt.Errorf("failed to write file block %d: %w", blk, err)
		}
	}

	return inode, blocks, nil
}

// inodeBitmapStats scans group g's on-disk inode bitmap and returns the number of
// used inodes plus the count of unused inodes at the tail of the table
// (itable_unused). The bitmap is the source of truth — setInodeBit/clearInodeBit
// write it through on every alloc/free — so this stays correct across reopen
// regardless of which inodes were freed below the allocation high-water mark.
func (b *builder) inodeBitmapStats(g uint32) (used, itableUnused uint16, err error) {
	gl := b.layout.GetGroupLayout(g)

	bitmap := make([]byte, blockSize)
	if err := b.disk.readAt(bitmap, int64(b.layout.BlockOffset(gl.InodeBitmapBlock))); err != nil {
		return 0, 0, fmt.Errorf("read inode bitmap for group %d: %w", g, err)
	}

	highestIndex := -1

	var usedCount uint32
	for i := uint32(0); i < inodesPerGroup; i++ {
		if bitmap[i/8]&(1<<(i%8)) != 0 {
			highestIndex = int(i)
			usedCount++
		}
	}

	return uint16(usedCount), uint16(inodesPerGroup - uint32(highestIndex+1)), nil
}

// calculateGroupStats returns free blocks, free inodes, and itable_unused for a
// group. Free inodes come straight from the bitmap (inodeBitmapStats); free blocks
// from the per-group cursor minus blocks freed below the high-water mark (seeded
// from the bitmap on reopen by loadBlockBitmap).
func (b *builder) calculateGroupStats(g uint32) (freeBlocks, freeInodes, itableUnused uint16, err error) {
	gl := b.layout.GetGroupLayout(g)

	usedBlocks := b.nextBlockPerGroup[g] - gl.GroupStart - b.freedBlocksPerGroup[g]
	freeBlocks = uint16(gl.BlocksInGroup - usedBlocks)

	usedInodes, itableUnused, err := b.inodeBitmapStats(g)
	if err != nil {
		return 0, 0, 0, err
	}
	freeInodes = uint16(inodesPerGroup) - usedInodes

	return freeBlocks, freeInodes, itableUnused, nil
}

// updateGroupDescriptor updates the group descriptor for the given group.
func (b *builder) updateGroupDescriptor(g uint32, freeBlocks, freeInodes, usedDirs, itableUnused uint16) error {
	gdOffset := b.layout.BlockOffset(b.layout.GetGroupLayout(0).GDTStart) + uint64(g*32)

	gdBuf := make([]byte, 32)
	if err := b.disk.readAt(gdBuf, int64(gdOffset)); err != nil {
		return fmt.Errorf("failed to read group descriptor for group %d: %w", g, err)
	}

	// Update fields
	binary.LittleEndian.PutUint16(gdBuf[12:14], freeBlocks)
	binary.LittleEndian.PutUint16(gdBuf[14:16], freeInodes)
	binary.LittleEndian.PutUint16(gdBuf[16:18], usedDirs)
	binary.LittleEndian.PutUint16(gdBuf[18:20], 0) // Flags
	binary.LittleEndian.PutUint16(gdBuf[28:30], itableUnused)

	if err := b.disk.writeAt(gdBuf, int64(gdOffset)); err != nil {
		return fmt.Errorf("failed to write group descriptor for group %d: %w", g, err)
	}

	// Update backup GDTs
	for bg := uint32(1); bg < b.layout.GroupCount; bg++ {
		if isSparseGroup(bg) {
			backupGl := b.layout.GetGroupLayout(bg)

			backupOffset := b.layout.BlockOffset(backupGl.GDTStart) + uint64(g*32)
			if err := b.disk.writeAt(gdBuf, int64(backupOffset)); err != nil {
				return fmt.Errorf("failed to write backup group descriptor for group %d: %w", bg, err)
			}
		}
	}

	return nil
}

// updateSuperblocks updates the primary and backup superblocks with total free blocks and inodes.
func (b *builder) updateSuperblocks(totalFreeBlocks, totalFreeInodes uint32) error {
	// Update primary superblock
	sbOffset := b.layout.PartitionStart + superblockOffset

	sbBuf := make([]byte, 1024)
	if err := b.disk.readAt(sbBuf, int64(sbOffset)); err != nil {
		return fmt.Errorf("failed to read primary superblock: %w", err)
	}

	binary.LittleEndian.PutUint32(sbBuf[0x0C:0x10], totalFreeBlocks)
	binary.LittleEndian.PutUint32(sbBuf[0x10:0x14], totalFreeInodes)

	if err := b.disk.writeAt(sbBuf, int64(sbOffset)); err != nil {
		return fmt.Errorf("failed to write primary superblock: %w", err)
	}

	// Update backup superblocks
	for g := uint32(1); g < b.layout.GroupCount; g++ {
		if isSparseGroup(g) {
			gl := b.layout.GetGroupLayout(g)

			backupSbOffset := b.layout.BlockOffset(gl.SuperblockBlock)
			if err := b.disk.readAt(sbBuf, int64(backupSbOffset)); err != nil {
				return fmt.Errorf("failed to read backup superblock for group %d: %w", g, err)
			}

			binary.LittleEndian.PutUint32(sbBuf[0x0C:0x10], totalFreeBlocks)
			binary.LittleEndian.PutUint32(sbBuf[0x10:0x14], totalFreeInodes)

			if err := b.disk.writeAt(sbBuf, int64(backupSbOffset)); err != nil {
				return fmt.Errorf("failed to write backup superblock for group %d: %w", g, err)
			}
		}
	}

	return nil
}

// createSymlink creates a symbolic link pointing to the specified target path.
// For targets <= 60 bytes, the target is stored directly in the inode's block array (fast symlink).
// For longer targets, a separate data block is allocated to store the target path.
// Returns the inode number of the created symlink.
func (b *builder) createSymlink(parentInode uint32, name, target string, uid, gid uint16) (uint32, error) {
	if err := validateName(name); err != nil {
		return 0, fmt.Errorf("invalid symlink name: %w", err)
	}

	if len(target) == 0 {
		return 0, fmt.Errorf("symlink target cannot be empty")
	}

	if len(target) > 4096 {
		return 0, fmt.Errorf("symlink target too long: %d > 4096", len(target))
	}

	existingInode, err := b.findEntry(parentInode, name)
	if err != nil {
		return 0, fmt.Errorf("failed to check for existing entry: %w", err)
	}
	if existingInode != 0 {
		return 0, fmt.Errorf("entry %q already exists", name)
	}

	inodeNum, err := b.allocateInode()
	if err != nil {
		return 0, err
	}

	inode := inode{
		Mode:       s_IFLNK | 0777,
		UID:        uid,
		GID:        gid,
		SizeLo:     uint32(len(target)),
		LinksCount: 1,
		Atime:      b.layout.CreatedAt,
		Ctime:      b.layout.CreatedAt,
		Mtime:      b.layout.CreatedAt,
		Crtime:     b.layout.CreatedAt,
		ExtraIsize: 32,
	}

	// Fast symlink: target stored in inode.Block (up to 60 bytes)
	if len(target) <= 60 {
		copy(inode.Block[:], target)
		inode.Flags = 0
		inode.BlocksLo = 0
	} else {
		inode.Flags = inodeFlagExtents

		dataBlock, err := b.allocateBlock()
		if err != nil {
			return 0, err
		}

		b.initExtentHeader(&inode)
		b.setExtent(&inode, 0, dataBlock, 1)
		inode.BlocksLo = blockSize / 512

		block := make([]byte, blockSize)
		copy(block, target)

		if err := b.disk.writeAt(block, int64(b.layout.BlockOffset(dataBlock))); err != nil {
			return 0, fmt.Errorf("failed to write symlink target block: %w", err)
		}
	}

	if err := b.writeInode(inodeNum, &inode); err != nil {
		return 0, err
	}

	if err := b.addDirEntry(parentInode, dirEntry{
		Inode: inodeNum,
		Type:  ftSymlink,
		Name:  []byte(name),
	}); err != nil {
		return 0, err
	}

	if b.debug {
		fmt.Printf("✓ Created symlink: %s -> %s\n", name, target)
	}

	return inodeNum, nil
}

// link creates a hard link to an existing inode under the specified parent directory.
// The target inode must exist and must not be a directory (ext4 forbids directory hardlinks).
// Increments the target inode's link count and adds a new directory entry pointing to it.
func (b *builder) link(parentInode uint32, name string, targetInode uint32) error {
	if err := validateName(name); err != nil {
		return fmt.Errorf("invalid link name: %w", err)
	}

	existingInode, err := b.findEntry(parentInode, name)
	if err != nil {
		return fmt.Errorf("failed to check for existing entry: %w", err)
	}
	if existingInode != 0 {
		return fmt.Errorf("entry %q already exists", name)
	}

	inode, err := b.readLiveInode(targetInode)
	if err != nil {
		return fmt.Errorf("failed to read target inode: %w", err)
	}
	// The bitmap bit can be set for a half-created inode whose table entry
	// was never written (failed create); a zero LinksCount exposes it.
	if inode.LinksCount == 0 {
		return fmt.Errorf("target inode %d has link count 0 (freed or never allocated)", targetInode)
	}
	if (inode.Mode & 0xF000) == s_IFDIR {
		return fmt.Errorf("hard links to directories are not allowed")
	}

	if err := b.incrementLinkCount(targetInode); err != nil {
		return err
	}

	if err := b.addDirEntry(parentInode, dirEntry{
		Inode: targetInode,
		Type:  modeToFileType(inode.Mode),
		Name:  []byte(name),
	}); err != nil {
		if _, decErr := b.decrementLinkCount(targetInode); decErr != nil {
			return fmt.Errorf("failed to add directory entry: %v (rollback failed: %w)", err, decErr)
		}
		return fmt.Errorf("failed to add directory entry: %w", err)
	}

	if b.debug {
		fmt.Printf("✓ Created hard link: %s -> inode %d\n", name, targetInode)
	}

	return nil
}

// freeInodeResources frees all resources associated with an inode (blocks, xattr, bitmap).
func (b *builder) freeInodeResources(entryInode uint32, inode *inode) error {
	if err := b.freeOldFileResources(inode); err != nil {
		return fmt.Errorf("failed to free entry resources: %w", err)
	}

	inode.LinksCount = 0
	inode.Dtime = b.layout.CreatedAt
	if err := b.writeInode(entryInode, inode); err != nil {
		return fmt.Errorf("failed to update deleted inode: %w", err)
	}

	if err := b.freeInode(entryInode); err != nil {
		return fmt.Errorf("failed to free inode: %w", err)
	}

	return nil
}

// deleteEmptyDir removes an empty directory entry and frees its resources.
func (b *builder) deleteEmptyDir(parentInode, entryInode uint32, name string, inode *inode) error {
	entries, err := b.listDirEntries(entryInode)
	if err != nil {
		return fmt.Errorf("failed to list directory entries: %w", err)
	}
	if len(entries) > 0 {
		return fmt.Errorf("directory %q is not empty", name)
	}

	if err := b.removeDirEntry(parentInode, name); err != nil {
		return fmt.Errorf("failed to remove directory entry: %w", err)
	}

	if err := b.freeInodeResources(entryInode, inode); err != nil {
		return err
	}

	if _, err := b.decrementLinkCount(parentInode); err != nil {
		return fmt.Errorf("failed to decrement parent link count: %w", err)
	}

	group := (entryInode - 1) / inodesPerGroup
	if b.usedDirsPerGroup[group] > 0 {
		b.usedDirsPerGroup[group]--
	}

	return nil
}

// unlinkFile removes a directory entry for a non-directory inode.
// Frees inode resources only when the link count reaches zero.
func (b *builder) unlinkFile(parentInode, entryInode uint32, name string) error {
	if err := b.removeDirEntry(parentInode, name); err != nil {
		return fmt.Errorf("failed to remove directory entry: %w", err)
	}

	count, err := b.decrementLinkCount(entryInode)
	if err != nil {
		return fmt.Errorf("failed to decrement link count: %w", err)
	}

	if count == 0 {
		inode, err := b.readInode(entryInode)
		if err != nil {
			return fmt.Errorf("failed to read inode for cleanup: %w", err)
		}
		if err := b.freeInodeResources(entryInode, inode); err != nil {
			return err
		}
	}

	return nil
}

// deleteEntry removes a file, symlink, or empty directory from the parent directory.
// For directories, returns an error if the directory is not empty (use deleteDirectory instead).
// The entry's inode and data blocks are freed when the link count reaches zero.
func (b *builder) deleteEntry(parentInode uint32, name string) error {
	if name == "." || name == ".." {
		return fmt.Errorf("cannot delete %q", name)
	}

	entryInode, err := b.findEntry(parentInode, name)
	if err != nil {
		return fmt.Errorf("failed to find entry: %w", err)
	}
	if entryInode == 0 {
		return fmt.Errorf("entry %q not found", name)
	}

	inode, err := b.readInode(entryInode)
	if err != nil {
		return fmt.Errorf("failed to read entry inode: %w", err)
	}

	if (inode.Mode & 0xF000) == s_IFDIR {
		if err := b.deleteEmptyDir(parentInode, entryInode, name, inode); err != nil {
			return err
		}
	} else {
		if err := b.unlinkFile(parentInode, entryInode, name); err != nil {
			return err
		}
	}

	if b.debug {
		fmt.Printf("✓ Deleted entry: %s (inode %d)\n", name, entryInode)
	}

	return nil
}

// deleteDirectory recursively removes a directory and all its contents.
// This is equivalent to "rm -rf" behavior - it deletes files, symlinks,
// and subdirectories without checking if they are empty.
func (b *builder) deleteDirectory(parentInode uint32, name string) error {
	if name == "." || name == ".." {
		return fmt.Errorf("cannot delete %q", name)
	}

	// Find the entry
	entryInode, err := b.findEntry(parentInode, name)
	if err != nil {
		return fmt.Errorf("failed to find entry: %w", err)
	}

	if entryInode == 0 {
		return fmt.Errorf("entry %q not found", name)
	}

	// Read the inode to verify it's a directory
	inode, err := b.readInode(entryInode)
	if err != nil {
		return fmt.Errorf("failed to read entry inode: %w", err)
	}

	if (inode.Mode & s_IFDIR) == 0 {
		return fmt.Errorf("%q is not a directory", name)
	}

	// List all entries in the directory
	entries, err := b.listDirEntries(entryInode)
	if err != nil {
		return fmt.Errorf("failed to list directory entries: %w", err)
	}

	// Recursively delete all entries
	for _, entry := range entries {
		entryName := string(entry.Name)
		if entry.Type == ftDir {
			if err := b.deleteDirectory(entryInode, entryName); err != nil {
				return fmt.Errorf("failed to delete subdirectory %q: %w", entryName, err)
			}
		} else {
			if err := b.deleteEntry(entryInode, entryName); err != nil {
				return fmt.Errorf("failed to delete entry %q: %w", entryName, err)
			}
		}
	}

	// Now the directory is empty, delete it
	return b.deleteEntry(parentInode, name)
}

// setXattr sets an extended attribute (xattr) on the specified inode.
// Extended attributes are name-value pairs that provide additional metadata
// beyond standard file attributes. Names use namespace prefixes like "user.",
// "trusted.", "security.", or "system.". If the xattr already exists, its value is updated.
func (b *builder) setXattr(inodeNum uint32, name string, value []byte) error {
	if len(name) == 0 {
		return fmt.Errorf("xattr name cannot be empty")
	}

	nameIndex, shortName, err := parseXattrName(name)
	if err != nil {
		return err
	}

	if len(shortName) > 255 {
		return fmt.Errorf("xattr name too long: %d > 255", len(shortName))
	}

	inode, err := b.readLiveInode(inodeNum)
	if err != nil {
		return fmt.Errorf("failed to read inode for xattr: %w", err)
	}

	var (
		xattrBlock uint32
		entries    []xAttrEntry
	)

	if inode.FileACLLo != 0 {
		xattrBlock = inode.FileACLLo

		var err error

		entries, err = b.readXattrBlock(xattrBlock)
		if err != nil {
			return fmt.Errorf("failed to read existing xattr block: %w", err)
		}
	} else {
		var err error

		xattrBlock, err = b.allocateBlock()
		if err != nil {
			return err
		}

		inode.FileACLLo = xattrBlock
		inode.BlocksLo += blockSize / 512
	}

	// Update existing or add new entry
	found := false

	for i, e := range entries {
		if e.NameIndex == nameIndex && e.Name == shortName {
			entries[i].Value = value
			found = true

			break
		}
	}

	if !found {
		entries = append(entries, xAttrEntry{
			NameIndex: nameIndex,
			Name:      shortName,
			Value:     value,
		})
	}

	if err := b.writeXattrBlock(xattrBlock, entries); err != nil {
		return err
	}

	if err := b.writeInode(inodeNum, inode); err != nil {
		return fmt.Errorf("failed to write inode after xattr update: %w", err)
	}

	if b.debug {
		fmt.Printf("✓ Set xattr %s on inode %d (%d bytes)\n", name, inodeNum, len(value))
	}

	return nil
}

// listXattrs returns a list of all extended attribute names associated with the specified inode.
// The returned names include their namespace prefixes (e.g., "user.attr", "trusted.security").
// Returns an empty slice if the inode has no extended attributes.
func (b *builder) listXattrs(inodeNum uint32) ([]string, error) {
	inode, err := b.readLiveInode(inodeNum)
	if err != nil {
		return nil, fmt.Errorf("failed to read inode for xattr listing: %w", err)
	}

	if inode.FileACLLo == 0 {
		return nil, nil
	}

	entries, err := b.readXattrBlock(inode.FileACLLo)
	if err != nil {
		return nil, fmt.Errorf("failed to read xattr block: %w", err)
	}

	names := make([]string, 0, len(entries))

	for _, e := range entries {
		prefix := xattrIndexToPrefix(e.NameIndex)
		names = append(names, prefix+e.Name)
	}

	return names, nil
}

// removeXattr removes an extended attribute from the specified inode.
// If the attribute doesn't exist, no error is returned (idempotent operation).
// The xattr block may be deallocated if it becomes empty after removal.
func (b *builder) removeXattr(inodeNum uint32, name string) error {
	nameIndex, shortName, err := parseXattrName(name)
	if err != nil {
		return err
	}

	inode, err := b.readLiveInode(inodeNum)
	if err != nil {
		return fmt.Errorf("failed to read inode for xattr removal: %w", err)
	}

	if inode.FileACLLo == 0 {
		return fmt.Errorf("no xattrs on inode %d", inodeNum)
	}

	entries, err := b.readXattrBlock(inode.FileACLLo)
	if err != nil {
		return fmt.Errorf("failed to read xattr block: %w", err)
	}

	newEntries := make([]xAttrEntry, 0, len(entries))
	found := false

	for _, e := range entries {
		if e.NameIndex == nameIndex && e.Name == shortName {
			found = true
			continue
		}

		newEntries = append(newEntries, e)
	}

	if !found {
		return fmt.Errorf("xattr %s not found", name)
	}

	if len(newEntries) == 0 {
		// Free the xattr block
		if err := b.freeBlockRun(inode.FileACLLo, 1); err != nil {
			return fmt.Errorf("failed to free xattr block during removal: %w", err)
		}

		inode.FileACLLo = 0
		inode.BlocksLo -= blockSize / 512
	} else {
		if err := b.writeXattrBlock(inode.FileACLLo, newEntries); err != nil {
			return err
		}
	}

	if err := b.writeInode(inodeNum, inode); err != nil {
		return fmt.Errorf("failed to write inode after xattr removal: %w", err)
	}

	return nil
}

// finalizeMetadata updates all filesystem metadata to reflect the final state.
// This includes recalculating block and inode usage statistics per group,
// updating group descriptors with accurate counts, and ensuring the superblock
// reflects the current filesystem state. Must be called after all file operations.
func (b *builder) finalizeMetadata() error {
	// Per-group free counts come straight from each group's bitmaps
	// (calculateGroupStats), so the superblock totals are the sum of the per-group
	// counts rather than a global-cursor formula that cannot see blocks or inodes
	// freed below the allocation high-water mark.
	var totalFreeBlocks, totalFreeInodes uint32

	for g := uint32(0); g < b.layout.GroupCount; g++ {
		freeBlocks, freeInodes, itableUnused, err := b.calculateGroupStats(g)
		if err != nil {
			return err
		}
		if err := b.updateGroupDescriptor(g, freeBlocks, freeInodes, b.usedDirsPerGroup[g], itableUnused); err != nil {
			return err
		}
		totalFreeBlocks += uint32(freeBlocks)
		totalFreeInodes += uint32(freeInodes)
	}

	if err := b.updateSuperblocks(totalFreeBlocks, totalFreeInodes); err != nil {
		return err
	}

	if b.debug {
		fmt.Printf("✓ Metadata finalized: %d free blocks, %d free inodes\n",
			totalFreeBlocks, totalFreeInodes)
	}

	return nil
}
