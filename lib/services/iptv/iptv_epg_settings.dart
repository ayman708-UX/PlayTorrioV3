import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// XMLTV EPG URL and home-screen TV guide visibility.
class IptvEpgSettings {
  static const _urlKey = 'playtorrio_iptv_epg_url';
  static const _showHomeGuideKey = 'playtorrio_iptv_show_home_guide';

  static final ValueNotifier<bool> showHomeTvGuide = ValueNotifier(false);

  static Future<void> initialize() async {
    final prefs = await SharedPreferences.getInstance();
    showHomeTvGuide.value = prefs.getBool(_showHomeGuideKey) ?? false;
  }

  static Future<String?> loadUrl() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_urlKey);
  }

  static Future<void> saveUrl(String? url) async {
    final prefs = await SharedPreferences.getInstance();
    if (url == null || url.trim().isEmpty) {
      await prefs.remove(_urlKey);
    } else {
      await prefs.setString(_urlKey, url.trim());
    }
  }

  static Future<void> setShowHomeTvGuide(bool value) async {
    if (showHomeTvGuide.value == value) return;
    showHomeTvGuide.value = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_showHomeGuideKey, value);
  }
}
