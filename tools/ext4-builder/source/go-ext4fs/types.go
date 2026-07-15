// Package ext4fs provides a pure Go implementation for creating and manipulating ext4 filesystem images.
// It allows building ext4 filesystems programmatically without external dependencies,
// suitable for creating disk images for virtual machines, containers, or embedded systems.
//
// The main entry point is Image in image.go, constructed via New and configured with
// ImageOption helpers from opts.go. Image wraps an internal builder that handles the
// low-level ext4 on-disk layout and metadata updates.
//
// Example usage:
//
//	img, err := ext4fs.New(
//		ext4fs.WithImagePath("disk.img"),
//		ext4fs.WithSizeInMB(64),
//	)
//	if err != nil {
//		panic(err)
//	}
//
//	rootDir, err := img.CreateDirectory(ext4fs.RootInode, "etc", 0755, 0, 0)
//	if err != nil {
//		panic(err)
//	}
//
//	if _, err := img.CreateFile(rootDir, "hostname", []byte("myhost\n"), 0644, 0, 0); err != nil {
//		panic(err)
//	}
//
//	if err := img.Save(); err != nil {
//		panic(err)
//	}
package ext4fs

const (
	// Block geometry
	sectorSize     = 512
	blockSize      = 4096
	blockSizeLog   = 2 // block_size = 1024 << BlockSizeLog
	blocksPerGroup = 32768
	inodesPerGroup = 8192
	inodeSize      = 256

	// Superblock is always at byte offset 1024 from partition start
	superblockOffset = 1024

	// Magic numbers
	ext4Magic    = 0xEF53
	extentMagic  = 0xF30A
	mbrSignature = 0xAA55

	// Reserved inodes
	badBlocksInode   = 1
	RootInode        = 2
	userQuotaInode   = 3
	groupQuotaInode  = 4
	bootLoaderInode  = 5
	undelDirInode    = 6
	resizeInode      = 7
	journalInode     = 8
	excludeInode     = 9
	replicaInode     = 10
	firstNonResInode = 11 // First inode for user data

	// Directory entry file types
	ftUnknown = 0
	ftRegFile = 1
	ftDir     = 2
	ftChrDev  = 3
	ftBlkDev  = 4
	ftFifo    = 5
	ftSock    = 6
	ftSymlink = 7
	ftMax     = 8

	// Inode mode bits
	s_IXOTH  = 0o0001
	s_IWOTH  = 0o0002
	s_IROTH  = 0o0004
	s_IXGRP  = 0o0010
	s_IWGRP  = 0o0020
	s_IRGRP  = 0o0040
	s_IXUSR  = 0o0100
	s_IWUSR  = 0o0200
	s_IRUSR  = 0o0400
	s_ISVTX  = 0o1000
	s_ISGID  = 0o2000
	s_ISUID  = 0o4000
	s_IFIFO  = 0x1000
	s_IFCHR  = 0x2000
	s_IFDIR  = 0x4000
	s_IFBLK  = 0x6000
	s_IFREG  = 0x8000
	s_IFLNK  = 0xA000
	s_IFSOCK = 0xC000

	// Inode flags
	inodeFlagExtents = 0x00080000

	// Feature flags - MINIMAL SET for kernel compatibility
	// Compatible features (optional)
	compatExtAttr  = 0x0008
	compatDirIndex = 0x0020

	// Incompatible features (required)
	incompatFileType = 0x0002
	incompatExtents  = 0x0040

	// Incompatible features we don't support (for Open validation)
	incompatJournal = 0x0004  // has_journal
	incompatMetaBG  = 0x0010  // meta_bg
	incompat64bit   = 0x0080  // 64bit
	incompatFlexBG  = 0x0200  // flex_bg
	incompatEncrypt = 0x10000 // encrypt

	// Mask of incompatible features we support
	incompatSupported = incompatFileType | incompatExtents

	// Read-only compatible features
	roCompatSparseSuper = 0x0001
	roCompatLargeFile   = 0x0002
	roCompatExtraIsize  = 0x0040

	// Xattr magic
	xAttrMagic = 0xEA020000

	// Xattr name indexes (namespaces)
	xAttrIndexUser            = 1
	xAttrIndexPosixACLAccess  = 2
	xAttrIndexPosixACLDefault = 3
	xAttrIndexTrusted         = 4
	xAttrIndexSecurity        = 6
	xAttrIndexSystem          = 7

	// Xattr block layout
	xAttrHeaderSize      = 32
	xAttrEntryHeaderSize = 16

	// Xattr hashing parameters (must match kernel algorithms)
	xattrNameHashShift  = 5
	xattrValueHashShift = 16
	xattrRound          = 3
	xattrPadBits        = 2
	xattrBlockHashShift = 16
)

// ============================================================================
// On-disk structures (must match kernel exactly)
// ============================================================================

