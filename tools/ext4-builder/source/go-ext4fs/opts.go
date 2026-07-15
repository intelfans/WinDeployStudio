package ext4fs

import (
	"fmt"
	"os"
)

// ImageOption is a functional option for configuring Image creation.
type ImageOption func(*Image) error

// WithImagePath sets the image path and creates/truncates the file.
// Use this option with New() to create a new image.
func WithImagePath(imagePath string) ImageOption {
	return func(i *Image) error {
		i.imagePath = imagePath

		// Create/truncate file
		f, err := os.OpenFile(imagePath, os.O_CREATE|os.O_RDWR|os.O_TRUNC, 0644)
		if err != nil {
			return fmt.Errorf("failed to open image file %s: %w", imagePath, err)
		}

		i.backend = &fileBackend{f: f}

		return nil
	}
}

// WithExistingImagePath opens an existing ext4 image file for reading and writing.
// Use this option with Open() to modify an existing image.
// The file must exist and contain a valid ext4 filesystem.
// Unlike WithImagePath, this option does not truncate the file.
func WithExistingImagePath(imagePath string) ImageOption {
	return func(i *Image) error {
		i.imagePath = imagePath

		// Open existing file for read/write without truncating
		f, err := os.OpenFile(imagePath, os.O_RDWR, 0644)
		if err != nil {
			return fmt.Errorf("failed to open existing image file %s: %w", imagePath, err)
		}

		// Get file size for sizeBytes
		stat, err := f.Stat()
		if err != nil {
			_ = f.Close()
			return fmt.Errorf("failed to stat image file %s: %w", imagePath, err)
		}

		i.sizeBytes = uint64(stat.Size())
		i.backend = &fileBackend{f: f}

		return nil
	}
}

// WithSizeInMB sets the image size in MB.
func WithSizeInMB(sizeMB int) ImageOption {
	return func(i *Image) error {
		i.sizeBytes = uint64(sizeMB) * 1024 * 1024
		return nil
	}
}

// WithSize sets image size in bytes.
func WithSize(sizeBytes uint64) ImageOption {
	return func(i *Image) error {
		i.sizeBytes = sizeBytes
		return nil
	}
}

// WithLabel sets the ext4 volume label written to the superblock.
// The label is what shows up at mount time. It must be at most 16 bytes
// (the on-disk VolumeName field); a longer label returns an error rather than
// being silently truncated, which would mount under an unexpected name.
// When unset, the label defaults to "ext4-go".
func WithLabel(label string) ImageOption {
	return func(i *Image) error {
		if len(label) > 16 {
			return fmt.Errorf("label too long: %d bytes, max 16", len(label))
		}

		i.label = label

		return nil
	}
}

// WithCreatedAt sets the creation timestamp.
func WithCreatedAt(createdAt uint32) ImageOption {
	return func(i *Image) error {
		i.createdAt = createdAt
		return nil
	}
}

// WithUUID sets a specific non-zero RFC 4122 UUID for a newly created image.
// When omitted, the upstream timestamp-derived UUID behavior is preserved for
// reproducible-image callers.
func WithUUID(uuid [16]byte) ImageOption {
	return func(i *Image) error {
		if uuid == ([16]byte{}) {
			return fmt.Errorf("UUID must not be all zero")
		}
		i.uuid = uuid
		i.hasUUID = true
		return nil
	}
}

// WithMemoryBackend creates an in-memory image of the given size in MB.
// Useful for testing and benchmarks to avoid disk I/O.
func WithMemoryBackend() ImageOption {
	return func(i *Image) error {
		i.backend = &memoryBackend{}
		return nil
	}
}
