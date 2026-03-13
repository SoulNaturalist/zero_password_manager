import 'package:flutter/material.dart';

enum AppTheme { dark, cyberpunk, glassmorphism }

abstract class BaseTheme {
  // Базовые цвета
  Color get background;
  Color get button;
  Color get input;
  Color get text;
  Color get accent;
  Color get secondary;
  Color get surface;
  Color get error;

  // Градиенты
  List<Color>? get backgroundGradient;
  List<Color>? get buttonGradient;
  List<Color>? get cardGradient;

  // Эффекты
  bool get hasGlassEffect;
  bool get hasNeonGlow;
  double get cardOpacity;
  double get blurRadius;
}

class DarkTheme extends BaseTheme {
  @override
  Color get background => const Color(0xFF1A142E);
  @override
  Color get button => const Color(0xFF5D52D2);
  @override
  Color get input => const Color(0xFF221937);
  @override
  Color get text => Colors.white;
  @override
  Color get accent => const Color(0xFF8B7ED8);
  @override
  Color get secondary => const Color(0xFF403A5C);
  @override
  Color get surface => const Color(0xFF2A1F3D);
  @override
  Color get error => const Color(0xFFE74C3C);

  @override
  List<Color>? get backgroundGradient => null;
  @override
  List<Color>? get buttonGradient => null;
  @override
  List<Color>? get cardGradient => null;

  @override
  bool get hasGlassEffect => false;
  @override
  bool get hasNeonGlow => false;
  @override
  double get cardOpacity => 1.0;
  @override
  double get blurRadius => 0.0;
}

class CyberpunkTheme extends BaseTheme {
  @override
  Color get background => const Color(0xFF0A0A0A);
  @override
  Color get button => const Color(0xFF00FFFF);
  @override
  Color get input => const Color(0xFF1A1A1A);
  @override
  Color get text => const Color(0xFF00FFFF);
  @override
  Color get accent => const Color(0xFFFF0080);
  @override
  Color get secondary => const Color(0xFF8000FF);
  @override
  Color get surface => const Color(0xFF151515);
  @override
  Color get error => const Color(0xFFFF0040);

  @override
  List<Color> get backgroundGradient => [
    const Color(0xFF0A0A0A),
    const Color(0xFF1A0A1A),
    const Color(0xFF0A1A1A),
  ];

  @override
  List<Color> get buttonGradient => [
    const Color(0xFF00FFFF),
    const Color(0xFF0080FF),
    const Color(0xFF8000FF),
  ];

  @override
  List<Color> get cardGradient => [
    const Color(0xFF1A1A1A),
    const Color(0xFF2A1A2A),
  ];

  @override
  bool get hasGlassEffect => false;
  @override
  bool get hasNeonGlow => true;
  @override
  double get cardOpacity => 0.9;
  @override
  double get blurRadius => 0.0;
}

class GlassmorphismTheme extends BaseTheme {
  @override
  Color get background => const Color(0xFF1E1E2E);
  @override
  Color get button => const Color(0xFF89B4FA);
  @override
  Color get input => const Color(0xFF313244);
  @override
  Color get text => const Color(0xFFCDD6F4);
  @override
  Color get accent => const Color(0xFFB4BEFE);
  @override
  Color get secondary => const Color(0xFF9399B2);
  @override
  Color get surface => const Color(0xFF181825);
  @override
  Color get error => const Color(0xFFF38BA8);

  @override
  List<Color> get backgroundGradient => [
    const Color(0xFF1E1E2E),
    const Color(0xFF2D2A45),
    const Color(0xFF3E3A5C),
  ];

  @override
  List<Color> get buttonGradient => [
    const Color(0xFF89B4FA),
    const Color(0xFFB4BEFE),
  ];

  @override
  List<Color> get cardGradient => [
    const Color(0x40313244),
    const Color(0x60181825),
  ];

  @override
  bool get hasGlassEffect => true;
  @override
  bool get hasNeonGlow => false;
  @override
  double get cardOpacity => 0.3;
  @override
  double get blurRadius => 20.0;
}

class ThemeManager {
  static AppTheme _currentTheme = AppTheme.dark;
  static BaseTheme _colors = DarkTheme();

  static AppTheme get currentTheme => _currentTheme;
  static BaseTheme get colors => _colors;

  static void setTheme(AppTheme theme) {
    _currentTheme = theme;
    switch (theme) {
      case AppTheme.dark:
        _colors = DarkTheme();
        break;
      case AppTheme.cyberpunk:
        _colors = CyberpunkTheme();
        break;
      case AppTheme.glassmorphism:
        _colors = GlassmorphismTheme();
        break;
    }
  }

  static String getThemeName(AppTheme theme) {
    switch (theme) {
      case AppTheme.dark:
        return 'Темная';
      case AppTheme.cyberpunk:
        return 'Cyberpunk';
      case AppTheme.glassmorphism:
        return 'Glassmorphism';
    }
  }
}

// Статический класс для обратной совместимости
class AppColors {
  static Color get background => ThemeManager.colors.background;
  static Color get button => ThemeManager.colors.button;
  static Color get input => ThemeManager.colors.input;
  static Color get text => ThemeManager.colors.text;
  static Color get accent => ThemeManager.colors.accent;
  static Color get secondary => ThemeManager.colors.secondary;
  static Color get surface => ThemeManager.colors.surface;
  static Color get error => ThemeManager.colors.error;
}
