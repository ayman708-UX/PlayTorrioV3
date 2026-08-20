import 'dart:convert';
import 'package:http/http.dart' as http;
import '../../models/anime/anime_media.dart';

class MiruroStreamResolver {
  static final MiruroStreamResolver instance = MiruroStreamResolver._internal();
  MiruroStreamResolver._internal();

  final Map<String, AnimeStreamResult> _streamCache = {};

  // Generate fallback episode list if provider API fails
  List<AnimeEpisode> generateEpisodeList(AnimeMedia anime) {
    final count = anime.totalEpisodes > 0 ? anime.totalEpisodes : 24;
    return List.generate(
      count,
      (i) => AnimeEpisode(
        number: i + 1,
        title: 'Episode ${i + 1}',
        thumbnail: anime.backdropUrl,
        description: 'Episode ${i + 1} of ${anime.displayTitle}',
      ),
    );
  }

  /// Resolve direct video stream for given anime and episode
  Future<AnimeStreamResult?> resolveStream({
    required AnimeMedia anime,
    required int episodeNumber,
    bool isDub = false,
  }) async {
    final cacheKey = '${anime.id}:$episodeNumber:$isDub';
    if (_streamCache.containsKey(cacheKey)) {
      return _streamCache[cacheKey];
    }

    AnimeStreamResult? result;

    // 1. Try Miruro / HiAnime endpoint
    result = await _fetchMiruroStream(anime, episodeNumber, isDub);

    // 2. Try Consumet / Gogoanime fallback
    result ??= await _fetchConsumetGogoStream(anime, episodeNumber, isDub);

    // 3. Try Zoro / HiAnime fallback
    result ??= await _fetchConsumetZoroStream(anime, episodeNumber, isDub);

    // 4. Fetch AniSkip intro/outro skip times if malId exists
    if (result != null && anime.idMal != null && anime.idMal! > 0) {
      final skipTimes = await _fetchSkipTimes(anime.idMal!, episodeNumber);
      if (skipTimes != null) {
        result = AnimeStreamResult(
          streamUrl: result.streamUrl,
          isM3U8: result.isM3U8,
          qualities: result.qualities,
          subtitles: result.subtitles,
          headers: result.headers,
          serverName: result.serverName,
          isDub: result.isDub,
          introStart: skipTimes['introStart'],
          introEnd: skipTimes['introEnd'],
          outroStart: skipTimes['outroStart'],
          outroEnd: skipTimes['outroEnd'],
        );
      }
    }

    if (result != null) {
      _streamCache[cacheKey] = result;
    }

    return result;
  }

