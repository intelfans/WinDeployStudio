package ext4fs

import (
	"path/filepath"
	"testing"
)

// FuzzReopenAccounting drives an arbitrary create/delete sequence, then asserts
// the on-disk free counts match the bitmaps after Save and again after a reopen
// and re-save. This is exactly the property the old cursor-based accounting broke:
// anything freed below the allocation high-water mark vanished from the counts on
// reopen, producing an image e2fsck rejects. FuzzOps already drives ops and a
// reopen cycle but only checks that Save succeeds — a wrong count saves fine, so
// it never caught this.
func FuzzReopenAccounting(f *testing.F) {
	f.Add([]byte{})
	f.Add([]byte{1, 5, 9, 3})              // mkdir, mkdir, mkdir, rmdir-middle
	f.Add([]byte{0, 4, 8, 2})              // file, file, file, delete
	f.Add([]byte{1, 0, 4, 9, 8, 2, 13, 3}) // mixed dirs and files with deletes

	f.Fuzz(func(t *testing.T, data []byte) {
		path := filepath.Join(t.TempDir(), "fuzz.img")

		img, err := New(WithImagePath(path), WithSizeInMB(8))
		if err != nil {
			t.Fatalf("New: %v", err)
		}
		applyAccountingOps(img, data)
		if err := img.Save(); err != nil {
			t.Fatalf("Save after ops: %v", err)
		}
		assertGroupFreeCountsMatchBitmaps(t, img.builder)
		if err := img.Close(); err != nil {
			t.Fatalf("Close: %v", err)
		}

		img2, err := Open(WithExistingImagePath(path))
		if err != nil {
			t.Fatalf("reopen of just-saved image: %v", err)
		}
		if err := img2.Save(); err != nil {
			t.Fatalf("Save after reopen: %v", err)
		}
		assertGroupFreeCountsMatchBitmaps(t, img2.builder)
		if err := img2.Close(); err != nil {
			t.Fatalf("Close after reopen: %v", err)
		}
	})
}

// applyAccountingOps interprets each byte as one allocation-affecting op: the low
// two bits pick the operation, higher bits pick the target name and parent. Op
// errors are ignored — the goal is to perturb allocation state, not to succeed.
func applyAccountingOps(img *Image, data []byte) {
	names := [6]string{"a", "b", "c", "d", "e", "f"}
	dirs := []uint32{RootInode}

	for _, op := range data {
		parent := dirs[int(op>>5)%len(dirs)]
		name := names[int(op>>2)%len(names)]

		switch op % 4 {
		case 0:
			_, _ = img.CreateFile(parent, name, []byte("xxxx"), 0644, 0, 0)
		case 1:
			if ino, err := img.CreateDirectory(parent, name, 0755, 0, 0); err == nil {
				dirs = append(dirs, ino)
			}
		case 2:
			_ = img.Delete(parent, name)
		case 3:
			_ = img.DeleteDirectory(parent, name)
		}
	}
}

// FuzzDirentScan feeds arbitrary bytes into a directory data block and runs the
// linear directory scanners over it. A corrupt rec_len/name_len must make them
// stop, not panic by slicing past the end of the block.
func FuzzDirentScan(f *testing.F) {
	f.Add([]byte{})
	f.Add([]byte{2, 0, 0, 0, 12, 0, 1, 2, 'a', 0, 0, 0})
	f.Add([]byte{0, 0, 0, 0, 0xFA, 0x0F, 0xFF, 0, 0, 0, 0, 0}) // rec_len 4090, then junk

	f.Fuzz(func(t *testing.T, data []byte) {
		img, err := New(WithMemoryBackend(), WithSizeInMB(8))
		if err != nil {
			t.Skip()
		}
		d, err := img.CreateDirectory(RootInode, "d", 0755, 0, 0)
		if err != nil {
			t.Skip()
		}
		if err := img.Save(); err != nil {
			t.Skip()
		}

		b := img.builder
		dInode, err := b.readInode(d)
		if err != nil {
			t.Skip()
		}
		blocks, err := b.getInodeBlocks(dInode)
		if err != nil || len(blocks) == 0 {
			t.Skip()
		}

		block := make([]byte, blockSize)
		copy(block, data) // arbitrary bytes, zero-padded / truncated to one block
		if err := b.disk.writeAt(block, int64(b.layout.BlockOffset(blocks[0]))); err != nil {
			t.Skip()
		}

		// None of the scanners may panic on a corrupt directory block —
		// including the append path (tryAddEntryToBlock) reached via CreateFile.
		_, _ = b.findEntry(d, "x")
		_, _ = b.listDirEntries(d)
		_ = b.removeDirEntry(d, "x")
		_, _ = img.CreateFile(d, "new", []byte("z"), 0644, 0, 0)
	})
}
