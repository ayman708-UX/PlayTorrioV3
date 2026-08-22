import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../iptv/playtorrio_tv/data/iptv_network.dart';
import '../../iptv/playtorrio_tv/data/models.dart';
import '../../iptv/playtorrio_tv/data/storage.dart';
import '../../iptv/playtorrio_tv/m3u/m3u_models.dart';
import '../../models/iptv/iptv_favorite_channel.dart';
import 'iptv_epg_settings.dart';
import 'xmltv_epg_service.dart';

/// Persists starred IPTV channels and builds TV guide data for the home screen.
class IptvFavoritesService {
  IptvFavoritesService._();
  static final IptvFavoritesService instance = IptvFavoritesService._();

  static const _favoritesKey = 'playtorrio_iptv_favorites_v1';

  final ValueNotifier<List<IptvFavoriteChannel>> favorites =
      ValueNotifier(const []);

  Future<void> initialize() async {
    favorites.value = await loadFavorites();
  }

  Future<List<IptvFavoriteChannel>> loadFavorites() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_favoritesKey);
    if (raw == null) return [];
    try {
      final arr = jsonDecode(raw) as List;
      return arr
          .map((e) => IptvFavoriteChannel.fromJson(e as Map<String, dynamic>))
          .where((c) => c.streamUrl.isNotEmpty)
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> _save(List<IptvFavoriteChannel> list) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _favoritesKey,
      jsonEncode(list.map((c) => c.toJson()).toList()),
    );
    favorites.value = List.unmodifiable(list);
  }

  bool isFavorite(String id) =>
      favorites.value.any((c) => c.id == id);

  Future<void> toggleM3uFavorite({
    required M3uPlaylist playlist,
    required M3uChannel channel,
  }) async {
    final id = _m3uChannelId(playlist.id, channel.url);
    final list = List<IptvFavoriteChannel>.from(favorites.value);
    final idx = list.indexWhere((c) => c.id == id);
    if (idx >= 0) {
      list.removeAt(idx);
    } else {
      list.add(IptvFavoriteChannel(
        id: id,
        name: channel.name,
        streamUrl: channel.url,
        logoUrl: channel.logo.isNotEmpty ? channel.logo : null,
        sourceType: 'm3u',
        playlistId: playlist.id,
        playlistName: playlist.name,
        tvgId: channel.tvgId.isNotEmpty ? channel.tvgId : null,
      ));
    }
    await _save(list);
  }

  Future<void> togglePortalFavorite({
    required VerifiedPortal portal,
    required IptvStream stream,
  }) async {
    final id = 'portal:${portal.key}:${stream.streamId}';
    final list = List<IptvFavoriteChannel>.from(favorites.value);
    final idx = list.indexWhere((c) => c.id == id);
    if (idx >= 0) {
      list.removeAt(idx);
    } else {
      list.add(IptvFavoriteChannel(
        id: id,
        name: stream.name,
        streamUrl: IptvClient.streamUrl(portal.portal, stream),
        logoUrl: stream.icon.isNotEmpty ? stream.icon : null,
        sourceType: 'portal',
        portalUrl: portal.portal.url,
        portalUser: portal.portal.username,
        portalPass: portal.portal.password,
        streamId: stream.streamId,
        tvgId: stream.epgChannelId.isNotEmpty ? stream.epgChannelId : null,
      ));
    }
    await _save(list);
  }

  Future<void> removeFavorite(String id) async {
    final list = favorites.value.where((c) => c.id != id).toList();
    await _save(list);
  }

  Future<List<IptvGuideEntry>> loadGuideEntries() async {
    final channels = favorites.value;
    if (channels.isEmpty) return [];

    final epgUrl = await IptvEpgSettings.loadUrl();
    if (epgUrl != null && epgUrl.isNotEmpty) {
      await XmltvEpgService.instance.ensureLoaded(epgUrl);
    }

    final entries = <IptvGuideEntry>[];
    for (final channel in channels) {
      entries.add(await _guideForChannel(channel));
    }
    return entries;
  }

  Future<IptvGuideEntry> _guideForChannel(IptvFavoriteChannel channel) async {
    if (channel.isPortal &&
        channel.portalUrl != null &&
        channel.portalUser != null &&
        channel.portalPass != null &&
        channel.streamId != null) {
      final portal = IptvPortal(
        url: channel.portalUrl!,
        username: channel.portalUser!,
        password: channel.portalPass!,
      );
      final epg = await IptvClient.shortEpg(portal, channel.streamId!, limit: 4);
      final now = epg.where((e) => e.isNow).toList();
      final next = epg.where((e) => !e.isNow && e.start.isAfter(DateTime.now())).toList();
      return IptvGuideEntry(
        channel: channel,
        nowTitle: now.isNotEmpty ? now.first.title : null,
        nextTitle: next.isNotEmpty ? next.first.title : null,
        nowStart: now.isNotEmpty ? now.first.start : null,
        nowStop: now.isNotEmpty ? now.first.stop : null,
      );
    }

    if (channel.tvgId != null && channel.tvgId!.isNotEmpty) {
      final programmes =
          XmltvEpgService.instance.programmesForChannel(channel.tvgId!);
      final now = DateTime.now();
      XmltvProgramme? current;
      XmltvProgramme? upcoming;
      for (final p in programmes) {
        if (p.start.isBefore(now) && p.end.isAfter(now)) {
          current = p;
        } else if (p.start.isAfter(now) && upcoming == null) {
          upcoming = p;
        }
      }
      return IptvGuideEntry(
        channel: channel,
        nowTitle: current?.title,
        nextTitle: upcoming?.title,
        nowStart: current?.start,
        nowStop: current?.end,
      );
    }

    return IptvGuideEntry(channel: channel);
  }

  /// Sync portal browser stars into unified favorites (called on guide refresh).
  Future<void> syncPortalBrowserFavorites() async {
    final portals = await IptvStore.load();
    if (portals.isEmpty) return;

    final list = List<IptvFavoriteChannel>.from(favorites.value);
    final existingPortalIds =
        list.where((c) => c.isPortal).map((c) => c.id).toSet();

    for (final portal in portals) {
      final starredIds =
          await IptvBrowserFavoritesStore.load(portal.key);
      if (starredIds.isEmpty) continue;

      final liveStreams =
          await IptvClient.streams(portal.portal, IptvSection.live, '');
      for (final stream in liveStreams) {
        if (!starredIds.contains(stream.streamId)) continue;
        final id = 'portal:${portal.key}:${stream.streamId}';
        if (existingPortalIds.contains(id)) continue;
        list.add(IptvFavoriteChannel(
          id: id,
          name: stream.name,
          streamUrl: IptvClient.streamUrl(portal.portal, stream),
          logoUrl: stream.icon.isNotEmpty ? stream.icon : null,
          sourceType: 'portal',
          portalUrl: portal.portal.url,
          portalUser: portal.portal.username,
          portalPass: portal.portal.password,
          streamId: stream.streamId,
          tvgId: stream.epgChannelId.isNotEmpty ? stream.epgChannelId : null,
        ));
      }
    }

    await _save(list);
  }

  static String _m3uChannelId(String playlistId, String url) =>
      'm3u:$playlistId:${url.hashCode}';
}
