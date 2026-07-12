import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:win_deploy_studio/app/visual_style.dart';
import 'package:win_deploy_studio/core/services/disk_safety_service.dart';
import 'package:win_deploy_studio/core/services/elevation_service.dart';
import 'package:win_deploy_studio/features/deployment/models/deployment_plan.dart';

void main() {
  test('elevated task serialization preserves disk identity and plan', () {
    const disk = DiskInfo(
      diskNumber: 7,
      model: 'Portable SSD',
      friendlyName: 'Portable SSD USB Device',
      sizeBytes: 1000204886016,
      sizeFormatted: '931.5 GB',
      serialNumber: 'SERIAL-1234',
      uniqueId: 'USB\\VID_1234&PID_5678',
      devicePath: r'\\?\PhysicalDrive7',
      busType: 'USB',
      partitionStyle: 'GPT',
      isRemovable: true,
      driveLetters: ['R:'],
      partitions: [
        DiskPartition(
          type: 'Basic',
          sizeBytes: 1000000000000,
          driveLetter: 'R:',
        ),
      ],
    );
    const plan = DeploymentPlan(
      platform: DeploymentPlatform.windows,
      purpose: DeploymentPurpose.toGo,
      imagePath: r'D:\Images\Windows.iso',
      imageIndex: 6,
      windowsGeneration: WindowsGeneration.windows11,
      bootMode: DeploymentBootMode.uefiGpt,
      deploymentMode: DeploymentMode.vhdx,
      virtualDiskSizeGb: 96,
      skipOobe: true,
      driverDirectory: r'D:\Drivers',
      preferredSystemLetter: 'R',
      preferredBootLetter: 'S',
    );
    const task = ElevatedTaskSpec(
      kind: ElevatedTaskKind.windowsToGo,
      disk: disk,
      isoPath: r'D:\Images\Windows.iso',
      localeCode: 'zh_TW',
      appearance: AppAppearanceSettings(
        themeMode: ThemeMode.dark,
        visualStyle: VisualStyle.win7,
        accentColor: Color(0xFF008272),
        fontFamily: 'Microsoft YaHei UI',
      ),
      imageIndex: 6,
      deploymentPlan: plan,
      progressPath: r'C:\Temp\progress.json',
      cancelPath: r'C:\Temp\cancel',
      resultPath: r'C:\Temp\result',
    );

    final decoded = ElevatedTaskSpec.decode(task.encode());

    expect(decoded.kind, task.kind);
    expect(decoded.localeCode, 'zh_TW');
    expect(decoded.appearance?.themeMode, ThemeMode.dark);
    expect(decoded.appearance?.visualStyle, VisualStyle.win7);
    expect(decoded.appearance?.accentColor, const Color(0xFF008272));
    expect(decoded.appearance?.fontFamily, 'Microsoft YaHei UI');
    expect(decoded.disk.toJson(), disk.toJson());
    expect(decoded.deploymentPlan?.toJson(), plan.toJson());
    expect(decoded.progressPath, task.progressPath);
    expect(decoded.cancelPath, task.cancelPath);
    expect(decoded.resultPath, task.resultPath);
    expect(decoded.validationIssueKey(), isNull);
  });

  test(
    'elevated task validation rejects a mismatched platform and purpose',
    () {
      const task = ElevatedTaskSpec(
        kind: ElevatedTaskKind.windowsToGo,
        disk: DiskInfo(
          diskNumber: 4,
          model: 'USB Disk',
          friendlyName: 'USB Disk',
          sizeBytes: 64000000000,
          sizeFormatted: '59.6 GB',
        ),
        isoPath: r'D:\Images\Linux.iso',
        localeCode: 'en',
        deploymentPlan: DeploymentPlan(
          platform: DeploymentPlatform.linux,
          purpose: DeploymentPurpose.installMedia,
          imagePath: r'D:\Images\Linux.iso',
        ),
      );

      expect(task.validationIssueKey(), 'deploy_compat_task_mismatch');
    },
  );

  test('elevated task validation rejects a mismatched image path', () {
    const task = ElevatedTaskSpec(
      kind: ElevatedTaskKind.windowsInstall,
      disk: DiskInfo(
        diskNumber: 4,
        model: 'USB Disk',
        friendlyName: 'USB Disk',
        sizeBytes: 64000000000,
        sizeFormatted: '59.6 GB',
      ),
      isoPath: r'D:\Images\Windows.iso',
      localeCode: 'en',
      deploymentPlan: DeploymentPlan(
        platform: DeploymentPlatform.windows,
        purpose: DeploymentPurpose.installMedia,
        imagePath: r'D:\Images\Other.iso',
      ),
    );

    expect(task.validationIssueKey(), 'deploy_compat_image_mismatch');
  });
}
