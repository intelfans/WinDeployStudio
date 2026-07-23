# Changelog

All notable changes to WinDeploy Studio are documented here.

## v2.1.0

Released: 2026-07-22

This is the first public feature release after v1.1.2 and includes the
cumulative work completed across the 2.0 development series.

### Installation Media

- Split Windows and Linux installation-media creation into clear, independent
  workflows with dedicated validation, progress, safety guidance, and results.
- Added Windows ISO preflight for real Setup layouts, WIM/ESD/SWM metadata,
  BIOS and UEFI boot files, EFI architecture, FAT32 single-file limits, and
  bounded mount/unmount operations.
- Added UEFI + GPT, UEFI + MBR, and Legacy BIOS layouts for Windows media,
  together with validated drive letters, volume labels, and custom icons.
- Added Linux ISOHybrid structural validation, raw whole-disk writing,
  cancellation and recovery handling, and full byte-for-byte verification.
  Linux media preserves the image's own boot layout and does not add
  persistence or convert firmware modes.
- Added clearer Linux boot-capability reporting and guidance for firmware that
  lists one USB through multiple similar boot entries.

### Windows To Go

- Rebuilt Windows To Go as a guided image, disk, deployment, options, summary,
  and execution workflow with compatibility checks before destructive work.
- Added direct, dynamic/fixed VHD, and dynamic/fixed VHDX deployment where the
  selected Windows generation supports them, including virtual-disk BCD
  binding and optional drive-letter repair.
- Added guarded settings for local-disk visibility, simplified first run,
  UASP fallback, CompactOS, WIMBoot, .NET Framework 3.5, driver injection, and
  deployment drive letters, with incompatible combinations blocked early.
- Added independent elapsed-time tracking, resilient progress restoration when
  navigating away, and a draggable/collapsible global operation-status panel.
- Clarified that Windows 10 and Windows 11 are the currently verified normal
  creation scope. Windows 7/8/8.1 and Server remain best-effort and may need
  matching drivers, updates, firmware modes, or recovery tools.
- Portable Linux workspaces are planned for a future release and are not
  available in this version. Linux installation-media creation remains
  available.

### Drive Testing And Disk Tools

- Added a native unbuffered, write-through benchmark with Quick, Standard,
  Extreme, and Full Write modes; sequential, 4K, multithread, mixed-load,
  latency, stability, and cache-behavior analysis; and live workload charts.
- Added saved history, date filtering, multi-selection, cross-drive comparison,
  selected-record deletion, and localized CSV, JSON, and self-contained HTML
  exports with device identity, complete data, and separated charts.
- Added read-only disk diagnostics for Windows storage, ATA SMART, NVMe health,
  and supported USB bridge paths, with honest Unknown/N/A fallbacks when the
  controller does not expose data.
- Added guarded BCD/EFI repair for revalidated external non-system Windows
  disks, including typed confirmation, backup, rollback, and post-repair checks.
- Added a Windows image-format conversion assistant under Disk Tools. It can
  rebuild a verified ISO from a complete Setup folder, replace compatible
  WIM/ESD/SWM install images using matching base media, and read VHD/VHDX
  sources in read-only mode. Linux Live/ISOHybrid/RAW/IMG/DD images are
  intentionally rejected and remain on the byte-for-byte installation-media
  path. The result is remounted, validated, hashed, and available directly to
  Installation Media or Windows To Go.

### Home, Images, And Downloads

- Redesigned Home with a denser quick-start layout, recent images, storage
  overview, clear-history action, and user-selectable/reorderable modules.
- Expanded Image Library metadata, source and experience classifications,
  language notices, local ISO discovery, published SHA-256/MD5 values, and
  silent known-image identification in Installation Media and Windows To Go.
- Added Microsoft official download routing, 123 Cloud options for Chinese
  users, and managed Global Mirror downloads with an in-app destination picker,
  progress, cancellation, resume checks, and trusted HTTPS boundaries.
- Added a bilingual light/dark project website with responsive image and
  release download pages, Markdown release notes, screenshots, and direct
  access to the same published resources.

### AI Assistant And Updates

- Added provider-neutral OpenAI-compatible configuration for a custom HTTPS
  endpoint, protected API key, and model selection while retaining a built-in
  default service with locked default fields.
- Improved streaming and non-streaming protocol compatibility, cancellation,
  network/proxy discovery, tool-call handling, bounded public web search,
  source filtering, Markdown normalization, and removal of raw tool/citation
  artifacts from user-facing replies.
- Updated product knowledge and first-choice guidance for current Image
  Library, Installation Media, Windows To Go, Disk Test, Disk Tools, feedback,
  and App Tour behavior.
