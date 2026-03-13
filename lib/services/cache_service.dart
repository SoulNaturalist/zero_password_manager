import 'package:hive_flutter/hive_flutter.dart';
import 'dart:convert';

class CacheService {
  static final CacheService _instance = CacheService._internal();
  factory CacheService() => _instance;
  CacheService._internal();

  static const String _vaultBoxName = 'encrypted_vault';

  /// Initialize Hive and open the necessary boxes.
  Future<void> init() async {
    await Hive.initFlutter();
    await Hive.openBox(_vaultBoxName);
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

  /// Clears the entire local cache (e.g., on logout or security reset).
  Future<void> clearCache() async {
    final box = Hive.box(_vaultBoxName);
    await box.clear();
  }
}
