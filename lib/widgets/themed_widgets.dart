import 'dart:ui';
import 'package:flutter/material.dart';
import '../theme/colors.dart';

class ThemedContainer extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final double? width;
  final double? height;
  final BorderRadius? borderRadius;

  const ThemedContainer({
    Key? key,
    required this.child,
    this.padding,
    this.margin,
    this.width,
    this.height,
    this.borderRadius,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final theme = ThemeManager.colors;
    final borderRad = borderRadius ?? BorderRadius.circular(12);

    if (theme.hasGlassEffect) {
      return Container(
        width: width,
        height: height,
        margin: margin,
        child: ClipRRect(
          borderRadius: borderRad,
          child: BackdropFilter(
            filter: ImageFilter.blur(
              sigmaX: theme.blurRadius,
              sigmaY: theme.blurRadius,
            ),
            child: Container(
              padding: padding,
              decoration: BoxDecoration(
                gradient:
                    theme.cardGradient != null
                        ? LinearGradient(
                          colors: theme.cardGradient!,
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        )
                        : null,
                color:
                    theme.cardGradient == null
                        ? theme.input.withOpacity(theme.cardOpacity)
                        : null,
                borderRadius: borderRad,
                border: Border.all(
                  color: theme.accent.withOpacity(0.2),
                  width: 1,
                ),
                boxShadow: [
                  BoxShadow(
                    color: theme.accent.withOpacity(0.1),
                    blurRadius: 20,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: child,
            ),
          ),
        ),
      );
    }

    return Container(
      width: width,
      height: height,
      margin: margin,
      padding: padding,
      decoration: BoxDecoration(
        gradient:
            theme.cardGradient != null
                ? LinearGradient(
                  colors: theme.cardGradient!,
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                )
                : null,
        color: theme.cardGradient == null ? theme.input : null,
        borderRadius: borderRad,
        border:
            theme.hasNeonGlow
                ? Border.all(color: theme.accent.withOpacity(0.5), width: 1)
                : null,
        boxShadow:
            theme.hasNeonGlow
                ? [
                  BoxShadow(
                    color: theme.accent.withOpacity(0.3),
                    blurRadius: 10,
                    spreadRadius: 0,
                  ),
                  BoxShadow(
                    color: theme.button.withOpacity(0.2),
                    blurRadius: 20,
                    spreadRadius: 0,
                  ),
                ]
                : [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 8,
                    offset: const Offset(0, 4),
                  ),
                ],
      ),
      child: child,
    );
  }
}

class ThemedButton extends StatelessWidget {
  final Widget child;
  final VoidCallback? onPressed;
  final EdgeInsetsGeometry? padding;
  final double? width;
  final double? height;

  const ThemedButton({
    Key? key,
    required this.child,
    this.onPressed,
    this.padding,
    this.width,
    this.height,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final theme = ThemeManager.colors;

    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        gradient:
            theme.buttonGradient != null
                ? LinearGradient(
                  colors: theme.buttonGradient!,
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                )
                : null,
        color: theme.buttonGradient == null ? theme.button : null,
        borderRadius: BorderRadius.circular(12),
        boxShadow:
            theme.hasNeonGlow
                ? [
                  BoxShadow(
                    color: theme.button.withOpacity(0.4),
                    blurRadius: 15,
                    spreadRadius: 0,
                  ),
                  BoxShadow(
                    color: theme.accent.withOpacity(0.3),
                    blurRadius: 25,
                    spreadRadius: 0,
                  ),
                ]
                : [
                  BoxShadow(
                    color: theme.button.withOpacity(0.3),
                    blurRadius: 8,
                    offset: const Offset(0, 4),
                  ),
                ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding:
                padding ??
                const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
            child: child,
          ),
        ),
      ),
    );
  }
}

class ThemedBackground extends StatelessWidget {
  final Widget child;

  const ThemedBackground({Key? key, required this.child}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final theme = ThemeManager.colors;

    // Определяем фоновое изображение в зависимости от темы
    String? backgroundImage;
    switch (ThemeManager.currentTheme) {
      case AppTheme.cyberpunk:
        backgroundImage = 'assets/images/backgrounds/cyberpunk_bg.png';
        break;
      case AppTheme.glassmorphism:
        backgroundImage = 'assets/images/backgrounds/glassmorphism_bg.jpg';
        break;
      case AppTheme.dark:
      default:
        backgroundImage = null;
        break;
    }

    if (backgroundImage != null) {
      return Stack(
        fit: StackFit.expand,
        children: [
          // Фоновое изображение (повернуто на 180 градусов, так как ассеты перевернуты)
          RotatedBox(
            quarterTurns: 2,
            child: Image.asset(
              backgroundImage,
              fit: BoxFit.cover,
              colorFilter:
                  theme.backgroundGradient != null
                      ? ColorFilter.mode(
                        theme.background.withOpacity(0.3),
                        BlendMode.overlay,
                      )
                      : null,
            ),
          ),
          // Градиентный оверлей
          if (theme.backgroundGradient != null)
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors:
                      theme.backgroundGradient!
                          .map((c) => c.withOpacity(0.7))
                          .toList(),
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  stops: const [0.0, 0.5, 1.0],
                ),
              ),
            ),
          // Основной контент
          child,
        ],
      );
    }

    if (theme.backgroundGradient != null) {
      return Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: theme.backgroundGradient!,
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            stops: const [0.0, 0.5, 1.0],
          ),
        ),
        child: child,
      );
    }

    return Container(color: theme.background, child: child);
  }
}

