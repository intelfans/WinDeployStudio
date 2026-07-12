# Changelog

All notable changes to WinDeploy Studio are documented here.

## v2.0.0

### New Features

- Added a unified deployment plan and a five-step Windows To Go workflow covering image, disk, deployment method, advanced options, and a complete preflight summary.
- Added explicit UEFI + GPT, UEFI + MBR, and Legacy BIOS selection for Windows installation media and To Go, together with preferred partition drive letters and custom volume labels/icons.
- Added direct, dynamic/fixed VHD, and dynamic/fixed VHDX Windows To Go deployment with compatibility checks, virtual-disk BCD binding, and optional stale drive-letter repair.
- Made Windows To Go policies configurable: local-disk SAN policy, OOBE/Audit behavior, WinRE, UASP, CompactOS, WIMBoot, and .NET Framework 3.5. UEFI deployments automatically use NTFS Windows storage backed by a separate FAT32 EFI partition.
- Added verified offline Windows INF injection and optional first-boot staging of vetted Linux packages, matching kernel modules, and explicit scripts for supported x64 Ubuntu/casper Linux To Go images. This does not add arbitrary-distribution Linux To Go support.
- Added one consistent Windows 11-inspired interface with aligned native title-bar styling and responsive deployment navigation.
- Added a top-level Disk Tools workspace with read-only Windows/NVMe diagnostics and guarded external-disk UEFI/BIOS boot repair with preflight, typed confirmation, BCD backup, and post-repair verification.
- Added automatic benchmark history, detail views, date filtering, two-result comparison, deletion controls, and CSV/JSON export.

### Improvements

- Expanded the native benchmark protocol with sequential and 4K random reads, mixed read/write scenarios, IOPS, latency percentiles, and cache-behavior analysis while retaining unbuffered, write-through I/O.
- Added compatibility blockers for unsupported deployment combinations, including Windows 7 VHDX, Windows 7 native VHD outside Enterprise/Ultimate, x86 Windows 7 UEFI, WIMBoot outside direct Windows 8.1 deployment, CompactOS outside Windows 10/11, and virtual disks below 32 GB.
- Added a dedicated responsive deployment shell and clearer top-level navigation for advanced deployment and disk-management workflows.
- Made the Windows To Go / Linux To Go mode selector more prominent and placed it directly in the workflow path.

### Fixes

- Fixed Linux To Go creation failing when a modern Ubuntu ISO contains a squashfs file larger than the FAT32 single-file limit.
- Replaced the single FAT32 LTG layout with a dedicated FAT32 boot/persistence partition and an NTFS Live-data partition.
- Added pre-erase validation for the bundled `mke2fs.exe`, patchable casper GRUB entries, FAT32 boot-file limits, and target capacity.
- Added partition-identity checks and per-file copy verification for both LTG partitions.
- Added fail-closed physical disk identity checks using serial number, device path, and UniqueId fallbacks, plus per-disk operation locks.
- Added language-independent partition-layout postconditions before Windows/Linux media deployment continues.
- Changed Linux ISOHybrid verification from sampled blocks to a full byte-for-byte comparison of the written image.
- Hardened WebView downloads with validator-aware resume, strict length checks, and fixed user-selected paths.
- Required both the GitHub Release asset digest and valid Authenticode publisher verification before an update installer can run.
- Enforced HTTPS-only AI proxy settings and protected local chat history directly with Windows DPAPI.
- Replaced the unclear localized-text-unavailable error shown for a mismatched To Go ISO with a direct, actionable format prompt.
- Unified the CJK font-pack card and detail-page icon as a wrench/tool symbol.

### Maintenance

- Removed the unused Windows 10, Windows 7, automatic-style selection paths and their settings/localization code.
- Updated app, Windows metadata, installer, scripts, README, and handover notes to version 2.0.0.

## v1.1.2

### Improvements

- Improved disk enumeration by parsing structured PowerShell JSON with real partition metadata.
- Improved To Go drive-letter reservation by checking both Windows volumes and file-system PSDrives before assigning temporary letters.
- Reduced repeated Enterprise/LTSC prompts in Image Center; the expert notice is now shown at the download action point.
- Added explicit community image download log entries in the requested `[CommunityDownload]` format.
- Updated app, Windows metadata, installer, scripts, README, handover notes, and release notes to version 1.1.2.

### Fixes

- Fixed removable disk diagnostics showing partition count as `0` because partitions were never populated.
- Fixed fragile hand-written JSON parsing in disk detection that could lose nested values.
- Fixed To Go temporary drive-letter selection relying on `Directory.existsSync`, which could miss occupied or special drive letters.
- Fixed unsigned project installers being blocked by the in-app updater while retaining signature-status logging.
- Fixed duplicate Russian installer custom messages.
- Fixed `scripts/build_windows.ps1` to use the same `flutter analyze --no-fatal-infos` behavior as the installer build.

