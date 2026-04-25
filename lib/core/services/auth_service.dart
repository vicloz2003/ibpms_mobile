import 'package:dio/dio.dart';
import '../models/auth_models.dart';
import '../network/dio_client.dart';
import '../storage/secure_storage.dart';

class AuthService {
  final Dio _dio = DioClient.create();

  Future<AuthResponse> login(LoginRequest request) async {
    final response = await _dio.post(
      '/auth/login',
      data: request.toJson(),
    );
    final auth = AuthResponse.fromJson(response.data as Map<String, dynamic>);
    await SecureStorageService.saveTokens(
      accessToken: auth.accessToken,
      refreshToken: auth.refreshToken,
      userId: auth.userId,
      username: auth.username,
      role: auth.role,
    );
    return auth;
  }

  Future<AuthResponse> register(RegisterRequest request) async {
    final response = await _dio.post(
      '/auth/register',
      data: request.toJson(),
    );
    final auth = AuthResponse.fromJson(response.data as Map<String, dynamic>);
    await SecureStorageService.saveTokens(
      accessToken: auth.accessToken,
      refreshToken: auth.refreshToken,
      userId: auth.userId,
      username: auth.username,
      role: auth.role,
    );
    return auth;
  }

  Future<void> logout() async {
    final refreshToken = await SecureStorageService.getRefreshToken();
    if (refreshToken != null) {
      try {
        await _dio.post('/auth/logout', data: {'refreshToken': refreshToken});
      } catch (_) {}
    }
    await SecureStorageService.clearAll();
  }
}
