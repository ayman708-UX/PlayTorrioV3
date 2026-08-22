import 'dart:async';
import 'package:flutter/material.dart';
import '../../models/anime/anime_media.dart';
import '../../models/stream/stream_model.dart';
import '../../services/anime/anime_scraper_service.dart';
import '../../services/anime/anime_library_service.dart';
import '../../utils/fullscreen_navigator.dart';
import '../player/player_screen.dart';

class AnimeStreamSheet extends StatefulWidget {
  final AnimeMedia anime;
  final int episodeNumber;
  final bool autoPlay;

  const AnimeStreamSheet({
    super.key,
    required this.anime,
    required this.episodeNumber,
    this.autoPlay = false,
  });

  @override
  State<AnimeStreamSheet> createState() => _AnimeStreamSheetState();
}

class _AnimeStreamSheetState extends State<AnimeStreamSheet> {
  final AnimeScraperService _scraper = AnimeScraperService.instance;
  final AnimeLibraryService _library = AnimeLibraryService.instance;

  final List<StreamSource> _allSources = [];
  String _selectedCategory = 'all'; // 'all', 'sub', 'dub'
  bool _isScraping = true;
  String? _error;
  StreamSubscription<StreamSource>? _streamSub;

  @override
  void initState() {
    super.initState();
    _startScraping();
  }

  @override
  void dispose() {
    _streamSub?.cancel();
    super.dispose();
  }

  void _startScraping() {
    setState(() {
      _allSources.clear();
      _isScraping = true;
      _error = null;
    });

    _streamSub = _scraper
        .scrapeStreamsStream(
      anime: widget.anime,
      episodeNumber: widget.episodeNumber,
    )
        .listen(
      (source) {
        if (mounted) {
          setState(() {
            _allSources.add(source);
          });

          if (widget.autoPlay && _allSources.length == 1) {
            _playSource(source);
          }
        }
      },
      onError: (e) {
        if (mounted) {
          setState(() {
            _isScraping = false;
            _error = e.toString();
          });
        }
      },
      onDone: () {
        if (mounted) {
          setState(() {
            _isScraping = false;
            if (_allSources.isEmpty) {
              _error =
                  'No playable streams found for Episode ${widget.episodeNumber}.';
            }
          });
        }
      },
    );
  }

  List<StreamSource> get _filteredSources {
    if (_selectedCategory == 'sub') {
      return _allSources
          .where((s) =>
              !(s.description?.toLowerCase().contains('dub') ?? false) &&
              !(s.name?.toLowerCase().contains('dub') ?? false))
          .toList();
    } else if (_selectedCategory == 'dub') {
      return _allSources
          .where((s) =>
              (s.description?.toLowerCase().contains('dub') ?? false) ||
              (s.name?.toLowerCase().contains('dub') ?? false))
          .toList();
    }
    return _allSources;
  }

