import 'dart:io';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:safe_device/safe_device.dart';

class SecurityUtils {
  static final DeviceInfoPlugin _deviceInfo = DeviceInfoPlugin();

  /// Gathers a detailed device integrity payload for the backend.
  static Future<Map<String, dynamic>> getDeviceSecurityPayload() async {
    final Map<String, dynamic> payload = {
      "platform": Platform.operatingSystem,
      "isRealDevice": await SafeDevice.isRealDevice,
      "isJailBroken": await SafeDevice.isJailBroken,
      "isSafeDevice": await SafeDevice.isSafeDevice,
      "isMockLocation": await SafeDevice.isMockLocation,
      "onExternalStorage": await SafeDevice.isOnExternalStorage,
    };

    if (Platform.isAndroid) {
      final androidInfo = await _deviceInfo.androidInfo;
      payload.addAll({
        "model": androidInfo.model,
        "version": androidInfo.version.release,
        "deviceId": androidInfo.id,
        "isEmulator": !androidInfo.isPhysicalDevice,
      });
    } else if (Platform.isIOS) {
      final iosInfo = await _deviceInfo.iosInfo;
      payload.addAll({
        "model": iosInfo.model,
        "version": iosInfo.systemVersion,
        "deviceId": iosInfo.identifierForVendor ?? "unknown_ios",
        "isEmulator": !iosInfo.isPhysicalDevice,
      });
    }

    return payload;
  }
}
