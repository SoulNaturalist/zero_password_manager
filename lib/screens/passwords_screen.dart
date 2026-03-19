import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:file_picker/file_picker.dart';
import 'package:shimmer/shimmer.dart';
import 'package:csv/csv.dart';
import 'dart:io';
import '../theme/colors.dart';
import '../widgets/themed_widgets.dart';
import '../main.dart';
import 'edit_password_screen.dart';
import 'folders_screen.dart';
import '../config/app_config.dart';
import '../utils/folder_service.dart';
import '../utils/hidden_folder_service.dart';
import '../services/vault_service.dart';
import '../utils/memory_security.dart';
import 'password_detail_screen.dart';
import 'sharing_screen.dart';

// ── helpers ──────────────────────────────────────────────────────────────────

Color _colorFromHex(String hex) {
  try {
    return Color(int.parse(hex.replaceFirst('#', '0xFF')));
  } catch (_) {
    return const Color(0xFF5D52D2);
  }
}

IconData _iconFromName(String name) {
  for (final e in _kFolderIcons) {
    if (e['name'] == name) return e['icon'] as IconData;
  }
  return Icons.folder;
}

const List<String> _kFolderColors = [
  '#5D52D2',
  '#E74C3C',
  '#E67E22',
  '#F1C40F',
  '#2ECC71',
  '#1ABC9C',
  '#3498DB',
  '#9B59B6',
  '#E91E63',
  '#00BCD4',
  '#FF5722',
  '#607D8B',
];

const List<Map<String, dynamic>> _kFolderIcons = [
  {'name': 'folder', 'icon': Icons.folder},
  {'name': 'work', 'icon': Icons.work},
  {'name': 'home', 'icon': Icons.home},
  {'name': 'lock', 'icon': Icons.lock},
  {'name': 'star', 'icon': Icons.star},
  {'name': 'favorite', 'icon': Icons.favorite},
  {'name': 'shopping_cart', 'icon': Icons.shopping_cart},
  {'name': 'school', 'icon': Icons.school},
  {'name': 'code', 'icon': Icons.code},
  {'name': 'gaming', 'icon': Icons.sports_esports},
  {'name': 'bank', 'icon': Icons.account_balance},
  {'name': 'email', 'icon': Icons.email},
  {'name': 'cloud', 'icon': Icons.cloud},
  {'name': 'social', 'icon': Icons.people},
  {'name': 'crypto', 'icon': Icons.currency_bitcoin},
  {'name': 'vpn_key', 'icon': Icons.vpn_key},
];

// ── screen ───────────────────────────────────────────────────────────────────

class PasswordsScreen extends StatefulWidget {
  const PasswordsScreen({super.key});

  @override
  State<PasswordsScreen> createState() => _PasswordsScreenState();
}

class _PasswordsScreenState extends State<PasswordsScreen> with RouteAware {
  List<Map<String, dynamic>> passwords = [];
  List<Map<String, dynamic>> searchResults = [];
  List<Map<String, dynamic>> folders = [];

  bool isLoading = true;
  bool isImporting = false;
  bool _hideSeedPhrases = false;
  bool isSearching = false;
  bool isSearchMode = false;

