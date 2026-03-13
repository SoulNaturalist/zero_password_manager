import 'package:flutter/material.dart';
import '../theme/colors.dart';
import '../utils/api_service.dart';
import '../config/app_config.dart';

class TotpConfirmScreen extends StatefulWidget {
  const TotpConfirmScreen({super.key});

  @override
  State<TotpConfirmScreen> createState() => _TotpConfirmScreenState();
}

class _TotpConfirmScreenState extends State<TotpConfirmScreen> {
  final _totpController = TextEditingController();
  bool _isLoading = false;
  String? _newUrl;
  String? _challengeId;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final args =
        ModalRoute.of(context)?.settings.arguments as Map<String, dynamic>?;
    if (args != null) {
      _newUrl = args['new_url'];
      _challengeId = args['challenge_id'];
    }
  }

  Future<void> _confirm() async {
    final totp = _totpController.text.trim();
    if (totp.isEmpty) return;

    setState(() => _isLoading = true);

    try {
      final response = await ApiService.post(
        '${AppConfig.baseUrl}/device/confirm-backend-change',
        body: {'challenge_id': _challengeId, 'totp': totp},
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        await AppConfig.setApiBaseUrl(_newUrl!);
        // Restart app flow
        if (mounted) {
          Navigator.pushNamedAndRemoveUntil(context, '/', (route) => false);
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('Ошибка подтверждения')));
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Ошибка: $e')));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Подтверждение смены сервера'),
        backgroundColor: AppColors.surface,
      ),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.security, size: 64, color: AppColors.button),
            const SizedBox(height: 24),
            Text(
              'Сервер запрашивает переезд на:\n${_newUrl ?? "..."}',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppColors.text,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 24),
            TextField(
              controller: _totpController,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: 'Введите 2FA код',
                fillColor: AppColors.surface,
                filled: true,
              ),
              style: TextStyle(color: AppColors.text),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _isLoading ? null : _confirm,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.button,
              ),
              child:
                  _isLoading
                      ? const CircularProgressIndicator()
                      : const Text('Подтвердить'),
            ),
          ],
        ),
      ),
    );
  }
}
