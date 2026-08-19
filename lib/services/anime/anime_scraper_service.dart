import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../../models/anime/anime_media.dart';
import '../../models/movie/movie_detail.dart';
import '../../models/movie/video.dart';
import '../../models/stream/stream_model.dart';

class AnimeScraperService {
  static final AnimeScraperService instance = AnimeScraperService._internal();
  AnimeScraperService._internal();

  /// Scrape all stream sources for an Anime and Episode across all providers concurrently.
  Stream<StreamSource> scrapeStreamsStream({
    required AnimeMedia anime,
    required int episodeNumber,
  }) async* {
    final controller = StreamController<StreamSource>();

    final tasks = <Future>[
      _scrapeMiruro(anime, episodeNumber, false, controller),
      _scrapeMiruro(anime, episodeNumber, true, controller),
      _scrapeGogoanime(anime, episodeNumber, false, controller),
      _scrapeGogoanime(anime, episodeNumber, true, controller),
      _scrapeZoro(anime, episodeNumber, false, controller),
      _scrapeZoro(anime, episodeNumber, true, controller),
    ];

    Future.wait(tasks).whenComplete(() {
      if (!controller.isClosed) {
        controller.close();
      }
    });

    yield* controller.stream;
  }

  // ───────────────────────────────────────────────────────────────────────────
  // Miruro Provider Scraper
  // ───────────────────────────────────────────────────────────────────────────

  Future<void> _scrapeMiruro(
    AnimeMedia anime,
    int episodeNumber,
    bool isDub,
    StreamController<StreamSource> controller,
  ) async {
    try {
      final sources = await _fetchMiruroSources(anime, episodeNumber, isDub);
      for (final s in sources) {
        if (!controller.isClosed) controller.add(s);
      }
    } catch (_) {}
  }

