import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// User-configurable player behavior, persisted across sessions.
///
/// Currently controls the auto-next episode dialog:
/// - `autoNextEnabled`: whether the "Up Next" countdown dialog appears at the
///   end of an episode. When disabled, playback simply stops at the end.
abstract final class PlayerSettings {
  static const _autoNextKey = 'player_auto_next_enabled';

  static final ValueNotifier<bool> autoNextEnabled = ValueNotifier<bool>(true);

  static Future<void> initialize() async {
    final preferences = await SharedPreferences.getInstance();
    autoNextEnabled.value = preferences.getBool(_autoNextKey) ?? true;
  }

  static Future<void> setAutoNextEnabled(bool value) async {
    if (autoNextEnabled.value == value) return;
    autoNextEnabled.value = value;
    final preferences = await SharedPreferences.getInstance();
    await preferences.setBool(_autoNextKey, value);
  }
}