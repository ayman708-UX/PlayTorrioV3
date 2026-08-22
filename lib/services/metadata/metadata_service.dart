import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../models/addon/addon.dart';
import '../../models/movie/movie.dart';
import '../../models/movie/movie_detail.dart';

/// Generic service for any Stremio-protocol addon.
/// All methods are static — provide the addon's base URL and they hit the
/// standard Stremio endpoints (catalog, meta, search).
class MetadataService {
  MetadataService._();

  static final Map<String, List<Movie>> _catalogCache = {};
  static final Map<String, MovieDetail> _metaCache = {};

  /// Clear the memory cache (e.g. when addons change)
  static void clearCache() {
    _catalogCache.clear();
    _metaCache.clear();
  }

  // ── Manifest ──────────────────────────────────────────────────────────

  /// Fetch and parse a manifest from any Stremio addon.
  static Future<AddonManifest> fetchManifest(String baseUrl) async {
    final url = '$baseUrl/manifest.json';
    final response = await http.get(
      Uri.parse(url),
      headers: {'Accept': 'application/json'},
    );

    if (response.statusCode != 200) {
      throw Exception(
        'Failed to fetch manifest (${response.statusCode})',
      );
    }

    final json = jsonDecode(response.body) as Map<String, dynamic>;
    return AddonManifest.fromJson(json);
  }

  // ── Catalog ───────────────────────────────────────────────────────────

  /// Fetch catalog items from any addon.
  static Future<List<Movie>> fetchCatalog({
    required String baseUrl,
    required String type,
    required String catalogId,
    String? genre,
    int? skip,
  }) async {
    final effectiveBaseUrl = (baseUrl.trim().isEmpty || !baseUrl.startsWith('http'))
        ? 'https://v3-cinemeta.strem.io'
        : (baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl);

    final extra = <String>[];
    if (genre != null) {
      extra.add('genre=${Uri.encodeComponent(genre)}');
    }
    if (skip != null && skip > 0) {
      extra.add('skip=$skip');
    }

    final extraPath = extra.isNotEmpty ? '/${extra.join("&")}' : '';
    final url = '$effectiveBaseUrl/catalog/$type/$catalogId$extraPath.json';

    if (_catalogCache.containsKey(url)) {
      return List.from(_catalogCache[url]!);
    }

    final response = await http.get(
      Uri.parse(url),
      headers: {'Accept': 'application/json'},
    );

    if (response.statusCode != 200) {
      throw Exception('Catalog fetch failed (${response.statusCode})');
    }

    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    final metas = decoded['metas'] as List<dynamic>? ?? [];

    final result = metas
        .map((item) => Movie.fromJson(
              item as Map<String, dynamic>,
              effectiveBaseUrl,
              fallbackType: type,
            ))
        .where((movie) => movie.poster != null && movie.poster!.isNotEmpty)
        .toList();

    _catalogCache[url] = result;
    return List.from(result);
  }

  // ── Search ────────────────────────────────────────────────────────────

  /// Search an addon's catalog.
  static Future<List<Movie>> search({
    required String baseUrl,
    required String type,
    required String catalogId,
    required String query,
  }) async {
    final effectiveBaseUrl = (baseUrl.trim().isEmpty || !baseUrl.startsWith('http'))
        ? 'https://v3-cinemeta.strem.io'
        : (baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl);

    final encoded = Uri.encodeComponent(query);
    final url = '$effectiveBaseUrl/catalog/$type/$catalogId/search=$encoded.json';

    // We can cache searches too!
    if (_catalogCache.containsKey(url)) {
      return List.from(_catalogCache[url]!);
    }

    final response = await http.get(Uri.parse(url));
    if (response.statusCode != 200) return [];
    
    final bodyStr = response.body.trim();
    if (bodyStr.isEmpty) return [];

    try {
      final decoded = jsonDecode(bodyStr) as Map<String, dynamic>;
      final metas = decoded['metas'] as List<dynamic>? ?? [];
      
      final result = metas
          .map((item) => Movie.fromJson(
                item as Map<String, dynamic>,
                effectiveBaseUrl,
                fallbackType: type,
              ))
          .where((movie) => movie.poster != null && movie.poster!.isNotEmpty)
          .toList();
          
      _catalogCache[url] = result;
      return List.from(result);
    } catch (e) {
      return [];
    }
  }

  // ── Meta (full details) ───────────────────────────────────────────────

  /// Fetch detailed metadata (background, description, rating, genres, etc.)
  static Future<MovieDetail?> fetchMeta({
    required String baseUrl,
    required String type,
    required String imdbId,
  }) async {
    final effectiveBaseUrl = (baseUrl.trim().isEmpty || !baseUrl.startsWith('http'))
        ? 'https://v3-cinemeta.strem.io'
        : (baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl);

    final encodedId = Uri.encodeComponent(imdbId);
    final url = '$effectiveBaseUrl/meta/$type/$encodedId.json';

    if (_metaCache.containsKey(url)) {
      return _metaCache[url];
    }

    final response = await http.get(Uri.parse(url));
    if (response.statusCode != 200) return null;
    
    final bodyStr = response.body.trim();
    if (bodyStr.isEmpty) return null;

    try {
      final decoded = jsonDecode(bodyStr) as Map<String, dynamic>;
      final meta = decoded['meta'] as Map<String, dynamic>?;

      if (meta == null) return null;
      
      final result = MovieDetail.fromJson(meta);
      _metaCache[url] = result;
      return result;
    } catch (e) {
      return null;
    }
  }
}