- Added provider-independent client-side output screening and Windows DPAPI
  protection for locally stored AI configuration and chat data.
- Rebuilt update discovery around GitHub Releases with Global Mirror and GitHub
  download choices, bilingual release-note selection, resilient metadata
  fallback, and visible download progress.
- Added HTTPS allowlists, concurrent-download isolation, published SHA-256
  verification, file-size checks, and Authenticode status checks before an
  update installer is launched.

### Experience, Localization, And Safety

- Added a production first-run App Tour with complete and single-section replay,
  secondary-page guidance, free exploration time, and automatic display on the
  first launch of each app version.
- Refined the Windows 11-inspired responsive interface, navigation, typography,
  card density, title bar, narrow-screen layouts, animations, and waiting views.
- Completed application and installer coverage for all 11 supported languages:
  Simplified Chinese, Traditional Chinese, English, French, German, Spanish,
  Portuguese, Russian, Arabic, Korean, and Japanese.
- Added Settings feedback and failure-only reporting actions that open the
  project's GitHub Issue form without automatically uploading private data.
- Added physical-disk identity revalidation, per-disk operation locks,
  in-memory PowerShell execution, explicit Windows system environments,
  timeouts, cancellation, RAW-volume recovery, structured logs, and safer
  cleanup across deployment workflows.
- The Windows application now requests administrator approval at startup so
  destructive workflows do not need scattered elevation buttons or prompts.
- Updated user documentation, third-party notices, website copy, installer
  text, AI guidance, tests, and version metadata for the current feature set.

## v2.0.9

### Reliability, Integrity, and Deployment Safety

- Strengthened Windows installation-media preflight for WIM, ESD, and split
  SWM images, BIOS/UEFI boot files, EFI architecture, FAT32 constraints, and
  bounded ISO mount/unmount operations.
- Added Linux ISOHybrid structural preflight and cancellation handling while
  preserving the selected ISO's own boot and partition layout during writing.
- Hardened ISO selection against overlapping scans and cancellation races so a
  stale result cannot replace a newer user choice.
- Hardened update downloads by requiring the GitHub Release asset SHA-256
  digest before installation and comparing mirror downloads against that same
  trusted digest.
- Improved download cancellation, timeout handling, and known-image
  verification without weakening HTTPS and trusted-host boundaries.
- Isolated AI streaming generations, bounded local image scans, selected the
  correct benchmark volume for multi-partition devices, and fixed empty-log ZIP
  export behavior.

### User Documentation

- Updated release metadata and the README with the current version and the
  automated-update integrity model.
- Clarified that the released Windows application requests UAC approval at
  startup and performs its disk and boot operations in one elevated process.
## v2.0.6

- Updated the application, Windows metadata, installer, build script, and documentation to version 2.0.6.

## v2.0.0

### New Features

- Added a unified deployment plan and a five-step Windows To Go workflow covering image, disk, deployment method, advanced options, and a complete preflight summary.
- Added explicit UEFI + GPT, UEFI + MBR, and Legacy BIOS selection for Windows installation media and To Go, together with preferred partition drive letters and custom volume labels/icons.
- Added direct, dynamic/fixed VHD, and dynamic/fixed VHDX Windows To Go deployment with compatibility checks, virtual-disk BCD binding, and optional stale drive-letter repair.
- Made Windows To Go policies configurable: local-disk SAN policy, OOBE/Audit behavior, WinRE, UASP, CompactOS, WIMBoot, and .NET Framework 3.5. UEFI deployments automatically use NTFS Windows storage backed by a separate FAT32 EFI partition.
- Added one consistent Windows 11-inspired interface with aligned native title-bar styling and responsive deployment navigation.
- Added a top-level Disk Tools workspace with read-only Windows/NVMe diagnostics and guarded external-disk UEFI/BIOS boot repair with preflight, typed confirmation, BCD backup, and post-repair verification.
- Added automatic benchmark history, detail views, date filtering, two-result comparison, deletion controls, and CSV/JSON export.

### Improvements

- Expanded the native benchmark protocol with sequential and 4K random reads, mixed read/write scenarios, IOPS, latency percentiles, and cache-behavior analysis while retaining unbuffered, write-through I/O.
- Added compatibility blockers for unsupported deployment combinations, including Windows 7 VHDX, Windows 7 native VHD outside Enterprise/Ultimate, x86 Windows 7 UEFI, WIMBoot outside direct Windows 8.1 deployment, CompactOS outside Windows 10/11, and virtual disks below 32 GB.
- Added a dedicated responsive deployment shell and clearer top-level navigation for advanced deployment and disk-management workflows.

### Fixes

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
