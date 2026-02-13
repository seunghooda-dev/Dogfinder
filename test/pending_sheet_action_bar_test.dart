import "package:dogfinder/main.dart";
import "package:flutter/material.dart";
import "package:flutter_test/flutter_test.dart";

void main() {
  testWidgets("PendingSheetActionBar disables actions when busy", (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: PendingSheetActionBar(
            busy: true,
            suspendedCount: 1,
          ),
        ),
      ),
    );

    final buttons = tester
        .widgetList<ButtonStyleButton>(find.byWidgetPredicate((w) => w is ButtonStyleButton))
        .toList();
    expect(buttons.length, greaterThanOrEqualTo(4));
    for (final b in buttons) {
      expect(b.onPressed, isNull);
    }
  });
}
