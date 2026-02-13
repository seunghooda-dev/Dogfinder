
import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:flutter_naver_login/flutter_naver_login.dart';
import 'package:flutter_naver_login/interface/types/naver_login_status.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:kakao_flutter_sdk_user/kakao_flutter_sdk_user.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'backend/api_contract.dart';
import 'backend/backend_api_factory.dart';
import 'backend/rest_backend_api.dart';
import 'push/push_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  const kakaoNativeAppKey = String.fromEnvironment("KAKAO_NATIVE_APP_KEY");
  if (kakaoNativeAppKey.isNotEmpty) {
    KakaoSdk.init(nativeAppKey: kakaoNativeAppKey);
  }
  final backendApi = createBackendApiFromEnvironment();
  final store = await AppStore.create(backendApi: backendApi);
  await PushService.instance.initialize(
    onToken: (token) async {
      await store.registerPushToken(token);
    },
    onForegroundMessage: ({
      required String title,
      required String body,
      required Map<String, dynamic> data,
    }) {
      final postId = (data["postId"] ?? "").toString();
      store.addLiveNotification(
        title: title,
        message: body,
        postId: postId.isEmpty ? null : postId,
      );
    },
  );
  await PushService.instance.registerTokenWithBackend(backendApi);
  runApp(DogFinderApp(store: store));
}

/// --------------------------------------------
/// Models
/// --------------------------------------------
enum PostType { lost, sighting, shelter }
enum PostStatus { active, resolved }
enum DogSize { small, medium, large }
enum CollarState { has, none, unknown }

class DogProfile {
  final String id;
  String name;
  DogSize size;
  List<String> colors;
  String? breed;
  String? collarDesc;
  CollarState collarState;
  String? memo;

  DogProfile({
    required this.id,
    required this.name,
    required this.size,
    required this.colors,
    this.breed,
    this.collarDesc,
    this.collarState = CollarState.unknown,
    this.memo,
  });

  Map<String, dynamic> toJson() => {
        "id": id,
        "name": name,
        "size": size.name,
        "colors": colors,
        "breed": breed,
        "collarDesc": collarDesc,
        "collarState": collarState.name,
        "memo": memo,
      };

  factory DogProfile.fromJson(Map<String, dynamic> json) {
    DogSize parseSize() {
      final raw = (json["size"] ?? "").toString();
      return DogSize.values.firstWhere(
        (e) => e.name == raw,
        orElse: () => DogSize.small,
      );
    }

    CollarState parseCollarState() {
      final raw = (json["collarState"] ?? "").toString();
      return CollarState.values.firstWhere(
        (e) => e.name == raw,
        orElse: () => CollarState.unknown,
      );
    }

    return DogProfile(
      id: (json["id"] ?? "").toString(),
      name: (json["name"] ?? "").toString(),
      size: parseSize(),
      colors: ((json["colors"] as List?) ?? const []).map((e) => e.toString()).toList(),
      breed: json["breed"]?.toString(),
      collarDesc: json["collarDesc"]?.toString(),
      collarState: parseCollarState(),
      memo: json["memo"]?.toString(),
    );
  }
}

class Post {
  final String id;
  final PostType type;
  PostStatus status;
  final DateTime createdAt;
  DateTime eventTime;
  String areaText;
  double distanceKm; // demo
  double? latitude;
  double? longitude;
  DogSize? size;
  List<String> colors;
  String? breedGuess;
  CollarState collarState;
  String title;
  String body;
  String ownerDeviceId;
  String? linkedDogId;
  String? photoBase64;

  // MVP 확장 여지(지금은 UI만 있고 저장은 안 씀)
  String? contactPhone;
  String? openChatUrl;

  Post({
    required this.id,
    required this.type,
    required this.createdAt,
    required this.eventTime,
    required this.areaText,
    required this.distanceKm,
    this.latitude,
    this.longitude,
    required this.title,
    required this.body,
    required this.ownerDeviceId,
    this.status = PostStatus.active,
    this.size,
    this.colors = const [],
    this.breedGuess,
    this.collarState = CollarState.unknown,
    this.linkedDogId,
    this.photoBase64,
    this.contactPhone,
    this.openChatUrl,
  });

  Map<String, dynamic> toJson() => {
        "id": id,
        "type": type.name,
        "status": status.name,
        "createdAt": createdAt.toIso8601String(),
        "eventTime": eventTime.toIso8601String(),
        "areaText": areaText,
        "distanceKm": distanceKm,
        "latitude": latitude,
        "longitude": longitude,
        "size": size?.name,
        "colors": colors,
        "breedGuess": breedGuess,
        "collarState": collarState.name,
        "title": title,
        "body": body,
        "ownerDeviceId": ownerDeviceId,
        "linkedDogId": linkedDogId,
        "photoBase64": photoBase64,
        "contactPhone": contactPhone,
        "openChatUrl": openChatUrl,
      };

  factory Post.fromJson(Map<String, dynamic> json) {
    PostType parseType() {
      final raw = (json["type"] ?? "").toString();
      return PostType.values.firstWhere((e) => e.name == raw, orElse: () => PostType.sighting);
    }

    PostStatus parseStatus() {
      final raw = (json["status"] ?? "").toString();
      return PostStatus.values.firstWhere((e) => e.name == raw, orElse: () => PostStatus.active);
    }

    DogSize? parseSize() {
      final raw = (json["size"] ?? "").toString();
      if (raw.isEmpty) return null;
      return DogSize.values.firstWhere((e) => e.name == raw, orElse: () => DogSize.small);
    }

    CollarState parseCollarState() {
      final raw = (json["collarState"] ?? "").toString();
      return CollarState.values.firstWhere((e) => e.name == raw, orElse: () => CollarState.unknown);
    }

    DateTime parseDt(String key) {
      final raw = (json[key] ?? "").toString();
      return DateTime.tryParse(raw) ?? DateTime.now();
    }

    return Post(
      id: (json["id"] ?? "").toString(),
      type: parseType(),
      status: parseStatus(),
      createdAt: parseDt("createdAt"),
      eventTime: parseDt("eventTime"),
      areaText: (json["areaText"] ?? "").toString(),
      distanceKm: (json["distanceKm"] is num) ? (json["distanceKm"] as num).toDouble() : 0,
      latitude: (json["latitude"] is num) ? (json["latitude"] as num).toDouble() : null,
      longitude: (json["longitude"] is num) ? (json["longitude"] as num).toDouble() : null,
      title: (json["title"] ?? "").toString(),
      body: (json["body"] ?? "").toString(),
      ownerDeviceId: (json["ownerDeviceId"] ?? "").toString(),
      size: parseSize(),
      colors: ((json["colors"] as List?) ?? const []).map((e) => e.toString()).toList(),
      breedGuess: json["breedGuess"]?.toString(),
      collarState: parseCollarState(),
      linkedDogId: json["linkedDogId"]?.toString(),
      photoBase64: json["photoBase64"]?.toString(),
      contactPhone: json["contactPhone"]?.toString(),
      openChatUrl: json["openChatUrl"]?.toString(),
    );
  }
}

class TipReport {
  final String id;
  final String postId;
  final String reporterId;
  final DateTime createdAt;
  DateTime seenTime;
  String seenAreaText;
  String situation;
  String memo;
  bool canCall;
  bool canChat;

  TipReport({
    required this.id,
    required this.postId,
    required this.reporterId,
    required this.createdAt,
    required this.seenTime,
    required this.seenAreaText,
    required this.situation,
    required this.memo,
    required this.canCall,
    required this.canChat,
  });

  Map<String, dynamic> toJson() => {
        "id": id,
        "postId": postId,
        "reporterId": reporterId,
        "createdAt": createdAt.toIso8601String(),
        "seenTime": seenTime.toIso8601String(),
        "seenAreaText": seenAreaText,
        "situation": situation,
        "memo": memo,
        "canCall": canCall,
        "canChat": canChat,
      };

  factory TipReport.fromJson(Map<String, dynamic> json) {
    DateTime parseDt(String key) {
      final raw = (json[key] ?? "").toString();
      return DateTime.tryParse(raw) ?? DateTime.now();
    }

    return TipReport(
      id: (json["id"] ?? "").toString(),
      postId: (json["postId"] ?? "").toString(),
      reporterId: (json["reporterId"] ?? json["reporterUserId"] ?? "").toString(),
      createdAt: parseDt("createdAt"),
      seenTime: parseDt("seenTime"),
      seenAreaText: (json["seenAreaText"] ?? "").toString(),
      situation: (json["situation"] ?? "").toString(),
      memo: (json["memo"] ?? "").toString(),
      canCall: json["canCall"] == true,
      canChat: json["canChat"] == true,
    );
  }
}

class PendingSyncResult {
  final int total;
  final int attempted;
  final int succeeded;
  final int failed;
  final int suspendedSkipped;
  final int waitingSkipped;
  final int newlySuspended;

  const PendingSyncResult({
    required this.total,
    required this.attempted,
    required this.succeeded,
    required this.failed,
    required this.suspendedSkipped,
    required this.waitingSkipped,
    required this.newlySuspended,
  });

  static const empty = PendingSyncResult(
    total: 0,
    attempted: 0,
    succeeded: 0,
    failed: 0,
    suspendedSkipped: 0,
    waitingSkipped: 0,
    newlySuspended: 0,
  );

  String get summaryText {
    if (total == 0) return "대기 작업이 없어요";
    final parts = <String>[
      "성공 $succeeded",
      "실패 $failed",
    ];
    if (suspendedSkipped > 0) {
      parts.add("중단 $suspendedSkipped");
    }
    if (waitingSkipped > 0) {
      parts.add("대기중 $waitingSkipped");
    }
    if (newlySuspended > 0) {
      parts.add("신규중단 $newlySuspended");
    }
    return "대기 동기화: ${parts.join(" · ")}";
  }

  String summaryWithRemaining(int remaining) {
    return "$summaryText · 남은 ${remaining < 0 ? 0 : remaining}건";
  }
}

/// --------------------------------------------
/// Store (ChangeNotifier) + deviceId persistence
/// --------------------------------------------
class AppStore extends ChangeNotifier {
  static const _prefsKeyDeviceId = "dog_finder_device_id";
  static const _prefsKeyAuthProvider = "dog_finder_auth_provider";
  static const _prefsKeyAuthName = "dog_finder_auth_name";
  static const _prefsKeyAuthUserId = "dog_finder_auth_user_id";
  static const _prefsKeyEmailUsers = "dog_finder_email_users";
  static const _prefsKeyDogs = "dog_finder_dogs";
  static const _prefsKeyPosts = "dog_finder_posts";
  static const _prefsKeyTips = "dog_finder_tips";
  static const _prefsKeySavedPostIds = "dog_finder_saved_post_ids";
  static const _prefsKeyPendingOps = "dog_finder_pending_ops";
  static const _prefsKeyPendingUiFilter = "dog_finder_pending_ui_filter";
  static const _prefsKeyPendingUiSort = "dog_finder_pending_ui_sort";
  static const _prefsKeyPendingUiType = "dog_finder_pending_ui_type";
  static const _pendingRetrySuspendThreshold = 5;
  static const _pendingDefaultBaseRetryDelay = Duration(seconds: 30);
  static const _pendingDefaultMaxRetryDelay = Duration(seconds: 1800);
  static Duration pendingBaseRetryDelay = _pendingDefaultBaseRetryDelay;
  static Duration pendingMaxRetryDelay = _pendingDefaultMaxRetryDelay;

  // (사소) id 충돌 방지 카운터
  static int _counter = 0;

  final String deviceId;
  final SharedPreferences _prefs;
  final BackendApi? backendApi;
  final List<DogProfile> dogs = [];
  final List<Post> posts = [];
  final List<TipReport> tips = [];
  final Set<String> savedPostIds = {};
  final List<Map<String, dynamic>> _pendingOps = [];
  final Map<String, Map<String, String>> _emailUsers = {};
  int pendingUiFilter = 0;
  int pendingUiSort = 0;
  String pendingUiType = "all";
  String? authProvider;
  String? authName;
  String? authUserId;
  final List<Map<String, dynamic>> _liveNotifications = [];
  Timer? _liveSyncTimer;
  bool _liveSyncBusy = false;

  AppStore._(
    this.deviceId,
    this._prefs, {
    this.authProvider,
    this.authName,
    this.authUserId,
    this.backendApi,
  }) {
    _loadEmailUsers();
    _loadData();
    _loadSavedPostIds();
    _loadPendingOps();
    _loadPendingUiState();
    if (dogs.isEmpty && posts.isEmpty && tips.isEmpty) {
      _seed();
      _saveData();
    }
  }

  static Future<AppStore> create({BackendApi? backendApi}) async {
    final prefs = await SharedPreferences.getInstance();
    var id = prefs.getString(_prefsKeyDeviceId);
    if (id == null || id.isEmpty) {
      id = "device_${DateTime.now().millisecondsSinceEpoch}_${Random().nextInt(999999)}";
      await prefs.setString(_prefsKeyDeviceId, id);
    }
    final provider = prefs.getString(_prefsKeyAuthProvider);
    final name = prefs.getString(_prefsKeyAuthName);
    final userId = prefs.getString(_prefsKeyAuthUserId);
    final store = AppStore._(
      id,
      prefs,
      authProvider: provider,
      authName: name,
      authUserId: userId,
      backendApi: backendApi,
    );
    await store.bootstrapSync();
    store.startRealtimeAlerts();
    return store;
  }

  static String _id() {
    _counter++;
    return "${DateTime.now().microsecondsSinceEpoch}_$_counter";
  }

  void _seed() {
    final d1 = DogProfile(
      id: _id(),
      name: "콩이",
      size: DogSize.small,
      colors: ["갈색"],
      breed: "푸들",
      collarState: CollarState.has,
      collarDesc: "빨간 하네스",
      memo: "겁 많고 사람은 좋아해요",
    );
    dogs.add(d1);

    posts.addAll([
      Post(
        id: _id(),
        type: PostType.lost,
        createdAt: DateTime.now().subtract(const Duration(hours: 2)),
        eventTime: DateTime.now().subtract(const Duration(hours: 3)),
        areaText: "서울 강남구 역삼동(대략)",
        distanceKm: 1.2,
        title: "푸들 추정, 빨간 목줄",
        body: "산책 중 목줄이 풀렸어요. 겁이 많습니다.",
        ownerDeviceId: deviceId,
        size: DogSize.small,
        colors: ["갈색"],
        breedGuess: "푸들",
        collarState: CollarState.has,
        linkedDogId: d1.id,
      ),
      Post(
        id: _id(),
        type: PostType.sighting,
        createdAt: DateTime.now().subtract(const Duration(hours: 1)),
        eventTime: DateTime.now().subtract(const Duration(hours: 1, minutes: 10)),
        areaText: "서울 강남구 삼성동(대략)",
        distanceKm: 2.8,
        title: "흰색 중형견 배회",
        body: "근처 공원에서 혼자 배회하고 있었어요.",
        ownerDeviceId: "device_other",
        size: DogSize.medium,
        colors: ["흰색"],
        collarState: CollarState.unknown,
      ),
      Post(
        id: _id(),
        type: PostType.shelter,
        createdAt: DateTime.now().subtract(const Duration(minutes: 40)),
        eventTime: DateTime.now().subtract(const Duration(minutes: 55)),
        areaText: "서울 강남구 도곡동(대략)",
        distanceKm: 3.4,
        title: "임시 보호 중인 갈색 소형견",
        body: "도로변에서 발견해 임시 보호 중입니다. 특징 확인 후 연락 부탁드려요.",
        ownerDeviceId: "device_rescuer",
        size: DogSize.small,
        colors: ["갈색"],
        collarState: CollarState.none,
      ),
    ]);
  }

  void addDog(DogProfile dog) {
    dogs.add(dog);
    _saveData();
    notifyListeners();
  }

  void updateDog(DogProfile dog) {
    final idx = dogs.indexWhere((d) => d.id == dog.id);
    if (idx >= 0) {
      dogs[idx] = dog;
      _saveData();
      notifyListeners();
    }
  }

  void deleteDog(String dogId) {
    dogs.removeWhere((d) => d.id == dogId);
    _saveData();
    notifyListeners();
  }

  Future<bool> addPost(Post post) async {
    var postToStore = post;
    var syncedToBackend = backendApi == null;

    if (backendApi != null) {
      try {
        final created = await backendApi!.createPost(_toApiPostCreateInput(post));
        postToStore = _mergePostFromApi(post, created);
        syncedToBackend = true;
      } catch (_) {
        syncedToBackend = false;
      }
    }

    posts.insert(0, postToStore);
    if (!syncedToBackend) {
      await _enqueuePendingOp(
        "create_post",
        {
          "localPostId": postToStore.id,
        },
      );
    }
    await _saveData();
    notifyListeners();
    return syncedToBackend;
  }

  Future<bool> setPostResolved(String postId, {String? resolvedNote}) async {
    final idx = posts.indexWhere((p) => p.id == postId);
    if (idx < 0) return backendApi == null;
    final p = posts[idx];

    var syncedToBackend = backendApi == null;
    if (backendApi != null) {
      try {
        await backendApi!.updatePost(postId, {
          "status": "resolved",
          if (resolvedNote != null && resolvedNote.trim().isNotEmpty) "resolvedNote": resolvedNote.trim(),
        });
        syncedToBackend = true;
      } catch (_) {
        syncedToBackend = false;
      }
    }

    p.status = PostStatus.resolved;
    if (resolvedNote != null && resolvedNote.trim().isNotEmpty) {
      p.body = "${p.body}\n\n[해결 후기]\n${resolvedNote.trim()}";
    }
    if (!syncedToBackend) {
      await _enqueuePendingOp(
        "resolve_post",
        {
          "postId": postId,
          "resolvedNote": resolvedNote,
        },
      );
    }
    await _saveData();
    notifyListeners();
    return syncedToBackend;
  }

  Future<bool> editPostBasic({
    required String postId,
    required String title,
    required String areaText,
    required String body,
  }) async {
    final idx = posts.indexWhere((p) => p.id == postId);
    if (idx < 0) return backendApi == null;

    var syncedToBackend = backendApi == null;
    final patch = <String, dynamic>{
      "title": title,
      "areaText": areaText,
      "body": _toApiPostBodyRaw(posts[idx].type, body),
    };
    if (backendApi != null) {
      try {
        await backendApi!.updatePost(postId, patch);
        syncedToBackend = true;
      } catch (_) {
        syncedToBackend = false;
      }
    }

    final p = posts[idx];
    p.title = title;
    p.areaText = areaText;
    p.body = body;
    if (!syncedToBackend) {
      await _enqueuePendingOp(
        "update_post",
        {
          "postId": postId,
          "patch": patch,
        },
      );
    }
    await _saveData();
    notifyListeners();
    return syncedToBackend;
  }

  Future<bool> addTip(TipReport tip) async {
    var syncedToBackend = backendApi == null;
    if (backendApi != null) {
      try {
        await backendApi!.createTip(tip.postId, _toApiTipCreateInput(tip));
        syncedToBackend = true;
      } catch (_) {
        syncedToBackend = false;
      }
    }

    tips.insert(0, tip);
    if (!syncedToBackend) {
      await _enqueuePendingOp(
        "create_tip",
        {
          "localTipId": tip.id,
        },
      );
    }
    await _saveData();
    notifyListeners();
    return syncedToBackend;
  }

  bool get isLoggedIn => (authProvider ?? "").isNotEmpty;
  int get pendingOpsCount => _pendingOps.length;
  int get suspendedPendingOpsCount => _pendingOps.where((e) => e["suspended"] == true).length;
  List<Map<String, dynamic>> get pendingOpsSnapshot =>
      _pendingOps.map((e) => Map<String, dynamic>.from(e)).toList(growable: false);
  int get unreadLiveNotificationCount => _liveNotifications.where((e) => e["read"] != true).length;
  List<Map<String, dynamic>> get liveNotificationsSnapshot => _liveNotifications
      .map((e) => Map<String, dynamic>.from(e))
      .toList(growable: false);

  bool isMine(Post post) {
    if (post.ownerDeviceId == deviceId) return true;
    final userId = authUserId;
    if (userId == null || userId.isEmpty) return false;
    return post.ownerDeviceId == userId;
  }

