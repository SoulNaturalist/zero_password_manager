import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:async';
import 'package:shared_preferences/shared_preferences.dart';
import '../theme/colors.dart';
import '../widgets/themed_widgets.dart';
import '../config/app_config.dart';
import '../utils/api_service.dart';
import '../utils/memory_security.dart';
import '../utils/password_history_service.dart';
import '../utils/folder_service.dart';
import '../services/auth_token_storage.dart';
import '../services/vault_service.dart';

// ── helpers (same as add_password_screen) ────────────────────────────────────

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

class EditPasswordScreen extends StatefulWidget {
  final Map<String, dynamic> password;

  const EditPasswordScreen({super.key, required this.password});

  @override
  State<EditPasswordScreen> createState() => _EditPasswordScreenState();
}

class _EditPasswordScreenState extends State<EditPasswordScreen> {
  final TextEditingController siteController = TextEditingController();
  final TextEditingController emailController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();
  final TextEditingController notesController = TextEditingController();
  final TextEditingController seedPhraseController = TextEditingController();

  bool isLoading = false;
  bool isGeneratingPassword = false;
  bool _isDecryptingPassword = false;
  bool _passwordDecrypted = false;
  bool has2FA = false;
  bool hasSeedPhrase = false;
  String? errorMessage;
  String? faviconUrl;
  bool isLoadingFavicon = false;
  bool _obscurePassword = true;

  List<Map<String, dynamic>> _folders = [];
  int? _selectedFolderId;

  @override
  void initState() {
    super.initState();
    siteController.text  = widget.password['site_url']  ?? widget.password['title']    ?? '';
    emailController.text = widget.password['subtitle']  ?? widget.password['site_login'] ?? '';

    // Do NOT decrypt password here — decrypt lazily when user taps the field
    has2FA      = widget.password['has_2fa']        as bool? ?? false;
    hasSeedPhrase = widget.password['has_seed_phrase'] as bool? ?? false;
    _selectedFolderId = widget.password['folder_id']  as int?;

    if (siteController.text.isNotEmpty) _loadFavicon(siteController.text);
    siteController.addListener(() => _loadFavicon(siteController.text));
    _loadFolders();
  }

  /// Lazily decrypt the password field only when the user taps it.
  /// Keeps plaintext out of memory until actually needed for editing.
  Future<void> _loadDecryptedPassword() async {
    if (_passwordDecrypted) return;
    setState(() => _isDecryptingPassword = true);

    try {
      final encPayload = widget.password['encrypted_payload'] as String?;
      final encNotes   = widget.password['notes_encrypted']   as String?;
      final encMeta    = widget.password['encrypted_metadata'] as String?;

      if (encPayload != null) {
        passwordController.text = await VaultService().decryptPayload(encPayload);
      }
      if (encNotes != null) {
        notesController.text = await VaultService().decryptPayload(encNotes);
      }
      final decryptedSeed =
          await VaultService().decryptSeedPhraseFromMetadata(encMeta);
      if (decryptedSeed != null) {
        seedPhraseController.text = decryptedSeed;
        unawaited(nativeWipe(decryptedSeed));
      }
      if (mounted) setState(() => _passwordDecrypted = true);
    } catch (e) {
      if (mounted) setState(() => errorMessage = 'Ошибка дешифрования: $e');
    } finally {
      if (mounted) setState(() => _isDecryptingPassword = false);
    }
  }

