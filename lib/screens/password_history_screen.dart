import 'package:flutter/material.dart';
import '../theme/colors.dart';
import '../utils/password_history_service.dart';

class PasswordHistoryScreen extends StatefulWidget {
  const PasswordHistoryScreen({super.key});

  @override
  State<PasswordHistoryScreen> createState() => _PasswordHistoryScreenState();
}

class _PasswordHistoryScreenState extends State<PasswordHistoryScreen> {
  List<Map<String, dynamic>> _history = [];
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final history = await PasswordHistoryService.getPasswordHistory();
      setState(() {
        _history = history;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'Ошибка при загрузке истории';
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('История паролей'),
        backgroundColor: AppColors.background,
        elevation: 0,
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _loadHistory),
        ],
      ),
      body:
          _isLoading
              ? const Center(child: CircularProgressIndicator())
              : _errorMessage != null
              ? _buildErrorWidget()
              : _history.isEmpty
              ? _buildEmptyWidget()
              : _buildHistoryList(),
    );
  }

  Widget _buildErrorWidget() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.error_outline,
            size: 64,
            color: Colors.red.withOpacity(0.7),
          ),
          const SizedBox(height: 16),
          Text(
            _errorMessage!,
            style: const TextStyle(color: Colors.red, fontSize: 16),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: _loadHistory,
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.button),
            child: const Text('Повторить'),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyWidget() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.history, size: 64, color: Colors.grey.withOpacity(0.7)),
          const SizedBox(height: 16),
          const Text(
            'История пуста',
            style: TextStyle(
              color: Colors.grey,
              fontSize: 18,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Здесь будут отображаться изменения\nваших паролей',
            style: TextStyle(color: Colors.grey, fontSize: 14),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildHistoryList() {
    return RefreshIndicator(
      onRefresh: _loadHistory,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _history.length,
        itemBuilder: (context, index) {
          final item = _history[index];
          return _buildHistoryItem(item);
        },
      ),
    );
  }

  Widget _buildHistoryItem(Map<String, dynamic> item) {
    final actionType = item['action_type'] ?? '';
    final siteUrl = item['site_url'] ?? '';
    final actionTime = item['action_time'] ?? '';
    final actionDetails = item['action_details'] ?? {};

    return Card(
      color: AppColors.input,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppColors.button.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    PasswordHistoryService.getActionTypeIcon(actionType),
                    style: const TextStyle(fontSize: 16),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        PasswordHistoryService.getActionTypeDisplayName(
                          actionType,
                        ),
                        style: TextStyle(
                          color: AppColors.text,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        siteUrl,
                        style: const TextStyle(
                          color: Colors.grey,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
                Text(
                  PasswordHistoryService.formatDate(actionTime),
                  style: const TextStyle(color: Colors.grey, fontSize: 12),
                ),
              ],
            ),
            if (actionDetails.isNotEmpty) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.grey.withOpacity(0.2)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Детали изменений:',
                      style: TextStyle(
                        color: Colors.grey,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 8),
                    ...actionDetails.entries.map((entry) {
                      final key = entry.key;
                      final value = entry.value;

                      return Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SizedBox(
                              width: 80,
                              child: Text(
                                _getFieldDisplayName(key),
                                style: const TextStyle(
                                  color: Colors.grey,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                            Expanded(
                              child: Text(
                                _formatFieldValue(value),
                                style: TextStyle(
                                  color: AppColors.text,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _getFieldDisplayName(String key) {
    switch (key.toLowerCase()) {
      case 'old':
        return 'Было:';
      case 'new':
        return 'Стало:';
      case 'site_url':
        return 'Сайт:';
      case 'site_login':
        return 'Логин:';
      case 'site_password':
        return 'Пароль:';
      case 'has_2fa':
        return '2FA:';
      case 'has_seed_phrase':
        return 'Seed:';
      case 'notes':
        return 'Заметки:';
      default:
        return '$key:';
    }
  }

  String _formatFieldValue(dynamic value) {
    if (value == null) {
      return 'не указано';
    }

    if (value is bool) {
      return value ? 'Да' : 'Нет';
    }

    if (value is String) {
      // Скрываем пароли
      if (value.contains('password') || value.contains('Password')) {
        return '••••••••';
      }
      return value;
    }

    return value.toString();
  }
}
