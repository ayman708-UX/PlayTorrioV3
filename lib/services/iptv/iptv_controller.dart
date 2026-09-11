import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../../models/iptv/iptv_models.dart';
import '../../models/iptv/m3u_models.dart';
import 'hardcoded_channels.dart';
import 'iptv_network.dart';
import 'iptv_settings.dart';
import 'iptv_storage.dart';
import 'm3u_parser.dart';
import 'm3u_store.dart';

enum IptvView {
  home,
  channelsHub,
  channelResults,
  portalList,
  sectionPick,
  browser,
  episodeList,
  m3uPlaylists,
}

/// Central controller for the IPTV system.
class IptvController extends ChangeNotifier {
  static final IptvController instance = IptvController._();
  IptvController._();
  factory IptvController() => instance;

  IptvView view = IptvView.home;

  // ── Portal-list state ──
  bool isScraping = false;
  String statusText = '';
  List<VerifiedPortal> verified = const [];

  CatalogSource scrapeSource = CatalogSource.cloudVault;

  void setScrapeSource(CatalogSource s) {
    if (s == scrapeSource) return;
    scrapeSource = s;
    IptvSettings.setDefaultScrapeSource(s);
    _scrapeAfter = null;
    _pendingPortals.clear();
    _pendingKeys.clear();
    canGetMore = false;
    statusText = '';
    notifyListeners();
  }

  List<VerifiedPortal> get manualVerified =>
      verified.where((v) => v.portal.source == 'Manual').toList();
  bool canGetMore = false;
  String? _scrapeAfter;

  final Set<String> _verifiedKeys = {};
  final Set<String> _attemptedKeys = {};
  final List<IptvPortal> _pendingPortals = [];
  final Set<String> _pendingKeys = {};

  final Set<String> _favoritePortals = {};
  bool isFavoritePortal(String key) => _favoritePortals.contains(key);

  // Manual edit
  bool editMode = false;
  final Set<String> selected = {};
  bool showAddDialog = false;
  bool isAdding = false;
  String? addError;

  // ── Browsing state ──
  VerifiedPortal? activePortal;
  IptvSection? activeSection;
  IptvStream? activeSeries;

  bool isLoading = false;
  List<IptvCategory> categories = const [];
  List<IptvStream> browserAllStreams = const [];
  List<IptvEpisode> episodes = const [];
  String? error;

  String? browserSelectedCategoryId;
  String browserSearch = '';

  // ── Live alive checking ──
  bool liveOnly = false;
  Set<String> aliveStreamIds = const {};
  bool isVerifyingAlive = false;
  int aliveChecked = 0;
  int aliveTotal = 0;
  int aliveCount = 0;
  int? aliveCheckedAt;
  bool _aliveCancel = false;

  // ── EPG cache ──
  final Map<String, Future<List<EpgEntry>>> _epgCache = {};

  Future<List<EpgEntry>> epgFor(IptvStream s) {
    final p = activePortal;
    if (p == null || s.kind != 'live' || s.streamId.isEmpty) {
      return Future.value(const []);
    }
    return _epgCache.putIfAbsent(
      s.streamId,
      () => IptvClient.shortEpg(p.portal, s.streamId, limit: 2),
    );
  }

  final Map<String, Future<List<EpgEntry>>> _hitEpgCache = {};

  Future<List<EpgEntry>> epgForHit(ChannelHit h) {
    if (h.stream.kind != 'live' || h.stream.streamId.isEmpty) {
      return Future.value(const []);
    }
    final key = '${h.portal.key}|${h.stream.streamId}';
    return _hitEpgCache.putIfAbsent(
      key,
      () => IptvClient.shortEpg(h.portal.portal, h.stream.streamId, limit: 2),
    );
  }

  // ── Channels Hub ──
  HardcodedChannel? activeHardcoded;
  String channelStatus = '';
  bool channelIsRunning = false;
  List<ChannelHit> channelResults = const [];
  bool _channelCancel = false;
  int _channelScanToken = 0;

  final Map<String, Set<String>> _favoriteHits = {};
  bool isFavoriteHit(String channelId, ChannelHit h) =>
      _favoriteHits[channelId]?.contains(h.streamUrl) ?? false;

  final Map<String, Set<String>> _channelAttempted = {};
  final Map<String, String?> _channelCatalogAfter = {};
  final Map<String, List<IptvPortal>> _channelScrapedPool = {};
  final Map<String, List<IptvPortal>> _channelPendingPortals = {};
  final Map<String, Set<String>> _channelPendingKeys = {};

  // ── M3U Playlists ──
  List<M3uPlaylist> m3uPlaylists = const [];
  M3uPlaylist? activeM3uPlaylist;
  bool isM3uLoading = false;

  // ── Channel picker cache ──
  List<PortalChannelGroup>? _xtremeGroupsCache;
  List<M3uChannelGroup>? _m3uGroupsCache;
  Future<void>? _xtremeFuture;

