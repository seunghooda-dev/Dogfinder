abstract class BackendApi {
  Future<AuthSession> signUpWithEmail({
    required String email,
    required String password,
    String? displayName,
  });

  Future<AuthSession> signInWithEmail({
    required String email,
    required String password,
  });

  Future<List<ApiPost>> listPosts({
    String? type,
    String? status,
    double? latitude,
    double? longitude,
    double? radiusKm,
    String? cursor,
  });

  Future<ApiPost> createPost(ApiPostCreateInput input);
  Future<ApiPost> updatePost(String postId, Map<String, dynamic> patch);
  Future<List<ApiTip>> listTips(String postId);
  Future<ApiTip> createTip(String postId, ApiTipCreateInput input);
  Future<void> registerPushToken(String token, {required String platform});
}

class AuthSession {
  final String accessToken;
  final String refreshToken;
  final String userId;
  final String? email;
  final String? displayName;

  const AuthSession({
    required this.accessToken,
    required this.refreshToken,
    required this.userId,
    this.email,
    this.displayName,
  });

  factory AuthSession.fromJson(Map<String, dynamic> json) {
    final user = (json["user"] as Map?)?.cast<String, dynamic>() ?? const <String, dynamic>{};
    return AuthSession(
      accessToken: (json["accessToken"] ?? "").toString(),
      refreshToken: (json["refreshToken"] ?? "").toString(),
      userId: (user["id"] ?? json["userId"] ?? "").toString(),
      email: user["email"]?.toString(),
      displayName: user["displayName"]?.toString(),
    );
  }

  Map<String, dynamic> toJson() => {
        "accessToken": accessToken,
        "refreshToken": refreshToken,
        "user": {
          "id": userId,
          "email": email,
          "displayName": displayName,
        },
      };
}

class ApiPost {
  final String id;
  final String type;
  final String status;
  final DateTime createdAt;
  final DateTime eventTime;
  final String areaText;
  final double? latitude;
  final double? longitude;
  final double distanceKm;
  final String title;
  final String body;
  final String ownerUserId;
  final String? photoUrl;

  const ApiPost({
    required this.id,
    required this.type,
    required this.status,
    required this.createdAt,
    required this.eventTime,
    required this.areaText,
    required this.latitude,
    required this.longitude,
    required this.distanceKm,
    required this.title,
    required this.body,
    required this.ownerUserId,
    this.photoUrl,
  });

  factory ApiPost.fromJson(Map<String, dynamic> json) {
    DateTime parseDateTime(String key) {
      final raw = (json[key] ?? "").toString();
      return DateTime.tryParse(raw) ?? DateTime.now();
    }

    return ApiPost(
      id: (json["id"] ?? "").toString(),
      type: (json["type"] ?? "").toString(),
      status: (json["status"] ?? "").toString(),
      createdAt: parseDateTime("createdAt"),
      eventTime: parseDateTime("eventTime"),
      areaText: (json["areaText"] ?? "").toString(),
      latitude: (json["latitude"] as num?)?.toDouble(),
      longitude: (json["longitude"] as num?)?.toDouble(),
      distanceKm: (json["distanceKm"] as num?)?.toDouble() ?? 0,
      title: (json["title"] ?? "").toString(),
      body: (json["body"] ?? "").toString(),
      ownerUserId: (json["ownerUserId"] ?? "").toString(),
      photoUrl: json["photoUrl"]?.toString(),
    );
  }

  Map<String, dynamic> toJson() => {
        "id": id,
        "type": type,
        "status": status,
        "createdAt": createdAt.toIso8601String(),
        "eventTime": eventTime.toIso8601String(),
        "areaText": areaText,
        "latitude": latitude,
        "longitude": longitude,
        "distanceKm": distanceKm,
        "title": title,
        "body": body,
        "ownerUserId": ownerUserId,
        "photoUrl": photoUrl,
      };
}

class ApiPostCreateInput {
  final String type;
  final DateTime eventTime;
  final String areaText;
  final double? latitude;
  final double? longitude;
  final String title;
  final String body;
  final String? photoUrl;

  const ApiPostCreateInput({
    required this.type,
    required this.eventTime,
    required this.areaText,
    required this.latitude,
    required this.longitude,
    required this.title,
    required this.body,
    this.photoUrl,
  });

  Map<String, dynamic> toJson() => {
        "type": type,
        "eventTime": eventTime.toIso8601String(),
        "areaText": areaText,
        "latitude": latitude,
        "longitude": longitude,
        "title": title,
        "body": body,
        "photoUrl": photoUrl,
      };
}

class ApiTip {
  final String id;
  final String postId;
  final String reporterUserId;
  final DateTime createdAt;
  final DateTime seenTime;
  final String seenAreaText;
  final String situation;
  final String memo;
  final bool canCall;
  final bool canChat;

  const ApiTip({
    required this.id,
    required this.postId,
    required this.reporterUserId,
    required this.createdAt,
    required this.seenTime,
    required this.seenAreaText,
    required this.situation,
    required this.memo,
    required this.canCall,
    required this.canChat,
  });

  factory ApiTip.fromJson(Map<String, dynamic> json) {
    DateTime parseDateTime(String key) {
      final raw = (json[key] ?? "").toString();
      return DateTime.tryParse(raw) ?? DateTime.now();
    }

    return ApiTip(
      id: (json["id"] ?? "").toString(),
      postId: (json["postId"] ?? "").toString(),
      reporterUserId: (json["reporterUserId"] ?? "").toString(),
      createdAt: parseDateTime("createdAt"),
      seenTime: parseDateTime("seenTime"),
      seenAreaText: (json["seenAreaText"] ?? "").toString(),
      situation: (json["situation"] ?? "").toString(),
      memo: (json["memo"] ?? "").toString(),
      canCall: json["canCall"] == true,
      canChat: json["canChat"] == true,
    );
  }

  Map<String, dynamic> toJson() => {
        "id": id,
        "postId": postId,
        "reporterUserId": reporterUserId,
        "createdAt": createdAt.toIso8601String(),
        "seenTime": seenTime.toIso8601String(),
        "seenAreaText": seenAreaText,
        "situation": situation,
        "memo": memo,
        "canCall": canCall,
        "canChat": canChat,
      };
}

class ApiTipCreateInput {
  final DateTime seenTime;
  final String seenAreaText;
  final String situation;
  final String memo;
  final bool canCall;
  final bool canChat;

  const ApiTipCreateInput({
    required this.seenTime,
    required this.seenAreaText,
    required this.situation,
    required this.memo,
    required this.canCall,
    required this.canChat,
  });

  Map<String, dynamic> toJson() => {
        "seenTime": seenTime.toIso8601String(),
        "seenAreaText": seenAreaText,
        "situation": situation,
        "memo": memo,
        "canCall": canCall,
        "canChat": canChat,
      };
}