  void _loadEmailUsers() {
    final raw = _prefs.getString(_prefsKeyEmailUsers);
    if (raw == null || raw.trim().isEmpty) return;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return;
      for (final entry in decoded.entries) {
        final email = entry.key.toString();
        final value = entry.value;
        if (value is! Map) continue;
        final password = (value["password"] ?? "").toString();
        final name = (value["name"] ?? "").toString();
        if (password.isEmpty) continue;
        _emailUsers[email] = {
          "password": password,
          "name": name,
        };
      }
    } catch (_) {}
  }

  Future<void> _saveEmailUsers() async {
    await _prefs.setString(_prefsKeyEmailUsers, jsonEncode(_emailUsers));
  }

  void _loadData() {
    List<Map<String, dynamic>> parseList(String key) {
      final raw = _prefs.getString(key);
      if (raw == null || raw.trim().isEmpty) return const [];
      try {
        final decoded = jsonDecode(raw);
        if (decoded is! List) return const [];
        return decoded.whereType<Map>().map((e) => e.cast<String, dynamic>()).toList();
      } catch (_) {
        return const [];
      }
    }

    final dogJson = parseList(_prefsKeyDogs);
    final postJson = parseList(_prefsKeyPosts);
    final tipJson = parseList(_prefsKeyTips);

    dogs
      ..clear()
      ..addAll(dogJson.map(DogProfile.fromJson));
    posts
      ..clear()
      ..addAll(postJson.map(Post.fromJson));
    tips
      ..clear()
      ..addAll(tipJson.map(TipReport.fromJson));
  }

  void _loadSavedPostIds() {
    final raw = _prefs.getStringList(_prefsKeySavedPostIds);
    savedPostIds
      ..clear()
      ..addAll(raw ?? const []);
  }

  Future<void> _saveSavedPostIds() async {
    await _prefs.setStringList(_prefsKeySavedPostIds, savedPostIds.toList());
  }

  bool isSavedPost(String postId) => savedPostIds.contains(postId);

  Future<void> toggleSavedPost(String postId) async {
    if (savedPostIds.contains(postId)) {
      savedPostIds.remove(postId);
    } else {
      savedPostIds.add(postId);
    }
    await _saveSavedPostIds();
    notifyListeners();
  }

  Future<void> _saveData() async {
    await _prefs.setString(_prefsKeyDogs, jsonEncode(dogs.map((e) => e.toJson()).toList()));
    await _prefs.setString(_prefsKeyPosts, jsonEncode(posts.map((e) => e.toJson()).toList()));
    await _prefs.setString(_prefsKeyTips, jsonEncode(tips.map((e) => e.toJson()).toList()));
  }

  void _loadPendingOps() {
    final raw = _prefs.getString(_prefsKeyPendingOps);
    if (raw == null || raw.trim().isEmpty) return;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return;
      _pendingOps
        ..clear()
        ..addAll(
          decoded
              .whereType<Map>()
              .map((e) => e.cast<String, dynamic>())
              .where((e) => e["type"] is String)
              .map((e) {
                e["retryCount"] = (e["retryCount"] is num) ? (e["retryCount"] as num).toInt() : 0;
                e["suspended"] = e["suspended"] == true;
                e["lastError"] = e["lastError"]?.toString();
                e["lastErrorAt"] = e["lastErrorAt"]?.toString();
                e["nextRetryAt"] = e["nextRetryAt"]?.toString();
                return e;
              }),
        );
    } catch (_) {}
  }

  Future<void> _savePendingOps() async {
    await _prefs.setString(_prefsKeyPendingOps, jsonEncode(_pendingOps));
  }

  void _loadPendingUiState() {
    pendingUiFilter = _prefs.getInt(_prefsKeyPendingUiFilter) ?? 0;
    pendingUiSort = _prefs.getInt(_prefsKeyPendingUiSort) ?? 0;
    pendingUiType = _prefs.getString(_prefsKeyPendingUiType) ?? "all";
  }

  Future<void> setPendingUiState({int? filter, int? sort, String? type}) async {
    if (filter != null) {
      pendingUiFilter = filter;
      await _prefs.setInt(_prefsKeyPendingUiFilter, filter);
    }
    if (sort != null) {
      pendingUiSort = sort;
      await _prefs.setInt(_prefsKeyPendingUiSort, sort);
    }
    if (type != null) {
      pendingUiType = type;
      await _prefs.setString(_prefsKeyPendingUiType, type);
    }
  }

  Future<void> clearPendingOps() async {
    _pendingOps.clear();
    await _savePendingOps();
    notifyListeners();
  }

  Future<void> clearSuspendedPendingOps() async {
    _pendingOps.removeWhere((op) => op["suspended"] == true);
    await _savePendingOps();
    notifyListeners();
  }

  Future<void> removePendingOpById(String opId) async {
    _pendingOps.removeWhere((op) => (op["id"] ?? "").toString() == opId);
    await _savePendingOps();
    notifyListeners();
  }

  Future<void> removePendingOpsByIds(Iterable<String> opIds) async {
    final ids = opIds.toSet();
    if (ids.isEmpty) return;
    _pendingOps.removeWhere((op) => ids.contains((op["id"] ?? "").toString()));
    await _savePendingOps();
    notifyListeners();
  }

  Future<void> reactivatePendingOpById(String opId) async {
    for (final op in _pendingOps) {
      if ((op["id"] ?? "").toString() != opId) continue;
      op["suspended"] = false;
      op["retryCount"] = 0;
      op["lastError"] = null;
      op["lastErrorAt"] = null;
      op["nextRetryAt"] = null;
      break;
    }
    await _savePendingOps();
    notifyListeners();
  }

  Future<void> reactivatePendingOpsByIds(Iterable<String> opIds) async {
    final ids = opIds.toSet();
    if (ids.isEmpty) return;
    for (final op in _pendingOps) {
      if (!ids.contains((op["id"] ?? "").toString())) continue;
      op["suspended"] = false;
      op["retryCount"] = 0;
      op["lastError"] = null;
      op["lastErrorAt"] = null;
      op["nextRetryAt"] = null;
    }
    await _savePendingOps();
    notifyListeners();
  }

  Future<void> _enqueuePendingOp(String type, Map<String, dynamic> payload) async {
    if (type == "update_post" || type == "resolve_post") {
      final targetPostId = (payload["postId"] ?? "").toString();
      if (targetPostId.isNotEmpty) {
        _pendingOps.removeWhere((op) {
          final opType = (op["type"] ?? "").toString();
          if (opType != type) return false;
          final opPayload = (op["payload"] as Map?)?.cast<String, dynamic>();
          if (opPayload == null) return false;
          return (opPayload["postId"] ?? "").toString() == targetPostId;
        });
      }
    }
    _pendingOps.add({
      "id": _id(),
      "type": type,
      "payload": payload,
      "createdAt": DateTime.now().toIso8601String(),
      "retryCount": 0,
      "suspended": false,
      "lastError": null,
      "lastErrorAt": null,
      "nextRetryAt": null,
    });
    await _savePendingOps();
  }

  Future<void> bootstrapSync() async {
    if (backendApi == null) return;
    await syncPendingOps();
    await syncFromBackend();
  }

  void startRealtimeAlerts() {
    if (backendApi == null || _liveSyncTimer != null) return;
    _registerRealtimeSession();
    _liveSyncTimer = Timer.periodic(const Duration(seconds: 20), (_) {
      _pollRealtimeChanges();
    });
  }

  Future<void> _registerRealtimeSession() async {
    if (backendApi == null) return;
    try {
      await registerPushToken("inapp_$deviceId");
    } catch (_) {}
  }

  Future<void> _pollRealtimeChanges() async {
    if (backendApi == null || _liveSyncBusy) return;
    _liveSyncBusy = true;
    final knownPostIds = posts.map((e) => e.id).toSet();
    final knownTipIds = tips.map((e) => e.id).toSet();
    try {
      await syncFromBackend();
      final newPosts = posts.where((p) => !knownPostIds.contains(p.id)).toList(growable: false);
      final newTips = tips.where((t) => !knownTipIds.contains(t.id)).toList(growable: false);

      for (final p in newPosts) {
        if (isMine(p)) continue;
        addLiveNotification(
          title: "새 ${_postTypeLabel(p.type)} 글",
          message: p.title,
          postId: p.id,
        );
      }
      for (final t in newTips) {
        final targetPost = posts.where((p) => p.id == t.postId).cast<Post?>().firstWhere((p) => p != null, orElse: () => null);
        if (targetPost == null || !isMine(targetPost)) continue;
        addLiveNotification(
          title: "내 게시글에 새 제보",
          message: targetPost.title,
          postId: targetPost.id,
        );
      }
    } finally {
      _liveSyncBusy = false;
    }
  }

  void addLiveNotification({
    required String title,
    required String message,
    String? postId,
  }) {
    _liveNotifications.insert(0, {
      "id": _id(),
      "title": title,
      "message": message,
      "postId": postId,
      "createdAt": DateTime.now().toIso8601String(),
      "read": false,
    });
    if (_liveNotifications.length > 100) {
      _liveNotifications.removeRange(100, _liveNotifications.length);
    }
    notifyListeners();
  }

  void markAllLiveNotificationsRead() {
    var changed = false;
    for (final item in _liveNotifications) {
      if (item["read"] == true) continue;
      item["read"] = true;
      changed = true;
    }
    if (changed) notifyListeners();
  }

  Future<void> registerPushToken(String token) async {
    if (backendApi == null) return;
    final trimmed = token.trim();
    if (trimmed.isEmpty) return;
    try {
      await backendApi!.registerPushToken(
        trimmed,
        platform: kIsWeb
            ? "web"
            : defaultTargetPlatform == TargetPlatform.iOS
                ? "ios"
                : "android",
      );
    } catch (_) {}
  }

  Future<void> syncFromBackend() async {
    if (backendApi == null) return;
    try {
      final remotePosts = await backendApi!.listPosts();
      if (remotePosts.isNotEmpty) {
        _mergeRemotePosts(remotePosts);
        for (final remotePost in remotePosts) {
          try {
            final remoteTips = await backendApi!.listTips(remotePost.id);
            _mergeRemoteTipsForPost(remotePost.id, remoteTips);
          } catch (_) {}
        }
      }
      await _saveData();
      notifyListeners();
    } catch (_) {}
  }

  Future<PendingSyncResult> syncPendingOps({bool ignoreBackoff = false}) async {
    return _syncPendingOpsInternal(ignoreBackoff: ignoreBackoff);
  }

  Future<PendingSyncResult> syncPendingOpsByIds(
    Iterable<String> opIds, {
    bool ignoreBackoff = false,
  }) async {
    final selectedIds = opIds.map((e) => e.toString()).where((e) => e.isNotEmpty).toSet();
    if (selectedIds.isEmpty) return PendingSyncResult.empty;
    return _syncPendingOpsInternal(
      ignoreBackoff: ignoreBackoff,
      onlyOpIds: selectedIds,
    );
  }

  Future<PendingSyncResult> _syncPendingOpsInternal({
    bool ignoreBackoff = false,
    Set<String>? onlyOpIds,
  }) async {
    if (backendApi == null || _pendingOps.isEmpty) return PendingSyncResult.empty;

    final now = DateTime.now();
    final failedIds = <String>{};
    var attempted = 0;
    var succeeded = 0;
    var failed = 0;
    var suspendedSkipped = 0;
    var waitingSkipped = 0;
    var newlySuspended = 0;
    final targetOps = onlyOpIds == null
        ? _pendingOps
        : _pendingOps.where((op) => onlyOpIds.contains((op["id"] ?? "").toString())).toList(growable: false);
    if (targetOps.isEmpty) return PendingSyncResult.empty;
    final ordered = List<Map<String, dynamic>>.from(targetOps)
      ..sort((a, b) {
        final pa = _pendingPriority((a["type"] ?? "").toString());
        final pb = _pendingPriority((b["type"] ?? "").toString());
        if (pa != pb) return pa.compareTo(pb);
        final ta = DateTime.tryParse((a["createdAt"] ?? "").toString()) ?? DateTime.fromMillisecondsSinceEpoch(0);
        final tb = DateTime.tryParse((b["createdAt"] ?? "").toString()) ?? DateTime.fromMillisecondsSinceEpoch(0);
        return ta.compareTo(tb);
      });
    for (final op in ordered) {
      final opId = (op["id"] ?? "").toString();
      final type = (op["type"] ?? "").toString();
      final payload = (op["payload"] as Map?)?.cast<String, dynamic>() ?? const <String, dynamic>{};
      if (op["suspended"] == true) {
        suspendedSkipped++;
        failedIds.add(opId);
        continue;
      }
      final nextRetryAtRaw = (op["nextRetryAt"] ?? "").toString();
      final nextRetryAt = DateTime.tryParse(nextRetryAtRaw);
      if (!ignoreBackoff && nextRetryAt != null && nextRetryAt.isAfter(now)) {
        waitingSkipped++;
        failedIds.add(opId);
        continue;
      }

      attempted++;
      try {
        switch (type) {
          case "create_post":
            await _syncCreatePostOp(payload);
            break;
          case "create_tip":
            await _syncCreateTipOp(payload);
            break;
          case "resolve_post":
            await _syncResolvePostOp(payload);
            break;
          case "update_post":
            await _syncUpdatePostOp(payload);
            break;
          default:
            failed++;
            failedIds.add(opId);
            continue;
        }
        succeeded++;
      } catch (e) {
        final retries = ((op["retryCount"] is num) ? (op["retryCount"] as num).toInt() : 0) + 1;
        op["retryCount"] = retries;
        op["lastError"] = e.toString();
        op["lastErrorAt"] = DateTime.now().toIso8601String();
        op["nextRetryAt"] = _nextRetryAtForAttempt(retries).toIso8601String();
        if (retries >= _pendingRetrySuspendThreshold) {
          if (op["suspended"] != true) {
            op["suspended"] = true;
            newlySuspended++;
          }
        }
        failed++;
        failedIds.add(opId);
      }
    }

    _pendingOps.removeWhere((op) {
      final opId = (op["id"] ?? "").toString();
      if (onlyOpIds != null && !onlyOpIds.contains(opId)) return false;
      return !failedIds.contains(opId);
    });
    await _savePendingOps();
    await _saveData();
    notifyListeners();
    return PendingSyncResult(
      total: ordered.length,
      attempted: attempted,
      succeeded: succeeded,
      failed: failed,
      suspendedSkipped: suspendedSkipped,
      waitingSkipped: waitingSkipped,
      newlySuspended: newlySuspended,
    );
  }

  static DateTime _nextRetryAtForAttempt(int retries) {
    final exp = retries <= 1 ? 0 : retries - 1;
    final baseMs = pendingBaseRetryDelay.inMilliseconds.clamp(0, pendingMaxRetryDelay.inMilliseconds);
    final delayMs = (baseMs * pow(2, exp)).toInt();
    final clampedMs = delayMs.clamp(baseMs, pendingMaxRetryDelay.inMilliseconds);
    return DateTime.now().add(Duration(milliseconds: clampedMs));
  }

  static int _pendingPriority(String type) {
    switch (type) {
      case "create_post":
        return 0;
      case "update_post":
        return 1;
      case "resolve_post":
        return 2;
      case "create_tip":
        return 3;
      default:
        return 9;
    }
  }

  static const _shelterTypeMarker = "[DOGFINDER_SHELTER]";

  static String _toApiPostType(PostType type) {
    if (type == PostType.lost) return "lost";
    return "sighting";
  }

  static String _toApiPostBody(Post post) {
    return _toApiPostBodyRaw(post.type, post.body);
  }

  static String _toApiPostBodyRaw(PostType type, String body) {
    if (type != PostType.shelter) return body;
    final normalized = body.trim();
    if (normalized.startsWith(_shelterTypeMarker)) return body;
    return "$_shelterTypeMarker\n$body";
  }

  static PostType _fromApiPostType({
    required String remoteType,
    required String remoteBody,
    PostType? fallback,
  }) {
    if (fallback == PostType.shelter) return PostType.shelter;
    if (remoteBody.trimLeft().startsWith(_shelterTypeMarker)) return PostType.shelter;
    if (remoteType == "lost") return PostType.lost;
    return PostType.sighting;
  }

  static String _displayPostBody(String body) {
    final trimmed = body.trimLeft();
    if (!trimmed.startsWith(_shelterTypeMarker)) return body;
    return trimmed.substring(_shelterTypeMarker.length).trimLeft();
  }

  static String _displayPostTitle(String title, PostType type) {
    if (type != PostType.shelter) return title;
    return title.replaceFirst(RegExp(r"^\s*보호신고\s*·\s*"), "");
  }

  Future<void> signIn(String provider, {String? displayName}) async {
    if (provider != "email") {
      authUserId = null;
    }
    authProvider = provider;
    authName = (displayName ?? "").trim().isNotEmpty
        ? displayName!.trim()
        : provider == "kakao"
            ? "카카오 사용자"
            : provider == "naver"
                ? "네이버 사용자"
                : "이메일 사용자";
    await _prefs.setString(_prefsKeyAuthProvider, authProvider!);
    await _prefs.setString(_prefsKeyAuthName, authName!);
    if (authUserId != null && authUserId!.isNotEmpty) {
      await _prefs.setString(_prefsKeyAuthUserId, authUserId!);
    } else {
      await _prefs.remove(_prefsKeyAuthUserId);
    }
    await syncPendingOps();
    await syncFromBackend();
    await PushService.instance.registerTokenWithBackend(backendApi);
    notifyListeners();
  }

  Future<String?> signUpWithEmail({
    required String email,
    required String password,
    String? displayName,
  }) async {
    final normalizedEmail = email.trim().toLowerCase();
    if (normalizedEmail.isEmpty || !normalizedEmail.contains("@")) {
      return "올바른 이메일을 입력해 주세요.";
    }
    if (password.length < 6) {
      return "비밀번호는 6자 이상이어야 해요.";
    }

    if (backendApi != null) {
      try {
        final session = await backendApi!.signUpWithEmail(
          email: normalizedEmail,
          password: password,
          displayName: displayName?.trim(),
        );
        await _upsertLocalEmailUser(
          email: normalizedEmail,
          password: password,
          displayName: session.displayName ?? displayName,
        );
        authUserId = session.userId.trim().isEmpty ? null : session.userId.trim();
        await signIn(
          "email",
          displayName: session.displayName ?? session.email ?? normalizedEmail,
        );
        return null;
      } on BackendException catch (e) {
        if (e.statusCode >= 400 && e.statusCode < 500) {
          return e.message;
        }
      } catch (_) {}
    }

    return _signUpWithEmailLocal(
      email: normalizedEmail,
      password: password,
      displayName: displayName,
    );
  }

  Future<String?> signInWithEmail({
    required String email,
    required String password,
  }) async {
    final normalizedEmail = email.trim().toLowerCase();
    if (backendApi != null) {
      try {
        final session = await backendApi!.signInWithEmail(
          email: normalizedEmail,
          password: password,
        );
        await _upsertLocalEmailUser(
          email: normalizedEmail,
          password: password,
          displayName: session.displayName ?? session.email ?? normalizedEmail,
        );
        authUserId = session.userId.trim().isEmpty ? null : session.userId.trim();
        await signIn(
          "email",
          displayName: session.displayName ?? session.email ?? normalizedEmail,
        );
        return null;
      } on BackendException catch (e) {
        if (e.statusCode >= 400 && e.statusCode < 500) {
          return e.message;
        }
      } catch (_) {}
    }

    return _signInWithEmailLocal(email: normalizedEmail, password: password);
  }

  Future<void> signOut() async {
    authProvider = null;
    authName = null;
    authUserId = null;
    if (backendApi is RestBackendApi) {
      (backendApi! as RestBackendApi).clearSession();
    }
    await _prefs.remove(_prefsKeyAuthProvider);
    await _prefs.remove(_prefsKeyAuthName);
    await _prefs.remove(_prefsKeyAuthUserId);
    notifyListeners();
  }

  @override
  void dispose() {
    _liveSyncTimer?.cancel();
    super.dispose();
  }

  ApiPostCreateInput _toApiPostCreateInput(Post post) {
    return ApiPostCreateInput(
      type: _toApiPostType(post.type),
      eventTime: post.eventTime,
      areaText: post.areaText,
      latitude: post.latitude,
      longitude: post.longitude,
      title: post.title,
      body: _toApiPostBody(post),
      photoUrl: post.photoBase64,
    );
  }

  ApiTipCreateInput _toApiTipCreateInput(TipReport tip) {
    return ApiTipCreateInput(
      seenTime: tip.seenTime,
      seenAreaText: tip.seenAreaText,
      situation: tip.situation,
      memo: tip.memo,
      canCall: tip.canCall,
      canChat: tip.canChat,
    );
  }

  Post _mergePostFromApi(Post local, ApiPost remote) {
    final mergedType = _fromApiPostType(
      remoteType: remote.type,
      remoteBody: remote.body,
      fallback: local.type,
    );
    return Post(
      id: remote.id.isEmpty ? local.id : remote.id,
      type: mergedType,
      status: remote.status == "resolved" ? PostStatus.resolved : PostStatus.active,
      createdAt: remote.createdAt,
      eventTime: remote.eventTime,
      areaText: remote.areaText.isEmpty ? local.areaText : remote.areaText,
      distanceKm: remote.distanceKm,
      latitude: remote.latitude,
      longitude: remote.longitude,
      title: remote.title.isEmpty ? local.title : _displayPostTitle(remote.title, mergedType),
      body: remote.body.isEmpty ? local.body : _displayPostBody(remote.body),
      ownerDeviceId: remote.ownerUserId.isEmpty ? local.ownerDeviceId : remote.ownerUserId,
      size: local.size,
      colors: local.colors,
      breedGuess: local.breedGuess,
      collarState: local.collarState,
      linkedDogId: local.linkedDogId,
      photoBase64: local.photoBase64,
      contactPhone: local.contactPhone,
      openChatUrl: local.openChatUrl,
    );
  }

  void _mergeRemotePosts(List<ApiPost> remotePosts) {
    for (final remote in remotePosts) {
      final idx = posts.indexWhere((p) => p.id == remote.id);
      if (idx >= 0) {
        posts[idx] = _mergePostFromApi(posts[idx], remote);
        continue;
      }
      posts.insert(
        0,
        Post(
          id: remote.id,
          type: _fromApiPostType(
            remoteType: remote.type,
            remoteBody: remote.body,
          ),
          status: remote.status == "resolved" ? PostStatus.resolved : PostStatus.active,
          createdAt: remote.createdAt,
          eventTime: remote.eventTime,
          areaText: remote.areaText,
          distanceKm: remote.distanceKm,
          latitude: remote.latitude,
          longitude: remote.longitude,
          title: _displayPostTitle(remote.title, _fromApiPostType(
            remoteType: remote.type,
            remoteBody: remote.body,
          )),
          body: _displayPostBody(remote.body),
          ownerDeviceId: remote.ownerUserId.isEmpty ? "remote_user" : remote.ownerUserId,
          photoBase64: remote.photoUrl,
        ),
      );
    }
  }

  void _mergeRemoteTipsForPost(String postId, List<ApiTip> remoteTips) {
    for (final remote in remoteTips) {
      final idx = tips.indexWhere((t) => t.id == remote.id);
      final merged = TipReport(
        id: remote.id,
        postId: postId,
        reporterId: remote.reporterUserId,
        createdAt: remote.createdAt,
        seenTime: remote.seenTime,
        seenAreaText: remote.seenAreaText,
        situation: remote.situation,
        memo: remote.memo,
        canCall: remote.canCall,
        canChat: remote.canChat,
      );
      if (idx >= 0) {
        tips[idx] = merged;
      } else {
        tips.insert(0, merged);
      }
    }
  }

  Future<void> _syncCreatePostOp(Map<String, dynamic> payload) async {
    final localPostId = (payload["localPostId"] ?? "").toString();
    if (localPostId.isEmpty) return;
    final idx = posts.indexWhere((p) => p.id == localPostId);
    if (idx < 0) return;

    final localPost = posts[idx];
    final created = await backendApi!.createPost(_toApiPostCreateInput(localPost));
    final merged = _mergePostFromApi(localPost, created);
    posts[idx] = merged;

    if (localPostId != merged.id) {
      if (savedPostIds.remove(localPostId)) {
        savedPostIds.add(merged.id);
      }
      for (var i = 0; i < tips.length; i++) {
        final tip = tips[i];
        if (tip.postId != localPostId) continue;
        tips[i] = TipReport(
          id: tip.id,
          postId: merged.id,
          reporterId: tip.reporterId,
          createdAt: tip.createdAt,
          seenTime: tip.seenTime,
          seenAreaText: tip.seenAreaText,
          situation: tip.situation,
          memo: tip.memo,
          canCall: tip.canCall,
          canChat: tip.canChat,
        );
      }
      for (final op in _pendingOps) {
        final opPayload = (op["payload"] as Map?)?.cast<String, dynamic>();
        if (opPayload == null) continue;
        if ((opPayload["postId"] ?? "").toString() == localPostId) {
          opPayload["postId"] = merged.id;
        }
      }
      await _saveSavedPostIds();
    }
  }

  Future<void> _syncCreateTipOp(Map<String, dynamic> payload) async {
    final localTipId = (payload["localTipId"] ?? "").toString();
    if (localTipId.isEmpty) return;
    final idx = tips.indexWhere((t) => t.id == localTipId);
    if (idx < 0) return;
    final tip = tips[idx];
    await backendApi!.createTip(tip.postId, _toApiTipCreateInput(tip));
  }

  Future<void> _syncResolvePostOp(Map<String, dynamic> payload) async {
    final postId = (payload["postId"] ?? "").toString();
    if (postId.isEmpty) return;
    final resolvedNote = payload["resolvedNote"]?.toString();
    await backendApi!.updatePost(postId, {
      "status": "resolved",
      if (resolvedNote != null && resolvedNote.trim().isNotEmpty) "resolvedNote": resolvedNote.trim(),
    });
  }

  Future<void> _syncUpdatePostOp(Map<String, dynamic> payload) async {
    final postId = (payload["postId"] ?? "").toString();
    if (postId.isEmpty) return;
    final patch = (payload["patch"] as Map?)?.cast<String, dynamic>() ?? const <String, dynamic>{};
    if (patch.isEmpty) return;
    final currentPost = posts.where((p) => p.id == postId).cast<Post?>().firstWhere((p) => p != null, orElse: () => null);
    if (currentPost != null && patch["body"] is String) {
      patch["body"] = _toApiPostBodyRaw(currentPost.type, patch["body"].toString());
    }
    await backendApi!.updatePost(postId, patch);
  }

  Future<String?> _signUpWithEmailLocal({
    required String email,
    required String password,
    String? displayName,
  }) async {
    if (_emailUsers.containsKey(email)) {
      return "이미 가입된 이메일입니다.";
    }
    await _upsertLocalEmailUser(
      email: email,
      password: password,
      displayName: displayName,
    );
    authUserId = null;
    await signIn(
      "email",
      displayName: (displayName ?? "").trim().isEmpty ? email : displayName!.trim(),
    );
    return null;
  }

  Future<String?> _signInWithEmailLocal({
    required String email,
    required String password,
  }) async {
    final info = _emailUsers[email];
    if (info == null) {
      return "가입된 이메일이 없어요.";
    }
    if ((info["password"] ?? "") != password) {
      return "비밀번호가 일치하지 않아요.";
    }
    final name = (info["name"] ?? "").trim();
    authUserId = null;
    await signIn(
      "email",
      displayName: name.isEmpty ? email : name,
    );
    return null;
  }

  Future<void> _upsertLocalEmailUser({
    required String email,
    required String password,
    String? displayName,
  }) async {
    _emailUsers[email] = {
      "password": password,
      "name": (displayName ?? "").trim(),
    };
    await _saveEmailUsers();
  }

  List<Post> matchLostPostsForSighting(Post sighting, {int limit = 10}) {
    final lost = posts.where((p) => p.type == PostType.lost && p.status == PostStatus.active).toList();

    int score(Post p) {
      int s = 0;

      String extractGu(String area) {
        final parts = area.split(" ");
        final gu = parts.firstWhere((e) => e.contains("구"), orElse: () => "");
        return gu;
      }

      final guA = extractGu(p.areaText);
      final guB = extractGu(sighting.areaText);
      if (guA.isNotEmpty && guA == guB) s += 40;

      if (p.size != null && sighting.size != null && p.size == sighting.size) s += 15;

      final colorOverlap = p.colors.toSet().intersection(sighting.colors.toSet()).isNotEmpty;
      if (colorOverlap) s += 20;

      if (p.collarState != CollarState.unknown &&
          sighting.collarState != CollarState.unknown &&
          p.collarState == sighting.collarState) {
        s += 10;
      }

      final recent = DateTime.now().difference(p.eventTime).inDays <= 7;
      if (recent) s += 10;

      // demo distance bonus (실제 위치 연동 시 좌표 기반으로 교체)
      if ((p.distanceKm - sighting.distanceKm).abs() <= 2.0) s += 5;

      return s;
    }

    lost.sort((a, b) => score(b).compareTo(score(a)));
    return lost.take(limit).toList();
  }
}

