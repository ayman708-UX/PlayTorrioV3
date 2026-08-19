import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../models/iptv/iptv_models.dart';
import 'epg_parser.dart';
import 'iptv_http.dart';
import 'iptv_storage.dart';
import 'm3u_parser.dart';
import 'short_epg_client.dart';
import 'stalker_client.dart';
import 'stream_validation_store.dart';
import 'xtream_client.dart';

/// Port of `IptvRepository.kt` — the central state + controller for IPTVNutz.
///
/// Uses a [ValueNotifier] of [IptvUiState] (Dart analogue of StateFlow).
class IptvRepository {
  IptvRepository._();
  static final IptvRepository instance = IptvRepository._();

  static const String _iptvOrgUrl = 'https://iptv-org.github.io/iptv/index.m3u';
  static const String _iptvOrgName = 'iptv-org';
  static const String _mjhEpgUrl =
      'https://raw.githubusercontent.com/matthuisman/i.mjh.nz/master/all/epg.xml';
  static const String _mjhEpgName = 'i.mjh.nz EPG';

  static const Duration _channelCacheTtl = Duration(hours: 1);
  static const Duration _epgCacheTtl = Duration(hours: 1);
  static const int _maxEpgCachePrograms = 150000;
  static const int _maxEpgCacheBytes = 8000000;

  int _idCounter = 0;
  bool _hasLoaded = false;
  IptvSettings _settings = const IptvSettings();
  final ValueNotifier<IptvUiState> _uiState =
      ValueNotifier<IptvUiState>(const IptvUiState());
  Timer? _epgTimer;

  // EPG lookups by normalized id / name, merged from all sources.
  Map<String, List<EpgProgram>> _epgProgramsByNormId = {};
  Map<String, List<EpgProgram>> _epgProgramsByName = {};

  ValueListenable<IptvUiState> get uiState => _uiState;
  IptvUiState get state => _uiState.value;

  String _nextId(String prefix) =>
      '${prefix}_${++_idCounter}_${DateTime.now().millisecondsSinceEpoch}';

  String _m3uCacheKey(M3uPlaylist p) => p.url.isNotEmpty ? p.url : 'm3u:${p.id}';
  String _xtreamCacheKey(XtreamAccount a) => 'xtream:${a.id}';
  String _stalkerCacheKey(StalkerAccount a) => 'stalker:${a.id}';

  // ── Initialization ─────────────────────────────────────────────────────

  Future<void> ensureLoaded() async {
    if (_hasLoaded) return;
    _hasLoaded = true;
    try {
      _settings = await IptvStorage.loadSettings();
    } catch (_) {
      _settings = const IptvSettings();
      await IptvStorage.saveSettings(_settings);
    }
    await _hydrateChannelsFromCache();
    await _loadCachedEpg();
    await StreamValidationStoreInit.init();
    _refreshUi();
  }

  Future<void> _hydrateChannelsFromCache() async {
    // Channels are persisted inline in settings (see models), so rehydration
    // simply keeps whatever was saved. Cache files are used for freshness.
  }

  // ── Persistence ────────────────────────────────────────────────────────

  Future<void> _saveToStorage() async {
    try {
      await IptvStorage.saveSettings(_settings);
    } catch (_) {}
  }

  // ── Source management ──────────────────────────────────────────────────

  Future<void> addM3uPlaylist(String name, String url) async {
    final id = _nextId('m3u');
    final playlist = M3uPlaylist(id: id, name: name, url: url);
    _settings = _copySettings(
      m3uPlaylists: [..._settings.m3uPlaylists, playlist],
    );
    if (url == _iptvOrgUrl) _maybeAutoAddIptvOrgEpg();
    await _saveToStorage();
    _refreshUi();
    await refreshM3uChannels(id);
  }

  void _maybeAutoAddIptvOrgEpg() {
    if (_settings.epgSources.any((e) => e.url == _mjhEpgUrl)) return;
    final id = _nextId('epg');
    _settings = _copySettings(
      epgSources: [
        ..._settings.epgSources,
        EpgSource(id: id, name: _mjhEpgName, url: _mjhEpgUrl),
      ],
    );
    _saveToStorage();
  }

