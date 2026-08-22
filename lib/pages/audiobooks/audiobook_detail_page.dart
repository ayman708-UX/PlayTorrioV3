import 'dart:ui';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../models/audiobook/audiobook_model.dart';
import '../../services/audiobook/audiobook_library_service.dart';
import '../../services/audiobook/audiobook_player_controller.dart';
import '../../services/audiobook/audiobook_scraper_service.dart';
import '../../utils/fullscreen_navigator.dart';
import 'audiobook_player_screen.dart';
import 'audiobook_route_transitions.dart';

class AudiobookDetailPage extends StatefulWidget {
  final Audiobook audiobook;
  final String? heroTag;

  const AudiobookDetailPage({
    super.key,
    required this.audiobook,
    this.heroTag,
  });

  @override
  State<AudiobookDetailPage> createState() => _AudiobookDetailPageState();
}

class _AudiobookDetailPageState extends State<AudiobookDetailPage> {
  List<AudiobookChapter>? _chapters;
  bool _loading = true;
  String? _error;
  bool _isLiked = false;

  @override
  void initState() {
    super.initState();
    _fetchChapters();
    AudiobookLibraryService.instance.init();
    _isLiked = AudiobookLibraryService.instance.isLiked(widget.audiobook.uuid);
    // Tapping the bottom play bar opens the fullscreen player.
    AudiobookPlayerController.instance.setExpandCallback(() {
      if (!mounted || _chapters == null || _chapters!.isEmpty) return;
      pushFullscreen(
        AudiobookPageRoute(
          page: AudiobookPlayerScreen(
            audiobook: widget.audiobook,
            chapters: _chapters!,
            initialChapterIndex: AudiobookPlayerController.instance.currentIndex,
          ),
        ),
      );
    });
  }

  Future<void> _toggleLike() async {
    await AudiobookLibraryService.instance.toggleLike(widget.audiobook);
    if (mounted) {
      setState(() {
        _isLiked = AudiobookLibraryService.instance.isLiked(widget.audiobook.uuid);
      });
    }
  }

