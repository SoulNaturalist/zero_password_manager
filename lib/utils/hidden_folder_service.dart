import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../config/app_config.dart';

/// In-memory session service that tracks whether the user has unlocked
/// hidden folders via TOTP this session. Resets on app restart.
class HiddenFolderService {
  HiddenFolderService._();
  static final HiddenFolderService instance = HiddenFolderService._();

  bool _unlocked = false;

  bool get isUnlocked => _unlocked;

  /// Submit a TOTP code to the server. Returns true on success.
  Future<bool> verifyTotp(String code) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('token');

      final response = await http.post(
        Uri.parse(AppConfig.verifyTotpUrl),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({'otp': code}),
      );

      if (response.statusCode == 200) {
        _unlocked = true;
        return true;
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  /// Lock hidden folders again (called from settings toggle or logout).
  void lock() => _unlocked = false;
}
