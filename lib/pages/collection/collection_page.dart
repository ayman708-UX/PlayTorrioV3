import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../models/download/download_item.dart';
import '../../models/movie/movie.dart';
import '../../models/my_list/my_list_item.dart';
import '../../models/playback/playback_history_item.dart';
import '../../services/download/download_service.dart';
import '../../services/my_list/my_list_service.dart';
import '../../services/playback/playback_history_service.dart';
import '../../services/trakt/trakt_auth_service.dart';
import '../../services/trakt/trakt_sync_service.dart';
import '../../utils/hub_navigator.dart';
import '../../utils/route_transitions.dart';
import '../details/details_page.dart';

class CollectionPage extends StatefulWidget {
  final int initialTabIndex;

  const CollectionPage({
    super.key,
    this.initialTabIndex = 0,
  });

  @override
  State<CollectionPage> createState() => _CollectionPageState();
}

class _CollectionPageState extends State<CollectionPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final TextEditingController _searchController = TextEditingController();

  String _filterType = 'all'; // 'all', 'movie', 'series', 'anime'
  String _sortBy = 'recent'; // 'recent', 'title', 'year'
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: 4,
      vsync: this,
      initialIndex: widget.initialTabIndex,
    );
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  List<MyListItem> _getFilteredAndSortedItems(List<MyListItem> allItems) {
    var filtered = allItems.where((item) {
      if (_filterType == 'movie' && item.type != 'movie') return false;
      if (_filterType == 'series' && item.type != 'series' && item.type != 'anime') return false;
      if (_filterType == 'anime' && item.type != 'anime') return false;

      if (_searchQuery.trim().isNotEmpty) {
        final query = _searchQuery.toLowerCase().trim();
        final title = item.title.toLowerCase();
        if (!title.contains(query)) return false;
      }
      return true;
    }).toList();

    switch (_sortBy) {
      case 'recent':
        filtered.sort((a, b) => b.addedAt.compareTo(a.addedAt));
        break;
      case 'title':
        filtered.sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
        break;
      case 'year':
        filtered.sort((a, b) => (b.year ?? 0).compareTo(a.year ?? 0));
        break;
    }
    return filtered;
  }

  int _getCrossAxisCount(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    if (width < 600) return 2;
    if (width < 900) return 3;
    if (width < 1200) return 4;
    return 5;
  }

  void _navigateToDetail(MyListItem item) {
    final effectiveId = item.imdbId ??
        (item.tmdbId != null ? 'tmdb:${item.tmdbId}' : null) ??
        item.traktId?.toString() ??
        '';

    final movie = Movie(
      id: effectiveId,
      name: item.title,
      poster: item.poster,
      year: item.year?.toString(),
      type: item.type,
      addonBaseUrl: 'https://v3-cinemeta.strem.io',
    );

    Navigator.push(
      context,
      LiquidRevealRoute(
        page: DetailsPage(movie: movie),
        tapPosition: null,
      ),
    );
  }

  Future<void> _confirmRemove(MyListItem item) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF151822),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Remove from Library?',
            style: TextStyle(fontWeight: FontWeight.w800, color: Colors.white)),
        content: Text(
          'Remove "${item.title}" from your library?',
          style: TextStyle(color: Colors.white.withValues(alpha: 0.7)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel',
                style: TextStyle(color: Colors.white.withValues(alpha: 0.6))),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFE50914),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text('Remove', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      MyListService.remove(item);
    }
  }

  @override
  Widget build(BuildContext context) {
    final traktAuth = TraktAuthService();

    return Scaffold(
      backgroundColor: const Color(0xFF080A0F),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0D1017),
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_rounded, size: 20),
          onPressed: () => HubNavigator.goHome(),
        ),
        title: const Text(
          'Library',
          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 20),
        ),
        actions: [
          ValueListenableBuilder<bool>(
            valueListenable: traktAuth.isLoggedIn,
            builder: (context, loggedIn, _) {
              if (!loggedIn) return const SizedBox.shrink();
              return ValueListenableBuilder<bool>(
                valueListenable: TraktSyncService.isSyncing,
                builder: (context, syncing, _) {
                  return IconButton(
                    tooltip: 'Sync with Trakt',
                    icon: syncing
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Color(0xFFED1C24),
                            ),
                          )
                        : const Icon(
                            Icons.sync_rounded,
                            color: Color(0xFFED1C24),
                            size: 22,
                          ),
                    onPressed: syncing ? null : () => TraktSyncService.manualSync(),
                  );
                },
              );
            },
          ),
          const SizedBox(width: 8),
        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: const Color(0xFF7C5CFF),
          indicatorWeight: 3,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white54,
          labelStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
          tabs: const [
            Tab(icon: Icon(Icons.favorite_rounded, size: 17), text: 'My List'),
            Tab(icon: Icon(Icons.bookmark_rounded, size: 17), text: 'Watchlist'),
            Tab(icon: Icon(Icons.history_rounded, size: 17), text: 'History'),
            Tab(icon: Icon(Icons.download_rounded, size: 17), text: 'Downloads'),
          ],
        ),
      ),
      body: Stack(
        children: [
          TabBarView(
            controller: _tabController,
            children: [
              _buildMyListTab(),
              _buildWatchlistTab(),
              _buildHistoryTab(),
              _buildDownloadsTab(),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMyListTab() {
    return ValueListenableBuilder<List<MyListItem>>(
      valueListenable: MyListService.items,
      builder: (context, allItems, _) {
        final items = _getFilteredAndSortedItems(allItems);

        return Column(
          children: [
            _buildFilterAndSearchBar(allItems.length),
            Expanded(
              child: items.isEmpty
                  ? _buildEmptyState(
                      icon: Icons.video_library_rounded,
                      title: allItems.isEmpty
                          ? 'Your list is empty'
                          : 'No matching items',
                      subtitle: allItems.isEmpty
                          ? 'Add movies, series or anime to access them quickly.'
                          : 'Try adjusting your search or filters.',
                    )
                  : _buildGrid(items),
            ),
          ],
        );
      },
    );
  }

  Widget _buildWatchlistTab() {
    return ValueListenableBuilder<List<MyListItem>>(
      valueListenable: MyListService.items,
      builder: (context, allItems, _) {
        final watchlist = allItems.where((i) => i.isWatchlist).toList();
        final items = _getFilteredAndSortedItems(watchlist);

        return Column(
          children: [
            _buildFilterAndSearchBar(watchlist.length),
            Expanded(
              child: items.isEmpty
                  ? _buildEmptyState(
                      icon: Icons.bookmark_border_rounded,
                      title: watchlist.isEmpty
                          ? 'Watchlist is empty'
                          : 'No matching items',
                      subtitle: watchlist.isEmpty
                          ? 'Save movies or series to watch later.'
                          : 'Try adjusting your search or filters.',
                    )
                  : _buildGrid(items),
            ),
          ],
        );
      },
    );
  }

  Widget _buildHistoryTab() {
    return ValueListenableBuilder<List<PlaybackHistoryItem>>(
      valueListenable: PlaybackHistoryService.history,
      builder: (context, historyItems, _) {
        if (historyItems.isEmpty) {
          return _buildEmptyState(
            icon: Icons.history_rounded,
            title: 'No Playback History',
            subtitle: 'Movies and episodes you watch will appear here so you can continue where you left off.',
          );
        }

        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
          itemCount: historyItems.length,
          separatorBuilder: (_, __) => const SizedBox(height: 12),
          itemBuilder: (context, index) {
            final item = historyItems[index];
            final progressPercent = (item.progressPercentage * 100).toInt();

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
                        ? CachedNetworkImage(
                            imageUrl: item.poster!,
                            width: 50,
                            height: 75,
                            fit: BoxFit.cover,
                            errorWidget: (_, __, ___) => Container(
                              width: 50,
                              height: 75,
                              color: Colors.white10,
                              child: const Icon(Icons.movie_rounded, color: Colors.white30),
                            ),
                          )
                        : Container(
                            width: 50,
                            height: 75,
                            color: Colors.white10,
                            child: const Icon(Icons.movie_rounded, color: Colors.white30),
                          ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.title,
                          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (item.episodeTitle != null) ...[
                          const SizedBox(height: 2),
                          Text(
                            'S${item.seasonNumber ?? 1} E${item.episodeNumber ?? 1} • ${item.episodeTitle!}',
                            style: const TextStyle(color: Colors.white54, fontSize: 12),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                        const SizedBox(height: 8),
                        LinearProgressIndicator(
                          value: item.progressPercentage,
                          backgroundColor: Colors.white10,
                          valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF7C5CFF)),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '$progressPercent% completed',
                          style: const TextStyle(color: Colors.white38, fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, color: Colors.white38, size: 20),
                    onPressed: () => PlaybackHistoryService.removeProgress(item.id),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildDownloadsTab() {
    return ValueListenableBuilder<List<DownloadItem>>(
      valueListenable: DownloadService.downloads,
      builder: (context, downloads, _) {
        if (downloads.isEmpty) {
          return _buildEmptyState(
            icon: Icons.download_done_rounded,
            title: 'No Downloads',
            subtitle: 'Downloaded movies and episodes will appear here for offline viewing.',
          );
        }

        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
          itemCount: downloads.length,
          separatorBuilder: (_, __) => const SizedBox(height: 12),
          itemBuilder: (context, index) {
            final item = downloads[index];
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
                        ? CachedNetworkImage(
                            imageUrl: item.poster!,
                            width: 50,
                            height: 75,
                            fit: BoxFit.cover,
                            errorWidget: (_, __, ___) => Container(
                              width: 50,
                              height: 75,
                              color: Colors.white10,
                              child: const Icon(Icons.movie_rounded, color: Colors.white30),
                            ),
                          )
                        : Container(
                            width: 50,
                            height: 75,
                            color: Colors.white10,
                            child: const Icon(Icons.movie_rounded, color: Colors.white30),
                          ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.title,
                          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (item.episodeTitle != null) ...[
                          const SizedBox(height: 2),
                          Text(
                            item.episodeTitle!,
                            style: const TextStyle(color: Colors.white54, fontSize: 12),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                        const SizedBox(height: 8),
                        LinearProgressIndicator(
                          value: item.progress > 0 ? item.progress : null,
                          backgroundColor: Colors.white10,
                          valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF7C5CFF)),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${item.status.name.toUpperCase()} • ${(item.progress * 100).toStringAsFixed(0)}%',
                          style: const TextStyle(color: Colors.white38, fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent),
                    onPressed: () => DownloadService.removeDownload(item.id),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildFilterAndSearchBar(int totalCount) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Container(
                  height: 40,
                  decoration: BoxDecoration(
                    color: const Color(0xFF141824),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Row(
                    children: [
                      const Icon(Icons.search_rounded, size: 18, color: Colors.white54),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: _searchController,
                          onChanged: (val) => setState(() => _searchQuery = val),
                          style: const TextStyle(fontSize: 13, color: Colors.white),
                          decoration: const InputDecoration(
                            hintText: 'Search library...',
                            hintStyle: TextStyle(color: Colors.white38, fontSize: 13),
                            border: InputBorder.none,
                            isDense: true,
                          ),
                        ),
                      ),
                      if (_searchQuery.isNotEmpty)
                        GestureDetector(
                          onTap: () {
                            _searchController.clear();
                            setState(() => _searchQuery = '');
                          },
                          child: const Icon(Icons.close_rounded, size: 16, color: Colors.white54),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _buildChoiceChip('All', 'all'),
              const SizedBox(width: 6),
              _buildChoiceChip('Movies', 'movie'),
              const SizedBox(width: 6),
              _buildChoiceChip('Series', 'series'),
              const SizedBox(width: 6),
              _buildChoiceChip('Anime', 'anime'),
              const Spacer(),
              PopupMenuButton<String>(
                initialValue: _sortBy,
                tooltip: 'Sort by',
                onSelected: (val) => setState(() => _sortBy = val),
                color: const Color(0xFF151822),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: const Color(0xFF141824),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.sort_rounded, size: 14, color: Colors.white70),
                      const SizedBox(width: 4),
                      Text(
                        _sortBy.toUpperCase(),
                        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white70),
                      ),
                    ],
                  ),
                ),
                itemBuilder: (context) => [
                  const PopupMenuItem(value: 'recent', child: Text('Recently Added')),
                  const PopupMenuItem(value: 'title', child: Text('Title (A-Z)')),
                  const PopupMenuItem(value: 'year', child: Text('Release Year')),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildChoiceChip(String label, String value) {
    final isSelected = _filterType == value;
    return GestureDetector(
      onTap: () => setState(() => _filterType = value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF7C5CFF) : const Color(0xFF141824),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
            color: isSelected ? Colors.white : Colors.white60,
          ),
        ),
      ),
    );
  }

  Widget _buildGrid(List<MyListItem> items) {
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: _getCrossAxisCount(context),
        childAspectRatio: 0.65,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
      ),
      itemCount: items.length,
      itemBuilder: (context, index) {
        final item = items[index];
        return GestureDetector(
          onTap: () => _navigateToDetail(item),
          onLongPress: () => _confirmRemove(item),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (item.poster != null && item.poster!.isNotEmpty)
                  CachedNetworkImage(
                    imageUrl: item.poster!,
                    fit: BoxFit.cover,
                    placeholder: (_, __) => Container(color: const Color(0xFF141824)),
                    errorWidget: (_, __, ___) => Container(
                      color: const Color(0xFF141824),
                      child: const Icon(Icons.movie_rounded, color: Colors.white24),
                    ),
                  )
                else
                  Container(
                    color: const Color(0xFF141824),
                    child: const Icon(Icons.movie_rounded, color: Colors.white24),
                  ),
                Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.bottomCenter,
                        end: Alignment.topCenter,
                        colors: [Colors.black87, Colors.transparent],
                      ),
                    ),
                    child: Text(
                      item.title,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildEmptyState({
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 48, color: Colors.white24),
          const SizedBox(height: 12),
          Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: Colors.white)),
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Text(
              subtitle,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 13, color: Colors.white54),
            ),
          ),
        ],
      ),
    );
  }
}