  Future<void> removeM3uPlaylist(String id) async {
    final playlist = _settings.m3uPlaylists.where((p) => p.id == id).firstOrNull;
    _settings = _copySettings(
      m3uPlaylists: _settings.m3uPlaylists.where((p) => p.id != id).toList(),
    );
    await _saveToStorage();
    if (playlist != null) await IptvStorage.invalidateChannelCache(_m3uCacheKey(playlist));
    _refreshUi();
  }

  Future<void> refreshM3uChannels(String id) async {
    final playlist = _settings.m3uPlaylists.where((p) => p.id == id).firstOrNull;
    if (playlist == null) return;
    _setState(state.copyWith(
      isLoading: true,
      refreshingSourceIds: {...state.refreshingSourceIds, id},
      clearError: true,
    ));

    final cached = await _loadChannelsFromCache(_m3uCacheKey(playlist));
    if (cached != null) {
      _settings = _copySettings(
        m3uPlaylists: _settings.m3uPlaylists
            .map((p) => p.id == id ? p.copyWith(channels: cached) : p)
            .toList(),
      );
      await _saveToStorage();
      _setState(state.copyWith(
        refreshingSourceIds: {...state.refreshingSourceIds}..remove(id),
      ));
      _refreshUi();
      return;
    }

    try {
      final m3uContent = await IptvHttp.getText(playlist.url);
      final channels = M3uParser.parse(m3uContent, id);
      await IptvStorage.saveChannelCache(
        _m3uCacheKey(playlist),
        channels,
        timestamp: DateTime.now(),
      );
      _settings = _copySettings(
        m3uPlaylists: _settings.m3uPlaylists
            .map((p) => p.id == id ? p.copyWith(channels: channels) : p)
            .toList(),
      );
      await _saveToStorage();
      _setState(state.copyWith(
        refreshingSourceIds: {...state.refreshingSourceIds}..remove(id),
      ));
      _refreshUi();
      if (_settings.epgSources.isNotEmpty) await refreshEpg();
    } catch (e) {
      _setState(state.copyWith(
        isLoading: false,
        error: 'Failed to load M3U: $e',
        refreshingSourceIds: {...state.refreshingSourceIds}..remove(id),
      ));
    }
  }

  Future<void> parseM3uContent(String content, String name) async {
    final id = _nextId('m3u_up');
    final channels = M3uParser.parse(content, id);
    final playlist = M3uPlaylist(id: id, name: name, url: '', channels: channels);
    _settings = _copySettings(
      m3uPlaylists: [..._settings.m3uPlaylists, playlist],
    );
    await IptvStorage.saveChannelCache(
      _m3uCacheKey(playlist),
      channels,
      timestamp: DateTime.now(),
    );
    await _saveToStorage();
    _refreshUi();
  }

  Future<void> addXtreamAccount(
    String name,
    String server,
    String username,
    String password, {
    PortalAccountInfo? info,
  }) async {
    final id = _nextId('xtream');
    final account = XtreamAccount(
      id: id,
      name: name,
      server: server,
      username: username,
      password: password,
      info: info,
    );
    _settings = _copySettings(
      xtreamAccounts: [..._settings.xtreamAccounts, account],
    );
    await _saveToStorage();
    _refreshUi();
    await refreshXtreamChannels(id);
  }

  Future<void> removeXtreamAccount(String id) async {
    final account = _settings.xtreamAccounts.where((a) => a.id == id).firstOrNull;
    _settings = _copySettings(
      xtreamAccounts:
          _settings.xtreamAccounts.where((a) => a.id != id).toList(),
    );
    await _saveToStorage();
    if (account != null) {
      await IptvStorage.invalidateChannelCache(_xtreamCacheKey(account));
    }
    _refreshUi();
  }

