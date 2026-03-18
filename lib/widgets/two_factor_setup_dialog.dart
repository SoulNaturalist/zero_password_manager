import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:flutter_form_builder/flutter_form_builder.dart';
import 'package:form_builder_validators/form_builder_validators.dart';
import '../config/app_config.dart';
import '../theme/colors.dart';
import '../models/server_error.dart';
import '../utils/form_error_handler.dart';

class TwoFactorSetupDialog extends StatefulWidget {
  final int userId;
  final String login;
  final String? initialSecret;
  final String? initialOtpUri;
  /// Bearer token used to authenticate /confirm_2fa during the enrollment
  /// flow (before the user has logged in for the first time).
  final String? enrollmentToken;

  const TwoFactorSetupDialog({
    super.key,
    required this.userId,
    required this.login,
    this.initialSecret,
    this.initialOtpUri,
    this.enrollmentToken,
  });

  @override
  State<TwoFactorSetupDialog> createState() => _TwoFactorSetupDialogState();
}

class _TwoFactorSetupDialogState extends State<TwoFactorSetupDialog> {
  String? _secret;
  String? _otpUri;
  final _formKey = GlobalKey<FormBuilderState>();
  bool _isFetching = true;
  bool _isConfirming = false;

  @override
  void initState() {
    super.initState();
    if (widget.initialSecret != null && widget.initialOtpUri != null) {
      _secret = widget.initialSecret;
      _otpUri = widget.initialOtpUri;
      _isFetching = false;
    } else {
      _fetchSetupData();
    }
  }

  Future<void> _fetchSetupData() async {
    try {
      final headers = <String, String>{'Content-Type': 'application/json'};
      if (widget.enrollmentToken != null) {
        headers['Authorization'] = 'Bearer ${widget.enrollmentToken}';
      }
      final response = await http.post(
        Uri.parse(AppConfig.setup2faUrl),
        headers: headers,
        body: json.encode({'user_id': widget.userId}),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        setState(() {
          _secret = data['secret'];
          _otpUri = data['otp_uri'];
          _isFetching = false;
        });
      } else {
        setState(() => _isFetching = false);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Ошибка инициализации 2FA')),
        );
      }
    } catch (e) {
      setState(() => _isFetching = false);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ошибка подключения')),
      );
    }
  }

  Future<void> _confirm2fa() async {
    if (!(_formKey.currentState?.saveAndValidate() ?? false)) return;

    setState(() => _isConfirming = true);

    final code = _formKey.currentState!.value['code'];

    try {
      final headers = <String, String>{'Content-Type': 'application/json'};
      if (widget.enrollmentToken != null) {
        headers['Authorization'] = 'Bearer ${widget.enrollmentToken}';
      }
      final response = await http.post(
        Uri.parse(AppConfig.confirm2faUrl),
        headers: headers,
        body: json.encode({'code': code}),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (!mounted) return;
        Navigator.of(context).pop(data);
      } else {
        final error = ServerError.fromJson(response.body, response.statusCode);
        if (!mounted) return;
        FormErrorHandler.applyErrors(
          formKey: _formKey,
          error: error,
          context: context,
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ошибка подтверждения')),
      );
    } finally {
      if (mounted) setState(() => _isConfirming = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Защита аккаунта'),
      backgroundColor: AppColors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      content: SingleChildScrollView(
        child: _isFetching
            ? const Center(child: CircularProgressIndicator())
            : FormBuilder(
                key: _formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'Отсканируйте код в приложении (Google Authenticator / Aegis):',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey),
                    ),
                    const SizedBox(height: 16),
                    if (_otpUri != null)
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: QrImageView(
                          data: _otpUri!,
                          version: QrVersions.auto,
                          size: 180.0,
                        ),
                      ),
                    const SizedBox(height: 16),
                    Text(
                      'Секрет: $_secret',
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        color: Colors.grey,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 24),
                    FormBuilderTextField(
                      name: 'code',
                      keyboardType: TextInputType.number,
                      textAlign: TextAlign.center,
                      style: TextStyle(color: AppColors.text, fontSize: 18, letterSpacing: 8),
                      decoration: InputDecoration(
                        hintText: '000000',
                        hintStyle: TextStyle(color: Colors.grey.withOpacity(0.5), letterSpacing: 8),
                        filled: true,
                        fillColor: AppColors.input,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        errorStyle: const TextStyle(color: Colors.redAccent),
                      ),
                      validator: FormBuilderValidators.compose([
                        FormBuilderValidators.required(errorText: 'Введите код'),
                        FormBuilderValidators.numeric(errorText: 'Только цифры'),
                        FormBuilderValidators.minLength(6, errorText: '6 цифр'),
                        FormBuilderValidators.maxLength(6, errorText: '6 цифр'),
                      ]),
                    ),
                  ],
                ),
              ),
      ),
      actions: [
        if (!_isFetching)
          TextButton(
            onPressed: _isConfirming ? null : _confirm2fa,
            style: TextButton.styleFrom(
              foregroundColor: AppColors.button,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            ),
            child: _isConfirming
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('ПОДТВЕРДИТЬ', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
      ],
    );
  }
}
