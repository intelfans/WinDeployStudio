import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:win_deploy_studio/core/services/arch_cow_partition_service.dart';

void main() {
  ArchCowPartitionTarget target() => ArchCowPartitionTarget(
    diskNumber: 4,
    diskGuid: '01234567-89AB-CDEF-0123-456789ABCDEF',
    partitionNumber: 3,
    partitionGuid: '89abcdef-0123-4567-89ab-cdef01234567',
    offsetBytes: 2 * 1024 * 1024,
    sizeBytes: 8 * 1024 * 1024 * 1024,
  );

  test('serializes the complete target identity for the native helper', () {
    expect(target().helperArguments(parentPid: 4321), [
      '--disk-number',
      '4',
      '--disk-guid',
      '01234567-89ab-cdef-0123-456789abcdef',
      '--partition-number',
      '3',
      '--partition-guid',
      '89abcdef-0123-4567-89ab-cdef01234567',
      '--partition-offset-bytes',
      '${2 * 1024 * 1024}',
      '--partition-size-bytes',
      '${8 * 1024 * 1024 * 1024}',
      '--parent-pid',
      '4321',
    ]);
  });

  test('rejects malformed identities and unsupported COW geometry', () {
    expect(
      () => ArchCowPartitionTarget(
        diskNumber: 0,
        diskGuid: 'not-a-guid',
        partitionNumber: 3,
        partitionGuid: '89abcdef-0123-4567-89ab-cdef01234567',
        offsetBytes: 2 * 1024 * 1024,
        sizeBytes: 8 * 1024 * 1024 * 1024,
      ),
      throwsArgumentError,
    );
    expect(
      () => ArchCowPartitionTarget(
        diskNumber: 0,
        diskGuid: '01234567-89ab-cdef-0123-456789abcdef',
        partitionNumber: 3,
        partitionGuid: '89abcdef-0123-4567-89ab-cdef01234567',
        offsetBytes: 1025,
        sizeBytes: 8 * 1024 * 1024 * 1024,
      ),
      throwsArgumentError,
    );
    expect(
      () => ArchCowPartitionTarget(
        diskNumber: 0,
        diskGuid: '01234567-89ab-cdef-0123-456789abcdef',
        partitionNumber: 3,
        partitionGuid: '89abcdef-0123-4567-89ab-cdef01234567',
        offsetBytes: 2 * 1024 * 1024,
        sizeBytes: ArchCowPartitionTarget.maximumPartitionBytes + 4096,
      ),
      throwsArgumentError,
    );
  });

  test(
    'requires the native success record instead of trusting exit code',
    () async {
      final service = ArchCowPartitionService(
        helperResolver: () async => r'C:\app\wds_arch_cow_helper.exe',
        processRunner: (executable, arguments) async {
          expect(executable, r'C:\app\wds_arch_cow_helper.exe');
          expect(arguments, contains('--partition-guid'));
          return ProcessResult(99, 0, 'RESULT|ok|invalid|WDS_ARCH_COW\n', '');
        },
      );

      final result = await service.format(target: target(), parentPid: 4321);

      expect(result.started, isTrue);
      expect(result.exitCode, 0);
      expect(result.succeeded, isFalse);
    },
  );

  test('parses a verified formatter success record', () async {
    final service = ArchCowPartitionService(
      helperResolver: () async => r'C:\app\wds_arch_cow_helper.exe',
      processRunner: (ignoredExecutable, ignoredArguments) async =>
          ProcessResult(
            100,
            0,
            'RESULT|ok|01234567-89ab-cdef-0123-456789abcdef|WDS_ARCH_COW\n',
            '',
          ),
    );

    final result = await service.format(target: target(), parentPid: 4321);

    expect(result.succeeded, isTrue);
    expect(result.uuid, '01234567-89ab-cdef-0123-456789abcdef');
  });
}