  Future<void> refreshXtreamChannels(String id) async {
    final account = _settings.xtreamAccounts.where((a) => a.id == id).firstOrNull;
    if (account == null) return;
    _setState(state.copyWith(
      isLoading: true,
      refreshingSourceIds: {...state.refreshingSourceIds, id},
      clearError: true,
    ));

    try {
      final baseUrl = account.server.replaceAll(RegExp(r'/+$'), '');
      final creds = 'username=${account.username}&password=${account.password}';
      const headers = {'User-Agent': 'VLC/3.0.20'};

      PortalAccountInfo? info;
      try {
        final infoJson = await IptvHttp.getText(
          '$baseUrl/player_api.php?$creds',
          headers: headers,
        );
        info = XtreamClient.parseAccountInfo(infoJson);
      } catch (_) {}

      var categoriesJson = '';
      try {
        categoriesJson = await IptvHttp.getText(
          '$baseUrl/player_api.php?$creds&action=get_live_categories',
          headers: headers,
        );
      } catch (_) {
        try {
          categoriesJson = await IptvHttp.getText(
            '$baseUrl/player_api.php?$creds&action=live_categories',
            headers: headers,
          );
        } catch (_) {}
      }
      final categories = XtreamClient.parseCategories(categoriesJson);

      var streamsJson = '';
      try {
        streamsJson = await IptvHttp.getText(
          '$baseUrl/player_api.php?$creds&action=get_live_streams',
          headers: headers,
        );
      } catch (_) {
        try {
          streamsJson = await IptvHttp.getText(
            '$baseUrl/player_api.php?$creds&action=live_streams',
            headers: headers,
          );
        } catch (_) {}
      }
      final channels = XtreamClient.parseChannels(
        streamsJson,
        id,
        account.server,
        account.username,
        account.password,
      );

      final updated = account.copyWith(
        categories: categories,
        channels: channels,
        info: info ?? account.info,
      );
      _settings = _copySettings(
        xtreamAccounts: _settings.xtreamAccounts
            .map((a) => a.id == id ? updated : a)
            .toList(),
      );
      await IptvStorage.saveChannelCache(
        _xtreamCacheKey(account),
        channels,
        timestamp: DateTime.now(),
      );
      await _saveToStorage();
      _setState(state.copyWith(
        refreshingSourceIds: {...state.refreshingSourceIds}..remove(id),
      ));
      _refreshUi();
    } catch (e) {
      _setState(state.copyWith(
        isLoading: false,
        error: 'Failed to load Xtream: $e',
        refreshingSourceIds: {...state.refreshingSourceIds}..remove(id),
      ));
    }
  }

  Future<void> addStalkerAccount(String name, String server, String macAddress) async {
    final id = _nextId('stalker');
    final account = StalkerAccount(
      id: id,
      name: name,
      server: server,
      macAddress: macAddress,
    );
    _settings = _copySettings(
      stalkerAccounts: [..._settings.stalkerAccounts, account],
    );
    await _saveToStorage();
    _refreshUi();
    await refreshStalkerChannels(id);
  }

  Future<void> removeStalkerAccount(String id) async {
    final account =
        _settings.stalkerAccounts.where((a) => a.id == id).firstOrNull;
    _settings = _copySettings(
      stalkerAccounts: _settings.stalkerAccounts.where((a) => a.id != id).toList(),
    );
    await _saveToStorage();
    if (account != null) {
      await IptvStorage.invalidateChannelCache(_stalkerCacheKey(account));
    }
    _refreshUi();
  }

  Future<void> refreshStalkerChannels(String id) async {
    final account = _settings.stalkerAccounts.where((a) => a.id == id).firstOrNull;
    if (account == null) return;
    _setState(state.copyWith(
      isLoading: true,
      refreshingSourceIds: {...state.refreshingSourceIds, id},
      clearError: true,
    ));

    try {
      final channels =
          await StalkerClient.fetchChannels(account.server, account.macAddress, id);
      final updated = account.copyWith(channels: channels);
      _settings = _copySettings(
        stalkerAccounts: _settings.stalkerAccounts
            .map((a) => a.id == id ? updated : a)
            .toList(),
      );
      await IptvStorage.saveChannelCache(
        _stalkerCacheKey(account),
        channels,
        timestamp: DateTime.now(),
      );
      await _saveToStorage();
      _setState(state.copyWith(
        refreshingSourceIds: {...state.refreshingSourceIds}..remove(id),
      ));
      _refreshUi();
    } catch (e) {
      _setState(state.copyWith(
        isLoading: false,
        error: 'Failed to load Stalker: $e',
        refreshingSourceIds: {...state.refreshingSourceIds}..remove(id),
      ));
    }
  }

