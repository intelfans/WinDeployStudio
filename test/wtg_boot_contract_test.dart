import 'package:flutter_test/flutter_test.dart';
import 'package:win_deploy_studio/core/services/wtg_service.dart';

void main() {
  test('direct deployment requires distinct device and osdevice bindings', () {
    final expected = WtgBootContract.expectedDevice(
      windowsDrive: r'W:\',
      storageDrive: r'W:\',
    );

    expect(expected, 'partition=W:');
    expect(
      WtgBootContract.listingMatches(
        'device partition=W:\ndevice partition=W:',
        expected,
      ),
      isFalse,
    );
    expect(
      WtgBootContract.listingMatches(
        'device partition=W:\nosdevice partition=W:',
        expected,
      ),
      isTrue,
    );
    expect(
      WtgBootContract.listingMatches('device partition=W:', expected),
      isFalse,
    );
  });

  test('virtual deployment binds the parent storage volume, not locate', () {
    final expected = WtgBootContract.expectedDevice(
      windowsDrive: r'I:\',
      storageDrive: r'R:\',
      virtualDiskFileName: 'Portable.vhdx',
    );

    expect(expected, r'vhd=[R:]\Portable.vhdx');
    expect(
      WtgBootContract.listingMatches(r'''device vhd=[R:]\Portable.vhdx
osdevice vhd=[R:]\Portable.vhdx''', expected),
      isTrue,
    );
    expect(
      WtgBootContract.listingMatches(r'''device vhd=[locate]\Portable.vhdx
osdevice vhd=[locate]\Portable.vhdx''', expected),
      isFalse,
    );
  });
}