### Notes

To Go creation and Windows installation media creation behavior remain unchanged except for safer drive-letter handling and more complete disk metadata.

## v1.1.1

### Improvements

- Refined Image Center LTSC descriptions across all 11 supported languages.
- Updated Windows 10 Enterprise LTSC wording to avoid implying the image is "based on itself".
- Clarified LTSC entries as long-term servicing channel deployment resources.
- Updated the Windows 10 Enterprise LTSC 123 Cloud mirror link.
- Updated app, Windows metadata, installer, scripts, README, and release notes to version 1.1.1.

### Fixes

- Fixed awkward/self-referential LTSC wording in every localized Windows 10 Enterprise LTSC detail page.
- Fixed stale v1.1.0 references in installer output naming and documentation.

### Notes

This is a small polish and consistency release focused on Image Center wording, LTSC mirror accuracy, and release metadata alignment.

## v1.1.0

### New Features

- Added Image Center top-level categories:
  - Official Microsoft
  - Community Images
- Added official Microsoft download flow for Windows 10 and Windows 11.
  - Shows a confirmation dialog.
  - Opens Microsoft official download pages in the system browser.
  - Does not use mirror selection, WebView2, China mirror, or GoFile mirror.
- Added community image trust labels and descriptions.
- Added StarValleyX language filter.
  - Visible only in Simplified Chinese and Traditional Chinese.
  - Hidden in English, Japanese, Korean, German, French, Spanish, Portuguese, Russian, and Arabic.
- Added advanced tool safety levels:
  - Beginner
  - Advanced
  - Expert
- Added professional warnings for DISM++, Windhawk, expert-level tools, and activation-related utilities.
- Added Sysinternals Suite to Toolbox.
- Added AI Assistant Notice with local "Do not show again" preference.
- Added MIT-friendly installer Open Source Notice.
- Added Special Thanks section in About and installer acknowledgement text.
- Added To Go waiting mini-game during image application.

### Improvements

- Renamed the Windows installation media feature to a clearer beginner-friendly name.
- Improved Image Center trust and transparency by separating official Microsoft sources from community-maintained images.
- Improved To Go progress UI by showing only reliable elapsed time during image application.
- Improved To Go compatibility detection by using selected disk metadata as fallback source of truth.
- Improved installer licensing language to align with MIT License.
- Updated version numbers across the app, Windows metadata, installer, scripts, and documentation to 1.1.0.
- Removed default download source selection from Settings and cleaned related UI remnants.
- Replaced project website entry in the app with focused repository/contact information.
- Improved AI connection error text to avoid unreadable placeholder characters.

### Fixes

- Fixed external USB/NVMe disks sometimes showing `0 B`, `Unknown`, and `N/A` in the To Go compatibility card.
- Fixed To Go image application details showing misleading written size, write speed, and remaining size values.
- Fixed low-speed warning appearing based on unreliable synthetic progress data.
- Fixed English navigation labels showing localization keys such as `nav_xxx`.
- Fixed text clipping in recommendation and tool cards.
- Fixed stale Settings UI where removed download source options could still appear.
- Fixed installer version and metadata consistency for v1.1.0.
- Fixed several mojibake and placeholder text issues in user-facing messages.

### Removed

- Removed inactive AdBlock-related code path for now.
- Removed default mirror/source selection setting from the app.
- Removed restrictive installer EULA wording incompatible with MIT License.

### Notes

Official Microsoft images now always redirect users to Microsoft's official download websites. Community images remain available through the existing mirror-based flow.

To Go creation behavior was intentionally kept stable. The v1.1.0 To Go progress change only affects display logic: unreliable synthetic write metrics were removed from the UI, while the creation pipeline remains unchanged.

## v1.0.2

### New Features

- Added To Go real-time progress metrics dashboard.
- Added elapsed time, write speed, written size, and remaining size display during imaging.
- Added Markdown rendering for update release notes.
- Added browser download button in the update dialog.

### Improvements

- Improved To Go progress calculation and UI responsiveness.
- Improved update dialog readability.
- Updated project version to 1.0.2.

### Fixes

- Fixed inaccurate remaining time estimation in the To Go module.
- Fixed UI lag when updating progress under high-speed write conditions.
- Fixed mismatch between displayed and actual written size in some cases.

## v1.0.1

### New Features

- Added manual mirror selection for image downloads.
- Added China and Global mirror options.

### Improvements

- Improved download experience.
- Improved auto update flow.
- Improved general UI polish.

## v1.0.0

### Initial Release

- Windows installation media creation.
- Windows To Go creation.
- Image Center.
- Toolbox.
- AI Assistant.
- Log Center.
- 11-language UI.
- Auto update support.
