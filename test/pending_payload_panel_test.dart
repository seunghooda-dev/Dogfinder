import "package:dogfinder/main.dart";
import "package:flutter/material.dart";
import "package:flutter_test/flutter_test.dart";

void main() {
  testWidgets("PendingPayloadPanel calls onCopy when copy button tapped", (tester) async {
    var copied = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PendingPayloadPanel(
            prettyPayload: "{\n  \"a\": 1\n}",
            onCopy: () async {
              copied = true;
            },
          ),
        ),
      ),
    );

    await tester.tap(find.text("복사"));
    await tester.pump();

    expect(copied, isTrue);
    expect(find.text("Payload"), findsOneWidget);
  });
}
