enum DeploymentPlatform { windows, linux }

enum DeploymentPurpose { installMedia, toGo }

enum DeploymentBootMode { uefiGpt, uefiMbr, legacyBios }

enum DeploymentMode { direct, vhd, vhdx }

enum VirtualDiskType { dynamic, fixed }

enum WindowsGeneration { unknown, windows7, windows81, windows10, windows11 }

enum CompatibilitySeverity { info, warning, error }

class DeploymentIssue {
  final String code;
  final CompatibilitySeverity severity;
  final String messageKey;

  const DeploymentIssue({
    required this.code,
    required this.severity,
    required this.messageKey,
  });
}

class DeploymentCompatibilityReport {
  final List<DeploymentIssue> issues;

  const DeploymentCompatibilityReport(this.issues);

  bool get canDeploy =>
      !issues.any((issue) => issue.severity == CompatibilitySeverity.error);

  List<DeploymentIssue> get errors => issues
      .where((issue) => issue.severity == CompatibilitySeverity.error)
      .toList(growable: false);

  List<DeploymentIssue> get warnings => issues
      .where((issue) => issue.severity == CompatibilitySeverity.warning)
      .toList(growable: false);
}

class DeploymentPlan {
  final DeploymentPlatform platform;
  final DeploymentPurpose purpose;
  final String imagePath;
  final int imageIndex;
  final String imageName;
  final String imageEdition;
  final String imageBuild;
  final String imageArchitecture;
  final WindowsGeneration windowsGeneration;
  final DeploymentBootMode bootMode;
  final DeploymentMode deploymentMode;
  final VirtualDiskType virtualDiskType;
  final int virtualDiskSizeGb;
  final String virtualDiskFileName;
  final bool blockLocalDisks;
  final bool skipOobe;
  final bool disableWinRe;
  final bool disableUasp;
  final bool compactOs;
  final bool wimBoot;
  final bool fixVhdDriveLetter;
  final bool enableNetFx3;
  final bool ntfsUefiSupport;
  final String preferredSystemLetter;
  final String preferredBootLetter;
  final String driverDirectory;
  final String customIconPath;
  final String customVolumeLabel;

  const DeploymentPlan({
    required this.platform,
    required this.purpose,
    required this.imagePath,
    this.imageIndex = 1,
    this.imageName = '',
    this.imageEdition = '',
    this.imageBuild = '',
    this.imageArchitecture = '',
    this.windowsGeneration = WindowsGeneration.unknown,
    this.bootMode = DeploymentBootMode.uefiGpt,
    this.deploymentMode = DeploymentMode.direct,
    this.virtualDiskType = VirtualDiskType.dynamic,
    this.virtualDiskSizeGb = 64,
    this.virtualDiskFileName = 'WinDeploy.vhdx',
    this.blockLocalDisks = true,
    this.skipOobe = false,
    this.disableWinRe = false,
    this.disableUasp = false,
    this.compactOs = false,
    this.wimBoot = false,
    this.fixVhdDriveLetter = false,
    this.enableNetFx3 = false,
    this.ntfsUefiSupport = false,
    this.preferredSystemLetter = '',
    this.preferredBootLetter = '',
    this.driverDirectory = '',
    this.customIconPath = '',
    this.customVolumeLabel = '',
  });

  bool get isWindows => platform == DeploymentPlatform.windows;
  bool get isLinux => platform == DeploymentPlatform.linux;
  bool get isToGo => purpose == DeploymentPurpose.toGo;
  bool get usesVirtualDisk => deploymentMode != DeploymentMode.direct;
  bool get usesNtfsUefiLayout =>
      isWindows && isToGo && bootMode != DeploymentBootMode.legacyBios;

