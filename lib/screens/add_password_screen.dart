import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../theme/colors.dart';
import '../widgets/themed_widgets.dart';
import '../config/app_config.dart';
import '../utils/api_service.dart';
import '../utils/password_history_service.dart';

class AddPasswordScreen extends StatefulWidget {
  const AddPasswordScreen({super.key});

  @override
  State<AddPasswordScreen> createState() => _AddPasswordScreenState();
}

class _AddPasswordScreenState extends State<AddPasswordScreen> {
  final TextEditingController siteController = TextEditingController();
  final TextEditingController emailController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();
  final TextEditingController notesController = TextEditingController();
  final TextEditingController seedPhraseController = TextEditingController();

  bool isLoading = false;
  bool isGeneratingPassword = false;
  bool has2FA = false;
  bool hasSeedPhrase = false;
  String? errorMessage;
  String? faviconUrl;
  bool isLoadingFavicon = false;

  @override
  void initState() {
    super.initState();
    siteController.addListener(() {
      _loadFavicon(siteController.text);
    });
  }

  @override
  void dispose() {
    siteController.dispose();
    emailController.dispose();
    passwordController.dispose();
    notesController.dispose();
    seedPhraseController.dispose();
    super.dispose();
  }

  Future<void> generatePassword() async {
    setState(() {
      isGeneratingPassword = true;
      errorMessage = null;
    });

    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('token');

      final response = await ApiService.get(
        AppConfig.generatePasswordUrl,
        headers: {
          'Authorization': 'Bearer $token',
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        setState(() {
          passwordController.text = data['password'];
        });
      } else {
        setState(() {
          errorMessage = 'Ошибка генерации пароля';
        });
      }
    } catch (e) {
      setState(() {
        errorMessage = 'Ошибка подключения к серверу';
      });
    } finally {
      setState(() {
        isGeneratingPassword = false;
      });
    }
  }

