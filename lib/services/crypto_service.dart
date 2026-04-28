import 'dart:convert';
import 'package:cryptography/cryptography.dart';
import 'dart:typed_data';

class CryptoService {
  static final CryptoService _instance = CryptoService._internal();
  factory CryptoService() => _instance;
  CryptoService._internal();

  final _aesGcm = AesGcm.with256bits();
  final _hmacSha256 = Hmac.sha256();

  /// OWASP 2023+ recommended minimum for PBKDF2-HMAC-SHA256.
  /// Bitwarden uses 600 000 since 2023; we match that as the new default.
  static const int defaultKdfIterations = 600000;

  /// Lower bound for legacy vaults registered before the 600k upgrade.
  /// Any value LOWER than this is rejected — without a floor, a malicious
  /// backend could downgrade a registering client to e.g. 1 000 iterations
  /// and offline-brute the resulting weak vault key. The floor is enforced
  /// client-side because the server is the very party we don't trust here.
  static const int legacyKdfIterations = 100000;
  static const int minAcceptableKdfIterations = 100000;

  static int _validateIterations(int iterations) {
    if (iterations < minAcceptableKdfIterations) {
      throw ArgumentError(
        'KDF downgrade rejected: iterations=$iterations is below the '
        'client floor ($minAcceptableKdfIterations). The server may be '
        'compromised — refusing to derive a weak vault key.',
      );
    }
    return iterations;
  }

  /// Derives a 256-bit key from a master password and salt using PBKDF2-SHA256.
  /// `iterations` MUST match the value used at registration time
  /// (returned by the server alongside the salt).
  Future<SecretKey> deriveMasterKey(
    String password,
    String saltB64, {
    int iterations = defaultKdfIterations,
  }) async {
    final salt = base64.decode(saltB64);
    final pbkdf2 = Pbkdf2(
      macAlgorithm: Hmac.sha256(),
      iterations: _validateIterations(iterations),
      bits: 256,
    );
    return await pbkdf2.deriveKeyFromPassword(password: password, nonce: salt);
  }

  /// Derives a 256-bit key directly from raw bytes (CWE-256: avoids String creation).
  Future<SecretKey> deriveMasterKeyFromBytes(
    List<int> passwordBytes,
    String saltB64, {
    int iterations = defaultKdfIterations,
  }) async {
    final salt = base64.decode(saltB64);
    final pbkdf2 = Pbkdf2(
      macAlgorithm: Hmac.sha256(),
      iterations: _validateIterations(iterations),
      bits: 256,
    );
    return await pbkdf2.deriveKey(secretKey: SecretKey(passwordBytes), nonce: salt);
  }

  /// Generates a deterministic site hash (Blind Encryption) using HMAC-SHA256.
  /// Server uses this as the lookup key, never seeing the actual site URL.
  Future<String> computeSiteHash(SecretKey masterKey, String siteUrl) async {
    final mac = await _hmacSha256.calculateMac(
      utf8.encode(siteUrl.toLowerCase().trim()),
      secretKey: masterKey,
    );
    return base64.encode(mac.bytes);
  }

  // ── AAD-bound AES-GCM (v2) ─────────────────────────────────────────────────
  //
  // Threat model: a malicious or compromised backend can swap fields between
  // a user's records (e.g. paste record A's encrypted_payload onto record B's
  // row). Plain AES-GCM with a constant or empty AAD does not bind a
  // ciphertext to its row context, so the swap decrypts cleanly and the user
  // sees the wrong password.
  //
  // v2 binds each ciphertext to a per-record context (typically derived from
  // the site_hash, which the server cannot forge — it's an HMAC under the
  // master key). A v2 blob is tagged with the literal prefix `v2:` so it is
  // unambiguously distinguishable from a v1 base64 string (`:` is never
  // produced by base64). Reads transparently fall back to v1 for legacy data.

  static const String _v2Prefix = 'v2:';

  List<int> _aadFor(String context) =>
      utf8.encode('vault-data:v2:$context');

