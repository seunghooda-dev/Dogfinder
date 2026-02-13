import "dart:convert";

import "package:http/http.dart" as http;

import "api_contract.dart";
import "backend_config.dart";

class RestBackendApi implements BackendApi {
  final BackendConfig config;
  final http.Client _client;
  static const Duration _requestTimeout = Duration(seconds: 15);

  String? _accessToken;

  RestBackendApi({
    required this.config,
    http.Client? client,
  }) : _client = client ?? http.Client();

  void clearSession() {
    _accessToken = null;
  }

  @override
  Future<AuthSession> signUpWithEmail({
    required String email,
    required String password,
    String? displayName,
  }) async {
    final body = <String, dynamic>{
      "email": email,
      "password": password,
      "displayName": displayName,
    };
    final json = await _send(
      "POST",
      "/v1/auth/email/signup",
      body: body,
    );
    final session = AuthSession.fromJson(json);
    _accessToken = session.accessToken;
    return session;
  }

  @override
  Future<AuthSession> signInWithEmail({
    required String email,
    required String password,
  }) async {
    final json = await _send(
      "POST",
      "/v1/auth/email/login",
      body: {
        "email": email,
        "password": password,
      },
    );
    final session = AuthSession.fromJson(json);
    _accessToken = session.accessToken;
    return session;
  }

  @override
  Future<AuthSession> signInWithSocial({
    required String provider,
    required String displayName,
    String? providerUserId,
    String? email,
    String? accessToken,
  }) async {
    final body = <String, dynamic>{
      "displayName": displayName,
      "provider": provider.trim().toLowerCase(),
      if (providerUserId != null && providerUserId.trim().isNotEmpty) "providerUserId": providerUserId.trim(),
      if (email != null && email.trim().isNotEmpty) "email": email.trim(),
      if (accessToken != null && accessToken.trim().isNotEmpty) "accessToken": accessToken.trim(),
    };

    final normalizedProvider = provider.trim().toLowerCase();
    final json = await _send(
      "POST",
      "/v1/auth/social/$normalizedProvider",
      body: body,
    );
    final session = AuthSession.fromJson(json);
    _accessToken = session.accessToken;
    return session;
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
    final query = <String, String>{};
    if (type != null && type.isNotEmpty) query["type"] = type;
    if (status != null && status.isNotEmpty) query["status"] = status;
    if (latitude != null) query["lat"] = latitude.toString();
    if (longitude != null) query["lng"] = longitude.toString();
    if (radiusKm != null) query["radiusKm"] = radiusKm.toString();
    if (cursor != null && cursor.isNotEmpty) query["cursor"] = cursor;

    final json = await _send(
      "GET",
      "/v1/posts",
      query: query,
    );
    final items = _extractItems(json);
    return items.map(ApiPost.fromJson).toList();
  }

  @override
  Future<ApiPost> createPost(ApiPostCreateInput input) async {
    final json = await _send(
      "POST",
      "/v1/posts",
      body: input.toJson(),
      requiresAuth: true,
    );
    return ApiPost.fromJson(json);
  }

  @override
  Future<ApiPost> updatePost(String postId, Map<String, dynamic> patch) async {
    final json = await _send(
      "PATCH",
      "/v1/posts/$postId",
      body: patch,
      requiresAuth: true,
    );
    return ApiPost.fromJson(json);
  }

  @override
  Future<List<ApiTip>> listTips(String postId) async {
    final json = await _send("GET", "/v1/posts/$postId/tips");
    final items = _extractItems(json);
    return items.map(ApiTip.fromJson).toList();
  }

  @override
  Future<ApiTip> createTip(String postId, ApiTipCreateInput input) async {
    final json = await _send(
      "POST",
      "/v1/posts/$postId/tips",
      body: input.toJson(),
      requiresAuth: true,
    );
    return ApiTip.fromJson(json);
  }

  @override
  Future<void> registerPushToken(String token, {required String platform}) async {
    await _send(
      "POST",
      "/v1/push/tokens",
      body: {
        "token": token,
        "platform": platform,
      },
      requiresAuth: true,
    );
  }

  Future<Map<String, dynamic>> _send(
    String method,
    String path, {
    Map<String, String>? query,
    Map<String, dynamic>? body,
    bool requiresAuth = false,
  }) async {
    final uri = config.baseUri.resolve(path).replace(queryParameters: query);
    final headers = <String, String>{
      "Accept": "application/json",
      "Content-Type": "application/json",
    };
    if (_accessToken != null && _accessToken!.isNotEmpty) {
      headers["Authorization"] = "Bearer $_accessToken";
    } else if (requiresAuth) {
      throw BackendException(401, "Authentication is required.");
    }

    late final http.Response response;
    switch (method) {
      case "GET":
        response = await _client.get(uri, headers: headers).timeout(_requestTimeout);
        break;
      case "POST":
        response = await _client
            .post(
          uri,
          headers: headers,
          body: jsonEncode(body ?? const {}),
        )
            .timeout(_requestTimeout);
        break;
      case "PATCH":
        response = await _client
            .patch(
          uri,
          headers: headers,
          body: jsonEncode(body ?? const {}),
        )
            .timeout(_requestTimeout);
        break;
      default:
        throw StateError("Unsupported method: $method");
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw BackendException(response.statusCode, _extractErrorMessage(response.body));
    }

    if (response.body.trim().isEmpty) {
      return const <String, dynamic>{};
    }
    final decoded = jsonDecode(response.body);
    if (decoded is Map<String, dynamic>) return decoded;
    if (decoded is Map) return decoded.cast<String, dynamic>();
    if (decoded is List) {
      return {
        "items": decoded.whereType<Map>().map((e) => e.cast<String, dynamic>()).toList(),
      };
    }
    return const <String, dynamic>{};
  }

  static List<Map<String, dynamic>> _extractItems(dynamic body) {
    if (body is List) {
      return body
          .whereType<Map>()
          .map((e) => e.cast<String, dynamic>())
          .toList();
    }
    if (body is! Map<String, dynamic>) return const [];
    final raw = body["items"] ?? body["data"];
    if (raw is! List) return const [];
    return raw.whereType<Map>().map((e) => e.cast<String, dynamic>()).toList();
  }

  static String _extractErrorMessage(String body) {
    if (body.trim().isEmpty) return "Request failed.";
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map) {
        final message = decoded["message"] ?? decoded["error"] ?? decoded["detail"];
        if (message != null) return message.toString();
      }
    } catch (_) {}
    return body;
  }
}

class BackendException implements Exception {
  final int statusCode;
  final String message;

  const BackendException(this.statusCode, this.message);

  @override
  String toString() => "BackendException($statusCode): $message";
}
