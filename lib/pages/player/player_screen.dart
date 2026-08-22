import 'dart:io';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';
import 'package:playtorrio/models/movie/video.dart';
import 'package:playtorrio/models/movie/movie_detail.dart';
import 'package:playtorrio/models/subtitle/subtitle_model.dart';
import 'package:playtorrio/services/subtitles/subtitle_service.dart';
import 'package:liquid_glass_easy/liquid_glass_easy.dart';

import '../../models/playback/playback_history_item.dart';
import '../../models/stream/stream_model.dart';
import '../../services/playback/playback_history_service.dart';
import '../../services/playback_coordinator.dart';
import '../../services/player_settings.dart';
import '../../services/stream/torrent_stream_service.dart';
import '../../services/trakt/trakt_sync_service.dart';
import '../../services/glass_settings.dart';
import '../../widgets/common/performance_liquid_lens.dart';
import 'package:fvp/fvp.dart';

class PlayerScreen extends StatefulWidget {
  final StreamSource source;
  final String title; // This is the torrent title, used for display
  final String? backdropUrl;
  final String? logoUrl;
  final MovieDetail? detail;
  final Video? episode;
  final VoidCallback? onNextEpisode;

  const PlayerScreen({
    super.key,
    required this.source,
    required this.title,
    this.backdropUrl,
    this.logoUrl,
    this.detail,
    this.episode,
    this.onNextEpisode,
  });

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen>
    with SingleTickerProviderStateMixin {
  VideoPlayerController? _controller;
  bool _isLoading = true;
  String _statusMessage = 'Initializing...';
  bool _showControls = true;
  bool _isHoveringUI = false;
  Timer? _hideTimer;
  DateTime? _lastPointerTimerReset;
  late AnimationController _logoAnimController;

  double _subtitleDelayMs = 0;
  double _subtitleScale = 1.0;
  String? _currentSubtitlePath;
  double _volume = 1.0;
  BoxFit _videoFit = BoxFit.contain;

  // ── Gesture state (volume / brightness swipes) ──
  double _brightness = 1.0;
  bool _showGestureIndicator = false;
  String _gestureIndicatorLabel = '';
  double _gestureIndicatorValue = 0.0;
  IconData _gestureIndicatorIcon = Icons.volume_up_rounded;
  Timer? _gestureIndicatorTimer;
  Offset? _gestureStartPosition;
  double _gestureStartVolume = 1.0;
  double _gestureStartBrightness = 1.0;

  // ── Auto-next episode state ──
  bool _autoNextShown = false;
  bool _autoNextDialogVisible = false;
  int _autoNextCountdown = 10;
  Timer? _autoNextTimer;

  // ── Accessibility / keyboard focus ──
  final FocusNode _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _logoAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);
    _initStream();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusNode.requestFocus();
    });
  }

  Future<void> _initStream() async {
    String? streamUrl;

    // Ensure only one source plays app-wide: stop any other active source.
    final sourceId = 'video:${widget.episode?.id ?? widget.detail?.id ?? widget.source.url}';
    PlaybackCoordinator.activate(
      sourceId,
      () {
        _controller?.pause();
      },
      kind: 'video',
      title: widget.title,
      subtitle: widget.episode?.title ?? widget.detail?.name,
      coverUrl: widget.backdropUrl,
      onTogglePlayPause: () {
        if (_controller == null) return;
        if (_controller!.value.isPlaying) {
          _controller!.pause();
        } else {
          _controller!.play();
        }
      },
    );

    print('[PlayerScreen] Initializing playback:');
    print('[PlayerScreen]   Title: ${widget.title}');
    print('[PlayerScreen]   Source Name: ${widget.source.name}');
    print('[PlayerScreen]   Addon Name: ${widget.source.addonName}');
    print('[PlayerScreen]   Source Title: ${widget.source.title}');
    print('[PlayerScreen]   Raw URL: ${widget.source.url}');

    try {
      if (widget.source.url != null && widget.source.url!.isNotEmpty) {
        // Direct URL
        streamUrl = widget.source.url;
      } else if (widget.source.infoHash != null) {
        // Torrent
        setState(() => _statusMessage = 'Gathering metadata & peers...');

        String magnet = 'magnet:?xt=urn:btih:${widget.source.infoHash!}';
        if (widget.source.sources != null) {
          for (final source in widget.source.sources!) {
            if (source.startsWith('tracker:')) {
              final trackerUrl = source.replaceFirst('tracker:', '');
              magnet += '&tr=${Uri.encodeComponent(trackerUrl)}';
            }
          }
        }

        streamUrl = await TorrentStreamService().streamTorrent(
          magnet,
          fileIdx: widget.source.fileIdx,
        );
      } else {
        throw Exception('No valid stream source found.');
      }

      if (streamUrl == null) throw Exception('Stream URL is null');

      // Sanitize URL (encode raw spaces, special characters, and FFmpeg delimiter '::')
      final sanitizedUrlStr = streamUrl.contains('::')
          ? streamUrl.replaceAll('::', '%3A%3A')
          : streamUrl;
      final cleanUri = Uri.parse(sanitizedUrlStr);
      print('[PlayerScreen] Attempting to open network stream URL: $cleanUri');

      if (!mounted) return;
      setState(() => _statusMessage = 'Buffering video...');

      final playerHeaders = <String, String>{};
      if (sanitizedUrlStr.contains('hakunaymatata.com')) {
        playerHeaders['User-Agent'] = 'Lavf/60.16.100';
      } else {
        playerHeaders['User-Agent'] =
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36';
      }
      if (widget.source.headers != null) {
        playerHeaders.addAll(widget.source.headers!);
      }

      _controller = VideoPlayerController.networkUrl(
        cleanUri,
        httpHeaders: playerHeaders,
      );
      await _controller!.initialize().timeout(
        const Duration(seconds: 15),
        onTimeout: () {
          throw TimeoutException(
            'Stream connection timed out after 15 seconds. The host server may be slow or offline.',
          );
        },
      );

      print(
        '[PlayerScreen SUCCESS] Video controller initialized successfully for $streamUrl',
      );

      if (!mounted) return;
      setState(() {
        _isLoading = false;
      });

      // Resume from history if previously watched
      if (widget.detail != null) {
        final historyItem = PlaybackHistoryService.getProgress(
          widget.episode?.id ?? widget.detail!.id,
        );
        if (historyItem != null && historyItem.position.inSeconds > 10) {
          _controller!.seekTo(historyItem.position);
        }
      }

      _controller!.addListener(_onPlaybackUpdate);
      _controller!.play();
      _startHideControlsTimer();
    } catch (e, stackTrace) {
      print(
        '[PlayerScreen ERROR] Failed to initialize stream URL: "$streamUrl"',
      );
      print('[PlayerScreen ERROR] Exception: $e');
      print('[PlayerScreen ERROR] StackTrace:\n$stackTrace');

      if (!mounted) return;

      String displayMessage = 'Error: $e';
      if (e is PlatformException &&
          (e.message?.contains('invalid or unsupported media') ?? false)) {
        displayMessage =
            'Media Open Error: Stream server quota exceeded or invalid media format.\nPlease select another stream.';
      }

      setState(() {
        _statusMessage = displayMessage;
      });
    }
  }

  void _onPlaybackUpdate() {
    if (_controller == null || !_controller!.value.isInitialized) return;

    // ── Auto-next episode: detect end-of-credits ──
    if (widget.episode != null &&
        widget.onNextEpisode != null &&
        PlayerSettings.autoNextEnabled.value &&
        !_autoNextShown &&
        !_autoNextDialogVisible) {
      final pos = _controller!.value.position;
      final dur = _controller!.value.duration;
      if (dur.inSeconds > 0 &&
          pos.inSeconds >= dur.inSeconds - 15 &&
          pos.inSeconds > 0) {
        _autoNextShown = true;
        _showAutoNextDialog();
      }
    }

    if (widget.detail != null) {
      final pos = _controller!.value.position;
      final dur = _controller!.value.duration;
      if (dur.inSeconds > 0 && pos.inSeconds % 5 == 0) {
        final itemId = widget.episode?.id ?? widget.detail!.id;
        final historyItem = PlaybackHistoryItem(
          id: itemId,
          title: widget.detail!.name,
          poster: widget.detail!.poster,
          backdrop: widget.backdropUrl,
          type: widget.detail!.type,
          episodeTitle: widget.episode?.title,
          seasonNumber: widget.episode?.season,
          episodeNumber: widget.episode?.episode,
          position: pos,
          duration: dur,
          lastWatched: DateTime.now(),
        );
        PlaybackHistoryService.saveProgress(historyItem);

        // Scrobble progress to Trakt every 15s or when complete
        if (pos.inSeconds % 15 == 0 || historyItem.isCompleted) {
          final progressPercent = (pos.inMilliseconds / dur.inMilliseconds) * 100.0;
          TraktSyncService.scrobblePlayback(
            action: historyItem.isCompleted ? 'stop' : 'start',
            progressPercent: progressPercent,
            title: widget.detail!.name,
            imdbId: widget.detail!.id.startsWith('tt') ? widget.detail!.id : null,
            tmdbId: widget.detail!.tmdbId != null ? int.tryParse(widget.detail!.tmdbId!) : null,
            season: widget.episode?.season,
            episode: widget.episode?.episode,
            type: widget.detail!.type,
          );
        }
      }
    }
  }

  /// Shows a countdown dialog near the end of an episode offering to play the
  /// next episode. Auto-plays after the countdown unless the user cancels.
  void _showAutoNextDialog() {
    if (!mounted || _autoNextDialogVisible) return;
    _autoNextDialogVisible = true;
    _autoNextCountdown = 10;

    _autoNextTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() {
        _autoNextCountdown--;
      });
      if (_autoNextCountdown <= 0) {
        timer.cancel();
        _playNextEpisode();
      }
    });

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            return AlertDialog(
              backgroundColor: const Color(0xFF13151C),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24),
                side: BorderSide(
                  color: const Color(0xFF7C5CFF).withValues(alpha: 0.3),
                ),
              ),
              title: const Row(
                children: [
                  Icon(
                    Icons.skip_next_rounded,
                    color: Color(0xFF7C5CFF),
                    size: 26,
                  ),
                  SizedBox(width: 10),
                  Text(
                    'Up Next',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Playing next episode in $_autoNextCountdown seconds...',
                    style: const TextStyle(color: Colors.white70),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'S${widget.episode?.season ?? '?'}E${(widget.episode?.episode ?? 0) + 1}',
                    style: const TextStyle(
                      color: Color(0xFF7C5CFF),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    _autoNextTimer?.cancel();
                    setDialogState(() {});
                    Navigator.pop(dialogContext);
                    _autoNextDialogVisible = false;
                  },
                  child: const Text(
                    'Cancel',
                    style: TextStyle(color: Colors.white54),
                  ),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF7C5CFF),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onPressed: () {
                    _autoNextTimer?.cancel();
                    Navigator.pop(dialogContext);
                    _autoNextDialogVisible = false;
                    _playNextEpisode();
                  },
                  child: const Text(
                    'Play Next',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _playNextEpisode() {
    _autoNextTimer?.cancel();
    _autoNextDialogVisible = false;
    widget.onNextEpisode?.call();
  }

  void _startHideControlsTimer() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 3), () {
      if (mounted &&
          _controller != null &&
          _controller!.value.isPlaying &&
          !_isHoveringUI) {
        setState(() => _showControls = false);
      }
    });
  }

  void _toggleControls() {
    setState(() => _showControls = !_showControls);
    if (_showControls) _startHideControlsTimer();
  }

  /// Keyboard/remote control for the player: space = play/pause, arrows = seek,
  /// M = mute, F = cycle aspect ratio, Esc = back.
  void _handleKeyEvent(KeyEvent event) {
    if (event is! KeyDownEvent) return;
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;

    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.space) {
      setState(() {
        if (controller.value.isPlaying) {
          controller.pause();
        } else {
          controller.play();
        }
      });
      _startHideControlsTimer();
    } else if (key == LogicalKeyboardKey.arrowRight) {
      controller.seekTo(controller.value.position + const Duration(seconds: 10));
      _startHideControlsTimer();
    } else if (key == LogicalKeyboardKey.arrowLeft) {
      final pos = controller.value.position - const Duration(seconds: 10);
      controller.seekTo(pos.inSeconds < 0 ? Duration.zero : pos);
      _startHideControlsTimer();
    } else if (key == LogicalKeyboardKey.keyM) {
      setState(() {
        _volume = _volume > 0 ? 0.0 : 1.0;
      });
      VideoPlayerPlatform.instance.setVolume(
        // ignore: invalid_use_of_visible_for_testing_member
        controller.playerId,
        _volume,
      );
      _startHideControlsTimer();
    } else if (key == LogicalKeyboardKey.keyF) {
      setState(() {
        if (_videoFit == BoxFit.contain) {
          _videoFit = BoxFit.cover;
        } else if (_videoFit == BoxFit.cover) {
          _videoFit = BoxFit.fill;
        } else {
          _videoFit = BoxFit.contain;
        }
      });
      _startHideControlsTimer();
    } else if (key == LogicalKeyboardKey.escape) {
      Navigator.pop(context);
    }
  }

  void _handlePointerActivity() {
    if (_isLoading) return;
    if (!_showControls) setState(() => _showControls = true);

    final now = DateTime.now();
    if (_lastPointerTimerReset == null ||
        now.difference(_lastPointerTimerReset!) >=
            const Duration(milliseconds: 250)) {
      _lastPointerTimerReset = now;
      _startHideControlsTimer();
    }
  }

  // ── Gesture handlers: vertical swipe left = volume, right = brightness ──

  void _onVerticalDragStart(DragStartDetails details) {
    if (_isLoading || _controller == null) return;
    _gestureStartPosition = details.globalPosition;
    _gestureStartVolume = _volume;
    _gestureStartBrightness = _brightness;
    _hideTimer?.cancel();
  }

  void _onVerticalDragUpdate(DragUpdateDetails details) {
    if (_isLoading || _controller == null || _gestureStartPosition == null) {
      return;
    }
    final screenHeight = MediaQuery.sizeOf(context).height;
    if (screenHeight <= 0) return;

    final delta = details.globalPosition.dy - _gestureStartPosition!.dy;
    final normalized = (delta / screenHeight).clamp(-1.0, 1.0);

    // Left half of screen = volume, right half = brightness
    final isLeftSide =
        details.globalPosition.dx < MediaQuery.sizeOf(context).width / 2;

    if (isLeftSide) {
      final newVolume = (_gestureStartVolume - normalized).clamp(0.0, 3.0);
      _volume = newVolume;
      final controller = _controller;
      if (controller != null) {
        VideoPlayerPlatform.instance.setVolume(
          // ignore: invalid_use_of_visible_for_testing_member
          controller.playerId,
          newVolume,
        );
      }
      _updateGestureIndicator(
        label: 'Volume',
        value: newVolume / 3.0,
        icon: newVolume == 0
            ? Icons.volume_off_rounded
            : Icons.volume_up_rounded,
      );
    } else {
      final newBrightness = (_gestureStartBrightness - normalized).clamp(0.0, 1.0);
      _brightness = newBrightness;
      _updateGestureIndicator(
        label: 'Brightness',
        value: newBrightness,
        icon: Icons.brightness_6_rounded,
      );
    }
  }

  void _onVerticalDragEnd(DragEndDetails details) {
    _gestureStartPosition = null;
    _startHideControlsTimer();
  }

  void _updateGestureIndicator({
    required String label,
    required double value,
    required IconData icon,
  }) {
    _gestureIndicatorTimer?.cancel();
    setState(() {
      _showGestureIndicator = true;
      _gestureIndicatorLabel = label;
      _gestureIndicatorValue = value.clamp(0.0, 1.0);
      _gestureIndicatorIcon = icon;
    });
    _gestureIndicatorTimer = Timer(const Duration(milliseconds: 900), () {
      if (mounted) setState(() => _showGestureIndicator = false);
    });
  }

  Future<void> _loadSubtitle(SubtitleVariant variant) async {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Downloading ${variant.language} subtitle...'),
          duration: const Duration(seconds: 2),
        ),
      );
    }

    final path = await SubtitleService().downloadSubtitle(variant);
    if (path == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to download subtitle')),
        );
      }
      return;
    }

    if (_controller != null) {
      _currentSubtitlePath = path;
      if (_subtitleDelayMs != 0) {
        final newPath = await _shiftSubtitleTime(path, _subtitleDelayMs);
        _controller!.setExternalSubtitle(newPath);
      } else {
        _controller!.setExternalSubtitle(path);
      }
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${variant.language} subtitle loaded'),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  Future<String> _shiftSubtitleTime(String originalPath, double delayMs) async {
    final file = File(originalPath);
    if (!await file.exists()) return originalPath;

    final content = await file.readAsString();
    final delay = delayMs.toInt();
    if (delay == 0) return originalPath;

    final regex = RegExp(r'(\d{2}):(\d{2}):(\d{2})([,.])(\d{3})');
    final newContent = content.replaceAllMapped(regex, (match) {
      final hours = int.parse(match.group(1)!);
      final minutes = int.parse(match.group(2)!);
      final seconds = int.parse(match.group(3)!);
      final sep = match.group(4)!;
      final ms = int.parse(match.group(5)!);

      var totalMs =
          (hours * 3600000) + (minutes * 60000) + (seconds * 1000) + ms + delay;
      if (totalMs < 0) totalMs = 0;

      final newHours = (totalMs ~/ 3600000).toString().padLeft(2, '0');
      final newMinutes = ((totalMs % 3600000) ~/ 60000).toString().padLeft(
        2,
        '0',
      );
      final newSeconds = ((totalMs % 60000) ~/ 1000).toString().padLeft(2, '0');
      final newMs = (totalMs % 1000).toString().padLeft(3, '0');

      return '$newHours:$newMinutes:$newSeconds$sep$newMs';
    });

    final newPath = originalPath
        .replaceAll('.srt', '_delayed.srt')
        .replaceAll('.vtt', '_delayed.vtt');
    final newFile = File(newPath);
    await newFile.writeAsString(newContent);
    return newPath;
  }

  void _showVolumeMenu() {
    final mediaInfo = _controller?.getMediaInfo();
    final audioTracks = mediaInfo?.audio;
    final activeTracks = _controller?.getActiveAudioTracks() ?? [];
    int currentTrackIndex = activeTracks.isNotEmpty ? activeTracks.first : 0;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return _StaticGlassPanel(
              child: Container(
                padding: const EdgeInsets.all(24),
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.sizeOf(context).height * 0.7,
                ),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Volume',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 24),
                      Row(
                        children: [
                          Icon(
                            _volume == 0
                                ? Icons.volume_off_rounded
                                : (_volume > 1.0
                                      ? Icons.volume_up_rounded
                                      : Icons.volume_down_rounded),
                            color: _volume > 1.0
                                ? const Color(0xFFFF5C5C)
                                : Colors.white54,
                            size: 24,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Slider(
                              value: _volume,
                              min: 0.0,
                              max: 3.0, // 300% volume
                              divisions: 60,
                              activeColor: _volume > 1.0
                                  ? const Color(0xFFFF5C5C)
                                  : const Color(0xFF7C5CFF),
                              label: '${(_volume * 100).toInt()}%',
                              onChanged: (value) {
                                setModalState(() => _volume = value);
                              },
                              onChangeEnd: (value) {
                                final controller = _controller;
                                if (controller != null) {
                                  // fvp exposes amplification beyond video_player's 1.0 clamp through the platform layer.
                                  VideoPlayerPlatform.instance.setVolume(
                                    // ignore: invalid_use_of_visible_for_testing_member
                                    controller.playerId,
                                    value,
                                  );
                                }
                              },
                            ),
                          ),
                          Text(
                            '${(_volume * 100).toInt()}%',
                            style: TextStyle(
                              color: _volume > 1.0
                                  ? const Color(0xFFFF5C5C)
                                  : Colors.white,
                              fontWeight: _volume > 1.0
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                            ),
                          ),
                        ],
                      ),
                      if (audioTracks != null && audioTracks.length > 1) ...[
                        const SizedBox(height: 32),
                        const Text(
                          'Audio Track',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 16),
                        ...audioTracks.asMap().entries.map((entry) {
                          final i = entry.key;
                          final track = entry.value;
                          final isSelected = currentTrackIndex == i;
                          String trackName =
                              track.metadata['title'] ??
                              track.metadata['language'] ??
                              'Track ${i + 1} (${track.codec.codec})';
                          return ListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Text(
                              trackName,
                              style: TextStyle(
                                color: isSelected
                                    ? const Color(0xFF7C5CFF)
                                    : Colors.white70,
                              ),
                            ),
                            trailing: isSelected
                                ? const Icon(
                                    Icons.check_rounded,
                                    color: Color(0xFF7C5CFF),
                                  )
                                : null,
                            onTap: () {
                              _controller?.setAudioTracks([i]);
                              setModalState(() {
                                currentTrackIndex = i;
                              });
                              // Navigator.pop(context); // Optional: close menu on selection
                            },
                          );
                        }),
                      ],
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _showSubtitleSettingsMenu() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return _StaticGlassPanel(
              child: Container(
                padding: const EdgeInsets.all(24),
                height: 250,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Subtitle Settings',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 24),
                    Row(
                      children: [
                        const Icon(
                          Icons.timer_rounded,
                          color: Colors.white54,
                          size: 20,
                        ),
                        const SizedBox(width: 12),
                        const Text(
                          'Delay (ms)',
                          style: TextStyle(color: Colors.white70),
                        ),
                        Expanded(
                          child: Slider(
                            value: _subtitleDelayMs,
                            min: -5000,
                            max: 5000,
                            divisions: 100,
                            activeColor: const Color(0xFF7C5CFF),
                            label: '${_subtitleDelayMs.toInt()} ms',
                            onChanged: (value) {
                              setModalState(() => _subtitleDelayMs = value);
                            },
                            onChangeEnd: (value) async {
                              if (_currentSubtitlePath != null) {
                                final newPath = await _shiftSubtitleTime(
                                  _currentSubtitlePath!,
                                  value,
                                );
                                _controller?.setExternalSubtitle(newPath);
                              }
                            },
                          ),
                        ),
                        Text(
                          '${_subtitleDelayMs.toInt()}',
                          style: const TextStyle(color: Colors.white),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        const Icon(
                          Icons.format_size_rounded,
                          color: Colors.white54,
                          size: 20,
                        ),
                        const SizedBox(width: 12),
                        const Text(
                          'Size Scale',
                          style: TextStyle(color: Colors.white70),
                        ),
                        Expanded(
                          child: Slider(
                            value: _subtitleScale,
                            min: 0.5,
                            max: 3.0,
                            divisions: 25,
                            activeColor: const Color(0xFF7C5CFF),
                            label: '${_subtitleScale.toStringAsFixed(1)}x',
                            onChanged: (value) {
                              setModalState(() => _subtitleScale = value);
                            },
                            onChangeEnd: (value) {
                              _controller?.setProperty(
                                'subtitle.scale',
                                value.toString(),
                              );
                            },
                          ),
                        ),
                        Text(
                          '${_subtitleScale.toStringAsFixed(1)}x',
                          style: const TextStyle(color: Colors.white),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _showSubtitleMenu() {
    int? searchYear;
    if (widget.detail?.year != null && widget.detail!.year!.isNotEmpty) {
      final yMatch = RegExp(r'\b(19\d\d|20\d\d)\b').firstMatch(widget.detail!.year!);
      if (yMatch != null) {
        searchYear = int.tryParse(yMatch.group(1)!);
      }
    }

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return _StaticGlassPanel(
          child: FutureBuilder<List<SubtitleLanguageGroup>>(
            future: SubtitleService().fetchAllSubtitles(
              widget.detail?.name ?? widget.title,
              imdbId: widget.detail?.id,
              season: widget.episode?.season,
              episode: widget.episode?.episode,
              year: searchYear,
            ),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const SizedBox(
                  height: 200,
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircularProgressIndicator(color: Color(0xFF7C5CFF)),
                        SizedBox(height: 16),
                        Text(
                          'Searching for subtitles...',
                          style: TextStyle(color: Colors.white70),
                        ),
                      ],
                    ),
                  ),
                );
              }
              if (snapshot.hasError ||
                  !snapshot.hasData ||
                  snapshot.data!.isEmpty) {
                return const SizedBox(
                  height: 200,
                  child: Center(
                    child: Text(
                      'No subtitles found.',
                      style: TextStyle(color: Colors.white70),
                    ),
                  ),
                );
              }

              final groups = snapshot.data!;
              return ListView.builder(
                padding: const EdgeInsets.symmetric(vertical: 16),
                itemCount: groups.length,
                itemBuilder: (context, index) {
                  final group = groups[index];
                  return ExpansionTile(
                    collapsedIconColor: Colors.white70,
                    iconColor: const Color(0xFF7C5CFF),
                    title: Text(
                      group.language,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    children: group.variants.map((variant) {
                      return ListTile(
                        title: Text(
                          variant.title,
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 14,
                          ),
                        ),
                        subtitle: Text(
                          variant.providerName,
                          style: const TextStyle(
                            color: Colors.white38,
                            fontSize: 12,
                          ),
                        ),
                        trailing: const Icon(
                          Icons.download_rounded,
                          color: Colors.white54,
                          size: 20,
                        ),
                        onTap: () {
                          Navigator.pop(context);
                          _loadSubtitle(variant);
                        },
                      );
                    }).toList(),
                  );
                },
              );
            },
          ),
        );
      },
    );
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _gestureIndicatorTimer?.cancel();
    _autoNextTimer?.cancel();
    _focusNode.dispose();
    PlaybackCoordinator.release(
      'video:${widget.episode?.id ?? widget.detail?.id ?? widget.source.url}',
    );
    if (_controller != null) {
      _controller!.removeListener(_onPlaybackUpdate);
      _controller!.dispose();
    }
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    _logoAnimController.dispose();
    TorrentStreamService().cleanup();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return KeyboardListener(
      focusNode: _focusNode,
      onKeyEvent: _handleKeyEvent,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: MouseRegion(
          cursor: (_showControls || _isLoading)
              ? SystemMouseCursors.basic
              : SystemMouseCursors.none,
          onHover: (_) => _handlePointerActivity(),
          child: GestureDetector(
            onTap: _toggleControls,
            onVerticalDragStart: _onVerticalDragStart,
            onVerticalDragUpdate: _onVerticalDragUpdate,
            onVerticalDragEnd: _onVerticalDragEnd,
            child: Stack(
              fit: StackFit.expand,
              children: [
                _buildPlayerBody(),
                // Brightness overlay (dim the screen)
                if (_brightness < 1.0)
                  IgnorePointer(
                    child: Container(
                      color: Colors.black.withValues(
                        alpha: (1.0 - _brightness) * 0.9,
                      ),
                    ),
                  ),
                // Gesture indicator overlay
                if (_showGestureIndicator)
                  IgnorePointer(
                    child: Center(
                      child: _buildGestureIndicator(),
                    ),
                  ),
              ],
            ),
          ),
        ), // Closes MouseRegion
      ),
    );
  }

  Widget _buildGestureIndicator() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 20),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(_gestureIndicatorIcon, color: Colors.white, size: 32),
          const SizedBox(height: 10),
          Text(
            _gestureIndicatorLabel,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: 140,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: _gestureIndicatorValue,
                minHeight: 6,
                backgroundColor: Colors.white24,
                valueColor: const AlwaysStoppedAnimation(Color(0xFF7C5CFF)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// The background + video stack shared by all platforms.
  Widget _buildBackgroundStack() {
    return Stack(
      children: [
        // Loading Backdrop
        if (_isLoading && widget.backdropUrl != null)
          Positioned.fill(
            child: Opacity(
              opacity: 0.4,
              child: Image.network(widget.backdropUrl!, fit: BoxFit.cover),
            ),
          ),

        // Video Player
        Center(
          child: _isLoading
              ? Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (widget.logoUrl != null)
                      AnimatedBuilder(
                        animation: _logoAnimController,
                        builder: (context, child) {
                          final val = _logoAnimController.value;
                          return Opacity(
                            opacity: 0.3 + (val * 0.7),
                            child: Transform.scale(
                              scale: 0.95 + (val * 0.1),
                              child: child,
                            ),
                          );
                        },
                        child: Image.network(
                          widget.logoUrl!,
                          height: 100,
                          fit: BoxFit.contain,
                        ),
                      )
                    else
                      const CircularProgressIndicator(color: Color(0xFF7C5CFF)),
                    const SizedBox(height: 32),
                    Text(
                      _statusMessage,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 16,
                        letterSpacing: 1.2,
                      ),
                    ),
                  ],
                )
              : SizedBox.expand(
                  child: FittedBox(
                    fit: _videoFit,
                    child: SizedBox(
                      width: _controller!.value.size.width,
                      height: _controller!.value.size.height,
                      child: VideoPlayer(_controller!),
                    ),
                  ),
                ),
        ),
      ],
    );
  }

  /// The controls overlay shared by both mobile and desktop paths.
  Widget _buildControlsOverlay() {
    return MouseRegion(
      onEnter: (_) {
        _isHoveringUI = true;
        _hideTimer?.cancel();
      },
      onExit: (_) {
        _isHoveringUI = false;
        _startHideControlsTimer();
      },
      child: Stack(
        children: [
          // Controls Overlay
          if (!_isLoading)
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: IgnorePointer(
                ignoring: !_showControls,
                child: AnimatedOpacity(
                  opacity: _showControls ? 1.0 : 0.0,
                  duration: const Duration(milliseconds: 200),
                  child: _buildControls(),
                ),
              ),
            ),

          // Top Bar
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: IgnorePointer(
              ignoring: !_showControls && !_isLoading,
              child: AnimatedOpacity(
                opacity: _showControls || _isLoading ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 200),
                child: _buildTopBar(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPlayerBody() {
    return ValueListenableBuilder<bool>(
      valueListenable: GlassSettings.enabled,
      builder: (context, enabled, _) {
        if (enabled) {
          return LiquidGlassView(
            realTimeCapture: _showControls && !_isLoading,
            useSync: true,
            pixelRatio: 0.85,
            refreshRate: LiquidGlassRefreshRate.deviceRefreshRate,
            regionCapture: true,
            backgroundWidget: _buildBackgroundStack(),
            child: _buildControlsOverlay(),
          );
        }

        return Stack(
          fit: StackFit.expand,
          children: [
            RepaintBoundary(child: _buildBackgroundStack()),
            RepaintBoundary(child: _buildControlsOverlay()),
          ],
        );
      },
    );
  }

  Widget _buildTopBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.black.withValues(alpha: 0.8), Colors.transparent],
        ),
      ),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(
              Icons.arrow_back_rounded,
              color: Colors.white,
              size: 28,
            ),
            onPressed: () => Navigator.pop(context),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              widget.title,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildControls() {
    return Container(
      padding: const EdgeInsets.fromLTRB(32, 64, 32, 32),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [Colors.black.withValues(alpha: 0.8), Colors.transparent],
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Seek bar with timers
          _CustomProgressBar(controller: _controller!),
          const SizedBox(height: 16),

          // Buttons Row
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // Left Side: Play/Pause, Rewind, Skip
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _AnimatedLiquidButton(
                    baseSize: 64,
                    semanticLabel: _controller!.value.isPlaying
                        ? 'Pause'
                        : 'Play',
                    icon: Icon(
                      _controller!.value.isPlaying
                          ? Icons.pause_rounded
                          : Icons.play_arrow_rounded,
                      color: Colors.white,
                      size: 38,
                    ),
                    onPressed: () {
                      setState(() {
                        if (_controller!.value.isPlaying) {
                          _controller!.pause();
                        } else {
                          _controller!.play();
                        }
                      });
                      _startHideControlsTimer();
                    },
                  ),
                  const SizedBox(width: 24),
                  _AnimatedLiquidButton(
                    baseSize: 48,
                    semanticLabel: 'Rewind 10 seconds',
                    icon: const Icon(
                      Icons.replay_10_rounded,
                      color: Colors.white,
                      size: 28,
                    ),
                    onPressed: () {
                      final pos = _controller!.value.position;
                      _controller!.seekTo(pos - const Duration(seconds: 10));
                      _startHideControlsTimer();
                    },
                  ),
                  const SizedBox(width: 16),
                  _AnimatedLiquidButton(
                    baseSize: 48,
                    semanticLabel: 'Forward 10 seconds',
                    icon: const Icon(
                      Icons.forward_10_rounded,
                      color: Colors.white,
                      size: 28,
                    ),
                    onPressed: () {
                      final pos = _controller!.value.position;
                      _controller!.seekTo(pos + const Duration(seconds: 10));
                      _startHideControlsTimer();
                    },
                  ),
                ],
              ),

              // Right Side: Aspect, Subtitles, Volume, Settings
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _AnimatedLiquidButton(
                    baseSize: 48,
                    semanticLabel: 'Cycle aspect ratio',
                    icon: const Icon(
                      Icons.aspect_ratio_rounded,
                      color: Colors.white,
                      size: 24,
                    ),
                    onPressed: () {
                      setState(() {
                        if (_videoFit == BoxFit.contain) {
                          _videoFit = BoxFit.cover;
                        } else if (_videoFit == BoxFit.cover) {
                          _videoFit = BoxFit.fill;
                        } else {
                          _videoFit = BoxFit.contain;
                        }
                      });
                      _startHideControlsTimer();
                    },
                  ),
                  const SizedBox(width: 16),
                  _AnimatedLiquidButton(
                    baseSize: 48,
                    semanticLabel: 'Subtitles',
                    icon: const Icon(
                      Icons.subtitles_rounded,
                      color: Colors.white,
                      size: 24,
                    ),
                    onPressed: () {
                      _startHideControlsTimer();
                      _showSubtitleMenu();
                    },
                  ),
                  const SizedBox(width: 16),
                  _AnimatedLiquidButton(
                    baseSize: 48,
                    semanticLabel: 'Volume',
                    icon: Icon(
                      _volume == 0
                          ? Icons.volume_off_rounded
                          : (_volume > 1.0
                                ? Icons.volume_up_rounded
                                : Icons.volume_down_rounded),
                      color: _volume > 1.0
                          ? const Color(0xFFFF5C5C)
                          : Colors.white,
                      size: 24,
                    ),
                    onPressed: () {
                      _startHideControlsTimer();
                      _showVolumeMenu();
                    },
                  ),
                  const SizedBox(width: 16),
                  _AnimatedLiquidButton(
                    baseSize: 48,
                    semanticLabel: 'Player settings',
                    icon: const Icon(
                      Icons.settings_rounded,
                      color: Colors.white,
                      size: 24,
                    ),
                    onPressed: () {
                      _startHideControlsTimer();
                      _showSubtitleSettingsMenu();
                    },
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StaticGlassPanel extends StatelessWidget {
  final Widget child;

  const _StaticGlassPanel({required this.child});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        boxShadow: [
          BoxShadow(
            color: Color(0x66000000),
            blurRadius: 24,
            offset: Offset(0, -4),
          ),
        ],
      ),
      child: PerformanceLiquidLens(
        style: PerformanceGlassStyles.sheet,
        child: DecoratedBox(
          decoration: const BoxDecoration(
            border: Border(top: BorderSide(color: Color(0x24FFFFFF))),
          ),
          child: child,
        ),
      ),
    );
  }
}

