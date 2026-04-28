import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Secure PIN hashing and rate-limiting using PBKDF2-HMAC-SHA256.
/// All data is stored in FlutterSecureStorage (hardware-backed on Android).
///
/// CVE mitigations:
///   CWE-922 — pin_hash stored in FlutterSecureStorage, not SharedPreferences
///   CWE-327 — PBKDF2 with OWASP-recommended 600k iterations (was 100k pre-audit)
///             + unique 16-byte salt (no rainbow tables)
///   CWE-284 — failed-attempt counter + lockout timestamp persisted in secure storage
///
/// Legacy hashes created with 100 000 iterations are auto-migrated on the
/// next successful unlock (see [verifyPin]).
class PinSecurity {
  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(
      encryptedSharedPreferences: false,  // Use KeyStore+SharedPreferences (API 18+, more compatible)
    ),
    iOptions: IOSOptions(
      // _this_device_only blocks iCloud Keychain backup of the PIN hash.
      accessibility: KeychainAccessibility.first_unlock_this_device_only,
    ),
  );

  // Storage keys
  static const _saltKey       = 'pin_kdf_salt';
  static const _hashKey       = 'pin_kdf_hash';
  static const _iterationsKey = 'pin_kdf_iterations';
  static const _attemptsKey   = 'pin_attempts';
  static const _lockoutKey    = 'pin_lockout_until';

  // Lockout policy
  static const int maxAttempts = 3;
  static const Duration lockoutDuration = Duration(minutes: 15);

  // ── PBKDF2 derivation ─────────────────────────────────────────────────────

  /// OWASP 2023+ recommended minimum for PBKDF2-HMAC-SHA256.
  static const int currentIterations = 600000;
  static const int legacyIterations  = 100000;

  /// Derives a 32-byte key from raw PIN bytes, a salt and an iteration count.
  static Future<List<int>> _derive(
    List<int> pinBytes,
    List<int> salt,
    int iterations,
  ) async {
    final pbkdf2 = Pbkdf2(
      macAlgorithm: Hmac.sha256(),
      iterations: iterations,
      bits: 256,
    );
    final sk = await pbkdf2.deriveKey(
      secretKey: SecretKey(pinBytes),
      nonce: salt,
    );
    return sk.extractBytes();
  }

  static Future<int> _readIterations() async {
    final raw = await _storage.read(key: _iterationsKey);
    return int.tryParse(raw ?? '') ?? legacyIterations;
  }

  // ── Storage operations ─────────────────────────────────────────────────────

  /// Hashes the PIN with a fresh random salt and stores both in SecureStorage.
  /// Must be called during PIN setup (setup_pin_screen.dart).
  static Future<void> storePinHash(Uint8List pinBytes) async {
    final rng  = Random.secure();
    final salt = List<int>.generate(16, (_) => rng.nextInt(256));
    final hash = await _derive(pinBytes, salt, currentIterations);
    await _storage.write(key: _saltKey, value: base64.encode(salt));
    await _storage.write(key: _hashKey, value: base64.encode(hash));
    await _storage.write(key: _iterationsKey, value: '$currentIterations');
    // Reset any leftover rate-limit state
    await _storage.delete(key: _attemptsKey);
    await _storage.delete(key: _lockoutKey);
  }

  /// Returns true if a PIN hash is stored (i.e. PIN was set up).
  static Future<bool> hasPinHash() async =>
      (await _storage.read(key: _hashKey)) != null;

  /// Verifies raw PIN bytes against the stored PBKDF2 hash.
  /// Uses constant-time comparison to prevent timing attacks.
  ///
  /// On successful verification of a *legacy* hash (100k iterations) the hash
  /// is transparently re-derived with the current 600k iteration count and
  /// re-written to secure storage — no user-visible re-prompt required.
  static Future<bool> verifyPin(Uint8List pinBytes) async {
    final saltB64 = await _storage.read(key: _saltKey);
    final hashB64 = await _storage.read(key: _hashKey);
    if (saltB64 == null || hashB64 == null) return false;

    final salt       = base64.decode(saltB64);
    final stored     = base64.decode(hashB64);
    final iterations = await _readIterations();
    final derived    = await _derive(pinBytes, salt, iterations);
    final ok         = _constantTimeEqual(derived, stored);

    if (ok && iterations < currentIterations) {
      // Auto-migrate legacy 100k hash → 600k. Same salt, same PIN, new hash.
      final fresh = await _derive(pinBytes, salt, currentIterations);
      await _storage.write(key: _hashKey, value: base64.encode(fresh));
      await _storage.write(key: _iterationsKey, value: '$currentIterations');
    }
    return ok;
  }

  /// Permanently removes all PIN data (called on duress wipe or logout).
  static Future<void> clearPinData() async {
    await _storage.delete(key: _saltKey);
    await _storage.delete(key: _hashKey);
    await _storage.delete(key: _iterationsKey);
    await _storage.delete(key: _attemptsKey);
    await _storage.delete(key: _lockoutKey);
  }

  // ── Rate limiting (CWE-284) ────────────────────────────────────────────────

  /// Returns the remaining lockout duration, or null if not locked.
  static Future<Duration?> getLockoutRemaining() async {
    final val = await _storage.read(key: _lockoutKey);
    if (val == null) return null;
    final epochMs = int.tryParse(val) ?? 0;
    if (epochMs == 0) return null;
    final remaining =
        DateTime.fromMillisecondsSinceEpoch(epochMs).difference(DateTime.now());
    return remaining.isNegative ? null : remaining;
  }

  /// Records one failed attempt.
  /// Returns the active lockout Duration when the threshold is reached, else null.
  static Future<Duration?> recordFailedAttempt() async {
    final raw      = await _storage.read(key: _attemptsKey) ?? '0';
    final attempts = (int.tryParse(raw) ?? 0) + 1;
    await _storage.write(key: _attemptsKey, value: '$attempts');

    if (attempts >= maxAttempts) {
      final lockUntil =
          DateTime.now().add(lockoutDuration).millisecondsSinceEpoch;
      await _storage.write(key: _lockoutKey, value: '$lockUntil');
      await _storage.write(key: _attemptsKey, value: '0');
      return lockoutDuration;
    }
    return null;
  }

  /// Returns current failed attempt count (0 if none).
  static Future<int> getAttemptCount() async {
    final raw = await _storage.read(key: _attemptsKey) ?? '0';
    return int.tryParse(raw) ?? 0;
  }

  /// Resets the attempt counter and clears any lockout after successful auth.
  static Future<void> resetAttempts() async {
    await _storage.write(key: _attemptsKey, value: '0');
    await _storage.delete(key: _lockoutKey);
  }

  // ── Internal ───────────────────────────────────────────────────────────────

  /// Constant-time byte comparison — prevents timing side-channels.
  static bool _constantTimeEqual(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    int diff = 0;
    for (int i = 0; i < a.length; i++) {
      diff |= a[i] ^ b[i];
    }
    return diff == 0;
  }
}