/// --------------------------------------------
/// StoreScope (InheritedNotifier) ? 안정적인 리빌드 전파
/// --------------------------------------------
class StoreScope extends InheritedNotifier<AppStore> {
  const StoreScope({super.key, required AppStore store, required super.child}) : super(notifier: store);

  static AppStore watch(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<StoreScope>();
    if (scope == null || scope.notifier == null) throw Exception("StoreScope not found");
    return scope.notifier!;
  }

  static AppStore read(BuildContext context) {
    final scope = context.getInheritedWidgetOfExactType<StoreScope>();
    if (scope == null || scope.notifier == null) throw Exception("StoreScope not found");
    return scope.notifier!;
  }
}

extension StoreX on BuildContext {
  /// 구독 O (notifyListeners 시 자동 rebuild)
  AppStore watchStore() => StoreScope.watch(this);

  /// 구독 X (불필요 리빌드 방지)
  AppStore readStore() => StoreScope.read(this);
}

/// --------------------------------------------
/// App Root
/// --------------------------------------------
class DogFinderApp extends StatelessWidget {
  final AppStore store;
  const DogFinderApp({super.key, required this.store});

  @override
  Widget build(BuildContext context) {
    const seed = Color(0xFF0F766E);
    const accent = Color(0xFFFF6A3D);
    final baseTheme = ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: seed,
        brightness: Brightness.light,
      ),
    );
    final textTheme = GoogleFonts.notoSansKrTextTheme(baseTheme.textTheme).copyWith(
      headlineSmall: GoogleFonts.notoSansKr(fontWeight: FontWeight.w800, letterSpacing: -0.35),
      titleLarge: GoogleFonts.notoSansKr(fontWeight: FontWeight.w800, letterSpacing: -0.25),
      titleMedium: GoogleFonts.notoSansKr(fontWeight: FontWeight.w700, letterSpacing: -0.12),
      titleSmall: GoogleFonts.notoSansKr(fontWeight: FontWeight.w700, letterSpacing: -0.08),
      labelLarge: GoogleFonts.notoSansKr(fontWeight: FontWeight.w700, letterSpacing: -0.02),
    );
    return StoreScope(
      store: store,
      child: MaterialApp(
        title: "Dog Finder MVP",
        theme: baseTheme.copyWith(
          scaffoldBackgroundColor: const Color(0xFFF4F7FB),
          textTheme: textTheme,
          primaryTextTheme: GoogleFonts.notoSansKrTextTheme(baseTheme.primaryTextTheme),
          appBarTheme: AppBarTheme(
            centerTitle: false,
            elevation: 0,
            scrolledUnderElevation: 0,
            backgroundColor: Colors.transparent,
            surfaceTintColor: Colors.transparent,
            foregroundColor: const Color(0xFF111827),
            titleTextStyle: GoogleFonts.notoSansKr(
              fontSize: 21,
              fontWeight: FontWeight.w800,
              color: const Color(0xFF111827),
              letterSpacing: -0.24,
            ),
          ),
          navigationBarTheme: NavigationBarThemeData(
            height: 72,
            backgroundColor: Colors.transparent,
            elevation: 0,
            indicatorColor: const Color(0xFFD9F4EE),
            iconTheme: WidgetStateProperty.resolveWith((states) {
              final selected = states.contains(WidgetState.selected);
              return IconThemeData(
                color: selected ? const Color(0xFF0F766E) : const Color(0xFF7D8491),
                size: selected ? 23 : 22,
              );
            }),
            labelTextStyle: WidgetStateProperty.resolveWith((states) {
              final selected = states.contains(WidgetState.selected);
              return GoogleFonts.notoSansKr(
                fontSize: 12,
                color: selected ? const Color(0xFF0F766E) : const Color(0xFF7D8491),
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              );
            }),
          ),
          cardTheme: CardThemeData(
            color: Colors.white,
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
              side: BorderSide(color: baseTheme.colorScheme.outline.withValues(alpha: 0.14)),
            ),
          ),
          inputDecorationTheme: InputDecorationTheme(
            filled: true,
            fillColor: Colors.white,
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide(color: baseTheme.colorScheme.outline.withValues(alpha: 0.2)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide(color: baseTheme.colorScheme.outline.withValues(alpha: 0.2)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide(color: accent, width: 1.5),
            ),
          ),
          chipTheme: baseTheme.chipTheme.copyWith(
            side: BorderSide(color: baseTheme.colorScheme.outline.withValues(alpha: 0.2)),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          filledButtonTheme: FilledButtonThemeData(
            style: FilledButton.styleFrom(
              backgroundColor: accent,
              foregroundColor: Colors.white,
              textStyle: GoogleFonts.notoSansKr(fontWeight: FontWeight.w700),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
          ),
          outlinedButtonTheme: OutlinedButtonThemeData(
            style: OutlinedButton.styleFrom(
              textStyle: GoogleFonts.notoSansKr(fontWeight: FontWeight.w700),
              side: BorderSide(color: baseTheme.colorScheme.outline.withValues(alpha: 0.3)),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            ),
          ),
          dividerColor: const Color(0xFFE9ECF1),
          floatingActionButtonTheme: const FloatingActionButtonThemeData(
            shape: StadiumBorder(),
            backgroundColor: Color(0xFF0F766E),
            foregroundColor: Colors.white,
          ),
        ),
        home: const Shell(),
      ),
    );
  }
}

/// --------------------------------------------
/// Shell with Bottom Tabs
/// --------------------------------------------
class Shell extends StatefulWidget {
  const Shell({super.key});
  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  int index = 0;

  @override
  Widget build(BuildContext context) {
    final pages = const [
      NearbyTab(),
      RegisterTab(),
      MyDogsTab(),
      MyActivityTab(),
    ];

    return Scaffold(
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 280),
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeInCubic,
        transitionBuilder: (child, animation) {
          final offset = Tween<Offset>(
            begin: const Offset(0.03, 0),
            end: Offset.zero,
          ).animate(animation);
          return FadeTransition(
            opacity: animation,
            child: SlideTransition(position: offset, child: child),
          );
        },
        child: KeyedSubtree(
          key: ValueKey(index),
          child: pages[index],
        ),
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(12, 0, 12, 10),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.95),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.14)),
            boxShadow: const [
              BoxShadow(
                color: Color(0x12000000),
                blurRadius: 22,
                offset: Offset(0, 10),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(22),
            child: NavigationBar(
              selectedIndex: index,
              onDestinationSelected: (i) => setState(() => index = i),
              indicatorShape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              destinations: const [
                NavigationDestination(
                  icon: Icon(Icons.place_outlined),
                  selectedIcon: Icon(Icons.place),
                  label: "근처",
                ),
                NavigationDestination(
                  icon: Icon(Icons.campaign_outlined),
                  selectedIcon: Icon(Icons.campaign),
                  label: "실종/제보",
                ),
                NavigationDestination(
                  icon: Icon(Icons.pets_outlined),
                  selectedIcon: Icon(Icons.pets),
                  label: "내 강아지",
                ),
                NavigationDestination(
                  icon: Icon(Icons.person_outline),
                  selectedIcon: Icon(Icons.person),
                  label: "내 활동",
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AppLayeredBackground extends StatelessWidget {
  final Widget child;
  const _AppLayeredBackground({required this.child});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFFF4FBFA),
            Color(0xFFF5F8FF),
            Color(0xFFFFF7F1),
          ],
        ),
      ),
      child: child,
    );
  }
}

/// --------------------------------------------
/// Tab 1: Nearby Feed
/// --------------------------------------------
class NearbyTab extends StatefulWidget {
  const NearbyTab({super.key});
  @override
  State<NearbyTab> createState() => _NearbyTabState();
}

class _NearbyTabState extends State<NearbyTab> {
  PostType? filterType;
  double radiusKm = 3;
  bool onlyActive = true;
  bool sortByDistance = false;
  int recentYears = 1; // 0 = 전체 기간
  String orderBasis = "등록일 기준";
  String regionFilter = "모든 지역";
  String animalFilter = "모든 동물";
  bool isSyncing = false;

  Future<void> _syncNow(AppStore store) async {
    final messenger = ScaffoldMessenger.of(context);
    if (store.backendApi == null) {
      messenger.showSnackBar(
        const SnackBar(content: Text("백엔드 미연결 상태입니다.")),
      );
      return;
    }
    setState(() => isSyncing = true);
    final pendingResult = await store.syncPendingOps();
    await store.syncFromBackend();
    if (!mounted) return;
    setState(() => isSyncing = false);
    messenger.showSnackBar(
      SnackBar(content: Text(pendingResult.summaryWithRemaining(store.pendingOpsCount))),
    );
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watchStore();
    final pendingCount = store.pendingOpsCount;
    final unreadLiveCount = store.unreadLiveNotificationCount;

    final all = store.posts.where((p) {
      if (onlyActive && p.status != PostStatus.active) return false;
      if (filterType != null && p.type != filterType) return false;
      if (recentYears > 0 && p.createdAt.isBefore(DateTime.now().subtract(Duration(days: 365 * recentYears)))) {
        return false;
      }
      if (regionFilter != "모든 지역" && !p.areaText.contains(regionFilter)) return false;
      if (animalFilter != "모든 동물") {
        if (animalFilter == "소형" && p.size != DogSize.small) return false;
        if (animalFilter == "중형" && p.size != DogSize.medium) return false;
        if (animalFilter == "대형" && p.size != DogSize.large) return false;
      }
      if (p.distanceKm > radiusKm) return false;
      return true;
    }).toList();

    all.sort((a, b) {
      if (orderBasis == "거리 기준" || sortByDistance) return a.distanceKm.compareTo(b.distanceKm);
      return b.createdAt.compareTo(a.createdAt);
    });

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 14,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "PAWINHAND",
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: const Color(0xFFEF7F1A),
                    letterSpacing: 0.2,
                  ),
            ),
            Text(
              "서울 강남구 · ${radiusKm.toStringAsFixed(0)}km 반경",
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: isSyncing
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Stack(
                    clipBehavior: Clip.none,
                    children: [
                      const Icon(Icons.sync),
                      if (pendingCount > 0)
                        Positioned(
                          right: -2,
                          top: -2,
                          child: Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              color: Theme.of(context).colorScheme.error,
                              shape: BoxShape.circle,
                            ),
                          ),
                        ),
                    ],
                  ),
            tooltip: pendingCount > 0 ? "동기화 (대기 $pendingCount건)" : "동기화",
            onLongPress: () => _showPendingOpsSheet(context, store),
            onPressed: isSyncing
                ? null
                : () => _syncNow(store),
          ),
          IconButton(
            icon: Stack(
              clipBehavior: Clip.none,
              children: [
                const Icon(Icons.notifications_none),
                if (unreadLiveCount > 0)
                  Positioned(
                    right: -2,
                    top: -2,
                    child: Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.error,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
              ],
            ),
            tooltip: unreadLiveCount > 0 ? "실시간 알림 ($unreadLiveCount)" : "실시간 알림",
            onPressed: () => _showLiveNotificationsSheet(context, store),
          ),
          IconButton(
            icon: const Icon(Icons.tune),
            onPressed: () async {
              final r = await showModalBottomSheet<_NearbyFilterResult>(
                context: context,
                isScrollControlled: true,
                builder: (_) => _NearbyFilterSheet(
                  initial: _NearbyFilterResult(
                    filterType: filterType,
                    radiusKm: radiusKm,
                    onlyActive: onlyActive,
                    sortByDistance: sortByDistance,
                  ),
                ),
              );
              if (r != null) {
                setState(() {
                  filterType = r.filterType;
                  radiusKm = r.radiusKm;
                  onlyActive = r.onlyActive;
                  sortByDistance = r.sortByDistance;
                });
              }
            },
          )
        ],
      ),
      body: _AppLayeredBackground(
        child: RefreshIndicator(
          onRefresh: () => _syncNow(store),
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 100),
            children: [
            Container(
              padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(24),
                gradient: const LinearGradient(
                  colors: [Color(0xFFFFF1DF), Color(0xFFFFF8F0), Color(0xFFE7F1FF)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                border: Border.all(color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.16)),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x12000000),
                    blurRadius: 18,
                    offset: Offset(0, 8),
                  ),
                ],
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          "Neighborhood Bulletin",
                          style: Theme.of(context).textTheme.labelSmall?.copyWith(letterSpacing: 0.4),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          "현재 반경 ${radiusKm.toStringAsFixed(0)}km 내 ${all.length}건",
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w800,
                                letterSpacing: -0.2,
                              ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          onlyActive ? "진행중 제보만 모아봤어요." : "전체 제보를 표시 중입니다.",
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: Theme.of(context).colorScheme.onSurfaceVariant,
                              ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  Container(
                    width: 50,
                    height: 50,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.85),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Icon(Icons.pin_drop_outlined, color: Color(0xFFEF7F1A)),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            _SegmentRow(filterType: filterType, onChanged: (v) => setState(() => filterType = v)),
            const SizedBox(height: 10),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _TopFilterChip(
                    icon: Icons.tune,
                    label: recentYears == 0 ? "전체 기간" : "최근 $recentYears년",
                    onTap: () async {
                      final picked = await _pickOption<int>(
                        context,
                        title: "기간 선택",
                        options: const [1, 3, 5, 0],
                        labelOf: (v) => v == 0 ? "전체 기간" : "최근 $v년",
                        initial: recentYears,
                      );
                      if (picked != null) setState(() => recentYears = picked);
                    },
                  ),
                  const SizedBox(width: 8),
                  _TopFilterChip(
                    label: orderBasis,
                    onTap: () async {
                      final picked = await _pickOption<String>(
                        context,
                        title: "정렬 기준",
                        options: const ["등록일 기준", "거리 기준"],
                        labelOf: (v) => v,
                        initial: orderBasis,
                      );
                      if (picked != null) setState(() => orderBasis = picked);
                    },
                  ),
                  const SizedBox(width: 8),
                  _TopFilterChip(
                    label: regionFilter,
                    onTap: () async {
                      final picked = await _pickOption<String>(
                        context,
                        title: "지역 선택",
                        options: const ["모든 지역", "강남구", "서초구", "송파구", "마포구"],
                        labelOf: (v) => v,
                        initial: regionFilter,
                      );
                      if (picked != null) setState(() => regionFilter = picked);
                    },
                  ),
                  const SizedBox(width: 8),
                  _TopFilterChip(
                    label: animalFilter,
                    onTap: () async {
                      final picked = await _pickOption<String>(
                        context,
                        title: "동물 크기",
                        options: const ["모든 동물", "소형", "중형", "대형"],
                        labelOf: (v) => v,
                        initial: animalFilter,
                      );
                      if (picked != null) setState(() => animalFilter = picked);
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Text(
                  "실시간 피드",
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
                ),
                const Spacer(),
                Text(
                  orderBasis == "거리 기준" ? "가까운 순" : "최신 순",
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            if (all.isEmpty)
              SizedBox(
                height: MediaQuery.of(context).size.height * 0.56,
                child: _EmptyState(
                  title: "근처에 글이 없어요",
                  desc: "첫 제보를 등록하면 주변 사용자에게 바로 노출됩니다.",
                  primaryText: "지금 목격 등록",
                  onPrimary: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const SightingCreatePage()),
                  ),
                  secondaryText: "보호 등록하기",
                  onSecondary: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const ShelterCreatePage()),
                  ),
                ),
              )
            else
              ...List.generate(
                all.length,
                (i) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _PostCard(post: all[i], revealIndex: i),
                ),
              ),
            ],
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const SightingCreatePage()),
        ),
        icon: const Icon(Icons.add),
        label: const Text("빠른 목격 등록"),
      ),
    );
  }
}

class _NearbyFilterResult {
  final PostType? filterType;
  final double radiusKm;
  final bool onlyActive;
  final bool sortByDistance;

  _NearbyFilterResult({
    required this.filterType,
    required this.radiusKm,
    required this.onlyActive,
    required this.sortByDistance,
  });
}

class _NearbyFilterSheet extends StatefulWidget {
  final _NearbyFilterResult initial;
  const _NearbyFilterSheet({required this.initial});

  @override
  State<_NearbyFilterSheet> createState() => _NearbyFilterSheetState();
}

class _NearbyFilterSheetState extends State<_NearbyFilterSheet> {
  late PostType? filterType = widget.initial.filterType;
  late double radiusKm = widget.initial.radiusKm;
  late bool onlyActive = widget.initial.onlyActive;
  late bool sortByDistance = widget.initial.sortByDistance;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Container(
        margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 16,
          bottom: 16 + MediaQuery.of(context).viewInsets.bottom,
        ),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.4)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text("필터", style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            const SizedBox(height: 12),
            Row(
              children: [
                const Text("반경"),
                Expanded(
                  child: Slider(
                    value: radiusKm,
                    min: 1,
                    max: 20,
                    divisions: 19,
                    label: "${radiusKm.toStringAsFixed(0)}km",
                    onChanged: (v) => setState(() => radiusKm = v),
                  ),
                ),
                Text("${radiusKm.toStringAsFixed(0)}km"),
              ],
            ),
            SwitchListTile(
              value: onlyActive,
              onChanged: (v) => setState(() => onlyActive = v),
              title: const Text("진행중만 보기"),
            ),
            SwitchListTile(
              value: sortByDistance,
              onChanged: (v) => setState(() => sortByDistance = v),
              title: const Text("가까운순 정렬"),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () {
                      setState(() {
                        filterType = null;
                        radiusKm = 3;
                        onlyActive = true;
                        sortByDistance = false;
                      });
                    },
                    child: const Text("초기화"),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: () {
                      Navigator.of(context).pop(
                        _NearbyFilterResult(
                          filterType: filterType,
                          radiusKm: radiusKm,
                          onlyActive: onlyActive,
                          sortByDistance: sortByDistance,
                        ),
                      );
                    },
                    child: const Text("적용"),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SegmentRow extends StatelessWidget {
  final PostType? filterType;
  final ValueChanged<PostType?> onChanged;

  const _SegmentRow({required this.filterType, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.2)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: SegmentedButton<PostType?>(
          showSelectedIcon: false,
          style: ButtonStyle(
            backgroundColor: WidgetStateProperty.resolveWith((states) {
              final selected = states.contains(WidgetState.selected);
              return selected ? const Color(0xFFFFE8CF) : Colors.transparent;
            }),
            foregroundColor: WidgetStateProperty.resolveWith((states) {
              final selected = states.contains(WidgetState.selected);
              return selected ? const Color(0xFFB95B00) : const Color(0xFF5D6470);
            }),
            textStyle: WidgetStateProperty.all(
              Theme.of(context).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700),
            ),
            shape: WidgetStateProperty.all(
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
          segments: const [
            ButtonSegment(value: null, label: Text("전체")),
            ButtonSegment(value: PostType.lost, label: Text("실종")),
            ButtonSegment(value: PostType.sighting, label: Text("목격")),
            ButtonSegment(value: PostType.shelter, label: Text("보호")),
          ],
          selected: {filterType},
          onSelectionChanged: (s) => onChanged(s.first),
        ),
      ),
    );
  }
}

Future<T?> _pickOption<T>(
  BuildContext context, {
  required String title,
  required List<T> options,
  required String Function(T value) labelOf,
  required T initial,
}) {
  return showModalBottomSheet<T>(
    context: context,
    showDragHandle: true,
    builder: (ctx) {
      return SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
              child: Text(title, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
            ),
            ...options.map(
              (v) => ListTile(
                title: Text(labelOf(v)),
                trailing: v == initial ? const Icon(Icons.check) : null,
                onTap: () => Navigator.of(ctx).pop(v),
              ),
            ),
          ],
        ),
      );
    },
  );
}

