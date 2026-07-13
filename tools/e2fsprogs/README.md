# e2fsprogs Compliance Gate

This release deliberately contains no `mke2fs.exe`, e2fsprogs binary, Cygwin
runtime, or other ext4 creator. Linux To Go persistence therefore remains
disabled until a reproducible and license-compliant toolchain is available.

The previously evaluated binary was a Google-signed Windows x86 Android SDK
build reporting `mke2fs 1.47.2 (1-Jan-2025)` and
`android-platform-15.0.0_r5-314-ga1f793f6b`. It was removed because the project
did not possess the complete corresponding source required for GPLv2
redistribution, including its exact build scripts and all statically linked
components.

`mke2fs` is GPL-2.0-only. A future release may include it only as a separate
command-line component, never linked into the Flutter application, and only if
all of the following are shipped together:

1. The exact tool binary and SHA-256.
2. The full GPLv2 text and all notices for every linked component.
3. Complete corresponding source for that exact binary, including patches,
   configuration, build scripts, toolchain inputs, and static dependencies.
4. A stable, immutable release URL for that source plus a real three-year
   written source offer from the project publisher.
5. Automated build and packaging checks that fail when any required item is
   absent.

References for audit only, not as a substitute for corresponding source:

- e2fsprogs project: https://e2fsprogs.sourceforge.net/
- AOSP commit: https://android.googlesource.com/platform/external/e2fsprogs/+/a1f793f6b1d0d063c7252704e11c475d3040ce85
- GPLv2 section 3: https://www.gnu.org/licenses/old-licenses/gpl-2.0.en.html
