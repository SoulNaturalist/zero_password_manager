import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:io' show Platform;
import 'package:shared_preferences/shared_preferences.dart';
import '../theme/colors.dart';
import '../config/app_config.dart';
import '../widgets/otp_input_dialog.dart';
import '../utils/passkey_service.dart';
import '../utils/biometric_service.dart';
import 'package:device_info_plus/device_info_plus.dart';
import '../services/crypto_service.dart';
import '../services/vault_service.dart';
import 'package:cryptography/cryptography.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final TextEditingController _loginController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  bool _isLoading = false;
  String? _errorMessage;
  final PasskeyService _passkeyService = PasskeyService();

  // ── Password login ─────────────────────────────────────────────────────────

  Future<void> _login() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final login = _loginController.text.trim();
    final password = _passwordController.text.trim();

    if (login.isEmpty || password.isEmpty) {
      setState(() {
        _errorMessage = 'Пожалуйста, введите логин и пароль';
        _isLoading = false;
      });
      return;
    }

    try {
      // Server uses OAuth2PasswordRequestForm — must send x-www-form-urlencoded
      // with field names "username" and "password".
      final response = await http.post(
        Uri.parse(AppConfig.loginUrl),
        headers: {'Content-Type': 'application/x-www-form-urlencoded'},
        body: 'username=${Uri.encodeComponent(login)}'
            '&password=${Uri.encodeComponent(password)}',
      );

      final data = json.decode(response.body);

      if (response.statusCode == 200) {
        if (data['two_fa_required'] == true) {
          if (!mounted) return;
          final String? otpCode = await showDialog<String>(
            context: context,
            builder: (context) => const OTPInputDialog(),
          );
          if (otpCode != null) {
            await _loginWithOTP(login, password, otpCode);
          } else {
            setState(() => _isLoading = false);
          }
          return;
        }

        await _onLoginSuccess(data, password);
      } else {
        setState(() {
          _errorMessage = data['detail'] ?? data['error'] ?? 'Ошибка авторизации';
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Ошибка подключения к серверу';
        _isLoading = false;
      });
    }
  }

  Future<void> _loginWithOTP(String login, String password, String otp) async {
    setState(() => _isLoading = true);
    try {
      final response = await http.post(
        Uri.parse(AppConfig.loginUrl),
        headers: {
          'Content-Type': 'application/x-www-form-urlencoded',
          'X-OTP': otp,
        },
        body: 'username=${Uri.encodeComponent(login)}'
            '&password=${Uri.encodeComponent(password)}',
      );

      final data = json.decode(response.body);

      if (response.statusCode == 200) {
        await _onLoginSuccess(data, password);
      } else {
        setState(() {
          _errorMessage = data['detail'] ?? 'Неверный код OTP';
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Ошибка подключения';
        _isLoading = false;
      });
    }
  }

  /// Common post-login setup: store token, derive master key, store it for
  /// biometric unlock, navigate to PIN.
  Future<void> _onLoginSuccess(Map<String, dynamic> data, String password) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('token', data['access_token'] ?? '');

    final salt = data['salt'] as String?;
    if (salt != null && password.isNotEmpty) {
      // Derive and unlock the vault
      await VaultService().unlock(password, salt);

      // Persist master key for biometric unlock so the vault can be opened
      // without re-entering the master password.
      final masterKey = VaultService().masterKey;
      if (masterKey != null) {
        final keyBytes = await masterKey.extractBytes();
        final keyB64 = base64.encode(keyBytes);
        // Store in secure storage (used by passkey and biometric flows)
        await _passkeyService.saveVaultKey(keyB64);
        // Also store in flutter_locker if biometrics are enabled
        if (await BiometricService.isBiometricEnabled()) {
          await BiometricService.storeBiometricSecret(keyB64);
        }
      }
    }

    if (!mounted) return;
    final pinHash = prefs.getString('pin_hash');
    if (pinHash != null) {
      Navigator.pushReplacementNamed(context, '/pin');
    } else {
      Navigator.pushReplacementNamed(context, '/setup-pin');
    }
  }

  // ── Passkey login ──────────────────────────────────────────────────────────

  Future<void> _loginWithPasskey() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final deviceInfo = DeviceInfoPlugin();
      String deviceId = 'unknown';

      if (Platform.isAndroid) {
        final androidInfo = await deviceInfo.androidInfo;
        deviceId = androidInfo.id;
      } else if (Platform.isIOS) {
        final iosInfo = await deviceInfo.iosInfo;
        deviceId = iosInfo.identifierForVendor ?? 'unknown_ios';
      }

      final data = await _passkeyService.loginWithPasskey(deviceId);

      if (data != null && data['access_token'] != null) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('token', data['access_token'] as String);

        // Restore master key from secure storage (saved during password login)
        final vaultKeyB64 = await _passkeyService.getVaultKey();
        if (vaultKeyB64 != null) {
          VaultService().setKey(SecretKey(base64.decode(vaultKeyB64)));
        } else {
          // Key not available — user must log in with password once to seed it
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  'Войдите один раз с паролем, чтобы активировать быстрый вход.',
                ),
                backgroundColor: Colors.orange,
              ),
            );
          }
        }

        if (!mounted) return;
        final pinHash = prefs.getString('pin_hash');
        if (pinHash != null) {
          Navigator.pushReplacementNamed(context, '/pin');
        } else {
          Navigator.pushReplacementNamed(context, '/setup-pin');
        }
      } else {
        setState(() => _errorMessage = 'Ошибка входа через Passkey');
      }
    } catch (e) {
      setState(() => _errorMessage = 'Ошибка: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  void dispose() {
    _loginController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Logo
              Container(
                margin: const EdgeInsets.only(bottom: 60),
                child: Column(
                  children: [
                    Container(
                      width: 80,
                      height: 80,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            AppColors.button.withOpacity(0.8),
                            AppColors.button.withOpacity(0.4),
                          ],
                        ),
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.button.withOpacity(0.3),
                            blurRadius: 15,
                            spreadRadius: 2,
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.security,
                        size: 40,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 16),
                    ShaderMask(
                      shaderCallback: (bounds) => LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          AppColors.button,
                          AppColors.button.withOpacity(0.7),
                        ],
                      ).createShader(bounds),
                      child: const Text(
                        'ZERO',
                        style: TextStyle(
                          fontSize: 48,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                          letterSpacing: 4,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Менеджер паролей',
                      style: TextStyle(
                        fontSize: 16,
                        color: Colors.grey[400],
                        fontWeight: FontWeight.w300,
                      ),
                    ),
                  ],
                ),
              ),

              // Login field
              TextField(
                controller: _loginController,
                autocorrect: false,
                decoration: InputDecoration(
                  hintText: 'Логин',
                  filled: true,
                  fillColor: AppColors.input,
                  border: const OutlineInputBorder(),
                  prefixIcon: const Icon(Icons.person),
                ),
              ),
              const SizedBox(height: 16),

              // Password field
              TextField(
                controller: _passwordController,
                obscureText: true,
                autocorrect: false,
                decoration: InputDecoration(
                  hintText: 'Пароль',
                  filled: true,
                  fillColor: AppColors.input,
                  border: const OutlineInputBorder(),
                  prefixIcon: const Icon(Icons.lock),
                ),
                onSubmitted: (_) => _login(),
              ),
              const SizedBox(height: 16),

              if (_errorMessage != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.red.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.red.withOpacity(0.3)),
                    ),
                    child: Text(
                      _errorMessage!,
                      style: const TextStyle(color: Colors.red),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),

              // Login button
              _isLoading
                  ? const CircularProgressIndicator()
                  : ElevatedButton(
                      onPressed: _login,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.button,
                        minimumSize: const Size(double.infinity, 50),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text(
                        'Войти',
                        style: TextStyle(fontSize: 16, color: Colors.white),
                      ),
                    ),
              const SizedBox(height: 16),

              // Passkey button
              OutlinedButton.icon(
                onPressed: _isLoading ? null : _loginWithPasskey,
                icon: const Icon(Icons.fingerprint),
                label: const Text('Войти с Passkey / биометрией'),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(double.infinity, 50),
                  side: BorderSide(color: AppColors.button),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
              const SizedBox(height: 16),

              TextButton(
                onPressed: () => Navigator.pushNamed(context, '/signup'),
                child: const Text('Нет аккаунта? Зарегистрироваться'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
