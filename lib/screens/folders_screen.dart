import 'dart:ui';
import 'package:flutter/material.dart';
import '../theme/colors.dart';
import '../widgets/themed_widgets.dart';
import '../utils/folder_service.dart';
import '../utils/hidden_folder_service.dart';

/// Palette of preset colours the user can pick for a folder.
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

IconData _iconFromName(String name) {
  for (final e in _kFolderIcons) {
    if (e['name'] == name) return e['icon'] as IconData;
  }
  return Icons.folder;
}

Color _colorFromHex(String hex) {
  try {
    return Color(int.parse(hex.replaceFirst('#', '0xFF')));
  } catch (_) {
    return const Color(0xFF5D52D2);
  }
}

class FoldersScreen extends StatefulWidget {
  const FoldersScreen({super.key});

  @override
  State<FoldersScreen> createState() => _FoldersScreenState();
}

class _FoldersScreenState extends State<FoldersScreen> {
  List<Map<String, dynamic>> _folders = [];
  bool _isLoading = true;
  final _hiddenService = HiddenFolderService.instance;

  @override
  void initState() {
    super.initState();
    _loadFolders();
  }

  Future<void> _loadFolders() async {
    setState(() => _isLoading = true);
    final folders = await FolderService.getFolders(
      includeHidden: _hiddenService.isUnlocked,
    );
    if (mounted) {
      setState(() {
        _folders = folders;
        _isLoading = false;
      });
    }
  }

  // ── TOTP verification dialog ────────────────────────────────────────────────

