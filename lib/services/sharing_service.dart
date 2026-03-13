import 'dart:convert';
import '../utils/api_service.dart';
import '../config/app_config.dart';
import 'crypto_service.dart';
import 'package:cryptography/cryptography.dart';

/// Zero-knowledge password sharing.
///
/// The sender decrypts the password locally, then re-encrypts it using a
/// [shareKey] that was derived from a shared secret agreed upon out-of-band
/// (or, in practice, sent as a one-time key along with the share invitation).
///
/// The server never receives plaintext — it only stores the re-encrypted blob.
class SharingService {
  static final SharingService _instance = SharingService._internal();
  factory SharingService() => _instance;
  SharingService._internal();

  final _crypto = CryptoService();

  // ── Share a password ──────────────────────────────────────────────────────

  /// Decrypt [encryptedPayload] with [masterKey], re-encrypt with a fresh
  /// ephemeral key, send the share to the server, and return the share id.
  ///
  /// The ephemeral key bytes are base64-encoded and returned so the caller can
  /// transmit them to the recipient out-of-band (e.g. display as a copy-able
  /// string or QR code).
  Future<({int shareId, String shareKey})> sharePassword({
    required String recipientLogin,
    required String encryptedPayload,
    required SecretKey masterKey,
    String? label,
    Map<String, dynamic>? metadata,
    int? expiresInDays,
  }) async {
    // 1. Decrypt the password with the master key
    final plaintext = await _crypto.decrypt(masterKey, encryptedPayload);

    // 2. Generate a fresh AES-256 ephemeral share key
    final aesGcm = AesGcm.with256bits();
    final shareSecretKey = await aesGcm.newSecretKey();
    final shareKeyBytes = await shareSecretKey.extractBytes();
    final shareKeyB64 = base64.encode(shareKeyBytes);

    // 3. Re-encrypt with the share key
    final reEncrypted = await _crypto.encrypt(shareSecretKey, plaintext);

    // 4. POST to server
    final body = {
      'recipient_login': recipientLogin,
      'encrypted_payload': reEncrypted,
      if (label != null) 'label': label,
      if (metadata != null) 'encrypted_metadata': metadata,
      if (expiresInDays != null) 'expires_in_days': expiresInDays,
    };
    final response = await ApiService.post(AppConfig.shareUrl, body: body);
    if (response.statusCode != 201) {
      final err = _extractError(response.body);
      throw Exception('Failed to create share: $err');
    }
    final data = json.decode(response.body) as Map<String, dynamic>;
    return (shareId: data['id'] as int, shareKey: shareKeyB64);
  }

  // ── List shares ───────────────────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> getIncomingShares() async {
    final response = await ApiService.get(AppConfig.shareIncomingUrl);
    if (response.statusCode != 200) throw Exception('Failed to load incoming shares');
    return List<Map<String, dynamic>>.from(json.decode(response.body));
  }

  Future<List<Map<String, dynamic>>> getOutgoingShares() async {
    final response = await ApiService.get(AppConfig.shareOutgoingUrl);
    if (response.statusCode != 200) throw Exception('Failed to load outgoing shares');
    return List<Map<String, dynamic>>.from(json.decode(response.body));
  }

  // ── Accept & decrypt a received share ────────────────────────────────────

  Future<void> acceptShare(int shareId) async {
    final response = await ApiService.post(AppConfig.getShareAcceptUrl(shareId));
    if (response.statusCode != 200) {
      throw Exception('Failed to accept share: ${_extractError(response.body)}');
    }
  }

  /// After accepting, retrieve the encrypted payload and decrypt it with
  /// the [shareKeyB64] that the sender transmitted out-of-band.
  Future<String> decryptReceivedShare(int shareId, String shareKeyB64) async {
    final response = await ApiService.get(AppConfig.getShareUrl(shareId));
    if (response.statusCode != 200) {
      throw Exception('Failed to fetch share: ${_extractError(response.body)}');
    }
    final data = json.decode(response.body) as Map<String, dynamic>;
    final encryptedPayload = data['encrypted_payload'] as String;

    final keyBytes = base64.decode(shareKeyB64);
    final shareKey = SecretKey(keyBytes);
    return await _crypto.decrypt(shareKey, encryptedPayload);
  }

  // ── Revoke a share ────────────────────────────────────────────────────────

  Future<void> revokeShare(int shareId) async {
    final response = await ApiService.delete(AppConfig.getShareUrl(shareId));
    if (response.statusCode != 204) {
      throw Exception('Failed to revoke share: ${_extractError(response.body)}');
    }
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  String _extractError(String body) {
    try {
      final data = json.decode(body);
      return data['detail']?.toString() ?? body;
    } catch (_) {
      return body;
    }
  }
}
