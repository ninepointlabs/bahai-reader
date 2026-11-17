import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';

/// The reading text's faces, as the GTK app picks them (Noto Serif, else DejaVu Serif). Nothing is fetched at runtime.
const readingFonts = ['Noto Serif', 'DejaVu Serif', 'Source Serif 4', 'Georgia', 'serif'];

/// The reading faces with a chosen font first (Aa → Reading font), falling back to the defaults for missing letters.
List<String> readingFontsFor(String? font) => font == null || font.isEmpty ? readingFonts : [font, ...readingFonts];

/// The interface font: the desktop's own where it is one of these (GNOME's and Omarchy's defaults), else sans-serif.
const interfaceFonts = ['Adwaita Sans', 'Inter', 'Cantarell', 'Noto Sans', 'sans-serif'];

/// The four colours the GTK app's look is built from (GTK `theme.py`), and what it derives from them.
class Palette {
  const Palette({
    required this.background,
    required this.foreground,
    required this.accent,
    required this.selection,
    this.sidebarHint,
    this.highlightBase = const {},
  });

  final Color background;
  final Color foreground;
  final Color accent;
  final Color selection;

  /// Omarchy's own darker background, used for the sidebar when it keeps the text readable.
  final Color? sidebarHint;

  /// Omarchy's yellow/green/blue/magenta, used for highlights when the theme has them.
  final Map<String, Color> highlightBase;

  static const dark = Palette(
      background: Color(0xFF161B19), foreground: Color(0xFFE6E1D3), accent: Color(0xFFC9AB70), selection: Color(0xFF303B35));
  static const light = Palette(
      background: Color(0xFFFAFAF7), foreground: Color(0xFF252B27), accent: Color(0xFF45654C), selection: Color(0xFFE2E9DF));
  static const sepia = Palette(
      background: Color(0xFFF2E9D7), foreground: Color(0xFF463C2F), accent: Color(0xFF7E5D28), selection: Color(0xFFE2D4B9));

  bool get isDark => luminance(background) < 0.4;
  Brightness get brightness => isDark ? Brightness.dark : Brightness.light;

  /// libadwaita's sidebar: Omarchy's darker background, else a step toward the foreground.
  Color get sidebar {
    final hint = sidebarHint;
    if (hint != null && contrast(hint, foreground) >= 7) return hint;
    return mix(background, foreground, isDark ? 0.06 : 0.035);
  }

  Color get card => mix(background, foreground, isDark ? 0.05 : 0.02);

  /// What floats over the page (popovers, dialogs): a step lighter than the page.
  Color get raised {
    if (luminance(background) < 0.4) return mix(background, foreground, 0.1);
    return background.toARGB32() != 0xFFFFFFFF ? Colors.white : mix(background, foreground, 0.04);
  }

  /// The accent as text on the page; some themes' accents are too faint for that.
  Color get accentText => readable(background, [accent, foreground]);
  Color get onAccent => readable(accent, [background, foreground, Colors.white, Colors.black]);
  Color get dim => foreground.withValues(alpha: 0.7);

  /// A highlight on this background, as the GTK app's translucent one looks over the page. Flutter paints a span's
  /// background per run of glyphs and the runs overlap a little, so a translucent colour would show darker seams between
  /// words; the colour is blended with the page here instead.
  Color highlight(String name) => Color.alphaBlend(swatch(name).withValues(alpha: isDark ? 0.40 : 0.32), background);
  Color swatch(String name) => highlightBase[name] ?? highlightDefaults[name] ?? highlightDefaults['yellow']!;

  static const highlightDefaults = {
    'yellow': Color(0xFFD0A215),
    'green': Color(0xFF879A39),
    'blue': Color(0xFF3F7FC4),
    'magenta': Color(0xFFCE5D97),
  };

  @override
  bool operator ==(Object other) =>
      other is Palette &&
      other.background == background &&
      other.foreground == foreground &&
      other.accent == accent &&
      other.selection == selection &&
      other.sidebarHint == sidebarHint &&
      _sameMap(other.highlightBase, highlightBase);

  @override
  int get hashCode => Object.hash(background, foreground, accent, selection, sidebarHint, highlightBase.length);
}

