import "package:dogfinder/main.dart";
import "package:flutter_test/flutter_test.dart";

void main() {
  test("PendingSyncResult.summaryText renders counts", () {
    const result = PendingSyncResult(
      total: 5,
      attempted: 4,
      succeeded: 2,
      failed: 2,
      suspendedSkipped: 1,
      waitingSkipped: 1,
      newlySuspended: 1,
    );

    expect(result.summaryText, "대기 동기화: 성공 2 · 실패 2 · 중단 1 · 대기중 1 · 신규중단 1");
    expect(result.summaryWithRemaining(3), "대기 동기화: 성공 2 · 실패 2 · 중단 1 · 대기중 1 · 신규중단 1 · 남은 3건");
  });

  test("filterAndSortPendingOpsForView applies type filter and sort", () {
    final ops = <Map<String, dynamic>>[
      {
        "id": "a",
        "type": "update_post",
        "suspended": false,
        "createdAt": "2026-01-01T00:00:00.000Z",
        "nextRetryAt": "2026-01-01T00:01:00.000Z",
      },
      {
        "id": "b",
        "type": "create_post",
        "suspended": false,
        "createdAt": "2026-01-01T00:02:00.000Z",
        "nextRetryAt": "2026-01-01T00:00:10.000Z",
      },
      {
        "id": "c",
        "type": "update_post",
        "suspended": true,
        "createdAt": "2026-01-01T00:03:00.000Z",
        "nextRetryAt": "2026-01-01T00:00:30.000Z",
      },
    ];

    final filtered = filterAndSortPendingOpsForView(
      ops,
      statusFilter: 1,
      typeFilter: "update_post",
      sortMode: 0,
    );
    expect(filtered.length, 1);
    expect(filtered.first["id"], "a");

    final sortedRecent = filterAndSortPendingOpsForView(
      ops,
      statusFilter: 0,
      typeFilter: "all",
      sortMode: 1,
    );
    expect(sortedRecent.first["id"], "c");
  });
}
