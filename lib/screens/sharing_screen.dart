import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/sharing_service.dart';
import '../services/vault_service.dart';

class SharingScreen extends StatefulWidget {
  const SharingScreen({super.key});

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
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final results = await Future.wait([
        _sharing.getIncomingShares(),
        _sharing.getOutgoingShares(),
      ]);
      setState(() {
        _incoming = results[0];
        _outgoing = results[1];
        _loading = false;
      });
    } catch (e) {
      setState(() => _loading = false);
      _showError('Failed to load shares: $e');
    }
  }

  // ── Create share ──────────────────────────────────────────────────────────

  void _showCreateShareDialog() {
    if (_vault.isLocked) {
      _showError('Vault is locked. Please unlock first.');
      return;
    }
    final recipientCtrl = TextEditingController();
    final payloadCtrl = TextEditingController();
    final labelCtrl = TextEditingController();
    int? expiryDays;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlgState) => AlertDialog(
          title: const Text('Share a Password'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'The password will be re-encrypted with a one-time key. '
                  'Send the key to the recipient separately.',
                  style: TextStyle(fontSize: 12),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: recipientCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Recipient username',
                    prefixIcon: Icon(Icons.person),
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: labelCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Label (optional)',
                    prefixIcon: Icon(Icons.label),
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: payloadCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Encrypted payload',
                    prefixIcon: Icon(Icons.lock),
                    helperText: 'Paste the encrypted_payload from the vault entry',
                  ),
                  maxLines: 3,
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<int?>(
                  value: expiryDays,
                  decoration: const InputDecoration(labelText: 'Expires in'),
                  items: const [
                    DropdownMenuItem(value: null, child: Text('Never')),
                    DropdownMenuItem(value: 1, child: Text('1 day')),
                    DropdownMenuItem(value: 7, child: Text('7 days')),
                    DropdownMenuItem(value: 30, child: Text('30 days')),
                  ],
                  onChanged: (v) => setDlgState(() => expiryDays = v),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                if (recipientCtrl.text.trim().isEmpty ||
                    payloadCtrl.text.trim().isEmpty) return;
                Navigator.pop(ctx);
                await _createShare(
                  recipient: recipientCtrl.text.trim(),
                  encryptedPayload: payloadCtrl.text.trim(),
                  label: labelCtrl.text.trim().isEmpty
                      ? null
                      : labelCtrl.text.trim(),
                  expiresInDays: expiryDays,
                );
              },
              child: const Text('Share'),
            ),
          ],
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
      _showShareKeyDialog(result.shareKey);
      await _load();
    } catch (e) {
      _showError('Share failed: $e');
    }
  }

  void _showShareKeyDialog(String shareKey) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Share Created'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Send this key to the recipient. Shown only once — copy it now.',
              style: TextStyle(fontSize: 12),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: SelectableText(
                      shareKey,
                      style: const TextStyle(
                          fontFamily: 'monospace', fontSize: 11),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.copy),
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: shareKey));
                      ScaffoldMessenger.of(ctx).showSnackBar(
                        const SnackBar(content: Text('Key copied')),
                      );
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }

  // ── Accept a share ────────────────────────────────────────────────────────

  void _showAcceptDialog(Map<String, dynamic> share) {
    final keyCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Accept & Decrypt Share'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (share['label'] != null)
              Text('Label: ${share['label']}',
                  style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            const Text('Enter the share key you received from the sender:'),
            const SizedBox(height: 8),
            TextField(
              controller: keyCtrl,
              decoration: const InputDecoration(
                labelText: 'Share key',
                prefixIcon: Icon(Icons.key),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              if (keyCtrl.text.trim().isEmpty) return;
              Navigator.pop(ctx);
              await _acceptShare(share['id'] as int, keyCtrl.text.trim());
            },
            child: const Text('Decrypt'),
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
      _showError('Failed: $e');
    }
  }

  void _showDecryptedResult(String plaintext) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Decrypted Password'),
        content: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.green.shade50,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              Expanded(
                child: SelectableText(
                  plaintext,
                  style: const TextStyle(fontFamily: 'monospace'),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.copy),
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: plaintext));
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    const SnackBar(content: Text('Copied')),
                  );
                },
              ),
            ],
          ),
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Secure Sharing'),
        bottom: TabBar(
          controller: _tabs,
          tabs: const [
            Tab(icon: Icon(Icons.inbox), text: 'Received'),
            Tab(icon: Icon(Icons.send), text: 'Sent'),
          ],
        ),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showCreateShareDialog,
        icon: const Icon(Icons.share),
        label: const Text('Share Password'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabs,
              children: [
                _buildIncomingList(),
                _buildOutgoingList(),
              ],
            ),
    );
  }

  Widget _buildIncomingList() {
    if (_incoming.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.inbox, size: 64, color: Colors.grey),
            SizedBox(height: 16),
            Text('No shares received yet'),
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        itemCount: _incoming.length,
        separatorBuilder: (_, __) => const Divider(),
        itemBuilder: (_, i) {
          final s = _incoming[i];
          final status = s['status'] as String;
          return ListTile(
            leading: CircleAvatar(
              backgroundColor:
                  status == 'accepted' ? Colors.green : Colors.orange,
              child: const Icon(Icons.lock_open, color: Colors.white),
            ),
            title: Text(s['label']?.toString() ?? 'Shared password'),
            subtitle: Text('Status: $status'),
            trailing: status == 'pending'
                ? ElevatedButton(
                    onPressed: () => _showAcceptDialog(s),
                    child: const Text('Accept'),
                  )
                : null,
          );
        },
      ),
    );
  }

  Widget _buildOutgoingList() {
    if (_outgoing.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.send, size: 64, color: Colors.grey),
            SizedBox(height: 16),
            Text('No shares sent yet'),
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        itemCount: _outgoing.length,
        separatorBuilder: (_, __) => const Divider(),
        itemBuilder: (_, i) {
          final s = _outgoing[i];
          return ListTile(
            leading: const CircleAvatar(
              child: Icon(Icons.share),
            ),
            title: Text(s['label']?.toString() ?? 'Shared password'),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('To: ${s['recipient_login']}'),
                Text('Status: ${s['status']}'),
                if (s['expires_at'] != null)
                  Text('Expires: ${s['expires_at']}',
                      style: const TextStyle(fontSize: 11)),
              ],
            ),
            isThreeLine: true,
            trailing: s['status'] != 'revoked'
                ? IconButton(
                    icon: const Icon(Icons.cancel, color: Colors.red),
                    tooltip: 'Revoke',
                    onPressed: () async {
                      try {
                        await _sharing.revokeShare(s['id'] as int);
                        await _load();
                      } catch (e) {
                        _showError('Revoke failed: $e');
                      }
                    },
                  )
                : const Icon(Icons.block, color: Colors.grey),
          );
        },
      ),
    );
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
    );
  }
}
