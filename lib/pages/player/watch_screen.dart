import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:liquid_glass_easy/liquid_glass_easy.dart';

import 'package:url_launcher/url_launcher.dart';

import '../../models/movie/movie.dart';
import '../../models/movie/link.dart';
import '../../models/movie/video.dart';
import '../../models/movie/movie_detail.dart';

import '../../models/stream/stream_model.dart';
import './player_screen.dart';
import '../../services/stream/stream_service.dart';
import '../../services/glass_settings.dart';
import '../../utils/fullscreen_navigator.dart';
import '../../widgets/common/performance_liquid_lens.dart';
import '../settings/settings_page.dart';
import '../details/details_page.dart';
import '../../utils/route_transitions.dart';

// ---------------------------------------------------------------------------
// Design tokens
// ---------------------------------------------------------------------------
class _C {
  static const bg = Color(0xFF0A0C10);
  static const surface = Color(0xFF13151C);
  static const surfaceLight = Color(0xFF1A1D26);
  static const accent = Color(0xFF7C5CFF);
  static const textPrimary = Color(0xFFF5F5F7);
  static const textSecondary = Color(0xFFAAAAAF);
  static const textTertiary = Color(0xFF66666B);
  static const gold = Color(0xFFFFC107);
}

class _S {
  static const xs = 8.0;
  static const sm = 12.0;
  static const md = 16.0;
  static const lg = 24.0;
}

// ---------------------------------------------------------------------------
// WatchScreen
// ---------------------------------------------------------------------------
class WatchScreen extends StatefulWidget {
  final MovieDetail detail;
  final Video? selectedEpisode;
  final String type;

  const WatchScreen({
    super.key,
    required this.detail,
    this.selectedEpisode,
    required this.type,
  });

  @override
  State<WatchScreen> createState() => _WatchScreenState();
}

