import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../models/iptv/iptv_models.dart';
import 'stream_validator.dart';

enum StreamStatus { unknown, alive, dead }

/// Port of `StreamValidationStore.kt` + `StreamValidationController.kt`.
///
/// In-memory map of URL → status with a 30-minute TTL, persisted dead URLs
/// to SharedPreferences so dead channels stay excluded across restarts.
class StreamValidationStore {
  static final StreamValidationStore instance = StreamValidationStore._();
  StreamValidationStore._();

  static const String _deadKey = 'iptv_dead_urls_v1';

  final Map<String, _StatusEntry> _statuses = {};
  DateTime? _loadedAt;

  Future<void> initialize() async {
    if (_loadedAt != null) return;
    _loadedAt = DateTime.now();
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_deadKey);
    if (raw == null) return;
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      for (final url in list) {
        _statuses[url.toString()] = _StatusEntry(
          status: StreamStatus.dead,
          checkedAt: DateTime.now(),
        );
      }
    } catch (_) {}
  }

  StreamStatus statusOf(String url) {
    final entry = _statuses[url];
    if (entry == null) return StreamStatus.unknown;
    if (DateTime.now().difference(entry.checkedAt) > StreamValidator.ttl) {
      return StreamStatus.unknown;
    }
    return entry.status;
  }

  bool isKnownDead(String url) => statusOf(url) == StreamStatus.dead;
  bool isKnownAlive(String url) => statusOf(url) == StreamStatus.alive;
  bool needsRecheck(String url) => statusOf(url) == StreamStatus.unknown;

  void updateStatus(String url, bool alive) {
    _statuses[url] = _StatusEntry(
      status: alive ? StreamStatus.alive : StreamStatus.dead,
      checkedAt: DateTime.now(),
    );
    if (!alive) _persistDead();
  }

  void clear() {
    _statuses.clear();
    _persistDead();
  }

  List<String> get deadUrls => _statuses.entries
      .where((e) => e.value.status == StreamStatus.dead)
      .map((e) => e.key)
      .toList();

  Future<void> _persistDead() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_deadKey, jsonEncode(deadUrls));
    } catch (_) {}
  }
}

/// Controller: scans a whole source's channels (or all sources) in batches.
class StreamValidationController {
  static Future<void> scanSource(
    List<IptvChannel> channels, {
    void Function(int done, int total)? onProgress,
  }) async {
    final urls = channels.map((c) => c.url).toList();
    await StreamValidator.validateUrls(
      urls,
      onProgress: onProgress,
    );
  }

  static Future<Map<String, StreamStatus>> resolveChannelsStatuses(
    List<IptvChannel> channels,
  ) async {
    final result = <String, StreamStatus>{};
    final toCheck = <String>[];
    for (final c in channels) {
      final status = StreamValidationStore.instance.statusOf(c.url);
      result[c.url] = status;
      if (status == StreamStatus.unknown) toCheck.add(c.url);
    }
    if (toCheck.isNotEmpty) {
      await StreamValidator.checkBatch(
        toCheck,
        onResult: (url, alive) {
          StreamValidationStore.instance.updateStatus(url, alive);
          result[url] = alive ? StreamStatus.alive : StreamStatus.dead;
        },
      );
    }
    return result;
  }
}

class _StatusEntry {
  final StreamStatus status;
  final DateTime checkedAt;

  _StatusEntry({required this.status, required this.checkedAt});
}
