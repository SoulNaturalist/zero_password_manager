import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AuthTokenStorage {
  AuthTokenStorage._();

  static const _tokenKey = 'token';
  static const FlutterSecureStorage _secureStorage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: false),
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
  );

  static Future<String?> readAccessToken() async {
    final secureToken = await _secureStorage.read(key: _tokenKey);
    if (secureToken != null && secureToken.isNotEmpty) {
      return secureToken;
    }

    final prefs = await SharedPreferences.getInstance();
    final legacyToken = prefs.getString(_tokenKey);
    if (legacyToken == null || legacyToken.isEmpty) {
      return null;
    }

    await _secureStorage.write(key: _tokenKey, value: legacyToken);
    await prefs.remove(_tokenKey);
    return legacyToken;
  }

  static Future<void> writeAccessToken(String token) async {
    await _secureStorage.write(key: _tokenKey, value: token);
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_tokenKey);
  }

  static Future<void> clearAccessToken() async {
    await _secureStorage.delete(key: _tokenKey);
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_tokenKey);
  }
}