bool _sameMap(Map<String, Color> a, Map<String, Color> b) => a.length == b.length && a.entries.every((e) => b[e.key] == e.value);

double luminance(Color c) {
  double ch(double v) => v <= 0.04045 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
  return 0.2126 * ch(c.r) + 0.7152 * ch(c.g) + 0.0722 * ch(c.b);
}

/// WCAG 2 contrast ratio.
double contrast(Color a, Color b) {
  final la = luminance(a), lb = luminance(b);
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}

/// The first candidate that meets [minimum] on [background], else the strongest one (GTK `readable()`).
Color readable(Color background, List<Color> candidates, {double minimum = 4.5}) {
  for (final c in candidates) {
    if (contrast(c, background) >= minimum) return c;
  }
  return candidates.reduce((a, b) => contrast(a, background) >= contrast(b, background) ? a : b);
}

/// [a] moved [t] of the way toward [b].
Color mix(Color a, Color b, double t) => Color.lerp(a, b, t)!.withValues(alpha: 1);

/// The palette of the live Omarchy theme, read from its `colors.toml`, or null when there is none (not Omarchy, or
/// not Linux). Only local files are read.
(Palette, String)? readOmarchyPalette({Map<String, String>? environment, String? home}) {
  if (!Platform.isLinux) return null;
  final env = environment ?? Platform.environment;
  final h = home ?? env['HOME'] ?? '';
  final states = [env['HOST_XDG_STATE_HOME'], env['XDG_STATE_HOME'], '$h/.local/state'].whereType<String>();
  final paths = [for (final s in states) '$s/omarchy/current/theme/colors.toml', '$h/.config/omarchy/current/theme/colors.toml'];
  for (final path in paths) {
    try {
      final source = File(path).readAsStringSync();
      final p = parseOmarchyColors(source);
      if (p != null) return (p, source);
    } on FileSystemException {
      continue;
    }
  }
  return null;
}

/// A palette from an Omarchy `colors.toml`: `key = "#rrggbb"` lines. Missing keys keep the GTK app's dark defaults.
Palette? parseOmarchyColors(String source) {
  final values = <String, Color>{};
  final line = RegExp(r'''^\s*([A-Za-z_]+)\s*=\s*["']#([0-9a-fA-F]{6})["']''', multiLine: true);
  for (final m in line.allMatches(source)) {
    values[m.group(1)!] = Color(0xFF000000 | int.parse(m.group(2)!, radix: 16));
  }
  if (values.isEmpty) return null;
  const base = Palette.dark;
  return Palette(
    background: values['background'] ?? base.background,
    foreground: values['foreground'] ?? base.foreground,
    accent: values['accent'] ?? base.accent,
    selection: values['selection'] ?? base.selection,
    sidebarHint: values['dark_background'],
    highlightBase: {for (final n in Palette.highlightDefaults.keys) if (values[n] != null) n: values[n]!},
  );
}

