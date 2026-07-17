import 'package:flutter_test/flutter_test.dart';
import 'package:win_deploy_studio/features/wtg/screens/wtg_screen.dart';

void main() {
  test('Windows To Go retries an initially empty image lookup', () async {
    var calls = 0;

    final images = await retryWindowsToGoImageLookup(() async {
      calls++;
      return calls == 1 ? <int>[] : <int>[1];
    }, retryDelay: Duration.zero);

    expect(calls, 2);
    expect(images, <int>[1]);
  });

  test('Windows To Go does not repeat a successful image lookup', () async {
    var calls = 0;

    final images = await retryWindowsToGoImageLookup(() async {
      calls++;
      return <String>['Tiny10'];
    }, retryDelay: Duration.zero);

    expect(calls, 1);
    expect(images, <String>['Tiny10']);
  });

  test(
    'Windows To Go preserves an empty result after its retry budget',
    () async {
      var calls = 0;

      final images = await retryWindowsToGoImageLookup(() async {
        calls++;
        return <Object>[];
      }, retryDelay: Duration.zero);

      expect(calls, 2);
      expect(images, isEmpty);
    },
  );
}
