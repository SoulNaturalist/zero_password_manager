import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:typed_data';
import 'package:bip39/bip39.dart' as bip39;
import '../theme/colors.dart';
import '../config/app_config.dart';
import '../utils/biometric_service.dart';
import '../utils/passkey_service.dart';
import '../utils/pin_security.dart';
import 'package:nk3_zero/utils/api_service.dart';
import 'dart:io';
import 'package:device_info_plus/device_info_plus.dart';
import '../services/auth_token_storage.dart';
import '../services/vault_service.dart';
import 'package:file_picker/file_picker.dart';
import 'package:csv/csv.dart';
import 'package:flutter/services.dart';
import '../utils/hidden_folder_service.dart';
import '../utils/memory_security.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _hasPinCode = false;
  bool _isLoading = true;
  bool _hideSeedPhrases = false;
  bool _biometricEnabled = false;
  bool _biometricAvailable = false;
  String _biometricType = 'Биометрическая аутентификация';
  AppTheme _currentTheme = AppTheme.dark;
  final PasskeyService _passkeyService = PasskeyService();
  List<dynamic> _devices = [];
  bool _isPasskeyLoading = false;
  String? _telegramChatId;
  String? _userLogin;
  int _passwordCount = 0;
  bool _isProfileLoading = false;
  bool _hasSeedPhrase = false;
  bool _showHiddenFolders = false;

  @override
  void initState() {
    super.initState();
    _checkPinCodeStatus();
    _loadSeedPhraseSettings();
    _loadBiometricSettings();
    _loadThemeSettings();
    _loadProfile();
    _showHiddenFolders = HiddenFolderService.instance.isUnlocked;
  }

  Future<void> _loadDevices() async {
    // Empty definition to fix missing method error
    // Can be populated later inside a proper device management system
    setState(() {
      _devices = [];
    });
  }

  Future<void> _checkPinCodeStatus() async {
    try {
      final hasPinHash = await PinSecurity.hasPinHash();
      setState(() {
        _hasPinCode = hasPinHash;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _toggleHiddenFolders(bool value) async {
    if (!value) {
      HiddenFolderService.instance.lock();
      setState(() => _showHiddenFolders = false);
      return;
    }

    // Request TOTP before revealing hidden folders
    final controller = TextEditingController();
    final verified = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColors.button.withOpacity(0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(Icons.shield_outlined, color: AppColors.button, size: 22),
            ),
            const SizedBox(width: 12),
            Text(
              'Скрытые папки',
              style: TextStyle(color: AppColors.text, fontSize: 17, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Введите TOTP-код для отображения скрытых папок',
              style: TextStyle(color: AppColors.text.withOpacity(0.7), fontSize: 13),
            ),
            const SizedBox(height: 20),
            StatefulBuilder(
              builder: (ctx2, setField) => TextField(
                controller: controller,
                keyboardType: TextInputType.number,
                autofocus: true,
                maxLength: 6,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AppColors.text,
                  fontSize: 28,
                  letterSpacing: 12,
                  fontWeight: FontWeight.bold,
                ),
                decoration: InputDecoration(
                  counterText: '',
                  hintText: '000000',
                  hintStyle: TextStyle(color: AppColors.text.withOpacity(0.3), letterSpacing: 12),
                  filled: true,
                  fillColor: AppColors.input,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide.none,
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(color: AppColors.button, width: 2),
                  ),
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Отмена', style: TextStyle(color: AppColors.text.withOpacity(0.6))),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.button,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () async {
              final ok = await HiddenFolderService.instance.verifyTotp(controller.text.trim());
              if (ctx.mounted) Navigator.pop(ctx, ok);
            },
            child: const Text('Подтвердить'),
          ),
        ],
      ),
    );

    if (verified == true) {
      setState(() => _showHiddenFolders = true);
    } else if (mounted && verified == false) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppColors.error,
          content: const Row(
            children: [
              Icon(Icons.error_outline, color: Colors.white),
              SizedBox(width: 8),
              Text('Неверный TOTP-код', style: TextStyle(color: Colors.white)),
            ],
          ),
        ),
      );
    }
  }

  Future<void> _loadSeedPhraseSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final hideSeedPhrases = prefs.getBool('hide_seed_phrases') ?? false;

      setState(() {
        _hideSeedPhrases = hideSeedPhrases;
      });
    } catch (e) {
      // Игнорируем ошибки при загрузке настроек
    }
  }

  Future<void> _changePinCode() async {
    final result = await Navigator.pushNamed(context, '/setup-pin');
    if (result == true) {
      _checkPinCodeStatus();
    }
  }

  Future<void> _removePinCode() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder:
          (context) => AlertDialog(
            backgroundColor: AppColors.input,
            title: Text(
              'Удалить PIN-код?',
              style: TextStyle(color: AppColors.text),
            ),
            content: const Text(
              'Вы уверены, что хотите удалить PIN-код? После этого для входа в приложение потребуется вводить логин и пароль.',
              style: TextStyle(color: Colors.grey),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Отмена'),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(true),
                style: TextButton.styleFrom(foregroundColor: Colors.red),
                child: const Text('Удалить'),
              ),
            ],
          ),
    );

    if (confirmed == true) {
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove('pin_code');
        await prefs.remove('pin_hash');

        // Clear PIN hash and attempt data from FlutterSecureStorage
        await PinSecurity.clearPinData();
        // Also clear persistent key since PIN is gone
        await VaultService().clearAllData();

        setState(() {
          _hasPinCode = false;
        });

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              backgroundColor: Colors.green,
              content: Text('PIN-код удален'),
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              backgroundColor: Colors.red,
              content: Text('Ошибка при удалении PIN-кода'),
            ),
          );
        }
      }
    }
  }

  Future<void> _importPasswordsFromFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['csv'],
        withData: true,
      );

      if (result == null || result.files.isEmpty) return;

      setState(() => _isLoading = true);

      final file = result.files.single;
      late String csvString;

      if (file.bytes != null) {
        csvString = utf8.decode(file.bytes!);
      } else if (file.path != null) {
        csvString = await File(file.path!).readAsString();
      } else {
        throw Exception("Cannot read file content");
      }

      final List<List<dynamic>> rows =
          const CsvToListConverter().convert(csvString);
      if (rows.isEmpty) throw Exception("CSV file is empty");

      // Identify headers
      final headers = rows[0].map((h) => h.toString().toLowerCase()).toList();
      final urlIndex = headers.indexOf('url');
      final userIndex = headers.indexOf('username');
      final passIndex = headers.indexOf('password');

      if (urlIndex == -1 || userIndex == -1 || passIndex == -1) {
        throw Exception(
          "Invalid CSV structure. Required headers: url, username, password",
        );
      }

      final List<Map<String, String>> entries = [];
      // Skip header row
      for (var i = 1; i < rows.length; i++) {
        final row = rows[i];
        if (row.length <= urlIndex ||
            row.length <= userIndex ||
            row.length <= passIndex)
          continue;

        entries.add({
          'url': row[urlIndex].toString(),
          'username': row[userIndex].toString(),
          'password': row[passIndex].toString(),
        });
      }

      if (entries.isEmpty) throw Exception("No valid entries found in CSV");

      await VaultService().importPasswordsBatch(entries);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Colors.green,
            content: Text('Успешно импортировано ${entries.length} паролей'),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Colors.red,
            content: Text('Ошибка импорта: ${e.toString()}'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _logout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder:
          (context) => AlertDialog(
            backgroundColor: AppColors.input,
            title: Text(
              'Выйти из аккаунта?',
              style: TextStyle(color: AppColors.text),
            ),
            content: const Text(
              'Вы будете перенаправлены на экран входа.',
              style: TextStyle(color: Colors.grey),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Отмена'),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(true),
                style: TextButton.styleFrom(foregroundColor: Colors.red),
                child: const Text('Выйти'),
              ),
            ],
          ),
    );

    if (confirmed == true) {
      try {
        await VaultService().clearAllData();
        if (mounted) {
          Navigator.pushNamedAndRemoveUntil(
            context,
            '/login',
            (route) => false,
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              backgroundColor: Colors.red,
              content: Text('Ошибка при выходе'),
            ),
          );
        }
      }
    }
  }

  Future<void> _updateFavicons() async {
    try {
      final token = await AuthTokenStorage.readAccessToken();
      if (token == null || token.isEmpty) {
        _showError('Сессия истекла, войдите снова');
        return;
      }

      final response = await http.post(
        Uri.parse(AppConfig.updateFaviconsUrl),
        headers: {'Authorization': 'Bearer $token'},
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              backgroundColor: Colors.green,
              content: Text('Обновлено фавиконок: ${data['updated'] ?? 0}'),
            ),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              backgroundColor: Colors.red,
              content: Text('Ошибка при обновлении фавиконок'),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            backgroundColor: Colors.red,
            content: Text('Ошибка подключения к серверу'),
          ),
        );
      }
    }
  }

  Future<void> _toggleSeedPhraseVisibility(bool value) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('hide_seed_phrases', value);

      setState(() {
        _hideSeedPhrases = value;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Colors.green,
            content: Text(
              value
                  ? 'Записи с seed фразами скрыты'
                  : 'Записи с seed фразами отображаются',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            backgroundColor: Colors.red,
            content: Text('Ошибка при сохранении настроек'),
          ),
        );
      }
    }
  }

  void _showBiometricSuccessAnimation() {
    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: '',
      barrierColor: Colors.black54,
      transitionDuration: const Duration(milliseconds: 300),
      pageBuilder: (ctx, anim1, anim2) => const _BiometricSuccessDialog(),
      transitionBuilder: (ctx, anim1, anim2, child) {
        return ScaleTransition(
          scale: CurvedAnimation(parent: anim1, curve: Curves.elasticOut),
          child: FadeTransition(opacity: anim1, child: child),
        );
      },
    );
  }

  Future<void> _loadBiometricSettings() async {
    try {
      final biometricAvailable = await BiometricService.isAvailable();
      final biometricEnabled = await BiometricService.isBiometricEnabled();

      setState(() {
        _biometricAvailable = biometricAvailable;
        _biometricEnabled = biometricEnabled && biometricAvailable;
        _biometricType = 'Биометрическая аутентификация';
      });
    } catch (e) {
      setState(() {
        _biometricAvailable = false;
        _biometricEnabled = false;
        _biometricType = 'Биометрическая аутентификация';
      });
    }
  }

  Future<void> _toggleBiometric(bool value) async {
    if (value) {
      // ── Step 1: Guard — vault must be unlocked ─────────────────────────────
      final vault = VaultService();
      if (vault.isLocked) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              backgroundColor: Colors.orange,
              content: Text('Хранилище заблокировано. Войдите через PIN для включения биометрии.'),
            ),
          );
        }
        return;
      }

      // ── Step 2: Check biometric hardware availability ─────────────────────
      final available = await BiometricService.isAvailable();
      if (!available) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              backgroundColor: Colors.orange,
              content: Text(
                'Отпечатки пальцев не настроены. Добавьте отпечаток в Настройках телефона → Безопасность.',
              ),
              duration: Duration(seconds: 5),
            ),
          );
        }
        return;
      }

      // ── Step 3: Store master key in secure storage (local only, no server) ─
      try {
        final keyBytes = await vault.masterKey!.extractBytes();
        final keyB64 = base64.encode(keyBytes);
        (keyBytes as Uint8List).fillRange(0, keyBytes.length, 0);

        final stored = await BiometricService.storeBiometricSecret(keyB64);

        if (stored) {
          await BiometricService.setBiometricEnabled(true);
          setState(() => _biometricEnabled = true);
          if (mounted) _showBiometricSuccessAnimation();
        } else {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                backgroundColor: Colors.red,
                content: Text('Не удалось сохранить ключ. Попробуйте снова.'),
              ),
            );
          }
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              backgroundColor: Colors.red,
              content: Text('Ошибка при включении биометрической аутентификации'),
            ),
          );
        }
      }
    } else {
      // Выключаем биометрическую аутентификацию
      final confirmed = await showDialog<bool>(
        context: context,
        builder:
            (context) => AlertDialog(
              backgroundColor: AppColors.input,
              title: Text(
                'Отключить $_biometricType?',
                style: TextStyle(color: AppColors.text),
              ),
              content: Text(
                'Вы уверены, что хотите отключить $_biometricType? После этого для входа потребуется вводить PIN-код или логин и пароль.',
                style: const TextStyle(color: Colors.grey),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: const Text('Отмена'),
                ),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  style: TextButton.styleFrom(foregroundColor: Colors.red),
                  child: const Text('Отключить'),
                ),
              ],
            ),
      );

      if (confirmed == true) {
        try {
          await BiometricService.setBiometricEnabled(false);
          setState(() {
            _biometricEnabled = false;
          });

          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                backgroundColor: Colors.green,
                content: Text('$_biometricType отключен'),
              ),
            );
          }
        } catch (e) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                backgroundColor: Colors.red,
                content: Text(
                  'Ошибка при отключении биометрической аутентификации',
                ),
              ),
            );
          }
        }
      }
    }
  }

  Future<void> _showBiometricDiagnostics() async {
    try {
      final diagnosticInfo = await BiometricService.getDiagnosticInfo();

      if (mounted) {
        showDialog(
          context: context,
          builder:
              (context) => AlertDialog(
                backgroundColor: AppColors.input,
                title: Text(
                  'Диагностика биометрии',
                  style: TextStyle(color: AppColors.text),
                ),
                content: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _buildDiagnosticRow(
                        'Статус системы',
                        diagnosticInfo['systemStatus'] ?? 'N/A',
                      ),
                      const SizedBox(height: 12),
                      _buildDiagnosticRow(
                        'Может проверять биометрию',
                        '${diagnosticInfo['canCheckBiometrics'] ?? 'N/A'}',
                      ),
                      _buildDiagnosticRow(
                        'Устройство поддерживается',
                        '${diagnosticInfo['isDeviceSupported'] ?? 'N/A'}',
                      ),
                      _buildDiagnosticRow(
                        'Включена в настройках',
                        '${diagnosticInfo['isEnabled'] ?? 'N/A'}',
                      ),
                      _buildDiagnosticRow(
                        'Всего доступных методов',
                        '${diagnosticInfo['totalAvailableMethods'] ?? 'N/A'}',
                      ),
                      _buildDiagnosticRow(
                        'Можно использовать',
                        '${diagnosticInfo['canUseBiometrics'] ?? 'N/A'}',
                      ),

                      if (diagnosticInfo['biometricDetails'] != null &&
                          (diagnosticInfo['biometricDetails']
                                  as Map<String, String>)
                              .isNotEmpty) ...[
                        const SizedBox(height: 12),
                        Text(
                          'Доступные методы:',
                          style: TextStyle(
                            color: AppColors.text,
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(height: 8),
                        ...(diagnosticInfo['biometricDetails']
                                as Map<String, String>)
                            .entries
                            .map(
                              (entry) => Padding(
                                padding: const EdgeInsets.only(
                                  left: 16,
                                  bottom: 4,
                                ),
                                child: Text(
                                  '• ${entry.value}',
                                  style: const TextStyle(
                                    color: Colors.grey,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                            ),
                      ],

                      if (diagnosticInfo['availableBiometrics'] != null &&
                          (diagnosticInfo['availableBiometrics'] as List)
                              .isNotEmpty) ...[
                        const SizedBox(height: 12),
                        Text(
                          'Технические названия:',
                          style: TextStyle(
                            color: AppColors.text,
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(height: 8),
                        ...(diagnosticInfo['availableBiometrics'] as List).map(
                          (biometric) => Padding(
                            padding: const EdgeInsets.only(left: 16, bottom: 4),
                            child: Text(
                              '• $biometric',
                              style: const TextStyle(
                                color: Colors.grey,
                                fontSize: 12,
                                fontFamily: 'monospace',
                              ),
                            ),
                          ),
                        ),
                      ],

                      if (diagnosticInfo['error'] != null) ...[
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.red.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: Colors.red.withOpacity(0.3),
                            ),
                          ),
                          child: Text(
                            'Ошибка: ${diagnosticInfo['error']}',
                            style: const TextStyle(
                              color: Colors.red,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Закрыть'),
                  ),
                  if (diagnosticInfo['canUseBiometrics'] == true &&
                      diagnosticInfo['isEnabled'] == false)
                    TextButton(
                      onPressed: () async {
                        Navigator.of(context).pop();
                        await _forceEnableBiometrics();
                      },
                      child: const Text('Принудительно включить'),
                    ),
                  TextButton(
                    onPressed: () async {
                      Navigator.of(context).pop();
                      await _resetBiometricSettings();
                    },
                    style: TextButton.styleFrom(foregroundColor: Colors.orange),
                    child: const Text('Сбросить настройки'),
                  ),
                ],
              ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Colors.red,
            content: Text('Ошибка при получении диагностики: $e'),
          ),
        );
      }
    }
  }

  Widget _buildDiagnosticRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 140,
            child: Text(
              label,
              style: TextStyle(
                color: AppColors.text,
                fontWeight: FontWeight.w500,
                fontSize: 12,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                color:
                    value == 'true'
                        ? Colors.green
                        : value == 'false'
                        ? Colors.red
                        : Colors.grey,
                fontSize: 12,
                fontWeight:
                    value == 'true' || value == 'false'
                        ? FontWeight.bold
                        : FontWeight.normal,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _forceEnableBiometrics() async {
    try {
      final success = await BiometricService.forceEnableBiometrics();

      if (success) {
        setState(() {
          _biometricEnabled = true;
        });

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              backgroundColor: Colors.green,
              content: Text(
                'Биометрическая аутентификация принудительно включена',
              ),
            ),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              backgroundColor: Colors.red,
              content: Text(
                'Не удалось включить биометрическую аутентификацию',
              ),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Colors.red,
            content: Text('Ошибка при включении биометрии: $e'),
          ),
        );
      }
    }
  }

  Future<void> _resetBiometricSettings() async {
    try {
      await BiometricService.resetBiometricSettings();

      setState(() {
        _biometricEnabled = false;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            backgroundColor: Colors.orange,
            content: Text('Настройки биометрии сброшены'),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Colors.red,
            content: Text('Ошибка при сбросе настроек: $e'),
          ),
        );
      }
    }
  }

  Future<void> _loadThemeSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final themeIndex = prefs.getInt('app_theme') ?? 0;

      setState(() {
        _currentTheme = AppTheme.values[themeIndex];
      });

      ThemeManager.setTheme(_currentTheme);
    } catch (e) {
      setState(() {
        _currentTheme = AppTheme.dark;
      });
      ThemeManager.setTheme(_currentTheme);
    }
  }

  Future<void> _changeTheme() async {
    final selectedTheme = await showDialog<AppTheme>(
      context: context,
      builder:
          (context) => AlertDialog(
            backgroundColor: AppColors.input,
            title: Text(
              'Выберите тему',
              style: TextStyle(color: AppColors.text),
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children:
                  AppTheme.values.map((theme) {
                    return RadioListTile<AppTheme>(
                      title: Text(
                        ThemeManager.getThemeName(theme),
                        style: TextStyle(color: AppColors.text),
                      ),
                      subtitle: Text(
                        _getThemeDescription(theme),
                        style: const TextStyle(
                          color: Colors.grey,
                          fontSize: 12,
                        ),
                      ),
                      value: theme,
                      groupValue: _currentTheme,
                      activeColor: AppColors.button,
                      onChanged: (value) => Navigator.of(context).pop(value),
                    );
                  }).toList(),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Отмена'),
              ),
            ],
          ),
    );

    if (selectedTheme != null && selectedTheme != _currentTheme) {
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setInt('app_theme', selectedTheme.index);

        setState(() {
          _currentTheme = selectedTheme;
        });

        ThemeManager.setTheme(selectedTheme);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              backgroundColor: Colors.green,
              content: Text(
                'Тема изменена на ${ThemeManager.getThemeName(selectedTheme)}',
              ),
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              backgroundColor: Colors.red,
              content: Text('Ошибка при сохранении темы'),
            ),
          );
        }
      }
    }
  }

  String _getThemeDescription(AppTheme theme) {
    switch (theme) {
      case AppTheme.dark:
        return 'Классическая темная тема';
      case AppTheme.cyberpunk:
        return 'Неоновые цвета и эффекты свечения';
      case AppTheme.glassmorphism:
        return 'Полупрозрачные элементы с размытием';
    }
  }

  Future<void> _loadProfile() async {
    setState(() => _isProfileLoading = true);
    try {
      final response = await ApiService.get(AppConfig.profileUrl);
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        setState(() {
          _telegramChatId = data['telegram_chat_id'];
          _userLogin = data['login'];
          _passwordCount = data['password_count'] ?? 0;
          _hasSeedPhrase = data['has_seed_phrase'] ?? false;
        });
      }
    } catch (_) {
    } finally {
      setState(() => _isProfileLoading = false);
    }
  }

  Future<void> _bindTelegram() async {
    final TextEditingController controller = TextEditingController(
      text: _telegramChatId,
    );

    final result = await showDialog<String>(
      context: context,
      builder:
          (context) => AlertDialog(
            backgroundColor: AppColors.input,
            title: const Text(
              'Привязка Telegram',
              style: TextStyle(color: Colors.white),
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Введите ваш Telegram Chat ID для получения уведомлений о безопасности.',
                  style: TextStyle(color: Colors.grey, fontSize: 13),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: controller,
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(
                    labelText: 'Chat ID',
                    labelStyle: TextStyle(color: Colors.grey),
                    enabledBorder: UnderlineInputBorder(
                      borderSide: BorderSide(color: Colors.grey),
                    ),
                  ),
                  keyboardType: TextInputType.number,
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Отмена'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, controller.text),
                child: const Text('Сохранить'),
              ),
            ],
          ),
    );

    if (result != null) {
      setState(() => _isProfileLoading = true);
      try {
        final response = await ApiService.post(
          AppConfig.updateProfileUrl,
          body: {'telegram_chat_id': result},
        );

        if (response.statusCode == 200) {
          setState(() {
            _telegramChatId = result;
          });
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                backgroundColor: Colors.green,
                content: Text('Настройки Telegram сохранены'),
              ),
            );
          }
        } else {
          // Ошибки (включая OTP) обрабатываются в ApiService автоматически,
          // но если мы здесь, значит запрос все же не удался после всех попыток
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                backgroundColor: Colors.red,
                content: Text('Ошибка при сохранении настроек'),
              ),
            );
          }
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(backgroundColor: Colors.red, content: Text('Ошибка: $e')),
          );
        }
      } finally {
        setState(() => _isProfileLoading = false);
      }
    }
  }

  Future<void> _registerPasskey() async {
    setState(() => _isPasskeyLoading = true);
    try {
      final deviceInfo = DeviceInfoPlugin();
      String deviceName = 'Unknown Device';
      String deviceId = 'unknown';

      if (Platform.isAndroid) {
        final androidInfo = await deviceInfo.androidInfo;
        deviceName = androidInfo.model;
        deviceId = androidInfo.id;
      } else if (Platform.isIOS) {
        final iosInfo = await deviceInfo.iosInfo;
        deviceName = iosInfo.name;
        deviceId = iosInfo.identifierForVendor ?? 'unknown_ios';
      }

      final success = await _passkeyService.registerPasskey(
        deviceName,
        deviceId,
      );
      if (success) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Passkey успешно зарегистрирован')),
          );
        }
        _loadDevices();
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Ошибка регистрации Passkey')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Ошибка: $e')));
      }
    } finally {
      setState(() => _isPasskeyLoading = false);
    }
  }

  Future<void> _revokeDevice(int id) async {
    try {
      final response = await ApiService.delete(
        AppConfig.getRevokeDeviceUrl(id),
      );
      if (response.statusCode == 200) {
        _loadDevices();
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Настройки'),
        backgroundColor: AppColors.background,
        elevation: 0,
      ),
      body:
          _isLoading
              ? const Center(child: CircularProgressIndicator())
              : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  // Секция безопасности
                  _buildSectionHeader('Безопасность'),

                  // PIN-код
                  _buildSettingTile(
                    icon: Icons.lock_outline,
                    title: 'PIN-код',
                    subtitle:
                        _hasPinCode
                            ? 'PIN-код установлен'
                            : 'PIN-код не установлен',
                    trailing:
                        _hasPinCode
                            ? Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                TextButton(
                                  onPressed: _changePinCode,
                                  child: const Text('Изменить'),
                                ),
                                TextButton(
                                  onPressed: _removePinCode,
                                  style: TextButton.styleFrom(
                                    foregroundColor: Colors.red,
                                  ),
                                  child: const Text('Удалить'),
                                ),
                              ],
                            )
                            : TextButton(
                              onPressed: _changePinCode,
                              child: const Text('Установить'),
                            ),
                  ),

                  // Скрытие seed фраз
                  _buildSettingTile(
                    icon: Icons.visibility_off,
                    title: 'Скрыть записи с seed фразами',
                    subtitle:
                        _hideSeedPhrases
                            ? 'Записи с seed фразами скрыты из списка'
                            : 'Записи с seed фразами отображаются в списке',
                    trailing: Switch(
                      value: _hideSeedPhrases,
                      onChanged: _toggleSeedPhraseVisibility,
                      activeColor: AppColors.button,
                    ),
                  ),

                  // Биометрическая аутентификация
                  if (_biometricAvailable)
                    _buildSettingTile(
                      icon: Icons.fingerprint,
                      title: _biometricType,
                      subtitle:
                          _biometricEnabled
                              ? 'Биометрическая аутентификация включена'
                              : 'Биометрическая аутентификация отключена',
                      trailing: Switch(
                        value: _biometricEnabled,
                        onChanged: _toggleBiometric,
                        activeColor: AppColors.button,
                      ),
                    ),

                  // Диагностика биометрии
                  if (_biometricAvailable)
                    _buildSettingTile(
                      icon: Icons.bug_report,
                      title: 'Диагностика биометрии',
                      subtitle:
                          'Проверить состояние биометрической аутентификации',
                      trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                      onTap: _showBiometricDiagnostics,
                    ),

                  // Тестирование биометрии
                  if (_biometricAvailable)
                    _buildSettingTile(
                      icon: Icons.science,
                      title: 'Тест биометрии',
                      subtitle:
                          'Подробное тестирование биометрической аутентификации',
                      trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                      onTap:
                          () => Navigator.pushNamed(context, '/biometric-test'),
                    ),

                  // Фраза восстановления (Seed Phrase)
                  _buildSettingTile(
                    icon: Icons.vpn_key_outlined,
                    title: 'Фраза восстановления',
                    subtitle: _hasSeedPhrase 
                        ? 'Просмотр фразы восстановления аккаунта'
                        : 'Фраза восстановления не установлена',
                    trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                    onTap: _hasSeedPhrase ? _viewSeedPhrase : _setupSeedPhrase,
                  ),

                  // История паролей
                  _buildSettingTile(
                    icon: Icons.history,
                    title: 'История паролей',
                    subtitle: 'Просмотр истории изменений паролей',
                    trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                    onTap:
                        () => Navigator.pushNamed(context, '/password-history'),
                  ),

                  const SizedBox(height: 24),

                  // ── Скрытые папки ────────────────────────────────────────
                  _buildSectionHeader('Скрытые папки'),

                  Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: _showHiddenFolders
                          ? AppColors.button.withOpacity(0.08)
                          : AppColors.surface,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: _showHiddenFolders
                            ? AppColors.button.withOpacity(0.35)
                            : AppColors.text.withOpacity(0.08),
                      ),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 42,
                          height: 42,
                          decoration: BoxDecoration(
                            color: _showHiddenFolders
                                ? AppColors.button.withOpacity(0.2)
                                : AppColors.input,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Icon(
                            _showHiddenFolders ? Icons.visibility : Icons.visibility_off,
                            color: _showHiddenFolders
                                ? AppColors.button
                                : AppColors.text.withOpacity(0.5),
                            size: 20,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Показывать скрытые папки',
                                style: TextStyle(
                                  color: AppColors.text,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 15,
                                ),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                _showHiddenFolders
                                    ? 'Разблокировано на эту сессию'
                                    : 'Требуется TOTP для включения',
                                style: TextStyle(
                                  color: _showHiddenFolders
                                      ? AppColors.button.withOpacity(0.8)
                                      : AppColors.text.withOpacity(0.5),
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Switch(
                          value: _showHiddenFolders,
                          onChanged: _toggleHiddenFolders,
                          activeColor: AppColors.button,
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 24),
                  _buildSectionHeader('Организация'),

                  _buildSettingTile(
                    icon: Icons.folder_open_outlined,
                    title: 'Папки',
                    subtitle: 'Управление папками и категориями',
                    trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                    onTap: () => Navigator.pushNamed(context, '/folders'),
                  ),

                  const SizedBox(height: 24),

                  // Секция интерфейса
                  _buildSectionHeader('Интерфейс'),

                  // Выбор темы
                  _buildSettingTile(
                    icon: Icons.palette,
                    title: 'Тема приложения',
                    subtitle: ThemeManager.getThemeName(_currentTheme),
                    trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                    onTap: _changeTheme,
                  ),

                  const SizedBox(height: 24),

                  // Секция сервера
                  _buildSectionHeader('Сервер'),
                  _buildSettingTile(
                    icon: Icons.dns_outlined,
                    title: 'Текущий сервер',
                    subtitle: AppConfig.apiBaseUrl ?? 'Не задан',
                    trailing: TextButton(
                      onPressed:
                          () => Navigator.pushNamed(context, '/setup-server'),
                      child: const Text('Изменить'),
                    ),
                  ),

                  const SizedBox(height: 24),

                  // Секция аккаунта
                  _buildSectionHeader('Аккаунт'),

                  // Информация о пользователе
                  _buildSettingTile(
                    icon: Icons.person_outline,
                    title: 'Профиль',
                    subtitle:
                        _userLogin != null
                            ? 'Логин: $_userLogin\nВсего паролей: $_passwordCount'
                            : 'Загрузка...',
                    trailing:
                        _isProfileLoading
                            ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                            : null,
                  ),

                  // Telegram Binding
                  _buildSettingTile(
                    icon: Icons.send,
                    title: 'Уведомления Telegram',
                    subtitle:
                        _telegramChatId != null && _telegramChatId!.isNotEmpty
                            ? 'Привязан Chat ID: $_telegramChatId'
                            : 'Уведомления не настроены',
                    trailing:
                        _isProfileLoading
                            ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                            : const Icon(Icons.arrow_forward_ios, size: 16),
                    onTap: () async {
                      final result = await Navigator.pushNamed(
                        context,
                        '/telegram-binding',
                      );
                      if (result != null) _loadProfile();
                    },
                  ),

                  // Passkeys
                  _buildSectionHeader('Passkeys (Безопасный вход)'),
                  _buildSettingTile(
                    icon: Icons.vpn_key_outlined,
                    title: 'Passkeys',
                    subtitle:
                        'Управление ключами доступа для беспарольного входа',
                    trailing:
                        _isPasskeyLoading
                            ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                            : const Icon(Icons.add_circle_outline),
                    onTap: _registerPasskey,
                  ),

                  if (_devices.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Column(
                        children:
                            _devices
                                .map(
                                  (device) => ListTile(
                                    contentPadding: EdgeInsets.zero,
                                    leading: const Icon(
                                      Icons.devices,
                                      color: Colors.grey,
                                      size: 20,
                                    ),
                                    title: Text(
                                      device['device_name'],
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 14,
                                      ),
                                    ),
                                    subtitle: Text(
                                      'Последний вход: ${device['last_used_at'] != null ? DateTime.parse(device['last_used_at']).toLocal().toString().split('.')[0] : "никогда"}',
                                      style: const TextStyle(
                                        color: Colors.grey,
                                        fontSize: 11,
                                      ),
                                    ),
                                    trailing: IconButton(
                                      icon: const Icon(
                                        Icons.delete_outline,
                                        color: Colors.red,
                                        size: 20,
                                      ),
                                      onPressed:
                                          () => _revokeDevice(device['id']),
                                    ),
                                  ),
                                )
                                .toList(),
                      ),
                    ),

                  const SizedBox(height: 24),

                  // Обновление фавиконок
                  _buildSettingTile(
                    icon: Icons.image,
                    title: 'Обновить фавиконки',
                    subtitle: 'Обновить фавиконки для всех паролей',
                    trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                    onTap: _updateFavicons,
                  ),

                  // Импорт паролей
                  _buildSettingTile(
                    icon: Icons.file_upload_outlined,
                    title: 'Импорт паролей (.csv)',
                    subtitle: 'Импорт из файлов браузеров или приложений',
                    trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                    onTap: _importPasswordsFromFile,
                  ),

                  // Выход
                  _buildSettingTile(
                    icon: Icons.logout,
                    title: 'Выйти из аккаунта',
                    subtitle: 'Выйти из текущего аккаунта',
                    trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                    onTap: _logout,
                  ),

                  const SizedBox(height: 24),

                  // Секция информации
                  _buildSectionHeader('Информация'),

                  // Версия приложения
                  _buildSettingTile(
                    icon: Icons.info_outline,
                    title: 'Версия приложения',
                    subtitle: '0.2.1',
                  ),

                  // О приложении
                  _buildSettingTile(
                    icon: Icons.description_outlined,
                    title: 'О приложении',
                    subtitle: 'Менеджер паролей',
                    trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                    onTap: () {
                      showAboutDialog(
                        context: context,
                        applicationName: 'Менеджер паролей',
                        applicationVersion: '1.0.0',
                        applicationIcon: Container(
                          width: 64,
                          height: 64,
                          decoration: BoxDecoration(
                            color: AppColors.button.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Icon(
                            Icons.lock_outline,
                            color: AppColors.button,
                            size: 32,
                          ),
                        ),
                        children: const [
                          Text('Безопасное хранение и управление паролями.'),
                        ],
                      );
                    },
                  ),

                  const SizedBox(height: 32),

                  // Плашка с информацией о создателе
                  _buildCreatorCard(),
                ],
              ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.bold,
          color: AppColors.button,
        ),
      ),
    );
  }

  Widget _buildSettingTile({
    required IconData icon,
    required String title,
    required String subtitle,
    Widget? trailing,
    VoidCallback? onTap,
  }) {
    return Card(
      color: AppColors.input,
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        leading: Icon(icon, color: AppColors.button),
        title: Text(
          title,
          style: TextStyle(color: AppColors.text, fontWeight: FontWeight.w500),
        ),
        subtitle: Text(subtitle, style: const TextStyle(color: Colors.grey)),
        trailing: trailing,
        onTap: onTap,
      ),
    );
  }

  Future<void> _viewSeedPhrase() async {
    final TextEditingController totpController = TextEditingController();
    try {
      final String? otp = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
          backgroundColor: AppColors.input,
          title: const Text('Безопасность', style: TextStyle(color: Colors.white)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Для просмотра фразы восстановления введите TOTP код из приложения.',
                style: TextStyle(color: Colors.grey, fontSize: 13),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: totpController,
                autofocus: true,
                keyboardType: TextInputType.number,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  hintText: 'TOTP Код',
                  hintStyle: TextStyle(color: Colors.grey),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Отмена')),
            TextButton(
              onPressed: () => Navigator.pop(context, totpController.text.trim()),
              child: const Text('Подтвердить'),
            ),
          ],
        ),
      );

      if (otp == null || otp.isEmpty) return;

      setState(() => _isProfileLoading = true);

      final verifyResponse = await ApiService.post(
        AppConfig.verifyTotpUrl,
        headers: {'X-OTP': otp},
        body: {},
      );

      if (verifyResponse.statusCode != 200) {
        _showError('Неверный TOTP код');
        return;
      }

      final verifyData = json.decode(verifyResponse.body) as Map<String, dynamic>;
      final accessToken = verifyData['seed_access_token'] as String?;
      if (accessToken == null || accessToken.isEmpty) {
        _showError('Не удалось подтвердить доступ');
        return;
      }

      final seedResponse = await http.get(
        Uri.parse(AppConfig.seedPhraseUrl),
        headers: {'Authorization': 'Bearer $accessToken'},
      );

      if (seedResponse.statusCode != 200) {
        _showError('Ошибка загрузки фразы');
        return;
      }

      final seedData = json.decode(seedResponse.body) as Map<String, dynamic>;
      final encryptedPhrase = seedData['seed_phrase_encrypted'] as String?;
      final legacyPhrase = seedData['seed_phrase'] as String?;
      if ((encryptedPhrase == null || encryptedPhrase.isEmpty) &&
          (legacyPhrase == null || legacyPhrase.isEmpty)) {
        _showError('Фраза восстановления не настроена');
        return;
      }

      String phrase;
      SecureBuffer? seedBuffer;
      if (encryptedPhrase != null && encryptedPhrase.isNotEmpty) {
        seedBuffer = await VaultService().decryptAccountSeedPhraseSecure(encryptedPhrase);
        final phraseBytes = seedBuffer.getBytesCopy();
        phrase = String.fromCharCodes(phraseBytes);
        phraseBytes.fillRange(0, phraseBytes.length, 0);
      } else {
        phrase = legacyPhrase!;
      }

      if (!mounted) return;
      await _showSeedPhraseDialog(phrase);
      await nativeWipe(phrase);
      seedBuffer?.wipe();
    } catch (e) {
      _showError('Ошибка соединения: $e');
    } finally {
      await wipeController(totpController);
      totpController.dispose();
      if (mounted) {
        setState(() => _isProfileLoading = false);
      }
    }
  }

  Future<void> _setupSeedPhrase() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.input,
        title: const Text('Создать фразу восстановления?', style: TextStyle(color: Colors.white)),
        content: const Text(
          'Это позволит восстановить доступ к аккаунту при потере пароля. Фраза будет сгенерирована на устройстве.',
          style: TextStyle(color: Colors.grey),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Отмена')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Продолжить'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    final String phrase = bip39.generateMnemonic(strength: 128);
    final encryptedPhrase = await VaultService().encryptAccountSeedPhrase(phrase);

    setState(() => _isProfileLoading = true);
    try {
      final response = await ApiService.post(
        AppConfig.seedPhraseUrl,
        body: {'seed_phrase_encrypted': encryptedPhrase},
      );

      if (response.statusCode == 200) {
        setState(() {
          _hasSeedPhrase = true;
        });
        if (!mounted) return;
        await _showSeedPhraseDialog(phrase);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(backgroundColor: Colors.green, content: Text('Фраза восстановления успешно создана')),
        );
      } else {
        _showError('Ошибка при создании фразы');
      }
    } catch (e) {
      _showError('Ошибка соединения: $e');
    } finally {
      await nativeWipe(phrase);
      if (mounted) {
        setState(() => _isProfileLoading = false);
      }
    }
  }

  Future<void> _showSeedPhraseDialog(String phrase) {
    return showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.input,
        title: const Text('Фраза восстановления', style: TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.3),
                borderRadius: BorderRadius.circular(12),
              ),
              child: SelectableText(
                phrase,
                style: const TextStyle(
                  color: Colors.white,
                  fontFamily: 'monospace',
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Никому не сообщайте эту фразу! Она дает полный доступ к вашему аккаунту и данным.',
              style: TextStyle(color: Colors.orangeAccent, fontSize: 12),
              textAlign: TextAlign.center,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Закрыть'),
          ),
          ElevatedButton(
            onPressed: () async {
              await copyWithAutoClear(phrase);
              if (!mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Фраза скопирована в буфер обмена')),
              );
            },
            child: const Text('Копировать'),
          ),
        ],
      ),
    );
  }

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: Colors.red),
    );
  }

  Widget _buildCreatorCard() {
    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppColors.button.withOpacity(0.1),
            AppColors.button.withOpacity(0.05),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.button.withOpacity(0.2), width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [AppColors.button, AppColors.button.withOpacity(0.8)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: AppColors.button.withOpacity(0.3),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: const Icon(Icons.code, color: Colors.white, size: 24),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Text(
                      'Создано ',
                      style: TextStyle(color: Colors.grey, fontSize: 14),
                    ),
                    const Text(
                      'NK_TRIPLLE',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 2),
                      child: const Text('❤️', style: TextStyle(fontSize: 16)),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  'С любовью к безопасности и удобству',
                  style: TextStyle(
                    color: Colors.grey.withOpacity(0.8),
                    fontSize: 12,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Biometric success animation dialog ────────────────────────────────────────

class _BiometricSuccessDialog extends StatefulWidget {
  const _BiometricSuccessDialog();

  @override
  State<_BiometricSuccessDialog> createState() => _BiometricSuccessDialogState();
}

class _BiometricSuccessDialogState extends State<_BiometricSuccessDialog>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _checkAnim;
  late final Animation<double> _pulseAnim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 900));
    _checkAnim = CurvedAnimation(parent: _ctrl, curve: const Interval(0.0, 0.7, curve: Curves.easeOutBack));
    _pulseAnim = CurvedAnimation(parent: _ctrl, curve: const Interval(0.6, 1.0, curve: Curves.easeOut));
    _ctrl.forward();
    // Auto-close after 2 seconds
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) Navigator.of(context).pop();
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Material(
        color: Colors.transparent,
        child: Container(
          width: 240,
          padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 24),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(28),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.3),
                blurRadius: 32,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedBuilder(
                animation: _ctrl,
                builder: (_, __) => Stack(
                  alignment: Alignment.center,
                  children: [
                    // Outer pulse ring
                    Transform.scale(
                      scale: 0.7 + 0.4 * _pulseAnim.value,
                      child: Opacity(
                        opacity: (1 - _pulseAnim.value).clamp(0.0, 1.0),
                        child: Container(
                          width: 96,
                          height: 96,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.green.withOpacity(0.2),
                          ),
                        ),
                      ),
                    ),
                    // Main circle
                    Transform.scale(
                      scale: _checkAnim.value,
                      child: Container(
                        width: 72,
                        height: 72,
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: LinearGradient(
                            colors: [Color(0xFF43A047), Color(0xFF2E7D32)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                        ),
                        child: const Icon(Icons.fingerprint, color: Colors.white, size: 38),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              Text(
                'Биометрия включена',
                style: TextStyle(
                  color: AppColors.text,
                  fontSize: 17,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Вход по отпечатку пальца\nактивирован',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AppColors.text.withOpacity(0.6),
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
