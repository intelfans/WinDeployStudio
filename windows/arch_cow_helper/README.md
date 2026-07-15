# Arch COW Partition Helper

`wds_arch_cow_helper.exe` creates the bounded ext4 COW filesystem used by the
Arch Linux To Go profile. It is a native part of the Windows application rather
than an imported formatter or a redistributed Linux utility.

## Safety Contract

The helper requires all of the following values. It rejects omitted, repeated,
or unrecognised arguments.

```text
--disk-number N
--disk-guid GPT-DISK-GUID
--partition-number N
--partition-guid GPT-PARTITION-GUID
--partition-offset-bytes N
--partition-size-bytes N
--parent-pid N
```

Before writing, it verifies the physical disk number and GPT disk GUID, then
requires the selected partition number, GPT partition GUID, Linux filesystem
partition type, starting offset, and length to match exactly. It opens only
`\\.\HarddiskNPartitionM` for writing; it never writes through a
`\\.\PhysicalDriveN` handle. The partition device number, length, sector
alignment, writability, and exclusive lock are checked before formatting. The
same GPT identity is checked again after formatting.

The formatter accepts only a 4 MiB to 16 GiB, 4 KiB-aligned partition and
creates a minimal ext4 filesystem labelled `WDS_ARCH_COW`. It also creates
`/wds-arch` for the matching `cow_directory=wds-arch` ArchISO boot parameter.
After flushing, it reads back and validates the ext4 superblock and root inode.
`--self-test` exercises the in-memory layout and superblock invariants without
opening any disk device.

No ArchISO, KIWI, e2fsprogs, or other GPL component is bundled or invoked.
The on-disk ext4 layout is implemented locally from the published ext4 format.