class _TopFilterChip extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  final IconData? icon;

  const _TopFilterChip({
    required this.label,
    required this.onTap,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    Color bg;
    Color fg;
    if (label.contains("최근")) {
      bg = const Color(0xFFFFE8CE);
      fg = const Color(0xFF9A4E00);
    } else if (label.contains("등록일") || label.contains("거리")) {
      bg = const Color(0xFFE8EDFF);
      fg = const Color(0xFF2F4DBA);
    } else if (label.contains("지역")) {
      bg = const Color(0xFFE8F5E9);
      fg = const Color(0xFF2E7D32);
    } else {
      bg = const Color(0xFFFFF3E0);
      fg = const Color(0xFF8A5A1F);
    }
    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.22)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 16, color: fg),
              const SizedBox(width: 5),
            ],
            Text(
              label,
              style: TextStyle(color: fg, fontWeight: FontWeight.w700, fontSize: 13),
            ),
            const SizedBox(width: 3),
            Icon(Icons.keyboard_arrow_down_rounded, size: 17, color: fg),
          ],
        ),
      ),
    );
  }
}

class _PostCard extends StatelessWidget {
  final Post post;
  final int revealIndex;
  const _PostCard({required this.post, this.revealIndex = 0});

  @override
  Widget build(BuildContext context) {
    final store = context.watchStore();
    final isSaved = store.isSavedPost(post.id);
    final typeText = _postTypeLabel(post.type);
    final statusText = post.status == PostStatus.active ? "진행중" : "해결";
    final timeAgo = _timeAgo(post.createdAt);
    final tags = <String>[
      if (post.colors.isNotEmpty) ...post.colors.take(2),
      if (post.size != null) _sizeLabel(post.size!),
      _collarLabel(post.collarState),
    ].where((e) => e.trim().isNotEmpty).take(4).toList();

    final dur = 240 + (revealIndex.clamp(0, 8) * 35);
    return TweenAnimationBuilder<double>(
      key: ValueKey("post-card-${post.id}"),
      duration: Duration(milliseconds: dur),
      curve: Curves.easeOutCubic,
      tween: Tween(begin: 0, end: 1),
      builder: (context, v, child) {
        return Opacity(
          opacity: v,
          child: Transform.translate(
            offset: Offset(0, (1 - v) * 18),
            child: child,
          ),
        );
      },
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => PostDetailPage(postId: post.id)),
        ),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            color: Colors.white,
            border: Border.all(color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.16)),
            boxShadow: const [
              BoxShadow(
                color: Color(0x14000000),
                blurRadius: 20,
                offset: Offset(0, 10),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Stack(
                children: [
                  Container(
                    height: 198,
                    decoration: BoxDecoration(
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
                      color: Theme.of(context).colorScheme.surfaceContainerHigh,
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: post.photoBase64 != null && post.photoBase64!.isNotEmpty
                        ? Stack(
                            fit: StackFit.expand,
                            children: [
                              Image.memory(
                                base64Decode(post.photoBase64!),
                                fit: BoxFit.cover,
                                width: double.infinity,
                              ),
                              const DecoratedBox(
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    begin: Alignment.topCenter,
                                    end: Alignment.bottomCenter,
                                    colors: [Color(0x00000000), Color(0x64000000)],
                                  ),
                                ),
                              ),
                            ],
                          )
                        : Center(
                            child: Icon(_postTypeIcon(post.type), size: 42),
                          ),
                  ),
                  Positioned(
                    left: 10,
                    top: 10,
                    child: _Badge(text: typeText),
                  ),
                  Positioned(
                    left: 76,
                    top: 10,
                    child: _Badge(text: statusText, outlined: true),
                  ),
                  Positioned(
                    right: 10,
                    top: 10,
                    child: Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.82),
                        shape: BoxShape.circle,
                      ),
                      child: IconButton(
                        visualDensity: VisualDensity.compact,
                        iconSize: 18,
                        icon: Icon(isSaved ? Icons.bookmark : Icons.bookmark_border),
                        onPressed: () {
                          store.toggleSavedPost(post.id);
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text(isSaved ? "저장을 해제했어요" : "저장했어요")),
                          );
                        },
                      ),
                    ),
                  ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 13, 14, 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      post.title,
                      style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, height: 1.2),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      "${post.areaText} · ${post.distanceKm.toStringAsFixed(1)}km · $timeAgo",
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: tags.map((t) => _ChipTag(text: t)).toList(),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  final String text;
  final bool outlined;
  const _Badge({required this.text, this.outlined = false});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isMissing = text == "실종";
    final isSighting = text == "목격";
    final isShelter = text == "보호";
    final isActive = text == "진행중";
    final bgColor = isMissing
        ? const Color(0xFFFFE7E6)
        : isSighting
            ? const Color(0xFFE6EEFF)
            : isShelter
                ? const Color(0xFFE7F6EB)
                : isActive
                    ? const Color(0xFFFFF1DB)
                    : outlined
                        ? cs.surface
                        : cs.surfaceContainerHigh;
    final fgColor = isMissing
        ? const Color(0xFFC62828)
        : isSighting
            ? const Color(0xFF2F55D4)
            : isShelter
                ? const Color(0xFF2E7D32)
                : isActive
                    ? const Color(0xFFB56A00)
                    : cs.onSurface;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(99),
        color: bgColor,
        border: Border.all(color: cs.outline.withValues(alpha: outlined ? 0.35 : 0.18)),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w700,
          color: fgColor,
        ),
      ),
    );
  }
}

class _ChipTag extends StatelessWidget {
  final String text;
  const _ChipTag({required this.text});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(99),
        color: cs.surface,
        border: Border.all(color: cs.outline.withValues(alpha: 0.2)),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 12,
          color: cs.onSurfaceVariant,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}

/// --------------------------------------------
/// Post Detail + Tip
/// --------------------------------------------
class PostDetailPage extends StatelessWidget {
  final String postId;
  const PostDetailPage({super.key, required this.postId});

  @override
  Widget build(BuildContext context) {
    final store = context.watchStore();
    final post = store.posts.where((p) => p.id == postId).cast<Post?>().firstWhere(
          (p) => p != null,
          orElse: () => null,
        );

    if (post == null) {
      return Scaffold(
        appBar: AppBar(title: const Text("상세")),
        body: const Center(child: Text("게시글을 찾을 수 없어요.")),
      );
    }

    final isMine = store.isMine(post);
    final isSaved = store.isSavedPost(post.id);
    final tips = store.tips.where((t) => t.postId == post.id).toList();

    return Scaffold(
      appBar: AppBar(
        title: Text("${_postTypeLabel(post.type)} 상세"),
        actions: [
          IconButton(
            icon: Icon(isSaved ? Icons.bookmark : Icons.bookmark_border),
            onPressed: () async {
              await store.toggleSavedPost(post.id);
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(isSaved ? "저장을 해제했어요" : "저장했어요")),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.share_outlined),
            onPressed: () async {
              final messenger = ScaffoldMessenger.of(context);
              final text = [
                "[DogFinder] ${_postTypeLabel(post.type)} 제보",
                post.title,
                "위치: ${post.areaText}",
                "시간: ${_fmt(post.eventTime)}",
                "상세: ${post.body}",
              ].join("\n");
              await Clipboard.setData(ClipboardData(text: text));
              if (!context.mounted) return;
              messenger.showSnackBar(const SnackBar(content: Text("공유용 문구를 복사했어요")));
            },
          ),
          IconButton(icon: const Icon(Icons.flag_outlined), onPressed: () {}),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 24),
        children: [
          _DetailHero(post: post),
          const SizedBox(height: 10),
          _InfoCard(post: post),
          const SizedBox(height: 10),
          _FeatureCard(post: post),
          const SizedBox(height: 10),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Text(
                post.body,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(height: 1.5),
              ),
            ),
          ),
          const SizedBox(height: 12),
          _CTASection(post: post),
          const SizedBox(height: 20),
          if (post.type == PostType.lost) ...[
            Text("제보 (${tips.length})", style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
            const SizedBox(height: 8),
            if (tips.isEmpty)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Text(
                    "아직 제보가 없어요.",
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                ),
              )
            else
              ...tips.map((t) => _TipTile(tip: t)),
            const SizedBox(height: 16),
          ],
          Text("비슷한 제보", style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
          const SizedBox(height: 8),
          ...store.posts
              .where((p) => p.id != post.id && p.status == PostStatus.active)
              .take(3)
              .map((p) => Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      title: Text(p.title),
                      subtitle: Text("${p.areaText} · ${p.distanceKm.toStringAsFixed(1)}km"),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => PostDetailPage(postId: p.id)),
                      ),
                    ),
                  )),
          const SizedBox(height: 24),
          if (isMine) ...[
            const Divider(),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () async {
                      final note = await _resolveDialog(context);
                      final synced = await store.setPostResolved(post.id, resolvedNote: note);
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              synced ? "해결 처리 완료" : "서버 반영 실패: 로컬에서만 해결 처리했어요",
                            ),
                          ),
                        );
                      }
                    },
                    child: const Text("해결 처리"),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton(
                    onPressed: () async {
                      final synced = await Navigator.of(context).push<bool>(
                        MaterialPageRoute(
                          builder: (_) => PostEditPage(
                            postId: post.id,
                            initialTitle: post.title,
                            initialAreaText: post.areaText,
                            initialBody: post.body,
                          ),
                        ),
                      );
                      if (!context.mounted || synced == null) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            synced ? "수정 완료" : "서버 반영 실패: 로컬에서만 수정했어요",
                          ),
                        ),
                      );
                    },
                    child: const Text("수정"),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class PostEditPage extends StatefulWidget {
  final String postId;
  final String initialTitle;
  final String initialAreaText;
  final String initialBody;

  const PostEditPage({
    super.key,
    required this.postId,
    required this.initialTitle,
    required this.initialAreaText,
    required this.initialBody,
  });

  @override
  State<PostEditPage> createState() => _PostEditPageState();
}

class _PostEditPageState extends State<PostEditPage> {
  late final TextEditingController titleC;
  late final TextEditingController areaC;
  late final TextEditingController bodyC;

  @override
  void initState() {
    super.initState();
    titleC = TextEditingController(text: widget.initialTitle);
    areaC = TextEditingController(text: widget.initialAreaText);
    bodyC = TextEditingController(text: widget.initialBody);
  }

  @override
  void dispose() {
    titleC.dispose();
    areaC.dispose();
    bodyC.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final store = context.readStore();
    return Scaffold(
      appBar: AppBar(title: const Text("게시글 수정")),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: titleC,
            decoration: const InputDecoration(labelText: "제목"),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: areaC,
            decoration: const InputDecoration(labelText: "위치"),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: bodyC,
            minLines: 3,
            maxLines: 8,
            decoration: const InputDecoration(labelText: "내용"),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: () async {
              final messenger = ScaffoldMessenger.of(context);
              final navigator = Navigator.of(context);
              final title = titleC.text.trim();
              final areaText = areaC.text.trim();
              final body = bodyC.text.trim();
              if (title.isEmpty || areaText.isEmpty) {
                messenger.showSnackBar(
                  const SnackBar(content: Text("제목과 위치는 필수입니다.")),
                );
                return;
              }
              final synced = await store.editPostBasic(
                postId: widget.postId,
                title: title,
                areaText: areaText,
                body: body,
              );
              if (!mounted) return;
              navigator.pop(synced);
            },
            child: const Text("저장"),
          ),
        ],
      ),
    );
  }
}

class _DetailHero extends StatelessWidget {
  final Post post;
  const _DetailHero({required this.post});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 198,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        color: Theme.of(context).colorScheme.surfaceContainerHigh,
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (post.photoBase64 != null && post.photoBase64!.isNotEmpty)
            Image.memory(
              base64Decode(post.photoBase64!),
              fit: BoxFit.cover,
              width: double.infinity,
              height: double.infinity,
            )
          else
            Center(
              child: Icon(
                _postTypeIcon(post.type),
                size: 52,
              ),
            ),
          Positioned(
            left: 12,
            bottom: 12,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.36),
                borderRadius: BorderRadius.circular(99),
              ),
              child: Text(
                _postTypeLabel(post.type),
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  final Post post;
  const _InfoCard({required this.post});

  @override
  Widget build(BuildContext context) {
    final typeLabel = _postTypeLabel(post.type);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "$typeLabel 정보",
              style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 10),
            Text("$typeLabel 시간: ${_fmt(post.eventTime)}"),
            const SizedBox(height: 6),
            Text("위치: ${post.areaText}"),
            const SizedBox(height: 6),
            Text("거리: ${post.distanceKm.toStringAsFixed(1)}km"),
            const SizedBox(height: 6),
            Text("상태: ${post.status == PostStatus.active ? "진행중" : "해결"}"),
          ],
        ),
      ),
    );
  }
}

class _FeatureCard extends StatelessWidget {
  final Post post;
  const _FeatureCard({required this.post});

  @override
  Widget build(BuildContext context) {
    final chips = <String>[
      if (post.size != null) _sizeLabel(post.size!),
      ...post.colors,
      if (post.breedGuess != null) "견종: ${post.breedGuess}",
      "목줄: ${_collarLabel(post.collarState)}",
    ].where((e) => e.trim().isNotEmpty).toList();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "특징",
              style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: chips.map((c) => _ChipTag(text: c)).toList(),
            ),
          ],
        ),
      ),
    );
  }
}

class _CTASection extends StatelessWidget {
  final Post post;
  const _CTASection({required this.post});

  Future<void> _showContactSheet(BuildContext context) async {
    final phone = post.contactPhone?.trim() ?? "";
    final chat = post.openChatUrl?.trim() ?? "";
    if (phone.isEmpty && chat.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("등록된 연락처가 없어요")),
      );
      return;
    }

    await showModalBottomSheet<void>(
      context: context,
      builder: (ctx) {
        final messenger = ScaffoldMessenger.of(ctx);
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (phone.isNotEmpty)
                  ListTile(
                    leading: const Icon(Icons.call_outlined),
                    title: Text(phone),
                    subtitle: const Text("전화번호"),
                    trailing: TextButton(
                      onPressed: () async {
                        await Clipboard.setData(ClipboardData(text: phone));
                        if (!ctx.mounted) return;
                        messenger.showSnackBar(const SnackBar(content: Text("전화번호를 복사했어요")));
                      },
                      child: const Text("복사"),
                    ),
                  ),
                if (chat.isNotEmpty)
                  ListTile(
                    leading: const Icon(Icons.chat_outlined),
                    title: Text(
                      chat,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: const Text("오픈채팅"),
                    trailing: TextButton(
                      onPressed: () async {
                        await Clipboard.setData(ClipboardData(text: chat));
                        if (!ctx.mounted) return;
                        messenger.showSnackBar(const SnackBar(content: Text("오픈채팅 링크를 복사했어요")));
                      },
                      child: const Text("복사"),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (post.type == PostType.lost) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FilledButton.icon(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => TipCreatePage(postId: post.id)),
            ),
            icon: const Icon(Icons.add_comment),
            label: const Text("목격 제보하기"),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: () => _showContactSheet(context),
            icon: const Icon(Icons.call_outlined),
            label: const Text("연락하기"),
          ),
        ],
      );
    } else if (post.type == PostType.sighting) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FilledButton.icon(
            onPressed: () async {
              final messenger = ScaffoldMessenger.of(context);
              final text = [
                "[DogFinder] 목격 제보",
                post.title,
                "위치: ${post.areaText}",
                "시간: ${_fmt(post.eventTime)}",
                "메모: ${post.body}",
              ].join("\n");
              await Clipboard.setData(ClipboardData(text: text));
              if (!context.mounted) return;
              messenger.showSnackBar(const SnackBar(content: Text("전달용 문구를 복사했어요")));
            },
            icon: const Icon(Icons.notifications_active_outlined),
            label: const Text("주인에게 알려주기"),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: () {
              final store = context.readStore();
              final matches = store.matchLostPostsForSighting(post, limit: 20);
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => MatchPage(matches: matches)),
              );
            },
            icon: const Icon(Icons.search),
            label: const Text("비슷한 실종글 보기"),
          ),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FilledButton.icon(
          onPressed: () async {
            final messenger = ScaffoldMessenger.of(context);
            final text = [
              "[DogFinder] 보호 중 알림",
              post.title,
              "위치: ${post.areaText}",
              "시간: ${_fmt(post.eventTime)}",
              "상세: ${post.body}",
            ].join("\n");
            await Clipboard.setData(ClipboardData(text: text));
            if (!context.mounted) return;
            messenger.showSnackBar(const SnackBar(content: Text("전달용 문구를 복사했어요")));
          },
          icon: const Icon(Icons.campaign_outlined),
          label: const Text("보호중 알림 공유"),
        ),
        const SizedBox(height: 10),
        OutlinedButton.icon(
          onPressed: () => _showContactSheet(context),
          icon: const Icon(Icons.call_outlined),
          label: const Text("연락하기"),
        ),
      ],
    );
  }
}

class _TipTile extends StatelessWidget {
  final TipReport tip;
  const _TipTile({required this.tip});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        title: Text("${tip.situation} · ${_fmt(tip.seenTime)}"),
        subtitle: Text("${tip.seenAreaText}\n${tip.memo}"),
        isThreeLine: true,
        trailing: Wrap(
          spacing: 6,
          children: [
            if (tip.canCall) const Icon(Icons.call, size: 18),
            if (tip.canChat) const Icon(Icons.chat, size: 18),
          ],
        ),
      ),
    );
  }
}

Future<String?> _resolveDialog(BuildContext context) async {
  final c = TextEditingController();

  // ? dialogContext를 사용해서 pop 대상이 다이얼로그가 되게 함
  final result = await showDialog<String?>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text("해결 처리"),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text("선택: 어떻게 찾았는지 한 줄 후기를 남기면 커뮤니티 신뢰도가 올라가요."),
          const SizedBox(height: 10),
          TextField(
            controller: c,
            decoration: const InputDecoration(hintText: "예) 역삼동 편의점 근처에서 목격 제보로 찾음"),
            maxLines: 3,
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text("취소")),
        FilledButton(onPressed: () => Navigator.pop(dialogContext, c.text), child: const Text("해결 처리")),
      ],
    ),
  );

  c.dispose();
  return result;
}

/// --------------------------------------------
/// Tab 2: Register (+)
/// --------------------------------------------
class RegisterTab extends StatelessWidget {
  const RegisterTab({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("등록")),
      body: _AppLayeredBackground(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(14, 8, 14, 20),
          children: [
          Container(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              gradient: const LinearGradient(
                colors: [Color(0xFFEAF7F4), Color(0xFFF1F8FE)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              border: Border.all(color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.35)),
            ),
            child: Row(
              children: [
                const Icon(Icons.edit_note_outlined),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    "상황에 맞는 등록 유형을 선택해 주세요",
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _RegisterActionCard(
            icon: Icons.report_outlined,
            title: "실종 등록",
            desc: "우리 아이를 잃어버렸을 때 즉시 제보 등록",
            onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const LostCreatePage())),
          ),
          const SizedBox(height: 10),
          _RegisterActionCard(
            icon: Icons.visibility_outlined,
            title: "목격 등록",
            desc: "근처에서 본 아이를 빠르게 공유",
            onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SightingCreatePage())),
          ),
          const SizedBox(height: 10),
          _RegisterActionCard(
            icon: Icons.shield_outlined,
            title: "보호 등록",
            desc: "임시 보호 중인 아이 정보를 안전하게 공유",
            onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ShelterCreatePage())),
          ),
          const SizedBox(height: 10),
          _RegisterActionCard(
            icon: Icons.pets_outlined,
            title: "내 강아지로 빠른 실종 등록",
            desc: "등록된 프로필 정보를 자동 입력해 바로 게시",
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const LostCreatePage(prefillFromDog: true)),
            ),
          ),
          const SizedBox(height: 14),
          Text(
            "지도는 옵션이고, 기본은 리스트/필드 중심으로 빠르게 등록하도록 설계했어요.",
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  height: 1.45,
                ),
          ),
          ],
        ),
      ),
    );
  }
}

class _RegisterActionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String desc;
  final VoidCallback onTap;

  const _RegisterActionCard({
    required this.icon,
    required this.title,
    required this.desc,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white.withValues(alpha: 0.9),
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Ink(
          padding: const EdgeInsets.fromLTRB(14, 14, 12, 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            gradient: const LinearGradient(
              colors: [Color(0xFFFFFFFF), Color(0xFFF9FCFF)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            border: Border.all(color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.18)),
            boxShadow: const [
              BoxShadow(
                color: Color(0x10000000),
                blurRadius: 16,
                offset: Offset(0, 8),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: const Color(0xFFE8F5F3),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: const Color(0xFF0F766E), size: 21),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      desc,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                            height: 1.35,
                          ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: Color(0xFF7D8491)),
            ],
          ),
        ),
      ),
    );
  }
}

