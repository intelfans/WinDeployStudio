package ext4fs_test

import (
	"fmt"
	"testing"

	"github.com/pilat/go-ext4fs"
)

// BenchmarkFilesystemCreation measures end-to-end image creation
func BenchmarkFilesystemCreation(b *testing.B) {
	for i := 0; i < b.N; i++ {
		builder, err := ext4fs.New(ext4fs.WithMemoryBackend(), ext4fs.WithSizeInMB(64))
		if err != nil {
			b.Fatal(err)
		}

		for j := 0; j < 10; j++ {
			dir, _ := builder.CreateDirectory(ext4fs.RootInode, fmt.Sprintf("dir%d", j), 0755, 0, 0)
			for k := 0; k < 5; k++ {
				_, err := builder.CreateFile(dir, fmt.Sprintf("file%d.txt", k), []byte("content"), 0644, 0, 0)
				if err != nil {
					b.Fatal(err)
				}
			}
		}

		_ = builder.Save()
		_ = builder.Close()
	}
}

// BenchmarkFileCreation measures file creation (fresh image per iteration)
func BenchmarkFileCreation(b *testing.B) {
	sizes := []struct {
		name string
		size int
	}{
		{"Empty", 0},
		{"1KB", 1024},
		{"4KB", 4096},
		{"16KB", 16 * 1024},
	}

	const filesPerImage = 100

	for _, sz := range sizes {
		b.Run(sz.name, func(b *testing.B) {
			content := make([]byte, sz.size)

			b.ResetTimer()
			for i := 0; i < b.N; i++ {
				builder, _ := ext4fs.New(ext4fs.WithMemoryBackend(), ext4fs.WithSizeInMB(64))
				for j := 0; j < filesPerImage; j++ {
					_, err := builder.CreateFile(ext4fs.RootInode, fmt.Sprintf("file%d.bin", j), content, 0644, 0, 0)
					if err != nil {
						b.Fatal(err)
					}
				}
				_ = builder.Save()
				_ = builder.Close()
			}
			// Report per-file cost
			b.ReportMetric(float64(b.Elapsed().Nanoseconds())/float64(b.N*filesPerImage), "ns/file")
		})
	}
}

// BenchmarkDirectoryCreation measures directory creation (fresh image per iteration)
func BenchmarkDirectoryCreation(b *testing.B) {
	const dirsPerImage = 100

	for i := 0; i < b.N; i++ {
		builder, _ := ext4fs.New(ext4fs.WithMemoryBackend(), ext4fs.WithSizeInMB(64))
		for j := 0; j < dirsPerImage; j++ {
			_, err := builder.CreateDirectory(ext4fs.RootInode, fmt.Sprintf("dir%d", j), 0755, 0, 0)
			if err != nil {
				b.Fatal(err)
			}
		}
		_ = builder.Save()
		_ = builder.Close()
	}
	b.ReportMetric(float64(b.Elapsed().Nanoseconds())/float64(b.N*dirsPerImage), "ns/dir")
}

// BenchmarkNestedDirectories measures deeply nested directory creation
func BenchmarkNestedDirectories(b *testing.B) {
	depths := []int{5, 10, 20}
	const chainsPerImage = 50

	for _, depth := range depths {
		b.Run(fmt.Sprintf("Depth%d", depth), func(b *testing.B) {
			for i := 0; i < b.N; i++ {
				builder, _ := ext4fs.New(ext4fs.WithMemoryBackend(), ext4fs.WithSizeInMB(64))
				for c := 0; c < chainsPerImage; c++ {
					parent := uint32(ext4fs.RootInode)
					for d := 0; d < depth; d++ {
						dir, err := builder.CreateDirectory(parent, fmt.Sprintf("l%d_c%d", d, c), 0755, 0, 0)
						if err != nil {
							b.Fatal(err)
						}
						parent = dir
					}
				}
				_ = builder.Save()
				_ = builder.Close()
			}
			b.ReportMetric(float64(b.Elapsed().Nanoseconds())/float64(b.N*chainsPerImage), "ns/chain")
		})
	}
}

