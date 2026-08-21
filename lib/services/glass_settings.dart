import 'package:flutter/foundation.dart';

import 'dock_theme_settings.dart';

/// Back-compat wrapper: liquid-glass effects are enabled only for that theme.
abstract final class GlassSettings {
  static final ValueNotifier<bool> enabled = _GlassEnabledNotifier();

  static Future<void> initialize() async {
    await DockThemeSettings.initialize();
  }

  static Future<void> setEnabled(bool value) async {
    await DockThemeSettings.setTheme(
      value ? DockTheme.liquidGlass : DockTheme.standard,
    );
  }
}

class _GlassEnabledNotifier extends ValueNotifier<bool> {
  _GlassEnabledNotifier()
      : super(DockThemeSettings.theme.value.usesLiquidGlass) {
    DockThemeSettings.theme.addListener(_sync);
  }

  void _sync() {
    final next = DockThemeSettings.theme.value.usesLiquidGlass;
    if (value != next) {
      value = next;
    }
  }
}
