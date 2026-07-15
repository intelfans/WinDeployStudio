package ext4fs

import (
	"encoding/binary"
	"fmt"
)

// writeDirBlock writes a block containing directory entries to disk.
// Directory entries are packed into the block with proper record length calculations
// to ensure correct parsing. The block becomes part of the directory's data extent.
func (b *builder) writeDirBlock(blockNum uint32, entries []dirEntry) error {
	block := make([]byte, blockSize)
	offset := 0

	for i, entry := range entries {
		nameLen := len(entry.Name)

		recLen := 8 + nameLen
		if recLen%4 != 0 {
			recLen += 4 - (recLen % 4)
		}

		if i == len(entries)-1 {
			recLen = blockSize - offset
		}

		binary.LittleEndian.PutUint32(block[offset:], entry.Inode)
		binary.LittleEndian.PutUint16(block[offset+4:], uint16(recLen))
		block[offset+6] = uint8(nameLen)
		block[offset+7] = entry.Type
		copy(block[offset+8:], entry.Name)

		offset += recLen
	}

	if err := b.disk.writeAt(block, int64(b.layout.BlockOffset(blockNum))); err != nil {
		return fmt.Errorf("failed to write directory block %d: %w", blockNum, err)
	}

	return nil
}

// addDirEntry adds a new directory entry to the specified directory.
// Searches existing directory blocks for space, or allocates new blocks if needed.
// Updates the directory's size and block allocation as entries are added.
func (b *builder) addDirEntry(dirInode uint32, entry dirEntry) error {
	inode, err := b.readLiveDirInode(dirInode)
	if err != nil {
		return fmt.Errorf("failed to read directory inode: %w", err)
	}

	dataBlocks, err := b.getInodeBlocks(inode)
	if err != nil {
		return fmt.Errorf("failed to get directory blocks: %w", err)
	}

	newNameLen := len(entry.Name)

	newRecLen := 8 + newNameLen
	if newRecLen%4 != 0 {
		newRecLen += 4 - (newRecLen % 4)
	}

	for _, blockNum := range dataBlocks {
		if success, err := b.tryAddEntryToBlock(blockNum, entry, newRecLen); err != nil {
			return fmt.Errorf("failed to add entry to directory block %d: %w", blockNum, err)
		} else if success {
			return nil
		}
	}

	// Allocate new block
	newBlock, err := b.allocateBlock()
	if err != nil {
		return err
	}

	if err := b.addBlockToInode(dirInode, newBlock); err != nil {
		return err
	}

	block := make([]byte, blockSize)
	binary.LittleEndian.PutUint32(block[0:], entry.Inode)
	binary.LittleEndian.PutUint16(block[4:], uint16(blockSize))
	block[6] = uint8(newNameLen)
	block[7] = entry.Type
	copy(block[8:], entry.Name)

	if err := b.disk.writeAt(block, int64(b.layout.BlockOffset(newBlock))); err != nil {
		return fmt.Errorf("failed to write directory block: %w", err)
	}

	inode, err = b.readInode(dirInode)
	if err != nil {
		return fmt.Errorf("failed to re-read directory inode: %w", err)
	}

	inode.SizeLo += blockSize

	inode.BlocksLo += blockSize / 512
	if err := b.writeInode(dirInode, inode); err != nil {
		return fmt.Errorf("failed to update directory inode: %w", err)
	}

	return nil
}

// tryAddEntryToBlock attempts to add a directory entry to an existing directory block.
// Returns true if the entry fits in the available space, false if the block is full.
// Calculates proper record lengths to maintain directory entry structure integrity.
func (b *builder) tryAddEntryToBlock(blockNum uint32, entry dirEntry, newRecLen int) (bool, error) {
	block := make([]byte, blockSize)
	if err := b.disk.readAt(block, int64(b.layout.BlockOffset(blockNum))); err != nil {
		return false, fmt.Errorf("failed to read directory block %d: %w", blockNum, err)
	}

	offset := 0
	lastOffset := 0

	for offset < blockSize {
		_, recLen, _, _, ok := parseDirentAt(block, offset)
		if !ok {
			break
		}
		lastOffset = offset
		offset += recLen
	}

	_, lastRecLen, lastNameLen, _, ok := parseDirentAt(block, lastOffset)
	if !ok {
		return false, fmt.Errorf("corrupt directory block %d", blockNum)
	}

	lastActualSize := 8 + lastNameLen
	if lastActualSize%4 != 0 {
		lastActualSize += 4 - (lastActualSize % 4)
	}

	spaceAvailable := lastRecLen - lastActualSize
	if spaceAvailable < newRecLen {
		return false, nil
	}

	binary.LittleEndian.PutUint16(block[lastOffset+4:], uint16(lastActualSize))

	newOffset := lastOffset + lastActualSize
	remaining := blockSize - newOffset

	binary.LittleEndian.PutUint32(block[newOffset:], entry.Inode)
	binary.LittleEndian.PutUint16(block[newOffset+4:], uint16(remaining))
	block[newOffset+6] = uint8(len(entry.Name))
	block[newOffset+7] = entry.Type
	copy(block[newOffset+8:], entry.Name)

	if err := b.disk.writeAt(block, int64(b.layout.BlockOffset(blockNum))); err != nil {
		return false, fmt.Errorf("failed to write directory block %d: %w", blockNum, err)
	}

	return true, nil
}

