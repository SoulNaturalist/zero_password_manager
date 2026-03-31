import 'package:local_auth/local_auth.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart';

/// Biometric authentication service.
///
/// Strategy:
///   1. [local_auth] checks biometric availability and performs the system prompt.
///   2. [FlutterSecureStorage] stores the master key (hardware-backed Android
///      Keystore / iOS Secure Enclave) under [_masterKeyStorageKey].
///   3. The app authenticates with biometrics first, then reads from secure
///      storage — this is the industry-standard approach for Flutter apps.
///
/// This pattern is more reliable than flutter_locker's combined auth+store
/// because FlutterSecureStorage uses the Keystore directly without requiring
/// BiometricPrompt's CryptoObject binding, which can fail on some devices.
class BiometricService {
  static const String _biometricKey = 'biometric_enabled';
  static const String _masterKeyStorageKey = 'biometric_master_key';

  static final BiometricService _instance = BiometricService._();
  factory BiometricService() => _instance;

  BiometricService._() {
    _initEnabledNotifier();
  }

  final ValueNotifier<bool> isEnabledNotifier = ValueNotifier<bool>(false);

  Future<void> _initEnabledNotifier() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      isEnabledNotifier.value = (prefs.getBool(_biometricKey) ?? false) && await isAvailable();
    } catch (_) {
      isEnabledNotifier.value = false;
    }
  }

  static final _auth = LocalAuthentication();
  static final _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: false),
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
  );

  // ── Availability ───────────────────────────────────────────────────────────

  /// Returns true if the device supports biometrics AND has at least one
  /// enrolled biometric (fingerprint / face).
  Future<bool> isAvailable() async {
    try {
      final isSupported = await _auth.isDeviceSupported();
      if (!isSupported) return false;
      final canCheck = await _auth.canCheckBiometrics;
      if (!canCheck) return false;
      final available = await _auth.getAvailableBiometrics();
      return available.isNotEmpty;
    } catch (e) {
      return false;
    }
  }

  /// Returns the list of enrolled biometric types for UI display.
  Future<List<BiometricType>> getAvailableBiometrics() async {
    try {
      return await _auth.getAvailableBiometrics();
    } catch (_) {
      return [];
    }
  }

  // ── Enabled flag ───────────────────────────────────────────────────────────

  Future<bool> isBiometricEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    final enabled = prefs.getBool(_biometricKey) ?? false;
    if (enabled != isEnabledNotifier.value) {
      isEnabledNotifier.value = enabled;
    }
    return enabled;
  }

  Future<void> setBiometricEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_biometricKey, enabled);
    isEnabledNotifier.value = enabled;
  }

  // ── Store master key (call after enabling biometrics) ──────────────────────

  /// Store [value] (base64-encoded master key) in hardware-backed secure storage.
  /// Does NOT require biometric auth to store — only to retrieve.
  /// Returns true on success.
  Future<bool> storeBiometricSecret(String value) async {
    try {
      await _storage.write(key: _masterKeyStorageKey, value: value);
      return true;
    } catch (e) {
      return false;
    }
  }

  // ── Authenticate and retrieve master key ───────────────────────────────────

  /// Show biometric prompt. On success, retrieve and return the stored secret.
  /// Returns null if auth failed, was cancelled, or no secret is stored.
  Future<String?> authenticate({
    String reason = 'Подтвердите отпечаток пальца для входа',
  }) async {
    try {
      final didAuth = await _auth.authenticate(
        localizedReason: reason,
        options: const AuthenticationOptions(
          biometricOnly: false, // allow device PIN fallback
          stickyAuth: true, // don't cancel on app switch
          useErrorDialogs: true,
        ),
      );
      if (!didAuth) return null;

      // Biometric passed — read the secret from secure storage
      final secret = await _storage.read(key: _masterKeyStorageKey);
      return secret;
    } catch (e) {
      return null;
    }
  }

  // ── Reset ──────────────────────────────────────────────────────────────────

  Future<void> resetBiometricSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_biometricKey);
    isEnabledNotifier.value = false;
    try {
      await _storage.delete(key: _masterKeyStorageKey);
    } catch (_) {}
  }

  // ── Diagnostic info (for debug/test screen) ────────────────────────────────

  Future<Map<String, dynamic>> getDiagnosticInfo() async {
    try {
      final isSupported = await _auth.isDeviceSupported();
      final canCheck = await _auth.canCheckBiometrics;
      final available = await _auth.getAvailableBiometrics();
      final isEnabled = await isBiometricEnabled();

      return {
        'canAuthenticate': canCheck && available.isNotEmpty,
        'isEnabled': isEnabled,
        'systemStatus': (canCheck && available.isNotEmpty) ? 'Доступна' : 'Недоступна',
        'canUseBiometrics': canCheck && available.isNotEmpty && isEnabled,
        'canCheckBiometrics': canCheck,
        'isDeviceSupported': isSupported,
        'totalAvailableMethods': available.length,
        'biometricDetails': {
          if (available.contains(BiometricType.fingerprint)) 'fingerprint': 'Отпечаток пальца',
          if (available.contains(BiometricType.face)) 'face': 'Распознавание лица',
          if (available.contains(BiometricType.iris)) 'iris': 'Сетчатка глаза',
        },
        'availableBiometrics': available.map((b) => b.name).toList(),
      };
    } catch (e) {
      return {
        'error': e.toString(),
        'canAuthenticate': false,
        'isEnabled': false,
        'systemStatus': 'Ошибка при проверке',
        'canUseBiometrics': false,
        'canCheckBiometrics': false,
        'isDeviceSupported': false,
        'totalAvailableMethods': 0,
        'biometricDetails': {},
        'availableBiometrics': [],
      };
    }
  }

  /// For test screen — verify biometric is working end-to-end.
  Future<bool> forceEnableBiometrics() async {
    final available = await isAvailable();
    if (!available) return false;
    final stored = await storeBiometricSecret('test_probe');
    if (!stored) return false;
    final result = await authenticate(reason: 'Тест биометрии');
    await _storage.delete(key: _masterKeyStorageKey);
    if (result != null) {
      await setBiometricEnabled(true);
      return true;
    }
    return false;
  }
}
