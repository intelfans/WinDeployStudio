import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:win_deploy_studio/core/services/wtg_service.dart';

void main() {
  test(
    'Windows To Go retries an external GPT layout after a removable-media limitation',
    () {
      expect(
        WtgService.shouldRetryWtgWithUefiMbr(
          requestedLayout: WtgBootLayout.uefiGpt,
          isRemovable: true,
          busType: 'USB',
          diskpartOutput:
              'Virtual Disk Service error: removable media does not support this operation.',
        ),
        isTrue,
      );
      expect(
        WtgService.shouldRetryWtgWithUefiMbr(
          requestedLayout: WtgBootLayout.uefiGpt,
          // USB bridges can advertise IsRemovable=false. The caller has already
          // established it as an external target, so the DiskPart error wins.
          isRemovable: false,
          busType: 'USB',
          diskpartOutput:
              'Virtual Disk Service error: removable media does not support this operation.',
        ),
        isTrue,
      );
      expect(
        WtgService.shouldRetryWtgWithUefiMbr(
          requestedLayout: WtgBootLayout.uefiGpt,
          isRemovable: true,
          busType: 'USB',
          diskpartOutput: '虚拟磁盘服务错误: 可移动媒体不支持此操作。',
        ),
        isTrue,
      );
      expect(
        WtgService.shouldRetryWtgWithUefiMbr(
          requestedLayout: WtgBootLayout.uefiGpt,
          isRemovable: false,
          busType: 'SATA',
          diskpartOutput:
              'Virtual Disk Service error: removable media does not support this operation.',
        ),
        isFalse,
      );
      expect(
        WtgService.shouldRetryWtgWithUefiMbr(
          requestedLayout: WtgBootLayout.uefiGpt,
          isRemovable: true,
          busType: 'USB',
          diskpartOutput: 'Access is denied.',
        ),
        isFalse,
      );
    },
  );

  test('Windows To Go executes the compatible layout after detection', () {
    final source = File(
      'lib/core/services/wtg_service.dart',
    ).readAsStringSync();
    final start = source.indexOf(
      'Future<_WtgPartitionLayout> _partitionDisk({',
    );
    final end = source.indexOf(
      'Future<_WtgPartitionLayout> _partitionDiskWithLayout({',
      start,
    );
    expect(start, greaterThanOrEqualTo(0));
    expect(end, greaterThan(start));
    final flow = source.substring(start, end);

    expect(flow, contains('shouldRetryWtgWithUefiMbr('));
    expect(flow, contains('bootLayout: WtgBootLayout.uefiMbr'));
    expect(flow, contains('Retrying Windows To Go with UEFI/MBR'));
    expect(flow, contains("message: 'wtg_svc_partition_fallback_uefi_mbr'"));
    expect(flow, isNot(contains('Automatic UEFI/MBR fallback is disabled')));
  });
}
