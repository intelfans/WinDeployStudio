import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:win_deploy_studio/app/routes.dart';

void main() {
  test('secondary workspace locations retain their parent navigation item', () {
    expect(appNavigationIndexForPath('/benchmark/history'), 4);
    expect(appNavigationIndexForPath('/disk-tools/diagnostics'), 5);
    expect(appNavigationIndexForPath('/disk-tools/boot-repair'), 5);
  });

  test('router accepts secondary workspace locations', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final router = container.read(routerProvider);

    router.go('/benchmark/history');
    expect(
      router.routeInformationProvider.value.uri.path,
      '/benchmark/history',
    );

    router.go('/disk-tools/diagnostics');
    expect(
      router.routeInformationProvider.value.uri.path,
      '/disk-tools/diagnostics',
    );

    router.go('/disk-tools/boot-repair');
    expect(
      router.routeInformationProvider.value.uri.path,
      '/disk-tools/boot-repair',
    );
  });
}