  // ── EPG ────────────────────────────────────────────────────────────────

  Future<void> addEpgSource(String name, String url) async {
    final id = _nextId('epg');
    _settings = _copySettings(
      epgSources: [..._settings.epgSources, EpgSource(id: id, name: name, url: url)],
    );
    await _saveToStorage();
    _refreshUi();
    await refreshEpg();
  }

  Future<void> addUploadedEpgSource(String name, String content) async {
    final id = _nextId('epg_upload');
    await IptvStorage.saveEpgSourceContent(id, content);
    _settings = _copySettings(
      epgSources: [..._settings.epgSources, EpgSource(id: id, name: name, url: 'file://$id')],
    );
    await _saveToStorage();
    _refreshUi();
    await refreshEpg();
  }

  Future<void> removeEpgSource(String id) async {
    final source = _settings.epgSources.where((s) => s.id == id).firstOrNull;
    _settings = _copySettings(
      epgSources: _settings.epgSources.where((s) => s.id != id).toList(),
    );
    if (source?.url.startsWith('file://') == true) {
      await IptvStorage.deleteEpgSourceContent(id);
    }
    await _saveToStorage();
    _refreshUi();
  }

  Future<void> refreshEpg() async {
    _epgTimer?.cancel();
    _setState(state.copyWith(epgLoading: true));

    final allPrograms = <String, List<EpgProgram>>{};
    final programsByName = <String, List<EpgProgram>>{};
    String? lastError;

    for (final source in _settings.epgSources) {
      try {
        late EpgParseResult result;
        if (source.url.startsWith('file://')) {
          final content = await IptvStorage.loadEpgSourceContent(source.id);
          if (content == null) {
            throw Exception('Local EPG file missing for "${source.name}"');
          }
          result = EpgParser.parseXmltv(content);
        } else {
          final xml = await IptvHttp.getText(
            source.url,
            headers: {'Accept': 'application/xml, text/xml, */*'},
            timeout: const Duration(seconds: 180),
          );
          result = EpgParser.parseXmltv(xml);
        }

        allPrograms.addAll(result.programsByChannelId);
        result.programsByChannelId.forEach((chId, progs) {
          final displayName = result.channelDisplayNames[chId];
          if (displayName != null) {
            final key = _normalizeIptvName(displayName);
            if (key.isNotEmpty) {
              final existing = programsByName[key];
              programsByName[key] = existing == null
                  ? progs
                  : [...existing, ...progs]..sort(
                      (a, b) => a.startTime.compareTo(b.startTime),
                    );
            }
          }
        });
      } catch (e) {
        lastError = e.toString();
      }
    }

    final programsByNormId = _buildNormalizedIdIndex(allPrograms);
    final allCh = getAllChannels();
    final matchedIds = allCh.where((ch) {
      final key = _normalizeEpgId(ch.epgChannelId);
      return key.isNotEmpty && programsByNormId.containsKey(key);
    }).length;
    final matchedNames = allCh.where((ch) {
      final byId = _normalizeEpgId(ch.epgChannelId);
      final hasById =
          byId.isNotEmpty && programsByNormId.containsKey(byId);
      final byName = !hasById &&
          _normalizeIptvName(ch.name).isNotEmpty &&
          programsByName.containsKey(_normalizeIptvName(ch.name));
      return byName;
    }).length;

    _epgProgramsByNormId = programsByNormId;
    _epgProgramsByName = programsByName;
    _setState(state.copyWith(
      epgLoading: false,
      epgError: lastError?.toString(),
      epgMatchCount: matchedIds + matchedNames,
    ));
    await _saveEpgCache(allPrograms, programsByName, programsByNormId);
  }

