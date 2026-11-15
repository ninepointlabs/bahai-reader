import 'package:flutter/material.dart';

/// Light and dark themes. The reading text uses the platform's serif face (fontconfig "serif" on Linux), so nothing
/// is fetched at runtime.
const readingFonts = ['Noto Serif', 'Source Serif 4', 'Georgia', 'DejaVu Serif', 'serif'];

ThemeData buildTheme(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  final scheme = ColorScheme.fromSeed(
    seedColor: const Color(0xFF8A6D3B),
    brightness: brightness,
    surface: dark ? const Color(0xFF1C1B19) : const Color(0xFFFBF8F2),
  );
  return ThemeData(
    colorScheme: scheme,
    useMaterial3: true,
    scaffoldBackgroundColor: scheme.surface,
    appBarTheme: AppBarTheme(backgroundColor: scheme.surface, scrolledUnderElevation: 1),
    cardTheme: CardThemeData(
      elevation: 0,
      color: dark ? const Color(0xFF262421) : Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: scheme.outlineVariant)),
    ),
  );
}

/// Highlight backgrounds, readable under text in both themes.
Color highlightColor(String name, Brightness brightness) {
  final dark = brightness == Brightness.dark;
  return switch (name) {
    'green' => dark ? const Color(0x664CAF50) : const Color(0x8099E2A0),
    'blue' => dark ? const Color(0x664A90E2) : const Color(0x80A6CBF5),
    'magenta' => dark ? const Color(0x66D04FC0) : const Color(0x80F2A7E6),
    _ => dark ? const Color(0x66E0B526) : const Color(0x99FFE873),
  };
}

/// Solid swatch for buttons and list markers.
Color swatchColor(String name) => switch (name) {
      'green' => const Color(0xFF4CAF50),
      'blue' => const Color(0xFF4A90E2),
      'magenta' => const Color(0xFFC04FB5),
      _ => const Color(0xFFE0B526),
    };
