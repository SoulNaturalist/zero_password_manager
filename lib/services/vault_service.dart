import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/api_service.dart';
import '../utils/biometric_service.dart';
import '../utils/memory_security.dart';
import 'auth_token_storage.dart';
import 'crypto_service.dart';
import 'cache_service.dart';
import '../config/app_config.dart';

class VaultService {
  static final VaultService _instance = VaultService._internal();
  factory VaultService() => _instance;
  VaultService._internal();

  SecretKey? _masterKey;
  final _crypto = CryptoService();
  final _cache  = CacheService();
  final _storage = const FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: false),
    // _this_device_only ⇒ blob never lands in iCloud Keychain backup.
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.first_unlock_this_device_only,
    ),
  );

  static const _storageKey = 'encrypted_master_key';
  static const _saltKey    = 'master_key_salt';
  static const _legacyNoPinMasterKey = 'master_key_no_pin';
  static const _legacyNoPinSaltKey = 'master_key_no_pin_salt';

  // ── Key state ────────────────────────────────────────────────────────────────

  SecretKey? get masterKey => _masterKey;
  bool get isLocked => _masterKey == null;

  void setKey(SecretKey key) => _masterKey = key;

  void lock() {
    _masterKey = null;
    _cache.clearCache();
  }

  // ── Static helpers (kept for compatibility with login screens) ───────────────

  static String generateRandomSalt() {
    final rng   = Random.secure();
    final bytes = Uint8List.fromList(List.generate(16, (_) => rng.nextInt(256)));
    return base64.encode(bytes);
  }

  static Future<SecretKey> generateMasterKey(
    String password,
    String salt, {
    int? kdfIterations,
  }) async =>
      CryptoService().deriveMasterKey(
        password,
        salt,
        iterations: kdfIterations ?? CryptoService.defaultKdfIterations,
      );

  static Future<void> saveMasterKey(SecretKey masterKey) async =>
      VaultService().setKey(masterKey);

  // ── Unlock / lock ────────────────────────────────────────────────────────────

  /// Derives master key from password+salt. Stores in biometric storage if enabled.
  ///
  /// `kdfIterations` MUST be the value the server returned alongside the salt
  /// (NULL on legacy accounts → falls back to 100 000 for backwards compat).
  /// Mismatched iterations silently produce a wrong key, which then fails
  /// AES-GCM auth on the first decrypt — DO NOT guess.
  Future<void> unlock(String password, String salt, {int? kdfIterations}) async {
    final iterations = kdfIterations ?? CryptoService.legacyKdfIterations;
    _masterKey = await _crypto.deriveMasterKey(password, salt, iterations: iterations);

    if (await BiometricService().isBiometricEnabled()) {
      final keyBytes = Uint8List.fromList(await _masterKey!.extractBytes());
      await BiometricService().storeBiometricSecret(base64.encode(keyBytes));
      // Wipe extracted bytes immediately after use
      keyBytes.fillRange(0, keyBytes.length, 0);
    }
  }

  /// Bytes-only variant of [unlock] that never materialises the password as a
  /// Dart `String`. Mitigates the CVE-2023-32784 class of memory-dump attacks.
  Future<void> unlockFromBytes(
    Uint8List passwordBytes,
    String salt, {
    int? kdfIterations,
  }) async {
    final iterations = kdfIterations ?? CryptoService.legacyKdfIterations;
    _masterKey = await _crypto.deriveMasterKeyFromBytes(
      passwordBytes,
      salt,
      iterations: iterations,
    );

    if (await BiometricService().isBiometricEnabled()) {
      final keyBytes = Uint8List.fromList(await _masterKey!.extractBytes());
      await BiometricService().storeBiometricSecret(base64.encode(keyBytes));
      keyBytes.fillRange(0, keyBytes.length, 0);
    }
  }

  Future<bool> tryUnlockWithBiometrics() async {
    final biometric = BiometricService();
    if (!await biometric.isBiometricEnabled()) return false;
    final secretB64 = await biometric.authenticate();
    if (secretB64 != null) {
      _masterKey = SecretKey(base64.decode(secretB64));
      return true;
    }
    return false;
  }

  Map<String, dynamic> _buildEncryptedMetadata({
    required String name,
    required String url,
    required String login,
    String? seedPhrase,
  }) {
    final metadata = <String, dynamic>{
      'site_url': url,
      'site_login': login,
      'name': name,
    };
    final trimmedSeed = seedPhrase?.trim();
    if (trimmedSeed != null && trimmedSeed.isNotEmpty) {
      metadata['seed_phrase'] = trimmedSeed;
    }
    return metadata;
  }

  Future<void> storeMasterKeyWithPin(String pin) async {
    if (_masterKey == null) return;

    final prefs = await SharedPreferences.getInstance();
    String? salt = prefs.getString(_saltKey);
    if (salt == null) {
      final rng = Random.secure();
      final saltBytes = Uint8List.fromList(List.generate(16, (_) => rng.nextInt(256)));
      salt = base64.encode(saltBytes);
      await prefs.setString(_saltKey, salt);
    }

    final pinKey      = await _crypto.deriveMasterKey(pin, salt);
    final keyBytes    = Uint8List.fromList(await _masterKey!.extractBytes());
    final keyB64      = base64.encode(keyBytes);
    final encryptedKey = await _crypto.encrypt(pinKey, keyB64);

    // Wipe key bytes after encryption
    keyBytes.fillRange(0, keyBytes.length, 0);
    // Native wipe of temporary base64 string
    await nativeWipe(keyB64);

    await _storage.write(key: _storageKey, value: encryptedKey);
  }

  /// Stores master key encrypted with PIN bytes (avoids String creation).
  /// CWE-256: PIN bytes are never converted to a Dart String.
  Future<void> storeMasterKeyWithPinBytes(Uint8List pinBytes) async {
    if (_masterKey == null) throw StateError('Vault is locked — master key not loaded');

    final prefs = await SharedPreferences.getInstance();
    String? salt = prefs.getString(_saltKey);
    if (salt == null) {
      final rng = Random.secure();
      final saltBytes = Uint8List.fromList(List.generate(16, (_) => rng.nextInt(256)));
      salt = base64.encode(saltBytes);
      await prefs.setString(_saltKey, salt);
    }

    final pinKey       = await _crypto.deriveMasterKeyFromBytes(pinBytes, salt);
    final keyBytes     = Uint8List.fromList(await _masterKey!.extractBytes());
    final keyB64       = base64.encode(keyBytes);
    final encryptedKey = await _crypto.encrypt(pinKey, keyB64);

    keyBytes.fillRange(0, keyBytes.length, 0);
    await nativeWipe(keyB64);

    await _storage.write(key: _storageKey, value: encryptedKey);
  }

  Future<bool> unlockWithPin(String pin) async {
    final encryptedKey = await _storage.read(key: _storageKey);
    if (encryptedKey == null) return false;

    final prefs = await SharedPreferences.getInstance();
    final salt  = prefs.getString(_saltKey);
    if (salt == null) return false;

    try {
      final pinKey       = await _crypto.deriveMasterKey(pin, salt);
      final decryptedB64 = await _crypto.decrypt(pinKey, encryptedKey);
      _masterKey = SecretKey(base64.decode(decryptedB64));
      
      // Auto-repair biometric secret if enabled
      if (await BiometricService().isBiometricEnabled()) {
        final keyBytes = Uint8List.fromList(await _masterKey!.extractBytes());
        await BiometricService().storeBiometricSecret(base64.encode(keyBytes));
        keyBytes.fillRange(0, keyBytes.length, 0);
      }
      
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Unlocks vault using raw PIN bytes (avoids String creation).
  /// CWE-256: PIN never leaves Uint8List form.
  Future<bool> unlockWithPinBytes(Uint8List pinBytes) async {
    final encryptedKey = await _storage.read(key: _storageKey);
    if (encryptedKey == null) return false;

    final prefs = await SharedPreferences.getInstance();
    final salt  = prefs.getString(_saltKey);
    if (salt == null) return false;

    try {
      final pinKey       = await _crypto.deriveMasterKeyFromBytes(pinBytes, salt);
      final decryptedB64 = await _crypto.decrypt(pinKey, encryptedKey);
      _masterKey = SecretKey(base64.decode(decryptedB64));
      
      // Auto-repair biometric secret if enabled
      if (await BiometricService().isBiometricEnabled()) {
        final keyBytes = Uint8List.fromList(await _masterKey!.extractBytes());
        await BiometricService().storeBiometricSecret(base64.encode(keyBytes));
        keyBytes.fillRange(0, keyBytes.length, 0);
      }
      
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> clearNoPinMasterKey() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_legacyNoPinMasterKey);
    await prefs.remove(_legacyNoPinSaltKey);
    await prefs.remove('pin_code');
  }

  Future<void> clearAllData() async {
    lock();

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('pin_hash');
    await prefs.remove('pin_code');
    await prefs.remove(_saltKey);

    await AuthTokenStorage.clearAccessToken();
    await _storage.delete(key: _storageKey);
    await _storage.deleteAll();

    await _cache.clearCache();
    await BiometricService().resetBiometricSettings();
  }

  // ── Password list — METADATA ONLY (no payload ever decrypted here) ───────────

  /// Fetches all passwords and decrypts ONLY metadata (name, login, site_url).
  /// The `encrypted_payload` field is preserved as-is for on-demand decryption.
  /// No plaintext password is ever held in the returned list.
  ///
  /// On success the raw server response is persisted in the local Hive cache so
  /// the vault remains readable when the server is unreachable or the token has
  /// just expired (e.g. after CSV import and app restart).
  Future<List<Map<String, dynamic>>> loadPasswordList() async {
    if (_masterKey == null) throw Exception('Vault is locked');

    List<dynamic>? rawList;

    try {
      final response = await ApiService.get(AppConfig.passwordsUrl);
      if (response.statusCode == 200) {
        rawList = json.decode(response.body) as List<dynamic>;
        // Persist encrypted server response for offline access
        await _cache.cachePasswordList(rawList.cast<Map<String, dynamic>>());
      }
    } catch (_) {
      // Network error — fall through to cache below
    }

    // Fall back to local cache when server is unavailable
    if (rawList == null) {
      final cached = _cache.getCachedPasswordList();
      if (cached != null) {
        rawList = cached;
      } else {
        throw Exception('Failed to fetch passwords and no local cache available');
      }
    }

    final result = <Map<String, dynamic>>[];
    for (final item in rawList) {
      result.add(await _decryptMetadataOnly(item as Map<String, dynamic>));
    }
    return result;
  }

  /// Fetches a single password entry and decrypts its metadata only.
  /// Returns the entry with `encrypted_payload` intact for lazy decryption.
  Future<Map<String, dynamic>> loadSingleEntry(int id) async {
    if (_masterKey == null) throw Exception('Vault is locked');

    final response = await ApiService.get('${AppConfig.passwordsUrl}/$id');
    if (response.statusCode != 200) throw Exception('Entry not found');

    return await _decryptMetadataOnly(
      json.decode(response.body) as Map<String, dynamic>,
    );
  }

  // ── Per-record AAD binding helpers ───────────────────────────────────────────
  //
  // The site_hash is HMAC-SHA256(masterKey, lower(url)) — the server cannot
  // forge it. Threading it through AAD makes a server-side row-swap fail GCM
  // authentication. For legacy v1 ciphertexts the context is silently ignored
  // (CryptoService.decrypt routes by the `v2:` prefix).

  static String _payloadCtx(String siteHash) => 'payload:$siteHash';
  static String _metaCtx(String siteHash)    => 'meta:$siteHash';
  static String _notesCtx(String siteHash)   => 'notes:$siteHash';

  // ── Payload decryption (on-demand only) ──────────────────────────────────────

  /// Decrypts a payload into a [SecureBuffer].
  /// **Caller MUST call [SecureBuffer.wipe] when done with the data.**
  ///
  /// [siteHash] — pass the row's site_hash for v2 ciphertexts. v1 (legacy)
  /// ignores it. Omitting it for a v2 blob throws by design — we refuse to
  /// silently drop the row-binding check.
  Future<SecureBuffer> decryptPayloadSecure(
    String encryptedB64, {
    String? siteHash,
  }) async {
    if (_masterKey == null) throw Exception('Vault is locked');
    final plaintextBytes = await _crypto.decryptToBytes(
      _masterKey!,
      encryptedB64,
      context: siteHash != null ? _payloadCtx(siteHash) : null,
    );
    try {
      return SecureBuffer.fromBytes(plaintextBytes);
    } finally {
      plaintextBytes.fillRange(0, plaintextBytes.length, 0);
    }
  }

  /// Decrypts a payload to a plain String (use only for edit/save — not display).
  Future<String> decryptPayload(
    String encryptedB64, {
    String? siteHash,
  }) async {
    if (_masterKey == null) throw Exception('Vault is locked');
    return await _crypto.decrypt(
      _masterKey!,
      encryptedB64,
      context: siteHash != null ? _payloadCtx(siteHash) : null,
    );
  }

  /// Notes-specific decryption. Same v1/v2 rules as [decryptPayload].
  Future<SecureBuffer> decryptNotesSecure(
    String encryptedB64, {
    String? siteHash,
  }) async {
    if (_masterKey == null) throw Exception('Vault is locked');
    final bytes = await _crypto.decryptToBytes(
      _masterKey!,
      encryptedB64,
      context: siteHash != null ? _notesCtx(siteHash) : null,
    );
    try {
      return SecureBuffer.fromBytes(bytes);
    } finally {
      bytes.fillRange(0, bytes.length, 0);
    }
  }

  // ── Write operations ─────────────────────────────────────────────────────────

  Future<void> addPassword({
    required String name,
    required String url,
    required String login,
    required String password,
    String? notes,
    String? seedPhrase,
    int? folderId,
  }) async {
    if (_masterKey == null) throw Exception('Vault is locked');

    final siteHash      = await _crypto.computeSiteHash(_masterKey!, url);
    final normalizedSeed = seedPhrase?.trim();
    final hasSeedPhrase = normalizedSeed != null && normalizedSeed.isNotEmpty;
    final encMeta       = await _crypto.encryptMetadata(
      _masterKey!,
      _buildEncryptedMetadata(
        name: name,
        url: url,
        login: login,
        seedPhrase: normalizedSeed,
      ),
      context: _metaCtx(siteHash),
    );
    final encPayload    = await _crypto.encryptBound(
      _masterKey!,
      password,
      _payloadCtx(siteHash),
    );
    final encNotes      = notes != null
        ? await _crypto.encryptBound(_masterKey!, notes, _notesCtx(siteHash))
        : null;

    final response = await ApiService.post(AppConfig.passwordsUrl, body: {
      'site_hash':              siteHash,
      'encrypted_metadata':     encMeta,
      'encrypted_payload':      encPayload,
      'notes_encrypted':        encNotes,
      'has_seed_phrase':        hasSeedPhrase,
      'folder_id':              folderId,
    });
    
    // Wipe transient plaintext strings
    await nativeWipe(password);
    if (notes != null) await nativeWipe(notes);
    if (seedPhrase != null) await nativeWipe(seedPhrase);

    if (response.statusCode != 201) throw Exception('Failed to save password');
  }

  Future<void> updatePassword({
    required int id,
    required String name,
    required String url,
    required String login,
    required String password,
    String? notes,
    String? seedPhrase,
  }) async {
    if (_masterKey == null) throw Exception('Vault is locked');

    final siteHash      = await _crypto.computeSiteHash(_masterKey!, url);
    final normalizedSeed = seedPhrase?.trim();
    final hasSeedPhrase = normalizedSeed != null && normalizedSeed.isNotEmpty;
    final encMeta       = await _crypto.encryptMetadata(
      _masterKey!,
      _buildEncryptedMetadata(
        name: name,
        url: url,
        login: login,
        seedPhrase: normalizedSeed,
      ),
      context: _metaCtx(siteHash),
    );
    final encPayload    = await _crypto.encryptBound(
      _masterKey!,
      password,
      _payloadCtx(siteHash),
    );
    final encNotes      = notes != null
        ? await _crypto.encryptBound(_masterKey!, notes, _notesCtx(siteHash))
        : null;

    final response = await ApiService.put('${AppConfig.passwordsUrl}/$id', body: {
      'site_hash':              siteHash,
      'encrypted_metadata':     encMeta,
      'encrypted_payload':      encPayload,
      'notes_encrypted':        encNotes,
      'has_seed_phrase':        hasSeedPhrase,
    });

    // Wipe transient plaintext strings
    await nativeWipe(password);
    if (notes != null) await nativeWipe(notes);
    if (seedPhrase != null) await nativeWipe(seedPhrase);

    if (response.statusCode != 200) throw Exception('Failed to update password');
  }

  Future<void> importPasswordsBatch(List<Map<String, String>> entries) async {
    if (_masterKey == null) throw Exception('Vault is locked');

    final items = <Map<String, dynamic>>[];
    for (final entry in entries) {
      final url   = entry['url'] ?? '';
      final login = entry['username'] ?? '';
      final pwd   = entry['password'] ?? '';
      final name  = url.isNotEmpty ? url : (login.isNotEmpty ? login : 'Imported');
      final siteHash = await _crypto.computeSiteHash(_masterKey!, url);

      items.add({
        'site_hash':          siteHash,
        'encrypted_metadata': await _crypto.encryptMetadata(
          _masterKey!,
          _buildEncryptedMetadata(name: name, url: url, login: login),
          context: _metaCtx(siteHash),
        ),
        'encrypted_payload':  await _crypto.encryptBound(
          _masterKey!,
          pwd,
          _payloadCtx(siteHash),
        ),
        'has_2fa':            false,
        'has_seed_phrase':    false,
      });
    }

    final response = await ApiService.post(AppConfig.importPasswordsUrl, body: {'items': items});
    if (response.statusCode != 201) throw Exception('Failed to import: ${response.body}');
    await _cache.clearCache();
  }

  // ── Private ─────────────────────────────────────────────────────────────────

  Future<Map<String, dynamic>> _decryptMetadataOnly(
    Map<String, dynamic> item,
  ) async {
    final entry = Map<String, dynamic>.from(item);

    // Strip any accidental plaintext password before we do anything else
    entry.remove('password');
    entry.remove('plain_password');

    try {
      if (entry['encrypted_metadata'] != null) {
        final siteHash = entry['site_hash'] as String?;
        final meta = await _crypto.decryptMetadata(
          _masterKey!,
          entry['encrypted_metadata'] as String,
          context: siteHash != null ? _metaCtx(siteHash) : null,
        );
        entry['title']    = meta['name']       ?? meta['site_url'] ?? '';
        entry['subtitle'] = meta['site_login'] ?? '';
        entry['site_url'] = meta['site_url']   ?? '';
        entry['has_seed_phrase'] = (meta['seed_phrase'] is String) &&
            (meta['seed_phrase'] as String).trim().isNotEmpty;
      }
    } catch (_) {
      // Decrypt failure here is also the malicious-server-swap signal: a v2
      // metadata blob that was moved onto a different site_hash row will fail
      // GCM authentication. We surface a placeholder rather than crash so the
      // user can still see *which* row is suspect.
      entry['title']    = '(encrypted)';
      entry['subtitle'] = '';
    }

    // Never put decrypted payload in the list — keep it encrypted for on-demand use
    return entry;
  }

  Future<SecureBuffer?> decryptSeedPhraseFromMetadataSecure(
    String? encryptedMetadata, {
    String? siteHash,
  }) async {
    if (_masterKey == null) throw Exception('Vault is locked');
    if (encryptedMetadata == null || encryptedMetadata.isEmpty) return null;

    final meta = await _crypto.decryptMetadata(
      _masterKey!,
      encryptedMetadata,
      context: siteHash != null ? _metaCtx(siteHash) : null,
    );
    final seedPhrase = meta['seed_phrase'];
    if (seedPhrase is! String || seedPhrase.trim().isEmpty) return null;
    final bytes = Uint8List.fromList(utf8.encode(seedPhrase));
    await nativeWipe(seedPhrase);
    return SecureBuffer.fromBytes(bytes);
  }

  Future<String?> decryptSeedPhraseFromMetadata(
    String? encryptedMetadata, {
    String? siteHash,
  }) async {
    final buffer = await decryptSeedPhraseFromMetadataSecure(
      encryptedMetadata,
      siteHash: siteHash,
    );
    if (buffer == null) return null;
    final bytes = buffer.getBytesCopy();
    try {
      return utf8.decode(bytes);
    } finally {
      bytes.fillRange(0, bytes.length, 0);
      buffer.wipe();
    }
  }

  // ── Account-level seed phrase (user profile, not per-record) ────────────────
  // Bound to the `account-seed` namespace to keep it cryptographically
  // separated from per-record blobs.

  static const String _accountSeedCtx = 'account-seed';

  Future<String> encryptAccountSeedPhrase(String phrase) async {
    if (_masterKey == null) throw Exception('Vault is locked');
    return _crypto.encryptBound(_masterKey!, phrase.trim(), _accountSeedCtx);
  }

  Future<SecureBuffer> decryptAccountSeedPhraseSecure(String encryptedB64) async {
    if (_masterKey == null) throw Exception('Vault is locked');
    final plaintextBytes = await _crypto.decryptToBytes(
      _masterKey!,
      encryptedB64,
      context: _accountSeedCtx,
    );
    try {
      return SecureBuffer.fromBytes(plaintextBytes);
    } finally {
      plaintextBytes.fillRange(0, plaintextBytes.length, 0);
    }
  }
}
