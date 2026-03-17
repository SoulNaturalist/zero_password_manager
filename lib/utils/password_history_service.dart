import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../config/app_config.dart';
import '../utils/api_service.dart';

class PasswordHistoryService {
  // Добавить запись в историю паролей
  static Future<bool> addPasswordHistory({
    int? passwordId,
    required String actionType,
    required Map<String, dynamic> actionDetails,
    required String siteUrl,
  }) async {
    try {
      final response = await ApiService.post(
        AppConfig.passwordHistoryUrl,
        body: {
          'password_id': passwordId,
          'action_type': actionType,
          'action_details': actionDetails,
          'site_url': siteUrl,
        },
      );

      return response.statusCode == 200 || response.statusCode == 201;
    } catch (e) {
      print('Ошибка при добавлении записи в историю: $e');
      return false;
    }
  }

  // Получить историю паролей
  static Future<List<Map<String, dynamic>>> getPasswordHistory() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('token');

      if (token == null) {
        return [];
      }

      final response = await ApiService.get(
        AppConfig.passwordHistoryUrl,
        headers: {'Authorization': 'Bearer $token'},
      );

      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);
        return data.cast<Map<String, dynamic>>();
      }

      return [];
    } catch (e) {
      print('Ошибка при получении истории паролей: $e');
      return [];
    }
  }

  // Получить читаемое название действия
  static String getActionTypeDisplayName(String actionType) {
    switch (actionType.toUpperCase()) {
      case 'CREATE':
        return 'Создание';
      case 'UPDATE':
        return 'Изменение';
      case 'DELETE':
        return 'Удаление';
      default:
        return actionType;
    }
  }

  // Получить иконку для типа действия
  static String getActionTypeIcon(String actionType) {
    switch (actionType.toUpperCase()) {
      case 'CREATE':
        return '➕';
      case 'UPDATE':
        return '✏️';
      case 'DELETE':
        return '🗑️';
      default:
        return '📝';
    }
  }

  // Форматировать дату
  static String formatDate(String dateString) {
    try {
      final date = DateTime.parse(dateString);
      final now = DateTime.now();
      final difference = now.difference(date);

      if (difference.inDays == 0) {
        if (difference.inHours == 0) {
          if (difference.inMinutes == 0) {
            return 'Только что';
          }
          return '${difference.inMinutes} мин назад';
        }
        return '${difference.inHours} ч назад';
      } else if (difference.inDays == 1) {
        return 'Вчера';
      } else if (difference.inDays < 7) {
        return '${difference.inDays} дн назад';
      } else {
        return '${date.day.toString().padLeft(2, '0')}.${date.month.toString().padLeft(2, '0')}.${date.year}';
      }
    } catch (e) {
      return dateString;
    }
  }
}
