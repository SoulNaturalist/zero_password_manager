import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../config/app_config.dart';
import '../services/auth_token_storage.dart';
import '../theme/colors.dart';
import '../l10n/l_text.dart';
import 'biometric_service.dart';
import 'pin_security.dart';

enum HiddenFolderAuthMethod { biometric, pin, totp }

/// Session-based unlock service for hidden folders.
///
/// • Supports biometric / PIN / TOTP verification.
/// • Unlock expires after [_sessionDuration] and on app background.
/// • Falls back to the best available method if the saved one is unavailable.
class HiddenFolderService with WidgetsBindingObserver {
  HiddenFolderService._() {
    WidgetsBinding.instance.addObserver(this);
  }

  static final HiddenFolderService instance = HiddenFolderService._();

  static const _methodKey = 'hidden_folder_auth_method';
  static const _sessionDuration = Duration(minutes: 5);

  DateTime? _unlockedUntil;

  bool get isUnlocked {
    final until = _unlockedUntil;
    return until != null && DateTime.now().isBefore(until);
  }

  void _grantUnlock([Duration duration = _sessionDuration]) {
    _unlockedUntil = DateTime.now().add(duration);
  }

  void lock() {
    _unlockedUntil = null;
  }

  // ── Lifecycle: lock on background ───────────────────────────────────────

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      lock();
    }
  }

  // ── Persisted method preference ──────────────────────────────────────────

  Future<HiddenFolderAuthMethod> getSavedMethod() async {
    final prefs = await SharedPreferences.getInstance();
    final idx = prefs.getInt(_methodKey);
    if (idx == null || idx >= HiddenFolderAuthMethod.values.length) {
      return HiddenFolderAuthMethod.totp;
    }
    return HiddenFolderAuthMethod.values[idx];
  }

  Future<void> saveMethod(HiddenFolderAuthMethod method) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_methodKey, method.index);
  }

  // ── Availability checks ─────────────────────────────────────────────────

  Future<Map<HiddenFolderAuthMethod, bool>> getAvailableMethods({
    required bool totpEnabled,
  }) async {
    final biometric = BiometricService();
    final biometricOk = await biometric.isAvailable() &&
        await biometric.isBiometricEnabled();
    final pinOk = await PinSecurity.hasPinHash();
    return {
      HiddenFolderAuthMethod.biometric: biometricOk,
      HiddenFolderAuthMethod.pin: pinOk,
      HiddenFolderAuthMethod.totp: totpEnabled,
    };
  }

  Future<bool> hasAnyMethodAvailable({required bool totpEnabled}) async {
    final methods = await getAvailableMethods(totpEnabled: totpEnabled);
    return methods.values.any((v) => v);
  }

  Future<HiddenFolderAuthMethod?> getBestAvailableMethod({
    required bool totpEnabled,
  }) async {
    final methods = await getAvailableMethods(totpEnabled: totpEnabled);
    for (final m in HiddenFolderAuthMethod.values) {
      if (methods[m] == true) return m;
    }
    return null;
  }

  // ── Self-check TOTP status from server ──────────────────────────────────

  Future<bool> _fetchTotpEnabled() async {
    try {
      final token = await AuthTokenStorage.readAccessToken();
      if (token == null || token.isEmpty) return false;
      final response = await http.get(
        Uri.parse(AppConfig.profileUrl),
        headers: {'Authorization': 'Bearer $token'},
      );
      if (response.statusCode == 200) {
        return jsonDecode(response.body)['totp_enabled'] ?? false;
      }
    } catch (_) {}
    return false;
  }

  // ── Unified verify with fallback ────────────────────────────────────────

  Future<bool> verifyWithSelectedMethod(BuildContext context) async {
    final totpEnabled = await _fetchTotpEnabled();
    final savedMethod = await getSavedMethod();
    final available = await getAvailableMethods(totpEnabled: totpEnabled);

    HiddenFolderAuthMethod method;
    if (available[savedMethod] == true) {
      method = savedMethod;
    } else {
      final fallback = await getBestAvailableMethod(totpEnabled: totpEnabled);
      if (fallback == null) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              backgroundColor: AppColors.error,
              content: const LText('Нет доступных методов защиты'),
            ),
          );
        }
        return false;
      }
      method = fallback;
    }

    final success = await _verifyByMethod(method, context);
    if (success) _grantUnlock();
    return success;
  }

  Future<bool> _verifyByMethod(
    HiddenFolderAuthMethod method,
    BuildContext context,
  ) {
    switch (method) {
      case HiddenFolderAuthMethod.biometric:
        return _verifyBiometric();
      case HiddenFolderAuthMethod.pin:
        return _verifyPin(context);
      case HiddenFolderAuthMethod.totp:
        return _verifyTotpDialog(context);
    }
  }

  // ── Biometric ───────────────────────────────────────────────────────────

  Future<bool> _verifyBiometric() async {
    // BiometricService.authenticate returns String? (the stored secret).
    // Non-null means authentication passed.
    final result = await BiometricService().authenticate(
      reason: 'Подтвердите для доступа к скрытым папкам',
    );
    return result != null;
  }

  // ── PIN ─────────────────────────────────────────────────────────────────

  Future<bool> _verifyPin(BuildContext context) async {
    final lockout = await PinSecurity.getLockoutRemaining();
    if (lockout != null) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: AppColors.error,
            content: LText('PIN заблокирован на ${lockout.inMinutes} мин.'),
          ),
        );
      }
      return false;
    }

    final controller = TextEditingController();
    try {
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
                child: Icon(Icons.pin, color: AppColors.button, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: LText(
                  'PIN-код',
                  style: TextStyle(
                    color: AppColors.text,
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              LText(
                'Введите PIN для доступа к скрытым папкам',
                style: TextStyle(
                  color: AppColors.text.withOpacity(0.7),
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 20),
              TextField(
                controller: controller,
                keyboardType: TextInputType.number,
                obscureText: true,
                autofocus: true,
                textAlign: TextAlign.center,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(6),
                ],
                style: TextStyle(
                  color: AppColors.text,
                  fontSize: 26,
                  letterSpacing: 10,
                  fontWeight: FontWeight.bold,
                ),
                decoration: InputDecoration(
                  counterText: '',
                  hintText: '••••',
                  hintStyle: TextStyle(
                    color: AppColors.text.withOpacity(0.3),
                    letterSpacing: 10,
                  ),
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
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: LText(
                'Отмена',
                style: TextStyle(color: AppColors.text.withOpacity(0.6)),
              ),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.button,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              onPressed: () async {
                final pin = controller.text.trim();
                if (pin.isEmpty) return;
                final pinBytes = Uint8List.fromList(utf8.encode(pin));
                final ok = await PinSecurity.verifyPin(pinBytes);
                if (ok) {
                  await PinSecurity.resetAttempts();
                } else {
                  await PinSecurity.recordFailedAttempt();
                }
                if (ctx.mounted) Navigator.pop(ctx, ok);
              },
              child: const LText('Подтвердить'),
            ),
          ],
        ),
      );
      return verified == true;
    } finally {
      controller.dispose();
    }
  }

  // ── TOTP (server verification) ──────────────────────────────────────────

  Future<bool> _verifyTotpDialog(BuildContext context) async {
    final controller = TextEditingController();
    try {
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
              Expanded(
                child: LText(
                  'TOTP-код',
                  style: TextStyle(
                    color: AppColors.text,
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              LText(
                'Введите TOTP-код для доступа к скрытым папкам',
                style: TextStyle(
                  color: AppColors.text.withOpacity(0.7),
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 20),
              TextField(
                controller: controller,
                keyboardType: TextInputType.number,
                autofocus: true,
                textAlign: TextAlign.center,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(6),
                ],
                style: TextStyle(
                  color: AppColors.text,
                  fontSize: 26,
                  letterSpacing: 10,
                  fontWeight: FontWeight.bold,
                ),
                decoration: InputDecoration(
                  counterText: '',
                  hintText: '000000',
                  hintStyle: TextStyle(
                    color: AppColors.text.withOpacity(0.3),
                    letterSpacing: 10,
                  ),
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
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: LText(
                'Отмена',
                style: TextStyle(color: AppColors.text.withOpacity(0.6)),
              ),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.button,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              onPressed: () async {
                final code = controller.text.trim();
                if (code.length != 6) {
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    SnackBar(
                      backgroundColor: AppColors.error,
                      content: const LText('Введите 6-значный код'),
                    ),
                  );
                  return;
                }
                final ok = await verifyTotp(code);
                if (ctx.mounted) Navigator.pop(ctx, ok);
              },
              child: const LText('Подтвердить'),
            ),
          ],
        ),
      );
      return verified == true;
    } finally {
      controller.dispose();
    }
  }

  // ── Server TOTP call ────────────────────────────────────────────────────

  Future<bool> verifyTotp(String code) async {
    try {
      final token = await AuthTokenStorage.readAccessToken();
      if (token == null || token.isEmpty) return false;

      final response = await http.post(
        Uri.parse(AppConfig.verifyHiddenFoldersTotpUrl),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({'otp': code.trim()}),
      );
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }
}

// ── Helper: method display info ──────────────────────────────────────────

String hiddenFolderMethodName(HiddenFolderAuthMethod method) {
  switch (method) {
    case HiddenFolderAuthMethod.biometric:
      return 'Биометрия';
    case HiddenFolderAuthMethod.pin:
      return 'PIN-код';
    case HiddenFolderAuthMethod.totp:
      return 'TOTP';
  }
}

IconData hiddenFolderMethodIcon(HiddenFolderAuthMethod method) {
  switch (method) {
    case HiddenFolderAuthMethod.biometric:
      return Icons.fingerprint;
    case HiddenFolderAuthMethod.pin:
      return Icons.pin;
    case HiddenFolderAuthMethod.totp:
      return Icons.security;
  }
}