  DeploymentPlan copyWith({
    DeploymentPlatform? platform,
    DeploymentPurpose? purpose,
    String? imagePath,
    int? imageIndex,
    String? imageName,
    String? imageEdition,
    String? imageBuild,
    String? imageArchitecture,
    WindowsGeneration? windowsGeneration,
    DeploymentBootMode? bootMode,
    DeploymentMode? deploymentMode,
    VirtualDiskType? virtualDiskType,
    int? virtualDiskSizeGb,
    String? virtualDiskFileName,
    bool? blockLocalDisks,
    bool? skipOobe,
    bool? disableWinRe,
    bool? disableUasp,
    bool? compactOs,
    bool? wimBoot,
    bool? fixVhdDriveLetter,
    bool? enableNetFx3,
    bool? ntfsUefiSupport,
    String? preferredSystemLetter,
    String? preferredBootLetter,
    String? driverDirectory,
    String? customIconPath,
    String? customVolumeLabel,
  }) {
    return DeploymentPlan(
      platform: platform ?? this.platform,
      purpose: purpose ?? this.purpose,
      imagePath: imagePath ?? this.imagePath,
      imageIndex: imageIndex ?? this.imageIndex,
      imageName: imageName ?? this.imageName,
      imageEdition: imageEdition ?? this.imageEdition,
      imageBuild: imageBuild ?? this.imageBuild,
      imageArchitecture: imageArchitecture ?? this.imageArchitecture,
      windowsGeneration: windowsGeneration ?? this.windowsGeneration,
      bootMode: bootMode ?? this.bootMode,
      deploymentMode: deploymentMode ?? this.deploymentMode,
      virtualDiskType: virtualDiskType ?? this.virtualDiskType,
      virtualDiskSizeGb: virtualDiskSizeGb ?? this.virtualDiskSizeGb,
      virtualDiskFileName: virtualDiskFileName ?? this.virtualDiskFileName,
      blockLocalDisks: blockLocalDisks ?? this.blockLocalDisks,
      skipOobe: skipOobe ?? this.skipOobe,
      disableWinRe: disableWinRe ?? this.disableWinRe,
      disableUasp: disableUasp ?? this.disableUasp,
      compactOs: compactOs ?? this.compactOs,
      wimBoot: wimBoot ?? this.wimBoot,
      fixVhdDriveLetter: fixVhdDriveLetter ?? this.fixVhdDriveLetter,
      enableNetFx3: enableNetFx3 ?? this.enableNetFx3,
      ntfsUefiSupport: ntfsUefiSupport ?? this.ntfsUefiSupport,
      preferredSystemLetter:
          preferredSystemLetter ?? this.preferredSystemLetter,
      preferredBootLetter: preferredBootLetter ?? this.preferredBootLetter,
      driverDirectory: driverDirectory ?? this.driverDirectory,
      customIconPath: customIconPath ?? this.customIconPath,
      customVolumeLabel: customVolumeLabel ?? this.customVolumeLabel,
    );
  }

  Map<String, dynamic> toJson() => {
    'platform': platform.name,
    'purpose': purpose.name,
    'imagePath': imagePath,
    'imageIndex': imageIndex,
    'imageName': imageName,
    'imageEdition': imageEdition,
    'imageBuild': imageBuild,
    'imageArchitecture': imageArchitecture,
    'windowsGeneration': windowsGeneration.name,
    'bootMode': bootMode.name,
    'deploymentMode': deploymentMode.name,
    'virtualDiskType': virtualDiskType.name,
    'virtualDiskSizeGb': virtualDiskSizeGb,
    'virtualDiskFileName': virtualDiskFileName,
    'blockLocalDisks': blockLocalDisks,
    'skipOobe': skipOobe,
    'disableWinRe': disableWinRe,
    'disableUasp': disableUasp,
    'compactOs': compactOs,
    'wimBoot': wimBoot,
    'fixVhdDriveLetter': fixVhdDriveLetter,
    'enableNetFx3': enableNetFx3,
    'ntfsUefiSupport': ntfsUefiSupport,
    'preferredSystemLetter': preferredSystemLetter,
    'preferredBootLetter': preferredBootLetter,
    'driverDirectory': driverDirectory,
    'customIconPath': customIconPath,
    'customVolumeLabel': customVolumeLabel,
  };

