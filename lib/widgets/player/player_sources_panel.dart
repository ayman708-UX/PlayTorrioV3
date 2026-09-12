import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../models/movie/movie_detail.dart';
import '../../models/movie/video.dart';
import '../../models/stream/stream_model.dart';
import '../../services/stream/stream_service.dart';
import '../../services/anime/anime_scraper_service.dart';
import '../../services/anime_arabic/anime_arabic_service.dart';
import '../../services/anime_arabic/anime_arabic_extractor.dart';
import 'player_glass.dart';

/// Glassmorphic Sources Side Panel for selecting episode stream sources,
/// with targeted scraping, episode caching, and error recovery banners.
class PlayerSourcesPanel extends StatefulWidget {
  final Video episode;
  final MovieDetail? detail;
  final String currentAddonName;
  final String? errorMessage;
  final List<StreamSource>? cachedSources;
  final Function(List<StreamSource> sources) onSourcesLoaded;
  final Function(StreamSource source, Video episode) onPlaySource;
  final VoidCallback onBackToEpisodes;
  final VoidCallback onClose;

  const PlayerSourcesPanel({
    super.key,
    required this.episode,
    this.detail,
    required this.currentAddonName,
    this.errorMessage,
    this.cachedSources,
    required this.onSourcesLoaded,
    required this.onPlaySource,
    required this.onBackToEpisodes,
    required this.onClose,
  });

  @override
  State<PlayerSourcesPanel> createState() => _PlayerSourcesPanelState();
}

class _PlayerSourcesPanelState extends State<PlayerSourcesPanel> {
  final List<StreamSource> _sources = [];
  bool _isLoading = false;
  StreamSubscription<StreamSource>? _streamSub;
  int? _hoveredIndex;

  @override
  void initState() {
    super.initState();

    if (widget.cachedSources != null && widget.cachedSources!.isNotEmpty) {
      _sources.addAll(widget.cachedSources!);
      _isLoading = false;
    } else {
      _startScraping();
    }
  }

