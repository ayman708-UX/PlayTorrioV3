import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../models/music/music_track.dart';
import 'music_download_service.dart';
import 'music_library_service.dart';
import 'music_service.dart';
import 'youtube_stream_http.dart';

enum MusicRepeatMode { off, all, one }

class MusicPlayerController extends ChangeNotifier {
  static final MusicPlayerController instance = MusicPlayerController._internal();
  MusicPlayerController._internal() {
    _initSettings();
  }

  Player? _player;
  final List<StreamSubscription> _subscriptions = [];
  int _loadGeneration = 0;

  MusicTrack? _currentTrack;
  List<MusicTrack> _playlist = [];
  List<MusicTrack> _originalPlaylist = [];
  int _currentIndex = 0;

  bool _isLoading = false;
  bool _isPlaying = false;
  String? _errorMessage;

  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  double _volume = 1.0;
  bool _isShuffle = false;
  MusicRepeatMode _repeatMode = MusicRepeatMode.off;

  MusicAudioSource _audioSource = MusicAudioSource.flac;
  String _currentQualityLabel = 'FLAC Hi-Res';
  bool _isCurrentTrackLossless = true;

  LyricsData _currentLyrics = LyricsData.empty();
  bool _isLoadingLyrics = false;
  int _activeLyricIndex = -1;

  // Getters
  MusicTrack? get currentTrack => _currentTrack;
  List<MusicTrack> get playlist => _playlist;
  int get currentIndex => _currentIndex;
  bool get isLoading => _isLoading;
  bool get isPlaying => _isPlaying;
  String? get errorMessage => _errorMessage;
  Duration get position => _position;
  Duration get duration => _duration;
  double get volume => _volume;
  bool get isShuffle => _isShuffle;
  MusicRepeatMode get repeatMode => _repeatMode;
  bool get hasTrack => _currentTrack != null;
  bool get hasNext => _playlist.isNotEmpty && (_repeatMode != MusicRepeatMode.off || _currentIndex < _playlist.length - 1);
  bool get hasPrevious => _playlist.isNotEmpty && (_currentIndex > 0 || _position.inSeconds > 3);
  LyricsData get currentLyrics => _currentLyrics;
  bool get isLoadingLyrics => _isLoadingLyrics;
  int get activeLyricIndex => _activeLyricIndex;
  MusicAudioSource get audioSource => _audioSource;
  String get currentQualityLabel => _currentQualityLabel;
  bool get isCurrentTrackLossless => _isCurrentTrackLossless;

