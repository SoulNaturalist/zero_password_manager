import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:crypto/crypto.dart';
import 'dart:typed_data';
import '../theme/colors.dart';
import '../services/vault_service.dart';

class SetupPinScreen extends StatefulWidget {
  const SetupPinScreen({super.key});

  @override
  State<SetupPinScreen> createState() => _SetupPinScreenState();
}

class _SetupPinScreenState extends State<SetupPinScreen>
    with TickerProviderStateMixin {
  final List<TextEditingController> _controllers = List.generate(
    4,
    (index) => TextEditingController(),
  );
  final List<FocusNode> _focusNodes = List.generate(4, (index) => FocusNode());

  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  // PIN digits stored as raw bytes (ASCII codes of '0'..'9').
  // Using Uint8List instead of String so the buffer can be zeroed after use.
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

    for (int i = 0; i < 4; i++) {
      _controllers[i].addListener(() {
        if (_controllers[i].text.length == 1 && i < 3) {
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
    // Zero out any residual PIN bytes
    _pinBytes.fillRange(0, _pinBytes.length, 0);
    _confirmPinBytes.fillRange(0, _confirmPinBytes.length, 0);
    super.dispose();
  }

  /// Reads the current controller values into a fresh Uint8List and clears
  /// the controllers so the digits are no longer held as Strings in TextField state.
  Uint8List _collectAndClearControllers() {
    final bytes = Uint8List(4);
    for (int i = 0; i < 4; i++) {
      final text = _controllers[i].text;
      bytes[i] = text.isNotEmpty ? text.codeUnitAt(0) : 0;
      _controllers[i].clear();
    }
    return bytes;
  }

  void _onPinChanged() {
    final entered = _controllers.map((c) => c.text).join();
    setState(() => _errorMessage = null);

    if (entered.length == 4) {
      // Collect bytes and immediately clear TextField state
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

    if (entered.length == 4) {
      _confirmPinBytes = _collectAndClearControllers();
      _savePin();
    }
  }

  Future<void> _savePin() async {
    // Constant-time byte comparison to avoid timing side-channels
    bool match = _pinBytes.length == _confirmPinBytes.length;
    for (int i = 0; i < _pinBytes.length; i++) {
      if (_pinBytes[i] != _confirmPinBytes[i]) match = false;
    }

    // Zero confirm buffer — no longer needed
    _confirmPinBytes.fillRange(0, _confirmPinBytes.length, 0);

    if (!match) {
      setState(() => _errorMessage = 'PIN-коды не совпадают');
      _focusNodes[0].requestFocus();
      return;
    }

    setState(() => _isLoading = true);

    try {
      // Store SHA-256 hash of the PIN bytes — never store the plaintext PIN.
      // The verify screen computes the same hash and compares hex strings.
      final pinString = String.fromCharCodes(_pinBytes);
      final hash = sha256.convert(_pinBytes).toString();

      // Zero out the PIN buffer after hashing and converting to string
      _pinBytes.fillRange(0, _pinBytes.length, 0);

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('pin_hash', hash);
      // Remove legacy plain-text key if present
      await prefs.remove('pin_code');

      // Persist the Master Key encrypted with the PIN
      await VaultService().storeMasterKeyWithPin(pinString);

      _showSuccessAnimation();
    } catch (e) {
      setState(() {
        _errorMessage = 'Ошибка сохранения PIN-кода';
        _isLoading = false;
      });
    }
  }

  void _showSuccessAnimation() {
    Navigator.pushNamedAndRemoveUntil(context, '/passwords', (route) => false);
  }

  void _goBack() {
    if (_isConfirming) {
      // Zero out first-entry buffer when going back
      _pinBytes.fillRange(0, _pinBytes.length, 0);
      _pinBytes = Uint8List(0);
      setState(() {
        _isConfirming = false;
      });
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

                  Text(
                    _isConfirming
                        ? 'Подтвердите PIN-код'
                        : 'Установите PIN-код',
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      color: AppColors.text,
                    ),
                  ),

                  const SizedBox(height: 8),

                  Text(
                    _isConfirming
                        ? 'Повторите ввод для подтверждения'
                        : 'Создайте 4-значный PIN-код для быстрого доступа',
                    style: const TextStyle(fontSize: 16, color: Colors.grey),
                    textAlign: TextAlign.center,
                  ),

                  const SizedBox(height: 40),

                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: List.generate(4, (index) {
                      return Container(
                        width: 60,
                        height: 60,
                        decoration: BoxDecoration(
                          color: AppColors.input,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color:
                                _focusNodes[index].hasFocus
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
                          onChanged:
                              (value) =>
                                  _isConfirming
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
                        border: Border.all(color: Colors.red.withOpacity(0.3)),
                      ),
                      child: Text(
                        _errorMessage!,
                        style: const TextStyle(color: Colors.red, fontSize: 14),
                      ),
                    ),

                  const SizedBox(height: 24),

                  if (_isLoading)
                    CircularProgressIndicator(
                      valueColor: AlwaysStoppedAnimation<Color>(
                        AppColors.button,
                      ),
                    ),

                  const SizedBox(height: 40),

                  const Text(
                    'PIN-код должен содержать 4 цифры',
                    style: TextStyle(fontSize: 14, color: Colors.grey),
                    textAlign: TextAlign.center,
                  ),

                  const SizedBox(height: 20),

                  if (!_isConfirming)
                    TextButton(
                      onPressed: () {
                        Navigator.pushNamedAndRemoveUntil(
                          context,
                          '/passwords',
                          (route) => false,
                        );
                      },
                      child: const Text(
                        'Пропустить',
                        style: TextStyle(color: Colors.grey, fontSize: 16),
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