  // null = show all, int = show folder
  int? _selectedFolderId;

  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    routeObserver.subscribe(this, ModalRoute.of(context)! as PageRoute);
  }

  @override
  void dispose() {
    routeObserver.unsubscribe(this);
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  @override
  void didPopNext() {
    _loadAll();
  }

  // ── data loading ────────────────────────────────────────────────────────────

  Future<void> _loadAll() async {
    await Future.wait([_loadPasswords(), _loadFolders()]);
  }

  Future<void> _loadFolders() async {
    final result = await FolderService.getFolders(
      includeHidden: HiddenFolderService.instance.isUnlocked,
    );
    if (mounted) {
      setState(() => folders = result);
    }
  }

  Future<void> _loadPasswords() async {
    setState(() => isLoading = true);
    await _loadSeedPhraseSettings();

    try {
      // Loads ONLY decrypted metadata — encrypted_payload stays encrypted
      final list = await VaultService().loadPasswordList();
      // Local folder assignments override any server-side folder_id.
      final folderMappings = await FolderService.getAllFolderMappings();

      setState(() {
        passwords = list.map<Map<String, dynamic>>((item) {
          final id = item['id'] as int?;
          final localFolderId = id != null ? folderMappings[id] : null;
          return {
            'id':               id,
            'title':            item['title']    ?? item['name'] ?? item['site_url'] ?? 'Безымянный',
            'subtitle':         item['subtitle'] ?? item['site_login'] ?? 'Нет логина',
            'site_url':         item['site_url']  ?? '',
            // Keep encrypted payload for on-demand decryption in PasswordDetailScreen
            'encrypted_payload':      item['encrypted_payload'],
            'encrypted_metadata':     item['encrypted_metadata'],
            'notes_encrypted':        item['notes_encrypted'],
            'has_2fa':          item['has_2fa']          ?? false,
            'has_seed_phrase':  item['has_seed_phrase']  ?? false,
            // Always use local assignment; fall back to server value if no local mapping.
            'folder_id':        localFolderId ?? item['folder_id'],
            'favicon_url':      item['favicon_url'],
            'rotation_interval_days': item['rotation_interval_days'],
            'last_rotated_at':  item['last_rotated_at'],
          };
        }).toList();
        isLoading = false;
      });
    } catch (e) {
      setState(() => isLoading = false);
    }
  }

  Future<void> _loadSeedPhraseSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (mounted) {
        setState(
          () => _hideSeedPhrases = prefs.getBool('hide_seed_phrases') ?? false,
        );
      }
    } catch (_) {
      if (mounted) setState(() => _hideSeedPhrases = false);
    }
  }

  // ── CSV import ──────────────────────────────────────────────────────────────

  Future<void> _importCSV() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['csv'],
        withData: true,
      );
      if (result == null || result.files.isEmpty) return;

      setState(() => isImporting = true);

      final file = result.files.single;
      late String csvString;

      if (file.bytes != null) {
        csvString = utf8.decode(file.bytes!);
      } else if (file.path != null) {
        csvString = await File(file.path!).readAsString();
      } else {
        throw Exception("Cannot read file content");
      }

      final List<List<dynamic>> rows = const CsvToListConverter().convert(csvString);
      if (rows.isEmpty) throw Exception("CSV file is empty");

      // Identify headers
      final headers = rows[0].map((h) => h.toString().toLowerCase()).toList();
      final urlIndex = headers.indexOf('url');
      final userIndex = headers.indexOf('username');
      final passIndex = headers.indexOf('password');

      if (urlIndex == -1 || userIndex == -1 || passIndex == -1) {
        throw Exception("Invalid CSV. Required headers: url, username, password");
      }

      final List<Map<String, String>> entries = [];
      for (var i = 1; i < rows.length; i++) {
        final row = rows[i];
        if (row.length <= urlIndex || row.length <= userIndex || row.length <= passIndex) continue;
        entries.add({
          'url': row[urlIndex].toString(),
          'username': row[userIndex].toString(),
          'password': row[passIndex].toString(),
        });
      }

      if (entries.isEmpty) throw Exception("No valid entries found");

      await VaultService().importPasswordsBatch(entries);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Colors.green,
            content: Text('Успешно импортировано ${entries.length} паролей'),
          ),
        );
        _loadPasswords();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Colors.red,
            content: Text('Ошибка импорта: ${e.toString()}'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => isImporting = false);
    }
  }

  // ── search ──────────────────────────────────────────────────────────────────

  Future<void> _searchPasswords(String query) async {
    if (query.trim().isEmpty) {
      setState(() {
        isSearchMode = false;
        searchResults.clear();
      });
      return;
    }

    setState(() {
      isSearching = true;
      isSearchMode = true;
    });

    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('token');

      final response = await http.get(
        Uri.parse(
          '${AppConfig.baseUrl}/passwords/search/${Uri.encodeComponent(query.trim())}',
        ),
        headers: {'Authorization': 'Bearer $token'},
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
      final List<dynamic> rawResults = data['results'] ?? [];
        setState(() {
          searchResults = rawResults.map<Map<String, dynamic>>((item) => {
            'id':              item['id'],
            'title':           item['site_url'] ?? '',
            'subtitle':        item['site_login'] ?? '',
            // Store only encrypted payload — never plaintext
            'encrypted_payload':     item['encrypted_payload'],
            'encrypted_metadata':    item['encrypted_metadata'],
            'notes_encrypted':       item['notes_encrypted'],
            'has_2fa':         item['has_2fa'] ?? false,
            'has_seed_phrase': item['has_seed_phrase'] ?? false,
            'favicon_url':     item['favicon_url'],
            'folder_id':       item['folder_id'],
          }).toList();
          isSearching = false;
        });
      } else {
        setState(() {
          searchResults.clear();
          isSearching = false;
        });
      }
    } catch (e) {
      setState(() {
        searchResults.clear();
        isSearching = false;
      });
    }
  }

  void _clearSearch() {
    _searchController.clear();
    setState(() {
      isSearchMode = false;
      searchResults.clear();
    });
    _searchFocusNode.unfocus();
  }

  // ── rotation helpers ─────────────────────────────────────────────────────────

  bool _isRotationDue(Map<String, dynamic> item) {
    final intervalDays = item['rotation_interval_days'] as int?;
    if (intervalDays == null) return false;
    final lastRotatedStr = item['last_rotated_at'] as String?;
    if (lastRotatedStr == null) return true; // never rotated
    try {
      final lastRotated = DateTime.parse(lastRotatedStr);
      return DateTime.now().isAfter(
          lastRotated.add(Duration(days: intervalDays)));
    } catch (_) {
      return false;
    }
  }

  void _sharePassword(Map<String, dynamic> item) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SharingScreen(initialEntry: item),
      ),
    );
  }

  // ── clipboard helpers ───────────────────────────────────────────────────────

  Future<void> _copyPassword(String? encryptedPayload) async {
    if (encryptedPayload == null || encryptedPayload.isEmpty) return;

    try {
      final buf = await VaultService().decryptPayloadSecure(encryptedPayload);
      await copySecureBuffer(buf);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: AppColors.button,
            content: const Row(
              children: [
                Icon(Icons.check_circle, color: Colors.white),
                SizedBox(width: 10),
                Text('Скопировано (авто-очистка через 30с)',
                    style: TextStyle(color: Colors.white)),
              ],
            ),
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            backgroundColor: Colors.red,
            content: Text('Ошибка дешифрования'),
          ),
        );
      }
    }
  }

  // ── navigation ──────────────────────────────────────────────────────────────

  void _navigateToAddPassword() async {
    final result = await Navigator.pushNamed(context, '/add');
    if (result == true) _loadAll();
  }

  /// Opens the detail screen for a password (lazy-decrypts on arrival).
  void _navigateToDetail(Map<String, dynamic> entry) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PasswordDetailScreen(entry: entry),
      ),
    );
    // Always reload list after returning (user may have edited or deleted)
    await _loadAll();
  }

  // Keep for backward compat (called from long-press edit action)
  void _navigateToEditPassword(Map<String, dynamic> password) async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => EditPasswordScreen(password: password),
      ),
    );
    if (result == true) await _loadAll();
  }

  void _openFoldersScreen() async {
    final selected = await Navigator.push<Map<String, dynamic>>(
      context,
      MaterialPageRoute(builder: (_) => const FoldersScreen()),
    );
    if (selected != null) {
      setState(() => _selectedFolderId = selected['id'] as int?);
    }
    await _loadFolders();
  }

  // ── favicon helpers ─────────────────────────────────────────────────────────

  Widget _buildFallbackFavicon(String? siteUrl) {
    if (siteUrl == null || siteUrl.isEmpty) {
      return Container(
        width: 24,
        height: 24,
        decoration: BoxDecoration(
          color: Colors.grey.withOpacity(0.2),
          borderRadius: BorderRadius.circular(6),
        ),
        child: const Icon(Icons.language, size: 14, color: Colors.grey),
      );
    }
    try {
      String fullUrl = siteUrl;
      if (!siteUrl.startsWith('http://') && !siteUrl.startsWith('https://')) {
        fullUrl = 'https://$siteUrl';
      }
      final uri = Uri.parse(fullUrl);
      String domain = uri.host;
      if (siteUrl.toLowerCase().contains('metamask')) domain = 'metamask.io';
      final faviconUrl =
          'https://www.google.com/s2/favicons?domain=$domain&sz=32';

      return Image.network(
        faviconUrl,
        width: 24,
        height: 24,
        fit: BoxFit.cover,
        errorBuilder:
            (_, __, ___) => Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                color: Colors.grey.withOpacity(0.2),
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Icon(Icons.language, size: 14, color: Colors.grey),
            ),
      );
    } catch (_) {
      return Container(
        width: 24,
        height: 24,
        decoration: BoxDecoration(
          color: Colors.grey.withOpacity(0.2),
          borderRadius: BorderRadius.circular(6),
        ),
        child: const Icon(Icons.language, size: 14, color: Colors.grey),
      );
    }
  }

  // ── build ────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return ThemedBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title:
              isSearchMode
                  ? _buildSearchField()
                  : NeonText(
                    text:
                        _selectedFolderId == null
                            ? 'Пароли'
                            : _folderName(_selectedFolderId!),
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
          backgroundColor:
              ThemeManager.currentTheme == AppTheme.dark
                  ? AppColors.background
                  : Colors.black.withOpacity(0.3),
          elevation: 0,
          leading:
              _selectedFolderId != null
                  ? IconButton(
                    icon: Icon(Icons.arrow_back, color: AppColors.text),
                    onPressed: () => setState(() => _selectedFolderId = null),
                  )
                  : null,
          actions: [
            if (!isSearchMode)
              IconButton(
                icon: Icon(Icons.search, color: AppColors.text),
                onPressed: () {
                  setState(() => isSearchMode = true);
                  Future.delayed(
                    const Duration(milliseconds: 100),
                    () => _searchFocusNode.requestFocus(),
                  );
                },
                tooltip: 'Поиск',
              ),
            if (isImporting)
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(AppColors.button),
                  ),
                ),
              )
            else
              IconButton(
                icon: Icon(Icons.upload_file, color: AppColors.text),
                onPressed: _importCSV,
                tooltip: 'Импорт CSV',
              ),
            IconButton(
              icon: Icon(Icons.settings, color: AppColors.text),
              onPressed: () async {
                await Navigator.pushNamed(context, '/settings');
                await _loadSeedPhraseSettings();
              },
              tooltip: 'Настройки',
            ),
            IconButton(
              icon: Icon(Icons.add, color: AppColors.text),
              onPressed: _navigateToAddPassword,
            ),
          ],
        ),
        body: Container(
          decoration:
              ThemeManager.currentTheme != AppTheme.dark
                  ? BoxDecoration(color: Colors.black.withOpacity(0.1))
                  : null,
          child:
              isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _buildBody(),
        ),
        bottomNavigationBar: _buildFolderNavBar(),
      ),
    );
  }

  String _folderName(int id) {
    final folder = folders.firstWhere(
      (f) => f['id'] == id,
      orElse: () => {'name': 'Папка'},
    );
    return folder['name'] as String? ?? 'Папка';
  }

  Widget _buildSearchField() {
    return ThemedContainer(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      borderRadius: BorderRadius.circular(12),
      child: TextField(
        controller: _searchController,
        focusNode: _searchFocusNode,
        style: TextStyle(color: AppColors.text),
        decoration: InputDecoration(
          hintText: 'Поиск паролей...',
          hintStyle: TextStyle(color: AppColors.text.withOpacity(0.6)),
          prefixIcon: Icon(
            Icons.search,
            color: AppColors.text.withOpacity(0.6),
          ),
          suffixIcon:
              _searchController.text.isNotEmpty
                  ? IconButton(
                    icon: Icon(
                      Icons.clear,
                      color: AppColors.text.withOpacity(0.6),
                    ),
                    onPressed: _clearSearch,
                  )
                  : null,
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(vertical: 12),
        ),
        onChanged: (value) {
          if (value.isEmpty) {
            _clearSearch();
          } else {
            Future.delayed(const Duration(milliseconds: 300), () {
              if (_searchController.text == value) _searchPasswords(value);
            });
          }
        },
      ),
    );
  }

  Widget _buildBody() {
    if (isSearchMode) {
      return _buildSearchBody();
    }
    return _buildNormalBody();
  }

  Widget _buildSearchBody() {
    if (isSearching) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(color: AppColors.button),
            const SizedBox(height: 16),
            NeonText(
              text: 'Поиск паролей...',
              style: TextStyle(color: AppColors.text.withOpacity(0.7)),
            ),
          ],
        ),
      );
    }
    if (searchResults.isEmpty && _searchController.text.isNotEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.search_off,
              size: 64,
              color: AppColors.text.withOpacity(0.5),
            ),
            const SizedBox(height: 16),
            NeonText(
              text: 'Пароли не найдены',
              style: const TextStyle(fontSize: 18),
            ),
            const SizedBox(height: 8),
            Text(
              'Попробуйте изменить запрос',
              style: TextStyle(
                fontSize: 14,
                color: AppColors.text.withOpacity(0.7),
              ),
            ),
          ],
        ),
      );
    }
    if (searchResults.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.search,
              size: 64,
              color: AppColors.text.withOpacity(0.5),
            ),
            const SizedBox(height: 16),
            NeonText(
              text: 'Введите запрос для поиска',
              style: const TextStyle(fontSize: 18),
            ),
          ],
        ),
      );
    }
    return _buildPasswordsList(searchResults);
  }

  Widget _buildNormalBody() {
    final List<Map<String, dynamic>> filtered =
        _selectedFolderId == null
            ? passwords
            : passwords
                .where((p) => p['folder_id'] == _selectedFolderId)
                .toList();

    return _buildPasswordsSection(filtered);
  }

  // ── Bottom folder nav bar ─────────────────────────────────────────────────

  Widget _buildFolderNavBar() {
    // Calculate counts for each folder locally
    final Map<int?, int> counts = {};
    for (var p in passwords) {
      final fid = p['folder_id'] as int?;
      counts[fid] = (counts[fid] ?? 0) + 1;
    }

    // "All" + actual folders + "+" button
    final items = <Map<String, dynamic>>[
      {
        'id': null,
        'name': 'Все',
        'icon': 'apps',
        'color': '#5D52D2',
        '_count': passwords.length
      },
      ...folders.map((f) {
        final fid = f['id'] as int?;
        return {
          ...f,
          '_count': counts[fid] ?? 0,
        };
      }),
    ];

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border(
          top: BorderSide(color: AppColors.text.withOpacity(0.08), width: 1),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.15),
            blurRadius: 20,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              height: 64,
              child: Row(
                children: [
                  Expanded(
                    child: ListView.builder(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                      itemCount: items.length,
                      itemBuilder: (ctx, i) {
                        final item = items[i];
                        final folderId = item['id'] as int?;
                        final isSelected = _selectedFolderId == folderId;
                        final color = _colorFromHex(item['color'] as String? ?? '#5D52D2');
                        final icon = _iconFromName(item['icon'] as String? ?? 'folder');
                        final count = (item['_count'] ?? item['password_count'] ?? 0) as int;

                        return GestureDetector(
                          onTap: () => setState(() => _selectedFolderId = folderId),
                          onLongPress: folderId != null
                              ? () => _showFolderActions(item)
                              : null,
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            curve: Curves.easeInOut,
                            margin: const EdgeInsets.only(right: 4),
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? color.withOpacity(0.15)
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(20),
                              border: isSelected
                                  ? Border.all(color: color.withOpacity(0.5), width: 1.5)
                                  : null,
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  icon,
                                  size: 16,
                                  color: isSelected
                                      ? color
                                      : AppColors.text.withOpacity(0.5),
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  item['name'] as String? ?? '',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: isSelected
                                        ? FontWeight.w700
                                        : FontWeight.w500,
                                    color: isSelected
                                        ? color
                                        : AppColors.text.withOpacity(0.65),
                                  ),
                                ),
                                const SizedBox(width: 5),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 5, vertical: 1),
                                  decoration: BoxDecoration(
                                    color: isSelected
                                        ? color.withOpacity(0.25)
                                        : AppColors.text.withOpacity(0.07),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    '$count',
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w600,
                                      color: isSelected
                                          ? color
                                          : AppColors.text.withOpacity(0.4),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  // New folder / manage button
                  GestureDetector(
                    onTap: () => _showFolderDialog(),
                    onLongPress: _openFoldersScreen,
                    child: Container(
                      width: 48,
                      height: 48,
                      margin: const EdgeInsets.only(right: 8),
                      decoration: BoxDecoration(
                        color: AppColors.button.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: AppColors.button.withOpacity(0.25),
                          width: 1,
                        ),
                      ),
                      child: Icon(Icons.create_new_folder_outlined,
                          size: 20, color: AppColors.button),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Move-to-folder ────────────────────────────────────────────────────────

  Future<void> _moveToFolder(Map<String, dynamic> item) async {
    if (folders.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppColors.input,
          content: Text(
            'Создайте папку сначала',
            style: TextStyle(color: AppColors.text),
          ),
        ),
      );
      return;
    }

    final int? currentFolderId = item['folder_id'] as int?;
    int? chosen = currentFolderId;

    await showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => DraggableScrollableSheet(
          initialChildSize: 0.55,
          minChildSize: 0.3,
          maxChildSize: 0.85,
          expand: false,
          builder: (_, ctrl) => Column(
            children: [
              const SizedBox(height: 12),
              Container(
                width: 40, height: 4,
                decoration: BoxDecoration(
                  color: AppColors.text.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  children: [
                    Icon(Icons.drive_file_move_outline,
                        color: AppColors.button, size: 22),
                    const SizedBox(width: 10),
                    NeonText(
                      text: 'Переместить в папку',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                        color: AppColors.text,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: ListView(
                  controller: ctrl,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 8),
                  children: [
                    // "No folder" option
                    _FolderMoveItem(
                      icon: Icons.folder_off_outlined,
                      iconColor: AppColors.text.withOpacity(0.4),
                      bgColor: AppColors.input,
                      label: 'Без папки',
                      isSelected: chosen == null,
                      onTap: () async {
                        setSheet(() => chosen = null);
                        Navigator.pop(ctx);
                        await _applyFolderMove(item, null);
                      },
                    ),
                    const SizedBox(height: 4),
                    ...folders.map((folder) {
                      final color = _colorFromHex(
                          folder['color'] as String? ?? '#5D52D2');
                      final icon = _iconFromName(
                          folder['icon'] as String? ?? 'folder');
                      final isHidden =
                          folder['is_hidden'] as bool? ?? false;
                      final isSel = chosen == folder['id'];
                      return _FolderMoveItem(
                        icon: icon,
                        iconColor: color,
                        bgColor: color.withOpacity(0.12),
                        label: folder['name'] as String? ?? '',
                        sublabel: isHidden ? '🔒 Скрытая' : null,
                        isSelected: isSel,
                        onTap: () async {
                          setSheet(() => chosen = folder['id'] as int?);
                          Navigator.pop(ctx);
                          await _applyFolderMove(item, folder['id'] as int?);
                        },
                      );
                    }),
                    const SizedBox(height: 24),
                    // Create new folder shortcut
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: OutlinedButton.icon(
                        onPressed: () {
                          Navigator.pop(ctx);
                          _showFolderDialog();
                        },
                        icon: Icon(Icons.add, color: AppColors.button),
                        label: Text(
                          'Создать новую папку',
                          style: TextStyle(color: AppColors.button),
                        ),
                        style: OutlinedButton.styleFrom(
                          side: BorderSide(
                              color: AppColors.button.withOpacity(0.4)),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _applyFolderMove(
      Map<String, dynamic> item, int? folderId) async {
    final id = item['id'] as int?;
    if (id == null) return;

    // Purely local — no server call.
    await FolderService.setFolderForPassword(id, folderId);

    if (!mounted) return;

    // Update in-memory list immediately.
    setState(() {
      passwords = passwords.map((p) {
        if (p['id'] == id) return {...p, 'folder_id': folderId};
        return p;
      }).toList();
    });

    // Reload folder counts in the bottom nav bar.
    await _loadFolders();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.green,
          content: Row(
            children: [
              const Icon(Icons.check_circle, color: Colors.white, size: 18),
              const SizedBox(width: 8),
              Text(
                folderId == null ? 'Удалено из папки' : 'Перемещено в папку',
                style: const TextStyle(color: Colors.white),
              ),
            ],
          ),
        ),
      );
    }
  }

  Future<void> _showFolderDialog({Map<String, dynamic>? existing}) async {
    final nameController = TextEditingController(text: existing?['name'] ?? '');
    String selectedColor = existing?['color'] as String? ?? '#5D52D2';
    String selectedIcon = existing?['icon'] as String? ?? 'folder';
    bool isHidden = existing?['is_hidden'] as bool? ?? false;

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          return AlertDialog(
            backgroundColor: AppColors.surface,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: NeonText(
              text: existing == null ? 'Новая папка' : 'Редактировать папку',
              style: TextStyle(
                color: AppColors.text,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 64,
                      height: 64,
                      decoration: BoxDecoration(
                        color: _colorFromHex(selectedColor).withOpacity(0.2),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: _colorFromHex(selectedColor), width: 2),
                      ),
                      child: Icon(
                        _iconFromName(selectedIcon),
                        color: _colorFromHex(selectedColor),
                        size: 32,
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  ThemedTextField(
                    controller: nameController,
                    hintText: 'Название папки',
                    prefixIcon: Icon(Icons.drive_file_rename_outline, color: AppColors.button),
                  ),
                  const SizedBox(height: 20),
                  // Hidden folder toggle
                  GestureDetector(
                    onTap: () => setDialogState(() => isHidden = !isHidden),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: isHidden
                            ? AppColors.button.withOpacity(0.12)
                            : AppColors.input,
                        borderRadius: BorderRadius.circular(12),
                        border: isHidden
                            ? Border.all(color: AppColors.button.withOpacity(0.4))
                            : null,
                      ),
                      child: Row(
                        children: [
                          Icon(
                            isHidden ? Icons.lock : Icons.lock_open,
                            color: isHidden ? AppColors.button : AppColors.text.withOpacity(0.5),
                            size: 18,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Скрытая папка',
                                    style: TextStyle(
                                        color: AppColors.text,
                                        fontWeight: FontWeight.w600,
                                        fontSize: 14)),
                                Text('Требует TOTP для просмотра',
                                    style: TextStyle(
                                        color: AppColors.text.withOpacity(0.5),
                                        fontSize: 11)),
                              ],
                            ),
                          ),
                          Switch(
                            value: isHidden,
                            onChanged: (v) => setDialogState(() => isHidden = v),
                            activeColor: AppColors.button,
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'Цвет',
                    style: TextStyle(
                      color: AppColors.text.withOpacity(0.7),
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _kFolderColors.map((hex) {
                      final isSelected = hex == selectedColor;
                      return GestureDetector(
                        onTap: () => setDialogState(() => selectedColor = hex),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 150),
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            color: _colorFromHex(hex),
                            borderRadius: BorderRadius.circular(8),
                            border: isSelected ? Border.all(color: Colors.white, width: 2.5) : null,
                            boxShadow: isSelected
                                ? [BoxShadow(color: _colorFromHex(hex).withOpacity(0.6), blurRadius: 8)]
                                : null,
                          ),
                          child: isSelected ? const Icon(Icons.check, color: Colors.white, size: 18) : null,
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'Иконка',
                    style: TextStyle(
                      color: AppColors.text.withOpacity(0.7),
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _kFolderIcons.map((entry) {
                      final name = entry['name'] as String? ?? 'Без имени';
                      final iconData = entry['icon'] as IconData;
                      final isSelected = name == selectedIcon;
                      return GestureDetector(
                        onTap: () => setDialogState(() => selectedIcon = name),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 150),
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: isSelected ? _colorFromHex(selectedColor).withOpacity(0.25) : AppColors.input,
                            borderRadius: BorderRadius.circular(10),
                            border: isSelected ? Border.all(color: _colorFromHex(selectedColor), width: 1.5) : null,
                          ),
                          child: Icon(
                            iconData,
                            color: isSelected ? _colorFromHex(selectedColor) : AppColors.text.withOpacity(0.6),
                            size: 20,
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text('Отмена', style: TextStyle(color: AppColors.text.withOpacity(0.6))),
              ),
              ThemedButton(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                onPressed: () async {
                  final name = nameController.text.trim();
                  if (name.isEmpty) return;

                  if (existing == null) {
                    await FolderService.createFolder(
                      name: name,
                      color: selectedColor,
                      icon: selectedIcon,
                      isHidden: isHidden,
                    );
                  } else {
                    await FolderService.updateFolder(
                      existing['id'] as int,
                      name: name,
                      color: selectedColor,
                      icon: selectedIcon,
                      isHidden: isHidden,
                    );
                  }
                  if (ctx.mounted) Navigator.pop(ctx, true);
                },
                child: Text(
                  existing == null ? 'Создать' : 'Сохранить',
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          );
        },
      ),
    );

    if (result == true) _loadFolders();
  }

  void _showFolderActions(Map<String, dynamic> folder) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.text.withOpacity(0.2),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            NeonText(
              text: folder['name'] as String? ?? '',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.text),
            ),
            const SizedBox(height: 16),
            ListTile(
              leading: Icon(Icons.edit, color: AppColors.button),
              title: Text('Редактировать', style: TextStyle(color: AppColors.text)),
              onTap: () {
                Navigator.pop(ctx);
                _showFolderDialog(existing: folder);
              },
            ),
            ListTile(
              leading: Icon(Icons.delete_outline, color: AppColors.error),
              title: Text('Удалить папку', style: TextStyle(color: AppColors.error)),
              onTap: () {
                Navigator.pop(ctx);
                _deleteFolder(folder);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _deleteFolder(Map<String, dynamic> folder) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: NeonText(text: 'Удалить папку?', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        content: Text(
          'Папка «${folder['name']}» будет удалена.\nПароли из этой папки останутся в общем списке.',
          style: TextStyle(color: AppColors.text.withOpacity(0.8)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Отмена', style: TextStyle(color: AppColors.text.withOpacity(0.6))),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Удалить', style: TextStyle(color: AppColors.error)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await FolderService.deleteFolder(folder['id'] as int);
      _loadFolders();
      if (_selectedFolderId == folder['id']) {
        setState(() => _selectedFolderId = null);
      }
    }
  }

  Widget _buildPasswordsSection(List<Map<String, dynamic>> filtered) {
    if (filtered.isEmpty) {
      return Padding(
        padding: const EdgeInsets.only(top: 80),
        child: Center(
          child: Column(
            children: [
              Icon(
                _selectedFolderId != null ? Icons.folder_open : Icons.lock_open,
                size: 72,
                color: AppColors.text.withOpacity(0.2),
              ),
              const SizedBox(height: 20),
              NeonText(
                text:
                    _selectedFolderId != null
                        ? 'Нет паролей в этой папке'
                        : 'У вас пока нет сохранённых паролей',
                style: const TextStyle(fontSize: 16),
              ),
            ],
          ),
        ),
      );
    }
    return _buildPasswordsList(filtered);
  }

  void _showPasswordContextMenu(Map<String, dynamic> item) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 36, height: 4,
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: AppColors.text.withOpacity(0.2),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
              child: Row(
                children: [
                  Container(
                    width: 38, height: 38,
                    decoration: BoxDecoration(
                      color: AppColors.button.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(Icons.web, color: AppColors.button, size: 18),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item['title'] ?? '',
                          style: TextStyle(
                            color: AppColors.text,
                            fontWeight: FontWeight.w700,
                            fontSize: 15,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          item['subtitle'] ?? '',
                          style: TextStyle(
                            color: AppColors.text.withOpacity(0.6),
                            fontSize: 13,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Divider(color: AppColors.text.withOpacity(0.08), height: 16),
            ListTile(
              leading: Container(
                width: 36, height: 36,
                decoration: BoxDecoration(
                  color: AppColors.button.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(Icons.drive_file_move_outline,
                    color: AppColors.button, size: 18),
              ),
              title: Text('Переместить в папку',
                  style: TextStyle(color: AppColors.text, fontSize: 15)),
              subtitle: Text(
                item['folder_id'] != null ? 'Изменить папку' : 'Добавить в папку',
                style: TextStyle(color: AppColors.text.withOpacity(0.5), fontSize: 12),
              ),
              onTap: () {
                Navigator.pop(ctx);
                _moveToFolder(item);
              },
            ),
            ListTile(
              leading: Container(
                width: 36, height: 36,
                decoration: BoxDecoration(
                  color: Colors.blue.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.share, color: Colors.blue, size: 18),
              ),
              title: Text('Поделиться паролем',
                  style: TextStyle(color: AppColors.text, fontSize: 15)),
              onTap: () {
                Navigator.pop(ctx);
                _sharePassword(item);
              },
            ),
            ListTile(
              leading: Container(
                width: 36, height: 36,
                decoration: BoxDecoration(
                  color: Colors.orange.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.edit_outlined,
                    color: Colors.orange, size: 18),
              ),
              title: Text('Редактировать',
                  style: TextStyle(color: AppColors.text, fontSize: 15)),
              onTap: () {
                Navigator.pop(ctx);
                _navigateToEditPassword(item);
              },
            ),
            ListTile(
              leading: Container(
                width: 36, height: 36,
                decoration: BoxDecoration(
                  color: Colors.green.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.copy_outlined,
                    color: Colors.green, size: 18),
              ),
              title: Text('Скопировать пароль',
                  style: TextStyle(color: AppColors.text, fontSize: 15)),
              onTap: () {
                Navigator.pop(ctx);
                _copyPassword(item['encrypted_payload'] ?? '');
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget _buildPasswordsList(List<Map<String, dynamic>> passwordsToShow) {
    final visiblePasswords =
        passwordsToShow
            .where(
              (item) => !(item['has_seed_phrase'] == true && _hideSeedPhrases),
            )
            .toList();

    if (visiblePasswords.isEmpty && _hideSeedPhrases) {
      return Padding(
        padding: const EdgeInsets.only(top: 80),
        child: Center(
          child: Column(
            children: [
              Icon(
                Icons.visibility_off,
                size: 64,
                color: AppColors.text.withOpacity(0.5),
              ),
              const SizedBox(height: 16),
              NeonText(
                text: 'Все записи с seed фразами скрыты',
                style: const TextStyle(fontSize: 16),
              ),
              const SizedBox(height: 8),
              Text(
                'Отключите скрытие в настройках, чтобы увидеть записи',
                style: TextStyle(
                  fontSize: 14,
                  color: AppColors.text.withOpacity(0.7),
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    return ListView.builder(
      itemCount: passwordsToShow.length,
      padding: const EdgeInsets.only(left: 16, right: 16, top: 16, bottom: 100),
      itemBuilder: (context, index) {
        final item = passwordsToShow[index];
        if (item['has_seed_phrase'] == true && _hideSeedPhrases) {
          return const SizedBox.shrink();
        }

        // Folder badge
        final folderId = item['folder_id'] as int?;
        Map<String, dynamic>? itemFolder;
        if (folderId != null) {
          try {
            itemFolder = folders.firstWhere((f) => f['id'] == folderId);
          } catch (_) {}
        }

        return ThemedContainer(
          margin: const EdgeInsets.only(bottom: 16),
          child: InkWell(
            onTap: () => _navigateToDetail(item),
            onLongPress: () => _showPasswordContextMenu(item),
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            if (item['favicon_url'] != null ||
                                item['title'] != null)
                              Container(
                                margin: const EdgeInsets.only(right: 12),
                                width: 24,
                                height: 24,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(6),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withOpacity(0.1),
                                      blurRadius: 4,
                                      offset: const Offset(0, 2),
                                    ),
                                  ],
                                ),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(6),
                                  child:
                                      item['favicon_url'] != null
                                          ? Image.network(
                                            item['favicon_url'],
                                            width: 24,
                                            height: 24,
                                            fit: BoxFit.cover,
                                            loadingBuilder: (
                                              ctx,
                                              child,
                                              progress,
                                            ) {
                                              if (progress == null)
                                                return child;
                                              return Shimmer.fromColors(
                                                baseColor: AppColors.input,
                                                highlightColor:
                                                    AppColors.background,
                                                child: Container(
                                                  width: 24,
                                                  height: 24,
                                                  decoration: BoxDecoration(
                                                    color: Colors.white,
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          6,
                                                        ),
                                                  ),
                                                ),
                                              );
                                            },
                                            errorBuilder:
                                                (_, __, ___) =>
                                                    _buildFallbackFavicon(
                                                      item['title'],
                                                    ),
                                          )
                                          : _buildFallbackFavicon(
                                            item['title'],
                                          ),
                                ),
                              ),
                            Expanded(
                              child: NeonText(
                                text: (item['title'] ?? '')
                                    .replaceAll('https://', '')
                                    .replaceAll('http://', ''),
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                        if (item['subtitle'] != null &&
                            item['subtitle'].toString().isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              item['subtitle'],
                              style: TextStyle(
                                fontSize: 14,
                                color: AppColors.text.withOpacity(0.7),
                              ),
                            ),
                          ),
                        // Folder badge
                        if (itemFolder != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  _iconFromName(
                                    itemFolder['icon'] as String? ?? 'folder',
                                  ),
                                  size: 12,
                                  color: _colorFromHex(
                                    itemFolder['color'] as String? ?? '#5D52D2',
                                  ),
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  itemFolder['name'] as String? ?? '',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: _colorFromHex(
                                      itemFolder['color'] as String? ??
                                          '#5D52D2',
                                    ),
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (item['has_2fa'] == true) ...[
                        Icon(
                          Icons.verified_user,
                          color:
                              ThemeManager.colors.hasNeonGlow
                                  ? AppColors.accent
                                  : AppColors.text,
                          size: 20,
                        ),
                        const SizedBox(width: 12),
                      ],
                      // Rotation due indicator
                      if (item['rotation_enabled'] == true &&
                          _isRotationDue(item)) ...[
                        Tooltip(
                          message: 'Password rotation due',
                          child: Icon(Icons.autorenew,
                              color: Colors.orange, size: 20),
                        ),
                        const SizedBox(width: 4),
                      ],
                      if (item['has_seed_phrase'] == true) ...[
                        IconButton(
                          icon: Icon(Icons.vpn_key, color: AppColors.button),
                          onPressed: () => _navigateToDetail(item),
                          tooltip: 'Открыть запись с seed-фразой',
                        ),
                        const SizedBox(width: 12),
                      ],
                      // Share button
                      IconButton(
                        icon: Icon(Icons.share, color: AppColors.button),
                        onPressed: () => _sharePassword(item),
                        tooltip: 'Поделиться паролем',
                      ),
                      IconButton(
                        icon: Icon(Icons.edit, color: AppColors.button),
                        onPressed: () => _navigateToEditPassword(item),
                        tooltip: 'Редактировать',
                      ),
                      IconButton(
                        icon: Icon(Icons.copy, color: AppColors.button),
                        onPressed: () => _copyPassword(item['encrypted_payload'] ?? ''),
                        tooltip: 'Копировать пароль',
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

// ── Folder move item ──────────────────────────────────────────────────────────

class _FolderMoveItem extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final Color bgColor;
  final String label;
  final String? sublabel;
  final bool isSelected;
  final VoidCallback onTap;

  const _FolderMoveItem({
    required this.icon,
    required this.iconColor,
    required this.bgColor,
    required this.label,
    this.sublabel,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: isSelected
              ? iconColor.withOpacity(0.12)
              : AppColors.input,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isSelected ? iconColor.withOpacity(0.5) : Colors.transparent,
            width: 1.5,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: bgColor,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: iconColor, size: 20),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      color: AppColors.text,
                      fontSize: 15,
                      fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                  if (sublabel != null)
                    Text(
                      sublabel!,
                      style: TextStyle(
                        color: AppColors.text.withOpacity(0.5),
                        fontSize: 12,
                      ),
                    ),
                ],
              ),
            ),
            if (isSelected)
              Icon(Icons.check_circle, color: iconColor, size: 20),
          ],
        ),
      ),
    );
  }
}