  factory DeploymentPlan.fromJson(Map<String, dynamic> json) {
    T enumValue<T extends Enum>(List<T> values, String key, T fallback) {
      final name = json[key]?.toString();
      return values.where((value) => value.name == name).firstOrNull ??
          fallback;
    }

    return DeploymentPlan(
      platform: enumValue(
        DeploymentPlatform.values,
        'platform',
        DeploymentPlatform.windows,
      ),
      purpose: enumValue(
        DeploymentPurpose.values,
        'purpose',
        DeploymentPurpose.toGo,
      ),
      imagePath: json['imagePath']?.toString() ?? '',
      imageIndex: (json['imageIndex'] as num?)?.toInt() ?? 1,
      imageName: json['imageName']?.toString() ?? '',
      imageEdition: json['imageEdition']?.toString() ?? '',
      imageBuild: json['imageBuild']?.toString() ?? '',
      imageArchitecture: json['imageArchitecture']?.toString() ?? '',
      windowsGeneration: enumValue(
        WindowsGeneration.values,
        'windowsGeneration',
        WindowsGeneration.unknown,
      ),
      bootMode: enumValue(
        DeploymentBootMode.values,
        'bootMode',
        DeploymentBootMode.uefiGpt,
      ),
      deploymentMode: enumValue(
        DeploymentMode.values,
        'deploymentMode',
        DeploymentMode.direct,
      ),
      virtualDiskType: enumValue(
        VirtualDiskType.values,
        'virtualDiskType',
        VirtualDiskType.dynamic,
      ),
      virtualDiskSizeGb: (json['virtualDiskSizeGb'] as num?)?.toInt() ?? 64,
      virtualDiskFileName:
          json['virtualDiskFileName']?.toString() ?? 'WinDeploy.vhdx',
      blockLocalDisks: json['blockLocalDisks'] as bool? ?? true,
      skipOobe: json['skipOobe'] as bool? ?? false,
      disableWinRe: json['disableWinRe'] as bool? ?? false,
      disableUasp: json['disableUasp'] as bool? ?? false,
      compactOs: json['compactOs'] as bool? ?? false,
      wimBoot: json['wimBoot'] as bool? ?? false,
      fixVhdDriveLetter: json['fixVhdDriveLetter'] as bool? ?? false,
      enableNetFx3: json['enableNetFx3'] as bool? ?? false,
      ntfsUefiSupport: json['ntfsUefiSupport'] as bool? ?? false,
      preferredSystemLetter: json['preferredSystemLetter']?.toString() ?? '',
      preferredBootLetter: json['preferredBootLetter']?.toString() ?? '',
      driverDirectory: json['driverDirectory']?.toString() ?? '',
      customIconPath: json['customIconPath']?.toString() ?? '',
      customVolumeLabel: json['customVolumeLabel']?.toString() ?? '',
    );
  }

  static WindowsGeneration detectWindowsGeneration({
    String build = '',
    String version = '',
  }) {
    final buildNumber = int.tryParse(
      RegExp(r'\d+').firstMatch(build)?.group(0) ?? '',
    );
    if (buildNumber != null) {
      if (buildNumber >= 22000) return WindowsGeneration.windows11;
      if (buildNumber >= 10240) return WindowsGeneration.windows10;
      if (buildNumber == 9600) return WindowsGeneration.windows81;
      if (buildNumber >= 7600 && buildNumber < 9200) {
        return WindowsGeneration.windows7;
      }
    }
    final normalized = version.toLowerCase();
    if (normalized.contains('windows 11')) return WindowsGeneration.windows11;
    if (normalized.contains('windows 10')) return WindowsGeneration.windows10;
    if (normalized.contains('8.1')) return WindowsGeneration.windows81;
    if (normalized.contains('windows 7')) return WindowsGeneration.windows7;
    return WindowsGeneration.unknown;
  }
}

class DeploymentCompatibility {
  const DeploymentCompatibility._();

