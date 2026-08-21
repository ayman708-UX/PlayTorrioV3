// Persistence + network fetch for M3U playlists.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'm3u_models.dart';
import 'm3u_parser.dart';

class M3uStore {
  static const _key = 'pt_iptv_m3u_playlists_v1';

  static Future<List<M3uPlaylist>> loadAll() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) return [];
    try {
      final arr = json.decode(raw) as List;
      return arr
          .map((e) => M3uPlaylist.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e) {
      debugPrint('M3uStore.loadAll failed: $e');
      return [];
    }
  }

  static Future<void> saveAll(List<M3uPlaylist> list) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _key,
      json.encode(list.map((p) => p.toJson()).toList()),
    );
  }

  static String newId() {
    final ts = DateTime.now().millisecondsSinceEpoch;
    final r = Random.secure().nextInt(1 << 32).toRadixString(16);
    return '${ts.toRadixString(16)}_$r';
  }
}

/// Fetches the body of a URL with a generous timeout. Mirrors the User-Agent
/// the rest of the IPTV stack uses so Xtream-style hosts don't 403 us.
class M3uFetcher {
  static const _ua = 'VLC/3.0.20 LibVLC/3.0.20';

  static Future<String> fetch(String url) async {
    final uri = Uri.parse(url);
    final res = await http
        .get(uri, headers: const {'User-Agent': _ua})
        .timeout(const Duration(seconds: 25));
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw HttpException(
          'HTTP ${res.statusCode} while fetching playlist',
          uri: uri);
    }
    final body = res.body;
    if (body.trim().isEmpty) {
      throw const FormatException('Empty response body');
    }
    return body;
  }

  /// Convenience: fetch + parse + return channel list.
  static Future<List<M3uChannel>> fetchAndParse(String url) async {
    final body = await fetch(url);
    return M3uParser.parse(body);
  }
}
