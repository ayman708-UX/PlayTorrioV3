import 'dart:async';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:liquid_glass_easy/liquid_glass_easy.dart';

import '../../models/anime/anime_media.dart';
import '../../services/anime/anilist_service.dart';
import '../../services/anime/anime_library_service.dart';
import '../../services/glass_settings.dart';
import '../../utils/route_transitions.dart';
import '../../widgets/anime/anime_slider_section.dart';
import '../../widgets/common/app_dock.dart';
import '../../widgets/common/liquid_dock.dart';
import '../collection/collection_page.dart';
import '../search/search_page.dart';
import '../settings/settings_page.dart';
import 'anime_details_modal.dart';
import 'anime_stream_sheet.dart';

class AnimePage extends StatefulWidget {
  const AnimePage({super.key});

  @override
  State<AnimePage> createState() => _AnimePageState();
}

class _AnimePageState extends State<AnimePage> {
  final AnilistService _anilistService = AnilistService.instance;
  final AnimeLibraryService _libraryService = AnimeLibraryService.instance;
  final ScrollController _scrollController = ScrollController();

  bool _loading = true;
  String? _error;

  List<AnimeMedia> _trending = [];
  List<AnimeMedia> _popularSeason = [];
  List<AnimeMedia> _topRated = [];
  List<AnimeMedia> _upcoming = [];
  List<AnimeMedia> _actionAnime = [];
  List<AnimeMedia> _romanceAnime = [];
  List<AnimeMedia> _fantasyAnime = [];
  List<AnimeMedia> _sciFiAnime = [];

  AnimeMedia? _activeDetailsModal;

  @override
  void initState() {
    super.initState();
    _libraryService.addListener(_onLibraryChanged);
    _libraryService.init();
    _loadAnimeData();
  }

  @override
  void dispose() {
    _libraryService.removeListener(_onLibraryChanged);
    _scrollController.dispose();
    super.dispose();
  }

  void _onLibraryChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _loadAnimeData() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final trendingFut = _anilistService.fetchTrendingAnime(perPage: 18);
      final seasonFut = _anilistService.fetchPopularThisSeason(perPage: 18);
      final topRatedFut = _anilistService.fetchTopRated(perPage: 18);
      final upcomingFut = _anilistService.fetchUpcomingNextSeason(perPage: 18);
      final actionFut = _anilistService.fetchByGenre('Action', perPage: 18);
      final romanceFut = _anilistService.fetchByGenre('Romance', perPage: 18);
      final fantasyFut = _anilistService.fetchByGenre('Fantasy', perPage: 18);
      final sciFiFut = _anilistService.fetchByGenre('Sci-Fi', perPage: 18);

      final results = await Future.wait([
        trendingFut,
        seasonFut,
        topRatedFut,
        upcomingFut,
        actionFut,
        romanceFut,
        fantasyFut,
        sciFiFut,
      ]);

