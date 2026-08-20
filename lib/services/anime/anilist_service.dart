import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../../models/anime/anime_media.dart';

class AnilistService {
  static final AnilistService instance = AnilistService._internal();
  AnilistService._internal();

  static const String _endpoint = 'https://graphql.anilist.co';

  final Map<String, dynamic> _memoryCache = {};

  static String currentSeason() {
    final month = DateTime.now().month;
    if (month >= 1 && month <= 3) return 'WINTER';
    if (month >= 4 && month <= 6) return 'SPRING';
    if (month >= 7 && month <= 9) return 'SUMMER';
    return 'FALL';
  }

  static String nextSeason() {
    final current = currentSeason();
    switch (current) {
      case 'WINTER':
        return 'SPRING';
      case 'SPRING':
        return 'SUMMER';
      case 'SUMMER':
        return 'FALL';
      case 'FALL':
        return 'WINTER';
      default:
        return 'WINTER';
    }
  }

  static int nextSeasonYear() {
    final now = DateTime.now();
    return currentSeason() == 'FALL' ? now.year + 1 : now.year;
  }

  Future<Map<String, dynamic>?> _postGraphQL(
    String query,
    Map<String, dynamic> variables,
  ) async {
    final cacheKey = '$query:${jsonEncode(variables)}';
    if (_memoryCache.containsKey(cacheKey)) {
      return _memoryCache[cacheKey] as Map<String, dynamic>?;
    }

    try {
      final res = await http.post(
        Uri.parse(_endpoint),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          'User-Agent': 'PlayTorrio/1.0.0 (Anime)',
        },
        body: jsonEncode({
          'query': query,
          'variables': variables,
        }),
      ).timeout(const Duration(seconds: 10));

      if (res.statusCode == 200) {
        final decoded = jsonDecode(res.body) as Map<String, dynamic>;
        if (decoded.containsKey('data')) {
          final data = decoded['data'] as Map<String, dynamic>;
          _memoryCache[cacheKey] = data;
          return data;
        }
      } else {
        debugPrint('AniList API error ${res.statusCode}: ${res.body}');
      }
    } catch (e) {
      debugPrint('AniList API request failed: $e');
    }
    return null;
  }

  static const String _mediaFields = '''
    id
    idMal
    title {
      romaji
      english
      native
      userPreferred
    }
    coverImage {
      extraLarge
      large
      medium
      color
    }
    bannerImage
    format
    status
    episodes
    duration
    genres
    averageScore
    meanScore
    popularity
    favourites
    season
    seasonYear
    description(asHtml: false)
    studios(isMain: true) {
      nodes {
        id
        name
      }
    }
    trailer {
      id
      site
    }
    nextAiringEpisode {
      airingAt
      timeUntilAiring
      episode
    }
  ''';

  /// Trending Anime
  Future<List<AnimeMedia>> fetchTrendingAnime({
    int page = 1,
    int perPage = 20,
  }) async {
    const query = '''
      query (\$page: Int, \$perPage: Int) {
        Page(page: \$page, perPage: \$perPage) {
          media(type: ANIME, sort: TRENDING_DESC, isAdult: false) {
            $_mediaFields
          }
        }
      }
    ''';

    final data = await _postGraphQL(query, {'page': page, 'perPage': perPage});
    return _parseMediaList(data);
  }

  /// Popular This Season
  Future<List<AnimeMedia>> fetchPopularThisSeason({
    int page = 1,
    int perPage = 20,
  }) async {
    const query = '''
      query (\$page: Int, \$perPage: Int, \$season: MediaSeason, \$seasonYear: Int) {
        Page(page: \$page, perPage: \$perPage) {
          media(type: ANIME, season: \$season, seasonYear: \$seasonYear, sort: POPULARITY_DESC, isAdult: false) {
            $_mediaFields
          }
        }
      }
    ''';

    final data = await _postGraphQL(query, {
      'page': page,
      'perPage': perPage,
      'season': currentSeason(),
      'seasonYear': DateTime.now().year,
    });
    return _parseMediaList(data);
  }

  /// Upcoming Next Season
  Future<List<AnimeMedia>> fetchUpcomingNextSeason({
    int page = 1,
    int perPage = 20,
  }) async {
    const query = '''
      query (\$page: Int, \$perPage: Int, \$season: MediaSeason, \$seasonYear: Int) {
        Page(page: \$page, perPage: \$perPage) {
          media(type: ANIME, season: \$season, seasonYear: \$seasonYear, sort: POPULARITY_DESC, isAdult: false) {
            $_mediaFields
          }
        }
      }
    ''';

    final data = await _postGraphQL(query, {
      'page': page,
      'perPage': perPage,
      'season': nextSeason(),
      'seasonYear': nextSeasonYear(),
    });
    return _parseMediaList(data);
  }

  /// All-Time Top Rated
  Future<List<AnimeMedia>> fetchTopRated({
    int page = 1,
    int perPage = 20,
  }) async {
    const query = '''
      query (\$page: Int, \$perPage: Int) {
        Page(page: \$page, perPage: \$perPage) {
          media(type: ANIME, sort: SCORE_DESC, isAdult: false) {
            $_mediaFields
          }
        }
      }
    ''';

    final data = await _postGraphQL(query, {'page': page, 'perPage': perPage});
    return _parseMediaList(data);
  }

  /// Filter By Genre
  Future<List<AnimeMedia>> fetchByGenre(
    String genre, {
    int page = 1,
    int perPage = 20,
  }) async {
    const query = '''
      query (\$page: Int, \$perPage: Int, \$genre: String) {
        Page(page: \$page, perPage: \$perPage) {
          media(type: ANIME, genre: \$genre, sort: POPULARITY_DESC, isAdult: false) {
            $_mediaFields
          }
        }
      }
    ''';

    final data = await _postGraphQL(query, {
      'page': page,
      'perPage': perPage,
      'genre': genre,
    });
    return _parseMediaList(data);
  }

  /// Search Anime
  Future<List<AnimeMedia>> searchAnime(
    String search, {
    String? genre,
    String? format,
    String? status,
    int page = 1,
    int perPage = 25,
  }) async {
    const query = '''
      query (\$page: Int, \$perPage: Int, \$search: String, \$genre: String, \$format: MediaFormat, \$status: MediaStatus) {
        Page(page: \$page, perPage: \$perPage) {
          media(type: ANIME, search: \$search, genre: \$genre, format: \$format, status: \$status, sort: [POPULARITY_DESC, SEARCH_MATCH], isAdult: false) {
            $_mediaFields
          }
        }
      }
    ''';

    final variables = <String, dynamic>{
      'page': page,
      'perPage': perPage,
      if (search.trim().isNotEmpty) 'search': search.trim(),
      if (genre != null && genre.isNotEmpty && genre != 'All') 'genre': genre,
      if (format != null && format.isNotEmpty && format != 'All')
        'format': format.toUpperCase(),
      if (status != null && status.isNotEmpty && status != 'All')
        'status': status.toUpperCase(),
    };

    final data = await _postGraphQL(query, variables);
    return _parseMediaList(data);
  }

  /// Full Anime Details (Including Voice Actors/Characters, Relations, Recommendations)
  Future<AnimeMedia?> fetchAnimeDetails(int anilistId) async {
    const query = '''
      query (\$id: Int) {
        Media(id: \$id, type: ANIME) {
          $_mediaFields
          characters(sort: ROLE, perPage: 8) {
            nodes {
              id
              name {
                full
                native
                userPreferred
              }
              image {
                large
                medium
              }
            }
          }
          relations {
            edges {
              relationType
              node {
                id
                title {
                  userPreferred
                  english
                  romaji
                }
                format
                type
                status
                coverImage {
                  large
                  medium
                }
              }
            }
          }
          recommendations(perPage: 12, sort: RATING_DESC) {
            nodes {
              mediaRecommendation {
                id
                title {
                  userPreferred
                  english
                  romaji
                }
                coverImage {
                  large
                  medium
                }
                format
                averageScore
              }
            }
          }
        }
      }
    ''';

    final data = await _postGraphQL(query, {'id': anilistId});
    if (data != null && data.containsKey('Media') && data['Media'] is Map) {
      return AnimeMedia.fromAnilistJson(data['Media'] as Map<String, dynamic>);
    }
    return null;
  }

  List<AnimeMedia> _parseMediaList(Map<String, dynamic>? data) {
    if (data == null) return [];
    final page = data['Page'];
    if (page is Map<String, dynamic> && page['media'] is List) {
      return (page['media'] as List)
          .whereType<Map<String, dynamic>>()
          .map((m) => AnimeMedia.fromAnilistJson(m))
          .toList();
    }
    return [];
  }
}
