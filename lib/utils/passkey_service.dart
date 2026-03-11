import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:passkeys/passkeys.dart';
import 'package:http/http.dart' as http;
import '../config/app_config.dart';
import 'api_service.dart';

class PasskeyService {
  final _passkeyAuth = PasskeyAuthenticator();
  final _storage = const FlutterSecureStorage();

  static const String _vaultKeyKey = 'vault_key_encrypted';

  /// Register a new Passkey for the current user
  Future<bool> registerPasskey(String deviceName, String deviceId) async {
    try {
      // 1. Get registration options from backend
      final response = await ApiService.post(
        AppConfig.webauthnRegisterOptionsUrl,
        body: {'device_name': deviceName},
      );
      
      if (response.statusCode != 200) return false;
      final optionsResponse = json.decode(response.body);

      // 2. Pass options to the authenticator (biometric prompt)
      final registrationResult = await _passkeyAuth.register(
        PasskeyRegistrationOptions.fromJson(optionsResponse),
      );

      // 3. Verify with backend
      final verifyResponse = await ApiService.post(
        AppConfig.webauthnRegisterVerifyUrl,
        body: {
          'registration_response': registrationResult.toJson(),
          'device_name': deviceName,
          'device_id': deviceId,
        },
      );

      if (verifyResponse.statusCode != 200) return false;
      final verifyData = json.decode(verifyResponse.body);
      return verifyData['status'] == 'success';
    } catch (e) {
      print('Passkey Registration Error: $e');
      return false;
    }
  }

  /// Login using a Passkey
  Future<Map<String, dynamic>?> loginWithPasskey(String deviceId) async {
    try {
      // 1. Get authentication options from backend (No Auth needed)
      final response = await http.post(
        Uri.parse(AppConfig.webauthnLoginOptionsUrl),
        headers: {'Content-Type': 'application/json'},
      );
      
      if (response.statusCode != 200) return null;
      final optionsResponse = json.decode(response.body);

      // 2. Authenticate with the platform
      final authenticationResult = await _passkeyAuth.authenticate(
        PasskeyAuthenticationOptions.fromJson(optionsResponse),
      );

      // 3. Verify with backend
      final verifyResponse = await http.post(
        Uri.parse(AppConfig.webauthnLoginVerifyUrl),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'authentication_response': authenticationResult.toJson(),
          'device_id': deviceId,
          'device_name': 'Mobile Device', 
        }),
      );

      if (verifyResponse.statusCode != 200) return null;
      return json.decode(verifyResponse.body);
    } catch (e) {
      print('Passkey Login Error: $e');
      return null;
    }
  }

  /// Store the Master Key (vault_key) securely
  /// It should be stored after a successful password login or during initial sync
  Future<void> saveVaultKey(String vaultKeyBase64) async {
    await _storage.write(
      key: _vaultKeyKey,
      value: vaultKeyBase64,
      aOptions: _getAndroidOptions(),
      iOptions: _getIOSOptions(),
    );
  }

  /// Retrieve the Master Key (vault_key) from secure storage
  Future<String?> getVaultKey() async {
    return await _storage.read(
      key: _vaultKeyKey,
      aOptions: _getAndroidOptions(),
      iOptions: _getIOSOptions(),
    );
  }

  /// Remove the Master Key (e.g., on logout or device revocation)
  Future<void> clearVaultKey() async {
    await _storage.delete(key: _vaultKeyKey);
  }

  AndroidOptions _getAndroidOptions() => const AndroidOptions(
        encryptedSharedPreferences: true,
      );

  IOSOptions _getIOSOptions() => const IOSOptions(
        accessibility: KeychainAccessibility.biometryCurrentSet,
      );
}
