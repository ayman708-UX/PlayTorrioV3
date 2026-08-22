import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:playtorrio/services/dock_theme_settings.dart';
import 'package:playtorrio/services/glass_settings.dart';

void main() {
  group('DockThemeSettings', () {
    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      await DockThemeSettings.initialize();
    });

    test('defaults to standard theme', () {
      expect(DockThemeSettings.theme.value, DockTheme.standard);
    });

    test('persists selected theme', () async {
      await DockThemeSettings.setTheme(DockTheme.carbonFiber);
      expect(DockThemeSettings.theme.value, DockTheme.carbonFiber);

      await DockThemeSettings.initialize();
      expect(DockThemeSettings.theme.value, DockTheme.carbonFiber);
    });

    test('glass enabled only for liquid glass theme', () async {
      await GlassSettings.initialize();
      expect(GlassSettings.enabled.value, false);

      await DockThemeSettings.setTheme(DockTheme.liquidGlass);
      expect(GlassSettings.enabled.value, true);

      await DockThemeSettings.setTheme(DockTheme.retro90s);
      expect(GlassSettings.enabled.value, false);
    });
  });
}
