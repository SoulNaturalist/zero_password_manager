import 'dart:convert';
import 'package:cryptography/cryptography.dart';
import 'dart:typed_data';

class CryptoService {
  static final CryptoService _instance = CryptoService._internal();
  factory CryptoService() => _instance;
  CryptoService._internal();

  final _aesGcm = AesGcm.with256bits();
  final _hmacSha256 = Hmac.sha256();

  /// Derives a 256-bit key from a master password and salt using PBKDF2-SHA256.
  Future<SecretKey> deriveMasterKey(String password, String saltB64) async {
    final salt = base64.decode(saltB64);
    final pbkdf2 = Pbkdf2(
      macAlgorithm: Hmac.sha256(),
      iterations: 100000, // Standard high iteration count
      bits: 256,
    );

    return await pbkdf2.deriveKeyFromPassword(password: password, nonce: salt);
  }

  /// Derives a 256-bit key directly from raw bytes (CWE-256: avoids String creation).
  Future<SecretKey> deriveMasterKeyFromBytes(List<int> passwordBytes, String saltB64) async {
    final salt = base64.decode(saltB64);
    final pbkdf2 = Pbkdf2(
      macAlgorithm: Hmac.sha256(),
      iterations: 100000,
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

  /// Encrypts data using AES-GCM.
  /// Returns base64(nonce + ciphertext + tag).
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

  /// Decrypts data from base64(nonce + ciphertext + tag).
  Future<String> decrypt(SecretKey key, String encryptedB64) async {
    final data = base64.decode(encryptedB64);

    // AesGcm uses 12-byte nonce and 16-byte MAC (tag)
    const nonceLen = 12;
    const macLen = 16;

    if (data.length < nonceLen + macLen) {
      throw Exception("Invalid encrypted data length");
    }

    final nonce = data.sublist(0, nonceLen);
    final ciphertext = data.sublist(nonceLen, data.length - macLen);
    final macBytes = data.sublist(data.length - macLen);

    final secretBox = SecretBox(ciphertext, nonce: nonce, mac: Mac(macBytes));

    final clearText = await _aesGcm.decrypt(secretBox, secretKey: key);

    return utf8.decode(clearText);
  }

  /// Helper for encrypting a full metadata object (site_url, site_login, etc.)
  Future<String> encryptMetadata(
    SecretKey key,
    Map<String, dynamic> metadata,
  ) async {
    return await encrypt(key, json.encode(metadata));
  }

  /// Helper for decrypting the metadata object.
  Future<Map<String, dynamic>> decryptMetadata(
    SecretKey key,
    String encryptedB64,
  ) async {
    final decrypted = await decrypt(key, encryptedB64);
    return json.decode(decrypted);
  }
}
