import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'screens/login_screen.dart';
import 'screens/signup_screen.dart';
import 'screens/passwords_screen.dart';
import 'screens/add_password_screen.dart';
import 'screens/splash_screen.dart';
import 'screens/pin_screen.dart';
import 'screens/setup_pin_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/biometric_test_screen.dart';
import 'screens/password_history_screen.dart';
import 'screens/folders_screen.dart';
import 'screens/setup_server_screen.dart';
import 'screens/totp_confirm_screen.dart';
import 'screens/telegram_binding_screen.dart';
import 'screens/reset_password_screen.dart';
import 'theme/colors.dart';
import 'utils/config_test.dart';
import 'services/cache_service.dart';
import 'services/ws_service.dart';
import 'config/app_config.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Загружаем конфигурацию в зависимости от окружения
  const environment = String.fromEnvironment(
    'ENVIRONMENT',
    defaultValue: 'dev',
  );
  await dotenv.load(fileName: 'env.$environment');

  await AppConfig.init();

  // Инициализируем локальный кэш (Hive)
  await CacheService().init();

  // Инициализируем WebSockets для мониторинга событий безопасности
  await WsService().init();

  // Загружаем сохраненную тему
  await _loadSavedTheme();

  // Выводим текущую конфигурацию
  ConfigTest.printCurrentConfig();

  runApp(const PasswordManagerApp());
}

Future<void> _loadSavedTheme() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final themeIndex = prefs.getInt('app_theme') ?? 0;
    final theme = AppTheme.values[themeIndex];
    ThemeManager.setTheme(theme);
  } catch (e) {
    ThemeManager.setTheme(AppTheme.dark);
  }
}

final RouteObserver<ModalRoute<void>> routeObserver =
    RouteObserver<ModalRoute<void>>();

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

class PasswordManagerApp extends StatefulWidget {
  const PasswordManagerApp({super.key});

  @override
  State<PasswordManagerApp> createState() => _PasswordManagerAppState();
}

class _PasswordManagerAppState extends State<PasswordManagerApp> {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: navigatorKey,
      debugShowCheckedModeBanner: false,
      title: 'Password Manager',
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: AppColors.background,
      ),
      initialRoute: '/',
      navigatorObservers: [routeObserver],
      routes: {
        '/': (context) => const SplashScreen(),
        '/signup': (context) => const SignUpScreen(),
        '/login': (context) => const LoginScreen(),
        '/pin': (context) => const PinScreen(),
        '/setup-pin': (context) => const SetupPinScreen(),
        '/settings': (context) => const SettingsScreen(),
        '/passwords': (context) => const PasswordsScreen(),
        '/add': (context) => const AddPasswordScreen(),
        '/biometric-test': (context) => const BiometricTestScreen(),
        '/password-history': (context) => const PasswordHistoryScreen(),
        '/folders': (context) => const FoldersScreen(),
        '/setup-server': (context) => const SetupServerScreen(),
        '/totp-confirm': (context) => const TotpConfirmScreen(),
        '/telegram-binding': (context) => const TelegramBindingScreen(),
        '/reset-password': (context) => const ResetPasswordScreen(),
      },
    );
  }
}
