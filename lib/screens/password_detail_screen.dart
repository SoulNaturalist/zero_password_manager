import 'dart:async';
import 'package:flutter/material.dart';
import '../theme/colors.dart';
import '../widgets/themed_widgets.dart';
import '../utils/memory_security.dart';
import '../services/vault_service.dart';
import 'edit_password_screen.dart';
import '../l10n/l_text.dart';

/// Shows the detail of a single password account.
/// Sensitive fields are decrypted only on demand and wiped again when hidden.
class PasswordDetailScreen extends StatefulWidget {
  /// Metadata-only map from [VaultService.loadPasswordList].
  /// Must contain: id, title, subtitle, encrypted_payload (optional),
  /// has_2fa, has_seed_phrase, notes_encrypted, encrypted_metadata.
  final Map<String, dynamic> entry;

  const PasswordDetailScreen({super.key, required this.entry});

  @override
  State<PasswordDetailScreen> createState() => _PasswordDetailScreenState();
}

class _PasswordDetailScreenState extends State<PasswordDetailScreen> {
  bool _isLoading = true;
  bool _showPwd = false;
  bool _showNotes = false;
  bool _showSeed = false;
  bool _copied = false;
  String? _errorMsg;

  String? _encryptedPayload;
  String? _encryptedNotes;
  String? _encryptedMetadata;

  String _pwdDisplay = '';
  String _notesDisplay = '';
  String _seedDisplay = '';

  @override
  void initState() {
    super.initState();
    _loadSensitiveData();
  }

  @override
  void dispose() {
    _wipeAllBuffers();
    super.dispose();
  }