/// The palette as a ThemeData, styled like the GTK app's libadwaita window: flat, soft controls with small radii,
/// one accent-coloured primary button, hairlines in the selection colour.
/// [monospace]: Aa → Interface font → Monospace (the fontconfig monospace family, Omarchy's configured font).
ThemeData buildTheme(Palette p, {bool monospace = false}) {
  final fg = p.foreground, bg = p.background;
  final scheme = ColorScheme(
    brightness: p.brightness,
    primary: p.accent,
    onPrimary: p.onAccent,
    secondary: p.accent,
    onSecondary: p.onAccent,
    secondaryContainer: p.selection,
    onSecondaryContainer: fg,
    tertiaryContainer: p.selection,
    onTertiaryContainer: fg,
    error: const Color(0xFFE0605A),
    onError: Colors.white,
    surface: bg,
    onSurface: fg,
    onSurfaceVariant: p.dim,
    surfaceContainerLowest: bg,
    surfaceContainerLow: p.card,
    surfaceContainer: p.card,
    surfaceContainerHigh: p.raised,
    surfaceContainerHighest: p.raised,
    outline: p.selection,
    outlineVariant: p.selection,
    inverseSurface: fg,
    onInverseSurface: bg,
  );
  final soft = fg.withValues(alpha: 0.07);
  final radius = BorderRadius.circular(6);
  // Styles given in full (buttons, tooltips) replace the theme's text style, so they name the interface font too;
  // otherwise they fall back to the system default font and ignore Aa → Interface font.
  final face = TextStyle(
    fontFamily: monospace ? 'monospace' : interfaceFonts.first,
    fontFamilyFallback: monospace ? interfaceFonts : interfaceFonts.sublist(1),
  );
  final label = face.copyWith(fontWeight: FontWeight.w700, fontSize: 14.5);
  final base = ThemeData(
    colorScheme: scheme,
    useMaterial3: true,
    brightness: p.brightness,
    fontFamily: monospace ? 'monospace' : interfaceFonts.first,
    fontFamilyFallback: monospace ? interfaceFonts : interfaceFonts.sublist(1),
  );
  return base.copyWith(
    scaffoldBackgroundColor: bg,
    canvasColor: bg,
    dividerColor: p.selection,
    dividerTheme: DividerThemeData(color: p.selection, thickness: 1, space: 1),
    hoverColor: fg.withValues(alpha: 0.08),
    focusColor: fg.withValues(alpha: 0.12),
    splashFactory: NoSplash.splashFactory,
    highlightColor: fg.withValues(alpha: 0.06),
    textSelectionTheme: TextSelectionThemeData(selectionColor: p.selection.withValues(alpha: 0.9), cursorColor: p.accent),
    textTheme: base.textTheme.apply(bodyColor: fg, displayColor: fg),
    appBarTheme: AppBarTheme(
      backgroundColor: bg,
      foregroundColor: fg,
      surfaceTintColor: Colors.transparent,
      scrolledUnderElevation: 0,
      shape: Border(bottom: BorderSide(color: p.selection)),
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      color: p.card,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: fg.withValues(alpha: 0.1))),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: p.raised,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10), side: BorderSide(color: fg.withValues(alpha: 0.12))),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: bg,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: BorderSide(color: fg.withValues(alpha: 0.12))),
    ),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(color: p.raised, borderRadius: radius, border: Border.all(color: fg.withValues(alpha: 0.12))),
      textStyle: face.copyWith(color: fg, fontSize: 13),
      waitDuration: const Duration(milliseconds: 500),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: p.accent,
        foregroundColor: p.onAccent,
        shape: RoundedRectangleBorder(borderRadius: radius),
        textStyle: label,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        backgroundColor: soft,
        foregroundColor: fg,
        side: BorderSide.none,
        shape: RoundedRectangleBorder(borderRadius: radius),
        textStyle: label,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: fg,
        shape: RoundedRectangleBorder(borderRadius: radius),
        textStyle: label,
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(foregroundColor: fg, shape: RoundedRectangleBorder(borderRadius: radius)),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: soft,
      isDense: true,
      hintStyle: TextStyle(color: p.dim),
      border: OutlineInputBorder(borderRadius: radius, borderSide: BorderSide.none),
      enabledBorder: OutlineInputBorder(borderRadius: radius, borderSide: BorderSide.none),
      focusedBorder: OutlineInputBorder(borderRadius: radius, borderSide: BorderSide(color: p.accent, width: 2)),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(color: p.accent, linearTrackColor: fg.withValues(alpha: 0.15)),
    sliderTheme: SliderThemeData(activeTrackColor: p.accent, thumbColor: p.accent, inactiveTrackColor: fg.withValues(alpha: 0.15)),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: p.raised,
      contentTextStyle: TextStyle(color: fg),
      behavior: SnackBarBehavior.floating,
      width: 360,
      shape: const StadiumBorder(),
    ),
    extensions: [ReaderColors(p)],
  );
}

/// The palette, reachable from any widget: `ReaderColors.of(context)`.
class ReaderColors extends ThemeExtension<ReaderColors> {
  const ReaderColors(this.palette);
  final Palette palette;

  static Palette of(BuildContext context) =>
      Theme.of(context).extension<ReaderColors>()?.palette ??
      (Theme.of(context).brightness == Brightness.dark ? Palette.dark : Palette.light);

  @override
  ReaderColors copyWith({Palette? palette}) => ReaderColors(palette ?? this.palette);

  @override
  ReaderColors lerp(ReaderColors? other, double t) => t < 0.5 || other == null ? this : other;
}
