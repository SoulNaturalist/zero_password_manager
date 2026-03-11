import 'dart:convert';
import '../utils/api_service.dart';
import '../config/app_config.dart';
import 'crypto_service.dart';
import 'vault_service.dart';
import 'package:cryptography/cryptography.dart';

/// Manages the emergency-access feature.
///
/// ## Flow (grantor side)
/// 1. [inviteContact] — invite a trusted person by login, set wait_days.
/// 2. [uploadVaultSnapshot] — encrypt entire vault with recipient's share key
///    and upload it.  Should be refreshed whenever the vault changes.
/// 3. [checkin] — call this periodically (e.g. on app open) while status = waiting.
///    Resets the approval timer.
/// 4. [denyAccess] — explicitly reject a pending request.
/// 5. [revokeAccess] — revoke the grant at any time.
///
/// ## Flow (grantee side)
/// 1. [acceptInvite] — accept the invitation.
/// 2. [requestAccess] — trigger the countdown timer.
/// 3. [downloadVault] — after status = approved, download the encrypted snapshot
///    and decrypt it with the share key.
class EmergencyService {
  static final EmergencyService _instance = EmergencyService._internal();
  factory EmergencyService() => _instance;
  EmergencyService._internal();

  final _crypto = CryptoService();
  final _vault = VaultService();

  // ── Grantor: invite ───────────────────────────────────────────────────────

  Future<Map<String, dynamic>> inviteContact({
    required String granteeLogin,
    int waitDays = 7,
  }) async {
    if (waitDays < 1 || waitDays > 30) {
      throw ArgumentError('waitDays must be between 1 and 30');
    }
    final response = await ApiService.post(
      AppConfig.emergencyAccessUrl,
      body: {'grantee_login': granteeLogin, 'wait_days': waitDays},
    );
    if (response.statusCode != 201) {
      throw Exception('Failed to invite contact: ${_extractError(response.body)}');
    }
    return json.decode(response.body) as Map<String, dynamic>;
  }

  // ── List all entries ──────────────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> listAll() async {
    final response = await ApiService.get(AppConfig.emergencyAccessUrl);
    if (response.statusCode != 200) throw Exception('Failed to load emergency access list');
    return List<Map<String, dynamic>>.from(json.decode(response.body));
  }

  // ── Grantee: accept invite ────────────────────────────────────────────────

  Future<Map<String, dynamic>> acceptInvite(int eaId) async {
    final response = await ApiService.post(AppConfig.getEmergencyAcceptUrl(eaId));
    if (response.statusCode != 200) {
      throw Exception('Failed to accept invite: ${_extractError(response.body)}');
    }
    return json.decode(response.body) as Map<String, dynamic>;
  }

  // ── Grantee: request emergency access (starts the countdown) ─────────────

  Future<Map<String, dynamic>> requestAccess(int eaId) async {
    final response = await ApiService.post(AppConfig.getEmergencyRequestUrl(eaId));
    if (response.statusCode != 200) {
      throw Exception('Failed to request access: ${_extractError(response.body)}');
    }
    return json.decode(response.body) as Map<String, dynamic>;
  }

  // ── Grantor: check-in (reset timer) ──────────────────────────────────────

  Future<Map<String, dynamic>> checkin(int eaId) async {
    final response = await ApiService.post(AppConfig.getEmergencyCheckinUrl(eaId));
    if (response.statusCode != 200) {
      throw Exception('Failed to check in: ${_extractError(response.body)}');
    }
    return json.decode(response.body) as Map<String, dynamic>;
  }

  // ── Grantor: deny request ─────────────────────────────────────────────────

  Future<void> denyAccess(int eaId) async {
    final response = await ApiService.post(AppConfig.getEmergencyDenyUrl(eaId));
    if (response.statusCode != 204) {
      throw Exception('Failed to deny access: ${_extractError(response.body)}');
    }
  }

  // ── Grantor: revoke grant ─────────────────────────────────────────────────

  Future<void> revokeAccess(int eaId) async {
    final response = await ApiService.delete(AppConfig.getEmergencyRevokeUrl(eaId));
    if (response.statusCode != 204) {
      throw Exception('Failed to revoke access: ${_extractError(response.body)}');
    }
  }

  // ── Grantor: upload encrypted vault snapshot ──────────────────────────────

  /// Encrypts [vaultJson] with a fresh ephemeral key and uploads it.
  /// Returns (shareKeyB64) that must be given to the grantee out-of-band.
  Future<String> uploadVaultSnapshot({
    required int eaId,
    required List<Map<String, dynamic>> decryptedPasswords,
  }) async {
    final vaultJson = json.encode(decryptedPasswords);

    // Generate ephemeral share key
    final aesGcm = AesGcm.with256bits();
    final shareKey = await aesGcm.newSecretKey();
    final shareKeyBytes = await shareKey.extractBytes();
    final shareKeyB64 = base64.encode(shareKeyBytes);

    // Encrypt vault
    final encryptedVault = await _crypto.encrypt(shareKey, vaultJson);

    final response = await ApiService.post(
      AppConfig.getEmergencyVaultUrl(eaId),
      body: {'encrypted_vault': encryptedVault},
    );
    if (response.statusCode != 200) {
      throw Exception('Failed to upload vault: ${_extractError(response.body)}');
    }
    return shareKeyB64;
  }

  // ── Grantee: download and decrypt vault ───────────────────────────────────

  /// Download the encrypted vault snapshot and decrypt it with [shareKeyB64].
  Future<List<Map<String, dynamic>>> downloadVault({
    required int eaId,
    required String shareKeyB64,
  }) async {
    final response = await ApiService.get(AppConfig.getEmergencyVaultUrl(eaId));
    if (response.statusCode != 200) {
      throw Exception('Failed to download vault: ${_extractError(response.body)}');
    }
    final data = json.decode(response.body) as Map<String, dynamic>;
    final encryptedVault = data['encrypted_vault'] as String;

    final keyBytes = base64.decode(shareKeyB64);
    final shareKey = SecretKey(keyBytes);
    final vaultJson = await _crypto.decrypt(shareKey, encryptedVault);
    return List<Map<String, dynamic>>.from(json.decode(vaultJson));
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

  /// Human-readable status labels for UI display.
  static String statusLabel(String status) {
    switch (status) {
      case 'invited':
        return 'Invited';
      case 'accepted':
        return 'Active';
      case 'waiting':
        return 'Access Requested';
      case 'approved':
        return 'Approved';
      case 'denied':
        return 'Denied';
      case 'revoked':
        return 'Revoked';
      default:
        return status;
    }
  }
}
