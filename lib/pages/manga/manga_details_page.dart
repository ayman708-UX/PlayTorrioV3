import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:liquid_glass_easy/liquid_glass_easy.dart';

import '../../models/manga/manga.dart';
import '../../models/manga/manga_chapter.dart';
import '../../services/manga/manga_service.dart';
import '../../utils/fullscreen_navigator.dart';
import 'manga_reader_page.dart';

class MangaDetailsPage extends StatefulWidget {
  final Manga manga;

  const MangaDetailsPage({super.key, required this.manga});

  @override
  State<MangaDetailsPage> createState() => _MangaDetailsPageState();
}

class _MangaDetailsPageState extends State<MangaDetailsPage> {
  final MangaService _mangaService = MangaService();
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _searchController = TextEditingController();
  
  Manga? _fullDetails;
  List<MangaChapter>? _chapters;
  Map<String, dynamic>? _historyEntry;
  bool _isLoading = true;
  bool _isLiked = false;

  // Chapter Pagination & Search
  String _chapterSearchQuery = '';
  int _currentChapterPage = 0;
  final int _chaptersPerPage = 50;

  @override
  void initState() {
    super.initState();
    _loadDetails();
    _loadLikedState();
  }

  Future<void> _loadLikedState() async {
    final liked = await _mangaService.isLiked(widget.manga.id);
    if (mounted) setState(() => _isLiked = liked);
  }

  Future<void> _toggleLike() async {
    final manga = _fullDetails ?? widget.manga;
    await _mangaService.toggleLike(manga);
    if (mounted) setState(() => _isLiked = !_isLiked);
  }
  
