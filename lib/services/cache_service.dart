import 'package:hive_flutter/hive_flutter.dart';
import 'dart:convert';

class CacheService {
  static final CacheService _instance = CacheService._internal();
  factory CacheService() => _instance;
  CacheService._internal();

  static const String _vaultBoxName = 'encrypted_vault';
  static const String _folderBoxName = 'folders_box';

  /// Initialize Hive and open the necessary boxes.
  Future<void> init() async {
    await Hive.initFlutter();
    await Hive.openBox(_vaultBoxName);
    await Hive.openBox(_folderBoxName);
  }

  /// Stores an encrypted password blob in the local cache, keyed by its site_hash.
  Future<void> cachePassword(
    String siteHash,
    Map<String, dynamic> encryptedData,
  ) async {
    final box = Hive.box(_vaultBoxName);
    await box.put(siteHash, json.encode(encryptedData));
  }

  /// Retrieves an encrypted password blob from the local cache.
  Map<String, dynamic>? getCachedPassword(String siteHash) {
    final box = Hive.box(_vaultBoxName);
    final data = box.get(siteHash);
    if (data != null) {
      return json.decode(data as String);
    }
    return null;
  }

  /// Bulk cache passwords (e.g., after a full vault sync).
  Future<void> cacheAll(List<Map<String, dynamic>> passwords) async {
    final box = Hive.box(_vaultBoxName);
    final Map<String, String> entries = {};

    for (var pwd in passwords) {
      final hash = pwd['site_hash'];
      if (hash != null) {
        entries[hash] = json.encode(pwd);
      }
    }

    if (entries.isNotEmpty) {
      await box.putAll(entries);
    }
  }

  /// Returns all cached site_hashes for offline listing.
  List<String> getAllCachedHashes() {
    final box = Hive.box(_vaultBoxName);
    return box.keys.cast<String>().toList();
  }

  /// Persists the full raw password list (server response, still server-encrypted)
  /// so the vault can be displayed offline or when the token has expired.
  Future<void> cachePasswordList(List<Map<String, dynamic>> rawList) async {
    final box = Hive.box(_vaultBoxName);
    await box.put('__list__', json.encode(rawList));
  }

  /// Returns the previously cached raw password list, or null if not available.
  List<Map<String, dynamic>>? getCachedPasswordList() {
    final box = Hive.box(_vaultBoxName);
    final data = box.get('__list__');
    if (data == null) return null;
    try {
      final list = json.decode(data as String) as List<dynamic>;
      return list.cast<Map<String, dynamic>>();
    } catch (_) {
      return null;
    }
  }

  /// Clears the entire local cache (e.g., on logout or security reset).
  Future<void> clearCache() async {
    await Hive.box(_vaultBoxName).clear();
    await Hive.box(_folderBoxName).clear();
  }

  // ── Folders ─────────────────────────────────────────────────────────────────

  /// Saves the list of local folders.
  Future<void> saveFolders(List<Map<String, dynamic>> folders) async {
    final box = Hive.box(_folderBoxName);
    await box.put('all_folders', json.encode(folders));
  }

  /// Retrieves the list of local folders.
  List<Map<String, dynamic>> getFolders() {
    final box = Hive.box(_folderBoxName);
    final data = box.get('all_folders');
    if (data == null) return [];
    try {
      final list = json.decode(data as String) as List<dynamic>;
      return list.cast<Map<String, dynamic>>();
    } catch (_) {
      return [];
    }
  }
}
