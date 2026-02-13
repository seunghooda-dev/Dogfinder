import "dart:convert";

import "package:dogfinder/backend/api_contract.dart";
import "package:dogfinder/main.dart";
import "package:flutter_test/flutter_test.dart";
import "package:shared_preferences/shared_preferences.dart";

class _FailingBackendApi implements BackendApi {
  @override
  Future<ApiPost> createPost(ApiPostCreateInput input) {
    throw Exception("network");
  }

  @override
  Future<ApiTip> createTip(String postId, ApiTipCreateInput input) {
    throw Exception("network");
  }

  @override
  Future<List<ApiPost>> listPosts({
    String? type,
    String? status,
    double? latitude,
    double? longitude,
    double? radiusKm,
    String? cursor,
  }) async {
    return const [];
  }

  @override
  Future<List<ApiTip>> listTips(String postId) async {
    return const [];
  }

  @override
  Future<void> registerPushToken(String token, {required String platform}) async {}

  @override
  Future<AuthSession> signInWithEmail({required String email, required String password}) {
    throw Exception("network");
  }

  @override
  Future<AuthSession> signUpWithEmail({
    required String email,
    required String password,
    String? displayName,
  }) {
    throw Exception("network");
  }

  @override
  Future<AuthSession> signInWithSocial({
    required String provider,
    required String displayName,
    String? providerUserId,
    String? email,
    String? accessToken,
  }) {
    throw Exception("network");
  }