  @override
  void dispose() {
    _scrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadDetails() async {
    final results = await Future.wait([
      _mangaService.getSeriesDetail(widget.manga.id),
      _mangaService.getChapters(widget.manga.id),
      _mangaService.getReadingHistory(),
    ]);

    final historyList = results[2] as List<Map<String, dynamic>>;
    Map<String, dynamic>? matchingHistory;
    try {
      matchingHistory = historyList.firstWhere((h) => h['manga']['id'] == widget.manga.id);
    } catch (e) {
      // No history found
    }

    if (mounted) {
      setState(() {
        _fullDetails = results[0] as Manga;
        _chapters = results[1] as List<MangaChapter>;
        _historyEntry = matchingHistory;
        _isLoading = false;
      });
    }
  }

  void _startReading(int chapterIndex, {int pageIndex = 0}) {
    if (_chapters == null || _chapters!.isEmpty) return;
    
    pushFullscreen(
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) => MangaReaderPage(
          manga: _fullDetails ?? widget.manga,
          chapters: _chapters!,
          currentChapterIndex: chapterIndex,
          resumePageIndex: pageIndex,
        ),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(opacity: animation, child: child);
        },
      ),
    ).then((_) {
      // Reload history when coming back in case they read more
      _loadDetails();
    });
  }

  List<MangaChapter> get _filteredChapters {
    if (_chapters == null) return [];
    if (_chapterSearchQuery.isEmpty) return _chapters!;
    
    final query = _chapterSearchQuery.toLowerCase();
    return _chapters!.where((c) => 
      c.name.toLowerCase().contains(query) || 
      c.number.toString().contains(query)
    ).toList();
  }

  List<MangaChapter> get _paginatedChapters {
    final filtered = _filteredChapters;
    final startIndex = _currentChapterPage * _chaptersPerPage;
    if (startIndex >= filtered.length) return [];
    
    final endIndex = (startIndex + _chaptersPerPage).clamp(0, filtered.length);
    return filtered.sublist(startIndex, endIndex);
  }

  @override
  Widget build(BuildContext context) {
    final displayManga = _fullDetails ?? widget.manga;
    final coverUrl = displayManga.coverNormal.isNotEmpty ? displayManga.coverNormal : displayManga.coverSmall;

    return Scaffold(
      backgroundColor: const Color(0xFF0F111A),
      body: Stack(
        children: [
          // Background Hero Cover
          Positioned.fill(
            child: Hero(
              tag: 'manga_cover_${displayManga.id}',
              child: Image.network(
                coverUrl,
                fit: BoxFit.cover,
                alignment: Alignment.topCenter,
              ),
            ),
          ),
          
          // Dark Gradient Overlay
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    const Color(0xFF0F111A).withValues(alpha: 0.6),
                    const Color(0xFF0F111A).withValues(alpha: 0.95),
                    const Color(0xFF0F111A),
                  ],
                  stops: const [0.0, 0.4, 1.0],
                ),
              ),
            ),
          ),

          // Main Scrollable Content
          LiquidGlassView(
            pixelRatio: 0.25,
            refreshRate: LiquidGlassRefreshRate.low,
            backgroundWidget: _buildScrollableContent(displayManga),
            child: Stack(
              children: [
                _buildAppBar(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildScrollableContent(Manga manga) {
    final paginatedList = _paginatedChapters;
    final totalFiltered = _filteredChapters.length;
    final totalPages = (totalFiltered / _chaptersPerPage).ceil();

    return CustomScrollView(
      controller: _scrollController,
      physics: const BouncingScrollPhysics(),
      slivers: [
        const SliverToBoxAdapter(child: SizedBox(height: 120)), // Top spacer

        // Metadata Header
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 40.0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Cover Image
                ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: Image.network(
                    manga.coverNormal.isNotEmpty ? manga.coverNormal : manga.coverSmall,
                    width: 200,
                    height: 300,
                    fit: BoxFit.cover,
                  ),
                ),
                const SizedBox(width: 40),
                
                // Details
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        manga.title,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 48,
                          fontWeight: FontWeight.bold,
                          letterSpacing: -1,
                          height: 1.1,
                        ),
                      ),
                      const SizedBox(height: 16),
                      if (manga.author.isNotEmpty || manga.year.isNotEmpty)
                        Text(
                          '${manga.author}${manga.author.isNotEmpty && manga.year.isNotEmpty ? ' • ' : ''}${manga.year}',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.7),
                            fontSize: 18,
                          ),
                        ),
                      const SizedBox(height: 24),
                      
                      // Tags
                      if (manga.tags.isNotEmpty)
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: manga.tags.take(6).map((tag) {
                            return Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
                              ),
                              child: Text(
                                tag,
                                style: const TextStyle(color: Colors.white, fontSize: 12),
                              ),
                            );
                          }).toList(),
                        ),
                        
                      const SizedBox(height: 32),
                      
                      // Action Buttons
                      if (!_isLoading)
                        Row(
                          children: [
                            if (_historyEntry != null)
                              _buildActionButton(
                                icon: Icons.play_arrow_rounded,
                                label: 'Resume Chapter ${(_chapters != null && _historyEntry!['chapterIndex'] < _chapters!.length) ? _chapters![_historyEntry!['chapterIndex']].number : ''}',
                                color: Colors.blueAccent,
                                onTap: () => _startReading(_historyEntry!['chapterIndex'], pageIndex: _historyEntry!['pageIndex']),
                              )
                            else if (_chapters != null && _chapters!.isNotEmpty)
                              _buildActionButton(
                                icon: Icons.menu_book_rounded,
                                label: 'Start Reading',
                                color: Colors.white,
                                textColor: Colors.black,
                                onTap: () => _startReading(_chapters!.length - 1),
                              ),
                            const SizedBox(width: 16),
                            _buildLikeButton(),
                          ],
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),

        const SliverToBoxAdapter(child: SizedBox(height: 40)),

        // Synopsis
        if (manga.synopsis.isNotEmpty)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 40.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Synopsis',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    manga.synopsis,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.8),
                      fontSize: 16,
                      height: 1.6,
                    ),
                  ),
                ],
              ),
            ),
          ),

        const SliverToBoxAdapter(child: SizedBox(height: 40)),

        // Chapters Header & Search
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 40.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Chapters',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                // Search Bar
                SizedBox(
                  width: 250,
                  height: 40,
                  child: TextField(
                    controller: _searchController,
                    onChanged: (val) {
                      setState(() {
                        _chapterSearchQuery = val;
                        _currentChapterPage = 0; // Reset page on search
                      });
                    },
                    style: const TextStyle(color: Colors.white, fontSize: 14),
                    decoration: InputDecoration(
                      hintText: 'Search chapters...',
                      hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.4)),
                      prefixIcon: const Icon(Icons.search_rounded, color: Colors.white54, size: 18),
                      filled: true,
                      fillColor: Colors.white.withValues(alpha: 0.05),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(20),
                        borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(20),
                        borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(20),
                        borderSide: const BorderSide(color: Colors.blueAccent),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        
        const SliverToBoxAdapter(child: SizedBox(height: 16)),

        if (_isLoading)
          const SliverToBoxAdapter(
            child: Center(
              child: CircularProgressIndicator(color: Colors.white),
            ),
          )
        else if (paginatedList.isEmpty)
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.all(32.0),
              child: Center(
                child: Text('No chapters found.', style: TextStyle(color: Colors.white70)),
              ),
            ),
          )
        else ...[
          SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, index) {
                final chapter = paginatedList[index];
                
                // We need the original absolute index for the reader
                final originalIndex = _chapters!.indexOf(chapter);
                
                final isRead = _historyEntry != null && _historyEntry!['chapterIndex'] < originalIndex; // Inverse because list is desc
                final isCurrent = _historyEntry != null && _historyEntry!['chapterIndex'] == originalIndex;

                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 40.0, vertical: 4.0),
                  child: ListTile(
                    onTap: () => _startReading(originalIndex),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    tileColor: isCurrent ? Colors.blueAccent.withValues(alpha: 0.2) : Colors.white.withValues(alpha: 0.05),
                    leading: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.1),
                        shape: BoxShape.circle,
                      ),
                      child: Center(
                        child: Text(
                          chapter.number > 0
                              ? chapter.number.toStringAsFixed(chapter.number.truncateToDouble() == chapter.number ? 0 : 1)
                              : '#',
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
                        ),
                      ),
                    ),
                    title: Text(
                      (chapter.name.isNotEmpty && chapter.name.toLowerCase() != 'last read')
                          ? chapter.name
                          : (chapter.number > 0
                              ? 'Chapter ${chapter.number.toStringAsFixed(chapter.number.truncateToDouble() == chapter.number ? 0 : 1)}'
                              : 'Chapter'),
                      style: TextStyle(
                        color: isRead ? Colors.white54 : Colors.white,
                        fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
                      ),
                    ),
                    trailing: const Icon(Icons.chevron_right_rounded, color: Colors.white54),
                  ),
                );
              },
              childCount: paginatedList.length,
            ),
          ),
          
          // Pagination Controls
          if (totalPages > 1)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 40.0, vertical: 32.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.chevron_left_rounded, color: Colors.white),
                      onPressed: _currentChapterPage > 0 ? () {
                        setState(() => _currentChapterPage--);
                      } : null,
                    ),
                    const SizedBox(width: 16),
                    Text(
                      'Page ${_currentChapterPage + 1} of $totalPages',
                      style: const TextStyle(color: Colors.white70, fontSize: 16),
                    ),
                    const SizedBox(width: 16),
                    IconButton(
                      icon: const Icon(Icons.chevron_right_rounded, color: Colors.white),
                      onPressed: _currentChapterPage < totalPages - 1 ? () {
                        setState(() => _currentChapterPage++);
                      } : null,
                    ),
                  ],
                ),
              ),
            ),
        ],
          
        const SliverToBoxAdapter(child: SizedBox(height: 120)),
      ],
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required Color color,
    Color textColor = Colors.white,
    required VoidCallback onTap,
  }) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: color.withValues(alpha: 0.3),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: textColor, size: 20),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  color: textColor,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLikeButton() {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: _toggleLike,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          decoration: BoxDecoration(
            color: _isLiked
                ? const Color(0xFFE50914)
                : Colors.white.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: _isLiked
                  ? const Color(0xFFE50914)
                  : Colors.white.withValues(alpha: 0.2),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                _isLiked ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                color: _isLiked ? Colors.white : Colors.white70,
                size: 20,
              ),
              const SizedBox(width: 8),
              Text(
                _isLiked ? 'Liked' : 'Like',
                style: TextStyle(
                  color: _isLiked ? Colors.white : Colors.white70,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAppBar() {
    return Positioned(
      top: 24,
      left: 24,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 16.0, sigmaY: 16.0),
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.05),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.1),
                width: 1.5,
              ),
              borderRadius: BorderRadius.circular(24),
            ),
            child: IconButton(
              icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
              onPressed: () => Navigator.of(context).pop(),
              splashRadius: 20,
            ),
          ),
        ),
      ),
    );
  }
}
