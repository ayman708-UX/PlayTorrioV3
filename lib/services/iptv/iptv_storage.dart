import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../models/iptv/iptv_models.dart';

/// Port of `IptvStorage.kt` — persistence for IPTV settings and caches.
class IptvStorage {
  static const String _settingsKey = 'iptv_settings_v1';

  // ── Settings ───────────────────────────────────────────────────────────

  static Future<IptvSettings> loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_settingsKey);
    if (raw == null) return const IptvSettings();
    return IptvSettings.decode(raw);
  }

  static Future<void> saveSettings(IptvSettings settings) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_settingsKey, IptvSettings.encode(settings));
  }

  // ── Channel cache ──────────────────────────────────────────────────────
  // Keyed by source cache key (playlist URL or "xtream:{id}" / "stalker:{id}").
  // Stores {channels, timestamp} JSON.

  static Future<File> _cacheFile(String key) async {
    final dir = await getApplicationCacheDirectory();
    final safe = Uri.encodeComponent(key);
    return File('${dir.path}/iptv_ch_$safe.json');
  }

  static Future<Map<String, dynamic>?> loadChannelCache(String key) async {
    try {
      final file = await _cacheFile(key);
      if (!await file.exists()) return null;
      final raw = await file.readAsString();
      return jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  static Future<void> saveChannelCache(
    String key,
    List<IptvChannel> channels, {
    required DateTime timestamp,
  }) async {
    try {
      final file = await _cacheFile(key);
      await file.writeAsString(
        jsonEncode({
          'channels': channels.map((c) => c.toJson()).toList(),
          'timestamp': timestamp.millisecondsSinceEpoch,
        }),
      );
    } catch (_) {}
  }

  static Future<void> invalidateChannelCache(String key) async {
    try {
      final file = await _cacheFile(key);
      if (await file.exists()) await file.delete();
    } catch (_) {}
  }

  // ── EPG cache ──────────────────────────────────────────────────────────

  static Future<Map<String, dynamic>?> loadEpgCache() async {
    try {
      final dir = await getApplicationCacheDirectory();
      final file = File('${dir.path}/iptv_epg_cache.json');
      if (!await file.exists()) return null;
      return jsonDecode(await file.readAsString()) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  static Future<void> saveEpgCache(Map<String, dynamic> data) async {
    try {
      final dir = await getApplicationCacheDirectory();
      final file = File('${dir.path}/iptv_epg_cache.json');
      await file.writeAsString(jsonEncode(data));
    } catch (_) {}
  }

  // ── Uploaded EPG source content ────────────────────────────────────────

  static Future<String?> loadEpgSourceContent(String id) async {
    try {
      final dir = await getApplicationCacheDirectory();
      final file = File('${dir.path}/iptv_epg_src_${Uri.encodeComponent(id)}.xml');
      if (!await file.exists()) return null;
      return await file.readAsString();
    } catch (_) {
      return null;
    }
  }

  static Future<void> saveEpgSourceContent(String id, String content) async {
    try {
      final dir = await getApplicationCacheDirectory();
      final file =
          File('${dir.path}/iptv_epg_src_${Uri.encodeComponent(id)}.xml');
      await file.writeAsString(content);
    } catch (_) {}
  }

  static Future<void> deleteEpgSourceContent(String id) async {
    try {
      final dir = await getApplicationCacheDirectory();
      final file =
          File('${dir.path}/iptv_epg_src_${Uri.encodeComponent(id)}.xml');
      if (await file.exists()) await file.delete();
    } catch (_) {}
  }
}