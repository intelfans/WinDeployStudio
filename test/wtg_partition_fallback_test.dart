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
}
