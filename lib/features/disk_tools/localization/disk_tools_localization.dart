import 'package:flutter/widgets.dart';

import '../../../core/localization/strings.dart';

String diskToolsText(BuildContext context, String key) => tr(context, key);

String diskToolsTextWith(
  BuildContext context,
  String key,
  Map<String, String> values,
) {
  var text = diskToolsText(context, key);
  for (final entry in values.entries) {
    text = text.replaceAll('{${entry.key}}', entry.value);
  }
  return text;
}

const diskToolsEnglish = <String, String>{
  'disk_tools_title': 'Disk tools',
  'disk_tools_subtitle':
      'Native Windows diagnostics and guarded boot repair for external disks.',
  'disk_tools_diagnostics_title': 'Disk diagnostics',
  'disk_tools_diagnostics_desc':
      'Read identity, health, temperature, reliability, and NVMe lifetime counters.',
  'disk_tools_boot_repair_title': 'BCD / EFI boot repair',
  'disk_tools_boot_repair_desc':
      'Repair boot files on a verified external Windows disk without formatting it.',
  'disk_tools_open': 'Open',
  'disk_tools_refresh': 'Refresh',
  'disk_tools_close': 'Close',
  'disk_tools_cancel': 'Cancel',
  'disk_tools_continue': 'Continue',
  'disk_tools_copy': 'Copy',
  'disk_tools_copied': 'Copied to the clipboard.',
  'disk_tools_value_unknown': 'Unknown / unavailable',
  'disk_tools_value_none': 'None',
  'disk_tools_yes': 'Yes',
  'disk_tools_no': 'No',
  'disk_tools_passed': 'Passed',
  'disk_tools_failed': 'Failed',
  'disk_tools_error_windows_only': 'This feature is available on Windows only.',
  'disk_diag_title': 'Disk diagnostics',
  'disk_diag_subtitle':
      'Values come from native Windows storage APIs and read-only NVMe protocol queries.',
  'disk_diag_collecting': 'Collecting native Windows disk data...',
  'disk_diag_no_disks': 'Windows did not report any physical disks.',
  'disk_diag_error': 'Disk diagnostics could not be collected.',
  'disk_diag_admin_cancelled': 'Administrator access was cancelled.',
  'disk_diag_admin_hint':
      'Some storage drivers expose reliability counters only to administrators.',
  'disk_diag_scan_admin': 'Scan as administrator',
  'disk_diag_admin_active': 'Administrator scan',
  'disk_diag_standard_active': 'Standard scan',
  'disk_diag_select_disk': 'Physical disk',
  'disk_diag_copy_report': 'Copy report',
  'disk_diag_report_copied': 'Diagnostic report copied.',
  'disk_diag_external': 'External',
  'disk_diag_internal': 'Internal',
  'disk_diag_system': 'System',
  'disk_diag_section_identity': 'Identity and interface',
  'disk_diag_section_health': 'Health and reliability',
  'disk_diag_section_lifetime': 'Lifetime counters',
  'disk_diag_section_topology': 'Disk state and topology',
  'disk_diag_model': 'Model',
  'disk_diag_capacity': 'Capacity',
  'disk_diag_serial': 'Serial number',
  'disk_diag_unique_id': 'Unique ID',
  'disk_diag_bus': 'Interface / bus',
  'disk_diag_vid': 'USB vendor ID (VID)',
  'disk_diag_pid': 'USB product ID (PID)',
  'disk_diag_firmware': 'Firmware',
  'disk_diag_media_type': 'Media type',
  'disk_diag_health': 'Windows health status',
  'disk_diag_health_unknown_note':
      'Windows did not expose a trustworthy health state. No health claim is made.',
  'disk_diag_temperature': 'Temperature',
  'disk_diag_remaining_life': 'Estimated remaining life',
  'disk_diag_remaining_life_note':
      'Shown only when Windows reports wear used; calculated as 100% minus wear.',
  'disk_diag_wear': 'Wear used',
  'disk_diag_read_errors_corrected': 'Read errors corrected',
  'disk_diag_read_errors_uncorrected': 'Read errors uncorrected',
  'disk_diag_read_errors_total': 'Read errors total',
  'disk_diag_write_errors_corrected': 'Write errors corrected',
  'disk_diag_write_errors_uncorrected': 'Write errors uncorrected',
  'disk_diag_write_errors_total': 'Write errors total',
  'disk_diag_power_on_hours': 'Power-on time',
  'disk_diag_host_reads': 'Lifetime host reads',
  'disk_diag_host_writes': 'Lifetime host writes',
  'disk_diag_host_read_commands': 'Host read commands',
  'disk_diag_host_write_commands': 'Host write commands',
  'disk_diag_media_errors': 'Media / data integrity errors',
  'disk_diag_partition_style': 'Partition style',
  'disk_diag_operational_status': 'Operational status',
  'disk_diag_mounts': 'Mounted volumes',
  'disk_diag_device_path': 'Device path',
  'disk_diag_pnp_id': 'PnP device ID',
  'disk_diag_offline': 'Offline',
  'disk_diag_read_only': 'Read-only',
  'disk_diag_removable': 'Removable media flag',
  'disk_diag_source_cim': 'Windows CIM / Storage Management',
  'disk_diag_source_reliability': 'Storage Reliability Counter',
  'disk_diag_source_nvme': 'Native Windows NVMe health log',
  'disk_diag_source_native': 'Native Windows storage APIs',
  'disk_diag_source_calculated': 'Calculated from a native counter',
  'disk_diag_unavailable_note':
      'Unknown means Windows or the storage bridge did not expose the value. It is never estimated.',
  'boot_repair_title': 'BCD / EFI boot repair',
  'boot_repair_subtitle':
      'Repair only a selected external Windows disk. This workflow never formats or clears a disk.',
  'boot_repair_loading':
      'Scanning external volumes for Windows installations...',
  'boot_repair_error_discovery':
      'External Windows volumes could not be scanned.',
  'boot_repair_error_preflight': 'The boot repair preflight could not run.',
  'boot_repair_error_preflight_failed':
      'Preflight did not pass. The repair was not started.',
  'boot_repair_error_preflight_timeout': 'Boot repair preflight timed out.',
  'boot_repair_error_execution': 'The boot repair process could not start.',
  'boot_repair_error_execution_timeout': 'The boot repair process timed out.',
  'boot_repair_error_invalid_response':
      'Windows returned an invalid boot repair response.',
  'boot_repair_error_disk_busy':
      'Another WinDeploy Studio operation is using this disk.',
  'boot_repair_no_windows_volumes':
      'No external volume containing a Windows directory was found.',
  'boot_repair_no_windows_volumes_hint':
      'Connect the external Windows disk, unlock it if encrypted, then refresh.',
  'boot_repair_source_volume': 'Windows system volume',
  'boot_repair_physical_disk': 'Bound physical disk',
  'boot_repair_firmware': 'Firmware mode',
  'boot_repair_firmware_uefi': 'UEFI',
  'boot_repair_firmware_bios': 'Legacy BIOS',
  'boot_repair_target_volume': 'EFI / system boot volume',
  'boot_repair_select_source': 'Select an external Windows volume',
  'boot_repair_select_firmware': 'Select firmware mode',
  'boot_repair_select_target': 'Select a compatible target volume',
  'boot_repair_no_compatible_target':
      'The selected disk has no compatible existing boot volume for this firmware mode.',
  'boot_repair_binding_title': 'Bound target preview',
  'boot_repair_binding_disk': 'Physical disk',
  'boot_repair_binding_identity': 'Disk identity binding',
  'boot_repair_identity_serial': 'Serial number',
  'boot_repair_identity_unique': 'Unique ID',
  'boot_repair_identity_path': 'Device path',
  'boot_repair_identity_pnp': 'PnP device ID',
  'boot_repair_binding_windows': 'Windows volume',
  'boot_repair_binding_target': 'Boot volume',
  'boot_repair_binding_partition': 'Partition',
  'boot_repair_binding_filesystem': 'File system',
  'boot_repair_binding_size': 'Size',
  'boot_repair_run_preflight': 'Run preflight',
  'boot_repair_preflight_running': 'Revalidating disk and volume bindings...',
  'boot_repair_preflight_title': 'Preflight results',
  'boot_repair_preflight_passed':
      'All checks passed. Review the plan before continuing.',
  'boot_repair_preflight_failed':
      'One or more checks failed. Nothing was changed.',
  'boot_repair_plan_title': 'Planned actions',
  'boot_repair_command_preview': 'Command preview',
  'boot_repair_plan_revalidate':
      'Revalidate the external physical disk and both volume GUID bindings as administrator.',
  'boot_repair_plan_mount':
      'Temporarily assign unused drive letters only when a selected volume has none.',
  'boot_repair_plan_backup':
      'Back up the existing BCD store, or record that no store exists.',
  'boot_repair_plan_bcdboot':
      'Run the Windows system bcdboot.exe against the selected volumes.',
  'boot_repair_plan_fallback':
      'Create the architecture-correct EFI fallback from bootmgfw.efi when absent.',
  'boot_repair_plan_verify':
      'Verify the BCD store, boot manager, and required EFI fallback.',
  'boot_repair_plan_unmount': 'Remove every temporary drive letter.',
  'boot_repair_warning_no_format':
      'No partition is created, deleted, cleared, or formatted.',
  'boot_repair_warning_boot_change':
      'Boot files on the selected external disk will be changed.',
  'boot_repair_review_title': 'Review boot repair',
  'boot_repair_review_body':
      'Confirm that disk {disk}, Windows volume {windows}, and boot volume {target} are the intended external device.',
  'boot_repair_final_confirm_title': 'Final confirmation',
  'boot_repair_final_confirm_body':
      'Type REPAIR to authorize BCD and boot-file changes on the selected external disk.',
  'boot_repair_confirm_word': 'REPAIR',
  'boot_repair_confirm_label': 'Confirmation',
  'boot_repair_execute': 'Repair boot files',
  'boot_repair_executing':
      'Backing up BCD, running bcdboot, and verifying boot files...',
  'boot_repair_result_cancelled': 'Administrator access was cancelled.',
  'boot_repair_result_success':
      'Boot repair completed and verification passed.',
  'boot_repair_result_failed':
      'Boot repair did not pass verification. Review the technical log.',
  'boot_repair_result_title': 'Repair result',
  'boot_repair_backup_title': 'BCD backup',
  'boot_repair_backup_created': 'Existing BCD backed up before bcdboot',
  'boot_repair_backup_not_present':
      'No existing BCD was present; a marker was saved before bcdboot',
  'boot_repair_backup_path': 'Backup folder',
  'boot_repair_log_path': 'Technical log',
  'boot_repair_open_logs': 'Open log folder',
  'boot_repair_copy_log': 'Copy technical log',
  'boot_repair_log_copied': 'Technical log copied.',
  'boot_repair_verification_title': 'Verification',
  'boot_repair_verify_bcd_exists': 'BCD store exists',
  'boot_repair_verify_bcd_readable': 'BCD store is readable',
  'boot_repair_verify_boot_manager': 'Boot manager exists',
  'boot_repair_verify_fallback': 'EFI fallback exists',
  'boot_repair_verify_not_required': 'Not required for Legacy BIOS',
  'boot_repair_check_unknown': 'Unknown check',
  'boot_repair_check_disk_binding': 'Physical disk identity is unchanged',
  'boot_repair_check_external_disk': 'Disk remains a safe external disk',
  'boot_repair_check_windows_binding': 'Windows volume binding is unchanged',
  'boot_repair_check_target_binding': 'Boot volume binding is unchanged',
  'boot_repair_check_windows_directory': 'Windows directory is present',
  'boot_repair_check_same_disk': 'Source and target are on the bound disk',
  'boot_repair_check_writable': 'Target is writable',
  'boot_repair_check_firmware_target': 'Target matches the firmware mode',
  'boot_repair_check_windows_tools': 'Windows boot tools are available',
  'boot_repair_check_detail_passed': 'Verified.',
  'boot_repair_check_detail_failed': 'Could not be verified.',
  'boot_repair_check_detail_disk_changed':
      'The selected physical disk identity changed or is unavailable.',
  'boot_repair_check_detail_not_safe_external':
      'The disk is no longer external, online, non-system, and non-boot.',
  'boot_repair_check_detail_volume_changed':
      'The partition offset or volume GUID no longer matches the selection.',
  'boot_repair_check_detail_windows_missing':
      'The selected volume no longer contains Windows and Windows\\System32.',
  'boot_repair_check_detail_cross_disk':
      'Both selected volumes must stay on the same bound external disk.',
  'boot_repair_check_detail_read_only':
      'The selected disk or target is read-only.',
  'boot_repair_check_detail_firmware_mismatch':
      'UEFI needs a FAT32 GPT ESP; BIOS needs an active MBR NTFS/FAT32 partition.',
  'boot_repair_check_detail_tools_missing':
      'The Windows system bcdboot.exe or bcdedit.exe is unavailable.',
};
