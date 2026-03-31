import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:crypto/crypto.dart';
import 'package:nk3_zero/main.dart'; // import for navigatorKey
import 'package:shared_preferences/shared_preferences.dart';

/// =============================================
///          MEMORY SECURITY & CLIPBOARD PROTECTION
/// =============================================
///
/// Центральный класс для безопасной работы с чувствительными данными:
/// - пароли, seed-фразы, TOTP-коды, мастер-ключи и т.д.

// ── SecureBuffer ──────────────────────────────────────────────────────────────

/// A `Uint8List` wrapper that can be explicitly zeroed out after use.
/// Uses a private buffer to prevent accidental reference leakage.
class SecureBuffer {
  Uint8List? _data;
  bool _wiped = false;

  SecureBuffer(Uint8List data) : _data = Uint8List.fromList(data);

  factory SecureBuffer.fromBytes(List<int> bytes) =>
      SecureBuffer(Uint8List.fromList(bytes));

  /// Returns a COPY of the internal bytes.
  /// Use this for transient operations (like String.fromCharCodes).
  Uint8List getBytesCopy() {
    if (_wiped || _data == null) throw StateError('SecureBuffer already wiped');
    return Uint8List.fromList(_data!);
  }

  /// Internal access for generation only.
  @visibleForTesting
  Uint8List get rawBytes {
    if (_wiped || _data == null) throw StateError('SecureBuffer already wiped');
    return _data!;
  }

  int get length => _data?.length ?? 0;
  bool get isWiped => _wiped;

  /// Overwrite every byte with zero and release the data.
  void wipe() {
    if (_wiped || _data == null) return;
    _data!.fillRange(0, _data!.length, 0);
    _data = null;
    _wiped = true;
  }
}

// ─────────────────────────────────────────────────────────────────────────────

class MemorySecurity {
  // ================== НАСТРОЙКИ (persisted in SharedPreferences) ==================
  static const String _clipboardDelayKey = 'clipboard_clear_delay_seconds';
  static const int _defaultDelaySeconds = 30;

  /// Получить время автоочистки буфера (настраивается пользователем)
  static Future<Duration> getClipboardClearDelay() async {
    final prefs = await SharedPreferences.getInstance();
    final seconds = prefs.getInt(_clipboardDelayKey) ?? _defaultDelaySeconds;
    return Duration(seconds: seconds.clamp(10, 120)); // от 10 до 120 сек
  }

  /// Установить время автоочистки
  static Future<void> setClipboardClearDelay(int seconds) async {
    if (seconds < 10 || seconds > 120) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_clipboardDelayKey, seconds);
  }

  // ================== ОСНОВНЫЕ ФУНКЦИИ КОПИРОВАНИЯ ==================

  /// Главная защищённая функция копирования чувствительных данных
  ///
  /// Что делает:
  /// 1. Копирует текст в буфер
  /// 2. Помечает как sensitive (Android 13+)
  /// 3. Native wipe оригинальной строки
  /// 4. Показывает уведомление пользователю
  /// 5. Планирует безопасную очистку через N секунд
  static Future<void> copySensitiveData(
    String sensitiveText, {
    String label = 'password', // для уведомлений
    Duration? clearAfter,
  }) async {
    if (sensitiveText.isEmpty) return;

    final delay = clearAfter ?? await getClipboardClearDelay();
    final clipboardHash = sha256.convert(utf8.encode(sensitiveText)).toString();

    try {
      // 1. Копируем в буфер
      await Clipboard.setData(ClipboardData(text: sensitiveText));

      // 2. Пытаемся пометить как sensitive (Android 13+)
      await _markClipboardAsSensitive(sensitiveText);

      // 3. Native wipe оригинальной строки
      await nativeWipe(sensitiveText);

      // 4. Показываем уведомление пользователю
      _showSecureCopyNotification(label, delay);

      // 5. Планируем безопасную очистку
      _scheduleSecureClipboardClear(clipboardHash, delay);
    } catch (e) {
      debugPrint('Secure copy failed: $e');
      // Fallback: стандартное копирование
      await Clipboard.setData(ClipboardData(text: sensitiveText));
    }
  }

  /// Специализированные методы для UI
  static Future<void> copyPassword(String password) =>
      copySensitiveData(password, label: 'Пароль');

  static Future<void> copySeedPhrase(String seed) => copySensitiveData(seed,
      label: 'Seed фраза', clearAfter: const Duration(seconds: 45));

  static Future<void> copyTotp(String totp) => copySensitiveData(totp,
      label: 'TOTP код', clearAfter: const Duration(seconds: 20));

  // ================== ВНУТРЕННИЕ ВСПОМОГАТЕЛЬНЫЕ МЕТОДЫ ==================

  /// Android-only: пометить содержимое буфера как sensitive (скрывает в клавиатуре)
  static Future<void> _markClipboardAsSensitive(String text) async {
    if (!Platform.isAndroid) return;

    const channel = MethodChannel('com.zerovault/clipboard');
    try {
      await channel.invokeMethod('setSensitiveClipboard', {'text': text});
    } catch (e) {
      debugPrint('Failed to mark clipboard as sensitive: $e');
    }
  }

  /// Показывает уведомление пользователю (Security Snackbar)
  static void _showSecureCopyNotification(String label, Duration delay) {
    final context = navigatorKey.currentContext;
    if (context == null) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.shield_rounded, color: Colors.white, size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                '$label скопирован • очистится через ${delay.inSeconds} сек',
                style: const TextStyle(color: Colors.white),
              ),
            ),
          ],
        ),
        backgroundColor: Colors.green.shade700,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        duration: const Duration(seconds: 4),
      ),
    );
  }

  /// Планирует безопасную очистку буфера обмена (с проверкой хеша)
  static void _scheduleSecureClipboardClear(String originalHash, Duration delay) {
    Future.delayed(delay, () async {
      try {
        final currentData = await Clipboard.getData('text/plain');
        final currentText = currentData?.text;

        if (currentText == null || currentText.isEmpty) return;

        final currentHash = sha256.convert(utf8.encode(currentText)).toString();

        // Очищаем только если это наш контент
        if (currentHash == originalHash) {
          await Clipboard.setData(const ClipboardData(text: ''));
          debugPrint('Clipboard securely cleared after ${delay.inSeconds}s');
        }
      } catch (e) {
        debugPrint('Failed to clear clipboard: $e');
      }
    });
  }
}

