import 'package:flutter/foundation.dart';

import '../../iptv/playtorrio_tv/data/iptv_network.dart';
import '../../iptv/playtorrio_tv/data/models.dart';
import '../../iptv/playtorrio_tv/data/storage.dart';

/// Slim orchestrator for the PT IPTV scraper and verified portal browser.
class IptvControllerService extends ChangeNotifier {
  List<VerifiedPortal> verifiedPortals = [];
  List<IptvPortal> scrapedPortals = [];
  String? scrapeCursor;
  String? scrapeError;
  bool scraping = false;
  bool verifying = false;
  String scrapeStatus = '';

  VerifiedPortal? activePortal;
  IptvSection activeSection = IptvSection.live;
  List<IptvCategory> categories = [];
  List<IptvStream> streams = [];
  String selectedCategoryId = '';
  Set<String> browserFavorites = {};
  bool loadingBrowse = false;

  Future<void> initialize() async {
    verifiedPortals = await IptvStore.load();
    notifyListeners();
  }

  Future<void> scrapeMore({CatalogSource source = CatalogSource.works}) async {
    if (scraping) return;
    scraping = true;
    scrapeError = null;
    scrapeStatus = 'Scanning catalog…';
    notifyListeners();

    try {
      final page = await IptvScraper.scrapeCatalogPage(
        after: scrapeCursor,
        source: source,
      );
      scrapeCursor = page.nextAfter;
      scrapeError = page.catalogError;
      scrapedPortals = [
        ...scrapedPortals,
        ...page.portals,
      ];
      scrapeStatus = page.hasMore
          ? 'Found ${scrapedPortals.length} portals (more available)'
          : 'Found ${scrapedPortals.length} portals';
    } catch (e) {
      scrapeError = e.toString();
      scrapeStatus = 'Scrape failed';
    } finally {
      scraping = false;
      notifyListeners();
    }
  }

  Future<void> verifyScraped({int target = 5}) async {
    if (verifying || scrapedPortals.isEmpty) return;
    verifying = true;
    scrapeStatus = 'Verifying portals…';
    notifyListeners();

    try {
      final existingKeys = verifiedPortals.map((p) => p.credKey).toSet();
      final toVerify = scrapedPortals
          .where((p) => !existingKeys.contains(p.credKey))
          .toList();

      final added = await IptvVerifier.verifyUntil(
        portals: toVerify,
        target: target,
        onProgress: (checked, total, alive) {
          scrapeStatus = 'Verified $alive working ($checked/$total checked)';
          notifyListeners();
        },
      );

      verifiedPortals = [...verifiedPortals, ...added];
      await IptvStore.save(verifiedPortals);
      scrapeStatus = '${verifiedPortals.length} portals ready';
    } finally {
      verifying = false;
      notifyListeners();
    }
  }

  void closePortal() {
    activePortal = null;
    categories = [];
    streams = [];
    notifyListeners();
  }

  Future<void> openPortal(VerifiedPortal portal) async {
    activePortal = portal;
    activeSection = IptvSection.live;
    selectedCategoryId = '';
    browserFavorites = await IptvBrowserFavoritesStore.load(portal.key);
    await _loadBrowseData();
  }

  Future<void> selectCategory(String categoryId) async {
    selectedCategoryId = categoryId;
    await _loadBrowseData();
  }

  Future<void> _loadBrowseData() async {
    final portal = activePortal;
    if (portal == null) return;
    loadingBrowse = true;
    notifyListeners();

    categories = await IptvClient.categories(portal.portal, activeSection);
    streams = await IptvClient.streams(
      portal.portal,
      activeSection,
      selectedCategoryId,
    );

    loadingBrowse = false;
    notifyListeners();
  }

  Future<void> toggleBrowserFavorite(IptvStream stream) async {
    final portal = activePortal;
    if (portal == null) return;
    if (browserFavorites.contains(stream.streamId)) {
      browserFavorites.remove(stream.streamId);
    } else {
      browserFavorites.add(stream.streamId);
    }
    await IptvBrowserFavoritesStore.save(portal.key, browserFavorites);
    notifyListeners();
  }

  bool isBrowserFavorite(IptvStream stream) =>
      browserFavorites.contains(stream.streamId);
}