class _CreateHeaderCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String desc;

  const _CreateHeaderCard({
    required this.icon,
    required this.title,
    required this.desc,
  });

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
      tween: Tween(begin: 0, end: 1),
      builder: (context, v, child) {
        return Opacity(
          opacity: v,
          child: Transform.translate(
            offset: Offset(0, (1 - v) * 10),
            child: child,
          ),
        );
      },
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          gradient: const LinearGradient(
            colors: [Color(0xFFE7F7F4), Color(0xFFF0F6FF), Color(0xFFFFF5EC)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          border: Border.all(color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.2)),
          boxShadow: const [
            BoxShadow(
              color: Color(0x12000000),
              blurRadius: 20,
              offset: Offset(0, 10),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.85),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, size: 18, color: const Color(0xFF0F766E)),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    desc,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FormSection extends StatelessWidget {
  final String title;
  final Widget child;

  const _FormSection({
    required this.title,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.26)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x12000000),
            blurRadius: 18,
            offset: Offset(0, 9),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }
}

/// --------------------------------------------
/// Lost Create (controllers + prefill 1회)
/// --------------------------------------------
class LostCreatePage extends StatefulWidget {
  final bool prefillFromDog;
  const LostCreatePage({super.key, this.prefillFromDog = false});

  @override
  State<LostCreatePage> createState() => _LostCreatePageState();
}

class _LostCreatePageState extends State<LostCreatePage> {
  int step = 0;

  String? selectedDogId;
  bool _prefilled = false;

  DateTime eventTime = DateTime.now();
  String situation = "산책 중";
  LatLng? lostPoint;
  String? lostPhotoBase64;
  final ImagePicker _picker = ImagePicker();

  late final TextEditingController areaC;
  late final TextEditingController titleC;
  late final TextEditingController bodyC;

  // ? 연락처도 컨트롤러로(입력값 보존)
  late final TextEditingController phoneC;
  late final TextEditingController openChatC;

  @override
  void initState() {
    super.initState();
    areaC = TextEditingController();
    titleC = TextEditingController();
    bodyC = TextEditingController();
    phoneC = TextEditingController();
    openChatC = TextEditingController();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_prefilled) return;
    if (!widget.prefillFromDog) return;

    final store = context.readStore();
    if (store.dogs.isEmpty) return;

