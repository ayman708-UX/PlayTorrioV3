import 'dart:async';
import 'dart:ui';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../models/audiobook/audiobook_model.dart';
import '../../services/audiobook/audiobook_player_controller.dart';
import '../../services/audiobook/audiobook_progress_service.dart';
import '../../services/audiobook/audiobook_scraper_service.dart';
import '../../widgets/common/page_search_button.dart';
import 'audiobook_detail_page.dart';
import 'audiobook_route_transitions.dart';

class AudiobooksPage extends StatefulWidget {
  const AudiobooksPage({super.key});

  @override
  State<AudiobooksPage> createState() => _AudiobooksPageState();
}

class _AudiobooksPageState extends State<AudiobooksPage> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  final ScrollController _continueScrollController = ScrollController();

  bool _isSearching = false;
  List<Audiobook> _searchResults = [];
  List<AudiobookProgress> _continueListeningList = [];
  String? _errorMessage;
  int _searchSequence = 0;

  @override
  void initState() {
    super.initState();
    _loadContinueListening();
    _performSearch('Harry Potter');
  }

  Future<void> _loadContinueListening() async {
    final list = await AudiobookProgressService.instance.getAllProgress();
    if (mounted) {
      setState(() {
        _continueListeningList = list;
      });
    }
  }

  void _scrollContinueLeft() {
    if (!_continueScrollController.hasClients) return;
    _continueScrollController.animateTo(
      (_continueScrollController.offset - 280).clamp(0.0, _continueScrollController.position.maxScrollExtent),
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
    );
  }

  void _scrollContinueRight() {
    if (!_continueScrollController.hasClients) return;
    _continueScrollController.animateTo(
      (_continueScrollController.offset + 280).clamp(0.0, _continueScrollController.position.maxScrollExtent),
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
    );
  }

  Timer? _searchDebounce;

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    _continueScrollController.dispose();
    _searchDebounce?.cancel();
    super.dispose();
  }

  Future<void> _performSearch(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return;
    _searchDebounce?.cancel();

    final currentSequence = ++_searchSequence;

    setState(() {
      _isSearching = true;
      _errorMessage = null;
    });

    try {
      final results = await AudiobookScraperService.instance.search(trimmed);
      debugPrint('Audiobook search [#$currentSequence] for "$trimmed" returned ${results.length} items');
      if (mounted && currentSequence == _searchSequence) {
        setState(() {
          _searchResults = results;
          _isSearching = false;
        });
      }
    } catch (e) {
      if (mounted && currentSequence == _searchSequence) {
        setState(() {
          _isSearching = false;
          _errorMessage = 'Failed to fetch audiobooks: $e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF080A0F),
      body: Stack(
        children: [
          // Background ambient glows
          Positioned(
            top: -100,
            left: -100,
            child: Container(
              width: 350,
              height: 350,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFF7C5CFF).withOpacity(0.18),
              ),
            ),
          ),
          Positioned(
            top: 200,
            right: -100,
            child: Container(
              width: 400,
              height: 400,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFF38BDF8).withOpacity(0.12),
              ),
            ),
          ),
          Positioned.fill(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 50, sigmaY: 50),
              child: Container(color: Colors.black.withOpacity(0.4)),
            ),
          ),

          // Main Scroll View
          CustomScrollView(
            physics: const BouncingScrollPhysics(),
            slivers: [
              // Title row with search
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 8, 12, 8),
                  child: Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'Audiobooks',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 28,
                            fontWeight: FontWeight.w900,
                            letterSpacing: -0.5,
                          ),
                        ),
                      ),
                      const PageSearchButton(),
                    ],
                  ),
                ),
              ),

              // Continue Listening Section (If available)
              if (_continueListeningList.isNotEmpty)
                SliverToBoxAdapter(
                  child: _buildContinueListeningSection(),
                ),

              // Search Status / Loading / Grid
              if (_isSearching)
                const SliverFillRemaining(
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        CircularProgressIndicator(color: Color(0xFF7C5CFF)),
                        SizedBox(height: 16),
                        Text(
                          'Scraping 9 audiobook sources...',
                          style: TextStyle(color: Colors.white70, fontSize: 14),
                        ),
                      ],
                    ),
                  ),
                )
              else if (_errorMessage != null)
                SliverFillRemaining(
                  child: Center(
                    child: Text(
                      _errorMessage!,
                      style: const TextStyle(color: Colors.redAccent, fontSize: 15),
                    ),
                  ),
                )
              else if (_searchResults.isEmpty)
                const SliverFillRemaining(
                  child: Center(
                    child: Text(
                      'No audiobooks found. Try another search query.',
                      style: TextStyle(color: Colors.white54, fontSize: 16),
                    ),
                  ),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(24, 8, 24, 40),
                  sliver: SliverGrid(
                    gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                      maxCrossAxisExtent: 180,
                      childAspectRatio: 0.62,
                      crossAxisSpacing: 16,
                      mainAxisSpacing: 16,
                    ),
                    delegate: SliverChildBuilderDelegate(
                      (context, index) {
                        final book = _searchResults[index];
                        final heroTag = 'audiobook-cover-$index-${book.uuid.isNotEmpty ? book.uuid : book.title}';
                        return _AudiobookCard(
                          key: ValueKey('book-$index-${book.uuid}'),
                          book: book,
                          heroTag: heroTag,
                          onReturn: _loadContinueListening,
                        );
                      },
                      childCount: _searchResults.length,
                    ),
                  ),
                ),
            ],
          ),

          // Persistent Bottom Navigation Dock
        ],
      ),
    );
  }

  Widget _buildContinueListeningSection() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Row(
                children: [
                  Icon(Icons.history_rounded, color: Color(0xFFA78BFA), size: 20),
                  SizedBox(width: 8),
                  Text(
                    'Continue Listening',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.3,
                    ),
                  ),
                ],
              ),
              Row(
                children: [
                  _ScrollArrowButton(
                    icon: Icons.chevron_left_rounded,
                    onTap: _scrollContinueLeft,
                  ),
                  const SizedBox(width: 8),
                  _ScrollArrowButton(
                    icon: Icons.chevron_right_rounded,
                    onTap: _scrollContinueRight,
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 110,
            child: ListView.builder(
              controller: _continueScrollController,
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              itemCount: _continueListeningList.length,
              itemBuilder: (context, index) {
                final item = _continueListeningList[index];
                return _ContinueListeningCard(
                  progress: item,
                  onDelete: () async {
                    await AudiobookProgressService.instance.removeProgress(item.key);
                    _loadContinueListening();
                  },
                  onTap: () async {
                    // Resume in the background so the bottom play bar appears.
                    AudiobookPlayerController.instance.play(
                      item.audiobook,
                      item.chapters,
                      chapterIndex: item.chapterIndex,
                      initialPosition: Duration(milliseconds: item.positionMs),
                    );
                    _loadContinueListening();
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _ContinueListeningCard extends StatefulWidget {
  final AudiobookProgress progress;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  const _ContinueListeningCard({
    required this.progress,
    required this.onTap,
    required this.onDelete,
  });

  @override
  State<_ContinueListeningCard> createState() => _ContinueListeningCardState();
}

class _ContinueListeningCardState extends State<_ContinueListeningCard> {
  bool _isHovered = false;
  bool _isPressed = false;
  bool _isDeleteHovered = false;

  @override
  Widget build(BuildContext context) {
    final item = widget.progress;
    final book = item.audiobook;
    final hasCover = book.coverImage.isNotEmpty;
    final heroTag = 'continue-cover-${book.uuid.isNotEmpty ? book.uuid : book.title}';

    final percent = item.durationMs > 0
        ? (item.positionMs / item.durationMs).clamp(0.0, 1.0)
        : 0.0;

    final currentChapterTitle = item.chapters.isNotEmpty && item.chapterIndex < item.chapters.length
        ? item.chapters[item.chapterIndex].title
        : 'Chapter ${item.chapterIndex + 1}';

    final scale = _isPressed ? 0.96 : (_isHovered ? 1.03 : 1.0);

    return Padding(
      padding: const EdgeInsets.only(right: 14),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          MouseRegion(
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
                  width: 285,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: _isHovered
                        ? const Color(0xFF1B2030)
                        : const Color(0xFF12151E).withValues(alpha: 0.85),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: _isHovered
                          ? const Color(0xFF7C5CFF).withValues(alpha: 0.6)
                          : Colors.white.withValues(alpha: 0.08),
                      width: _isHovered ? 1.5 : 1.0,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: _isHovered
                            ? const Color(0xFF7C5CFF).withValues(alpha: 0.3)
                            : Colors.black.withValues(alpha: 0.4),
                        blurRadius: _isHovered ? 14 : 8,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      // Book Cover Art
                      SizedBox(
                        width: 60,
                        height: 90,
                        child: Hero(
                          tag: heroTag,
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child: hasCover
                                ? CachedNetworkImage(
                                    imageUrl: book.coverImage,
                                    fit: BoxFit.cover,
                                    placeholder: (_, __) => Container(color: const Color(0xFF1A1F2C)),
                                    errorWidget: (_, __, ___) => Container(
                                      color: const Color(0xFF1A1F2C),
                                      child: const Icon(Icons.headphones_rounded, color: Colors.white38),
                                    ),
                                  )
                                : Container(
                                    color: const Color(0xFF1A1F2C),
                                    child: const Icon(Icons.headphones_rounded, color: Colors.white38),
                                  ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),

                      // Info & Progress
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              book.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              currentChapterTitle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.6),
                                fontSize: 11,
                              ),
                            ),
                            const SizedBox(height: 8),
                            // Progress bar
                            ClipRRect(
                              borderRadius: BorderRadius.circular(4),
                              child: LinearProgressIndicator(
                                value: percent,
                                minHeight: 4,
                                backgroundColor: Colors.white.withValues(alpha: 0.1),
                                valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF7C5CFF)),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '${(percent * 100).toInt()}% completed',
                              style: const TextStyle(
                                color: Color(0xFFA78BFA),
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 6),

                      // Play Button Icon
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: _isHovered
                              ? const Color(0xFF7C5CFF)
                              : const Color(0xFF7C5CFF).withValues(alpha: 0.2),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.play_arrow_rounded,
                          color: _isHovered ? Colors.white : const Color(0xFFA78BFA),
                          size: 20,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),

          // X Delete Button
          Positioned(
            top: -4,
            right: -4,
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              onEnter: (_) => setState(() => _isDeleteHovered = true),
              onExit: (_) => setState(() => _isDeleteHovered = false),
              child: GestureDetector(
                onTap: widget.onDelete,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: _isDeleteHovered
                        ? const Color(0xFFFF4D4D)
                        : const Color(0xFF1E2332),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: _isDeleteHovered
                          ? const Color(0xFFFF4D4D)
                          : Colors.white.withValues(alpha: 0.2),
                      width: 1.2,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.5),
                        blurRadius: 6,
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.close_rounded,
                    color: Colors.white,
                    size: 14,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ScrollArrowButton extends StatefulWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _ScrollArrowButton({
    required this.icon,
    required this.onTap,
  });

  @override
  State<_ScrollArrowButton> createState() => _ScrollArrowButtonState();
}

class _ScrollArrowButtonState extends State<_ScrollArrowButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: _isHovered
                ? const Color(0xFF7C5CFF).withOpacity(0.3)
                : Colors.white.withOpacity(0.08),
            shape: BoxShape.circle,
            border: Border.all(
              color: _isHovered
                  ? const Color(0xFF7C5CFF)
                  : Colors.white.withOpacity(0.1),
            ),
          ),
          child: Icon(
            widget.icon,
            color: _isHovered ? Colors.white : Colors.white70,
            size: 18,
          ),
        ),
      ),
    );
  }
}

class _AudiobookCard extends StatefulWidget {
  final Audiobook book;
  final String heroTag;
  final VoidCallback? onReturn;

  const _AudiobookCard({
    super.key,
    required this.book,
    required this.heroTag,
    this.onReturn,
  });

  @override
  State<_AudiobookCard> createState() => _AudiobookCardState();
}

class _AudiobookCardState extends State<_AudiobookCard> {
  bool _isHovered = false;
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    final book = widget.book;
    final hasCover = book.coverImage.isNotEmpty;
    final heroTag = widget.heroTag;

    final scale = _isPressed
        ? 0.95
        : (_isHovered ? 1.04 : 1.0);

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTapDown: (_) => setState(() => _isPressed = true),
        onTapUp: (_) => setState(() => _isPressed = false),
        onTapCancel: () => setState(() => _isPressed = false),
        onTap: () async {
          await Navigator.push(
            context,
            AudiobookPageRoute(
              page: AudiobookDetailPage(
                audiobook: book,
                heroTag: heroTag,
              ),
            ),
          );
          widget.onReturn?.call();
        },
        child: AnimatedScale(
          scale: scale,
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            decoration: BoxDecoration(
              color: _isHovered
                  ? const Color(0xFF191E2C)
                  : const Color(0xFF12151E),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: _isHovered
                    ? const Color(0xFF7C5CFF).withOpacity(0.6)
                    : Colors.white.withOpacity(0.08),
                width: _isHovered ? 1.5 : 1.0,
              ),
              boxShadow: [
                BoxShadow(
                  color: _isHovered
                      ? const Color(0xFF7C5CFF).withOpacity(0.35)
                      : Colors.black.withOpacity(0.4),
                  blurRadius: _isHovered ? 16 : 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Cover Image with Hero Transition
                Expanded(
                  child: Hero(
                    tag: heroTag,
                    child: ClipRRect(
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                      child: hasCover
                          ? CachedNetworkImage(
                              imageUrl: book.coverImage,
                              width: double.infinity,
                              fit: BoxFit.cover,
                              placeholder: (_, __) => Container(color: const Color(0xFF1A1F2C)),
                              errorWidget: (_, __, ___) => Container(
                                color: const Color(0xFF1A1F2C),
                                child: const Icon(Icons.headphones_rounded, size: 40, color: Colors.white38),
                              ),
                            )
                          : Container(
                              color: const Color(0xFF1A1F2C),
                              child: const Center(
                                child: Icon(Icons.headphones_rounded, size: 40, color: Colors.white38),
                              ),
                            ),
                    ),
                  ),
                ),
                // Information
                Padding(
                  padding: const EdgeInsets.all(10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        book.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: _isHovered ? Colors.white : Colors.white.withOpacity(0.9),
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          height: 1.2,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Builder(
                        builder: (context) {
                          final isTorrent = book.source.toLowerCase().contains('audiobookbay');
                          return Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: isTorrent
                                  ? const Color(0xFFFF9800).withValues(alpha: 0.25)
                                  : (_isHovered
                                      ? const Color(0xFF7C5CFF).withValues(alpha: 0.35)
                                      : const Color(0xFF7C5CFF).withValues(alpha: 0.2)),
                              borderRadius: BorderRadius.circular(6),
                              border: isTorrent
                                  ? Border.all(color: const Color(0xFFFF9800).withValues(alpha: 0.4), width: 0.8)
                                  : null,
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (isTorrent) ...[
                                  const Icon(Icons.warning_amber_rounded, color: Color(0xFFFFB74D), size: 10),
                                  const SizedBox(width: 3),
                                ],
                                Text(
                                  isTorrent ? 'AUDIOBOOKBAY (TORRENT)' : book.source.toUpperCase(),
                                  style: TextStyle(
                                    color: isTorrent ? const Color(0xFFFFB74D) : const Color(0xFFA78BFA),
                                    fontSize: 9,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ],
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

