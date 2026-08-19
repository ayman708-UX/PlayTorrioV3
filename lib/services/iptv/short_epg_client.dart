import 'dart:async';
import 'dart:convert';

import '../../models/iptv/iptv_models.dart';
import 'iptv_http.dart';

/// Port of `ShortEpgClient.kt` + `ShortEpgCache.kt`.
///
/// Fetches a short EPG window for one Xtream channel via
/// `player_api.php?action=get_short_epg`, with a small TTL + single-flight cache.
class ShortEpgClient {
  static String _decodeBase64(String raw) {
    final u = raw.replaceAll(RegExp('[^A-Za-z0-9+/=]'), '');
    if (u.isEmpty || u.length % 4 == 1) return raw;
    final padded = u + ('=' * ((4 - u.length % 4) % 4));
    try {
      return utf8.decode(base64Decode(padded), allowMalformed: true);
    } catch (_) {
      return raw;
    }
  }

  static String? _decodeField(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    final direct = raw.trim();
    if (direct.length < 40 &&
        !direct.contains('+') &&
        !direct.contains('/') &&
        !direct.contains('=')) {
      return direct;
    }
    return _decodeBase64(direct);
  }

  static DateTime? _parseTimestamp(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    final trimmed = raw.trim();
    final digitsOnly = int.tryParse(trimmed);
    if (digitsOnly != null) {
      final millis = digitsOnly < 1000000000000 ? digitsOnly * 1000 : digitsOnly;
      return DateTime.fromMillisecondsSinceEpoch(millis, isUtc: true).toLocal();
    }
    final m = RegExp(
      r'(\d{4})-(\d{2})-(\d{2})[ T](\d{2}):(\d{2})(?::(\d{2}))?',
    ).firstMatch(trimmed);
    if (m == null) return null;
    final year = int.tryParse(m.group(1)!) ?? 0;
    final month = int.tryParse(m.group(2)!) ?? 0;
    final day = int.tryParse(m.group(3)!) ?? 0;
    final hour = int.tryParse(m.group(4)!) ?? 0;
    final minute = int.tryParse(m.group(5)!) ?? 0;
    final second = int.tryParse(m.group(6) ?? '0') ?? 0;
    return DateTime(year, month, day, hour, minute, second);
  }

  static bool _isGarbage(DateTime t) {
    final now = DateTime.now();
    return t.isBefore(now.subtract(const Duration(days: 1))) ||
        t.isAfter(now.add(const Duration(days: 90)));
  }

  static Future<List<EpgProgram>> fetchShortEpg(
    XtreamAccount account,
    IptvChannel channel, {
    int limit = 8,
  }) async {
    final server = account.server.replaceAll(RegExp(r'/+$'), '');
    final url =
        '$server/player_api.php?username=${account.username}&password=${account.password}'
        '&action=get_short_epg&stream_id=${channel.id}&limit=$limit';
    String body;
    try {
      body = await IptvHttp.getTextVlc(url);
    } catch (_) {
      return const [];
    }
    if (body.isEmpty) return const [];

    List<dynamic> listings;
    try {
      final root = jsonDecode(body);
      if (root is! Map<String, dynamic>) return const [];
      listings = root['epg_listings'] is List
          ? root['epg_listings'] as List<dynamic>
          : const [];
    } catch (_) {
      return const [];
    }

    final programs = <EpgProgram>[];
    for (final element in listings) {
      if (element is! Map<String, dynamic>) continue;
      final start = _parseTimestamp(element['start']?.toString());
      if (start == null || _isGarbage(start)) continue;
      var stop = _parseTimestamp(element['stop']?.toString());
      if (stop == null || !stop.isAfter(start)) {
        stop = start.add(const Duration(hours: 1));
      }
      if (_isGarbage(stop)) continue;

      final title = _decodeField(element['title']?.toString()) ?? 'Unknown';
      final description = _decodeField(element['description']?.toString());
      programs.add(
        EpgProgram(
          channelId: channel.id,
          title: title.isEmpty ? 'Unknown' : title,
          description: description,
          startTime: start,
          endTime: stop,
        ),
      );
    }

    programs.sort((a, b) => a.startTime.compareTo(b.startTime));
    return programs;
  }
}

/// 5-minute TTL, single-flight, in-memory cache keyed by `server|channelId|limit`.
class ShortEpgCache {
  static final ShortEpgCache instance = ShortEpgCache._();
  ShortEpgCache._();

  static const _ttl = Duration(minutes: 5);

  final Map<String, _Entry> _cache = {};

  Future<List<EpgProgram>> getOrLoad(
    XtreamAccount account,
    IptvChannel channel, {
    int limit = 8,
  }) async {
    final key = '${account.server}|${channel.id}|$limit';
    final existing = _cache[key];
    if (existing != null &&
        existing.done != null &&
        !existing.done!.isBefore(DateTime.now().subtract(_ttl))) {
      return existing.result;
    }
    if (existing != null && existing.inFlight != null) {
      return existing.inFlight!;
    }

    final completer = Completer<List<EpgProgram>>();
    final entry = _Entry(inFlight: completer.future);
    _cache[key] = entry;

    try {
      final result = await ShortEpgClient.fetchShortEpg(account, channel, limit: limit);
      entry.result = result;
      entry.done = DateTime.now();
      if (!completer.isCompleted) completer.complete(result);
      return result;
    } catch (e) {
      entry.result = const [];
      entry.done = DateTime.now();
      if (!completer.isCompleted) completer.complete(const []);
      return const [];
    }
  }

  void clear() => _cache.clear();
}

class _Entry {
  DateTime? done;
  List<EpgProgram> result = const [];
  Future<List<EpgProgram>>? inFlight;

  _Entry({this.inFlight});
}
