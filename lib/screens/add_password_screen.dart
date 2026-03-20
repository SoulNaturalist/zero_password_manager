import 'dart:math';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/colors.dart';
import '../widgets/themed_widgets.dart';
import '../utils/folder_service.dart';
import '../utils/hidden_folder_service.dart';
import '../utils/memory_security.dart';
import '../services/vault_service.dart';
import '../utils/password_history_service.dart';
import '../l10n/l_text.dart';

// ── icon/color helpers ────────────────────────────────────────────────────────

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

// ── Password strength ─────────────────────────────────────────────────────────

enum _Strength { empty, weak, fair, good, strong }

_Strength _evaluate(String pwd) {
  if (pwd.isEmpty) return _Strength.empty;
  int score = 0;
  if (pwd.length >= 8) score++;
  if (pwd.length >= 14) score++;
  if (RegExp(r'[A-Z]').hasMatch(pwd)) score++;
  if (RegExp(r'[a-z]').hasMatch(pwd)) score++;
  if (RegExp(r'\d').hasMatch(pwd)) score++;
  if (RegExp(r'[!@#\$%^&*()_+\-=]').hasMatch(pwd)) score++;
  if (score <= 1) return _Strength.weak;
  if (score <= 2) return _Strength.fair;
  if (score <= 4) return _Strength.good;
  return _Strength.strong;
}

String _strengthLabel(_Strength s) {
  switch (s) {
    case _Strength.empty: return '';
    case _Strength.weak: return 'Слабый';
    case _Strength.fair: return 'Средний';
    case _Strength.good: return 'Хороший';
    case _Strength.strong: return 'Надёжный';
  }
}

Color _strengthColor(_Strength s) {
  switch (s) {
    case _Strength.empty: return Colors.transparent;
    case _Strength.weak: return const Color(0xFFE74C3C);
    case _Strength.fair: return const Color(0xFFE67E22);
    case _Strength.good: return const Color(0xFF2ECC71);
    case _Strength.strong: return const Color(0xFF1ABC9C);
  }
}

double _strengthFraction(_Strength s) {
  switch (s) {
    case _Strength.empty: return 0;
    case _Strength.weak: return 0.25;
    case _Strength.fair: return 0.5;
    case _Strength.good: return 0.75;
    case _Strength.strong: return 1;
  }
}

// ─────────────────────────────────────────────────────────────────────────────

class AddPasswordScreen extends StatefulWidget {
  const AddPasswordScreen({super.key});

  @override
  State<AddPasswordScreen> createState() => _AddPasswordScreenState();
}

