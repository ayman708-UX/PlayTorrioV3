import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import '../../models/music/music_track.dart';
import '../playback_coordinator.dart';
import 'music_library_service.dart';
import 'music_service.dart';
import 'youtube_stream_http.dart';

enum MusicRepeatMode { off, all, one }

class MusicPlayerController extends ChangeNotifier {
  static final MusicPlayerController instance = MusicPlayerController._internal();
  MusicPlayerController._internal();

  VideoPlayerController? _videoPlayerController;

  /// Called when the universal play bar requests expanding the full player.
  VoidCallback? _onExpandRequested;

  /// Called when the universal play bar requests opening the artist.
  VoidCallback? _onOpenArtistRequested;

  /// Lets the universal play bar open the full music player.
  void setExpandCallback(VoidCallback callback) {
    _onExpandRequested = callback;
  }

  /// Lets the universal play bar open the artist for the current track.
  void setOpenArtistCallback(VoidCallback callback) {
    _onOpenArtistRequested = callback;
  }

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

  Future<void> playTrack(
    MusicTrack track, {
    List<MusicTrack>? playlistQueue,
  }) async {
    // Ensure only one source plays app-wide: stop any other active source.
    PlaybackCoordinator.activate(
      'music:${track.id}',
      () {
        _videoPlayerController?.pause();
        _isPlaying = false;
        notifyListeners();
      },
      kind: 'music',
      title: track.title,
      subtitle: track.artist,
      coverUrl: track.coverUrl,
      onTogglePlayPause: togglePlayPause,
      onExpand: _onExpandRequested,
      onOpenArtist: _onOpenArtistRequested,
      onSeek: seekTo,
    );

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

  Future<void> _loadAndPlayTrack(MusicTrack track) async {
    _currentTrack = track;
    _isLoading = true;
    _errorMessage = null;
    _position = Duration.zero;
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
    if (_videoPlayerController != null) {
      _videoPlayerController!.removeListener(_onPlayerStateChanged);
      await _videoPlayerController!.dispose();
      _videoPlayerController = null;
    }

    try {
      final streamResult = await MusicService.instance.getAudioStream(track);
      if (streamResult == null || streamResult.url.isEmpty) {
        throw Exception('Failed to extract audio stream from YouTube');
      }

      final uri = Uri.parse(streamResult.url);
      final headers = YoutubeStreamHttp.streamHeaders(
        streamResult.url,
        userAgent: streamResult.userAgent,
      );

      final controller = VideoPlayerController.networkUrl(
        uri,
        httpHeaders: headers,
      );

      await controller.initialize();
      controller.setVolume(_volume);
      controller.addListener(_onPlayerStateChanged);

      _videoPlayerController = controller;
      if (controller.value.duration > Duration.zero) {
        _duration = controller.value.duration;
      }
      _isLoading = false;
      _isPlaying = true;
      await controller.play();
      notifyListeners();
    } catch (e) {
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

  void _onPlayerStateChanged() {
    final controller = _videoPlayerController;
    if (controller == null) return;

    final value = controller.value;
    _position = value.position;
    if (value.duration > Duration.zero) {
      _duration = value.duration;
    }
    _isPlaying = value.isPlaying;

    // Keep the universal play bar's progress bar in sync.
    PlaybackCoordinator.setProgress(_position, _duration);

    _updateActiveLyricIndex();

    // Check track completed
    if (value.isInitialized &&
        _duration > Duration.zero &&
        _position >= _duration - const Duration(milliseconds: 500) &&
        !value.isPlaying) {
      _onTrackEnded();
    } else {
      notifyListeners();
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
    if (_videoPlayerController != null) {
      await _videoPlayerController!.play();
      _isPlaying = true;
      PlaybackCoordinator.setPlaying(true);
      notifyListeners();
    } else if (_currentTrack != null) {
      await _loadAndPlayTrack(_currentTrack!);
    }
  }

  Future<void> pause() async {
    if (_videoPlayerController != null) {
      await _videoPlayerController!.pause();
      _isPlaying = false;
      PlaybackCoordinator.setPlaying(false);
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
    if (_videoPlayerController != null) {
      await _videoPlayerController!.seekTo(position);
      _position = position;
      _updateActiveLyricIndex();
      notifyListeners();
    }
  }

  Future<void> setVolume(double volume) async {
    _volume = volume.clamp(0.0, 1.0);
    if (_videoPlayerController != null) {
      await _videoPlayerController!.setVolume(_volume);
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
    if (_currentTrack != null) {
      PlaybackCoordinator.release('music:${_currentTrack!.id}');
    }
    _videoPlayerController?.removeListener(_onPlayerStateChanged);
    _videoPlayerController?.dispose();
    super.dispose();
  }
}