      if (mounted) {
        setState(() {
          _trending = results[0];
          _popularSeason = results[1];
          _topRated = results[2];
          _upcoming = results[3];
          _actionAnime = results[4];
          _romanceAnime = results[5];
          _fantasyAnime = results[6];
          _sciFiAnime = results[7];
          _loading = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading Anime data: $e');
      if (mounted) {
        setState(() {
          _error = 'Failed to load Anime catalog. Check your internet connection.';
          _loading = false;
        });
      }
    }
  }

  void _playEpisode(AnimeMedia anime, int episodeNumber, [bool isDub = false]) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => AnimeStreamSheet(
        anime: anime,
        episodeNumber: episodeNumber,
        autoPlay: true,
      ),
    );
  }

  void _openDetails(AnimeMedia anime) {
    setState(() => _activeDetailsModal = anime);
  }

  void _navigateToSettings(Offset? tapPosition) {
    Navigator.push(
      context,
      LiquidRevealRoute(
        page: const SettingsPage(),
        tapPosition: tapPosition,
      ),
    );
  }

  void _navigateToSearch(Offset? tapPosition) {
    Navigator.push(
      context,
      LiquidRevealRoute(
        page: const SearchPage(),
        tapPosition: tapPosition,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final topPadding = MediaQuery.of(context).padding.top;

    final backgroundContent = Stack(
      children: [
        // Ambient background glows matching Home
        Positioned(
          top: -120,
          right: -120,
          child: Container(
            width: 500,
            height: 500,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0xFF7C5CFF).withValues(alpha: 0.08),
            ),
          ),
        ),
        Positioned(
          bottom: 100,
          left: -100,
          child: Container(
            width: 450,
            height: 450,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0xFF00D2EF).withValues(alpha: 0.05),
            ),
          ),
        ),

        // Main scrollable content
        if (_loading && _trending.isEmpty)
          const Center(
            child: CircularProgressIndicator(color: Color(0xFF7C5CFF)),
          )
        else if (_error != null && _trending.isEmpty)
          Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(
                  Icons.error_outline_rounded,
                  color: Colors.redAccent,
                  size: 48,
                ),
                const SizedBox(height: 16),
                Text(
                  _error!,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 16),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF7C5CFF),
                  ),
                  onPressed: _loadAnimeData,
                  child: const Text('Retry'),
                ),
              ],
            ),
          )
        else
          RefreshIndicator(
            color: const Color(0xFF7C5CFF),
            backgroundColor: const Color(0xFF151822),
            onRefresh: _loadAnimeData,
            child: ListView(
              controller: _scrollController,
              clipBehavior: Clip.none,
              padding: EdgeInsets.zero,
              physics: const BouncingScrollPhysics(
                parent: AlwaysScrollableScrollPhysics(),
              ),
              children: [
                // 1. Full Bleed Hero Carousel (Matching Home Page)
                if (_trending.isNotEmpty)
                  _AnimeHeroCarousel(
                    animeList: _trending.take(6).toList(),
                    onWatchNow: (anime) => _playEpisode(anime, 1),
                    onDetailsTap: _openDetails,
                  ),

                const SizedBox(height: 24),

                // 2. Sliders with Desktop Scroll Arrows
                AnimeSliderSection(
                  title: '🔥 Trending Anime',
                  subtitle: 'Top popular and trending series',
                  animeList: _trending,
                  onAnimeTap: _openDetails,
                ),
                AnimeSliderSection(
                  title: '🌟 Popular This Season (${AnilistService.currentSeason()})',
                  subtitle: 'Currently airing hits',
                  animeList: _popularSeason,
                  onAnimeTap: _openDetails,
                ),
                AnimeSliderSection(
                  title: '⭐ All-Time Masterpieces',
                  subtitle: 'Critically acclaimed top rated anime',
                  animeList: _topRated,
                  onAnimeTap: _openDetails,
                ),
                AnimeSliderSection(
                  title: '🚀 Anticipated Next Season',
                  subtitle: 'Upcoming anime you cannot miss',
                  animeList: _upcoming,
                  onAnimeTap: _openDetails,
                ),
                AnimeSliderSection(
                  title: '⚔️ Action & Adventure',
                  subtitle: 'High octane battles and epic journeys',
                  animeList: _actionAnime,
                  onAnimeTap: _openDetails,
                ),
                AnimeSliderSection(
                  title: '💖 Romance & Drama',
                  subtitle: 'Heartfelt emotional stories',
                  animeList: _romanceAnime,
                  onAnimeTap: _openDetails,
                ),
                AnimeSliderSection(
                  title: '🔮 Fantasy & Isekai',
                  subtitle: 'Magical realms and alternate worlds',
                  animeList: _fantasyAnime,
                  onAnimeTap: _openDetails,
                ),
                AnimeSliderSection(
                  title: '🤖 Sci-Fi & Cyberpunk',
                  subtitle: 'Futuristic technologies and dystopian worlds',
                  animeList: _sciFiAnime,
                  onAnimeTap: _openDetails,
                ),

                const SizedBox(height: 90),
              ],
            ),
          ),
      ],
    );

    final overlayChildren = <Widget>[
      // Floating Glass App Bar (Home Page Style)
      Positioned(
        top: 0,
        left: 0,
        right: 0,
        child: _AnimeGlassAppBar(
          topPadding: topPadding,
          onSearchTap: _navigateToSearch,
          onSettingsTap: _navigateToSettings,
        ),
      ),

      // Anime Details Modal Popup
      if (_activeDetailsModal != null)
        Positioned.fill(
          child: AnimeDetailsModal(
            initialAnime: _activeDetailsModal!,
            onPlayEpisode: (anime, epNum, dub) {
              setState(() => _activeDetailsModal = null);
              _playEpisode(anime, epNum, dub);
            },
            onNavigateToAnime: (nextAnime) {
              setState(() => _activeDetailsModal = nextAnime);
            },
            onClose: () => setState(() => _activeDetailsModal = null),
          ),
        ),
    ];

    return Scaffold(
      backgroundColor: const Color(0xFF080A0F),
      body: ValueListenableBuilder<bool>(
        valueListenable: GlassSettings.enabled,
        builder: (context, enabled, _) {
          final overlays = Stack(children: overlayChildren);
          if (enabled) {
            return LiquidGlassView(
              realTimeCapture: true,
              useSync: true,
              pixelRatio: 0.85,
              refreshRate: LiquidGlassRefreshRate.deviceRefreshRate,
              regionCapture: true,
              backgroundWidget: backgroundContent,
              child: overlays,
            );
          }

          return Container(
            color: const Color(0xFF080A0F),
            child: Stack(
              children: [
                RepaintBoundary(child: backgroundContent),
                ...overlayChildren,
              ],
            ),
          );
        },
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Frosted Glass App Bar for Anime (Matching Home Page GlassAppBar)
// ─────────────────────────────────────────────────────────────────────────────

class _AnimeGlassAppBar extends StatelessWidget {
  final double topPadding;
  final void Function(Offset?) onSearchTap;
  final void Function(Offset?) onSettingsTap;

  const _AnimeGlassAppBar({
    required this.topPadding,
    required this.onSearchTap,
    required this.onSettingsTap,
  });

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: Container(
        padding: EdgeInsets.only(
          top: topPadding + 10,
          bottom: 14,
          left: 20,
          right: 8,
        ),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: const [Color(0xF5080A0F), Color(0xE6080A0F)],
          ),
          border: Border(
            bottom: BorderSide(color: Colors.white.withValues(alpha: 0.06)),
          ),
        ),
        child: Row(
          children: [
            // Back button
            IconButton(
              icon: const Icon(
                Icons.arrow_back_ios_new_rounded,
                color: Colors.white,
                size: 20,
              ),
              onPressed: () => Navigator.pop(context),
            ),
            const SizedBox(width: 4),

            // Logo
            Image.asset(
              'assets/icon.png',
              width: 32,
              height: 32,
              fit: BoxFit.contain,
            ),
            const SizedBox(width: 10),
            RichText(
              text: const TextSpan(
                text: 'PlayTorrio ',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.5,
                  color: Colors.white,
                ),
                children: [
                  TextSpan(
                    text: 'Anime',
                    style: TextStyle(
                      color: Color(0xFF7C5CFF),
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
            ),
            const Spacer(),

            // Search Button
            Builder(
              builder: (context) {
                return IconButton(
                  icon: Icon(
                    Icons.search_rounded,
                    color: Colors.white.withValues(alpha: 0.65),
                    size: 25,
                  ),
                  onPressed: () {
                    final box = context.findRenderObject() as RenderBox?;
                    final offset = box != null
                        ? box.localToGlobal(box.size.center(Offset.zero))
                        : null;
                    onSearchTap(offset);
                  },
                );
              },
            ),

            // Settings Button
            Builder(
              builder: (context) {
                return IconButton(
                  icon: Icon(
                    Icons.settings_rounded,
                    color: Colors.white.withValues(alpha: 0.65),
                    size: 24,
                  ),
                  onPressed: () {
                    final box = context.findRenderObject() as RenderBox?;
                    final offset = box != null
                        ? box.localToGlobal(box.size.center(Offset.zero))
                        : null;
                    onSettingsTap(offset);
                  },
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Full-Bleed Anime Hero Carousel (Matching Home Page _HeroCarousel)
// ─────────────────────────────────────────────────────────────────────────────

class _AnimeHeroCarousel extends StatefulWidget {
  final List<AnimeMedia> animeList;
  final Function(AnimeMedia) onWatchNow;
  final Function(AnimeMedia) onDetailsTap;

  const _AnimeHeroCarousel({
    required this.animeList,
    required this.onWatchNow,
    required this.onDetailsTap,
  });

  @override
  State<_AnimeHeroCarousel> createState() => _AnimeHeroCarouselState();
}

class _AnimeHeroCarouselState extends State<_AnimeHeroCarousel> {
  static const _rotateEvery = Duration(seconds: 8);
  final PageController _pageController = PageController();

  Timer? _timer;
  int _index = 0;
  bool _isHovering = false;

  @override
  void initState() {
    super.initState();
    _startTimer();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _pageController.dispose();
    super.dispose();
  }

  void _startTimer() {
    _timer?.cancel();
    if (widget.animeList.length < 2) return;
    _timer = Timer.periodic(_rotateEvery, (_) {
      if (!mounted || !_pageController.hasClients) return;
      final next = (_index + 1) % widget.animeList.length;
      _pageController.animateToPage(
        next,
        duration: const Duration(milliseconds: 700),
        curve: Curves.easeInOutCubic,
      );
    });
  }

  void _pauseTimer() => _timer?.cancel();

  void _goTo(int index) {
    if (!_pageController.hasClients) return;
    _pageController.animateToPage(
      index,
      duration: const Duration(milliseconds: 600),
      curve: Curves.easeInOutCubic,
    );
  }

  double _heroHeight(double screenWidth, double screenHeight) {
    if (screenWidth < 600) {
      return (screenHeight * 0.66).clamp(460.0, 640.0);
    } else if (screenWidth < 1000) {
      return (screenHeight * 0.62).clamp(520.0, 680.0);
    } else {
      return (screenHeight * 0.78).clamp(620.0, 760.0);
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.sizeOf(context).width;
    final screenHeight = MediaQuery.sizeOf(context).height;
    final heroHeight = _heroHeight(screenWidth, screenHeight);

    if (widget.animeList.isEmpty) return SizedBox(height: heroHeight);

    return MouseRegion(
      onEnter: (_) {
        setState(() => _isHovering = true);
        _pauseTimer();
      },
      onExit: (_) {
        setState(() => _isHovering = false);
        _startTimer();
      },
      child: SizedBox(
        height: heroHeight,
        width: double.infinity,
        child: Stack(
          fit: StackFit.expand,
          children: [
            PageView.builder(
              controller: _pageController,
              itemCount: widget.animeList.length,
              onPageChanged: (i) => setState(() => _index = i),
              itemBuilder: (context, i) {
                final anime = widget.animeList[i];
                return _AnimeHeroSlide(
                  anime: anime,
                  screenWidth: screenWidth,
                  onWatchNow: () => widget.onWatchNow(anime),
                  onDetailsTap: () => widget.onDetailsTap(anime),
                );
              },
            ),

            // Dot indicators
            if (widget.animeList.length > 1)
              Positioned(
                bottom: 14,
                left: 0,
                right: 0,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(widget.animeList.length, (i) {
                    final active = i == _index;
                    return GestureDetector(
                      onTap: () => _goTo(i),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 250),
                        curve: Curves.easeOutCubic,
                        margin: const EdgeInsets.symmetric(horizontal: 4),
                        width: active ? 22 : 7,
                        height: 7,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(4),
                          color: active
                              ? const Color(0xFF7C5CFF)
                              : Colors.white.withValues(alpha: 0.30),
                          boxShadow: active
                              ? [
                                  BoxShadow(
                                    color: const Color(0xFF7C5CFF)
                                        .withValues(alpha: 0.55),
                                    blurRadius: 8,
                                  ),
                                ]
                              : null,
                        ),
                      ),
                    );
                  }),
                ),
              ),

            // Desktop Hover Arrows
            if (widget.animeList.length > 1 &&
                _isHovering &&
                screenWidth > 600) ...[
              if (_index > 0)
                Positioned(
                  left: 24,
                  top: 0,
                  bottom: 0,
                  child: Center(
                    child: _CarouselArrow(
                      icon: Icons.arrow_back_ios_new_rounded,
                      onTap: () => _goTo(_index - 1),
                    ),
                  ),
                ),
              if (_index < widget.animeList.length - 1)
                Positioned(
                  right: 24,
                  top: 0,
                  bottom: 0,
                  child: Center(
                    child: _CarouselArrow(
                      icon: Icons.arrow_forward_ios_rounded,
                      onTap: () => _goTo(_index + 1),
                    ),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class _AnimeHeroSlide extends StatelessWidget {
  final AnimeMedia anime;
  final double screenWidth;
  final VoidCallback onWatchNow;
  final VoidCallback onDetailsTap;

  const _AnimeHeroSlide({
    required this.anime,
    required this.screenWidth,
    required this.onWatchNow,
    required this.onDetailsTap,
  });

  @override
  Widget build(BuildContext context) {
    final isCompact = screenWidth < 600;

    return Stack(
      fit: StackFit.expand,
      children: [
        // Background Image
        CachedNetworkImage(
          imageUrl: anime.backdropUrl,
          fit: BoxFit.cover,
          alignment: Alignment.topCenter,
          filterQuality: FilterQuality.medium,
          placeholder: (_, __) => const ColoredBox(color: Color(0xFF151822)),
          errorWidget: (_, __, ___) => const ColoredBox(color: Color(0xFF151822)),
        ),

        // Top Gradient
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.center,
                colors: [
                  const Color(0xFF080A0F).withValues(alpha: 0.75),
                  Colors.transparent,
                ],
              ),
            ),
          ),
        ),

        // Bottom Gradient
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.bottomCenter,
                end: Alignment.topCenter,
                stops: const [0.0, 0.35, 0.75],
                colors: [
                  const Color(0xFF080A0F),
                  const Color(0xFF080A0F).withValues(alpha: 0.85),
                  Colors.transparent,
                ],
              ),
            ),
          ),
        ),

        // Content Overlay
        Positioned(
          left: 26,
          right: 26,
          bottom: 48,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Rating + Year + Episodes row
              Row(
                children: [
                  if (anime.averageScore > 0) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 11,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFD700).withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(9),
                        border: Border.all(
                          color: const Color(0xFFFFD700).withValues(alpha: 0.28),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.star_rounded,
                            size: 17,
                            color: Color(0xFFFFD700),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            anime.formattedScore,
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFFFFD700),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                  ],
                  if (anime.seasonYear > 0)
                    Text(
                      '${anime.seasonYear}',
                      style: TextStyle(
                        fontSize: 15,
                        color: Colors.white.withValues(alpha: 0.55),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  if (anime.totalEpisodes > 0) ...[
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Icon(
                        Icons.circle,
                        size: 4,
                        color: Colors.white.withValues(alpha: 0.25),
                      ),
                    ),
                    Text(
                      '${anime.totalEpisodes} Episodes',
                      style: TextStyle(
                        fontSize: 15,
                        color: Colors.white.withValues(alpha: 0.55),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                  if (anime.studioName.isNotEmpty) ...[
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Icon(
                        Icons.circle,
                        size: 4,
                        color: Colors.white.withValues(alpha: 0.25),
                      ),
                    ),
                    Text(
                      anime.studioName,
                      style: TextStyle(
                        fontSize: 15,
                        color: Colors.white.withValues(alpha: 0.55),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ],
              ),

              const SizedBox(height: 16),

              // Title
              Text(
                anime.displayTitle,
                style: TextStyle(
                  fontSize: isCompact ? 30 : 44,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -1.2,
                  height: 1.05,
                  color: Colors.white,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),

              // Description
              if (anime.description.isNotEmpty) ...[
                SizedBox(height: isCompact ? 12 : 16),
                ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: isCompact ? double.infinity : 580,
                  ),
                  child: Text(
                    anime.description,
                    maxLines: isCompact ? 2 : 3,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: isCompact ? 14.5 : 15.5,
                      color: Colors.white.withValues(alpha: 0.65),
                      height: 1.5,
                    ),
                  ),
                ),
              ],

              // Genre chips
              if (anime.genres.isNotEmpty) ...[
                const SizedBox(height: 16),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: anime.genres.take(4).map((genre) {
                    return Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 13,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.12),
                        ),
                      ),
                      child: Text(
                        genre,
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.white.withValues(alpha: 0.70),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ],

              // Action buttons (Matching Home Page)
              SizedBox(height: isCompact ? 22 : 26),
              Row(
                children: [
                  ElevatedButton.icon(
                    onPressed: onWatchNow,
                    icon: const Icon(Icons.play_arrow_rounded, size: 24),
                    label: const Text(
                      'Watch Ep 1',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 15.5,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF7C5CFF),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 28,
                        vertical: 16,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      elevation: 12,
                      shadowColor: const Color(0xFF7C5CFF).withValues(alpha: 0.45),
                    ),
                  ),
                  const SizedBox(width: 12),
                  OutlinedButton.icon(
                    onPressed: onDetailsTap,
                    icon: Icon(
                      Icons.info_outline_rounded,
                      size: 21,
                      color: Colors.white.withValues(alpha: 0.80),
                    ),
                    label: Text(
                      'Details',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 15.5,
                        color: Colors.white.withValues(alpha: 0.80),
                      ),
                    ),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 16,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      side: BorderSide(
                        color: Colors.white.withValues(alpha: 0.18),
                        width: 1.2,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _CarouselArrow extends StatefulWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _CarouselArrow({required this.icon, required this.onTap});

  @override
  State<_CarouselArrow> createState() => _CarouselArrowState();
}

class _CarouselArrowState extends State<_CarouselArrow> {
  bool _isHoveringArrow = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHoveringArrow = true),
      onExit: (_) => setState(() => _isHoveringArrow = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          width: 52,
          height: 52,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: _isHoveringArrow
                ? Colors.black.withValues(alpha: 0.6)
                : Colors.black.withValues(alpha: 0.3),
            border: Border.all(
              color: _isHoveringArrow
                  ? Colors.white.withValues(alpha: 0.6)
                  : Colors.white.withValues(alpha: 0.2),
              width: 1.5,
            ),
          ),
          child: Icon(
            widget.icon,
            color: _isHoveringArrow ? Colors.white : Colors.white70,
            size: 24,
          ),
        ),
      ),
    );
  }
}
