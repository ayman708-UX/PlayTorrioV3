import 'dart:async';
import 'dart:ui';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';

import '../../models/audiobook/audiobook_model.dart';
import '../../services/audiobook/audiobook_progress_service.dart';
import '../../services/playback_coordinator.dart';
import '../../services/stream/torrent_stream_service.dart';

class AudiobookPlayerScreen extends StatefulWidget {
  final Audiobook audiobook;
  final List<AudiobookChapter> chapters;
  final int initialChapterIndex;
  final Duration? initialPosition;

  const AudiobookPlayerScreen({
    super.key,
    required this.audiobook,
    required this.chapters,
    this.initialChapterIndex = 0,
    this.initialPosition,
  });

  @override
  State<AudiobookPlayerScreen> createState() => _AudiobookPlayerScreenState();
}

class _AudiobookPlayerScreenState extends State<AudiobookPlayerScreen> with SingleTickerProviderStateMixin {
  VideoPlayerController? _controller;
  late int _currentChapterIndex;

  bool _isLoading = true;
  bool _isPlaying = false;
  bool _autoplayNext = true;
  String _statusMessage = 'Initializing chapter...';
  String? _errorMessage;

  double _volume = 1.0;
  double _playbackSpeed = 1.0;
  final List<double> _speeds = [1.0, 1.25, 1.5, 1.75, 2.0];

  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  bool _isDraggingSeekBar = false;
  double _dragValue = 0.0;

  bool _showChaptersDrawer = false;
  late AnimationController _discAnimController;
  Timer? _progressTimer;
  bool _hasRestoredPosition = false;

