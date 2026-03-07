import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../theme/colors.dart';
import '../config/app_config.dart';
import '../widgets/otp_input_dialog.dart';

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
      final response = await http.post(
        Uri.parse(AppConfig.loginUrl),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({'login': login, 'password': password}),
      );

      final data = json.decode(response.body);

      if (response.statusCode == 200) {
        if (data['two_fa_required'] == true) {
          // Показываем ввод OTP
          if (!mounted) return;
          final String? otpCode = await showDialog<String>(
            context: context,
            builder: (context) => const OTPInputDialog(),
          );

          if (otpCode != null) {
            // Повторяем логин с OTP в заголовке
            await _loginWithOTP(login, password, otpCode);
          } else {
            setState(() => _isLoading = false);
          }
          return;
        }

        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('token', data['access_token']); // Backend returns access_token
        
        // Проверяем, установлен ли PIN-код
        final pinCode = prefs.getString('pin_code');
        if (pinCode != null) {
          Navigator.pushReplacementNamed(context, '/pin');
        } else {
          Navigator.pushReplacementNamed(context, '/setup-pin');
        }
      } else {
        setState(() {
          _errorMessage = data['error'] ?? 'Ошибка авторизации';
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Ошибка подключения к серверу';
      });
    } finally {
      setState(() {
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
          'Content-Type': 'application/json',
          'X-OTP': otp,
        },
        body: json.encode({'login': login, 'password': password}),
      );

      final data = json.decode(response.body);

      if (response.statusCode == 200) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('token', data['access_token']);
        
        if (!mounted) return;
        final pinCode = prefs.getString('pin_code');
        if (pinCode != null) {
          Navigator.pushReplacementNamed(context, '/pin');
        } else {
          Navigator.pushReplacementNamed(context, '/setup-pin');
        }
      } else {
        setState(() {
          _errorMessage = data['detail'] ?? 'Неверный код OTP';
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Ошибка подключения';
      });
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
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
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
              
              TextField(
                controller: _loginController,
                decoration: InputDecoration(
                  hintText: 'Логин',
                  filled: true,
                  fillColor: AppColors.input,
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _passwordController,
                obscureText: true,
                decoration: InputDecoration(
                  hintText: 'Пароль',
                  filled: true,
                  fillColor: AppColors.input,
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              if (_errorMessage != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(
                    _errorMessage!,
                    style: const TextStyle(color: Colors.red),
                  ),
                ),
              _isLoading
                  ? const CircularProgressIndicator()
                  : ElevatedButton(
                      onPressed: _login,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.button,
                        padding: const EdgeInsets.symmetric(horizontal: 60, vertical: 16),
                      ),
                      child: const Text('Войти'),
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
