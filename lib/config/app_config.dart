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

  static String getPasswordUrl(String siteUrl) => '$apiUrl/passwords/${Uri.encodeComponent(siteUrl)}';
  static String getFolderPasswordsUrl(int folderId) => '$apiUrl/folders/$folderId/passwords';
  static String getFolderUrl(int folderId) => '$apiUrl/folders/$folderId';
} 