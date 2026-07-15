package ext4fs

import "fmt"

// memoryBackend implements diskBackend using an in-memory byte slice.
// Used for testing and benchmarks to avoid file I/O overhead.
type memoryBackend struct {
	data []byte
}

var _ diskBackend = (*memoryBackend)(nil)

// truncate resizes the in-memory buffer to size, preserving existing data like
// os.File.Truncate: growing zero-fills the new tail, shrinking keeps the prefix.
// In New the old buffer is nil, so the copy is a no-op and the result is a fresh
// zeroed slice; Resize relies on the preserve semantics.
func (m *memoryBackend) truncate(size int64) error {
	newData := make([]byte, size)
	copy(newData, m.data)
	m.data = newData
	return nil
}

func (m *memoryBackend) readAt(p []byte, off int64) error {
	if off < 0 || off+int64(len(p)) > int64(len(m.data)) {
		return fmt.Errorf("disk read error: offset %d out of range (size %d)", off, len(m.data))
	}
	copy(p, m.data[off:])
	return nil
}

func (m *memoryBackend) writeAt(p []byte, off int64) error {
	if off < 0 || off+int64(len(p)) > int64(len(m.data)) {
		return fmt.Errorf("disk write error: offset %d out of range (size %d)", off, len(m.data))
	}
	copy(m.data[off:], p)
	return nil
}

func (m *memoryBackend) sync() error {
	return nil
}

func (m *memoryBackend) close() error {
	return nil
}
