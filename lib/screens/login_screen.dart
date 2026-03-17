import 'package:flutter/material.dart';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_form_builder/flutter_form_builder.dart';
import 'package:form_builder_validators/form_builder_validators.dart';
import 'package:device_info_plus/device_info_plus.dart';
import '../theme/colors.dart';
import '../config/app_config.dart';
import '../widgets/otp_input_dialog.dart';
import '../utils/passkey_service.dart';
import '../services/vault_service.dart';
import '../models/server_error.dart';
import '../utils/form_error_handler.dart';
import '../utils/security_utils.dart';
import '../utils/pin_security.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormBuilderState>();
  bool _isLoading = false;
  late AnimationController _shakeController;
  final PasskeyService _passkeyService = PasskeyService();

  @override
  void initState() {
    super.initState();
    _shakeController = AnimationController(
      duration: const Duration(milliseconds: 500),
      vsync: this,
    );
  }

  @override
  void dispose() {
    _shakeController.dispose();
    super.dispose();
  }

  void _playErrorShake() {
    _shakeController.forward(from: 0.0);
  }

  Future<void> _login() async {
    if (!(_formKey.currentState?.saveAndValidate() ?? false)) {
      _playErrorShake();
      return;
    }

    setState(() => _isLoading = true);

    final values = _formKey.currentState!.value;
    final login = values['login'];
    final password = values['password'];
    final devicePayload = await SecurityUtils.getDeviceSecurityPayload();

    try {
      final response = await http.post(
        Uri.parse(AppConfig.loginUrl),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'login': login, 
          'password': password,
          'device_info': devicePayload,
        }),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        
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

        await _handleSuccessfulLogin(data, password);
      } else {
        final error = ServerError.fromJson(response.body, response.statusCode);
        if (!mounted) return;
        
        FormErrorHandler.applyErrors(
          formKey: _formKey,
          error: error,
          context: context,
        );
        _playErrorShake();
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ошибка подключения к серверу')),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _loginWithOTP(String login, String password, String otp) async {
    setState(() => _isLoading = true);
    final devicePayload = await SecurityUtils.getDeviceSecurityPayload();
    
    try {
      final response = await http.post(
        Uri.parse(AppConfig.loginUrl),
        headers: {'Content-Type': 'application/json', 'X-OTP': otp},
        body: json.encode({
          'login': login, 
          'password': password,
          'device_info': devicePayload,
        }),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        await _handleSuccessfulLogin(data, password);
      } else {
        final error = ServerError.fromJson(response.body, response.statusCode);
        if (!mounted) return;
        FormErrorHandler.applyErrors(formKey: _formKey, error: error, context: context);
        _playErrorShake();
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Ошибка OTP')));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _handleSuccessfulLogin(Map<String, dynamic> data, String password) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('token', data['access_token']);

    final salt = data['salt'];
    if (salt != null) {
      await VaultService().unlock(password, salt);
    }

    if (!mounted) return;
    final hasPinHash = await PinSecurity.hasPinHash();
    if (hasPinHash) {
      Navigator.pushReplacementNamed(context, '/pin');
    } else {
      Navigator.pushReplacementNamed(context, '/setup-pin');
    }
  }

  Future<void> _loginWithPasskey() async {
    setState(() => _isLoading = true);

    try {
      final deviceInfo = DeviceInfoPlugin();
      String deviceId = 'unknown';

      if (Platform.isAndroid) {
        deviceId = (await deviceInfo.androidInfo).id;
      } else if (Platform.isIOS) {
        deviceId = (await deviceInfo.iosInfo).identifierForVendor ?? 'unknown_ios';
      }

      final data = await _passkeyService.loginWithPasskey(deviceId);

      if (data != null && data['access_token'] != null) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('token', data['access_token']);

        if (!mounted) return;
        final hasPinHash = await PinSecurity.hasPinHash();
        if (hasPinHash) {
          Navigator.pushReplacementNamed(context, '/pin');
        } else {
          Navigator.pushReplacementNamed(context, '/setup-pin');
        }
      } else {
        _playErrorShake();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Ошибка входа через Passkey')),
          );
        }
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Ошибка: $e')));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(color: AppColors.background),
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24.0),
            child: AnimatedBuilder(
              animation: _shakeController,
              builder: (context, child) {
                final double offset = 10 *
                    (1 - _shakeController.value) *
                    (0.5 - (0.5 - _shakeController.value).abs()).sign;
                return Transform.translate(
                  offset: Offset(offset, 0),
                  child: child,
                );
              },
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 400),
                child: FormBuilder(
                  key: _formKey,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _buildHeader(),
                      const SizedBox(height: 48),

                      FormBuilderTextField(
                        name: 'login',
                        style: TextStyle(color: AppColors.text),
                        decoration: InputDecoration(
                          hintText: 'Логин',
                          prefixIcon: Icon(Icons.person_outline, color: AppColors.button),
                          filled: true,
                          fillColor: AppColors.input,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none,
                          ),
                        ),
                        validator: FormBuilderValidators.compose([
                          FormBuilderValidators.required(errorText: 'Введите логин'),
                        ]),
                      ),
                      const SizedBox(height: 16),

                      FormBuilderTextField(
                        name: 'password',
                        obscureText: true,
                        style: TextStyle(color: AppColors.text),
                        decoration: InputDecoration(
                          hintText: 'Пароль',
                          prefixIcon: Icon(Icons.lock_outline, color: AppColors.button),
                          filled: true,
                          fillColor: AppColors.input,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none,
                          ),
                        ),
                        validator: FormBuilderValidators.required(errorText: 'Введите пароль'),
                      ),
                      const SizedBox(height: 32),

                      _isLoading
                          ? const CircularProgressIndicator()
                          : Column(
                              children: [
                                Container(
                                  width: double.infinity,
                                  height: 56,
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(12),
                                    gradient: LinearGradient(
                                      colors: [AppColors.button, AppColors.button.withOpacity(0.8)],
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                        color: AppColors.button.withOpacity(0.3),
                                        blurRadius: 10,
                                        offset: const Offset(0, 4),
                                      ),
                                    ],
                                  ),
                                  child: ElevatedButton(
                                    onPressed: _login,
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.transparent,
                                      shadowColor: Colors.transparent,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                    ),
                                    child: const Text(
                                      'Войти',
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 16),
                                OutlinedButton.icon(
                                  onPressed: _isLoading ? null : _loginWithPasskey,
                                  icon: const Icon(Icons.fingerprint),
                                  label: const Text('Войти с Passkey'),
                                  style: OutlinedButton.styleFrom(
                                    minimumSize: const Size(double.infinity, 56),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    side: BorderSide(color: AppColors.button),
                                    foregroundColor: Colors.white,
                                  ),
                                ),
                              ],
                            ),
                      
                      const SizedBox(height: 24),
                      TextButton(
                        onPressed: () => Navigator.pushNamed(context, '/reset-password'),
                        child: Text(
                          'Забыли пароль?',
                          style: TextStyle(color: AppColors.button.withOpacity(0.8)),
                        ),
                      ),
                      TextButton(
                        onPressed: () => Navigator.pushReplacementNamed(context, '/signup'),
                        child: Text(
                          'Нет аккаунта? Зарегистрироваться',
                          style: TextStyle(color: AppColors.button),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Column(
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
          child: const Icon(Icons.security, size: 40, color: Colors.white),
        ),
        const SizedBox(height: 16),
        ShaderMask(
          shaderCallback: (bounds) => LinearGradient(
            colors: [AppColors.button, AppColors.button.withOpacity(0.7)],
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
          'Защищенный вход в хранилище',
          style: TextStyle(
            fontSize: 16,
            color: Colors.grey[400],
            fontWeight: FontWeight.w300,
          ),
        ),
      ],
    );
  }
}
