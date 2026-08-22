import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../../utils/parse_torrent_title.dart';

/// TorBox debrid integration — streams torrents via TorBox cloud instead of
/// local P2P when an API key is configured.
class TorBoxService {
  static final TorBoxService _instance = TorBoxService._internal();
  factory TorBoxService() => _instance;
  TorBoxService._internal();

  static const _baseUrl = 'https://api.torbox.app/v1';
  static const _storageKey = 'torbox_api_key';

  String? _apiKey;
  final ValueNotifier<bool> isConfigured = ValueNotifier(false);

  String? get apiKey => _apiKey;

  Future<void> initialize() async {
    final prefs = await SharedPreferences.getInstance();
    _apiKey = prefs.getString(_storageKey);
    isConfigured.value = _apiKey != null && _apiKey!.isNotEmpty;
  }

  Future<void> setApiKey(String key) async {
    final trimmed = key.trim();
    if (trimmed.isEmpty) {
      await clearApiKey();
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_storageKey, trimmed);
    _apiKey = trimmed;
    isConfigured.value = true;
  }

  Future<void> clearApiKey() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_storageKey);
    _apiKey = null;
    isConfigured.value = false;
  }

  /// Returns lowercase info-hashes that TorBox has cached.
  Future<Set<String>> checkCachedBatch(List<String> hashes) async {
    if (!isConfigured.value || hashes.isEmpty) return {};

    final unique = hashes
        .map((h) => h.toLowerCase())
        .where((h) => h.length == 40)
        .toSet()
        .toList();
    if (unique.isEmpty) return {};

    final cached = <String>{};
    const batchSize = 50;

    for (var i = 0; i < unique.length; i += batchSize) {
      final batch = unique.sublist(
        i,
        i + batchSize > unique.length ? unique.length : i + batchSize,
      );
      final query = batch.map((h) => 'hash=$h').join('&');
      final uri = Uri.parse(
        '$_baseUrl/api/torrents/checkcached?$query&format=object',
      );

      try {
        final response = await http
            .get(uri, headers: _authHeaders)
            .timeout(const Duration(seconds: 15));

        if (response.statusCode != 200) continue;

        final body = jsonDecode(response.body) as Map<String, dynamic>;
        if (body['success'] != true) continue;

        final data = body['data'];
        if (data is Map) {
          for (final hash in batch) {
            final entry = data[hash] ?? data[hash.toUpperCase()];
            if (entry != null) cached.add(hash);
          }
        } else if (data is List) {
          for (final item in data) {
            if (item is Map && item['hash'] != null) {
              cached.add(item['hash'].toString().toLowerCase());
            }
          }
        }
      } catch (e) {
        debugPrint('[TorBox] checkCachedBatch error: $e');
      }
    }

    return cached;
  }

  /// Resolves a magnet/info-hash to a direct HTTPS stream URL via TorBox.
  Future<String?> streamTorrent(
    String magnetOrHash, {
    int? season,
    int? episode,
    int? fileIdx,
    void Function(String message)? onLog,
  }) async {
    if (!isConfigured.value || _apiKey == null) return null;

    final hash = _extractHash(magnetOrHash);
    final magnet = magnetOrHash.startsWith('magnet:')
        ? magnetOrHash
        : 'magnet:?xt=urn:btih:${hash ?? magnetOrHash}';

    void log(String msg) {
      debugPrint('[TorBox] $msg');
      onLog?.call(msg);
    }

    try {
      log('Submitting torrent to TorBox...');
      final torrentId = await _createTorrent(magnet);
      if (torrentId == null) {
        log('Failed to create torrent on TorBox');
        return null;
      }

      log('Waiting for TorBox (id=$torrentId)...');
      final torrent = await _waitForReady(torrentId, onLog: log);
      if (torrent == null) {
        log('Timed out waiting for TorBox download');
        return null;
      }

      final files = _parseFiles(torrent);
      if (files.isEmpty) {
        log('No files found in TorBox torrent');
        return null;
      }

      final selected = _selectFile(
        files,
        season: season,
        episode: episode,
        preferredIdx: fileIdx,
      );
      if (selected == null) {
        log('No suitable media file found in torrent');
        return null;
      }

      log('Requesting stream link for file ${selected.id}...');
      final url = await _requestDownloadLink(torrentId, selected.id);
      if (url == null) {
        log('Failed to get TorBox download link');
        return null;
      }

      log('TorBox stream ready');
      return url;
    } catch (e, st) {
      log('TorBox error: $e\n$st');
      return null;
    }
  }

  Map<String, String> get _authHeaders => {
        'Authorization': 'Bearer $_apiKey',
        'Accept': 'application/json',
      };

  Future<int?> _createTorrent(String magnet) async {
    final uri = Uri.parse('$_baseUrl/api/torrents/createtorrent');
    final request = http.MultipartRequest('POST', uri)
      ..headers.addAll(_authHeaders)
      ..fields['magnet'] = magnet;

    final streamed = await request.send().timeout(const Duration(seconds: 30));
    final body = await streamed.stream.bytesToString();

    if (streamed.statusCode != 200) {
      debugPrint('[TorBox] createtorrent HTTP ${streamed.statusCode}: $body');
      return null;
    }

    final json = jsonDecode(body) as Map<String, dynamic>;
    if (json['success'] != true) {
      debugPrint('[TorBox] createtorrent failed: ${json['detail'] ?? json['error']}');
      return null;
    }

    final data = json['data'];
    if (data is Map) {
      final id = data['torrent_id'] ?? data['id'];
      if (id != null) return (id as num).toInt();
    }

    return null;
  }

  Future<Map<String, dynamic>?> _waitForReady(
    int torrentId, {
    void Function(String message)? onLog,
    Duration timeout = const Duration(minutes: 10),
  }) async {
    final deadline = DateTime.now().add(timeout);
    var pollInterval = const Duration(seconds: 2);

    while (DateTime.now().isBefore(deadline)) {
      final torrent = await _fetchTorrent(torrentId);
      if (torrent == null) {
        await Future.delayed(pollInterval);
        continue;
      }

      final state = torrent['download_state']?.toString().toLowerCase() ?? '';
      final finished = torrent['download_finished'] == true;
      final progress = (torrent['progress'] as num?)?.toDouble() ?? 0;

      onLog?.call('TorBox status: $state (${progress.toStringAsFixed(0)}%)');

      if (state == 'cached' ||
          state == 'completed' ||
          finished ||
          progress >= 100) {
        return torrent;
      }

      if (state == 'metaDL' || state == 'downloading') {
        pollInterval = const Duration(seconds: 3);
      }

      await Future.delayed(pollInterval);
    }

    return null;
  }

  Future<Map<String, dynamic>?> _fetchTorrent(int torrentId) async {
    final uri = Uri.parse(
      '$_baseUrl/api/torrents/mylist?id=$torrentId&bypass_cache=true',
    );

    try {
      final response = await http
          .get(uri, headers: _authHeaders)
          .timeout(const Duration(seconds: 20));

      if (response.statusCode != 200) return null;

      final json = jsonDecode(response.body) as Map<String, dynamic>;
      if (json['success'] != true) return null;

      final data = json['data'];
      if (data is Map) return Map<String, dynamic>.from(data);
      if (data is List && data.isNotEmpty) {
        final first = data.first;
        if (first is Map) return Map<String, dynamic>.from(first);
      }
    } catch (e) {
      debugPrint('[TorBox] fetchTorrent error: $e');
    }

    return null;
  }

  Future<String?> _requestDownloadLink(int torrentId, int fileId) async {
    final uri = Uri.parse(
      '$_baseUrl/api/torrents/requestdl'
      '?token=${Uri.encodeComponent(_apiKey!)}'
      '&torrent_id=$torrentId'
      '&file_id=$fileId'
      '&redirect=true',
    );

    try {
      final client = http.Client();
      try {
        final request = http.Request('GET', uri)..followRedirects = false;
        final response = await client
            .send(request)
            .timeout(const Duration(seconds: 30));
        final body = await response.stream.bytesToString();

        if (response.statusCode >= 300 && response.statusCode < 400) {
          final location = response.headers['location'];
          if (location != null && location.isNotEmpty) return location;
        }

        if (response.statusCode == 200) {
          try {
            final json = jsonDecode(body) as Map<String, dynamic>;
            if (json['success'] == true && json['data'] != null) {
              return json['data'].toString();
            }
          } catch (_) {
            if (body.startsWith('http')) return body.trim();
          }
        }
      } finally {
        client.close();
      }
    } catch (e) {
      debugPrint('[TorBox] requestDownloadLink error: $e');
    }

    return null;
  }

  List<_TorBoxFile> _parseFiles(Map<String, dynamic> torrent) {
    final raw = torrent['files'];
    if (raw is! List) return [];

    return raw
        .whereType<Map>()
        .map((f) => _TorBoxFile(
              id: ((f['id'] ?? f['id_']) as num?)?.toInt() ?? 0,
              name: f['name']?.toString() ?? f['short_name']?.toString() ?? '',
              size: ((f['size'] as num?) ?? 0).toInt(),
              mimetype: f['mimetype']?.toString() ?? '',
            ))
        .where((f) => f.id > 0 && f.name.isNotEmpty)
        .toList();
  }

  static final _hashRegExp = RegExp(r'[0-9a-fA-F]{40}');
  static final _ptt = ParseTorrentTitle();

  static String? _extractHash(String magnetOrHash) {
    final match = _hashRegExp.firstMatch(magnetOrHash);
    return match?.group(0)?.toLowerCase();
  }

  bool _isMediaFile(String name) {
    final lower = name.toLowerCase();
    return lower.endsWith('.mp4') ||
        lower.endsWith('.mkv') ||
        lower.endsWith('.avi') ||
        lower.endsWith('.webm') ||
        lower.endsWith('.mov') ||
        lower.endsWith('.flv') ||
        lower.endsWith('.ts') ||
        lower.endsWith('.mp3') ||
        lower.endsWith('.m4b') ||
        lower.endsWith('.m4a') ||
        lower.endsWith('.aac') ||
        lower.endsWith('.flac') ||
        lower.endsWith('.ogg') ||
        lower.endsWith('.opus') ||
        lower.endsWith('.wav');
  }

  bool _isFileMatch(String name, int targetSeason, int targetEpisode) {
    final result = _ptt.parse(name);
    final parsedSeason = result['season'] as int?;
    final parsedEpisode = result['episode'] as int?;

    if (parsedSeason != null && parsedEpisode != null) {
      return parsedSeason == targetSeason && parsedEpisode == targetEpisode;
    }

    if (parsedSeason == null && parsedEpisode != null) {
      return parsedEpisode == targetEpisode;
    }

    return false;
  }

  _TorBoxFile? _selectFile(
    List<_TorBoxFile> files, {
    int? season,
    int? episode,
    int? preferredIdx,
  }) {
    if (preferredIdx != null) {
      for (final file in files) {
        if (file.id == preferredIdx) return file;
      }
    }

    final mediaFiles = files.where((f) => _isMediaFile(f.name)).toList();
    if (mediaFiles.isEmpty) {
      if (files.isEmpty) return null;
      files.sort((a, b) => b.size.compareTo(a.size));
      return files.first;
    }

    if (season != null && episode != null) {
      final episodeMatches = mediaFiles
          .where((f) => _isFileMatch(f.name, season, episode))
          .toList();
      if (episodeMatches.isNotEmpty) {
        episodeMatches.sort((a, b) => b.size.compareTo(a.size));
        return episodeMatches.first;
      }
    }

    mediaFiles.sort((a, b) => b.size.compareTo(a.size));
    return mediaFiles.first;
  }
}