// parseDirentAt reads the linear directory entry at offset within a directory
// block. ok is false when the entry's rec_len or name_len would run past the end
// of the block — a corrupt or truncated on-disk directory — so callers stop
// scanning the block instead of slicing out of bounds and panicking.
func parseDirentAt(block []byte, offset int) (entryInode uint32, recLen, nameLen int, name string, ok bool) {
	if offset+8 > len(block) {
		return 0, 0, 0, "", false
	}
	recLen = int(binary.LittleEndian.Uint16(block[offset+4:]))
	if recLen < 8 || offset+recLen > len(block) {
		return 0, 0, 0, "", false
	}
	nameLen = int(block[offset+6])
	if nameLen > recLen-8 {
		return 0, 0, 0, "", false
	}
	entryInode = binary.LittleEndian.Uint32(block[offset:])
	name = string(block[offset+8 : offset+8+nameLen])
	return entryInode, recLen, nameLen, name, true
}

// removeDirEntry removes a directory entry with the specified name from the directory.
// The entry is removed by expanding the previous entry's rec_len to absorb the deleted entry,
// or by setting inode=0 if it's the first entry in a block.
// Returns an error if the entry is not found.
func (b *builder) removeDirEntry(dirInode uint32, name string) error {
	inode, err := b.readInode(dirInode)
	if err != nil {
		return fmt.Errorf("failed to read directory inode for entry removal: %w", err)
	}

	dataBlocks, err := b.getInodeBlocks(inode)
	if err != nil {
		return fmt.Errorf("failed to get directory blocks for entry removal: %w", err)
	}

	for _, blockNum := range dataBlocks {
		block := make([]byte, blockSize)
		if err := b.disk.readAt(block, int64(b.layout.BlockOffset(blockNum))); err != nil {
			return fmt.Errorf("failed to read directory block %d: %w", blockNum, err)
		}

		offset := 0
		prevOffset := -1

		for offset < blockSize {
			_, recLen, _, entryName, ok := parseDirentAt(block, offset)
			if !ok {
				break
			}

			if entryName == name {
				if prevOffset < 0 {
					// First entry in block: set inode to 0 to mark as unused
					binary.LittleEndian.PutUint32(block[offset:], 0)
				} else {
					// Not first entry: expand previous entry's rec_len
					prevRecLen := binary.LittleEndian.Uint16(block[prevOffset+4:])
					binary.LittleEndian.PutUint16(block[prevOffset+4:], prevRecLen+uint16(recLen))
				}

				if err := b.disk.writeAt(block, int64(b.layout.BlockOffset(blockNum))); err != nil {
					return fmt.Errorf("failed to write directory block %d: %w", blockNum, err)
				}

				return nil
			}

			prevOffset = offset
			offset += recLen
		}
	}

	return fmt.Errorf("entry %q not found in directory", name)
}

// findEntry searches for a directory entry with the specified name.
// Returns the inode number if found, or 0 if the entry doesn't exist.
// Used to check for existing files before creation or overwriting.
func (b *builder) findEntry(dirInode uint32, name string) (uint32, error) {
	inode, err := b.readLiveDirInode(dirInode)
	if err != nil {
		return 0, fmt.Errorf("failed to read directory inode for entry search: %w", err)
	}

	dataBlocks, err := b.getInodeBlocks(inode)
	if err != nil {
		return 0, fmt.Errorf("failed to get directory blocks for entry search: %w", err)
	}

	for _, blockNum := range dataBlocks {
		block := make([]byte, blockSize)
		if err := b.disk.readAt(block, int64(b.layout.BlockOffset(blockNum))); err != nil {
			return 0, fmt.Errorf("failed to read directory block %d: %w", blockNum, err)
		}

		offset := 0
		for offset < blockSize {
			entryInode, recLen, _, entryName, ok := parseDirentAt(block, offset)
			if !ok {
				break
			}

			if entryName == name {
				return entryInode, nil
			}

			offset += recLen
		}
	}

	return 0, nil
}

// listDirEntries returns all directory entries in the specified directory.
// Skips entries with inode=0 (deleted entries) and "." / ".." entries.
// Returns a slice of dirEntry containing name, inode, and type for each entry.
func (b *builder) listDirEntries(dirInode uint32) ([]dirEntry, error) {
	inode, err := b.readInode(dirInode)
	if err != nil {
		return nil, fmt.Errorf("failed to read directory inode: %w", err)
	}

	dataBlocks, err := b.getInodeBlocks(inode)
	if err != nil {
		return nil, fmt.Errorf("failed to get directory blocks: %w", err)
	}

	var entries []dirEntry

	for _, blockNum := range dataBlocks {
		block := make([]byte, blockSize)
		if err := b.disk.readAt(block, int64(b.layout.BlockOffset(blockNum))); err != nil {
			return nil, fmt.Errorf("failed to read directory block %d: %w", blockNum, err)
		}

		offset := 0
		for offset < blockSize {
			entryInode, recLen, _, entryName, ok := parseDirentAt(block, offset)
			if !ok {
				break
			}

			if entryInode != 0 {
				entryType := block[offset+7]

				// Skip "." and ".."
				if entryName != "." && entryName != ".." {
					entries = append(entries, dirEntry{
						Inode: entryInode,
						Type:  entryType,
						Name:  []byte(entryName),
					})
				}
			}

			offset += recLen
		}
	}

	return entries, nil
}