  Future<bool> _requestTotp({String reason = 'Введите TOTP-код для доступа к скрытым папкам'}) async {
    final controller = TextEditingController();
    final verified = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColors.button.withOpacity(0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(Icons.shield_outlined, color: AppColors.button, size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Подтверждение',
                style: TextStyle(color: AppColors.text, fontSize: 17, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              reason,
              style: TextStyle(color: AppColors.text.withOpacity(0.7), fontSize: 13),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: controller,
              keyboardType: TextInputType.number,
              autofocus: true,
              maxLength: 6,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppColors.text,
                fontSize: 26,
                letterSpacing: 10,
                fontWeight: FontWeight.bold,
              ),
              decoration: InputDecoration(
                counterText: '',
                hintText: '000000',
                hintStyle: TextStyle(color: AppColors.text.withOpacity(0.3), letterSpacing: 10),
                filled: true,
                fillColor: AppColors.input,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none,
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(color: AppColors.button, width: 2),
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Отмена', style: TextStyle(color: AppColors.text.withOpacity(0.6))),
          ),
          StatefulBuilder(
            builder: (ctx2, setBtn) => ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.button,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: () async {
                final ok = await _hiddenService.verifyTotp(controller.text.trim());
                if (ctx2.mounted) Navigator.pop(ctx2, ok);
              },
              child: const Text('Подтвердить'),
            ),
          ),
        ],
      ),
    );
    return verified == true;
  }

  // ── Folder dialog ───────────────────────────────────────────────────────────

  Future<void> _showFolderDialog({Map<String, dynamic>? existing}) async {
    final nameController = TextEditingController(text: existing?['name'] ?? '');
    String selectedColor = existing?['color'] as String? ?? '#5D52D2';
    String selectedIcon = existing?['icon'] as String? ?? 'folder';
    bool isHidden = existing?['is_hidden'] as bool? ?? false;

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          backgroundColor: AppColors.surface,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
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
                // Folder preview
                Center(
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      color: _colorFromHex(selectedColor).withOpacity(0.15),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: _colorFromHex(selectedColor), width: 2),
                      boxShadow: ThemeManager.colors.hasNeonGlow
                          ? [BoxShadow(color: _colorFromHex(selectedColor).withOpacity(0.5), blurRadius: 16)]
                          : null,
                    ),
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        Icon(_iconFromName(selectedIcon), color: _colorFromHex(selectedColor), size: 34),
                        if (isHidden)
                          Positioned(
                            right: 6,
                            top: 6,
                            child: Container(
                              padding: const EdgeInsets.all(2),
                              decoration: BoxDecoration(
                                color: AppColors.surface,
                                shape: BoxShape.circle,
                              ),
                              child: Icon(Icons.lock, size: 12, color: _colorFromHex(selectedColor)),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                // Name
                ThemedTextField(
                  controller: nameController,
                  hintText: 'Название папки',
                  prefixIcon: Icon(Icons.drive_file_rename_outline, color: AppColors.button),
                ),
                const SizedBox(height: 20),
                // Hidden toggle
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: isHidden
                        ? AppColors.button.withOpacity(0.1)
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
                            Text(
                              'Скрытая папка',
                              style: TextStyle(
                                color: AppColors.text,
                                fontWeight: FontWeight.w600,
                                fontSize: 14,
                              ),
                            ),
                            Text(
                              'Требует TOTP для просмотра',
                              style: TextStyle(
                                color: AppColors.text.withOpacity(0.5),
                                fontSize: 11,
                              ),
                            ),
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
                const SizedBox(height: 20),
                // Color picker
                Text('Цвет',
                    style: TextStyle(
                        color: AppColors.text.withOpacity(0.7),
                        fontSize: 13,
                        fontWeight: FontWeight.w600)),
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
                          border: isSelected
                              ? Border.all(color: Colors.white, width: 2.5)
                              : null,
                          boxShadow: isSelected
                              ? [BoxShadow(color: _colorFromHex(hex).withOpacity(0.6), blurRadius: 8)]
                              : null,
                        ),
                        child: isSelected
                            ? const Icon(Icons.check, color: Colors.white, size: 18)
                            : null,
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 20),
                // Icon picker
                Text('Иконка',
                    style: TextStyle(
                        color: AppColors.text.withOpacity(0.7),
                        fontSize: 13,
                        fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _kFolderIcons.map((entry) {
                    final name = entry['name'] as String? ?? '';
                    final iconData = entry['icon'] as IconData;
                    final isSelected = name == selectedIcon;
                    return GestureDetector(
                      onTap: () => setDialogState(() => selectedIcon = name),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: isSelected
                              ? _colorFromHex(selectedColor).withOpacity(0.25)
                              : AppColors.input,
                          borderRadius: BorderRadius.circular(10),
                          border: isSelected
                              ? Border.all(color: _colorFromHex(selectedColor), width: 1.5)
                              : null,
                        ),
                        child: Icon(
                          iconData,
                          color: isSelected
                              ? _colorFromHex(selectedColor)
                              : AppColors.text.withOpacity(0.6),
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
        ),
      ),
    );

    if (result == true) _loadFolders();
  }

  Future<void> _deleteFolder(Map<String, dynamic> folder) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: NeonText(
          text: 'Удалить папку?',
          style: TextStyle(color: AppColors.text, fontSize: 18, fontWeight: FontWeight.bold),
        ),
        content: Text(
          'Папка «${folder['name']}» будет удалена.\nПароли из этой папки не удаляются.',
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
    }
  }

  // ── Tap on a hidden (locked) folder ────────────────────────────────────────

  Future<void> _handleHiddenFolderTap(Map<String, dynamic> folder) async {
    if (_hiddenService.isUnlocked) {
      Navigator.pop(context, folder);
      return;
    }
    final ok = await _requestTotp();
    if (ok && mounted) {
      await _loadFolders();
      Navigator.pop(context, folder);
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppColors.error,
          content: const Row(
            children: [
              Icon(Icons.error_outline, color: Colors.white),
              SizedBox(width: 8),
              Text('Неверный TOTP-код', style: TextStyle(color: Colors.white)),
            ],
          ),
        ),
      );
    }
  }

  // ── Build ───────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return ThemedBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: NeonText(
            text: 'Папки',
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          backgroundColor: ThemeManager.currentTheme == AppTheme.dark
              ? AppColors.background
              : Colors.black.withOpacity(0.3),
          elevation: 0,
          actions: [
            // Hidden lock toggle button
            IconButton(
              icon: Icon(
                _hiddenService.isUnlocked ? Icons.visibility : Icons.visibility_off,
                color: _hiddenService.isUnlocked ? AppColors.button : AppColors.text.withOpacity(0.5),
              ),
              tooltip: _hiddenService.isUnlocked ? 'Скрыть скрытые папки' : 'Показать скрытые папки',
              onPressed: () async {
                if (_hiddenService.isUnlocked) {
                  HiddenFolderService.instance.lock();
                  await _loadFolders();
                } else {
                  final ok = await _requestTotp();
                  if (ok) await _loadFolders();
                }
              },
            ),
            IconButton(
              icon: Icon(Icons.create_new_folder, color: AppColors.button),
              onPressed: () => _showFolderDialog(),
              tooltip: 'Создать папку',
            ),
          ],
        ),
        body: Container(
          decoration: ThemeManager.currentTheme != AppTheme.dark
              ? BoxDecoration(color: Colors.black.withOpacity(0.1))
              : null,
          child: _isLoading
              ? Center(child: CircularProgressIndicator(color: AppColors.button))
              : _buildBody(),
        ),
        floatingActionButton: !_isLoading
            ? FloatingActionButton(
                onPressed: () => _showFolderDialog(),
                backgroundColor: AppColors.button,
                child: const Icon(Icons.create_new_folder, color: Colors.white),
              )
            : null,
      ),
    );
  }

  Widget _buildBody() {
    if (_folders.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.folder_open, size: 80, color: AppColors.text.withOpacity(0.3)),
            const SizedBox(height: 20),
            NeonText(text: 'Нет папок', style: TextStyle(fontSize: 20, color: AppColors.text)),
            const SizedBox(height: 8),
            Text(
              'Создайте папку для организации\nваших паролей',
              style: TextStyle(fontSize: 14, color: AppColors.text.withOpacity(0.6)),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            ThemedButton(
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
              onPressed: () => _showFolderDialog(),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.create_new_folder, color: Colors.white, size: 20),
                  SizedBox(width: 8),
                  Text('Создать папку',
                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 1.2,
      ),
      itemCount: _folders.length,
      itemBuilder: (context, index) {
        final folder = _folders[index];
        final color = _colorFromHex(folder['color'] as String? ?? '#5D52D2');
        final iconData = _iconFromName(folder['icon'] as String? ?? 'folder');
        final count = folder['password_count'] as int? ?? 0;
        final isHidden = folder['is_hidden'] as bool? ?? false;
        final isLocked = isHidden && !_hiddenService.isUnlocked;

        return ThemedContainer(
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => isHidden
                ? _handleHiddenFolderTap(folder)
                : Navigator.pop(context, folder),
            onLongPress: () => _showFolderActions(folder),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Stack(
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              color: color.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: color.withOpacity(0.5)),
                            ),
                            child: Icon(iconData, color: color, size: 24),
                          ),
                          GestureDetector(
                            onTap: () => _showFolderActions(folder),
                            child: Icon(
                              Icons.more_vert,
                              color: AppColors.text.withOpacity(0.5),
                              size: 20,
                            ),
                          ),
                        ],
                      ),
                      const Spacer(),
                      if (isLocked)
                        Text('••••••',
                            style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: AppColors.text.withOpacity(0.4),
                                letterSpacing: 4))
                      else
                        NeonText(
                          text: folder['name'] as String? ?? '',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: AppColors.text,
                          ),
                        ),
                      const SizedBox(height: 4),
                      Text(
                        isLocked ? 'Скрытая' : '$count ${_passwordsWord(count)}',
                        style: TextStyle(
                            fontSize: 12,
                            color: AppColors.text.withOpacity(0.5)),
                      ),
                    ],
                  ),
                  // Lock badge
                  if (isHidden)
                    Positioned(
                      top: 0,
                      right: 28,
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: isLocked
                              ? AppColors.error.withOpacity(0.15)
                              : AppColors.button.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Icon(
                          isLocked ? Icons.lock : Icons.lock_open,
                          size: 12,
                          color: isLocked ? AppColors.error : AppColors.button,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  void _showFolderActions(Map<String, dynamic> folder) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
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

  String _passwordsWord(int count) {
    if (count % 100 >= 11 && count % 100 <= 14) return 'паролей';
    switch (count % 10) {
      case 1:
        return 'пароль';
      case 2:
      case 3:
      case 4:
        return 'пароля';
      default:
        return 'паролей';
    }
  }
}
