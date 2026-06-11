import 'package:dio/dio.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import '../network/dio_client.dart';
import '../storage/secure_storage.dart';

/// Background/terminated message handler (RF-29/30). FCM requires this to be a
/// top-level or static function annotated with @pragma('vm:entry-point').
/// Notification-payload messages are rendered by the Android system tray on their
/// own when the app is backgrounded, so this only needs to exist (no work) to keep
/// the messaging isolate alive for data-only payloads.
@pragma('vm:entry-point')
Future<void> firebaseBackgroundHandler(RemoteMessage message) async {}

/// Handles Firebase Cloud Messaging (RF-28/29/30):
/// - Requests notification permission on Android 13+ / iOS
/// - Registers the FCM token with the backend via PATCH /profile/fcm-token
/// - Re-registers whenever the token refreshes
/// - Renders a heads-up notification for FOREGROUND messages (Android does not
///   auto-display notification-payload messages while the app is open)
class FcmService {
  FcmService._();

  static final _messaging = FirebaseMessaging.instance;
  static final _localNotifications = FlutterLocalNotificationsPlugin();

  /// High-importance channel so foreground updates appear as a heads-up banner.
  static const AndroidNotificationChannel _channel = AndroidNotificationChannel(
    'ibpms_default',
    'Notificaciones iBPMS',
    description: 'Avances de trámites y tareas asignadas',
    importance: Importance.high,
  );

  /// Call once after Firebase.initializeApp().
  static Future<void> init() async {
    if (kIsWeb) return;

    // Request permission (required on iOS and Android 13+)
    await _messaging.requestPermission(alert: true, badge: true, sound: true);

    // Initialize the local-notifications plugin and register the Android channel.
    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const initSettings = InitializationSettings(android: androidInit);
    await _localNotifications.initialize(initSettings);
    await _localNotifications
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(_channel);

    // iOS: also surface a banner while the app is foregrounded.
    await _messaging.setForegroundNotificationPresentationOptions(
      alert: true,
      badge: true,
      sound: true,
    );

    // FOREGROUND messages — render them ourselves so the user always sees the update.
    FirebaseMessaging.onMessage.listen(_showLocalNotification);

    // Token refresh — re-register with backend
    _messaging.onTokenRefresh.listen((token) async {
      await _sendTokenToBackend(token);
    });
  }

  static Future<void> _showLocalNotification(RemoteMessage message) async {
    final notification = message.notification;
    if (notification == null) return;
    await _localNotifications.show(
      notification.hashCode,
      notification.title,
      notification.body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          _channel.id,
          _channel.name,
          channelDescription: _channel.description,
          importance: Importance.high,
          priority: Priority.high,
          icon: '@mipmap/ic_launcher',
        ),
      ),
    );
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
