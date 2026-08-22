import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Visual style for the bottom dock and related menu chrome.
enum DockTheme {
  standard('Standard', 'Clean frosted panels'),
  liquidGlass('Liquid Glass', 'Refraction, jelly, and lens effects'),
  carbonFiber('Carbon Fiber', 'Dark woven texture with metallic trim'),
  retro90s('90s Retro', 'Neon gradients and chunky arcade styling');

  const DockTheme(this.label, this.description);
  final String label;
  final String description;

  bool get usesLiquidGlass => this == DockTheme.liquidGlass;
}

/// Persists and broadcasts the selected menu theme.
abstract final class DockThemeSettings {
  static const _preferenceKey = 'menu_theme_v1';
  static const _legacyGlassKey = 'full_liquid_glass_enabled';

  static final ValueNotifier<DockTheme> theme =
      ValueNotifier<DockTheme>(DockTheme.standard);

  static Future<void> initialize() async {
    final preferences = await SharedPreferences.getInstance();
    final stored = preferences.getString(_preferenceKey);

    if (stored != null) {
      theme.value = DockTheme.values.firstWhere(
        (t) => t.name == stored,
        orElse: () => DockTheme.standard,
      );
      return;
    }

    // Migrate legacy glass toggle.
    final legacyGlass = preferences.getBool(_legacyGlassKey) ?? false;
    theme.value =
        legacyGlass ? DockTheme.liquidGlass : DockTheme.standard;
  }

  static Future<void> setTheme(DockTheme value) async {
    if (theme.value == value) return;
    theme.value = value;
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_preferenceKey, value.name);
    await preferences.setBool(_legacyGlassKey, value.usesLiquidGlass);
  }
}