  void _startScraping() {
    setState(() {
      _sources.clear();
      _isLoading = true;
    });

    final detail = widget.detail;
    final ep = widget.episode;
    final type = detail?.type ?? 'tv';
    final id = ep.id.isNotEmpty
        ? ep.id
        : '${detail?.id ?? ""}:${ep.season ?? 1}:${ep.episode ?? 1}';
    final title = detail?.name ?? ep.title;
    final year = int.tryParse(detail?.year ?? '');
    final epNum = ep.episode ?? 1;

    final isArabicAnime = id.startsWith('arabic_anime:') ||
        (detail?.id.startsWith('arabic_anime:') ?? false) ||
        widget.currentAddonName == 'ArabicAnime';

    _streamSub?.cancel();

    if (isArabicAnime) {
      String slug = '';
      if (detail?.id.startsWith('arabic_anime:') == true) {
        slug = detail!.id.replaceFirst('arabic_anime:', '');
      } else if (id.startsWith('arabic_anime:')) {
        final parts = id.split(':');
        if (parts.length >= 2) slug = parts[1];
      }

      () async {
        try {
          if (slug.isEmpty && title.isNotEmpty) {
            final searchResults = await AnimeArabicService.instance.search(title);
            if (searchResults.isNotEmpty) {
              slug = searchResults.first.slug;
            }
          }

          if (slug.isNotEmpty) {
            final arabicDetails = await AnimeArabicService.instance.getDetails(slug);
            final targetEp = arabicDetails.episodes.firstWhere(
              (e) => e.number == epNum,
              orElse: () => ArabicEpisode(
                number: epNum,
                title: 'الحلقة $epNum',
                encodedHref: '',
                watchPath: '/e/$slug-$epNum#tok',
              ),
            );

            final hits = await AnimeArabicExtractor.instance.resolveEpisode(targetEp);
            final sources = AnimeArabicExtractor.toSources(
              hits,
              animeTitle: arabicDetails.title.isNotEmpty ? arabicDetails.title : title,
              episodeNumber: epNum,
            );

            if (mounted) {
              setState(() {
                _sources.addAll(sources);
                _isLoading = false;
              });
              widget.onSourcesLoaded(List.from(_sources));
            }
            return;
          }
        } catch (e) {
          debugPrint('[PlayerSourcesPanel] Arabic anime scrape error: $e');
        }

        if (mounted) {
          setState(() => _isLoading = false);
        }
      }();
      return;
    }

    final isAnime = type == 'anime' ||
        id.startsWith('anilist:') ||
        (detail?.id.startsWith('anilist:') ?? false) ||
        widget.currentAddonName == 'MegaPlay' ||
        widget.currentAddonName == 'AniDB' ||
        widget.currentAddonName == 'WatchHentai' ||
        widget.currentAddonName == 'Hentaini';

    if (isAnime) {
      int? anilistId;
      if (detail?.id.startsWith('anilist:') == true) {
        anilistId = int.tryParse(detail!.id.replaceFirst('anilist:', ''));
      } else if (id.startsWith('anilist:')) {
        final parts = id.split(':');
        if (parts.length >= 2) {
          anilistId = int.tryParse(parts[1]);
        }
      }

      _streamSub = AnimeScraperService.instance
          .scrapeStreamsByDetails(
        title: title,
        anilistId: anilistId,
        episodeNumber: epNum,
      )
          .listen(
        (source) {
          if (!mounted) return;
          setState(() {
            final exists = _sources.any((s) =>
                (source.url != null && s.url == source.url) ||
                (s.name == source.name && s.title == source.title));
            if (!exists) {
              _sources.add(source);
            }
          });
        },
        onError: (_) {
          if (mounted) setState(() => _isLoading = false);
        },
        onDone: () {
          if (mounted) {
            setState(() => _isLoading = false);
            widget.onSourcesLoaded(List.from(_sources));
          }
        },
      );
      return;
    }

    _streamSub = StreamService.fetchStreamsForTargetAddon(
      targetAddonName: widget.currentAddonName,
      type: type,
      id: id,
      title: title,
      year: year,
      season: ep.season,
      episode: ep.episode,
    ).listen(
      (source) {
        if (!mounted) return;
        setState(() {
          // Deduplicate by URL / infoHash / title
          final exists = _sources.any((s) =>
              (source.infoHash != null && s.infoHash == source.infoHash) ||
              (source.url != null && s.url == source.url) ||
              (s.name == source.name && s.title == source.title));
          if (!exists) {
            _sources.add(source);
          }
        });
      },
      onError: (_) {
        if (mounted) setState(() => _isLoading = false);
      },
      onDone: () {
        if (mounted) {
          setState(() => _isLoading = false);
          widget.onSourcesLoaded(List.from(_sources));
        }
      },
    );
  }

