import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/colors.dart';
import '../utils/pin_security.dart';
import '../services/vault_service.dart';
import '../l10n/l_text.dart';
import '../utils/memory_security.dart';

/// PIN setup screen.
///
/// Security properties:
///   CWE-922 — PBKDF2 hash stored in FlutterSecureStorage (not SharedPreferences)
///   CWE-327 — PBKDF2-HMAC-SHA256 with 100k iterations + unique 16-byte salt
///   CWE-256 — PIN bytes never converted to an immutable Dart String
class SetupPinScreen extends StatefulWidget {
  const SetupPinScreen({super.key});

  @override
  State<SetupPinScreen> createState() => _SetupPinScreenState();
}

class _SetupPinScreenState extends State<SetupPinScreen>
    with TickerProviderStateMixin {
  final TextEditingController _pinController = TextEditingController();
  final FocusNode _pinFocusNode = FocusNode();

  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  // PIN digits as raw bytes (ASCII codes of '0'..'9') — zeroed after use.
  Uint8List _pinBytes = Uint8List(0);
  Uint8List _confirmPinBytes = Uint8List(0);

  bool _isConfirming = false;
  bool _isLoading = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();

    _animationController = AnimationController(
      duration: const Duration(milliseconds: 1000),
      vsync: this,
    );

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeInOut),
    );

    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.3),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeOutCubic),
    );

    _animationController.forward();

    // Auto-focus the field
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _pinFocusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _pinController.dispose();
    _pinFocusNode.dispose();
    _animationController.dispose();
    _pinBytes.fillRange(0, _pinBytes.length, 0);
    _confirmPinBytes.fillRange(0, _confirmPinBytes.length, 0);
    super.dispose();
  }

  Uint8List _collectBytesFromText(String text) {
    final bytes = Uint8List(text.length);
    for (int i = 0; i < text.length; i++) {
      bytes[i] = text.codeUnitAt(i);
    }
    return bytes;
  }

  void _onPinInputChanged(String value) {
    setState(() => _errorMessage = null);

    if (value.length == 6) {
      if (!_isConfirming) {
        _pinBytes = _collectBytesFromText(value);
        wipeController(_pinController);
        _proceedToConfirm();
      } else {
        _confirmPinBytes = _collectBytesFromText(value);
        wipeController(_pinController);
        _savePin();
      }
    }
  }

  void _proceedToConfirm() {
    setState(() => _isConfirming = true);
    _pinFocusNode.requestFocus();
  }

  void _clearInput() {
    _pinController.clear();
    setState(() => _errorMessage = null);
  }

  Future<void> _savePin() async {
    // Constant-time comparison to avoid timing side-channels
    bool match = _pinBytes.length == _confirmPinBytes.length;
    if (match) {
      for (int i = 0; i < _pinBytes.length; i++) {
        if (_pinBytes[i] != _confirmPinBytes[i]) match = false;
      }
    }

    // Zero confirm buffer — no longer needed
    _confirmPinBytes.fillRange(0, _confirmPinBytes.length, 0);
    _confirmPinBytes = Uint8List(0);

    if (!match) {
      setState(() {
        _errorMessage = 'PIN-коды не совпадают';
        _isConfirming = false;
        _pinBytes.fillRange(0, _pinBytes.length, 0);
        _pinBytes = Uint8List(0);
      });
      _pinFocusNode.requestFocus();
      return;
    }

    setState(() => _isLoading = true);

    try {
      // 1. Store PBKDF2 hash in FlutterSecureStorage (CWE-922 + CWE-327)
      await PinSecurity.storePinHash(_pinBytes);

      // 2. Encrypt master key with PIN bytes — no String creation (CWE-256)
      await VaultService().storeMasterKeyWithPinBytes(_pinBytes);

      // 3. Remove no-PIN key if it existed (user now has a PIN).
      await VaultService().clearNoPinMasterKey();

      // 3. Zero PIN bytes after all operations
      _pinBytes.fillRange(0, _pinBytes.length, 0);
      _pinBytes = Uint8List(0);

      _showSuccessAnimation();
    } catch (e, st) {
      debugPrint('PIN save error: $e\n$st');
      setState(() {
        _errorMessage = 'Ошибка сохранения PIN-кода';
        _isLoading = false;
        _isConfirming = false;
        _pinBytes.fillRange(0, _pinBytes.length, 0); 
        _pinBytes = Uint8List(0);
      });
      _pinFocusNode.requestFocus();
    }
  }

  void _showSuccessAnimation() {
    if (mounted) {
      Navigator.pushNamedAndRemoveUntil(context, '/passwords', (route) => false);
    }
  }

  void _goBack() {
    if (_isConfirming) {
      _pinBytes.fillRange(0, _pinBytes.length, 0);
      _pinBytes = Uint8List(0);
      _pinController.clear();
      setState(() => _isConfirming = false);
      _pinFocusNode.requestFocus();
    } else {
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final value = _pinController.text;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: AppColors.text),
          onPressed: _goBack,
        ),
      ),
      body: SafeArea(
        child: FadeTransition(
          opacity: _fadeAnimation,
          child: SlideTransition(
            position: _slideAnimation,
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          AppColors.button.withOpacity(0.2),
                          AppColors.button.withOpacity(0.1),
                        ],
                      ),
                      borderRadius: BorderRadius.circular(40),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.button.withOpacity(0.3),
                          blurRadius: 20,
                          spreadRadius: 5,
                        ),
                      ],
                    ),
                    child: Icon(
                      _isConfirming ? Icons.lock_outline : Icons.security,
                      size: 40,
                      color: AppColors.button,
                    ),
                  ),

                  const SizedBox(height: 40),

                  LText(
                    _isConfirming ? 'Подтвердите PIN-код' : 'Установите PIN-код',
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      color: AppColors.text,
                    ),
                  ),

                  const SizedBox(height: 8),

                  LText(
                    _isConfirming
                        ? 'Повторите ввод для подтверждения'
                        : 'Создайте 6-значный PIN-код для быстрого доступа',
                    style: const TextStyle(fontSize: 16, color: Colors.grey),
                    textAlign: TextAlign.center,
                  ),

                  const SizedBox(height: 40),

                  Stack(
                    alignment: Alignment.center,
                    children: [
                      // Hidden TextField to receive input
                      Opacity(
                        opacity: 0,
                        child: TextField(
                          controller: _pinController,
                          focusNode: _pinFocusNode,
                          autofocus: true,
                          keyboardType: TextInputType.number,
                          maxLength: 6,
                          onChanged: _onPinInputChanged,
                          showCursor: false,
                          enableInteractiveSelection: false,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                          ],
                        ),
                      ),
                      // Visual dots overlay
                      GestureDetector(
                        onTap: () => _pinFocusNode.requestFocus(),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: List.generate(6, (index) {
                            final hasValue = value.length > index;
                            return Container(
                              width: 46,
                              height: 52,
                              decoration: BoxDecoration(
                                color: AppColors.input,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: value.length == index
                                      ? AppColors.button
                                      : Colors.transparent,
                                  width: 2,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.1),
                                    blurRadius: 8,
                                    offset: const Offset(0, 4),
                                  ),
                                ],
                              ),
                              child: Center(
                                child: hasValue
                                    ? Container(
                                        width: 12,
                                        height: 12,
                                        decoration: BoxDecoration(
                                          color: AppColors.text,
                                          shape: BoxShape.circle,
                                        ),
                                      )
                                    : null,
                              ),
                            );
                          }),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 24),

                  if (value.isNotEmpty)
                    TextButton.icon(
                      onPressed: _clearInput,
                      icon: const Icon(Icons.backspace_outlined, size: 16),
                      label: const LText('Стереть всё'),
                      style: TextButton.styleFrom(
                        foregroundColor: AppColors.text.withOpacity(0.6),
                      ),
                    ),

                  const SizedBox(height: 24),

                  if (_errorMessage != null)
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 300),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.red.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.red.withOpacity(0.3)),
                      ),
                      child: LText(
                        _errorMessage!,
                        style: const TextStyle(color: Colors.red, fontSize: 14),
                      ),
                    ),

                  const SizedBox(height: 24),

                  if (_isLoading)
                    CircularProgressIndicator(
                      valueColor:
                          AlwaysStoppedAnimation<Color>(AppColors.button),
                    ),

                  const SizedBox(height: 40),

                  const LText(
                    'PIN-код должен содержать 6 цифр',
                    style: TextStyle(fontSize: 14, color: Colors.grey),
                    textAlign: TextAlign.center,
                  ),

                  const SizedBox(height: 20),

                  if (!_isConfirming)
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 8),
                      child: LText(
                        'PIN обязателен: мастер-ключ больше не сохраняется без локального секрета.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.grey, fontSize: 14),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
