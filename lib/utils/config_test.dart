import '../config/app_config.dart';

class ConfigTest {
  static void printCurrentConfig() {
    print('=== ТЕКУЩАЯ КОНФИГУРАЦИЯ ===');
    print('Окружение: ${AppConfig.environment}');
    print('Базовый URL: ${AppConfig.apiBaseUrl}');
    print('Режим разработки: ${AppConfig.isDevelopment}');
    print('Режим продакшена: ${AppConfig.isProduction}');
    print('');
    print('=== URL ЭНДПОИНТОВ ===');
    print('Login: ${AppConfig.loginUrl}');
    print('Register: ${AppConfig.registerUrl}');
    print('Passwords: ${AppConfig.passwordsUrl}');
    print('Generate Password: ${AppConfig.generatePasswordUrl}');
    print('Import Passwords: ${AppConfig.importPasswordsUrl}');
    print('========================');
  }
}
