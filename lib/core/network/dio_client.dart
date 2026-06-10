import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import '../storage/secure_storage.dart';

class DioClient {
  /// Production host:port, injected at build time:
  ///   flutter build apk --dart-define=API_HOST=34.237.109.152:3000
  /// Empty in dev builds, so the emulator/web defaults below apply.
  static const String _apiHost = String.fromEnvironment('API_HOST', defaultValue: '');

  /// Resolved backend host: production flag if set, else dev defaults.
  /// Android emulator reaches the host machine's localhost via 10.0.2.2.
  static String get _host {
    if (_apiHost.isNotEmpty) return _apiHost;
    return kIsWeb ? 'localhost:3000' : '10.0.2.2:3000';
  }

  static String get baseUrl => 'http://$_host/api/v1';

  /// STOMP-over-WebSocket endpoint, derived from the same host.
  static String get wsUrl => 'ws://$_host/ws/websocket';

  static Dio create() {
    final dio = Dio(BaseOptions(
      baseUrl: DioClient.baseUrl,
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 10),
      headers: {'Content-Type': 'application/json'},
    ));

    dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) async {
        final token = await SecureStorageService.getAccessToken();
        if (token != null && token.isNotEmpty) {
          options.headers['Authorization'] = 'Bearer $token';
        }
        handler.next(options);
      },
      onError: (error, handler) async {
        final status = error.response?.statusCode;
        if (status == 401 || status == 403) {
          await SecureStorageService.clearAll();
        }
        handler.next(error);
      },
    ));

    return dio;
  }
}
