import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/api_service.dart';
import '../utils/biometric_service.dart';
import '../utils/memory_security.dart';
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
  final _storage = const FlutterSecureStorage();

  static const _storageKey = 'encrypted_master_key';
  static const _saltKey    = 'master_key_salt';

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

  static Future<SecretKey> generateMasterKey(String password, String salt) async =>
      CryptoService().deriveMasterKey(password, salt);

  static Future<void> saveMasterKey(SecretKey masterKey) async =>
      VaultService().setKey(masterKey);

  // ── Unlock / lock ────────────────────────────────────────────────────────────

  /// Derives master key from password+salt. Stores in biometric storage if enabled.
  Future<void> unlock(String password, String salt) async {
    _masterKey = await _crypto.deriveMasterKey(password, salt);

    if (await BiometricService.isBiometricEnabled()) {
      final keyBytes = await _masterKey!.extractBytes();
      await BiometricService.storeBiometricSecret(base64.encode(keyBytes));
      // Wipe extracted bytes immediately after use
      (keyBytes as Uint8List).fillRange(0, keyBytes.length, 0);
    }
  }

  Future<bool> tryUnlockWithBiometrics() async {
    if (!await BiometricService.isBiometricEnabled()) return false;
    final secretB64 = await BiometricService.authenticate();
    if (secretB64 != null) {
      _masterKey = SecretKey(base64.decode(secretB64));
      return true;
    }
    return false;
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
    final keyBytes    = await _masterKey!.extractBytes();
    final keyB64      = base64.encode(keyBytes);
    final encryptedKey = await _crypto.encrypt(pinKey, keyB64);

    // Wipe key bytes after encryption
    (keyBytes as Uint8List).fillRange(0, keyBytes.length, 0);
    // Native wipe of temporary base64 string
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
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> clearAllData() async {
    lock();

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('token');
    await prefs.remove('pin_hash');
    await prefs.remove('pin_code');
    await prefs.remove(_saltKey);

    await _storage.delete(key: _storageKey);
    await _storage.deleteAll();

    await _cache.clearCache();
    await BiometricService.resetBiometricSettings();
  }

  // ── Password list — METADATA ONLY (no payload ever decrypted here) ───────────

  /// Fetches all passwords and decrypts ONLY metadata (name, login, site_url).
  /// The `encrypted_payload` field is preserved as-is for on-demand decryption.
  /// No plaintext password is ever held in the returned list.
  Future<List<Map<String, dynamic>>> loadPasswordList() async {
    if (_masterKey == null) throw Exception('Vault is locked');

    final response = await ApiService.get(AppConfig.passwordsUrl);
    if (response.statusCode != 200) throw Exception('Failed to fetch passwords');

    final rawList = json.decode(response.body) as List<dynamic>;
    final result  = <Map<String, dynamic>>[];

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

  // ── Payload decryption (on-demand only) ──────────────────────────────────────

  /// Decrypts a payload into a [SecureBuffer].
  /// **Caller MUST call [SecureBuffer.wipe] when done with the data.**
  Future<SecureBuffer> decryptPayloadSecure(String encryptedB64) async {
    if (_masterKey == null) throw Exception('Vault is locked');
    final plaintext = await _crypto.decrypt(_masterKey!, encryptedB64);
    return SecureBuffer.fromBytes(plaintext.codeUnits);
  }

  /// Decrypts a payload to a plain String (use only for edit/save — not display).
  Future<String> decryptPayload(String encryptedB64) async {
    if (_masterKey == null) throw Exception('Vault is locked');
    return await _crypto.decrypt(_masterKey!, encryptedB64);
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
    final encMeta       = await _crypto.encryptMetadata(_masterKey!, {'site_url': url, 'site_login': login, 'name': name});
    final encPayload    = await _crypto.encrypt(_masterKey!, password);
    final encNotes      = notes       != null ? await _crypto.encrypt(_masterKey!, notes)       : null;
    final encSeed       = seedPhrase  != null ? await _crypto.encrypt(_masterKey!, seedPhrase)  : null;

    final response = await ApiService.post(AppConfig.passwordsUrl, body: {
      'site_hash':              siteHash,
      'encrypted_metadata':     encMeta,
      'encrypted_payload':      encPayload,
      'notes_encrypted':        encNotes,
      'seed_phrase_encrypted':  encSeed,
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
    int? folderId,
  }) async {
    if (_masterKey == null) throw Exception('Vault is locked');

    final siteHash      = await _crypto.computeSiteHash(_masterKey!, url);
    final encMeta       = await _crypto.encryptMetadata(_masterKey!, {'site_url': url, 'site_login': login, 'name': name});
    final encPayload    = await _crypto.encrypt(_masterKey!, password);
    final encNotes      = notes       != null ? await _crypto.encrypt(_masterKey!, notes)       : null;
    final encSeed       = seedPhrase  != null ? await _crypto.encrypt(_masterKey!, seedPhrase)  : null;

    final response = await ApiService.put('${AppConfig.passwordsUrl}/$id', body: {
      'site_hash':              siteHash,
      'encrypted_metadata':     encMeta,
      'encrypted_payload':      encPayload,
      'notes_encrypted':        encNotes,
      'seed_phrase_encrypted':  encSeed,
      'folder_id':              folderId,
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

      items.add({
        'site_hash':          await _crypto.computeSiteHash(_masterKey!, url),
        'encrypted_metadata': await _crypto.encryptMetadata(_masterKey!, {'site_url': url, 'site_login': login, 'name': name}),
        'encrypted_payload':  await _crypto.encrypt(_masterKey!, pwd),
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
        final meta = await _crypto.decryptMetadata(
          _masterKey!,
          entry['encrypted_metadata'] as String,
        );
        entry['title']    = meta['name']       ?? meta['site_url'] ?? '';
        entry['subtitle'] = meta['site_login'] ?? '';
        entry['site_url'] = meta['site_url']   ?? '';
      }
    } catch (_) {
      entry['title']    = '(encrypted)';
      entry['subtitle'] = '';
    }

    // Never put decrypted payload in the list — keep it encrypted for on-demand use
    return entry;
  }
}
