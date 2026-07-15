package ext4fs

import (
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// Regression tests for input-validation holes found by FuzzOps. Operations
// against freed (stale) inode numbers used to write into unrelated blocks
// once the number was reused; reallocating a freed directory inode inside its
// own former subtree built a self-referencing directory and overflowed the
// stack in deleteDirectory (corpus entry d50efc265656c7ad).

func TestStaleInodeOpsRejected(t *testing.T) {
	img, err := New(WithMemoryBackend(), WithSizeInMB(8))
	require.NoError(t, err)

	stale, err := img.CreateDirectory(RootInode, "doomed", 0755, 0, 0)
	require.NoError(t, err)
	require.NoError(t, img.DeleteDirectory(RootInode, "doomed"))

	_, err = img.CreateDirectory(stale, "cycle", 0755, 0, 0)
	assert.ErrorContains(t, err, "not allocated")

	_, err = img.CreateFile(stale, "f", []byte("x"), 0644, 0, 0)
	assert.ErrorContains(t, err, "not allocated")

	_, err = img.CreateSymlink(stale, "s", "/tmp", 0, 0)
	assert.ErrorContains(t, err, "not allocated")

	assert.ErrorContains(t, img.SetXattr(stale, "user.a", []byte("v")), "not allocated")

	_, err = img.ListXattrs(stale)
	assert.ErrorContains(t, err, "not allocated")

	assert.ErrorContains(t, img.RemoveXattr(stale, "user.a"), "not allocated")
	assert.ErrorContains(t, img.Delete(stale, "x"), "not allocated")
	assert.ErrorContains(t, img.DeleteDirectory(stale, "x"), "not allocated")

	// Out-of-range inode numbers are equally dead.
	_, err = img.CreateFile(999999, "f", []byte("x"), 0644, 0, 0)
	assert.ErrorContains(t, err, "not allocated")

	// Hard link to a freed file inode must fail, not resurrect garbage.
	fileInode, err := img.CreateFile(RootInode, "f1", []byte("x"), 0644, 0, 0)
	require.NoError(t, err)
	require.NoError(t, img.Delete(RootInode, "f1"))
	assert.ErrorContains(t, img.Link(RootInode, "lnk", fileInode), "not allocated")

	// The image must remain fully usable after all rejections.
	_, err = img.CreateFile(RootInode, "ok", []byte("fine"), 0644, 0, 0)
	require.NoError(t, err)
	require.NoError(t, img.Save())
}

func TestParentMustBeDirectory(t *testing.T) {
	img, err := New(WithMemoryBackend(), WithSizeInMB(8))
	require.NoError(t, err)

	fileInode, err := img.CreateFile(RootInode, "plain", []byte("x"), 0644, 0, 0)
	require.NoError(t, err)

	_, err = img.CreateFile(fileInode, "child", []byte("x"), 0644, 0, 0)
	assert.ErrorContains(t, err, "not a directory")

	_, err = img.CreateDirectory(fileInode, "child", 0755, 0, 0)
	assert.ErrorContains(t, err, "not a directory")
}

func TestDuplicateNamesRejected(t *testing.T) {
	img, err := New(WithMemoryBackend(), WithSizeInMB(8))
	require.NoError(t, err)

	_, err = img.CreateDirectory(RootInode, "dir", 0755, 0, 0)
	require.NoError(t, err)
	_, err = img.CreateDirectory(RootInode, "dir", 0755, 0, 0)
	assert.ErrorContains(t, err, "already exists")

	_, err = img.CreateSymlink(RootInode, "lnk", "/tmp", 0, 0)
	require.NoError(t, err)
	_, err = img.CreateSymlink(RootInode, "lnk", "/tmp", 0, 0)
	assert.ErrorContains(t, err, "already exists")
}

func TestOverwriteOnlyRegularFiles(t *testing.T) {
	img, err := New(WithMemoryBackend(), WithSizeInMB(8))
	require.NoError(t, err)

	// File-over-file overwrite is the documented semantic and must work.
	first, err := img.CreateFile(RootInode, "file", []byte("one"), 0644, 0, 0)
	require.NoError(t, err)
	second, err := img.CreateFile(RootInode, "file", []byte("two"), 0644, 0, 0)
	require.NoError(t, err)
	assert.Equal(t, first, second, "overwrite must reuse the inode")

	// A directory or symlink under the same name must not be morphed into a file.
	_, err = img.CreateDirectory(RootInode, "dir", 0755, 0, 0)
	require.NoError(t, err)
	_, err = img.CreateFile(RootInode, "dir", []byte("x"), 0644, 0, 0)
	assert.ErrorContains(t, err, "not a regular file")

	_, err = img.CreateSymlink(RootInode, "lnk", "/tmp", 0, 0)
	require.NoError(t, err)
	_, err = img.CreateFile(RootInode, "lnk", []byte("x"), 0644, 0, 0)
	assert.ErrorContains(t, err, "not a regular file")
}
