import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:safe_device/safe_device.dart';
import 'package:nk3_zero/screens/login_screen.dart';
import 'package:nk3_zero/screens/pin_screen.dart';
import 'package:nk3_zero/screens/setup_pin_screen.dart';
import '../config/app_config.dart';
import '../utils/pin_security.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  bool _isDeviceCompromised = false;

  @override
  void initState() {
    super.initState();
    _checkSecurityAndNavigate();
  }

  Future<void> _checkSecurityAndNavigate() async {
    bool isCompromised = false;
    try {
      // Check for Root/Jailbreak or unsafe environment
      bool isJailBroken = await SafeDevice.isJailBroken;
      bool isRealDevice = await SafeDevice.isRealDevice;
      
      // We block if it's jailbroken. We could also block if it's an emulator
      // but let's stick to user request of blocking on Root/Jailbreak primarily.
      if (isJailBroken) {
        isCompromised = true;
      }
    } catch (e) {
      debugPrint("Security check error: $e");
    }

    if (!mounted) return;

    if (isCompromised) {
      setState(() => _isDeviceCompromised = true);
      return;
    }

    await Future.delayed(const Duration(seconds: 2));
    await _navigateNext();
  }

  Future<void> _navigateNext() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token');
    final hasPinHash = await PinSecurity.hasPinHash();

    if (!mounted) return;

    if (AppConfig.needsSetup) {
      Navigator.of(context).pushReplacementNamed('/setup-server');
      return;
    }

    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (context) {
          if (token != null) {
            if (hasPinHash) {
              return const PinScreen();
            } else {
              return const SetupPinScreen();
            }
          } else {
            return const LoginScreen();
          }
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isDeviceCompromised) {
      return Scaffold(
        backgroundColor: Theme.of(context).colorScheme.background,
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.gpp_bad_rounded, color: Colors.red, size: 80),
                const SizedBox(height: 24),
                Text(
                  'Устройство небезопасно',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        color: Colors.red,
                        fontWeight: FontWeight.bold,
                      ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                Text(
                  'Обнаружены root-права или модификация системы. В целях защиты ваших паролей приложение заблокировано.',
                  style: Theme.of(context).textTheme.bodyMedium,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 32),
                ElevatedButton(
                  onPressed: () => SystemNavigator.pop(),
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                  child: const Text('Закрыть приложение', style: TextStyle(color: Colors.white)),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.background,
      body: Center(
        child: Image.asset(
          'lib/assets/raw.png',
          width: 150,
          height: 150,
          fit: BoxFit.contain,
        ),
      ),
    );
  }
}
