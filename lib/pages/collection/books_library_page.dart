import 'package:flutter/material.dart';

import '../../models/audiobook/audiobook_model.dart';
import '../../models/manga/manga.dart';
import '../../models/playback/playback_history_item.dart';
import '../../services/audiobook/audiobook_library_service.dart';
import '../../services/manga/manga_service.dart';
import '../../services/playback/playback_history_service.dart';
import '../../widgets/common/library_tabs.dart';
import '../../widgets/manga/manga_card.dart';
import '../audiobooks/audiobook_detail_page.dart';
import '../audiobooks/audiobook_route_transitions.dart';
import '../manga/manga_details_page.dart';
import '../../utils/route_transitions.dart';

/// The Books hub's Library: shows the user's liked manga, liked audiobooks,
/// and playback history, using the shared [LibraryTabs] design.
class BooksLibraryPage extends StatefulWidget {
  const BooksLibraryPage({super.key});

  @override
  State<BooksLibraryPage> createState() => _BooksLibraryPageState();
}

class _BooksLibraryPageState extends State<BooksLibraryPage> {
  final MangaService _mangaService = MangaService();
  List<Manga> _likedManga = [];
  bool _loadingManga = true;

  @override
  void initState() {
    super.initState();
    AudiobookLibraryService.instance.init();
    _loadLikedManga();
  }

  Future<void> _loadLikedManga() async {
    final liked = await _mangaService.getLikedManga();
    if (mounted) {
      setState(() {
        _likedManga = liked;
        _loadingManga = false;
      });
    }
  }

  void _openManga(Manga manga) {
    Navigator.push(
      context,
      LiquidRevealRoute(page: MangaDetailsPage(manga: manga), tapPosition: null),
    ).then((_) => _loadLikedManga());
  }

  void _openAudiobook(Audiobook book) {
    Navigator.push(
      context,
      AudiobookPageRoute(page: AudiobookDetailPage(audiobook: book)),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loadingManga) {
      return const Center(
        child: CircularProgressIndicator(color: Color(0xFF7C5CFF)),
      );
    }

    return LibraryTabs(
      title: 'Library',
      titleIcon: Icons.collections_bookmark_rounded,
      tabs: [
        LibraryTab(
          label: 'Audiobooks',
          icon: Icons.headphones_rounded,
          builder: (_) => _buildAudiobooksTab(),
        ),
        LibraryTab(
          label: 'Manga',
          icon: Icons.auto_stories_rounded,
          builder: (_) => _buildMangaTab(),
        ),
        LibraryTab(
          label: 'History',
          icon: Icons.history_rounded,
          builder: (_) => _buildHistoryTab(),
        ),
      ],
    );
  }

  Widget _buildMangaTab() {
    if (_likedManga.isEmpty) {
      return const LibraryEmptyState(
        icon: Icons.auto_stories_rounded,
        title: 'No liked manga',
        subtitle: 'Tap the heart on a manga to save it here.',
      );
    }
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 200,
        mainAxisSpacing: 24,
        crossAxisSpacing: 16,
        mainAxisExtent: 300,
      ),
      itemCount: _likedManga.length,
      itemBuilder: (context, index) {
        final manga = _likedManga[index];
        return MangaCard(manga: manga, onTap: () => _openManga(manga));
      },
    );
  }

  Widget _buildAudiobooksTab() {
    final liked = AudiobookLibraryService.instance.liked;
    if (liked.isEmpty) {
      return const LibraryEmptyState(
        icon: Icons.headphones_rounded,
        title: 'No liked audiobooks',
        subtitle: 'Tap the heart on an audiobook to save it here.',
      );
    }
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 200,
        mainAxisSpacing: 24,
        crossAxisSpacing: 16,
        mainAxisExtent: 300,
      ),
      itemCount: liked.length,
      itemBuilder: (context, index) {
        final book = liked[index];
        return _LikedAudiobookCard(book: book, onTap: () => _openAudiobook(book));
      },
    );
  }

  Widget _buildHistoryTab() {
    return ValueListenableBuilder<List<PlaybackHistoryItem>>(
      valueListenable: PlaybackHistoryService.history,
      builder: (context, history, _) {
        if (history.isEmpty) {
          return const LibraryEmptyState(
            icon: Icons.history_rounded,
            title: 'No playback history',
            subtitle: 'Audiobooks you listen to will appear here.',
          );
        }
        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
          itemCount: history.length,
          separatorBuilder: (_, __) => const SizedBox(height: 12),
          itemBuilder: (context, index) {
            final item = history[index];
            return Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF12151E),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
              ),
              child: Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: item.poster != null
                        ? Image.network(
                            item.poster!,
                            width: 50,
                            height: 75,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => Container(
                              width: 50,
                              height: 75,
                              color: Colors.white10,
                              child: const Icon(Icons.headphones_rounded,
                                  color: Colors.white30),
                            ),
                          )
                        : Container(
                            width: 50,
                            height: 75,
                            color: Colors.white10,
                            child: const Icon(Icons.headphones_rounded,
                                color: Colors.white30),
                          ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.title,
                          style: const TextStyle(
                              fontWeight: FontWeight.w700, fontSize: 15),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 8),
                        LinearProgressIndicator(
                          value: item.progressPercentage,
                          backgroundColor: Colors.white10,
                          valueColor: const AlwaysStoppedAnimation<Color>(
                              Color(0xFF7C5CFF)),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${(item.progressPercentage * 100).toInt()}% completed',
                          style: const TextStyle(
                              color: Colors.white38, fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded,
                        color: Colors.white38, size: 20),
                    onPressed: () =>
                        PlaybackHistoryService.removeProgress(item.id),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

class _LikedAudiobookCard extends StatelessWidget {
  final Audiobook book;
  final VoidCallback onTap;

  const _LikedAudiobookCard({required this.book, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final hasCover = book.coverImage.isNotEmpty;
    return GestureDetector(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: hasCover
                  ? Image.network(
                      book.coverImage,
                      fit: BoxFit.cover,
                      width: double.infinity,
                      errorBuilder: (_, __, ___) => Container(
                        color: const Color(0xFF141824),
                        child: const Icon(Icons.headphones_rounded,
                            color: Colors.white24, size: 40),
                      ),
                    )
                  : Container(
                      color: const Color(0xFF141824),
                      child: const Icon(Icons.headphones_rounded,
                          color: Colors.white24, size: 40),
                    ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            book.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