  // ── Filters / favorites / history / search ─────────────────────────────

  void clearSourceSelection() {
    _setState(state.copyWith(selectedSourceIds: const {}));
    _applyFilters();
  }

  void toggleSourceSelection(int index) {
    final allIds = getAllSourceIds();
    final sourceId = index < allIds.length ? allIds[index] : null;
    if (sourceId == null) return;
    final current = state.selectedSourceIds;
    final newIds = <String>{...current};
    if (current.contains(sourceId)) {
      newIds.remove(sourceId);
    } else {
      newIds.add(sourceId);
    }
    _setState(state.copyWith(selectedSourceIds: newIds));
    _applyFilters();
  }

  void selectSource(int index) {
    final allIds = getAllSourceIds();
    final sourceId = index < allIds.length ? allIds[index] : null;
    if (sourceId == null) return;
    _setState(state.copyWith(selectedSourceIds: {sourceId}));
    _applyFilters();
  }

  void selectCategory(String? category) {
    _setState(state.copyWith(selectedCategory: category));
    _applyFilters();
  }

  List<String> getAllCategories() =>
      getAllChannels().map((c) => c.group).whereType<String>().toSet().toList()..sort();

  List<String> getAllSourceNames() => [
        ..._settings.m3uPlaylists.map((p) => p.name),
        ..._settings.xtreamAccounts.map((a) => a.name),
        ..._settings.stalkerAccounts.map((a) => a.name),
      ];

  List<String> getAllSourceIds() => [
        ..._settings.m3uPlaylists.map((p) => p.id),
        ..._settings.xtreamAccounts.map((a) => a.id),
        ..._settings.stalkerAccounts.map((a) => a.id),
      ];

  void toggleFavorite(String channelId) {
    final current = _settings.favoriteChannelIds;
    final newSet = <String>{...current};
    if (current.contains(channelId)) {
      newSet.remove(channelId);
    } else {
      newSet.add(channelId);
    }
    _settings = _copySettings(favoriteChannelIds: newSet.toList());
    _saveToStorage();
    _setState(state.copyWith(favoriteChannelIds: _settings.favoriteChannelIds));
  }

  bool isFavorite(String channelId) =>
      _settings.favoriteChannelIds.contains(channelId);

  List<String> get favoriteChannelIds => _settings.favoriteChannelIds;

  List<IptvChannel> getFavoriteChannels() =>
      getAllChannels().where((c) => favoriteChannelIds.contains(c.id)).toList();

  void setSearchQuery(String query) {
    _setState(state.copyWith(searchQuery: query));
    _applyFilters();
  }

  void togglePlaylistsExpanded() =>
      _setState(state.copyWith(playlistsExpanded: !state.playlistsExpanded));

  void toggleChannelsExpanded() =>
      _setState(state.copyWith(channelsExpanded: !state.channelsExpanded));

  void toggleFavoritesExpanded() =>
      _setState(state.copyWith(favoritesExpanded: !state.favoritesExpanded));

  void addPredefinedPlaylist() {
    final exists = _settings.m3uPlaylists.any((p) => p.url == _iptvOrgUrl);
    if (!exists) {
      addM3uPlaylist(_iptvOrgName, _iptvOrgUrl);
    } else {
      _maybeAutoAddIptvOrgEpg();
      refreshEpg();
    }
  }

  bool hasPredefinedPlaylist() =>
      _settings.m3uPlaylists.any((p) => p.url == _iptvOrgUrl);

  void addToHistory(String channelId) {
    final current = [..._settings.historyChannelIds];
    current.remove(channelId);
    current.insert(0, channelId);
    _settings = _copySettings(channelHistory: current.take(15).toList());
    _saveToStorage();
    _refreshUi();
  }

  void clearHistory() {
    _settings = _copySettings(channelHistory: const []);
    _saveToStorage();
    _refreshUi();
  }

