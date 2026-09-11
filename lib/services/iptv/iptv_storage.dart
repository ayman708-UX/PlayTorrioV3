import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../models/iptv/iptv_models.dart';

/// Verified portal store.
class IptvStore {
  static const _key = 'pt_iptv_verified_portals';
  static const _favKey = 'pt_iptv_favorite_portal_keys';

  static Future<List<VerifiedPortal>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) return [];
    try {
      final arr = json.decode(raw) as List;
      return arr.map((e) {
        final o = e as Map<String, dynamic>;
        return VerifiedPortal(
          portal: IptvPortal(
            url: o['url'] as String? ?? '',
            username: o['username'] as String? ?? '',
            password: o['password'] as String? ?? '',
            source: o['source'] as String? ?? '',
          ),
          name: o['name'] as String? ?? '',
          expiry: o['expiry'] as String? ?? '',
          maxConnections: o['max'] as String? ?? '1',
          activeConnections: o['active'] as String? ?? '0',
        );
      }).toList();
    } catch (e) {
      debugPrint('IptvStore.load failed: $e');
      return [];
    }
  }

  static Future<void> save(List<VerifiedPortal> list) async {
    final prefs = await SharedPreferences.getInstance();
    final arr = list
        .map((v) => {
              'url': v.portal.url,
              'username': v.portal.username,
              'password': v.portal.password,
              'source': v.portal.source,
              'name': v.name,
              'expiry': v.expiry,
              'max': v.maxConnections,
              'active': v.activeConnections,
            })
        .toList();
    await prefs.setString(_key, json.encode(arr));
  }

  static Future<Set<String>> loadFavorites() async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_favKey) ?? const <String>[];
    return list.toSet();
  }

  static Future<void> saveFavorites(Set<String> keys) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_favKey, keys.toList());
  }
}

/// Per-portal cache of "alive" live channel IDs + per-portal Live-only pref.
class IptvAliveStore {
  static String portalKey(IptvPortal p) =>
      '${p.url}|${p.username}|${p.password}'.toLowerCase();

  static String _aliveKey(String k) => 'pt_iptv_alive_$k';
  static String _liveOnlyKey(String k) => 'pt_iptv_liveonly_$k';

  static Future<AliveSnapshot?> load(String key) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_aliveKey(key));
    if (raw == null) return null;
    try {
      final o = json.decode(raw) as Map<String, dynamic>;
      final ids = (o['ids'] as List).map((e) => e as String).toSet();
      return AliveSnapshot(
        checkedAt: (o['at'] as num?)?.toInt() ?? 0,
        aliveIds: ids,
      );
    } catch (_) {
      return null;
    }
  }

  static Future<void> save(String key, AliveSnapshot snap) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _aliveKey(key),
      json.encode({'at': snap.checkedAt, 'ids': snap.aliveIds.toList()}),
    );
  }

  static Future<void> clear(String key) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_aliveKey(key));
    await prefs.remove(_liveOnlyKey(key));
  }

  static Future<bool> loadLiveOnly(String key) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_liveOnlyKey(key)) ?? false;
  }

  static Future<void> saveLiveOnly(String key, bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_liveOnlyKey(key), enabled);
  }
}

class AliveSnapshot {
  final int checkedAt;
  final Set<String> aliveIds;
  const AliveSnapshot({required this.checkedAt, required this.aliveIds});
}

/// Per-HardcodedChannel persisted alive stream hits.
class IptvChannelResultsStore {
  static String _key(String channelId) => 'pt_iptv_ch_$channelId';

  static Future<List<StoredHit>> load(String channelId) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key(channelId));
    if (raw == null) return [];
    try {
      final arr = json.decode(raw) as List;
      return arr.map((e) {
        final o = e as Map<String, dynamic>;
        return StoredHit(
          portalUrl: o['pu'] as String? ?? '',
          portalUser: o['uu'] as String? ?? '',
          portalPass: o['pp'] as String? ?? '',
          portalName: o['pn'] as String? ?? '',
          streamId: o['sid'] as String? ?? '',
          streamName: o['sn'] as String? ?? '',
          streamIcon: o['si'] as String? ?? '',
          streamCategoryId: o['scid'] as String? ?? '',
          streamContainerExt: o['sce'] as String? ?? '',
          streamKind: o['sk'] as String? ?? 'live',
          streamUrl: o['url'] as String? ?? '',
        );
      }).toList();
    } catch (_) {
      return [];
    }
  }

  static Future<void> save(String channelId, List<StoredHit> hits) async {
    final prefs = await SharedPreferences.getInstance();
    final arr = hits
        .map((h) => {
              'pu': h.portalUrl,
              'uu': h.portalUser,
              'pp': h.portalPass,
              'pn': h.portalName,
              'sid': h.streamId,
              'sn': h.streamName,
              'si': h.streamIcon,
              'scid': h.streamCategoryId,
              'sce': h.streamContainerExt,
              'sk': h.streamKind,
              'url': h.streamUrl,
            })
        .toList();
    await prefs.setString(_key(channelId), json.encode(arr));
  }

  static Future<void> clear(String channelId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key(channelId));
  }
}

