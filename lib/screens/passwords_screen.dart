import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:file_picker/file_picker.dart';
import 'package:shimmer/shimmer.dart';
import '../theme/colors.dart';
import '../widgets/themed_widgets.dart';
import '../main.dart'; // Импортируйте routeObserver
import 'edit_password_screen.dart';
import '../config/app_config.dart';
import '../utils/api_service.dart';

class PasswordsScreen extends StatefulWidget {
  const PasswordsScreen({super.key});

  @override
  State<PasswordsScreen> createState() => _PasswordsScreenState();
}

class _PasswordsScreenState extends State<PasswordsScreen> with RouteAware {
  List<Map<String, dynamic>> passwords = [];
  List<Map<String, dynamic>> searchResults = [];
  bool isLoading = true;
  bool isImporting = false;
  bool _hideSeedPhrases = false;
  bool isSearching = false;
  bool isSearchMode = false;
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _loadPasswords();
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
    // Вызывается при возвращении на этот экран
    _loadPasswords();
  }

  Future<void> _loadPasswords() async {
    setState(() {
      isLoading = true;
    });

    // Загружаем настройки перед загрузкой паролей
    await _loadSeedPhraseSettings();

    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('token');

      final response = await ApiService.get(
        AppConfig.passwordsUrl,
        headers: {'Authorization': 'Bearer $token'},
      );

      if (response.statusCode == 200) {
        final List data = json.decode(response.body);
        print('DEBUG: Получены пароли от сервера:');
        for (var item in data) {
          print('DEBUG: ${item['site_url']} - favicon_url: ${item['favicon_url']}');
          
          // Специальная отладка для MetaMask
          if (item['site_url'] != null && item['site_url'].toString().toLowerCase().contains('metamask')) {
            print('DEBUG: METAMASK НАЙДЕН!');
            print('DEBUG: site_url: ${item['site_url']}');
            print('DEBUG: favicon_url: ${item['favicon_url']}');
            print('DEBUG: Все поля: $item');
          }
        }
        setState(() {
          passwords = data.map<Map<String, dynamic>>((item) => {
                'id': item['id'],
                'title': item['site_url'],
                'subtitle': item['site_login'],
                'password': item['site_password'],
                'has_2fa': item['has_2fa'],
                'has_seed_phrase': item['has_seed_phrase'],
                'seed_phrase': item['seed_phrase'],
                'notes': item['notes'],
                'favicon_url': item['favicon_url'],
              }).toList();
          isLoading = false;
        });
      } else {
        setState(() {
          isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        isLoading = false;
      });
    }
  }

  Future<void> _importCSV() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['csv'],
        withData: true, // Запрашиваем данные файла
      );

      if (result == null) return;

      setState(() {
        isImporting = true;
      });

      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('token');

      final request = http.MultipartRequest(
        'POST',
        Uri.parse(AppConfig.importPasswordsUrl),
      );

      // Добавляем заголовки
      request.headers.addAll({
        'Authorization': 'Bearer $token',
        'Accept': 'application/json',
      });

      // Добавляем файл используя байты
      request.files.add(
        http.MultipartFile.fromBytes(
          'file',
          result.files.single.bytes!, // Используем байты файла
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
            content: Text(
              'Импортировано: ${data['imported']}, Ошибок: ${data['failed']}',
            ),
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
      print('Ошибка импорта: $e'); // Добавляем логирование для отладки
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.red,
          content: Text('Ошибка при импорте файла: ${e.toString()}'),
        ),
      );
    } finally {
      setState(() {
        isImporting = false;
      });
    }
  }

  Future<void> _loadSeedPhraseSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final hideSeedPhrases = prefs.getBool('hide_seed_phrases') ?? false;
      
      print('Loading seed phrase settings: $hideSeedPhrases'); // Отладка
      
      if (mounted) {
        setState(() {
          _hideSeedPhrases = hideSeedPhrases;
        });
        print('Updated _hideSeedPhrases to: $_hideSeedPhrases'); // Отладка
      }
    } catch (e) {
      print('Error loading seed phrase settings: $e'); // Отладка
      // Игнорируем ошибки при загрузке настроек
      if (mounted) {
        setState(() {
          _hideSeedPhrases = false;
        });
      }
    }
  }

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
        Uri.parse('${AppConfig.baseUrl}/passwords/search/${Uri.encodeComponent(query.trim())}'),
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
      print('Ошибка поиска: $e');
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

  void _copyPassword(String password) {
    if (password.isEmpty) return;
    
    Clipboard.setData(ClipboardData(text: password));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: AppColors.button,
        content: Row(
          children: [
            Icon(Icons.check_circle, color: Colors.white),
            const SizedBox(width: 10),
            Text(
              'Пароль скопирован в буфер обмена',
              style: TextStyle(color: Colors.white),
            ),
          ],
        ),
      ),
    );
  }

  void _copySeedPhrase(String seedPhrase) {
    if (seedPhrase.isEmpty) return;
    
    Clipboard.setData(ClipboardData(text: seedPhrase));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: AppColors.accent,
        content: Row(
          children: [
            Icon(Icons.check_circle, color: Colors.white),
            const SizedBox(width: 10),
            Text(
              'Seed фраза скопирована в буфер обмена',
              style: TextStyle(color: Colors.white),
            ),
          ],
        ),
      ),
    );
  }

  void _navigateToAddPassword() async {
    final result = await Navigator.pushNamed(context, '/add');
    if (result == true) {
      _loadPasswords(); // Обновляем список паролей
    }
  }

  void _navigateToEditPassword(Map<String, dynamic> password) async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => EditPasswordScreen(password: password),
      ),
    );
    
    if (result == true) {
      // Пароль был удален, обновляем список
      await _loadPasswords();
    } else if (result != null && result['success'] == true) {
      // Обновляем конкретный пароль в списке
      setState(() {
        // Ищем пароль по ID или по старому названию
        final index = passwords.indexWhere((p) => 
          p['id'] == password['id'] || p['title'] == password['title']
        );
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
          };
        }
      });
      // Затем обновляем весь список для синхронизации
      await _loadPasswords();
    }
  }

  Widget _buildFallbackFavicon(String? siteUrl) {
    print('DEBUG: _buildFallbackFavicon вызван для: $siteUrl');
    
    if (siteUrl == null || siteUrl.isEmpty) {
      print('DEBUG: siteUrl пустой, возвращаем иконку по умолчанию');
      return Container(
        width: 24,
        height: 24,
        decoration: BoxDecoration(
          color: Colors.grey.withOpacity(0.2),
          borderRadius: BorderRadius.circular(6),
        ),
        child: const Icon(
          Icons.language,
          size: 14,
          color: Colors.grey,
        ),
      );
    }

    try {
      // Добавляем протокол, если его нет
      String fullUrl = siteUrl;
      if (!siteUrl.startsWith('http://') && !siteUrl.startsWith('https://')) {
        fullUrl = 'https://$siteUrl';
      }

      // Получаем домен из URL
      final uri = Uri.parse(fullUrl);
      String domain = uri.host;
      
      // Специальная обработка для MetaMask
      if (siteUrl.toLowerCase().contains('metamask')) {
        domain = 'metamask.io';
      }
      
      final faviconUrl = 'https://www.google.com/s2/favicons?domain=$domain&sz=32';
      
      print('DEBUG: Fallback фавиконка для $siteUrl -> $domain -> $faviconUrl');

      return Image.network(
        faviconUrl,
        width: 24,
        height: 24,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) {
          print('DEBUG: Ошибка загрузки fallback фавиконки для $siteUrl ($faviconUrl): $error');
          return Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              color: Colors.grey.withOpacity(0.2),
              borderRadius: BorderRadius.circular(6),
            ),
            child: const Icon(
              Icons.language,
              size: 14,
              color: Colors.grey,
            ),
          );
        },
      );
    } catch (e) {
      print('DEBUG: Исключение в _buildFallbackFavicon для $siteUrl: $e');
      return Container(
        width: 24,
        height: 24,
        decoration: BoxDecoration(
          color: Colors.grey.withOpacity(0.2),
          borderRadius: BorderRadius.circular(6),
        ),
        child: const Icon(
          Icons.language,
          size: 14,
          color: Colors.grey,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return ThemedBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: isSearchMode
              ? _buildSearchField()
              : NeonText(
                  text: 'Пароли',
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
          backgroundColor: ThemeManager.currentTheme == AppTheme.dark 
              ? AppColors.background 
              : Colors.black.withOpacity(0.3),
          elevation: 0,
          actions: [
            if (!isSearchMode)
              IconButton(
                icon: Icon(Icons.search, color: AppColors.text),
                onPressed: () {
                  setState(() {
                    isSearchMode = true;
                  });
                  Future.delayed(const Duration(milliseconds: 100), () {
                    _searchFocusNode.requestFocus();
                  });
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
              ? BoxDecoration(
                  color: Colors.black.withOpacity(0.1),
                )
              : null,
          child: isLoading
              ? const Center(child: CircularProgressIndicator())
              : _buildBody(),
        ),
      ),
    );
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
              if (_searchController.text == value) {
                _searchPasswords(value);
              }
            });
          }
        },
      ),
    );
  }

  Widget _buildBody() {
    if (isSearchMode) {
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

    // Обычный режим отображения всех паролей
    if (passwords.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            NeonText(
              text: 'У вас пока нет сохранённых паролей',
              style: const TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 20),
          ],
        ),
      );
    }

    return _buildPasswordsList(passwords);
  }

  Widget _buildPasswordsList(List<Map<String, dynamic>> passwordsToShow) {
    // Подсчитываем видимые записи
    final visiblePasswords = passwordsToShow.where((item) => 
      !(item['has_seed_phrase'] == true && _hideSeedPhrases)
    ).toList();
    
    if (visiblePasswords.isEmpty && _hideSeedPhrases) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
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
              style: TextStyle(fontSize: 14, color: AppColors.text.withOpacity(0.7)),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }
    
    return ListView.builder(
      itemCount: passwordsToShow.length,
      padding: const EdgeInsets.all(16),
      itemBuilder: (context, index) {
        final item = passwordsToShow[index];
          
        // Скрываем всю запись, если у неё есть seed фраза и включена настройка скрытия
        if (item['has_seed_phrase'] == true && _hideSeedPhrases) {
          return const SizedBox.shrink(); // Возвращаем пустой виджет
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
                                          loadingBuilder: (BuildContext context, Widget child, ImageChunkEvent? loadingProgress) {
                                            if (loadingProgress == null) return child;
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
                                          errorBuilder: (context, error, stackTrace) {
                                            print('DEBUG: Ошибка загрузки фавиконки для ${item['title']}: ${item['favicon_url']} - $error');
                                            return _buildFallbackFavicon(item['title']);
                                          },
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
                          color: ThemeManager.colors.hasNeonGlow ? AppColors.accent : AppColors.text,
                          size: 20,
                        ),
                        const SizedBox(width: 12),
                      ],
                      if (item['has_seed_phrase'] == true) ...[
                        IconButton(
                          icon: Icon(Icons.vpn_key, color: AppColors.button),
                          onPressed: () => _copySeedPhrase(item['seed_phrase'] ?? ''),
                          tooltip: 'Копировать seed фразу',
                        ),
                        const SizedBox(width: 12),
                      ],
                      IconButton(
                        icon: Icon(Icons.edit, color: AppColors.button),
                        onPressed: () => _navigateToEditPassword(item),
                        tooltip: 'Редактировать',
                      ),
                      IconButton(
                        icon: Icon(Icons.copy, color: AppColors.button),
                        onPressed: () => _copyPassword(item['password']),
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