  /// Encrypts [plaintext] under [key] and binds the ciphertext to [context]
  /// (e.g. `'payload:' + siteHash`). The result is prefixed with `v2:` so
  /// readers can route to bound decryption automatically.
  Future<String> encryptBound(
    SecretKey key,
    String plaintext,
    String context,
  ) async {
    final clearText = utf8.encode(plaintext);
    final secretBox = await _aesGcm.encrypt(
      clearText,
      secretKey: key,
      aad: _aadFor(context),
    );

    final combined = Uint8List(
      secretBox.nonce.length +
          secretBox.cipherText.length +
          secretBox.mac.bytes.length,
    );
    int offset = 0;
    combined.setAll(offset, secretBox.nonce);
    offset += secretBox.nonce.length;
    combined.setAll(offset, secretBox.cipherText);
    offset += secretBox.cipherText.length;
    combined.setAll(offset, secretBox.mac.bytes);

    return _v2Prefix + base64.encode(combined);
  }

  /// Encrypts data using AES-GCM. Legacy (v1) format with empty AAD.
  /// Returns base64(nonce + ciphertext + tag). Used for shared/ephemeral
  /// blobs that have no stable record context to bind to.
  Future<String> encrypt(SecretKey key, String plaintext) async {
    final clearText = utf8.encode(plaintext);
    final secretBox = await _aesGcm.encrypt(clearText, secretKey: key);

    final combined = Uint8List(
      secretBox.nonce.length +
          secretBox.cipherText.length +
          secretBox.mac.bytes.length,
    );
    int offset = 0;

    combined.setAll(offset, secretBox.nonce);
    offset += secretBox.nonce.length;

    combined.setAll(offset, secretBox.cipherText);
    offset += secretBox.cipherText.length;

    combined.setAll(offset, secretBox.mac.bytes);

    return base64.encode(combined);
  }

  /// Internal raw GCM open. Accepts either the legacy `base64(...)` form or a
  /// `v2:` prefixed bound form; for v2 the caller MUST supply the same
  /// context that was used at encrypt time, otherwise the GCM tag check
  /// fails — exactly what we want when the backend tries to swap rows.
  Future<Uint8List> _openGcm(
    SecretKey key,
    String encryptedB64,
    List<int>? aad,
  ) async {
    final data = base64.decode(encryptedB64);
    const nonceLen = 12;
    const macLen = 16;
    if (data.length < nonceLen + macLen) {
      throw Exception('Invalid encrypted data length');
    }
    final nonce = data.sublist(0, nonceLen);
    final ciphertext = data.sublist(nonceLen, data.length - macLen);
    final macBytes = data.sublist(data.length - macLen);
    final secretBox = SecretBox(ciphertext, nonce: nonce, mac: Mac(macBytes));
    final clearText = await _aesGcm.decrypt(
      secretBox,
      secretKey: key,
      aad: aad ?? const <int>[],
    );
    return Uint8List.fromList(clearText);
  }

  /// Decrypts data, auto-detecting v1 vs v2.
  /// For v2 ciphertexts, [context] MUST be supplied and match the value used
  /// at encrypt time. For v1 ciphertexts (legacy), [context] is ignored.
  Future<Uint8List> decryptToBytes(
    SecretKey key,
    String encryptedB64, {
    String? context,
  }) async {
    if (encryptedB64.startsWith(_v2Prefix)) {
      if (context == null) {
        throw StateError(
          'v2 ciphertext requires a binding context — refusing to decrypt '
          'without it (this would silently degrade authentication).',
        );
      }
      return _openGcm(key, encryptedB64.substring(_v2Prefix.length),
          _aadFor(context));
    }
    return _openGcm(key, encryptedB64, null);
  }

  /// Decrypts to UTF-8 String; see [decryptToBytes] for [context] semantics.
  Future<String> decrypt(
    SecretKey key,
    String encryptedB64, {
    String? context,
  }) async {
    final clearText = await decryptToBytes(key, encryptedB64, context: context);
    try {
      return utf8.decode(clearText);
    } finally {
      clearText.fillRange(0, clearText.length, 0);
    }
  }

  /// Encrypts a full metadata object bound to [context] (typically
  /// `'meta:' + siteHash`). Always emits v2.
  Future<String> encryptMetadata(
    SecretKey key,
    Map<String, dynamic> metadata, {
    required String context,
  }) async {
    return await encryptBound(key, json.encode(metadata), context);
  }

  /// Decrypts a metadata object. Auto-detects v1/v2; for v2 [context] is
  /// required and is checked by GCM.
  Future<Map<String, dynamic>> decryptMetadata(
    SecretKey key,
    String encryptedB64, {
    String? context,
  }) async {
    final decrypted = await decrypt(key, encryptedB64, context: context);
    return json.decode(decrypted);
  }
}