  Future<void> _fetchChapters() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final chapters = await AudiobookScraperService.instance.getChapters(widget.audiobook);
      if (mounted) {
        setState(() {
          _chapters = chapters;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'Failed to load chapters: $e';
        });
      }
    }
  }

  void _playChapter(AudiobookChapter chapter) {
    if (_chapters == null || _chapters!.isEmpty) return;
    final initialIndex = _chapters!.indexOf(chapter).clamp(0, _chapters!.length - 1);

    // Start playback in the background so the bottom play bar appears instead
    // of a fullscreen player. Tapping the bottom bar opens the fullscreen
    // player.
    AudiobookPlayerController.instance.play(
      widget.audiobook,
      _chapters!,
      chapterIndex: initialIndex,
    );
  }

  @override
  Widget build(BuildContext context) {
    final book = widget.audiobook;
    final hasCover = book.coverImage.isNotEmpty;

    return Scaffold(
      backgroundColor: const Color(0xFF080A0F),
      body: Stack(
        children: [
          // Background ambient cover blur
          if (hasCover)
            Positioned.fill(
              child: Opacity(
                opacity: 0.25,
                child: Image.network(
                  book.coverImage,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => const SizedBox(),
                ),
              ),
            ),
          Positioned.fill(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 40, sigmaY: 40),
              child: Container(color: Colors.black.withOpacity(0.6)),
            ),
          ),

          // Main content
          CustomScrollView(
            physics: const BouncingScrollPhysics(),
            slivers: [
              // Header
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 56, 24, 24),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Back Button
                      IconButton(
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white),
                        style: IconButton.styleFrom(
                          backgroundColor: Colors.white.withOpacity(0.1),
                          padding: const EdgeInsets.all(12),
                        ),
                      ),
                      const SizedBox(width: 16),
                      // Cover Image
                      Container(
                        width: 130,
                        height: 190,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFF7C5CFF).withOpacity(0.3),
                              blurRadius: 20,
                              spreadRadius: 2,
                            ),
                          ],
                        ),
                        child: Hero(
                          tag: widget.heroTag ?? 'audiobook-cover-${book.uuid.isNotEmpty ? book.uuid : book.title}',
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(16),
                            child: hasCover
                                ? CachedNetworkImage(
                                    imageUrl: book.coverImage,
                                    fit: BoxFit.cover,
                                    placeholder: (_, __) => Container(color: const Color(0xFF161A26)),
                                    errorWidget: (_, __, ___) => const Icon(Icons.headphones_rounded, size: 48, color: Colors.white54),
                                  )
                                : Container(
                                    color: const Color(0xFF161A26),
                                    child: const Icon(Icons.headphones_rounded, size: 48, color: Colors.white54),
                                  ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 20),
                      // Details
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const SizedBox(height: 12),
                            Builder(
                              builder: (context) {
                                final isTorrent = book.source.toLowerCase().contains('audiobookbay');
                                return Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: isTorrent
                                            ? const Color(0xFFFF9800).withValues(alpha: 0.2)
                                            : const Color(0xFF7C5CFF).withValues(alpha: 0.2),
                                        borderRadius: BorderRadius.circular(20),
                                        border: Border.all(
                                          color: isTorrent
                                              ? const Color(0xFFFF9800).withValues(alpha: 0.5)
                                              : const Color(0xFF7C5CFF).withValues(alpha: 0.4),
                                        ),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          if (isTorrent) ...[
                                            const Icon(Icons.warning_amber_rounded, color: Color(0xFFFFB74D), size: 13),
                                            const SizedBox(width: 4),
                                          ],
                                          Text(
                                            isTorrent ? 'AUDIOBOOKBAY (TORRENT)' : book.source.toUpperCase(),
                                            style: TextStyle(
                                              color: isTorrent ? const Color(0xFFFFB74D) : const Color(0xFFA78BFA),
                                              fontSize: 11,
                                              fontWeight: FontWeight.bold,
                                              letterSpacing: 1.0,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    if (isTorrent) ...[
                                      const SizedBox(height: 8),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFFFF9800).withValues(alpha: 0.12),
                                          borderRadius: BorderRadius.circular(8),
                                          border: Border.all(color: const Color(0xFFFF9800).withValues(alpha: 0.3)),
                                        ),
                                        child: const Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(Icons.info_outline_rounded, color: Color(0xFFFFB74D), size: 14),
                                            SizedBox(width: 6),
                                            Flexible(
                                              child: Text(
                                                '⚠️ Warning: Streams via P2P Torrent.',
                                                style: TextStyle(
                                                  color: Color(0xFFFFC107),
                                                  fontSize: 11,
                                                  fontWeight: FontWeight.w600,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ],
                                );
                              },
                            ),
                            const SizedBox(height: 12),
                            Text(
                              book.title,
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 22,
                                fontWeight: FontWeight.bold,
                                height: 1.2,
                              ),
                            ),
                            const SizedBox(height: 16),
                            if (_chapters != null && _chapters!.isNotEmpty)
                              Row(
                                children: [
                                  _PlayFirstChapterButton(
                                    onPressed: () => _playChapter(_chapters!.first),
                                  ),
                                  const SizedBox(width: 12),
                                  _LikeButton(
                                    isLiked: _isLiked,
                                    onTap: _toggleLike,
                                  ),
                                ],
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // Section Title
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  child: Row(
                    children: [
                      Icon(Icons.format_list_bulleted_rounded, color: Color(0xFFA78BFA), size: 20),
                      SizedBox(width: 8),
                      Text(
                        'Chapters & Audio Files',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // Chapters List
              if (_loading)
                const SliverFillRemaining(
                  child: Center(
                    child: CircularProgressIndicator(color: Color(0xFF7C5CFF)),
                  ),
                )
              else if (_error != null)
                SliverFillRemaining(
                  child: Center(
                    child: Text(
                      _error!,
                      style: const TextStyle(color: Colors.redAccent),
                    ),
                  ),
                )
              else if (_chapters == null || _chapters!.isEmpty)
                const SliverFillRemaining(
                  child: Center(
                    child: Text(
                      'No playable chapters found.',
                      style: TextStyle(color: Colors.white54, fontSize: 16),
                    ),
                  ),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) {
                        final chapter = _chapters![index];
                        return _ChapterTile(
                          chapter: chapter,
                          onTap: () => _playChapter(chapter),
                        );
                      },
                      childCount: _chapters!.length,
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PlayFirstChapterButton extends StatefulWidget {
  final VoidCallback onPressed;

  const _PlayFirstChapterButton({required this.onPressed});

  @override
  State<_PlayFirstChapterButton> createState() => _PlayFirstChapterButtonState();
}

class _PlayFirstChapterButtonState extends State<_PlayFirstChapterButton> {
  bool _isHovered = false;
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    final scale = _isPressed
        ? 0.94
        : (_isHovered ? 1.05 : 1.0);

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTapDown: (_) => setState(() => _isPressed = true),
        onTapUp: (_) => setState(() => _isPressed = false),
        onTapCancel: () => setState(() => _isPressed = false),
        onTap: widget.onPressed,
        child: AnimatedScale(
          scale: scale,
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOutCubic,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: _isHovered
                    ? [const Color(0xFF8B6CFF), const Color(0xFF48CAFF)]
                    : [const Color(0xFF7C5CFF), const Color(0xFF38BDF8)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF7C5CFF).withOpacity(_isHovered ? 0.6 : 0.35),
                  blurRadius: _isHovered ? 16 : 8,
                  spreadRadius: _isHovered ? 2 : 0,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.play_arrow_rounded, color: Colors.white, size: 24),
                SizedBox(width: 8),
                Text(
                  'Play First Chapter',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.3,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _LikeButton extends StatefulWidget {
  final bool isLiked;
  final VoidCallback onTap;

  const _LikeButton({required this.isLiked, required this.onTap});

  @override
  State<_LikeButton> createState() => _LikeButtonState();
}

class _LikeButtonState extends State<_LikeButton> {
  bool _isHovered = false;
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    final scale = _isPressed ? 0.94 : (_isHovered ? 1.05 : 1.0);

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
          curve: Curves.easeOutCubic,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            decoration: BoxDecoration(
              color: widget.isLiked
                  ? const Color(0xFFE50914)
                  : Colors.white.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: widget.isLiked
                    ? const Color(0xFFE50914)
                    : Colors.white.withValues(alpha: 0.2),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  widget.isLiked
                      ? Icons.favorite_rounded
                      : Icons.favorite_border_rounded,
                  color: widget.isLiked ? Colors.white : Colors.white70,
                  size: 22,
                ),
                const SizedBox(width: 8),
                Text(
                  widget.isLiked ? 'Liked' : 'Like',
                  style: TextStyle(
                    color: widget.isLiked ? Colors.white : Colors.white70,
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ChapterTile extends StatefulWidget {
  final AudiobookChapter chapter;
  final VoidCallback onTap;

  const _ChapterTile({
    required this.chapter,
    required this.onTap,
  });

  @override
  State<_ChapterTile> createState() => _ChapterTileState();
}

class _ChapterTileState extends State<_ChapterTile> {
  bool _isHovered = false;
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    final chapter = widget.chapter;
    final scale = _isPressed
        ? 0.98
        : (_isHovered ? 1.015 : 1.0);

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
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
            curve: Curves.easeOutCubic,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              decoration: BoxDecoration(
                color: _isHovered
                    ? const Color(0xFF1B2030)
                    : const Color(0xFF12151E).withValues(alpha: 0.7),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: _isHovered
                      ? const Color(0xFF7C5CFF).withOpacity(0.5)
                      : Colors.white.withValues(alpha: 0.08),
                  width: _isHovered ? 1.5 : 1.0,
                ),
                boxShadow: _isHovered
                    ? [
                        BoxShadow(
                          color: const Color(0xFF7C5CFF).withOpacity(0.25),
                          blurRadius: 14,
                          offset: const Offset(0, 4),
                        )
                      ]
                    : [],
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: _isHovered
                            ? const Color(0xFF7C5CFF)
                            : const Color(0xFF7C5CFF).withOpacity(0.15),
                        shape: BoxShape.circle,
                        boxShadow: _isHovered
                            ? [
                                BoxShadow(
                                  color: const Color(0xFF7C5CFF).withOpacity(0.5),
                                  blurRadius: 10,
                                )
                              ]
                            : [],
                      ),
                      child: Icon(
                        Icons.play_arrow_rounded,
                        color: _isHovered ? Colors.white : const Color(0xFFA78BFA),
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            chapter.title,
                            style: TextStyle(
                              color: _isHovered ? Colors.white : Colors.white.withOpacity(0.95),
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            chapter.isTorrent ? 'Torrent Stream' : 'Direct Audio Stream',
                            style: TextStyle(
                              color: _isHovered ? const Color(0xFFA78BFA) : Colors.white.withOpacity(0.5),
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Icon(
                      Icons.headphones_rounded,
                      color: _isHovered ? const Color(0xFF7C5CFF) : Colors.white.withOpacity(0.3),
                      size: 20,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