class _AddPasswordScreenState extends State<AddPasswordScreen>
    with SingleTickerProviderStateMixin {
  final siteController = TextEditingController();
  final emailController = TextEditingController();
  final passwordController = TextEditingController();
  final notesController = TextEditingController();
  final seedPhraseController = TextEditingController();

  bool isLoading = false;
  bool isGeneratingPassword = false;
  bool has2FA = false;
  bool hasSeedPhrase = false;
  String? errorMessage;
  String? faviconUrl;
  bool isLoadingFavicon = false;
  bool _obscurePassword = true;
  bool _copied = false;

  List<Map<String, dynamic>> _folders = [];
  int? _selectedFolderId;
  _Strength _strength = _Strength.empty;

  late final AnimationController _genAnim;

  @override
  void initState() {
    super.initState();
    _genAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    siteController.addListener(() => _loadFavicon(siteController.text));
    passwordController.addListener(() {
      setState(() => _strength = _evaluate(passwordController.text));
    });
    _loadFolders();
  }

  @override
  void dispose() {
    // Best-effort wipe sensitive data before releasing
    unawaited(wipeController(passwordController));
    unawaited(wipeController(seedPhraseController));
    siteController.dispose();
    emailController.dispose();
    passwordController.dispose();
    notesController.dispose();
    seedPhraseController.dispose();
    _genAnim.dispose();
    super.dispose();
  }

  Future<void> _loadFolders() async {
    final folders = await FolderService.getFolders(
      includeHidden: HiddenFolderService.instance.isUnlocked,
    );
    if (mounted) setState(() => _folders = folders);
  }

  // ── password generation ────────────────────────────────────────────────────

  Future<void> _generatePassword() async {
    _genAnim.forward(from: 0);
    setState(() => isGeneratingPassword = true);
    await Future.delayed(const Duration(milliseconds: 300));
    final pwd = _buildPassword(24);
    if (mounted) {
      setState(() {
        passwordController.text = pwd;
        isGeneratingPassword = false;
        _obscurePassword = false;
        _strength = _evaluate(pwd);
      });
    }
  }

  String _buildPassword(int length) {
    const upper = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ';
    const lower = 'abcdefghijklmnopqrstuvwxyz';
    const digits = '0123456789';
    const symbols = '!@#\$%^&*()_+-=';
    final all = upper + lower + digits + symbols;
    final rng = Random.secure();
    final chars = <String>[
      upper[rng.nextInt(upper.length)],
      lower[rng.nextInt(lower.length)],
      digits[rng.nextInt(digits.length)],
      symbols[rng.nextInt(symbols.length)],
    ];
    for (var i = 4; i < length; i++) chars.add(all[rng.nextInt(all.length)]);
    chars.shuffle(rng);
    return chars.join();
  }

  // ── save ───────────────────────────────────────────────────────────────────

  Future<void> _savePassword() async {
    final site = siteController.text.trim();
    final email = emailController.text.trim();
    final password = passwordController.text.trim();

    if (site.isEmpty || email.isEmpty || password.isEmpty) {
      setState(() => errorMessage = 'Заполните сайт, логин и пароль');
      return;
    }

    setState(() { isLoading = true; errorMessage = null; });

    try {
      await VaultService().addPassword(
        name: site,
        url: site,
        login: email,
        password: password,
        notes: notesController.text.trim().isNotEmpty ? notesController.text.trim() : null,
        seedPhrase: hasSeedPhrase && seedPhraseController.text.trim().isNotEmpty
            ? seedPhraseController.text.trim()
            : null,
        folderId: _selectedFolderId,
      );

      await PasswordHistoryService.addPasswordHistory(
        actionType: 'CREATE',
        actionDetails: {
          'site_url': site,
          'site_login': email,
          'has_2fa': has2FA,
          'has_seed_phrase': hasSeedPhrase,
        },
        siteUrl: site,
      );

      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      setState(() => errorMessage = 'Ошибка при сохранении: $e');
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  // ── favicon ────────────────────────────────────────────────────────────────

  Future<void> _loadFavicon(String url) async {
    if (url.isEmpty) {
      setState(() { faviconUrl = null; isLoadingFavicon = false; });
      return;
    }
    setState(() => isLoadingFavicon = true);
    try {
      String domain = url.trim();
      if (domain.startsWith('http://')) domain = domain.substring(7);
      else if (domain.startsWith('https://')) domain = domain.substring(8);
      if (domain.contains('/')) domain = domain.split('/')[0];
      if (!domain.contains('.') && domain.isNotEmpty) domain = '$domain.com';
      if (url.toLowerCase().contains('metamask')) domain = 'metamask.io';
      setState(() {
        faviconUrl = 'https://www.google.com/s2/favicons?domain=$domain&sz=32';
        isLoadingFavicon = false;
      });
    } catch (_) {
      setState(() { faviconUrl = null; isLoadingFavicon = false; });
    }
  }

  // ── folder picker ──────────────────────────────────────────────────────────

  void _showFolderPicker() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.55,
        minChildSize: 0.3,
        maxChildSize: 0.85,
        expand: false,
        builder: (_, controller) => Column(
          children: [
            const SizedBox(height: 12),
            Container(
              width: 40,
              height: 4,
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
                  Icon(Icons.folder_special, color: AppColors.button, size: 20),
                  const SizedBox(width: 10),
                  NeonText(
                    text: 'Выберите папку',
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
                controller: controller,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                children: [
                  // No folder option
                  _FolderTile(
                    icon: Icons.folder_off,
                    iconColor: AppColors.text.withOpacity(0.5),
                    bgColor: AppColors.input,
                    label: 'Без папки',
                    isSelected: _selectedFolderId == null,
                    onTap: () {
                      setState(() => _selectedFolderId = null);
                      Navigator.pop(ctx);
                    },
                  ),
                  const SizedBox(height: 4),
                  ..._folders.map((folder) {
                    final color = _colorFromHex(folder['color'] as String? ?? '#5D52D2');
                    final icon = _iconFromName(folder['icon'] as String? ?? 'folder');
                    final isHidden = folder['is_hidden'] as bool? ?? false;
                    final isSelected = _selectedFolderId == folder['id'];
                    return _FolderTile(
                      icon: icon,
                      iconColor: color,
                      bgColor: color.withOpacity(0.12),
                      label: folder['name'] as String? ?? '',
                      sublabel: isHidden ? '🔒 Скрытая' : null,
                      isSelected: isSelected,
                      onTap: () {
                        setState(() => _selectedFolderId = folder['id'] as int?);
                        Navigator.pop(ctx);
                      },
                    );
                  }),
                  const SizedBox(height: 20),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final selectedFolder = _selectedFolderId != null
        ? _folders.firstWhere(
            (f) => f['id'] == _selectedFolderId,
            orElse: () => <String, dynamic>{},
          )
        : null;

    return ThemedBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: NeonText(
            text: 'Новая запись',
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          backgroundColor: ThemeManager.currentTheme == AppTheme.dark
              ? AppColors.background
              : Colors.black.withOpacity(0.3),
          elevation: 0,
        ),
        body: Container(
          decoration: ThemeManager.currentTheme != AppTheme.dark
              ? BoxDecoration(color: Colors.black.withOpacity(0.1))
              : null,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Site card ─────────────────────────────────────────────
                _SectionLabel(label: 'Сайт / Сервис', icon: Icons.language),
                const SizedBox(height: 8),
                ThemedTextField(
                  controller: siteController,
                  hintText: 'https://example.com',
                  prefixIcon: _buildFaviconWidget(),
                ),
                const SizedBox(height: 20),

                // ── Login ─────────────────────────────────────────────────
                _SectionLabel(label: 'Логин / Email', icon: Icons.person_outline),
                const SizedBox(height: 8),
                ThemedTextField(
                  controller: emailController,
                  hintText: 'user@example.com',
                  prefixIcon: Icon(Icons.alternate_email, color: AppColors.button),
                  keyboardType: TextInputType.emailAddress,
                ),
                const SizedBox(height: 20),

                // ── Password ──────────────────────────────────────────────
                _SectionLabel(label: 'Пароль', icon: Icons.lock_outline),
                const SizedBox(height: 8),
                ThemedTextField(
                  controller: passwordController,
                  hintText: 'Введите или сгенерируйте',
                  obscureText: _obscurePassword,
                  suffixIcon: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // copy button
                      if (passwordController.text.isNotEmpty)
                        AnimatedSwitcher(
                          duration: const Duration(milliseconds: 300),
                          child: IconButton(
                            key: ValueKey(_copied),
                            icon: Icon(
                              _copied ? Icons.check : Icons.copy,
                              color: _copied ? Colors.green : AppColors.text.withOpacity(0.5),
                              size: 20,
                            ),
                            onPressed: () async {
                              await Clipboard.setData(ClipboardData(text: passwordController.text));
                              setState(() => _copied = true);
                              Future.delayed(const Duration(seconds: 2), () {
                                if (mounted) setState(() => _copied = false);
                              });
                            },
                          ),
                        ),
                      // visibility toggle
                      IconButton(
                        icon: Icon(
                          _obscurePassword ? Icons.visibility_off : Icons.visibility,
                          color: AppColors.text.withOpacity(0.5),
                          size: 20,
                        ),
                        onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                      ),
                      // generate button
                      Padding(
                        padding: const EdgeInsets.only(right: 4),
                        child: RotationTransition(
                          turns: _genAnim,
                          child: IconButton(
                            icon: isGeneratingPassword
                                ? SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.button),
                                  )
                                : Icon(Icons.auto_awesome, color: AppColors.button, size: 20),
                            tooltip: 'Сгенерировать',
                            onPressed: isGeneratingPassword ? null : _generatePassword,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                // Strength bar
                const SizedBox(height: 8),
                _StrengthBar(strength: _strength),
                const SizedBox(height: 20),

                // ── Notes ─────────────────────────────────────────────────
                _SectionLabel(label: 'Заметки', icon: Icons.notes, optional: true),
                const SizedBox(height: 8),
                ThemedTextField(
                  controller: notesController,
                  hintText: 'Дополнительная информация...',
                  maxLines: 3,
                ),
                const SizedBox(height: 20),

                // ── Folder picker ─────────────────────────────────────────
                if (_folders.isNotEmpty) ...[
                  _SectionLabel(label: 'Папка', icon: Icons.folder_open, optional: true),
                  const SizedBox(height: 8),
                  ThemedContainer(
                    child: InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: _showFolderPicker,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                        child: Row(
                          children: [
                            if (selectedFolder != null && selectedFolder.isNotEmpty) ...[
                              Container(
                                width: 34,
                                height: 34,
                                decoration: BoxDecoration(
                                  color: _colorFromHex(selectedFolder['color'] as String? ?? '#5D52D2').withOpacity(0.18),
                                  borderRadius: BorderRadius.circular(9),
                                ),
                                child: Icon(
                                  _iconFromName(selectedFolder['icon'] as String? ?? 'folder'),
                                  color: _colorFromHex(selectedFolder['color'] as String? ?? '#5D52D2'),
                                  size: 18,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: LText(
                                  selectedFolder['name'] as String? ?? '',
                                  style: TextStyle(color: AppColors.text, fontSize: 15),
                                ),
                              ),
                            ] else ...[
                              Icon(Icons.folder_open, color: AppColors.text.withOpacity(0.4), size: 22),
                              const SizedBox(width: 12),
                              Expanded(
                                child: LText(
                                  'Выбрать папку',
                                  style: TextStyle(color: AppColors.text.withOpacity(0.55), fontSize: 15),
                                ),
                              ),
                            ],
                            Icon(Icons.chevron_right, color: AppColors.text.withOpacity(0.35)),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                ],

                // ── Toggles ───────────────────────────────────────────────
                _ToggleCard(
                  icon: Icons.security,
                  label: 'Двухфакторная аутентификация',
                  subtitle: 'При входе требуется OTP-код',
                  value: has2FA,
                  onChanged: (v) => setState(() => has2FA = v),
                ),
                const SizedBox(height: 12),
                _ToggleCard(
                  icon: Icons.grain,
                  label: 'Seed-фраза',
                  subtitle: 'Хранить мнемоническую фразу',
                  value: hasSeedPhrase,
                  onChanged: (v) {
                    setState(() {
                      hasSeedPhrase = v;
                      if (!v) seedPhraseController.clear();
                    });
                  },
                ),
                if (hasSeedPhrase) ...[
                  const SizedBox(height: 12),
                  ThemedTextField(
                    controller: seedPhraseController,
                    hintText: 'word1 word2 word3 ... word12',
                    maxLines: 2,
                    prefixIcon: Icon(Icons.grain, color: AppColors.accent),
                  ),
                ],
                const SizedBox(height: 24),

                // ── Error ─────────────────────────────────────────────────
                if (errorMessage != null)
                  Container(
                    padding: const EdgeInsets.all(12),
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      color: AppColors.error.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: AppColors.error.withOpacity(0.4)),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.error_outline, color: AppColors.error, size: 18),
                        const SizedBox(width: 8),
                        Expanded(
                          child: LText(errorMessage!,
                              style: TextStyle(color: AppColors.error, fontSize: 13)),
                        ),
                      ],
                    ),
                  ),

                // ── Save button ───────────────────────────────────────────
                isLoading
                    ? Center(child: CircularProgressIndicator(color: AppColors.button))
                    : ThemedElevatedButton(
                        onPressed: _savePassword,
                        minimumSize: const Size.fromHeight(52),
                        child: const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.save_outlined, size: 20),
                            SizedBox(width: 8),
                            LText('Сохранить', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                          ],
                        ),
                      ),
                SizedBox(height: MediaQuery.of(context).padding.bottom + 20),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFaviconWidget() {
    if (isLoadingFavicon) {
      return Padding(
        padding: const EdgeInsets.all(14),
        child: SizedBox(
          width: 16, height: 16,
          child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.button),
        ),
      );
    }
    if (faviconUrl != null) {
      return Container(
        margin: const EdgeInsets.all(10),
        width: 22,
        height: 22,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: Image.network(
            faviconUrl!,
            width: 22,
            height: 22,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) =>
                Icon(Icons.language, size: 18, color: AppColors.text.withOpacity(0.4)),
          ),
        ),
      );
    }
    return Icon(Icons.language, color: AppColors.text.withOpacity(0.4));
  }
}

// ── Supporting widgets ────────────────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool optional;

  const _SectionLabel({required this.label, required this.icon, this.optional = false});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 15, color: AppColors.button.withOpacity(0.8)),
        const SizedBox(width: 6),
        LText(
          label,
          style: TextStyle(
            color: AppColors.text.withOpacity(0.75),
            fontSize: 13,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.3,
          ),
        ),
        if (optional) ...[
          const SizedBox(width: 6),
          LText(
            '(необязательно)',
            style: TextStyle(color: AppColors.text.withOpacity(0.4), fontSize: 11),
          ),
        ],
      ],
    );
  }
}

