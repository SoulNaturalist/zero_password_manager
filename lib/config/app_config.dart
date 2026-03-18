import 'package:flutter_dotenv/flutter_dotenv.dart';

import 'package:shared_preferences/shared_preferences.dart';

class AppConfig {
  static String? apiBaseUrl;
  static bool isInitialized = false;

  static Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    apiBaseUrl = prefs.getString("api_base_url");
    isInitialized = true;
  }

  static Future<void> setApiBaseUrl(String url) async {
    final prefs = await SharedPreferences.getInstance();
    if (url.endsWith('/')) {
      url = url.substring(0, url.length - 1);
    }
    await prefs.setString("api_base_url", url);
    apiBaseUrl = url;
  }

  static bool get needsSetup {
    return apiBaseUrl == null || apiBaseUrl!.isEmpty;
  }

  static String get environment {
    return dotenv.env['ENVIRONMENT'] ?? 'dev';
  }

  static bool get isDevelopment {
    return environment == 'dev';
  }

  static bool get isProduction {
    return environment == 'prod';
  }

  static String get apiUrl {
    return apiBaseUrl ?? 'http://localhost:3000';
  }

  static String get baseUrl {
    return apiUrl;
  }

  // Методы для получения полных URL эндпоинтов
  static String get loginUrl => '$apiUrl/api/v1/login';
  static String get loginMfaUrl => '$apiUrl/api/v1/login/mfa';
  static String get registerUrl => '$apiUrl/api/v1/register';
  static String get setup2faUrl => '$apiUrl/api/v1/setup_2fa';
  static String get confirm2faUrl => '$apiUrl/api/v1/confirm_2fa';
  static String get passwordsUrl => '$apiUrl/passwords';
  static String get importPasswordsUrl => '$apiUrl/import-passwords';
  static String get updateFaviconsUrl => '$apiUrl/update-favicons';
  static String get passwordHistoryUrl => '$apiUrl/password-history';
  static String get foldersUrl => '$apiUrl/folders';
  static String get profileUrl => '$apiUrl/profile';
  static String get updateProfileUrl => '$apiUrl/profile/update';
  static String get resetPasswordUrl => '$apiUrl/api/v1/reset-password';
  static String get verifyTotpUrl => '$apiUrl/api/v1/verify-totp';
  static String get seedPhraseUrl => '$apiUrl/profile/seed-phrase';
  static String get shareUrl => '$apiUrl/sharing';
  static String get shareIncomingUrl => '$apiUrl/sharing/incoming';
  static String get shareOutgoingUrl => '$apiUrl/sharing/outgoing';
  static String get emergencyAccessUrl => '$apiUrl/emergency-access';
  static String get rotationDueUrl => '$apiUrl/rotation/due';

  // WebAuthn Endpoints
  static String get webauthnRegisterOptionsUrl =>
      '$apiUrl/webauthn/register/options';
  static String get webauthnRegisterVerifyUrl =>
      '$apiUrl/webauthn/register/verify';
  static String get webauthnLoginOptionsUrl => '$apiUrl/webauthn/login/options';
  static String get webauthnLoginVerifyUrl => '$apiUrl/webauthn/login/verify';
  static String get webauthnDevicesUrl => '$apiUrl/webauthn/devices';

  static String getPasswordUrl(String siteUrl) =>
      '$apiUrl/passwords/${Uri.encodeComponent(siteUrl)}';
  static String getFolderPasswordsUrl(int folderId) =>
      '$apiUrl/folders/$folderId/passwords';
  static String getFolderUrl(int folderId) => '$apiUrl/folders/$folderId';
  static String getRevokeDeviceUrl(int deviceId) =>
      '$apiUrl/webauthn/devices/$deviceId';

  // Emergency Access Urls
  static String getEmergencyAcceptUrl(int id) => '$apiUrl/emergency-access/$id/accept';
  static String getEmergencyRequestUrl(int id) => '$apiUrl/emergency-access/$id/request';
  static String getEmergencyCheckinUrl(int id) => '$apiUrl/emergency-access/$id/checkin';
  static String getEmergencyDenyUrl(int id) => '$apiUrl/emergency-access/$id/deny';
  static String getEmergencyRevokeUrl(int id) => '$apiUrl/emergency-access/$id/revoke';
  static String getEmergencyVaultUrl(int id) => '$apiUrl/emergency-access/$id/vault';

  // Sharing Urls
  static String getShareAcceptUrl(int id) => '$apiUrl/sharing/$id/accept';
  static String getShareUrl(int id) => '$apiUrl/sharing/$id';

  // Rotation Urls
  static String getRotationConfigUrl(int id) => '$apiUrl/rotation/$id/config';
  static String getRotateUrl(int id) => '$apiUrl/rotation/$id/rotate';
}
