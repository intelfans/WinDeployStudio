package ext4fs_test

import (
	"github.com/pilat/go-ext4fs"
)

// Building a small root filesystem image from scratch.
func Example() {
	img, err := ext4fs.New(
		ext4fs.WithImagePath("disk.img"),
		ext4fs.WithSizeInMB(64),
	)
	if err != nil {
		panic(err)
	}
	etc, err := img.CreateDirectory(ext4fs.RootInode, "etc", 0755, 0, 0)
	if err != nil {
		panic(err)
	}

	if _, err := img.CreateFile(etc, "hostname", []byte("myhost\n"), 0644, 0, 0); err != nil {
		panic(err)
	}
	if _, err := img.CreateSymlink(etc, "hosts", "/etc/hostname", 0, 0); err != nil {
		panic(err)
	}
	if err := img.SetXattr(etc, "user.comment", []byte("system configuration")); err != nil {
		panic(err)
	}

	if err := img.Save(); err != nil {
		panic(err)
	}
	if err := img.Close(); err != nil {
		panic(err)
	}
}

// Reopening an image created by this library and replacing a file.
func ExampleOpen() {
	img, err := ext4fs.Open(ext4fs.WithExistingImagePath("disk.img"))
	if err != nil {
		panic(err)
	}
	_ = img.Delete(ext4fs.RootInode, "init")
	if _, err := img.CreateFile(ext4fs.RootInode, "init", []byte("#!/bin/sh\nexec /bin/sh\n"), 0755, 0, 0); err != nil {
		panic(err)
	}

	if err := img.Save(); err != nil {
		panic(err)
	}
	if err := img.Close(); err != nil {
		panic(err)
	}
}

// Building on a roomy sparse canvas, then shrinking the image to its
// high-water mark. The result is typically a few MiB on disk.
func ExampleImage_Resize() {
	img, err := ext4fs.New(
		ext4fs.WithImagePath("fixture.img"),
		ext4fs.WithSizeInMB(16384), // 16 GiB canvas, sparse on disk
		ext4fs.WithLabel("fixtures"),
	)
	if err != nil {
		panic(err)
	}
	if _, err := img.CreateFile(ext4fs.RootInode, "data.bin", []byte("payload"), 0444, 0, 0); err != nil {
		panic(err)
	}

	if err := img.Resize(img.MinSize()); err != nil {
		panic(err)
	}
	if err := img.Save(); err != nil {
		panic(err)
	}
	if err := img.Close(); err != nil {
		panic(err)
	}
}

// Pinning the creation timestamp makes the output byte-for-byte reproducible:
// timestamps, the volume UUID and hash seeds all derive from it.
func ExampleWithCreatedAt() {
	img, err := ext4fs.New(
		ext4fs.WithImagePath("disk.img"),
		ext4fs.WithSizeInMB(64),
		ext4fs.WithCreatedAt(1700000000),
	)
	if err != nil {
		panic(err)
	}
	if err := img.Save(); err != nil {
		panic(err)
	}
	if err := img.Close(); err != nil {
		panic(err)
	}
}
