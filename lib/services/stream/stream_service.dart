import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../models/addon/addon.dart';
import '../../models/stream/stream_model.dart';
import '../addon/addon_manager.dart';
import '../scraper/stream_scraper.dart';
import '../scraper/sites/knaben.dart';
import '../scraper/sites/torrent_galaxy.dart';
import '../scraper/sites/fourkhdhub.dart';
import '../scraper/sites/xdownloader.dart';
import '../scraper/sites/videasy.dart';
import '../scraper/sites/vidsrc.dart';
import '../scraper/sites/multiembed.dart';
import '../scraper/sites/vidcore.dart';
import '../scraper/sites/flystream.dart';
import '../scraper/sites/movienight.dart';
import '../scraper/sites/downloadeverything.dart';
import '../scraper/sites/movy.dart';
import '../scraper/sites/vuflix.dart';
import '../scraper/sites/rivestream.dart';


/// Service that fetches playback streams from all installed Stremio addons
/// that declare "stream" in their manifest resources.
class StreamService {
  StreamService._();

  /// Fetches streams from all active stream-capable addons for the given
  /// content type and ID.
  ///
  /// Streams are yielded progressively as each addon responds, so the UI
  /// can populate immediately instead of waiting for all addons.
  ///
  /// For series episodes, [id] should be the video ID (e.g. "tt1234567:1:2").
  static Stream<StreamSource> fetchStreams({
    required String type,
    required String id,
    required String title,
    int? year,
    int? season,
    int? episode,
  }) {
    final controller = StreamController<StreamSource>();

    final addons = AddonManager.instance.activeAddons
        .where((a) => a.manifest.supportsStream)
        .toList();

    // Register built-in scrapers
    ScraperManager.instance.registerScraper(KnabenScraper());
    ScraperManager.instance.registerScraper(TorrentGalaxyScraper());
    ScraperManager.instance.registerScraper(FourKHDHubScraper());
    ScraperManager.instance.registerScraper(XDownloaderScraper());
    ScraperManager.instance.registerScraper(VideasyScraper());
    ScraperManager.instance.registerScraper(VidSrcScraper());
    ScraperManager.instance.registerScraper(MultiEmbedScraper());
    ScraperManager.instance.registerScraper(VidCoreScraper());
    ScraperManager.instance.registerScraper(FlyStreamScraper());
    ScraperManager.instance.registerScraper(MovieNightScraper());
    ScraperManager.instance.registerScraper(DownloadEverythingScraper());
    ScraperManager.instance.registerScraper(MovyScraper());
    ScraperManager.instance.registerScraper(VuflixScraper());
    ScraperManager.instance.registerScraper(RiveStreamScraper());

    int pending = addons.length + 1; // addons + local scrapers

    // Local scrapers
    ScraperManager.instance.scrapeAll(
      type: type,
      title: title,
      year: year,
      season: season,
      episode: episode,
      imdbId: id.split(':')[0],
    ).listen((source) {
      if (!controller.isClosed) controller.add(source);
    }, onDone: () {
      pending--;
      if (pending == 0 && !controller.isClosed) controller.close();
    });


    for (final addon in addons) {
      _fetchFromAddon(addon, type, id).then((sources) {
        if (!controller.isClosed) {
          for (final source in sources) {
            controller.add(source);
          }
        }
      }).catchError((_) {}).whenComplete(() {
        pending--;
        if (pending == 0 && !controller.isClosed) {
          controller.close();
        }
      });
    }

    return controller.stream;
  }

  static Future<List<StreamSource>> _fetchFromAddon(
    InstalledAddon addon,
    String type,
    String id,
  ) async {
    try {
      // Standard IDs (tt123456, tt123456:1:2, kitsu:123) go raw in the path.
      // Only URL-based custom IDs need encoding.
      final needsEncoding = id.contains('://') || id.contains('/');
      final pathId = needsEncoding ? Uri.encodeComponent(id) : id;
      final url = '${addon.baseUrl}/stream/$type/$pathId.json';

      final response = await http.get(
        Uri.parse(url),
        headers: {
          'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
          'Accept': 'application/json',
        },
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode != 200) return [];

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final streams = data['streams'] as List<dynamic>?;

      if (streams == null || streams.isEmpty) return [];

      return streams
          .whereType<Map>()
          .map((json) => StreamSource.fromJson(Map<String, dynamic>.from(json), addon.manifest.name))
          .where((s) => s.url != null || s.infoHash != null || s.externalUrl != null)
          .toList();
    } catch (e, st) {
      debugPrint('Addon ${addon.manifest.name} failed: $e\n$st');
      return []; // Silently skip failed addons
    }
  }
}
