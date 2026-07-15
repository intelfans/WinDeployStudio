package ext4fs_test

import (
	"bytes"
	"path/filepath"
	"testing"

	"github.com/pilat/go-ext4fs"
)

// FuzzOps drives the public API with an arbitrary operation sequence and
// verifies the properties no input may break: no panics, Save always
// succeeds, and the saved image survives Open plus another write cycle
// (bitmaps and directory structures reload cleanly). Individual operations
// are free to fail — invalid names, missing targets and exhausted space are
// expected — but no sequence may corrupt the builder state.
//
// The fuzzer cannot reach the extent-tree paths: the allocator never splits
// an allocation (PR #4), so multi-extent files require group-spanning sizes
// far beyond this 8 MB image. Those paths are covered by the extent unit
// tests and the ExtentTreeMultiGroup e2e test.
func FuzzOps(f *testing.F) {
	// One byte selects the op; following bytes parameterize it.
	f.Add([]byte{})
	f.Add([]byte{0, 0, 0, 16, 0})
	f.Add([]byte{1, 0, 1, 0, 1, 2, 0, 1})
	f.Add([]byte{4, 0, 2, 3, 5, 0, 3, 12, 6, 0, 4, 0})
	f.Add([]byte{7, 0, 0, 9, 'a', '/', 'b', 0, 0, 0, 255, 255})
	f.Add([]byte{0, 0, 0, 255, 255, 0, 0, 1, 255, 255, 2, 0, 0, 0, 0, 1, 255, 255})

	f.Fuzz(func(t *testing.T, data []byte) {
		path := filepath.Join(t.TempDir(), "fuzz.img")

		img, err := ext4fs.New(ext4fs.WithImagePath(path), ext4fs.WithSizeInMB(8))
		if err != nil {
			t.Fatalf("New: %v", err)
		}

		applyFuzzOps(img, data)

		if err := img.Save(); err != nil {
			t.Fatalf("Save after ops: %v", err)
		}
		if err := img.Close(); err != nil {
			t.Fatalf("Close: %v", err)
		}

		img2, err := ext4fs.Open(ext4fs.WithExistingImagePath(path))
		if err != nil {
			t.Fatalf("reopen of just-saved image: %v", err)
		}
		_, _ = img2.CreateFile(ext4fs.RootInode, "post-reopen", []byte("x"), 0644, 0, 0)
		if err := img2.Save(); err != nil {
			t.Fatalf("Save after reopen: %v", err)
		}
		if err := img2.Close(); err != nil {
			t.Fatalf("Close after reopen: %v", err)
		}
	})
}

// applyFuzzOps interprets data as an operation sequence: one byte selects the
// op, following bytes parameterize it. Operation errors are deliberately
// ignored — invalid inputs must be rejected gracefully, never corrupt state.
func applyFuzzOps(img *ext4fs.Image, data []byte) {
	names := [8]string{"n0", "n1", "n2", "n3", "n4", "n5", "n6", "n7"}
	dirs := []uint32{ext4fs.RootInode}
	var files []uint32

	for i := 0; i < len(data); {
		op := data[i]
		i++
		arg := func() byte { // next parameter byte, 0 when data is exhausted
			if i >= len(data) {
				return 0
			}
			b := data[i]
			i++
			return b
		}

		parent := dirs[int(arg())%len(dirs)]
		name := names[int(arg())%len(names)]

		switch op % 8 {
		case 0: // create a file of up to 64 KiB
			size := (int(arg())<<8 | int(arg())) % (64 << 10)
			if ino, err := img.CreateFile(parent, name, bytes.Repeat([]byte{op}, size), 0644, 0, 0); err == nil {
				files = append(files, ino)
			}
		case 1:
			if ino, err := img.CreateDirectory(parent, name, 0755, 0, 0); err == nil {
				dirs = append(dirs, ino)
			}
		case 2:
			_ = img.Delete(parent, name)
		case 3:
			_ = img.DeleteDirectory(parent, name)
		case 4:
			_, _ = img.CreateSymlink(parent, name, "/"+names[int(arg())%len(names)], 0, 0)
		case 5:
			_ = img.SetXattr(parent, "user."+name, bytes.Repeat([]byte{op}, int(arg())))
		case 6:
			if len(files) > 0 {
				_ = img.Link(parent, name, files[int(arg())%len(files)])
			}
		case 7: // create with a raw, possibly invalid name
			end := i + int(arg())%32 + 1
			if end > len(data) {
				end = len(data)
			}
			_, _ = img.CreateFile(parent, string(data[i:end]), []byte("x"), 0644, 0, 0)
			i = end
		}
	}
}