  List<IptvChannel> getHistoryChannels() => _settings.historyChannelIds
      .map((id) => getAllChannels().where((c) => c.id == id).firstOrNull)
      .whereType<IptvChannel>()
      .toList();

  List<IptvChannel> getLastFilteredChannels() => state.channels;

  List<XtreamAccount> getXtreamAccounts() => _settings.xtreamAccounts;

  Future<List<EpgProgram>> getEpgProgramsForChannel(IptvChannel channel) async {
    if (channel.sourceType == SourceType.xtream) {
      final account = _settings.xtreamAccounts
          .where((a) => a.id == channel.sourceId)
          .firstOrNull;
      if (account != null) {
        return ShortEpgCache.instance.getOrLoad(account, channel, limit: 2);
      }
      return const [];
    }
    final byId = channel.epgChannelId == null
        ? null
        : _epgProgramsByNormId[_normalizeEpgId(channel.epgChannelId)];
    final byName = _epgProgramsByName[_normalizeIptvName(channel.name)];
    return byId ?? byName ?? const [];
  }

  Future<(EpgProgram?, EpgProgram?)> getEpgNowNext(
    String? channelId,
    String? channelName,
  ) async {
    final now = DateTime.now();
    List<EpgProgram> programs = const [];
    if (channelId != null) {
      final ch = getAllChannels().where((c) => c.id == channelId).firstOrNull;
      if (ch != null) programs = await getEpgProgramsForChannel(ch);
    }
    if (programs.isEmpty && channelName != null) {
      programs = _epgProgramsByName[_normalizeIptvName(channelName)] ?? const [];
    }
    EpgProgram? current;
    EpgProgram? next;
    for (final p in programs) {
      if (p.startTime.isBefore(now) && p.endTime.isAfter(now)) current = p;
      if (p.startTime.isAfter(now)) {
        next = p;
        break;
      }
    }
    return (current, next);
  }

  List<IptvChannel> getAllChannels() => [
        ..._settings.m3uPlaylists.expand((p) => p.channels),
        ..._settings.xtreamAccounts.expand((a) => a.channels),
        ..._settings.stalkerAccounts.expand((a) => a.channels),
      ];

  /// Map of normalized channel-name keys → current EPG program title, from the
  /// pre-loaded XMLTV cache. Empty when no EPG is loaded for a channel.
  Map<String, String> buildCurrentEpgTitleMap() {
    final now = DateTime.now();
    final titlesByChannelKey = <String, String>{};
    _epgProgramsByName.forEach((nameKey, programs) {
      final current = programs
          .firstWhere(
            (p) => p.startTime.isBefore(now) && p.endTime.isAfter(now),
            orElse: () => _emptyProgram,
          )
          .title;
      if (current.trim().isNotEmpty) {
        titlesByChannelKey[_normalizeIptvName(nameKey)] = current;
      }
    });
    return titlesByChannelKey;
  }

  static final EpgProgram _emptyProgram = EpgProgram(
    channelId: '',
    title: '',
    startTime: DateTime.fromMillisecondsSinceEpoch(0),
    endTime: DateTime.fromMillisecondsSinceEpoch(0),
  );

  /// Lazily and concurrently enriches the EPG lookup for candidate channels.
  /// Xtream candidates get current-program via [ShortEpgCache]; M3U/Stalker
  /// fall back to the loaded XMLTV map. Capped at [cap] channels.
  Future<Map<String, String>> buildLazyEpgTitleLookup(
    List<IptvChannel> candidates, {
    int cap = 8,
  }) async {
    final merged = buildCurrentEpgTitleMap();
    if (candidates.isEmpty) return merged;

    final xtreamCandidates =
        candidates.where((c) => c.sourceType == SourceType.xtream).take(cap);
    final now = DateTime.now();

    final futures = xtreamCandidates.map((channel) async {
      final account = _settings.xtreamAccounts
          .where((a) => a.id == channel.sourceId)
          .firstOrNull;
      if (account == null) return;
      try {
        final programs = await ShortEpgCache.instance.getOrLoad(
          account,
          channel,
          limit: 2,
        );
        final current = programs
            .firstWhere(
              (p) => p.startTime.isBefore(now) && p.endTime.isAfter(now),
              orElse: () => _emptyProgram,
            )
            .title;
        if (current.trim().isNotEmpty) {
          merged[_normalizeIptvName(channel.name)] = current;
        }
      } catch (_) {}
    });

    await Future.wait(futures);
    return merged;
  }

