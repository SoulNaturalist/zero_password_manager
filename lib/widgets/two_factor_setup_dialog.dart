import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:qr_flutter/qr_flutter.dart';
import '../config/app_config.dart';
import '../theme/colors.dart';

class TwoFactorSetupDialog extends StatefulWidget {
  final int userId;
  final String login;

  const TwoFactorSetupDialog({
    super.key,
    required this.userId,
    required this.login,
  });

  @override
  State<TwoFactorSetupDialog> createState() => _TwoFactorSetupDialogState();
}

class _TwoFactorSetupDialogState extends State<TwoFactorSetupDialog> {
  String? _secret;
  String? _otpUri;
  final TextEditingController _codeController = TextEditingController();
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _fetchSetupData();
  }

  Future<void> _fetchSetupData() async {
    try {
      final response = await http.post(
        Uri.parse(AppConfig.setup2faUrl),
        headers: {
          'Content-Type': 'application/json',
          // В продакшене тут нужен временный токен регистрации или JWT
          // Но для упрощения (как просил юзер) просто привязываем по ID или логину
        },
        body: json.encode({'user_id': widget.userId}),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        setState(() {
          _secret = data['secret'];
          _otpUri = data['otp_uri'];
          _isLoading = false;
        });
      } else {
        setState(() {
          _errorMessage = 'Ошибка загрузки данных 2FA';
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

  Future<void> _confirm2fa() async {
    final code = _codeController.text.trim();
    if (code.length != 6) {
      setState(() => _errorMessage = 'Введите 6-значный код');
      return;
    }

    setState(() => _isLoading = true);

    try {
      final response = await http.post(
        Uri.parse(AppConfig.confirm2faUrl),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'user_id': widget.userId,
          'code': code,
        }),
      );

      if (response.statusCode == 200) {
        Navigator.of(context).pop(true); // Успех
      } else {
        final data = json.decode(response.body);
        setState(() {
          _errorMessage = data['detail'] ?? 'Неверный код';
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

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Настройка 2FA'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_isLoading)
              const CircularProgressIndicator()
            else if (_errorMessage != null)
              Text(_errorMessage!, style: const TextStyle(color: Colors.red))
            else ...[
              const Text('Отсканируйте QR-код в Google Authenticator или Aegis:'),
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
                    size: 200.0,
                  ),
                ),
              const SizedBox(height: 16),
              Text('Секрет: $_secret', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
              const SizedBox(height: 16),
              TextField(
                controller: _codeController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  hintText: 'Введите 6-значный код',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        if (!_isLoading)
          ElevatedButton(
            onPressed: _confirm2fa,
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.button),
            child: const Text('Подтвердить'),
          ),
      ],
    );
  }
}
