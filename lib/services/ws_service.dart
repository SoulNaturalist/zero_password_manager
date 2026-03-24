import 'dart:async';
import 'dart:convert';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:web_socket_channel/io.dart';
import '../config/app_config.dart';
import '../main.dart'; // import navigatorKey
import 'auth_token_storage.dart';

class WsService {
  static final WsService _instance = WsService._internal();
  factory WsService() => _instance;
  WsService._internal();

  WebSocketChannel? _channel;
  StreamSubscription? _subscription;
  Timer? _reconnectTimer;

  final FlutterLocalNotificationsPlugin _notificationsPlugin =
      FlutterLocalNotificationsPlugin();

  bool _isInit = false;
  bool _isConnecting = false;
  bool _isConnected = false;
  bool _manuallyClosed = false;

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
    await connect();
  }

  Future<void> connect() async {
    if (_isConnecting || _isConnected) return;
    if (AppConfig.apiBaseUrl == null) return;

    final token = await AuthTokenStorage.readAccessToken();
    // If user is not authenticated yet, we cannot connect to device channel
    if (token == null || token.isEmpty) return;

    _isConnecting = true;
    _manuallyClosed = false;
    _reconnectTimer?.cancel();

    final wsUrl = AppConfig.apiBaseUrl!.replaceFirst('http', 'ws');
    final uri = Uri.parse('$wsUrl/ws/device-events');

    try {
      // Clean up old subscription if any (though _isConnected check should prevent this)
      await _subscription?.cancel();
      _subscription = null;

      _channel = IOWebSocketChannel.connect(
        uri,
        headers: {'Authorization': 'Bearer $token'},
      );

      _isConnected = true;
      _isConnecting = false;

      _subscription = _channel!.stream.listen(
        (message) {
          _handleMessage(message);
        },
        onDone: () {
          _isConnected = false;
          _channel = null;
          if (!_manuallyClosed) {
            _scheduleReconnect();
          }
        },
        onError: (e) {
          _isConnected = false;
          _channel = null;
          if (!_manuallyClosed) {
            _scheduleReconnect();
          }
        },
        cancelOnError: true,
      );
    } catch (e) {
      _isConnected = false;
      _isConnecting = false;
      _channel = null;
      _scheduleReconnect();
    }
  }

  void _scheduleReconnect() {
    if (_manuallyClosed) return;
    if (_reconnectTimer?.isActive ?? false) return;

    _reconnectTimer = Timer(const Duration(seconds: 10), () {
      connect();
    });
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
      DateTime.now().millisecondsSinceEpoch ~/ 1000,
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

  Future<void> disconnect() async {
    _manuallyClosed = true;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    
    _isConnected = false;
    _isConnecting = false;

    await _subscription?.cancel();
    _subscription = null;

    await _channel?.sink.close();
    _channel = null;
  }
}