  static DeploymentCompatibilityReport evaluate(DeploymentPlan plan) {
    final issues = <DeploymentIssue>[];
    void error(String code, String key) => issues.add(
      DeploymentIssue(
        code: code,
        severity: CompatibilitySeverity.error,
        messageKey: key,
      ),
    );
    void warning(String code, String key) => issues.add(
      DeploymentIssue(
        code: code,
        severity: CompatibilitySeverity.warning,
        messageKey: key,
      ),
    );

    if (plan.imagePath.trim().isEmpty) {
      error('image_missing', 'deploy_compat_image_missing');
    }

    if (plan.isLinux) {
      if (plan.deploymentMode != DeploymentMode.direct) {
        error('linux_virtual_disk', 'deploy_compat_linux_direct_only');
      }
      if (plan.wimBoot ||
          plan.compactOs ||
          plan.enableNetFx3 ||
          plan.ntfsUefiSupport ||
          plan.skipOobe ||
          plan.disableWinRe ||
          plan.disableUasp ||
          plan.fixVhdDriveLetter ||
          plan.preferredSystemLetter.isNotEmpty ||
          plan.preferredBootLetter.isNotEmpty) {
        error('linux_windows_options', 'deploy_compat_linux_windows_options');
      }
      if (plan.driverDirectory.isNotEmpty) {
        warning('linux_driver_staging', 'deploy_compat_linux_driver_staging');
      }
      _validateSharedIdentity(plan, error);
      return DeploymentCompatibilityReport(issues);
    }

    if (plan.purpose == DeploymentPurpose.installMedia &&
        plan.deploymentMode != DeploymentMode.direct) {
      error('install_virtual_disk', 'deploy_compat_install_direct_only');
    }

    if (plan.windowsGeneration == WindowsGeneration.windows7) {
      if (plan.deploymentMode == DeploymentMode.vhdx) {
        error('win7_vhdx', 'deploy_compat_win7_no_vhdx');
      }
      if (plan.imageArchitecture.toLowerCase().contains('x86') &&
          plan.bootMode != DeploymentBootMode.legacyBios) {
        error('win7_x86_uefi', 'deploy_compat_win7_x86_legacy');
      }
      if (plan.deploymentMode == DeploymentMode.vhd &&
          !supportsWindows7NativeVhdEdition(
            plan.imageEdition,
            imageName: plan.imageName,
          )) {
        error('win7_vhd_edition', 'deploy_compat_win7_vhd_edition');
      }
    }

    final architecture = plan.imageArchitecture.trim().toLowerCase().replaceAll(
      '-',
      '',
    );
    if ((architecture.contains('arm64') || architecture == 'arm') &&
        plan.bootMode != DeploymentBootMode.uefiGpt) {
      error('arm_requires_uefi_gpt', 'deploy_compat_arm_requires_uefi_gpt');
    }

    if (plan.usesVirtualDisk &&
        plan.windowsGeneration == WindowsGeneration.unknown) {
      error('unknown_virtual_disk', 'deploy_compat_unknown_virtual_disk');
    }

    if (plan.wimBoot &&
        (plan.windowsGeneration != WindowsGeneration.windows81 ||
            plan.deploymentMode != DeploymentMode.direct)) {
      error('wimboot_scope', 'deploy_compat_wimboot_scope');
    }

    if (plan.compactOs &&
        plan.windowsGeneration != WindowsGeneration.windows10 &&
        plan.windowsGeneration != WindowsGeneration.windows11) {
      error('compact_scope', 'deploy_compat_compact_scope');
    }

    if (plan.fixVhdDriveLetter && !plan.usesVirtualDisk) {
      warning('fix_letter_direct', 'deploy_compat_fix_letter_vhd_only');
    }

    if (plan.ntfsUefiSupport &&
        plan.bootMode == DeploymentBootMode.legacyBios) {
      error('ntfs_uefi_legacy', 'deploy_compat_ntfs_uefi_requires_uefi');
    }

    if (plan.virtualDiskSizeGb < 32 && plan.usesVirtualDisk) {
      error('vhd_too_small', 'deploy_compat_vhd_too_small');
    }

    if (plan.usesVirtualDisk) {
      final fileName = plan.virtualDiskFileName.trim();
      final expectedExtension = plan.deploymentMode == DeploymentMode.vhd
          ? '.vhd'
          : '.vhdx';
      if (!_isSafeFileName(fileName)) {
        error('vhd_invalid_name', 'deploy_compat_vhd_invalid_name');
      } else if (!fileName.toLowerCase().endsWith(expectedExtension)) {
        error('vhd_wrong_extension', 'deploy_compat_vhd_wrong_extension');
      }
    }

    final systemLetter = _normalizeLetter(plan.preferredSystemLetter);
    final bootLetter = _normalizeLetter(plan.preferredBootLetter);
    if (systemLetter != null && systemLetter == bootLetter) {
      error('duplicate_letters', 'deploy_compat_duplicate_letters');
    }
    if ((plan.preferredSystemLetter.isNotEmpty && systemLetter == null) ||
        (plan.preferredBootLetter.isNotEmpty && bootLetter == null)) {
      error('invalid_letter', 'deploy_compat_invalid_letter');
    }

    _validateSharedIdentity(plan, error);

    return DeploymentCompatibilityReport(issues);
  }

