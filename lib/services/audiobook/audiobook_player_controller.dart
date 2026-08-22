import 'dart:async';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../../models/audiobook/audiobook_model.dart';
import '../playback_coordinator.dart';
import '../stream/torrent_stream_service.dart';

/// A singleton controller that plays audiobooks in the **background**, so the
/// universal play bar appears instead of a fullscreen player.
///
/// Starting an audiobook from a detail page uses this controller (bottom bar
/// shows). Tapping the bottom bar opens the fullscreen player via
/// [setExpandCallback].
class AudiobookPlayerController extends ChangeNotifier {
  static final AudiobookPlayerController instance =
      AudiobookPlayerController._internal();
  AudiobookPlayerController._internal();

  VideoPlayerController? _controller;
  Audiobook? _audiobook;
  List<AudiobookChapter> _chapters = [];
  int _currentIndex = 0;
  bool _isPlaying = false;
  bool _isLoading = false;

  VoidCallback? _onExpandRequested;

  Audiobook? get audiobook => _audiobook;
  List<AudiobookChapter> get chapters => _chapters;
  int get currentIndex => _currentIndex;
  bool get isPlaying => _isPlaying;
  bool get isLoading => _isLoading;
  bool get hasAudiobook => _audiobook != null;

  void setExpandCallback(VoidCallback callback) {
    _onExpandRequested = callback;
  }

  Future<void> play(
    Audiobook audiobook,
    List<AudiobookChapter> chapters, {
    int chapterIndex = 0,
    Duration? initialPosition,
  }) async {
    _audiobook = audiobook;
    _chapters = chapters;
    _currentIndex = chapterIndex;

    PlaybackCoordinator.activate(
      'audiobook:${audiobook.uuid}:$chapterIndex',
      () {
        _controller?.pause();
        _isPlaying = false;
        notifyListeners();
      },
      kind: 'audiobook',
      title: audiobook.title,
      subtitle: chapters.isNotEmpty ? chapters[chapterIndex].title : '',
      coverUrl: audiobook.coverImage,
      onTogglePlayPause: togglePlayPause,
      onExpand: _onExpandRequested,
    );

    await _loadChapter(chapterIndex, initialPosition: initialPosition);
  }

  Future<void> _loadChapter(int index, {Duration? initialPosition}) async {
    if (index < 0 || index >= _chapters.length) return;
    _currentIndex = index;
    _isLoading = true;
    notifyListeners();

    // Clean up previous controller
    if (_controller != null) {
      _controller!.removeListener(_onPlayerStateChanged);
      await _controller!.dispose();
      _controller = null;
    }

    final chapter = _chapters[index];
    try {
      String? streamUrl;
      if (chapter.isTorrent) {
        streamUrl = await TorrentStreamService().streamTorrent(
          chapter.url,
          fileIdx: chapter.torrentFileIndex,
        );
      } else {
        streamUrl = chapter.url;
      }
      if (streamUrl == null || streamUrl.isEmpty) {
        throw Exception('Audio stream URL could not be resolved.');
      }

      final sanitized = streamUrl.contains('::')
          ? streamUrl.replaceAll('::', '%3A%3A')
          : streamUrl;
      final headers = <String, String>{
        'User-Agent':
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
      };
      if (chapter.httpHeaders != null) headers.addAll(chapter.httpHeaders!);

      final controller = VideoPlayerController.networkUrl(
        Uri.parse(sanitized),
        httpHeaders: headers,
      );
      await controller.initialize();
      controller.addListener(_onPlayerStateChanged);
      if (initialPosition != null && initialPosition > Duration.zero) {
        await controller.seekTo(initialPosition);
      }
      _controller = controller;
      _isLoading = false;
      _isPlaying = true;
      await controller.play();
      notifyListeners();
    } catch (e) {
      _isLoading = false;
      _isPlaying = false;
      debugPrint('Audiobook background playback error: $e');
      notifyListeners();
    }
  }

  void _onPlayerStateChanged() {
    final c = _controller;
    if (c == null) return;
    final playing = c.value.isPlaying;
    if (playing != _isPlaying) {
      _isPlaying = playing;
      PlaybackCoordinator.setPlaying(playing);
      notifyListeners();
    }
  }

  Future<void> togglePlayPause() async {
    if (_controller == null) return;
    if (_controller!.value.isPlaying) {
      await _controller!.pause();
    } else {
      await _controller!.play();
    }
  }

  Future<void> stop() async {
    PlaybackCoordinator.release(
      _audiobook != null ? 'audiobook:${_audiobook!.uuid}:$_currentIndex' : '',
    );
    _controller?.removeListener(_onPlayerStateChanged);
    await _controller?.dispose();
    _controller = null;
    _audiobook = null;
    _chapters = [];
    _isPlaying = false;
    _isLoading = false;
    notifyListeners();
  }

  @override
  void dispose() {
    _controller?.removeListener(_onPlayerStateChanged);
    _controller?.dispose();
    super.dispose();
  }
}
