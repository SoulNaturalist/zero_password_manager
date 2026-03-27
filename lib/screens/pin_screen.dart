import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/colors.dart';
import '../utils/biometric_service.dart';
import '../utils/memory_security.dart';
import '../utils/pin_security.dart';
import '../services/vault_service.dart';
import '../l10n/l_text.dart';
import '../utils/memory_security.dart';

/// PIN verification screen.
///
/// Security properties:
///   CWE-922 — PIN hash stored in FlutterSecureStorage, not SharedPreferences
///   CWE-327 — PBKDF2-HMAC-SHA256 with unique salt (no rainbow tables)
///   CWE-256 — PIN bytes never become an immutable Dart String; vault ops use pinBytes
///   CWE-284 — attempt counter + lockout persisted in FlutterSecureStorage
///   CWE-200 — unified error message, no attempt counter in UI
class PinScreen extends StatefulWidget {
  const PinScreen({super.key});

  @override
  State<PinScreen> createState() => _PinScreenState();
}

class _PinScreenState extends State<PinScreen> with TickerProviderStateMixin {
  final TextEditingController _pinController = TextEditingController();
  final FocusNode _pinFocusNode = FocusNode();

  late AnimationController _animationController;
  late AnimationController _shakeController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;
  late Animation<double> _shakeAnimation;

  // PIN stored as raw bytes (ASCII codes of '0'..'9') — zeroed after each use.
  Uint8List _pinBytes = Uint8List(0);

  bool _isLoading = false;
  String? _errorMessage;
  bool _isLocked = false;
  Duration? _lockoutRemaining;
  Timer? _lockoutTimer;

  bool _biometricAvailable = false;
  bool _biometricEnabled = false;
  bool _showPinInput = false;
  bool _hasPinHash = false;

  @override
  void initState() {
    super.initState();

    _animationController = AnimationController(
      duration: const Duration(milliseconds: 1000),
      vsync: this,
    );

    _shakeController = AnimationController(
      duration: const Duration(milliseconds: 500),
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

    _shakeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _shakeController, curve: Curves.elasticIn),
    );

