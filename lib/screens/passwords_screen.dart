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

      setState(() {
        passwords = list.map<Map<String, dynamic>>((item) => {
          'id':               item['id'],
          'title':            item['title']    ?? item['name'] ?? item['site_url'] ?? 'Безымянный',
          'subtitle':         item['subtitle'] ?? item['site_login'] ?? 'Нет логина',
          'site_url':         item['site_url']  ?? '',
          // Keep encrypted payload for on-demand decryption in PasswordDetailScreen
          'encrypted_payload':      item['encrypted_payload'],
          'notes_encrypted':        item['notes_encrypted'],
          'seed_phrase_encrypted':  item['seed_phrase_encrypted'],
          'has_2fa':          item['has_2fa']          ?? false,
          'has_seed_phrase':  item['has_seed_phrase']  ?? false,
          'folder_id':        item['folder_id'],
          'favicon_url':      item['favicon_url'],
          'rotation_interval_days': item['rotation_interval_days'],
          'last_rotated_at':  item['last_rotated_at'],
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
            'notes_encrypted':       item['notes_encrypted'],
            'seed_phrase_encrypted': item['seed_phrase_encrypted'],
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

  void _copySeedPhrase(String seedPhrase) {
    if (seedPhrase.isEmpty) return;
    Clipboard.setData(ClipboardData(text: seedPhrase));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: AppColors.accent,
        content: const Row(
          children: [
            Icon(Icons.check_circle, color: Colors.white),
            SizedBox(width: 10),
            Text(
              'Seed фраза скопирована в буфер обмена',
              style: TextStyle(color: Colors.white),
            ),
          ],
        ),
      ),
    );
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
    // Filter passwords by selected folder
    final List<Map<String, dynamic>> filtered =
        _selectedFolderId == null
            ? passwords
            : passwords
                .where((p) => p['folder_id'] == _selectedFolderId)
                .toList();

    return CustomScrollView(
      slivers: [
        // Folder bar (only when viewing all)
        if (_selectedFolderId == null && folders.isNotEmpty)
          SliverToBoxAdapter(child: _buildFolderBar()),

        // Password list
        SliverToBoxAdapter(child: _buildPasswordsSection(filtered)),
      ],
    );
  }

  Widget _buildFolderBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              NeonText(
                text: 'Папки',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppColors.text.withOpacity(0.7),
                ),
              ),
              GestureDetector(
                onTap: _openFoldersScreen,
                child: Text(
                  'Управление',
                  style: TextStyle(
                    fontSize: 13,
                    color: AppColors.button,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 96,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: folders.length + 2, // +1 for "All" chip, +1 for "Add" chip
              separatorBuilder: (_, __) => const SizedBox(width: 10),
              itemBuilder: (context, index) {
                if (index == folders.length + 1) {
                  return _buildAddFolderChip();
                }
                if (index == 0) {
                  return _buildFolderChip(
                    label: 'Все',
                    icon: Icons.apps,
                    color: AppColors.button,
                    count: passwords.length,
                    isSelected: _selectedFolderId == null,
                    onTap: () => setState(() => _selectedFolderId = null),
                    onLongPress: () {}, // No actions for "All" chip
                  );
                }
                final folder = folders[index - 1];
                final color = _colorFromHex(
                  folder['color'] as String? ?? '#5D52D2',
                );
                final iconData = _iconFromName(
                  folder['icon'] as String? ?? 'folder',
                );
                final isSelected = _selectedFolderId == folder['id'];
                final count = folder['password_count'] ?? 0;

                return _buildFolderChip(
                  label: folder['name'] as String? ?? '',
                  icon: iconData,
                  color: color,
                  count: count,
                  isSelected: isSelected,
                  onTap: () => setState(() => _selectedFolderId = folder['id'] as int),
                  onLongPress: () => _showFolderActions(folder),
                );
              },
            ),
          ),
          const SizedBox(height: 8),
          Divider(color: AppColors.text.withOpacity(0.08), height: 1),
        ],
      ),
    );
  }

  Widget _buildFolderChip({
    required String label,
    required IconData icon,
    required Color color,
    required int count,
    required bool isSelected,
    required VoidCallback onTap,
    required VoidCallback onLongPress,
  }) {
    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeInOut,
        width: 76,
        decoration: BoxDecoration(
          color: isSelected ? color.withOpacity(0.15) : AppColors.input,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? color : AppColors.text.withOpacity(0.06),
            width: isSelected ? 1.5 : 1,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: color.withOpacity(
                      ThemeManager.colors.hasNeonGlow ? 0.35 : 0.15,
                    ),
                    blurRadius: ThemeManager.colors.hasNeonGlow ? 12 : 6,
                    spreadRadius: 0,
                  ),
                ]
              : null,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: isSelected
                    ? color.withOpacity(0.25)
                    : AppColors.text.withOpacity(0.07),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                icon,
                color: isSelected ? color : AppColors.text.withOpacity(0.45),
                size: 20,
              ),
            ),
            const SizedBox(height: 5),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 10.5,
                  color: isSelected ? color : AppColors.text.withOpacity(0.75),
                  fontWeight:
                      isSelected ? FontWeight.w700 : FontWeight.w500,
                  letterSpacing: -0.2,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: 2),
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(
                color: isSelected
                    ? color.withOpacity(0.2)
                    : AppColors.text.withOpacity(0.06),
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
  }

  Widget _buildAddFolderChip() {
    return GestureDetector(
      onTap: () => _showFolderDialog(),
      child: Container(
        width: 76,
        decoration: BoxDecoration(
          color: AppColors.input,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: AppColors.button.withOpacity(0.25),
            width: 1,
            style: BorderStyle.solid,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: AppColors.button.withOpacity(0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(Icons.add, color: AppColors.button, size: 20),
            ),
            const SizedBox(height: 5),
            Text(
              'Новая',
              style: TextStyle(
                fontSize: 10.5,
                color: AppColors.button.withOpacity(0.85),
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
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
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: passwordsToShow.length,
      padding: const EdgeInsets.all(16),
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
                          onPressed:
                              () => _copySeedPhrase(item['seed_phrase'] ?? ''),
                          tooltip: 'Копировать seed фразу',
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
                        onPressed: () => _copyPassword(item['password'] ?? ''),
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