    final d = store.dogs.first;
    selectedDogId = d.id;
    titleC.text = "${d.breed ?? "견종 추정"} · ${d.collarDesc ?? "목줄 정보"}";
    bodyC.text = d.memo ?? "";
    _prefilled = true;
  }

  @override
  void dispose() {
    areaC.dispose();
    titleC.dispose();
    bodyC.dispose();
    phoneC.dispose();
    openChatC.dispose();
    super.dispose();
  }

  Future<void> _pickLostPhoto() async {
    try {
      final x = await _picker.pickImage(source: ImageSource.gallery, imageQuality: 75, maxWidth: 1440);
      if (x == null) return;
      final bytes = await x.readAsBytes();
      if (!mounted) return;
      setState(() => lostPhotoBase64 = base64Encode(bytes));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("사진을 불러오지 못했어요.")));
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watchStore();

    return Scaffold(
      appBar: AppBar(title: const Text("실종 등록")),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 8, 14, 0),
            child: _CreateHeaderCard(
              icon: Icons.report_outlined,
              title: "실종 등록",
              desc: "3단계 입력으로 실종 제보를 정확하게 올릴 수 있어요.",
            ),
          ),
          Expanded(
            child: Theme(
              data: Theme.of(context).copyWith(
                canvasColor: Colors.transparent,
                colorScheme: Theme.of(context).colorScheme.copyWith(
                      primary: Theme.of(context).colorScheme.primary,
                      surface: Colors.transparent,
                    ),
              ),
              child: Stepper(
                margin: const EdgeInsets.fromLTRB(6, 6, 6, 16),
                currentStep: step,
                onStepCancel: step == 0 ? null : () => setState(() => step -= 1),
                onStepContinue: () {
                  if (step < 2) {
                    setState(() => step += 1);
                  } else {
                    _submitLost(context);
                  }
                },
                controlsBuilder: (context, details) {
                  final last = step == 2;
                  return Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Row(
                      children: [
                        Expanded(
                          child: FilledButton(
                            onPressed: details.onStepContinue,
                            child: Text(last ? "등록하기" : "다음"),
                          ),
                        ),
                        const SizedBox(width: 12),
                        if (step != 0)
                          Expanded(
                            child: OutlinedButton(
                              onPressed: details.onStepCancel,
                              child: const Text("이전"),
                            ),
                          ),
                      ],
                    ),
                  );
                },
                steps: [
                  Step(
                    title: const Text("내 강아지 선택"),
                    isActive: step >= 0,
                    content: _FormSection(
                      title: "강아지 프로필 연결",
                      child: store.dogs.isEmpty
                          ? _EmptyStateInline(
                              title: "등록된 강아지가 없어요",
                              desc: "사전 등록하면 실종 등록이 훨씬 빨라져요.",
                              primaryText: "강아지 추가",
                              onPrimary: () => Navigator.of(context).push(
                                MaterialPageRoute(builder: (_) => const DogEditPage()),
                              ),
                            )
                          : Column(
                              children: [
                                ...store.dogs.map(
                                  (d) => Card(
                                    margin: const EdgeInsets.symmetric(vertical: 4),
                                    child: ListTile(
                                      onTap: () => setState(() => selectedDogId = d.id),
                                      title: Text(d.name),
                                      subtitle: Text("${_sizeLabel(d.size)} · ${d.colors.join(", ")}"),
                                      trailing: Icon(
                                        selectedDogId == d.id
                                            ? Icons.check_circle
                                            : Icons.radio_button_unchecked,
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Align(
                                  alignment: Alignment.centerLeft,
                                  child: OutlinedButton.icon(
                                    onPressed: () => Navigator.of(context).push(
                                      MaterialPageRoute(builder: (_) => const DogEditPage()),
                                    ),
                                    icon: const Icon(Icons.add),
                                    label: const Text("새 강아지 추가"),
                                  ),
                                ),
                              ],
                            ),
                    ),
                  ),
                  Step(
                    title: const Text("실종 정보"),
                    isActive: step >= 1,
                    content: _FormSection(
                      title: "발생 정보",
                      child: Column(
                        children: [
                          ListTile(
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            tileColor: Theme.of(context).colorScheme.surfaceContainerLowest,
                            title: const Text("실종 시간"),
                            subtitle: Text(_fmt(eventTime)),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () async {
                              final picked = await _pickDateAndTime(
                                context,
                                firstDate: DateTime.now().subtract(const Duration(days: 365)),
                                lastDate: DateTime.now(),
                                initial: eventTime,
                              );
                              if (picked == null) return;
                              setState(() => eventTime = picked);
                            },
                          ),
                          const SizedBox(height: 12),
                          _LocationPickerField(
                            controller: areaC,
                            labelText: "실종 위치",
                            hintText: "현재 위치 또는 지도에서 선택",
                            onLocationChanged: (p) => lostPoint = p,
                          ),
                          const SizedBox(height: 12),
                          DropdownButtonFormField<String>(
                            initialValue: situation,
                            items: const [
                              DropdownMenuItem(value: "산책 중", child: Text("산책 중")),
                              DropdownMenuItem(value: "문 열림", child: Text("문 열림")),
                              DropdownMenuItem(value: "목줄 풀림", child: Text("목줄 풀림")),
                              DropdownMenuItem(value: "기타", child: Text("기타")),
                            ],
                            onChanged: (v) => setState(() => situation = v ?? "산책 중"),
                            decoration: const InputDecoration(labelText: "당시 상황"),
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: phoneC,
                            decoration: const InputDecoration(labelText: "연락 전화번호(권장)", hintText: "010-0000-0000"),
                            keyboardType: TextInputType.phone,
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: openChatC,
                            decoration: const InputDecoration(labelText: "오픈채팅 링크(선택)"),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            "안전: 정확한 주소 공개는 금지하고, 동 단위/대략 위치만 입력하세요.",
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                                  height: 1.35,
                                ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  Step(
                    title: const Text("게시글 내용"),
                    isActive: step >= 2,
                    content: _FormSection(
                      title: "게시글 작성",
                      child: Column(
                        children: [
                          TextField(
                            controller: titleC,
                            decoration: const InputDecoration(labelText: "제목", hintText: "예) 푸들 추정, 빨간 목줄"),
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: bodyC,
                            decoration: const InputDecoration(labelText: "특징/메모", hintText: "예) 겁 많음, 사람 좋아함…"),
                            maxLines: 5,
                          ),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              FilledButton.tonalIcon(
                                onPressed: _pickLostPhoto,
                                icon: const Icon(Icons.photo_library_outlined),
                                label: const Text("사진 첨부"),
                              ),
                              const SizedBox(width: 8),
                              if (lostPhotoBase64 != null)
                                OutlinedButton(
                                  onPressed: () => setState(() => lostPhotoBase64 = null),
                                  child: const Text("제거"),
                                ),
                            ],
                          ),
                          if (lostPhotoBase64 != null) ...[
                            const SizedBox(height: 10),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: Image.memory(
                                base64Decode(lostPhotoBase64!),
                                height: 140,
                                width: double.infinity,
                                fit: BoxFit.cover,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _submitLost(BuildContext context) async {
    final store = context.readStore();

    if (titleC.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("제목을 입력해 주세요")));
      return;
    }
    if (areaC.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("실종 위치를 입력해 주세요")));
      return;
    }

    final dog = selectedDogId == null
        ? null
        : store.dogs.where((d) => d.id == selectedDogId).cast<DogProfile?>().firstWhere(
              (d) => d != null,
              orElse: () => null,
            );

    final contactPhone = phoneC.text.trim();
    final openChat = openChatC.text.trim().isEmpty ? null : openChatC.text.trim();

    final post = Post(
      id: AppStore._id(),
      type: PostType.lost,
      createdAt: DateTime.now(),
      eventTime: eventTime,
      areaText: areaC.text.trim(),
      distanceKm: _estimateDistanceKm(point: lostPoint, areaText: areaC.text.trim()),
      latitude: lostPoint?.latitude,
      longitude: lostPoint?.longitude,
      title: titleC.text.trim(),
      body: "[상황] $situation\n${bodyC.text.trim()}",
      ownerDeviceId: store.deviceId,
      size: dog?.size,
      colors: dog?.colors ?? const [],
      breedGuess: dog?.breed,
      collarState: dog?.collarState ?? CollarState.unknown,
      linkedDogId: dog?.id,
      photoBase64: lostPhotoBase64,
      contactPhone: contactPhone.isEmpty ? null : contactPhone,
      openChatUrl: openChat,
    );

    final synced = await store.addPost(post);
    if (!context.mounted) return;
    Navigator.of(context).pop();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          synced ? "실종글 등록 완료" : "서버 전송 실패: 로컬에 임시 저장했어요",
        ),
      ),
    );
  }
}

/// --------------------------------------------
/// Sighting Create (controllers + breedGuess controller)
/// --------------------------------------------
class SightingCreatePage extends StatefulWidget {
  const SightingCreatePage({super.key});

  @override
  State<SightingCreatePage> createState() => _SightingCreatePageState();
}

class _SightingCreatePageState extends State<SightingCreatePage> {
  DateTime seenTime = DateTime.now();
  DogSize size = DogSize.small;
  final Set<String> colors = {"갈색"};
  CollarState collarState = CollarState.unknown;
  String status = "배회";
  bool isProtecting = false;
  LatLng? sightingPoint;
  String? sightingPhotoBase64;
  final ImagePicker _picker = ImagePicker();

  late final TextEditingController areaC;
  late final TextEditingController memoC;
  late final TextEditingController breedGuessC;
  late final TextEditingController otherColorC;

  @override
  void initState() {
    super.initState();
    areaC = TextEditingController();
    memoC = TextEditingController();
    breedGuessC = TextEditingController();
    otherColorC = TextEditingController();
  }

  @override
  void dispose() {
    areaC.dispose();
    memoC.dispose();
    breedGuessC.dispose();
    otherColorC.dispose();
    super.dispose();
  }

  Future<void> _pickSightingPhoto() async {
    try {
      final x = await _picker.pickImage(source: ImageSource.gallery, imageQuality: 75, maxWidth: 1440);
      if (x == null) return;
      final bytes = await x.readAsBytes();
      if (!mounted) return;
      setState(() => sightingPhotoBase64 = base64Encode(bytes));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("사진을 불러오지 못했어요.")));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("목격 등록(빠르게)")),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(14, 8, 14, 20),
        children: [
          const _CreateHeaderCard(
            icon: Icons.visibility_outlined,
            title: "목격 등록",
            desc: "현장 정보를 입력해 보호자 찾기를 도와주세요.",
          ),
          const SizedBox(height: 12),
          _FormSection(
            title: "기본 정보",
            child: Column(
              children: [
                Row(
                  children: [
                    FilledButton.tonalIcon(
                      onPressed: _pickSightingPhoto,
                      icon: const Icon(Icons.photo_library_outlined),
                      label: const Text("사진 첨부"),
                    ),
                    const SizedBox(width: 8),
                    if (sightingPhotoBase64 != null)
                      OutlinedButton(
                        onPressed: () => setState(() => sightingPhotoBase64 = null),
                        child: const Text("제거"),
                      ),
                  ],
                ),
                if (sightingPhotoBase64 != null) ...[
                  const SizedBox(height: 10),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.memory(
                      base64Decode(sightingPhotoBase64!),
                      height: 140,
                      width: double.infinity,
                      fit: BoxFit.cover,
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                ListTile(
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  tileColor: Theme.of(context).colorScheme.surfaceContainerLowest,
                  title: const Text("목격 시간"),
                  subtitle: Text(_fmt(seenTime)),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () async {
                    final picked = await _pickDateAndTime(
                      context,
                      firstDate: DateTime.now().subtract(const Duration(days: 30)),
                      lastDate: DateTime.now(),
                      initial: seenTime,
                    );
                    if (picked == null) return;
                    setState(() => seenTime = picked);
                  },
                ),
                const SizedBox(height: 12),
                _LocationPickerField(
                  controller: areaC,
                  labelText: "목격 위치",
                  hintText: "현재 위치 또는 지도에서 선택",
                  onLocationChanged: (p) => sightingPoint = p,
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          _FormSection(
            title: "외형과 상황",
            child: Column(
              children: [
                DropdownButtonFormField<DogSize>(
                  initialValue: size,
                  items: const [
                    DropdownMenuItem(value: DogSize.small, child: Text("소형")),
                    DropdownMenuItem(value: DogSize.medium, child: Text("중형")),
                    DropdownMenuItem(value: DogSize.large, child: Text("대형")),
                  ],
                  onChanged: (v) => setState(() => size = v ?? DogSize.small),
                  decoration: const InputDecoration(labelText: "크기"),
                ),
                const SizedBox(height: 12),
                _ColorMultiSelect(
                  selected: colors,
                  otherColorController: otherColorC,
                  onChanged: (s) => setState(() {
                    colors
                      ..clear()
                      ..addAll(s);
                  }),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<CollarState>(
                  initialValue: collarState,
                  items: const [
                    DropdownMenuItem(value: CollarState.has, child: Text("목줄 있음")),
                    DropdownMenuItem(value: CollarState.none, child: Text("목줄 없음")),
                    DropdownMenuItem(value: CollarState.unknown, child: Text("모름")),
                  ],
                  onChanged: (v) => setState(() => collarState = v ?? CollarState.unknown),
                  decoration: const InputDecoration(labelText: "목줄"),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: breedGuessC,
                  decoration: const InputDecoration(labelText: "견종 추정(선택)", hintText: "예) 푸들"),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: status,
                  items: const [
                    DropdownMenuItem(value: "도망 중", child: Text("도망 중")),
                    DropdownMenuItem(value: "배회", child: Text("배회")),
                    DropdownMenuItem(value: "사람 따라옴", child: Text("사람 따라옴")),
                    DropdownMenuItem(value: "보호 중", child: Text("보호 중")),
                  ],
                  onChanged: (v) {
                    setState(() {
                      status = v ?? "배회";
                      isProtecting = status == "보호 중";
                    });
                  },
                  decoration: const InputDecoration(labelText: "상태"),
                ),
                if (isProtecting) ...[
                  const SizedBox(height: 10),
                  Text(
                    "보호 중이면 정확한 주소는 공개하지 마세요(기본 비공개).",
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                ],
                const SizedBox(height: 12),
                TextField(
                  controller: memoC,
                  decoration: const InputDecoration(labelText: "메모", hintText: "예) 공원 입구 쪽에서 봤어요"),
                  maxLines: 4,
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: () async {
              final store = context.readStore();
              final breedGuess = breedGuessC.text.trim();
              if (areaC.text.trim().isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("목격 위치를 선택해 주세요")));
                return;
              }

              final post = Post(
                id: AppStore._id(),
                type: PostType.sighting,
                createdAt: DateTime.now(),
                eventTime: seenTime,
                areaText: areaC.text.trim(),
                distanceKm: _estimateDistanceKm(point: sightingPoint, areaText: areaC.text.trim()),
                latitude: sightingPoint?.latitude,
                longitude: sightingPoint?.longitude,
                title: "${colors.isEmpty ? "색상 미상" : colors.first} ${_sizeLabel(size)}견 목격",
                body: memoC.text.trim().isEmpty ? "[$status] 목격" : "[$status] ${memoC.text.trim()}",
                ownerDeviceId: store.deviceId,
                size: size,
                colors: _applyOtherColor(colors, otherColorC.text),
                breedGuess: breedGuess.isEmpty ? null : breedGuess,
                collarState: collarState,
                photoBase64: sightingPhotoBase64,
              );

              final synced = await store.addPost(post);
              if (!context.mounted) return;
              if (!synced) {
                ScaffoldMessenger.of(context)
                    .showSnackBar(const SnackBar(content: Text("서버 전송 실패: 로컬에 임시 저장했어요")));
              }

              final matches = store.matchLostPostsForSighting(post, limit: 20);
              Navigator.of(context).pushReplacement(
                MaterialPageRoute(builder: (_) => MatchPage(matches: matches)),
              );
            },
            child: const Text("등록하기"),
          ),
        ],
      ),
    );
  }
}

class ShelterCreatePage extends StatefulWidget {
  const ShelterCreatePage({super.key});

  @override
  State<ShelterCreatePage> createState() => _ShelterCreatePageState();
}

class _ShelterCreatePageState extends State<ShelterCreatePage> {
  DateTime protectedAt = DateTime.now();
  DogSize size = DogSize.small;
  final Set<String> colors = {"갈색"};
  CollarState collarState = CollarState.unknown;
  LatLng? protectedPoint;
  String? shelterPhotoBase64;
  final ImagePicker _picker = ImagePicker();

  late final TextEditingController areaC;
  late final TextEditingController memoC;
  late final TextEditingController breedGuessC;
  late final TextEditingController shelterNameC;
  late final TextEditingController phoneC;
  late final TextEditingController openChatC;
  late final TextEditingController otherColorC;

  @override
  void initState() {
    super.initState();
    areaC = TextEditingController();
    memoC = TextEditingController();
    breedGuessC = TextEditingController();
    shelterNameC = TextEditingController();
    phoneC = TextEditingController();
    openChatC = TextEditingController();
    otherColorC = TextEditingController();
  }

  @override
  void dispose() {
    areaC.dispose();
    memoC.dispose();
    breedGuessC.dispose();
    shelterNameC.dispose();
    phoneC.dispose();
    openChatC.dispose();
    otherColorC.dispose();
    super.dispose();
  }

  Future<void> _pickPhoto() async {
    try {
      final x = await _picker.pickImage(source: ImageSource.gallery, imageQuality: 75, maxWidth: 1440);
      if (x == null) return;
      final bytes = await x.readAsBytes();
      if (!mounted) return;
      setState(() => shelterPhotoBase64 = base64Encode(bytes));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("사진을 불러오지 못했어요.")));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("보호 등록")),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(14, 8, 14, 20),
        children: [
          const _CreateHeaderCard(
            icon: Icons.shield_outlined,
            title: "보호 등록",
            desc: "보호 중인 아이 정보를 공유해 보호자 연결을 돕습니다.",
          ),
          const SizedBox(height: 12),
          _FormSection(
            title: "보호 기본 정보",
            child: Column(
              children: [
                Row(
                  children: [
                    FilledButton.tonalIcon(
                      onPressed: _pickPhoto,
                      icon: const Icon(Icons.photo_library_outlined),
                      label: const Text("사진 첨부"),
                    ),
                    const SizedBox(width: 8),
                    if (shelterPhotoBase64 != null)
                      OutlinedButton(
                        onPressed: () => setState(() => shelterPhotoBase64 = null),
                        child: const Text("제거"),
                      ),
                  ],
                ),
                if (shelterPhotoBase64 != null) ...[
                  const SizedBox(height: 10),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.memory(
                      base64Decode(shelterPhotoBase64!),
                      height: 140,
                      width: double.infinity,
                      fit: BoxFit.cover,
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                ListTile(
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  tileColor: Theme.of(context).colorScheme.surfaceContainerLowest,
                  title: const Text("보호 시작 시간"),
                  subtitle: Text(_fmt(protectedAt)),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () async {
                    final picked = await _pickDateAndTime(
                      context,
                      firstDate: DateTime.now().subtract(const Duration(days: 30)),
                      lastDate: DateTime.now(),
                      initial: protectedAt,
                    );
                    if (picked == null) return;
                    setState(() => protectedAt = picked);
                  },
                ),
                const SizedBox(height: 12),
                _LocationPickerField(
                  controller: areaC,
                  labelText: "보호 위치",
                  hintText: "현재 위치 또는 지도에서 선택",
                  onLocationChanged: (p) => protectedPoint = p,
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          _FormSection(
            title: "외형 및 연락 정보",
            child: Column(
              children: [
                DropdownButtonFormField<DogSize>(
                  initialValue: size,
                  items: const [
                    DropdownMenuItem(value: DogSize.small, child: Text("소형")),
                    DropdownMenuItem(value: DogSize.medium, child: Text("중형")),
                    DropdownMenuItem(value: DogSize.large, child: Text("대형")),
                  ],
                  onChanged: (v) => setState(() => size = v ?? DogSize.small),
                  decoration: const InputDecoration(labelText: "크기"),
                ),
                const SizedBox(height: 12),
                _ColorMultiSelect(
                  selected: colors,
                  otherColorController: otherColorC,
                  onChanged: (s) => setState(() {
                    colors
                      ..clear()
                      ..addAll(s);
                  }),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<CollarState>(
                  initialValue: collarState,
                  items: const [
                    DropdownMenuItem(value: CollarState.has, child: Text("목줄 있음")),
                    DropdownMenuItem(value: CollarState.none, child: Text("목줄 없음")),
                    DropdownMenuItem(value: CollarState.unknown, child: Text("모름")),
                  ],
                  onChanged: (v) => setState(() => collarState = v ?? CollarState.unknown),
                  decoration: const InputDecoration(labelText: "목줄"),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: breedGuessC,
                  decoration: const InputDecoration(labelText: "견종 추정(선택)", hintText: "예) 믹스"),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: shelterNameC,
                  decoration: const InputDecoration(labelText: "보호 장소/기관(선택)", hintText: "예) 개인 임시보호, OO보호소"),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: phoneC,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(labelText: "연락처(선택)", hintText: "010-0000-0000"),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: openChatC,
                  decoration: const InputDecoration(labelText: "오픈채팅 링크(선택)"),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: memoC,
                  maxLines: 4,
                  decoration: const InputDecoration(labelText: "메모", hintText: "발견 상황, 건강 상태, 보호 기간 등"),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: () async {
              if (areaC.text.trim().isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("보호 위치를 선택해 주세요")));
                return;
              }
              final store = context.readStore();
              final breedGuess = breedGuessC.text.trim();
              final shelterName = shelterNameC.text.trim();
              final bodyLines = <String>[
                if (shelterName.isNotEmpty) "보호처: $shelterName",
                if (memoC.text.trim().isNotEmpty) memoC.text.trim(),
              ];
              final post = Post(
                id: AppStore._id(),
                type: PostType.shelter,
                createdAt: DateTime.now(),
                eventTime: protectedAt,
                areaText: areaC.text.trim(),
                distanceKm: _estimateDistanceKm(point: protectedPoint, areaText: areaC.text.trim()),
                latitude: protectedPoint?.latitude,
                longitude: protectedPoint?.longitude,
                title: "보호신고 · ${colors.isEmpty ? "색상 미상" : colors.first} ${_sizeLabel(size)}견",
                body: bodyLines.isEmpty ? "임시 보호 중입니다." : bodyLines.join("\n"),
                ownerDeviceId: store.deviceId,
                size: size,
                colors: _applyOtherColor(colors, otherColorC.text),
                breedGuess: breedGuess.isEmpty ? null : breedGuess,
                collarState: collarState,
                photoBase64: shelterPhotoBase64,
                contactPhone: phoneC.text.trim().isEmpty ? null : phoneC.text.trim(),
                openChatUrl: openChatC.text.trim().isEmpty ? null : openChatC.text.trim(),
              );

              final synced = await store.addPost(post);
              if (!context.mounted) return;
              Navigator.of(context).pop();
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(synced ? "보호 등록 완료" : "서버 전송 실패: 로컬에 임시 저장했어요")),
              );
            },
            child: const Text("보호 등록하기"),
          ),
        ],
      ),
    );
  }
}

class MatchPage extends StatelessWidget {
  final List<Post> matches;
  const MatchPage({super.key, required this.matches});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("유사 실종글")),
      body: matches.isEmpty
          ? _EmptyState(
              title: "유사한 실종 글이 아직 없어요",
              desc: "대신 근처 실종글을 더 찾아보거나, 이 목격글을 공유해 주세요.",
              primaryText: "근처로",
              onPrimary: () => Navigator.of(context).pop(),
              secondaryText: "공유하기",
              onSecondary: () async {
                final messenger = ScaffoldMessenger.of(context);
                const text = "[DogFinder] 유사 실종글은 아직 없지만, 목격 등록이 올라왔어요. 근처 게시글을 확인해 주세요.";
                await Clipboard.setData(const ClipboardData(text: text));
                if (!context.mounted) return;
                messenger.showSnackBar(const SnackBar(content: Text("공유용 문구를 복사했어요")));
              },
            )
          : ListView.separated(
              padding: const EdgeInsets.all(12),
              itemBuilder: (_, i) => _PostCard(post: matches[i], revealIndex: i),
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemCount: matches.length,
            ),
    );
  }
}

/// --------------------------------------------
/// Tip Create
/// --------------------------------------------
class TipCreatePage extends StatefulWidget {
  final String postId;
  const TipCreatePage({super.key, required this.postId});

  @override
  State<TipCreatePage> createState() => _TipCreatePageState();
}

class _TipCreatePageState extends State<TipCreatePage> {
  DateTime seenTime = DateTime.now();
  String situation = "지나가다 봄";
  bool canCall = true;
  bool canChat = false;

  late final TextEditingController areaC;
  late final TextEditingController memoC;

  @override
  void initState() {
    super.initState();
    areaC = TextEditingController();
    memoC = TextEditingController();
  }

  @override
  void dispose() {
    areaC.dispose();
    memoC.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("제보하기")),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(14, 8, 14, 20),
        children: [
          const _CreateHeaderCard(
            icon: Icons.add_comment_outlined,
            title: "목격 제보 작성",
            desc: "핵심 정보만 입력하면 바로 보호자에게 전달됩니다.",
          ),
          const SizedBox(height: 12),
          _FormSection(
            title: "제보 정보",
            child: Column(
              children: [
                ListTile(
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  tileColor: Theme.of(context).colorScheme.surfaceContainerLowest,
                  title: const Text("목격 시간"),
                  subtitle: Text(_fmt(seenTime)),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () async {
                    final picked = await _pickDateAndTime(
                      context,
                      firstDate: DateTime.now().subtract(const Duration(days: 30)),
                      lastDate: DateTime.now(),
                      initial: seenTime,
                    );
                    if (picked == null) return;
                    setState(() => seenTime = picked);
                  },
                ),
                const SizedBox(height: 12),
                _LocationPickerField(
                  controller: areaC,
                  labelText: "목격 위치",
                  hintText: "현재 위치 또는 지도에서 선택",
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: situation,
                  items: const [
                    DropdownMenuItem(value: "지나가다 봄", child: Text("지나가다 봄")),
                    DropdownMenuItem(value: "잠깐 봄", child: Text("잠깐 봄")),
                    DropdownMenuItem(value: "따라가 봄", child: Text("따라가 봄")),
                    DropdownMenuItem(value: "보호 중", child: Text("보호 중")),
                    DropdownMenuItem(value: "기타", child: Text("기타")),
                  ],
                  onChanged: (v) => setState(() => situation = v ?? "지나가다 봄"),
                  decoration: const InputDecoration(labelText: "상황"),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: memoC,
                  maxLines: 4,
                  decoration: const InputDecoration(labelText: "메모", hintText: "예) ○○편의점 앞에서 봤어요"),
                ),
                const SizedBox(height: 10),
                SwitchListTile(
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  tileColor: Theme.of(context).colorScheme.surfaceContainerLowest,
                  value: canCall,
                  onChanged: (v) => setState(() => canCall = v),
                  title: const Text("전화 가능"),
                ),
                const SizedBox(height: 8),
                SwitchListTile(
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  tileColor: Theme.of(context).colorScheme.surfaceContainerLowest,
                  value: canChat,
                  onChanged: (v) => setState(() => canChat = v),
                  title: const Text("채팅 가능"),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: () async {
              if (areaC.text.trim().isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("목격 위치를 선택해 주세요")));
                return;
              }
              final store = context.readStore();
              final tip = TipReport(
                id: AppStore._id(),
                postId: widget.postId,
                reporterId: store.authUserId ?? store.deviceId,
                createdAt: DateTime.now(),
                seenTime: seenTime,
                seenAreaText: areaC.text.trim(),
                situation: situation,
                memo: memoC.text.trim(),
                canCall: canCall,
                canChat: canChat,
              );
              final synced = await store.addTip(tip);
              if (!context.mounted) return;
              Navigator.of(context).pop();
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    synced ? "제보가 전달됐어요" : "서버 전송 실패: 로컬에 임시 저장했어요",
                  ),
                ),
              );
            },
            child: const Text("제보 보내기"),
          ),
        ],
      ),
    );
  }
}

/// --------------------------------------------
/// Tab 3: My Dogs
/// --------------------------------------------
class MyDogsTab extends StatelessWidget {
  const MyDogsTab({super.key});

  @override
  Widget build(BuildContext context) {
    final store = context.watchStore();

    return Scaffold(
      appBar: AppBar(
        title: const Text("내 강아지"),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const DogEditPage())),
          ),
        ],
      ),
      body: _AppLayeredBackground(
        child: Column(
          children: [
          Container(
            margin: const EdgeInsets.fromLTRB(14, 8, 14, 0),
            child: _CreateHeaderCard(
              icon: Icons.pets_outlined,
              title: "내 강아지 관리",
              desc: "프로필을 등록해두면 실종 대응이 빨라져요. (${store.dogs.length}마리)",
            ),
          ),
          Expanded(
            child: store.dogs.isEmpty
                ? _EmptyState(
                    title: "사전 등록된 강아지가 없어요",
                    desc: "미리 등록해두면 실종 시 즉시 글을 올릴 수 있어요.",
                    primaryText: "강아지 추가",
                    onPrimary: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const DogEditPage())),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(14, 10, 14, 90),
                    itemBuilder: (_, i) {
                      final d = store.dogs[i];
                      return Card(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
                          child: Column(
                            children: [
                              Row(
                                children: [
                                  CircleAvatar(
                                    backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                                    child: Icon(Icons.pets, color: Theme.of(context).colorScheme.onPrimaryContainer),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(d.name, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                                        const SizedBox(height: 2),
                                        Text(
                                          "${d.breed ?? "견종 미상"} · ${_sizeLabel(d.size)} · ${d.colors.join(", ")}",
                                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                                color: Theme.of(context).colorScheme.onSurfaceVariant,
                                              ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 10),
                              Row(
                                children: [
                                  Expanded(
                                    child: OutlinedButton(
                                      onPressed: () => Navigator.of(context).push(
                                        MaterialPageRoute(builder: (_) => DogDetailPage(dogId: d.id)),
                                      ),
                                      child: const Text("프로필 보기"),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: FilledButton.tonal(
                                      onPressed: () => Navigator.of(context).push(
                                        MaterialPageRoute(builder: (_) => const LostCreatePage(prefillFromDog: true)),
                                      ),
                                      child: const Text("실종 등록"),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                    separatorBuilder: (_, __) => const SizedBox(height: 12),
                    itemCount: store.dogs.length,
                  ),
          ),
          ],
        ),
      ),
    );
  }
}

class DogDetailPage extends StatelessWidget {
  final String dogId;
  const DogDetailPage({super.key, required this.dogId});

  @override
  Widget build(BuildContext context) {
    final store = context.watchStore();
    final dog = store.dogs.where((d) => d.id == dogId).cast<DogProfile?>().firstWhere(
          (d) => d != null,
          orElse: () => null,
        );

    if (dog == null) {
      return Scaffold(
        appBar: AppBar(title: const Text("프로필")),
        body: const Center(child: Text("강아지 프로필을 찾을 수 없어요.")),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(dog.name),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => DogEditPage(existing: dog)),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            onPressed: () async {
              final ok = await showDialog<bool>(
                context: context,
                builder: (_) => AlertDialog(
                  title: const Text("삭제할까요?"),
                  content: const Text("삭제하면 되돌릴 수 없어요."),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(context, false), child: const Text("취소")),
                    FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text("삭제")),
                  ],
                ),
              );
              if (ok == true) {
                store.deleteDog(dog.id);
                if (context.mounted) Navigator.of(context).pop();
              }
            },
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 20),
        children: [
          Container(
            height: 190,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              color: Theme.of(context).colorScheme.surfaceContainerHigh,
            ),
            alignment: Alignment.center,
            child: const Icon(Icons.pets, size: 56),
          ),
          const SizedBox(height: 10),
          _FormSection(
            title: "프로필 정보",
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text("이름: ${dog.name}"),
                const SizedBox(height: 6),
                Text("견종: ${dog.breed ?? "미상"}"),
                const SizedBox(height: 6),
                Text("크기: ${_sizeLabel(dog.size)}"),
                const SizedBox(height: 6),
                Text("색상: ${dog.colors.join(", ")}"),
                const SizedBox(height: 6),
                Text("목줄: ${_collarLabel(dog.collarState)} ${dog.collarDesc ?? ""}"),
                if (dog.memo != null && dog.memo!.trim().isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Text("특이사항: ${dog.memo}"),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class DogEditPage extends StatefulWidget {
  final DogProfile? existing;
  const DogEditPage({super.key, this.existing});

  @override
  State<DogEditPage> createState() => _DogEditPageState();
}

class _DogEditPageState extends State<DogEditPage> {
  late final TextEditingController nameC;
  late final TextEditingController breedC;
  late final TextEditingController collarDescC;
  late final TextEditingController memoC;
  late final TextEditingController otherColorC;

  DogSize size = DogSize.small;
  final Set<String> colors = {};
  CollarState collarState = CollarState.unknown;

  @override
  void initState() {
    super.initState();
    final ex = widget.existing;
    nameC = TextEditingController(text: ex?.name ?? "");
    breedC = TextEditingController(text: ex?.breed ?? "");
    collarDescC = TextEditingController(text: ex?.collarDesc ?? "");
    memoC = TextEditingController(text: ex?.memo ?? "");
    otherColorC = TextEditingController();

    if (ex != null) {
      size = ex.size;
      colors.addAll(ex.colors);
      collarState = ex.collarState;
    } else {
      colors.add("갈색");
    }
  }

  @override
  void dispose() {
    nameC.dispose();
    breedC.dispose();
    collarDescC.dispose();
    memoC.dispose();
    otherColorC.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final store = context.readStore();
    return Scaffold(
      appBar: AppBar(title: Text(widget.existing == null ? "강아지 추가" : "프로필 수정")),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(14, 8, 14, 20),
        children: [
          _CreateHeaderCard(
            icon: Icons.pets_outlined,
            title: widget.existing == null ? "강아지 추가" : "프로필 수정",
            desc: "실종 대비를 위해 프로필 정보를 자세히 입력해 주세요.",
          ),
          const SizedBox(height: 12),
          _FormSection(
            title: "기본 정보",
            child: Column(
              children: [
                TextField(controller: nameC, decoration: const InputDecoration(labelText: "이름(필수)")),
                const SizedBox(height: 12),
                DropdownButtonFormField<DogSize>(
                  initialValue: size,
                  items: const [
                    DropdownMenuItem(value: DogSize.small, child: Text("소형")),
                    DropdownMenuItem(value: DogSize.medium, child: Text("중형")),
                    DropdownMenuItem(value: DogSize.large, child: Text("대형")),
                  ],
                  onChanged: (v) => setState(() => size = v ?? DogSize.small),
                  decoration: const InputDecoration(labelText: "크기"),
                ),
                const SizedBox(height: 12),
                _ColorMultiSelect(
                  selected: colors,
                  otherColorController: otherColorC,
                  onChanged: (s) => setState(() {
                    colors
                      ..clear()
                      ..addAll(s);
                  }),
                ),
                const SizedBox(height: 12),
                TextField(controller: breedC, decoration: const InputDecoration(labelText: "견종(선택)")),
              ],
            ),
          ),
          const SizedBox(height: 10),
          _FormSection(
            title: "세부 정보",
            child: Column(
              children: [
                DropdownButtonFormField<CollarState>(
                  initialValue: collarState,
                  items: const [
                    DropdownMenuItem(value: CollarState.has, child: Text("목줄 있음")),
                    DropdownMenuItem(value: CollarState.none, child: Text("목줄 없음")),
                    DropdownMenuItem(value: CollarState.unknown, child: Text("모름")),
                  ],
                  onChanged: (v) => setState(() => collarState = v ?? CollarState.unknown),
                  decoration: const InputDecoration(labelText: "목줄 상태"),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: collarDescC,
                  decoration: const InputDecoration(labelText: "목줄 특징(선택)", hintText: "예) 빨간 하네스, 은색 버클"),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: memoC,
                  decoration: const InputDecoration(labelText: "특이사항/성격(선택)"),
                  maxLines: 3,
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: () {
              final name = nameC.text.trim();
              if (name.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("이름은 필수입니다")));
                return;
              }
              if (colors.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("색상을 1개 이상 선택해 주세요")));
                return;
              }

              if (widget.existing == null) {
                store.addDog(
                  DogProfile(
                    id: AppStore._id(),
                    name: name,
                    size: size,
                    colors: _applyOtherColor(colors, otherColorC.text),
                    breed: breedC.text.trim().isEmpty ? null : breedC.text.trim(),
                    collarState: collarState,
                    collarDesc: collarDescC.text.trim().isEmpty ? null : collarDescC.text.trim(),
                    memo: memoC.text.trim().isEmpty ? null : memoC.text.trim(),
                  ),
                );
              } else {
                final d = widget.existing!;
                store.updateDog(
                  DogProfile(
                    id: d.id,
                    name: name,
                    size: size,
                    colors: _applyOtherColor(colors, otherColorC.text),
                    breed: breedC.text.trim().isEmpty ? null : breedC.text.trim(),
                    collarState: collarState,
                    collarDesc: collarDescC.text.trim().isEmpty ? null : collarDescC.text.trim(),
                    memo: memoC.text.trim().isEmpty ? null : memoC.text.trim(),
                  ),
                );
              }

              Navigator.of(context).pop();
            },
            child: const Text("저장"),
          ),
        ],
      ),
    );
  }
}

class _ColorMultiSelect extends StatelessWidget {
  final Set<String> selected;
  final ValueChanged<Set<String>> onChanged;
  final TextEditingController? otherColorController;

  const _ColorMultiSelect({required this.selected, required this.onChanged, this.otherColorController});

  @override
  Widget build(BuildContext context) {
    const all = ["흰색", "검정", "갈색", "회색", "믹스", "기타"];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text("색상(다중)", style: TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: all.map((c) {
            final on = selected.contains(c);
            return FilterChip(
              label: Text(c),
              selected: on,
              onSelected: (v) {
                final next = Set<String>.from(selected);
                if (v) {
                  next.add(c);
                } else {
                  next.remove(c);
                }
                onChanged(next);
              },
            );
          }).toList(),
        ),
        if (selected.contains("기타")) ...[
          const SizedBox(height: 10),
          TextField(
            controller: otherColorController,
            decoration: const InputDecoration(labelText: "기타 색상 직접 입력", hintText: "예) 크림, 탄색"),
          ),
        ],
      ],
    );
  }
}

/// --------------------------------------------
/// Tab 4: My Activity
/// --------------------------------------------
class MyActivityTab extends StatefulWidget {
  const MyActivityTab({super.key});

  @override
  State<MyActivityTab> createState() => _MyActivityTabState();
}

class _MyActivityTabState extends State<MyActivityTab> {
  int seg = 0;
  bool isSyncing = false;

  Future<void> _syncNow(AppStore store) async {
    final messenger = ScaffoldMessenger.of(context);
    if (store.backendApi == null) {
      messenger.showSnackBar(
        const SnackBar(content: Text("백엔드 미연결 상태입니다.")),
      );
      return;
    }

    setState(() => isSyncing = true);
    final pendingResult = await store.syncPendingOps();
    await store.syncFromBackend();
    if (!mounted) return;
    setState(() => isSyncing = false);
    messenger.showSnackBar(
      SnackBar(content: Text(pendingResult.summaryWithRemaining(store.pendingOpsCount))),
    );
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watchStore();
    final pendingCount = store.pendingOpsCount;

    if (!store.isLoggedIn) {
      return Scaffold(
        appBar: AppBar(title: const Text("내 활동")),
        body: const _LoginGate(),
      );
    }

    final myPosts = store.posts.where(store.isMine).toList();
    final myLost = myPosts.where((p) => p.type == PostType.lost).toList();
    final mySighting = myPosts.where((p) => p.type == PostType.sighting).toList();
    final myShelter = myPosts.where((p) => p.type == PostType.shelter).toList();
    final savedPosts = store.posts.where((p) => store.isSavedPost(p.id)).toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    final myReporterId = store.authUserId ?? store.deviceId;
    final myTips = store.tips.where((t) => t.reporterId == myReporterId).toList();

    List<Post> list = const [];
    String empty = "";
    Widget? customBody;
    switch (seg) {
      case 0:
        list = myLost;
        empty = "내 실종글이 없어요";
        break;
      case 1:
        list = mySighting;
        empty = "내 목격글이 없어요";
        break;
      case 2:
        list = myShelter;
        empty = "내 보호글이 없어요";
        break;
      case 3:
        customBody = savedPosts.isEmpty
            ? _EmptyState(
                title: "저장한 글이 없어요",
                desc: "글 상세 화면의 북마크 버튼으로 저장해 보세요.",
                primaryText: "근처 글 보기",
                onPrimary: () => ScaffoldMessenger.of(context)
                    .showSnackBar(const SnackBar(content: Text("하단 탭의 근처를 눌러주세요"))),
              )
            : ListView.separated(
                padding: const EdgeInsets.fromLTRB(14, 6, 14, 90),
                itemBuilder: (_, i) => _PostCard(post: savedPosts[i], revealIndex: i),
                separatorBuilder: (_, __) => const SizedBox(height: 12),
                itemCount: savedPosts.length,
              );
        break;
      default:
        customBody = myTips.isEmpty
            ? _EmptyState(
                title: "내가 보낸 제보가 없어요",
                desc: "실종글 상세에서 제보를 남기면 여기에서 볼 수 있어요.",
                primaryText: "근처 글 보기",
                onPrimary: () => ScaffoldMessenger.of(context)
                    .showSnackBar(const SnackBar(content: Text("하단 탭의 근처를 눌러주세요"))),
              )
            : ListView.separated(
                padding: const EdgeInsets.fromLTRB(14, 6, 14, 90),
                itemBuilder: (_, i) {
                  final tip = myTips[i];
                  final post = store.posts
                      .where((p) => p.id == tip.postId)
                      .cast<Post?>()
                      .firstWhere((p) => p != null, orElse: () => null);
                  return Card(
                    child: ListTile(
                      leading: CircleAvatar(
                        backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                        child: Icon(
                          Icons.campaign_outlined,
                          color: Theme.of(context).colorScheme.onPrimaryContainer,
                        ),
                      ),
                      title: Text(post?.title ?? "게시글 정보 없음"),
                      subtitle: Text(
                        "${tip.seenAreaText}\n${tip.memo.isEmpty ? tip.situation : tip.memo}",
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: Text(_fmt(tip.createdAt), style: const TextStyle(fontSize: 12)),
                      onTap: post == null
                          ? null
                          : () => Navigator.of(context).push(
                                MaterialPageRoute(builder: (_) => PostDetailPage(postId: post.id)),
                              ),
                    ),
                  );
                },
                separatorBuilder: (_, __) => const SizedBox(height: 12),
                itemCount: myTips.length,
              );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text("내 활동 · ${store.authName ?? ""}"),
        actions: [
          IconButton(
            icon: isSyncing
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Stack(
                    clipBehavior: Clip.none,
                    children: [
                      const Icon(Icons.sync),
                      if (pendingCount > 0)
                        Positioned(
                          right: -2,
                          top: -2,
                          child: Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              color: Theme.of(context).colorScheme.error,
                              shape: BoxShape.circle,
                            ),
                          ),
                        ),
                    ],
                  ),
            tooltip: pendingCount > 0 ? "동기화 (대기 $pendingCount건)" : "동기화",
            onLongPress: () => _showPendingOpsSheet(context, store),
            onPressed: isSyncing
                ? null
                : () => _syncNow(store),
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () async {
              try {
                if (store.authProvider == "kakao") {
                  await UserApi.instance.logout();
                } else if (store.authProvider == "naver") {
                  await FlutterNaverLogin.logOutAndDeleteToken();
                }
              } catch (_) {}
              await store.signOut();
            },
          ),
        ],
      ),
      body: _AppLayeredBackground(
        child: Column(
          children: [
          Container(
            margin: const EdgeInsets.fromLTRB(14, 6, 14, 0),
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.35)),
            ),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 16,
                  backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                  child: Icon(Icons.person_outline, color: Theme.of(context).colorScheme.onPrimaryContainer, size: 18),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    "${store.authName ?? ""}님의 활동",
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
                  ),
                ),
                Text(
                  "대기 $pendingCount",
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 8),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.35)),
              ),
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: SegmentedButton<int>(
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(value: 0, label: Text("실종")),
                    ButtonSegment(value: 1, label: Text("목격")),
                    ButtonSegment(value: 2, label: Text("보호")),
                    ButtonSegment(value: 3, label: Text("저장")),
                    ButtonSegment(value: 4, label: Text("제보")),
                  ],
                  selected: {seg},
                  onSelectionChanged: (s) => setState(() => seg = s.first),
                ),
              ),
            ),
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () => _syncNow(store),
              child: customBody ??
                  (list.isEmpty
                      ? ListView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          children: [
                            SizedBox(
                              height: MediaQuery.of(context).size.height * 0.5,
                              child: _EmptyState(
                                title: empty,
                                desc: "등록 탭에서 실종/목격/보호 글을 작성해 보세요.",
                                primaryText: "등록하러 가기",
                                onPrimary: () => ScaffoldMessenger.of(context)
                                    .showSnackBar(const SnackBar(content: Text("하단 탭의 등록(+)을 눌러주세요"))),
                              ),
                            ),
                          ],
                        )
                      : ListView.separated(
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: const EdgeInsets.fromLTRB(14, 6, 14, 90),
                          itemBuilder: (_, i) => _PostCard(post: list[i], revealIndex: i),
                          separatorBuilder: (_, __) => const SizedBox(height: 12),
                          itemCount: list.length,
                        )),
            ),
          ),
          ],
        ),
      ),
    );
  }
}

