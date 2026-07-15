package ext4fs

import (
	"encoding/binary"
	"fmt"
	"strings"
)

// parseXattrName parses an extended attribute name into its namespace index and short name.
// Extended attribute names use prefixes like "user.", "trusted.", etc.
// Returns the namespace index, the name without prefix, and any parsing error.
func parseXattrName(name string) (uint8, string, error) {
	prefixes := []struct {
		prefix string
		index  uint8
	}{
		{"user.", xAttrIndexUser},
		{"security.", xAttrIndexSecurity},
		{"trusted.", xAttrIndexTrusted},
		{"system.posix_acl_access", xAttrIndexPosixACLAccess},
		{"system.posix_acl_default", xAttrIndexPosixACLDefault},
		{"system.", xAttrIndexSystem},
	}

	for _, p := range prefixes {
		if strings.HasPrefix(name, p.prefix) {
			shortName := strings.TrimPrefix(name, p.prefix)
			// Special case for POSIX ACLs - name is empty
			if p.index == xAttrIndexPosixACLAccess || p.index == xAttrIndexPosixACLDefault {
				shortName = ""
			}

			return p.index, shortName, nil
		}
	}

	return 0, "", fmt.Errorf("unknown xattr namespace in: %s", name)
}

// xattrIndexToPrefix converts an extended attribute namespace index to its string prefix.
// Used when listing or displaying extended attribute names to users.
// Returns the full prefix including the dot (e.g., "user.", "trusted.").
func xattrIndexToPrefix(index uint8) string {
	switch index {
	case xAttrIndexUser:
		return "user."
	case xAttrIndexSecurity:
		return "security."
	case xAttrIndexTrusted:
		return "trusted."
	case xAttrIndexPosixACLAccess:
		return "system.posix_acl_access"
	case xAttrIndexPosixACLDefault:
		return "system.posix_acl_default"
	case xAttrIndexSystem:
		return "system."
	default:
		return fmt.Sprintf("unknown(%d).", index)
	}
}

// freeOldFileResources frees the blocks and xattr associated with an existing inode.
func (b *builder) freeOldFileResources(oldInode *inode) error {
	// Free the xattr block if present
	if oldInode.FileACLLo != 0 {
		if err := b.freeBlockRun(oldInode.FileACLLo, 1); err != nil {
			return fmt.Errorf("failed to free xattr block during overwrite: %w", err)
		}
	}

	// Free extent runs directly (not individual blocks)
	if (oldInode.Flags & inodeFlagExtents) != 0 {
		if err := b.freeInodeExtentRuns(oldInode); err != nil {
			return fmt.Errorf("failed to free extent runs: %w", err)
		}
	}

	return nil
}

// freeInodeExtentRuns frees all extent runs from an inode, preserving contiguity.
func (b *builder) freeInodeExtentRuns(inode *inode) error {
	entries := binary.LittleEndian.Uint16(inode.Block[2:4])
	depth := binary.LittleEndian.Uint16(inode.Block[6:8])

	if entries == 0 {
		return nil
	}

	if depth == 0 {
		// Leaf extents in inode
		for i := uint16(0); i < entries && i < 4; i++ {
			off := 12 + i*12
			length := binary.LittleEndian.Uint16(inode.Block[off+4:])
			startLo := binary.LittleEndian.Uint32(inode.Block[off+8:])

			if err := b.freeBlockRun(startLo, uint32(length)); err != nil {
				return err
			}
		}
	} else {
		// Extent tree: free leaf block extents, then the leaf blocks themselves
		for i := uint16(0); i < entries && i < 4; i++ {
			off := 12 + i*12
			leafBlock := binary.LittleEndian.Uint32(inode.Block[off+4:])

			leafData := make([]byte, blockSize)
			if err := b.disk.readAt(leafData, int64(b.layout.BlockOffset(leafBlock))); err != nil {
				return fmt.Errorf("failed to read extent leaf block %d: %w", leafBlock, err)
			}

			leafEntries := binary.LittleEndian.Uint16(leafData[2:4])
			for j := uint16(0); j < leafEntries; j++ {
				extOff := 12 + j*12
				length := binary.LittleEndian.Uint16(leafData[extOff+4:])
				startLo := binary.LittleEndian.Uint32(leafData[extOff+8:])

				if err := b.freeBlockRun(startLo, uint32(length)); err != nil {
					return err
				}
			}

			// Free the leaf block itself
			if err := b.freeBlockRun(leafBlock, 1); err != nil {
				return err
			}
		}
	}

	return nil
}