  Future<void> _loadSensitiveData() async {
    setState(() {
      _isLoading = true;
      _errorMsg = null;
    });

    try {
      Map<String, dynamic> full = widget.entry;
      if (full['encrypted_payload'] == null) {
        final id = full['id'] as int?;
        if (id != null) {
          full = await VaultService().loadSingleEntry(id);
        }
      }

      _encryptedPayload = full['encrypted_payload'] as String?;
      _encryptedNotes = full['notes_encrypted'] as String?;
      _encryptedMetadata = full['encrypted_metadata'] as String?;
    } catch (e) {
      _errorMsg = 'Ошибка расшифровки: $e';
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _wipeAllBuffers() {
    _wipeDisplayedValue(_pwdDisplay);
    _wipeDisplayedValue(_notesDisplay);
    _wipeDisplayedValue(_seedDisplay);
    _pwdDisplay = '';
    _notesDisplay = '';
    _seedDisplay = '';
  }

  void _wipeDisplayedValue(String value) {
    if (value.isEmpty) return;
    unawaited(wipeController(TextEditingController(text: value)));
  }

  Future<void> _copyPassword() async {
    if (_encryptedPayload == null || _encryptedPayload!.isEmpty) return;

    final passwordBuf = await VaultService().decryptPayloadSecure(_encryptedPayload!);
    try {
      await copySecureBuffer(passwordBuf);
    } finally {
      passwordBuf.wipe();
    }

    if (!mounted) return;
    setState(() => _copied = true);
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  Future<void> _togglePasswordVisibility() async {
    if (_showPwd) {
      _wipeDisplayedValue(_pwdDisplay);
      if (!mounted) return;
      setState(() {
        _showPwd = false;
        _pwdDisplay = '';
      });
      return;
    }

    if (_encryptedPayload == null || _encryptedPayload!.isEmpty) return;

    try {
      final passwordBuf = await VaultService().decryptPayloadSecure(_encryptedPayload!);
      final bytes = passwordBuf.getBytesCopy();
      final display = String.fromCharCodes(bytes);
      bytes.fillRange(0, bytes.length, 0);
      passwordBuf.wipe();

      if (!mounted) {
        await nativeWipe(display);
        return;
      }

      setState(() {
        _pwdDisplay = display;
        _showPwd = true;
      });
    } catch (e) {
      if (mounted) {
        setState(() => _errorMsg = 'Ошибка расшифровки: $e');
      }
    }
  }

  Future<void> _toggleNotesVisibility() async {
    if (_showNotes) {
      _wipeDisplayedValue(_notesDisplay);
      if (!mounted) return;
      setState(() {
        _showNotes = false;
        _notesDisplay = '';
      });
      return;
    }

    if (_encryptedNotes == null || _encryptedNotes!.isEmpty) return;

    try {
      final notesBuf = await VaultService().decryptPayloadSecure(_encryptedNotes!);
      final bytes = notesBuf.getBytesCopy();
      final display = String.fromCharCodes(bytes);
      bytes.fillRange(0, bytes.length, 0);
      notesBuf.wipe();

      if (!mounted) {
        await nativeWipe(display);
        return;
      }

      setState(() {
        _notesDisplay = display;
        _showNotes = true;
      });
    } catch (e) {
      if (mounted) {
        setState(() => _errorMsg = 'Ошибка расшифровки: $e');
      }
    }
  }

  Future<void> _toggleSeedVisibility() async {
    if (_showSeed) {
      _wipeDisplayedValue(_seedDisplay);
      if (!mounted) return;
      setState(() {
        _showSeed = false;
        _seedDisplay = '';
      });
      return;
    }

    if (_encryptedMetadata == null || _encryptedMetadata!.isEmpty) return;

    try {
      final seedBuf =
          await VaultService().decryptSeedPhraseFromMetadataSecure(_encryptedMetadata!);
      if (seedBuf == null) return;

      final bytes = seedBuf.getBytesCopy();
      final display = String.fromCharCodes(bytes);
      bytes.fillRange(0, bytes.length, 0);
      seedBuf.wipe();

      if (!mounted) {
        await nativeWipe(display);
        return;
      }

      setState(() {
        _seedDisplay = display;
        _showSeed = true;
      });
    } catch (e) {
      if (mounted) {
        setState(() => _errorMsg = 'Ошибка расшифровки: $e');
      }
    }
  }

  void _openEdit() {
    Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => EditPasswordScreen(password: widget.entry),
      ),
    ).then((changed) {
      if (changed == true && mounted) {
        _wipeAllBuffers();
        _loadSensitiveData();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final entry = widget.entry;
    final title = entry['title'] as String? ?? '';
    final login = entry['subtitle'] as String? ?? '';
    final has2fa = entry['has_2fa'] as bool? ?? false;
    final hasSeed = entry['has_seed_phrase'] as bool? ?? false;

    return ThemedBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: NeonText(
            text: title.isNotEmpty ? title : 'Пароль',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          backgroundColor: ThemeManager.currentTheme == AppTheme.dark
              ? AppColors.background
              : Colors.black.withOpacity(0.3),
          elevation: 0,
          actions: [
            IconButton(
              icon: Icon(Icons.edit_outlined, color: AppColors.button),
              tooltip: 'Редактировать',
              onPressed: _isLoading ? null : _openEdit,
            ),
          ],
        ),
        body: _isLoading
            ? Center(child: CircularProgressIndicator(color: AppColors.button))
            : Container(
                decoration: ThemeManager.currentTheme != AppTheme.dark
                    ? BoxDecoration(color: Colors.black.withOpacity(0.1))
                    : null,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
                  children: [
                    _buildHeaderCard(title, login),
                    const SizedBox(height: 20),
                    if (_errorMsg != null) ...[
                      _ErrorBanner(message: _errorMsg!),
                      const SizedBox(height: 16),
                    ],
                    if ((_encryptedPayload ?? '').isNotEmpty) _buildPasswordCard(),
                    const SizedBox(height: 12),
                    Row(children: [
                      if (has2fa) _FlagChip(icon: Icons.security, label: '2FA'),
                      if (has2fa && hasSeed) const SizedBox(width: 8),
                      if (hasSeed) _FlagChip(icon: Icons.grain, label: 'Seed'),
                    ]),
                    if (has2fa || hasSeed) const SizedBox(height: 12),
                    if ((_encryptedNotes ?? '').isNotEmpty)
                      _buildRevealCard(
                        icon: Icons.notes,
                        label: 'Заметки',
                        content: _notesDisplay,
                        revealed: _showNotes,
                        onToggle: _toggleNotesVisibility,
                      ),
                    if ((_encryptedMetadata ?? '').isNotEmpty && hasSeed) ...[
                      const SizedBox(height: 12),
                      _buildRevealCard(
                        icon: Icons.grain,
                        label: 'Seed-фраза',
                        content: _seedDisplay,
                        revealed: _showSeed,
                        onToggle: _toggleSeedVisibility,
                        highValue: true,
                      ),
                    ],
                  ],
                ),
              ),
      ),
    );
  }

  Widget _buildHeaderCard(String title, String login) {
    return ThemedContainer(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: AppColors.button.withOpacity(0.15),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(Icons.language, color: AppColors.button, size: 26),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  NeonText(
                    text: title.isNotEmpty ? title : '—',
                    style: TextStyle(
                      color: AppColors.text,
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  LText(
                    login.isNotEmpty ? login : 'Логин не указан',
                    style: TextStyle(
                      color: AppColors.text.withOpacity(0.6),
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
            if (login.isNotEmpty)
              IconButton(
                icon: Icon(Icons.copy, size: 18, color: AppColors.text.withOpacity(0.5)),
                tooltip: 'Скопировать логин',
                onPressed: () => copyWithAutoClear(login),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildPasswordCard() {
    return ThemedContainer(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.lock_outline, size: 15, color: AppColors.button.withOpacity(0.8)),
                const SizedBox(width: 6),
                LText(
                  'Пароль',
                  style: TextStyle(
                    color: AppColors.text.withOpacity(0.7),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 250),
                    child: LText(
                      _showPwd ? _pwdDisplay : '•' * (_pwdDisplay.isEmpty ? 12 : _pwdDisplay.length.clamp(8, 24)),
                      key: ValueKey(_showPwd),
                      style: TextStyle(
                        color: AppColors.text,
                        fontSize: _showPwd ? 15 : 20,
                        letterSpacing: _showPwd ? 0.5 : 4,
                        fontFamily: _showPwd ? null : 'monospace',
                      ),
                    ),
                  ),
                ),
                IconButton(
                  icon: Icon(
                    _showPwd ? Icons.visibility_off : Icons.visibility,
                    color: AppColors.text.withOpacity(0.5),
                    size: 20,
                  ),
                  onPressed: _togglePasswordVisibility,
                  tooltip: _showPwd ? 'Скрыть' : 'Показать',
                ),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 200),
                  child: IconButton(
                    key: ValueKey(_copied),
                    icon: Icon(
                      _copied ? Icons.check_circle : Icons.copy,
                      color: _copied ? Colors.green : AppColors.button,
                      size: 20,
                    ),
                    onPressed: _copyPassword,
                    tooltip: 'Копировать (авто-очистка через 30с)',
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRevealCard({
    required IconData icon,
    required String label,
    required String content,
    required bool revealed,
    required Future<void> Function() onToggle,
    bool highValue = false,
  }) {
    return ThemedContainer(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: () => unawaited(onToggle()),
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Icon(
                    icon,
                    size: 15,
                    color: highValue
                        ? AppColors.error.withOpacity(0.8)
                        : AppColors.button.withOpacity(0.8),
                  ),
                  const SizedBox(width: 6),
                  LText(
                    label,
                    style: TextStyle(
                      color: AppColors.text.withOpacity(0.7),
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const Spacer(),
                  Icon(
                    revealed ? Icons.expand_less : Icons.expand_more,
                    color: AppColors.text.withOpacity(0.5),
                    size: 20,
                  ),
                ],
              ),
            ),
          ),
          if (revealed)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: LSelectableText(
                content,
                style: TextStyle(
                  color: highValue ? AppColors.error : AppColors.text,
                  fontSize: 13,
                  height: 1.5,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _FlagChip extends StatelessWidget {
  final IconData icon;
  final String label;

  const _FlagChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.button.withOpacity(0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.button.withOpacity(0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: AppColors.button),
          const SizedBox(width: 5),
          LText(label, style: TextStyle(color: AppColors.button, fontSize: 12, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  final String message;
  const _ErrorBanner({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.error.withOpacity(0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.error.withOpacity(0.4)),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline, color: AppColors.error, size: 18),
          const SizedBox(width: 8),
          Expanded(child: LText(message, style: TextStyle(color: AppColors.error, fontSize: 13))),
        ],
      ),
    );
  }
}
