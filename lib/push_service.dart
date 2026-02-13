import "package:firebase_core/firebase_core.dart";
import "package:firebase_messaging/firebase_messaging.dart";
import "package:flutter/foundation.dart";
import "package:flutter_local_notifications/flutter_local_notifications.dart";

import "backend/api_contract.dart";

Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {}

class PushService {
  PushService._();

  static final PushService instance = PushService._();

  final FlutterLocalNotificationsPlugin _localNotifications = FlutterLocalNotificationsPlugin();

  bool _initialized = false;
  String? _lastToken;

  bool get isInitialized => _initialized;
  String? get lastToken => _lastToken;

  Future<void> initialize({
    required Future<void> Function(String token) onToken,
    required void Function({
      required String title,
      required String body,
      required Map<String, dynamic> data,
    }) onForegroundMessage,
  }) async {
    if (_initialized) return;
    if (kIsWeb) return;

    final options = _firebaseOptionsForCurrentPlatform();
    if (options == null) return;

    try {
      await Firebase.initializeApp(options: options);
    } catch (_) {
      return;
    }

    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

    final messaging = FirebaseMessaging.instance;
    try {
      await messaging.requestPermission(
        alert: true,
        announcement: false,
        badge: true,
        carPlay: false,
        criticalAlert: false,
        provisional: false,
        sound: true,
      );
    } catch (_) {}

    await _initLocalNotifications();

    final token = await _safeGetToken(messaging);
    if (token != null && token.isNotEmpty) {
      _lastToken = token;
      await onToken(token);
    }

    messaging.onTokenRefresh.listen((token) async {
      if (token.trim().isEmpty) return;
      _lastToken = token;
      await onToken(token);
    });

    FirebaseMessaging.onMessage.listen((message) async {      final title = message.notification?.title ?? message.data["title"]?.toString() ?? "새 알림";
      final body = message.notification?.body ?? message.data["body"]?.toString() ?? "";

      await _showLocalNotification(title: title, body: body);
      onForegroundMessage(
        title: title,
        body: body,
        data: Map<String, dynamic>.from(message.data),
      );
    });

    _initialized = true;
  }

  Future<void> registerTokenWithBackend(BackendApi? backendApi) async {
    final token = _lastToken;
    if (backendApi == null || token == null || token.trim().isEmpty) return;
    try {
      await backendApi.registerPushToken(
        token,
        platform: defaultTargetPlatform == TargetPlatform.iOS ? "ios" : "android",
      );
    } catch (_) {}
  }

  static Future<String?> _safeGetToken(FirebaseMessaging messaging) async {
    try {
      return await messaging.getToken();
    } catch (_) {
      return null;
    }
  }

  Future<void> _initLocalNotifications() async {
    const androidSettings = AndroidInitializationSettings("@mipmap/ic_launcher");
    const iosSettings = DarwinInitializationSettings();
    const settings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );
    await _localNotifications.initialize(settings);
  }

  Future<void> _showLocalNotification({
    required String title,
    required String body,
  }) async {
    const android = AndroidNotificationDetails(
      "dogfinder_push_channel",
      "DogFinder Push",
      channelDescription: "DogFinder realtime alerts",
      importance: Importance.high,
      priority: Priority.high,
    );
    const ios = DarwinNotificationDetails();
    const details = NotificationDetails(android: android, iOS: ios);
    await _localNotifications.show(
      DateTime.now().millisecondsSinceEpoch.remainder(100000),
      title,
      body,
      details,
    );
  }

  static FirebaseOptions? _firebaseOptionsForCurrentPlatform() {
    const apiKey = String.fromEnvironment("FIREBASE_API_KEY");
    const projectId = String.fromEnvironment("FIREBASE_PROJECT_ID");
    const messagingSenderId = String.fromEnvironment("FIREBASE_MESSAGING_SENDER_ID");
    const androidAppId = String.fromEnvironment("FIREBASE_ANDROID_APP_ID");
    const iosAppId = String.fromEnvironment("FIREBASE_IOS_APP_ID");
    const iosBundleId = String.fromEnvironment("FIREBASE_IOS_BUNDLE_ID");
    const storageBucket = String.fromEnvironment("FIREBASE_STORAGE_BUCKET");

    if (apiKey.isEmpty || projectId.isEmpty || messagingSenderId.isEmpty) {
      return null;
    }

    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        if (androidAppId.isEmpty) return null;
        return FirebaseOptions(
          apiKey: apiKey,
          appId: androidAppId,
          messagingSenderId: messagingSenderId,
          projectId: projectId,
          storageBucket: storageBucket.isEmpty ? null : storageBucket,
        );
      case TargetPlatform.iOS:
        if (iosAppId.isEmpty || iosBundleId.isEmpty) return null;
        return FirebaseOptions(
          apiKey: apiKey,
          appId: iosAppId,
          messagingSenderId: messagingSenderId,
          projectId: projectId,
          iosBundleId: iosBundleId,
          storageBucket: storageBucket.isEmpty ? null : storageBucket,
        );
      default:
        return null;
    }
  }
}