  @override
  void dispose() {
    _streamSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.sizeOf(context).width;
    final isCompact = screenWidth < 680;
    final drawerWidth = isCompact ? screenWidth * 0.94 : 440.0;
    final sNum = widget.episode.season ?? 1;
    final eNum = widget.episode.episode ?? 1;

    return Align(
      alignment: Alignment.centerRight,
      child: SizedBox(
        width: drawerWidth,
        height: MediaQuery.sizeOf(context).height,
        child: Container(
          decoration: BoxDecoration(
          color: const Color(0xF2080C14),
          border: const Border(
            left: BorderSide(color: Color(0x33FFFFFF), width: 1.2),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.85),
              offset: const Offset(-8, 0),
              blurRadius: 36,
            ),
          ],
        ),
        child: ClipRRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // ── Header Bar ──
                _buildHeader(sNum, eNum, isCompact),

                // ── Error Notice Banner (if previous stream failed) ──
                if (widget.errorMessage != null && widget.errorMessage!.isNotEmpty)
                  _buildErrorBanner(widget.errorMessage!, isCompact),

                const Divider(height: 1, color: Color(0x1AFFFFFF)),

                // ── Sources List / Loading / Empty State ──
                Expanded(
                  child: _sources.isEmpty && _isLoading
                      ? _buildLoadingState()
                      : (_sources.isEmpty && !_isLoading
                          ? _buildEmptyState()
                          : _buildSourcesList(isCompact)),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
    );
  }

  Widget _buildHeader(int sNum, int eNum, bool isCompact) {
    return Container(
      padding: EdgeInsets.only(
        top: MediaQuery.paddingOf(context).top + 12,
        left: isCompact ? 12 : 16,
        right: isCompact ? 12 : 16,
        bottom: 12,
      ),
      color: const Color(0x66000000),
      child: Row(
        children: [
          // Back to Episodes Button
          PlayerIconButton(
            size: 36,
            iconSize: 20,
            icon: const Icon(Icons.chevron_left_rounded),
            tooltip: 'Back to Episodes',
            backgroundColor: Colors.white.withValues(alpha: 0.08),
            onPressed: widget.onBackToEpisodes,
          ),
          const SizedBox(width: 10),

          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: PlayerTheme.accent.withValues(alpha: 0.25),
                        borderRadius: BorderRadius.circular(5),
                        border: Border.all(color: PlayerTheme.accent.withValues(alpha: 0.50)),
                      ),
                      child: Text(
                        'S$sNum : E$eNum',
                        style: const TextStyle(
                          color: Color(0xFF9D84FF),
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.4,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        widget.episode.title.isNotEmpty
                            ? widget.episode.title
                            : 'Episode $eNum',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14.5,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.2,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  'Provider: ${widget.currentAddonName}',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.50),
                    fontSize: 11.5,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),

          // Close Drawer Button
          PlayerIconButton(
            size: 36,
            iconSize: 18,
            icon: const Icon(Icons.close_rounded),
            tooltip: 'Close',
            backgroundColor: Colors.white.withValues(alpha: 0.08),
            onPressed: widget.onClose,
          ),
        ],
      ),
    );
  }

  Widget _buildErrorBanner(String message, bool isCompact) {
    return Container(
      margin: EdgeInsets.all(isCompact ? 10 : 14),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(
        color: const Color(0x33EF4444),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0x99EF4444), width: 1.2),
        boxShadow: const [
          BoxShadow(
            color: Color(0x33EF4444),
            blurRadius: 12,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          const Icon(Icons.warning_amber_rounded, color: Color(0xFFFCA5A5), size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                height: 1.3,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLoadingState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(
            width: 32,
            height: 32,
            child: CircularProgressIndicator(
              strokeWidth: 2.8,
              valueColor: AlwaysStoppedAnimation<Color>(PlayerTheme.accent),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Scraping sources (${widget.currentAddonName})...',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.70),
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.search_off_rounded, color: Colors.white.withValues(alpha: 0.30), size: 48),
            const SizedBox(height: 12),
            const Text(
              'No streams found for this episode',
              style: TextStyle(
                color: Colors.white,
                fontSize: 14.5,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Try going back to episodes and choosing another episode or provider.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.50),
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _startScraping,
              icon: const Icon(Icons.refresh_rounded, size: 16),
              label: const Text('Rescrape Sources'),
              style: ElevatedButton.styleFrom(
                backgroundColor: PlayerTheme.accent,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSourcesList(bool isCompact) {
    return ListView.separated(
      physics: const BouncingScrollPhysics(),
      padding: EdgeInsets.symmetric(
        horizontal: isCompact ? 12 : 16,
        vertical: 14,
      ),
      itemCount: _sources.length + (_isLoading ? 1 : 0),
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        if (index == _sources.length && _isLoading) {
          return Container(
            padding: const EdgeInsets.all(12),
            alignment: Alignment.center,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(PlayerTheme.accent),
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  'Scraping additional sources...',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.60),
                    fontSize: 11.5,
                  ),
                ),
              ],
            ),
          );
        }

        final source = _sources[index];
        final isHovered = _hoveredIndex == index;

        return _buildSourceCard(source, index, isHovered, isCompact);
      },
    );
  }

  Widget _buildSourceCard(
    StreamSource source,
    int index,
    bool isHovered,
    bool isCompact,
  ) {
    final title = source.title ?? source.name ?? 'Stream Source';
    final isTorrent = source.infoHash != null && source.infoHash!.isNotEmpty;
    final resolution = _extractResolution(title);

    return MouseRegion(
      onEnter: (_) => setState(() => _hoveredIndex = index),
      onExit: (_) => setState(() => _hoveredIndex = null),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () => widget.onPlaySource(source, widget.episode),
        child: AnimatedScale(
          scale: isHovered ? 1.015 : 1.0,
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOutCubic,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            decoration: BoxDecoration(
              color: isHovered ? const Color(0x331E2435) : const Color(0x1F121722),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isHovered
                    ? PlayerTheme.accent.withValues(alpha: 0.80)
                    : Colors.white.withValues(alpha: 0.10),
                width: isHovered ? 1.4 : 1.0,
              ),
              boxShadow: [
                if (isHovered)
                  BoxShadow(
                    color: PlayerTheme.accent.withValues(alpha: 0.25),
                    blurRadius: 14,
                    offset: const Offset(0, 3),
                  ),
              ],
            ),
            padding: EdgeInsets.all(isCompact ? 10 : 12),
            child: Row(
              children: [
                // Icon / Type Badge
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: isTorrent
                        ? const Color(0x33F59E0B)
                        : const Color(0x337C5CFF),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    isTorrent ? Icons.cloud_download_rounded : Icons.play_arrow_rounded,
                    color: isTorrent ? const Color(0xFFFBBF24) : const Color(0xFF9D84FF),
                    size: 18,
                  ),
                ),
                const SizedBox(width: 12),

                // Source Info
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Badges Row (Resolution, Type, Provider)
                      Row(
                        children: [
                          if (resolution.isNotEmpty) ...[
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                              margin: const EdgeInsets.only(right: 6),
                              decoration: BoxDecoration(
                                color: _getResolutionColor(resolution),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                resolution,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 9.5,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 0.4,
                                ),
                              ),
                            ),
                          ],

                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                            margin: const EdgeInsets.only(right: 6),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.10),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              isTorrent ? 'P2P' : 'HTTP',
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.70),
                                fontSize: 9.5,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),