// BenchmarkSymlink measures symlink creation
func BenchmarkSymlink(b *testing.B) {
	scenarios := []struct {
		name   string
		target string
	}{
		{"FastSymlink", "short.txt"},
		{"SlowSymlink", "/very/long/path/that/exceeds/sixty/bytes/and/requires/block/allocation.txt"},
	}

	const linksPerImage = 100

	for _, sc := range scenarios {
		b.Run(sc.name, func(b *testing.B) {
			for i := 0; i < b.N; i++ {
				builder, _ := ext4fs.New(ext4fs.WithMemoryBackend(), ext4fs.WithSizeInMB(64))
				for j := 0; j < linksPerImage; j++ {
					_, err := builder.CreateSymlink(ext4fs.RootInode, fmt.Sprintf("link%d", j), sc.target, 0, 0)
					if err != nil {
						b.Fatal(err)
					}
				}
				_ = builder.Save()
				_ = builder.Close()
			}
			b.ReportMetric(float64(b.Elapsed().Nanoseconds())/float64(b.N*linksPerImage), "ns/link")
		})
	}
}

// BenchmarkXattr measures extended attribute operations
func BenchmarkXattr(b *testing.B) {
	sizes := []struct {
		name string
		size int
	}{
		{"16B", 16},
		{"256B", 256},
		{"1KB", 1024},
	}

	for _, sz := range sizes {
		b.Run(sz.name, func(b *testing.B) {
			value := make([]byte, sz.size)

			builder, err := ext4fs.New(ext4fs.WithMemoryBackend(), ext4fs.WithSizeInMB(64))
			if err != nil {
				b.Fatal(err)
			}
			defer func() {
				_ = builder.Save()
				_ = builder.Close()
			}()

			inode, err := builder.CreateFile(ext4fs.RootInode, "testfile", []byte("x"), 0644, 0, 0)
			if err != nil {
				b.Fatal(err)
			}

			b.ResetTimer()
			for i := 0; i < b.N; i++ {
				err = builder.SetXattr(inode, "user.bench", value)
				if err != nil {
					b.Fatal(err)
				}
			}
			b.ReportMetric(float64(b.Elapsed().Nanoseconds())/float64(b.N), "ns/xattr")
		})
	}
}

// BenchmarkManyFilesInDirectory measures directory scaling
func BenchmarkManyFilesInDirectory(b *testing.B) {
	counts := []int{100, 500, 1000}

	for _, count := range counts {
		b.Run(fmt.Sprintf("%dFiles", count), func(b *testing.B) {
			for i := 0; i < b.N; i++ {
				builder, _ := ext4fs.New(ext4fs.WithMemoryBackend(), ext4fs.WithSizeInMB(128))
				dir, err := builder.CreateDirectory(ext4fs.RootInode, "testdir", 0755, 0, 0)
				if err != nil {
					b.Fatal(err)
				}

				for j := 0; j < count; j++ {
					_, err := builder.CreateFile(dir, fmt.Sprintf("file%04d.txt", j), []byte("x"), 0644, 0, 0)
					if err != nil {
						b.Fatal(err)
					}
				}

				_ = builder.Save()
				_ = builder.Close()
			}
			b.ReportMetric(float64(b.Elapsed().Nanoseconds())/float64(b.N*count), "ns/file")
		})
	}
}

// BenchmarkImageInit measures just image initialization
func BenchmarkImageInit(b *testing.B) {
	sizes := []int{16, 64, 256}

	for _, sizeMB := range sizes {
		b.Run(fmt.Sprintf("%dMB", sizeMB), func(b *testing.B) {
			for i := 0; i < b.N; i++ {
				builder, err := ext4fs.New(ext4fs.WithMemoryBackend(), ext4fs.WithSizeInMB(sizeMB))
				if err != nil {
					b.Fatal(err)
				}
				_ = builder.Save()
				_ = builder.Close()
			}
		})
	}
}
