import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/emergency_service.dart';
import '../services/vault_service.dart';

class EmergencyScreen extends StatefulWidget {
  const EmergencyScreen({super.key});

  @override
  State<EmergencyScreen> createState() => _EmergencyScreenState();
}

class _EmergencyScreenState extends State<EmergencyScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  final _service = EmergencyService();
  final _vault = VaultService();

  List<Map<String, dynamic>> _asGrantor = [];
  List<Map<String, dynamic>> _asGrantee = [];
  bool _loading = true;
  int? _currentUserId;

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
      final all = await _service.listAll();
      // Separate by role — server returns grantor_id and grantee_id
      final userId = _currentUserId;
      if (userId != null) {
        setState(() {
          _asGrantor =
              all.where((e) => e['grantor_id'] == userId).toList();
          _asGrantee =
              all.where((e) => e['grantee_id'] == userId).toList();
          _loading = false;
        });
      } else {
        // On first load, both lists contain all entries; split after fetching user id
        setState(() {
          _asGrantor = all; // will be filtered once we know userId
          _asGrantee = all;
          _loading = false;
        });
      }
    } catch (e) {
      setState(() => _loading = false);
      _showError('Failed to load: $e');
    }
  }

  // ── Invite a trusted contact ──────────────────────────────────────────────

  void _showInviteDialog() {
    final loginCtrl = TextEditingController();
    int waitDays = 7;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlgState) => AlertDialog(
          title: const Text('Add Emergency Contact'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'If you do not respond within the wait period after an '
                  'emergency request, your contact will gain access to the '
                  'encrypted vault snapshot you upload.',
                  style: TextStyle(fontSize: 12),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: loginCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Contact username',
                    prefixIcon: Icon(Icons.person_add),
                  ),
                ),
                const SizedBox(height: 12),
                Text('Wait period: $waitDays days',
                    style: const TextStyle(fontWeight: FontWeight.bold)),
                Slider(
                  value: waitDays.toDouble(),
                  min: 1,
                  max: 30,
                  divisions: 29,
                  label: '$waitDays days',
                  onChanged: (v) =>
                      setDlgState(() => waitDays = v.round()),
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
                if (loginCtrl.text.trim().isEmpty) return;
                Navigator.pop(ctx);
                await _invite(loginCtrl.text.trim(), waitDays);
              },
              child: const Text('Invite'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _invite(String login, int waitDays) async {
    try {
      await _service.inviteContact(granteeLogin: login, waitDays: waitDays);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Invitation sent to $login')),
      );
      await _load();
    } catch (e) {
      _showError('Failed to invite: $e');
    }
  }

  // ── Upload vault snapshot ─────────────────────────────────────────────────

  Future<void> _uploadVault(int eaId) async {
    if (_vault.isLocked) {
      _showError('Vault is locked. Please unlock first.');
      return;
    }
    try {
      final passwords = await _vault.syncVault();
      final shareKeyB64 = await _service.uploadVaultSnapshot(
        eaId: eaId,
        decryptedPasswords: passwords,
      );
      if (!mounted) return;
      _showShareKeyDialog(shareKeyB64);
    } catch (e) {
      _showError('Upload failed: $e');
    }
  }

  void _showShareKeyDialog(String key) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Vault Uploaded'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Give this key to your emergency contact now. '
              'They will need it to decrypt the vault. Store it safely.',
              style: TextStyle(fontSize: 12),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.amber.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.amber),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: SelectableText(
                      key,
                      style: const TextStyle(
                          fontFamily: 'monospace', fontSize: 11),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.copy),
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: key));
                      ScaffoldMessenger.of(ctx)
                          .showSnackBar(const SnackBar(content: Text('Copied')));
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

  // ── Download vault (grantee) ──────────────────────────────────────────────

  void _showDownloadVaultDialog(int eaId) {
    final keyCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Access Emergency Vault'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Enter the emergency key you received from the vault owner:'),
            const SizedBox(height: 8),
            TextField(
              controller: keyCtrl,
              decoration: const InputDecoration(
                labelText: 'Emergency key',
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
              await _downloadAndShowVault(eaId, keyCtrl.text.trim());
            },
            child: const Text('Decrypt'),
          ),
        ],
      ),
    );
  }

  Future<void> _downloadAndShowVault(int eaId, String shareKey) async {
    try {
      final passwords = await _service.downloadVault(
          eaId: eaId, shareKeyB64: shareKey);
      if (!mounted) return;
      _showVaultContent(passwords);
    } catch (e) {
      _showError('Failed to download vault: $e');
    }
  }

  void _showVaultContent(List<Map<String, dynamic>> passwords) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Emergency Vault (${passwords.length} entries)'),
        content: SizedBox(
          width: double.maxFinite,
          height: 400,
          child: ListView.builder(
            itemCount: passwords.length,
            itemBuilder: (_, i) {
              final p = passwords[i];
              final name = p['name']?.toString() ??
                  p['site_url']?.toString() ??
                  'Entry ${p['id']}';
              return ListTile(
                title: Text(name),
                subtitle: Text(p['site_login']?.toString() ?? ''),
              );
            },
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
        title: const Text('Emergency Access'),
        bottom: TabBar(
          controller: _tabs,
          tabs: const [
            Tab(icon: Icon(Icons.security), text: 'My Contacts'),
            Tab(icon: Icon(Icons.emergency), text: 'My Access'),
          ],
        ),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showInviteDialog,
        icon: const Icon(Icons.person_add),
        label: const Text('Add Contact'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabs,
              children: [
                _buildGrantorList(),
                _buildGranteeList(),
              ],
            ),
    );
  }

  // ── Grantor tab ───────────────────────────────────────────────────────────

  Widget _buildGrantorList() {
    if (_asGrantor.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.security, size: 64, color: Colors.grey),
            const SizedBox(height: 16),
            const Text('No emergency contacts yet'),
            const SizedBox(height: 8),
            ElevatedButton.icon(
              onPressed: _showInviteDialog,
              icon: const Icon(Icons.person_add),
              label: const Text('Add Contact'),
            ),
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        itemCount: _asGrantor.length,
        separatorBuilder: (_, __) => const Divider(),
        itemBuilder: (_, i) => _buildGrantorTile(_asGrantor[i]),
      ),
    );
  }

  Widget _buildGrantorTile(Map<String, dynamic> ea) {
    final status = ea['status'] as String;
    final eaId = ea['id'] as int;
    final granteeLogin = ea['grantee_login']?.toString() ?? '?';

    return ExpansionTile(
      leading: CircleAvatar(
        backgroundColor: _statusColor(status),
        child: const Icon(Icons.person, color: Colors.white),
      ),
      title: Text(granteeLogin),
      subtitle: Text(
        '${EmergencyService.statusLabel(status)} · ${ea['wait_days']} day wait',
      ),
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              // Upload vault
              ElevatedButton.icon(
                onPressed: () => _uploadVault(eaId),
                icon: const Icon(Icons.upload, size: 16),
                label: const Text('Upload Vault'),
              ),
              // Check-in (only when waiting)
              if (status == 'waiting')
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green),
                  onPressed: () async {
                    try {
                      await _service.checkin(eaId);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Check-in recorded')),
                      );
                      await _load();
                    } catch (e) {
                      _showError('$e');
                    }
                  },
                  icon: const Icon(Icons.check, size: 16),
                  label: const Text('Check In'),
                ),
              // Deny (only when waiting)
              if (status == 'waiting')
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.orange),
                  onPressed: () async {
                    try {
                      await _service.denyAccess(eaId);
                      await _load();
                    } catch (e) {
                      _showError('$e');
                    }
                  },
                  icon: const Icon(Icons.block, size: 16),
                  label: const Text('Deny'),
                ),
              // Revoke
              if (status != 'revoked')
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.red),
                  onPressed: () async {
                    final confirm = await _confirmDialog(
                        'Revoke access for $granteeLogin?');
                    if (!confirm) return;
                    try {
                      await _service.revokeAccess(eaId);
                      await _load();
                    } catch (e) {
                      _showError('$e');
                    }
                  },
                  icon: const Icon(Icons.delete, size: 16),
                  label: const Text('Revoke'),
                ),
            ],
          ),
        ),
      ],
    );
  }

  // ── Grantee tab ───────────────────────────────────────────────────────────

  Widget _buildGranteeList() {
    if (_asGrantee.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.emergency, size: 64, color: Colors.grey),
            SizedBox(height: 16),
            Text('No emergency access granted to you'),
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        itemCount: _asGrantee.length,
        separatorBuilder: (_, __) => const Divider(),
        itemBuilder: (_, i) => _buildGranteeTile(_asGrantee[i]),
      ),
    );
  }

  Widget _buildGranteeTile(Map<String, dynamic> ea) {
    final status = ea['status'] as String;
    final eaId = ea['id'] as int;
    final grantorLogin = ea['grantor_login']?.toString() ?? '?';

    return ExpansionTile(
      leading: CircleAvatar(
        backgroundColor: _statusColor(status),
        child: const Icon(Icons.lock, color: Colors.white),
      ),
      title: Text(grantorLogin),
      subtitle: Text(
        '${EmergencyService.statusLabel(status)} · ${ea['wait_days']} day wait',
      ),
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              // Accept invite
              if (status == 'invited')
                ElevatedButton.icon(
                  onPressed: () async {
                    try {
                      await _service.acceptInvite(eaId);
                      await _load();
                    } catch (e) {
                      _showError('$e');
                    }
                  },
                  icon: const Icon(Icons.check, size: 16),
                  label: const Text('Accept Invite'),
                ),
              // Request access
              if (status == 'accepted')
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.orange),
                  onPressed: () async {
                    final confirm = await _confirmDialog(
                      'Request emergency access from $grantorLogin?\n'
                      'They have ${ea['wait_days']} days to respond.',
                    );
                    if (!confirm) return;
                    try {
                      await _service.requestAccess(eaId);
                      await _load();
                      if (!mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                            content: Text('Access requested. Timer started.')),
                      );
                    } catch (e) {
                      _showError('$e');
                    }
                  },
                  icon: const Icon(Icons.emergency, size: 16),
                  label: const Text('Request Access'),
                ),
              // Download vault
              if (status == 'approved')
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green),
                  onPressed: () => _showDownloadVaultDialog(eaId),
                  icon: const Icon(Icons.download, size: 16),
                  label: const Text('Get Vault'),
                ),
              if (ea['requested_at'] != null && status == 'waiting')
                Text(
                  'Requested: ${ea['requested_at']}',
                  style: const TextStyle(fontSize: 11, color: Colors.grey),
                ),
            ],
          ),
        ),
      ],
    );
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  Color _statusColor(String status) {
    switch (status) {
      case 'invited':
        return Colors.blue;
      case 'accepted':
        return Colors.green;
      case 'waiting':
        return Colors.orange;
      case 'approved':
        return Colors.teal;
      case 'denied':
        return Colors.red;
      case 'revoked':
        return Colors.grey;
      default:
        return Colors.grey;
    }
  }

  Future<bool> _confirmDialog(String message) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirm'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
    );
  }
}