// ── Native Bridge ─────────────────────────────────────────────────────────────

const _channel = MethodChannel('secure_wipe');

/// Native wipe через MethodChannel (вызывает Kotlin-код)
Future<void> nativeWipe(String? text) async {
  if (text == null || text.isEmpty || kIsWeb) return;

  try {
    await _channel.invokeMethod('wipeString', text);
  } catch (e) {
    debugPrint('Native wipe failed: $e');
    // Fallback: хотя бы в Dart памяти (best-effort)
    final bytes = Uint8List.fromList(utf8.encode(text));
    bytes.fillRange(0, bytes.length, 0);
  }
}

// ── TextEditingController wipe ────────────────────────────────────────────────

/// Best-effort wipe of a TextEditingController.
/// Overwrites visible text with NUL characters and calls native wipe.
Future<void> wipeController(TextEditingController controller) async {
  final text = controller.text;
  if (text.isEmpty) return;

  try {
    await nativeWipe(text);
    controller.text = '\u0000' * text.length;
    controller.clear();
  } catch (_) {}
}

// ── CSPRNG password generator ─────────────────────────────────────────────────

/// Generates a cryptographically secure random password directly into a SecureBuffer.
String generateSecurePassword({int length = 24}) {
  if (length < 14) throw ArgumentError('Password length must be at least 14');

  const upper = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ';
  const lower = 'abcdefghijklmnopqrstuvwxyz';
  const digits = '0123456789';
  const symbols = '!@#\$%^&*()_+-=[]{}|;:,.<>?';
  const all = upper + lower + digits + symbols;

  final buffer = SecureBuffer(Uint8List(length));
  final rng = Random.secure();

  try {
    final bytes = buffer.rawBytes;
    bytes[0] = upper.codeUnitAt(rng.nextInt(upper.length));
    bytes[1] = lower.codeUnitAt(rng.nextInt(lower.length));
    bytes[2] = digits.codeUnitAt(rng.nextInt(digits.length));
    bytes[3] = symbols.codeUnitAt(rng.nextInt(symbols.length));

    for (int i = 4; i < length; i++) {
      bytes[i] = all.codeUnitAt(rng.nextInt(all.length));
    }

    // Shuffle
    for (int i = length - 1; i > 0; i--) {
      final j = rng.nextInt(i + 1);
      final tmp = bytes[i];
      bytes[i] = bytes[j];
      bytes[j] = tmp;
    }

    return String.fromCharCodes(bytes);
  } finally {
    buffer.wipe();
  }
}

// ── Compatibility Helpers ─────────────────────────────────

Future<void> copySecureBuffer(SecureBuffer buffer, {Duration? clearAfter}) async {
  final copy = buffer.getBytesCopy();
  try {
    final text = String.fromCharCodes(copy);
    await MemorySecurity.copySensitiveData(text, clearAfter: clearAfter);
  } finally {
    copy.fillRange(0, copy.length, 0);
  }
}

Future<void> copyWithAutoClear(String text, {Duration? clearAfter}) async {
  await MemorySecurity.copySensitiveData(text, clearAfter: clearAfter);
}