/// --------------------------------------------
/// Shared Empty States
/// --------------------------------------------
class _EmptyState extends StatelessWidget {
  final String title;
  final String desc;
  final String primaryText;
  final VoidCallback onPrimary;
  final String? secondaryText;
  final VoidCallback? onSecondary;

  const _EmptyState({
    required this.title,
    required this.desc,
    required this.primaryText,
    required this.onPrimary,
    this.secondaryText,
    this.onSecondary,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Container(
          width: 360,
          padding: const EdgeInsets.fromLTRB(18, 20, 18, 18),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFFFFFFFF), Color(0xFFF7FBFF)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.28)),
            boxShadow: const [
              BoxShadow(
                color: Color(0x14000000),
                blurRadius: 22,
                offset: Offset(0, 12),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: const Color(0xFFE8F5F3),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.pets_outlined, color: Color(0xFF0F766E)),
              ),
              const SizedBox(height: 12),
              Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              Text(desc, textAlign: TextAlign.center, style: const TextStyle(height: 1.45)),
              const SizedBox(height: 16),
              SizedBox(width: 220, child: FilledButton(onPressed: onPrimary, child: Text(primaryText))),
              if (secondaryText != null && onSecondary != null) ...[
                const SizedBox(height: 10),
                SizedBox(width: 220, child: OutlinedButton(onPressed: onSecondary, child: Text(secondaryText!))),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyStateInline extends StatelessWidget {
  final String title;
  final String desc;
  final String primaryText;
  final VoidCallback onPrimary;

  const _EmptyStateInline({
    required this.title,
    required this.desc,
    required this.primaryText,
    required this.onPrimary,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          Text(desc, style: const TextStyle(height: 1.4)),
          const SizedBox(height: 10),
          OutlinedButton.icon(onPressed: onPrimary, icon: const Icon(Icons.add), label: Text(primaryText)),
        ],
      ),
    );
  }
}

class PendingPayloadPanel extends StatelessWidget {
  final String prettyPayload;
  final Future<void> Function() onCopy;

  const PendingPayloadPanel({
    super.key,
    required this.prettyPayload,
    required this.onCopy,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text("Payload", style: TextStyle(fontWeight: FontWeight.w700)),
            const Spacer(),
            TextButton.icon(
              onPressed: () => onCopy(),
              icon: const Icon(Icons.copy, size: 16),
              label: const Text("복사"),
            ),
          ],
        ),
        SelectableText(
          prettyPayload,
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }
}

class PendingSheetActionBar extends StatelessWidget {
  final bool busy;
  final int suspendedCount;
  final VoidCallback? onRetry;
  final VoidCallback? onForceRetry;
  final VoidCallback? onClear;
  final VoidCallback? onClearSuspended;

  const PendingSheetActionBar({
    super.key,
    required this.busy,
    required this.suspendedCount,
    this.onRetry,
    this.onForceRetry,
    this.onClear,
    this.onClearSuspended,
  });

  @override
  Widget build(BuildContext context) {
    final retry = busy ? null : onRetry;
    final force = busy ? null : onForceRetry;
    final clear = busy ? null : onClear;
    final clearSuspended = busy ? null : onClearSuspended;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        TextButton.icon(
          onPressed: retry,
          icon: const Icon(Icons.sync, size: 18),
          label: const Text("지금 재시도"),
        ),
        TextButton.icon(
          onPressed: force,
          icon: const Icon(Icons.flash_on, size: 18),
          label: const Text("강제 재시도"),
        ),
        TextButton.icon(
          onPressed: clear,
          icon: const Icon(Icons.delete_outline, size: 18),
          label: const Text("비우기"),
        ),
        if (suspendedCount > 0)
          TextButton.icon(
            onPressed: clearSuspended,
            icon: const Icon(Icons.warning_amber_outlined, size: 18),
            label: Text("실패많음 $suspendedCount건"),
          ),
      ],
    );
  }
}

class PendingSelectionActionBar extends StatelessWidget {
  final bool busy;
  final bool hasSuspendedSelected;
  final VoidCallback? onRetrySelected;
  final VoidCallback? onReactivateSelected;
  final VoidCallback? onDeleteSelected;

  const PendingSelectionActionBar({
    super.key,
    required this.busy,
    required this.hasSuspendedSelected,
    this.onRetrySelected,
    this.onReactivateSelected,
    this.onDeleteSelected,
  });

  @override
  Widget build(BuildContext context) {
    final retry = busy ? null : onRetrySelected;
    final reactivate = (busy || !hasSuspendedSelected) ? null : onReactivateSelected;
    final remove = busy ? null : onDeleteSelected;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        TextButton.icon(
          onPressed: retry,
          icon: const Icon(Icons.flash_on, size: 18),
          label: const Text("선택 재시도"),
        ),
        TextButton.icon(
          onPressed: reactivate,
          icon: const Icon(Icons.restart_alt, size: 18),
          label: const Text("선택 재활성화"),
        ),
        TextButton.icon(
          onPressed: remove,
          icon: const Icon(Icons.delete_outline, size: 18),
          label: const Text("선택 삭제"),
        ),
      ],
    );
  }
}

class _LocationPickerField extends StatefulWidget {
  final TextEditingController controller;
  final String labelText;
  final String hintText;
  final ValueChanged<LatLng>? onLocationChanged;

  const _LocationPickerField({
    required this.controller,
    required this.labelText,
    required this.hintText,
    this.onLocationChanged,
  });

  @override
  State<_LocationPickerField> createState() => _LocationPickerFieldState();
}

class _LocationPickerFieldState extends State<_LocationPickerField> {
  bool _loadingCurrent = false;
  bool _loadingAddress = false;

  Future<String> _resolveAddress(double lat, double lng) async {
    try {
      final marks = await placemarkFromCoordinates(lat, lng);
      if (marks.isEmpty) return "";
      final p = marks.first;
      final parts = <String>[
        p.administrativeArea ?? "",
        p.subAdministrativeArea ?? "",
        p.locality ?? "",
        p.subLocality ?? "",
      ].where((e) => e.trim().isNotEmpty).toList();
      return parts.join(" ");
    } catch (_) {
      return "";
    }
  }

  Future<void> _setPickedLocation({
    required String sourceLabel,
    required double latitude,
    required double longitude,
  }) async {
    setState(() => _loadingAddress = true);
    final address = await _resolveAddress(latitude, longitude);
    final coordinate = "(${latitude.toStringAsFixed(5)}, ${longitude.toStringAsFixed(5)})";
    widget.controller.text = address.isEmpty ? "$sourceLabel $coordinate" : "$sourceLabel $address $coordinate";
    widget.onLocationChanged?.call(LatLng(latitude, longitude));
    if (mounted) {
      setState(() => _loadingAddress = false);
    }
  }

  Future<void> _pickCurrentLocation() async {
    setState(() => _loadingCurrent = true);
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("위치 서비스가 꺼져 있어요.")));
        }
        return;
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("위치 권한이 필요해요.")));
        }
        return;
      }

      final pos = await Geolocator.getCurrentPosition();
      await _setPickedLocation(
        sourceLabel: "현재 위치",
        latitude: pos.latitude,
        longitude: pos.longitude,
      );
      if (mounted) setState(() {});
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("현재 위치를 가져오지 못했어요.")));
      }
    } finally {
      if (mounted) setState(() => _loadingCurrent = false);
    }
  }

  Future<void> _pickOnMap() async {
    final result = await Navigator.of(context).push<LatLng>(
      MaterialPageRoute(builder: (_) => const MapPickPage()),
    );
    if (result == null) return;
    await _setPickedLocation(
      sourceLabel: "지도 선택",
      latitude: result.latitude,
      longitude: result.longitude,
    );
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: widget.controller,
          readOnly: true,
          decoration: InputDecoration(labelText: widget.labelText, hintText: widget.hintText),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            FilledButton.tonalIcon(
              onPressed: _loadingCurrent ? null : _pickCurrentLocation,
              icon: const Icon(Icons.my_location),
              label: Text(_loadingCurrent ? "불러오는 중..." : "현재 내 위치"),
            ),
            OutlinedButton.icon(
              onPressed: _pickOnMap,
              icon: const Icon(Icons.map_outlined),
              label: const Text("지도에서 선택"),
            ),
          ],
        ),
        if (_loadingAddress) ...[
          const SizedBox(height: 8),
          const Text("주소 확인 중...", style: TextStyle(fontSize: 12)),
        ],
      ],
    );
  }
}

class MapPickPage extends StatefulWidget {
  const MapPickPage({super.key});

  @override
  State<MapPickPage> createState() => _MapPickPageState();
}

class _MapPickPageState extends State<MapPickPage> {
  LatLng selected = const LatLng(37.4979, 127.0276);
  String _address = "";
  bool _resolving = false;
  int _resolveSeq = 0;

  @override
  void initState() {
    super.initState();
    _updateAddress(selected);
  }