  @override
  Future<ApiPost> updatePost(String postId, Map<String, dynamic> patch) {
    throw Exception("network");
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    AppStore.pendingBaseRetryDelay = Duration.zero;
    AppStore.pendingMaxRetryDelay = const Duration(seconds: 1800);
  });

  test("syncPendingOps returns empty result when queue is empty", () async {
    SharedPreferences.setMockInitialValues({});
    final store = await AppStore.create(backendApi: _FailingBackendApi());

    await store.clearPendingOps();
    final result = await store.syncPendingOps();

    expect(result.total, 0);
    expect(result.succeeded, 0);
    expect(result.failed, 0);
  });

  test("update_post pending op is deduped by postId", () async {
    SharedPreferences.setMockInitialValues({});
    final store = await AppStore.create(backendApi: _FailingBackendApi());
    final post = store.posts.first;

    await store.editPostBasic(
      postId: post.id,
      title: "A1",
      areaText: post.areaText,
      body: post.body,
    );
    await store.editPostBasic(
      postId: post.id,
      title: "A2",
      areaText: post.areaText,
      body: post.body,
    );

    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString("dog_finder_pending_ops");
    expect(raw, isNotNull);

    final decoded = jsonDecode(raw!) as List<dynamic>;
    final updates = decoded
        .whereType<Map>()
        .map((e) => e.cast<String, dynamic>())
        .where((e) => e["type"] == "update_post")
        .toList();

    expect(updates.length, 1);
    final payload = (updates.first["payload"] as Map).cast<String, dynamic>();
    final patch = (payload["patch"] as Map).cast<String, dynamic>();
    expect(patch["title"], "A2");
  });

  test("clearPendingOps removes queued operations", () async {
    SharedPreferences.setMockInitialValues({});
    final store = await AppStore.create(backendApi: _FailingBackendApi());
    final post = store.posts.first;

    await store.editPostBasic(
      postId: post.id,
      title: "B1",
      areaText: post.areaText,
      body: post.body,
    );
    expect(store.pendingOpsCount, greaterThan(0));

    await store.clearPendingOps();
    expect(store.pendingOpsCount, 0);

    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString("dog_finder_pending_ops");
    expect(raw, isNotNull);
    final decoded = jsonDecode(raw!) as List<dynamic>;
    expect(decoded, isEmpty);
  });

  test("pending op is suspended after repeated sync failures", () async {
    SharedPreferences.setMockInitialValues({});
    final store = await AppStore.create(backendApi: _FailingBackendApi());
    final post = store.posts.first;

    await store.editPostBasic(
      postId: post.id,
      title: "C1",
      areaText: post.areaText,
      body: post.body,
    );

    PendingSyncResult? lastResult;
    for (var i = 0; i < 5; i++) {
      lastResult = await store.syncPendingOps();
    }

    expect(store.pendingOpsCount, 1);
    expect(store.suspendedPendingOpsCount, 1);

    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString("dog_finder_pending_ops");
    expect(raw, isNotNull);
    final decoded = (jsonDecode(raw!) as List<dynamic>).whereType<Map>().map((e) => e.cast<String, dynamic>()).toList();
    expect(decoded.length, 1);
    expect(decoded.first["suspended"], isTrue);
    expect(decoded.first["retryCount"], 5);
    expect(lastResult, isNotNull);
    expect(lastResult!.failed, 1);
    expect(lastResult.newlySuspended, 1);
  });

  test("clearSuspendedPendingOps removes only suspended items", () async {
    SharedPreferences.setMockInitialValues({});
    final store = await AppStore.create(backendApi: _FailingBackendApi());
    final post = store.posts.first;

    await store.editPostBasic(
      postId: post.id,
      title: "D1",
      areaText: post.areaText,
      body: post.body,
    );
    await store.syncPendingOps();
    await store.syncPendingOps();

    await store.editPostBasic(
      postId: post.id,
      title: "D2",
      areaText: post.areaText,
      body: post.body,
    );
    for (var i = 0; i < 5; i++) {
      await store.syncPendingOps();
    }

    expect(store.pendingOpsCount, 1);
    expect(store.suspendedPendingOpsCount, 1);

    await store.clearSuspendedPendingOps();
    expect(store.pendingOpsCount, 0);
    expect(store.suspendedPendingOpsCount, 0);
  });

  test("reactivatePendingOpById unsuspends and resets retry count", () async {
    SharedPreferences.setMockInitialValues({});
    final store = await AppStore.create(backendApi: _FailingBackendApi());
    final post = store.posts.first;

    await store.editPostBasic(
      postId: post.id,
      title: "E1",
      areaText: post.areaText,
      body: post.body,
    );
    for (var i = 0; i < 5; i++) {
      await store.syncPendingOps();
    }
    expect(store.suspendedPendingOpsCount, 1);
    final opId = (store.pendingOpsSnapshot.first["id"] ?? "").toString();
    expect(opId.isNotEmpty, isTrue);

    await store.reactivatePendingOpById(opId);
    expect(store.suspendedPendingOpsCount, 0);

    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString("dog_finder_pending_ops");
    expect(raw, isNotNull);
    final decoded = (jsonDecode(raw!) as List<dynamic>).whereType<Map>().map((e) => e.cast<String, dynamic>()).toList();
    expect(decoded.length, 1);
    expect(decoded.first["suspended"], isFalse);
    expect(decoded.first["retryCount"], 0);
    expect(decoded.first["lastError"], isNull);
    expect(decoded.first["lastErrorAt"], isNull);
  });

  test("failed sync stores lastError and lastErrorAt", () async {
    SharedPreferences.setMockInitialValues({});
    final store = await AppStore.create(backendApi: _FailingBackendApi());
    final post = store.posts.first;

    await store.editPostBasic(
      postId: post.id,
      title: "F1",
      areaText: post.areaText,
      body: post.body,
    );
    final result = await store.syncPendingOps();
    expect(result.failed, 1);

    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString("dog_finder_pending_ops");
    expect(raw, isNotNull);
    final decoded = (jsonDecode(raw!) as List<dynamic>).whereType<Map>().map((e) => e.cast<String, dynamic>()).toList();
    expect(decoded.length, 1);
    final op = decoded.first;
    expect((op["lastError"] ?? "").toString().isNotEmpty, isTrue);
    expect((op["lastErrorAt"] ?? "").toString().isNotEmpty, isTrue);
  });

  test("failed sync stores nextRetryAt in the future", () async {
    SharedPreferences.setMockInitialValues({});
    final store = await AppStore.create(backendApi: _FailingBackendApi());
    final post = store.posts.first;

    await store.editPostBasic(
      postId: post.id,
      title: "G1",
      areaText: post.areaText,
      body: post.body,
    );
    await store.syncPendingOps();

    final raw = (await SharedPreferences.getInstance()).getString("dog_finder_pending_ops");
    expect(raw, isNotNull);
    final decoded = (jsonDecode(raw!) as List<dynamic>).whereType<Map>().map((e) => e.cast<String, dynamic>()).toList();
    expect(decoded.length, 1);
    final nextRetryAtRaw = (decoded.first["nextRetryAt"] ?? "").toString();
    expect(nextRetryAtRaw.isNotEmpty, isTrue);
    final nextRetryAt = DateTime.tryParse(nextRetryAtRaw);
    expect(nextRetryAt, isNotNull);
    expect(nextRetryAt!.isAfter(DateTime.now().subtract(const Duration(seconds: 1))), isTrue);
  });

  test("syncPendingOps skips item before nextRetryAt", () async {
    AppStore.pendingBaseRetryDelay = const Duration(seconds: 30);
    AppStore.pendingMaxRetryDelay = const Duration(seconds: 1800);
    SharedPreferences.setMockInitialValues({});
    final store = await AppStore.create(backendApi: _FailingBackendApi());
    final post = store.posts.first;

    await store.editPostBasic(
      postId: post.id,
      title: "H1",
      areaText: post.areaText,
      body: post.body,
    );
    await store.syncPendingOps();
    final second = await store.syncPendingOps();

    expect(second.waitingSkipped, 1);
    expect(second.attempted, 0);
    expect(second.failed, 0);
    expect(store.pendingOpsCount, 1);
  });

  test("syncPendingOps with ignoreBackoff attempts waiting item", () async {
    AppStore.pendingBaseRetryDelay = const Duration(seconds: 30);
    AppStore.pendingMaxRetryDelay = const Duration(seconds: 1800);
    SharedPreferences.setMockInitialValues({});
    final store = await AppStore.create(backendApi: _FailingBackendApi());
    final post = store.posts.first;

    await store.editPostBasic(
      postId: post.id,
      title: "I1",
      areaText: post.areaText,
      body: post.body,
    );
    await store.syncPendingOps();
    final forced = await store.syncPendingOps(ignoreBackoff: true);

    expect(forced.waitingSkipped, 0);
    expect(forced.attempted, 1);
    expect(forced.failed, 1);
  });

  test("syncPendingOps without ignoreBackoff keeps waiting item unattempted", () async {
    AppStore.pendingBaseRetryDelay = const Duration(seconds: 30);
    AppStore.pendingMaxRetryDelay = const Duration(seconds: 1800);
    SharedPreferences.setMockInitialValues({});
    final store = await AppStore.create(backendApi: _FailingBackendApi());
    final post = store.posts.first;

    await store.editPostBasic(
      postId: post.id,
      title: "J1",
      areaText: post.areaText,
      body: post.body,
    );
    await store.syncPendingOps();
    final normal = await store.syncPendingOps();

    expect(normal.waitingSkipped, 1);
    expect(normal.attempted, 0);
    expect(normal.failed, 0);
  });

  test("pending sheet ui state persists across store recreation", () async {
    SharedPreferences.setMockInitialValues({});
    final store = await AppStore.create(backendApi: _FailingBackendApi());
    await store.setPendingUiState(filter: 2, sort: 1, type: "update_post");

    final recreated = await AppStore.create(backendApi: _FailingBackendApi());
    expect(recreated.pendingUiFilter, 2);
    expect(recreated.pendingUiSort, 1);
    expect(recreated.pendingUiType, "update_post");
  });

  test("removePendingOpsByIds removes only selected operations", () async {
    SharedPreferences.setMockInitialValues({});
    final store = await AppStore.create(backendApi: _FailingBackendApi());
    final posts = store.posts.take(2).toList();

    await store.editPostBasic(
      postId: posts[0].id,
      title: "K1",
      areaText: posts[0].areaText,
      body: posts[0].body,
    );
    await store.editPostBasic(
      postId: posts[1].id,
      title: "K2",
      areaText: posts[1].areaText,
      body: posts[1].body,
    );
    expect(store.pendingOpsCount, 2);
    final ids = store.pendingOpsSnapshot.map((e) => (e["id"] ?? "").toString()).toList();

    await store.removePendingOpsByIds([ids.first]);
    expect(store.pendingOpsCount, 1);
  });

  test("reactivatePendingOpsByIds unsuspends selected operations", () async {
    SharedPreferences.setMockInitialValues({});
    final store = await AppStore.create(backendApi: _FailingBackendApi());
    final post = store.posts.first;

    await store.editPostBasic(
      postId: post.id,
      title: "L1",
      areaText: post.areaText,
      body: post.body,
    );
    for (var i = 0; i < 5; i++) {
      await store.syncPendingOps();
    }
    expect(store.suspendedPendingOpsCount, 1);
    final id = (store.pendingOpsSnapshot.first["id"] ?? "").toString();

    await store.reactivatePendingOpsByIds([id]);
    expect(store.suspendedPendingOpsCount, 0);
  });

  test("syncPendingOpsByIds attempts only selected operations", () async {
    SharedPreferences.setMockInitialValues({});
    final store = await AppStore.create(backendApi: _FailingBackendApi());
    final posts = store.posts.take(2).toList();

    await store.editPostBasic(
      postId: posts[0].id,
      title: "M1",
      areaText: posts[0].areaText,
      body: posts[0].body,
    );
    await store.editPostBasic(
      postId: posts[1].id,
      title: "M2",
      areaText: posts[1].areaText,
      body: posts[1].body,
    );
    final ids = store.pendingOpsSnapshot.map((e) => (e["id"] ?? "").toString()).toList(growable: false);
    expect(ids.length, 2);

    final result = await store.syncPendingOpsByIds([ids.first], ignoreBackoff: true);
    expect(result.total, 1);
    expect(result.attempted, 1);
    expect(result.failed, 1);
    expect(store.pendingOpsCount, 2);

    final snapshots = store.pendingOpsSnapshot;
    final firstOp = snapshots.firstWhere((e) => (e["id"] ?? "").toString() == ids.first);
    final secondOp = snapshots.firstWhere((e) => (e["id"] ?? "").toString() == ids.last);
    expect(firstOp["retryCount"], 1);
    expect(secondOp["retryCount"], 0);
  });

  test("syncPendingOpsByIds returns empty for unknown ids and keeps queue", () async {
    SharedPreferences.setMockInitialValues({});
    final store = await AppStore.create(backendApi: _FailingBackendApi());
    final post = store.posts.first;

    await store.editPostBasic(
      postId: post.id,
      title: "N1",
      areaText: post.areaText,
      body: post.body,
    );
    expect(store.pendingOpsCount, 1);

    final result = await store.syncPendingOpsByIds(const ["unknown-op-id"], ignoreBackoff: true);
    expect(result.total, 0);
    expect(result.attempted, 0);
    expect(result.failed, 0);
    expect(store.pendingOpsCount, 1);
  });
}