class _AnimatedLiquidButton extends StatefulWidget {
  final double baseSize;
  final Widget icon;
  final VoidCallback onPressed;
  final String? semanticLabel;

  const _AnimatedLiquidButton({
    required this.baseSize,
    required this.icon,
    required this.onPressed,
    this.semanticLabel,
  });

  @override
  State<_AnimatedLiquidButton> createState() => _AnimatedLiquidButtonState();
}

class _AnimatedLiquidButtonState extends State<_AnimatedLiquidButton> {
  bool _hovered = false;
  bool _pressed = false;
  double _jellyValue = 0;

  void _setHovered(bool value) {
    setState(() {
      _hovered = value;
      _jellyValue += value ? 10 : -10;
    });
  }

  void _setPressed(bool value) {
    setState(() {
      _pressed = value;
      _jellyValue += value ? 20 : -20;
    });
  }

  Widget _buildLiquid() {
    return MouseRegion(
      onEnter: (_) => _setHovered(true),
      onExit: (_) => _setHovered(false),
      child: Listener(
        onPointerDown: (_) => _setPressed(true),
        onPointerUp: (_) => _setPressed(false),
        onPointerCancel: (_) => _setPressed(false),
        child: AnimatedScale(
          scale: _pressed ? 0.88 : (_hovered ? 1.32 : 1),
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutBack,
          child: LiquidGlassJelly(
            value: _jellyValue,
            width: widget.baseSize,
            height: widget.baseSize,
            config: const LiquidGlassJellyConfig(
              style: LiquidGlassJellyStyle.squashStretch,
              stiffness: 200,
              damping: 14,
              maxVelocity: 50,
            ),
            child: SizedBox.square(
              dimension: widget.baseSize,
              child: LiquidGlassButton.custom(
                padding: EdgeInsets.zero,
                style: const LiquidGlassStyle(
                  shape: LiquidGlassShape.squircle(
                    cornerRadius: 999,
                    clipQuality: LiquidGlassClipQuality.exact,
                    borderWidth: 1.5,
                    lightIntensity: 1.5,
                    lightColor: Color(0xEFFFFFFF),
                    lightDirection: 115,
                    borderType: OpticalBorder(
                      borderSaturation: 1.6,
                      ambientIntensity: 1.2,
                      borderSolidity: 0.2,
                      lightSpread: 0.75,
                    ),
                  ),
                  appearance: LiquidGlassAppearance(
                    color: Color(0x22FFFFFF),
                    saturation: 1.12,
                    blur: LiquidGlassBlur(sigmaX: 2, sigmaY: 2),
                  ),
                  refraction: LiquidGlassRefraction(
                    magnification: 1.055,
                    chromaticAberration: 0.0025,
                    refractionType: OpticalRefraction(
                      refraction: 1.52,
                      refractionWidth: 22,
                      depth: 0.76,
                    ),
                  ),
                ),
                onPressed: widget.onPressed,
                child: AnimatedScale(
                  scale: _pressed ? 0.82 : (_hovered ? 1.12 : 1),
                  duration: const Duration(milliseconds: 150),
                  curve: Curves.easeOutBack,
                  child: widget.icon,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildOptimized() {
    return SizedBox.square(
      dimension: widget.baseSize,
      child: Material(
        color: const Color(0xE61A1D26),
        shape: const CircleBorder(side: BorderSide(color: Color(0x2EFFFFFF))),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          customBorder: const CircleBorder(),
          hoverColor: const Color(0x1FFFFFFF),
          splashColor: const Color(0x337C5CFF),
          onTap: widget.onPressed,
          child: Center(child: widget.icon),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: Semantics(
        button: true,
        label: widget.semanticLabel,
        child: ValueListenableBuilder<bool>(
          valueListenable: GlassSettings.enabled,
          builder: (context, enabled, _) =>
              enabled ? _buildLiquid() : _buildOptimized(),
        ),
      ),
    );
  }
}

class _CustomProgressBar extends StatefulWidget {
  final VideoPlayerController controller;

  const _CustomProgressBar({required this.controller});

  @override
  State<_CustomProgressBar> createState() => _CustomProgressBarState();
}

class _CustomProgressBarState extends State<_CustomProgressBar> {
  double? _hoverX;
  bool _isDragging = false;
  Duration? _dragPosition;

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, "0");
    String twoDigitMinutes = twoDigits(duration.inMinutes.remainder(60));
    String twoDigitSeconds = twoDigits(duration.inSeconds.remainder(60));
    if (duration.inHours > 0) {
      return "${duration.inHours}:$twoDigitMinutes:$twoDigitSeconds";
    }
    return "$twoDigitMinutes:$twoDigitSeconds";
  }

  void _seekTo(double x, double width, Duration totalDuration) {
    if (width <= 0) return;
    final percent = (x / width).clamp(0.0, 1.0);
    final position = totalDuration * percent;
    widget.controller.seekTo(position);
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder(
      valueListenable: widget.controller,
      builder: (context, VideoPlayerValue value, child) {
        final duration = value.duration;
        final position = _isDragging
            ? (_dragPosition ?? value.position)
            : value.position;
        final buffered = value.buffered;

        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Row(
            children: [
              Text(
                _formatDuration(position),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final width = constraints.maxWidth;

                    return MouseRegion(
                      onHover: (event) {
                        setState(() {
                          _hoverX = event.localPosition.dx.clamp(0.0, width);
                        });
                      },
                      onExit: (event) {
                        setState(() {
                          _hoverX = null;
                        });
                      },
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onHorizontalDragStart: (details) {
                          setState(() {
                            _isDragging = true;
                            _hoverX = details.localPosition.dx.clamp(
                              0.0,
                              width,
                            );
                            _dragPosition = duration * (_hoverX! / width);
                          });
                        },
                        onHorizontalDragUpdate: (details) {
                          setState(() {
                            _hoverX = details.localPosition.dx.clamp(
                              0.0,
                              width,
                            );
                            _dragPosition = duration * (_hoverX! / width);
                          });
                        },
                        onHorizontalDragEnd: (details) {
                          if (_dragPosition != null) {
                            widget.controller.seekTo(_dragPosition!);
                          }
                          setState(() {
                            _isDragging = false;
                            _dragPosition = null;
                          });
                        },
                        onTapDown: (details) {
                          _seekTo(details.localPosition.dx, width, duration);
                        },
                        child: Stack(
                          clipBehavior: Clip.none,
                          alignment: Alignment.centerLeft,
                          children: [
                            // Invisible tap target
                            Container(
                              height: 32, // Much larger hit area
                              width: double.infinity,
                              color: Colors.transparent,
                            ),

                            // Background Bar
                            Container(
                              height: 6,
                              width: double.infinity,
                              decoration: BoxDecoration(
                                color: Colors.white24,
                                borderRadius: BorderRadius.circular(3),
                              ),
                            ),

                            // Buffered Bar(s)
                            for (final range in buffered)
                              if (duration.inMilliseconds > 0)
                                Positioned(
                                  left:
                                      (width *
                                              (range.start.inMilliseconds /
                                                  duration.inMilliseconds))
                                          .clamp(0.0, width),
                                  child: Container(
                                    height: 6,
                                    width:
                                        (width *
                                                ((range.end.inMilliseconds -
                                                        range
                                                            .start
                                                            .inMilliseconds) /
                                                    duration.inMilliseconds))
                                            .clamp(0.0, width),
                                    decoration: BoxDecoration(
                                      color: Colors.white38,
                                      borderRadius: BorderRadius.circular(3),
                                    ),
                                  ),
                                ),

                            // Played Bar
                            Container(
                              height: 6,
                              width: duration.inMilliseconds > 0
                                  ? (width *
                                            (position.inMilliseconds /
                                                duration.inMilliseconds))
                                        .clamp(0.0, width)
                                  : 0,
                              decoration: BoxDecoration(
                                color: const Color(0xFF7C5CFF),
                                borderRadius: BorderRadius.circular(3),
                              ),
                            ),

                            // Scrubber handle
                            Positioned(
                              left: duration.inMilliseconds > 0
                                  ? (width *
                                                (position.inMilliseconds /
                                                    duration.inMilliseconds))
                                            .clamp(0.0, width) -
                                        8
                                  : -8,
                              child: Container(
                                width: 16,
                                height: 16,
                                decoration: const BoxDecoration(
                                  color: Colors.white,
                                  shape: BoxShape.circle,
                                ),
                              ),
                            ),

                            // Hover Tooltip
                            if (_hoverX != null)
                              Positioned(
                                left: _hoverX! - 25,
                                bottom: 20,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.black87,
                                    borderRadius: BorderRadius.circular(4),
                                    border: Border.all(
                                      color: Colors.white24,
                                      width: 1,
                                    ),
                                  ),
                                  child: Text(
                                    _formatDuration(
                                      duration * (_hoverX! / width),
                                    ),
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(width: 16),
              Text(
                _formatDuration(duration),
                style: const TextStyle(
                  color: Colors.white54,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
