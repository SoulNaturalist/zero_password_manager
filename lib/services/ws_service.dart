import 'dart:convert';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../config/app_config.dart';
import '../main.dart'; // import navigatorKey

class WsService {
  static final WsService _instance = WsService._internal();
  factory WsService() => _instance;
  WsService._internal();

  WebSocketChannel? _channel;
  final FlutterLocalNotificationsPlugin _notificationsPlugin =
      FlutterLocalNotificationsPlugin();
  bool _isInit = false;

  Future<void> init() async {
    if (_isInit) return;

    // Setup notifications
    const AndroidInitializationSettings androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const InitializationSettings initSettings = InitializationSettings(
      android: androidSettings,
    );

    await _notificationsPlugin.initialize(
      initSettings,
      onDidReceiveNotificationResponse: _onNotificationTap,
    );

    _isInit = true;
    connect();
  }

  void connect() async {
    if (AppConfig.apiBaseUrl == null) return;

    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token');
    // If user is not authenticated yet, we cannot connect to device channel
    if (token == null || token.isEmpty) return;

    final wsUrl = AppConfig.apiBaseUrl!.replaceFirst('http', 'ws');
    final uri = Uri.parse('$wsUrl/ws/device-events?token=$token');

    try {
      _channel?.sink.close();
      _channel = WebSocketChannel.connect(uri);

      _channel!.stream.listen(
        (message) {
          _handleMessage(message);
        },
        onDone: () {
          Future.delayed(const Duration(seconds: 10), connect);
        },
        onError: (e) {
          Future.delayed(const Duration(seconds: 10), connect);
        },
      );
    } catch (e) {
      Future.delayed(const Duration(seconds: 10), connect);
    }
  }

  void _handleMessage(dynamic message) {
    try {
      final data = jsonDecode(message);
      if (data['type'] == 'backend_change_request') {
        _showNotification(data['new_url'], data['challenge_id']);
      }
    } catch (e) {
      // Ignore parse errors
    }
  }

  Future<void> _showNotification(String newUrl, String challengeId) async {
    const androidDetails = AndroidNotificationDetails(
      'zero_vault_events',
      'Security Events',
      channelDescription:
          'Notifications for backend changes and security alerts',
      importance: Importance.max,
      priority: Priority.high,
    );

    await _notificationsPlugin.show(
      DateTime.now().millisecond,
      'Смена сервера Zero Vault',
      'Нажмите для подтверждения переезда на $newUrl',
      const NotificationDetails(android: androidDetails),
      payload: jsonEncode({
        'route': '/totp-confirm',
        'new_url': newUrl,
        'challenge_id': challengeId,
      }),
    );
  }

  void _onNotificationTap(NotificationResponse response) {
    if (response.payload != null) {
      final data = jsonDecode(response.payload!);
      if (data['route'] == '/totp-confirm') {
        navigatorKey.currentState?.pushNamed(
          '/totp-confirm',
          arguments: {
            'new_url': data['new_url'],
            'challenge_id': data['challenge_id'],
          },
        );
      }
    }
  }

  void disconnect() {
    _channel?.sink.close();
    _channel = null;
  }
}