  Future<List<StreamSource>> _fetchMiruroSources(
    AnimeMedia anime,
    int episodeNumber,
    bool isDub,
  ) async {
    final list = <StreamSource>[];
    try {
      final uri = Uri.parse(
          'https://api.miruro.online/anime/info/${anime.id}?dub=$isDub');
      final res = await http.get(uri, headers: {
        'User-Agent':
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/133.0.0.0 Safari/537.36',
        'Accept': 'application/json',
      }).timeout(const Duration(seconds: 6));

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        final episodes = data['episodes'] as List?;
        if (episodes != null && episodes.isNotEmpty) {
          final ep = episodes.firstWhere(
            (e) => (e['number'] as int? ?? 0) == episodeNumber,
            orElse: () => episodes.first,
          );
          final epId = ep['id']?.toString() ?? '$episodeNumber';

          final watchUri = Uri.parse(
              'https://api.miruro.online/anime/watch/$epId?dub=$isDub');
          final watchRes = await http.get(watchUri, headers: {
            'User-Agent':
                'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/133.0.0.0 Safari/537.36',
            'Accept': 'application/json',
          }).timeout(const Duration(seconds: 6));

          if (watchRes.statusCode == 200) {
            final watchData = jsonDecode(watchRes.body) as Map<String, dynamic>;
            final sources = watchData['sources'] as List?;
            final dubTag = isDub ? 'Dub' : 'Sub';

            if (sources != null) {
              for (final s in sources) {
                if (s is Map<String, dynamic>) {
                  final url = s['url']?.toString() ?? '';
                  final quality = s['quality']?.toString() ?? 'auto';
                  if (url.isNotEmpty) {
                    list.add(
                      StreamSource(
                        name: '⚡ Miruro • $quality ($dubTag)',
                        title:
                            '${anime.displayTitle} - EP $episodeNumber [$quality]',
                        description:
                            'Miruro Ultra Fast HLS • ${isDub ? "English Dub" : "Japanese Sub"} • $quality',
                        url: url,
                        addonName: 'Miruro Anime',
                        headers: {
                          'Referer': 'https://miruro.to/',
                          'Origin': 'https://miruro.to',
                          'User-Agent':
                              'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/133.0.0.0 Safari/537.36',
                        },
                        behaviorHints: {
                          'notWebReady': false,
                          'proxyHeaders': {
                            'request': {'Referer': 'https://miruro.to/'}
                          },
                        },
                      ),
                    );
                  }
                }
              }
            }
          }
        }
      }
    } catch (_) {}
    return list;
  }

  // ───────────────────────────────────────────────────────────────────────────
  // Gogoanime Provider Scraper
  // ───────────────────────────────────────────────────────────────────────────

  Future<void> _scrapeGogoanime(
    AnimeMedia anime,
    int episodeNumber,
    bool isDub,
    StreamController<StreamSource> controller,
  ) async {
    try {
      final sources = await _fetchGogoSources(anime, episodeNumber, isDub);
      for (final s in sources) {
        if (!controller.isClosed) controller.add(s);
      }
    } catch (_) {}
  }

  Future<List<StreamSource>> _fetchGogoSources(
    AnimeMedia anime,
    int episodeNumber,
    bool isDub,
  ) async {
    final list = <StreamSource>[];
    try {
      final cleanTitle = _cleanTitle(anime.displayTitle);
      final searchUri = Uri.parse(
          'https://consumet.api.amvstr.me/anime/gogoanime/$cleanTitle');
      final searchRes = await http.get(searchUri, headers: {
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64)',
      }).timeout(const Duration(seconds: 6));

      if (searchRes.statusCode == 200) {
        final searchData = jsonDecode(searchRes.body) as Map<String, dynamic>;
        final results = searchData['results'] as List?;
        if (results != null && results.isNotEmpty) {
          final target = results.firstWhere(
            (r) =>
                isDub ? (r['id']?.toString().contains('-dub') ?? false) : true,
            orElse: () => results.first,
          );

          final gogoId = target['id']?.toString() ?? '';
          final episodeId = '$gogoId-episode-$episodeNumber';

          final watchUri = Uri.parse(
              'https://consumet.api.amvstr.me/anime/gogoanime/watch/$episodeId');
          final watchRes = await http.get(watchUri, headers: {
            'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64)',
          }).timeout(const Duration(seconds: 6));

          if (watchRes.statusCode == 200) {
            final watchData = jsonDecode(watchRes.body) as Map<String, dynamic>;
            final sources = watchData['sources'] as List?;
            final dubTag = isDub ? 'Dub' : 'Sub';

            if (sources != null) {
              for (final s in sources) {
                if (s is Map<String, dynamic>) {
                  final url = s['url']?.toString() ?? '';
                  final quality = s['quality']?.toString() ?? 'default';
                  if (url.isNotEmpty) {
                    list.add(
                      StreamSource(
                        name: '📺 Gogoanime • $quality ($dubTag)',
                        title:
                            '${anime.displayTitle} - EP $episodeNumber [$quality]',
                        description:
                            'Gogoanime Server • ${isDub ? "English Dub" : "Japanese Sub"} • $quality',
                        url: url,
                        addonName: 'Gogoanime',
                        headers: {
                          'Referer': 'https://anitaku.to/',
                          'User-Agent':
                              'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/133.0.0.0 Safari/537.36',
                        },
                      ),
                    );
                  }
                }
              }
            }
          }
        }
      }
    } catch (_) {}
    return list;
  }

  // ───────────────────────────────────────────────────────────────────────────
  // Zoro / HiAnime Provider Scraper
  // ───────────────────────────────────────────────────────────────────────────

  Future<void> _scrapeZoro(
    AnimeMedia anime,
    int episodeNumber,
    bool isDub,
    StreamController<StreamSource> controller,
  ) async {
    try {
      final sources = await _fetchZoroSources(anime, episodeNumber, isDub);
      for (final s in sources) {
        if (!controller.isClosed) controller.add(s);
      }
    } catch (_) {}
  }

  Future<List<StreamSource>> _fetchZoroSources(
    AnimeMedia anime,
    int episodeNumber,
    bool isDub,
  ) async {
    final list = <StreamSource>[];
    try {
      final cleanTitle = _cleanTitle(anime.displayTitle);
      final searchUri =
          Uri.parse('https://consumet.api.amvstr.me/anime/zoro/$cleanTitle');
      final searchRes = await http.get(searchUri, headers: {
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64)',
      }).timeout(const Duration(seconds: 6));

      if (searchRes.statusCode == 200) {
        final searchData = jsonDecode(searchRes.body) as Map<String, dynamic>;
        final results = searchData['results'] as List?;
        if (results != null && results.isNotEmpty) {
          final zoroId = results.first['id']?.toString() ?? '';
          final watchUri = Uri.parse(
              'https://consumet.api.amvstr.me/anime/zoro/watch?episodeId=$zoroId\$episode\$$episodeNumber&server=vidcloud');

          final watchRes = await http.get(watchUri, headers: {
            'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64)',
          }).timeout(const Duration(seconds: 6));

          if (watchRes.statusCode == 200) {
            final watchData = jsonDecode(watchRes.body) as Map<String, dynamic>;
            final sources = watchData['sources'] as List?;
            final dubTag = isDub ? 'Dub' : 'Sub';

            if (sources != null) {
              for (final s in sources) {
                if (s is Map<String, dynamic>) {
                  final url = s['url']?.toString() ?? '';
                  final quality = s['quality']?.toString() ?? 'auto';
                  if (url.isNotEmpty) {
                    list.add(
                      StreamSource(
                        name: '✨ HiAnime • $quality ($dubTag)',
                        title:
                            '${anime.displayTitle} - EP $episodeNumber [$quality]',
                        description:
                            'HiAnime Cloud HLS • ${isDub ? "English Dub" : "Japanese Sub"} • $quality',
                        url: url,
                        addonName: 'HiAnime',
                        headers: {
                          'Referer': 'https://hianime.to/',
                          'User-Agent':
                              'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/133.0.0.0 Safari/537.36',
                        },
                      ),
                    );
                  }
                }
              }
            }
          }
        }
      }
    } catch (_) {}
    return list;
  }

  static String _cleanTitle(String title) {
    return title
        .replaceAll(RegExp(r'\([^)]*\)'), '')
        .replaceAll(RegExp(r'\[[^\]]*\]'), '')
        .replaceAll(RegExp(r'[^a-zA-Z0-9\s]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim()
        .replaceAll(' ', '-');
  }

  /// Converts AnimeMedia and Episode to MovieDetail and Video for the existing PlayerScreen
  static MovieDetail toMovieDetail(AnimeMedia anime) {
    return MovieDetail(
      id: 'anilist:${anime.id}',
      type: 'anime',
      name: anime.displayTitle,
      poster: anime.coverUrl,
      background: anime.backdropUrl,
      description: anime.description,
      year: anime.seasonYear > 0 ? '${anime.seasonYear}' : null,
      imdbRating: anime.averageScore > 0 ? anime.formattedScore : null,
      genres: anime.genres,
      videos: List.generate(
        anime.totalEpisodes > 0 ? anime.totalEpisodes : 24,
        (i) => Video(
          id: 'anilist:${anime.id}:${i + 1}',
          season: 1,
          episode: i + 1,
          title: 'Episode ${i + 1}',
          thumbnail: anime.backdropUrl,
        ),
      ),
    );
  }

  static Video toVideo(AnimeMedia anime, int episodeNumber) {
    return Video(
      id: 'anilist:${anime.id}:$episodeNumber',
      season: 1,
      episode: episodeNumber,
      title: 'Episode $episodeNumber',
      thumbnail: anime.backdropUrl,
    );
  }
}
