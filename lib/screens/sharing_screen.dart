import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/colors.dart';
import '../widgets/themed_widgets.dart';
import '../services/sharing_service.dart';
import '../services/vault_service.dart';
import '../l10n/l_text.dart';

class SharingScreen extends StatefulWidget {
  /// Optional password entry from the vault list. When provided the share
  /// creation sheet opens automatically with the entry's data pre-filled.
  final Map<String, dynamic>? initialEntry;

  const SharingScreen({super.key, this.initialEntry});

  @override
  State<SharingScreen> createState() => _SharingScreenState();
}

class _SharingScreenState extends State<SharingScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  final _sharing = SharingService();
  final _vault = VaultService();

  List<Map<String, dynamic>> _incoming = [];
  List<Map<String, dynamic>> _outgoing = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
    _load();
    // Auto-open share sheet when launched from the password list
    if (widget.initialEntry != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _showCreateShareSheet(widget.initialEntry!);
      });
    }
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  // ── Data ──────────────────────────────────────────────────────────────────

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final results = await Future.wait([
        _sharing.getIncomingShares(),
        _sharing.getOutgoingShares(),
      ]);
      if (mounted) {
        setState(() {
          _incoming = results[0];
          _outgoing = results[1];
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        _showError('Ошибка загрузки: $e');
      }
    }
  }

  // ── Create share ──────────────────────────────────────────────────────────

  void _showCreateShareSheet([Map<String, dynamic>? entry]) {
    if (_vault.isLocked) {
      _showError('Хранилище заблокировано. Пожалуйста, войдите снова.');
      return;
    }

    final recipientCtrl = TextEditingController();
    final labelCtrl = TextEditingController(
      text: entry?['title'] as String? ?? '',
    );
    final encryptedPayload = entry?['encrypted_payload'] as String? ?? '';
    int? expiryDays = 7;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(ctx).viewInsets.bottom,
          ),
          child: Container(
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(24)),
              border: Border.all(
                color: AppColors.button.withOpacity(0.15),
                width: 1,
              ),
            ),
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Handle
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: AppColors.text.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Title row
                    Row(
                      children: [
                        Container(
                          width: 38,
                          height: 38,
                          decoration: BoxDecoration(
                            color: AppColors.button.withOpacity(0.12),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(
                            Icons.share_rounded,
                            color: AppColors.button,
                            size: 20,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            NeonText(
                              text: 'Поделиться паролем',
                              style: TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.bold,
                                color: AppColors.text,
                              ),
                            ),
                            LText(
                              'Пароль шифруется одноразовым ключом',
                              style: TextStyle(
                                fontSize: 12,
                                color: AppColors.text.withOpacity(0.5),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),

                    // Recipient field
                    _SheetLabel(label: 'Получатель', icon: Icons.person_outline),
                    const SizedBox(height: 6),
                    _StyledField(
                      controller: recipientCtrl,
                      hint: 'Логин получателя',
                      icon: Icons.alternate_email,
                    ),
                    const SizedBox(height: 12),

                    // Label field
                    _SheetLabel(label: 'Метка (необязательно)', icon: Icons.label_outline),
                    const SizedBox(height: 6),
                    _StyledField(
                      controller: labelCtrl,
                      hint: 'Название для получателя',
                      icon: Icons.title,
                    ),
                    const SizedBox(height: 12),

                    // Expiry
                    _SheetLabel(label: 'Срок действия', icon: Icons.timer_outlined),
                    const SizedBox(height: 6),
                    ThemedContainer(
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<int?>(
                          value: expiryDays,
                          isExpanded: true,
                          dropdownColor: AppColors.surface,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 4),
                          style: TextStyle(color: AppColors.text, fontSize: 14),
                          items: const [
                            DropdownMenuItem(
                                value: null, child: LText('Без срока')),
                            DropdownMenuItem(
                                value: 1, child: LText('1 день')),
                            DropdownMenuItem(
                                value: 7, child: LText('7 дней')),
                            DropdownMenuItem(
                                value: 30, child: LText('30 дней')),
                          ],
                          onChanged: (v) => setSheet(() => expiryDays = v),
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Submit button
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: ElevatedButton(
                        onPressed: () async {
                          final recipient = recipientCtrl.text.trim();
                          if (recipient.isEmpty) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: LText('Введите логин получателя'),
                              ),
                            );
                            return;
                          }
                          if (encryptedPayload.isEmpty) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content:
                                    LText('Выберите пароль для отправки'),
                              ),
                            );
                            return;
                          }
                          Navigator.pop(ctx);
                          await _createShare(
                            recipient: recipient,
                            encryptedPayload: encryptedPayload,
                            label: labelCtrl.text.trim().isEmpty
                                ? null
                                : labelCtrl.text.trim(),
                            expiresInDays: expiryDays,
                          );
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.button,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                          elevation: 0,
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: const [
                            Icon(Icons.lock_outlined, size: 18),
                            SizedBox(width: 8),
                            LText(
                              'Создать ссылку',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _createShare({
    required String recipient,
    required String encryptedPayload,
    String? label,
    int? expiresInDays,
  }) async {
    try {
      final result = await _sharing.sharePassword(
        recipientLogin: recipient,
        encryptedPayload: encryptedPayload,
        masterKey: _vault.masterKey!,
        label: label,
        expiresInDays: expiresInDays,
      );
      if (!mounted) return;
      _showShareKeyDialog(result.shareKey, label ?? 'пароль');
      await _load();
    } catch (e) {
      _showError('Ошибка: $e');
    }
  }

  void _showShareKeyDialog(String shareKey, String label) {
    bool _keyCopied = false;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) => AlertDialog(
          backgroundColor: AppColors.surface,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: Colors.green.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.check_circle_outline,
                    color: Colors.green, size: 20),
              ),
              const SizedBox(width: 10),
              NeonText(
                text: 'Доступ создан',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: AppColors.text,
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              LText(
                'Передайте ключ получателю отдельным каналом. Ключ отображается только один раз.',
                style: TextStyle(
                  fontSize: 13,
                  color: AppColors.text.withOpacity(0.65),
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 14),
              ThemedContainer(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      Expanded(
                        child: LSelectableText(
                          shareKey,
                          style: TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 11,
                            color: AppColors.button,
                            letterSpacing: 0.3,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      GestureDetector(
                        onTap: () {
                          Clipboard.setData(ClipboardData(text: shareKey));
                          setDlg(() => _keyCopied = true);
                          Future.delayed(const Duration(seconds: 2), () {
                            if (ctx.mounted) setDlg(() => _keyCopied = false);
                          });
                        },
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 200),
                          child: Icon(
                            _keyCopied
                                ? Icons.check_circle
                                : Icons.copy_rounded,
                            key: ValueKey(_keyCopied),
                            color: _keyCopied
                                ? Colors.green
                                : AppColors.button,
                            size: 20,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          actions: [
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => Navigator.pop(ctx),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.button,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                child: const LText('Готово'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Accept a share ────────────────────────────────────────────────────────

  void _showAcceptDialog(Map<String, dynamic> share) {
    final keyCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: NeonText(
          text: 'Принять пароль',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: AppColors.text,
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (share['label'] != null) ...[
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: AppColors.button.withOpacity(0.10),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: LText(
                  share['label'].toString(),
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: AppColors.button,
                    fontSize: 13,
                  ),
                ),
              ),
              const SizedBox(height: 12),
            ],
            LText(
              'Введите ключ, полученный от отправителя:',
              style: TextStyle(
                  fontSize: 13, color: AppColors.text.withOpacity(0.7)),
            ),
            const SizedBox(height: 10),
            _StyledField(
              controller: keyCtrl,
              hint: 'Вставьте ключ здесь',
              icon: Icons.key_rounded,
            ),
          ],
        ),
        actions: [
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(ctx),
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(
                        color: AppColors.text.withOpacity(0.2)),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  child: LText('Отмена',
                      style: TextStyle(
                          color: AppColors.text.withOpacity(0.7))),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ElevatedButton(
                  onPressed: () async {
                    if (keyCtrl.text.trim().isEmpty) return;
                    Navigator.pop(ctx);
                    await _acceptShare(
                        share['id'] as int, keyCtrl.text.trim());
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.button,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const LText('Расшифровать'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _acceptShare(int shareId, String shareKey) async {
    try {
      await _sharing.acceptShare(shareId);
      final plaintext =
          await _sharing.decryptReceivedShare(shareId, shareKey);
      if (!mounted) return;
      _showDecryptedResult(plaintext);
      await _load();
    } catch (e) {
      _showError('Ошибка: $e');
    }
  }

  void _showDecryptedResult(String plaintext) {
    bool _copied = false;
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) => AlertDialog(
          backgroundColor: AppColors.surface,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20)),
          title: Row(
            children: [
              Icon(Icons.lock_open_rounded, color: Colors.green, size: 22),
              const SizedBox(width: 8),
              NeonText(
                text: 'Расшифрован',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: AppColors.text,
                ),
              ),
            ],
          ),
          content: ThemedContainer(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Expanded(
                    child: LSelectableText(
                      plaintext,
                      style: TextStyle(
                        fontFamily: 'monospace',
                        color: AppColors.text,
                        fontSize: 14,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: () {
                      Clipboard.setData(ClipboardData(text: plaintext));
                      setDlg(() => _copied = true);
                      Future.delayed(const Duration(seconds: 2), () {
                        if (ctx.mounted) setDlg(() => _copied = false);
                      });
                    },
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 200),
                      child: Icon(
                        _copied ? Icons.check_circle : Icons.copy_rounded,
                        key: ValueKey(_copied),
                        color: _copied ? Colors.green : AppColors.button,
                        size: 20,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => Navigator.pop(ctx),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.button,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                child: const LText('Закрыть'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return ThemedBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: ThemeManager.currentTheme == AppTheme.dark
              ? AppColors.background
              : Colors.black.withOpacity(0.3),
          elevation: 0,
          title: NeonText(
            text: 'Поделиться',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          bottom: TabBar(
            controller: _tabs,
            indicatorColor: AppColors.button,
            labelColor: AppColors.button,
            unselectedLabelColor: AppColors.text.withOpacity(0.5),
            tabs: const [
              Tab(icon: Icon(Icons.inbox_rounded), text: 'Входящие'),
              Tab(icon: Icon(Icons.send_rounded), text: 'Исходящие'),
            ],
          ),
          actions: [
            IconButton(
              icon: Icon(Icons.refresh_rounded, color: AppColors.text),
              onPressed: _load,
              tooltip: 'Обновить',
            ),
          ],
        ),
        floatingActionButton:
            widget.initialEntry == null
                ? FloatingActionButton.extended(
                    onPressed: () => _showCreateShareSheet(),
                    backgroundColor: AppColors.button,
                    foregroundColor: Colors.white,
                    icon: const Icon(Icons.share_rounded),
                    label: const LText('Поделиться',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                  )
                : null,
        body: _loading
            ? Center(
                child:
                    CircularProgressIndicator(color: AppColors.button))
            : TabBarView(
                controller: _tabs,
                children: [
                  _buildIncomingList(),
                  _buildOutgoingList(),
                ],
              ),
      ),
    );
  }

  Widget _buildIncomingList() {
    if (_incoming.isEmpty) {
      return _buildEmptyState(
        icon: Icons.inbox_rounded,
        title: 'Нет входящих',
        subtitle: 'Когда кто-то поделится паролем,\nон появится здесь',
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      color: AppColors.button,
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: _incoming.length,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (_, i) {
          final s = _incoming[i];
          final isPending = s['status'] == 'pending';
          return ThemedContainer(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: (isPending ? Colors.orange : Colors.green)
                          .withOpacity(0.12),
                      borderRadius: BorderRadius.circular(11),
                    ),
                    child: Icon(
                      isPending
                          ? Icons.lock_clock_outlined
                          : Icons.lock_open_rounded,
                      color: isPending ? Colors.orange : Colors.green,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        LText(
                          s['label']?.toString() ?? 'Общий пароль',
                          style: TextStyle(
                            color: AppColors.text,
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(height: 2),
                        LText(
                          isPending ? 'Ожидает принятия' : 'Принято',
                          style: TextStyle(
                            fontSize: 12,
                            color: isPending
                                ? Colors.orange
                                : Colors.green,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (isPending)
                    ElevatedButton(
                      onPressed: () => _showAcceptDialog(s),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.button,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 8),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                      ),
                      child: const LText('Принять',
                          style: TextStyle(fontSize: 13)),
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildOutgoingList() {
    if (_outgoing.isEmpty) {
      return _buildEmptyState(
        icon: Icons.send_rounded,
        title: 'Нет исходящих',
        subtitle: 'Поделитесь паролем — нажмите\n«Поделиться» в списке паролей',
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      color: AppColors.button,
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: _outgoing.length,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (_, i) {
          final s = _outgoing[i];
          final isRevoked = s['status'] == 'revoked';
          return ThemedContainer(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: (isRevoked
                              ? AppColors.text.withOpacity(0.1)
                              : AppColors.button.withOpacity(0.12)),
                      borderRadius: BorderRadius.circular(11),
                    ),
                    child: Icon(
                      isRevoked
                          ? Icons.block_rounded
                          : Icons.share_rounded,
                      color: isRevoked
                          ? AppColors.text.withOpacity(0.4)
                          : AppColors.button,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        LText(
                          s['label']?.toString() ?? 'Пароль',
                          style: TextStyle(
                            color: AppColors.text,
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(height: 2),
                        LText(
                          'Кому: ${s['recipient_login'] ?? '—'}',
                          style: TextStyle(
                            fontSize: 12,
                            color: AppColors.text.withOpacity(0.55),
                          ),
                        ),
                        if (s['expires_at'] != null)
                          LText(
                            'До: ${_formatDate(s['expires_at'].toString())}',
                            style: TextStyle(
                              fontSize: 11,
                              color: AppColors.text.withOpacity(0.4),
                            ),
                          ),
                      ],
                    ),
                  ),
                  if (!isRevoked)
                    IconButton(
                      icon: Icon(Icons.cancel_outlined,
                          color: AppColors.text.withOpacity(0.4), size: 20),
                      tooltip: 'Отозвать',
                      onPressed: () async {
                        final ok = await showDialog<bool>(
                          context: context,
                          builder: (c) => AlertDialog(
                            backgroundColor: AppColors.surface,
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16)),
                            title: NeonText(
                                text: 'Отозвать доступ?',
                                style: TextStyle(color: AppColors.text)),
                            content: LText(
                              'Получатель больше не сможет расшифровать пароль.',
                              style: TextStyle(
                                  color: AppColors.text.withOpacity(0.7)),
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(c, false),
                                child: LText('Отмена',
                                    style: TextStyle(
                                        color:
                                            AppColors.text.withOpacity(0.6))),
                              ),
                              ElevatedButton(
                                onPressed: () => Navigator.pop(c, true),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppColors.error,
                                  foregroundColor: Colors.white,
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(10)),
                                ),
                                child: const LText('Отозвать'),
                              ),
                            ],
                          ),
                        );
                        if (ok == true) {
                          try {
                            await _sharing.revokeShare(s['id'] as int);
                            await _load();
                          } catch (e) {
                            _showError('Ошибка: $e');
                          }
                        }
                      },
                    )
                  else
                    Padding(
                      padding: const EdgeInsets.only(right: 4),
                      child: LText(
                        'Отозван',
                        style: TextStyle(
                          fontSize: 11,
                          color: AppColors.text.withOpacity(0.35),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildEmptyState({
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: AppColors.button.withOpacity(0.08),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Icon(icon,
                  size: 40, color: AppColors.button.withOpacity(0.5)),
            ),
            const SizedBox(height: 20),
            NeonText(
              text: title,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: AppColors.text,
              ),
            ),
            const SizedBox(height: 8),
            LText(
              subtitle,
              style: TextStyle(
                fontSize: 13,
                color: AppColors.text.withOpacity(0.5),
                height: 1.5,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: LText(message),
        backgroundColor: AppColors.error,
      ),
    );
  }

  String _formatDate(String iso) {
    try {
      final d = DateTime.parse(iso).toLocal();
      return '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';
    } catch (_) {
      return iso;
    }
  }
}

// ── Small helper widgets ──────────────────────────────────────────────────────

class _SheetLabel extends StatelessWidget {
  final String label;
  final IconData icon;
  const _SheetLabel({required this.label, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 13, color: AppColors.button.withOpacity(0.8)),
        const SizedBox(width: 5),
        LText(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: AppColors.text.withOpacity(0.6),
            letterSpacing: 0.3,
          ),
        ),
      ],
    );
  }
}

class _StyledField extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final IconData icon;
  const _StyledField(
      {required this.controller, required this.hint, required this.icon});

  @override
  Widget build(BuildContext context) {
    return ThemedContainer(
      child: TextField(
        controller: controller,
        style: TextStyle(color: AppColors.text, fontSize: 14),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle:
              TextStyle(color: AppColors.text.withOpacity(0.35), fontSize: 14),
          prefixIcon: Icon(icon, color: AppColors.button.withOpacity(0.7), size: 18),
          border: InputBorder.none,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        ),
      ),
    );
  }
}
