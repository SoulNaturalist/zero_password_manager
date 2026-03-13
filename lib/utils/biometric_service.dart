import 'package:flutter_locker/flutter_locker.dart';
import 'package:shared_preferences/shared_preferences.dart';

class BiometricService {
  static const String _biometricKey = 'biometric_enabled';
  static const String _secretKey = 'biometric_passcode_key';

  // Проверка доступности биометрической аутентификации
  static Future<bool> isAvailable() async {
    try {
      final isAvailable = await FlutterLocker.canAuthenticate();
      print('BiometricService: canAuthenticate = $isAvailable');
      return isAvailable;
    } catch (e) {
      print('BiometricService: Error checking availability: $e');
      return false;
    }
  }

  // Проверяем, включена ли биометрия в настройках
  static Future<bool> isBiometricEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_biometricKey) ?? false;
  }

  // Включаем/выключаем биометрию
  static Future<void> setBiometricEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_biometricKey, enabled);
  }

  // Аутентификация пользователя и расшифровка секрета
  static Future<String?> authenticate({
    String reason = 'Подтвердите свою личность',
  }) async {
    try {
      final secret = await FlutterLocker.retrieve(
        RetrieveSecretRequest(
          key: _secretKey,
          androidPrompt: AndroidPrompt(title: reason, cancelLabel: 'Отмена'),
          iOsPrompt: IOsPrompt(touchIdText: reason),
        ),
      );
      print('BiometricService: Authentication successful');
      return secret;
    } catch (e) {
      print('BiometricService: Authentication failed: $e');
      return null;
    }
  }

  // Установка секрета с использованием биометрии
  static Future<bool> storeBiometricSecret(String value) async {
    try {
      await FlutterLocker.save(
        SaveSecretRequest(
          key: _secretKey,
          secret: value,
          androidPrompt: AndroidPrompt(
            title: 'Сохранить с биометрией',
            cancelLabel: 'Отмена',
          ),
        ),
      );
      print('BiometricService: Secret stored');
      return true;
    } catch (e) {
      print('BiometricService: Error storing secret: $e');
      return false;
    }
  }

  // Удаление биометрических данных
  static Future<void> resetBiometricSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_biometricKey);
      await FlutterLocker.delete(_secretKey);
      print('BiometricService: Biometric settings reset');
    } catch (e) {
      print('BiometricService: Error resetting biometric settings: $e');
    }
  }

  // Принудительное включение (для теста)
  static Future<bool> forceEnableBiometrics() async {
    final available = await isAvailable();
    if (!available) return false;

    final stored = await storeBiometricSecret('dummy_secret');
    if (!stored) return false;

    final authenticated = await authenticate();
    if (authenticated != null) {
      await setBiometricEnabled(true);
      return true;
    }

    return false;
  }

  // Диагностическая информация
  static Future<Map<String, dynamic>> getDiagnosticInfo() async {
    try {
      final canAuthenticate = await FlutterLocker.canAuthenticate();
      final isEnabled = await isBiometricEnabled();

      return {
        'canAuthenticate': canAuthenticate,
        'isEnabled': isEnabled,
        'systemStatus': canAuthenticate ? 'Доступна' : 'Недоступна',
        'canUseBiometrics': canAuthenticate && isEnabled,
        'canCheckBiometrics': canAuthenticate,
        'isDeviceSupported': canAuthenticate,
        'totalAvailableMethods': canAuthenticate ? 1 : 0,
        'biometricDetails':
            canAuthenticate
                ? {'fingerprint': 'Отпечаток пальца', 'face': 'Face ID'}
                : {},
        'availableBiometrics': canAuthenticate ? ['fingerprint', 'face'] : [],
      };
    } catch (e) {
      return {
        'error': e.toString(),
        'canAuthenticate': false,
        'isEnabled': false,
        'systemStatus': 'Ошибка при проверке',
        'canUseBiometrics': false,
        'canCheckBiometrics': false,
        'isDeviceSupported': false,
        'totalAvailableMethods': 0,
        'biometricDetails': {},
        'availableBiometrics': [],
      };
    }
  }
}
