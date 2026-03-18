import '../services/cache_service.dart';

class FolderService {
  /// Returns list of folder maps from local storage.
  static Future<List<Map<String, dynamic>>> getFolders({
    bool includeHidden = false,
  }) async {
    final all = CacheService().getFolders();
    if (includeHidden) return all;
    return all.where((f) => !(f['is_hidden'] as bool? ?? false)).toList();
  }

  /// Creates a new folder locally and returns its map.
  static Future<Map<String, dynamic>?> createFolder({
    required String name,
    required String color,
    required String icon,
    bool isHidden = false,
  }) async {
    final folders = CacheService().getFolders();
    final newFolder = {
      'id': DateTime.now().millisecondsSinceEpoch,
      'name': name,
      'color': color,
      'icon': icon,
      'is_hidden': isHidden,
      'password_count': 0,
    };
    folders.add(newFolder);
    await CacheService().saveFolders(folders);
    return newFolder;
  }

  /// Updates local folder fields; returns updated map.
  static Future<Map<String, dynamic>?> updateFolder(
    int folderId, {
    String? name,
    String? color,
    String? icon,
    bool? isHidden,
  }) async {
    final folders = CacheService().getFolders();
    final index = folders.indexWhere((f) => f['id'] == folderId);
    if (index == -1) return null;

    if (name != null) folders[index]['name'] = name;
    if (color != null) folders[index]['color'] = color;
    if (icon != null) folders[index]['icon'] = icon;
    if (isHidden != null) folders[index]['is_hidden'] = isHidden;

    await CacheService().saveFolders(folders);
    return folders[index];
  }

  /// Deletes the local folder; returns true on success.
  static Future<bool> deleteFolder(int folderId) async {
    final folders = CacheService().getFolders();
    final initialLength = folders.length;
    folders.removeWhere((f) => f['id'] == folderId);
    if (folders.length < initialLength) {
      await CacheService().saveFolders(folders);
      return true;
    }
    return false;
  }
}