class NeonText extends StatelessWidget {
  final String text;
  final TextStyle? style;
  final bool enableGlow;

  const NeonText({
    Key? key,
    required this.text,
    this.style,
    this.enableGlow = true,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final theme = ThemeManager.colors;
    final textStyle = style ?? TextStyle(color: theme.text);

    if (theme.hasNeonGlow && enableGlow) {
      return Stack(
        children: [
          // Внешнее свечение
          Text(
            text,
            style: textStyle.copyWith(
              foreground:
                  Paint()
                    ..style = PaintingStyle.stroke
                    ..strokeWidth = 3
                    ..color = theme.accent.withOpacity(0.5),
            ),
          ),
          // Внутреннее свечение
          Text(
            text,
            style: textStyle.copyWith(
              foreground:
                  Paint()
                    ..style = PaintingStyle.stroke
                    ..strokeWidth = 1
                    ..color = theme.button.withOpacity(0.8),
            ),
          ),
          // Основной текст
          Text(text, style: textStyle),
        ],
      );
    }

    return Text(text, style: textStyle);
  }
}

class ThemedTextField extends StatelessWidget {
  final TextEditingController? controller;
  final String? hintText;
  final bool obscureText;
  final Widget? prefixIcon;
  final Widget? suffixIcon;
  final int maxLines;
  final bool enabled;
  final TextInputType? keyboardType;

  const ThemedTextField({
    Key? key,
    this.controller,
    this.hintText,
    this.obscureText = false,
    this.prefixIcon,
    this.suffixIcon,
    this.maxLines = 1,
    this.enabled = true,
    this.keyboardType,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final theme = ThemeManager.colors;

    if (theme.hasGlassEffect) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: Colors.white.withOpacity(0.2),
                width: 1,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 10,
                  offset: const Offset(0, 5),
                ),
              ],
            ),
            child: TextField(
              controller: controller,
              obscureText: obscureText,
              maxLines: maxLines,
              enabled: enabled,
              keyboardType: keyboardType,
              style: TextStyle(color: theme.text, fontSize: 16),
              decoration: InputDecoration(
                hintText: hintText,
                hintStyle: TextStyle(color: theme.text.withOpacity(0.6)),
                prefixIcon: prefixIcon,
                suffixIcon: suffixIcon,
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 16,
                ),
              ),
            ),
          ),
        ),
      );
    }

    return TextField(
      controller: controller,
      obscureText: obscureText,
      maxLines: maxLines,
      enabled: enabled,
      keyboardType: keyboardType,
      style: TextStyle(color: theme.text),
      decoration: InputDecoration(
        hintText: hintText,
        hintStyle: TextStyle(color: theme.text.withOpacity(0.6)),
        prefixIcon: prefixIcon,
        suffixIcon: suffixIcon,
        filled: true,
        fillColor: theme.input,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide:
              theme.hasNeonGlow
                  ? BorderSide(color: theme.accent.withOpacity(0.3))
                  : BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: theme.button),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 16,
        ),
      ),
    );
  }
}

class ThemedElevatedButton extends StatelessWidget {
  final Widget child;
  final VoidCallback? onPressed;
  final Size? minimumSize;

  const ThemedElevatedButton({
    Key? key,
    required this.child,
    this.onPressed,
    this.minimumSize,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final theme = ThemeManager.colors;

    if (theme.hasGlassEffect) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Container(
            width: minimumSize?.width ?? double.infinity,
            height: minimumSize?.height ?? 50,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  theme.button.withOpacity(0.8),
                  theme.button.withOpacity(0.6),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: Colors.white.withOpacity(0.3),
                width: 1,
              ),
              boxShadow: [
                BoxShadow(
                  color: theme.button.withOpacity(0.3),
                  blurRadius: 15,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: onPressed,
                borderRadius: BorderRadius.circular(12),
                child: Center(
                  child: DefaultTextStyle(
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                    child: child,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }

    return ElevatedButton(
      onPressed: onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: theme.button,
        foregroundColor: Colors.white,
        minimumSize: minimumSize,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        elevation: theme.hasNeonGlow ? 8 : 2,
        shadowColor: theme.hasNeonGlow ? theme.button.withOpacity(0.5) : null,
      ),
      child: child,
    );
  }
}
