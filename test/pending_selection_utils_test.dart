import "package:dogfinder/main.dart";
import "package:flutter_test/flutter_test.dart";

void main() {
  test("sanitizeSelectedPendingIds keeps only existing ids", () {
    final selected = <String>{"a", "b", "x"};
    final existing = <String>{"a", "b", "c"};

    final sanitized = sanitizeSelectedPendingIds(selected, existing);
    expect(sanitized, {"a", "b"});
  });

  test("countSelectedInFilteredPendingIds counts intersection only", () {
    final selected = <String>{"a", "b", "z"};
    final filtered = <String>["b", "c", "a", "d"];

    final count = countSelectedInFilteredPendingIds(selected, filtered);
    expect(count, 2);
  });

  test("countSelectedInFilteredPendingIds returns zero on empty filtered", () {
    final selected = <String>{"a", "b"};
    const filtered = <String>[];

    final count = countSelectedInFilteredPendingIds(selected, filtered);
    expect(count, 0);
  });

  test("selectedIdsRemainingInQueue keeps only ids still in queue snapshot", () {
    final selected = <String>{"x", "y", "z"};
    final queueOps = <Map<String, dynamic>>[
      {"id": "y"},
      {"id": "a"},
      {"id": "z"},
    ];

    final remained = selectedIdsRemainingInQueue(selected, queueOps);
    expect(remained, {"y", "z"});
  });

  test("buildSelectedSyncSummaryText renders selected and remaining counts", () {
    const result = PendingSyncResult(
      total: 3,
      attempted: 2,
      succeeded: 1,
      failed: 1,
      suspendedSkipped: 1,
      waitingSkipped: 0,
      newlySuspended: 0,
    );

    final text = buildSelectedSyncSummaryText(
      requestedSelectedCount: 4,
      result: result,
      selectedRemaining: 2,
      totalRemaining: 5,
    );

    expect(text.contains("선택 4건 재시도"), isTrue);
    expect(text.contains("선택잔여 2건"), isTrue);
    expect(text.contains("전체잔여 5건"), isTrue);
  });
}
