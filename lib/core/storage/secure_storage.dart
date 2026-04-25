import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class SecureStorageService {
  static const _storage = FlutterSecureStorage();
  static const _accessTokenKey = 'accessToken';
  static const _refreshTokenKey = 'refreshToken';
  static const _userIdKey = 'userId';
  static const _usernameKey = 'username';
  static const _roleKey = 'role';

  /// Reads a value safely, returning null on any storage/crypto error
  /// without wiping the stored data (avoids destroying a valid session).
  static Future<String?> _safeRead(String key) async {
    try {
      return await _storage.read(key: key);
    } catch (_) {
      return null;
    }
  }

  static Future<void> saveTokens({
    required String accessToken,
    required String refreshToken,
    required String userId,
    required String username,
    required String role,
  }) async {
    await Future.wait([
      _storage.write(key: _accessTokenKey, value: accessToken),
      _storage.write(key: _refreshTokenKey, value: refreshToken),
      _storage.write(key: _userIdKey, value: userId),
      _storage.write(key: _usernameKey, value: username),
      _storage.write(key: _roleKey, value: role),
    ]);
  }

  static Future<String?> getAccessToken() => _safeRead(_accessTokenKey);

  static Future<String?> getRefreshToken() => _safeRead(_refreshTokenKey);

  static Future<String?> getUserId() => _safeRead(_userIdKey);

  static Future<String?> getUsername() => _safeRead(_usernameKey);

  static Future<String?> getRole() => _safeRead(_roleKey);

  static Future<void> clearAll() => _storage.deleteAll();

  static Future<bool> isLoggedIn() async {
    final token = await getAccessToken();
    return token != null && token.isNotEmpty;
  }
}