class _WatchScreenState extends State<WatchScreen>
    with SingleTickerProviderStateMixin {
  // Stream sources
  final List<StreamSource> _sources = [];
  final List<StreamSource> _pendingSources = [];
  Timer? _sourceBatchTimer;
  bool _isLoadingSources = true;

  // Animation
  late AnimationController _animController;
  late Animation<double> _fadeAnim;
  late Animation<Offset> _slideAnim;

  // Scroll
  final ScrollController _sourcesScrollController = ScrollController();
  final ScrollController _mainScrollController = ScrollController();

  @override
  void initState() {
    super.initState();

    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _fadeAnim = CurvedAnimation(parent: _animController, curve: Curves.easeOut);
    _slideAnim = Tween<Offset>(begin: const Offset(0, 0.03), end: Offset.zero)
        .animate(
          CurvedAnimation(parent: _animController, curve: Curves.easeOutCubic),
        );

    _animController.forward();
    _loadStreams();
  }

  @override
  void dispose() {
    _sourceBatchTimer?.cancel();
    _animController.dispose();
    _sourcesScrollController.dispose();
    _mainScrollController.dispose();
    super.dispose();
  }

  Future<void> _loadStreams() async {
    final streamId = widget.selectedEpisode?.id ?? widget.detail.id;

    try {
      await for (final source in StreamService.fetchStreams(
        type: widget.type,
        id: streamId,
        title: widget.detail.name,
        year: int.tryParse(widget.detail.year ?? ''),
        season: widget.selectedEpisode?.season,
        episode: widget.selectedEpisode?.episode,
      )) {
        if (!mounted) return;
        _pendingSources.add(source);
        _sourceBatchTimer ??= Timer(
          const Duration(milliseconds: 60),
          _flushPendingSources,
        );
      }
    } catch (_) {}

    _flushPendingSources();
    if (mounted && _isLoadingSources) {
      setState(() => _isLoadingSources = false);
    }
  }

  void _flushPendingSources() {
    _sourceBatchTimer?.cancel();
    _sourceBatchTimer = null;
    if (!mounted || _pendingSources.isEmpty) return;

    final batch = List<StreamSource>.of(_pendingSources);
    _pendingSources.clear();
    setState(() {
      _sources.addAll(batch);
      _isLoadingSources = false;
    });
  }

  /// Called by the player's auto-next dialog. Pops the player and re-opens the
  /// watch screen for the next episode (season/episode +1).
  void _playNextEpisode() {
    final ep = widget.selectedEpisode;
    if (ep == null) return;

    final nextEpisode = Video(
      id: ep.id,
      title: ep.title,
      season: ep.season,
      episode: (ep.episode ?? 0) + 1,
      released: ep.released,
      thumbnail: ep.thumbnail,
      overview: ep.overview,
    );

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => WatchScreen(
          detail: widget.detail,
          selectedEpisode: nextEpisode,
          type: widget.type,
        ),
      ),
    );
  }

  String? _selectedAddonFilter;

  List<StreamSource> get _filteredSources {
    var sorted = List<StreamSource>.from(_sources);
    if (_selectedAddonFilter != null) {
      sorted = sorted
          .where((s) => s.addonName == _selectedAddonFilter)
          .toList();
    }
    sorted.sort((a, b) => b.qualityRank.compareTo(a.qualityRank));
    return sorted;
  }

  bool _isDesktop() => MediaQuery.sizeOf(context).width >= 900;

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.sizeOf(context);
    final bgUrl = widget.detail.background ?? widget.detail.poster;
    final isDesktop = _isDesktop();

    final background = Stack(
      children: [
        const Positioned.fill(child: ColoredBox(color: _C.bg)),
        if (bgUrl != null) _buildBackdrop(bgUrl, screenSize, isDesktop),
      ],
    );
    final content = Stack(
      children: [
        SafeArea(
          child: isDesktop
              ? _buildDesktopLayout(screenSize)
              : _buildMobileLayout(screenSize),
        ),
        Positioned(
          top: MediaQuery.of(context).padding.top + 8,
          left: 12,
          child: _buildBackButton(),
        ),
      ],
    );

    return Scaffold(
      backgroundColor: _C.bg,
      body: ValueListenableBuilder<bool>(
        valueListenable: GlassSettings.enabled,
        builder: (context, enabled, _) {
          if (enabled) {
            return LiquidGlassView(
              realTimeCapture: true,
              useSync: true,
              pixelRatio: 0.85,
              refreshRate: LiquidGlassRefreshRate.deviceRefreshRate,
              regionCapture: true,
              backgroundWidget: background,
              child: content,
            );
          }
          return Stack(children: [background, content]);
        },
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Backdrop
  // ─────────────────────────────────────────────────────────────────────────
  Widget _buildBackdrop(String url, Size screenSize, bool isDesktop) {
    return Positioned.fill(
      child: Stack(
        fit: StackFit.expand,
        children: [
          CachedNetworkImage(
            imageUrl: url,
            fit: BoxFit.cover,
            errorWidget: (_, __, ___) => const ColoredBox(color: _C.bg),
          ),
          // Left-to-right dimming: dark on left (text side), lighter on right
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                colors: [
                  _C.bg.withValues(alpha: isDesktop ? 0.92 : 0.88),
                  _C.bg.withValues(alpha: isDesktop ? 0.70 : 0.60),
                  _C.bg.withValues(alpha: isDesktop ? 0.20 : 0.15),
                ],
                stops: const [0.0, 0.5, 1.0],
              ),
            ),
          ),
          // Bottom vertical gradient for legibility
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.transparent,
                  _C.bg.withValues(alpha: 0.30),
                  _C.bg.withValues(alpha: 0.85),
                ],
                stops: const [0.0, 0.6, 1.0],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Desktop: side-by-side 60/40
  // ─────────────────────────────────────────────────────────────────────────
  Widget _buildDesktopLayout(Size screenSize) {
    return SlideTransition(
      position: _slideAnim,
      child: FadeTransition(
        opacity: _fadeAnim,
        child: Padding(
          padding: const EdgeInsets.only(
            top: 60,
            left: 48,
            right: 0,
            bottom: 24,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Left: info region
              Expanded(
                flex: 6,
                child: SingleChildScrollView(
                  controller: _mainScrollController,
                  physics: const BouncingScrollPhysics(),
                  child: _buildInfoRegion(isDesktop: true),
                ),
              ),
              const SizedBox(width: 32),
              // Right: sources panel (extends to right edge)
              Expanded(
                flex: 4,
                child: Padding(
                  padding: const EdgeInsets.only(right: 24),
                  child: _buildSourcesPanel(isDesktop: true),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Mobile: stacked vertically
  // ─────────────────────────────────────────────────────────────────────────
  Widget _buildMobileLayout(Size screenSize) {
    final filtered = _filteredSources;

    return SlideTransition(
      position: _slideAnim,
      child: FadeTransition(
        opacity: _fadeAnim,
        child: CustomScrollView(
          controller: _mainScrollController,
          physics: const BouncingScrollPhysics(),
          slivers: [
            // ── Top padding ──
            const SliverPadding(padding: EdgeInsets.only(top: 60)),

            // ── Info region (single box) ──
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: _S.lg),
                child: _buildInfoRegion(isDesktop: false),
              ),
            ),

            const SliverPadding(padding: EdgeInsets.only(top: _S.lg)),

            // ── Sources header ──
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: _S.lg),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Row(
                          children: [
                            Icon(
                              Icons.stream_rounded,
                              color: _C.accent,
                              size: 20,
                            ),
                            SizedBox(width: _S.xs),
                            Text(
                              'Watch Sources',
                              style: TextStyle(
                                color: _C.textPrimary,
                                fontSize: 18,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                        if (_sources.isNotEmpty) _buildAddonFilterDropdown(),
                      ],
                    ),
                    const SizedBox(height: _S.sm),
                    Text(
                      _isLoadingSources
                          ? 'Searching sources...'
                          : '${filtered.length} source${filtered.length == 1 ? '' : 's'} found',
                      style: const TextStyle(
                        color: _C.textTertiary,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: _S.md),
                  ],
                ),
              ),
            ),

            // ── Sources list (virtualized!) ──
            if (_isLoadingSources && filtered.isEmpty)
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: _S.lg),
                sliver: SliverList.builder(
                  itemCount: 4,
                  itemBuilder: (context, index) => Padding(
                    padding: const EdgeInsets.only(bottom: _S.xs),
                    child: _buildShimmerCard(),
                  ),
                ),
              )
            else if (!_isLoadingSources && filtered.isEmpty)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: _S.lg),
                  child: _buildEmptyState(),
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: _S.lg),
                sliver: SliverList.builder(
                  itemCount: filtered.length + (_isLoadingSources ? 2 : 0),
                  itemBuilder: (context, index) {
                    if (index >= filtered.length) {
                      return Padding(
                        padding: const EdgeInsets.only(bottom: _S.xs),
                        child: _buildShimmerCard(),
                      );
                    }
                    return Padding(
                      padding: const EdgeInsets.only(bottom: _S.xs),
                      child: _SourceCard(
                        source: filtered[index],
                        backdropUrl:
                            widget.detail.background ?? widget.detail.poster,
                        logoUrl: widget.detail.logo,
                        detail: widget.detail,
                        episode: widget.selectedEpisode,
                        onNextEpisode: _playNextEpisode,
                      ),
                    );
                  },
                ),
              ),

            // ── Bottom padding ──
            const SliverPadding(padding: EdgeInsets.only(bottom: 24)),
          ],
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Info Region
  // ─────────────────────────────────────────────────────────────────────────
  Widget _buildInfoRegion({required bool isDesktop}) {
    final meta = widget.detail;
    final ep = widget.selectedEpisode;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Episode info header (if applicable)
        if (ep != null) ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: _C.accent.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: _C.accent.withValues(alpha: 0.3)),
            ),
            child: Text(
              'S${ep.season ?? '?'}E${ep.episode ?? '?'}',
              style: const TextStyle(
                color: _C.accent,
                fontSize: 13,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.5,
              ),
            ),
          ),
          const SizedBox(height: _S.sm),
        ],

        // Logo or title
        _buildLogoOrTitle(meta, isDesktop),
        const SizedBox(height: _S.sm),

        // Episode title (if applicable, different from series title)
        if (ep != null && ep.title.isNotEmpty && ep.title != meta.name)
          Padding(
            padding: const EdgeInsets.only(bottom: _S.sm),
            child: Text(
              ep.title,
              style: TextStyle(
                fontSize: isDesktop ? 20 : 17,
                fontWeight: FontWeight.w600,
                color: _C.textPrimary.withValues(alpha: 0.85),
              ),
            ),
          ),

        // Meta row
        _buildMetaRow(meta),
        const SizedBox(height: _S.md),

        // Genre pills
        if (meta.genres.isNotEmpty) ...[
          _buildGenrePills(meta.genres),
          const SizedBox(height: _S.lg),
        ],

        // Synopsis
        if (_getSynopsis() != null) ...[
          _buildSynopsis(_getSynopsis()!),
          const SizedBox(height: _S.lg),
        ],

        // Director
        if (meta.director.isNotEmpty) ...[
          _buildLabelChips('DIRECTOR', meta.director),
          const SizedBox(height: _S.md),
        ],

        // Cast
        if (meta.cast.isNotEmpty) ...[
          _buildLabelChips('CAST', meta.cast.take(8).toList()),
          const SizedBox(height: _S.lg),
        ],

        // Action bar
        _buildActionBar(),
        const SizedBox(height: _S.lg),
      ],
    );
  }

  String? _getSynopsis() {
    final ep = widget.selectedEpisode;
    if (ep != null && ep.overview != null && ep.overview!.isNotEmpty) {
      return ep.overview;
    }
    return widget.detail.description;
  }

  Widget _buildLogoOrTitle(MovieDetail meta, bool isDesktop) {
    if (meta.logo != null && meta.logo!.isNotEmpty) {
      return ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: isDesktop ? 380 : 260,
          maxHeight: isDesktop ? 120 : 80,
        ),
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
        fontSize: isDesktop ? 36 : 28,
        fontWeight: FontWeight.w800,
        height: 1.1,
        letterSpacing: -0.5,
        color: _C.textPrimary,
        shadows: [
          Shadow(
            color: Colors.black.withValues(alpha: 0.7),
            blurRadius: 20,
            offset: const Offset(0, 4),
          ),
        ],
      ),
    );
  }

  Widget _buildMetaRow(MovieDetail meta) {
    final items = <Widget>[];

    if (meta.year != null && meta.year!.isNotEmpty) {
      items.add(
        Text(
          meta.year!,
          style: const TextStyle(
            color: _C.textPrimary,
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
      );
    }

    if (meta.runtime != null && meta.runtime!.isNotEmpty) {
      items.add(
        Text(
          meta.runtime!,
          style: const TextStyle(color: _C.textSecondary, fontSize: 14),
        ),
      );
    }

    if (meta.imdbRating != null && meta.imdbRating!.isNotEmpty) {
      items.add(
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: _C.gold.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: _C.gold.withValues(alpha: 0.4)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.star_rounded, color: _C.gold, size: 14),
              const SizedBox(width: 3),
              Text(
                meta.imdbRating!,
                style: const TextStyle(
                  color: _C.gold,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      );
    }

    final spaced = <Widget>[];
    for (int i = 0; i < items.length; i++) {
      spaced.add(items[i]);
      if (i < items.length - 1) {
        spaced.add(
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: _S.xs),
            child: Text(
              '·',
              style: TextStyle(color: _C.textTertiary, fontSize: 16),
            ),
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

  Widget _buildGenrePills(List<String> genres) {
    return Wrap(
      spacing: _S.xs,
      runSpacing: _S.xs,
      children: genres
          .map(
            (g) => Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
              ),
              child: Text(
                g,
                style: const TextStyle(
                  color: _C.textSecondary,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          )
          .toList(),
    );
  }

  bool _synopsisExpanded = false;

  Widget _buildSynopsis(String text) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AnimatedCrossFade(
          firstChild: Text(
            text,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: _C.textSecondary,
              fontSize: 14,
              height: 1.6,
            ),
          ),
          secondChild: Text(
            text,
            style: const TextStyle(
              color: _C.textSecondary,
              fontSize: 14,
              height: 1.6,
            ),
          ),
          crossFadeState: _synopsisExpanded
              ? CrossFadeState.showSecond
              : CrossFadeState.showFirst,
          duration: const Duration(milliseconds: 250),
        ),
        const SizedBox(height: 6),
        LayoutBuilder(
          builder: (context, constraints) {
            final painter = TextPainter(
              text: TextSpan(
                text: text,
                style: const TextStyle(fontSize: 14, height: 1.6),
              ),
              maxLines: 3,
              textDirection: TextDirection.ltr,
            )..layout(maxWidth: constraints.maxWidth);

            if (!painter.didExceedMaxLines) return const SizedBox.shrink();

            return GestureDetector(
              onTap: () =>
                  setState(() => _synopsisExpanded = !_synopsisExpanded),
              child: Text(
                _synopsisExpanded ? 'Show less' : 'Read more',
                style: TextStyle(
                  color: _C.accent,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _buildLabelChips(String label, List<String> items) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: _C.textTertiary,
            fontSize: 11,
            fontWeight: FontWeight.w600,
            letterSpacing: 1.0,
          ),
        ),
        const SizedBox(height: _S.xs),
        Wrap(
          spacing: _S.xs,
          runSpacing: _S.xs,
          children: items
              .map(
                (name) => Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: _C.surfaceLight,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    name,
                    style: const TextStyle(
                      color: _C.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                ),
              )
              .toList(),
        ),
      ],
    );
  }

  Widget _buildActionBar() {
    final links = widget.detail.links.take(4).toList();

    // Fallback if no links provided by addon
    if (links.isEmpty && widget.detail.id.startsWith('tt')) {
      links.add(
        Link(
          name: 'IMDb',
          category: 'imdb',
          url: 'https://www.imdb.com/title/${widget.detail.id}/',
        ),
      );
    }

    if (links.isEmpty) {
      // Generic fallback
      final query = Uri.encodeComponent(
        '${widget.detail.name} ${widget.detail.year ?? ''}',
      );
      links.add(
        Link(
          name: 'Search',
          category: 'web',
          url: 'https://google.com/search?q=$query',
        ),
      );
    }

    return Row(
      children: links.map((link) {
        IconData icon = Icons.link_rounded;
        final nameLower = link.name.toLowerCase();
        final catLower = link.category.toLowerCase();

        if (nameLower.contains('imdb') || catLower.contains('imdb'))
          icon = Icons.movie_creation_outlined;
        else if (nameLower.contains('trailer') || catLower.contains('trailer'))
          icon = Icons.play_circle_outline;
        else if (nameLower.contains('wiki') || catLower.contains('wiki'))
          icon = Icons.article_outlined;
        else if (nameLower.contains('search') || catLower.contains('search'))
          icon = Icons.search_rounded;

        return Expanded(
          child: Padding(
            padding: EdgeInsets.only(right: link == links.last ? 0 : _S.sm),
            child: _buildActionButton(
              icon,
              link.name,
              onTap: () async {
                HapticFeedback.lightImpact();
                final uri = Uri.parse(link.url);
                if (await canLaunchUrl(uri)) {
                  await launchUrl(uri);
                }
              },
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildActionButton(
    IconData icon,
    String label, {
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: _C.surface.withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: _C.textSecondary, size: 22),
            const SizedBox(height: 4),
            Text(
              label,
              style: const TextStyle(
                color: _C.textSecondary,
                fontSize: 11,
                fontWeight: FontWeight.w500,
              ),
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Sources Panel
  // ─────────────────────────────────────────────────────────────────────────
  Widget _buildSourcesPanel({required bool isDesktop}) {
    final filtered = _filteredSources;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                const Icon(Icons.stream_rounded, color: _C.accent, size: 20),
                const SizedBox(width: _S.xs),
                const Text(
                  'Watch Sources',
                  style: TextStyle(
                    color: _C.textPrimary,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            if (_sources.isNotEmpty) _buildAddonFilterDropdown(),
          ],
        ),
        const SizedBox(height: _S.sm),

        // Source count
        Text(
          _isLoadingSources
              ? 'Searching sources...'
              : '${filtered.length} source${filtered.length == 1 ? '' : 's'} found',
          style: const TextStyle(color: _C.textTertiary, fontSize: 12),
        ),
        const SizedBox(height: _S.md),

        // Source list
        if (isDesktop)
          Expanded(child: _buildSourcesList(filtered, isDesktop))
        else
          _buildSourcesList(filtered, isDesktop),
      ],
    );
  }

  Widget _buildSourcesList(List<StreamSource> sources, bool isDesktop) {
    if (_isLoadingSources && sources.isEmpty) {
      return _buildShimmerList();
    }

    if (!_isLoadingSources && sources.isEmpty) {
      return _buildEmptyState();
    }

    final list = ListView.separated(
      controller: isDesktop ? _sourcesScrollController : null,
      shrinkWrap: !isDesktop,
      physics: isDesktop
          ? const BouncingScrollPhysics()
          : const NeverScrollableScrollPhysics(),
      itemCount: sources.length + (_isLoadingSources ? 2 : 0),
      separatorBuilder: (_, __) => const SizedBox(height: _S.xs),
      itemBuilder: (context, index) {
        if (index >= sources.length) {
          return _buildShimmerCard();
        }
        return _SourceCard(
          source: sources[index],
          backdropUrl: widget.detail.background ?? widget.detail.poster,
          logoUrl: widget.detail.logo,
          detail: widget.detail,
          episode: widget.selectedEpisode,
          onNextEpisode: _playNextEpisode,
        );
      },
    );

    return list;
  }

  Widget _buildAddonFilterDropdown() {
    final addons = _sources.map((e) => e.addonName).toSet().toList();
    if (addons.isEmpty) return const SizedBox.shrink();
    final currentText = _selectedAddonFilter ?? 'All Sources';

    return Builder(
      builder: (buttonContext) {
        return GestureDetector(
          onTap: () => _showGlassDropdown(buttonContext, addons),
          child: DecoratedBox(
            decoration: const BoxDecoration(
              borderRadius: BorderRadius.all(Radius.circular(18)),
              boxShadow: [
                BoxShadow(
                  color: Color(0x40000000),
                  blurRadius: 10,
                  offset: Offset(0, 4),
                ),
              ],
            ),
            child: PerformanceLiquidLens(
              style: PerformanceGlassStyles.menuButton,
              child: Container(
                height: 36,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: const Color(0x26FFFFFF)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      currentText,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(width: 4),
                    const Icon(
                      Icons.arrow_drop_down,
                      color: Colors.white70,
                      size: 20,
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  void _showGlassDropdown(BuildContext buttonContext, List<String> addons) {
    final RenderBox button = buttonContext.findRenderObject() as RenderBox;
    final RenderBox overlay =
        Navigator.of(context).overlay!.context.findRenderObject() as RenderBox;
    final Offset buttonOffset = button.localToGlobal(
      Offset.zero,
      ancestor: overlay,
    );

    // We want the dropdown to align with the right edge of the button, and appear just below it.
    final topOffset = buttonOffset.dy + button.size.height + 8;
    final rightOffset =
        overlay.size.width - buttonOffset.dx - button.size.width;

    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Dismiss',
      barrierColor: Colors
          .transparent, // True dropdowns do not dim the background heavily
      transitionDuration: const Duration(milliseconds: 250),
      pageBuilder: (context, animation, secondaryAnimation) {
        return Stack(
          children: [
            Positioned(
              top: topOffset,
              right: rightOffset,
              child: Material(
                color: Colors.transparent,
                child: TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0.0, end: 1.0),
                  duration: const Duration(milliseconds: 250),
                  curve: Curves.easeOut,
                  builder: (context, value, child) {
                    return Transform.translate(
                      offset: Offset(
                        0,
                        -10 * (1 - value),
                      ), // Slide down slightly
                      child: Opacity(
                        opacity: value.clamp(0.0, 1.0),
                        child: child,
                      ),
                    );
                  },
                  child: DecoratedBox(
                    decoration: const BoxDecoration(
                      borderRadius: BorderRadius.all(Radius.circular(16)),
                      boxShadow: [
                        BoxShadow(
                          color: Color(0x99000000),
                          blurRadius: 18,
                          offset: Offset(0, 8),
                        ),
                      ],
                    ),
                    child: PerformanceLiquidLens(
                      style: PerformanceGlassStyles.menu,
                      child: Container(
                        width: 200,
                        constraints: const BoxConstraints(maxHeight: 300),
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: const Color(0x26FFFFFF)),
                        ),
                        child: SingleChildScrollView(
                          physics: const BouncingScrollPhysics(),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _buildDropdownItem('All Sources', null),
                              const SizedBox(height: 4),
                              Container(
                                height: 1,
                                color: Colors.white.withValues(alpha: 0.1),
                              ),
                              const SizedBox(height: 4),
                              ...addons.map((a) => _buildDropdownItem(a, a)),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildDropdownItem(String title, String? value) {
    final isSelected = _selectedAddonFilter == value;
    return InkWell(
      onTap: () {
        setState(() {
          _selectedAddonFilter = value;
        });
        Navigator.pop(context);
      },
      borderRadius: BorderRadius.circular(16),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          color: isSelected
              ? Colors.white.withValues(alpha: 0.1)
              : Colors.transparent,
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  color: isSelected ? Colors.white : Colors.white70,
                  fontSize: 15,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                ),
              ),
            ),
            if (isSelected)
              const Icon(Icons.check_circle, color: Colors.white, size: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return const _EmptySourcesStateWidget();
  }

  Widget _buildShimmerList() {
    return Column(
      children: List.generate(
        4,
        (_) => Padding(
          padding: const EdgeInsets.only(bottom: _S.xs),
          child: _buildShimmerCard(),
        ),
      ),
    );
  }

  Widget _buildShimmerCard() {
    return const _ShimmerCard();
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Back Button
  // ─────────────────────────────────────────────────────────────────────────
  Widget _buildBackButton() {
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: _C.bg.withValues(alpha: 0.7),
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: IconButton(
        icon: const Icon(
          Icons.arrow_back_ios_new_rounded,
          size: 18,
          color: _C.textPrimary,
        ),
        onPressed: () => Navigator.pop(context),
        padding: EdgeInsets.zero,
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Source Card
// ─────────────────────────────────────────────────────────────────────────────
class _SourceCard extends StatefulWidget {
  final StreamSource source;
  final String? backdropUrl;
  final String? logoUrl;
  final MovieDetail detail;
  final Video? episode;
  final VoidCallback? onNextEpisode;

  const _SourceCard({
    required this.source,
    this.backdropUrl,
    this.logoUrl,
    required this.detail,
    this.episode,
    this.onNextEpisode,
  });

  @override
  State<_SourceCard> createState() => _SourceCardState();
}

class _SourceCardState extends State<_SourceCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final s = widget.source;
    final badges = <Widget>[];

    // Quality badge
    if (s.quality != null) {
      Color badgeColor;
      switch (s.quality) {
        case '4K':
          badgeColor = const Color(0xFFFF6B6B);
          break;
        case '1080p':
          badgeColor = const Color(0xFF51CF66);
          break;
        case '720p':
          badgeColor = const Color(0xFF339AF0);
          break;
        default:
          badgeColor = _C.textTertiary;
      }
      badges.add(_badge(s.quality!, badgeColor));
    }

    if (s.isHDR) badges.add(_badge('HDR', const Color(0xFFFFD43B)));
    if (s.codec != null) badges.add(_badge(s.codec!, _C.textTertiary));
    if (s.fileSize != null) badges.add(_badge(s.fileSize!, _C.textTertiary));

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () {
              HapticFeedback.lightImpact();

              if (s.externalUrl != null && s.externalUrl!.isNotEmpty) {
                if (s.externalUrl!.startsWith('stremio://')) {
                  // Example: stremio:///detail/movie/tt28479262
                  final uriStr = s.externalUrl!.replaceFirst(
                    'stremio:///',
                    'stremio://',
                  );
                  final uri = Uri.parse(uriStr);
                  final segments = uri.pathSegments;
                  if (uri.host == 'detail' && segments.length >= 2) {
                    final type = segments[0];
                    final id = segments[1];
                    final movie = Movie(
                      id: id,
                      type: type,
                      name: s.name ?? 'Unknown',
                      addonBaseUrl: 'https://v3-cinemeta.strem.io',
                    );
                    Navigator.push(
                      context,
                      CinematicSlideRoute(page: DetailsPage(movie: movie)),
                    );
                    return;
                  }
                  return;
                } else {
                  // Fallback for http URLs or other schemes
                  launchUrl(
                    Uri.parse(s.externalUrl!),
                    mode: LaunchMode.externalApplication,
                  );
                  return;
                }
              }

              pushFullscreen(
                MaterialPageRoute(
                  builder: (_) => PlayerScreen(
                    source: s,
                    title: s.displayTitle,
                    backdropUrl: widget.backdropUrl,
                    logoUrl: widget.logoUrl,
                    detail: widget.detail,
                    episode: widget.episode,
                    onNextEpisode: widget.onNextEpisode,
                  ),
                ),
              );
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: _hovered
                    ? _C.surfaceLight.withValues(alpha: 0.9)
                    : _C.surface.withValues(alpha: 0.7),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: _hovered
                      ? _C.accent.withValues(alpha: 0.3)
                      : Colors.white.withValues(alpha: 0.06),
                ),
                boxShadow: _hovered
                    ? [
                        BoxShadow(
                          color: _C.accent.withValues(alpha: 0.08),
                          blurRadius: 16,
                        ),
                      ]
                    : [],
              ),
              child: Row(
                children: [
                  // Addon icon
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: _C.accent.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.extension_rounded,
                      color: _C.accent,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: _S.sm),
                  // Info
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          s.name != null && s.name!.isNotEmpty
                              ? s.name!
                              : s.addonName,
                          style: const TextStyle(
                            color: _C.textPrimary,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (s.title != null && s.title!.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            s.title!,
                            style: const TextStyle(
                              color: _C.textTertiary,
                              fontSize: 12,
                              height: 1.4,
                            ),
                          ),
                        ],
                        if (s.description != null &&
                            s.description!.isNotEmpty) ...[
                          const SizedBox(height: 6),
                          Text(
                            s.description!,
                            maxLines: 4,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: _C.textSecondary,
                              fontSize: 12,
                              height: 1.3,
                            ),
                          ),
                        ],
                        if (badges.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Wrap(spacing: 4, runSpacing: 4, children: badges),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: _S.xs),
                  // Play chevron
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: _hovered
                          ? _C.accent.withValues(alpha: 0.2)
                          : Colors.white.withValues(alpha: 0.06),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.play_arrow_rounded,
                      color: _hovered ? _C.accent : _C.textTertiary,
                      size: 20,
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

  Widget _badge(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.3,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Shimmer Card
// ─────────────────────────────────────────────────────────────────────────────
class _ShimmerCard extends StatefulWidget {
  const _ShimmerCard();

  @override
  State<_ShimmerCard> createState() => _ShimmerCardState();
}

class _ShimmerCardState extends State<_ShimmerCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: _C.surface.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white.withValues(alpha: 0.04)),
          ),
          child: Row(
            children: [
              _shimmerBox(40, 40, 10),
              const SizedBox(width: _S.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _shimmerBox(double.infinity, 12, 4),
                    const SizedBox(height: 8),
                    _shimmerBox(180, 10, 4),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        _shimmerBox(40, 16, 4),
                        const SizedBox(width: 4),
                        _shimmerBox(50, 16, 4),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: _S.xs),
              _shimmerBox(36, 36, 18),
            ],
          ),
        );
      },
    );
  }

  Widget _shimmerBox(double width, double height, double radius) {
    final shimmerValue = _controller.value;
    final gradientStart = shimmerValue - 0.3;
    final gradientEnd = shimmerValue + 0.3;

    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        gradient: LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [
            _C.surfaceLight.withValues(alpha: 0.5),
            _C.surfaceLight.withValues(alpha: 0.8),
            _C.surfaceLight.withValues(alpha: 0.5),
          ],
          stops: [
            (gradientStart).clamp(0.0, 1.0),
            (shimmerValue).clamp(0.0, 1.0),
            (gradientEnd).clamp(0.0, 1.0),
          ],
        ),
      ),
    );
  }
}

class _EmptySourcesStateWidget extends StatefulWidget {
  const _EmptySourcesStateWidget();

  @override
  State<_EmptySourcesStateWidget> createState() =>
      _EmptySourcesStateWidgetState();
}

class _EmptySourcesStateWidgetState extends State<_EmptySourcesStateWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _animController;
  late Animation<double> _scaleAnim;
  late Animation<double> _fadeAnim;
  bool _isHovering = false;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );
    _fadeAnim = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _animController,
        curve: const Interval(0.0, 0.4, curve: Curves.easeOut),
      ),
    );
    _scaleAnim = Tween<double>(begin: 0.95, end: 1.0).animate(
      CurvedAnimation(
        parent: _animController,
        curve: const Interval(0.0, 0.4, curve: Curves.easeOutBack),
      ),
    );
    // Run the entrance once. A perpetual pulse kept this whole state ticking.
    _animController.forward();
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Static card content — identical on every platform.
    final cardContent = Container(
      padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 24),
      decoration: BoxDecoration(
        color: const Color(0xF0141419),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0xFF7C5CFC).withValues(alpha: 0.1),
              border: Border.all(
                color: const Color(0xFF7C5CFC).withValues(alpha: 0.3),
              ),
            ),
            child: const Icon(
              Icons.radar_rounded,
              color: Color(0xFF7C5CFC),
              size: 40,
            ),
          ),
          const SizedBox(height: 24),
          const Text(
            'No sources found',
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 12),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 280),
            child: const Text(
              'No streams found. Install more addons from Settings or try another title.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Color(0xFF9B9BA5),
                fontSize: 14,
                height: 1.5,
              ),
            ),
          ),
          const SizedBox(height: 32),
          MouseRegion(
            onEnter: (_) => setState(() => _isHovering = true),
            onExit: (_) => setState(() => _isHovering = false),
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const SettingsPage()),
                );
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(32),
                  gradient: const LinearGradient(
                    colors: [Color(0xFF7C5CFC), Color(0xFF5CFCB6)],
                  ),
                  boxShadow: _isHovering
                      ? [
                          BoxShadow(
                            color: const Color(
                              0xFF7C5CFC,
                            ).withValues(alpha: 0.4),
                            blurRadius: 16,
                            offset: const Offset(0, 4),
                          ),
                        ]
                      : [],
                ),
                child: AnimatedScale(
                  scale: _isHovering ? 1.05 : 1.0,
                  duration: const Duration(milliseconds: 200),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.extension_rounded,
                        color: Colors.white,
                        size: 18,
                      ),
                      SizedBox(width: 8),
                      Text(
                        'Install Addons',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );

    // The glass card — blur is static, not animated
    final glassCard = Container(
      width: double.infinity,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.3),
            blurRadius: 30,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: cardContent,
    );

    // Only the initial fade/scale is animated (runs once, then stops)
    return AnimatedBuilder(
      animation: _fadeAnim,
      builder: (context, child) {
        return Opacity(
          opacity: _fadeAnim.value.clamp(0.0, 1.0),
          child: Transform.scale(scale: _scaleAnim.value, child: child),
        );
      },
      child: glassCard,
    );
  }
}
