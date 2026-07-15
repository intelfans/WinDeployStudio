package ext4fs

// diskBackend abstracts I/O operations for different storage backends.
// This interface allows the filesystem builder to work with various storage
// types (files, memory buffers, network storage) through a common API.
type diskBackend interface {
	truncate(size int64) error
	readAt(p []byte, off int64) (err error)
	writeAt(p []byte, off int64) error
	sync() error
	close() error
}
