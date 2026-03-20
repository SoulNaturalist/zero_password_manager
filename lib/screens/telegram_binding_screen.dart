import 'package:flutter/material.dart';
import 'dart:convert';
import '../theme/colors.dart';
import '../widgets/themed_widgets.dart';
import '../config/app_config.dart';
import '../services/auth_token_storage.dart';
import '../utils/api_service.dart';
import '../widgets/otp_input_dialog.dart';
import '../l10n/l_text.dart';

class TelegramBindingScreen extends StatefulWidget {
  const TelegramBindingScreen({super.key});

  @override
  State<TelegramBindingScreen> createState() => _TelegramBindingScreenState();
}

class _TelegramBindingScreenState extends State<TelegramBindingScreen> {
  final TextEditingController _chatIdController = TextEditingController();
  bool _isLoading = false;
  String? _currentChatId;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    setState(() => _isLoading = true);
    try {
      final token = await AuthTokenStorage.readAccessToken();
      if (token == null || token.isEmpty) {
        setState(() => _errorMessage = 'Сессия истекла, войдите снова');
        return;
      }

      final response = await ApiService.get(
        AppConfig.profileUrl,
        headers: {'Authorization': 'Bearer $token'},
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        setState(() {
          _currentChatId = data['telegram_chat_id'];
          if (_currentChatId != null) {
            _chatIdController.text = _currentChatId!;
          }
        });
      }
    } catch (e) {
      setState(() => _errorMessage = 'Ошибка загрузки профиля');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _saveBinding() async {
    final chatId = _chatIdController.text.trim();
    if (chatId.isEmpty) {
      setState(() => _errorMessage = 'Введите Chat ID');
      return;
    }

    // Security: Mandatory TOTP for binding
    final String? otp = await showDialog<String>(
      context: context,
      builder: (context) => const OTPInputDialog(),
    );

    if (otp == null) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final token = await AuthTokenStorage.readAccessToken();
      if (token == null || token.isEmpty) {
        setState(() => _errorMessage = 'Сессия истекла, войдите снова');
        return;
      }

      final response = await ApiService.post(
        '${AppConfig.baseUrl}/profile/update',
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
          'X-OTP': otp,
        },
        body: jsonEncode({'telegram_chat_id': chatId, 'totp_code': otp}),
      );

      if (response.statusCode == 200) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: LText('Telegram успешно привязан')),
        );
        Navigator.pop(context);
      } else {
        final data = jsonDecode(response.body);
        setState(
          () =>
              _errorMessage =
                  data['error'] ?? data['detail'] ?? 'Ошибка привязки',
        );
      }
    } catch (e) {
      setState(() => _errorMessage = 'Ошибка подключения к серверу');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ThemedBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: NeonText(
            text: 'Привязка Telegram',
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          backgroundColor: AppColors.background.withOpacity(0.5),
          elevation: 0,
        ),
        body:
            _isLoading
                ? const Center(child: CircularProgressIndicator())
                : Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ThemedContainer(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          children: [
                            Icon(
                              Icons.notifications_active,
                              size: 48,
                              color: AppColors.button,
                            ),
                            const SizedBox(height: 16),
                            const LText(
                              'Получайте уведомления о безопасности!',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(height: 8),
                            LText(
                              'Мы будем присылать оповещения о входе, изменении паролей и попытках взлома в ваш Telegram.',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: Colors.grey[400]),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 32),
                      NeonText(
                        text: 'Ваш Telegram Chat ID',
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 12),
                      ThemedTextField(
                        controller: _chatIdController,
                        hintText: 'Например: 123456789',
                        keyboardType: TextInputType.number,
                        prefixIcon: const Icon(Icons.send, color: Colors.blue),
                      ),
                      const SizedBox(height: 12),
                      LText(
                        'Узнать свой ID можно через бота @userinfobot или аналогичные.',
                        style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                      ),
                      const Spacer(),
                      if (_errorMessage != null)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 16),
                          child: LText(
                            _errorMessage!,
                            style: const TextStyle(color: Colors.red),
                          ),
                        ),
                      ThemedElevatedButton(
                        onPressed: _isLoading ? null : _saveBinding,
                        minimumSize: const Size.fromHeight(56),
                        child: const LText('Привязать Telegram'),
                      ),
                    ],
                  ),
                ),
      ),
    );
  }
}
