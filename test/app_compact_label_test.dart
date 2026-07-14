import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:win_deploy_studio/shared/widgets/app_compact_label.dart';

void main() {
  testWidgets('compact labels move as a whole instead of splitting in a wrap', (
    tester,
  ) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.binding.setSurfaceSize(const Size(170, 120));

    const tagKey = Key('community-tag');
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 170,
            child: Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                const SizedBox(key: Key('first-tag'), width: 80, height: 24),
                Container(
                  key: tagKey,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  child: const AppCompactLabel('Community Image'),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    final label = tester.widget<Text>(find.text('Community Image'));
    expect(label.softWrap, isFalse);
    expect(label.maxLines, 1);
    expect(label.overflow, TextOverflow.visible);
    expect(
      tester.getTopLeft(find.byKey(tagKey)).dy,
      greaterThan(tester.getTopLeft(find.byKey(const Key('first-tag'))).dy),
    );
    expect(tester.takeException(), isNull);
  });
}
