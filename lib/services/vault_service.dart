import 'dart:math';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/api_service.dart';
import '../utils/biometric_service.dart';
import 'crypto_service.dart';
import 'cache_service.dart';
import '../config/app_config.dart';
import 'dart:convert';
import 'dart:typed_data';

class VaultService {
  static final VaultService _instance = VaultService._internal();
  factory VaultService() => _instance;
  VaultService._internal();

  SecretKey? _masterKey;
  final _crypto = CryptoService();
  final _cache = CacheService();
  final _storage = const FlutterSecureStorage();

  static const _storageKey = 'encrypted_master_key';
  static const _saltKey = 'master_key_salt';

  /// Generates a random 16-byte salt for key derivation.
  static String generateRandomSalt() {
    final random = Random.secure();
    final bytes = Uint8List.fromList(List.generate(16, (_) => random.nextInt(256)));
    return base64.encode(bytes);
  }

  /// Static helper for generating a master key (matching user template).
  static Future<SecretKey> generateMasterKey(String password, String salt) async {
    return await CryptoService().deriveMasterKey(password, salt);
  }

  /// Static helper for saving a master key (matching user template).
  /// Note: Real implementation might prefer PIN-based storage call.
  static Future<void> saveMasterKey(SecretKey masterKey) async {
    VaultService().setKey(masterKey);
    // Note: To persist this between sessions, storeMasterKeyWithPin must be called later.
  }

  bool get isLocked => _masterKey == null;

  void setKey(SecretKey key) {
    _masterKey = key;
  }

  void lock() {
    _masterKey = null;
    _cache.clearCache();
  }

  /// Encrypts and stores the master key using a key derived from the PIN.
  Future<void> storeMasterKeyWithPin(String pin) async {
    if (_masterKey == null) return;

    // Use a unique salt for PIN-based encryption
    final prefs = await SharedPreferences.getInstance();
    String? salt = prefs.getString(_saltKey);
    if (salt == null) {
      final random = Uint8List(16);
      // In a real app, use a proper CSPRNG.
      // cryptography's Pbkdf2 takes a nonce/salt.
      salt = base64.encode(DateTime.now().toIso8601String().codeUnits.take(16).toList());
      await prefs.setString(_saltKey, salt);
    }

    final pinKey = await _crypto.deriveMasterKey(pin, salt);
    final keyBytes = await _masterKey!.extractBytes();
    final encryptedKey = await _crypto.encrypt(pinKey, base64.encode(keyBytes));

    await _storage.write(key: _storageKey, value: encryptedKey);
  }

  /// Restores the master key using the PIN.
  Future<bool> unlockWithPin(String pin) async {
    final encryptedKey = await _storage.read(key: _storageKey);
    if (encryptedKey == null) return false;

    final prefs = await SharedPreferences.getInstance();
    final salt = prefs.getString(_saltKey);
    if (salt == null) return false;

    try {
      final pinKey = await _crypto.deriveMasterKey(pin, salt);
      final decryptedB64 = await _crypto.decrypt(pinKey, encryptedKey);
      _masterKey = SecretKey(base64.decode(decryptedB64));
      return true;
    } catch (e) {
      return false;
    }
  }

  /// Derives the master key and unlocks the vault.
  Future<void> unlock(String password, String salt) async {
    _masterKey = await _crypto.deriveMasterKey(password, salt);

    // If biometrics are enabled, store the master key securely
    if (await BiometricService.isBiometricEnabled()) {
      final keyBytes = await _masterKey!.extractBytes();
      await BiometricService.storeBiometricSecret(base64.encode(keyBytes));
    }
  }

  /// Attempts to unlock the vault using stored biometrics.
  Future<bool> tryUnlockWithBiometrics() async {
    if (!await BiometricService.isBiometricEnabled()) return false;

    final secretB64 = await BiometricService.authenticate();
    if (secretB64 != null) {
      _masterKey = SecretKey(base64.decode(secretB64));
      return true;
    }
    return false;
  }

  /// Securely clears all vault-related data (for logout).
  Future<void> clearAllData() async {
    // 1. Clear in-memory state
    lock();

    // 2. Clear SharedPreferences
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('token');
    await prefs.remove('pin_hash');
    await prefs.remove('pin_code'); // Legacy cleanup
    await prefs.remove(_saltKey);

    // 3. Clear Secure Storage
    await _storage.delete(key: _storageKey);
    await _storage.deleteAll(); // Safety net

    // 4. Clear Cache
    await _cache.clearCache();

    // 5. Reset Biometrics
    await BiometricService.resetBiometricSettings();
  }

  /// Fetches all passwords from the server, decrypts them, and updates the local cache.
  Future<List<Map<String, dynamic>>> syncVault() async {
    if (_masterKey == null) throw Exception("Vault is locked");

    final response = await ApiService.get(AppConfig.passwordsUrl);
    if (response.statusCode != 200)
      throw Exception("Failed to fetch passwords");

    final List<dynamic> encryptedList = json.decode(response.body);
    final List<Map<String, dynamic>> decryptedList = [];

    for (var item in encryptedList) {
      final decrypted = await _decryptPasswordItem(item);
      decryptedList.add(decrypted);
    }

    await _cache.cacheAll(decryptedList);
    return decryptedList;
  }