  void _playSource(StreamSource source) {
    _library.updateProgress(
      anime: widget.anime,
      episodeNumber: widget.episodeNumber,
      positionSeconds: 1,
      durationSeconds: 1440,
    );

    final detail = AnimeScraperService.toMovieDetail(widget.anime);
    final video =
        AnimeScraperService.toVideo(widget.anime, widget.episodeNumber);

    pushFullscreenReplacement(
      MaterialPageRoute(
        builder: (_) => PlayerScreen(
          source: source,
          title: '${widget.anime.displayTitle} - Episode ${widget.episodeNumber}',
          backdropUrl: widget.anime.backdropUrl,
          detail: detail,
          episode: video,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filteredSources;

    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF0F121C),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag handle
          Container(
            margin: const EdgeInsets.only(top: 12, bottom: 8),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.white24,
              borderRadius: BorderRadius.circular(2),
            ),
          ),

          // Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${widget.anime.displayTitle} • Ep ${widget.episodeNumber}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          if (_isScraping) ...[
                            const SizedBox(
                              width: 12,
                              height: 12,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Color(0xFF7C5CFF),
                              ),
                            ),
                            const SizedBox(width: 8),
                            const Text(
                              'Cascading native anime extractors...',
                              style: TextStyle(
                                color: Color(0xFF7C5CFF),
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ] else
                            Text(
                              '${_allSources.length} sources found',
                              style: const TextStyle(
                                color: Colors.white54,
                                fontSize: 12,
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded, color: Colors.white54),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),

          // Sub / Dub Category Filter Pills
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
            child: Row(
              children: [
                _buildFilterChip('All (${_allSources.length})', 'all'),
                const SizedBox(width: 8),
                _buildFilterChip('Sub', 'sub'),
                const SizedBox(width: 8),
                _buildFilterChip('Dub', 'dub'),
              ],
            ),
          ),

          const SizedBox(height: 6),
          const Divider(color: Colors.white10, height: 1),

          // Stream list
          Flexible(
            child: _allSources.isEmpty && _isScraping
                ? const Padding(
                    padding: EdgeInsets.symmetric(vertical: 40),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircularProgressIndicator(color: Color(0xFF7C5CFF)),
                        SizedBox(height: 14),
                        Text(
                          'Extracting MegaPlay, VidWish, AllAnime & Miruro streams...',
                          style: TextStyle(color: Colors.white70, fontSize: 13),
                        ),
                      ],
                    ),
                  )
                : _allSources.isEmpty && _error != null
                    ? Padding(
                        padding: const EdgeInsets.all(28),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.error_outline_rounded,
                              color: Colors.redAccent,
                              size: 40,
                            ),
                            const SizedBox(height: 10),
                            Text(
                              _error!,
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 13,
                              ),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 14),
                            ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF7C5CFF),
                              ),
                              onPressed: _startScraping,
                              child: const Text('Retry Scraping'),
                            ),
                          ],
                        ),
                      )
                    : filtered.isEmpty
                        ? Padding(
                            padding: const EdgeInsets.all(32),
                            child: Text(
                              'No ${_selectedCategory.toUpperCase()} sources found.',
                              style: const TextStyle(
                                  color: Colors.white54, fontSize: 13),
                            ),
                          )
                        : ListView.separated(
                            shrinkWrap: true,
                            padding: const EdgeInsets.all(16),
                            itemCount: filtered.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: 10),
                            itemBuilder: (context, index) {
                              final s = filtered[index];
                              final isDub =
                                  (s.description?.toLowerCase().contains('dub') ??
                                          false) ||
                                      (s.name?.toLowerCase().contains('dub') ??
                                          false);

                              return Material(
                                color: Colors.transparent,
                                child: InkWell(
                                  onTap: () => _playSource(s),
                                  borderRadius: BorderRadius.circular(14),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                      vertical: 12,
                                    ),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF191C28),
                                      borderRadius: BorderRadius.circular(14),
                                      border: Border.all(
                                        color:
                                            Colors.white.withValues(alpha: 0.08),
                                      ),
                                    ),
                                    child: Row(
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.all(8),
                                          decoration: BoxDecoration(
                                            color: const Color(0xFF7C5CFF)
                                                .withValues(alpha: 0.2),
                                            borderRadius:
                                                BorderRadius.circular(10),
                                          ),
                                          child: const Icon(
                                            Icons.play_circle_fill_rounded,
                                            color: Color(0xFF7C5CFF),
                                            size: 24,
                                          ),
                                        ),
                                        const SizedBox(width: 14),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                s.name ?? 'Stream Source',
                                                style: const TextStyle(
                                                  color: Colors.white,
                                                  fontSize: 14,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                              const SizedBox(height: 3),
                                              Text(
                                                s.description ?? s.addonName,
                                                style: const TextStyle(
                                                  color: Colors.white54,
                                                  fontSize: 11,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 8,
                                            vertical: 4,
                                          ),
                                          decoration: BoxDecoration(
                                            color: isDub
                                                ? Colors.orange
                                                    .withValues(alpha: 0.2)
                                                : Colors.blue
                                                    .withValues(alpha: 0.2),
                                            borderRadius:
                                                BorderRadius.circular(6),
                                          ),
                                          child: Text(
                                            isDub ? 'DUB' : 'SUB',
                                            style: TextStyle(
                                              color: isDub
                                                  ? Colors.orangeAccent
                                                  : Colors.lightBlueAccent,
                                              fontSize: 10,
                                              fontWeight: FontWeight.w900,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChip(String label, String category) {
    final isSelected = _selectedCategory == category;
    return GestureDetector(
      onTap: () => setState(() => _selectedCategory = category),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected
              ? const Color(0xFF7C5CFF)
              : Colors.white.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected
                ? const Color(0xFF7C5CFF)
                : Colors.white.withValues(alpha: 0.12),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.white : Colors.white70,
            fontSize: 12,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
          ),
        ),
      ),
    );
  }
}