  Future<void> _initSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString('music_audio_source');
      if (saved == 'youtube') {
        _audioSource = MusicAudioSource.youtube;
        _currentQualityLabel = 'YouTube HQ';
        _isCurrentTrackLossless = false;
      } else {
        _audioSource = MusicAudioSource.flac;
        _currentQualityLabel = 'FLAC Hi-Res';
        _isCurrentTrackLossless = true;
      }
      notifyListeners();
    } catch (_) {}
  }

  Future<void> setAudioSource(MusicAudioSource source) async {
    if (_audioSource == source) return;
    _audioSource = source;
    _currentQualityLabel = source == MusicAudioSource.flac ? 'FLAC Hi-Res' : 'YouTube HQ';
    _isCurrentTrackLossless = source == MusicAudioSource.flac;
    notifyListeners();

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('music_audio_source', source == MusicAudioSource.flac ? 'flac' : 'youtube');
    } catch (_) {}

    // If a track is currently loaded/playing, reload it seamlessly with new source at current position
    if (_currentTrack != null) {
      final currentPos = _position;
      await _loadAndPlayTrack(_currentTrack!, startPosition: currentPos);
    }
  }

  Future<void> playTrack(
    MusicTrack track, {
    List<MusicTrack>? playlistQueue,
  }) async {
    if (playlistQueue != null && playlistQueue.isNotEmpty) {
      _originalPlaylist = List<MusicTrack>.from(playlistQueue);
      if (_isShuffle) {
        final rest = List<MusicTrack>.from(playlistQueue)..removeWhere((t) => t.id == track.id);
        rest.shuffle(Random());
        _playlist = [track, ...rest];
        _currentIndex = 0;
      } else {
        _playlist = List<MusicTrack>.from(playlistQueue);
        _currentIndex = _playlist.indexWhere((t) => t.id == track.id);
        if (_currentIndex < 0) {
          _playlist.insert(0, track);
          _currentIndex = 0;
        }
      }
    } else {
      if (!_playlist.any((t) => t.id == track.id)) {
        _playlist.add(track);
        _originalPlaylist.add(track);
      }
      _currentIndex = _playlist.indexWhere((t) => t.id == track.id);
    }

    await _loadAndPlayTrack(track);
  }

  Future<void> _loadAndPlayTrack(MusicTrack track, {Duration? startPosition}) async {
    final int myGeneration = ++_loadGeneration;
    _currentTrack = track;
    _isLoading = true;
    _errorMessage = null;
    _position = startPosition ?? Duration.zero;
    _duration = track.durationSeconds > 0
        ? Duration(seconds: track.durationSeconds)
        : Duration.zero;
    _currentLyrics = LyricsData.empty();
    _activeLyricIndex = -1;
    notifyListeners();

    // Add to recent history
    MusicLibraryService.instance.addToRecent(track);

    // Fetch lyrics asynchronously
    _fetchLyricsForTrack(track);

    // Dispose previous controller
    for (final s in _subscriptions) {
      s.cancel();
    }
    _subscriptions.clear();

    if (_player != null) {
      await _player!.dispose();
      _player = null;
    }

    if (myGeneration != _loadGeneration) return;

    try {
      final downloadedTrack = MusicDownloadService.instance.getDownloadedTrack(track.id);
      final downloadedFile = downloadedTrack != null ? File(downloadedTrack.localAudioPath) : null;
      final isOffline = downloadedFile != null && downloadedFile.existsSync() && downloadedFile.lengthSync() > 100;

      final player = Player();
      final Media media;

      if (isOffline && downloadedTrack != null) {
        _currentQualityLabel = downloadedTrack.quality.contains('FLAC')
            ? 'FLAC Lossless (Offline)'
            : 'HQ Audio (Offline)';
        _isCurrentTrackLossless = downloadedTrack.format.toLowerCase() == 'flac';
        media = Media(downloadedFile.uri.toString());
      } else {
        final streamResult = await MusicService.instance.getAudioStream(
          track,
          source: _audioSource,
        );
        if (streamResult == null || streamResult.url.isEmpty) {
          throw Exception('Failed to extract audio stream');
        }

        _currentQualityLabel = streamResult.quality;
        _isCurrentTrackLossless = streamResult.isLossless;

        final uri = Uri.parse(streamResult.url);
        final headers = streamResult.isLossless
            ? (streamResult.userAgent != null ? {'User-Agent': streamResult.userAgent!} : <String, String>{})
            : YoutubeStreamHttp.streamHeaders(
                streamResult.url,
                userAgent: streamResult.userAgent,
              );

        media = Media(
          uri.toString(),
          httpHeaders: headers,
        );
      }

      if (myGeneration != _loadGeneration) {
        await player.dispose();
        return;
      }

      // Held locally (not in the shared `_subscriptions` field) until this
      // call is confirmed to still be the current one -- otherwise a
      // superseded call's cleanup could cancel a newer call's subscriptions
      // out from under it.
      final localSubs = [
        player.stream.playing.listen((playing) {
          _isPlaying = playing;
          notifyListeners();
        }),
        player.stream.position.listen((pos) {
          _position = pos;
          _updateActiveLyricIndex();
          notifyListeners();
        }),
        player.stream.duration.listen((dur) {
          if (dur > Duration.zero) {
            _duration = dur;
            _isLoading = false;
            notifyListeners();
          }
        }),
        player.stream.completed.listen((completed) {
          if (completed) {
            _onTrackEnded();
          }
        }),
        player.stream.error.listen((err) {
          _isLoading = false;
          _isPlaying = false;
          _errorMessage = 'Could not load audio: $err';
          debugPrint('Playback error for ${track.title}: $err');
          notifyListeners();
        }),
      ];

      await player.open(media);
      await player.setVolume(_volume * 100.0);

      if (startPosition != null && startPosition > Duration.zero) {
        await player.seek(startPosition);
      }

      if (myGeneration != _loadGeneration) {
        for (final s in localSubs) {
          s.cancel();
        }
        await player.dispose();
        return;
      }

      _subscriptions.addAll(localSubs);
      _player = player;
      _isLoading = false;
      _isPlaying = true;
      notifyListeners();
    } catch (e) {
      if (myGeneration != _loadGeneration) return;
      _isLoading = false;
      _isPlaying = false;
      _errorMessage = 'Could not load audio: ${e.toString()}';
      debugPrint('Playback error for ${track.title}: $e');
      notifyListeners();
    }
  }

  Future<void> _fetchLyricsForTrack(MusicTrack track) async {
    _isLoadingLyrics = true;
    notifyListeners();
    try {
      final lyrics = await MusicService.instance.fetchLyrics(track);
      if (_currentTrack?.id == track.id) {
        _currentLyrics = lyrics;
        _isLoadingLyrics = false;
        _updateActiveLyricIndex();
        notifyListeners();
      }
    } catch (_) {
      if (_currentTrack?.id == track.id) {
        _isLoadingLyrics = false;
        notifyListeners();
      }
    }
  }

  void _updateActiveLyricIndex() {
    if (_currentLyrics.isSynced && _currentLyrics.syncedLines.isNotEmpty) {
      final newIndex = _currentLyrics.activeLineIndex(_position);
      if (newIndex != _activeLyricIndex) {
        _activeLyricIndex = newIndex;
        notifyListeners();
      }
    }
  }

  void _onTrackEnded() {
    if (_repeatMode == MusicRepeatMode.one && _currentTrack != null) {
      seekTo(Duration.zero);
      play();
    } else if (hasNext) {
      playNext();
    } else if (_repeatMode == MusicRepeatMode.all && _playlist.isNotEmpty) {
      _currentIndex = 0;
      _loadAndPlayTrack(_playlist[0]);
    } else {
      _isPlaying = false;
      notifyListeners();
    }
  }

  Future<void> play() async {
    if (_player != null) {
      await _player!.play();
      _isPlaying = true;
      notifyListeners();
    } else if (_currentTrack != null) {
      await _loadAndPlayTrack(_currentTrack!);
    }
  }

  Future<void> pause() async {
    if (_player != null) {
      await _player!.pause();
      _isPlaying = false;
      notifyListeners();
    }
  }

  Future<void> togglePlayPause() async {
    if (_isPlaying) {
      await pause();
    } else {
      await play();
    }
  }

  Future<void> seekTo(Duration position) async {
    if (_player != null) {
      await _player!.seek(position);
      _position = position;
      _updateActiveLyricIndex();
      notifyListeners();
    }
  }

  Future<void> setVolume(double volume) async {
    _volume = volume.clamp(0.0, 1.0);
    if (_player != null) {
      await _player!.setVolume(_volume * 100.0);
    }
    notifyListeners();
  }

  void toggleShuffle() {
    _isShuffle = !_isShuffle;
    if (_isShuffle) {
      if (_currentTrack != null) {
        final rest = List<MusicTrack>.from(_originalPlaylist)..removeWhere((t) => t.id == _currentTrack!.id);
        rest.shuffle(Random());
        _playlist = [_currentTrack!, ...rest];
        _currentIndex = 0;
      } else {
        _playlist.shuffle(Random());
      }
    } else {
      _playlist = List<MusicTrack>.from(_originalPlaylist);
      if (_currentTrack != null) {
        _currentIndex = _playlist.indexWhere((t) => t.id == _currentTrack!.id);
        if (_currentIndex < 0) _currentIndex = 0;
      }
    }
    notifyListeners();
  }

  void toggleRepeat() {
    switch (_repeatMode) {
      case MusicRepeatMode.off:
        _repeatMode = MusicRepeatMode.all;
        break;
      case MusicRepeatMode.all:
        _repeatMode = MusicRepeatMode.one;
        break;
      case MusicRepeatMode.one:
        _repeatMode = MusicRepeatMode.off;
        break;
    }
    notifyListeners();
  }

  Future<void> playNext() async {
    if (_playlist.isEmpty) return;

    if (_currentIndex < _playlist.length - 1) {
      _currentIndex++;
      await _loadAndPlayTrack(_playlist[_currentIndex]);
    } else if (_repeatMode == MusicRepeatMode.all) {
      _currentIndex = 0;
      await _loadAndPlayTrack(_playlist[0]);
    }
  }

  Future<void> playPrevious() async {
    if (_playlist.isEmpty) return;

    if (_position.inSeconds > 3) {
      await seekTo(Duration.zero);
      return;
    }

    if (_currentIndex > 0) {
      _currentIndex--;
      await _loadAndPlayTrack(_playlist[_currentIndex]);
    } else {
      await seekTo(Duration.zero);
    }
  }

  void removeFromQueue(int index) {
    if (index >= 0 && index < _playlist.length) {
      _playlist.removeAt(index);
      if (index < _currentIndex) {
        _currentIndex--;
      }
      notifyListeners();
    }
  }

  void clearQueue() {
    _playlist.clear();
    _currentIndex = 0;
    notifyListeners();
  }

  @override
  void dispose() {
    for (final s in _subscriptions) {
      s.cancel();
    }
    _subscriptions.clear();
    _player?.dispose();
    super.dispose();
  }
}