  static List<DeploymentMode> deploymentModesFor(DeploymentPlan plan) {
    if (plan.isLinux || plan.purpose == DeploymentPurpose.installMedia) {
      return const [DeploymentMode.direct];
    }
    if (plan.windowsGeneration == WindowsGeneration.windows7) {
      return supportsWindows7NativeVhdEdition(
            plan.imageEdition,
            imageName: plan.imageName,
          )
          ? const [DeploymentMode.direct, DeploymentMode.vhd]
          : const [DeploymentMode.direct];
    }
    if (plan.windowsGeneration == WindowsGeneration.unknown) {
      return const [DeploymentMode.direct];
    }
    return DeploymentMode.values;
  }

  static bool supportsWimBoot(DeploymentPlan plan) =>
      plan.isWindows &&
      plan.windowsGeneration == WindowsGeneration.windows81 &&
      plan.deploymentMode == DeploymentMode.direct;

  static bool supportsCompactOs(DeploymentPlan plan) =>
      plan.isWindows &&
      (plan.windowsGeneration == WindowsGeneration.windows10 ||
          plan.windowsGeneration == WindowsGeneration.windows11);

  static bool supportsWindows7NativeVhdEdition(
    String edition, {
    String imageName = '',
  }) {
    final editionId = edition.trim().toLowerCase().replaceAll(
      RegExp(r'[^a-z0-9]'),
      '',
    );
    if (editionId.isNotEmpty) {
      return editionId.startsWith('enterprise') ||
          editionId.startsWith('ultimate');
    }

    final name = imageName.trim().toLowerCase();
    const supportedNames = [
      'enterprise',
      'ultimate',
      '企业版',
      '企業版',
      '旗舰版',
      '旗艦版',
    ];
    return supportedNames.any(name.contains);
  }

  static String? _normalizeLetter(String value) {
    final normalized = value
        .trim()
        .replaceAll(RegExp(r'[:\\]'), '')
        .toUpperCase();
    return RegExp(r'^[D-Z]$').hasMatch(normalized) ? normalized : null;
  }

  static void _validateSharedIdentity(
    DeploymentPlan plan,
    void Function(String code, String key) error,
  ) {
    final label = plan.customVolumeLabel.trim();
    final labelLimit = plan.purpose == DeploymentPurpose.installMedia ? 11 : 32;
    if (label.length > labelLimit ||
        RegExp(r'[\\/:*?"<>|\x00-\x1F]').hasMatch(label)) {
      error('invalid_volume_label', 'deploy_compat_invalid_volume_label');
    }

    final iconPath = plan.customIconPath.trim();
    if (iconPath.isNotEmpty && !iconPath.toLowerCase().endsWith('.ico')) {
      error('invalid_icon', 'deploy_compat_invalid_icon');
    }
  }

  static bool _isSafeFileName(String value) {
    if (value.isEmpty || value == '.' || value == '..') return false;
    if (value.endsWith('.') || value.endsWith(' ')) return false;
    return !RegExp(r'[\\/:*?"<>|\x00-\x1F]').hasMatch(value);
  }
}
