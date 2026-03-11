import 'package:flutter_dotenv/flutter_dotenv.dart';

class AppConfig {
  static String get apiBaseUrl {
    return dotenv.env['API_BASE_URL'] ?? 'http://localhost:3000';
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
    return apiBaseUrl;
  }

  static String get baseUrl {
    return apiBaseUrl;
  }

  // Методы для получения полных URL эндпоинтов
  static String get loginUrl => '$apiUrl/login';
  static String get registerUrl => '$apiUrl/register';
  static String get setup2faUrl => '$apiUrl/2fa/setup';
  static String get confirm2faUrl => '$apiUrl/2fa/confirm';
  static String get passwordsUrl => '$apiUrl/passwords';
  static String get generatePasswordUrl => '$apiUrl/api/generate-password';
  static String get importPasswordsUrl => '$apiUrl/import-passwords';
  static String get updateFaviconsUrl => '$apiUrl/update-favicons';
  static String get passwordHistoryUrl => '$apiUrl/password-history';
  static String get foldersUrl => '$apiUrl/folders';
  static String get profileUrl => '$apiUrl/profile';
  static String get updateProfileUrl => '$apiUrl/profile/update';

  // WebAuthn Endpoints
  static String get webauthnRegisterOptionsUrl => '$apiUrl/webauthn/register/options';
  static String get webauthnRegisterVerifyUrl => '$apiUrl/webauthn/register/verify';
  static String get webauthnLoginOptionsUrl => '$apiUrl/webauthn/login/options';
  static String get webauthnLoginVerifyUrl => '$apiUrl/webauthn/login/verify';
  static String get webauthnDevicesUrl => '$apiUrl/webauthn/devices';

  static String getPasswordUrl(String siteUrl) => '$apiUrl/passwords/${Uri.encodeComponent(siteUrl)}';
  static String getFolderPasswordsUrl(int folderId) => '$apiUrl/folders/$folderId/passwords';
  static String getFolderUrl(int folderId) => '$apiUrl/folders/$folderId';
  static String getRevokeDeviceUrl(int deviceId) => '$apiUrl/webauthn/devices/$deviceId';

  // Password Rotation
  static String getRotationConfigUrl(int passwordId) => '$apiUrl/passwords/$passwordId/rotation';
  static String getRotateUrl(int passwordId) => '$apiUrl/passwords/$passwordId/rotate';
  static String get rotationDueUrl => '$apiUrl/passwords/rotation-due';

  // Secure Sharing
  static String get shareUrl => '$apiUrl/share';
  static String get shareIncomingUrl => '$apiUrl/share/incoming';
  static String get shareOutgoingUrl => '$apiUrl/share/outgoing';
  static String getShareUrl(int shareId) => '$apiUrl/share/$shareId';
  static String getShareAcceptUrl(int shareId) => '$apiUrl/share/$shareId/accept';

  // Emergency Access
  static String get emergencyAccessUrl => '$apiUrl/emergency-access';
  static String getEmergencyAcceptUrl(int eaId) => '$apiUrl/emergency-access/$eaId/accept';
  static String getEmergencyRequestUrl(int eaId) => '$apiUrl/emergency-access/$eaId/request-access';
  static String getEmergencyCheckinUrl(int eaId) => '$apiUrl/emergency-access/$eaId/checkin';
  static String getEmergencyDenyUrl(int eaId) => '$apiUrl/emergency-access/$eaId/deny';
  static String getEmergencyRevokeUrl(int eaId) => '$apiUrl/emergency-access/$eaId';
  static String getEmergencyVaultUrl(int eaId) => '$apiUrl/emergency-access/$eaId/vault';
}