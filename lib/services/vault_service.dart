import 'package:cryptography/cryptography.dart';
import '../utils/api_service.dart';
import '../utils/biometric_service.dart';
import 'crypto_service.dart';
import 'cache_service.dart';
import '../config/app_config.dart';
import 'dart:convert';

class VaultService {
  static final VaultService _instance = VaultService._internal();
  factory VaultService() => _instance;
  VaultService._internal();

  SecretKey? _masterKey;
  final _crypto = CryptoService();
  final _cache = CacheService();

  bool get isLocked => _masterKey == null;

  /// Exposes the in-memory master key for zero-knowledge re-encryption
  /// (sharing, emergency vault upload). Returns null when vault is locked.
  SecretKey? get masterKey => _masterKey;

  void setKey(SecretKey key) {
    _masterKey = key;
  }

  void lock() {
    _masterKey = null;
    _cache.clearCache();
  }

  /// Derives the master key and unlocks the vault.
  Future<void> unlock(String password, String salt) async {
    _masterKey = await _crypto.deriveMasterKey(password, salt);
    
    // If biometrics are enabled, store the master key securely
    if (await BiometricService.isBiometricEnabled()) {
      await BiometricService.storeBiometricSecret(base64.encode(_masterKey!));
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

  /// Fetches all passwords from the server, decrypts them, and updates the local cache.
  Future<List<Map<String, dynamic>>> syncVault() async {
    if (_masterKey == null) throw Exception("Vault is locked");

    final response = await ApiService.get(AppConfig.passwordsUrl);
    if (response.statusCode != 200) throw Exception("Failed to fetch passwords");

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
    
    final metadata = {
      'site_url': url,
      'site_login': login,
      'name': name,
    };
    
    final encryptedMetadata = await _crypto.encryptMetadata(_masterKey!, metadata);
    final encryptedPayload = await _crypto.encrypt(_masterKey!, password);
    final encryptedNotes = notes != null ? await _crypto.encrypt(_masterKey!, notes) : null;
    final encryptedSeed = seedPhrase != null ? await _crypto.encrypt(_masterKey!, seedPhrase) : null;

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
    
    final metadata = {
      'site_url': url,
      'site_login': login,
      'name': name,
    };
    
    final encryptedMetadata = await _crypto.encryptMetadata(_masterKey!, metadata);
    final encryptedPayload = await _crypto.encrypt(_masterKey!, password);
    final encryptedNotes = notes != null ? await _crypto.encrypt(_masterKey!, notes) : null;
    final encryptedSeed = seedPhrase != null ? await _crypto.encrypt(_masterKey!, seedPhrase) : null;

    final body = {
      'site_hash': siteHash,
      'encrypted_metadata': encryptedMetadata,
      'encrypted_payload': encryptedPayload,
      'notes_encrypted': encryptedNotes,
      'seed_phrase_encrypted': encryptedSeed,
      'folder_id': folderId,
    };

    final response = await ApiService.put('${AppConfig.passwordsUrl}/$id', body: body);
    if (response.statusCode != 200) throw Exception("Failed to update password");

    // Update local cache
    final updatedPassword = json.decode(response.body);
    await _cache.cachePassword(siteHash, updatedPassword);
  }

  Future<Map<String, dynamic>> _decryptPasswordItem(Map<String, dynamic> item) async {
    if (_masterKey == null) return item;

    try {
      if (item['encrypted_metadata'] != null) {
        final metadata = await _crypto.decryptMetadata(_masterKey!, item['encrypted_metadata']);
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
