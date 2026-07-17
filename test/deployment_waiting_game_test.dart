import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:win_deploy_studio/features/wtg/screens/wtg_screen.dart';

void main() {
  testWidgets('waiting game scales down without creating a scroll view', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(220, 160));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 150,
            height: 112,
            child: DeploymentWaitingGame(
              score: 2,
              activeTarget: 4,
              onTargetPressed: (_) {},
            ),
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.byType(Scrollable), findsNothing);
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget.key is ValueKey<String> &&
            (widget.key! as ValueKey<String>).value.startsWith(
              'deployment-game-target-',
            ),
      ),
      findsNWidgets(9),
    );
  });
}
