import "package:dogfinder/main.dart";
import "package:flutter/material.dart";
import "package:flutter_test/flutter_test.dart";

void main() {
  testWidgets("PendingSelectionActionBar disables all actions when busy", (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: PendingSelectionActionBar(
            busy: true,
            hasSuspendedSelected: true,
          ),
        ),
      ),
    );

    final buttons = tester
        .widgetList<ButtonStyleButton>(find.byWidgetPredicate((w) => w is ButtonStyleButton))
        .toList();
    expect(buttons.length, 3);
    for (final b in buttons) {
      expect(b.onPressed, isNull);
    }
  });

  testWidgets("PendingSelectionActionBar disables reactivate when no suspended selected", (tester) async {
    var retryCalled = false;
    var reactivateCalled = false;
    var deleteCalled = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PendingSelectionActionBar(
            busy: false,
            hasSuspendedSelected: false,
            onRetrySelected: () => retryCalled = true,
            onReactivateSelected: () => reactivateCalled = true,
            onDeleteSelected: () => deleteCalled = true,
          ),
        ),
      ),
    );

    final buttons = tester
        .widgetList<ButtonStyleButton>(find.byWidgetPredicate((w) => w is ButtonStyleButton))
        .toList();
    expect(buttons.length, 3);
    expect(buttons[1].onPressed, isNull);
    buttons[0].onPressed?.call();
    buttons[2].onPressed?.call();

    expect(retryCalled, isTrue);
    expect(reactivateCalled, isFalse);
    expect(deleteCalled, isTrue);
  });
}