class _TorBoxFile {
  final int id;
  final String name;
  final int size;
  final String mimetype;

  const _TorBoxFile({
    required this.id,
    required this.name,
    required this.size,
    required this.mimetype,
  });
}

/// Exposed for unit tests.
@visibleForTesting
TorBoxFileSelector get torBoxFileSelectorForTest => TorBoxFileSelector.instance;

@visibleForTesting
class TorBoxFileSelector {
  TorBoxFileSelector._();
  static final instance = TorBoxFileSelector._();

  static final _ptt = ParseTorrentTitle();

  bool isMediaFile(String name) {
    final lower = name.toLowerCase();
    return lower.endsWith('.mp4') ||
        lower.endsWith('.mkv') ||
        lower.endsWith('.avi') ||
        lower.endsWith('.webm') ||
        lower.endsWith('.mov') ||
        lower.endsWith('.mp3') ||
        lower.endsWith('.m4b');
  }

  int? selectFileId(
    List<Map<String, dynamic>> files, {
    int? season,
    int? episode,
    int? preferredIdx,
  }) {
    final parsed = files
        .map((f) => (
              id: ((f['id'] ?? f['id_']) as num?)?.toInt() ?? 0,
              name: f['name']?.toString() ?? '',
              size: ((f['size'] as num?) ?? 0).toInt(),
            ))
        .where((f) => f.id > 0 && f.name.isNotEmpty)
        .toList();

    if (preferredIdx != null) {
      for (final file in parsed) {
        if (file.id == preferredIdx) return file.id;
      }
    }

    final media = parsed.where((f) => isMediaFile(f.name)).toList();
    final pool = media.isNotEmpty ? media : parsed;
    if (pool.isEmpty) return null;

    if (season != null && episode != null) {
      for (final file in pool) {
        final result = _ptt.parse(file.name);
        final ps = result['season'] as int?;
        final pe = result['episode'] as int?;
        if (ps == season && pe == episode) return file.id;
        if (ps == null && pe == episode) return file.id;
      }
    }

    pool.sort((a, b) => b.size.compareTo(a.size));
    return pool.first.id;
  }
}