class _StrengthBar extends StatelessWidget {
  final _Strength strength;

  const _StrengthBar({required this.strength});

  @override
  Widget build(BuildContext context) {
    if (strength == _Strength.empty) return const SizedBox.shrink();
    final color = _strengthColor(strength);
    final fraction = _strengthFraction(strength);
    final label = _strengthLabel(strength);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: fraction),
            duration: const Duration(milliseconds: 350),
            curve: Curves.easeOut,
            builder: (_, v, __) => Stack(
              children: [
                Container(height: 4, width: double.infinity, color: AppColors.input),
                FractionallySizedBox(
                  widthFactor: v,
                  child: Container(
                    height: 4,
                    decoration: BoxDecoration(
                      color: color,
                      borderRadius: BorderRadius.circular(4),
                      boxShadow: [BoxShadow(color: color.withOpacity(0.5), blurRadius: 4)],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 4),
        LText(label, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600)),
      ],
    );
  }
}

class _ToggleCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _ToggleCard({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: value ? AppColors.button.withOpacity(0.1) : AppColors.input,
        borderRadius: BorderRadius.circular(14),
        border: value ? Border.all(color: AppColors.button.withOpacity(0.4)) : null,
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: value ? AppColors.button.withOpacity(0.2) : AppColors.surface,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 18, color: value ? AppColors.button : AppColors.text.withOpacity(0.5)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                LText(label,
                    style: TextStyle(
                        color: AppColors.text,
                        fontWeight: FontWeight.w600,
                        fontSize: 14)),
                const SizedBox(height: 2),
                LText(subtitle,
                    style: TextStyle(color: AppColors.text.withOpacity(0.5), fontSize: 11)),
              ],
            ),
          ),
          Switch(value: value, onChanged: onChanged, activeColor: AppColors.button),
        ],
      ),
    );
  }
}

class _FolderTile extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final Color bgColor;
  final String label;
  final String? sublabel;
  final bool isSelected;
  final VoidCallback onTap;

  const _FolderTile({
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
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          margin: const EdgeInsets.symmetric(vertical: 3),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: isSelected ? AppColors.button.withOpacity(0.12) : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            border: isSelected ? Border.all(color: AppColors.button.withOpacity(0.4)) : null,
          ),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(color: bgColor, borderRadius: BorderRadius.circular(10)),
                child: Icon(icon, color: iconColor, size: 20),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    LText(label,
                        style: TextStyle(
                            color: AppColors.text,
                            fontWeight: FontWeight.w500,
                            fontSize: 15)),
                    if (sublabel != null)
                      LText(sublabel!,
                          style: TextStyle(color: AppColors.text.withOpacity(0.5), fontSize: 11)),
                  ],
                ),
              ),
              if (isSelected)
                Icon(Icons.check_circle, color: AppColors.button, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}
