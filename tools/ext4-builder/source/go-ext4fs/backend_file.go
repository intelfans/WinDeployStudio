package ext4fs

import (
	"fmt"
	"os"
)

// fileBackend implements diskBackend using a regular file on disk.
// Provides random access read/write operations for ext4 image files.
// Includes additional methods for synchronization and resource cleanup.
type fileBackend struct {
	f *os.File
}

var _ diskBackend = (*fileBackend)(nil)

func (fb *fileBackend) truncate(size int64) error {
	if fb.f.Name() == "" {
		return fmt.Errorf("imagePath is required")
	}

	if err := fb.f.Truncate(size); err != nil {
		return fmt.Errorf("failed to truncate image file: %w", err)
	}

	return nil
}

func (fb *fileBackend) readAt(p []byte, off int64) error {
	_, err := fb.f.ReadAt(p, off)
	if err != nil {
		return fmt.Errorf("disk read error: %w", err)
	}

	return nil
}

func (fb *fileBackend) writeAt(p []byte, off int64) error {
	_, err := fb.f.WriteAt(p, off)
	if err != nil {
		return fmt.Errorf("disk write error: %w", err)
	}

	return nil
}

func (fb *fileBackend) sync() error {
	if err := fb.f.Sync(); err != nil {
		return fmt.Errorf("disk sync error: %w", err)
	}

	return nil
}

func (fb *fileBackend) close() error {
	if err := fb.f.Close(); err != nil {
		return fmt.Errorf("disk close error: %w", err)
	}

	return nil
}
