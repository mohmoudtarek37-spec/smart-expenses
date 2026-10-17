import 'package:flutter/material.dart';

/// Blue-on-navy visual identity from the approved Hesabaty reference.
/// Uses gradients and translucent surfaces without expensive backdrop blur.
abstract final class HesabatyTheme {
  static const navy = Color(0xFF071E38);
  static const navyCard = Color(0xFF133A5D);
  static const blueGlow = Color(0xFF85CFFF);
  static const ice = Color(0xFFD9ECFA);
  static const ink = Color(0xFFEAF6FF);

  static ThemeData create({required bool dark}) {
    final scheme = dark
        ? const ColorScheme.dark(
            primary: blueGlow,
            onPrimary: Color(0xFF082743),
            secondary: Color(0xFF64B4E9),
            onSecondary: Color(0xFF082743),
            surface: navyCard,
            onSurface: ink,
            error: Color(0xFFFF7893),
            onError: Color(0xFF350813),
          )
        : const ColorScheme.light(
            primary: Color(0xFF176496),
            onPrimary: Colors.white,
            secondary: Color(0xFF2C7DAD),
            onSecondary: Colors.white,
            surface: Color(0xFFF2F8FE),
            onSurface: Color(0xFF12334E),
            error: Color(0xFFBA334E),
            onError: Colors.white,
          );
    final border = BorderRadius.circular(17);
    final background = dark ? navy : ice;
    final surface = dark
        ? const Color(0xFF143B60)
        : const Color(0xFFE8F3FC);
    return ThemeData(
      useMaterial3: true,
      brightness: dark ? Brightness.dark : Brightness.light,
      scaffoldBackgroundColor: background,
      colorScheme: scheme,
      canvasColor: surface,
      dividerColor: dark
          ? const Color(0x5585AED1) : const Color(0xFFBCD5E9),
      iconTheme: IconThemeData(color: scheme.onSurface),
      appBarTheme: AppBarTheme(
        backgroundColor: background,
        foregroundColor: scheme.onSurface,
        centerTitle: true,
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: dark
            ? const Color(0xFF1A456C) : const Color(0xFFF6FBFF),
        contentPadding: const EdgeInsets.symmetric(
            horizontal: 14, vertical: 14),
        border: OutlineInputBorder(borderRadius: border),
        enabledBorder: OutlineInputBorder(
          borderRadius: border,
          borderSide: BorderSide(color: scheme.primary.withValues(alpha: 0.33)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: border,
          borderSide: BorderSide(color: scheme.primary, width: 1.5),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(style: FilledButton.styleFrom(
        backgroundColor: scheme.primary,
        foregroundColor: scheme.onPrimary,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        shape: RoundedRectangleBorder(borderRadius: border),
      )),
      outlinedButtonTheme: OutlinedButtonThemeData(style:
          OutlinedButton.styleFrom(
        foregroundColor: scheme.onSurface,
        side: BorderSide(color: scheme.primary.withValues(alpha: 0.48)),
        shape: RoundedRectangleBorder(borderRadius: border),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
      )),
      textButtonTheme: TextButtonThemeData(style: TextButton.styleFrom(
        foregroundColor: scheme.primary,
      )),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: scheme.primary,
        foregroundColor: scheme.onPrimary,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24)),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: dark
            ? const Color(0xFF295A80) : const Color(0xFF164468),
        contentTextStyle: const TextStyle(color: Colors.white),
      ),
    );
  }
}
