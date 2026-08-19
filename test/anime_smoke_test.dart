import 'package:flutter_test/flutter_test.dart';
import 'package:playtorrio/models/anime/anime_media.dart';
import 'package:playtorrio/services/anime/anilist_service.dart';
import 'package:playtorrio/services/anime/anime_scraper_service.dart';

void main() {
  test('AnimeMedia AniList JSON parsing and getters', () {
    final anilistJson = {
      'id': 16498,
      'idMal': 16498,
      'title': {
        'romaji': 'Shingeki no Kyojin',
        'english': 'Attack on Titan',
        'native': '進撃の巨人',
        'userPreferred': 'Attack on Titan',
      },
      'coverImage': {
        'extraLarge': 'https://s4.anilist.co/file/anilistcdn/media/anime/cover/large/bx16498-m5BeEg6bWWAc.jpg',
        'large': 'https://s4.anilist.co/file/anilistcdn/media/anime/cover/medium/bx16498-m5BeEg6bWWAc.jpg',
        'color': '#5bbfe6',
      },
      'bannerImage': 'https://s4.anilist.co/file/anilistcdn/media/anime/banner/16498-8jpFCOcDmnei.jpg',
      'format': 'TV',
      'status': 'FINISHED',
      'episodes': 25,
      'duration': 24,
      'genres': ['Action', 'Drama', 'Fantasy', 'Mystery'],
      'averageScore': 85,
      'meanScore': 85,
      'popularity': 550000,
      'season': 'SPRING',
      'seasonYear': 2013,
      'description': 'Centuries ago, mankind was almost slaughtered to extinction...',
      'studios': {
        'nodes': [
          {'id': 858, 'name': 'WIT STUDIO'}
        ]
      }
    };

    final anime = AnimeMedia.fromAnilistJson(anilistJson);
    expect(anime.id, 16498);
    expect(anime.displayTitle, 'Attack on Titan');
    expect(anime.formattedScore, '8.5');
    expect(anime.formattedFormat, 'TV Series');
    expect(anime.formattedStatus, 'Completed');
    expect(anime.formattedSeasonYear, 'Spring 2013');
    expect(anime.studioName, 'WIT STUDIO');
    expect(anime.genres.length, 4);

    final json = anime.toJson();
    final restored = AnimeMedia.fromJson(json);
    expect(restored.id, 16498);
    expect(restored.displayTitle, 'Attack on Titan');
    expect(restored.studioName, 'WIT STUDIO');
  });

  test('AnilistService season helpers return valid values', () {
    final currentSeason = AnilistService.currentSeason();
    expect(['WINTER', 'SPRING', 'SUMMER', 'FALL'].contains(currentSeason), isTrue);

    final nextSeason = AnilistService.nextSeason();
    expect(['WINTER', 'SPRING', 'SUMMER', 'FALL'].contains(nextSeason), isTrue);

    final nextYear = AnilistService.nextSeasonYear();
    expect(nextYear >= DateTime.now().year, isTrue);
  });

  test('AnimeWatchlistItem progress calculation', () {
    const anime = AnimeMedia(
      id: 100,
      titleEnglish: 'Frieren: Beyond Journey\'s End',
      totalEpisodes: 28,
    );

    final item = AnimeWatchlistItem(
      anime: anime,
      status: AnimeWatchStatus.watching,
      lastWatchedEpisode: 12,
      lastWatchedPositionSeconds: 720,
      totalDurationSeconds: 1440,
      updatedAt: DateTime.now(),
    );

    expect(item.watchProgress, 0.5);
    expect(item.status, AnimeWatchStatus.watching);
  });

  test('AnimeScraperService bridges AnimeMedia to MovieDetail and Video for PlayerScreen', () {
    const anime = AnimeMedia(
      id: 500,
      titleEnglish: 'Solo Leveling',
      totalEpisodes: 12,
      averageScore: 88,
      seasonYear: 2024,
      genres: ['Action', 'Fantasy'],
    );

    final detail = AnimeScraperService.toMovieDetail(anime);
    expect(detail.id, 'anilist:500');
    expect(detail.name, 'Solo Leveling');
    expect(detail.type, 'anime');
    expect(detail.videos.length, 12);
    expect(detail.videos.first.episode, 1);

    final video = AnimeScraperService.toVideo(anime, 5);
    expect(video.id, 'anilist:500:5');
    expect(video.episode, 5);
    expect(video.title, 'Episode 5');
  });
}
