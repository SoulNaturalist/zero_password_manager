import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LanguageService extends ChangeNotifier {
  LanguageService._();

  static final LanguageService instance = LanguageService._();
  static const _storageKey = 'app_language_code';

  Locale _locale = _deviceLocale();

  Locale get locale => _locale;
  String get languageCode => _locale.languageCode;
  bool get isRussian => languageCode == 'ru';

  static Locale _deviceLocale() {
    final deviceLocale = PlatformDispatcher.instance.locale;
    final code = deviceLocale.languageCode.toLowerCase().startsWith('ru')
        ? 'ru'
        : 'en';
    return Locale(code);
  }

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    final String? savedCode = prefs.getString(_storageKey);
    if (savedCode == 'ru' || savedCode == 'en') {
      _locale = Locale(savedCode);
    } else {
      _locale = _deviceLocale();
    }
  }

  Future<void> setLanguageCode(String code) async {
    if (code != 'ru' && code != 'en') return;
    if (_locale.languageCode == code) return;

    _locale = Locale(code);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_storageKey, code);
    notifyListeners();
  }
}
