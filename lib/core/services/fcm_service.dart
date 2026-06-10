import 'package:dio/dio.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import '../network/dio_client.dart';
import '../storage/secure_storage.dart';

/// Handles Firebase Cloud Messaging (RF-28/29/30):
/// - Requests notification permission on Android 13+
/// - Registers the FCM token with the backend via PATCH /profile/fcm-token
/// - Re-registers whenever the token refreshes
/// - Shows a local snackbar for foreground messages (background handled by OS)
class FcmService {
  FcmService._();

  static final _messaging = FirebaseMessaging.instance;

  /// Call once after Firebase.initializeApp().
  static Future<void> init() async {
    if (kIsWeb) return;

    // Request permission (required on iOS and Android 13+)
    await _messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    // Foreground messages — log for now; UI layer can listen via onMessage stream
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      debugPrint('[FCM] Foreground message: ${message.notification?.title} — ${message.notification?.body}');
    });

    // Token refresh — re-register with backend
    _messaging.onTokenRefresh.listen((token) async {
      await _sendTokenToBackend(token);
    });
  }

  /// Register (or refresh) the FCM token with the Spring Boot backend.
  /// Must be called after successful login.
  static Future<void> registerToken() async {
    if (kIsWeb) return;
    try {
      final token = await _messaging.getToken();
      if (token != null) {
        await _sendTokenToBackend(token);
      }
    } catch (e) {
      debugPrint('[FCM] Could not register token: $e');
    }
  }

  static Future<void> _sendTokenToBackend(String token) async {
    try {
      final accessToken = await SecureStorageService.getAccessToken();
      if (accessToken == null) return;
      final dio = DioClient.create();
      await dio.patch(
        '/profile/fcm-token',
        data: {'fcmToken': token},
        options: Options(headers: {'Authorization': 'Bearer $accessToken'}),
      );
      debugPrint('[FCM] Token registered with backend.');
    } catch (e) {
      debugPrint('[FCM] Failed to register token: $e');
    }
  }
}
