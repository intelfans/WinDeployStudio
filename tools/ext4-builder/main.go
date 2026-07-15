package main

import (
	crand "crypto/rand"
	"encoding/hex"
	"errors"
	"flag"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"strings"

	ext4fs "github.com/pilat/go-ext4fs"
)

const (
	minimumSizeMB = 4
	maximumSizeMB = 4095
)

func main() {
	output := flag.String("output", "", "absolute output image path on a local drive")
	sizeMB := flag.Int("size-mb", 0, "image size in MiB")
	label := flag.String("label", "", "ext4 volume label (1-16 printable ASCII bytes)")
	debianPersistence := flag.Bool("debian-persistence", false, "write /persistence.conf containing / union")
	flag.Parse()

	if flag.NArg() != 0 {
		fail(errors.New("positional arguments are not supported"))
	}
	if err := createImage(*output, *sizeMB, *label, *debianPersistence); err != nil {
		fail(err)
	}
}

func createImage(output string, sizeMB int, label string, debianPersistence bool) error {
	if sizeMB < minimumSizeMB || sizeMB > maximumSizeMB {
		return fmt.Errorf("size-mb must be between %d and %d", minimumSizeMB, maximumSizeMB)
	}
	if !isValidLabel(label) {
		return errors.New("label must contain 1-16 printable ASCII bytes")
	}
	output, err := validateOutputPath(output)
	if err != nil {
		return err
	}

	var imageUUID [16]byte
	if _, err := io.ReadFull(crand.Reader, imageUUID[:]); err != nil {
		return fmt.Errorf("generate ext4 UUID: %w", err)
	}
	imageUUID[6] = (imageUUID[6] & 0x0f) | 0x40
	imageUUID[8] = (imageUUID[8] & 0x3f) | 0x80

	tempOutput, err := siblingTemporaryPath(output)
	if err != nil {
		return err
	}
	removeTemporary := true
	defer func() {
		if removeTemporary {
			_ = os.Remove(tempOutput)
		}
	}()

	image, err := ext4fs.New(
		ext4fs.WithImagePath(tempOutput),
		ext4fs.WithSizeInMB(sizeMB),
		ext4fs.WithLabel(label),
		ext4fs.WithUUID(imageUUID),
	)
	if err != nil {
		return fmt.Errorf("create ext4 image: %w", err)
	}
	closed := false
	defer func() {
		if !closed {
			_ = image.Close()
		}
	}()

	if debianPersistence {
		if _, err := image.CreateFile(
			ext4fs.RootInode,
			"persistence.conf",
			[]byte("/ union\n"),
			0644,
			0,
			0,
		); err != nil {
			return fmt.Errorf("write Debian persistence configuration: %w", err)
		}
	}
	if err := image.Save(); err != nil {
		return fmt.Errorf("finalize ext4 image: %w", err)
	}
	if err := image.Close(); err != nil {
		return fmt.Errorf("close ext4 image: %w", err)
	}
	closed = true

	if err := os.Rename(tempOutput, output); err != nil {
		return fmt.Errorf("publish ext4 image: %w", err)
	}
	removeTemporary = false
	return nil
}

func validateOutputPath(output string) (string, error) {
	if output == "" {
		return "", errors.New("output is required")
	}
	clean := filepath.Clean(output)
	if !filepath.IsAbs(clean) {
		return "", errors.New("output must be an absolute local-drive path")
	}
	volume := filepath.VolumeName(clean)
	if len(volume) != 2 || volume[1] != ':' {
		return "", errors.New("output must be on a local drive letter")
	}
	lower := strings.ToLower(clean)
	if strings.HasPrefix(lower, `\\.\`) || strings.HasPrefix(lower, `\\?\`) {
		return "", errors.New("device namespace paths are not allowed")
	}
	if _, err := os.Lstat(clean); err == nil {
		return "", errors.New("output must not already exist")
	} else if !os.IsNotExist(err) {
		return "", fmt.Errorf("inspect output: %w", err)
	}
	directory := filepath.Dir(clean)
	info, err := os.Stat(directory)
	if err != nil {
		return "", fmt.Errorf("inspect output directory: %w", err)
	}
	if !info.IsDir() {
		return "", errors.New("output parent is not a directory")
	}
	return clean, nil
}

func siblingTemporaryPath(output string) (string, error) {
	var token [8]byte
	if _, err := io.ReadFull(crand.Reader, token[:]); err != nil {
		return "", fmt.Errorf("generate temporary filename: %w", err)
	}
	return filepath.Join(
		filepath.Dir(output),
		"."+filepath.Base(output)+".wds-"+hex.EncodeToString(token[:])+".tmp",
	), nil
}

func isValidLabel(label string) bool {
	if len(label) == 0 || len(label) > 16 {
		return false
	}
	for _, value := range []byte(label) {
		if value < 0x20 || value > 0x7e {
			return false
		}
	}
	return true
}

func fail(err error) {
	fmt.Fprintln(os.Stderr, "wds-ext4-builder:", err)
	os.Exit(1)
}
