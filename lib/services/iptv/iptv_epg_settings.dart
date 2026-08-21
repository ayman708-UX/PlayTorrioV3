import 'package:shared_preferences/shared_preferences.dart';

/// XMLTV EPG URL for M3U channel guides.
class IptvEpgSettings {
  static const _key = 'playtorrio_iptv_epg_url';

  static Future<String?> loadUrl() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_key);
  }

  static Future<void> saveUrl(String? url) async {
    final prefs = await SharedPreferences.getInstance();
    if (url == null || url.trim().isEmpty) {
      await prefs.remove(_key);
    } else {
      await prefs.setString(_key, url.trim());
    }
  }
}
