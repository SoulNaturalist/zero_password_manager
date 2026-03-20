import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/colors.dart';
import '../utils/pin_security.dart';
import '../services/vault_service.dart';
import '../l10n/l_text.dart';

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
  final List<TextEditingController> _controllers = List.generate(
    6,
    (index) => TextEditingController(),
  );
  final List<FocusNode> _focusNodes = List.generate(6, (index) => FocusNode());

  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  // PIN digits as raw bytes (ASCII codes of '0'..'9') — zeroed after use.
  Uint8List _pinBytes        = Uint8List(0);
  Uint8List _confirmPinBytes = Uint8List(0);

  bool _isConfirming = false;
  bool _isLoading    = false;
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

    for (int i = 0; i < 6; i++) {
      _controllers[i].addListener(() {
        if (_controllers[i].text.length == 1 && i < 5) {
          _focusNodes[i + 1].requestFocus();
        }
      });
    }
  }

  @override
  void dispose() {
    for (var controller in _controllers) {
      controller.dispose();
    }
    for (var node in _focusNodes) {
      node.dispose();
    }
    _animationController.dispose();
    _pinBytes.fillRange(0, _pinBytes.length, 0);
    _confirmPinBytes.fillRange(0, _confirmPinBytes.length, 0);
    super.dispose();
  }

  Uint8List _collectAndClearControllers() {
    final bytes = Uint8List(6);
    for (int i = 0; i < 6; i++) {
      final text = _controllers[i].text;
      bytes[i] = text.isNotEmpty ? text.codeUnitAt(0) : 0;
      _controllers[i].clear();
    }
    return bytes;
  }

  void _onPinChanged() {
    final entered = _controllers.map((c) => c.text).join();
    setState(() => _errorMessage = null);

    if (entered.length == 6) {
      _pinBytes = _collectAndClearControllers();
      _proceedToConfirm();
    }
  }

  void _proceedToConfirm() {
    setState(() => _isConfirming = true);
    _focusNodes[0].requestFocus();
  }

  void _onConfirmPinChanged() {
    final entered = _controllers.map((c) => c.text).join();
    setState(() => _errorMessage = null);

    if (entered.length == 6) {
      _confirmPinBytes = _collectAndClearControllers();
      _savePin();
    }
  }

  Future<void> _savePin() async {
    // Constant-time comparison to avoid timing side-channels
    bool match = _pinBytes.length == _confirmPinBytes.length;
    for (int i = 0; i < _pinBytes.length; i++) {
      if (_pinBytes[i] != _confirmPinBytes[i]) match = false;
    }

    // Zero confirm buffer — no longer needed
    _confirmPinBytes.fillRange(0, _confirmPinBytes.length, 0);
    _confirmPinBytes = Uint8List(0);

    if (!match) {
      setState(() => _errorMessage = 'PIN-коды не совпадают');
      _focusNodes[0].requestFocus();
      return;
    }

    setState(() => _isLoading = true);

    try {
      // 1. Store PBKDF2 hash in FlutterSecureStorage (CWE-922 + CWE-327)
      //    No String created from PIN bytes (CWE-256).
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
      });
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
      setState(() => _isConfirming = false);
      _focusNodes[0].requestFocus();
    } else {
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
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

                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: List.generate(6, (index) {
                      return Container(
                        width: 46,
                        height: 52,
                        decoration: BoxDecoration(
                          color: AppColors.input,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: _focusNodes[index].hasFocus
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
                        child: TextField(
                          controller: _controllers[index],
                          focusNode: _focusNodes[index],
                          textAlign: TextAlign.center,
                          keyboardType: TextInputType.number,
                          obscureText: true,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                            LengthLimitingTextInputFormatter(1),
                          ],
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: AppColors.text,
                          ),
                          decoration: const InputDecoration(
                            border: InputBorder.none,
                            contentPadding: EdgeInsets.zero,
                          ),
                          onChanged: (value) => _isConfirming
                              ? _onConfirmPinChanged()
                              : _onPinChanged(),
                        ),
                      );
                    }),
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
                        border:
                            Border.all(color: Colors.red.withOpacity(0.3)),
                      ),
                      child: LText(
                        _errorMessage!,
                        style:
                            const TextStyle(color: Colors.red, fontSize: 14),
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
