import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'l10n/app_localizations.dart';
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
import 'utils/memory_security.dart';
import 'services/cache_service.dart';
import 'services/language_service.dart';
import 'services/ws_service.dart';
import 'services/vault_service.dart';
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

  // Загружаем сохраненную тему
  await _loadSavedTheme();
  await LanguageService.instance.init();

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

class _PasswordManagerAppState extends State<PasswordManagerApp>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// CWE-316 / CWE-312 — clear the clipboard and lock the vault whenever the
  /// app leaves the foreground. The Dart Future.delayed timer used by
  /// MemorySecurity.copySensitiveData dies as soon as the isolate is paused,
  /// so without this hook a copied password would linger in the system
  /// clipboard until another app overwrites it — potentially forever.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      // Fire-and-forget: the isolate may be suspended imminently, so we want
      // the synchronous native clear to run before we lose CPU time.
      MemorySecurity.forceClearClipboard();
      // Lock the in-memory master key so a post-resume attacker without
      // biometrics/PIN can't read the vault.
      VaultService().lock();
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: LanguageService.instance,
      builder: (context, _) => MaterialApp(
        navigatorKey: navigatorKey,
        debugShowCheckedModeBanner: false,
        locale: LanguageService.instance.locale,
        supportedLocales: const [Locale('ru'), Locale('en')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        title: AppLocalizations.translateStandalone('Password Manager'),
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
      ),
    );
  }
}
