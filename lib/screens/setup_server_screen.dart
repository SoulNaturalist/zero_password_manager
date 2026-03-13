import 'package:flutter/material.dart';
import '../config/app_config.dart';
import '../theme/colors.dart';

class SetupServerScreen extends StatefulWidget {
  const SetupServerScreen({super.key});

  @override
  State<SetupServerScreen> createState() => _SetupServerScreenState();
}

class _SetupServerScreenState extends State<SetupServerScreen> {
  final _urlController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _isLoading = false;

  void _saveUrl() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    String url = _urlController.text.trim();
    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      url = 'https://$url';
    }

    await AppConfig.setApiBaseUrl(url);

    if (mounted) {
      Navigator.pushReplacementNamed(context, '/');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Настройка сервера'),
        backgroundColor: AppColors.surface,
        elevation: 0,
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Icon(
                  Icons.dns_outlined,
                  size: 80,
                  color: AppColors.button,
                ),
                const SizedBox(height: 24),
                Text(
                  'Добро пожаловать!',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: AppColors.text,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                const Text(
                  'Пожалуйста, укажите URL вашего сервера Zero Vault. '
                  'Это может быть как доменное имя (например, https://api.vault.com), так и локальный IP.',
                  style: TextStyle(
                    fontSize: 16,
                    color: Colors.grey,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 32),
                TextFormField(
                  controller: _urlController,
                  style: TextStyle(color: AppColors.text),
                  decoration: InputDecoration(
                    labelText: 'URL сервера',
                    labelStyle: const TextStyle(color: Colors.grey),
                    hintText: 'https://...',
                    hintStyle: TextStyle(color: Colors.grey.withOpacity(0.5)),
                    filled: true,
                    fillColor: AppColors.surface,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: AppColors.button),
                    ),
                  ),
                  keyboardType: TextInputType.url,
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Введите URL сервера';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: _isLoading ? null : _saveUrl,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.button,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child:
                      _isLoading
                          ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(
                                Colors.white,
                              ),
                            ),
                          )
                          : const Text(
                            'Продолжить',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