// overwriteFile replaces the content of an existing file with new content.
// Frees the old blocks and allocates new ones as needed for the new content size.
// Updates the inode metadata while preserving the inode number.
// Returns the inode number (same as input) on success.
func (b *builder) overwriteFile(inodeNum uint32, content []byte, mode, uid, gid uint16) (uint32, error) {
	// Read existing inode to get its blocks
	oldInode, err := b.readInode(inodeNum)
	if err != nil {
		return 0, fmt.Errorf("failed to read inode for overwrite: %w", err)
	}

	linksCount := oldInode.LinksCount

	if err := b.freeOldFileResources(oldInode); err != nil {
		return 0, err
	}

	inode := b.makeFileInode(mode, uid, gid, uint64(len(content)))
	inode.LinksCount = linksCount

	inode, _, err = b.allocateAndWriteFileContent(inode, content)
	if err != nil {
		return 0, err
	}

	if err := b.writeInode(inodeNum, &inode); err != nil {
		return 0, err
	}

	return inodeNum, nil
}

// writeXattrBlock writes extended attribute entries to a dedicated block.
// Extended attributes are stored in a special format with hash-based ordering
// for efficient lookup. The block is referenced from the inode's FileACLLo field.
func (b *builder) writeXattrBlock(blockNum uint32, entries []xAttrEntry) error {
	block := make([]byte, blockSize)

	entriesOffset := xAttrHeaderSize
	valuesEnd := blockSize

	// Sort entries for consistent ordering (by index, then name)
	sortedEntries := make([]xAttrEntry, len(entries))
	copy(sortedEntries, entries)

	for i := 0; i < len(sortedEntries)-1; i++ {
		for j := i + 1; j < len(sortedEntries); j++ {
			if sortedEntries[i].NameIndex > sortedEntries[j].NameIndex ||
				(sortedEntries[i].NameIndex == sortedEntries[j].NameIndex &&
					sortedEntries[i].Name > sortedEntries[j].Name) {
				sortedEntries[i], sortedEntries[j] = sortedEntries[j], sortedEntries[i]
			}
		}
	}

	// Collect entry hashes for block hash calculation
	entryHashes := make([]uint32, 0, len(sortedEntries))

	for _, entry := range sortedEntries {
		nameLen := len(entry.Name)

		entrySize := xAttrEntryHeaderSize + nameLen
		if entrySize%4 != 0 {
			entrySize += 4 - (entrySize % 4)
		}

		valueSize := len(entry.Value)

		valueSizeAligned := valueSize
		if valueSizeAligned%4 != 0 {
			valueSizeAligned += 4 - (valueSizeAligned % 4)
		}

		// Check space: entries grow up, values grow down
		if entriesOffset+entrySize > valuesEnd-valueSizeAligned {
			return fmt.Errorf("xattr block full: cannot fit %s", entry.Name)
		}

		// Write value at end of block (growing downward)
		valuesEnd -= valueSizeAligned
		copy(block[valuesEnd:], entry.Value)

		// Calculate entry hash
		entryHash := xattrEntryHash(entry.NameIndex, entry.Name, entry.Value)
		entryHashes = append(entryHashes, entryHash)

		// Write entry header
		block[entriesOffset] = uint8(nameLen)
		block[entriesOffset+1] = entry.NameIndex
		binary.LittleEndian.PutUint16(block[entriesOffset+2:], uint16(valuesEnd))
		binary.LittleEndian.PutUint32(block[entriesOffset+4:], 0) // value_inum (unused)
		binary.LittleEndian.PutUint32(block[entriesOffset+8:], uint32(valueSize))
		binary.LittleEndian.PutUint32(block[entriesOffset+12:], entryHash)

		// Write name
		copy(block[entriesOffset+xAttrEntryHeaderSize:], entry.Name)

		entriesOffset += entrySize
	}

	// Calculate block hash
	blockHash := xattrBlockHash(entryHashes)

	// Write header
	binary.LittleEndian.PutUint32(block[0:4], xAttrMagic)
	binary.LittleEndian.PutUint32(block[4:8], 1)           // refcount
	binary.LittleEndian.PutUint32(block[8:12], 1)          // blocks
	binary.LittleEndian.PutUint32(block[12:16], blockHash) // hash
	// checksum at 16:20, reserved at 20:32 - leave as zero

	if err := b.disk.writeAt(block, int64(b.layout.BlockOffset(blockNum))); err != nil {
		return fmt.Errorf("failed to write xattr block %d: %w", blockNum, err)
	}

	return nil
}