// superblock represents the ext4 superblock structure (1024 bytes total)
// as defined in the Linux kernel's struct ext4_super_block. The superblock
// contains global filesystem metadata including block counts, inode counts,
// supported features, and maintenance information. It is located at offset
// 1024 bytes from the start of the filesystem. Only fields needed for minimal
// ext4 compatibility are included with correct byte offsets.
type superblock struct {
	InodesCount       uint32     // 0x00
	BlocksCountLo     uint32     // 0x04
	RBlocksCountLo    uint32     // 0x08
	FreeBlocksCountLo uint32     // 0x0C
	FreeInodesCount   uint32     // 0x10
	FirstDataBlock    uint32     // 0x14: 0 for 4K blocks
	LogBlockSize      uint32     // 0x18: block_size = 1024 << log_block_size
	LogClusterSize    uint32     // 0x1C
	BlocksPerGroup    uint32     // 0x20
	ClustersPerGroup  uint32     // 0x24
	InodesPerGroup    uint32     // 0x28
	MTime             uint32     // 0x2C
	WTime             uint32     // 0x30
	MntCount          uint16     // 0x34
	MaxMntCount       uint16     // 0x36
	Magic             uint16     // 0x38: 0xEF53
	State             uint16     // 0x3A: 1 = clean
	Errors            uint16     // 0x3C: 1 = continue
	MinorRevLevel     uint16     // 0x3E
	LastCheck         uint32     // 0x40
	CheckInterval     uint32     // 0x44
	CreatorOS         uint32     // 0x48: 0 = Linux
	RevLevel          uint32     // 0x4C: 1 = dynamic
	DefResUID         uint16     // 0x50
	DefResGID         uint16     // 0x52
	FirstInode        uint32     // 0x54: 11
	InodeSize         uint16     // 0x58: 256
	BlockGroupNr      uint16     // 0x5A
	FeatureCompat     uint32     // 0x5C
	FeatureIncompat   uint32     // 0x60
	FeatureROCompat   uint32     // 0x64
	UUID              [16]byte   // 0x68
	VolumeName        [16]byte   // 0x78
	LastMounted       [64]byte   // 0x88
	AlgorithmUsageBmp uint32     // 0xC8
	PreallocBlocks    uint8      // 0xCC
	PreallocDirBlocks uint8      // 0xCD
	ReservedGDTBlocks uint16     // 0xCE
	JournalUUID       [16]byte   // 0xD0
	JournalInum       uint32     // 0xE0
	JournalDev        uint32     // 0xE4
	LastOrphan        uint32     // 0xE8
	HashSeed          [4]uint32  // 0xEC
	DefHashVersion    uint8      // 0xFC
	JnlBackupType     uint8      // 0xFD
	DescSize          uint16     // 0xFE: 32 for 32-bit mode
	DefaultMountOpts  uint32     // 0x100
	FirstMetaBg       uint32     // 0x104
	MkfsTime          uint32     // 0x108
	JnlBlocks         [17]uint32 // 0x10C
	BlocksCountHi     uint32     // 0x150
	RBlocksCountHi    uint32     // 0x154
	FreeBlocksCountHi uint32     // 0x158
	MinExtraIsize     uint16     // 0x15C
	WantExtraIsize    uint16     // 0x15E
	Flags             uint32     // 0x160
	RaidStride        uint16     // 0x164
	MmpInterval       uint16     // 0x166
	MmpBlock          uint64     // 0x168
	RaidStripeWidth   uint32     // 0x170
	LogGroupsPerFlex  uint8      // 0x174
	ChecksumType      uint8      // 0x175
	ReservedPad       uint16     // 0x176
	KBytesWritten     uint64     // 0x178
	SnapshotInum      uint32     // 0x180
	SnapshotID        uint32     // 0x184
	SnapshotRBlksCnt  uint64     // 0x188
	SnapshotList      uint32     // 0x190
	ErrorCount        uint32     // 0x194
	FirstErrorTime    uint32     // 0x198
	FirstErrorIno     uint32     // 0x19C
	FirstErrorBlock   uint64     // 0x1A0
	FirstErrorFunc    [32]byte   // 0x1A8
	FirstErrorLine    uint32     // 0x1C8
	LastErrorTime     uint32     // 0x1CC
	LastErrorIno      uint32     // 0x1D0
	LastErrorLine     uint32     // 0x1D4
	LastErrorBlock    uint64     // 0x1D8
	LastErrorFunc     [32]byte   // 0x1E0
	MountOpts         [64]byte   // 0x200
	UsrQuotaInum      uint32     // 0x240
	GrpQuotaInum      uint32     // 0x244
	OverheadBlocks    uint32     // 0x248
	BackupBgs         [2]uint32  // 0x24C
	EncryptAlgos      [4]uint8   // 0x254
	EncryptPwSalt     [16]byte   // 0x258
	LpfIno            uint32     // 0x268
	PrjQuotaInum      uint32     // 0x26C
	ChecksumSeed      uint32     // 0x270
	WtimeHi           uint8      // 0x274
	MtimeHi           uint8      // 0x275
	MkfsTimeHi        uint8      // 0x276
	LastcheckHi       uint8      // 0x277
	FirstErrorTimeHi  uint8      // 0x278
	LastErrorTimeHi   uint8      // 0x279
	ErrorTimePad      [2]uint8   // 0x27A
	Encoding          uint16     // 0x27C
	EncodingFlags     uint16     // 0x27E
	OrphanFileInum    uint32     // 0x280
	Reserved          [94]uint32 // 0x284
	Checksum          uint32     // 0x3FC
}

