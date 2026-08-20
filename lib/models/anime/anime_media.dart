class AnimeMedia {
  final int id; // AniList ID
  final int? idMal; // MyAnimeList ID
  final String titleRomaji;
  final String titleEnglish;
  final String titleNative;
  final String titleUserPreferred;
  final String coverImageExtraLarge;
  final String coverImageLarge;
  final String coverImageMedium;
  final String? coverColor;
  final String bannerImage;
  final String format; // TV, MOVIE, OVA, ONA, SPECIAL
  final String status; // RELEASING, FINISHED, NOT_YET_RELEASED, CANCELLED, HIATUS
  final int totalEpisodes;
  final int durationMinutes;
  final List<String> genres;
  final int averageScore; // e.g. 84 for 8.4/10
  final int meanScore;
  final int popularity;
  final int favourites;
  final String season; // WINTER, SPRING, SUMMER, FALL
  final int seasonYear;
  final String description;
  final String studioName;
  final String? trailerUrl;
  final String? trailerSite;
  final AnimeNextAiring? nextAiring;
  final List<AnimeCharacter> characters;
  final List<AnimeRelation> relations;
  final List<AnimeMedia> recommendations;

  const AnimeMedia({
    required this.id,
    this.idMal,
    this.titleRomaji = '',
    this.titleEnglish = '',
    this.titleNative = '',
    this.titleUserPreferred = '',
    this.coverImageExtraLarge = '',
    this.coverImageLarge = '',
    this.coverImageMedium = '',
    this.coverColor,
    this.bannerImage = '',
    this.format = 'TV',
    this.status = 'FINISHED',
    this.totalEpisodes = 0,
    this.durationMinutes = 24,
    this.genres = const [],
    this.averageScore = 0,
    this.meanScore = 0,
    this.popularity = 0,
    this.favourites = 0,
    this.season = '',
    this.seasonYear = 0,
    this.description = '',
    this.studioName = '',
    this.trailerUrl,
    this.trailerSite,
    this.nextAiring,
    this.characters = const [],
    this.relations = const [],
    this.recommendations = const [],
  });

  String get displayTitle {
    if (titleEnglish.isNotEmpty) return titleEnglish;
    if (titleUserPreferred.isNotEmpty) return titleUserPreferred;
    if (titleRomaji.isNotEmpty) return titleRomaji;
    return titleNative;
  }

  String get coverUrl {
    if (coverImageExtraLarge.isNotEmpty) return coverImageExtraLarge;
    if (coverImageLarge.isNotEmpty) return coverImageLarge;
    if (coverImageMedium.isNotEmpty) return coverImageMedium;
    return '';
  }

  String get backdropUrl {
    if (bannerImage.isNotEmpty) return bannerImage;
    return coverUrl;
  }

  String get formattedScore {
    if (averageScore <= 0) return 'N/A';
    return (averageScore / 10.0).toStringAsFixed(1);
  }

  String get formattedFormat {
    switch (format.toUpperCase()) {
      case 'TV':
        return 'TV Series';
      case 'TV_SHORT':
        return 'TV Short';
      case 'MOVIE':
        return 'Movie';
      case 'SPECIAL':
        return 'Special';
      case 'OVA':
        return 'OVA';
      case 'ONA':
        return 'ONA';
      default:
        return format;
    }
  }

  String get formattedStatus {
    switch (status.toUpperCase()) {
      case 'RELEASING':
        return 'Airing';
      case 'FINISHED':
        return 'Completed';
      case 'NOT_YET_RELEASED':
        return 'Upcoming';
      case 'CANCELLED':
        return 'Cancelled';
      case 'HIATUS':
        return 'On Hiatus';
      default:
        return status;
    }
  }

  String get formattedSeasonYear {
    if (season.isEmpty && seasonYear == 0) return '';
    final s = season.isNotEmpty
        ? '${season[0].toUpperCase()}${season.substring(1).toLowerCase()}'
        : '';
    if (seasonYear > 0) {
      return s.isNotEmpty ? '$s $seasonYear' : '$seasonYear';
    }
    return s;
  }

  factory AnimeMedia.fromAnilistJson(Map<String, dynamic> json) {
    final title = json['title'] is Map<String, dynamic>
        ? json['title'] as Map<String, dynamic>
        : {};
    final cover = json['coverImage'] is Map<String, dynamic>
        ? json['coverImage'] as Map<String, dynamic>
        : {};
    final studioNodes = json['studios'] is Map<String, dynamic> &&
            json['studios']['nodes'] is List
        ? (json['studios']['nodes'] as List)
        : [];
    String studio = '';
    if (studioNodes.isNotEmpty && studioNodes.first is Map) {
      studio = studioNodes.first['name']?.toString() ?? '';
    }

    final trailerData = json['trailer'] is Map<String, dynamic>
        ? json['trailer'] as Map<String, dynamic>
        : null;

    final nextAiringData = json['nextAiringEpisode'] is Map<String, dynamic>
        ? json['nextAiringEpisode'] as Map<String, dynamic>
        : null;

    final characterList = <AnimeCharacter>[];
    if (json['characters'] is Map<String, dynamic> &&
        json['characters']['nodes'] is List) {
      for (final c in json['characters']['nodes'] as List) {
        if (c is Map<String, dynamic>) {
          characterList.add(AnimeCharacter.fromJson(c));
        }
      }
    }

    final relationList = <AnimeRelation>[];
    if (json['relations'] is Map<String, dynamic> &&
        json['relations']['edges'] is List) {
      for (final edge in json['relations']['edges'] as List) {
        if (edge is Map<String, dynamic> &&
            edge['node'] is Map<String, dynamic>) {
          relationList.add(AnimeRelation.fromEdgeJson(edge));
        }
      }
    }

    final recList = <AnimeMedia>[];
    if (json['recommendations'] is Map<String, dynamic> &&
        json['recommendations']['nodes'] is List) {
      for (final rec in json['recommendations']['nodes'] as List) {
        if (rec is Map<String, dynamic> &&
            rec['mediaRecommendation'] is Map<String, dynamic>) {
          recList.add(AnimeMedia.fromAnilistJson(
              rec['mediaRecommendation'] as Map<String, dynamic>));
        }
      }
    }

    String rawDesc = json['description']?.toString() ?? '';
    // Strip HTML tags if any remain
    rawDesc = rawDesc.replaceAll(RegExp(r'<[^>]*>|&[^;]+;'), ' ').trim();

    return AnimeMedia(
      id: json['id'] as int? ?? 0,
      idMal: json['idMal'] as int?,
      titleRomaji: title['romaji']?.toString() ?? '',
      titleEnglish: title['english']?.toString() ?? '',
      titleNative: title['native']?.toString() ?? '',
      titleUserPreferred: title['userPreferred']?.toString() ?? '',
      coverImageExtraLarge: cover['extraLarge']?.toString() ?? '',
      coverImageLarge: cover['large']?.toString() ?? '',
      coverImageMedium: cover['medium']?.toString() ?? '',
      coverColor: cover['color']?.toString(),
      bannerImage: json['bannerImage']?.toString() ?? '',
      format: json['format']?.toString() ?? 'TV',
      status: json['status']?.toString() ?? 'FINISHED',
      totalEpisodes: json['episodes'] as int? ?? 0,
      durationMinutes: json['duration'] as int? ?? 24,
      genres: json['genres'] is List
          ? (json['genres'] as List).map((g) => g.toString()).toList()
          : const [],
      averageScore: json['averageScore'] as int? ?? 0,
      meanScore: json['meanScore'] as int? ?? 0,
      popularity: json['popularity'] as int? ?? 0,
      favourites: json['favourites'] as int? ?? 0,
      season: json['season']?.toString() ?? '',
      seasonYear: json['seasonYear'] as int? ?? 0,
      description: rawDesc,
      studioName: studio,
      trailerUrl: trailerData != null && trailerData['site'] == 'youtube'
          ? trailerData['id']?.toString()
          : null,
      trailerSite: trailerData?['site']?.toString(),
      nextAiring: nextAiringData != null
          ? AnimeNextAiring.fromJson(nextAiringData)
          : null,
      characters: characterList,
      relations: relationList,
      recommendations: recList,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'idMal': idMal,
        'titleRomaji': titleRomaji,
        'titleEnglish': titleEnglish,
        'titleNative': titleNative,
        'titleUserPreferred': titleUserPreferred,
        'coverImageExtraLarge': coverImageExtraLarge,
        'coverImageLarge': coverImageLarge,
        'coverImageMedium': coverImageMedium,
        'coverColor': coverColor,
        'bannerImage': bannerImage,
        'format': format,
        'status': status,
        'totalEpisodes': totalEpisodes,
        'durationMinutes': durationMinutes,
        'genres': genres,
        'averageScore': averageScore,
        'meanScore': meanScore,
        'popularity': popularity,
        'favourites': favourites,
        'season': season,
        'seasonYear': seasonYear,
        'description': description,
        'studioName': studioName,
      };

  factory AnimeMedia.fromJson(Map<String, dynamic> json) => AnimeMedia(
        id: json['id'] as int? ?? 0,
        idMal: json['idMal'] as int?,
        titleRomaji: json['titleRomaji']?.toString() ?? '',
        titleEnglish: json['titleEnglish']?.toString() ?? '',
        titleNative: json['titleNative']?.toString() ?? '',
        titleUserPreferred: json['titleUserPreferred']?.toString() ?? '',
        coverImageExtraLarge: json['coverImageExtraLarge']?.toString() ?? '',
        coverImageLarge: json['coverImageLarge']?.toString() ?? '',
        coverImageMedium: json['coverImageMedium']?.toString() ?? '',
        coverColor: json['coverColor']?.toString(),
        bannerImage: json['bannerImage']?.toString() ?? '',
        format: json['format']?.toString() ?? 'TV',
        status: json['status']?.toString() ?? 'FINISHED',
        totalEpisodes: json['totalEpisodes'] as int? ?? 0,
        durationMinutes: json['durationMinutes'] as int? ?? 24,
        genres: json['genres'] is List
            ? (json['genres'] as List).map((e) => e.toString()).toList()
            : const [],
        averageScore: json['averageScore'] as int? ?? 0,
        meanScore: json['meanScore'] as int? ?? 0,
        popularity: json['popularity'] as int? ?? 0,
        favourites: json['favourites'] as int? ?? 0,
        season: json['season']?.toString() ?? '',
        seasonYear: json['seasonYear'] as int? ?? 0,
        description: json['description']?.toString() ?? '',
        studioName: json['studioName']?.toString() ?? '',
      );
}

class AnimeNextAiring {
  final int episode;
  final int timeUntilAiringSeconds;
  final int airingAtTimestamp;

  const AnimeNextAiring({
    required this.episode,
    required this.timeUntilAiringSeconds,
    required this.airingAtTimestamp,
  });

  factory AnimeNextAiring.fromJson(Map<String, dynamic> json) =>
      AnimeNextAiring(
        episode: json['episode'] as int? ?? 1,
        timeUntilAiringSeconds: json['timeUntilAiring'] as int? ?? 0,
        airingAtTimestamp: json['airingAt'] as int? ?? 0,
      );

  String get formattedTimeRemaining {
    if (timeUntilAiringSeconds <= 0) return 'Airing soon';
    final days = timeUntilAiringSeconds ~/ 86400;
    final hours = (timeUntilAiringSeconds % 86400) ~/ 3600;
    final mins = (timeUntilAiringSeconds % 3600) ~/ 60;
    if (days > 0) return '${days}d ${hours}h';
    if (hours > 0) return '${hours}h ${mins}m';
    return '${mins}m';
  }
}

class AnimeCharacter {
  final int id;
  final String nameFull;
  final String nameNative;
  final String imageLarge;
  final String role;

  const AnimeCharacter({
    required this.id,
    required this.nameFull,
    this.nameNative = '',
    required this.imageLarge,
    this.role = '',
  });

  factory AnimeCharacter.fromJson(Map<String, dynamic> json) {
    final name = json['name'] is Map<String, dynamic>
        ? json['name'] as Map<String, dynamic>
        : {};
    final image = json['image'] is Map<String, dynamic>
        ? json['image'] as Map<String, dynamic>
        : {};
    return AnimeCharacter(
      id: json['id'] as int? ?? 0,
      nameFull: name['userPreferred']?.toString() ??
          name['full']?.toString() ??
          'Unknown',
      nameNative: name['native']?.toString() ?? '',
      imageLarge: image['large']?.toString() ??
          image['medium']?.toString() ??
          '',
      role: json['role']?.toString() ?? '',
    );
  }
}

class AnimeRelation {
  final String relationType; // ADAPTATION, PREQUEL, SEQUEL, SIDE_STORY, SPIN_OFF
  final int id;
  final String title;
  final String format;
  final String status;
  final String coverUrl;

  const AnimeRelation({
    required this.relationType,
    required this.id,
    required this.title,
    required this.format,
    required this.status,
    required this.coverUrl,
  });

  factory AnimeRelation.fromEdgeJson(Map<String, dynamic> json) {
    final node = json['node'] as Map<String, dynamic>;
    final titleObj = node['title'] is Map<String, dynamic>
        ? node['title'] as Map<String, dynamic>
        : {};
    final cover = node['coverImage'] is Map<String, dynamic>
        ? node['coverImage'] as Map<String, dynamic>
        : {};

    return AnimeRelation(
      relationType: json['relationType']?.toString() ?? 'RELATED',
      id: node['id'] as int? ?? 0,
      title: titleObj['english']?.toString() ??
          titleObj['userPreferred']?.toString() ??
          titleObj['romaji']?.toString() ??
          '',
      format: node['format']?.toString() ?? '',
      status: node['status']?.toString() ?? '',
      coverUrl: cover['large']?.toString() ?? cover['medium']?.toString() ?? '',
    );
  }
}

class AnimeEpisode {
  final int number;
  final String title;
  final String thumbnail;
  final String description;
  final bool isFiller;

  const AnimeEpisode({
    required this.number,
    this.title = '',
    this.thumbnail = '',
    this.description = '',
    this.isFiller = false,
  });

  String get displayTitle {
    if (title.isNotEmpty && title != 'Episode $number') {
      return 'EP $number: $title';
    }
    return 'Episode $number';
  }
}

class AnimeStreamSubtitle {
  final String url;
  final String lang;
  final String label;

  const AnimeStreamSubtitle({
    required this.url,
    required this.lang,
    required this.label,
  });
}

class AnimeStreamQuality {
  final String quality; // '1080p', '720p', '480p', '360p', 'auto', 'default'
  final String url;
  final bool isM3U8;

  const AnimeStreamQuality({
    required this.quality,
    required this.url,
    this.isM3U8 = true,
  });
}

class AnimeStreamResult {
  final String streamUrl; // Main playlist or direct stream
  final bool isM3U8;
  final List<AnimeStreamQuality> qualities;
  final List<AnimeStreamSubtitle> subtitles;
  final Map<String, String> headers;
  final String serverName;
  final bool isDub;
  final int? introStart;
  final int? introEnd;
  final int? outroStart;
  final int? outroEnd;

  const AnimeStreamResult({
    required this.streamUrl,
    this.isM3U8 = true,
    this.qualities = const [],
    this.subtitles = const [],
    this.headers = const {},
    this.serverName = 'Miruro',
    this.isDub = false,
    this.introStart,
    this.introEnd,
    this.outroStart,
    this.outroEnd,
  });
}

enum AnimeWatchStatus {
  watching,
  planToWatch,
  completed,
  dropped,
}

class AnimeWatchlistItem {
  final AnimeMedia anime;
  final AnimeWatchStatus status;
  final int lastWatchedEpisode;
  final int lastWatchedPositionSeconds;
  final int totalDurationSeconds;
  final DateTime updatedAt;

  const AnimeWatchlistItem({
    required this.anime,
    required this.status,
    this.lastWatchedEpisode = 0,
    this.lastWatchedPositionSeconds = 0,
    this.totalDurationSeconds = 0,
    required this.updatedAt,
  });

  double get watchProgress {
    if (totalDurationSeconds <= 0) return 0.0;
    return (lastWatchedPositionSeconds / totalDurationSeconds).clamp(0.0, 1.0);
  }

  Map<String, dynamic> toJson() => {
        'anime': anime.toJson(),
        'status': status.name,
        'lastWatchedEpisode': lastWatchedEpisode,
        'lastWatchedPositionSeconds': lastWatchedPositionSeconds,
        'totalDurationSeconds': totalDurationSeconds,
        'updatedAt': updatedAt.toIso8601String(),
      };

  factory AnimeWatchlistItem.fromJson(Map<String, dynamic> json) =>
      AnimeWatchlistItem(
        anime: AnimeMedia.fromJson(json['anime'] as Map<String, dynamic>),
        status: AnimeWatchStatus.values.firstWhere(
          (s) => s.name == json['status'],
          orElse: () => AnimeWatchStatus.watching,
        ),
        lastWatchedEpisode: json['lastWatchedEpisode'] as int? ?? 0,
        lastWatchedPositionSeconds:
            json['lastWatchedPositionSeconds'] as int? ?? 0,
        totalDurationSeconds: json['totalDurationSeconds'] as int? ?? 0,
        updatedAt: DateTime.tryParse(json['updatedAt']?.toString() ?? '') ??
            DateTime.now(),
      );
}
