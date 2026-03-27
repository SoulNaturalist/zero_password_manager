import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:passkeys/authenticator.dart';
import 'package:passkeys/types.dart';
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

      final challenge = optionsResponse['challenge'] as String? ?? '';
      final rp = RelyingPartyType(
        name: optionsResponse['rp']['name'],
        id: optionsResponse['rp']['id'],
      );
      final user = UserType(
        displayName: optionsResponse['user']['displayName'],
        name: optionsResponse['user']['name'],
        id: optionsResponse['user']['id'],
      );
      
      final authSelection = optionsResponse['authenticatorSelection'] ?? {};
      final authSelectionType = AuthenticatorSelectionType(
        authenticatorAttachment: authSelection['authenticatorAttachment'],
        requireResidentKey: authSelection['requireResidentKey'] ?? false,
        residentKey: authSelection['residentKey'],
        userVerification: authSelection['userVerification'],
      );
      
      final pubKeyCredParams = (optionsResponse['pubKeyCredParams'] as List?)
          ?.map((e) => PubKeyCredParamType(alg: e['alg'], type: e['type']))
          .whereType<PubKeyCredParamType>()
          .toList();

      final request = RegisterRequestType(
        challenge: _normalizeChallenge(challenge),
        relyingParty: rp,
        user: user,
        authSelectionType: authSelectionType,
        pubKeyCredParams: pubKeyCredParams,
        excludeCredentials: [],
        timeout: optionsResponse['timeout'],
        attestation: optionsResponse['attestation'],
      );

      final registrationResult = await _passkeyAuth.register(request);

      // 3. Verify with backend
      final verifyResponse = await ApiService.post(
        AppConfig.webauthnRegisterVerifyUrl,
        body: {
          'registration_response': {
            'id': registrationResult.id,
            'rawId': registrationResult.rawId,
            'clientDataJSON': registrationResult.clientDataJSON,
            'attestationObject': registrationResult.attestationObject,
          },
          'device_name': deviceName,
          'device_id': deviceId,
        },
      );

      if (verifyResponse.statusCode != 200) return false;
      final verifyData = json.decode(verifyResponse.body);
      return verifyData['status'] == 'success';
    } catch (e) {
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
      final allowCredentials = (optionsResponse['allowCredentials'] as List?)
          ?.map(
            (e) => CredentialType(
              id: e['id'],
              type: e['type'],
              transports: (e['transports'] as List?)?.cast<String>() ?? [],
            ),
          )
          .toList();

      final request = AuthenticateRequestType(
        relyingPartyId: optionsResponse['rpId'],
        challenge: _normalizeChallenge(optionsResponse['challenge']),
        timeout: optionsResponse['timeout'],
        userVerification: optionsResponse['userVerification'],
        allowCredentials: allowCredentials,
        mediation: MediationType.Optional,
        preferImmediatelyAvailableCredentials: true,
      );

      final authenticationResult = await _passkeyAuth.authenticate(request);

      // 3. Verify with backend
      final verifyResponse = await http.post(
        Uri.parse(AppConfig.webauthnLoginVerifyUrl),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'authentication_response': {
            'id': authenticationResult.id,
            'rawId': authenticationResult.rawId,
            'clientDataJSON': authenticationResult.clientDataJSON,
            'authenticatorData': authenticationResult.authenticatorData,
            'signature': authenticationResult.signature,
          },
          'device_id': deviceId,
          'device_name': 'Mobile Device',
        }),
      );

      if (verifyResponse.statusCode != 200) return null;
      return json.decode(verifyResponse.body);
    } catch (e) {
      return null;
    }
  }

  /// Remove padding and ensure base64url format for challenges as required by passkeys 2.x
  String _normalizeChallenge(String challenge) {
    return challenge.replaceAll('=', '').replaceAll('+', '-').replaceAll('/', '_');
  }

  /// Store the Master Key (vault_key) securely
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

  AndroidOptions _getAndroidOptions() =>
      const AndroidOptions(encryptedSharedPreferences: false);

  IOSOptions _getIOSOptions() =>
      const IOSOptions(accessibility: KeychainAccessibility.first_unlock);
}