  Future<AnimeStreamResult?> _fetchMiruroStream(
    AnimeMedia anime,
    int episodeNumber,
    bool isDub,
  ) async {
    try {
      final uri = Uri.parse(
          'https://api.miruro.online/anime/info/${anime.id}?dub=$isDub');

      final res = await http.get(uri, headers: {
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) Chrome/133.0.0.0 Safari/537.36',
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
          return await _fetchMiruroEpisodeSources(epId, isDub);
        }
      }
    } catch (_) {}
    return null;
  }

  Future<AnimeStreamResult?> _fetchMiruroEpisodeSources(
    String episodeId,
    bool isDub,
  ) async {
    try {
      final uri = Uri.parse(
          'https://api.miruro.online/anime/watch/$episodeId?dub=$isDub');
      final res = await http.get(uri, headers: {
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) Chrome/133.0.0.0 Safari/537.36',
        'Accept': 'application/json',
      }).timeout(const Duration(seconds: 6));

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        final sources = data['sources'] as List?;
        final tracks = data['subtitles'] as List? ?? data['tracks'] as List?;

        if (sources != null && sources.isNotEmpty) {
          final qualities = <AnimeStreamQuality>[];
          String mainUrl = '';

          for (final s in sources) {
            if (s is Map<String, dynamic>) {
              final url = s['url']?.toString() ?? '';
              final quality = s['quality']?.toString() ?? 'default';
              final isM3u8 = s['isM3U8'] as bool? ?? url.contains('.m3u8');
              if (url.isNotEmpty) {
                if (mainUrl.isEmpty) mainUrl = url;
                qualities.add(AnimeStreamQuality(
                  quality: quality,
                  url: url,
                  isM3U8: isM3u8,
                ));
              }
            }
          }

          final subtitles = <AnimeStreamSubtitle>[];
          if (tracks != null) {
            for (final t in tracks) {
              if (t is Map<String, dynamic>) {
                final subUrl = t['url']?.toString() ?? t['file']?.toString() ?? '';
                final lang = t['lang']?.toString() ?? t['label']?.toString() ?? 'English';
                if (subUrl.isNotEmpty) {
                  subtitles.add(AnimeStreamSubtitle(
                    url: subUrl,
                    lang: lang,
                    label: lang,
                  ));
                }
              }
            }
          }

          if (mainUrl.isNotEmpty) {
            return AnimeStreamResult(
              streamUrl: mainUrl,
              isM3U8: mainUrl.contains('.m3u8'),
              qualities: qualities,
              subtitles: subtitles,
              headers: {
                'Referer': 'https://miruro.to/',
                'Origin': 'https://miruro.to',
              },
              serverName: 'Miruro Fast',
              isDub: isDub,
            );
          }
        }
      }
    } catch (_) {}
    return null;
  }

  Future<AnimeStreamResult?> _fetchConsumetGogoStream(
    AnimeMedia anime,
    int episodeNumber,
    bool isDub,
  ) async {
    try {
      final cleanTitle = _cleanTitle(anime.displayTitle);
      final searchUri = Uri.parse(
          'https://consumet.api.amvstr.me/anime/gogoanime/$cleanTitle');

      final searchRes = await http.get(searchUri, headers: {
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) Chrome/133.0.0.0',
      }).timeout(const Duration(seconds: 6));

      if (searchRes.statusCode == 200) {
        final searchData = jsonDecode(searchRes.body) as Map<String, dynamic>;
        final results = searchData['results'] as List?;
        if (results != null && results.isNotEmpty) {
          // Look for matching sub/dub entry
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
            'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) Chrome/133.0.0.0',
          }).timeout(const Duration(seconds: 6));

          if (watchRes.statusCode == 200) {
            final watchData = jsonDecode(watchRes.body) as Map<String, dynamic>;
            final sources = watchData['sources'] as List?;
            if (sources != null && sources.isNotEmpty) {
              final qualities = <AnimeStreamQuality>[];
              String mainUrl = '';

              for (final s in sources) {
                if (s is Map<String, dynamic>) {
                  final url = s['url']?.toString() ?? '';
                  final quality = s['quality']?.toString() ?? 'default';
                  if (url.isNotEmpty) {
                    if (mainUrl.isEmpty || quality == 'default') {
                      mainUrl = url;
                    }
                    qualities.add(AnimeStreamQuality(
                      quality: quality,
                      url: url,
                      isM3U8: url.contains('.m3u8'),
                    ));
                  }
                }
              }

              if (mainUrl.isNotEmpty) {
                return AnimeStreamResult(
                  streamUrl: mainUrl,
                  isM3U8: mainUrl.contains('.m3u8'),
                  qualities: qualities,
                  headers: {
                    'Referer': 'https://anitaku.to/',
                    'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) Chrome/133.0.0.0',
                  },
                  serverName: 'Gogo Server',
                  isDub: isDub,
                );
              }
            }
          }
        }
      }
    } catch (_) {}
    return null;
  }

  Future<AnimeStreamResult?> _fetchConsumetZoroStream(
    AnimeMedia anime,
    int episodeNumber,
    bool isDub,
  ) async {
    try {
      final cleanTitle = _cleanTitle(anime.displayTitle);
      final searchUri = Uri.parse(
          'https://consumet.api.amvstr.me/anime/zoro/$cleanTitle');

      final searchRes = await http.get(searchUri, headers: {
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) Chrome/133.0.0.0',
      }).timeout(const Duration(seconds: 6));

      if (searchRes.statusCode == 200) {
        final searchData = jsonDecode(searchRes.body) as Map<String, dynamic>;
        final results = searchData['results'] as List?;
        if (results != null && results.isNotEmpty) {
          final zoroId = results.first['id']?.toString() ?? '';
          final watchUri = Uri.parse(
              'https://consumet.api.amvstr.me/anime/zoro/watch?episodeId=$zoroId\$episode\$$episodeNumber&server=vidcloud');

          final watchRes = await http.get(watchUri, headers: {
            'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) Chrome/133.0.0.0',
          }).timeout(const Duration(seconds: 6));

          if (watchRes.statusCode == 200) {
            final watchData = jsonDecode(watchRes.body) as Map<String, dynamic>;
            final sources = watchData['sources'] as List?;
            final subtitlesList = watchData['subtitles'] as List?;

            if (sources != null && sources.isNotEmpty) {
              final qualities = <AnimeStreamQuality>[];
              String mainUrl = '';

              for (final s in sources) {
                if (s is Map<String, dynamic>) {
                  final url = s['url']?.toString() ?? '';
                  final quality = s['quality']?.toString() ?? 'auto';
                  if (url.isNotEmpty) {
                    if (mainUrl.isEmpty) mainUrl = url;
                    qualities.add(AnimeStreamQuality(
                      quality: quality,
                      url: url,
                      isM3U8: url.contains('.m3u8'),
                    ));
                  }
                }
              }

              final subs = <AnimeStreamSubtitle>[];
              if (subtitlesList != null) {
                for (final sub in subtitlesList) {
                  if (sub is Map<String, dynamic>) {
                    final subUrl = sub['url']?.toString() ?? '';
                    final lang = sub['lang']?.toString() ?? 'English';
                    if (subUrl.isNotEmpty) {
                      subs.add(AnimeStreamSubtitle(
                        url: subUrl,
                        lang: lang,
                        label: lang,
                      ));
                    }
                  }
                }
              }

              if (mainUrl.isNotEmpty) {
                return AnimeStreamResult(
                  streamUrl: mainUrl,
                  isM3U8: mainUrl.contains('.m3u8'),
                  qualities: qualities,
                  subtitles: subs,
                  headers: {
                    'Referer': 'https://hianime.to/',
                    'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) Chrome/133.0.0.0',
                  },
                  serverName: 'HiAnime Server',
                  isDub: isDub,
                );
              }
            }
          }
        }
      }
    } catch (_) {}
    return null;
  }

  Future<Map<String, int>?> _fetchSkipTimes(int malId, int episodeNumber) async {
    try {
      final uri = Uri.parse(
          'https://api.aniskip.com/v2/skip-times/$malId/$episodeNumber?types=op&types=ed&episodeLength=0');
      final res = await http.get(uri).timeout(const Duration(seconds: 4));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        if (data['found'] == true && data['results'] is List) {
          final results = data['results'] as List;
          int? introStart, introEnd, outroStart, outroEnd;

          for (final r in results) {
            if (r is Map<String, dynamic>) {
              final type = r['skipType']?.toString().toLowerCase();
              final interval = r['interval'] as Map<String, dynamic>?;
              if (interval != null) {
                final startTime = (interval['startTime'] as num?)?.toInt();
                final endTime = (interval['endTime'] as num?)?.toInt();
                if (type == 'op' && startTime != null && endTime != null) {
                  introStart = startTime;
                  introEnd = endTime;
                } else if (type == 'ed' && startTime != null && endTime != null) {
                  outroStart = startTime;
                  outroEnd = endTime;
                }
              }
            }
          }

          return {
            if (introStart != null) 'introStart': introStart,
            if (introEnd != null) 'introEnd': introEnd,
            if (outroStart != null) 'outroStart': outroStart,
            if (outroEnd != null) 'outroEnd': outroEnd,
          };
        }
      }
    } catch (_) {}
    return null;
  }

  String _cleanTitle(String title) {
    return title
        .replaceAll(RegExp(r'\([^)]*\)'), '')
        .replaceAll(RegExp(r'\[[^\]]*\]'), '')
        .replaceAll(RegExp(r'[^a-zA-Z0-9\s]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim()
        .replaceAll(' ', '-');
  }
}
