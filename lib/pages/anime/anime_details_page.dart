import 'dart:math' as math;
import 'dart:ui';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../models/anime/anime_media.dart';
import '../../services/anime/anilist_service.dart';
import '../../services/anime/anime_library_service.dart';
import '../../services/anime/extractors/anikoto_resolver.dart';
import '../../utils/route_transitions.dart';
import 'anime_stream_sheet.dart';

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
  static const accent = Color(0xFF7C5CFF);
  static const accentDim = Color(0xFF5A3BC8);
  static const gold = Color(0xFFFFC107);
}

class AnimeDetailsPage extends StatefulWidget {
  final AnimeMedia anime;

  const AnimeDetailsPage({
    super.key,
    required this.anime,
  });

  @override
  State<AnimeDetailsPage> createState() => _AnimeDetailsPageState();
}

class _AnimeDetailsPageState extends State<AnimeDetailsPage>
    with SingleTickerProviderStateMixin {
  late AnimeMedia _anime;
  bool _isDub = false;
  bool _isSynopsisExpanded = false;

  int _selectedEpisodeBatch = 0; // 50 episodes per chunk
  int? _highlightedEpisode;
  AnikotoSeries? _anikotoSeries;

  static const int _chunkSize = 50;

  final TextEditingController _jumpEpController = TextEditingController();

  late AnimationController _animController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  final ScrollController _castScrollController = ScrollController();
  final ScrollController _relationsScrollController = ScrollController();
  final ScrollController _recsScrollController = ScrollController();

  bool _canScrollCastLeft = false;
  bool _canScrollCastRight = true;
  bool _isHoveringCast = false;

  bool _canScrollRelationsLeft = false;
  bool _canScrollRelationsRight = true;
  bool _isHoveringRelations = false;

  bool _canScrollRecsLeft = false;
  bool _canScrollRecsRight = true;
  bool _isHoveringRecs = false;

  @override
  void initState() {
    super.initState();
    _anime = widget.anime;

    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 650),
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animController, curve: Curves.easeOut),
    );
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.04),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(parent: _animController, curve: Curves.easeOutCubic),
    );

    _castScrollController.addListener(_updateCastScrollButtons);
    _relationsScrollController.addListener(_updateRelationsScrollButtons);
    _recsScrollController.addListener(_updateRecsScrollButtons);

    _loadDetails();
    _resolveAnikoto();
  }

  @override
  void dispose() {
    _animController.dispose();
    _jumpEpController.dispose();
    _castScrollController.dispose();
    _relationsScrollController.dispose();
    _recsScrollController.dispose();
    super.dispose();
  }

  void _loadDetails() async {
    final full = await AnilistService.instance.fetchAnimeDetails(_anime.id);
    if (mounted) {
      setState(() {
        if (full != null) _anime = full;
      });
      _animController.forward();

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _updateCastScrollButtons();
          _updateRelationsScrollButtons();
          _updateRecsScrollButtons();
        }
      });
    }
  }

  void _resolveAnikoto() async {
    try {
      final series = await AnikotoResolver.instance.resolveAnikoto(
        anilistId: _anime.id,
        titleCandidates: [
          _anime.titleEnglish,
          _anime.titleRomaji,
          _anime.titleNative,
          _anime.titleUserPreferred,
        ].where((t) => t.isNotEmpty).toList(),
        expectedEpisodes:
            _anime.totalEpisodes > 0 ? _anime.totalEpisodes : null,
      );
      if (series != null && mounted) {
        setState(() => _anikotoSeries = series);
      }
    } catch (_) {}
  }

  int get _computedTotalEpisodes {
    if (_anikotoSeries != null && _anikotoSeries!.episodes.isNotEmpty) {
      return _anikotoSeries!.episodes.length;
    }
    if (_anime.totalEpisodes > 0) return _anime.totalEpisodes;
    if (_anime.nextAiring != null && _anime.nextAiring!.episode > 1) {
      return _anime.nextAiring!.episode - 1;
    }
    if (_anime.format.toUpperCase() == 'MOVIE') return 1;
    return 24;
  }

  void _updateCastScrollButtons() {
    if (!_castScrollController.hasClients) return;
    final canLeft = _castScrollController.position.pixels > 0;
    final canRight = _castScrollController.position.pixels <
        _castScrollController.position.maxScrollExtent;
    if (_canScrollCastLeft != canLeft || _canScrollCastRight != canRight) {
      setState(() {
        _canScrollCastLeft = canLeft;
        _canScrollCastRight = canRight;
      });
    }
  }

  void _updateRelationsScrollButtons() {
    if (!_relationsScrollController.hasClients) return;
    final canLeft = _relationsScrollController.position.pixels > 0;
    final canRight = _relationsScrollController.position.pixels <
        _relationsScrollController.position.maxScrollExtent;
    if (_canScrollRelationsLeft != canLeft ||
        _canScrollRelationsRight != canRight) {
      setState(() {
        _canScrollRelationsLeft = canLeft;
        _canScrollRelationsRight = canRight;
      });
    }
  }

  void _updateRecsScrollButtons() {
    if (!_recsScrollController.hasClients) return;
    final canLeft = _recsScrollController.position.pixels > 0;
    final canRight = _recsScrollController.position.pixels <
        _recsScrollController.position.maxScrollExtent;
    if (_canScrollRecsLeft != canLeft || _canScrollRecsRight != canRight) {
      setState(() {
        _canScrollRecsLeft = canLeft;
        _canScrollRecsRight = canRight;
      });
    }
  }

  void _scrollList(ScrollController controller, double directionMultiplier) {
    if (!controller.hasClients) return;
    final viewportWidth = controller.position.viewportDimension;
    final scrollAmount = viewportWidth * 0.7 * directionMultiplier;
    final target = (controller.position.pixels + scrollAmount)
        .clamp(0.0, controller.position.maxScrollExtent);
    controller.animateTo(
      target,
      duration: const Duration(milliseconds: 450),
      curve: Curves.easeOutCubic,
    );
  }

  void _playEpisode(int episodeNumber) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => AnimeStreamSheet(
        anime: _anime,
        episodeNumber: episodeNumber,
        autoPlay: false,
      ),
    );
  }

  void _jumpToEpisode(String value) {
    final ep = int.tryParse(value.trim());
    if (ep == null || ep <= 0) return;

    final totalEps = _computedTotalEpisodes;
    final targetEp = ep.clamp(1, totalEps);
    final targetBatch = ((targetEp - 1) / _chunkSize).floor();

    setState(() {
      _selectedEpisodeBatch = targetBatch;
      _highlightedEpisode = targetEp;
    });
    FocusScope.of(context).unfocus();
  }

  void _navigateToAnime(AnimeMedia target) {
    Navigator.push(
      context,
      CinematicSlideRoute(
        page: AnimeDetailsPage(anime: target),
      ),
    );
  }

  bool _isDesktop() {
    if (kIsWeb) return true;
    return defaultTargetPlatform == TargetPlatform.windows ||
        defaultTargetPlatform == TargetPlatform.macOS ||
        defaultTargetPlatform == TargetPlatform.linux;
  }

  @override
  Widget build(BuildContext context) {
    final bgUrl = _anime.backdropUrl;
    final posterUrl = _anime.coverUrl;
    final isDesktop = _isDesktop();
    final screenSize = MediaQuery.sizeOf(context);

    final heroHeight =
        (screenSize.height * (isDesktop ? 0.46 : 0.4)).clamp(320.0, 520.0);
    final contentMaxWidth = isDesktop ? 1440.0 : double.infinity;
    final overlap = isDesktop ? 120.0 : 70.0;

    return Scaffold(
      backgroundColor: _Palette.bg,
      body: Stack(
        children: [
          if (bgUrl.isNotEmpty) _buildBackdrop(bgUrl, screenSize),

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
                        padding: EdgeInsets.symmetric(
                          horizontal: isDesktop ? _Space.xxl : _Space.lg,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SizedBox(height: heroHeight - overlap),
                            isDesktop
                                ? _buildDesktopLayout(posterUrl)
                                : _buildMobileLayout(posterUrl),
                            const SizedBox(height: _Space.xl),

                            // Characters & Voice Cast Row
                            if (_anime.characters.isNotEmpty) ...[
                              _buildCharactersRow(),
                              const SizedBox(height: _Space.xl),
                            ],

                            // Episodes Section with 50-Chunking & Jump Input
                            _buildEpisodesSection(),
                            const SizedBox(height: _Space.xl),

                            // Franchise & Relations Row
                            if (_anime.relations.isNotEmpty) ...[
                              _buildRelationsRow(),
                              const SizedBox(height: _Space.xl),
                            ],

                            // You May Also Like / Recommendations Row
                            if (_anime.recommendations.isNotEmpty) ...[
                              _buildRecommendationsRow(),
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

          // Floating Frosted Back Button (Top Left)
          Positioned(
            top: _Space.lg,
            left: isDesktop ? _Space.xxl : _Space.md,
            child: ClipOval(
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                child: IconButton(
                  icon: const Icon(
                    Icons.arrow_back_ios_new_rounded,
                    color: Colors.white,
                    size: 20,
                  ),
                  onPressed: () => Navigator.pop(context),
                  style: IconButton.styleFrom(
                    backgroundColor: Colors.white.withValues(alpha: 0.1),
                    padding: const EdgeInsets.all(12),
                    side: BorderSide(
                      color: Colors.white.withValues(alpha: 0.14),
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

  // ─── Persistent Cinematic Backdrop ─────────────────────────────
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
            CachedNetworkImage(
              imageUrl: bgUrl,
              fit: BoxFit.cover,
              alignment: Alignment.topCenter,
              errorWidget: (_, __, ___) => const ColoredBox(color: _Palette.surface),
            ),
            // Horizontal wash: darkens where the title sits
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
            // Slow bottom fade: resolves smoothly to solid background
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
            // Top contrast cap for back button
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.black54, Colors.transparent],
                  stops: [0.0, 0.22],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─── Desktop 2-Column Layout ───────────────────────────────────
  Widget _buildDesktopLayout(String posterUrl) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 280,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (posterUrl.isNotEmpty)
                DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: [
                      BoxShadow(
                        color: _Palette.accent.withValues(alpha: 0.22),
                        blurRadius: 46,
                        spreadRadius: -6,
                      ),
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.55),
                        blurRadius: 30,
                        offset: const Offset(0, 14),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: AspectRatio(
                      aspectRatio: 2 / 3,
                      child: CachedNetworkImage(
                        imageUrl: posterUrl,
                        fit: BoxFit.cover,
                        errorWidget: (_, __, ___) =>
                            const ColoredBox(color: _Palette.surface),
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
              _buildTitle(isDesktop: true),
              const SizedBox(height: _Space.md),
              _buildMetadataRow(),
              if (_anime.description.isNotEmpty) ...[
                const SizedBox(height: _Space.lg),
                _buildSynopsis(_anime.description),
              ],
              if (_anime.genres.isNotEmpty) ...[
                const SizedBox(height: _Space.lg),
                _buildGenreChips(_anime.genres),
              ],
            ],
          ),
        ),
      ],
    );
  }

  // ─── Mobile / Compact Single Column Layout ─────────────────────
  Widget _buildMobileLayout(String posterUrl) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            if (posterUrl.isNotEmpty)
              DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  boxShadow: [
                    BoxShadow(
                      color: _Palette.accent.withValues(alpha: 0.20),
                      blurRadius: 28,
                      spreadRadius: -4,
                    ),
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.5),
                      blurRadius: 16,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: CachedNetworkImage(
                    imageUrl: posterUrl,
                    width: 110,
                    fit: BoxFit.cover,
                  ),
                ),
              ),
            const SizedBox(width: _Space.md),
            Expanded(child: _buildTitle(isDesktop: false)),
          ],
        ),
        const SizedBox(height: _Space.lg),
        _buildMetadataRow(),
        const SizedBox(height: _Space.lg),
        Row(
          children: [
            Expanded(child: _buildPlayButton(fullWidth: true)),
            const SizedBox(width: _Space.sm),
            _buildLibraryButton(fullWidth: false),
          ],
        ),
        if (_anime.description.isNotEmpty) ...[
          const SizedBox(height: _Space.lg),
          _buildSynopsis(_anime.description),
        ],
        if (_anime.genres.isNotEmpty) ...[
          const SizedBox(height: _Space.md),
          _buildGenreChips(_anime.genres),
        ],
      ],
    );
  }

  Widget _buildTitle({required bool isDesktop}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          _anime.displayTitle,
          style: TextStyle(
            fontSize: isDesktop ? 38 : 26,
            fontWeight: FontWeight.w900,
            height: 1.12,
            letterSpacing: -0.8,
            color: Colors.white,
            shadows: [
              Shadow(
                color: Colors.black.withValues(alpha: 0.7),
                blurRadius: 20,
                offset: const Offset(0, 6),
              ),
            ],
          ),
        ),
        if (_anime.titleNative.isNotEmpty &&
            _anime.titleNative != _anime.displayTitle)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              _anime.titleNative,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.5),
                fontSize: isDesktop ? 14 : 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildMetadataRow() {
    final List<Widget> items = [];

    if (_anime.seasonYear > 0) {
      items.add(
        Text(
          '${_anime.seasonYear}',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 15,
            fontWeight: FontWeight.w700,
          ),
        ),
      );
    }

    if (_anime.formattedFormat.isNotEmpty) {
      items.add(
        Text(
          _anime.formattedFormat,
          style: const TextStyle(color: Colors.white70, fontSize: 14),
        ),
      );
    }

    final totalEps = _computedTotalEpisodes;
    if (totalEps > 0) {
      items.add(
        Text(
          '$totalEps Ep${totalEps > 1 ? "s" : ""}',
          style: const TextStyle(color: Colors.white70, fontSize: 14),
        ),
      );
    }

    if (_anime.averageScore > 0) {
      items.add(
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(5),
            border: Border.all(color: Colors.white.withValues(alpha: 0.25)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.star_rounded, color: _Palette.gold, size: 14),
              const SizedBox(width: 4),
              Text(
                _anime.formattedScore,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (_anime.studioName.isNotEmpty) {
      items.add(
        Text(
          _anime.studioName,
          style: const TextStyle(color: Colors.white70, fontSize: 14),
        ),
      );
    }

    final List<Widget> spaced = [];
    for (int i = 0; i < items.length; i++) {
      spaced.add(items[i]);
      if (i < items.length - 1) {
        spaced.add(
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: _Space.sm),
            child: Text('•', style: TextStyle(color: Colors.white30, fontSize: 16)),
          ),
        );
      }
    }

    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      runSpacing: 6,
      children: spaced,
    );
  }

  Widget _buildPlayButton({required bool fullWidth}) {
    final library = AnimeLibraryService.instance;
    final watchItem = library.getWatchlistItem(_anime.id);
    final resumeEp = watchItem?.lastWatchedEpisode ?? 1;

    return _HoverScale(
      onTap: () => _playEpisode(resumeEp),
      child: Container(
        width: fullWidth ? double.infinity : null,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [_Palette.accent, _Palette.accentDim],
          ),
          borderRadius: BorderRadius.circular(10),
          boxShadow: [
            BoxShadow(
              color: _Palette.accent.withValues(alpha: 0.35),
              blurRadius: 16,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: fullWidth ? MainAxisSize.max : MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 24),
            const SizedBox(width: 6),
            Text(
              watchItem != null && watchItem.lastWatchedEpisode > 0
                  ? 'Resume Ep $resumeEp'
                  : 'Play Ep 1',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.3,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLibraryButton({required bool fullWidth}) {
    final library = AnimeLibraryService.instance;
    final watchItem = library.getWatchlistItem(_anime.id);

    return PopupMenuButton<AnimeWatchStatus>(
      onSelected: (status) {
        library.setWatchlistStatus(_anime, status);
        setState(() {});
      },
      color: const Color(0xFF161A26),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
      ),
      itemBuilder: (context) => [
        const PopupMenuItem(
          value: AnimeWatchStatus.watching,
          child: Text('Watching', style: TextStyle(color: Colors.white)),
        ),
        const PopupMenuItem(
          value: AnimeWatchStatus.planToWatch,
          child: Text('Plan to Watch', style: TextStyle(color: Colors.white)),
        ),
        const PopupMenuItem(
          value: AnimeWatchStatus.completed,
          child: Text('Completed', style: TextStyle(color: Colors.white)),
        ),
        const PopupMenuItem(
          value: AnimeWatchStatus.dropped,
          child: Text('Dropped', style: TextStyle(color: Colors.white54)),
        ),
      ],
      child: _HoverScale(
        child: Container(
          width: fullWidth ? double.infinity : null,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 13),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: watchItem != null
                  ? const Color(0xFF00D294)
                  : Colors.white.withValues(alpha: 0.15),
            ),
          ),
          child: Row(
            mainAxisSize: fullWidth ? MainAxisSize.max : MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                watchItem != null
                    ? Icons.check_circle_rounded
                    : Icons.bookmark_outline_rounded,
                color: watchItem != null
                    ? const Color(0xFF00D294)
                    : Colors.white70,
                size: 18,
              ),
              const SizedBox(width: 8),
              Text(
                watchItem != null
                    ? watchItem.status.name.toUpperCase()
                    : 'ADD TO LIST',
                style: TextStyle(
                  color: watchItem != null
                      ? const Color(0xFF00D294)
                      : Colors.white70,
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.3,
                ),
              ),
              const SizedBox(width: 4),
              const Icon(
                Icons.arrow_drop_down_rounded,
                color: Colors.white54,
                size: 18,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSynopsis(String description) {
    return GestureDetector(
      onTap: () => setState(() => _isSynopsisExpanded = !_isSynopsisExpanded),
      child: AnimatedCrossFade(
        duration: const Duration(milliseconds: 200),
        firstChild: Text(
          description,
          maxLines: 4,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: Colors.white70,
            fontSize: 14.5,
            height: 1.55,
          ),
        ),
        secondChild: Text(
          description,
          style: const TextStyle(
            color: Colors.white70,
            fontSize: 14.5,
            height: 1.55,
          ),
        ),
        crossFadeState: _isSynopsisExpanded
            ? CrossFadeState.showSecond
            : CrossFadeState.showFirst,
      ),
    );
  }

  Widget _buildGenreChips(List<String> genres) {
    return Wrap(
      spacing: _Space.xs,
      runSpacing: _Space.xs,
      children: genres
          .map(
            (g) => Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
              ),
              child: Text(
                g,
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          )
          .toList(),
    );
  }

  // ─── Characters & Voice Cast Row ───────────────────────────────
  Widget _buildCharactersRow() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader('Characters & Cast'),
        const SizedBox(height: _Space.md),
        MouseRegion(
          onEnter: (_) => setState(() => _isHoveringCast = true),
          onExit: (_) => setState(() => _isHoveringCast = false),
          child: Stack(
            children: [
              SizedBox(
                height: 180,
                child: ListView.separated(
                  controller: _castScrollController,
                  scrollDirection: Axis.horizontal,
                  physics: const BouncingScrollPhysics(),
                  itemCount: _anime.characters.length,
                  separatorBuilder: (_, __) => const SizedBox(width: _Space.md),
                  itemBuilder: (context, index) {
                    final char = _anime.characters[index];
                    return SizedBox(
                      width: 100,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _HoverScale(
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: CachedNetworkImage(
                                imageUrl: char.imageLarge,
                                width: 100,
                                height: 110,
                                fit: BoxFit.cover,
                                errorWidget: (_, __, ___) => Container(
                                  width: 100,
                                  height: 110,
                                  color: _Palette.surface,
                                  child: const Icon(
                                    Icons.person_rounded,
                                    color: Colors.white24,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            char.nameFull,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            char.role,
                            style: const TextStyle(
                              color: Colors.white38,
                              fontSize: 10,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
              if (_canScrollCastLeft)
                Positioned(
                  left: 0,
                  top: 0,
                  bottom: 0,
                  child: _buildScrollArrow(
                    icon: Icons.chevron_left_rounded,
                    onTap: () => _scrollList(_castScrollController, -1),
                    visible: _isHoveringCast,
                  ),
                ),
              if (_canScrollCastRight)
                Positioned(
                  right: 0,
                  top: 0,
                  bottom: 0,
                  child: _buildScrollArrow(
                    icon: Icons.chevron_right_rounded,
                    onTap: () => _scrollList(_castScrollController, 1),
                    visible: _isHoveringCast,
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  // ─── Episodes Section (50-Chunking, Jump Input, SUB/DUB) ────────
  Widget _buildEpisodesSection() {
    final library = AnimeLibraryService.instance;
    final watchItem = library.getWatchlistItem(_anime.id);
    final totalEps = _computedTotalEpisodes;
    final totalBatches = (totalEps / _chunkSize).ceil().clamp(1, 9999);
    final currentBatchSafe = _selectedEpisodeBatch.clamp(0, totalBatches - 1);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Episodes Header & Controls
        Wrap(
          spacing: 12,
          runSpacing: 10,
          crossAxisAlignment: WrapCrossAlignment.center,
          alignment: WrapAlignment.spaceBetween,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildSectionHeader('Episodes'),
                const SizedBox(width: 8),
                Text(
                  '($totalEps total)',
                  style: const TextStyle(color: Colors.white54, fontSize: 14),
                ),
              ],
            ),

            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // SUB / DUB Switcher
                Container(
                  padding: const EdgeInsets.all(3),
                  decoration: BoxDecoration(
                    color: const Color(0xFF141724),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.white12),
                  ),
                  child: Row(
                    children: [
                      GestureDetector(
                        onTap: () => setState(() => _isDub = false),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 5,
                          ),
                          decoration: BoxDecoration(
                            color: !_isDub ? _Palette.accent : Colors.transparent,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Text(
                            'SUB',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                      ),
                      GestureDetector(
                        onTap: () => setState(() => _isDub = true),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 5,
                          ),
                          decoration: BoxDecoration(
                            color: _isDub ? _Palette.accent : Colors.transparent,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Text(
                            'DUB',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(width: 12),

                // Jump to Ep Input
                Container(
                  width: 130,
                  height: 34,
                  decoration: BoxDecoration(
                    color: const Color(0xFF141724),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.white12),
                  ),
                  child: TextField(
                    controller: _jumpEpController,
                    keyboardType: TextInputType.number,
                    textInputAction: TextInputAction.go,
                    onSubmitted: _jumpToEpisode,
                    style: const TextStyle(color: Colors.white, fontSize: 12),
                    decoration: InputDecoration(
                      hintText: 'Jump to ep #',
                      hintStyle: const TextStyle(color: Colors.white38, fontSize: 11),
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 10,
                      ),
                      suffixIcon: IconButton(
                        padding: EdgeInsets.zero,
                        icon: const Icon(
                          Icons.arrow_forward_rounded,
                          color: _Palette.accent,
                          size: 16,
                        ),
                        onPressed: () =>
                            _jumpToEpisode(_jumpEpController.text),
                      ),
                    ),
                  ),
                ),

                const SizedBox(width: 8),

                // 50-Chunk Dropdown
                if (totalBatches > 1)
                  Container(
                    height: 34,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF141724),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: _Palette.accent.withValues(alpha: 0.4),
                      ),
                    ),
                    child: DropdownButton<int>(
                      value: currentBatchSafe,
                      underline: const SizedBox.shrink(),
                      dropdownColor: const Color(0xFF141724),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                      icon: const Icon(
                        Icons.expand_more_rounded,
                        color: _Palette.accent,
                        size: 16,
                      ),
                      items: List.generate(
                        totalBatches,
                        (idx) {
                          final start = idx * _chunkSize + 1;
                          final end = math.min((idx + 1) * _chunkSize, totalEps);
                          return DropdownMenuItem(
                            value: idx,
                            child: Text('$start – $end'),
                          );
                        },
                      ),
                      onChanged: (val) {
                        if (val != null) {
                          setState(() => _selectedEpisodeBatch = val);
                        }
                      },
                    ),
                  ),
              ],
            ),
          ],
        ),

        const SizedBox(height: _Space.md),

        // Episode Grid
        _buildEpisodeGrid(
          totalEps,
          currentBatchSafe * _chunkSize,
          math.min((currentBatchSafe + 1) * _chunkSize, totalEps),
          watchItem?.lastWatchedEpisode,
        ),
      ],
    );
  }

  Widget _buildEpisodeGrid(
    int total,
    int startIndex,
    int endIndex,
    int? lastWatchedEp,
  ) {
    final count = endIndex - startIndex;
    if (count <= 0) return const SizedBox.shrink();

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 85,
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        childAspectRatio: 1.4,
      ),
      itemCount: count,
      itemBuilder: (context, index) {
        final epNum = startIndex + index + 1;
        final isWatched = lastWatchedEp != null && epNum <= lastWatchedEp;
        final isCurrent = lastWatchedEp == epNum;
        final isHighlighted = _highlightedEpisode == epNum;

        return _HoverScale(
          onTap: () => _playEpisode(epNum),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            decoration: BoxDecoration(
              color: isHighlighted
                  ? const Color(0xFFEF4444).withValues(alpha: 0.30)
                  : isCurrent
                      ? _Palette.accent.withValues(alpha: 0.35)
                      : (isWatched
                          ? Colors.white.withValues(alpha: 0.08)
                          : const Color(0xFF141724)),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: isHighlighted
                    ? const Color(0xFFEF4444)
                    : isCurrent
                        ? _Palette.accent
                        : (isWatched
                            ? Colors.white24
                            : Colors.white.withValues(alpha: 0.08)),
                width: (isCurrent || isHighlighted) ? 1.5 : 1,
              ),
            ),
            child: Center(
              child: Text(
                '$epNum',
                style: TextStyle(
                  color: isHighlighted
                      ? const Color(0xFFEF4444)
                      : isCurrent
                          ? _Palette.accent
                          : (isWatched ? Colors.white70 : Colors.white),
                  fontSize: 13.5,
                  fontWeight: (isCurrent || isHighlighted)
                      ? FontWeight.w900
                      : FontWeight.bold,
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  // ─── Franchise & Relations Row ─────────────────────────────────
  Widget _buildRelationsRow() {
    final isDesktop = _isDesktop();
    final cardWidth = isDesktop ? 165.0 : 135.0;
    final cardHeight = cardWidth * 1.5 + 68.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader('Franchise & Relations'),
        const SizedBox(height: _Space.md),
        MouseRegion(
          onEnter: (_) => setState(() => _isHoveringRelations = true),
          onExit: (_) => setState(() => _isHoveringRelations = false),
          child: Stack(
            children: [
              SizedBox(
                height: cardHeight,
                child: ListView.separated(
                  controller: _relationsScrollController,
                  scrollDirection: Axis.horizontal,
                  physics: const BouncingScrollPhysics(),
                  itemCount: _anime.relations.length,
                  separatorBuilder: (_, __) => const SizedBox(width: _Space.md),
                  itemBuilder: (context, index) {
                    final rel = _anime.relations[index];
                    return SizedBox(
                      width: cardWidth,
                      child: _HoverScale(
                        onTap: () async {
                          final media = await AnilistService.instance
                              .fetchAnimeDetails(rel.id);
                          if (media != null && mounted) {
                            _navigateToAnime(media);
                          }
                        },
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            DecoratedBox(
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(12),
                                boxShadow: [
                                  BoxShadow(
                                    color: _Palette.accent.withValues(alpha: 0.15),
                                    blurRadius: 18,
                                    spreadRadius: -4,
                                  ),
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.45),
                                    blurRadius: 14,
                                    offset: const Offset(0, 6),
                                  ),
                                ],
                              ),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(12),
                                child: AspectRatio(
                                  aspectRatio: 2 / 3,
                                  child: CachedNetworkImage(
                                    imageUrl: rel.coverUrl,
                                    fit: BoxFit.cover,
                                    errorWidget: (_, __, ___) => Container(
                                      color: _Palette.surface,
                                      child: const Icon(
                                        Icons.movie_creation_outlined,
                                        color: Colors.white24,
                                        size: 32,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: _Palette.accent.withValues(alpha: 0.18),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                rel.relationType.replaceAll('_', ' '),
                                style: const TextStyle(
                                  color: _Palette.accent,
                                  fontSize: 9.5,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 0.2,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              rel.title,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                height: 1.2,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
              if (_canScrollRelationsLeft)
                Positioned(
                  left: 0,
                  top: 0,
                  bottom: 0,
                  child: _buildScrollArrow(
                    icon: Icons.chevron_left_rounded,
                    onTap: () => _scrollList(_relationsScrollController, -1),
                    visible: _isHoveringRelations,
                  ),
                ),
              if (_canScrollRelationsRight)
                Positioned(
                  right: 0,
                  top: 0,
                  bottom: 0,
                  child: _buildScrollArrow(
                    icon: Icons.chevron_right_rounded,
                    onTap: () => _scrollList(_relationsScrollController, 1),
                    visible: _isHoveringRelations,
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  // ─── Recommendations Row ───────────────────────────────────────
  Widget _buildRecommendationsRow() {
    final isDesktop = _isDesktop();
    final cardWidth = isDesktop ? 165.0 : 135.0;
    final cardHeight = cardWidth * 1.5 + 68.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader('You May Also Like'),
        const SizedBox(height: _Space.md),
        MouseRegion(
          onEnter: (_) => setState(() => _isHoveringRecs = true),
          onExit: (_) => setState(() => _isHoveringRecs = false),
          child: Stack(
            children: [
              SizedBox(
                height: cardHeight,
                child: ListView.separated(
                  controller: _recsScrollController,
                  scrollDirection: Axis.horizontal,
                  physics: const BouncingScrollPhysics(),
                  itemCount: _anime.recommendations.length,
                  separatorBuilder: (_, __) => const SizedBox(width: _Space.md),
                  itemBuilder: (context, index) {
                    final rec = _anime.recommendations[index];
                    return SizedBox(
                      width: cardWidth,
                      child: _HoverScale(
                        onTap: () => _navigateToAnime(rec),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            DecoratedBox(
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(12),
                                boxShadow: [
                                  BoxShadow(
                                    color: _Palette.accent.withValues(alpha: 0.15),
                                    blurRadius: 18,
                                    spreadRadius: -4,
                                  ),
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.45),
                                    blurRadius: 14,
                                    offset: const Offset(0, 6),
                                  ),
                                ],
                              ),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(12),
                                child: AspectRatio(
                                  aspectRatio: 2 / 3,
                                  child: CachedNetworkImage(
                                    imageUrl: rec.coverUrl,
                                    fit: BoxFit.cover,
                                    errorWidget: (_, __, ___) => Container(
                                      color: _Palette.surface,
                                      child: const Icon(
                                        Icons.movie_creation_outlined,
                                        color: Colors.white24,
                                        size: 32,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              rec.displayTitle,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                height: 1.25,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            if (rec.formattedFormat.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(top: 2),
                                child: Text(
                                  rec.formattedFormat,
                                  style: const TextStyle(
                                    color: Colors.white38,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w500,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
              if (_canScrollRecsLeft)
                Positioned(
                  left: 0,
                  top: 0,
                  bottom: 0,
                  child: _buildScrollArrow(
                    icon: Icons.chevron_left_rounded,
                    onTap: () => _scrollList(_recsScrollController, -1),
                    visible: _isHoveringRecs,
                  ),
                ),
              if (_canScrollRecsRight)
                Positioned(
                  right: 0,
                  top: 0,
                  bottom: 0,
                  child: _buildScrollArrow(
                    icon: Icons.chevron_right_rounded,
                    onTap: () => _scrollList(_recsScrollController, 1),
                    visible: _isHoveringRecs,
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSectionHeader(String title) {
    return Text(
      title,
      style: const TextStyle(
        fontSize: 20,
        fontWeight: FontWeight.w800,
        letterSpacing: -0.4,
        color: Colors.white,
      ),
    );
  }

  Widget _buildScrollArrow({
    required IconData icon,
    required VoidCallback onTap,
    required bool visible,
  }) {
    return AnimatedOpacity(
      opacity: visible ? 1.0 : 0.0,
      duration: const Duration(milliseconds: 200),
      child: Center(
        child: ClipOval(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
            child: Material(
              color: Colors.black.withValues(alpha: 0.65),
              child: InkWell(
                onTap: onTap,
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: Icon(icon, color: Colors.white, size: 24),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _HoverScale extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  const _HoverScale({required this.child, this.onTap});

  @override
  State<_HoverScale> createState() => _HoverScaleState();
}

class _HoverScaleState extends State<_HoverScale> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      cursor: widget.onTap != null
          ? SystemMouseCursors.click
          : SystemMouseCursors.basic,
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          transform: Matrix4.identity()
            ..scaleByDouble(
              _hover ? 1.04 : 1.0,
              _hover ? 1.04 : 1.0,
              1.0,
              1.0,
            ),
          transformAlignment: Alignment.center,
          child: widget.child,
        ),
      ),
    );
  }
}