// groupDesc32 represents the 32-byte block group descriptor structure
// used in non-64bit ext4 filesystems. Each block group has a descriptor
// that tracks the location of bitmaps, inode tables, and usage statistics
// for that specific block group. This enables parallel operations across
// multiple block groups.
type groupDesc32 struct {
	BlockBitmapLo     uint32 // Block bitmap block
	InodeBitmapLo     uint32 // Inode bitmap block
	InodeTableLo      uint32 // Inode table block
	FreeBlocksCountLo uint16 // Free blocks count
	FreeInodesCountLo uint16 // Free inodes count
	UsedDirsCountLo   uint16 // Directories count
	Flags             uint16 // Flags
	ExcludeBitmapLo   uint32 // Exclude bitmap
	BlockBitmapCsumLo uint16 // Block bitmap checksum
	InodeBitmapCsumLo uint16 // Inode bitmap checksum
	ItableUnusedLo    uint16 // Unused inodes count
	Checksum          uint16 // Group checksum
}

// inode represents the ext4 inode structure (256 bytes total)
// as defined in the Linux kernel's struct ext4_inode. Each inode
// contains metadata about a file or directory including ownership,
// permissions, timestamps, and block pointers or extent tree root.
// The inode number uniquely identifies each file system object.
type inode struct {
	Mode        uint16   // 0x00: File mode
	UID         uint16   // 0x02: Owner UID
	SizeLo      uint32   // 0x04: Size in bytes (low)
	Atime       uint32   // 0x08: Access time
	Ctime       uint32   // 0x0C: Change time
	Mtime       uint32   // 0x10: Modification time
	Dtime       uint32   // 0x14: Deletion time
	GID         uint16   // 0x18: Group ID
	LinksCount  uint16   // 0x1A: Links count
	BlocksLo    uint32   // 0x1C: Block count (512-byte units)
	Flags       uint32   // 0x20: Flags
	Version     uint32   // 0x24: Version (osd1)
	Block       [60]byte // 0x28: Block pointers / extent tree
	Generation  uint32   // 0x64: Generation
	FileACLLo   uint32   // 0x68: File ACL
	SizeHi      uint32   // 0x6C: Size high / dir ACL
	ObsoFAddr   uint32   // 0x70: Obsolete
	BlocksHi    uint16   // 0x74: Blocks count high
	FileACLHi   uint16   // 0x76: File ACL high
	UIDHi       uint16   // 0x78: UID high
	GIDHi       uint16   // 0x7A: GID high
	ChecksumLo  uint16   // 0x7C: Checksum low
	Reserved    uint16   // 0x7E: Reserved
	ExtraIsize  uint16   // 0x80: Extra inode size
	ChecksumHi  uint16   // 0x82: Checksum high
	CtimeExtra  uint32   // 0x84: Ctime extra
	MtimeExtra  uint32   // 0x88: Mtime extra
	AtimeExtra  uint32   // 0x8C: Atime extra
	Crtime      uint32   // 0x90: Creation time
	CrtimeExtra uint32   // 0x94: Creation time extra
	VersionHi   uint32   // 0x98: Version high
	Projid      uint32   // 0x9C: Project ID
	// Padding to 256 bytes
	Padding [96]byte // 0xA0-0xFF
}

// dirEntry represents an ext4 directory entry with file type information.
// Directory entries map filenames to inode numbers and contain metadata
// about the file type. The structure is variable-length to accommodate
// different filename lengths up to 255 bytes.
type dirEntry struct {
	Inode   uint32 // Inode number
	RecLen  uint16 // Record length
	NameLen uint8  // Name length
	Type    uint8  // File type
	Name    []byte // Name (up to 255)
}

// xAttrEntry represents an extended attribute (xattr) attached to an inode.
// Extended attributes provide additional metadata beyond standard file attributes,
// organized into namespaces like user, trusted, security, and system.
// Each xattr consists of a name index, name, and value.
type xAttrEntry struct {
	NameIndex uint8
	Name      string // Without namespace prefix
	Value     []byte
}