  // ── Init ──
  bool _initialized = false;
  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;

    final stored = await IptvStore.load();
    _favoritePortals
      ..clear()
      ..addAll(await IptvStore.loadFavorites());
    verified = _sortFavoritesFirst(stored);
    _verifiedKeys
      ..clear()
      ..addAll(stored.map((v) => v.credKey));

    m3uPlaylists = await M3uStore.loadAll();
    scrapeSource = IptvSettings.defaultScrapeSource.value;

    // Auto-bootstrap portals if library is completely empty
    if (verified.isEmpty) {
      scrape();
    }

    notifyListeners();
  }

  List<VerifiedPortal> _sortFavoritesFirst(List<VerifiedPortal> list) {
    final favs = <VerifiedPortal>[];
    final rest = <VerifiedPortal>[];
    for (final v in list) {
      if (_favoritePortals.contains(v.key)) {
        favs.add(v);
      } else {
        rest.add(v);
      }
    }
    return [...favs, ...rest];
  }

  List<ChannelHit> _sortHitsFavoritesFirst(
      String channelId, List<ChannelHit> list) {
    final favs = _favoriteHits[channelId] ?? const <String>{};
    if (favs.isEmpty) return list;
    final f = <ChannelHit>[];
    final r = <ChannelHit>[];
    for (final h in list) {
      if (favs.contains(h.streamUrl)) {
        f.add(h);
      } else {
        r.add(h);
      }
    }
    return [...f, ...r];
  }

  Future<void> toggleFavoritePortal(String key) async {
    if (_favoritePortals.contains(key)) {
      _favoritePortals.remove(key);
    } else {
      _favoritePortals.add(key);
    }
    verified = _sortFavoritesFirst(verified);
    await IptvStore.saveFavorites(_favoritePortals);
    notifyListeners();
  }

  Future<void> toggleFavoriteHit(ChannelHit h) async {
    final ch = activeHardcoded;
    if (ch == null) return;
    final set = _favoriteHits.putIfAbsent(ch.id, () => <String>{});
    if (set.contains(h.streamUrl)) {
      set.remove(h.streamUrl);
    } else {
      set.add(h.streamUrl);
    }
    channelResults = _sortHitsFavoritesFirst(ch.id, channelResults);
    await IptvChannelFavoritesStore.save(ch.id, set);
    notifyListeners();
  }

  // ────────────────────────────────────────────────────────────────────────
  // Portal-list actions
  // ────────────────────────────────────────────────────────────────────────
  Future<void> scrape() async {
    if (isScraping) return;
    isScraping = true;
    statusText = 'Finding live portals…';
    canGetMore = false;
    notifyListeners();
    await _scrapeAndVerify();
  }

  Future<void> getMore() async {
    if (isScraping) return;
    isScraping = true;
    statusText = 'Searching for more…';
    notifyListeners();
    await _scrapeAndVerify();
  }

  Future<void> _scrapeAndVerify() async {
    const targetAlive = 5;
    const maxPagesPerPress = 40;
    final newAlive = <VerifiedPortal>[];
    ScrapePage? page;
    var pagesTried = 0;
    var exhausted = false;

    try {
      while (newAlive.length < targetAlive && pagesTried < maxPagesPerPress) {
        while (_pendingPortals.isEmpty && pagesTried < maxPagesPerPress) {
          pagesTried++;
          page = await IptvScraper.scrapeCatalogPage(
            maxResults: 50,
            after: _scrapeAfter,
            source: scrapeSource,
          );
          _scrapeAfter = page.nextAfter;

          for (final p in page.portals) {
            if (_verifiedKeys.contains(p.credKey)) continue;
            if (_attemptedKeys.contains(p.credKey)) continue;
            if (_pendingKeys.contains(p.credKey)) continue;
            _pendingKeys.add(p.credKey);
            _pendingPortals.add(p);
          }

          if (_pendingPortals.isEmpty && !page.hasMore) {
            exhausted = true;
            break;
          }
        }

        if (_pendingPortals.isEmpty) {
          break;
        }

        final remaining = targetAlive - newAlive.length;
        statusText =
            'Verifying ${_pendingPortals.length} portals · need $remaining more';
        notifyListeners();

        final snapshot = List<IptvPortal>.from(_pendingPortals);
        await IptvVerifier.verifyUntil(
          portals: snapshot,
          target: remaining,
          onAttempted: (p) {
            _attemptedKeys.add(p.credKey);
            if (_pendingKeys.remove(p.credKey)) {
              _pendingPortals.removeWhere((x) => x.credKey == p.credKey);
            }
          },
          onProgress: (c, t, a) {
            final total = newAlive.length + a;
            statusText = 'Verifying $c / $t · alive $total / $targetAlive';
            notifyListeners();
          },
          onAlive: (v) {
            if (_verifiedKeys.add(v.credKey)) {
              newAlive.add(v);
              verified = _sortFavoritesFirst([...verified, v]);
              notifyListeners();
            }
          },
        );

        if (newAlive.length < targetAlive &&
            _pendingPortals.isEmpty &&
            (page == null || !page.hasMore)) {
          exhausted = true;
          break;
        }
      }

      if (newAlive.isNotEmpty) await IptvStore.save(verified);

      _invalidateChannelCaches();
      canGetMore = _pendingPortals.isNotEmpty ||
          (page?.hasMore ?? canGetMore);

      if (newAlive.isEmpty) {
        statusText = exhausted
            ? 'No live portals found in this source.'
            : (canGetMore
                ? 'No new live portals. Try Get More.'
                : 'No new live portals.');
      } else {
        final hit = newAlive.length >= targetAlive;
        statusText = hit
            ? 'Found ${newAlive.length} live portals.'
            : 'Found ${newAlive.length} live portals'
                '${exhausted ? ' (source exhausted).' : ' (stopped early).'}';
        if (_pendingPortals.isNotEmpty) {
          statusText += ' (${_pendingPortals.length} more queued)';
        }
      }
    } catch (e) {
      statusText = 'Scrape failed: $e';
    } finally {
      isScraping = false;
      notifyListeners();
    }
  }

  Future<void> runVerification() async {
    final manual = manualVerified;
    if (manual.isEmpty) return;
    statusText = 'Re-checking saved portals…';
    notifyListeners();
    final manualKeys = manual.map((v) => v.key).toSet();
    final scrapedKept = verified.where((v) => !manualKeys.contains(v.key)).toList();
    final freshManual = <VerifiedPortal>[];
    for (final v in manual) {
      final fresh = await IptvClient.verifyOrNull(v.portal);
      if (fresh != null) freshManual.add(fresh);
    }
    verified = _sortFavoritesFirst([...freshManual, ...scrapedKept]);
    _verifiedKeys
      ..clear()
      ..addAll(verified.map((v) => v.credKey));
    _invalidateChannelCaches();
    await IptvStore.save(verified);
    statusText = '${freshManual.length} portals still alive.';
    notifyListeners();
  }

  // ────────────────────────────────────────────────────────────────────────
  // Edit / delete portals
  // ────────────────────────────────────────────────────────────────────────
  void toggleEditMode() {
    editMode = !editMode;
    if (!editMode) selected.clear();
    notifyListeners();
  }

  void toggleSelect(String key) {
    if (selected.contains(key)) {
      selected.remove(key);
    } else {
      selected.add(key);
    }
    notifyListeners();
  }

  void selectAllPortals() {
    selected.clear();
    selected.addAll(verified.map((v) => v.key));
    notifyListeners();
  }

  void deselectAllPortals() {
    selected.clear();
    notifyListeners();
  }

  Future<void> deleteAllPortals() async {
    verified = const [];
    _verifiedKeys.clear();
    selected.clear();
    editMode = false;
    _invalidateChannelCaches();
    await IptvStore.save(verified);
    notifyListeners();
  }

  Future<void> deletePortalsByKeys(Set<String> keys) async {
    if (keys.isEmpty) return;
    final keep = verified.where((v) => !keys.contains(v.key)).toList();
    verified = keep;
    _verifiedKeys
      ..clear()
      ..addAll(keep.map((v) => v.credKey));
    selected.removeWhere((k) => keys.contains(k));
    _invalidateChannelCaches();
    await IptvStore.save(keep);
    notifyListeners();
  }

  Future<void> removeChannelHits(String channelId, Set<String> streamUrls) async {
    channelResults = channelResults.where((h) => !streamUrls.contains(h.streamUrl)).toList();
    await _saveChannelHits(channelId, channelResults);
    notifyListeners();
  }

  Future<void> removeAllChannelHits(String channelId) async {
    channelResults = const [];
    await _saveChannelHits(channelId, const []);
    notifyListeners();
  }

  Future<void> deleteAllM3uPlaylists() async {
    m3uPlaylists = const [];
    _invalidateChannelCaches();
    await M3uStore.saveAll(m3uPlaylists);
    notifyListeners();
  }

  // ────────────────────────────────────────────────────────────────────────
  // Add manual portal
  // ────────────────────────────────────────────────────────────────────────
  Future<bool> addManual({
    required String url,
    required String username,
    required String password,
  }) async {
    final cleanUrl = normalizeUrl(url);
    if (cleanUrl.isEmpty || username.isEmpty || password.isEmpty) {
      addError = 'All fields required';
      notifyListeners();
      return false;
    }
    isAdding = true;
    addError = null;
    notifyListeners();
    final p = IptvPortal(
      url: cleanUrl,
      username: username.trim(),
      password: password.trim(),
      source: 'Manual',
    );
    if (_verifiedKeys.contains(p.credKey)) {
      addError = 'Portal already added (same credentials)';
      isAdding = false;
      notifyListeners();
      return false;
    }
    final v = await IptvClient.verifyOrNull(p);
    isAdding = false;
    if (v == null) {
      addError = 'Login failed — wrong credentials or dead portal.';
      notifyListeners();
      return false;
    }
    verified = _sortFavoritesFirst([v, ...verified]);
    _verifiedKeys.add(v.credKey);
    _invalidateChannelCaches();
    await IptvStore.save(verified);
    notifyListeners();
    return true;
  }

  String normalizeUrl(String raw) {
    var s = raw.trim();
    if (s.isEmpty) return '';
    if (!s.startsWith('http://') && !s.startsWith('https://')) {
      s = 'http://$s';
    }
    while (s.endsWith('/')) {
      s = s.substring(0, s.length - 1);
    }
    return s;
  }

  // ────────────────────────────────────────────────────────────────────────
  // Bulk import from JSON
  // ────────────────────────────────────────────────────────────────────────
  bool isImporting = false;

  Future<({int added, int skipped, int failed, String? error})>
      importFromJsonString(String contents) async {
    if (isImporting) {
      return (added: 0, skipped: 0, failed: 0, error: 'Already importing.');
    }
    List<IptvPortal> candidates = [];
    try {
      final decoded = json.decode(contents);
      List<dynamic> raw;
      if (decoded is Map<String, dynamic>) {
        final p = decoded['portals'];
        if (p is List) {
          raw = p;
        } else {
          return (
            added: 0,
            skipped: 0,
            failed: 0,
            error: 'JSON missing "portals" array.'
          );
        }
      } else if (decoded is List) {
        raw = decoded;
      } else {
        return (
          added: 0,
          skipped: 0,
          failed: 0,
          error: 'Unsupported JSON shape.'
        );
      }
      for (final e in raw) {
        if (e is! Map) continue;
        final url = normalizeUrl(e['url']?.toString() ?? '');
        final user = e['username']?.toString() ?? '';
        final pass = e['password']?.toString() ?? '';
        if (url.isEmpty || user.isEmpty || pass.isEmpty) continue;
        candidates.add(IptvPortal(
          url: url,
          username: user,
          password: pass,
          source: 'Manual',
        ));
      }
    } catch (e) {
      return (added: 0, skipped: 0, failed: 0, error: 'Invalid JSON: $e');
    }

    if (candidates.isEmpty) {
      return (
        added: 0,
        skipped: 0,
        failed: 0,
        error: 'No portal entries found.'
      );
    }

    isImporting = true;
    statusText = 'Importing 0 / ${candidates.length}…';
    notifyListeners();

    int added = 0, skipped = 0, failed = 0, done = 0;
    final newAlive = <VerifiedPortal>[];
    final seenInBatch = <String>{};

    const concurrency = 8;
    var idx = 0;

    Future<void> worker() async {
      while (idx < candidates.length) {
        final i = idx++;
        final p = candidates[i];
        if (_verifiedKeys.contains(p.credKey) || !seenInBatch.add(p.credKey)) {
          skipped++;
        } else {
          final v = await IptvClient.verifyOrNull(p);
          if (v == null) {
            failed++;
          } else {
            final manualV = VerifiedPortal(
              portal: IptvPortal(
                url: v.portal.url,
                username: v.portal.username,
                password: v.portal.password,
                source: 'Manual',
              ),
              name: v.name,
              expiry: v.expiry,
              maxConnections: v.maxConnections,
              activeConnections: v.activeConnections,
            );
            newAlive.add(manualV);
            _verifiedKeys.add(manualV.credKey);
            added++;
          }
        }
        done++;
        statusText = 'Importing $done / ${candidates.length}…';
        notifyListeners();
      }
    }

    await Future.wait(List.generate(concurrency, (_) => worker()));

    if (newAlive.isNotEmpty) {
      verified = _sortFavoritesFirst([...newAlive, ...verified]);
      _invalidateChannelCaches();
      await IptvStore.save(verified);
    }

    isImporting = false;
    statusText = 'Imported $added · skipped $skipped · failed $failed';
    notifyListeners();
    return (added: added, skipped: skipped, failed: failed, error: null);
  }

  // ────────────────────────────────────────────────────────────────────────
  // M3U Playlist Management
  // ────────────────────────────────────────────────────────────────────────
  Future<void> addM3uFromUrl(String name, String url) async {
    isM3uLoading = true;
    notifyListeners();
    try {
      final channels = await M3uFetcher.fetchAndParse(url);
      final pl = M3uPlaylist(
        id: M3uStore.newId(),
        name: name.trim().isEmpty ? 'Playlist' : name.trim(),
        sourceUrl: url,
        addedAt: DateTime.now().millisecondsSinceEpoch,
        updatedAt: DateTime.now().millisecondsSinceEpoch,
        channels: channels,
      );
      m3uPlaylists = [...m3uPlaylists, pl];
      _invalidateChannelCaches();
      await M3uStore.saveAll(m3uPlaylists);
    } finally {
      isM3uLoading = false;
      notifyListeners();
    }
  }

  Future<void> addM3uFromContent(String name, String content) async {
    isM3uLoading = true;
    notifyListeners();
    try {
      final channels = M3uParser.parse(content);
      final pl = M3uPlaylist(
        id: M3uStore.newId(),
        name: name.trim().isEmpty ? 'Uploaded Playlist' : name.trim(),
        sourceUrl: null,
        addedAt: DateTime.now().millisecondsSinceEpoch,
        updatedAt: DateTime.now().millisecondsSinceEpoch,
        channels: channels,
      );
      m3uPlaylists = [...m3uPlaylists, pl];
      _invalidateChannelCaches();
      await M3uStore.saveAll(m3uPlaylists);
    } finally {
      isM3uLoading = false;
      notifyListeners();
    }
  }

  Future<void> deleteM3uPlaylist(String id) async {
    m3uPlaylists = m3uPlaylists.where((p) => p.id != id).toList();
    _invalidateChannelCaches();
    await M3uStore.saveAll(m3uPlaylists);
    notifyListeners();
  }

  // ────────────────────────────────────────────────────────────────────────
  // Hardcoded Channels Scan & Stream Discovery
  // ────────────────────────────────────────────────────────────────────────
  void stopChannelSearch() {
    _channelCancel = true;
    _channelScanToken++;
    channelIsRunning = false;
    channelStatus = 'Stopped.';
    notifyListeners();
  }

  Future<void> openHardcodedChannel(HardcodedChannel ch) async {
    // 1. Immediately abort any prior search
    _channelCancel = true;
    final token = ++_channelScanToken;
    channelIsRunning = false;
    activeHardcoded = ch;
    view = IptvView.channelResults;
    channelResults = const [];
    channelStatus = '';
    notifyListeners();

    // 2. Load stored results for this specific channel
    final stored = await IptvChannelResultsStore.load(ch.id);
    if (_channelScanToken != token || activeHardcoded?.id != ch.id) return;

    final favs = await IptvChannelFavoritesStore.load(ch.id);
    if (_channelScanToken != token || activeHardcoded?.id != ch.id) return;
    _favoriteHits[ch.id] = favs;

    // Filter stored hits with HardcodedChannels.matches so any contaminated cache is cleaned
    final validStored = stored
        .where((h) => HardcodedChannels.matches(h.streamName, ch.keywords, ch.exclude))
        .toList();

    if (validStored.length != stored.length) {
      await IptvChannelResultsStore.save(ch.id, validStored);
    }

    channelResults = _sortHitsFavoritesFirst(
      ch.id,
      validStored
          .map((h) => ChannelHit(
                portal: VerifiedPortal(
                  portal: IptvPortal(
                    url: h.portalUrl,
                    username: h.portalUser,
                    password: h.portalPass,
                    source: 'Saved',
                  ),
                  name: h.portalName,
                  expiry: '',
                  maxConnections: '1',
                  activeConnections: '0',
                ),
                stream: IptvStream(
                  streamId: h.streamId,
                  name: h.streamName,
                  icon: h.streamIcon,
                  categoryId: h.streamCategoryId,
                  containerExt: h.streamContainerExt,
                  kind: h.streamKind,
                ),
                streamUrl: h.streamUrl,
              ))
          .toList(),
    );
    notifyListeners();

    if (channelResults.isEmpty) {
      await runChannelScan(ch);
    }
  }

  Future<void> getMoreChannels() async {
    final ch = activeHardcoded;
    if (ch == null) return;
    await runChannelScan(ch, scrapeMore: true);
  }

  Future<void> runChannelScan(HardcodedChannel ch, {bool scrapeMore = false}) async {
    _channelCancel = false;
    final token = ++_channelScanToken;
    channelIsRunning = true;
    notifyListeners();

    final attempted = _channelAttempted.putIfAbsent(ch.id, () => <String>{});
    final pool = _channelScrapedPool.putIfAbsent(ch.id, () => []);

    final poolKeys = pool.map((p) => p.key).toSet();
    for (final vp in verified) {
      if (!attempted.contains(vp.key) && !poolKeys.contains(vp.key)) {
        pool.add(vp.portal);
      }
    }

    final needsBootstrap =
        verified.isEmpty && pool.every((p) => attempted.contains(p.key));
    if (scrapeMore || needsBootstrap) {
      final pendingQueue =
          _channelPendingPortals.putIfAbsent(ch.id, () => <IptvPortal>[]);
      final pendingKeys =
          _channelPendingKeys.putIfAbsent(ch.id, () => <String>{});

      pendingQueue.removeWhere((p) =>
          _verifiedKeys.contains(p.credKey) || attempted.contains(p.key));
      pendingKeys
        ..clear()
        ..addAll(pendingQueue.map((p) => p.credKey));

      if (pendingQueue.isEmpty) {
        if (_channelScanToken != token || activeHardcoded?.id != ch.id) return;
        channelStatus = 'Discovering fresh portals…';
        notifyListeners();
        try {
          final after = _channelCatalogAfter[ch.id];
          final page = await IptvScraper.scrapeCatalogPage(
              maxResults: 60, after: after, source: scrapeSource);
          if (_channelScanToken != token || activeHardcoded?.id != ch.id) return;

          _channelCatalogAfter[ch.id] = page.nextAfter;
          final knownKeys = {
            ...pool.map((p) => p.key),
            ...attempted,
          };
          for (final p in page.portals) {
            if (_verifiedKeys.contains(p.credKey)) continue;
            if (knownKeys.contains(p.key)) continue;
            if (pendingKeys.add(p.credKey)) pendingQueue.add(p);
          }
          if (pendingQueue.isEmpty &&
              !page.hasMore &&
              channelResults.isEmpty) {
            if (_channelScanToken == token && activeHardcoded?.id == ch.id) {
              channelIsRunning = false;
              channelStatus = 'No more portals available.';
              notifyListeners();
            }
            return;
          }
        } catch (_) {}
      }

      if (pendingQueue.isNotEmpty) {
        if (_channelScanToken != token || activeHardcoded?.id != ch.id) return;
        final snapshot = List<IptvPortal>.from(pendingQueue);
        channelStatus = 'Verifying ${snapshot.length} portals…';
        notifyListeners();
        await IptvVerifier.verifyUntil(
          portals: snapshot,
          target: 5,
          onAttempted: (p) {
            if (pendingKeys.remove(p.credKey)) {
              pendingQueue.removeWhere((x) => x.credKey == p.credKey);
            }
          },
          onAlive: (v) async {
            if (_channelScanToken != token || activeHardcoded?.id != ch.id) return;
            if (_verifiedKeys.add(v.credKey)) {
              verified = _sortFavoritesFirst([...verified, v]);
              await IptvStore.save(verified);
              if (!attempted.contains(v.key) &&
                  !pool.any((p) => p.key == v.key)) {
                pool.add(v.portal);
              }
            }
          },
          onProgress: (c, t, a) {
            if (_channelScanToken != token || activeHardcoded?.id != ch.id) return;
            channelStatus = 'Verifying portals $c/$t · $a active';
            notifyListeners();
          },
        );
      }
    }

    if (_channelCancel || _channelScanToken != token || activeHardcoded?.id != ch.id) {
      if (_channelScanToken == token) {
        channelIsRunning = false;
        channelStatus = 'Stopped.';
        notifyListeners();
      }
      return;
    }

    final toScan = pool.take(8).toList();
    if (toScan.isEmpty) {
      if (_channelScanToken == token && activeHardcoded?.id == ch.id) {
        channelIsRunning = false;
        channelStatus = channelResults.isEmpty
            ? 'No working portals available. Tap Scan More.'
            : '${channelResults.length} streams alive.';
        notifyListeners();
      }
      return;
    }

    channelStatus = 'Scanning ${toScan.length} portals in parallel…';
    notifyListeners();

    for (final p in toScan) {
      attempted.add(p.key);
    }
    pool.removeWhere((p) => attempted.contains(p.key));

    final verifiedByKey = {for (final v in verified) v.key: v};
    final candidatesByPortal =
        await Future.wait(toScan.map((p) async {
      if (_channelCancel || _channelScanToken != token || activeHardcoded?.id != ch.id) {
        return <_Candidate>[];
      }
      final vp = verifiedByKey[p.key] ??
          VerifiedPortal(
            portal: p,
            name: p.url,
            expiry: '',
            maxConnections: '1',
            activeConnections: '0',
          );
      try {
        final streams =
            await IptvClient.streams(vp.portal, IptvSection.live, '');
        if (_channelCancel || _channelScanToken != token || activeHardcoded?.id != ch.id) {
          return <_Candidate>[];
        }
        return streams
            .where((s) =>
                HardcodedChannels.matches(s.name, ch.keywords, ch.exclude))
            .map((s) => _Candidate(
                  portal: vp,
                  stream: s,
                  url: IptvClient.streamUrl(vp.portal, s),
                ))
            .toList();
      } catch (_) {
        return <_Candidate>[];
      }
    }));

    if (_channelCancel || _channelScanToken != token || activeHardcoded?.id != ch.id) {
      return;
    }

    final have = channelResults.map((h) => h.streamUrl).toSet();
    final seen = <String>{};
    final newCandidates = <_Candidate>[];
    for (final list in candidatesByPortal) {
      for (final c in list) {
        if (c.url.isEmpty) continue;
        if (have.contains(c.url)) continue;
        if (!seen.add(c.url)) continue;
        newCandidates.add(c);
      }
    }

    if (newCandidates.isEmpty || _channelCancel || _channelScanToken != token || activeHardcoded?.id != ch.id) {
      if (_channelScanToken == token && activeHardcoded?.id == ch.id) {
        channelIsRunning = false;
        channelStatus = channelResults.isEmpty
            ? 'No matching channels found. Try Scan More.'
            : '${channelResults.length} alive · no new matches.';
        notifyListeners();
      }
      return;
    }

    final byUrl = {for (final c in newCandidates) c.url: c};
    channelStatus = 'Found ${newCandidates.length} streams · verifying health…';
    notifyListeners();

    await IptvAliveChecker.launchCheck(
      streams: newCandidates.map((c) => MapEntry(c.url, c.url)).toList(),
      isCancelled: () => _channelCancel || _channelScanToken != token || activeHardcoded?.id != ch.id,
      onResult: (id, alive) async {
        if (!alive) return;
        if (_channelCancel || _channelScanToken != token || activeHardcoded?.id != ch.id) return;
        final c = byUrl[id];
        if (c == null) return;
        if (channelResults.any((h) => h.streamUrl == c.url)) return;
        final hit = ChannelHit(portal: c.portal, stream: c.stream, streamUrl: c.url);
        channelResults =
            _sortHitsFavoritesFirst(ch.id, [...channelResults, hit]);
        await _saveChannelHits(ch.id, channelResults);
        notifyListeners();
      },
      onProgress: (p) async {
        if (_channelCancel || _channelScanToken != token || activeHardcoded?.id != ch.id) return;
        channelStatus = 'Sniffing ${p.checked}/${p.total} · '
            '${channelResults.length} verified live';
        notifyListeners();
      },
      onDone: () async {
        if (_channelCancel || _channelScanToken != token || activeHardcoded?.id != ch.id) return;
        channelIsRunning = false;
        channelStatus = channelResults.isEmpty
            ? 'No alive streams found for ${ch.name}.'
            : '${channelResults.length} live stream'
                '${channelResults.length == 1 ? '' : 's'} ready.';
        notifyListeners();
      },
    );
  }

  Future<void> _saveChannelHits(String channelId, List<ChannelHit> hits) async {
    final stored = hits
        .map((h) => StoredHit(
              portalUrl: h.portal.portal.url,
              portalUser: h.portal.portal.username,
              portalPass: h.portal.portal.password,
              portalName: h.portal.name,
              streamId: h.stream.streamId,
              streamName: h.stream.name,
              streamIcon: h.stream.icon,
              streamCategoryId: h.stream.categoryId,
              streamContainerExt: h.stream.containerExt,
              streamKind: h.stream.kind,
              streamUrl: h.streamUrl,
            ))
        .toList();
    await IptvChannelResultsStore.save(channelId, stored);
  }

  // ────────────────────────────────────────────────────────────────────────
  // Portal Browser
  // ────────────────────────────────────────────────────────────────────────
  Future<void> openSection(VerifiedPortal p, IptvSection section) async {
    activePortal = p;
    activeSection = section;
    view = IptvView.browser;
    isLoading = true;
    error = null;
    categories = const [];
    browserAllStreams = const [];
    browserSelectedCategoryId = null;
    browserSearch = '';
    aliveStreamIds = const {};
    aliveCheckedAt = null;
    _epgCache.clear();
    notifyListeners();
    try {
      final cats = await IptvClient.categories(p.portal, section);
      final streams = await IptvClient.streams(p.portal, section, '');
      categories = [const IptvCategory(id: '', name: 'All'), ...cats];
      browserAllStreams = streams;
      browserSelectedCategoryId = cats.isNotEmpty ? cats.first.id : '';

      if (section == IptvSection.live) {
        final key = IptvAliveStore.portalKey(p.portal);
        liveOnly = await IptvAliveStore.loadLiveOnly(key);
        final snap = await IptvAliveStore.load(key);
        if (snap != null) {
          aliveStreamIds = snap.aliveIds;
          aliveCheckedAt = snap.checkedAt;
        }
      } else {
        liveOnly = false;
      }
    } catch (e) {
      error = '$e';
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  void selectBrowserCategory(String id) {
    browserSelectedCategoryId = id;
    notifyListeners();
  }

  void setBrowserSearch(String q) {
    browserSearch = q;
    notifyListeners();
  }

  Future<void> startAliveCheck({bool force = false}) async {
    final p = activePortal;
    final section = activeSection;
    if (p == null || section != IptvSection.live) return;
    if (isVerifyingAlive) return;
    if (!force && aliveCheckedAt != null) return;

    final pkey = IptvAliveStore.portalKey(p.portal);
    final entries = browserAllStreams
        .map((s) => MapEntry(s.streamId, IptvClient.streamUrl(p.portal, s)))
        .toList();
    if (entries.isEmpty) return;

    isVerifyingAlive = true;
    aliveChecked = 0;
    aliveTotal = entries.length;
    aliveCount = 0;
    final aliveSet = <String>{};
    _aliveCancel = false;
    notifyListeners();

    await IptvAliveChecker.launchCheck(
      streams: entries,
      onResult: (id, alive) async {
        if (alive) aliveSet.add(id);
      },
      onProgress: (prog) async {
        aliveChecked = prog.checked;
        aliveTotal = prog.total;
        aliveCount = prog.alive;
        notifyListeners();
      },
      onDone: () async {
        aliveStreamIds = aliveSet;
        aliveCheckedAt = DateTime.now().millisecondsSinceEpoch;
        await IptvAliveStore.save(
          pkey,
          AliveSnapshot(
            checkedAt: aliveCheckedAt!,
            aliveIds: aliveSet,
          ),
        );
        isVerifyingAlive = false;
        notifyListeners();
      },
      isCancelled: () => _aliveCancel,
    );
  }

  void stopAliveCheck() {
    _aliveCancel = true;
    isVerifyingAlive = false;
    notifyListeners();
  }

  void back() {
    switch (view) {
      case IptvView.home:
        break;
      case IptvView.channelsHub:
      case IptvView.portalList:
      case IptvView.m3uPlaylists:
        view = IptvView.home;
        break;
      case IptvView.channelResults:
        stopChannelSearch();
        view = IptvView.home;
        activeHardcoded = null;
        channelResults = const [];
        channelStatus = '';
        break;
      case IptvView.sectionPick:
        view = IptvView.portalList;
        activePortal = null;
        break;
      case IptvView.browser:
        view = IptvView.sectionPick;
        activeSection = null;
        stopAliveCheck();
        break;
      case IptvView.episodeList:
        view = IptvView.browser;
        activeSeries = null;
        episodes = const [];
        break;
    }
    notifyListeners();
  }

  /// Returns all available Xtream channels from verified portals, grouped by portal.
  Future<List<PortalChannelGroup>> getAllXtremeChannels() async {
    if (_xtremeGroupsCache != null) return _xtremeGroupsCache!;
    _xtremeFuture ??= _loadXtremeChannels().then((g) {
      _xtremeGroupsCache = g;
      _xtremeFuture = null;
      notifyListeners();
    });
    await _xtremeFuture;
    return _xtremeGroupsCache!;
  }

  Future<List<PortalChannelGroup>> _loadXtremeChannels() async {
    final groups = <PortalChannelGroup>[];
    for (final portal in verified) {
      try {
        final categories = await IptvClient.categories(portal.portal, IptvSection.live);
        final liveStreams = <IptvStream>[];
        for (final cat in categories) {
          final streams = await IptvClient.streams(portal.portal, IptvSection.live, cat.id);
          liveStreams.addAll(streams);
        }
        if (liveStreams.isNotEmpty) {
          final hits = liveStreams.map((stream) {
            final url = '${portal.portal.url}/live/${portal.portal.username}/${portal.portal.password}/${stream.streamId}.${stream.containerExt}';
            return ChannelHit(portal: portal, stream: stream, streamUrl: url);
          }).toList();
          groups.add(PortalChannelGroup(portal: portal, hits: hits));
        }
      } catch (_) {}
    }
    return groups;
  }

  /// Returns all channels from loaded M3U playlists.
  List<M3uChannelGroup> getAllM3uChannels() {
    if (_m3uGroupsCache != null) return _m3uGroupsCache!;
    _m3uGroupsCache = _buildM3uGroups();
    return _m3uGroupsCache!;
  }

  List<M3uChannelGroup> _buildM3uGroups() {
    final groups = <M3uChannelGroup>[];
    for (final playlist in m3uPlaylists) {
      if (playlist.channels.isNotEmpty) {
        groups.add(M3uChannelGroup(playlist: playlist, channels: playlist.channels));
      }
    }
    return groups;
  }

  /// Invalidate the channel picker caches when portals or playlists change.
  void _invalidateChannelCaches() {
    _xtremeGroupsCache = null;
    _xtremeFuture = null;
    _m3uGroupsCache = null;
  }

  /// Cached Xtream channel groups (sync getter; triggers async load if needed).
  List<PortalChannelGroup> get xtremeGroups {
    if (_xtremeGroupsCache != null) return _xtremeGroupsCache!;
    _xtremeFuture ??= _loadXtremeChannels().then((g) {
      _xtremeGroupsCache = g;
      _xtremeFuture = null;
      notifyListeners();
    });
    return _xtremeGroupsCache ?? const [];
  }

  /// Cached M3U channel groups.
  List<M3uChannelGroup> get m3uGroups {
    if (_m3uGroupsCache != null) return _m3uGroupsCache!;
    _m3uGroupsCache = _buildM3uGroups();
    return _m3uGroupsCache!;
  }
}

class PortalChannelGroup {
  final VerifiedPortal portal;
  final List<ChannelHit> hits;
  const PortalChannelGroup({required this.portal, required this.hits});
  String get name => portal.name;
}

class M3uChannelGroup {
  final M3uPlaylist playlist;
  final List<M3uChannel> channels;
  const M3uChannelGroup({required this.playlist, required this.channels});
  String get name => playlist.name;
}

class _Candidate {
  final VerifiedPortal portal;
  final IptvStream stream;
  final String url;
  const _Candidate({
    required this.portal,
    required this.stream,
    required this.url,
  });
}
