import 'dart:async';
import 'package:flutter/foundation.dart';
import '../../models/music/music_track.dart';
import 'deezer_api_client.dart';
import 'lyrics_service.dart';
import 'qobuz_music_service.dart';
import 'youtube_stream_resolver.dart';

enum MusicAudioSource { flac, youtube }

class MusicStreamResult {
  final String url;
  final String? userAgent;
  final String format;
  final String quality;
  final bool isLossless;

  const MusicStreamResult({
    required this.url,
    this.userAgent,
    this.format = 'flac',
    this.quality = 'FLAC Hi-Res',
    this.isLossless = true,
  });
}

class MusicService {
  static final MusicService instance = MusicService._internal();
  MusicService._internal();

  final DeezerApiClient _deezer = DeezerApiClient.instance;
  final QobuzMusicService _qobuz = QobuzMusicService.instance;
  final YoutubeStreamResolver _streamResolver = YoutubeStreamResolver.instance;
  final LyricsService _lyricsService = LyricsService.instance;

  Future<MusicSearchData> searchFull(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return MusicSearchData.empty;

    try {
      final tracksFuture = _deezer.searchTracks(trimmed, limit: 30);
      final artistsFuture = _deezer.searchArtists(trimmed, limit: 15);
      final albumsFuture = _deezer.searchAlbums(trimmed, limit: 15);
      final playlistsFuture = _deezer.searchPlaylists(trimmed, limit: 15);

      final results = await Future.wait([
        tracksFuture,
        artistsFuture,
        albumsFuture,
        playlistsFuture,
      ]);

      return MusicSearchData(
        tracks: results[0] as List<MusicTrack>,
        artists: results[1] as List<MusicArtist>,
        albums: results[2] as List<MusicAlbum>,
        playlists: results[3] as List<MusicPlaylist>,
      );
    } catch (e) {
      debugPrint('searchFull error: $e');
      return MusicSearchData.empty;
    }
  }

  Future<List<MusicTrack>> searchTracks(String query) async {
    return _deezer.searchTracks(query);
  }

  Future<List<MusicArtist>> fetchTrendingArtists() async {
    try {
      final artists = await _deezer.getChartArtists(limit: 20);
      if (artists.isNotEmpty) return artists;
    } catch (e) {
      debugPrint('fetchTrendingArtists error: $e');
    }
    return [];
  }

  Future<List<MusicAlbum>> fetchNewReleases() async {
    try {
      final albums = await _deezer.getNewReleases(limit: 20);
      if (albums.isNotEmpty) return albums;
      return await _deezer.getChartAlbums(limit: 20);
    } catch (e) {
      debugPrint('fetchNewReleases error: $e');
      return [];
    }
  }

  Future<List<MusicPlaylist>> fetchCuratedPlaylists() async {
    try {
      final playlists = await _deezer.getChartPlaylists(limit: 20);
      if (playlists.isNotEmpty) return playlists;
      return await _deezer.getEditorialSelection(limit: 20);
    } catch (e) {
      debugPrint('fetchCuratedPlaylists error: $e');
      return [];
    }
  }

  Future<Map<String, List<MusicTrack>>> fetchFeaturedSections() async {
    final results = <String, List<MusicTrack>>{};

    try {
      // 1. Chart Top Tracks
      final chartTracks = await _deezer.getChartTracks(limit: 25);
      if (chartTracks.isNotEmpty) {
        results['🔥 Top Global & Trending Hits'] = chartTracks;
      }

      // 2. Genre / Mood Searches
      final queries = {
        '🌟 Pop Essentials': 'Top Pop Hits',
        '🎙️ Hip-Hop & Rap Heavyweights': 'Hip Hop Hits',
        '🎧 Electronic, Dance & EDM': 'Electronic Dance',
        '🎸 Rock Classics & Alternative': 'Rock Essentials',
        '🎬 Film & Anime Soundtracks': 'Hans Zimmer Soundtracks',
        '🌙 Chill, Lofi & Ambient Beats': 'Lofi Beats Chill',
      };

      for (final entry in queries.entries) {
        final tracks = await _deezer.searchTracks(entry.value, limit: 15);
        if (tracks.isNotEmpty) {
          results[entry.key] = tracks;
        }
      }
    } catch (e) {
      debugPrint('fetchFeaturedSections error: $e');
    }

    return results;
  }

  Future<MusicArtistDetails?> fetchArtistDetails(String artistId) async {
    return _deezer.getArtistDetails(artistId);
  }

  Future<MusicAlbumDetails?> fetchAlbumDetails(String albumId) async {
    return _deezer.getAlbumDetails(albumId);
  }

  Future<MusicPlaylistDetails?> fetchPlaylistDetails(String playlistId) async {
    return _deezer.getPlaylistDetails(playlistId);
  }

  Future<List<MusicGenre>> fetchGenres() async {
    return _deezer.getGenres();
  }

  Future<List<MusicTrack>> fetchGenreTracks(String genreName) async {
    return _deezer.searchTracks('$genreName Top Hits', limit: 25);
  }

  Future<MusicStreamResult?> getAudioStream(
    MusicTrack track, {
    MusicAudioSource source = MusicAudioSource.flac,
  }) async {
    if (source == MusicAudioSource.flac) {
      try {
        final flac = await _qobuz.resolveLosslessUrl(track);
        if (flac != null && flac.url.isNotEmpty) {
          return MusicStreamResult(
            url: flac.url,
            userAgent: flac.headers['User-Agent'],
            format: flac.format,
            quality: flac.quality,
            isLossless: true,
          );
        }
      } catch (e) {
        debugPrint('Qobuz FLAC error, falling back to YouTube: $e');
      }
    }

    // YouTube Audio Stream (Primary or Fallback)
    final yt = await _streamResolver.resolveUrl(track);
    if (yt != null && yt.url.isNotEmpty) {
      return MusicStreamResult(
        url: yt.url,
        userAgent: yt.userAgent,
        format: 'm4a',
        quality: 'YouTube HQ',
        isLossless: false,
      );
    }

    return null;
  }

  Future<LyricsData> fetchLyrics(MusicTrack track) async {
    return _lyricsService.getLyrics(track);
  }
}