  @override
  void dispose() {
    // Best-effort wipe of sensitive controllers before releasing
    unawaited(wipeController(passwordController));
    unawaited(wipeController(seedPhraseController));
    unawaited(wipeController(notesController));
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

  /// Generates a cryptographically secure password using [Random.secure()].
  Future<void> generatePassword() async {
    setState(() { isGeneratingPassword = true; errorMessage = null; });

    try {
      // Ensure password field is decrypted before overwriting
      if (!_passwordDecrypted) await _loadDecryptedPassword();
      final password = generateSecurePassword(length: 24);
      setState(() {
        passwordController.text = password;
        _obscurePassword = false;
      });
    } catch (e) {
      setState(() => errorMessage = 'Ошибка генерации пароля');
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
      final siteId = widget.password['id'];
      if (siteId == null) throw Exception("Missing password ID");


      await VaultService().updatePassword(
        id: siteId,
        name: site,
        url: site,
        login: email,
        password: password,
        notes:
            notesController.text.trim().isNotEmpty
                ? notesController.text.trim()
                : null,
        seedPhrase:
            hasSeedPhrase && seedPhraseController.text.trim().isNotEmpty
                ? seedPhraseController.text.trim()
                : null,
      );
      // Folder assignment is local-only — save after successful server update.
      if (siteId is int) {
        await FolderService.setFolderForPassword(siteId, _selectedFolderId);
      }

      await PasswordHistoryService.addPasswordHistory(
        passwordId: siteId,
        actionType: 'UPDATE',
        actionDetails: {
          'previous': {
            'site_url': widget.password['title'] ?? '',
            'site_login': widget.password['subtitle'] ?? '',
            'has_2fa': widget.password['has_2fa'] ?? false,
          },
          'new': {
            'site_url': site,
            'site_login': email,
            'has_2fa': has2FA,
          },
        },
        siteUrl: site,
      );

      if (mounted) {
        Navigator.pop(context, true);
      }
    } catch (e) {
      setState(() => errorMessage = 'Ошибка при сохранении: ${e.toString()}');
    } finally {
      setState(() => isLoading = false);
    }
  }

  Future<void> deletePassword() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder:
          (context) => AlertDialog(
            backgroundColor: AppColors.surface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            title: NeonText(
              text: 'Подтверждение удаления',
              style: TextStyle(
                color: AppColors.text,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            content: Text(
              'Вы уверены, что хотите удалить этот пароль?',
              style: TextStyle(color: AppColors.text.withOpacity(0.8)),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text(
                  'Отмена',
                  style: TextStyle(color: AppColors.text.withOpacity(0.6)),
                ),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: Text(
                  'Удалить',
                  style: TextStyle(color: AppColors.error),
                ),
              ),
            ],
          ),
    );

    if (confirmed != true) return;

    setState(() {
      isLoading = true;
      errorMessage = null;
    });

    try {
      final token = await AuthTokenStorage.readAccessToken();
      if (token == null || token.isEmpty) {
        throw Exception('Missing access token');
      }

      final passwordId = widget.password['id'];

      // Log history BEFORE deleting — once the password is deleted the server
      // cannot satisfy the FK constraint if we send the old password_id.
      // Sending passwordId: null keeps the history record valid regardless.
      await PasswordHistoryService.addPasswordHistory(
        passwordId: null,
        actionType: 'DELETE',
        actionDetails: {
          'deleted_password': {
            'site_url': widget.password['title'] ?? '',
            'site_login': widget.password['subtitle'] ?? '',
            'has_2fa': widget.password['has_2fa'] ?? false,
            'has_seed_phrase': widget.password['has_seed_phrase'] ?? false,
          },
        },
        siteUrl: widget.password['title'] ?? '',
      );

      http.Response response;

      if (passwordId != null) {
        response = await ApiService.delete(
          '${AppConfig.passwordsUrl}/$passwordId',
          headers: {'Authorization': 'Bearer $token'},
        );
      } else {
        response = await http.delete(
          Uri.parse(AppConfig.getPasswordUrl(widget.password['title'] ?? '')),
          headers: {'Authorization': 'Bearer $token'},
        );
      }

      if (response.statusCode == 204 || response.statusCode == 200) {
        if (mounted) Navigator.pop(context, true);
      } else {
        final data = jsonDecode(response.body);
        setState(
          () =>
              errorMessage =
                  data['error'] ?? data['detail'] ?? 'Ошибка при удалении',
        );
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
      if (domain.startsWith('http://'))
        domain = domain.substring(7);
      else if (domain.startsWith('https://'))
        domain = domain.substring(8);
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
      builder:
          (ctx) => Column(
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
              ListTile(
                leading: Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: AppColors.input,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    Icons.folder_off,
                    color: AppColors.text.withOpacity(0.5),
                    size: 20,
                  ),
                ),
                title: Text(
                  'Без папки',
                  style: TextStyle(color: AppColors.text),
                ),
                trailing:
                    _selectedFolderId == null
                        ? Icon(Icons.check, color: AppColors.button)
                        : null,
                onTap: () {
                  setState(() => _selectedFolderId = null);
                  Navigator.pop(ctx);
                },
              ),
              ..._folders.map((folder) {
                final color = _colorFromHex(
                  folder['color'] as String? ?? '#5D52D2',
                );
                final icon = _iconFromName(
                  folder['icon'] as String? ?? 'folder',
                );
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
                  title: Text(
                    folder['name'] as String? ?? '',
                    style: TextStyle(color: AppColors.text),
                  ),
                  trailing:
                      isSelected
                          ? Icon(Icons.check, color: AppColors.button)
                          : null,
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
    final selectedFolder =
        _selectedFolderId != null
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
            text: 'Редактирование пароля',
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          backgroundColor:
              ThemeManager.currentTheme == AppTheme.dark
                  ? AppColors.background
                  : Colors.black.withOpacity(0.3),
          elevation: 0,
          actions: [
            IconButton(
              icon: Icon(Icons.delete, color: AppColors.error),
              onPressed: isLoading ? null : deletePassword,
            ),
          ],
        ),
        body: Container(
          decoration:
              ThemeManager.currentTheme != AppTheme.dark
                  ? BoxDecoration(color: Colors.black.withOpacity(0.1))
                  : null,
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20.0),
            child: Column(
              children: [
                // Site field with favicon
                ThemedTextField(
                  controller: siteController,
                  hintText: 'Сайт',
                  prefixIcon:
                      faviconUrl != null
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
                              child:
                                  isLoadingFavicon
                                      ? const SizedBox(
                                        width: 20,
                                        height: 20,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          valueColor:
                                              AlwaysStoppedAnimation<Color>(
                                                Colors.grey,
                                              ),
                                        ),
                                      )
                                      : Image.network(
                                        faviconUrl!,
                                        width: 20,
                                        height: 20,
                                        fit: BoxFit.cover,
                                        errorBuilder:
                                            (_, __, ___) => Container(
                                              width: 20,
                                              height: 20,
                                              decoration: BoxDecoration(
                                                color: Colors.grey.withOpacity(
                                                  0.2,
                                                ),
                                                borderRadius:
                                                    BorderRadius.circular(4),
                                              ),
                                              child: const Icon(
                                                Icons.language,
                                                size: 12,
                                                color: Colors.grey,
                                              ),
                                            ),
                                      ),
                            ),
                          )
                          : const Icon(Icons.language, color: Colors.grey),
                ),
                const SizedBox(height: 16),
                ThemedTextField(controller: emailController, hintText: 'Логин'),
                const SizedBox(height: 16),
                GestureDetector(
                  onTap: _passwordDecrypted ? null : _loadDecryptedPassword,
                  child: AbsorbPointer(
                    absorbing: !_passwordDecrypted,
                    child: ThemedTextField(
                      controller: passwordController,
                      hintText: _isDecryptingPassword ? 'Дешифровка...' : 'Пароль',
                      obscureText: _obscurePassword,
                      suffixIcon: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (_isDecryptingPassword)
                            const Padding(
                              padding: EdgeInsets.only(right: 8),
                              child: SizedBox(width: 18, height: 18,
                                  child: CircularProgressIndicator(strokeWidth: 2)),
                            )
                          else
                            IconButton(
                              icon: Icon(
                                _obscurePassword ? Icons.visibility_off : Icons.visibility,
                                color: AppColors.text.withOpacity(0.5),
                              ),
                              onPressed: _passwordDecrypted
                                  ? () => setState(() => _obscurePassword = !_obscurePassword)
                                  : null,
                            ),
                          IconButton(
                            icon: isGeneratingPassword
                                ? const SizedBox(
                                    width: 20, height: 20,
                                    child: CircularProgressIndicator(strokeWidth: 2))
                                : const Icon(Icons.refresh),
                            onPressed: isGeneratingPassword ? null : generatePassword,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                ThemedTextField(
                  controller: seedPhraseController,
                  hintText: 'Seed фраза (необязательно)',
                  enabled: hasSeedPhrase,
                  maxLines: 3,
                ),
                const SizedBox(height: 16),
                ThemedTextField(
                  controller: notesController,
                  hintText: 'Заметки (необязательно)',
                  maxLines: 3,
                ),
                const SizedBox(height: 16),

                // ── Folder picker ──────────────────────────────────────────
                if (_folders.isNotEmpty) ...[
                  ThemedContainer(
                    child: InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: _showFolderPicker,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        child: Row(
                          children: [
                            if (selectedFolder != null &&
                                (selectedFolder as Map).isNotEmpty) ...[
                              Container(
                                width: 32,
                                height: 32,
                                decoration: BoxDecoration(
                                  color: _colorFromHex(
                                    selectedFolder['color'] as String? ??
                                        '#5D52D2',
                                  ).withOpacity(0.2),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Icon(
                                  _iconFromName(
                                    selectedFolder['icon'] as String? ??
                                        'folder',
                                  ),
                                  color: _colorFromHex(
                                    selectedFolder['color'] as String? ??
                                        '#5D52D2',
                                  ),
                                  size: 18,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  selectedFolder['name'] as String? ?? '',
                                  style: TextStyle(
                                    color: AppColors.text,
                                    fontSize: 15,
                                  ),
                                ),
                              ),
                            ] else ...[
                              Icon(
                                Icons.folder_open,
                                color: AppColors.text.withOpacity(0.5),
                                size: 22,
                              ),
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
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
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
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
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
                SizedBox(height: MediaQuery.of(context).padding.bottom + 32),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
