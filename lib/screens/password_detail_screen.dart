import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/colors.dart';
import '../widgets/themed_widgets.dart';
import '../utils/memory_security.dart';
import '../services/vault_service.dart';
import 'edit_password_screen.dart';

/// Shows the detail of a single password account.
/// The plaintext password is never held as a String in a field —
/// it lives in a [SecureBuffer] that is wiped when the screen is popped.
///
/// Navigation flow:
///   PasswordsScreen → PasswordDetailScreen → (optional) EditPasswordScreen
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
  // Secure buffers for sensitive data — wiped in dispose()
  SecureBuffer? _passwordBuf;
  SecureBuffer? _notesBuf;
  SecureBuffer? _seedBuf;

  bool _isLoading  = true;
  bool _showPwd    = false;
  bool _showNotes  = false;
  bool _showSeed   = false;
  bool _copied     = false;
  String? _errorMsg;

  // Cached decoded strings — only live in memory while screen is active
  String _pwdDisplay   = '';
  String _notesDisplay = '';
  String _seedDisplay  = '';

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

  // ── Load ──────────────────────────────────────────────────────────────────

  Future<void> _loadSensitiveData() async {
    setState(() { _isLoading = true; _errorMsg = null; });

    try {
      // If the list-view entry had no encrypted_payload, fetch the full entry
      Map<String, dynamic> full = widget.entry;
      if (full['encrypted_payload'] == null) {
        final id = full['id'] as int?;
        if (id != null) {
          full = await VaultService().loadSingleEntry(id);
        }
      }

      final encPayload = full['encrypted_payload'] as String?;
      final encNotes   = full['notes_encrypted']   as String?;
      final encMeta    = full['encrypted_metadata'] as String?;

      if (encPayload != null) {
        _passwordBuf = await VaultService().decryptPayloadSecure(encPayload);
        _pwdDisplay  = String.fromCharCodes(_passwordBuf!.getBytesCopy());
      }
      if (encNotes != null) {
        _notesBuf    = await VaultService().decryptPayloadSecure(encNotes);
        _notesDisplay = String.fromCharCodes(_notesBuf!.getBytesCopy());
      }
      if (encMeta != null) {
        _seedBuf     = await VaultService().decryptSeedPhraseFromMetadataSecure(encMeta);
      }
      if (_seedBuf != null) {
        _seedDisplay = String.fromCharCodes(_seedBuf!.getBytesCopy());
      }
    } catch (e) {
      _errorMsg = 'Ошибка расшифровки: $e';
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _wipeAllBuffers() {
    _passwordBuf?.wipe();
    _notesBuf?.wipe();
    _seedBuf?.wipe();
    // Overwrite display strings (best-effort — Dart Strings are immutable)
    if (_pwdDisplay.isNotEmpty) unawaited(wipeController(TextEditingController(text: _pwdDisplay)));
    if (_notesDisplay.isNotEmpty) unawaited(wipeController(TextEditingController(text: _notesDisplay)));
    if (_seedDisplay.isNotEmpty) unawaited(wipeController(TextEditingController(text: _seedDisplay)));
    
    _pwdDisplay   = '';
    _notesDisplay = '';
    _seedDisplay  = '';
  }

  // ── Actions ───────────────────────────────────────────────────────────────

  Future<void> _copyPassword() async {
    if (_passwordBuf == null) return;
    await copySecureBuffer(_passwordBuf!);
    setState(() => _copied = true);
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  void _openEdit() {
    // Pass the encrypted entry (NOT the decrypted password)
    // EditPasswordScreen will decrypt on-demand when the user needs it
    Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => EditPasswordScreen(password: widget.entry),
      ),
    ).then((changed) {
      if (changed == true && mounted) {
        // Re-load if the password was changed
        _wipeAllBuffers();
        _loadSensitiveData();
      }
    });
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final entry   = widget.entry;
    final title   = entry['title']    as String? ?? '';
    final login   = entry['subtitle'] as String? ?? '';
    final has2fa  = entry['has_2fa']  as bool? ?? false;
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
                    // ── Header card ──────────────────────────────────────────
                    _buildHeaderCard(title, login),
                    const SizedBox(height: 20),

                    // ── Error ────────────────────────────────────────────────
                    if (_errorMsg != null) ...[
                      _ErrorBanner(message: _errorMsg!),
                      const SizedBox(height: 16),
                    ],

                    // ── Password card ────────────────────────────────────────
                    if (_pwdDisplay.isNotEmpty)
                      _buildPasswordCard(),
                    const SizedBox(height: 12),

                    // ── Flags ────────────────────────────────────────────────
                    Row(children: [
                      if (has2fa) _FlagChip(icon: Icons.security, label: '2FA'),
                      if (has2fa && hasSeed) const SizedBox(width: 8),
                      if (hasSeed) _FlagChip(icon: Icons.grain, label: 'Seed'),
                    ]),
                    if (has2fa || hasSeed) const SizedBox(height: 12),

                    // ── Notes card ───────────────────────────────────────────
                    if (_notesDisplay.isNotEmpty)
                      _buildRevealCard(
                        icon: Icons.notes,
                        label: 'Заметки',
                        content: _notesDisplay,
                        revealed: _showNotes,
                        onToggle: () => setState(() => _showNotes = !_showNotes),
                      ),

                    // ── Seed phrase card ─────────────────────────────────────
                    if (_seedDisplay.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      _buildRevealCard(
                        icon: Icons.grain,
                        label: 'Seed-фраза',
                        content: _seedDisplay,
                        revealed: _showSeed,
                        onToggle: () => setState(() => _showSeed = !_showSeed),
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
            // Favicon / initial
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
                  Text(
                    login.isNotEmpty ? login : 'Логин не указан',
                    style: TextStyle(
                      color: AppColors.text.withOpacity(0.6),
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
            // Copy login
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
                Text(
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
                    child: Text(
                      _showPwd ? _pwdDisplay : '•' * _pwdDisplay.length.clamp(8, 24),
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
                // Reveal toggle
                IconButton(
                  icon: Icon(
                    _showPwd ? Icons.visibility_off : Icons.visibility,
                    color: AppColors.text.withOpacity(0.5),
                    size: 20,
                  ),
                  onPressed: () => setState(() => _showPwd = !_showPwd),
                  tooltip: _showPwd ? 'Скрыть' : 'Показать',
                ),
                // Copy
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
    required VoidCallback onToggle,
    bool highValue = false,
  }) {
    return ThemedContainer(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: onToggle,
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Icon(icon, size: 15,
                      color: highValue ? AppColors.error.withOpacity(0.8) : AppColors.button.withOpacity(0.8)),
                  const SizedBox(width: 6),
                  Text(label,
                      style: TextStyle(
                          color: AppColors.text.withOpacity(0.7),
                          fontSize: 12,
                          fontWeight: FontWeight.w600)),
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
              child: SelectableText(
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

// ── Small UI widgets ────────────────────────────────────────────────────────

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
          Text(label, style: TextStyle(color: AppColors.button, fontSize: 12, fontWeight: FontWeight.w600)),
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
          Expanded(child: Text(message, style: TextStyle(color: AppColors.error, fontSize: 13))),
        ],
      ),
    );
  }
}