  Future<void> savePassword() async {
    final site = siteController.text.trim();
    final email = emailController.text.trim();
    final password = passwordController.text.trim();

    if (site.isEmpty || email.isEmpty || password.isEmpty) {
      setState(() {
        errorMessage = 'Все поля обязательны';
      });
      return;
    }

    setState(() {
      isLoading = true;
      errorMessage = null;
    });

    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('token');

      // Добавляем протокол, если его нет
      String fullUrl = site;
      if (!site.startsWith('http://') && !site.startsWith('https://')) {
        fullUrl = 'https://$site';
      }

      final response = await ApiService.post(
        AppConfig.passwordsUrl,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({
          'site_url': fullUrl,
          'site_login': email,
          'site_password': password,
          'has_2fa': has2FA,
          'has_seed_phrase': hasSeedPhrase,
          'seed_phrase': seedPhraseController.text.trim(),
          'notes': notesController.text.trim(),
        }),
      );

      if (response.statusCode == 201) {
        final data = jsonDecode(response.body);
        print('DEBUG: Пароль сохранен, ответ сервера: $data');
        
        // Добавляем запись в историю паролей
        await PasswordHistoryService.addPasswordHistory(
          passwordId: data['id'],
          actionType: 'CREATE',
          actionDetails: {
            'created_password': {
              'site_url': fullUrl,
              'site_login': email,
              'has_2fa': has2FA,
              'has_seed_phrase': hasSeedPhrase,
            },
          },
          siteUrl: fullUrl,
        );
        
        if (mounted) {
          Navigator.pop(context, true);
        }
      } else {
        final data = jsonDecode(response.body);
        setState(() {
          errorMessage = data['error'] ?? 'Ошибка при сохранении';
        });
      }
    } catch (e) {
      setState(() {
        errorMessage = 'Ошибка подключения к серверу';
      });
    } finally {
      setState(() {
        isLoading = false;
      });
    }
  }

  Future<void> _loadFavicon(String url) async {
    if (url.isEmpty) {
      setState(() {
        faviconUrl = null;
        isLoadingFavicon = false;
      });
      return;
    }

    setState(() {
      isLoadingFavicon = true;
    });

    try {
      String domain = url.trim();
      
      // Убираем протокол если есть
      if (domain.startsWith('http://')) {
        domain = domain.substring(7);
      } else if (domain.startsWith('https://')) {
        domain = domain.substring(8);
      }
      
      // Убираем путь если есть (оставляем только домен)
      if (domain.contains('/')) {
        domain = domain.split('/')[0];
      }
      
      // Если домен не содержит точку, добавляем .com (для случаев типа "github")
      if (!domain.contains('.') && domain.isNotEmpty) {
        domain = '$domain.com';
      }
      
      // Специальная обработка для MetaMask
      if (url.toLowerCase().contains('metamask')) {
        domain = 'metamask.io';
      }

      setState(() {
        faviconUrl = 'https://www.google.com/s2/favicons?domain=$domain&sz=32';
        isLoadingFavicon = false;
      });
    } catch (e) {
      setState(() {
        faviconUrl = null;
        isLoadingFavicon = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return ThemedBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: NeonText(
            text: 'Добавление пароля',
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          backgroundColor: ThemeManager.currentTheme == AppTheme.dark 
              ? AppColors.background 
              : Colors.black.withOpacity(0.3),
          elevation: 0,
        ),
        body: Container(
          decoration: ThemeManager.currentTheme != AppTheme.dark
              ? BoxDecoration(
                  color: Colors.black.withOpacity(0.1),
                )
              : null,
          child: Padding(
            padding: const EdgeInsets.all(20.0),
            child: Column(
              children: [
                ThemedTextField(
                  controller: siteController,
                  hintText: 'Сайт',
                  prefixIcon: faviconUrl != null
                      ? Container(
                          margin: const EdgeInsets.all(8.0),
                          width: 20,
                          height: 20,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(4),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.1),
                                blurRadius: 2,
                                offset: const Offset(0, 1),
                              ),
                            ],
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: isLoadingFavicon
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      valueColor: AlwaysStoppedAnimation<Color>(Colors.grey),
                                    ),
                                  )
                                : Image.network(
                                    faviconUrl!,
                                    width: 20,
                                    height: 20,
                                    fit: BoxFit.cover,
                                    errorBuilder: (context, error, stackTrace) {
                                      return Container(
                                        width: 20,
                                        height: 20,
                                        decoration: BoxDecoration(
                                          color: Colors.grey.withOpacity(0.2),
                                          borderRadius: BorderRadius.circular(4),
                                        ),
                                        child: const Icon(
                                          Icons.language,
                                          size: 12,
                                          color: Colors.grey,
                                        ),
                                      );
                                    },
                                  ),
                          ),
                        )
                      : const Icon(Icons.language, color: Colors.grey),
                ),
                const SizedBox(height: 16),
                ThemedTextField(
                  controller: emailController,
                  hintText: 'Логин',
                ),
                const SizedBox(height: 16),
                ThemedTextField(
                  controller: passwordController,
                  hintText: 'Пароль',
                  obscureText: true,
                  suffixIcon: IconButton(
                    icon: isGeneratingPassword
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                            ),
                          )
                        : const Icon(Icons.refresh),
                    onPressed: isGeneratingPassword ? null : generatePassword,
                  ),
                ),
                const SizedBox(height: 16),
                ThemedTextField(
                  controller: notesController,
                  hintText: 'Заметки (необязательно)',
                  maxLines: 3,
                ),
                const SizedBox(height: 16),
                ThemedTextField(
                  controller: seedPhraseController,
                  hintText: 'Seed фраза (необязательно)',
                  enabled: hasSeedPhrase,
                ),
                const SizedBox(height: 16),
                ThemedContainer(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      NeonText(
                        text: 'Двухфакторная аутентификация',
                        style: TextStyle(color: AppColors.text),
                      ),
                      Switch(
                        value: has2FA,
                        onChanged: (value) {
                          setState(() {
                            has2FA = value;
                          });
                        },
                        activeColor: AppColors.button,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                ThemedContainer(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      NeonText(
                        text: 'Seed фраза',
                        style: TextStyle(color: AppColors.text),
                      ),
                      Switch(
                        value: hasSeedPhrase,
                        onChanged: (value) {
                          setState(() {
                            hasSeedPhrase = value;
                            if (!value) {
                              seedPhraseController.clear();
                            }
                          });
                        },
                        activeColor: AppColors.button,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                if (errorMessage != null)
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.red.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.red.withOpacity(0.3)),
                    ),
                    child: Text(
                      errorMessage!,
                      style: const TextStyle(color: Colors.red),
                    ),
                  ),
                const SizedBox(height: 16),
                isLoading
                    ? CircularProgressIndicator(color: AppColors.button)
                    : ThemedElevatedButton(
                        onPressed: savePassword,
                        minimumSize: const Size.fromHeight(50),
                        child: const Text('Сохранить'),
                      ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