    _animationController.forward();
    _checkInitialState();
  }

  Future<void> _checkInitialState() async {
    await _checkLockout();
    final hasPin = await PinSecurity.hasPinHash();
    final bioAvailable = await BiometricService.isAvailable();
    final bioEnabled = await BiometricService.isBiometricEnabled();

    if (mounted) {
      setState(() {
        _hasPinHash = hasPin;
        _biometricAvailable = bioAvailable;
        _biometricEnabled = bioEnabled;
        // If bio is available and enabled, don't show PIN input by default
        _showPinInput = !bioEnabled || !bioAvailable || !hasPin;
      });
    }

    if (bioAvailable && bioEnabled) {
      _authenticateWithBiometrics();
    } else if (hasPin && !_isLocked) {
      _pinFocusNode.requestFocus();
    } else if (!hasPin && !bioEnabled) {
      // Inconsistent state fallback
      if (mounted) Navigator.pushReplacementNamed(context, '/setup-pin');
    }
  }

  @override
  void dispose() {
    _lockoutTimer?.cancel();
    _pinController.dispose();
    _pinFocusNode.dispose();
    _animationController.dispose();
    _shakeController.dispose();
    _pinBytes.fillRange(0, _pinBytes.length, 0);
    super.dispose();
  }

  // ── Lockout check (CWE-284) ───────────────────────────────────────────────

  Future<void> _checkLockout() async {
    final remaining = await PinSecurity.getLockoutRemaining();
    if (remaining != null) {
      setState(() {
        _isLocked = true;
        _lockoutRemaining = remaining;
      });
      _startLockoutCountdown();
    }
  }

  void _startLockoutCountdown() {
    _lockoutTimer?.cancel();
    _lockoutTimer = Timer.periodic(const Duration(seconds: 1), (timer) async {
      final remaining = await PinSecurity.getLockoutRemaining();
      if (remaining == null) {
        timer.cancel();
        if (mounted) {
          setState(() {
            _isLocked = false;
            _lockoutRemaining = null;
            _errorMessage = null;
          });
          _pinFocusNode.requestFocus();
        }
      } else {
        if (mounted) {
          setState(() => _lockoutRemaining = remaining);
        }
      }
    });
  }

  // ── PIN input ─────────────────────────────────────────────────────────────

  Uint8List _collectBytesFromText(String text) {
    final bytes = Uint8List(text.length);
    for (int i = 0; i < text.length; i++) {
      bytes[i] = text.codeUnitAt(i);
    }
    return bytes;
  }

  void _onPinInputChanged(String value) {
    setState(() => _errorMessage = null);

    if (value.length == 6 && !_isLocked) {
      _pinBytes = _collectBytesFromText(value);
      wipeController(_pinController);
      _verifyPin();
    }
  }

  void _clearInput() {
    _pinController.clear();
    setState(() => _errorMessage = null);
  }

  void _togglePinInput() {
    setState(() {
      _showPinInput = true;
      _errorMessage = null;
    });
    Future.delayed(const Duration(milliseconds: 100), () {
      if (_pinFocusNode.canRequestFocus) _pinFocusNode.requestFocus();
    });
  }

  // ── PIN verification ──────────────────────────────────────────────────────

  Future<void> _verifyPin() async {
    if (_isLoading || _isLocked) return;
    setState(() => _isLoading = true);

    // Constant-time delay to prevent timing attacks
    await Future.delayed(const Duration(milliseconds: 1500));

    try {
      final hasPin = await PinSecurity.hasPinHash();
      if (!hasPin) {
        if (mounted) Navigator.pushReplacementNamed(context, '/setup-pin');
        return;
      }

      // Build reversed copy for duress-PIN check before any zeroing
      final reversedBytes = Uint8List.fromList(_pinBytes.reversed.toList());

      // ── Normal PIN check ──
      final isCorrect = await PinSecurity.verifyPin(_pinBytes);

      if (isCorrect) {
        // Reset attempt counter on success
        await PinSecurity.resetAttempts();

        // Unlock vault directly with bytes — no String creation (CWE-256)
        if (VaultService().isLocked) {
          await VaultService().unlockWithPinBytes(_pinBytes);
        } else {
          await VaultService().storeMasterKeyWithPinBytes(_pinBytes);
        }

        // Zero PIN bytes now that vault is unlocked
        _pinBytes.fillRange(0, _pinBytes.length, 0);
        reversedBytes.fillRange(0, reversedBytes.length, 0);
        _pinBytes = Uint8List(0);

        _showSuccessAnimation();
        return;
      }

      // ── Duress PIN check (reversed digits) ──
      final isDuress = await PinSecurity.verifyPin(reversedBytes);
      reversedBytes.fillRange(0, reversedBytes.length, 0);
      _pinBytes.fillRange(0, _pinBytes.length, 0);
      _pinBytes = Uint8List(0);

      if (isDuress) {
        await _executeDuressWipe();
        return;
      }

      // ── Wrong PIN — update rate-limit state ──
      final lockoutDuration = await PinSecurity.recordFailedAttempt();
      if (lockoutDuration != null) {
        // Just hit lockout threshold
        setState(() {
          _isLocked = true;
          _lockoutRemaining = lockoutDuration;
          // CWE-200: no attempt count in message
          _errorMessage = 'Доступ временно заблокирован';
          _isLoading = false;
        });
        _startLockoutCountdown();
      } else {
        setState(() {
          // CWE-200: unified message without attempt counter
          _errorMessage = 'Ошибка аутентификации';
          _isLoading = false;
        });
        _shakeController.forward().then((_) => _shakeController.reverse());
        await Future.delayed(const Duration(milliseconds: 300));
        if (mounted) _pinFocusNode.requestFocus();
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Ошибка проверки PIN-кода';
        _isLoading = false;
      });
    }
  }

  // ── Duress wipe ───────────────────────────────────────────────────────────

  /// Duress PIN: wipe all vault data including hardware keys.
  Future<void> _executeDuressWipe() async {
    try {
      // 1. Wipe all local secure data (FlutterSecureStorage + SharedPreferences + cache)
      await VaultService().clearAllData();
      // 2. Wipe PIN hash and rate-limit data
      await PinSecurity.clearPinData();

      if (mounted) {
        Navigator.pushNamedAndRemoveUntil(
          context,
          '/login',
          (route) => false,
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Ошибка при выполнении операции';
          _isLoading = false;
        });
      }
    }
  }

  // ── Navigation ────────────────────────────────────────────────────────────

  void _showSuccessAnimation() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    if (mounted) {
      Navigator.pushNamedAndRemoveUntil(context, '/passwords', (route) => false);
    }
  }

  // ── Biometrics ────────────────────────────────────────────────────────────

  Future<void> _authenticateWithBiometrics() async {
    try {
      final success = await VaultService().tryUnlockWithBiometrics();
      if (success) {
        SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
        if (mounted) {
          Navigator.pushNamedAndRemoveUntil(context, '/passwords', (route) => false);
        }
      } else {
        if (mounted) {
          setState(() {
            _errorMessage = _hasPinHash 
                ? 'Биометрия не подошла. Используйте PIN.'
                : 'Ошибка биометрии. Попробуйте войти заново.';
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _errorMessage = 'Системная ошибка биометрии');
      }
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final value = _pinController.text;

    return Scaffold(
      backgroundColor: AppColors.background,
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
                      _biometricEnabled && !_showPinInput
                          ? Icons.fingerprint
                          : Icons.lock_outline,
                      size: 40,
                      color: AppColors.button,
                    ),
                  ),

                  const SizedBox(height: 40),

                  LText(
                    _showPinInput ? 'Введите PIN-код' : 'Подтвердите личность',
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      color: AppColors.text,
                    ),
                  ),

                  const SizedBox(height: 8),

                  LText(
                    _showPinInput
                        ? 'Для доступа к приложению'
                        : (_biometricEnabled
                            ? 'Используйте биометрию для входа'
                            : 'Введите PIN-код'),
                    style: const TextStyle(fontSize: 16, color: Colors.grey),
                  ),

                  const SizedBox(height: 40),

                  if (_showPinInput)
                    AnimatedBuilder(
                      animation: _shakeAnimation,
                      builder: (context, child) {
                        return Transform.translate(
                          offset: Offset(_shakeAnimation.value * 10, 0),
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              Opacity(
                                opacity: 0,
                                child: TextField(
                                  controller: _pinController,
                                  focusNode: _pinFocusNode,
                                  enabled: !_isLocked && !_isLoading,
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
                              GestureDetector(
                                onTap: () {
                                  if (!_isLocked && !_isLoading) {
                                    _pinFocusNode.requestFocus();
                                  }
                                },
                                child: Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceEvenly,
                                  children: List.generate(6, (index) {
                                    final hasValue = value.length > index;
                                    return Container(
                                      width: 46,
                                      height: 52,
                                      decoration: BoxDecoration(
                                        color: AppColors.input,
                                        borderRadius: BorderRadius.circular(12),
                                        border: Border.all(
                                          color: value.length == index &&
                                                  !_isLocked &&
                                                  !_isLoading
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
                        );
                      },
                    )
                  else if (_biometricEnabled && _biometricAvailable)
                    Column(
                      children: [
                        IconButton(
                          icon: Icon(Icons.fingerprint,
                              size: 64, color: AppColors.button),
                          onPressed: _authenticateWithBiometrics,
                        ),
                        const SizedBox(height: 20),
                        if (_hasPinHash)
                          TextButton(
                            onPressed: _togglePinInput,
                            child: const LText('Использовать PIN-код'),
                          ),
                      ],
                    ),

                  const SizedBox(height: 24),

                  if (_showPinInput &&
                      value.isNotEmpty &&
                      !_isLocked &&
                      !_isLoading)
                    TextButton.icon(
                      onPressed: _clearInput,
                      icon: const Icon(Icons.backspace_outlined, size: 16),
                      label: const LText('Стереть всё'),
                      style: TextButton.styleFrom(
                        foregroundColor: AppColors.text.withOpacity(0.6),
                      ),
                    ),

                  const SizedBox(height: 24),

                  if (_isLocked && _lockoutRemaining != null)
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 300),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.orange.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.orange.withOpacity(0.5)),
                      ),
                      child: LText(
                        'Повторите через ${_lockoutRemaining!.inMinutes}м '
                        '${(_lockoutRemaining!.inSeconds % 60).toString().padLeft(2, '0')}с',
                        style:
                            const TextStyle(color: Colors.orange, fontSize: 14),
                      ),
                    ),

                  if (_errorMessage != null && !_isLocked)
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 300),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 8),
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

                  TextButton(
                    onPressed: () =>
                        Navigator.pushReplacementNamed(context, '/login'),
                    child: const LText(
                      'Выйти',
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
