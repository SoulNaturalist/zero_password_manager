import 'dart:math';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:flutter_form_builder/flutter_form_builder.dart';
import 'package:form_builder_validators/form_builder_validators.dart';
import '../theme/colors.dart';
import '../config/app_config.dart';
import '../widgets/two_factor_setup_dialog.dart';
import '../services/auth_token_storage.dart';
import '../services/vault_service.dart';
import '../models/server_error.dart';
import '../utils/form_error_handler.dart';

class SignUpScreen extends StatefulWidget {
  const SignUpScreen({super.key});

  @override
  State<SignUpScreen> createState() => _SignUpScreenState();
}

class _SignUpScreenState extends State<SignUpScreen> with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormBuilderState>();
  bool _isLoading = false;
  late AnimationController _shakeController;

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

  Future<void> _generatePassword() async {
    try {
      // Client-side password generation
      final password = _generatePasswordString(24);
      _formKey.currentState?.fields['password']?.didChange(password);
      
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Сгенерирован надежный пароль'),
          backgroundColor: Colors.green,
          duration: Duration(seconds: 2),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Не удалось сгенерировать пароль')),
      );
    }
  }

  String _generatePasswordString(int length) {
    if (length < 24) length = 24;

    const upper   = 'ABCDEFGHJKLMNPQRSTUVWXYZ';   // no I/O (ambiguous)
    const lower   = 'abcdefghjkmnpqrstuvwxyz';     // no i/l/o
    const digits  = '23456789';                    // no 0/1
    const symbols = r'!@#$%^&*()_+-=[]{}|;:,.<>?';

    final rng = Random.secure();

    int pick(String charset) => rng.nextInt(charset.length);

    // Guarantee at least two of each required character class.
    final mandatory = [
      upper[pick(upper)],
      upper[pick(upper)],
      lower[pick(lower)],
      lower[pick(lower)],
      digits[pick(digits)],
      digits[pick(digits)],
      symbols[pick(symbols)],
      symbols[pick(symbols)],
    ];

    final allChars = upper + lower + digits + symbols;
    final password = List<String>.from(mandatory);
    while (password.length < length) {
      password.add(allChars[pick(allChars)]);
    }

    // Fisher-Yates shuffle using the same CSPRNG.
    for (int i = password.length - 1; i > 0; i--) {
      final j = rng.nextInt(i + 1);
      final tmp = password[i];
      password[i] = password[j];
      password[j] = tmp;
    }

    return password.join();
  }

  Future<void> _register() async {
    if (!(_formKey.currentState?.saveAndValidate() ?? false)) {
      _playErrorShake();
      return;
    }

    setState(() => _isLoading = true);

    final values = _formKey.currentState!.value;
    final login = values['login'];
    final password = values['password'];

    try {
      // 1. Client-side Zero-Knowledge: Generate salt and derive Master Key
      final salt = VaultService.generateRandomSalt();
      final masterKey = await VaultService.generateMasterKey(password, salt);

      // 2. Send registration request with the client-generated salt
      final response = await http.post(
        Uri.parse(AppConfig.registerUrl),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'login': login,
          'password': password,
          'salt': salt, // Send salt to server
        }),
      );

      if (response.statusCode == 201) {
        final data = jsonDecode(response.body);
        if (!mounted) return;

        final dynamic setupData = await showDialog<dynamic>(
          context: context,
          barrierDismissible: false,
          builder: (context) => TwoFactorSetupDialog(
            userId: data['id'],
            login: data['login'],
            initialSecret: data['totp_secret'],
            initialOtpUri: data['totp_uri'],
            enrollmentToken: data['access_token'],
          ),
        );

        if (setupData != null && setupData is Map<String, dynamic>) {
          // 3. Save Master Key to session (VaultService) after successful 2FA setup
          await VaultService.saveMasterKey(masterKey);

          await AuthTokenStorage.writeAccessToken(setupData['access_token'] as String);

          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Регистрация успешно завершена')),
          );

          // New users must always set up a PIN
          Navigator.pushReplacementNamed(context, '/setup-pin');
        }
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          color: AppColors.background,
        ),
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
                      // Logo & Header (Keep original UI)
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
                          errorStyle: const TextStyle(color: Colors.redAccent),
                        ),
                        validator: FormBuilderValidators.compose([
                          FormBuilderValidators.required(errorText: 'Введите логин'),
                          FormBuilderValidators.minLength(3, errorText: 'Минимум 3 символа'),
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
                          suffixIcon: IconButton(
                            icon: const Icon(Icons.auto_fix_high),
                            color: AppColors.button,
                            tooltip: 'Сгенерировать надежный пароль',
                            onPressed: _generatePassword,
                          ),
                          filled: true,
                          fillColor: AppColors.input,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none,
                          ),
                          errorMaxLines: 3,
                          errorStyle: const TextStyle(color: Colors.redAccent),
                        ),
                        validator: FormBuilderValidators.compose([
                          FormBuilderValidators.required(errorText: 'Введите пароль'),
                          FormBuilderValidators.minLength(14, errorText: 'Минимум 14 символов'),
                        ]),
                      ),
                      const SizedBox(height: 32),

                      _isLoading
                          ? const CircularProgressIndicator()
                          : Container(
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
                                onPressed: _register,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.transparent,
                                  shadowColor: Colors.transparent,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                                child: const Text(
                                  'Зарегистрироваться',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            ),
                      const SizedBox(height: 24),
                      TextButton(
                        onPressed: () => Navigator.pushReplacementNamed(context, '/login'),
                        child: Text(
                          'Уже есть аккаунт? Войти',
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
          child: const Icon(Icons.person_add, size: 40, color: Colors.white),
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
          'Создание защищенного аккаунта',
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