  /// Adds a new password item. Encrypts data before sending it to the server.
  Future<void> addPassword({
    required String name,
    required String url,
    required String login,
    required String password,
    String? notes,
    String? seedPhrase,
    int? folderId,
  }) async {
    if (_masterKey == null) throw Exception("Vault is locked");

    final siteHash = await _crypto.computeSiteHash(_masterKey!, url);

    final metadata = {'site_url': url, 'site_login': login, 'name': name};

    final encryptedMetadata = await _crypto.encryptMetadata(
      _masterKey!,
      metadata,
    );
    final encryptedPayload = await _crypto.encrypt(_masterKey!, password);
    final encryptedNotes =
        notes != null ? await _crypto.encrypt(_masterKey!, notes) : null;
    final encryptedSeed =
        seedPhrase != null
            ? await _crypto.encrypt(_masterKey!, seedPhrase)
            : null;

    final body = {
      'site_hash': siteHash,
      'encrypted_metadata': encryptedMetadata,
      'encrypted_payload': encryptedPayload,
      'notes_encrypted': encryptedNotes,
      'seed_phrase_encrypted': encryptedSeed, // Updated field name
      'folder_id': folderId,
    };

    final response = await ApiService.post(AppConfig.passwordsUrl, body: body);
    if (response.statusCode != 201) throw Exception("Failed to save password");

    // Cache locally as well
    final newPassword = json.decode(response.body);
    await _cache.cachePassword(siteHash, newPassword);
  }

  /// Bulk imports passwords after client-side encryption.
  Future<void> importPasswordsBatch(List<Map<String, String>> entries) async {
    if (_masterKey == null) throw Exception("Vault is locked");

    final List<Map<String, dynamic>> encryptedItems = [];

    for (var entry in entries) {
      final url = entry['url'] ?? '';
      final login = entry['username'] ?? '';
      final password = entry['password'] ?? '';
      final name = url.isNotEmpty ? url : (login.isNotEmpty ? login : "Imported");

      final siteHash = await _crypto.computeSiteHash(_masterKey!, url);
      final metadata = {'site_url': url, 'site_login': login, 'name': name};

      final encryptedMetadata = await _crypto.encryptMetadata(_masterKey!, metadata);
      final encryptedPayload = await _crypto.encrypt(_masterKey!, password);

      encryptedItems.add({
        'site_hash': siteHash,
        'encrypted_metadata': encryptedMetadata,
        'encrypted_payload': encryptedPayload,
        'has_2fa': false,
        'has_seed_phrase': false,
      });
    }

    final response = await ApiService.post(
      AppConfig.importPasswordsUrl,
      body: {'items': encryptedItems},
    );

    if (response.statusCode != 201) {
      throw Exception("Failed to import passwords: ${response.body}");
    }

    // Clear cache to force re-sync after bulk import
    await _cache.clearCache();
  }

  /// Updates an existing password item.
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
    if (_masterKey == null) throw Exception("Vault is locked");

    final siteHash = await _crypto.computeSiteHash(_masterKey!, url);

    final metadata = {'site_url': url, 'site_login': login, 'name': name};

    final encryptedMetadata = await _crypto.encryptMetadata(
      _masterKey!,
      metadata,
    );
    final encryptedPayload = await _crypto.encrypt(_masterKey!, password);
    final encryptedNotes =
        notes != null ? await _crypto.encrypt(_masterKey!, notes) : null;
    final encryptedSeed =
        seedPhrase != null
            ? await _crypto.encrypt(_masterKey!, seedPhrase)
            : null;

    final body = {
      'site_hash': siteHash,
      'encrypted_metadata': encryptedMetadata,
      'encrypted_payload': encryptedPayload,
      'notes_encrypted': encryptedNotes,
      'seed_phrase_encrypted': encryptedSeed,
      'folder_id': folderId,
    };

    final response = await ApiService.put(
      '${AppConfig.passwordsUrl}/$id',
      body: body,
    );
    if (response.statusCode != 200)
      throw Exception("Failed to update password");

    // Update local cache
    final updatedPassword = json.decode(response.body);
    await _cache.cachePassword(siteHash, updatedPassword);
  }

  Future<Map<String, dynamic>> _decryptPasswordItem(
    Map<String, dynamic> item,
  ) async {
    if (_masterKey == null) return item;

    try {
      if (item['encrypted_metadata'] != null) {
        final metadata = await _crypto.decryptMetadata(
          _masterKey!,
          item['encrypted_metadata'],
        );
        item.addAll(metadata);
      }

      // We don't decrypt payloads here to keep it efficient,
      // they are decrypted on-demand (e.g., when copying or editing)
    } catch (e) {
      // Potentially legacy item or wrong key
    }
    return item;
  }

  Future<String> decryptPayload(String encryptedB64) async {
    if (_masterKey == null) throw Exception("Vault is locked");
    return await _crypto.decrypt(_masterKey!, encryptedB64);
  }
}