  // ── Internal helpers ───────────────────────────────────────────────────

  IptvSettings _copySettings({
    List<M3uPlaylist>? m3uPlaylists,
    List<XtreamAccount>? xtreamAccounts,
    List<StalkerAccount>? stalkerAccounts,
    List<EpgSource>? epgSources,
    List<String>? favoriteChannelIds,
    List<String>? channelHistory,
  }) {
    return IptvSettings(
      m3uPlaylists: m3uPlaylists ?? _settings.m3uPlaylists,
      xtreamAccounts: xtreamAccounts ?? _settings.xtreamAccounts,
      stalkerAccounts: stalkerAccounts ?? _settings.stalkerAccounts,
      epgSources: epgSources ?? _settings.epgSources,
      favoriteChannelIds: favoriteChannelIds ?? _settings.favoriteChannelIds,
      historyChannelIds: channelHistory ?? _settings.historyChannelIds,
    );
  }

  void _setState(IptvUiState newState) {
    _uiState.value = newState;
  }

  void _applyFilters() {
    try {
      final stateValue = state;
      final selectedIds = stateValue.selectedSourceIds;
      final query = stateValue.searchQuery.trim().toLowerCase();
      final category = stateValue.selectedCategory;

      var filtered = getAllChannels();

      if (selectedIds.isNotEmpty) {
        filtered = filtered.where((c) => selectedIds.contains(c.sourceId)).toList();
      } else {
        final allIds = getAllSourceIds().toSet();
        filtered = filtered.where((c) => allIds.contains(c.sourceId)).toList();
      }

      if (query.isNotEmpty) {
        filtered =
            filtered.where((c) => c.name.toLowerCase().contains(query)).toList();
      }

      if (category != null) {
        filtered = filtered.where((c) => c.group == category).toList();
      }

      _uiState.value = stateValue.copyWith(
        m3uPlaylists: _settings.m3uPlaylists,
        xtreamAccounts: _settings.xtreamAccounts,
        stalkerAccounts: _settings.stalkerAccounts,
        epgSources: _settings.epgSources,
        favoriteChannelIds: _settings.favoriteChannelIds,
        channels: filtered,
        isLoading: false,
        clearError: true,
      );
    } catch (_) {}
  }

  void _refreshUi() => _applyFilters();

