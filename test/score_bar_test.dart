// A score bar fills from the left edge, in one direction, on every screen that
// draws one. `FractionallySizedBox` centres its child unless told otherwise,
// which grows the fill outward from the middle of the track and leaves a bar
// that reads as easily right-to-left as left-to-right.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:udi_streaks/ui/kit.dart';

void main() {
  /// The bar's own box, and the filled portion inside it.
  Future<(Rect track, Rect fill)> pumpBar(WidgetTester tester, double v) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(width: 200, child: ScoreBar(v, label: 'test')),
        ),
      ),
    ));
    // Past the grow-to-value tween, so the fill is at its final width.
    await tester.pumpAndSettle();
    final fills = find.descendant(
      of: find.byType(FractionallySizedBox),
      matching: find.byType(Container),
    );
    return (
      tester.getRect(find.byType(FractionallySizedBox)),
      tester.getRect(fills.first),
    );
  }

  testWidgets('the fill starts at the left edge, not the middle',
      (tester) async {
    final (track, fill) = await pumpBar(tester, 0.5);

    expect(fill.left, track.left);
    // Half a 200dp bar, so a centred fill would start at 50 and end at 150.
    expect(fill.width, closeTo(100, 0.5));
  });

  testWidgets('the fill grows only rightward as the value rises',
      (tester) async {
    final (_, quarter) = await pumpBar(tester, 0.25);
    final (_, threeQuarters) = await pumpBar(tester, 0.75);

    // Same origin at both values — only the right edge moves.
    expect(threeQuarters.left, quarter.left);
    expect(threeQuarters.right, greaterThan(quarter.right));
  });

  testWidgets('a full bar spans the track and an empty one has no width',
      (tester) async {
    final (fullTrack, full) = await pumpBar(tester, 1);
    expect(full.width, closeTo(fullTrack.width, 0.5));

    final (emptyTrack, empty) = await pumpBar(tester, 0);
    expect(empty.left, emptyTrack.left);
    expect(empty.width, 0);
  });
}
