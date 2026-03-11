import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:file_picker/file_picker.dart';
import 'package:shimmer/shimmer.dart';
import '../theme/colors.dart';
import '../widgets/themed_widgets.dart';
import '../main.dart';
import 'edit_password_screen.dart';
import 'folders_screen.dart';
import '../config/app_config.dart';
import '../utils/api_service.dart';
import '../utils/folder_service.dart';
import '../services/vault_service.dart';
import '../services/cache_service.dart';

// ── helpers ──────────────────────────────────────────────────────────────────

Color _colorFromHex(String hex) {
  try {
    return Color(int.parse(hex.replaceFirst('#', '0xFF')));
  } catch (_) {
    return const Color(0xFF5D52D2);
  }
}

IconData _iconFromName(String name) {
  const map = {
    'folder': Icons.folder,
    'work': Icons.work,
    'home': Icons.home,
    'lock': Icons.lock,
    'star': Icons.star,
    'favorite': Icons.favorite,
    'shopping_cart': Icons.shopping_cart,
    'school': Icons.school,
    'code': Icons.code,
    'gaming': Icons.sports_esports,
    'bank': Icons.account_balance,
    'email': Icons.email,
    'cloud': Icons.cloud,
    'social': Icons.people,
    'crypto': Icons.currency_bitcoin,
    'vpn_key': Icons.vpn_key,
  };
  return map[name] ?? Icons.folder;
}

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
    final result = await FolderService.getFolders();
    if (mounted) {
      setState(() => folders = result);
    }
  }

  Future<void> _loadPasswords() async {
    setState(() => isLoading = true);
    await _loadSeedPhraseSettings();

    try {
      final decryptedData = await VaultService().syncVault();
      
      setState(() {
        passwords = decryptedData.map<Map<String, dynamic>>((item) => {
          'id': item['id'],
          'title': item['name'] ?? item['site_url'] ?? 'Безымянный', // From metadata
          'subtitle': item['site_login'] ?? 'Нет логина', // From metadata
          'password': item['encrypted_payload'], // Still encrypted
          'has_2fa': item['has_2fa'],
          'has_seed_phrase': item['has_seed_phrase'],
          'seed_phrase': item['seed_phrase'],
          'notes_encrypted': item['notes_encrypted'],
          'favicon_url': item['favicon_url'],
          'folder_id': item['folder_id'],
          'site_url': item['site_url'], // From metadata
        }).toList();
        isLoading = false;
      });
    } catch (e) {
      // If error, try to load from cache
      final cachedHashes = CacheService().getAllCachedHashes();
      if (cachedHashes.isNotEmpty) {
        final List<Map<String, dynamic>> cachedList = [];
        for (var hash in cachedHashes) {
          final pwd = CacheService().getCachedPassword(hash);
          if (pwd != null) cachedList.add(pwd);
        }
        
        setState(() {
          passwords = cachedList; // Already partially decrypted metadata if synced before
          isLoading = false;
        });
      } else {
        setState(() => isLoading = false);
      }
    }
  }

  Future<void> _loadSeedPhraseSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (mounted) {
        setState(() => _hideSeedPhrases = prefs.getBool('hide_seed_phrases') ?? false);
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
      if (result == null) return;

      setState(() => isImporting = true);

      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('token');

      final request = http.MultipartRequest(
        'POST',
        Uri.parse(AppConfig.importPasswordsUrl),
      );
      request.headers.addAll({
        'Authorization': 'Bearer $token',
        'Accept': 'application/json',
      });
      request.files.add(
        http.MultipartFile.fromBytes(
          'file',
          result.files.single.bytes!,
          filename: result.files.single.name,
        ),
      );

      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);
      final data = json.decode(response.body);

      if (response.statusCode == 200) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Colors.green,
            content: Text('Импортировано: ${data['imported']}, Ошибок: ${data['failed']}'),
          ),
        );
        _loadPasswords();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Colors.red,
            content: Text(data['error'] ?? 'Ошибка при импорте'),
          ),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.red,
          content: Text('Ошибка при импорте файла: ${e.toString()}'),
        ),
      );
    } finally {
      setState(() => isImporting = false);
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
            '${AppConfig.baseUrl}/passwords/search/${Uri.encodeComponent(query.trim())}'),
        headers: {'Authorization': 'Bearer $token'},
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final List results = data['results'] ?? [];
        setState(() {
          searchResults = results.map<Map<String, dynamic>>((item) => {
            'id': item['id'],
            'title': item['site_url'],
            'subtitle': item['site_login'],
            'password': item['site_password'],
            'has_2fa': item['has_2fa'],
            'has_seed_phrase': item['has_seed_phrase'],
            'seed_phrase': item['seed_phrase'],
            'notes': item['notes'],
            'favicon_url': item['favicon_url'],
            'folder_id': item['folder_id'],
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
    Navigator.pushNamed(context, '/sharing');
  }

  // ── clipboard helpers ───────────────────────────────────────────────────────

  void _copyPassword(String encryptedPassword) async {
    if (encryptedPassword.isEmpty) return;
    
    try {
      final decrypted = await VaultService().decryptPayload(encryptedPassword);
      Clipboard.setData(ClipboardData(text: decrypted));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppColors.button,
          content: const Row(children: [
            Icon(Icons.check_circle, color: Colors.white),
            SizedBox(width: 10),
            Text('Пароль дешифрован и скопирован', style: TextStyle(color: Colors.white)),
          ]),
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: Colors.red,
          content: Text('Ошибка дешифрования'),
        ),
      );
    }
  }

  void _copySeedPhrase(String seedPhrase) {
    if (seedPhrase.isEmpty) return;
    Clipboard.setData(ClipboardData(text: seedPhrase));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: AppColors.accent,
        content: const Row(children: [
          Icon(Icons.check_circle, color: Colors.white),
          SizedBox(width: 10),
          Text('Seed фраза скопирована в буфер обмена', style: TextStyle(color: Colors.white)),
        ]),
      ),
    );
  }

  // ── navigation ──────────────────────────────────────────────────────────────

  void _navigateToAddPassword() async {
    final result = await Navigator.pushNamed(context, '/add');
    if (result == true) _loadAll();
  }

  void _navigateToEditPassword(Map<String, dynamic> password) async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => EditPasswordScreen(password: password)),
    );

    if (result == true) {
      await _loadAll();
    } else if (result != null && result['success'] == true) {
      setState(() {
        final index = passwords.indexWhere(
            (p) => p['id'] == password['id'] || p['title'] == password['title']);
        if (index != -1) {
          passwords[index] = {
            'id': result['data']['id'],
            'title': result['data']['title'],
            'subtitle': result['data']['subtitle'],
            'password': result['data']['password'],
            'has_2fa': result['data']['has_2fa'],
            'has_seed_phrase': result['data']['has_seed_phrase'],
            'seed_phrase': result['data']['seed_phrase'],
            'notes': result['data']['notes'],
            'favicon_url': result['data']['favicon_url'],
            'folder_id': result['data']['folder_id'],
          };
        }
      });
      await _loadAll();
    }
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
      final faviconUrl = 'https://www.google.com/s2/favicons?domain=$domain&sz=32';

      return Image.network(
        faviconUrl,
        width: 24,
        height: 24,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => Container(
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
          title: isSearchMode
              ? _buildSearchField()
              : NeonText(
                  text: _selectedFolderId == null
                      ? 'Пароли'
                      : _folderName(_selectedFolderId!),
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
          backgroundColor: ThemeManager.currentTheme == AppTheme.dark
              ? AppColors.background
              : Colors.black.withOpacity(0.3),
          elevation: 0,
          leading: _selectedFolderId != null
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
          decoration: ThemeManager.currentTheme != AppTheme.dark
              ? BoxDecoration(color: Colors.black.withOpacity(0.1))
              : null,
          child: isLoading
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
          prefixIcon: Icon(Icons.search, color: AppColors.text.withOpacity(0.6)),
          suffixIcon: _searchController.text.isNotEmpty
              ? IconButton(
                  icon: Icon(Icons.clear, color: AppColors.text.withOpacity(0.6)),
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
            Icon(Icons.search_off, size: 64, color: AppColors.text.withOpacity(0.5)),
            const SizedBox(height: 16),
            NeonText(text: 'Пароли не найдены', style: const TextStyle(fontSize: 18)),
            const SizedBox(height: 8),
            Text(
              'Попробуйте изменить запрос',
              style: TextStyle(fontSize: 14, color: AppColors.text.withOpacity(0.7)),
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
            Icon(Icons.search, size: 64, color: AppColors.text.withOpacity(0.5)),
            const SizedBox(height: 16),
            NeonText(text: 'Введите запрос для поиска', style: const TextStyle(fontSize: 18)),
          ],
        ),
      );
    }
    return _buildPasswordsList(searchResults);
  }

  Widget _buildNormalBody() {
    // Filter passwords by selected folder
    final List<Map<String, dynamic>> filtered = _selectedFolderId == null
        ? passwords
        : passwords.where((p) => p['folder_id'] == _selectedFolderId).toList();

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
            height: 90,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: folders.length + 1, // +1 for "All" chip
              separatorBuilder: (_, __) => const SizedBox(width: 10),
              itemBuilder: (context, index) {
                if (index == 0) {
                  return _buildFolderChip(
                    label: 'Все',
                    icon: Icons.apps,
                    color: AppColors.button,
                    count: passwords.length,
                    isSelected: _selectedFolderId == null,
                    onTap: () => setState(() => _selectedFolderId = null),
                  );
                }
                final folder = folders[index - 1];
                final color = _colorFromHex(folder['color'] as String? ?? '#5D52D2');
                final iconData = _iconFromName(folder['icon'] as String? ?? 'folder');
                final isSelected = _selectedFolderId == folder['id'];
                final count = passwords.where((p) => p['folder_id'] == folder['id']).length;

                return _buildFolderChip(
                  label: folder['name'] as String? ?? '',
                  icon: iconData,
                  color: color,
                  count: count,
                  isSelected: isSelected,
                  onTap: () => setState(() => _selectedFolderId = folder['id'] as int),
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
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        width: 80,
        decoration: BoxDecoration(
          color: isSelected ? color.withOpacity(0.2) : AppColors.input,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isSelected ? color : Colors.transparent,
            width: 1.5,
          ),
          boxShadow: isSelected && ThemeManager.colors.hasNeonGlow
              ? [BoxShadow(color: color.withOpacity(0.4), blurRadius: 10)]
              : null,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: isSelected ? color : AppColors.text.withOpacity(0.5), size: 22),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                color: isSelected ? color : AppColors.text.withOpacity(0.7),
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.normal,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 2),
            Text(
              '$count',
              style: TextStyle(
                fontSize: 11,
                color: isSelected ? color.withOpacity(0.8) : AppColors.text.withOpacity(0.4),
              ),
            ),
          ],
        ),
      ),
    );
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
                text: _selectedFolderId != null
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
    final visiblePasswords = passwordsToShow
        .where((item) => !(item['has_seed_phrase'] == true && _hideSeedPhrases))
        .toList();

    if (visiblePasswords.isEmpty && _hideSeedPhrases) {
      return Padding(
        padding: const EdgeInsets.only(top: 80),
        child: Center(
          child: Column(
            children: [
              Icon(Icons.visibility_off, size: 64, color: AppColors.text.withOpacity(0.5)),
              const SizedBox(height: 16),
              NeonText(text: 'Все записи с seed фразами скрыты', style: const TextStyle(fontSize: 16)),
              const SizedBox(height: 8),
              Text(
                'Отключите скрытие в настройках, чтобы увидеть записи',
                style: TextStyle(fontSize: 14, color: AppColors.text.withOpacity(0.7)),
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
            onTap: () => _navigateToEditPassword(item),
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
                            if (item['favicon_url'] != null || item['title'] != null)
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
                                  child: item['favicon_url'] != null
                                      ? Image.network(
                                          item['favicon_url'],
                                          width: 24,
                                          height: 24,
                                          fit: BoxFit.cover,
                                          loadingBuilder: (ctx, child, progress) {
                                            if (progress == null) return child;
                                            return Shimmer.fromColors(
                                              baseColor: AppColors.input,
                                              highlightColor: AppColors.background,
                                              child: Container(
                                                width: 24,
                                                height: 24,
                                                decoration: BoxDecoration(
                                                  color: Colors.white,
                                                  borderRadius: BorderRadius.circular(6),
                                                ),
                                              ),
                                            );
                                          },
                                          errorBuilder: (_, __, ___) =>
                                              _buildFallbackFavicon(item['title']),
                                        )
                                      : _buildFallbackFavicon(item['title']),
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
                        if (item['subtitle'] != null && item['subtitle'].toString().isNotEmpty)
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
                                  _iconFromName(itemFolder['icon'] as String? ?? 'folder'),
                                  size: 12,
                                  color: _colorFromHex(
                                      itemFolder['color'] as String? ?? '#5D52D2'),
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  itemFolder['name'] as String? ?? '',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: _colorFromHex(
                                        itemFolder['color'] as String? ?? '#5D52D2'),
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        if (item['notes'] != null && item['notes'].toString().isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              item['notes'],
                              style: TextStyle(
                                fontSize: 12,
                                color: AppColors.text.withOpacity(0.6),
                                fontStyle: FontStyle.italic,
                              ),
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
                          color: ThemeManager.colors.hasNeonGlow
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
                          onPressed: () => _copySeedPhrase(item['seed_phrase'] ?? ''),
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
