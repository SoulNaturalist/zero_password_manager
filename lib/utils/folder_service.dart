import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../config/app_config.dart';
import 'api_service.dart';

class FolderService {
  static Future<Map<String, String>> _authHeaders() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token');
    return {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $token',
    };
  }

  /// Returns list of folder maps from the server.
  /// Pass [includeHidden] = true (after TOTP verification) to also receive hidden folders.
  static Future<List<Map<String, dynamic>>> getFolders({
    bool includeHidden = false,
  }) async {
    final headers = await _authHeaders();
    final url = includeHidden
        ? '${AppConfig.foldersUrl}?include_hidden=true'
        : AppConfig.foldersUrl;
    final response = await ApiService.get(url, headers: headers);
    if (response.statusCode == 200) {
      final List data = json.decode(response.body);
      return data.cast<Map<String, dynamic>>();
    }
    return [];
  }

  /// Creates a new folder and returns its map, or null on error.
  static Future<Map<String, dynamic>?> createFolder({
    required String name,
    required String color,
    required String icon,
    bool isHidden = false,
  }) async {
    final headers = await _authHeaders();
    final response = await ApiService.post(
      AppConfig.foldersUrl,
      headers: headers,
      body: json.encode({
        'name': name,
        'color': color,
        'icon': icon,
        'is_hidden': isHidden,
      }),
    );
    if (response.statusCode == 201) {
      return json.decode(response.body) as Map<String, dynamic>;
    }
    return null;
  }

  /// Updates folder fields; returns updated map or null on error.
  static Future<Map<String, dynamic>?> updateFolder(
    int folderId, {
    String? name,
    String? color,
    String? icon,
    bool? isHidden,
  }) async {
    final headers = await _authHeaders();
    final body = <String, dynamic>{};
    if (name != null) body['name'] = name;
    if (color != null) body['color'] = color;
    if (icon != null) body['icon'] = icon;
    if (isHidden != null) body['is_hidden'] = isHidden;

    final response = await ApiService.put(
      AppConfig.getFolderUrl(folderId),
      headers: headers,
      body: json.encode(body),
    );
    if (response.statusCode == 200) {
      return json.decode(response.body) as Map<String, dynamic>;
    }
    return null;
  }

  /// Deletes the folder; returns true on success.
  static Future<bool> deleteFolder(int folderId) async {
    final headers = await _authHeaders();
    final response = await ApiService.delete(
      AppConfig.getFolderUrl(folderId),
      headers: headers,
    );
    return response.statusCode == 204;
  }
}