  Future<List<IptvChannel>?> _loadChannelsFromCache(String key) async {
    final cached = await IptvStorage.loadChannelCache(key);
    if (cached == null) return null;
    final timestamp =
        (cached['timestamp'] as num?)?.toInt() ?? 0;
    final age = DateTime.now().millisecondsSinceEpoch - timestamp;
    if (age < 0 || age > _channelCacheTtl.inMilliseconds) return null;
    return (cached['channels'] as List<dynamic>? ?? [])
        .map((e) => IptvChannel.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> _loadCachedEpg() async {
    final cached = await IptvStorage.loadEpgCache();
    if (cached == null) return;
    try {
      final timestamp = (cached['timestamp'] as num?)?.toInt() ?? 0;
      final age = DateTime.now().millisecondsSinceEpoch - timestamp;
      if (timestamp > 0 && age >= 0 && age <= _epgCacheTtl.inMilliseconds) {
        final programs = _decodeEpgMap(cached['programsByChannelId']);
        final programsByName = _decodeEpgMap(cached['programsByName']);
        final programsByNormId = _buildNormalizedIdIndex(programs);
        _epgProgramsByName = programsByName;
        _epgProgramsByNormId = programsByNormId;
        final allCh = getAllChannels();
        final matchedIds = allCh.where((ch) {
          final key = _normalizeEpgId(ch.epgChannelId);
          return key.isNotEmpty && programsByNormId.containsKey(key);
        }).length;
        final matchedNames = allCh.where((ch) {
          final byId = _normalizeEpgId(ch.epgChannelId);
          final hasById = byId.isNotEmpty && programsByNormId.containsKey(byId);
          final byName = !hasById &&
              _normalizeIptvName(ch.name).isNotEmpty &&
              programsByName.containsKey(_normalizeIptvName(ch.name));
          return byName;
        }).length;
        _setState(state.copyWith(
          epgLoading: false,
          epgMatchCount: matchedIds + matchedNames,
        ));
      }
    } catch (_) {}
  }

  Map<String, List<EpgProgram>> _decodeEpgMap(dynamic raw) {
    final result = <String, List<EpgProgram>>{};
    if (raw is! Map) return result;
    raw.forEach((k, v) {
      if (v is List) {
        result[k.toString()] = v
            .whereType<Map>()
            .map((e) => EpgProgram(
                  channelId: e['channelId']?.toString() ?? '',
                  title: e['title']?.toString() ?? 'Unknown',
                  description: e['description']?.toString(),
                  startTime: DateTime.fromMillisecondsSinceEpoch(
                    (e['startTime'] as num?)?.toInt() ?? 0,
                  ),
                  endTime: DateTime.fromMillisecondsSinceEpoch(
                    (e['endTime'] as num?)?.toInt() ?? 0,
                  ),
                  icon: e['icon']?.toString(),
                ))
            .toList();
      }
    });
    return result;
  }

  Future<void> _saveEpgCache(
    Map<String, List<EpgProgram>> programs,
    Map<String, List<EpgProgram>> programsByName,
    Map<String, List<EpgProgram>> programsByNormId,
  ) async {
    try {
      final totalPrograms = programs.values.fold<int>(0, (a, l) => a + l.length);
      if (totalPrograms > _maxEpgCachePrograms) return;
      final data = {
        'programsByChannelId': _encodeEpgMap(programs),
        'programsByName': _encodeEpgMap(programsByName),
        'programsByNormId': _encodeEpgMap(programsByNormId),
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      };
      final encoded = jsonEncode(data);
      if (encoded.length > _maxEpgCacheBytes) return;
      await IptvStorage.saveEpgCache(data);
    } catch (_) {}
  }

  Map<String, dynamic> _encodeEpgMap(Map<String, List<EpgProgram>> programs) {
    return programs.map((k, list) => MapEntry(
          k,
          list
              .map((p) => {
                    'channelId': p.channelId,
                    'title': p.title,
                    'description': p.description,
                    'startTime': p.startTime.millisecondsSinceEpoch,
                    'endTime': p.endTime.millisecondsSinceEpoch,
                    'icon': p.icon,
                  })
              .toList(),
        ));
  }

  Map<String, List<EpgProgram>> _buildNormalizedIdIndex(
    Map<String, List<EpgProgram>> programsByChannelId,
  ) {
    final result = <String, List<EpgProgram>>{};
    programsByChannelId.forEach((id, progs) {
      final key = _normalizeEpgId(id);
      if (key.isEmpty) return;
      final existing = result[key];
      result[key] = existing == null
          ? progs
          : [...existing, ...progs]
            ..sort((a, b) => a.startTime.compareTo(b.startTime));
    });
    return result;
  }

  String _normalizeEpgId(String? id) {
    if (id == null) return '';
    var s = id.trim().toLowerCase();
    final at = s.indexOf('@');
    if (at >= 0) s = s.substring(0, at).trim();
    return s;
  }

  String _normalizeIptvName(String name) {
    if (name.isEmpty) return '';
    return name
        .toLowerCase()
        .replaceAll(RegExp(r'\([^)]*\)'), ' ')
        .replaceAll(RegExp(r'\[[^\]]*\]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }
}

/// Helper to initialize the stream-validation store from the repository.
abstract final class StreamValidationStoreInit {
  static Future<void> init() => StreamValidationStore.instance.initialize();
}