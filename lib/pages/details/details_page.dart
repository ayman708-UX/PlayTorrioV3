import 'dart:ui';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../models/movie/cast_member.dart';
import '../../models/movie/movie.dart';
import '../../models/movie/video.dart';
import '../../models/movie/movie_detail.dart';
import '../../models/my_list/my_list_item.dart';
import '../../services/addon/addon_manager.dart';
import '../../services/metadata/bestsimilar_scraper.dart';
import '../../services/metadata/metadata_service.dart';
import '../../services/my_list/my_list_service.dart';
import '../../utils/route_transitions.dart';
import '../discover/discover_page.dart';
import '../player/watch_screen.dart';
// ---------------------------------------------------------------------------
// Design tokens
// ---------------------------------------------------------------------------
class _Space {
  static const xs = 8.0;
  static const sm = 12.0;
  static const md = 16.0;
  static const lg = 24.0;
  static const xl = 32.0;
  static const xxl = 48.0;
}

class _Palette {
  static const bg = Color(0xFF0B0D12);
  static const surface = Color(0xFF15171F);
  static const accent = Color(0xFFE50914);
  static const accentDim = Color(0xFF9A0710);
  static const gold = Color(0xFFFFC107);

  static const avatarPairs = [
    [Color(0xFF3A1C71), Color(0xFFD76D77)],
    [Color(0xFF11998E), Color(0xFF38EF7D)],
    [Color(0xFF1F4037), Color(0xFF99F2C8)],
    [Color(0xFF2C3E50), Color(0xFF4CA1AF)],
    [Color(0xFF614385), Color(0xFF516395)],
    [Color(0xFF232526), Color(0xFF6E6E6E)],
  ];
}

class DetailsPage extends StatefulWidget {
  final Movie movie;

  /// Optional "More Like This" row. Not every addon/catalog gives you
  /// recommendations for free — pass in whatever list of Movie you already
  /// have (e.g. same-genre catalog results, or a recommendations field if
  /// your addon's meta response includes one). Section just doesn't render
  /// if this is null/empty, so it's safe to leave unset for now.
  final List<Movie>? relatedItems;

  const DetailsPage({
    super.key,
    required this.movie,
    this.relatedItems,
  });

  @override
  State<DetailsPage> createState() => _DetailsPageState();
}

class _DetailsPageState extends State<DetailsPage> with SingleTickerProviderStateMixin {
  MovieDetail? _detail;
  bool _isLoading = true;

  int? _selectedSeason;
  int? _previousSeason;
  List<Video> _currentSeasonEpisodes = [];

  bool _isSynopsisExpanded = false;

  // Similar content from BestSimilar
  List<BSItem> _similarItems = [];
  bool _isFetchingSimilar = false;

  late AnimationController _animController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  final Map<int, ScrollController> _episodeControllers = {};
  
  ScrollController get _episodeScrollController {
    final key = _selectedSeason ?? -1;
    if (!_episodeControllers.containsKey(key)) {
      final c = ScrollController();
      c.addListener(_updateEpisodeScrollButtons);
      _episodeControllers[key] = c;
    }
    return _episodeControllers[key]!;
  }

  final ScrollController _castScrollController = ScrollController();
  final ScrollController _seasonScrollController = ScrollController();
  final ScrollController _relatedScrollController = ScrollController();
  final ScrollController _similarScrollController = ScrollController();

  bool _canScrollEpisodesLeft = false;
  bool _canScrollEpisodesRight = true;
  bool _isHoveringEpisodes = false;

  bool _canScrollCastLeft = false;
  bool _canScrollCastRight = true;
  bool _isHoveringCast = false;

  bool _canScrollRelatedLeft = false;
  bool _canScrollRelatedRight = true;
  bool _isHoveringRelated = false;

  bool _canScrollSeasonsLeft = false;
  bool _canScrollSeasonsRight = true;
  bool _isHoveringSeasons = false;

