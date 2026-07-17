import 'package:flutter/material.dart';

class PanelTheme {
  final String name;
  final String description;
  final Color background;
  final Color surface;
  final Color primary;
  final Color secondary;

  const PanelTheme({
    required this.name,
    required this.description,
    required this.background,
    required this.surface,
    required this.primary,
    required this.secondary,
  });

  ThemeData toThemeData() {
    return ThemeData(
      brightness: Brightness.dark,
      useMaterial3: true,
      fontFamily: "SF Pro Display",
      splashFactory: InkSparkle.splashFactory,
      scaffoldBackgroundColor: background,
      cardColor: surface,
      colorScheme: ColorScheme.fromSeed(
        seedColor: primary,
        brightness: Brightness.dark,
        primary: primary,
        secondary: secondary,
        surface: surface,
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 84,
        backgroundColor: surface.withValues(alpha: 0.88),
        indicatorColor: primary.withValues(alpha: 0.18),
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => TextStyle(
            color: states.contains(WidgetState.selected)
                ? primary
                : Colors.white,
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(
            color: states.contains(WidgetState.selected)
                ? primary
                : const Color(0xFFE4E7EF),
            size: states.contains(WidgetState.selected) ? 30 : 28,
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surface.withValues(alpha: 0.78),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: primary.withValues(alpha: 0.7)),
        ),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: background,
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: false,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          textStyle: const TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
    );
  }
}

const panelThemes = [
  PanelTheme(
    name: "Vault Purple",
    description: "Dark, premium, Apple-inspired",
    background: Color(0xFF080C12),
    surface: Color(0xFF121821),
    primary: Color(0xFF8B4DFF),
    secondary: Color(0xFFFF7A1A),
  ),
  PanelTheme(
    name: "Graphite Copper",
    description: "Industrial dark with warm energy",
    background: Color(0xFF0D0F12),
    surface: Color(0xFF1A1D22),
    primary: Color(0xFFFF7A1A),
    secondary: Color(0xFF8B4DFF),
  ),
  PanelTheme(
    name: "Emerald Grid",
    description: "Maintenance, testing, completed work",
    background: Color(0xFF07100D),
    surface: Color(0xFF111C18),
    primary: Color(0xFF35E177),
    secondary: Color(0xFF5E78FF),
  ),
  PanelTheme(
    name: "Ocean Control",
    description: "Clean, technical, documentation-heavy",
    background: Color(0xFF071018),
    surface: Color(0xFF101A24),
    primary: Color(0xFF18D4E8),
    secondary: Color(0xFFFFC43D),
  ),
];

final panelThemeController = ValueNotifier<PanelTheme>(panelThemes.first);