// readXattrBlock reads extended attribute entries from a dedicated block.
// Parses the special xattr block format to extract name-value pairs.
// Returns a slice of XattrEntry structures for further processing.
func (b *builder) readXattrBlock(blockNum uint32) ([]xAttrEntry, error) {
	block := make([]byte, blockSize)
	if err := b.disk.readAt(block, int64(b.layout.BlockOffset(blockNum))); err != nil {
		return nil, fmt.Errorf("failed to read xattr block %d: %w", blockNum, err)
	}

	magic := binary.LittleEndian.Uint32(block[0:4])
	if magic != xAttrMagic {
		return nil, nil
	}

	var entries []xAttrEntry

	offset := xAttrHeaderSize

	for offset+xAttrEntryHeaderSize <= blockSize {
		nameLen := int(block[offset])
		if nameLen == 0 {
			break
		}

		nameIndex := block[offset+1]
		valueOffs := binary.LittleEndian.Uint16(block[offset+2 : offset+4])
		valueSize := binary.LittleEndian.Uint32(block[offset+8 : offset+12])

		// entryHash at offset+12:offset+16 - we don't need it for reading

		if offset+xAttrEntryHeaderSize+nameLen > blockSize {
			break
		}

		name := string(block[offset+xAttrEntryHeaderSize : offset+xAttrEntryHeaderSize+nameLen])

		var value []byte
		if valueSize > 0 && int(valueOffs)+int(valueSize) <= blockSize {
			value = make([]byte, valueSize)
			copy(value, block[valueOffs:int(valueOffs)+int(valueSize)])
		}

		entries = append(entries, xAttrEntry{
			NameIndex: nameIndex,
			Name:      name,
			Value:     value,
		})

		// Entries are 4-byte aligned
		entrySize := xAttrEntryHeaderSize + nameLen
		if entrySize%4 != 0 {
			entrySize += 4 - (entrySize % 4)
		}

		offset += entrySize
	}

	return entries, nil
}

// xattrEntryHash calculates a hash for an extended attribute entry.
// The hash is used for ordering entries in the xattr block for efficient lookup.
// Combines the namespace index, name, and value into a single hash value.
func xattrEntryHash(nameIndex uint8, name string, value []byte) uint32 {
	// First compute name hash
	hash := uint32(0)
	for _, c := range []byte(name) {
		hash = (hash << xattrNameHashShift) ^ (hash >> (32 - xattrNameHashShift)) ^ uint32(c)
	}

	// Continue (not XOR!) with value hash
	if len(value) > 0 {
		paddedLen := (len(value) + xattrRound) >> xattrPadBits
		for i := 0; i < paddedLen; i++ {
			var word uint32

			offset := i * 4
			for j := 0; j < 4 && offset+j < len(value); j++ {
				word |= uint32(value[offset+j]) << (j * 8)
			}

			hash = (hash << xattrValueHashShift) ^ (hash >> (32 - xattrValueHashShift)) ^ word
		}
	}

	return hash
}

// xattrBlockHash calculates a verification hash for the entire xattr block.
// Used to detect corruption or tampering of extended attribute data.
// The hash is stored in the xattr block header for integrity checking.
func xattrBlockHash(entryHashes []uint32) uint32 {
	hash := uint32(0)

	for _, entryHash := range entryHashes {
		if entryHash == 0 {
			return 0
		}

		hash = (hash << xattrBlockHashShift) ^ (hash >> (32 - xattrBlockHashShift)) ^ entryHash
	}

	return hash
}
