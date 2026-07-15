package ext4fs_test

import (
	"bytes"
	"context"
	"crypto/sha256"
	"encoding/hex"
	"fmt"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"strconv"
	"strings"
	"testing"
	"time"

	"github.com/pilat/go-ext4fs"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// =============================================================================
// Constants
// =============================================================================

const (
	// Docker image to use for ext4 validation (pinned for reproducible CI)
	dockerImage = "alpine:3.21"
	// Default test image size in MB
	defaultImageSizeMB = 64

	stickyBit = 0o1000

	// Fixture settings for deterministic full-features image
	fixtureSizeMB     = 64
	fixturesCreatedAt = uint32(1600000000)
	expectedSHA256Hex = "391d60c1629a4062d7b922da1083b1b0db6bcc624fdf3310db785f2634044025"

	// Directory inside the Docker container where host images are mounted.
	sharedContainerDir = "/ext4-images"

	// ext4 geometry invariants, mirrored here for resize target math.
	testBlockSize      = 4096
	testBlocksPerGroup = 32768
)

// =============================================================================
// Package State
// =============================================================================

var (
	dockerContainerID string
	dockerAvailable   bool
	sharedHostDir     string
)

// =============================================================================
// Test Main
// =============================================================================

// TestMain sets up a single long-lived Docker container that is reused by all
// end-to-end tests. The container is stopped and removed once all tests
// complete. If Docker is not available, all tests in this package are
// effectively skipped.
func TestMain(m *testing.M) {
	// Do not run docker for benchmarks
	benchOnly := false
	for _, arg := range os.Args {
		if strings.Contains(arg, "-test.bench") {
			benchOnly = true
			break
		}
	}
	if benchOnly {
		code := m.Run()
		os.Exit(code)
	}

	if err := exec.Command("docker", "info").Run(); err != nil {
		// Unit tests, the fuzz target and its corpus still run; only the
		// kernel-backed e2e tests skip (via skipIfNoDocker).
		fmt.Fprintln(os.Stderr, "Docker not available, skipping e2e tests")
		os.Exit(m.Run())
	}

	dockerAvailable = true

	dir, err := os.MkdirTemp("", "ext4fs-e2e-")
	if err != nil {
		fmt.Fprintln(os.Stderr, "failed to create shared host dir for e2e tests:", err)
		os.Exit(1)
	}
	sharedHostDir = dir

	id, err := startDockerContainer()
	if err != nil {
		fmt.Fprintln(os.Stderr, "failed to start Docker container for e2e tests:", err)
		os.Exit(1)
	}
	dockerContainerID = strings.TrimSpace(id)

	code := m.Run()

	if dockerContainerID != "" {
		stopDockerContainer(dockerContainerID)
	}
	if sharedHostDir != "" {
		_ = os.RemoveAll(sharedHostDir)
	}

	os.Exit(code)
}

// =============================================================================
// End-to-End Tests
// =============================================================================

func TestExt4FS(t *testing.T) {
	skipIfNoDocker(t)

	tests := []struct {
		name string
		run  func(t *testing.T)
	}{
		{"BasicFilesystemCreation", testBasicFilesystemCreation},
		{"FileCreation", testFileCreation},
		{"FileOverwriting", testFileOverwriting},
		{"MultipleFileOverwrites", testMultipleFileOverwrites},
		{"OverwriteInSubdirectory", testOverwriteInSubdirectory},
		{"DirectoryCreation", testDirectoryCreation},
		{"SymlinkCreation", testSymlinkCreation},
		{"LongSymlink", testLongSymlink},
		{"ComplexFilesystem", testComplexFilesystem},
		{"LargeFile", testLargeFile},
		{"FilesystemIntegrity", testFilesystemIntegrity},
		{"DifferentImageSizes", testDifferentImageSizes},
		{"FilesystemStatistics", testFilesystemStatistics},
		{"SpecialFileNames", testSpecialFileNames},
		{"MultiBlockDirectory", testMultiBlockDirectory},
		{"MultiBlockDirectoryWithSymlinks", testMultiBlockDirectoryWithSymlinks},
		{"MultiBlockDirectoryNested", testMultiBlockDirectoryNested},
		{"ManySmallFiles", testManySmallFiles},
		{"DirectoryExtentTree", testDirectoryExtentTree},
		{"FreedBlockRunReuse", testFreedBlockRunReuse},
		{"LargeFileAfterFragmentation", testLargeFileAfterFragmentation},
		{"ExtentTreeMultiGroup", testExtentTreeMultiGroup},
		{"XattrBasic", testXattrBasic},
		{"XattrSELinux", testXattrSELinux},
		{"XattrMultiple", testXattrMultiple},
		{"XattrOnDirectory", testXattrOnDirectory},
		{"XattrOverwrite", testXattrOverwrite},
		{"XattrLargeValue", testXattrLargeValue},
		{"XattrWithFileOverwrite", testXattrWithFileOverwrite},
		{"XattrSymlink", testXattrSymlink},
		{"XattrCapabilities", testXattrCapabilities},
		{"XattrRemove", testXattrRemove},
		{"XattrList", testXattrList},
		{"XattrComplexFilesystem", testXattrComplexFilesystem},
		{"XattrManyFiles", testXattrManyFiles},
		{"XattrEmpty", testXattrEmpty},
		{"XattrPosixACL", testXattrPosixACL},
		{"DeleteFile", testDeleteFile},
		{"DeleteSymlink", testDeleteSymlink},
		{"DeleteEmptyDirectory", testDeleteEmptyDirectory},
		{"DeleteNonEmptyDirectoryFails", testDeleteNonEmptyDirectoryFails},
		{"DeleteDirectoryRecursive", testDeleteDirectoryRecursive},
		{"DeleteAndRecreate", testDeleteAndRecreate},
		{"DeleteFileWithXattr", testDeleteFileWithXattr},
		{"DeleteInSubdirectory", testDeleteInSubdirectory},
		{"DeleteMultipleFiles", testDeleteMultipleFiles},
		{"DeleteDirectoryDeep", testDeleteDirectoryDeep},
		{"DeleteLargeFile", testDeleteLargeFile},
		{"DeleteLargeDirectory", testDeleteLargeDirectory},
		{"DeleteSlowSymlink", testDeleteSlowSymlink},
		{"DeleteDirectoryWithXattr", testDeleteDirectoryWithXattr},
		{"DeleteNotFound", testDeleteNotFound},
		{"DeleteDotDotFails", testDeleteDotDotFails},
		{"DeleteFirstEntry", testDeleteFirstEntry},
		{"DeleteStressTest", testDeleteStressTest},
		{"InodeReuse", testInodeReuse},
		{"OpenAndModify", testOpenAndModify},
		{"OpenAndAddFile", testOpenAndAddFile},
		{"OpenAndDeleteFile", testOpenAndDeleteFile},
		{"OpenInvalidImage", testOpenInvalidImage},
		{"LargeFileAfterDeletes", testLargeFileAfterDeletes},
		{"HardlinkToDirectory", testHardlinkToDirectory},
		{"HardlinkExistingName", testHardlinkExistingName},
		{"HardlinkInvalidName", testHardlinkInvalidName},
		{"HardlinkNonExistentInode", testHardlinkNonExistentInode},
		{"HardlinkBasic", testHardlinkBasic},
		{"HardlinkDeleteOne", testHardlinkDeleteOne},
		{"HardlinkDeleteAll", testHardlinkDeleteAll},
		{"HardlinkToSymlink", testHardlinkToSymlink},
		{"HardlinkMultiple", testHardlinkMultiple},
		{"HardlinkOverwrite", testHardlinkOverwrite},
		{"HardlinkDeleteDirectoryExternal", testHardlinkDeleteDirectoryExternal},
		{"HardlinkDeleteDirectoryInternal", testHardlinkDeleteDirectoryInternal},
		{"VolumeLabel", testVolumeLabel},
		{"ResizeShrink", testResizeShrink},
		{"ResizeShrinkPartial", testResizeShrinkPartial},
		{"ResizeShrinkSparseBoundary", testResizeShrinkSparseBoundary},
		{"ResizeShrinkInodeBound", testResizeShrinkInodeBound},
		{"ResizeGrow", testResizeGrow},
		{"ResizeGrowMultiGroup", testResizeGrowMultiGroup},
		{"ResizeGrowAfterShrink", testResizeGrowAfterShrink},
		{"ResizeOpenGrow", testResizeOpenGrow},
		{"ResizeOpenShrink", testResizeOpenShrink},
	}

	for _, tc := range tests {
		t.Run(tc.name, tc.run)
	}
}

func testBasicFilesystemCreation(t *testing.T) {
	env := newTestEnv(t, defaultImageSizeMB)
	env.finalize()

	output := env.dockerExecSimple(
		`ls -la`,
		`test -d "lost+found" && echo "lost+found exists"`,
	)

	assert.Contains(t, output, "lost+found exists")
}

func testFileCreation(t *testing.T) {
	testCases := []struct {
		name     string
		filename string
		content  string
		mode     uint16
		uid      uint16
		gid      uint16
	}{
		{
			name:     "simple text file",
			filename: "hello.txt",
			content:  "Hello, World!\n",
			mode:     0644,
			uid:      0,
			gid:      0,
		},
		{
			name:     "empty file",
			filename: "empty.txt",
			content:  "",
			mode:     0644,
			uid:      0,
			gid:      0,
		},
		{
			name:     "file with custom permissions",
			filename: "secret.txt",
			content:  "secret data",
			mode:     0600,
			uid:      1000,
			gid:      1000,
		},
		{
			name:     "executable script",
			filename: "script.sh",
			content:  "#!/bin/sh\necho 'Hello'\n",
			mode:     0755,
			uid:      0,
			gid:      0,
		},
		{
			name:     "multiline file",
			filename: "multiline.txt",
			content:  "Line 1\nLine 2\nLine 3\nLine 4\nLine 5\n",
			mode:     0644,
			uid:      0,
			gid:      0,
		},
		{
			name:     "file with special characters",
			filename: "special.txt",
			content:  "Tab:\there\nUnicode: 你好世界\nSymbols: @#$%^&*()\n",
			mode:     0644,
			uid:      0,
			gid:      0,
		},
	}

	for _, tc := range testCases {
		t.Run(tc.name, func(t *testing.T) {
			env := newTestEnv(t, defaultImageSizeMB)

			_, err := env.builder.CreateFile(ext4fs.RootInode, tc.filename, []byte(tc.content), tc.mode, tc.uid, tc.gid)
			require.NoError(t, err)
			env.finalize()

			commands := []string{
				fmt.Sprintf(`test -f "%s" && echo "file exists"`, tc.filename),
			}
			if tc.content != "" {
				commands = append(commands, fmt.Sprintf(`cat "%s"`, tc.filename))
			}
			commands = append(commands,
				fmt.Sprintf(`stat -c "%%a" "%s"`, tc.filename),
				fmt.Sprintf(`stat -c "%%u:%%g" "%s"`, tc.filename),
			)

			output := env.dockerExecSimple(commands...)

			assert.Contains(t, output, "file exists")
			if tc.content != "" {
				assert.Contains(t, output, tc.content)
			}
			assert.Contains(t, output, fmt.Sprintf("%o", tc.mode))
			assert.Contains(t, output, fmt.Sprintf("%d:%d", tc.uid, tc.gid))
		})
	}
}

func testFileOverwriting(t *testing.T) {
	testCases := []struct {
		name            string
		originalContent string
		originalMode    uint16
		originalUID     uint16
		originalGID     uint16
		newContent      string
		newMode         uint16
		newUID          uint16
		newGID          uint16
	}{
		{
			name:            "overwrite with larger content",
			originalContent: "tiny",
			originalMode:    0644,
			originalUID:     0,
			originalGID:     0,
			newContent:      "This is a much longer content that should completely replace the original file data",
			newMode:         0644,
			newUID:          0,
			newGID:          0,
		},
		{
			name:            "overwrite with smaller content",
			originalContent: "This is a very long original content that will be replaced with something shorter",
			originalMode:    0644,
			originalUID:     0,
			originalGID:     0,
			newContent:      "short",
			newMode:         0644,
			newUID:          0,
			newGID:          0,
		},
		{
			name:            "overwrite with different permissions",
			originalContent: "test content",
			originalMode:    0644,
			originalUID:     0,
			originalGID:     0,
			newContent:      "test content",
			newMode:         0600,
			newUID:          0,
			newGID:          0,
		},
		{
			name:            "overwrite with different ownership",
			originalContent: "test content",
			originalMode:    0644,
			originalUID:     0,
			originalGID:     0,
			newContent:      "test content",
			newMode:         0644,
			newUID:          1000,
			newGID:          1000,
		},
		{
			name:            "overwrite everything",
			originalContent: "original",
			originalMode:    0644,
			originalUID:     0,
			originalGID:     0,
			newContent:      "completely new content with different everything",
			newMode:         0755,
			newUID:          500,
			newGID:          500,
		},
		{
			name:            "overwrite empty file",
			originalContent: "",
			originalMode:    0644,
			originalUID:     0,
			originalGID:     0,
			newContent:      "now has content",
			newMode:         0644,
			newUID:          0,
			newGID:          0,
		},
		{
			name:            "overwrite to empty file",
			originalContent: "has content",
			originalMode:    0644,
			originalUID:     0,
			originalGID:     0,
			newContent:      "",
			newMode:         0644,
			newUID:          0,
			newGID:          0,
		},
	}

	for _, tc := range testCases {
		t.Run(tc.name, func(t *testing.T) {
			env := newTestEnv(t, defaultImageSizeMB)

			filename := "testfile.txt"

			_, err := env.builder.CreateFile(ext4fs.RootInode, filename, []byte(tc.originalContent), tc.originalMode, tc.originalUID, tc.originalGID)
			require.NoError(t, err)
			_, err = env.builder.CreateFile(ext4fs.RootInode, filename, []byte(tc.newContent), tc.newMode, tc.newUID, tc.newGID)
			require.NoError(t, err)
			env.finalize()

			commands := []string{
				fmt.Sprintf(`test -f "%s" && echo "file exists"`, filename),
			}
			if tc.newContent != "" {
				commands = append(commands, fmt.Sprintf(`cat "%s"`, filename))
			} else {
				commands = append(commands, fmt.Sprintf(`[ $(stat -c %%s "%s") -eq 0 ] && echo "file is empty"`, filename))
			}
			commands = append(commands,
				fmt.Sprintf(`stat -c "%%a" "%s"`, filename),
				fmt.Sprintf(`stat -c "%%u:%%g" "%s"`, filename),
			)

			output := env.dockerExecSimple(commands...)

			assert.Contains(t, output, "file exists")
			if tc.newContent != "" {
				assert.Contains(t, output, tc.newContent)
				if tc.originalContent != tc.newContent && tc.originalContent != "" {
					assert.NotContains(t, output, tc.originalContent, "should not contain original content")
				}
			} else {
				assert.Contains(t, output, "file is empty")
			}
			assert.Contains(t, output, fmt.Sprintf("%o", tc.newMode))
			assert.Contains(t, output, fmt.Sprintf("%d:%d", tc.newUID, tc.newGID))
		})
	}
}

func testMultipleFileOverwrites(t *testing.T) {
	env := newTestEnv(t, defaultImageSizeMB)

	filename := "multi-overwrite.txt"

	contents := []string{
		"First version",
		"Second version - longer content",
		"Third",
		"Fourth version with even more content than before",
		"Final version",
	}
	modes := []uint16{0644, 0600, 0755, 0400, 0777}
	uids := []uint16{0, 1000, 500, 0, 1001}
	gids := []uint16{0, 1000, 500, 0, 1001}

	for i, content := range contents {
		_, err := env.builder.CreateFile(ext4fs.RootInode, filename, []byte(content), modes[i], uids[i], gids[i])
		require.NoError(t, err)
	}
	env.finalize()

	output := env.dockerExecSimple(
		fmt.Sprintf(`test -f "%s" && echo "file exists"`, filename),
		fmt.Sprintf(`cat "%s"`, filename),
		fmt.Sprintf(`stat -c "%%a" "%s"`, filename),
		fmt.Sprintf(`stat -c "%%u:%%g" "%s"`, filename),
	)

	assert.Contains(t, output, "file exists")
	assert.Contains(t, output, contents[len(contents)-1])
	for i := 0; i < len(contents)-1; i++ {
		assert.NotContains(t, output, contents[i])
	}
	assert.Contains(t, output, fmt.Sprintf("%o", modes[len(modes)-1]))
	assert.Contains(t, output, fmt.Sprintf("%d:%d", uids[len(uids)-1], gids[len(gids)-1]))
}

func testOverwriteInSubdirectory(t *testing.T) {
	env := newTestEnv(t, defaultImageSizeMB)

	subdir, err := env.builder.CreateDirectory(ext4fs.RootInode, "subdir", 0755, 0, 0)
	require.NoError(t, err)

	filename := "file.txt"

	_, err = env.builder.CreateFile(subdir, filename, []byte("original content"), 0644, 0, 0)
	require.NoError(t, err)
	_, err = env.builder.CreateFile(subdir, filename, []byte("new content"), 0600, 1000, 1000)
	require.NoError(t, err)
	env.finalize()

	output := env.dockerExecSimple(
		`test -f "subdir/file.txt" && echo "file exists"`,
		`cat "subdir/file.txt"`,
		`stat -c "%a" "subdir/file.txt"`,
		`stat -c "%u:%g" "subdir/file.txt"`,
	)

	assert.Contains(t, output, "file exists")
	assert.Contains(t, output, "new content")
	assert.NotContains(t, output, "original content")
	assert.Contains(t, output, "600")
	assert.Contains(t, output, "1000:1000")
}

func testDirectoryCreation(t *testing.T) {
	testCases := []struct {
		name      string
		structure func(t *testing.T, b *ext4fs.Image)
		verify    []string
		expects   []string
	}{
		{
			name: "single directory",
			structure: func(t *testing.T, b *ext4fs.Image) {
				_, err := b.CreateDirectory(ext4fs.RootInode, "mydir", 0755, 0, 0)
				require.NoError(t, err)
			},
			verify: []string{
				`test -d "mydir" && echo "mydir is directory"`,
				`stat -c "%a" "mydir"`,
			},
			expects: []string{"mydir is directory", "755"},
		},
		{
			name: "nested directories",
			structure: func(t *testing.T, b *ext4fs.Image) {
				dir1, err := b.CreateDirectory(ext4fs.RootInode, "level1", 0755, 0, 0)
				require.NoError(t, err)
				dir2, err := b.CreateDirectory(dir1, "level2", 0755, 0, 0)
				require.NoError(t, err)
				_, err = b.CreateDirectory(dir2, "level3", 0755, 0, 0)
				require.NoError(t, err)
			},
			verify: []string{
				`test -d "level1/level2/level3" && echo "nested dirs exist"`,
			},
			expects: []string{"nested dirs exist"},
		},
		{
			name: "directory with sticky bit",
			structure: func(t *testing.T, b *ext4fs.Image) {
				_, err := b.CreateDirectory(ext4fs.RootInode, "tmp", 0777|stickyBit, 0, 0)
				require.NoError(t, err)
			},
			verify: []string{
				`test -d "tmp" && echo "tmp exists"`,
				`stat -c "%a" "tmp"`,
			},
			expects: []string{"tmp exists", "1777"},
		},
		{
			name: "directory with custom ownership",
			structure: func(t *testing.T, b *ext4fs.Image) {
				_, err := b.CreateDirectory(ext4fs.RootInode, "userdir", 0750, 1000, 1000)
				require.NoError(t, err)
			},
			verify: []string{
				`stat -c "%u:%g" "userdir"`,
				`stat -c "%a" "userdir"`,
			},
			expects: []string{"1000:1000", "750"},
		},
		{
			name: "multiple directories at same level",
			structure: func(t *testing.T, b *ext4fs.Image) {
				_, err := b.CreateDirectory(ext4fs.RootInode, "bin", 0755, 0, 0)
				require.NoError(t, err)
				_, err = b.CreateDirectory(ext4fs.RootInode, "etc", 0755, 0, 0)
				require.NoError(t, err)
				_, err = b.CreateDirectory(ext4fs.RootInode, "home", 0755, 0, 0)
				require.NoError(t, err)
				_, err = b.CreateDirectory(ext4fs.RootInode, "var", 0755, 0, 0)
				require.NoError(t, err)
			},
			verify: []string{
				`ls -1d bin etc home var | wc -l | tr -d ' '`,
			},
			expects: []string{"4"},
		},
	}

	for _, tc := range testCases {
		t.Run(tc.name, func(t *testing.T) {
			env := newTestEnv(t, defaultImageSizeMB)
			tc.structure(t, env.builder)
			env.finalize()

			output := env.dockerExecSimple(tc.verify...)

			for _, expected := range tc.expects {
				assert.Contains(t, output, expected)
			}
		})
	}
}

func testSymlinkCreation(t *testing.T) {
	testCases := []struct {
		name    string
		setup   func(t *testing.T, b *ext4fs.Image)
		verify  []string
		expects []string
	}{
		{
			name: "simple symlink to file",
			setup: func(t *testing.T, b *ext4fs.Image) {
				_, err := b.CreateFile(ext4fs.RootInode, "original.txt", []byte("original content"), 0644, 0, 0)
				require.NoError(t, err)
				_, err = b.CreateSymlink(ext4fs.RootInode, "link.txt", "original.txt", 0, 0)
				require.NoError(t, err)
			},
			verify: []string{
				`test -L "link.txt" && echo "is symlink"`,
				`readlink "link.txt"`,
				`cat "link.txt"`,
			},
			expects: []string{"is symlink", "original.txt", "original content"},
		},
		{
			name: "symlink to directory",
			setup: func(t *testing.T, b *ext4fs.Image) {
				dir, err := b.CreateDirectory(ext4fs.RootInode, "realdir", 0755, 0, 0)
				require.NoError(t, err)
				_, err = b.CreateFile(dir, "file.txt", []byte("in dir"), 0644, 0, 0)
				require.NoError(t, err)
				_, err = b.CreateSymlink(ext4fs.RootInode, "linkdir", "realdir", 0, 0)
				require.NoError(t, err)
			},
			verify: []string{
				`test -L "linkdir" && echo "is symlink"`,
				`cat "linkdir/file.txt"`,
			},
			expects: []string{"is symlink", "in dir"},
		},
		{
			name: "relative symlink",
			setup: func(t *testing.T, b *ext4fs.Image) {
				dir, err := b.CreateDirectory(ext4fs.RootInode, "subdir", 0755, 0, 0)
				require.NoError(t, err)
				_, err = b.CreateFile(ext4fs.RootInode, "root.txt", []byte("root file"), 0644, 0, 0)
				require.NoError(t, err)
				_, err = b.CreateSymlink(dir, "toroot", "../root.txt", 0, 0)
				require.NoError(t, err)
			},
			verify: []string{
				`readlink "subdir/toroot"`,
				`cat "subdir/toroot"`,
			},
			expects: []string{"../root.txt", "root file"},
		},
	}

	for _, tc := range testCases {
		t.Run(tc.name, func(t *testing.T) {
			env := newTestEnv(t, defaultImageSizeMB)
			tc.setup(t, env.builder)
			env.finalize()

			output := env.dockerExecSimple(tc.verify...)

			for _, expected := range tc.expects {
				assert.Contains(t, output, expected)
			}
		})
	}
}

func testLongSymlink(t *testing.T) {
	env := newTestEnv(t, defaultImageSizeMB)

	// Create a deep directory structure to make a long path
	parent := uint32(ext4fs.RootInode)
	dirs := []string{"dir1", "dir2", "dir3", "dir4", "dir5", "dir6", "dir7"}
	for _, dir := range dirs {
		var err error
		parent, err = env.builder.CreateDirectory(parent, dir, 0755, 0, 0)
		require.NoError(t, err)
	}

	// Create a target file deep in the structure
	_, err := env.builder.CreateFile(parent, "target.txt", []byte("target content"), 0644, 0, 0)
	require.NoError(t, err)

	// Create symlink target path >60 bytes
	longTarget := "dir1/dir2/dir3/dir4/dir5/dir6/dir7/target.txt"
	_, err = env.builder.CreateSymlink(ext4fs.RootInode, "longlink", longTarget, 0, 0)
	require.NoError(t, err)

	env.finalize()

	output := env.dockerExecSimple(
		`test -L "longlink" && echo "is symlink"`,
		`readlink "longlink"`,
		`cat "longlink"`,
	)

	assert.Contains(t, output, "is symlink")
	assert.Contains(t, output, longTarget)
	assert.Contains(t, output, "target content")
}

func testComplexFilesystem(t *testing.T) {
	env := newTestEnv(t, defaultImageSizeMB)

	// Create /etc with config files
	etcDir, err := env.builder.CreateDirectory(ext4fs.RootInode, "etc", 0755, 0, 0)
	require.NoError(t, err)
	_, err = env.builder.CreateFile(etcDir, "passwd", []byte("root:x:0:0:root:/root:/bin/sh\n"), 0644, 0, 0)
	require.NoError(t, err)
	_, err = env.builder.CreateFile(etcDir, "hostname", []byte("testhost\n"), 0644, 0, 0)
	require.NoError(t, err)

	// Create /home/user
	homeDir, err := env.builder.CreateDirectory(ext4fs.RootInode, "home", 0755, 0, 0)
	require.NoError(t, err)
	userDir, err := env.builder.CreateDirectory(homeDir, "user", 0750, 1000, 1000)
	require.NoError(t, err)
	_, err = env.builder.CreateFile(userDir, ".bashrc", []byte("export PS1='$ '\n"), 0644, 1000, 1000)
	require.NoError(t, err)
	_, err = env.builder.CreateFile(userDir, ".profile", []byte("# profile\n"), 0644, 1000, 1000)
	require.NoError(t, err)

	// Create /var/log
	varDir, err := env.builder.CreateDirectory(ext4fs.RootInode, "var", 0755, 0, 0)
	require.NoError(t, err)
	logDir, err := env.builder.CreateDirectory(varDir, "log", 0755, 0, 0)
	require.NoError(t, err)
	_, err = env.builder.CreateFile(logDir, "messages", []byte("system started\n"), 0640, 0, 4)
	require.NoError(t, err)

	// Create /tmp with sticky bit
	_, err = env.builder.CreateDirectory(ext4fs.RootInode, "tmp", 0777|stickyBit, 0, 0)
	require.NoError(t, err)

	// Create symlink
	_, err = env.builder.CreateSymlink(userDir, "logs", "/var/log", 1000, 1000)
	require.NoError(t, err)

	env.finalize()

	output := env.dockerExecSimple(
		`find . -type d | sort`,
		`echo "---"`,
		`cat etc/passwd`,
		`cat etc/hostname`,
		`echo "---"`,
		`stat -c "%a %n" tmp`,
		`stat -c "%u:%g %n" home/user/.bashrc`,
		`echo "---"`,
		`readlink home/user/logs`,
	)

	// Verify structure
	assert.Contains(t, output, "./etc")
	assert.Contains(t, output, "./home")
	assert.Contains(t, output, "./home/user")
	assert.Contains(t, output, "./var")
	assert.Contains(t, output, "./var/log")
	assert.Contains(t, output, "./tmp")
	assert.Contains(t, output, "./lost+found")

	// Verify file contents
	assert.Contains(t, output, "root:x:0:0:root:/root:/bin/sh")
	assert.Contains(t, output, "testhost")

	// Verify permissions
	assert.Contains(t, output, "1777 tmp")
	assert.Contains(t, output, "1000:1000 home/user/.bashrc")

	// Verify symlink
	assert.Contains(t, output, "/var/log")
}

func testLargeFile(t *testing.T) {
	env := newTestEnv(t, defaultImageSizeMB)

	// Create a file larger than 4KB (one block) - use 16KB (4 blocks)
	largeContent := make([]byte, 16*1024)
	for i := range largeContent {
		largeContent[i] = byte(i % 256)
	}
	copy(largeContent[:16], []byte("HEADER_START____"))
	copy(largeContent[len(largeContent)-16:], []byte("____FOOTER_END__"))

	_, err := env.builder.CreateFile(ext4fs.RootInode, "largefile.bin", largeContent, 0644, 0, 0)
	require.NoError(t, err)
	env.finalize()

	output := env.dockerExecSimple(
		`stat -c "%s" largefile.bin`,
		`head -c 16 largefile.bin`,
		`tail -c 16 largefile.bin`,
	)

	assert.Contains(t, output, "16384")
	assert.Contains(t, output, "HEADER_START____")
	assert.Contains(t, output, "____FOOTER_END__")
}

func testFilesystemIntegrity(t *testing.T) {
	testCases := []struct {
		name  string
		setup func(t *testing.T, b *ext4fs.Image)
	}{
		{
			name:  "empty filesystem",
			setup: func(t *testing.T, b *ext4fs.Image) {},
		},
		{
			name: "filesystem with files",
			setup: func(t *testing.T, b *ext4fs.Image) {
				_, err := b.CreateFile(ext4fs.RootInode, "test.txt", []byte("test"), 0644, 0, 0)
				require.NoError(t, err)
			},
		},
		{
			name: "filesystem with directories",
			setup: func(t *testing.T, b *ext4fs.Image) {
				dir, err := b.CreateDirectory(ext4fs.RootInode, "subdir", 0755, 0, 0)
				require.NoError(t, err)
				_, err = b.CreateFile(dir, "nested.txt", []byte("nested"), 0644, 0, 0)
				require.NoError(t, err)
			},
		},
		{
			name: "complex filesystem",
			setup: func(t *testing.T, b *ext4fs.Image) {
				for i := 0; i < 5; i++ {
					dirName := fmt.Sprintf("dir%d", i)
					dir, err := b.CreateDirectory(ext4fs.RootInode, dirName, 0755, 0, 0)
					require.NoError(t, err)

					for j := 0; j < 3; j++ {
						fileName := fmt.Sprintf("file%d.txt", j)
						content := fmt.Sprintf("Content of %s/%s\n", dirName, fileName)
						_, err = b.CreateFile(dir, fileName, []byte(content), 0644, 0, 0)
						require.NoError(t, err)
					}
				}
			},
		},
	}

	for _, tc := range testCases {
		t.Run(tc.name, func(t *testing.T) {
			env := newTestEnv(t, defaultImageSizeMB)
			tc.setup(t, env.builder)
			env.finalize()

			// dockerExec already runs e2fsck -n -f which fails on issues
			_, stderr, err := env.dockerExec(`echo "Filesystem check passed"`)
			require.NoError(t, err, "e2fsck failed: %s", stderr)
		})
	}
}

func testDifferentImageSizes(t *testing.T) {
	sizes := []int{16, 32, 64, 128, 256, 512}

	for _, sizeMB := range sizes {
		t.Run(fmt.Sprintf("%dMB", sizeMB), func(t *testing.T) {
			env := newTestEnv(t, sizeMB)

			_, err := env.builder.CreateFile(ext4fs.RootInode, "test.txt", []byte("test content"), 0644, 0, 0)
			require.NoError(t, err)
			dir, err := env.builder.CreateDirectory(ext4fs.RootInode, "subdir", 0755, 0, 0)
			require.NoError(t, err)
			_, err = env.builder.CreateFile(dir, "nested.txt", []byte("nested content"), 0644, 0, 0)
			require.NoError(t, err)

			env.finalize()

			output := env.dockerExecSimple(
				`cat test.txt`,
				`cat subdir/nested.txt`,
			)

			assert.Contains(t, output, "test content")
			assert.Contains(t, output, "nested content")
		})
	}
}

func testFilesystemStatistics(t *testing.T) {
	env := newTestEnv(t, defaultImageSizeMB)

	_, err := env.builder.CreateFile(ext4fs.RootInode, "data.bin", make([]byte, 8192), 0644, 0, 0)
	require.NoError(t, err)
	env.finalize()

	output := env.dockerExecSimple(
		`df -h . | tail -1`,
		`echo "---"`,
		`stat -f -c "%T" .`,
	)

	assert.Contains(t, output, "ext")
}

func testSpecialFileNames(t *testing.T) {
	testCases := []struct {
		name     string
		filename string
	}{
		{"single char", "a"},
		{"max length minus safety", strings.Repeat("x", 200)},
		{"with spaces", "file with spaces.txt"},
		{"with dots", "file.multiple.dots.txt"},
		{"hidden file", ".hidden"},
		{"numbers only", "12345"},
		{"mixed case", "MixedCase.TXT"},
		{"underscore", "file_name_with_underscores"},
		{"hyphen", "file-name-with-hyphens"},
	}

	for _, tc := range testCases {
		t.Run(tc.name, func(t *testing.T) {
			env := newTestEnv(t, defaultImageSizeMB)

			content := fmt.Sprintf("Content of %s\n", tc.filename)
			_, err := env.builder.CreateFile(ext4fs.RootInode, tc.filename, []byte(content), 0644, 0, 0)
			require.NoError(t, err)
			env.finalize()

			output := env.dockerExecSimple(
				fmt.Sprintf(`cat "%s"`, tc.filename),
			)

			assert.Contains(t, output, content)
		})
	}
}

func testMultiBlockDirectory(t *testing.T) {
	env := newTestEnv(t, 128)

	testDir, err := env.builder.CreateDirectory(ext4fs.RootInode, "many_files", 0755, 0, 0)
	require.NoError(t, err)

	numFiles := 400
	for i := 0; i < numFiles; i++ {
		fileName := fmt.Sprintf("file_%03d.txt", i)
		content := fmt.Sprintf("This is file number %d\n", i)
		_, err = env.builder.CreateFile(testDir, fileName, []byte(content), 0644, 0, 0)
		require.NoError(t, err)
	}

	env.finalize()

	output := env.dockerExecSimple(
		`cd many_files`,
		`ls -1 | wc -l`,
		`test -f file_000.txt && echo "first file exists"`,
		`test -f file_199.txt && echo "middle file exists"`,
		`test -f file_399.txt && echo "last file exists"`,
		`cat file_000.txt`,
		`cat file_399.txt`,
	)

	assert.Contains(t, output, "400")
	assert.Contains(t, output, "first file exists")
	assert.Contains(t, output, "middle file exists")
	assert.Contains(t, output, "last file exists")
	assert.Contains(t, output, "This is file number 0")
	assert.Contains(t, output, "This is file number 399")
}

func testMultiBlockDirectoryWithSymlinks(t *testing.T) {
	env := newTestEnv(t, 128)

	testDir, err := env.builder.CreateDirectory(ext4fs.RootInode, "mixed_dir", 0755, 0, 0)
	require.NoError(t, err)

	// Add 100 regular files
	for i := 0; i < 100; i++ {
		fileName := fmt.Sprintf("regular_%03d.txt", i)
		_, err = env.builder.CreateFile(testDir, fileName, []byte("regular file"), 0644, 0, 0)
		require.NoError(t, err)
	}

	// Add 100 subdirectories
	for i := 0; i < 100; i++ {
		dirName := fmt.Sprintf("subdir_%03d", i)
		_, err = env.builder.CreateDirectory(testDir, dirName, 0755, 0, 0)
		require.NoError(t, err)
	}

	// Add 100 symlinks
	for i := 0; i < 100; i++ {
		linkName := fmt.Sprintf("link_%03d", i)
		target := fmt.Sprintf("regular_%03d.txt", i)
		_, err = env.builder.CreateSymlink(testDir, linkName, target, 0, 0)
		require.NoError(t, err)
	}

	env.finalize()

	output := env.dockerExecSimple(
		`cd mixed_dir`,
		`ls -1 | wc -l`,
		`ls -1 regular_* | wc -l`,
		`ls -1d subdir_* | wc -l`,
		`ls -1 link_* | wc -l`,
		`test -f regular_000.txt && echo "regular file exists"`,
		`test -d subdir_050 && echo "subdir exists"`,
		`test -L link_099 && echo "symlink exists"`,
		`readlink link_050`,
	)

	assert.Contains(t, output, "300")
	assert.Contains(t, output, "100")
	assert.Contains(t, output, "regular file exists")
	assert.Contains(t, output, "subdir exists")
	assert.Contains(t, output, "symlink exists")
	assert.Contains(t, output, "regular_050.txt")
}

func testMultiBlockDirectoryNested(t *testing.T) {
	env := newTestEnv(t, 128)

	level1, err := env.builder.CreateDirectory(ext4fs.RootInode, "level1", 0755, 0, 0)
	require.NoError(t, err)

	for i := 0; i < 200; i++ {
		fileName := fmt.Sprintf("l1_file_%03d.txt", i)
		_, err = env.builder.CreateFile(level1, fileName, []byte("level 1 content"), 0644, 0, 0)
		require.NoError(t, err)
	}

	level2, err := env.builder.CreateDirectory(level1, "level2", 0755, 0, 0)
	require.NoError(t, err)

	for i := 0; i < 200; i++ {
		fileName := fmt.Sprintf("l2_file_%03d.txt", i)
		_, err = env.builder.CreateFile(level2, fileName, []byte("level 2 content"), 0644, 0, 0)
		require.NoError(t, err)
	}

	env.finalize()

	output := env.dockerExecSimple(
		`cd level1`,
		`ls -1 l1_file_* | wc -l`,
		`test -d level2 && echo "level2 exists"`,
		`cd level2`,
		`ls -1 l2_file_* | wc -l`,
		`cat l2_file_000.txt`,
	)
	assert.Contains(t, output, "200")
	assert.Contains(t, output, "level2 exists")
	assert.Contains(t, output, "level 2 content")
}

// testManySmallFiles creates 500 small files in one directory and verifies
// they all survive a kernel mount. Despite its former name
// (testExtentTreeConversion), this never reached the extent-tree code: each
// file is a single contiguous extent. It guards directory growth and inode
// allocation at volume.
func testManySmallFiles(t *testing.T) {
	env := newTestEnv(t, 128)

	testDir, err := env.builder.CreateDirectory(ext4fs.RootInode, "extent_test", 0755, 0, 0)
	require.NoError(t, err)

	for i := 0; i < 500; i++ {
		fileName := fmt.Sprintf("file_%04d.txt", i)
		content := fmt.Sprintf("Content %d\n", i)
		_, err = env.builder.CreateFile(testDir, fileName, []byte(content), 0644, 0, 0)
		require.NoError(t, err)
	}

	env.finalize()

	output := env.dockerExecSimple(
		`cd extent_test`,
		`ls -1 | wc -l`,
		`test -f file_0000.txt && echo "first exists"`,
		`test -f file_0250.txt && echo "middle exists"`,
		`test -f file_0499.txt && echo "last exists"`,
		`cat file_0000.txt`,
		`cat file_0499.txt`,
	)

	assert.Contains(t, output, "500")
	assert.Contains(t, output, "first exists")
	assert.Contains(t, output, "middle exists")
	assert.Contains(t, output, "last exists")
	assert.Contains(t, output, "Content 0")
	assert.Contains(t, output, "Content 499")
}

// testFreedBlockRunReuse overwrites a multi-block file and creates an
// equally-sized one, which must reuse the freed run as a single contiguous
// extent (best-fit allocator, PR #4). Despite its former name
// (testExtentTreeLeafAllocation), no extent tree is built here — that is
// exactly the point of the #4 fix.
func testFreedBlockRunReuse(t *testing.T) {
	env := newTestEnv(t, 128)

	// Create a large file to allocate many contiguous blocks
	largeContent := make([]byte, 20*4096)
	for i := range largeContent {
		largeContent[i] = byte(i % 256)
	}
	_, err := env.builder.CreateFile(ext4fs.RootInode, "big1", largeContent, 0644, 0, 0)
	require.NoError(t, err)

	// Overwrite it with small content, freeing the blocks
	smallContent := []byte("small")
	_, err = env.builder.CreateFile(ext4fs.RootInode, "big1", smallContent, 0644, 0, 0)
	require.NoError(t, err)

	// The freed 20-block run must be reused for the next file of the same size
	_, err = env.builder.CreateFile(ext4fs.RootInode, "big2", largeContent, 0644, 0, 0)
	require.NoError(t, err)

	env.finalize()

	output := env.dockerExecSimple(
		`test -f "big1" && echo "big1 exists"`,
		`test -f "big2" && echo "big2 exists"`,
		`cat "big1"`,
		`stat -c "%s" "big2"`,
		`filefrag big2`,
	)

	assert.Contains(t, output, "big1 exists")
	assert.Contains(t, output, "big2 exists")
	assert.Contains(t, output, "small")
	assert.Contains(t, output, fmt.Sprintf("%d", 20*4096))
	assert.Equal(t, 1, filefragExtentCount(t, output), "big2 must reuse the freed run as one contiguous extent")
}

// testLargeFileAfterFragmentation heavily fragments the free space and then
// creates a large file. The allocator must NOT stitch the file together from
// the single-block holes (that was the bug fixed in PR #4 — thousands of
// extents); it must fall back to fresh contiguous blocks from the group tail.
// Despite its former name (testExtentTreeManyExtents), this never builds an
// extent tree — the allocator sidesteps fragmentation by design.
func testLargeFileAfterFragmentation(t *testing.T) {
	env := newTestEnv(t, 256) // Larger image to have enough space

	// Create 700 single-block files to allocate blocks
	for i := 0; i < 700; i++ {
		content := []byte(fmt.Sprintf("file %d content", i))
		_, err := env.builder.CreateFile(ext4fs.RootInode, fmt.Sprintf("frag_%04d.txt", i), content, 0644, 0, 0)
		require.NoError(t, err)
	}

	// Delete every other file, leaving 350 single-block holes
	for i := 0; i < 700; i += 2 {
		err := env.builder.Delete(ext4fs.RootInode, fmt.Sprintf("frag_%04d.txt", i))
		require.NoError(t, err)
	}

	// No freed run fits 350 blocks, so the allocator must take fresh
	// contiguous blocks past the high-water mark instead of the holes
	largeContent := make([]byte, 350*4096)
	for i := range largeContent {
		largeContent[i] = byte(i % 256)
	}
	_, err := env.builder.CreateFile(ext4fs.RootInode, "fragmented_large.bin", largeContent, 0644, 0, 0)
	require.NoError(t, err)

	env.finalize()

	output := env.dockerExecSimple(
		`test -f "fragmented_large.bin" && echo "file exists"`,
		`stat -c "%s" "fragmented_large.bin"`,
		`md5sum "fragmented_large.bin" | cut -d' ' -f1`,
		`filefrag fragmented_large.bin`,
	)

	assert.Contains(t, output, "file exists")
	assert.Contains(t, output, fmt.Sprintf("%d", 350*4096))
	// Verify data integrity - content is deterministic: byte(i % 256)
	assert.Contains(t, output, "927be24bf1e37fc370e57d3d25ee929b")
	assert.Equal(t, 1, filefragExtentCount(t, output), "allocator must take fresh contiguous tail blocks, not stitch the holes")
}

// testExtentTreeMultiGroup creates a file spanning five block groups. Fresh
// allocation is contiguous within a group but breaks at every group's
// metadata blocks, so the file collects >4 extents and the inode must be
// converted to a depth-1 extent tree (the inline inode area fits only 4).
// filefrag pins the actual extent count so this test cannot silently degrade
// into a single-extent file — the fate of the original "extent tree" e2e
// tests after the PR #4 allocator rework.
func testExtentTreeMultiGroup(t *testing.T) {
	env := newTestEnv(t, 640) // five 128 MiB block groups

	const fileSize = 520 << 20 // more than 4 groups of data, so >= 5 extents
	content := make([]byte, fileSize)
	for i := range content {
		content[i] = byte(i % 256)
	}
	_, err := env.builder.CreateFile(ext4fs.RootInode, "spanning.bin", content, 0644, 0, 0)
	require.NoError(t, err)

	sum := sha256.Sum256(content)

	env.finalize()

	output := env.dockerExecSimple(
		`stat -c "%s" spanning.bin`,
		`filefrag spanning.bin`,
		`sha256sum spanning.bin | cut -d' ' -f1`,
	)

	assert.Contains(t, output, fmt.Sprintf("%d", fileSize))
	assert.Contains(t, output, hex.EncodeToString(sum[:]))

	extents := filefragExtentCount(t, output)
	assert.GreaterOrEqual(t, extents, 5,
		"file must have >4 extents, otherwise the depth-1 extent tree path was not exercised")
}

// filefragExtentCount extracts N from filefrag's "N extents found" line.
func filefragExtentCount(t *testing.T, output string) int {
	t.Helper()

	for _, line := range strings.Split(output, "\n") {
		if !strings.Contains(line, "extent") || !strings.Contains(line, "found") {
			continue
		}
		fields := strings.Fields(line) // e.g. "spanning.bin: 5 extents found"
		for i, f := range fields {
			if strings.HasPrefix(f, "extent") && i > 0 {
				n, err := strconv.Atoi(fields[i-1])
				require.NoError(t, err, "unparseable filefrag line: %q", line)
				return n
			}
		}
	}
	t.Fatalf("no 'extents found' line in filefrag output: %q", output)
	return 0
}

func testDirectoryExtentTree(t *testing.T) {
	env := newTestEnv(t, 128)

	// Create a directory that will have many blocks
	dir, err := env.builder.CreateDirectory(ext4fs.RootInode, "bigdir", 0755, 0, 0)
	require.NoError(t, err)

	// Create many files with long names to fill directory blocks
	for i := 0; i < 1000; i++ {
		fileName := fmt.Sprintf("very_long_file_name_that_takes_up_space_%04d.txt", i)
		_, err = env.builder.CreateFile(dir, fileName, []byte("content"), 0644, 0, 0)
		require.NoError(t, err)
	}

	env.finalize()

	output := env.dockerExecSimple(
		`ls bigdir | wc -l`,
		`test -d "bigdir" && echo "directory exists"`,
	)

	assert.Contains(t, output, "1000")
	assert.Contains(t, output, "directory exists")
}

func testXattrBasic(t *testing.T) {
	testCases := []struct {
		name      string
		xattrName string
		value     string
	}{
		{
			name:      "user xattr",
			xattrName: "user.myattr",
			value:     "myvalue",
		},
		{
			name:      "security selinux context",
			xattrName: "security.selinux",
			value:     "unconfined_u:object_r:user_home_t:s0\x00",
		},
		{
			name:      "trusted xattr",
			xattrName: "trusted.overlay.opaque",
			value:     "y",
		},
		{
			name:      "user xattr with special chars",
			xattrName: "user.test.nested.name",
			value:     "value with spaces and 日本語",
		},
		{
			name:      "binary value",
			xattrName: "user.binary",
			value:     string([]byte{0x00, 0x01, 0x02, 0xFF, 0xFE}),
		},
	}

	for _, tc := range testCases {
		t.Run(tc.name, func(t *testing.T) {
			env := newTestEnv(t, defaultImageSizeMB)

			fileInode, err := env.builder.CreateFile(ext4fs.RootInode, "testfile.txt", []byte("content"), 0644, 0, 0)
			require.NoError(t, err)

			err = env.builder.SetXattr(fileInode, tc.xattrName, []byte(tc.value))
			require.NoError(t, err)

			env.finalize()

			var commands []string
			if strings.HasPrefix(tc.xattrName, "user.") {
				commands = []string{
					fmt.Sprintf(`getfattr -n "%s" --only-values testfile.txt | xxd`, tc.xattrName),
				}
			} else if strings.HasPrefix(tc.xattrName, "security.") {
				commands = []string{
					fmt.Sprintf(`getfattr -n "%s" --only-values testfile.txt 2>/dev/null | xxd || echo "xattr set but not readable without privileges"`, tc.xattrName),
					fmt.Sprintf(`getfattr -d -m - testfile.txt 2>/dev/null | grep -q "%s" && echo "xattr exists in listing"`, tc.xattrName),
				}
			} else {
				commands = []string{
					fmt.Sprintf(`getfattr -n "%s" --only-values testfile.txt 2>/dev/null | xxd || echo "xattr requires privileges"`, tc.xattrName),
				}
			}

			output := env.dockerExecSimple(commands...)

			if strings.HasPrefix(tc.xattrName, "user.") {
				assert.NotEmpty(t, output)
			}
		})
	}
}

func testXattrSELinux(t *testing.T) {
	env := newTestEnv(t, defaultImageSizeMB)

	contexts := []struct {
		filename string
		context  string
	}{
		{"system_file.txt", "system_u:object_r:etc_t:s0"},
		{"user_file.txt", "unconfined_u:object_r:user_home_t:s0"},
		{"bin_file", "system_u:object_r:bin_t:s0"},
	}

	for _, c := range contexts {
		fileInode, err := env.builder.CreateFile(ext4fs.RootInode, c.filename, []byte("content"), 0644, 0, 0)
		require.NoError(t, err)
		err = env.builder.SetXattr(fileInode, "security.selinux", []byte(c.context+"\x00"))
		require.NoError(t, err)
	}

	env.finalize()

	output := env.dockerExecSimple(
		`getfattr -d -m security.selinux system_file.txt 2>/dev/null || true`,
		`getfattr -d -m - user_file.txt 2>/dev/null | grep -c security || echo "0"`,
	)

	assert.NotEmpty(t, output)
}

func testXattrMultiple(t *testing.T) {
	env := newTestEnv(t, defaultImageSizeMB)

	fileInode, err := env.builder.CreateFile(ext4fs.RootInode, "multi_xattr.txt", []byte("content"), 0644, 0, 0)
	require.NoError(t, err)

	xattrs := map[string]string{
		"user.attr1":          "value1",
		"user.attr2":          "value2",
		"user.attr3":          "value3",
		"user.long.name.attr": "long_value_here",
	}

	for name, value := range xattrs {
		err := env.builder.SetXattr(fileInode, name, []byte(value))
		require.NoError(t, err)
	}

	env.finalize()

	output := env.dockerExecSimple(`getfattr -d multi_xattr.txt`)

	for name := range xattrs {
		assert.Contains(t, output, name)
	}
}

func testXattrOnDirectory(t *testing.T) {
	env := newTestEnv(t, defaultImageSizeMB)

	dirInode, err := env.builder.CreateDirectory(ext4fs.RootInode, "labeled_dir", 0755, 0, 0)
	require.NoError(t, err)

	err = env.builder.SetXattr(dirInode, "user.dir_attr", []byte("directory_value"))
	require.NoError(t, err)

	err = env.builder.SetXattr(dirInode, "security.selinux", []byte("system_u:object_r:var_t:s0\x00"))
	require.NoError(t, err)

	fileInode, err := env.builder.CreateFile(dirInode, "file_in_dir.txt", []byte("content"), 0644, 0, 0)
	require.NoError(t, err)

	err = env.builder.SetXattr(fileInode, "user.file_attr", []byte("file_value"))
	require.NoError(t, err)

	env.finalize()

	output := env.dockerExecSimple(
		`getfattr -d labeled_dir`,
		`getfattr -d labeled_dir/file_in_dir.txt`,
	)

	assert.Contains(t, output, "user.dir_attr")
	assert.Contains(t, output, "user.file_attr")
}

func testXattrOverwrite(t *testing.T) {
	env := newTestEnv(t, defaultImageSizeMB)

	fileInode, err := env.builder.CreateFile(ext4fs.RootInode, "overwrite.txt", []byte("content"), 0644, 0, 0)
	require.NoError(t, err)

	err = env.builder.SetXattr(fileInode, "user.test", []byte("initial_value"))
	require.NoError(t, err)

	err = env.builder.SetXattr(fileInode, "user.test", []byte("new_value"))
	require.NoError(t, err)

	env.finalize()

	output := env.dockerExecSimple(`getfattr -n user.test --only-values overwrite.txt`)

	assert.Contains(t, output, "new_value")
	assert.NotContains(t, output, "initial_value")
}

func testXattrLargeValue(t *testing.T) {
	env := newTestEnv(t, defaultImageSizeMB)

	fileInode, err := env.builder.CreateFile(ext4fs.RootInode, "large_xattr.txt", []byte("content"), 0644, 0, 0)
	require.NoError(t, err)

	largeValue := make([]byte, 2000)
	for i := range largeValue {
		largeValue[i] = byte('A' + (i % 26))
	}

	err = env.builder.SetXattr(fileInode, "user.large", largeValue)
	require.NoError(t, err)

	env.finalize()

	output := env.dockerExecSimple(`getfattr -n user.large --only-values large_xattr.txt | wc -c`)

	assert.Contains(t, output, "2000")
}

func testXattrWithFileOverwrite(t *testing.T) {
	env := newTestEnv(t, defaultImageSizeMB)

	fileInode, err := env.builder.CreateFile(ext4fs.RootInode, "xattr_overwrite.txt", []byte("original"), 0644, 0, 0)
	require.NoError(t, err)

	err = env.builder.SetXattr(fileInode, "user.original", []byte("original_attr"))
	require.NoError(t, err)

	newInode, err := env.builder.CreateFile(ext4fs.RootInode, "xattr_overwrite.txt", []byte("new content"), 0644, 0, 0)
	require.NoError(t, err)

	err = env.builder.SetXattr(newInode, "user.new", []byte("new_attr"))
	require.NoError(t, err)

	env.finalize()

	output := env.dockerExecSimple(
		`cat xattr_overwrite.txt`,
		`echo "---"`,
		`getfattr -d xattr_overwrite.txt`,
	)

	assert.Contains(t, output, "new content")
	assert.Contains(t, output, "user.new")
}

func testXattrSymlink(t *testing.T) {
	env := newTestEnv(t, defaultImageSizeMB)

	_, err := env.builder.CreateFile(ext4fs.RootInode, "target.txt", []byte("target content"), 0644, 0, 0)
	require.NoError(t, err)

	linkInode, err := env.builder.CreateSymlink(ext4fs.RootInode, "link.txt", "target.txt", 0, 0)
	require.NoError(t, err)

	err = env.builder.SetXattr(linkInode, "user.link_attr", []byte("link_value"))
	require.NoError(t, err)

	env.finalize()

	output := env.dockerExecSimple(
		`getfattr -h -d link.txt 2>/dev/null || echo "symlink xattr not readable"`,
		`test -L link.txt && echo "is symlink"`,
	)

	assert.Contains(t, output, "is symlink")
}

func testXattrCapabilities(t *testing.T) {
	env := newTestEnv(t, defaultImageSizeMB)

	fileInode, err := env.builder.CreateFile(ext4fs.RootInode, "ping_clone", []byte("#!/bin/sh\necho ping"), 0755, 0, 0)
	require.NoError(t, err)

	// VFS capability v2 structure for CAP_NET_RAW (bit 13)
	capData := []byte{
		0x00, 0x00, 0x00, 0x02, // VFS_CAP_REVISION_2
		0x00, 0x20, 0x00, 0x00, // permitted low (CAP_NET_RAW = bit 13)
		0x00, 0x00, 0x00, 0x00, // permitted high
		0x00, 0x00, 0x00, 0x00, // inheritable low
		0x00, 0x00, 0x00, 0x00, // inheritable high
	}

	err = env.builder.SetXattr(fileInode, "security.capability", capData)
	require.NoError(t, err)

	env.finalize()

	output := env.dockerExecSimple(
		`getfattr -d -m security.capability ping_clone 2>/dev/null | grep -c capability || echo "0"`,
		`getcap ping_clone 2>/dev/null || echo "getcap requires privileges"`,
	)

	assert.NotEmpty(t, output)
}

func testXattrRemove(t *testing.T) {
	env := newTestEnv(t, defaultImageSizeMB)

	fileInode, err := env.builder.CreateFile(ext4fs.RootInode, "remove_xattr.txt", []byte("content"), 0644, 0, 0)
	require.NoError(t, err)

	err = env.builder.SetXattr(fileInode, "user.keep", []byte("keep_value"))
	require.NoError(t, err)

	err = env.builder.SetXattr(fileInode, "user.remove", []byte("remove_value"))
	require.NoError(t, err)

	err = env.builder.RemoveXattr(fileInode, "user.remove")
	require.NoError(t, err)

	env.finalize()

	output := env.dockerExecSimple(`getfattr -d remove_xattr.txt`)

	assert.Contains(t, output, "user.keep")
	assert.NotContains(t, output, "user.remove")
}

func testXattrList(t *testing.T) {
	env := newTestEnv(t, defaultImageSizeMB)

	fileInode, err := env.builder.CreateFile(ext4fs.RootInode, "list_xattr.txt", []byte("content"), 0644, 0, 0)
	require.NoError(t, err)

	// Test multiple namespaces to cover xattrIndexToPrefix branches
	expectedAttrs := []string{
		"user.alpha",
		"user.beta",
		"security.selinux",
		"trusted.overlay",
	}

	for _, attr := range expectedAttrs {
		err = env.builder.SetXattr(fileInode, attr, []byte("value"))
		require.NoError(t, err)
	}

	listedAttrs, err := env.builder.ListXattrs(fileInode)
	require.NoError(t, err)
	assert.Len(t, listedAttrs, len(expectedAttrs))

	for _, expected := range expectedAttrs {
		assert.Contains(t, listedAttrs, expected)
	}

	env.finalize()

	output := env.dockerExecSimple(`getfattr -d -m ".*" list_xattr.txt 2>/dev/null | grep -E "^(user|security|trusted)\." | wc -l`)
	// Should have 4 attrs listed
	assert.Contains(t, output, "4")
}

func testXattrComplexFilesystem(t *testing.T) {
	env := newTestEnv(t, defaultImageSizeMB)

	// Create /etc with SELinux contexts
	etcDir, err := env.builder.CreateDirectory(ext4fs.RootInode, "etc", 0755, 0, 0)
	require.NoError(t, err)
	err = env.builder.SetXattr(etcDir, "security.selinux", []byte("system_u:object_r:etc_t:s0\x00"))
	require.NoError(t, err)

	passwdInode, err := env.builder.CreateFile(etcDir, "passwd", []byte("root:x:0:0::/root:/bin/bash\n"), 0644, 0, 0)
	require.NoError(t, err)
	err = env.builder.SetXattr(passwdInode, "security.selinux", []byte("system_u:object_r:passwd_file_t:s0\x00"))
	require.NoError(t, err)

	shadowInode, err := env.builder.CreateFile(etcDir, "shadow", []byte("root:!:::::::\n"), 0000, 0, 0)
	require.NoError(t, err)
	err = env.builder.SetXattr(shadowInode, "security.selinux", []byte("system_u:object_r:shadow_t:s0\x00"))
	require.NoError(t, err)

	// Create /bin with executable capabilities
	binDir, err := env.builder.CreateDirectory(ext4fs.RootInode, "bin", 0755, 0, 0)
	require.NoError(t, err)
	err = env.builder.SetXattr(binDir, "security.selinux", []byte("system_u:object_r:bin_t:s0\x00"))
	require.NoError(t, err)

	// Create /home/user with user xattrs
	homeDir, err := env.builder.CreateDirectory(ext4fs.RootInode, "home", 0755, 0, 0)
	require.NoError(t, err)

	userDir, err := env.builder.CreateDirectory(homeDir, "user", 0700, 1000, 1000)
	require.NoError(t, err)
	err = env.builder.SetXattr(userDir, "security.selinux", []byte("unconfined_u:object_r:user_home_dir_t:s0\x00"))
	require.NoError(t, err)
	err = env.builder.SetXattr(userDir, "user.quota.space", []byte("1073741824"))
	require.NoError(t, err)

	docInode, err := env.builder.CreateFile(userDir, "document.txt", []byte("My document\n"), 0644, 1000, 1000)
	require.NoError(t, err)
	err = env.builder.SetXattr(docInode, "security.selinux", []byte("unconfined_u:object_r:user_home_t:s0\x00"))
	require.NoError(t, err)
	err = env.builder.SetXattr(docInode, "user.author", []byte("testuser"))
	require.NoError(t, err)
	err = env.builder.SetXattr(docInode, "user.created", []byte("2024-01-01"))
	require.NoError(t, err)

	env.finalize()

	output := env.dockerExecSimple(
		`getfattr -d -m - etc 2>/dev/null | head -5`,
		`getfattr -d home/user/document.txt`,
		`cat home/user/document.txt`,
	)

	assert.Contains(t, output, "My document")
	assert.Contains(t, output, "user.author")
	assert.Contains(t, output, "user.created")
}

func testXattrManyFiles(t *testing.T) {
	env := newTestEnv(t, 128)

	numFiles := 100
	for i := 0; i < numFiles; i++ {
		filename := fmt.Sprintf("file_%03d.txt", i)
		fileInode, err := env.builder.CreateFile(ext4fs.RootInode, filename, []byte(fmt.Sprintf("content %d", i)), 0644, 0, 0)
		require.NoError(t, err)

		err = env.builder.SetXattr(fileInode, "user.index", []byte(fmt.Sprintf("%d", i)))
		require.NoError(t, err)

		err = env.builder.SetXattr(fileInode, "security.selinux", []byte(fmt.Sprintf("user_u:object_r:file_%d_t:s0\x00", i)))
		require.NoError(t, err)
	}

	env.finalize()

	output := env.dockerExecSimple(
		`ls -1 file_*.txt | wc -l`,
		`getfattr -n user.index --only-values file_000.txt`,
		`getfattr -n user.index --only-values file_099.txt`,
	)

	assert.Contains(t, output, "100")
	assert.Contains(t, output, "0")
	assert.Contains(t, output, "99")
}

func testXattrEmpty(t *testing.T) {
	env := newTestEnv(t, defaultImageSizeMB)

	fileInode, err := env.builder.CreateFile(ext4fs.RootInode, "empty_xattr.txt", []byte("content"), 0644, 0, 0)
	require.NoError(t, err)

	err = env.builder.SetXattr(fileInode, "user.empty", []byte{})
	require.NoError(t, err)

	err = env.builder.SetXattr(fileInode, "user.notempty", []byte("has_value"))
	require.NoError(t, err)

	env.finalize()

	output := env.dockerExecSimple(`getfattr -d empty_xattr.txt`)

	assert.Contains(t, output, "user.empty")
	assert.Contains(t, output, "user.notempty")
}

func testXattrPosixACL(t *testing.T) {
	env := newTestEnv(t, defaultImageSizeMB)

	fileInode, err := env.builder.CreateFile(ext4fs.RootInode, "acl_file.txt", []byte("content"), 0644, 0, 0)
	require.NoError(t, err)

	// POSIX ACL format (version 2): user::rw-, group::r--, other::r--
	aclData := []byte{
		0x02, 0x00, 0x00, 0x00, // version 2
		0x01, 0x00, // ACL_USER_OBJ
		0x06, 0x00, // permissions: rw-
		0x04, 0x00, // ACL_GROUP_OBJ
		0x04, 0x00, // permissions: r--
		0x20, 0x00, // ACL_OTHER
		0x04, 0x00, // permissions: r--
	}

	err = env.builder.SetXattr(fileInode, "system.posix_acl_access", aclData)
	require.NoError(t, err)

	env.finalize()

	output := env.dockerExecSimple(
		`getfattr -d -m - acl_file.txt 2>/dev/null | grep -c posix_acl || echo "0"`,
		`getfacl acl_file.txt 2>/dev/null || echo "acl present"`,
	)

	assert.NotEmpty(t, output)
}

func testDeleteFile(t *testing.T) {
	env := newTestEnv(t, defaultImageSizeMB)

	// Create a file and then delete it
	_, err := env.builder.CreateFile(ext4fs.RootInode, "to_delete.txt", []byte("delete me"), 0644, 0, 0)
	require.NoError(t, err)

	_, err = env.builder.CreateFile(ext4fs.RootInode, "keep.txt", []byte("keep me"), 0644, 0, 0)
	require.NoError(t, err)

	err = env.builder.Delete(ext4fs.RootInode, "to_delete.txt")
	require.NoError(t, err)

	env.finalize()

	output := env.dockerExecSimple(
		`test -f "keep.txt" && echo "keep.txt exists"`,
		`test -f "to_delete.txt" && echo "to_delete.txt exists" || echo "to_delete.txt deleted"`,
		`cat keep.txt`,
	)

	assert.Contains(t, output, "keep.txt exists")
	assert.Contains(t, output, "to_delete.txt deleted")
	assert.Contains(t, output, "keep me")
}

func testDeleteSymlink(t *testing.T) {
	env := newTestEnv(t, defaultImageSizeMB)

	_, err := env.builder.CreateFile(ext4fs.RootInode, "target.txt", []byte("target content"), 0644, 0, 0)
	require.NoError(t, err)

	_, err = env.builder.CreateSymlink(ext4fs.RootInode, "link.txt", "target.txt", 0, 0)
	require.NoError(t, err)

	err = env.builder.Delete(ext4fs.RootInode, "link.txt")
	require.NoError(t, err)

	env.finalize()

	output := env.dockerExecSimple(
		`test -f "target.txt" && echo "target.txt exists"`,
		`test -L "link.txt" && echo "link.txt exists" || echo "link.txt deleted"`,
		`cat target.txt`,
	)

	assert.Contains(t, output, "target.txt exists")
	assert.Contains(t, output, "link.txt deleted")
	assert.Contains(t, output, "target content")
}

func testDeleteEmptyDirectory(t *testing.T) {
	env := newTestEnv(t, defaultImageSizeMB)

	_, err := env.builder.CreateDirectory(ext4fs.RootInode, "empty_dir", 0755, 0, 0)
	require.NoError(t, err)

	err = env.builder.Delete(ext4fs.RootInode, "empty_dir")
	require.NoError(t, err)

	env.finalize()

	output := env.dockerExecSimple(
		`test -d "empty_dir" && echo "empty_dir exists" || echo "empty_dir deleted"`,
	)

	assert.Contains(t, output, "empty_dir deleted")
}

func testDeleteNonEmptyDirectoryFails(t *testing.T) {
	env := newTestEnv(t, defaultImageSizeMB)

	dir, err := env.builder.CreateDirectory(ext4fs.RootInode, "non_empty", 0755, 0, 0)
	require.NoError(t, err)

	_, err = env.builder.CreateFile(dir, "file.txt", []byte("content"), 0644, 0, 0)
	require.NoError(t, err)

	// Delete should fail because directory is not empty
	err = env.builder.Delete(ext4fs.RootInode, "non_empty")
	require.Error(t, err)
	assert.Contains(t, err.Error(), "not empty")

	env.finalize()

	output := env.dockerExecSimple(
		`test -d "non_empty" && echo "non_empty exists"`,
		`test -f "non_empty/file.txt" && echo "file.txt exists"`,
	)

	assert.Contains(t, output, "non_empty exists")
	assert.Contains(t, output, "file.txt exists")
}

func testDeleteDirectoryRecursive(t *testing.T) {
	env := newTestEnv(t, defaultImageSizeMB)

	// Create a directory tree
	dir1, err := env.builder.CreateDirectory(ext4fs.RootInode, "dir1", 0755, 0, 0)
	require.NoError(t, err)

	dir2, err := env.builder.CreateDirectory(dir1, "dir2", 0755, 0, 0)
	require.NoError(t, err)

	_, err = env.builder.CreateFile(dir1, "file1.txt", []byte("file1"), 0644, 0, 0)
	require.NoError(t, err)

	_, err = env.builder.CreateFile(dir2, "file2.txt", []byte("file2"), 0644, 0, 0)
	require.NoError(t, err)

	_, err = env.builder.CreateSymlink(dir2, "link.txt", "../file1.txt", 0, 0)
	require.NoError(t, err)

	// Keep another file at root level
	_, err = env.builder.CreateFile(ext4fs.RootInode, "keep.txt", []byte("keep"), 0644, 0, 0)
	require.NoError(t, err)

	// Delete directory recursively
	err = env.builder.DeleteDirectory(ext4fs.RootInode, "dir1")
	require.NoError(t, err)

	env.finalize()

	output := env.dockerExecSimple(
		`test -d "dir1" && echo "dir1 exists" || echo "dir1 deleted"`,
		`test -f "keep.txt" && echo "keep.txt exists"`,
		`cat keep.txt`,
	)

	assert.Contains(t, output, "dir1 deleted")
	assert.Contains(t, output, "keep.txt exists")
	assert.Contains(t, output, "keep")
}

func testDeleteAndRecreate(t *testing.T) {
	env := newTestEnv(t, defaultImageSizeMB)

	// Create, delete, recreate file
	_, err := env.builder.CreateFile(ext4fs.RootInode, "recreate.txt", []byte("original"), 0644, 0, 0)
	require.NoError(t, err)

	err = env.builder.Delete(ext4fs.RootInode, "recreate.txt")
	require.NoError(t, err)

	_, err = env.builder.CreateFile(ext4fs.RootInode, "recreate.txt", []byte("new content"), 0755, 1000, 1000)
	require.NoError(t, err)

	env.finalize()

	output := env.dockerExecSimple(
		`test -f "recreate.txt" && echo "file exists"`,
		`cat recreate.txt`,
		`stat -c "%a" recreate.txt`,
		`stat -c "%u:%g" recreate.txt`,
	)

	assert.Contains(t, output, "file exists")
	assert.Contains(t, output, "new content")
	assert.NotContains(t, output, "original")
	assert.Contains(t, output, "755")
	assert.Contains(t, output, "1000:1000")
}

func testDeleteFileWithXattr(t *testing.T) {
	env := newTestEnv(t, defaultImageSizeMB)

	fileInode, err := env.builder.CreateFile(ext4fs.RootInode, "xattr_file.txt", []byte("content"), 0644, 0, 0)
	require.NoError(t, err)

	err = env.builder.SetXattr(fileInode, "user.attr1", []byte("value1"))
	require.NoError(t, err)

	err = env.builder.SetXattr(fileInode, "user.attr2", []byte("value2"))
	require.NoError(t, err)

	// Delete the file (should also free xattr block)
	err = env.builder.Delete(ext4fs.RootInode, "xattr_file.txt")
	require.NoError(t, err)

	// Create another file to reuse freed blocks
	_, err = env.builder.CreateFile(ext4fs.RootInode, "new_file.txt", []byte("new content"), 0644, 0, 0)
	require.NoError(t, err)

	env.finalize()

	output := env.dockerExecSimple(
		`test -f "xattr_file.txt" && echo "xattr_file.txt exists" || echo "xattr_file.txt deleted"`,
		`test -f "new_file.txt" && echo "new_file.txt exists"`,
		`cat new_file.txt`,
	)

	assert.Contains(t, output, "xattr_file.txt deleted")
	assert.Contains(t, output, "new_file.txt exists")
	assert.Contains(t, output, "new content")
}

func testDeleteInSubdirectory(t *testing.T) {
	env := newTestEnv(t, defaultImageSizeMB)

	dir, err := env.builder.CreateDirectory(ext4fs.RootInode, "subdir", 0755, 0, 0)
	require.NoError(t, err)

	_, err = env.builder.CreateFile(dir, "file1.txt", []byte("file1"), 0644, 0, 0)
	require.NoError(t, err)

	_, err = env.builder.CreateFile(dir, "file2.txt", []byte("file2"), 0644, 0, 0)
	require.NoError(t, err)

	_, err = env.builder.CreateFile(dir, "file3.txt", []byte("file3"), 0644, 0, 0)
	require.NoError(t, err)

	// Delete middle file
	err = env.builder.Delete(dir, "file2.txt")
	require.NoError(t, err)

	env.finalize()

	output := env.dockerExecSimple(
		`test -d "subdir" && echo "subdir exists"`,
		`test -f "subdir/file1.txt" && echo "file1.txt exists"`,
		`test -f "subdir/file2.txt" && echo "file2.txt exists" || echo "file2.txt deleted"`,
		`test -f "subdir/file3.txt" && echo "file3.txt exists"`,
		`ls subdir | wc -l | tr -d ' '`,
	)

	assert.Contains(t, output, "subdir exists")
	assert.Contains(t, output, "file1.txt exists")
	assert.Contains(t, output, "file2.txt deleted")
	assert.Contains(t, output, "file3.txt exists")
	assert.Contains(t, output, "2")
}

func testDeleteMultipleFiles(t *testing.T) {
	env := newTestEnv(t, 128)

	// Create many files
	for i := 0; i < 100; i++ {
		filename := fmt.Sprintf("file_%03d.txt", i)
		_, err := env.builder.CreateFile(ext4fs.RootInode, filename, []byte(fmt.Sprintf("content %d", i)), 0644, 0, 0)
		require.NoError(t, err)
	}

	// Delete every other file
	for i := 0; i < 100; i += 2 {
		filename := fmt.Sprintf("file_%03d.txt", i)
		err := env.builder.Delete(ext4fs.RootInode, filename)
		require.NoError(t, err)
	}

	env.finalize()

	output := env.dockerExecSimple(
		`ls -1 file_*.txt | wc -l | tr -d ' '`,
		`test -f "file_001.txt" && echo "file_001.txt exists"`,
		`test -f "file_000.txt" && echo "file_000.txt exists" || echo "file_000.txt deleted"`,
		`test -f "file_099.txt" && echo "file_099.txt exists"`,
		`test -f "file_098.txt" && echo "file_098.txt exists" || echo "file_098.txt deleted"`,
	)

	assert.Contains(t, output, "50")
	assert.Contains(t, output, "file_001.txt exists")
	assert.Contains(t, output, "file_000.txt deleted")
	assert.Contains(t, output, "file_099.txt exists")
	assert.Contains(t, output, "file_098.txt deleted")
}

func testDeleteDirectoryDeep(t *testing.T) {
	env := newTestEnv(t, 128)

	// Create a deep directory structure
	parent := uint32(ext4fs.RootInode)
	for i := 0; i < 10; i++ {
		dirName := fmt.Sprintf("level%d", i)
		dir, err := env.builder.CreateDirectory(parent, dirName, 0755, 0, 0)
		require.NoError(t, err)

		// Add some files at each level
		for j := 0; j < 5; j++ {
			fileName := fmt.Sprintf("file%d.txt", j)
			_, err = env.builder.CreateFile(dir, fileName, []byte(fmt.Sprintf("content %d-%d", i, j)), 0644, 0, 0)
			require.NoError(t, err)
		}

		parent = dir
	}

	// Keep a file at root
	_, err := env.builder.CreateFile(ext4fs.RootInode, "root_file.txt", []byte("root"), 0644, 0, 0)
	require.NoError(t, err)

	// Delete the entire tree from root
	err = env.builder.DeleteDirectory(ext4fs.RootInode, "level0")
	require.NoError(t, err)

	env.finalize()

	output := env.dockerExecSimple(
		`test -d "level0" && echo "level0 exists" || echo "level0 deleted"`,
		`test -f "root_file.txt" && echo "root_file.txt exists"`,
		`cat root_file.txt`,
	)

	assert.Contains(t, output, "level0 deleted")
	assert.Contains(t, output, "root_file.txt exists")
	assert.Contains(t, output, "root")
}

func testDeleteLargeFile(t *testing.T) {
	env := newTestEnv(t, 128)

	// Create a large file that uses multiple extents (>4 extents triggers extent tree)
	largeContent := make([]byte, 100*4096) // 100 blocks = 400KB
	for i := range largeContent {
		largeContent[i] = byte(i % 256)
	}

	_, err := env.builder.CreateFile(ext4fs.RootInode, "large_file.bin", largeContent, 0644, 0, 0)
	require.NoError(t, err)

	// Create another file to fragment allocation
	_, err = env.builder.CreateFile(ext4fs.RootInode, "small.txt", []byte("small"), 0644, 0, 0)
	require.NoError(t, err)

	// Delete the large file
	err = env.builder.Delete(ext4fs.RootInode, "large_file.bin")
	require.NoError(t, err)

	// Create a new file to reuse freed blocks
	_, err = env.builder.CreateFile(ext4fs.RootInode, "reuse.txt", []byte("reused blocks"), 0644, 0, 0)
	require.NoError(t, err)

	env.finalize()

	output := env.dockerExecSimple(
		`test -f "large_file.bin" && echo "large exists" || echo "large deleted"`,
		`test -f "small.txt" && echo "small exists"`,
		`test -f "reuse.txt" && echo "reuse exists"`,
		`cat reuse.txt`,
	)

	assert.Contains(t, output, "large deleted")
	assert.Contains(t, output, "small exists")
	assert.Contains(t, output, "reuse exists")
	assert.Contains(t, output, "reused blocks")
}

func testDeleteLargeDirectory(t *testing.T) {
	env := newTestEnv(t, 128)

	// Create a directory with many files to trigger extent tree conversion.
	// A directory needs >4 non-contiguous blocks to have an extent tree.
	// Long filenames help fill blocks quickly.
	dir, err := env.builder.CreateDirectory(ext4fs.RootInode, "bigdir", 0755, 0, 0)
	require.NoError(t, err)

	// Create 1000 files with long names to fill multiple directory blocks
	for i := 0; i < 1000; i++ {
		fileName := fmt.Sprintf("file_with_a_reasonably_long_name_to_fill_blocks_%04d.txt", i)
		_, err = env.builder.CreateFile(dir, fileName, []byte("content"), 0644, 0, 0)
		require.NoError(t, err)
	}

	// Delete the large directory recursively (should free extent tree blocks)
	err = env.builder.DeleteDirectory(ext4fs.RootInode, "bigdir")
	require.NoError(t, err)

	// Verify we can still create new files (blocks were properly freed)
	_, err = env.builder.CreateFile(ext4fs.RootInode, "after_delete.txt", []byte("success"), 0644, 0, 0)
	require.NoError(t, err)

	env.finalize()

	output := env.dockerExecSimple(
		`test -d "bigdir" && echo "bigdir exists" || echo "bigdir deleted"`,
		`test -f "after_delete.txt" && echo "after_delete.txt exists"`,
		`cat after_delete.txt`,
	)

	assert.Contains(t, output, "bigdir deleted")
	assert.Contains(t, output, "after_delete.txt exists")
	assert.Contains(t, output, "success")
}

func testDeleteSlowSymlink(t *testing.T) {
	env := newTestEnv(t, defaultImageSizeMB)

	// Create a slow symlink (>60 bytes, stored in a data block)
	longTarget := "/very/long/path/that/exceeds/sixty/bytes/to/trigger/slow/symlink/storage/mechanism"
	_, err := env.builder.CreateSymlink(ext4fs.RootInode, "slow_link", longTarget, 0, 0)
	require.NoError(t, err)

	// Delete the slow symlink
	err = env.builder.Delete(ext4fs.RootInode, "slow_link")
	require.NoError(t, err)

	// Create a file to potentially reuse the freed block
	_, err = env.builder.CreateFile(ext4fs.RootInode, "after_delete.txt", []byte("after"), 0644, 0, 0)
	require.NoError(t, err)

	env.finalize()

	output := env.dockerExecSimple(
		`test -L "slow_link" && echo "symlink exists" || echo "symlink deleted"`,
		`test -f "after_delete.txt" && echo "after exists"`,
		`cat after_delete.txt`,
	)

	assert.Contains(t, output, "symlink deleted")
	assert.Contains(t, output, "after exists")
	assert.Contains(t, output, "after")
}

func testDeleteDirectoryWithXattr(t *testing.T) {
	env := newTestEnv(t, defaultImageSizeMB)

	// Create directory with xattrs
	dir, err := env.builder.CreateDirectory(ext4fs.RootInode, "xattr_dir", 0755, 0, 0)
	require.NoError(t, err)

	err = env.builder.SetXattr(dir, "user.dir_attr", []byte("dir_value"))
	require.NoError(t, err)

	err = env.builder.SetXattr(dir, "security.selinux", []byte("system_u:object_r:var_t:s0\x00"))
	require.NoError(t, err)

	// Delete the directory (should free xattr block too)
	err = env.builder.Delete(ext4fs.RootInode, "xattr_dir")
	require.NoError(t, err)

	// Create a new directory to reuse resources
	_, err = env.builder.CreateDirectory(ext4fs.RootInode, "new_dir", 0755, 0, 0)
	require.NoError(t, err)

	env.finalize()

	output := env.dockerExecSimple(
		`test -d "xattr_dir" && echo "xattr_dir exists" || echo "xattr_dir deleted"`,
		`test -d "new_dir" && echo "new_dir exists"`,
	)

	assert.Contains(t, output, "xattr_dir deleted")
	assert.Contains(t, output, "new_dir exists")
}

func testDeleteNotFound(t *testing.T) {
	env := newTestEnv(t, defaultImageSizeMB)

	// Try to delete non-existent file
	err := env.builder.Delete(ext4fs.RootInode, "does_not_exist.txt")
	require.Error(t, err)
	assert.Contains(t, err.Error(), "not found")

	// Try to delete non-existent directory
	err = env.builder.DeleteDirectory(ext4fs.RootInode, "does_not_exist_dir")
	require.Error(t, err)
	assert.Contains(t, err.Error(), "not found")

	env.finalize()

	// Just verify filesystem is valid
	output := env.dockerExecSimple(`echo "filesystem valid"`)
	assert.Contains(t, output, "filesystem valid")
}

func testDeleteDotDotFails(t *testing.T) {
	env := newTestEnv(t, defaultImageSizeMB)

	dir, err := env.builder.CreateDirectory(ext4fs.RootInode, "testdir", 0755, 0, 0)
	require.NoError(t, err)

	// Try to delete "."
	err = env.builder.Delete(dir, ".")
	require.Error(t, err)
	assert.Contains(t, err.Error(), `cannot delete "."`)

	// Try to delete ".."
	err = env.builder.Delete(dir, "..")
	require.Error(t, err)
	assert.Contains(t, err.Error(), `cannot delete ".."`)

	env.finalize()

	output := env.dockerExecSimple(
		`test -d "testdir" && echo "testdir exists"`,
	)

	assert.Contains(t, output, "testdir exists")
}

func testDeleteFirstEntry(t *testing.T) {
	env := newTestEnv(t, defaultImageSizeMB)

	// Create files in order: first, second, third
	_, err := env.builder.CreateFile(ext4fs.RootInode, "aaa_first.txt", []byte("first"), 0644, 0, 0)
	require.NoError(t, err)

	_, err = env.builder.CreateFile(ext4fs.RootInode, "bbb_second.txt", []byte("second"), 0644, 0, 0)
	require.NoError(t, err)

	_, err = env.builder.CreateFile(ext4fs.RootInode, "ccc_third.txt", []byte("third"), 0644, 0, 0)
	require.NoError(t, err)

	// Delete the first entry (after . and .. and lost+found)
	err = env.builder.Delete(ext4fs.RootInode, "aaa_first.txt")
	require.NoError(t, err)

	env.finalize()

	output := env.dockerExecSimple(
		`test -f "aaa_first.txt" && echo "first exists" || echo "first deleted"`,
		`test -f "bbb_second.txt" && echo "second exists"`,
		`test -f "ccc_third.txt" && echo "third exists"`,
		`cat bbb_second.txt`,
		`cat ccc_third.txt`,
	)

	assert.Contains(t, output, "first deleted")
	assert.Contains(t, output, "second exists")
	assert.Contains(t, output, "third exists")
	assert.Contains(t, output, "second")
	assert.Contains(t, output, "third")
}

func testDeleteStressTest(t *testing.T) {
	env := newTestEnv(t, 128)

	// Create 200 files
	for i := 0; i < 200; i++ {
		filename := fmt.Sprintf("stress_%03d.txt", i)
		_, err := env.builder.CreateFile(ext4fs.RootInode, filename, []byte(fmt.Sprintf("content %d", i)), 0644, 0, 0)
		require.NoError(t, err)
	}

	// Delete all 200 files
	for i := 0; i < 200; i++ {
		filename := fmt.Sprintf("stress_%03d.txt", i)
		err := env.builder.Delete(ext4fs.RootInode, filename)
		require.NoError(t, err)
	}

	// Create 200 new files (should reuse freed inodes and blocks)
	for i := 0; i < 200; i++ {
		filename := fmt.Sprintf("new_%03d.txt", i)
		_, err := env.builder.CreateFile(ext4fs.RootInode, filename, []byte(fmt.Sprintf("new content %d", i)), 0644, 0, 0)
		require.NoError(t, err)
	}

	env.finalize()

	output := env.dockerExecSimple(
		`ls -1 stress_*.txt 2>/dev/null | wc -l | tr -d ' '`,
		`ls -1 new_*.txt | wc -l | tr -d ' '`,
		`cat new_000.txt`,
		`cat new_199.txt`,
	)

	assert.Contains(t, output, "0")   // No stress_* files should exist
	assert.Contains(t, output, "200") // All new_* files should exist
	assert.Contains(t, output, "new content 0")
	assert.Contains(t, output, "new content 199")
}

// testInodeReuse verifies that freed inodes are properly reused when creating new files.
// This catches a bug where allocateInode only increments nextInode but never reuses
// freed inodes from the freeInodeList.
func testInodeReuse(t *testing.T) {
	env := newTestEnv(t, 64)

	// Phase 1: Create files and verify sequential allocation
	inode1, err := env.builder.CreateFile(ext4fs.RootInode, "file1.txt", []byte("content1"), 0644, 0, 0)
	require.NoError(t, err)

	inode2, err := env.builder.CreateFile(ext4fs.RootInode, "file2.txt", []byte("content2"), 0644, 0, 0)
	require.NoError(t, err)

	inode3, err := env.builder.CreateFile(ext4fs.RootInode, "file3.txt", []byte("content3"), 0644, 0, 0)
	require.NoError(t, err)

	inode4, err := env.builder.CreateFile(ext4fs.RootInode, "file4.txt", []byte("content4"), 0644, 0, 0)
	require.NoError(t, err)

	require.Equal(t, inode1+1, inode2, "initial inodes should be sequential")
	require.Equal(t, inode2+1, inode3, "initial inodes should be sequential")
	require.Equal(t, inode3+1, inode4, "initial inodes should be sequential")

	// Phase 2: Delete multiple files to test LIFO reuse order
	// Delete in order: file2, file4 -> freeInodeList = [inode2, inode4]
	err = env.builder.Delete(ext4fs.RootInode, "file2.txt")
	require.NoError(t, err)

	err = env.builder.Delete(ext4fs.RootInode, "file4.txt")
	require.NoError(t, err)

	// Phase 3: Create new files - should reuse in LIFO order (inode4 first, then inode2)
	newA, err := env.builder.CreateFile(ext4fs.RootInode, "new_a.txt", []byte("new_a"), 0644, 0, 0)
	require.NoError(t, err)
	require.Equalf(t, inode4, newA, "first reuse should get inode4 (LIFO): expected %d, got %d", inode4, newA)

	newB, err := env.builder.CreateFile(ext4fs.RootInode, "new_b.txt", []byte("new_b"), 0644, 0, 0)
	require.NoError(t, err)
	require.Equalf(t, inode2, newB, "second reuse should get inode2 (LIFO): expected %d, got %d", inode2, newB)

	// Phase 4: No more freed inodes - should allocate new one (inode5 = inode4 + 1)
	newC, err := env.builder.CreateFile(ext4fs.RootInode, "new_c.txt", []byte("new_c"), 0644, 0, 0)
	require.NoError(t, err)
	expectedNew := inode4 + 1
	require.Equalf(t, expectedNew, newC, "after exhausting freed inodes, should allocate new: expected %d, got %d", expectedNew, newC)

	// Phase 5: Test directory inode reuse
	dir1, err := env.builder.CreateDirectory(ext4fs.RootInode, "dir1", 0755, 0, 0)
	require.NoError(t, err)

	err = env.builder.Delete(ext4fs.RootInode, "dir1")
	require.NoError(t, err)

	dir2, err := env.builder.CreateDirectory(ext4fs.RootInode, "dir2", 0755, 0, 0)
	require.NoError(t, err)
	require.Equalf(t, dir1, dir2, "directory inode should be reused: expected %d, got %d", dir1, dir2)

	// Phase 6: Test symlink inode reuse
	sym1, err := env.builder.CreateSymlink(ext4fs.RootInode, "sym1", "file1.txt", 0, 0)
	require.NoError(t, err)

	err = env.builder.Delete(ext4fs.RootInode, "sym1")
	require.NoError(t, err)

	sym2, err := env.builder.CreateSymlink(ext4fs.RootInode, "sym2", "file3.txt", 0, 0)
	require.NoError(t, err)
	require.Equalf(t, sym1, sym2, "symlink inode should be reused: expected %d, got %d", sym1, sym2)

	env.finalize()

	// Phase 7: Verify with Linux kernel - check inode numbers match
	output := env.dockerExecSimple(
		`stat -c "%i" file1.txt`,
		`stat -c "%i" file3.txt`,
		`stat -c "%i" new_a.txt`,
		`stat -c "%i" new_b.txt`,
		`stat -c "%i" new_c.txt`,
		`stat -c "%i" dir2`,
		`stat -c "%i" sym2`,
		// Verify files are readable
		`cat new_a.txt`,
		`cat new_b.txt`,
		`cat new_c.txt`,
	)

	// Verify inodes match what we recorded
	assert.Contains(t, output, fmt.Sprintf("%d", inode1))
	assert.Contains(t, output, fmt.Sprintf("%d", inode3))
	assert.Contains(t, output, fmt.Sprintf("%d", newA))
	assert.Contains(t, output, fmt.Sprintf("%d", newB))
	assert.Contains(t, output, fmt.Sprintf("%d", newC))
	assert.Contains(t, output, fmt.Sprintf("%d", dir2))
	assert.Contains(t, output, fmt.Sprintf("%d", sym2))

	// Verify content is correct (not corrupted by inode reuse)
	assert.Contains(t, output, "new_a")
	assert.Contains(t, output, "new_b")
	assert.Contains(t, output, "new_c")
}

func testOpenAndModify(t *testing.T) {
	// Create initial image with a file
	env := newTestEnv(t, defaultImageSizeMB)
	_, err := env.builder.CreateFile(ext4fs.RootInode, "hello.txt", []byte("hello world"), 0644, 0, 0)
	require.NoError(t, err)
	env.finalize()

	// Verify initial file exists
	output := env.dockerExecSimple(`cat hello.txt`)
	assert.Contains(t, output, "hello world")

	// Open and modify: delete old file, create new file
	img, err := ext4fs.Open(ext4fs.WithExistingImagePath(env.imagePath))
	require.NoError(t, err)

	err = img.Delete(ext4fs.RootInode, "hello.txt")
	require.NoError(t, err)

	_, err = img.CreateFile(ext4fs.RootInode, "world.txt", []byte("modified content"), 0644, 0, 0)
	require.NoError(t, err)

	err = img.Save()
	require.NoError(t, err)
	err = img.Close()
	require.NoError(t, err)

	// Verify modification
	output = env.dockerExecSimple(
		`test -f hello.txt && echo "hello exists" || echo "hello deleted"`,
		`cat world.txt`,
	)
	assert.Contains(t, output, "hello deleted")
	assert.Contains(t, output, "modified content")
}

func testOpenAndAddFile(t *testing.T) {
	// Create initial image with some files
	env := newTestEnv(t, defaultImageSizeMB)
	_, err := env.builder.CreateFile(ext4fs.RootInode, "original.txt", []byte("original content"), 0644, 0, 0)
	require.NoError(t, err)

	dir, err := env.builder.CreateDirectory(ext4fs.RootInode, "subdir", 0755, 0, 0)
	require.NoError(t, err)

	_, err = env.builder.CreateFile(dir, "nested.txt", []byte("nested content"), 0644, 0, 0)
	require.NoError(t, err)

	env.finalize()

	// Open and add new files without modifying existing ones
	img, err := ext4fs.Open(ext4fs.WithExistingImagePath(env.imagePath))
	require.NoError(t, err)

	_, err = img.CreateFile(ext4fs.RootInode, "new.txt", []byte("new content"), 0644, 0, 0)
	require.NoError(t, err)

	// Add file in existing directory
	_, err = img.CreateFile(dir, "another.txt", []byte("another content"), 0644, 0, 0)
	require.NoError(t, err)

	err = img.Save()
	require.NoError(t, err)
	err = img.Close()
	require.NoError(t, err)

	// Verify all files exist
	output := env.dockerExecSimple(
		`cat original.txt`,
		`cat new.txt`,
		`cat subdir/nested.txt`,
		`cat subdir/another.txt`,
	)
	assert.Contains(t, output, "original content")
	assert.Contains(t, output, "new content")
	assert.Contains(t, output, "nested content")
	assert.Contains(t, output, "another content")
}

func testOpenAndDeleteFile(t *testing.T) {
	// Create initial image with multiple files
	env := newTestEnv(t, defaultImageSizeMB)
	_, err := env.builder.CreateFile(ext4fs.RootInode, "keep.txt", []byte("keep this"), 0644, 0, 0)
	require.NoError(t, err)
	_, err = env.builder.CreateFile(ext4fs.RootInode, "delete.txt", []byte("delete this"), 0644, 0, 0)
	require.NoError(t, err)
	_, err = env.builder.CreateFile(ext4fs.RootInode, "also_keep.txt", []byte("also keep"), 0644, 0, 0)
	require.NoError(t, err)
	env.finalize()

	// Open and delete file
	img, err := ext4fs.Open(ext4fs.WithExistingImagePath(env.imagePath))
	require.NoError(t, err)

	err = img.Delete(ext4fs.RootInode, "delete.txt")
	require.NoError(t, err)

	err = img.Save()
	require.NoError(t, err)
	err = img.Close()
	require.NoError(t, err)

	// Verify results
	output := env.dockerExecSimple(
		`cat keep.txt`,
		`test -f delete.txt && echo "delete exists" || echo "delete removed"`,
		`cat also_keep.txt`,
	)
	assert.Contains(t, output, "keep this")
	assert.Contains(t, output, "delete removed")
	assert.Contains(t, output, "also keep")
}

func testOpenInvalidImage(t *testing.T) {
	tmpDir := t.TempDir()
	invalidPath := filepath.Join(tmpDir, "invalid.img")

	// Test opening non-existent file
	_, err := ext4fs.Open(ext4fs.WithExistingImagePath(invalidPath))
	require.Error(t, err)

	// Create an invalid (empty) file
	f, err := os.Create(invalidPath)
	require.NoError(t, err)
	err = f.Truncate(4 * 1024 * 1024) // 4MB of zeros
	require.NoError(t, err)
	err = f.Close()
	require.NoError(t, err)

	// Test opening invalid ext4 image (wrong magic)
	_, err = ext4fs.Open(ext4fs.WithExistingImagePath(invalidPath))
	require.Error(t, err)
	assert.Contains(t, err.Error(), "invalid ext4 magic")

	// Test opening standard ext4 image (created by mke2fs with default features)
	// Standard mke2fs enables features like 64bit, flex_bg, etc. that we don't support
	standardImgPath := filepath.Join(sharedContainerDir, "standard.img")
	cmd := exec.Command("docker", "exec", dockerContainerID,
		"sh", "-c", fmt.Sprintf("mke2fs -t ext4 -q %s 64M && chmod 666 %s", standardImgPath, standardImgPath))
	if err := cmd.Run(); err == nil {
		standardHostPath := filepath.Join(sharedHostDir, "standard.img")
		_, err = ext4fs.Open(ext4fs.WithExistingImagePath(standardHostPath))
		require.Error(t, err)
		assert.Contains(t, err.Error(), "unsupported filesystem features")
		assert.Contains(t, err.Error(), "only images created by this library are supported")
	}
}

// testLargeFileAfterDeletes verifies that creating a large file after deleting
// many small files does not cause excessive fragmentation leading to "too many extents".
//
// Bug scenario: allocateBlocks() prioritizes freed blocks (scattered) over consecutive
// blocks. When many files are deleted, their freed blocks are scattered across the disk.
// Creating a large file then allocates these scattered blocks first, causing each block
// to become a separate extent. If the file needs more blocks than maxTotalExtents (1360),
// file creation fails with "too many extents" error.
//
// This test creates ~2000 single-block files, deletes them all, then creates a large file
// requiring ~2000 blocks. With the bug, this would create ~2000 extents (exceeding 1360 max).
// The fix should allocate consecutive blocks for large files, keeping extent count low.
func testLargeFileAfterDeletes(t *testing.T) {
	env := newTestEnv(t, defaultImageSizeMB)

	const numFiles = 2000

	// Step 1: Create many small files (each uses 1 block)
	// These will allocate consecutive blocks initially
	for i := 0; i < numFiles; i++ {
		content := make([]byte, 100) // Small content, fits in 1 block
		_, err := env.builder.CreateFile(ext4fs.RootInode, fmt.Sprintf("temp_%04d.txt", i), content, 0644, 0, 0)
		require.NoError(t, err, "failed to create temp file %d", i)
	}

	// Step 2: Delete all files to populate the free block list with scattered blocks
	for i := 0; i < numFiles; i++ {
		err := env.builder.Delete(ext4fs.RootInode, fmt.Sprintf("temp_%04d.txt", i))
		require.NoError(t, err, "failed to delete temp file %d", i)
	}

	// Step 3: Create a large file that needs ~2000 blocks
	// With the bug: allocates 2000 scattered freed blocks = 2000 extents (fails: max is 1360)
	// With the fix: allocates consecutive blocks = 1 extent (succeeds)
	largeContent := make([]byte, numFiles*4096) // ~8MB, needs ~2000 blocks
	for i := range largeContent {
		largeContent[i] = byte(i % 256)
	}
	_, err := env.builder.CreateFile(ext4fs.RootInode, "large_file.bin", largeContent, 0644, 0, 0)
	require.NoError(t, err, "failed to create large file after deletes - likely too many extents due to fragmentation")

	env.finalize()

	// Verify the large file is readable and correct on real Linux kernel
	output := env.dockerExecSimple(
		`stat -c "%s" large_file.bin`,
		`ls -la large_file.bin`,
	)

	expectedSize := fmt.Sprintf("%d", numFiles*4096)
	assert.Contains(t, output, expectedSize, "large file should have correct size")
}

// =============================================================================
// Hardlink Tests — Validation (no Docker needed)
// =============================================================================

func testHardlinkToDirectory(t *testing.T) {
	env := newTestEnv(t, defaultImageSizeMB)

	dir, err := env.builder.CreateDirectory(ext4fs.RootInode, "mydir", 0755, 0, 0)
	require.NoError(t, err)

	err = env.builder.Link(ext4fs.RootInode, "link_to_dir", dir)
	require.Error(t, err)
	assert.Contains(t, err.Error(), "directories are not allowed")

	env.finalize()

	// Verify the rejected link didn't corrupt the image
	env.dockerExecSimple(`test -d "mydir" && echo "dir ok"`)
}

func testHardlinkExistingName(t *testing.T) {
	env := newTestEnv(t, defaultImageSizeMB)

	inode, err := env.builder.CreateFile(ext4fs.RootInode, "file.txt", []byte("hello"), 0644, 0, 0)
	require.NoError(t, err)

	err = env.builder.Link(ext4fs.RootInode, "file.txt", inode)
	require.Error(t, err)
	assert.Contains(t, err.Error(), "already exists")

	env.finalize()

	// Verify the file is intact after the rejected link
	output := env.dockerExecSimple(`cat file.txt`)
	assert.Contains(t, output, "hello")
}

func testHardlinkInvalidName(t *testing.T) {
	env := newTestEnv(t, defaultImageSizeMB)

	inode, err := env.builder.CreateFile(ext4fs.RootInode, "file.txt", []byte("hello"), 0644, 0, 0)
	require.NoError(t, err)

	for _, name := range []string{"", ".", ".."} {
		err = env.builder.Link(ext4fs.RootInode, name, inode)
		assert.Error(t, err, "expected error for name %q", name)
	}

	env.finalize()

	// Verify the image is valid after all rejected links
	output := env.dockerExecSimple(`cat file.txt`)
	assert.Contains(t, output, "hello")
}

func testHardlinkNonExistentInode(t *testing.T) {
	env := newTestEnv(t, defaultImageSizeMB)

	err := env.builder.Link(ext4fs.RootInode, "link", 99999)
	require.Error(t, err)

	env.finalize()

	// Verify the image passes e2fsck after the rejected link
	env.dockerExecSimple(`ls /`)
}

// =============================================================================
// Hardlink Tests — E2E (Docker validation)
// =============================================================================

func testHardlinkBasic(t *testing.T) {
	env := newTestEnv(t, defaultImageSizeMB)

	inode, err := env.builder.CreateFile(ext4fs.RootInode, "original.txt", []byte("shared content"), 0644, 0, 0)
	require.NoError(t, err)

	err = env.builder.Link(ext4fs.RootInode, "link.txt", inode)
	require.NoError(t, err)

	env.finalize()

	output := env.dockerExecSimple(
		`cat original.txt`,
		`cat link.txt`,
		`ORIG=$(stat -c "%i" original.txt) && LINK=$(stat -c "%i" link.txt) && test "$ORIG" = "$LINK" && echo "INODE_MATCH"`,
		`stat -c "LINKCOUNT=%h" original.txt`,
	)

	assert.Contains(t, output, "shared content")
	assert.Contains(t, output, "INODE_MATCH")
	assert.Contains(t, output, "LINKCOUNT=2")
}

func testHardlinkDeleteOne(t *testing.T) {
	env := newTestEnv(t, defaultImageSizeMB)

	inode, err := env.builder.CreateFile(ext4fs.RootInode, "original.txt", []byte("survive delete"), 0644, 0, 0)
	require.NoError(t, err)

	err = env.builder.Link(ext4fs.RootInode, "link.txt", inode)
	require.NoError(t, err)

	err = env.builder.Delete(ext4fs.RootInode, "original.txt")
	require.NoError(t, err)

	env.finalize()

	output := env.dockerExecSimple(
		`test -f "original.txt" && echo "original exists" || echo "original deleted"`,
		`cat link.txt`,
		`stat -c "LINKCOUNT=%h" link.txt`,
	)

	assert.Contains(t, output, "original deleted")
	assert.Contains(t, output, "survive delete")
	assert.Contains(t, output, "LINKCOUNT=1")
}

func testHardlinkDeleteAll(t *testing.T) {
	env := newTestEnv(t, defaultImageSizeMB)

	inode, err := env.builder.CreateFile(ext4fs.RootInode, "file.txt", []byte("will be freed"), 0644, 0, 0)
	require.NoError(t, err)

	err = env.builder.Link(ext4fs.RootInode, "link1.txt", inode)
	require.NoError(t, err)

	err = env.builder.Link(ext4fs.RootInode, "link2.txt", inode)
	require.NoError(t, err)

	// Delete all three names
	err = env.builder.Delete(ext4fs.RootInode, "file.txt")
	require.NoError(t, err)
	err = env.builder.Delete(ext4fs.RootInode, "link1.txt")
	require.NoError(t, err)
	err = env.builder.Delete(ext4fs.RootInode, "link2.txt")
	require.NoError(t, err)

	// Create a new file to confirm blocks were freed (no corruption)
	_, err = env.builder.CreateFile(ext4fs.RootInode, "new_file.txt", []byte("after cleanup"), 0644, 0, 0)
	require.NoError(t, err)

	env.finalize()

	output := env.dockerExecSimple(
		`test -f "file.txt" && echo "file exists" || echo "file deleted"`,
		`test -f "link1.txt" && echo "link1 exists" || echo "link1 deleted"`,
		`test -f "link2.txt" && echo "link2 exists" || echo "link2 deleted"`,
		`cat new_file.txt`,
	)

	assert.Contains(t, output, "file deleted")
	assert.Contains(t, output, "link1 deleted")
	assert.Contains(t, output, "link2 deleted")
	assert.Contains(t, output, "after cleanup")
}

func testHardlinkToSymlink(t *testing.T) {
	env := newTestEnv(t, defaultImageSizeMB)

	_, err := env.builder.CreateFile(ext4fs.RootInode, "target.txt", []byte("target content"), 0644, 0, 0)
	require.NoError(t, err)

	symlinkInode, err := env.builder.CreateSymlink(ext4fs.RootInode, "sym.txt", "target.txt", 0, 0)
	require.NoError(t, err)

	err = env.builder.Link(ext4fs.RootInode, "hardlink_to_sym.txt", symlinkInode)
	require.NoError(t, err)

	env.finalize()

	output := env.dockerExecSimple(
		`echo "SYM_TARGET=$(readlink sym.txt)"`,
		`echo "HARDLINK_TARGET=$(readlink hardlink_to_sym.txt)"`,
		`ORIG=$(stat -c "%i" sym.txt) && LINK=$(stat -c "%i" hardlink_to_sym.txt) && test "$ORIG" = "$LINK" && echo "INODE_MATCH"`,
	)

	assert.Contains(t, output, "SYM_TARGET=target.txt")
	assert.Contains(t, output, "HARDLINK_TARGET=target.txt")
	assert.Contains(t, output, "INODE_MATCH")
}

func testHardlinkMultiple(t *testing.T) {
	env := newTestEnv(t, defaultImageSizeMB)

	inode, err := env.builder.CreateFile(ext4fs.RootInode, "source.txt", []byte("multi-link"), 0644, 0, 0)
	require.NoError(t, err)

	for i := 1; i <= 3; i++ {
		err = env.builder.Link(ext4fs.RootInode, fmt.Sprintf("link_%d.txt", i), inode)
		require.NoError(t, err)
	}

	env.finalize()

	output := env.dockerExecSimple(
		`stat -c "LINKCOUNT=%h" source.txt`,
		`S=$(stat -c "%i" source.txt) && for f in link_1.txt link_2.txt link_3.txt; do L=$(stat -c "%i" "$f"); test "$S" = "$L" || { echo "MISMATCH $f"; exit 1; }; done && echo "ALL_INODES_MATCH"`,
		`cat link_3.txt`,
	)

	assert.Contains(t, output, "LINKCOUNT=4")
	assert.Contains(t, output, "ALL_INODES_MATCH")
	assert.Contains(t, output, "multi-link")
}

func testHardlinkOverwrite(t *testing.T) {
	env := newTestEnv(t, defaultImageSizeMB)

	// Create file, hardlink it, then overwrite original via CreateFile
	inode, err := env.builder.CreateFile(ext4fs.RootInode, "a.txt", []byte("original"), 0644, 0, 0)
	require.NoError(t, err)

	err = env.builder.Link(ext4fs.RootInode, "b.txt", inode)
	require.NoError(t, err)

	// Overwrite a.txt — should update the shared inode in-place (like O_TRUNC)
	_, err = env.builder.CreateFile(ext4fs.RootInode, "a.txt", []byte("updated content"), 0644, 0, 0)
	require.NoError(t, err)

	env.finalize()

	output := env.dockerExecSimple(
		`cat a.txt`,
		`cat b.txt`,
		`stat -c "LINKCOUNT=%h" a.txt`,
		`ORIG=$(stat -c "%i" a.txt) && LINK=$(stat -c "%i" b.txt) && test "$ORIG" = "$LINK" && echo "INODE_MATCH"`,
	)

	// Both names should see the updated content (same inode, in-place overwrite)
	assert.Contains(t, output, "updated content")
	// Link count must still be 2
	assert.Contains(t, output, "LINKCOUNT=2")
	// Same inode number
	assert.Contains(t, output, "INODE_MATCH")
}

func testHardlinkDeleteDirectoryExternal(t *testing.T) {
	env := newTestEnv(t, defaultImageSizeMB)

	// Create /dir/file.txt with a hardlink at /link.txt (outside the dir)
	dir, err := env.builder.CreateDirectory(ext4fs.RootInode, "dir", 0755, 0, 0)
	require.NoError(t, err)

	inode, err := env.builder.CreateFile(dir, "file.txt", []byte("survive rm -rf"), 0644, 0, 0)
	require.NoError(t, err)

	err = env.builder.Link(ext4fs.RootInode, "link.txt", inode)
	require.NoError(t, err)

	// rm -rf /dir — should unlink dir/file.txt (count 2→1), link.txt survives
	err = env.builder.DeleteDirectory(ext4fs.RootInode, "dir")
	require.NoError(t, err)

	env.finalize()

	output := env.dockerExecSimple(
		`test -d "dir" && echo "dir exists" || echo "dir deleted"`,
		`cat link.txt`,
		`stat -c "LINKCOUNT=%h" link.txt`,
	)

	assert.Contains(t, output, "dir deleted")
	assert.Contains(t, output, "survive rm -rf")
	assert.Contains(t, output, "LINKCOUNT=1")
}

func testHardlinkDeleteDirectoryInternal(t *testing.T) {
	env := newTestEnv(t, defaultImageSizeMB)

	// Two names inside the same directory pointing to the same inode
	dir, err := env.builder.CreateDirectory(ext4fs.RootInode, "dir", 0755, 0, 0)
	require.NoError(t, err)

	inode, err := env.builder.CreateFile(dir, "a.txt", []byte("shared data"), 0644, 0, 0)
	require.NoError(t, err)

	err = env.builder.Link(dir, "b.txt", inode)
	require.NoError(t, err)

	// rm -rf /dir — unlinkFile called twice for the same inode (count 2→1→0, then freed)
	err = env.builder.DeleteDirectory(ext4fs.RootInode, "dir")
	require.NoError(t, err)

	// Verify no corruption by creating a new file
	_, err = env.builder.CreateFile(ext4fs.RootInode, "clean.txt", []byte("all good"), 0644, 0, 0)
	require.NoError(t, err)

	env.finalize()

	output := env.dockerExecSimple(
		`test -d "dir" && echo "dir exists" || echo "dir deleted"`,
		`cat clean.txt`,
	)

	assert.Contains(t, output, "dir deleted")
	assert.Contains(t, output, "all good")
}

// =============================================================================
// Volume Label & Resize Tests
// =============================================================================

// testVolumeLabel verifies a custom WithLabel survives to the mounted image and
// is reported by dumpe2fs.
func testVolumeLabel(t *testing.T) {
	env := newTestEnvOpts(t, ext4fs.WithSizeInMB(defaultImageSizeMB), ext4fs.WithLabel("myvolume"))

	_, err := env.builder.CreateFile(ext4fs.RootInode, "marker.txt", []byte("labeled\n"), 0o644, 0, 0)
	require.NoError(t, err)

	env.finalize()

	// Mount + e2fsck validate the image; dumpe2fs reads the label without mounting.
	assert.Contains(t, env.dockerExecSimple(`cat marker.txt`), "labeled")
	assert.Contains(t, env.dumpe2fsHeader(), "myvolume", "dumpe2fs should report the custom volume label")
}

// testResizeShrink builds a 16 GiB canvas (128 groups), fills it, then shrinks
// to MinSize. The resulting image must be exactly MinSize, pass e2fsck, mount,
// and preserve every entry.
func testResizeShrink(t *testing.T) {
	env := newTestEnvOpts(t, ext4fs.WithSizeInMB(16384), ext4fs.WithLabel("shrunk")) // 128 groups, 16 GiB

	writeResizeFixture(t, env.builder)

	minSize := env.builder.MinSize()
	require.NoError(t, env.builder.Resize(minSize))
	require.Equal(t, minSize, env.builder.Size())

	env.finalize()

	info, err := os.Stat(env.imagePath)
	require.NoError(t, err)
	assert.Equal(t, int64(minSize), info.Size(), "image file is exactly MinSize bytes")

	output := env.dockerExecSimple(verifyResizeFixtureCmds()...)
	assertResizeFixture(t, output)
	assert.Contains(t, env.dumpe2fsHeader(), "shrunk")
}

// testResizeShrinkPartial shrinks to a target well above MinSize whose new last
// group is a non-sparse interior boundary (group 2), and confirms the kernel
// sees the leftover space as free.
func testResizeShrinkPartial(t *testing.T) {
	env := newTestEnvOpts(t, ext4fs.WithSizeInMB(512)) // 4 groups

	writeResizeFixture(t, env.builder)

	// 3 groups, last group index 2 (not a sparse-super group), partial.
	target := uint64(2*testBlocksPerGroup+10000) * testBlockSize
	require.NoError(t, env.builder.Resize(target))
	require.Equal(t, target, env.builder.Size())

	env.finalize()

	output := env.dockerExecSimple(append(verifyResizeFixtureCmds(),
		`echo "AVAIL1K=$(df -k . | awk 'NR==2{print $4}')"`,
	)...)
	assertResizeFixture(t, output)
	assert.Greater(t, parseLabeledInt(t, output, "AVAIL1K="), 100_000,
		"partial shrink leaves substantial free space on the mounted filesystem")
}

// testResizeShrinkInodeBound creates enough empty files to spill inodes into a
// higher group than any data block, then shrinks to MinSize. The new last group
// holds inodes but no data, which the kernel must accept; all files survive.
func testResizeShrinkInodeBound(t *testing.T) {
	env := newTestEnvOpts(t, ext4fs.WithSizeInMB(256)) // 2 groups

	const (
		dirs   = 92
		perDir = 90
	)

	want := 0
	for d := 0; d < dirs; d++ {
		dirInode, err := env.builder.CreateDirectory(ext4fs.RootInode, fmt.Sprintf("d%03d", d), 0o755, 0, 0)
		require.NoError(t, err)

		for f := 0; f < perDir; f++ {
			_, err := env.builder.CreateFile(dirInode, fmt.Sprintf("f%03d", f), nil, 0o644, 0, 0)
			require.NoError(t, err)
			want++
		}
	}

	// Inodes have spilled past group 0 (8192 inodes/group), so MinSize is bound
	// by the inode group, not the data blocks.
	minSize := env.builder.MinSize()
	require.NoError(t, env.builder.Resize(minSize))
	require.Equal(t, minSize, env.builder.Size())

	env.finalize()

	output := env.dockerExecSimple(`echo "FILECOUNT=$(find . -type f | wc -l)"`)
	assert.Equal(t, want, parseLabeledInt(t, output, "FILECOUNT="), "all files survive the inode-bound shrink")
}

// testResizeShrinkSparseBoundary shrinks so the new last group is itself a
// sparse-super group (group 9), exercising the backup-superblock rewrite at the
// boundary.
func testResizeShrinkSparseBoundary(t *testing.T) {
	env := newTestEnvOpts(t, ext4fs.WithSizeInMB(2048)) // 16 groups

	writeResizeFixture(t, env.builder)

	// Target a size whose last group index is 9 (a sparse group): just past
	// group 9's start, well above MinSize for the tiny fixture. This makes the
	// new top group an even count of 10 groups with a partial, sparse last group.
	target := uint64(9*testBlocksPerGroup+5000) * testBlockSize
	require.NoError(t, env.builder.Resize(target))
	require.Equal(t, target, env.builder.Size())

	env.finalize()

	output := env.dockerExecSimple(verifyResizeFixtureCmds()...)
	assertResizeFixture(t, output)
}

// testResizeGrow grows a single-group image across the first group boundary
// (1 -> 2 groups), creating the sparse backup for group 1.
func testResizeGrow(t *testing.T) {
	env := newTestEnvOpts(t, ext4fs.WithSizeInMB(64), ext4fs.WithLabel("grown")) // 1 group

	writeResizeFixture(t, env.builder)

	require.NoError(t, env.builder.Resize(256*1024*1024)) // 2 groups
	require.Equal(t, uint64(256*1024*1024), env.builder.Size())

	env.finalize()

	// Label via read-only dumpe2fs (no mount, no mutation).
	assert.Contains(t, env.dumpe2fsHeader(), "grown")

	// The grown space is usable: the kernel can write a 64 MiB file into it. This
	// mutates the image, so it is the last operation on it (e2fsck runs before
	// the write, validating the grown geometry).
	output := env.dockerExecSimple(append(verifyResizeFixtureCmds(),
		`dd if=/dev/zero of=grown.bin bs=1M count=64 2>/dev/null && echo GROW-WRITE-OK`,
	)...)
	assertResizeFixture(t, output)
	assert.Contains(t, output, "GROW-WRITE-OK")
}

// testResizeGrowMultiGroup grows across several group boundaries (2 -> 8 groups),
// adding new sparse-super groups (3, 5, 7).
func testResizeGrowMultiGroup(t *testing.T) {
	env := newTestEnvOpts(t, ext4fs.WithSizeInMB(256)) // 2 groups

	writeResizeFixture(t, env.builder)

	require.NoError(t, env.builder.Resize(1024*1024*1024)) // 8 groups

	env.finalize()

	output := env.dockerExecSimple(verifyResizeFixtureCmds()...)
	assertResizeFixture(t, output)
}

// testResizeGrowAfterShrink shrinks then grows in one build session, exercising
// re-initialization of groups that were previously cut off.
func testResizeGrowAfterShrink(t *testing.T) {
	env := newTestEnvOpts(t, ext4fs.WithSizeInMB(256)) // 2 groups

	writeResizeFixture(t, env.builder)

	require.NoError(t, env.builder.Resize(env.builder.MinSize())) // shrink to 1 group
	require.NoError(t, env.builder.Resize(256*1024*1024))         // grow back to 2 groups

	env.finalize()

	output := env.dockerExecSimple(verifyResizeFixtureCmds()...)
	assertResizeFixture(t, output)
}

// testResizeOpenGrow reopens a saved image and grows it, validating that resize
// works identically on the Open path (state reconstructed from bitmaps).
func testResizeOpenGrow(t *testing.T) {
	env := newTestEnvOpts(t, ext4fs.WithSizeInMB(64), ext4fs.WithLabel("reopen")) // 1 group
	writeResizeFixture(t, env.builder)
	env.finalize()

	reopened, err := ext4fs.Open(ext4fs.WithExistingImagePath(env.imagePath))
	require.NoError(t, err)
	require.NoError(t, reopened.Resize(256*1024*1024)) // 2 groups
	require.NoError(t, reopened.Save())
	require.NoError(t, reopened.Close())

	output := env.dockerExecSimple(verifyResizeFixtureCmds()...)
	assertResizeFixture(t, output)
	assert.Contains(t, env.dumpe2fsHeader(), "reopen", "label preserved through Open+Resize")
}

// testResizeOpenShrink reopens a saved image and shrinks it, validating the
// shrink path on the Open entry (state reconstructed from on-disk bitmaps).
func testResizeOpenShrink(t *testing.T) {
	env := newTestEnvOpts(t, ext4fs.WithSizeInMB(256)) // 2 groups
	writeResizeFixture(t, env.builder)
	env.finalize()

	reopened, err := ext4fs.Open(ext4fs.WithExistingImagePath(env.imagePath))
	require.NoError(t, err)
	require.NoError(t, reopened.Resize(reopened.MinSize())) // collapse to 1 group
	require.NoError(t, reopened.Save())
	require.NoError(t, reopened.Close())

	output := env.dockerExecSimple(verifyResizeFixtureCmds()...)
	assertResizeFixture(t, output)
}

// writeResizeFixture writes a representative tree (file, dir, xattr, hardlink,
// symlink) used by the resize end-to-end tests.
func writeResizeFixture(t *testing.T, b *ext4fs.Image) {
	t.Helper()

	etc, err := b.CreateDirectory(ext4fs.RootInode, "etc", 0o755, 0, 0)
	require.NoError(t, err)

	_, err = b.CreateFile(etc, "hostname", []byte("resized-host\n"), 0o644, 0, 0)
	require.NoError(t, err)

	fileInode, err := b.CreateFile(ext4fs.RootInode, "data.txt", []byte("payload-content\n"), 0o644, 0, 0)
	require.NoError(t, err)

	require.NoError(t, b.SetXattr(fileInode, "user.kind", []byte("fixture")))
	require.NoError(t, b.Link(ext4fs.RootInode, "data.hardlink", fileInode))

	_, err = b.CreateSymlink(ext4fs.RootInode, "data.symlink", "data.txt", 0, 0)
	require.NoError(t, err)
}

// verifyResizeFixtureCmds returns the in-container commands that read back the
// fixture written by writeResizeFixture.
func verifyResizeFixtureCmds() []string {
	return []string{
		`cat etc/hostname`,
		`cat data.txt`,
		`cat data.hardlink`,
		`A=$(stat -c "%i:%h" data.txt) && B=$(stat -c "%i:%h" data.hardlink) && test "$A" = "$B" && echo "HARDLINK-OK:$A"`,
		`readlink data.symlink`,
		`getfattr -n user.kind --only-values data.txt 2>/dev/null && echo`,
		`echo RESIZE-VERIFY-DONE`,
	}
}

// parseLabeledInt extracts the integer from the first "label=N" line in output.
func parseLabeledInt(t *testing.T, output, label string) int {
	t.Helper()

	for _, line := range strings.Split(output, "\n") {
		rest, ok := strings.CutPrefix(strings.TrimSpace(line), label)
		if !ok {
			continue
		}

		n, err := strconv.Atoi(strings.TrimSpace(rest))
		require.NoError(t, err, "parse %q", line)

		return n
	}

	t.Fatalf("label %q not found in output:\n%s", label, output)

	return 0
}

// assertResizeFixture checks the output of verifyResizeFixtureCmds.
func assertResizeFixture(t *testing.T, output string) {
	t.Helper()

	assert.Contains(t, output, "resized-host")
	assert.Contains(t, output, "payload-content") // data.txt and its hardlink
	assert.Contains(t, output, "HARDLINK-OK:")    // shared inode + link count 2
	assert.Contains(t, output, "data.txt")        // symlink target
	assert.Contains(t, output, "fixture")         // xattr value
	assert.Contains(t, output, "RESIZE-VERIFY-DONE")
}

// =============================================================================
// Fingerprint Test
// =============================================================================

// TestFullFeaturesFixtureFingerprint verifies that building the full-features
// filesystem with a fixed createdAt timestamp produces a deterministic image
// whose fingerprint (sha256 of "size:filehash") matches expectedSHA256Hex.
func TestFullFeaturesFixtureFingerprint(t *testing.T) {
	tmpDir := t.TempDir()
	imagePath := filepath.Join(tmpDir, "full_features.img")

	size, fileHash, err := buildAndHashFullFeaturesFixture(imagePath)
	require.NoError(t, err)

	actual := computeFingerprint(size, fileHash)
	assert.Equal(t, expectedSHA256Hex, actual, "fingerprint mismatch: expected=%s actual=%s", expectedSHA256Hex, actual)
}

// =============================================================================
// Test Infrastructure
// =============================================================================

// -----------------------------------------------------------------------------
// Test Environment
// -----------------------------------------------------------------------------

// testEnv encapsulates all resources needed for a single end-to-end test case.
// It manages the temporary image file and ext4fs.Image instance, providing
// convenience methods for finalizing and executing Docker commands.
type testEnv struct {
	t         *testing.T
	imagePath string
	builder   *ext4fs.Image
}

// newTestEnv creates a new test environment with the specified image size.
// The image file is created in the shared host directory (bind-mounted to Docker)
// so it's immediately accessible inside the container without docker cp.
func newTestEnv(t *testing.T, sizeMB int) *testEnv {
	t.Helper()

	require.NotEmpty(t, sharedHostDir, "sharedHostDir must be initialized in TestMain")

	_ = t.TempDir() // still create a per-test temp dir for any future use
	imagePath := filepath.Join(sharedHostDir, fmt.Sprintf("test-%d.img", time.Now().UnixNano()))

	builder, err := ext4fs.New(ext4fs.WithImagePath(imagePath), ext4fs.WithSizeInMB(sizeMB))
	require.NoError(t, err, "failed to create ext4 image builder")

	return &testEnv{
		t:         t,
		imagePath: imagePath,
		builder:   builder,
	}
}

// newTestEnvOpts creates a test environment with arbitrary image options. The
// image path (bind-mounted into Docker) is supplied automatically; callers add
// size, label, etc. Useful for resize and label tests that need WithLabel or an
// over-allocated canvas size.
func newTestEnvOpts(t *testing.T, opts ...ext4fs.ImageOption) *testEnv {
	t.Helper()

	require.NotEmpty(t, sharedHostDir, "sharedHostDir must be initialized in TestMain")

	imagePath := filepath.Join(sharedHostDir, fmt.Sprintf("test-%d.img", time.Now().UnixNano()))

	allOpts := append([]ext4fs.ImageOption{ext4fs.WithImagePath(imagePath)}, opts...)

	builder, err := ext4fs.New(allOpts...)
	require.NoError(t, err, "failed to create ext4 image builder")

	return &testEnv{
		t:         t,
		imagePath: imagePath,
		builder:   builder,
	}
}

// runInContainer runs a shell command inside the long-lived container WITHOUT
// mounting the image. Use it for read-only inspection (e.g. dumpe2fs) that must
// not mutate the artifact under test.
func (e *testEnv) runInContainer(script string) (stdout, stderr string, err error) {
	e.t.Helper()

	if !dockerAvailable || dockerContainerID == "" {
		return "", "", fmt.Errorf("docker test container not available")
	}

	ctx, cancel := context.WithTimeout(context.Background(), 60*time.Second)
	defer cancel()

	cmd := exec.CommandContext(ctx, "docker", "exec", dockerContainerID, "sh", "-c", script)

	var stdoutBuf, stderrBuf bytes.Buffer
	cmd.Stdout = &stdoutBuf
	cmd.Stderr = &stderrBuf

	err = cmd.Run()

	return stdoutBuf.String(), stderrBuf.String(), err
}

// dumpe2fsHeader returns the dumpe2fs superblock header for the image, used to
// assert on-disk properties such as the volume label. It reads the image file
// directly, without mounting, so it cannot mutate the artifact under test.
func (e *testEnv) dumpe2fsHeader() string {
	e.t.Helper()

	remoteImage := filepath.Join(sharedContainerDir, filepath.Base(e.imagePath))

	stdout, stderr, err := e.runInContainer(fmt.Sprintf("dumpe2fs -h %s 2>/dev/null", remoteImage))
	if err != nil {
		e.t.Fatalf("dumpe2fs failed: %v\nstdout: %s\nstderr: %s", err, stdout, stderr)
	}

	return stdout
}

// finalize saves the image and closes the builder, making it ready for mounting.
func (e *testEnv) finalize() {
	e.t.Helper()

	err := e.builder.Save()
	require.NoError(e.t, err, "failed to save image")

	err = e.builder.Close()
	require.NoError(e.t, err, "failed to close builder")
}

// dockerExec runs commands inside the long-lived Docker container with the
// ext4 image mounted. It runs e2fsck for validation, mounts the filesystem,
// executes the provided commands, and returns stdout/stderr.
func (e *testEnv) dockerExec(commands ...string) (stdout, stderr string, err error) {
	e.t.Helper()

	if !dockerAvailable || dockerContainerID == "" {
		return "", "", fmt.Errorf("docker test container not available")
	}

	ctx, cancel := context.WithTimeout(context.Background(), 60*time.Second)
	defer cancel()

	remoteImage := filepath.Join(sharedContainerDir, filepath.Base(e.imagePath))
	mountDir := fmt.Sprintf("/mnt/ext4-%d", time.Now().UnixNano())

	script := buildMountScript(remoteImage, mountDir, commands)

	cmd := exec.CommandContext(ctx, "docker", "exec", "--privileged", dockerContainerID, "sh", "-c", script)

	var stdoutBuf, stderrBuf bytes.Buffer
	cmd.Stdout = &stdoutBuf
	cmd.Stderr = &stderrBuf

	err = cmd.Run()

	if ctx.Err() == context.DeadlineExceeded {
		return stdoutBuf.String(), stderrBuf.String(), fmt.Errorf("docker exec timed out after 60s")
	}

	return stdoutBuf.String(), stderrBuf.String(), err
}

// dockerExecSimple runs commands in Docker and returns combined stdout output.
// It fails the test immediately if any command returns an error.
func (e *testEnv) dockerExecSimple(commands ...string) string {
	e.t.Helper()

	stdout, stderr, err := e.dockerExec(commands...)
	if err != nil {
		e.t.Fatalf("docker exec failed: %v\nstdout: %s\nstderr: %s", err, stdout, stderr)
	}

	return stdout
}

// -----------------------------------------------------------------------------
// Docker Container Management
// -----------------------------------------------------------------------------

// startDockerContainer starts a privileged Alpine container with the shared
// host directory mounted and necessary tools installed.
func startDockerContainer() (string, error) {
	volumeArg := fmt.Sprintf("%s:%s", sharedHostDir, sharedContainerDir)

	cmd := exec.Command(
		"docker", "run", "-d", "--privileged", "-v", volumeArg, dockerImage,
		"sleep", "infinity",
	)

	var stdout, stderr bytes.Buffer
	cmd.Stdout = &stdout
	cmd.Stderr = &stderr

	if err := cmd.Run(); err != nil {
		return "", fmt.Errorf("docker run failed: %w (stderr: %s)", err, stderr.String())
	}

	containerID := strings.TrimSpace(stdout.String())

	installCmd := exec.Command(
		"docker", "exec", containerID,
		"apk", "add", "--no-cache", "e2fsprogs", "e2fsprogs-extra", "attr", "acl", "libcap",
	)

	if err := installCmd.Run(); err != nil {
		_ = exec.Command("docker", "rm", "-f", containerID).Run()
		return "", fmt.Errorf("failed to install packages: %w", err)
	}

	return containerID, nil
}

// stopDockerContainer stops and removes the test container.
// This is best-effort cleanup; failures here should not mask test results.
func stopDockerContainer(id string) {
	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()

	_ = exec.CommandContext(ctx, "docker", "stop", "-t", "5", id).Run()
	_ = exec.CommandContext(ctx, "docker", "rm", id).Run()
}

// skipIfNoDocker skips the test if the shared Docker container is not available.
func skipIfNoDocker(t *testing.T) {
	t.Helper()

	if !dockerAvailable || dockerContainerID == "" {
		t.Skip("Docker test container not available, skipping e2e test")
	}
}

// -----------------------------------------------------------------------------
// Script Builder
// -----------------------------------------------------------------------------

// buildMountScript generates a shell script that mounts the ext4 image,
// runs e2fsck, executes the specified commands, and cleans up.
func buildMountScript(imagePath, mountDir string, commands []string) string {
	return fmt.Sprintf(`
set -e

mkdir -p %[2]s

cleanup() {
	umount %[2]s 2>/dev/null || umount -l %[2]s 2>/dev/null || true
}
trap cleanup EXIT

e2fsck -n -f %[1]s || { echo "e2fsck failed"; exit 1; }

mount -t ext4 -o loop %[1]s %[2]s

cd %[2]s
%[3]s
`, imagePath, mountDir, strings.Join(commands, "\n"))
}

// -----------------------------------------------------------------------------
// Fixture Helpers
// -----------------------------------------------------------------------------

// buildAndHashFullFeaturesFixture builds the deterministic fixture image
// and returns its size and sha256 hash.
func buildAndHashFullFeaturesFixture(imagePath string) (size uint64, hash string, err error) {
	_ = os.Remove(imagePath)

	img, err := ext4fs.New(
		ext4fs.WithImagePath(imagePath),
		ext4fs.WithSizeInMB(fixtureSizeMB),
		ext4fs.WithCreatedAt(fixturesCreatedAt),
	)
	if err != nil {
		return 0, "", fmt.Errorf("failed to create image: %w", err)
	}

	defer func() {
		_ = img.Close()
		_ = os.Remove(imagePath)
	}()

	if err := buildFullFeaturesFixture(img); err != nil {
		return 0, "", fmt.Errorf("fixture build failed: %w", err)
	}

	if err := img.Save(); err != nil {
		return 0, "", fmt.Errorf("failed to save image: %w", err)
	}

	info, err := os.Stat(imagePath)
	if err != nil {
		return 0, "", fmt.Errorf("failed to stat image %q: %w", imagePath, err)
	}

	f, err := os.Open(imagePath)
	if err != nil {
		return 0, "", fmt.Errorf("failed to open image %q: %w", imagePath, err)
	}
	defer func() {
		_ = f.Close()
	}()

	h := sha256.New()
	if _, err := io.Copy(h, f); err != nil {
		return 0, "", fmt.Errorf("failed to hash image %q: %w", imagePath, err)
	}

	return uint64(info.Size()), hex.EncodeToString(h.Sum(nil)), nil
}

// buildFullFeaturesFixture populates the image with the standard fixture layout.
func buildFullFeaturesFixture(b *ext4fs.Image) error {
	root := uint32(ext4fs.RootInode)

	etcInode, err := b.CreateDirectory(root, "etc", 0o755, 0, 0)
	if err != nil {
		return fmt.Errorf("failed to create /etc: %w", err)
	}

	if _, err := b.CreateFile(etcInode, "hostname", []byte("ext4-fixture\n"), 0o644, 0, 0); err != nil {
		return fmt.Errorf("failed to create /etc/hostname: %w", err)
	}

	homeInode, err := b.CreateDirectory(root, "home", 0o755, 0, 0)
	if err != nil {
		return fmt.Errorf("failed to create /home: %w", err)
	}

	userInode, err := b.CreateDirectory(homeInode, "user", 0o700, 1000, 1000)
	if err != nil {
		return fmt.Errorf("failed to create /home/user: %w", err)
	}

	if _, err := b.CreateFile(userInode, "note.txt", []byte("hello from ext4 fixtures\n"), 0o600, 1000, 1000); err != nil {
		return fmt.Errorf("failed to create /home/user/note.txt: %w", err)
	}

	if err := b.SetXattr(userInode, "user.comment", []byte("example user directory")); err != nil {
		return fmt.Errorf("failed to set xattr on /home/user: %w", err)
	}

	return nil
}

// computeFingerprint computes the sha256 of "size:filehash".
func computeFingerprint(size uint64, fileHash string) string {
	h := sha256.New()
	_, _ = fmt.Fprintf(h, "%d:%s", size, fileHash)
	return hex.EncodeToString(h.Sum(nil))
}