  bool _canScrollSimilarLeft = false;
  bool _canScrollSimilarRight = true;
  bool _isHoveringSimilar = false;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(vsync: this, duration: const Duration(milliseconds: 650));
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0)
        .animate(CurvedAnimation(parent: _animController, curve: Curves.easeOut));
    _slideAnimation = Tween<Offset>(begin: const Offset(0, 0.04), end: Offset.zero)
        .animate(CurvedAnimation(parent: _animController, curve: Curves.easeOutCubic));

    _castScrollController.addListener(_updateCastScrollButtons);
    _relatedScrollController.addListener(_updateRelatedScrollButtons);
    _seasonScrollController.addListener(_updateSeasonScrollButtons);
    _similarScrollController.addListener(_updateSimilarScrollButtons);

    _fetchDetails();
  }

  @override
  void dispose() {
    _animController.dispose();
    for (final c in _episodeControllers.values) {
      c.dispose();
    }
    _castScrollController.dispose();
    _seasonScrollController.dispose();
    _relatedScrollController.dispose();
    _similarScrollController.dispose();
    super.dispose();
  }

  Future<void> _handlePlayAction(Video? ep) async {
    if (_detail == null) return;
    
    Navigator.push(
      context,
      CinematicSlideRoute(
        page: WatchScreen(
          detail: _detail!,
          type: widget.movie.type,
          selectedEpisode: ep,
        ),
      ),
    );
  }

  void _updateEpisodeScrollButtons() {
    if (!_episodeScrollController.hasClients) return;
    final canLeft = _episodeScrollController.position.pixels > 0;
    final canRight = _episodeScrollController.position.pixels < _episodeScrollController.position.maxScrollExtent;
    if (_canScrollEpisodesLeft != canLeft || _canScrollEpisodesRight != canRight) {
      setState(() {
        _canScrollEpisodesLeft = canLeft;
        _canScrollEpisodesRight = canRight;
      });
    }
  }

  void _updateCastScrollButtons() {
    if (!_castScrollController.hasClients) return;
    final canLeft = _castScrollController.position.pixels > 0;
    final canRight = _castScrollController.position.pixels < _castScrollController.position.maxScrollExtent;
    if (_canScrollCastLeft != canLeft || _canScrollCastRight != canRight) {
      setState(() {
        _canScrollCastLeft = canLeft;
        _canScrollCastRight = canRight;
      });
    }
  }

  void _updateRelatedScrollButtons() {
    if (!_relatedScrollController.hasClients) return;
    final canLeft = _relatedScrollController.position.pixels > 0;
    final canRight = _relatedScrollController.position.pixels < _relatedScrollController.position.maxScrollExtent;
    if (_canScrollRelatedLeft != canLeft || _canScrollRelatedRight != canRight) {
      setState(() {
        _canScrollRelatedLeft = canLeft;
        _canScrollRelatedRight = canRight;
      });
    }
  }

  void _updateSeasonScrollButtons() {
    if (!_seasonScrollController.hasClients) return;
    final canLeft = _seasonScrollController.position.pixels > 0;
    final canRight = _seasonScrollController.position.pixels < _seasonScrollController.position.maxScrollExtent;
    if (_canScrollSeasonsLeft != canLeft || _canScrollSeasonsRight != canRight) {
      setState(() {
        _canScrollSeasonsLeft = canLeft;
        _canScrollSeasonsRight = canRight;
      });
    }
  }

  void _updateSimilarScrollButtons() {
    if (!_similarScrollController.hasClients) return;
    final canLeft = _similarScrollController.position.pixels > 0;
    final canRight = _similarScrollController.position.pixels < _similarScrollController.position.maxScrollExtent;
    if (_canScrollSimilarLeft != canLeft || _canScrollSimilarRight != canRight) {
      setState(() {
        _canScrollSimilarLeft = canLeft;
        _canScrollSimilarRight = canRight;
      });
    }
  }

  void _scrollList(ScrollController controller, double directionMultiplier) {
    if (!controller.hasClients) return;
    final viewportWidth = controller.position.viewportDimension;
    final scrollAmount = viewportWidth * 0.7 * directionMultiplier;
    final target = (controller.position.pixels + scrollAmount).clamp(0.0, controller.position.maxScrollExtent);
    controller.animateTo(target, duration: const Duration(milliseconds: 450), curve: Curves.easeOutCubic);
  }

  Future<void> _fetchDetails() async {
    final meta = await MetadataService.fetchMeta(
      baseUrl: widget.movie.addonBaseUrl,
      type: widget.movie.type,
      imdbId: widget.movie.id,
    );

    if (mounted) {
      setState(() {
        _detail = meta;
        _isLoading = false;

        if (meta != null && (widget.movie.type == 'series' || widget.movie.type == 'anime') && meta.videos.isNotEmpty) {
          final seasons = meta.videos.map((v) => v.season).where((s) => s != null).toSet().toList();
          seasons.sort();
          if (seasons.isNotEmpty) {
            _selectedSeason = seasons.first;
            _updateEpisodesForSeason();
          }
        }
      });
      _animController.forward();
      
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _updateSeasonScrollButtons();
          _updateCastScrollButtons();
          _updateRelatedScrollButtons();
        }
      });

      // Fire off similar content fetch in background
      _fetchSimilarContent();
    }
  }

  Future<void> _fetchSimilarContent() async {
    if (_isFetchingSimilar) return;
    setState(() => _isFetchingSimilar = true);

    try {
      final title = _detail?.name ?? widget.movie.name;
      final yearStr = _detail?.year ?? widget.movie.year;
      final year = yearStr != null ? int.tryParse(yearStr.replaceAll(RegExp(r'[^0-9]'), '')) : null;
      final isTv = widget.movie.type == 'series' || widget.movie.type == 'anime';

      final hit = await BestSimilarScraper.findBest(
        title: title,
        year: year,
        isTv: isTv,
      );

      if (hit == null || !mounted) {
        if (mounted) setState(() => _isFetchingSimilar = false);
        return;
      }

      final details = await BestSimilarScraper.fetchDetails(
        id: hit.id,
        slug: hit.slug,
      );

      if (mounted) {
        setState(() {
          _similarItems = details?.similar ?? [];
          _isFetchingSimilar = false;
        });
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _updateSimilarScrollButtons();
        });
      }
    } catch (e) {
      debugPrint('[Similar] fetch failed: $e');
      if (mounted) setState(() => _isFetchingSimilar = false);
    }
  }

  Future<void> _openSimilarItem(BSItem item) async {
    final type = widget.movie.type;
    final baseUrl = widget.movie.addonBaseUrl;

    // Find search-capable catalogs on the original addon
    final manager = AddonManager.instance;
    final addon = manager.activeAddons.where((a) => a.baseUrl == baseUrl).firstOrNull;
    if (addon == null) return;

    final searchCatalogs = addon.manifest.catalogs
        .where((c) => c.supportsSearch && c.type == type)
        .toList();

    Movie? found;
    for (final catalog in searchCatalogs) {
      try {
        final results = await MetadataService.search(
          baseUrl: baseUrl,
          type: type,
          catalogId: catalog.id,
          query: item.title,
        );
        // Try to match by title and year
        for (final r in results) {
          final nameMatch = r.name.toLowerCase().trim() == item.title.toLowerCase().trim();
          final yearMatch = item.year == null ||
              r.year == null ||
              r.year == '${item.year}' ||
              r.year == '${item.year}-';
          if (nameMatch && yearMatch) {
            found = r;
            break;
          }
        }
        // If exact match not found, take first result with matching name
        if (found == null) {
          for (final r in results) {
            if (r.name.toLowerCase().trim() == item.title.toLowerCase().trim()) {
              found = r;
              break;
            }
          }
        }
        if (found != null) break;
      } catch (_) {}
    }

    if (found != null && mounted) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => DetailsPage(movie: found!)),
      );
    }
  }

  void _updateEpisodesForSeason() {
    if (_detail == null || _selectedSeason == null) return;
    setState(() {
      _currentSeasonEpisodes = _detail!.videos.where((v) => v.season == _selectedSeason).toList();
      _currentSeasonEpisodes.sort((a, b) => (a.episode ?? 0).compareTo(b.episode ?? 0));
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_episodeScrollController.hasClients) _episodeScrollController.jumpTo(0);
      _updateEpisodeScrollButtons();
    });
  }

  bool _isDesktop() {
    if (kIsWeb) return true;
    return defaultTargetPlatform == TargetPlatform.windows ||
        defaultTargetPlatform == TargetPlatform.macOS ||
        defaultTargetPlatform == TargetPlatform.linux;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _Palette.bg,
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: _Palette.accent))
          : _detail == null
              ? _buildError()
              : _buildContent(context),
    );
  }

  Widget _buildError() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.broken_image_rounded, size: 64, color: Colors.white24),
          const SizedBox(height: _Space.md),
          const Text('Details unavailable.', style: TextStyle(color: Colors.white54, fontSize: 18)),
          const SizedBox(height: _Space.lg),
          ElevatedButton(
            onPressed: () => Navigator.pop(context),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.white10, foregroundColor: Colors.white),
            child: const Text('Go Back'),
          )
        ],
      ),
    );
  }

  Widget _buildContent(BuildContext context) {
    final meta = _detail!;
    final bgUrl = meta.background ?? meta.poster ?? widget.movie.poster;
    final posterUrl = meta.poster ?? widget.movie.poster;
    final isDesktop = _isDesktop();
    final screenSize = MediaQuery.sizeOf(context);

    // This is now just how far down the *content* starts — the backdrop
    // itself is full-viewport and persistent (see _buildBackdrop), so this
    // no longer controls when the image "runs out".
    final heroHeight = (screenSize.height * (isDesktop ? 0.46 : 0.4)).clamp(320.0, 520.0);
    final contentMaxWidth = isDesktop ? 1440.0 : double.infinity;
    final overlap = isDesktop ? 120.0 : 70.0;

    return Stack(
      children: [
        if (bgUrl != null) _buildBackdrop(bgUrl, screenSize),
        Positioned.fill(
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            child: Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: contentMaxWidth),
                child: SlideTransition(
                  position: _slideAnimation,
                  child: FadeTransition(
                    opacity: _fadeAnimation,
                    child: Padding(
                      padding: EdgeInsets.symmetric(horizontal: isDesktop ? _Space.xxl : _Space.lg),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(height: heroHeight - overlap),
                          isDesktop ? _buildDesktopLayout(meta, posterUrl) : _buildMobileLayout(meta, posterUrl),
                          const SizedBox(height: _Space.xl),
                          if (meta.castMembers.isNotEmpty || meta.cast.isNotEmpty) ...[
                            _buildCastRow(meta),
                            const SizedBox(height: _Space.xl),
                          ],
                          if (meta.directorsList.isNotEmpty || meta.director.isNotEmpty) ...[
                            _buildDirectorRow(meta),
                            const SizedBox(height: _Space.xl),
                          ],
                          if ((widget.movie.type == 'series' || widget.movie.type == 'anime') && meta.videos.isNotEmpty) ...[
                            _buildSeasonSelector(meta),
                            const SizedBox(height: _Space.lg),
                            AnimatedSwitcher(
                              duration: const Duration(milliseconds: 550),
                              switchInCurve: Curves.easeOutCubic,
                              switchOutCurve: Curves.easeInCubic,
                              layoutBuilder: (currentChild, previousChildren) {
                                return Stack(
                                  alignment: Alignment.topCenter,
                                  children: <Widget>[
                                    ...previousChildren,
                                    if (currentChild != null) currentChild,
                                  ],
                                );
                              },
                              transitionBuilder: (Widget child, Animation<double> animation) {
                                final isIncoming = child.key == ValueKey(_selectedSeason);
                                final int incomingSeason = _selectedSeason ?? 1;
                                final int previousSeason = _previousSeason ?? 1;
                                
                                final bool slidingRight = incomingSeason > previousSeason;
                                
                                // Incoming starts offset, Outgoing ends offset
                                final Offset beginOffset = isIncoming 
                                    ? (slidingRight ? const Offset(0.12, 0.0) : const Offset(-0.12, 0.0))
                                    : (slidingRight ? const Offset(-0.12, 0.0) : const Offset(0.12, 0.0));
                                    
                                final slideAnimation = Tween<Offset>(
                                  begin: beginOffset,
                                  end: Offset.zero,
                                ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOutCubic));

                                final scaleAnimation = Tween<double>(
                                  begin: 0.94,
                                  end: 1.0,
                                ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOutCubic));

                                return FadeTransition(
                                  opacity: animation,
                                  child: SlideTransition(
                                    position: slideAnimation,
                                    child: ScaleTransition(
                                      scale: scaleAnimation,
                                      child: child,
                                    ),
                                  ),
                                );
                              },
                              child: _buildEpisodeSlider(key: ValueKey(_selectedSeason)),
                            ),
                            const SizedBox(height: _Space.xl),
                          ],
                          if (widget.relatedItems != null && widget.relatedItems!.isNotEmpty) ...[
                            _buildRelatedRow(widget.relatedItems!),
                            const SizedBox(height: _Space.xl),
                          ],
                          if (_similarItems.isNotEmpty) ...[
                            _buildSimilarRow(),
                            const SizedBox(height: _Space.xl),
                          ] else if (_isFetchingSimilar) ...[
                            _buildSectionHeader('Similar Content'),
                            const Center(
                              child: Padding(
                                padding: EdgeInsets.symmetric(vertical: 40),
                                child: SizedBox(
                                  width: 24, height: 24,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.5,
                                    color: _Palette.accent,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: _Space.xl),
                          ],
                          const SizedBox(height: _Space.xxl),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        Positioned(
          top: _Space.lg,
          left: isDesktop ? _Space.xxl : _Space.md,
          child: ClipOval(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
              child: IconButton(
                icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 20),
                onPressed: () => Navigator.pop(context),
                style: IconButton.styleFrom(
                  backgroundColor: Colors.white.withOpacity(0.1),
                  padding: const EdgeInsets.all(12),
                  side: BorderSide(color: Colors.white.withOpacity(0.12)),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  // -------------------------------------------------------------------------
  // Persistent, full-viewport cinematic backdrop.
  //
  // Unlike a hero strip that gets cropped to a fixed height and then hands
  // off to flat background color, this sits behind the *entire* screen and
  // stays there while the foreground scrolls over it — so the image never
  // abruptly disappears, it just gradually recedes under layered scrims.
  // Three separate gradients do different jobs so no single one has to be
  // aggressive enough to look like a hard cutoff:
  //   1. a soft cap at the very top (keeps the back button legible)
  //   2. a slow bottom fade that only reaches solid bg near ~90% down
  //   3. a gentle horizontal wash so text on the left never fights the image
  // -------------------------------------------------------------------------
  Widget _buildBackdrop(String bgUrl, Size screenSize) {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      height: screenSize.height,
      child: FadeTransition(
        opacity: _fadeAnimation,
        child: Stack(
          fit: StackFit.expand,
          children: [
            CachedNetworkImage(imageUrl: bgUrl, fit: BoxFit.cover, alignment: Alignment.topCenter),
            // horizontal wash — darkens where the title/synopsis sit, leaves
            // the rest of the image breathing room instead of blacking it all out
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                  colors: [_Palette.bg, Color(0x991A1D26), Colors.transparent],
                  stops: [0.0, 0.42, 0.82],
                ),
              ),
            ),
            // slow bottom fade — the whole point of the fix: this used to
            // resolve to solid bg by ~70% of a 300-460px strip, now it takes
            // nearly the full viewport height to settle
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.transparent, Color(0x661A1D26), _Palette.bg],
                  stops: [0.0, 0.62, 0.94],
                ),
              ),
            ),
            // top cap so the back button always has contrast
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.black45, Colors.transparent],
                  stops: [0.0, 0.22],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // -------------------------------------------------------------------------
  // Desktop: real two-column layout. Poster + actions pinned left;
  // logo/title, metadata, synopsis fill the right. With the backdrop now
  // persistent behind everything, this row no longer needs a "quick facts"
  // filler box just to feel less empty underneath the poster — genres are
  // already in the metadata line, so it's dropped to avoid repeating itself.
  // -------------------------------------------------------------------------
  Widget _buildDesktopLayout(MovieDetail meta, String? posterUrl) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 280,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (posterUrl != null)
                DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: [
                      // subtle accent-tinted glow behind the poster, on top
                      // of the usual drop shadow, so it reads as "lit" rather
                      // than just floating on black
                      BoxShadow(color: _Palette.accent.withOpacity(0.18), blurRadius: 46, spreadRadius: -6),
                      BoxShadow(color: Colors.black.withOpacity(0.55), blurRadius: 30, offset: const Offset(0, 14)),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: AspectRatio(
                      aspectRatio: 2 / 3,
                      child: CachedNetworkImage(
                        imageUrl: posterUrl,
                        fit: BoxFit.cover,
                        errorWidget: (_, __, ___) => const ColoredBox(color: _Palette.surface),
                      ),
                    ),
                  ),
                ),
              const SizedBox(height: _Space.lg),
              _buildPlayButton(fullWidth: true),
              const SizedBox(height: _Space.sm),
              _buildLibraryButton(fullWidth: true),
            ],
          ),
        ),
        const SizedBox(width: _Space.xl),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildLogoOrTitle(meta, isDesktop: true),
              const SizedBox(height: _Space.md),
              _buildMetadataRow(meta),
              if (meta.description != null && meta.description!.isNotEmpty) ...[
                const SizedBox(height: _Space.lg),
                _buildSynopsis(meta.description!),
              ],
              if (meta.genres.isNotEmpty) ...[
                const SizedBox(height: _Space.lg),
                _buildGenreChips(meta.genres),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildMobileLayout(MovieDetail meta, String? posterUrl) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            if (posterUrl != null)
              DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  boxShadow: [
                    BoxShadow(color: _Palette.accent.withOpacity(0.16), blurRadius: 28, spreadRadius: -4),
                    BoxShadow(color: Colors.black.withOpacity(0.5), blurRadius: 16, offset: const Offset(0, 8)),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: CachedNetworkImage(imageUrl: posterUrl, width: 110, fit: BoxFit.cover),
                ),
              ),
            const SizedBox(width: _Space.md),
            Expanded(child: _buildLogoOrTitle(meta, isDesktop: false)),
          ],
        ),
        const SizedBox(height: _Space.lg),
        _buildMetadataRow(meta),
        const SizedBox(height: _Space.lg),
        Row(
          children: [
            Expanded(child: _buildPlayButton(fullWidth: true)),
            const SizedBox(width: _Space.sm),
            _buildLibraryButton(fullWidth: false),
          ],
        ),
        if (meta.description != null && meta.description!.isNotEmpty) ...[
          const SizedBox(height: _Space.lg),
          _buildSynopsis(meta.description!),
        ],
        if (meta.genres.isNotEmpty) ...[
          const SizedBox(height: _Space.md),
          _buildGenreChips(meta.genres),
        ],
      ],
    );
  }

  // Logo is now capped in both width AND height, so it can never dwarf the
  // poster next to it the way it did before (that's what made the poster
  // look like an afterthought in the screenshot).
  Widget _buildLogoOrTitle(MovieDetail meta, {required bool isDesktop}) {
    if (meta.logo != null && meta.logo!.isNotEmpty) {
      return ConstrainedBox(
        constraints: BoxConstraints(maxWidth: isDesktop ? 380 : 220, maxHeight: isDesktop ? 130 : 80),
        child: CachedNetworkImage(
          imageUrl: meta.logo!,
          alignment: Alignment.bottomLeft,
          fit: BoxFit.contain,
          errorWidget: (_, __, ___) => _buildTextTitle(meta.name, isDesktop),
        ),
      );
    }
    return _buildTextTitle(meta.name, isDesktop);
  }

  Widget _buildTextTitle(String text, bool isDesktop) {
    return Text(
      text,
      style: TextStyle(
        fontSize: isDesktop ? 40 : 28,
        fontWeight: FontWeight.w800,
        height: 1.1,
        letterSpacing: -1.0,
        color: Colors.white,
        shadows: [Shadow(color: Colors.black.withOpacity(0.7), blurRadius: 20, offset: const Offset(0, 6))],
      ),
    );
  }

  // Small pill chips for genres, sitting under the synopsis. This replaces
  // the old boxed "Quick Facts" panel — same information, but styled as a
  // lightweight row instead of a card that left dead space under the poster.
  Widget _buildGenreChips(List<String> genres) {
    return Wrap(
      spacing: _Space.xs,
      runSpacing: _Space.xs,
      children: genres
          .map(
            (g) {
              Offset? lastTap;
              return GestureDetector(
                onTapDown: (d) => lastTap = d.globalPosition,
                onTap: () {
                  Navigator.push(
                    context,
                    LiquidRevealRoute(
                      page: DiscoverPage(query: g, isGenre: true),
                      tapPosition: lastTap,
                    ),
                  );
                },
                child: MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.06),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.white.withOpacity(0.12)),
                    ),
                    child: Text(g, style: const TextStyle(color: Colors.white70, fontSize: 12.5, fontWeight: FontWeight.w600)),
                  ),
                ),
              );
            },
          )
          .toList(),
    );
  }

  Widget _buildMetadataRow(MovieDetail meta) {
    final List<Widget> items = [];

    if (meta.year != null && meta.year!.isNotEmpty) {
      items.add(Text(meta.year!, style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600)));
    }

    if (widget.movie.type == 'series' || widget.movie.type == 'anime') {
      final seasonCount = meta.videos.map((v) => v.season).where((s) => s != null).toSet().length;
      if (seasonCount > 0) {
        items.add(Text('$seasonCount Season${seasonCount > 1 ? "s" : ""}',
            style: const TextStyle(color: Colors.white70, fontSize: 14)));
      }
    } else if (meta.runtime != null && meta.runtime!.isNotEmpty) {
      items.add(Text(meta.runtime!, style: const TextStyle(color: Colors.white70, fontSize: 14)));
    }

    if (meta.imdbRating != null && meta.imdbRating!.isNotEmpty) {
      items.add(
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.12),
            borderRadius: BorderRadius.circular(5),
            border: Border.all(color: Colors.white.withOpacity(0.25)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.star_rounded, color: _Palette.gold, size: 14),
              const SizedBox(width: 4),
              Text(meta.imdbRating!, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
            ],
          ),
        ),
      );
    }

    if (meta.genres.isNotEmpty) {
      items.add(Text(meta.genres.take(3).join(' · '), style: const TextStyle(color: Colors.white70, fontSize: 14)));
    }

    final List<Widget> spaced = [];
    for (int i = 0; i < items.length; i++) {
      spaced.add(items[i]);
      if (i < items.length - 1) {
        spaced.add(const Padding(
          padding: EdgeInsets.symmetric(horizontal: _Space.sm),
          child: Text('•', style: TextStyle(color: Colors.white30, fontSize: 16)),
        ));
      }
    }

    return Wrap(crossAxisAlignment: WrapCrossAlignment.center, runSpacing: 6, children: spaced);
  }

  Widget _buildPlayButton({required bool fullWidth}) {
    return _HoverButton(
      onTap: () => _handlePlayAction(
        (widget.movie.type == 'series' || widget.movie.type == 'anime') && _currentSeasonEpisodes.isNotEmpty
            ? _currentSeasonEpisodes.first
            : null,
      ),
      child: Container(
        width: fullWidth ? double.infinity : null,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        decoration: BoxDecoration(
          gradient: const LinearGradient(colors: [_Palette.accent, _Palette.accentDim]),
          borderRadius: BorderRadius.circular(8),
          boxShadow: [BoxShadow(color: _Palette.accent.withOpacity(0.35), blurRadius: 16, offset: const Offset(0, 4))],
        ),
        child: Row(
          mainAxisSize: fullWidth ? MainAxisSize.max : MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 24),
            const SizedBox(width: 6),
            Text(
              (widget.movie.type == 'series' || widget.movie.type == 'anime') ? 'Play Episodes' : 'Play Movie',
              style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLibraryButton({required bool fullWidth}) {
    return ValueListenableBuilder<List<MyListItem>>(
      valueListenable: MyListService.items,
      builder: (context, items, _) {
        final inList = _detail != null &&
            MyListService.isInList(
              MyListItem.fromMovieDetail(
                id: _detail!.id,
                name: _detail!.name,
                poster: _detail!.poster,
                year: _detail!.year,
                type: _detail!.type,
                imdbId: _detail!.id.startsWith('tt') ? _detail!.id : null,
                tmdbId: _detail!.tmdbId != null ? int.tryParse(_detail!.tmdbId!) : null,
              ),
            );

        return _HoverButton(
          onTap: () => _toggleMyList(),
          child: Container(
            width: fullWidth ? double.infinity : null,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            decoration: BoxDecoration(
              color: inList
                  ? const Color(0xFF7C5CFF).withOpacity(0.18)
                  : Colors.white.withOpacity(0.08),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: inList
                    ? const Color(0xFF7C5CFF).withOpacity(0.35)
                    : Colors.white.withOpacity(0.14),
              ),
            ),
            child: Row(
              mainAxisSize: fullWidth ? MainAxisSize.max : MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  inList ? Icons.bookmark_added_rounded : Icons.bookmark_add_outlined,
                  color: inList ? const Color(0xFF7C5CFF) : Colors.white,
                  size: 22,
                ),
                const SizedBox(width: 6),
                Text(
                  inList ? 'In Library' : 'Add to Library',
                  style: TextStyle(
                    color: inList ? const Color(0xFF7C5CFF) : Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _toggleMyList() {
    if (_detail == null) return;

    final item = MyListItem.fromMovieDetail(
      id: _detail!.id,
      name: _detail!.name,
      poster: _detail!.poster,
      year: _detail!.year,
      type: _detail!.type,
      imdbId: _detail!.id.startsWith('tt') ? _detail!.id : null,
      tmdbId: _detail!.tmdbId != null ? int.tryParse(_detail!.tmdbId!) : null,
    );

    MyListService.toggle(item);
  }

  Widget _buildSynopsis(String text) {
    const style = TextStyle(color: Colors.white70, fontSize: 15, height: 1.55, letterSpacing: 0.2);
    const maxLines = 3;

    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth = constraints.maxWidth.clamp(0.0, 720.0);
        final tp = TextPainter(
          text: TextSpan(text: text, style: style),
          maxLines: maxLines,
          textDirection: TextDirection.ltr,
        )..layout(maxWidth: maxWidth);

        final isOverflowing = tp.didExceedMaxLines;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: AnimatedSize(
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeInOut,
                alignment: Alignment.topCenter,
                child: Text(
                  text,
                  maxLines: _isSynopsisExpanded ? null : maxLines,
                  overflow: _isSynopsisExpanded ? TextOverflow.visible : TextOverflow.fade,
                  style: style,
                ),
              ),
            ),
            if (isOverflowing) ...[
              const SizedBox(height: _Space.xs),
              GestureDetector(
                onTap: () => setState(() => _isSynopsisExpanded = !_isSynopsisExpanded),
                child: Text(
                  _isSynopsisExpanded ? 'Show less' : 'Read more',
                  style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ],
        );
      },
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: _Space.md),
      child: Text(title, style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold, letterSpacing: -0.3)),
    );
  }

  Widget _buildCastRow(MovieDetail meta) {
    final List<CastMember> members = meta.castMembers.isNotEmpty
        ? meta.castMembers
        : meta.cast.map((c) => CastMember(name: c)).toList();

    return MouseRegion(
      onEnter: (_) => setState(() => _isHoveringCast = true),
      onExit: (_) => setState(() => _isHoveringCast = false),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionHeader('Cast'),
          SizedBox(
            height: 148,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                ListView.separated(
                  clipBehavior: Clip.none,
                  controller: _castScrollController,
                  scrollDirection: Axis.horizontal,
                  physics: const BouncingScrollPhysics(),
                  itemCount: members.length,
                  separatorBuilder: (_, __) => const SizedBox(width: _Space.lg),
                  itemBuilder: (context, index) {
                    final member = members[index];
                    final name = member.name;
                    final initials = name.isNotEmpty
                        ? name.trim().split(' ').map((e) => e.isNotEmpty ? e[0] : '').take(2).join('').toUpperCase()
                        : '?';
                    final pair = _Palette.avatarPairs[name.hashCode.abs() % _Palette.avatarPairs.length];

                    return SizedBox(
                      width: 88,
                      child: Column(
                        children: [
                          Builder(
                            builder: (context) {
                              Offset? lastTap;
                              return GestureDetector(
                                onTapDown: (d) => lastTap = d.globalPosition,
                                child: _HoverButton(
                                  onTap: () {
                                    Navigator.push(
                                      context,
                                      LiquidRevealRoute(
                                        page: DiscoverPage(query: name, isGenre: false),
                                        tapPosition: lastTap,
                                      ),
                                    );
                                  },
                                  scaleAmount: 1.05,
                                  child: Container(
                                    width: 76,
                                    height: 76,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      gradient: member.profileUrl == null
                                          ? LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: pair)
                                          : null,
                                      border: Border.all(color: Colors.white.withOpacity(0.1), width: 1.5),
                                    ),
                                    clipBehavior: Clip.antiAlias,
                                    alignment: Alignment.center,
                                    child: member.profileUrl != null
                                        ? CachedNetworkImage(
                                            imageUrl: member.profileUrl!,
                                            width: 76,
                                            height: 76,
                                            fit: BoxFit.cover,
                                            placeholder: (_, __) => Container(
                                              decoration: BoxDecoration(
                                                gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: pair),
                                              ),
                                              alignment: Alignment.center,
                                              child: Text(initials, style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)),
                                            ),
                                            errorWidget: (_, __, ___) => Container(
                                              decoration: BoxDecoration(
                                                gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: pair),
                                              ),
                                              alignment: Alignment.center,
                                              child: Text(initials, style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)),
                                            ),
                                          )
                                        : Text(initials, style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)),
                                  ),
                                ),
                              );
                            }
                          ),
                          const SizedBox(height: 6),
                          Text(
                            name,
                            textAlign: TextAlign.center,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600, height: 1.2),
                          ),
                          if (member.character != null && member.character!.isNotEmpty) ...[
                            const SizedBox(height: 2),
                            Text(
                              member.character!,
                              textAlign: TextAlign.center,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(color: Colors.white54, fontSize: 10.5, height: 1.1),
                            ),
                          ],
                        ],
                      ),
                    );
                  },
                ),
                if (_isDesktop()) ...[
                  if (_canScrollCastLeft)
                    Positioned(
                      left: 0, top: 10, bottom: 40,
                      child: _buildScrollArrow(Icons.arrow_back_ios_new_rounded, () => _scrollList(_castScrollController, -1), _isHoveringCast),
                    ),
                  if (_canScrollCastRight)
                    Positioned(
                      right: 0, top: 10, bottom: 40,
                      child: _buildScrollArrow(Icons.arrow_forward_ios_rounded, () => _scrollList(_castScrollController, 1), _isHoveringCast),
                    ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDirectorRow(MovieDetail meta) {
    final List<CrewMember> directors = meta.directorsList.isNotEmpty
        ? meta.directorsList
        : meta.director.map((d) => CrewMember(name: d, job: 'Director')).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader('Direction'),
        SizedBox(
          height: 132,
          child: ListView.separated(
            clipBehavior: Clip.none,
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            itemCount: directors.length,
            separatorBuilder: (_, __) => const SizedBox(width: _Space.lg),
            itemBuilder: (context, index) {
              final director = directors[index];
              final name = director.name;
              final initials = name.isNotEmpty
                  ? name.trim().split(' ').map((e) => e.isNotEmpty ? e[0] : '').take(2).join('').toUpperCase()
                  : '?';
              final pair = _Palette.avatarPairs[name.hashCode.abs() % _Palette.avatarPairs.length];

              return SizedBox(
                width: 88,
                child: Column(
                  children: [
                    Builder(
                      builder: (context) {
                        Offset? lastTap;
                        return GestureDetector(
                          onTapDown: (d) => lastTap = d.globalPosition,
                          child: _HoverButton(
                            onTap: () {
                              Navigator.push(
                                context,
                                LiquidRevealRoute(
                                  page: DiscoverPage(query: name, isGenre: false),
                                  tapPosition: lastTap,
                                ),
                              );
                            },
                            scaleAmount: 1.05,
                            child: Container(
                              width: 76,
                              height: 76,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                gradient: director.profileUrl == null
                                    ? LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: pair)
                                    : null,
                                border: Border.all(color: Colors.white.withOpacity(0.1), width: 1.5),
                              ),
                              clipBehavior: Clip.antiAlias,
                              alignment: Alignment.center,
                              child: director.profileUrl != null
                                  ? CachedNetworkImage(
                                      imageUrl: director.profileUrl!,
                                      width: 76,
                                      height: 76,
                                      fit: BoxFit.cover,
                                      placeholder: (_, __) => Container(
                                        decoration: BoxDecoration(
                                          gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: pair),
                                        ),
                                        alignment: Alignment.center,
                                        child: Text(initials, style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)),
                                      ),
                                      errorWidget: (_, __, ___) => Container(
                                        decoration: BoxDecoration(
                                          gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: pair),
                                        ),
                                        alignment: Alignment.center,
                                        child: Text(initials, style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)),
                                      ),
                                    )
                                  : Text(initials, style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)),
                            ),
                          ),
                        );
                      }
                    ),
                    const SizedBox(height: 6),
                    Text(
                      name,
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600, height: 1.2),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      director.job,
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white54, fontSize: 10.5, height: 1.1),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildSeasonSelector(MovieDetail meta) {
    final seasons = meta.videos.map((v) => v.season).where((s) => s != null).toSet().toList();
    seasons.sort();

    return MouseRegion(
      onEnter: (_) => setState(() => _isHoveringSeasons = true),
      onExit: (_) => setState(() => _isHoveringSeasons = false),
      child: SizedBox(
        height: 44,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            ListView.separated(
              clipBehavior: Clip.none,
              controller: _seasonScrollController,
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              itemCount: seasons.length,
              separatorBuilder: (_, __) => const SizedBox(width: _Space.sm),
              itemBuilder: (context, index) {
                final season = seasons[index];
                final isSelected = _selectedSeason == season;
                return _HoverButton(
                  onTap: () {
                    if (_selectedSeason != season) {
                      setState(() {
                        _previousSeason = _selectedSeason;
                        _selectedSeason = season;
                      });
                      _updateEpisodesForSeason();
                    }
                  },
                  scaleAmount: 1.02,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: const EdgeInsets.symmetric(horizontal: 22),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: isSelected ? Colors.white : Colors.white.withOpacity(0.07),
                      borderRadius: BorderRadius.circular(22),
                      border: Border.all(color: isSelected ? Colors.white : Colors.white.withOpacity(0.1)),
                    ),
                    child: Text(
                      'Season $season',
                      style: TextStyle(
                        color: isSelected ? Colors.black : Colors.white,
                        fontSize: 15,
                        fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                      ),
                    ),
                  ),
                );
              },
            ),
            if (_isDesktop()) ...[
              if (_canScrollSeasonsLeft)
                Positioned(
                  left: 0, top: 0, bottom: 0,
                  child: _buildScrollArrow(Icons.arrow_back_ios_new_rounded, () => _scrollList(_seasonScrollController, -1), _isHoveringSeasons),
                ),
              if (_canScrollSeasonsRight)
                Positioned(
                  right: 0, top: 0, bottom: 0,
                  child: _buildScrollArrow(Icons.arrow_forward_ios_rounded, () => _scrollList(_seasonScrollController, 1), _isHoveringSeasons),
                ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildEpisodeSlider({Key? key}) {
    final isDesktop = _isDesktop();
    final cardWidth = isDesktop ? 300.0 : 230.0;
    final fadeWidth = isDesktop ? 60.0 : 40.0;

    return MouseRegion(
      key: key,
      onEnter: (_) => setState(() => _isHoveringEpisodes = true),
      onExit: (_) => setState(() => _isHoveringEpisodes = false),
      child: SizedBox(
        height: isDesktop ? 275 : 245,
        child: Stack(
          clipBehavior: Clip.hardEdge,
          children: [
            ShaderMask(
              shaderCallback: (Rect bounds) {
                final leftFadeStop = bounds.width > 0 ? (fadeWidth / bounds.width).clamp(0.01, 0.2) : 0.05;
                final rightFadeStop = bounds.width > 0 ? (1.0 - (fadeWidth / bounds.width)).clamp(0.8, 0.99) : 0.95;

                return LinearGradient(
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                  colors: [
                    _canScrollEpisodesLeft ? Colors.transparent : Colors.black,
                    Colors.black,
                    Colors.black,
                    _canScrollEpisodesRight ? Colors.transparent : Colors.black,
                  ],
                  stops: [
                    0.0,
                    leftFadeStop,
                    rightFadeStop,
                    1.0,
                  ],
                ).createShader(bounds);
              },
              blendMode: BlendMode.dstIn,
              child: ListView.separated(
                clipBehavior: Clip.hardEdge,
                controller: _episodeScrollController,
                scrollDirection: Axis.horizontal,
                physics: const BouncingScrollPhysics(),
                itemCount: _currentSeasonEpisodes.length,
                separatorBuilder: (_, __) => const SizedBox(width: _Space.md),
                itemBuilder: (context, index) {
                  final ep = _currentSeasonEpisodes[index];
                  return SizedBox(
                    width: cardWidth,
                    child: _EpisodeCard(
                      episode: ep,
                      fallbackImageUrl: _detail?.background ?? _detail?.poster ?? widget.movie.poster,
                      onTap: () => _handlePlayAction(ep),
                    ),
                  );
                },
              ),
            ),
            if (isDesktop) ...[
              if (_canScrollEpisodesLeft)
                Positioned(
                  left: 0,
                  top: 0,
                  bottom: 0,
                  child: Container(
                    width: fadeWidth + 10,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.centerLeft,
                        end: Alignment.centerRight,
                        colors: [
                          _Palette.bg,
                          _Palette.bg.withValues(alpha: 0.0),
                        ],
                      ),
                    ),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: _buildScrollArrow(
                        Icons.arrow_back_ios_new_rounded,
                        () => _scrollList(_episodeScrollController, -1),
                        _isHoveringEpisodes,
                      ),
                    ),
                  ),
                ),
              if (_canScrollEpisodesRight)
                Positioned(
                  right: 0,
                  top: 0,
                  bottom: 0,
                  child: Container(
                    width: fadeWidth + 10,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.centerRight,
                        end: Alignment.centerLeft,
                        colors: [
                          _Palette.bg,
                          _Palette.bg.withValues(alpha: 0.0),
                        ],
                      ),
                    ),
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: _buildScrollArrow(
                        Icons.arrow_forward_ios_rounded,
                        () => _scrollList(_episodeScrollController, 1),
                        _isHoveringEpisodes,
                      ),
                    ),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }

  // "More Like This" — fills the dead space at the bottom of the page and
  // gives people somewhere to go next instead of hitting a wall of black.
  Widget _buildRelatedRow(List<Movie> related) {
    final isDesktop = _isDesktop();
    final cardWidth = isDesktop ? 150.0 : 120.0;
    final fadeWidth = isDesktop ? 60.0 : 40.0;

    return MouseRegion(
      onEnter: (_) => setState(() => _isHoveringRelated = true),
      onExit: (_) => setState(() => _isHoveringRelated = false),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionHeader('More Like This'),
          SizedBox(
            height: cardWidth * 1.5 + 8,
            child: Stack(
              clipBehavior: Clip.hardEdge,
              children: [
                ShaderMask(
                  shaderCallback: (Rect bounds) {
                    final leftFadeStop = bounds.width > 0 ? (fadeWidth / bounds.width).clamp(0.01, 0.2) : 0.05;
                    final rightFadeStop = bounds.width > 0 ? (1.0 - (fadeWidth / bounds.width)).clamp(0.8, 0.99) : 0.95;

                    return LinearGradient(
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                      colors: [
                        _canScrollRelatedLeft ? Colors.transparent : Colors.black,
                        Colors.black,
                        Colors.black,
                        _canScrollRelatedRight ? Colors.transparent : Colors.black,
                      ],
                      stops: [
                        0.0,
                        leftFadeStop,
                        rightFadeStop,
                        1.0,
                      ],
                    ).createShader(bounds);
                  },
                  blendMode: BlendMode.dstIn,
                  child: ListView.separated(
                    clipBehavior: Clip.hardEdge,
                    controller: _relatedScrollController,
                    scrollDirection: Axis.horizontal,
                    physics: const BouncingScrollPhysics(),
                    itemCount: related.length,
                    separatorBuilder: (_, __) => const SizedBox(width: _Space.md),
                    itemBuilder: (context, index) {
                      final item = related[index];
                      return SizedBox(
                        width: cardWidth,
                        child: _HoverButton(
                          onTap: () {
                            Navigator.pushReplacement(
                              context,
                              MaterialPageRoute(builder: (_) => DetailsPage(movie: item)),
                            );
                          },
                          scaleAmount: 1.05,
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child: AspectRatio(
                              aspectRatio: 2 / 3,
                              child: item.poster != null
                                  ? CachedNetworkImage(imageUrl: item.poster!, fit: BoxFit.cover)
                                  : const ColoredBox(color: _Palette.surface),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
                if (isDesktop) ...[
                  if (_canScrollRelatedLeft)
                    Positioned(
                      left: 0,
                      top: 0,
                      bottom: 0,
                      child: Container(
                        width: fadeWidth + 10,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.centerLeft,
                            end: Alignment.centerRight,
                            colors: [
                              _Palette.bg,
                              _Palette.bg.withValues(alpha: 0.0),
                            ],
                          ),
                        ),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: _buildScrollArrow(
                            Icons.arrow_back_ios_new_rounded,
                            () => _scrollList(_relatedScrollController, -1),
                            _isHoveringRelated,
                          ),
                        ),
                      ),
                    ),
                  if (_canScrollRelatedRight)
                    Positioned(
                      right: 0,
                      top: 0,
                      bottom: 0,
                      child: Container(
                        width: fadeWidth + 10,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.centerRight,
                            end: Alignment.centerLeft,
                            colors: [
                              _Palette.bg,
                              _Palette.bg.withValues(alpha: 0.0),
                            ],
                          ),
                        ),
                        child: Align(
                          alignment: Alignment.centerRight,
                          child: _buildScrollArrow(
                            Icons.arrow_forward_ios_rounded,
                            () => _scrollList(_relatedScrollController, 1),
                            _isHoveringRelated,
                          ),
                        ),
                      ),
                    ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSimilarRow() {
    final isDesktop = _isDesktop();
    final cardWidth = isDesktop ? 160.0 : 130.0;
    final cardHeight = cardWidth * 1.5 + 64; // poster + text area
    final fadeWidth = isDesktop ? 60.0 : 40.0;

    return MouseRegion(
      onEnter: (_) => setState(() => _isHoveringSimilar = true),
      onExit: (_) => setState(() => _isHoveringSimilar = false),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionHeader('Similar Content'),
          SizedBox(
            height: cardHeight,
            child: Stack(
              clipBehavior: Clip.hardEdge,
              children: [
                ShaderMask(
                  shaderCallback: (Rect bounds) {
                    final leftFadeStop = bounds.width > 0 ? (fadeWidth / bounds.width).clamp(0.01, 0.2) : 0.05;
                    final rightFadeStop = bounds.width > 0 ? (1.0 - (fadeWidth / bounds.width)).clamp(0.8, 0.99) : 0.95;

                    return LinearGradient(
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                      colors: [
                        _canScrollSimilarLeft ? Colors.transparent : Colors.black,
                        Colors.black,
                        Colors.black,
                        _canScrollSimilarRight ? Colors.transparent : Colors.black,
                      ],
                      stops: [
                        0.0,
                        leftFadeStop,
                        rightFadeStop,
                        1.0,
                      ],
                    ).createShader(bounds);
                  },
                  blendMode: BlendMode.dstIn,
                  child: ListView.separated(
                    clipBehavior: Clip.hardEdge,
                    controller: _similarScrollController,
                    scrollDirection: Axis.horizontal,
                    physics: const BouncingScrollPhysics(),
                    itemCount: _similarItems.length,
                    separatorBuilder: (_, __) => const SizedBox(width: _Space.md),
                    itemBuilder: (context, index) {
                      final item = _similarItems[index];
                      return SizedBox(
                        width: cardWidth,
                        child: _HoverButton(
                          onTap: () => _openSimilarItem(item),
                          scaleAmount: 1.05,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Poster
                              Stack(
                                children: [
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(10),
                                    child: AspectRatio(
                                      aspectRatio: 2 / 3,
                                      child: item.thumbUrl.isNotEmpty
                                          ? CachedNetworkImage(
                                              imageUrl: item.thumbUrl,
                                              fit: BoxFit.cover,
                                              errorWidget: (_, __, ___) => Container(
                                                color: _Palette.surface,
                                                child: const Center(
                                                  child: Icon(Icons.movie_rounded, color: Colors.white24, size: 36),
                                                ),
                                              ),
                                            )
                                          : Container(
                                              color: _Palette.surface,
                                              child: const Center(
                                                child: Icon(Icons.movie_rounded, color: Colors.white24, size: 36),
                                              ),
                                            ),
                                    ),
                                  ),
                                  // Similarity badge
                                  if (item.similarityPercent != null)
                                    Positioned(
                                      top: 6,
                                      right: 6,
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                                        decoration: BoxDecoration(
                                          color: Colors.black.withOpacity(0.75),
                                          borderRadius: BorderRadius.circular(6),
                                          border: Border.all(color: _Palette.accent.withOpacity(0.6)),
                                        ),
                                        child: Text(
                                          '${item.similarityPercent}%',
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 11,
                                            fontWeight: FontWeight.w800,
                                          ),
                                        ),
                                      ),
                                    ),
                                  // Rating badge
                                  if (item.rating != null)
                                    Positioned(
                                      bottom: 6,
                                      left: 6,
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                                        decoration: BoxDecoration(
                                          color: Colors.black.withOpacity(0.75),
                                          borderRadius: BorderRadius.circular(6),
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            const Icon(Icons.star_rounded, color: _Palette.gold, size: 13),
                                            const SizedBox(width: 3),
                                            Text(
                                              item.rating!.toStringAsFixed(1),
                                              style: const TextStyle(
                                                color: Colors.white,
                                                fontSize: 11,
                                                fontWeight: FontWeight.w700,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              // Title
                              Text(
                                item.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 2),
                              // Year + genre
                              Text(
                                [
                                  if (item.year != null) '${item.year}',
                                  if (item.genre != null) item.genre!.split(',').first.trim(),
                                ].join(' · '),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.white38,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
                if (isDesktop) ...[
                  if (_canScrollSimilarLeft)
                    Positioned(
                      left: 0,
                      top: 0,
                      bottom: 60,
                      child: Container(
                        width: fadeWidth + 10,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.centerLeft,
                            end: Alignment.centerRight,
                            colors: [
                              _Palette.bg,
                              _Palette.bg.withValues(alpha: 0.0),
                            ],
                          ),
                        ),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: _buildScrollArrow(
                            Icons.arrow_back_ios_new_rounded,
                            () => _scrollList(_similarScrollController, -1),
                            _isHoveringSimilar,
                          ),
                        ),
                      ),
                    ),
                  if (_canScrollSimilarRight)
                    Positioned(
                      right: 0,
                      top: 0,
                      bottom: 60,
                      child: Container(
                        width: fadeWidth + 10,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.centerRight,
                            end: Alignment.centerLeft,
                            colors: [
                              _Palette.bg,
                              _Palette.bg.withValues(alpha: 0.0),
                            ],
                          ),
                        ),
                        child: Align(
                          alignment: Alignment.centerRight,
                          child: _buildScrollArrow(
                            Icons.arrow_forward_ios_rounded,
                            () => _scrollList(_similarScrollController, 1),
                            _isHoveringSimilar,
                          ),
                        ),
                      ),
                    ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildScrollArrow(IconData icon, VoidCallback onTap, bool isVisible) {
    return Center(
      child: AnimatedOpacity(
        opacity: isVisible ? 1.0 : 0.0,
        duration: const Duration(milliseconds: 200),
        child: IgnorePointer(
          ignoring: !isVisible,
          child: _HoverButton(
            onTap: onTap,
            scaleAmount: 1.1,
            child: ClipOval(
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                child: Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.6),
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white.withOpacity(0.2)),
                  ),
                  child: Icon(icon, color: Colors.white, size: 18),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _EpisodeCard extends StatefulWidget {
  final Video episode;
  final String? fallbackImageUrl;
  final VoidCallback? onTap;

  const _EpisodeCard({required this.episode, this.fallbackImageUrl, this.onTap});

  @override
  State<_EpisodeCard> createState() => _EpisodeCardState();
}

class _EpisodeCardState extends State<_EpisodeCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final ep = widget.episode;
    final imgUrl = ep.thumbnail ?? widget.fallbackImageUrl;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap ?? () {},
        child: AnimatedScale(
          scale: _hovered ? 1.03 : 1.0,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
          child: Container(
            decoration: BoxDecoration(
              color: _Palette.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _hovered ? Colors.white.withOpacity(0.22) : Colors.white.withOpacity(0.04)),
              boxShadow: _hovered
                  ? [BoxShadow(color: Colors.black.withOpacity(0.4), blurRadius: 18, offset: const Offset(0, 8))]
                  : [],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  AspectRatio(
                    aspectRatio: 16 / 9,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        if (imgUrl != null)
                          CachedNetworkImage(
                            imageUrl: imgUrl,
                            fit: BoxFit.cover,
                            errorWidget: (context, url, error) => const ColoredBox(color: Color(0xFF1B1E27)),
                          )
                        else
                          const ColoredBox(color: Color(0xFF1B1E27)),
                        DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [Colors.transparent, Colors.black.withOpacity(0.75)],
                              stops: const [0.5, 1.0],
                            ),
                          ),
                        ),
                        Center(
                          child: AnimatedOpacity(
                            opacity: _hovered ? 1.0 : 0.0,
                            duration: const Duration(milliseconds: 150),
                            child: Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                shape: BoxShape.circle,
                                boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.5), blurRadius: 10)],
                              ),
                              child: const Icon(Icons.play_arrow_rounded, color: Colors.black, size: 24),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(_Space.sm),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          children: [
                            Text('EP ${ep.episode ?? "?"}', style: const TextStyle(color: _Palette.accent, fontWeight: FontWeight.bold, fontSize: 12)),
                            const Spacer(),
                            if (ep.released != null && ep.released!.length >= 10)
                              Text(ep.released!.substring(0, 10), style: const TextStyle(color: Colors.white38, fontSize: 11)),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          ep.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13.5),
                        ),
                        if (ep.overview != null) ...[
                          const SizedBox(height: 3),
                          Text(
                            ep.overview!,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: Colors.white54, fontSize: 11.5, height: 1.3),
                          ),
                        ],
                      ],
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

class _HoverButton extends StatefulWidget {
  final Widget child;
  final VoidCallback onTap;
  final double scaleAmount;

  const _HoverButton({required this.child, required this.onTap, this.scaleAmount = 1.04});

  @override
  State<_HoverButton> createState() => _HoverButtonState();
}

class _HoverButtonState extends State<_HoverButton> {
  bool _isHovered = false;
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() { _isHovered = false; _isPressed = false; }),
      child: GestureDetector(
        onTapDown: (_) => setState(() => _isPressed = true),
        onTapUp: (_) => setState(() => _isPressed = false),
        onTapCancel: () => setState(() => _isPressed = false),
        onTap: widget.onTap,
        child: AnimatedScale(
          scale: _isPressed ? 0.96 : (_isHovered ? widget.scaleAmount : 1.0),
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOutCubic,
          child: widget.child,
        ),
      ),
    );
  }
}