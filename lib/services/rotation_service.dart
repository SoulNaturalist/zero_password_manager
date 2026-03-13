import 'dart:convert';
import '../utils/api_service.dart';
import '../config/app_config.dart';
import 'crypto_service.dart';
import 'package:cryptography/cryptography.dart';

/// Handles automatic password rotation.
///
/// Rotation flow:
/// 1. App calls [getPasswordsDueForRotation] on startup / periodically.
/// 2. For each due password, the app generates a new password string.
/// 3. App calls [rotatePassword] with the new plaintext → service encrypts
///    it and POSTs the new payload to the server.
/// 4. Server records [last_rotated_at].
class RotationService {
  static final RotationService _instance = RotationService._internal();
  factory RotationService() => _instance;
  RotationService._internal();

  final _crypto = CryptoService();

  // ── Configure rotation for a single password ──────────────────────────────

  Future<Map<String, dynamic>> setRotationConfig({
    required int passwordId,
    required bool enabled,
    int? intervalDays,
  }) async {
    final body = {
      'rotation_enabled': enabled,
      if (intervalDays != null) 'rotation_interval_days': intervalDays,
    };
    final response = await ApiService.put(
      AppConfig.getRotationConfigUrl(passwordId),
      body: body,
    );
    if (response.statusCode != 200) {
      throw Exception('Failed to set rotation config: ${_extractError(response.body)}');
    }
    return json.decode(response.body) as Map<String, dynamic>;
  }

  // ── Query passwords due for rotation ─────────────────────────────────────

  /// Returns list of {id, encrypted_metadata, rotation_interval_days, last_rotated_at}.
  /// The caller should decrypt [encrypted_metadata] to show a human-readable label.
  Future<List<Map<String, dynamic>>> getPasswordsDueForRotation() async {
    final response = await ApiService.get(AppConfig.rotationDueUrl);
    if (response.statusCode != 200) {
      throw Exception('Failed to fetch rotation-due list');
    }
    return List<Map<String, dynamic>>.from(json.decode(response.body));
  }

  // ── Perform rotation ──────────────────────────────────────────────────────

  /// Encrypt [newPassword] with [masterKey] and send to server.
  /// Returns the updated password record.
  Future<Map<String, dynamic>> rotatePassword({
    required int passwordId,
    required String newPassword,
    required SecretKey masterKey,
    String? newNotes,
    Map<String, dynamic>? newMetadata,
  }) async {
    final encryptedPayload = await _crypto.encrypt(masterKey, newPassword);
    final encryptedNotes =
        newNotes != null ? await _crypto.encrypt(masterKey, newNotes) : null;
    final encryptedMetadata = newMetadata != null
        ? await _crypto.encryptMetadata(masterKey, newMetadata)
        : null;

    final body = <String, dynamic>{
      'encrypted_payload': encryptedPayload,
      if (encryptedNotes != null) 'notes_encrypted': encryptedNotes,
      if (encryptedMetadata != null) 'encrypted_metadata': encryptedMetadata,
    };

    final response = await ApiService.post(
      AppConfig.getRotateUrl(passwordId),
      body: body,
    );
    if (response.statusCode != 200) {
      throw Exception('Failed to rotate password: ${_extractError(response.body)}');
    }
    return json.decode(response.body) as Map<String, dynamic>;
  }

  // ── Generate a strong random password ────────────────────────────────────

  Future<String> generateNewPassword({int length = 24}) async {
    final response = await ApiService.get(
      '${AppConfig.generatePasswordUrl}?length=$length',
    );
    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      return data['password'] as String;
    }
    // Fallback: local generation
    const chars =
        'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789!@#\$%^&*()_+-=';
    final buf = StringBuffer();
    for (var i = 0; i < length; i++) {
      buf.write(chars[DateTime.now().microsecondsSinceEpoch % chars.length]);
    }
    return buf.toString();
  }

  String _extractError(String body) {
    try {
      final data = json.decode(body);
      return data['detail']?.toString() ?? body;
    } catch (_) {
      return body;
    }
  }
}
