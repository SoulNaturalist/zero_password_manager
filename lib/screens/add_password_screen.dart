import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../theme/colors.dart';
import '../widgets/themed_widgets.dart';
import '../config/app_config.dart';
import '../utils/api_service.dart';
import '../utils/password_history_service.dart';
import '../utils/folder_service.dart';

// ── icon/color helpers (shared with folders_screen) ─────────────────────────

Color _colorFromHex(String hex) {
  try {
    return Color(int.parse(hex.replaceFirst('#', '0xFF')));
  } catch (_) {
    return const Color(0xFF5D52D2);
  }
}

IconData _iconFromName(String name) {
  const map = {
    'folder': Icons.folder,
    'work': Icons.work,
    'home': Icons.home,
    'lock': Icons.lock,
    'star': Icons.star,
    'favorite': Icons.favorite,
    'shopping_cart': Icons.shopping_cart,
    'school': Icons.school,
    'code': Icons.code,
    'gaming': Icons.sports_esports,
    'bank': Icons.account_balance,
    'email': Icons.email,
    'cloud': Icons.cloud,
    'social': Icons.people,
    'crypto': Icons.currency_bitcoin,
    'vpn_key': Icons.vpn_key,
  };
  return map[name] ?? Icons.folder;
}

// ─────────────────────────────────────────────────────────────────────────────

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

  List<Map<String, dynamic>> _folders = [];
  int? _selectedFolderId;

  @override
  void initState() {
    super.initState();
    siteController.addListener(() => _loadFavicon(siteController.text));
    _loadFolders();
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

  Future<void> _loadFolders() async {
    final folders = await FolderService.getFolders();
    if (mounted) setState(() => _folders = folders);
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
        headers: {'Authorization': 'Bearer $token'},
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        setState(() => passwordController.text = data['password']);
      } else {
        setState(() => errorMessage = 'Ошибка генерации пароля');
      }
    } catch (e) {
      setState(() => errorMessage = 'Ошибка подключения к серверу');
    } finally {
      setState(() => isGeneratingPassword = false);
    }
  }

  Future<void> savePassword() async {
    final site = siteController.text.trim();
    final email = emailController.text.trim();
    final password = passwordController.text.trim();

    if (site.isEmpty || email.isEmpty || password.isEmpty) {
      setState(() => errorMessage = 'Все поля обязательны');
      return;
    }

    setState(() {
      isLoading = true;
      errorMessage = null;
    });

    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('token');

      String fullUrl = site;
      if (!site.startsWith('http://') && !site.startsWith('https://')) {
        fullUrl = 'https://$site';
      }

      final body = <String, dynamic>{
        'site_url': fullUrl,
        'site_login': email,
        'site_password': password,
        'has_2fa': has2FA,
        'has_seed_phrase': hasSeedPhrase,
        'seed_phrase': seedPhraseController.text.trim(),
        'notes': notesController.text.trim(),
      };
      if (_selectedFolderId != null) body['folder_id'] = _selectedFolderId;

      final response = await ApiService.post(
        AppConfig.passwordsUrl,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode(body),
      );

      if (response.statusCode == 201) {
        final data = jsonDecode(response.body);

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

        if (mounted) Navigator.pop(context, true);
      } else {
        final data = jsonDecode(response.body);
        setState(() => errorMessage = data['error'] ?? 'Ошибка при сохранении');
      }
    } catch (e) {
      setState(() => errorMessage = 'Ошибка подключения к серверу');
    } finally {
      setState(() => isLoading = false);
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

    setState(() => isLoadingFavicon = true);

    try {
      String domain = url.trim();
      if (domain.startsWith('http://')) domain = domain.substring(7);
      else if (domain.startsWith('https://')) domain = domain.substring(8);
      if (domain.contains('/')) domain = domain.split('/')[0];
      if (!domain.contains('.') && domain.isNotEmpty) domain = '$domain.com';
      if (url.toLowerCase().contains('metamask')) domain = 'metamask.io';

      setState(() {
        faviconUrl = 'https://www.google.com/s2/favicons?domain=$domain&sz=32';
        isLoadingFavicon = false;
      });
    } catch (_) {
      setState(() {
        faviconUrl = null;
        isLoadingFavicon = false;
      });
    }
  }

  void _showFolderPicker() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 12),
          Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: AppColors.text.withOpacity(0.2),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 16),
          NeonText(
            text: 'Выберите папку',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: AppColors.text,
            ),
          ),
          const SizedBox(height: 8),
          // "No folder" option
          ListTile(
            leading: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: AppColors.input,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(Icons.folder_off, color: AppColors.text.withOpacity(0.5), size: 20),
            ),
            title: Text('Без папки', style: TextStyle(color: AppColors.text)),
            trailing: _selectedFolderId == null
                ? Icon(Icons.check, color: AppColors.button)
                : null,
            onTap: () {
              setState(() => _selectedFolderId = null);
              Navigator.pop(ctx);
            },
          ),
          ..._folders.map((folder) {
            final color = _colorFromHex(folder['color'] as String? ?? '#5D52D2');
            final icon = _iconFromName(folder['icon'] as String? ?? 'folder');
            final isSelected = _selectedFolderId == folder['id'];
            return ListTile(
              leading: Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: color.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: color.withOpacity(0.4)),
                ),
                child: Icon(icon, color: color, size: 20),
              ),
              title: Text(folder['name'] as String? ?? '', style: TextStyle(color: AppColors.text)),
              trailing: isSelected ? Icon(Icons.check, color: AppColors.button) : null,
              onTap: () {
                setState(() => _selectedFolderId = folder['id'] as int?);
                Navigator.pop(ctx);
              },
            );
          }),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final selectedFolder = _selectedFolderId != null
        ? _folders.firstWhere(
            (f) => f['id'] == _selectedFolderId,
            orElse: () => <String, dynamic>{},
          )
        : null;

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
              ? BoxDecoration(color: Colors.black.withOpacity(0.1))
              : null,
          child: SingleChildScrollView(
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
                                    errorBuilder: (_, __, ___) => Container(
                                      width: 20,
                                      height: 20,
                                      decoration: BoxDecoration(
                                        color: Colors.grey.withOpacity(0.2),
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: const Icon(Icons.language, size: 12, color: Colors.grey),
                                    ),
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
                            child: CircularProgressIndicator(strokeWidth: 2),
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

                // ── Folder picker ──────────────────────────────────────────
                if (_folders.isNotEmpty) ...[
                  ThemedContainer(
                    child: InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: _showFolderPicker,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        child: Row(
                          children: [
                            if (selectedFolder != null &&
                                (selectedFolder as Map).isNotEmpty) ...[
                              Container(
                                width: 32,
                                height: 32,
                                decoration: BoxDecoration(
                                  color: _colorFromHex(selectedFolder['color'] as String? ?? '#5D52D2')
                                      .withOpacity(0.2),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Icon(
                                  _iconFromName(selectedFolder['icon'] as String? ?? 'folder'),
                                  color: _colorFromHex(
                                      selectedFolder['color'] as String? ?? '#5D52D2'),
                                  size: 18,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  selectedFolder['name'] as String? ?? '',
                                  style: TextStyle(color: AppColors.text, fontSize: 15),
                                ),
                              ),
                            ] else ...[
                              Icon(Icons.folder_open, color: AppColors.text.withOpacity(0.5), size: 22),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  'Выбрать папку (необязательно)',
                                  style: TextStyle(
                                    color: AppColors.text.withOpacity(0.6),
                                    fontSize: 15,
                                  ),
                                ),
                              ),
                            ],
                            Icon(
                              Icons.chevron_right,
                              color: AppColors.text.withOpacity(0.4),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],

                // ── Toggles ────────────────────────────────────────────────
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
                        onChanged: (value) => setState(() => has2FA = value),
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
                            if (!value) seedPhraseController.clear();
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
                    child: Text(errorMessage!, style: const TextStyle(color: Colors.red)),
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
