import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:nk3_zero/screens/login_screen.dart';
import 'package:nk3_zero/screens/pin_screen.dart';
import 'package:nk3_zero/screens/setup_pin_screen.dart';
import '../config/app_config.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();

    _navigateAfterDelay();
  }

  Future<void> _navigateAfterDelay() async {
    await Future.delayed(const Duration(seconds: 2));

    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token');
    final pinHash = prefs.getString('pin_hash');

    if (!mounted) return;

    if (AppConfig.needsSetup) {
      Navigator.of(context).pushReplacementNamed('/setup-server');
      return;
    }

    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (context) {
          if (token != null) {
            if (pinHash != null) {
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