class StoredHit {
  final String portalUrl;
  final String portalUser;
  final String portalPass;
  final String portalName;
  final String streamId;
  final String streamName;
  final String streamIcon;
  final String streamCategoryId;
  final String streamContainerExt;
  final String streamKind;
  final String streamUrl;

  const StoredHit({
    required this.portalUrl,
    required this.portalUser,
    required this.portalPass,
    required this.portalName,
    required this.streamId,
    required this.streamName,
    required this.streamIcon,
    required this.streamCategoryId,
    required this.streamContainerExt,
    required this.streamKind,
    required this.streamUrl,
  });
}

/// Per-HardcodedChannel set of favorited stream URLs (pinned to top).
class IptvChannelFavoritesStore {
  static String _key(String channelId) => 'pt_iptv_chfav_$channelId';

  static Future<Set<String>> load(String channelId) async {
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getStringList(_key(channelId)) ?? const <String>[]).toSet();
  }

  static Future<void> save(String channelId, Set<String> urls) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_key(channelId), urls.toList());
  }
}

/// Per-Portal (or per-M3U playlist) set of favorited stream IDs.
class IptvPortalFavoritesStore {
  static String portalKey(IptvPortal p) =>
      '${p.url}|${p.username}|${p.password}'.toLowerCase();

  static String _key(String k) => 'pt_iptv_portalfav_$k';

  static Future<Set<String>> load(String key) async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_key(key)) ?? const <String>[];
    return list.toSet();
  }

  static Future<void> save(String key, Set<String> ids) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_key(key), ids.toList());
  }
}

/// Custom quick channels store (user-added channels).
class IptvQuickChannelStore {
  static const String _key = 'pt_iptv_quick_channels';

  static Future<List<QuickChannel>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) return [];
    try {
      final arr = json.decode(raw) as List;
      return arr.map((e) {
        final o = e as Map<String, dynamic>;
        return QuickChannel.fromJson(o);
      }).toList();
    } catch (e) {
      debugPrint('IptvQuickChannelStore.load failed: $e');
      return [];
    }
  }

  static Future<void> save(List<QuickChannel> channels) async {
    final prefs = await SharedPreferences.getInstance();
    final arr = channels.map((c) => c.toJson()).toList();
    await prefs.setString(_key, json.encode(arr));
  }

  static Future<void> add(QuickChannel channel) async {
    final list = await load();
    list.add(channel);
    await save(list);
  }

  static Future<void> remove(String id) async {
    final list = await load();
    list.removeWhere((c) => c.id == id);
    await save(list);
  }
}

/// Persisted state for a single MultiNutz cell.
class MultiNutzCellState {
  final int index;
  final String? channelName;
  final String? streamUrl;
  final double volume;
  final bool isMuted;
  final bool wasPlaying;

  const MultiNutzCellState({
    required this.index,
    this.channelName,
    this.streamUrl,
    this.volume = 0.5,
    this.isMuted = true,
    this.wasPlaying = false,
  });

  Map<String, dynamic> toJson() => {
        'index': index,
        'channelName': channelName,
        'streamUrl': streamUrl,
        'volume': volume,
        'isMuted': isMuted,
        'wasPlaying': wasPlaying,
      };

  factory MultiNutzCellState.fromJson(Map<String, dynamic> o) =>
      MultiNutzCellState(
        index: o['index'] as int? ?? 0,
        channelName: o['channelName'] as String?,
        streamUrl: o['streamUrl'] as String?,
        volume: (o['volume'] as num?)?.toDouble() ?? 0.5,
        isMuted: o['isMuted'] as bool? ?? true,
        wasPlaying: o['wasPlaying'] as bool? ?? false,
      );
}

/// Persistent session store for the MultiNutz multi-window page.
/// Saves each cell's stream URL, name, volume, mute state and play state
/// so the user can leave the tab and return to find their streams still loaded.
class MultiNutzSessionStore {
  static const String _key = 'pt_multinutz_session';
  static const int maxCells = 6;

  static Future<List<MultiNutzCellState>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) return [];
    try {
      final arr = json.decode(raw) as List;
      return arr
          .map((e) => MultiNutzCellState.fromJson(e as Map<String, dynamic>))
          .where((s) => s.streamUrl != null && s.streamUrl!.isNotEmpty)
          .toList();
    } catch (e) {
      debugPrint('MultiNutzSessionStore.load failed: $e');
      return [];
    }
  }

  static Future<void> save(List<MultiNutzCellState> states) async {
    final prefs = await SharedPreferences.getInstance();
    final arr = states.map((s) => s.toJson()).toList();
    await prefs.setString(_key, json.encode(arr));
  }

  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }
}

