import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:crypto/crypto.dart';

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

// ── Native Bridge ─────────────────────────────────────────────────────────────

const _channel = MethodChannel('secure_wipe');

/// Calls native code to guaranteed zeroing of the string memory.
Future<void> nativeWipe(String? text) async {
  if (text == null || text.isEmpty || kIsWeb) return;
  try {
    await _channel.invokeMethod('wipeString', text);
  } catch (e) {
    debugPrint('Native wipe failed: $e');
  }
}

// ── TextEditingController wipe ────────────────────────────────────────────────

/// Best-effort wipe of a TextEditingController.
/// Overwrites visible text with NUL characters and calls native wipe.
Future<void> wipeController(TextEditingController controller) async {
  final text = controller.text;
  if (text.isEmpty) return;

  try {
    // 1. Notify native side to zero the underlying memory if possible
    await nativeWipe(text);

    // 2. Overwrite in Dart (reduces exposure in heap scans)
    controller.text = '\u0000' * text.length;
    controller.clear();
  } catch (_) {}
}

// ── CSPRNG password generator ─────────────────────────────────────────────────

/// Generates a cryptographically secure random password directly into a SecureBuffer.
String generateSecurePassword({int length = 24}) {
  if (length < 14) throw ArgumentError('Password length must be at least 14');

  const upper   = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ';
  const lower   = 'abcdefghijklmnopqrstuvwxyz';
  const digits  = '0123456789';
  const symbols = '!@#\$%^&*()_+-=[]{}|;:,.<>?';
  const all     = upper + lower + digits + symbols;

  final buffer = SecureBuffer(Uint8List(length));
  final rng = Random.secure();

  try {
    final bytes = buffer.rawBytes;
    // Ensure complexity
    bytes[0] = upper.codeUnitAt(rng.nextInt(upper.length));
    bytes[1] = lower.codeUnitAt(rng.nextInt(lower.length));
    bytes[2] = digits.codeUnitAt(rng.nextInt(digits.length));
    bytes[3] = symbols.codeUnitAt(rng.nextInt(symbols.length));

    for (int i = 4; i < length; i++) {
      bytes[i] = all.codeUnitAt(rng.nextInt(all.length));
    }

    // Shuffle in place
    for (int i = length - 1; i > 0; i--) {
      final j = rng.nextInt(i + 1);
      final tmp = bytes[i];
      bytes[i] = bytes[j];
      bytes[j] = tmp;
    }

    return String.fromCharCodes(bytes);
  } finally {
    // Note: the returned string still exists in heap, but the buffer is zeroed.
    // The caller should wipe the controller/field using [wipeController].
    buffer.wipe();
  }
}

// ── Clipboard with native-assisted wipe ───────────────────────────────────────

/// Copies a SecureBuffer to clipboard and schedules native wipe.
Future<void> copySecureBuffer(SecureBuffer buffer, {
  Duration clearAfter = const Duration(seconds: 30),
}) async {
  final copy = buffer.getBytesCopy();
  final text = String.fromCharCodes(copy);
  final clipboardHash = sha256.convert(utf8.encode(text)).toString();
  
  try {
    await Clipboard.setData(ClipboardData(text: text));
    await nativeWipe(text);
    
    // Schedule system clipboard clear
    Future.delayed(clearAfter, () async {
      final current = await Clipboard.getData('text/plain');
      final currentText = current?.text;
      if (currentText != null &&
          sha256.convert(utf8.encode(currentText)).toString() == clipboardHash) {
        await Clipboard.setData(const ClipboardData(text: ''));
      }
    });
  } finally {
    copy.fillRange(0, copy.length, 0);
  }
}

/// Fallback for plain strings
Future<void> copyWithAutoClear(String text, {
  Duration clearAfter = const Duration(seconds: 30),
}) async {
  final clipboardHash = sha256.convert(utf8.encode(text)).toString();
  await Clipboard.setData(ClipboardData(text: text));
  await nativeWipe(text);
  Future.delayed(clearAfter, () async {
    final current = await Clipboard.getData('text/plain');
    final currentText = current?.text;
    if (currentText != null &&
        sha256.convert(utf8.encode(currentText)).toString() == clipboardHash) {
      await Clipboard.setData(const ClipboardData(text: ''));
    }
  });
}
