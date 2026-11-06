import 'package:flutter/material.dart';

/// 取自用户录屏的基础配色；播放器的封面配色由播放页单独处理。
class VideoTheme {
  static const primary = Color(0xFF4C6CF4);
  static const background = Color(0xFFEFECF0);
  static const card = Color(0xFFFCF7F9);
  static const playing = Color(0xFFDEDBEA);

  static ThemeData get light => _theme(Brightness.light);
  static ThemeData get dark => _theme(Brightness.dark);

  static Color canvas(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
      ? const Color(0xFF17171C)
      : background;

  static Color surface(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
      ? const Color(0xFF25242C)
      : card;

  static Color secondaryText(BuildContext context) =>
      Theme.of(context).colorScheme.onSurface.withValues(alpha: .58);

  static ThemeData _theme(Brightness brightness) {
    final dark = brightness == Brightness.dark;
    final scheme =
        ColorScheme.fromSeed(
          seedColor: primary,
          brightness: brightness,
        ).copyWith(
          primary: primary,
          surface: dark ? const Color(0xFF25242C) : card,
          onSurface: dark ? const Color(0xFFF3F0F5) : const Color(0xFF202024),
        );
    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: dark ? const Color(0xFF17171C) : background,
      fontFamily: 'sans-serif',
      appBarTheme: AppBarTheme(
        backgroundColor: dark ? const Color(0xFF17171C) : background,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        titleTextStyle: TextStyle(
          color: scheme.onSurface,
          fontSize: 17,
          fontWeight: FontWeight.w700,
        ),
      ),
      dividerTheme: DividerThemeData(
        color: scheme.onSurface.withValues(alpha: .1),
        space: 1,
        thickness: .6,
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(color: primary),
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: primary,
        selectionColor: primary.withValues(alpha: .2),
        selectionHandleColor: primary,
      ),
    );
  }
}