                          if (source.name != null && source.name!.isNotEmpty) ...[
                            Flexible(
                              child: Text(
                                source.name!,
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.50),
                                  fontSize: 11,
                                  fontWeight: FontWeight.w500,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ],
                      ),

                      const SizedBox(height: 4),

                      // Title
                      Text(
                        title,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          height: 1.25,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),

                const SizedBox(width: 8),

                if (source.isMagnet && source.magnetUrl != null) ...[
                  Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(16),
                      onTap: () {
                        Clipboard.setData(ClipboardData(text: source.magnetUrl!));
                        HapticFeedback.lightImpact();
                        ScaffoldMessenger.of(context).hideCurrentSnackBar();
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.check_circle_rounded, color: Color(0xFF10B981), size: 18),
                                SizedBox(width: 8),
                                Text(
                                  'Magnet link copied to clipboard',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                            backgroundColor: const Color(0xFF1A1D26),
                            behavior: SnackBarBehavior.floating,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            duration: const Duration(seconds: 2),
                          ),
                        );
                      },
                      child: Container(
                        padding: const EdgeInsets.all(7),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.08),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.link_rounded,
                          color: Colors.white70,
                          size: 16,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                ],

                // Play Button Icon
                Container(
                  padding: const EdgeInsets.all(7),
                  decoration: BoxDecoration(
                    color: (isHovered ? PlayerTheme.accent : Colors.white.withValues(alpha: 0.08)),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.play_arrow_rounded,
                    color: Colors.white,
                    size: 16,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _extractResolution(String title) {
    final lower = title.toLowerCase();
    if (lower.contains('4k') || lower.contains('2160p') || lower.contains('uhd')) return '4K';
    if (lower.contains('1080p') || lower.contains('fhd')) return '1080P';
    if (lower.contains('720p') || lower.contains('hd')) return '720P';
    if (lower.contains('480p') || lower.contains('sd')) return '480P';
    return '';
  }

  Color _getResolutionColor(String res) {
    switch (res) {
      case '4K':
        return const Color(0xFF8B5CF6);
      case '1080P':
        return const Color(0xFF10B981);
      case '720P':
        return const Color(0xFF3B82F6);
      default:
        return Colors.white.withValues(alpha: 0.20);
    }
  }
}
