import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../main.dart'; // Для navigatorKey
import '../widgets/otp_input_dialog.dart';

class ApiService {
  static Future<http.Response> get(String url, {Map<String, String>? headers}) async {
    return _handleRequest(() => http.get(Uri.parse(url), headers: headers), url, headers: headers);
  }

  static Future<http.Response> post(String url, {Map<String, String>? headers, Object? body}) async {
    return _handleRequest(() => http.post(Uri.parse(url), headers: headers, body: body), url, headers: headers, body: body);
  }

  static Future<http.Response> _handleRequest(
    Future<http.Response> Function() requestFn,
    String url, {
    Map<String, String>? headers,
    Object? body,
  }) async {
    var response = await requestFn();

    // Проверяем на потребность в OTP (401 OTP_REQUIRED или кастомный заголовок)
    if (_isOtpRequired(response)) {
      final context = navigatorKey.currentContext;
      if (context != null) {
        final String? otpCode = await showDialog<String>(
          context: context,
          builder: (context) => const OTPInputDialog(),
        );

        if (otpCode != null) {
          // Повторяем запрос с OTP в заголовке
          final newHeaders = Map<String, String>.from(headers ?? {});
          newHeaders['X-OTP'] = otpCode;
          
          // Рекурсивный вызов с новыми заголовками
          if (response.request?.method == 'GET') {
            return http.get(Uri.parse(url), headers: newHeaders);
          } else if (response.request?.method == 'POST') {
            return http.post(Uri.parse(url), headers: newHeaders, body: body);
          }
        }
      }
    }

    return response;
  }

  static bool _isOtpRequired(http.Response response) {
    // Backend returns 401/403 with specific detail or header
    if (response.statusCode == 401 || response.statusCode == 403) {
      try {
        final data = json.decode(response.body);
        if (data['detail'] == 'OTP_REQUIRED' || data['error'] == 'OTP_REQUIRED') {
          return true;
        }
      } catch (_) {}
      
      if (response.headers['x-2fa-required'] == 'true') {
        return true;
      }
    }
    return false;
  }
}
