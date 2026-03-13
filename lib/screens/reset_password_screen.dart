import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:flutter_form_builder/flutter_form_builder.dart';
import 'package:form_builder_validators/form_builder_validators.dart';
import '../theme/colors.dart';
import '../config/app_config.dart';
import '../models/server_error.dart';
import '../utils/form_error_handler.dart';

class ResetPasswordScreen extends StatefulWidget {
  const ResetPasswordScreen({super.key});

  @override
  State<ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends State<ResetPasswordScreen> with SingleTickerProviderStateMixin {
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

  Future<void> _resetPassword() async {
    if (!(_formKey.currentState?.saveAndValidate() ?? false)) {
      _playErrorShake();
      return;
    }

    setState(() => _isLoading = true);

    final values = _formKey.currentState!.value;
    
    try {
      final response = await http.post(
        Uri.parse(AppConfig.resetPasswordUrl),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'login': values['login'],
          'totp_code': values['totp_code'],
          'new_password': values['new_password'],
        }),
      );

      if (response.statusCode == 200) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Пароль успешно сброшен. Теперь вы можете войти.'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.pop(context);
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
      appBar: AppBar(
        title: const Text('Сброс пароля'),
        backgroundColor: AppColors.background,
        elevation: 0,
      ),
      body: Container(
        color: AppColors.background,
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
                      _buildSecurityWarning(),
                      const SizedBox(height: 32),
                      
                      FormBuilderTextField(
                        name: 'login',
                        style: TextStyle(color: AppColors.text),
                        decoration: _buildInputDecoration('Логин', Icons.person_outline),
                        validator: FormBuilderValidators.compose([
                          FormBuilderValidators.required(errorText: 'Введите логин'),
                        ]),
                      ),
                      const SizedBox(height: 16),

                      FormBuilderTextField(
                        name: 'totp_code',
                        style: TextStyle(color: AppColors.text),
                        decoration: _buildInputDecoration('TOTP код', Icons.shutter_speed_outlined),
                        keyboardType: TextInputType.number,
                        validator: FormBuilderValidators.compose([
                          FormBuilderValidators.required(errorText: 'Введите TOTP код'),
                          FormBuilderValidators.numeric(errorText: 'Только цифры'),
                          FormBuilderValidators.minLength(6, errorText: '6 цифр'),
                          FormBuilderValidators.maxLength(6, errorText: '6 цифр'),
                        ]),
                      ),
                      const SizedBox(height: 16),

                      FormBuilderTextField(
                        name: 'new_password',
                        obscureText: true,
                        style: TextStyle(color: AppColors.text),
                        decoration: _buildInputDecoration('Новый пароль', Icons.lock_outline),
                        validator: FormBuilderValidators.compose([
                          FormBuilderValidators.required(errorText: 'Введите новый пароль'),
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
                              ),
                              child: ElevatedButton(
                                onPressed: _resetPassword,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.transparent,
                                  shadowColor: Colors.transparent,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                                child: const Text(
                                  'Сбросить пароль',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                  ),
                                ),
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

  Widget _buildSecurityWarning() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.red.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.red.withOpacity(0.3)),
      ),
      child: Column(
        children: [
          const Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: Colors.redAccent),
              SizedBox(width: 8),
              Text(
                'Важное предупреждение!',
                style: TextStyle(
                  color: Colors.redAccent,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'Сброс пароля позволит войти в аккаунт, но НЕ восстановит доступ к зашифрованным паролям в сейфе автоматически. '
            'Для восстановления доступа к данным вам ПОТРЕБУЕТСЯ сид-фраза после входа.',
            style: TextStyle(
              color: AppColors.text.withOpacity(0.9),
              fontSize: 13,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }

  InputDecoration _buildInputDecoration(String hint, IconData icon) {
    return InputDecoration(
      hintText: hint,
      prefixIcon: Icon(icon, color: AppColors.button),
      filled: true,
      fillColor: AppColors.input,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      errorStyle: const TextStyle(color: Colors.redAccent),
    );
  }
}