  Future<void> _updateAddress(LatLng point) async {
    final seq = ++_resolveSeq;
    setState(() => _resolving = true);
    try {
      final marks = await placemarkFromCoordinates(point.latitude, point.longitude);
      if (!mounted || seq != _resolveSeq) return;
      if (marks.isEmpty) {
        setState(() {
          _address = "";
          _resolving = false;
        });
        return;
      }
      final p = marks.first;
      final parts = <String>[
        p.administrativeArea ?? "",
        p.subAdministrativeArea ?? "",
        p.locality ?? "",
        p.subLocality ?? "",
      ].where((e) => e.trim().isNotEmpty).toList();
      setState(() {
        _address = parts.join(" ");
        _resolving = false;
      });
    } catch (_) {
      if (!mounted || seq != _resolveSeq) return;
      setState(() {
        _address = "";
        _resolving = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("지도에서 위치 선택")),
      body: Column(
        children: [
          Expanded(
            child: FlutterMap(
              options: MapOptions(
                initialCenter: selected,
                initialZoom: 14,
                onTap: (_, latlng) {
                  setState(() => selected = latlng);
                  _updateAddress(latlng);
                },
              ),
              children: [
                TileLayer(
                  urlTemplate: "https://tile.openstreetmap.org/{z}/{x}/{y}.png",
                  userAgentPackageName: "com.example.dogfinder",
                ),
                MarkerLayer(
                  markers: [
                    Marker(
                      point: selected,
                      width: 40,
                      height: 40,
                      child: const Icon(Icons.location_on, color: Colors.red, size: 36),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "${selected.latitude.toStringAsFixed(5)}, ${selected.longitude.toStringAsFixed(5)}",
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _resolving ? "주소 확인 중..." : (_address.isEmpty ? "주소를 찾지 못했어요" : _address),
                        style: const TextStyle(fontSize: 12),
                      ),
                    ],
                  ),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(context).pop(selected),
                  child: const Text("이 위치 사용"),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

Future<DateTime?> _pickDateAndTime(
  BuildContext context, {
  required DateTime initial,
  required DateTime firstDate,
  required DateTime lastDate,
}) async {
  final d = await showDatePicker(
    context: context,
    firstDate: firstDate,
    lastDate: lastDate,
    initialDate: initial,
  );
  if (d == null) return null;
  if (!context.mounted) return null;

  int hour = initial.hour;
  int minute = initial.minute;
  final ok = await showModalBottomSheet<bool>(
    context: context,
    builder: (sheetContext) => StatefulBuilder(
      builder: (sheetContext, setSheetState) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text("시/분 선택", style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<int>(
                      initialValue: hour,
                      items: List.generate(
                        24,
                        (i) => DropdownMenuItem(value: i, child: Text("${i.toString().padLeft(2, '0')}시")),
                      ),
                      onChanged: (v) => setSheetState(() => hour = v ?? hour),
                      decoration: const InputDecoration(labelText: "시"),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: DropdownButtonFormField<int>(
                      initialValue: minute,
                      items: List.generate(
                        60,
                        (i) => DropdownMenuItem(value: i, child: Text("${i.toString().padLeft(2, '0')}분")),
                      ),
                      onChanged: (v) => setSheetState(() => minute = v ?? minute),
                      decoration: const InputDecoration(labelText: "분"),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(sheetContext).pop(false),
                      child: const Text("취소"),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton(
                      onPressed: () => Navigator.of(sheetContext).pop(true),
                      child: const Text("적용"),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    ),
  );

  if (ok != true) return null;
  return DateTime(d.year, d.month, d.day, hour, minute);
}

List<String> _applyOtherColor(Set<String> selected, String otherInput) {
  final next = selected.where((e) => e != "기타").toList();
  if (selected.contains("기타")) {
    final cleaned = otherInput.trim();
    if (cleaned.isNotEmpty) {
      next.add("기타:$cleaned");
    } else {
      next.add("기타");
    }
  }
  return next;
}

class _LoginGate extends StatefulWidget {
  const _LoginGate();

  @override
  State<_LoginGate> createState() => _LoginGateState();
}

class _LoginGateState extends State<_LoginGate> {
  bool _busy = false;
  bool _signupMode = false;
  late final TextEditingController _emailC;
  late final TextEditingController _passwordC;
  late final TextEditingController _nameC;

  @override
  void initState() {
    super.initState();
    _emailC = TextEditingController();
    _passwordC = TextEditingController();
    _nameC = TextEditingController();
  }

  @override
  void dispose() {
    _emailC.dispose();
    _passwordC.dispose();
    _nameC.dispose();
    super.dispose();
  }

  Future<void> _submitEmailAuth() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final store = context.readStore();
      final email = _emailC.text.trim();
      final password = _passwordC.text;
      String? err;
      if (_signupMode) {
        err = await store.signUpWithEmail(
          email: email,
          password: password,
          displayName: _nameC.text.trim(),
        );
      } else {
        err = await store.signInWithEmail(email: email, password: password);
      }
      if (!mounted) return;
      if (err != null) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _loginWithKakao() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      const kakaoNativeAppKey = String.fromEnvironment("KAKAO_NATIVE_APP_KEY");
      if (kakaoNativeAppKey.isEmpty) {
        throw Exception("KAKAO_NATIVE_APP_KEY가 설정되지 않았습니다.");
      }

      if (await isKakaoTalkInstalled()) {
        await UserApi.instance.loginWithKakaoTalk();
      } else {
        await UserApi.instance.loginWithKakaoAccount();
      }
      final me = await UserApi.instance.me();
      final name = me.kakaoAccount?.profile?.nickname ?? me.kakaoAccount?.email ?? "카카오 사용자";
      if (!mounted) return;
      await context.readStore().signIn("kakao", displayName: name);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("카카오 로그인 실패: $e")));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _loginWithNaver() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final res = await FlutterNaverLogin.logIn();
      if (res.status != NaverLoginStatus.loggedIn) {
        throw Exception("네이버 로그인에 실패했습니다.");
      }
      final account = res.account;
      final name = (account?.nickname ?? "").trim().isNotEmpty
          ? account!.nickname
          : (account?.name ?? "").trim().isNotEmpty
              ? account!.name
              : (account?.email ?? "").trim().isNotEmpty
                  ? account!.email
                  : "네이버 사용자";
      if (!mounted) return;
      await context.readStore().signIn("naver", displayName: name);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("네이버 로그인 실패: $e")));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 20),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const _CreateHeaderCard(
                icon: Icons.lock_outline,
                title: "로그인 필요",
                desc: "내 활동 기능은 로그인 후 사용할 수 있습니다.",
              ),
              const SizedBox(height: 12),
              _FormSection(
                title: "계정 인증",
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SegmentedButton<bool>(
                      showSelectedIcon: false,
                      segments: const [
                        ButtonSegment(value: false, label: Text("로그인")),
                        ButtonSegment(value: true, label: Text("회원가입")),
                      ],
                      selected: {_signupMode},
                      onSelectionChanged: (s) => setState(() => _signupMode = s.first),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _emailC,
                      keyboardType: TextInputType.emailAddress,
                      decoration: const InputDecoration(labelText: "이메일"),
                    ),
                    const SizedBox(height: 8),
                    if (_signupMode) ...[
                      TextField(
                        controller: _nameC,
                        decoration: const InputDecoration(labelText: "이름(선택)"),
                      ),
                      const SizedBox(height: 8),
                    ],
                    TextField(
                      controller: _passwordC,
                      obscureText: true,
                      decoration: const InputDecoration(labelText: "비밀번호 (6자 이상)"),
                      onSubmitted: (_) => _submitEmailAuth(),
                    ),
                    const SizedBox(height: 10),
                    FilledButton.icon(
                      onPressed: _busy ? null : _submitEmailAuth,
                      icon: const Icon(Icons.mail_outline),
                      label: Text(_busy ? "처리 중..." : (_signupMode ? "이메일 회원가입" : "이메일 로그인")),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              _FormSection(
                title: "소셜 로그인",
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    FilledButton.icon(
                      style: FilledButton.styleFrom(backgroundColor: const Color(0xFFFEE500), foregroundColor: Colors.black),
                      onPressed: _busy ? null : _loginWithKakao,
                      icon: const Icon(Icons.chat_bubble_outline),
                      label: Text(_busy ? "처리 중..." : "카카오톡 로그인"),
                    ),
                    const SizedBox(height: 10),
                    FilledButton.icon(
                      style: FilledButton.styleFrom(backgroundColor: const Color(0xFF03C75A), foregroundColor: Colors.white),
                      onPressed: _busy ? null : _loginWithNaver,
                      icon: const Icon(Icons.account_circle_outlined),
                      label: const Text("네이버 로그인"),
                    ),
                    if (kIsWeb ||
                        defaultTargetPlatform == TargetPlatform.windows ||
                        defaultTargetPlatform == TargetPlatform.linux) ...[
                      const SizedBox(height: 10),
                      Text(
                        "소셜 로그인 SDK는 Android/iOS 환경에서 동작합니다.",
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Theme.of(context).colorScheme.onSurfaceVariant,
                            ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// --------------------------------------------
/// Utils
/// --------------------------------------------
LatLng? _extractCoordinatesFromArea(String text) {
  final m = RegExp(r"\((-?\d+(?:\.\d+)?),\s*(-?\d+(?:\.\d+)?)\)").firstMatch(text);
  if (m == null) return null;
  final lat = double.tryParse(m.group(1) ?? "");
  final lng = double.tryParse(m.group(2) ?? "");
  if (lat == null || lng == null) return null;
  return LatLng(lat, lng);
}

double _estimateDistanceKm({LatLng? point, String? areaText}) {
  final target = point ?? _extractCoordinatesFromArea(areaText ?? "");
  if (target == null) return 3.0;
  const center = LatLng(37.4979, 127.0276);
  final meters = Geolocator.distanceBetween(
    center.latitude,
    center.longitude,
    target.latitude,
    target.longitude,
  );
  if (meters.isNaN || meters.isInfinite) return 3.0;
  return (meters / 1000).clamp(0.1, 30.0).toDouble();
}

String _fmt(DateTime dt) {
  String two(int n) => n.toString().padLeft(2, '0');
  return "${dt.year}-${two(dt.month)}-${two(dt.day)} ${two(dt.hour)}:${two(dt.minute)}";
}

String _pendingTypeLabel(String type) {
  switch (type) {
    case "create_post":
      return "게시글 등록";
    case "create_tip":
      return "제보 등록";
    case "resolve_post":
      return "해결 처리";
    case "update_post":
      return "게시글 수정";
    default:
      return "기타";
  }
}

String _pendingTargetLabel(Map<String, dynamic> payload) {
  final postId = (payload["postId"] ?? payload["localPostId"] ?? "").toString();
  if (postId.isNotEmpty) return "post: $postId";
  final tipId = (payload["localTipId"] ?? "").toString();
  if (tipId.isNotEmpty) return "tip: $tipId";
  return "-";
}

int countActiveReadyPendingOps(List<Map<String, dynamic>> ops, DateTime now) {
  return ops.where((op) {
    if (op["suspended"] == true) return false;
    final nextRetryAt = DateTime.tryParse((op["nextRetryAt"] ?? "").toString());
    if (nextRetryAt == null) return true;
    return !nextRetryAt.isAfter(now);
  }).length;
}

int countActiveAllPendingOps(List<Map<String, dynamic>> ops) {
  return ops.where((op) => op["suspended"] != true).length;
}

Set<String> sanitizeSelectedPendingIds(Set<String> selectedIds, Set<String> existingIds) {
  return selectedIds.where((id) => existingIds.contains(id)).toSet();
}

int countSelectedInFilteredPendingIds(Set<String> selectedIds, List<String> filteredIds) {
  return filteredIds.where((id) => selectedIds.contains(id)).length;
}

Set<String> selectedIdsRemainingInQueue(Set<String> selectedIds, List<Map<String, dynamic>> queueOps) {
  final queueIds = queueOps.map((op) => (op["id"] ?? "").toString()).where((id) => id.isNotEmpty).toSet();
  return sanitizeSelectedPendingIds(selectedIds, queueIds);
}

String buildSelectedSyncSummaryText({
  required int requestedSelectedCount,
  required PendingSyncResult result,
  required int selectedRemaining,
  required int totalRemaining,
}) {
  return "선택 $requestedSelectedCount건 재시도: ${result.summaryText} · 선택잔여 $selectedRemaining건 · 전체잔여 $totalRemaining건";
}

Future<int?> _pickForceRetryMode(
  BuildContext context, {
  required int readyCount,
  required int forceCount,
}) async {
  return showModalBottomSheet<int>(
    context: context,
    builder: (ctx) {
      return SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.playlist_add_check_circle_outlined),
              title: const Text("활성 항목만"),
              subtitle: Text("현재 재시도 가능한 항목만 실행 ($readyCount건)"),
              onTap: () => Navigator.of(ctx).pop(0),
            ),
            ListTile(
              leading: const Icon(Icons.flash_on),
              title: const Text("전체(중단 제외)"),
              subtitle: Text("백오프 대기 항목도 강제 재시도 ($forceCount건)"),
              onTap: () => Navigator.of(ctx).pop(1),
            ),
          ],
        ),
      );
    },
  );
}

List<Map<String, dynamic>> filterAndSortPendingOpsForView(
  List<Map<String, dynamic>> ops, {
  required int statusFilter, // 0=all,1=active,2=suspended
  required String typeFilter, // all|create_post|update_post|resolve_post|create_tip
  required int sortMode, // 0=nextRetryAt asc, 1=createdAt desc
}) {
  final filtered = ops.where((op) {
    final suspended = op["suspended"] == true;
    if (statusFilter == 1 && suspended) return false;
    if (statusFilter == 2 && !suspended) return false;
    if (typeFilter != "all" && (op["type"] ?? "").toString() != typeFilter) return false;
    return true;
  }).toList(growable: true);

  filtered.sort((a, b) {
    if (sortMode == 1) {
      final ta = DateTime.tryParse((a["createdAt"] ?? "").toString()) ?? DateTime.fromMillisecondsSinceEpoch(0);
      final tb = DateTime.tryParse((b["createdAt"] ?? "").toString()) ?? DateTime.fromMillisecondsSinceEpoch(0);
      return tb.compareTo(ta);
    }
    final ra = DateTime.tryParse((a["nextRetryAt"] ?? "").toString()) ?? DateTime.fromMillisecondsSinceEpoch(0);
    final rb = DateTime.tryParse((b["nextRetryAt"] ?? "").toString()) ?? DateTime.fromMillisecondsSinceEpoch(0);
    return ra.compareTo(rb);
  });
  return filtered;
}

String _prettyPayloadJson(Map<String, dynamic> payload) {
  try {
    return const JsonEncoder.withIndent("  ").convert(payload);
  } catch (_) {
    return jsonEncode(payload);
  }
}

Future<void> _showPendingOpsSheet(BuildContext context, AppStore store) async {
  final messenger = ScaffoldMessenger.of(context);
  var filter = store.pendingUiFilter;
  var sortMode = store.pendingUiSort;
  var typeFilter = store.pendingUiType;
  var busy = false;
  var selecting = false;
  final selectedIds = <String>{};

  await showModalBottomSheet<void>(
    context: context,
    builder: (ctx) {
      return StatefulBuilder(
        builder: (context, setLocalState) {
          final ops = store.pendingOpsSnapshot;
          final suspendedCount = store.suspendedPendingOpsCount;
          if (ops.isEmpty) {
            return const SafeArea(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Text("대기 중인 동기화 작업이 없어요."),
              ),
            );
          }

          final filteredOps = filterAndSortPendingOpsForView(
            ops,
            statusFilter: filter,
            typeFilter: typeFilter,
            sortMode: sortMode,
          );
          final allOpIds = ops.map((e) => (e["id"] ?? "").toString()).where((e) => e.isNotEmpty).toSet();
          final sanitizedSelectedIds = sanitizeSelectedPendingIds(selectedIds, allOpIds);
          if (sanitizedSelectedIds.length != selectedIds.length) {
            selectedIds
              ..clear()
              ..addAll(sanitizedSelectedIds);
          }
          final filteredIds = filteredOps.map((e) => (e["id"] ?? "").toString()).where((e) => e.isNotEmpty).toList();
          final selectedInFilteredCount = countSelectedInFilteredPendingIds(selectedIds, filteredIds);
          final filteredSuspendedIds = filteredOps
              .where((e) => e["suspended"] == true)
              .map((e) => (e["id"] ?? "").toString())
              .where((e) => e.isNotEmpty)
              .toList();
          final selectedOps = ops
              .where((e) => selectedIds.contains((e["id"] ?? "").toString()))
              .toList(growable: false);
          final selectedSuspendedIds = selectedOps
              .where((e) => e["suspended"] == true)
              .map((e) => (e["id"] ?? "").toString())
              .where((e) => e.isNotEmpty)
              .toList(growable: false);
          final now = DateTime.now();
          final readyCount = countActiveReadyPendingOps(ops, now);
          final forceCount = countActiveAllPendingOps(ops);
          final selectedReadyCount = countActiveReadyPendingOps(selectedOps, now);
          final selectedForceCount = countActiveAllPendingOps(selectedOps);

          return SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text("대기 작업 ${ops.length}건", style: const TextStyle(fontWeight: FontWeight.w700)),
                      const SizedBox(height: 6),
                      PendingSheetActionBar(
                        busy: busy,
                        suspendedCount: suspendedCount,
                        onRetry: () async {
                          setLocalState(() => busy = true);
                          final result = await store.syncPendingOps();
                          if (!ctx.mounted) return;
                          setLocalState(() => busy = false);
                          messenger.showSnackBar(
                            SnackBar(content: Text(result.summaryWithRemaining(store.pendingOpsCount))),
                          );
                        },
                        onForceRetry: () async {
                          final mode = await _pickForceRetryMode(
                            context,
                            readyCount: readyCount,
                            forceCount: forceCount,
                          );
                          if (mode == null) return;
                          setLocalState(() => busy = true);
                          final result = mode == 0
                              ? await store.syncPendingOps()
                              : await store.syncPendingOps(ignoreBackoff: true);
                          if (!ctx.mounted) return;
                          setLocalState(() => busy = false);
                          messenger.showSnackBar(
                            SnackBar(content: Text(result.summaryWithRemaining(store.pendingOpsCount))),
                          );
                        },
                        onClear: () async {
                          setLocalState(() => busy = true);
                          await store.clearPendingOps();
                          if (!ctx.mounted) return;
                          setLocalState(() => busy = false);
                          messenger.showSnackBar(const SnackBar(content: Text("대기열을 비웠어요")));
                          Navigator.of(ctx).pop();
                        },
                        onClearSuspended: () async {
                          setLocalState(() => busy = true);
                          await store.clearSuspendedPendingOps();
                          if (!ctx.mounted) return;
                          setLocalState(() => busy = false);
                          messenger.showSnackBar(const SnackBar(content: Text("중단된 작업을 정리했어요")));
                        },
                      ),
                      if (busy) const LinearProgressIndicator(),
                    ],
                  ),
                ),
                if (filteredIds.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
                    child: Row(
                      children: [
                        TextButton.icon(
                          onPressed: busy
                              ? null
                              : () {
                                  setLocalState(() {
                                    selecting = !selecting;
                                    if (!selecting) selectedIds.clear();
                                  });
                                },
                          icon: Icon(selecting ? Icons.check_box : Icons.checklist_rtl),
                          label: Text(selecting ? "선택 종료" : "선택 모드"),
                        ),
                        if (selecting) ...[
                          const SizedBox(width: 8),
                          TextButton(
                            onPressed: busy
                                ? null
                                : () {
                                    setLocalState(() {
                                      if (selectedInFilteredCount == filteredIds.length) {
                                        selectedIds.removeAll(filteredIds);
                                      } else {
                                        selectedIds.addAll(filteredIds);
                                      }
                                    });
                                  },
                            child: Text(
                              selectedInFilteredCount == filteredIds.length ? "현재필터 선택해제" : "현재필터 전체선택",
                            ),
                          ),
                          const SizedBox(width: 4),
                          TextButton(
                            onPressed: busy
                                ? null
                                : () {
                                    setLocalState(() {
                                      if (selectedIds.length == allOpIds.length) {
                                        selectedIds.clear();
                                      } else {
                                        selectedIds
                                          ..clear()
                                          ..addAll(allOpIds);
                                      }
                                    });
                                  },
                            child: Text(
                              selectedIds.length == allOpIds.length ? "전체 선택해제" : "전체 선택",
                            ),
                          ),
                          const Spacer(),
                          Text(
                            "${selectedIds.length}건 선택 (현재필터 $selectedInFilteredCount/${filteredIds.length})",
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ],
                    ),
                  ),
                if (selecting && selectedIds.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
                    child: PendingSelectionActionBar(
                      busy: busy,
                      hasSuspendedSelected: selectedSuspendedIds.isNotEmpty,
                      onRetrySelected: () async {
                        final requestedSelectedCount = selectedIds.length;
                        final mode = await _pickForceRetryMode(
                          context,
                          readyCount: selectedReadyCount,
                          forceCount: selectedForceCount,
                        );
                        if (mode == null) return;
                        setLocalState(() => busy = true);
                        final result = mode == 0
                            ? await store.syncPendingOpsByIds(selectedIds)
                            : await store.syncPendingOpsByIds(selectedIds, ignoreBackoff: true);
                        if (!ctx.mounted) return;
                        setLocalState(() {
                          busy = false;
                          final remained = selectedIdsRemainingInQueue(selectedIds, store.pendingOpsSnapshot);
                          selectedIds
                            ..clear()
                            ..addAll(remained);
                        });
                        final selectedRemaining = selectedIds.length;
                        messenger.showSnackBar(
                          SnackBar(
                            content: Text(
                              buildSelectedSyncSummaryText(
                                requestedSelectedCount: requestedSelectedCount,
                                result: result,
                                selectedRemaining: selectedRemaining,
                                totalRemaining: store.pendingOpsCount,
                              ),
                            ),
                          ),
                        );
                      },
                      onReactivateSelected: () async {
                        setLocalState(() => busy = true);
                        await store.reactivatePendingOpsByIds(selectedSuspendedIds);
                        if (!ctx.mounted) return;
                        setLocalState(() => busy = false);
                        messenger.showSnackBar(
                          SnackBar(content: Text("선택 중단 ${selectedSuspendedIds.length}건 재활성화")),
                        );
                      },
                      onDeleteSelected: () async {
                        final count = selectedIds.length;
                        setLocalState(() => busy = true);
                        await store.removePendingOpsByIds(selectedIds);
                        if (!ctx.mounted) return;
                        setLocalState(() {
                          busy = false;
                          selectedIds.clear();
                        });
                        messenger.showSnackBar(
                          SnackBar(content: Text("선택한 $count건을 삭제했어요")),
                        );
                      },
                    ),
                  ),
                if (filteredIds.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
                    child: Row(
                      children: [
                        TextButton.icon(
                          onPressed: busy
                              ? null
                              : () async {
                                  setLocalState(() => busy = true);
                                  await store.removePendingOpsByIds(filteredIds);
                                  if (!ctx.mounted) return;
                                  setLocalState(() => busy = false);
                                  messenger.showSnackBar(
                                    SnackBar(content: Text("현재 필터 결과 ${filteredIds.length}건을 삭제했어요")),
                                  );
                                },
                          icon: const Icon(Icons.delete_sweep_outlined, size: 18),
                          label: const Text("현재필터 비우기"),
                        ),
                        const SizedBox(width: 8),
                        TextButton.icon(
                          onPressed: busy || filteredSuspendedIds.isEmpty
                              ? null
                              : () async {
                                  setLocalState(() => busy = true);
                                  await store.reactivatePendingOpsByIds(filteredSuspendedIds);
                                  if (!ctx.mounted) return;
                                  setLocalState(() => busy = false);
                                  messenger.showSnackBar(
                                    SnackBar(content: Text("현재 필터 중단 ${filteredSuspendedIds.length}건 재활성화")),
                                  );
                                },
                          icon: const Icon(Icons.restart_alt, size: 18),
                          label: const Text("현재필터 재활성화"),
                        ),
                      ],
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        ChoiceChip(
                          label: const Text("전체"),
                          selected: filter == 0,
                          onSelected: (_) {
                            setLocalState(() => filter = 0);
                            store.setPendingUiState(filter: 0);
                          },
                        ),
                        ChoiceChip(
                          label: const Text("활성"),
                          selected: filter == 1,
                          onSelected: (_) {
                            setLocalState(() => filter = 1);
                            store.setPendingUiState(filter: 1);
                          },
                        ),
                        ChoiceChip(
                          label: const Text("중단"),
                          selected: filter == 2,
                          onSelected: (_) {
                            setLocalState(() => filter = 2);
                            store.setPendingUiState(filter: 2);
                          },
                        ),
                        ChoiceChip(
                          label: const Text("유형:전체"),
                          selected: typeFilter == "all",
                          onSelected: (_) {
                            setLocalState(() => typeFilter = "all");
                            store.setPendingUiState(type: "all");
                          },
                        ),
                        ChoiceChip(
                          label: const Text("등록"),
                          selected: typeFilter == "create_post",
                          onSelected: (_) {
                            setLocalState(() => typeFilter = "create_post");
                            store.setPendingUiState(type: "create_post");
                          },
                        ),
                        ChoiceChip(
                          label: const Text("수정"),
                          selected: typeFilter == "update_post",
                          onSelected: (_) {
                            setLocalState(() => typeFilter = "update_post");
                            store.setPendingUiState(type: "update_post");
                          },
                        ),
                        ChoiceChip(
                          label: const Text("해결"),
                          selected: typeFilter == "resolve_post",
                          onSelected: (_) {
                            setLocalState(() => typeFilter = "resolve_post");
                            store.setPendingUiState(type: "resolve_post");
                          },
                        ),
                        ChoiceChip(
                          label: const Text("제보"),
                          selected: typeFilter == "create_tip",
                          onSelected: (_) {
                            setLocalState(() => typeFilter = "create_tip");
                            store.setPendingUiState(type: "create_tip");
                          },
                        ),
                      ],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
                  child: Row(
                    children: [
                      const Text("정렬"),
                      const SizedBox(width: 8),
                      ChoiceChip(
                        label: const Text("빠른재시도"),
                        selected: sortMode == 0,
                        onSelected: (_) {
                          setLocalState(() => sortMode = 0);
                          store.setPendingUiState(sort: 0);
                        },
                      ),
                      const SizedBox(width: 8),
                      ChoiceChip(
                        label: const Text("최근순"),
                        selected: sortMode == 1,
                        onSelected: (_) {
                          setLocalState(() => sortMode = 1);
                          store.setPendingUiState(sort: 1);
                        },
                      ),
                    ],
                  ),
                ),
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                    itemBuilder: (_, i) {
                      final op = filteredOps[i];
                      final opId = (op["id"] ?? "").toString();
                      final type = (op["type"] ?? "").toString();
                      final createdAtRaw = (op["createdAt"] ?? "").toString();
                      final createdAt = DateTime.tryParse(createdAtRaw);
                      final retryCount = (op["retryCount"] is num) ? (op["retryCount"] as num).toInt() : 0;
                      final suspended = op["suspended"] == true;
                      final lastError = op["lastError"]?.toString();
                      final hasLastError = lastError != null && lastError.trim().isNotEmpty;
                      final nextRetryAtRaw = op["nextRetryAt"]?.toString() ?? "";
                      final nextRetryAt = DateTime.tryParse(nextRetryAtRaw);
                      final payload = (op["payload"] as Map?)?.cast<String, dynamic>() ?? const <String, dynamic>{};
                      final prettyPayload = _prettyPayloadJson(payload);
                      final isSelected = selectedIds.contains(opId);
                      return ExpansionTile(
                        leading: selecting
                            ? Checkbox(
                                value: isSelected,
                                onChanged: busy || opId.isEmpty
                                    ? null
                                    : (v) {
                                        setLocalState(() {
                                          if (v == true) {
                                            selectedIds.add(opId);
                                          } else {
                                            selectedIds.remove(opId);
                                          }
                                        });
                                      },
                              )
                            : const Icon(Icons.sync_problem_outlined),
                        title: Text(_pendingTypeLabel(type)),
                        subtitle: Text(
                          "${_pendingTargetLabel(payload)} · 재시도 $retryCount회${nextRetryAt != null ? " · 다음시도 ${_fmt(nextRetryAt)}" : ""}${suspended ? " · 자동재시도중단" : ""}${hasLastError ? "\n최근 오류: ${lastError.split('\n').first}" : ""}",
                        ),
                        trailing: Wrap(
                          spacing: 4,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Text(
                              createdAt == null ? "-" : _fmt(createdAt),
                              style: const TextStyle(fontSize: 12),
                            ),
                            if (!selecting && suspended)
                              IconButton(
                                icon: const Icon(Icons.restart_alt, size: 18),
                                tooltip: "재활성화",
                                onPressed: () async {
                                  Navigator.of(ctx).pop();
                                  await store.reactivatePendingOpById(opId);
                                  messenger.showSnackBar(const SnackBar(content: Text("작업을 재활성화했어요")));
                                },
                              ),
                            if (!selecting)
                              IconButton(
                                icon: const Icon(Icons.close, size: 18),
                                tooltip: "삭제",
                                onPressed: () async {
                                  Navigator.of(ctx).pop();
                                  await store.removePendingOpById(opId);
                                  messenger.showSnackBar(const SnackBar(content: Text("대기 작업 1건을 삭제했어요")));
                                },
                              ),
                          ],
                        ),
                        children: [
                          if (hasLastError)
                            Padding(
                              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                              child: Align(
                                alignment: Alignment.centerLeft,
                                child: Text(
                                  "마지막 오류: $lastError",
                                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                        color: Theme.of(context).colorScheme.error,
                                      ),
                                ),
                              ),
                            ),
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                            child: PendingPayloadPanel(
                              prettyPayload: prettyPayload,
                              onCopy: () async {
                                await Clipboard.setData(ClipboardData(text: prettyPayload));
                                if (!ctx.mounted) return;
                                messenger.showSnackBar(const SnackBar(content: Text("payload를 복사했어요")));
                              },
                            ),
                          ),
                        ],
                      );
                    },
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemCount: filteredOps.length,
                  ),
                ),
              ],
            ),
          );
        },
      );
    },
  );
}

Future<void> _showLiveNotificationsSheet(BuildContext context, AppStore store) async {
  store.markAllLiveNotificationsRead();
  final items = store.liveNotificationsSnapshot;
  final messenger = ScaffoldMessenger.of(context);

  await showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (ctx) {
      if (items.isEmpty) {
        return const SafeArea(
          child: SizedBox(
            height: 220,
            child: Center(child: Text("새 실시간 알림이 없어요")),
          ),
        );
      }
      return SafeArea(
        child: ListView.separated(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          itemBuilder: (_, i) {
            final item = items[i];
            final title = (item["title"] ?? "").toString();
            final message = (item["message"] ?? "").toString();
            final createdAt = DateTime.tryParse((item["createdAt"] ?? "").toString());
            final postId = (item["postId"] ?? "").toString();
            return ListTile(
              leading: const Icon(Icons.notifications_active_outlined),
              title: Text(title),
              subtitle: Text("$message\n${createdAt == null ? "-" : _fmt(createdAt)}"),
              isThreeLine: true,
              onTap: () {
                Navigator.of(ctx).pop();
                if (postId.isEmpty) return;
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => PostDetailPage(postId: postId)),
                );
              },
            );
          },
          separatorBuilder: (_, __) => const Divider(height: 1),
          itemCount: items.length,
        ),
      );
    },
  );

  if (!context.mounted) return;
  if (items.isNotEmpty) {
    messenger.showSnackBar(const SnackBar(content: Text("실시간 알림을 확인했어요")));
  }
}

String _postTypeLabel(PostType type) {
  switch (type) {
    case PostType.lost:
      return "실종";
    case PostType.sighting:
      return "목격";
    case PostType.shelter:
      return "보호";
  }
}

IconData _postTypeIcon(PostType type) {
  switch (type) {
    case PostType.lost:
      return Icons.report;
    case PostType.sighting:
      return Icons.visibility;
    case PostType.shelter:
      return Icons.shield_outlined;
  }
}

String _timeAgo(DateTime dt) {
  final d = DateTime.now().difference(dt);
  if (d.inMinutes < 1) return "방금 전";
  if (d.inMinutes < 60) return "${d.inMinutes}분 전";
  if (d.inHours < 24) return "${d.inHours}시간 전";
  return "${d.inDays}일 전";
}

String _sizeLabel(DogSize s) {
  switch (s) {
    case DogSize.small:
      return "소형";
    case DogSize.medium:
      return "중형";
    case DogSize.large:
      return "대형";
  }
}

String _collarLabel(CollarState s) {
  switch (s) {
    case CollarState.has:
      return "있음";
    case CollarState.none:
      return "없음";
    case CollarState.unknown:
      return "모름";
  }
}




