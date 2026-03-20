import 'package:flutter/material.dart';
import '../theme/colors.dart';
import '../utils/biometric_service.dart';
import '../l10n/l_text.dart';

class BiometricTestScreen extends StatefulWidget {
  const BiometricTestScreen({super.key});

  @override
  State<BiometricTestScreen> createState() => _BiometricTestScreenState();
}

class _BiometricTestScreenState extends State<BiometricTestScreen> {
  Map<String, dynamic> _diagnosticInfo = {};
  bool _isLoading = true;
  String _testResult = '';
  bool _isTesting = false;

  @override
  void initState() {
    super.initState();
    _loadDiagnosticInfo();
  }

  Future<void> _loadDiagnosticInfo() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final info = await BiometricService.getDiagnosticInfo();
      setState(() {
        _diagnosticInfo = info;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _diagnosticInfo = {'error': e.toString()};
        _isLoading = false;
      });
    }
  }

  Future<void> _testBiometricAuthentication() async {
    setState(() {
      _isTesting = true;
      _testResult = '';
    });

    try {
      final result = await BiometricService.authenticate(
        reason: 'Тестирование биометрической аутентификации',
      );

      setState(() {
        _testResult = result != null ? 'Успешно!' : 'Не удалось';
        _isTesting = false;
      });
    } catch (e) {
      setState(() {
        _testResult = 'Ошибка: $e';
        _isTesting = false;
      });
    }
  }

  Future<void> _forceEnableBiometrics() async {
    setState(() {
      _isTesting = true;
    });

    try {
      final success = await BiometricService.forceEnableBiometrics();

      if (success) {
        setState(() {
          _testResult = 'Биометрия принудительно включена!';
        });
        await _loadDiagnosticInfo(); // Обновляем диагностику
      } else {
        setState(() {
          _testResult = 'Не удалось включить биометрию';
        });
      }
    } catch (e) {
      setState(() {
        _testResult = 'Ошибка: $e';
      });
    } finally {
      setState(() {
        _isTesting = false;
      });
    }
  }

  Future<void> _resetBiometricSettings() async {
    setState(() {
      _isTesting = true;
    });

    try {
      await BiometricService.resetBiometricSettings();
      setState(() {
        _testResult = 'Настройки биометрии сброшены';
      });
      await _loadDiagnosticInfo(); // Обновляем диагностику
    } catch (e) {
      setState(() {
        _testResult = 'Ошибка при сбросе: $e';
      });
    } finally {
      setState(() {
        _isTesting = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        title: LText('Тест биометрии', style: TextStyle(color: AppColors.text)),
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: AppColors.text),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body:
          _isLoading
              ? const Center(child: CircularProgressIndicator())
              : SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Статус системы
                    _buildStatusCard(),
                    const SizedBox(height: 16),

                    // Диагностическая информация
                    _buildDiagnosticCard(),
                    const SizedBox(height: 16),

                    // Тестовые кнопки
                    _buildTestButtons(),
                    const SizedBox(height: 16),

                    // Результат теста
                    if (_testResult.isNotEmpty) _buildTestResult(),
                  ],
                ),
              ),
    );
  }

  Widget _buildStatusCard() {
    final systemStatus = _diagnosticInfo['systemStatus'] ?? 'Неизвестно';
    final canUse = _diagnosticInfo['canUseBiometrics'] ?? false;

    Color statusColor;
    IconData statusIcon;

    if (canUse) {
      statusColor = Colors.green;
      statusIcon = Icons.check_circle;
    } else {
      statusColor = Colors.red;
      statusIcon = Icons.error;
    }

    return Card(
      color: AppColors.input,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(statusIcon, color: statusColor, size: 32),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  LText(
                    'Статус биометрии',
                    style: TextStyle(
                      color: AppColors.text,
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 4),
                  LText(
                    systemStatus,
                    style: TextStyle(color: statusColor, fontSize: 14),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDiagnosticCard() {
    return Card(
      color: AppColors.input,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            LText(
              'Диагностическая информация',
              style: TextStyle(
                color: AppColors.text,
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 12),
            _buildDiagnosticRow(
              'Может проверять биометрию',
              '${_diagnosticInfo['canCheckBiometrics'] ?? 'N/A'}',
            ),
            _buildDiagnosticRow(
              'Устройство поддерживается',
              '${_diagnosticInfo['isDeviceSupported'] ?? 'N/A'}',
            ),
            _buildDiagnosticRow(
              'Включена в настройках',
              '${_diagnosticInfo['isEnabled'] ?? 'N/A'}',
            ),
            _buildDiagnosticRow(
              'Всего доступных методов',
              '${_diagnosticInfo['totalAvailableMethods'] ?? 'N/A'}',
            ),
            _buildDiagnosticRow(
              'Можно использовать',
              '${_diagnosticInfo['canUseBiometrics'] ?? 'N/A'}',
            ),

            if (_diagnosticInfo['biometricDetails'] != null &&
                (_diagnosticInfo['biometricDetails'] as Map<String, String>)
                    .isNotEmpty) ...[
              const SizedBox(height: 12),
              LText(
                'Доступные методы:',
                style: TextStyle(
                  color: AppColors.text,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 8),
              ...(_diagnosticInfo['biometricDetails'] as Map<String, String>)
                  .entries
                  .map(
                    (entry) => Padding(
                      padding: const EdgeInsets.only(left: 16, bottom: 4),
                      child: LText(
                        '• ${entry.value}',
                        style: const TextStyle(
                          color: Colors.grey,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildDiagnosticRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 140,
            child: LText(
              label,
              style: TextStyle(
                color: AppColors.text,
                fontWeight: FontWeight.w500,
                fontSize: 12,
              ),
            ),
          ),
          Expanded(
            child: LText(
              value,
              style: TextStyle(
                color:
                    value == 'true'
                        ? Colors.green
                        : value == 'false'
                        ? Colors.red
                        : Colors.grey,
                fontSize: 12,
                fontWeight:
                    value == 'true' || value == 'false'
                        ? FontWeight.bold
                        : FontWeight.normal,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTestButtons() {
    return Card(
      color: AppColors.input,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            LText(
              'Тестирование',
              style: TextStyle(
                color: AppColors.text,
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _isTesting ? null : _testBiometricAuthentication,
                    icon: const Icon(Icons.fingerprint),
                    label: const LText('Тест аутентификации'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.button,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _isTesting ? null : _forceEnableBiometrics,
                    icon: const Icon(Icons.power_settings_new),
                    label: const LText('Принудительно включить'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.orange,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _isTesting ? null : _resetBiometricSettings,
                    icon: const Icon(Icons.refresh),
                    label: const LText('Сбросить'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTestResult() {
    final isSuccess =
        _testResult.contains('Успешно') || _testResult.contains('включена');
    final isError =
        _testResult.contains('Ошибка') || _testResult.contains('Не удалось');

    Color resultColor;
    if (isSuccess) {
      resultColor = Colors.green;
    } else if (isError) {
      resultColor = Colors.red;
    } else {
      resultColor = Colors.orange;
    }

    return Card(
      color: AppColors.input,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            LText(
              'Результат теста',
              style: TextStyle(
                color: AppColors.text,
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: resultColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: resultColor.withOpacity(0.3)),
              ),
              child: Row(
                children: [
                  Icon(
                    isSuccess ? Icons.check_circle : Icons.info,
                    color: resultColor,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: LText(
                      _testResult,
                      style: TextStyle(
                        color: resultColor,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