  @override
  void initState() {
    super.initState();
    _currentChapterIndex = widget.initialChapterIndex;
    _discAnimController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 12),
    );

    _initChapter(_currentChapterIndex);

    // Save progress every 5 seconds
    _progressTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      _saveProgress();
    });
  }

  @override
  void dispose() {
    _saveProgress();
    _progressTimer?.cancel();
    PlaybackCoordinator.release(
      'audiobook:${widget.audiobook.uuid}:$_currentChapterIndex',
    );
    _controller?.removeListener(_onPlayerStateChanged);
    _controller?.dispose();
    _discAnimController.dispose();
    TorrentStreamService().cleanup();
    super.dispose();
  }

  void _saveProgress() {
    if (_controller != null && _controller!.value.isInitialized) {
      AudiobookProgressService.instance.saveProgress(
        audiobook: widget.audiobook,
        chapters: widget.chapters,
        chapterIndex: _currentChapterIndex,
        position: _controller!.value.position,
        duration: _controller!.value.duration,
      );
    }
  }

  Future<void> _initChapter(int index) async {
    if (index < 0 || index >= widget.chapters.length) return;

    // Ensure only one source plays app-wide: stop any other active source.
    final sourceId = 'audiobook:${widget.audiobook.uuid}:$index';
    PlaybackCoordinator.activate(
      sourceId,
      () {
        _controller?.pause();
      },
      kind: 'audiobook',
      title: widget.audiobook.title,
      subtitle: widget.chapters[index].title,
      coverUrl: widget.audiobook.coverImage,
      onTogglePlayPause: () {
        if (_controller == null) return;
        if (_controller!.value.isPlaying) {
          _controller!.pause();
        } else {
          _controller!.play();
        }
      },
    );

    // Save progress before switching
    _saveProgress();

    // Clean up previous controller
    if (_controller != null) {
      _controller!.removeListener(_onPlayerStateChanged);
      await _controller!.dispose();
      _controller = null;
    }

    setState(() {
      _currentChapterIndex = index;
      _isLoading = true;
      _errorMessage = null;
      _statusMessage = 'Preparing ${widget.chapters[index].title}...';
      _position = Duration.zero;
      _duration = Duration.zero;
    });

    final chapter = widget.chapters[index];
    String? streamUrl;

    try {
      if (chapter.isTorrent) {
        setState(() => _statusMessage = 'Fetching torrent metadata & peers...');
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

      final sanitizedUrlStr = streamUrl.contains('::')
          ? streamUrl.replaceAll('::', '%3A%3A')
          : streamUrl;
      final cleanUri = Uri.parse(sanitizedUrlStr);

      final headers = <String, String>{
        'User-Agent':
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
      };
      if (chapter.httpHeaders != null) {
        headers.addAll(chapter.httpHeaders!);
      }

      final controller = VideoPlayerController.networkUrl(
        cleanUri,
        httpHeaders: headers,
      );

      await controller.initialize();
      controller.setVolume(_volume);
      controller.setPlaybackSpeed(_playbackSpeed);
      controller.addListener(_onPlayerStateChanged);

      // Auto-seek if resuming initial position
      if (!_hasRestoredPosition &&
          index == widget.initialChapterIndex &&
          widget.initialPosition != null &&
          widget.initialPosition! > Duration.zero &&
          widget.initialPosition! < controller.value.duration) {
        await controller.seekTo(widget.initialPosition!);
        _hasRestoredPosition = true;
      }

      if (!mounted) return;

      setState(() {
        _controller = controller;
        _isLoading = false;
        _duration = controller.value.duration;
      });

      controller.play();
      _discAnimController.repeat();
      setState(() => _isPlaying = true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = 'Playback Error: $e';
      });
    }
  }

  void _onPlayerStateChanged() {
    if (_controller == null || !_controller!.value.isInitialized) return;

    final val = _controller!.value;
    final isPlaying = val.isPlaying;
    final pos = val.position;
    final dur = val.duration;

    if (mounted) {
      if (!_isDraggingSeekBar) {
        setState(() {
          _position = pos;
          _duration = dur;
          _isPlaying = isPlaying;
        });
      }

      if (isPlaying && !_discAnimController.isAnimating) {
        _discAnimController.repeat();
      } else if (!isPlaying && _discAnimController.isAnimating) {
        _discAnimController.stop();
      }

      // Check chapter end for Autoplay
      if (dur > Duration.zero && pos >= dur - const Duration(milliseconds: 500)) {
        if (_autoplayNext && _currentChapterIndex < widget.chapters.length - 1) {
          _initChapter(_currentChapterIndex + 1);
        }
      }
    }
  }

  void _togglePlayPause() {
    if (_controller == null || !_controller!.value.isInitialized) return;

    if (_controller!.value.isPlaying) {
      _controller!.pause();
      _discAnimController.stop();
      setState(() => _isPlaying = false);
    } else {
      _controller!.play();
      _discAnimController.repeat();
      setState(() => _isPlaying = true);
    }
  }

  void _seekRelative(int seconds) {
    if (_controller == null || !_controller!.value.isInitialized) return;
    final target = _position + Duration(seconds: seconds);
    final clamped = target < Duration.zero
        ? Duration.zero
        : (target > _duration ? _duration : target);
    _controller!.seekTo(clamped);
  }

  void _cycleSpeed() {
    final nextIdx = (_speeds.indexOf(_playbackSpeed) + 1) % _speeds.length;
    final newSpeed = _speeds[nextIdx];
    setState(() => _playbackSpeed = newSpeed);
    _controller?.setPlaybackSpeed(newSpeed);
  }

  String _formatDuration(Duration d) {
    if (d.inHours > 0) {
      final hours = d.inHours.toString().padLeft(2, '0');
      final mins = (d.inMinutes % 60).toString().padLeft(2, '0');
      final secs = (d.inSeconds % 60).toString().padLeft(2, '0');
      return '$hours:$mins:$secs';
    }
    final mins = d.inMinutes.toString().padLeft(2, '0');
    final secs = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$mins:$secs';
  }

  @override
  Widget build(BuildContext context) {
    final hasCover = widget.audiobook.coverImage.isNotEmpty;
    final currentChapter = widget.chapters.isNotEmpty && _currentChapterIndex < widget.chapters.length
        ? widget.chapters[_currentChapterIndex]
        : null;

    return Scaffold(
      backgroundColor: const Color(0xFF080A0F),
      body: Stack(
        children: [
          // Background ambient cover blur
          if (hasCover)
            Positioned.fill(
              child: Opacity(
                opacity: 0.2,
                child: Image.network(
                  widget.audiobook.coverImage,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => const SizedBox(),
                ),
              ),
            ),
          Positioned.fill(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 60, sigmaY: 60),
              child: Container(color: Colors.black.withOpacity(0.65)),
            ),
          ),

          // Main Layout
          SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final isWide = constraints.maxWidth > 800;

                return Column(
                  children: [
                    // Top App Bar
                    _buildTopAppBar(context),

                    // Center Content
                    Expanded(
                      child: isWide
                          ? Row(
                              children: [
                                // Left Side: Vinyl / Cover Art & Title
                                Expanded(
                                  flex: 5,
                                  child: Center(
                                    child: SingleChildScrollView(
                                      child: Column(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          _buildCoverArt(hasCover),
                                          const SizedBox(height: 24),
                                          _buildTitleSection(currentChapter),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                                // Right Side: Player Controls & Inline Chapters List
                                Expanded(
                                  flex: 6,
                                  child: Padding(
                                    padding: const EdgeInsets.all(24),
                                    child: Column(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        _buildPlaybackControlsSection(),
                                        const SizedBox(height: 24),
                                        Expanded(
                                          child: _buildChaptersListView(),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            )
                          : Column(
                              children: [
                                Expanded(
                                  child: Center(
                                    child: SingleChildScrollView(
                                      child: Column(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          _buildCoverArt(hasCover),
                                          const SizedBox(height: 24),
                                          _buildTitleSection(currentChapter),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                                _buildPlaybackControlsSection(),
                              ],
                            ),
                    ),
                  ],
                );
              },
            ),
          ),

          // Mobile Chapters Drawer Overlay
          if (_showChaptersDrawer)
            Positioned.fill(
              child: GestureDetector(
                onTap: () => setState(() => _showChaptersDrawer = false),
                child: Container(
                  color: Colors.black.withOpacity(0.6),
                  child: Align(
                    alignment: Alignment.bottomCenter,
                    child: Container(
                      height: MediaQuery.of(context).size.height * 0.65,
                      decoration: const BoxDecoration(
                        color: Color(0xFF10131C),
                        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                      ),
                      child: Column(
                        children: [
                          Padding(
                            padding: const EdgeInsets.all(16),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text(
                                  'Chapters List',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.close_rounded, color: Colors.white70),
                                  onPressed: () => setState(() => _showChaptersDrawer = false),
                                ),
                              ],
                            ),
                          ),
                          Expanded(child: _buildChaptersListView()),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildTopAppBar(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: Row(
        children: [
          _PlayerIconButton(
            icon: Icons.arrow_back_ios_new_rounded,
            onTap: () => Navigator.pop(context),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.audiobook.title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Builder(
                  builder: (context) {
                    final isTorrent = widget.audiobook.source.toLowerCase().contains('audiobookbay');
                    return Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (isTorrent) ...[
                          const Icon(Icons.warning_amber_rounded, color: Color(0xFFFFB74D), size: 12),
                          const SizedBox(width: 4),
                        ],
                        Text(
                          isTorrent ? 'AUDIOBOOKBAY (TORRENT)' : widget.audiobook.source.toUpperCase(),
                          style: TextStyle(
                            color: isTorrent ? const Color(0xFFFFB74D) : const Color(0xFFA78BFA),
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
          // Autoplay Toggle Switch
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.06),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.white.withOpacity(0.08)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Autoplay',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(width: 6),
                Switch(
                  value: _autoplayNext,
                  onChanged: (val) => setState(() => _autoplayNext = val),
                  activeColor: const Color(0xFF7C5CFF),
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          // Chapters Button
          _PlayerIconButton(
            icon: Icons.format_list_bulleted_rounded,
            onTap: () => setState(() => _showChaptersDrawer = !_showChaptersDrawer),
          ),
        ],
      ),
    );
  }

  Widget _buildCoverArt(bool hasCover) {
    return AnimatedBuilder(
      animation: _discAnimController,
      builder: (context, child) {
        return Transform.rotate(
          angle: _discAnimController.value * 2 * 3.14159,
          child: child,
        );
      },
      child: Container(
        width: 220,
        height: 220,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF7C5CFF).withOpacity(_isPlaying ? 0.45 : 0.2),
              blurRadius: _isPlaying ? 30 : 16,
              spreadRadius: _isPlaying ? 4 : 1,
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(110),
          child: Stack(
            alignment: Alignment.center,
            children: [
              if (hasCover)
                Hero(
                  tag: 'audiobook-cover-${widget.audiobook.uuid.isNotEmpty ? widget.audiobook.uuid : widget.audiobook.title}',
                  child: CachedNetworkImage(
                    imageUrl: widget.audiobook.coverImage,
                    width: 220,
                    height: 220,
                    fit: BoxFit.cover,
                    errorWidget: (_, __, ___) => Container(
                      color: const Color(0xFF161A26),
                      child: const Icon(Icons.headphones_rounded, size: 64, color: Colors.white54),
                    ),
                  ),
                )
              else
                Container(
                  color: const Color(0xFF161A26),
                  child: const Icon(Icons.headphones_rounded, size: 64, color: Colors.white54),
                ),
              // Center Vinyl Ring Hole
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: const Color(0xFF080A0F),
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white.withOpacity(0.3), width: 3),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTitleSection(AudiobookChapter? currentChapter) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        children: [
          Text(
            currentChapter?.title ?? 'Chapter ${_currentChapterIndex + 1}',
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.bold,
              height: 1.3,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 8),
          Text(
            'Chapter ${_currentChapterIndex + 1} of ${widget.chapters.length}',
            style: TextStyle(
              color: Colors.white.withOpacity(0.6),
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPlaybackControlsSection() {
    if (_isLoading) {
      return Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          children: [
            const CircularProgressIndicator(color: Color(0xFF7C5CFF)),
            const SizedBox(height: 16),
            Text(
              _statusMessage,
              style: const TextStyle(color: Colors.white70, fontSize: 13),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    if (_errorMessage != null) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Text(
              _errorMessage!,
              style: const TextStyle(color: Colors.redAccent, fontSize: 14),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: () => _initChapter(_currentChapterIndex),
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF7C5CFF)),
              child: const Text('Retry Chapter'),
            ),
          ],
        ),
      );
    }

    final maxSec = _duration.inSeconds.toDouble();
    final curSec = _isDraggingSeekBar ? _dragValue : _position.inSeconds.toDouble().clamp(0.0, maxSec > 0 ? maxSec : 1.0);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      decoration: BoxDecoration(
        color: const Color(0xFF10131E).withOpacity(0.8),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Seek Slider Bar
          Row(
            children: [
              Text(
                _formatDuration(_isDraggingSeekBar ? Duration(seconds: _dragValue.toInt()) : _position),
                style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 12, fontWeight: FontWeight.bold),
              ),
              Expanded(
                child: SliderTheme(
                  data: SliderThemeData(
                    trackHeight: 4,
                    thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                    overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
                    activeTrackColor: const Color(0xFF7C5CFF),
                    inactiveTrackColor: Colors.white.withOpacity(0.12),
                    thumbColor: Colors.white,
                  ),
                  child: Slider(
                    value: curSec,
                    min: 0.0,
                    max: maxSec > 0 ? maxSec : 1.0,
                    onChangeStart: (val) {
                      setState(() {
                        _isDraggingSeekBar = true;
                        _dragValue = val;
                      });
                    },
                    onChanged: (val) {
                      setState(() {
                        _dragValue = val;
                      });
                    },
                    onChangeEnd: (val) {
                      _isDraggingSeekBar = false;
                      _controller?.seekTo(Duration(seconds: val.toInt()));
                    },
                  ),
                ),
              ),
              Text(
                _formatDuration(_duration),
                style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 12, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Control Buttons Row
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              // Speed Selector
              InkWell(
                onTap: _cycleSpeed,
                borderRadius: BorderRadius.circular(16),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Text(
                    '${_playbackSpeed}x',
                    style: const TextStyle(
                      color: Color(0xFFA78BFA),
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),

              // Prev Chapter
              _PlayerIconButton(
                icon: Icons.skip_previous_rounded,
                size: 32,
                onTap: _currentChapterIndex > 0 ? () => _initChapter(_currentChapterIndex - 1) : null,
              ),

              // Rewind 15s
              _PlayerIconButton(
                icon: Icons.replay_10_rounded,
                size: 32,
                onTap: () => _seekRelative(-15),
              ),

              // Big Play / Pause Button
              _PlayPauseButton(
                isPlaying: _isPlaying,
                onTap: _togglePlayPause,
              ),

              // Forward 15s
              _PlayerIconButton(
                icon: Icons.forward_10_rounded,
                size: 32,
                onTap: () => _seekRelative(15),
              ),

              // Next Chapter
              _PlayerIconButton(
                icon: Icons.skip_next_rounded,
                size: 32,
                onTap: _currentChapterIndex < widget.chapters.length - 1
                    ? () => _initChapter(_currentChapterIndex + 1)
                    : null,
              ),

              // Volume Popup / Toggle
              _VolumeButton(
                volume: _volume,
                onVolumeChanged: (v) {
                  setState(() => _volume = v);
                  _controller?.setVolume(v);
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildChaptersListView() {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF10131E).withOpacity(0.6),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
      ),
      child: ListView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: widget.chapters.length,
        itemBuilder: (context, index) {
          final chapter = widget.chapters[index];
          final isSelected = index == _currentChapterIndex;

          return _ChapterListItemTile(
            chapter: chapter,
            index: index,
            isSelected: isSelected,
            isPlaying: isSelected && _isPlaying,
            onTap: () {
              if (_showChaptersDrawer) {
                setState(() => _showChaptersDrawer = false);
              }
              _initChapter(index);
            },
          );
        },
      ),
    );
  }
}

class _PlayerIconButton extends StatefulWidget {
  final IconData icon;
  final double size;
  final VoidCallback? onTap;

  const _PlayerIconButton({
    required this.icon,
    this.size = 24,
    this.onTap,
  });

  @override
  State<_PlayerIconButton> createState() => _PlayerIconButtonState();
}

class _PlayerIconButtonState extends State<_PlayerIconButton> {
  bool _isHovered = false;
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null;
    final scale = _isPressed ? 0.9 : (_isHovered ? 1.12 : 1.0);

    return MouseRegion(
      cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTapDown: enabled ? (_) => setState(() => _isPressed = true) : null,
        onTapUp: enabled ? (_) => setState(() => _isPressed = false) : null,
        onTapCancel: enabled ? () => setState(() => _isPressed = false) : null,
        onTap: widget.onTap,
        child: AnimatedScale(
          scale: scale,
          duration: const Duration(milliseconds: 150),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: _isHovered && enabled
                  ? Colors.white.withOpacity(0.12)
                  : Colors.transparent,
              shape: BoxShape.circle,
            ),
            child: Icon(
              widget.icon,
              size: widget.size,
              color: enabled
                  ? (_isHovered ? const Color(0xFFA78BFA) : Colors.white)
                  : Colors.white24,
            ),
          ),
        ),
      ),
    );
  }
}

class _PlayPauseButton extends StatefulWidget {
  final bool isPlaying;
  final VoidCallback onTap;

  const _PlayPauseButton({
    required this.isPlaying,
    required this.onTap,
  });

  @override
  State<_PlayPauseButton> createState() => _PlayPauseButtonState();
}

class _PlayPauseButtonState extends State<_PlayPauseButton> {
  bool _isHovered = false;
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    final scale = _isPressed ? 0.92 : (_isHovered ? 1.08 : 1.0);

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTapDown: (_) => setState(() => _isPressed = true),
        onTapUp: (_) => setState(() => _isPressed = false),
        onTapCancel: () => setState(() => _isPressed = false),
        onTap: widget.onTap,
        child: AnimatedScale(
          scale: scale,
          duration: const Duration(milliseconds: 150),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                colors: _isHovered
                    ? [const Color(0xFF8B6CFF), const Color(0xFF48CAFF)]
                    : [const Color(0xFF7C5CFF), const Color(0xFF38BDF8)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF7C5CFF).withOpacity(_isHovered ? 0.6 : 0.35),
                  blurRadius: _isHovered ? 20 : 12,
                  spreadRadius: _isHovered ? 2 : 0,
                ),
              ],
            ),
            child: Icon(
              widget.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
              size: 36,
              color: Colors.white,
            ),
          ),
        ),
      ),
    );
  }
}

class _VolumeButton extends StatefulWidget {
  final double volume;
  final ValueChanged<double> onVolumeChanged;

  const _VolumeButton({
    required this.volume,
    required this.onVolumeChanged,
  });

  @override
  State<_VolumeButton> createState() => _VolumeButtonState();
}

class _VolumeButtonState extends State<_VolumeButton> {
  bool _showSlider = false;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _PlayerIconButton(
          icon: widget.volume == 0
              ? Icons.volume_off_rounded
              : (widget.volume > 0.5 ? Icons.volume_up_rounded : Icons.volume_down_rounded),
          size: 24,
          onTap: () {
            setState(() => _showSlider = !_showSlider);
          },
        ),
        if (_showSlider)
          SizedBox(
            width: 90,
            child: SliderTheme(
              data: SliderThemeData(
                trackHeight: 3,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
                activeTrackColor: const Color(0xFF7C5CFF),
                inactiveTrackColor: Colors.white24,
                thumbColor: Colors.white,
              ),
              child: Slider(
                value: widget.volume,
                min: 0.0,
                max: 1.0,
                onChanged: widget.onVolumeChanged,
              ),
            ),
          ),
      ],
    );
  }
}

class _ChapterListItemTile extends StatefulWidget {
  final AudiobookChapter chapter;
  final int index;
  final bool isSelected;
  final bool isPlaying;
  final VoidCallback onTap;

  const _ChapterListItemTile({
    required this.chapter,
    required this.index,
    required this.isSelected,
    required this.isPlaying,
    required this.onTap,
  });

  @override
  State<_ChapterListItemTile> createState() => _ChapterListItemTileState();
}

class _ChapterListItemTileState extends State<_ChapterListItemTile> {
  bool _isHovered = false;
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    final scale = _isPressed ? 0.98 : (_isHovered ? 1.015 : 1.0);

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        child: GestureDetector(
          onTapDown: (_) => setState(() => _isPressed = true),
          onTapUp: (_) => setState(() => _isPressed = false),
          onTapCancel: () => setState(() => _isPressed = false),
          onTap: widget.onTap,
          child: AnimatedScale(
            scale: scale,
            duration: const Duration(milliseconds: 150),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: widget.isSelected
                    ? const Color(0xFF7C5CFF).withOpacity(0.25)
                    : (_isHovered ? Colors.white.withOpacity(0.08) : Colors.transparent),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: widget.isSelected
                      ? const Color(0xFF7C5CFF).withOpacity(0.6)
                      : (_isHovered ? Colors.white.withOpacity(0.12) : Colors.transparent),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    widget.isSelected
                        ? (widget.isPlaying ? Icons.graphic_eq_rounded : Icons.pause_circle_filled_rounded)
                        : Icons.play_circle_outline_rounded,
                    color: widget.isSelected ? const Color(0xFFA78BFA) : Colors.white54,
                    size: 22,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      widget.chapter.title,
                      style: TextStyle(
                        color: widget.isSelected ? Colors.white : Colors.white70,
                        fontSize: 14,
                        fontWeight: widget.isSelected ? FontWeight.bold : FontWeight.normal,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
