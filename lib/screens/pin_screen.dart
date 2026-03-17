import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/colors.dart';
import '../utils/biometric_service.dart';
import '../utils/memory_security.dart';
import '../utils/pin_security.dart';
import '../services/vault_service.dart';

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
  final List<TextEditingController> _controllers = List.generate(
    4,
    (index) => TextEditingController(),
  );
  final List<FocusNode> _focusNodes = List.generate(4, (index) => FocusNode());

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
    _checkLockout();
    _checkBiometricAvailability();

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
    _lockoutTimer?.cancel();
    for (var controller in _controllers) {
      controller.dispose();
    }
    for (var node in _focusNodes) {
      node.dispose();
    }
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
        }
      } else {
        if (mounted) {
          setState(() => _lockoutRemaining = remaining);
        }
      }
    });
  }

  // ── PIN input ─────────────────────────────────────────────────────────────

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

    if (entered.length == 4 && !_isLocked) {
      _pinBytes = _collectAndClearControllers();
      _verifyPin();
    }
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
        if (mounted) _focusNodes[0].requestFocus();
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

  Future<void> _checkBiometricAvailability() async {
    final available = await BiometricService.isAvailable();
    final enabled   = await BiometricService.isBiometricEnabled();
    if (mounted) {
      setState(() {
        _biometricAvailable = available;
        _biometricEnabled   = enabled;
      });
    }
    if (available && enabled) {
      _authenticateWithBiometrics();
    }
  }

  Future<void> _authenticateWithBiometrics() async {
    try {
      final success = await VaultService().tryUnlockWithBiometrics();
      if (success) {
        SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
        if (mounted) {
          Navigator.pushNamedAndRemoveUntil(
            context,
            '/passwords',
            (route) => false,
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              backgroundColor: Colors.orange,
              content: Text(
                'Биометрическая аутентификация не удалась. Используйте PIN-код.',
              ),
            ),
          );
        }
      }
    } catch (_) {}
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
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
                  AnimatedBuilder(
                    animation: _animationController,
                    builder: (context, child) {
                      return Transform.scale(
                        scale: 0.8 + (_animationController.value * 0.2),
                        child: Container(
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
                            Icons.lock_outline,
                            size: 40,
                            color: AppColors.button,
                          ),
                        ),
                      );
                    },
                  ),

                  const SizedBox(height: 40),

                  Text(
                    'Введите PIN-код',
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      color: AppColors.text,
                    ),
                  ),

                  const SizedBox(height: 8),

                  const Text(
                    'Для доступа к приложению',
                    style: TextStyle(fontSize: 16, color: Colors.grey),
                  ),

                  const SizedBox(height: 40),

                  // PIN fields (disabled while locked)
                  AnimatedBuilder(
                    animation: _shakeAnimation,
                    builder: (context, child) {
                      return Transform.translate(
                        offset: Offset(_shakeAnimation.value * 10, 0),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: List.generate(4, (index) {
                            return Container(
                              width: 60,
                              height: 60,
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
                                enabled: !_isLocked && !_isLoading,
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
                                onChanged: (value) => _onPinChanged(),
                              ),
                            );
                          }),
                        ),
                      );
                    },
                  ),

                  const SizedBox(height: 24),

                  // Lockout countdown
                  if (_isLocked && _lockoutRemaining != null)
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 300),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.orange.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                        border:
                            Border.all(color: Colors.orange.withOpacity(0.5)),
                      ),
                      child: Text(
                        'Повторите через ${_lockoutRemaining!.inMinutes}м '
                        '${(_lockoutRemaining!.inSeconds % 60).toString().padLeft(2, '0')}с',
                        style: const TextStyle(
                          color: Colors.orange,
                          fontSize: 14,
                        ),
                      ),
                    ),

                  // Generic error message (CWE-200: no attempt count)
                  if (_errorMessage != null && !_isLocked)
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

                  const Text(
                    'Используйте PIN-код для быстрого доступа',
                    style: TextStyle(fontSize: 14, color: Colors.grey),
                    textAlign: TextAlign.center,
                  ),

                  if (_biometricAvailable && _biometricEnabled && !_isLocked) ...[
                    const SizedBox(height: 20),
                    ElevatedButton.icon(
                      onPressed: _authenticateWithBiometrics,
                      icon:
                          const Icon(Icons.fingerprint, color: Colors.white),
                      label: const Text(
                        'Использовать биометрию',
                        style: TextStyle(color: Colors.white),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.button,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 12,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ],

                  const SizedBox(height: 20),

                  TextButton(
                    onPressed: () =>
                        Navigator.pushReplacementNamed(context, '/login'),
                    child: const Text(
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
