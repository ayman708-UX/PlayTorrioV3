import 'dart:async';
import 'dart:ui';

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
import '../../services/addon/addon_manager.dart';
import '../../services/stream/stream_service.dart';
import '../../services/theme/glass_settings.dart';
import '../../services/scraper/builtin_providers_settings_service.dart';
import '../../widgets/common/performance_liquid_lens.dart';
import '../settings/settings_page.dart';
import '../details/details_page.dart';
import '../../utils/navigation/route_transitions.dart';

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
  final Duration? initialPosition;

  final bool isCollection;

  const WatchScreen({
    super.key,
    required this.detail,
    this.selectedEpisode,
    required this.type,
    this.initialPosition,
    this.isCollection = false,
  });

  @override
  State<WatchScreen> createState() => _WatchScreenState();
}

class _WatchScreenState extends State<WatchScreen>
    with SingleTickerProviderStateMixin {
  bool get _isCollection =>
      widget.isCollection ||
      widget.type == 'collections' ||
      widget.type == 'collection' ||
      widget.detail.isCollection ||
      (widget.selectedEpisode != null &&
          widget.selectedEpisode!.id.startsWith('tt') &&
          (widget.detail.type == 'collections' ||
              widget.detail.type == 'collection' ||
              widget.detail.isCollection));

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

  // Addon priority caching
  Map<String, int>? _cachedAddonOrder;
  Map<String, int> get _addonOrder {
    if (_cachedAddonOrder != null) return _cachedAddonOrder!;
    final map = <String, int>{};
    final allAddons = AddonManager.instance.addons;
    for (int i = 0; i < allAddons.length; i++) {
      final a = allAddons[i];
      map[a.manifest.name.toLowerCase()] = i;
      map[a.manifest.id.toLowerCase()] = i;
      if (a.manifest.id == 'builtin.playtorriohttp' || a.baseUrl == 'builtin:playtorriohttp') {
        map['playtorriohttp'] = i;
      }
      if (a.manifest.id == 'builtin.playtorrio' || a.baseUrl == 'builtin:playtorrio') {
        map['playtorrio'] = i;
      }
    }
    return _cachedAddonOrder = map;
  }

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

    // 1. Immediately inject any embedded streams from the video (e.g. Torbox/Debrid direct streams)
    if (widget.selectedEpisode != null && widget.selectedEpisode!.streams.isNotEmpty) {
      _pendingSources.addAll(widget.selectedEpisode!.streams);
      _flushPendingSources();
    }

    final isColl = _isCollection;
    final effectiveType = isColl ? 'movie' : widget.type;
    final effectiveTitle = (isColl && widget.selectedEpisode != null)
        ? widget.selectedEpisode!.title
        : widget.detail.name;
    final epReleased = widget.selectedEpisode?.released;
    final effectiveYear = (isColl && epReleased != null && epReleased.length >= 4)
        ? int.tryParse(epReleased.substring(0, 4))
        : int.tryParse(widget.detail.year ?? '');
    final effectiveSeason = isColl ? null : widget.selectedEpisode?.season;
    final effectiveEpisode = isColl ? null : widget.selectedEpisode?.episode;

    try {
      await for (final source in StreamService.fetchStreams(
        type: effectiveType,
        id: streamId,
        title: effectiveTitle,
        year: effectiveYear,
        season: effectiveSeason,
        episode: effectiveEpisode,
      )) {
        if (!mounted) return;
        _pendingSources.add(source);
        if (_sources.isEmpty) {
          _flushPendingSources();
        } else {
          _sourceBatchTimer ??= Timer(
            const Duration(milliseconds: 50),
            _flushPendingSources,
          );
        }
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
    });
  }

  String? _selectedAddonFilter;
  String? _selectedSizeFilter;
  String _selectedTypeFilter = 'all'; // 'all', 'debrid', 'torrent', 'direct'
  String _selectedSeederFilter = 'all'; // 'all', 'most', '50+', '20+', '5+', '1+'
  String _selectedAudioFilter = 'all'; // 'all', 'multi', 'english', 'hindi', 'german', 'french', 'spanish', 'spanish_castilian', 'spanish_latino', 'russian', 'japanese', 'italian'

  List<StreamSource> get _filteredSources {
    var list = List<StreamSource>.from(_sources);
    if (_selectedAddonFilter != null) {
      list = list.where((s) => s.addonName == _selectedAddonFilter).toList();
    }
    if (_selectedTypeFilter == 'debrid') {
      list = list.where((s) => s.isDebrid).toList();
    } else if (_selectedTypeFilter == 'torrent') {
      list = list.where((s) => s.isTorrent).toList();
    } else if (_selectedTypeFilter == 'direct') {
      list = list.where((s) => s.isHttpDirect).toList();
    }
    if (_selectedSizeFilter != null) {
      switch (_selectedSizeFilter) {
        case '<1gb':
          list = list.where((s) {
            final sz = s.sizeBytes;
            return sz != null && sz < 1024 * 1024 * 1024;
          }).toList();
          break;
        case '1-5gb':
          list = list.where((s) {
            final sz = s.sizeBytes;
            return sz != null && sz >= 1024 * 1024 * 1024 && sz <= 5.0 * 1024 * 1024 * 1024;
          }).toList();
          break;
        case '5-15gb':
          list = list.where((s) {
            final sz = s.sizeBytes;
            return sz != null && sz > 5.0 * 1024 * 1024 * 1024 && sz <= 15.0 * 1024 * 1024 * 1024;
          }).toList();
          break;
        case '15-30gb':
          list = list.where((s) {
            final sz = s.sizeBytes;
            return sz != null && sz > 15.0 * 1024 * 1024 * 1024 && sz <= 30.0 * 1024 * 1024 * 1024;
          }).toList();
          break;
        case '>30gb':
          list = list.where((s) {
            final sz = s.sizeBytes;
            return sz != null && sz > 30.0 * 1024 * 1024 * 1024;
          }).toList();
          break;
      }
    }

    if (_selectedSeederFilter == '50+') {
      list = list.where((s) => (s.seeders ?? 0) >= 50).toList();
    } else if (_selectedSeederFilter == '20+') {
      list = list.where((s) => (s.seeders ?? 0) >= 20).toList();
    } else if (_selectedSeederFilter == '5+') {
      list = list.where((s) => (s.seeders ?? 0) >= 5).toList();
    } else if (_selectedSeederFilter == '1+') {
      list = list.where((s) => (s.seeders ?? 0) >= 1).toList();
    }

    // Filter by audio language / dub
    if (_selectedAudioFilter != 'all') {
      list = list
          .where((s) => s.hasAudioLanguage(_selectedAudioFilter,
              mediaTitle: widget.detail.name))
          .toList();
    }

    // Filter by active status of built-in providers
    if (!AddonManager.instance.isPlayTorrioActive) {
      list = list.where((s) => !s.isTorrent || s.isDebrid).toList();
    }
    if (!AddonManager.instance.isPlayTorrioHttpActive) {
      list = list.where((s) => s.addonName.toLowerCase() != 'playtorriohttp').toList();
    }

    // Cached dynamic addon priority lookup from user's installed addons order
    final addonOrder = _addonOrder;
    final isCustomBuiltin = BuiltinProvidersSettingsService.instance.isCustom;

    list.sort((a, b) {
      final isHttpA = a.addonName.toLowerCase() == 'playtorriohttp';
      final isHttpB = b.addonName.toLowerCase() == 'playtorriohttp';

      // When custom Built-in providers mode is active, provider rank strictly dictates order
      if (isCustomBuiltin && isHttpA && isHttpB) {
        final pidA = a.providerId ?? BuiltinProvidersSettingsService.detectProviderId(a);
        final pidB = b.providerId ?? BuiltinProvidersSettingsService.detectProviderId(b);
        final rankA = BuiltinProvidersSettingsService.instance.getProviderRank(pidA);
        final rankB = BuiltinProvidersSettingsService.instance.getProviderRank(pidB);
        if (rankA != rankB) {
          return rankA.compareTo(rankB);
        }
        // Within the same provider, sort by secondary filter / quality:
        if (_selectedSeederFilter == 'most') {
          return (b.seeders ?? 0).compareTo(a.seeders ?? 0);
        } else if (_selectedSizeFilter == 'largest') {
          return (b.sizeBytes ?? 0).compareTo(a.sizeBytes ?? 0);
        } else if (_selectedSizeFilter == 'smallest') {
          return (a.sizeBytes ?? double.infinity).compareTo(b.sizeBytes ?? double.infinity);
        } else {
          final qComp = b.qualityRank.compareTo(a.qualityRank);
          if (qComp != 0) return qComp;
          return (b.seeders ?? 0).compareTo(a.seeders ?? 0);
        }
      }

      // Addon-level order comparison
      final orderA = addonOrder[a.addonName.toLowerCase()] ?? 999;
      final orderB = addonOrder[b.addonName.toLowerCase()] ?? 999;
      if (orderA != orderB) {
        return orderA.compareTo(orderB);
      }

      // Standard sort across streams of the same addon
      if (_selectedSeederFilter == 'most') {
        return (b.seeders ?? 0).compareTo(a.seeders ?? 0);
      } else if (_selectedSizeFilter == 'largest') {
        return (b.sizeBytes ?? 0).compareTo(a.sizeBytes ?? 0);
      } else if (_selectedSizeFilter == 'smallest') {
        return (a.sizeBytes ?? double.infinity).compareTo(b.sizeBytes ?? double.infinity);
      } else {
        final qComp = b.qualityRank.compareTo(a.qualityRank);
        if (qComp != 0) return qComp;
        return (b.seeders ?? 0).compareTo(a.seeders ?? 0);
      }
    });
    return list;
  }

  String _getSeederFilterLabel(String filter) {
    switch (filter) {
      case 'most':
        return 'Most Seeds';
      case '50+':
        return '50+ Seeds';
      case '20+':
        return '20+ Seeds';
      case '5+':
        return '5+ Seeds';
      case '1+':
        return 'Active Seeds';
      default:
        return 'All Seeds';
    }
  }

  String _getSizeFilterLabel(String? filter) {
    switch (filter) {
      case '<1gb':
        return '< 1 GB';
      case '1-5gb':
        return '1–5 GB';
      case '5-15gb':
        return '5–15 GB';
      case '15-30gb':
        return '15–30 GB';
      case '>30gb':
        return '> 30 GB';
      case 'largest':
        return 'Largest';
      case 'smallest':
        return 'Smallest';
      default:
        return 'All Sizes';
    }
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
    final isWide = screenSize.width >= 1500;
    final leftFlex = isWide ? 5 : 5;
    final rightFlex = isWide ? 5 : 6;

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
                flex: leftFlex,
                child: SingleChildScrollView(
                  controller: _mainScrollController,
                  physics: const BouncingScrollPhysics(),
                  child: _buildInfoRegion(isDesktop: true),
                ),
              ),
              const SizedBox(width: 32),
              // Right: sources panel (extends to right edge)
              Flexible(
                flex: rightFlex,
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
                        Text(
                          _isLoadingSources
                              ? (filtered.isEmpty
                                  ? 'Searching sources...'
                                  : '${filtered.length} found · Searching...')
                              : '${filtered.length} source${filtered.length == 1 ? '' : 's'} found',
                          style: const TextStyle(
                            color: _C.textTertiary,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                    if (_sources.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          _buildTypeChip('all', 'All (${_sources.length})', Icons.apps_rounded, null),
                          _buildTypeChip(
                            'debrid',
                            '⚡ Debrid (${_sources.where((s) => s.isDebrid).length})',
                            Icons.bolt_rounded,
                            const Color(0xFF00E5FF),
                          ),
                          _buildTypeChip(
                            'torrent',
                            '🧲 Torrents (${_sources.where((s) => s.isTorrent).length})',
                            Icons.share_rounded,
                            const Color(0xFF7C5CFF),
                          ),
                          _buildTypeChip(
                            'direct',
                            '🌐 Direct (${_sources.where((s) => s.isHttpDirect).length})',
                            Icons.link_rounded,
                            const Color(0xFF10B981),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          _buildSeederFilterDropdown(),
                          _buildSizeFilterDropdown(),
                          _buildAddonFilterDropdown(),
                          _buildAudioFilterDropdown(),
                        ],
                      ),
                    ],
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
                        initialPosition: widget.initialPosition,
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
              _isCollection
                  ? 'PART ${ep.episode ?? 1}'
                  : 'S${ep.season ?? '?' }E${ep.episode ?? '?' }',
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
                style: const TextStyle(
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

        if (nameLower.contains('imdb') || catLower.contains('imdb')) {
          icon = Icons.movie_creation_outlined;
        } else if (nameLower.contains('trailer') || catLower.contains('trailer')) {
          icon = Icons.play_circle_outline;
        } else if (nameLower.contains('wiki') || catLower.contains('wiki')) {
          icon = Icons.article_outlined;
        } else if (nameLower.contains('search') || catLower.contains('search')) {
          icon = Icons.search_rounded;
        }

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
            const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.stream_rounded, color: _C.accent, size: 20),
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
            Text(
              _isLoadingSources
                  ? (filtered.isEmpty
                      ? 'Searching sources...'
                      : '${filtered.length} found · Searching...')
                  : '${filtered.length} source${filtered.length == 1 ? '' : 's'} found',
              style: const TextStyle(color: _C.textTertiary, fontSize: 12),
            ),
          ],
        ),
        const SizedBox(height: 10),

        // Stream Type Filter Bar (All / Debrid / Torrents / Direct HTTP)
        if (_sources.isNotEmpty) ...[
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              _buildTypeChip('all', 'All (${_sources.length})', Icons.apps_rounded, null),
              _buildTypeChip(
                'debrid',
                '⚡ Debrid (${_sources.where((s) => s.isDebrid).length})',
                Icons.bolt_rounded,
                const Color(0xFF00E5FF),
              ),
              _buildTypeChip(
                'torrent',
                '🧲 Torrents (${_sources.where((s) => s.isTorrent).length})',
                Icons.share_rounded,
                const Color(0xFF7C5CFF),
              ),
              _buildTypeChip(
                'direct',
                '🌐 Direct (${_sources.where((s) => s.isHttpDirect).length})',
                Icons.link_rounded,
                const Color(0xFF10B981),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _buildSeederFilterDropdown(),
              _buildSizeFilterDropdown(),
              _buildAddonFilterDropdown(),
              _buildAudioFilterDropdown(),
            ],
          ),
          const SizedBox(height: 12),
        ],

        // Source list
        if (isDesktop)
          Flexible(
            flex: 1,
            child: SingleChildScrollView(
              controller: _sourcesScrollController,
              physics: const BouncingScrollPhysics(),
              child: _buildSourcesList(filtered, isDesktop),
            ),
          )
        else
          _buildSourcesList(filtered, isDesktop),
      ],
    );
  }

  Widget _buildTypeChip(String typeKey, String label, IconData icon, Color? color) {
    final isSelected = _selectedTypeFilter == typeKey;
    final activeColor = color ?? _C.accent;

    return ChoiceChip(
      label: Text(label),
      selected: isSelected,
      selectedColor: activeColor.withValues(alpha: 0.25),
      backgroundColor: const Color(0xFF13151C),
      labelStyle: TextStyle(
        color: isSelected ? Colors.white : Colors.white70,
        fontWeight: isSelected ? FontWeight.w800 : FontWeight.w500,
        fontSize: 11.5,
      ),
      side: BorderSide(
        color: isSelected ? activeColor : Colors.white.withValues(alpha: 0.1),
        width: isSelected ? 1.5 : 1.0,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      onSelected: (selected) {
        if (selected) {
          setState(() {
            _selectedTypeFilter = typeKey;
          });
        }
      },
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
          initialPosition: widget.initialPosition,
        );
      },
    );

    return list;
  }

  Widget _buildSeederFilterDropdown() {
    final currentText = _getSeederFilterLabel(_selectedSeederFilter);

    return Builder(
      builder: (buttonContext) {
        return GestureDetector(
          onTap: () => _isDesktop()
              ? _showSeederGlassDropdown(buttonContext)
              : _showSeederBottomSheet(),
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
                  border: Border.all(
                    color: _selectedSeederFilter != 'all'
                        ? const Color(0xFF10B981).withValues(alpha: 0.6)
                        : const Color(0x26FFFFFF),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.people_alt_rounded,
                      color: _selectedSeederFilter != 'all'
                          ? const Color(0xFF10B981)
                          : Colors.white70,
                      size: 16,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      currentText,
                      style: TextStyle(
                        color: _selectedSeederFilter != 'all'
                            ? const Color(0xFF10B981)
                            : Colors.white,
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

  void _showSeederGlassDropdown(BuildContext buttonContext) {
    final RenderBox button = buttonContext.findRenderObject() as RenderBox;
    final RenderBox overlay =
        Navigator.of(context).overlay!.context.findRenderObject() as RenderBox;
    final Offset buttonOffset = button.localToGlobal(
      Offset.zero,
      ancestor: overlay,
    );
    const double dialogWidth = 230.0;
    final double spaceBelow = overlay.size.height - (buttonOffset.dy + button.size.height + 8) - 16;
    final double spaceAbove = buttonOffset.dy - 16;
    final bool openAbove = spaceBelow < 280 && spaceAbove > spaceBelow;

    final double maxMenuHeight = (openAbove ? spaceAbove : spaceBelow).clamp(160.0, 420.0);
    final double? topOffset = openAbove ? null : (buttonOffset.dy + button.size.height + 8);
    final double? bottomOffset = openAbove ? (overlay.size.height - buttonOffset.dy + 8) : null;

    final double rawLeft = buttonOffset.dx;
    final double maxLeft = overlay.size.width - dialogWidth - 12.0;
    final double leftOffset = rawLeft.clamp(12.0, maxLeft > 12.0 ? maxLeft : 12.0);

    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Dismiss',
      barrierColor: Colors.transparent,
      transitionDuration: const Duration(milliseconds: 250),
      pageBuilder: (context, animation, secondaryAnimation) {
        return Stack(
          children: [
            Positioned(
              top: topOffset,
              bottom: bottomOffset,
              left: leftOffset,
              child: Material(
                color: Colors.transparent,
                child: TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0.0, end: 1.0),
                  duration: const Duration(milliseconds: 250),
                  curve: Curves.easeOut,
                  builder: (context, value, child) {
                    return Transform.translate(
                      offset: Offset(0, (openAbove ? 10 : -10) * (1 - value)),
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
                        width: dialogWidth,
                        constraints: BoxConstraints(maxHeight: maxMenuHeight),
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
                              _buildSeederDropdownItem('All Seeds', 'all'),
                              const SizedBox(height: 4),
                              Container(
                                height: 1,
                                color: Colors.white.withValues(alpha: 0.1),
                              ),
                              const SizedBox(height: 4),
                              _buildSeederDropdownItem('Most Seeds (High to Low)', 'most'),
                              _buildSeederDropdownItem('50+ Seeds', '50+'),
                              _buildSeederDropdownItem('20+ Seeds', '20+'),
                              _buildSeederDropdownItem('5+ Seeds', '5+'),
                              _buildSeederDropdownItem('Active Seeds (>0)', '1+'),
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

  Widget _buildSeederDropdownItem(String title, String value) {
    final isSelected = _selectedSeederFilter == value;
    return InkWell(
      onTap: () {
        setState(() {
          _selectedSeederFilter = value;
        });
        Navigator.pop(context);
      },
      borderRadius: BorderRadius.circular(16),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 14),
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
                  fontSize: 14,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                ),
              ),
            ),
            if (isSelected)
              const Icon(Icons.check_circle, color: Color(0xFF10B981), size: 18),
          ],
        ),
      ),
    );
  }

  Widget _buildSizeFilterDropdown() {
    final currentText = _getSizeFilterLabel(_selectedSizeFilter);

    return Builder(
      builder: (buttonContext) {
        return GestureDetector(
          onTap: () => _isDesktop()
              ? _showSizeGlassDropdown(buttonContext)
              : _showSizeBottomSheet(),
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
                    const Icon(
                      Icons.data_usage_rounded,
                      color: Colors.white70,
                      size: 16,
                    ),
                    const SizedBox(width: 6),
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

  void _showSizeGlassDropdown(BuildContext buttonContext) {
    final RenderBox button = buttonContext.findRenderObject() as RenderBox;
    final RenderBox overlay =
        Navigator.of(context).overlay!.context.findRenderObject() as RenderBox;
    final Offset buttonOffset = button.localToGlobal(
      Offset.zero,
      ancestor: overlay,
    );
    const double dialogWidth = 230.0;
    final double spaceBelow = overlay.size.height - (buttonOffset.dy + button.size.height + 8) - 16;
    final double spaceAbove = buttonOffset.dy - 16;
    final bool openAbove = spaceBelow < 280 && spaceAbove > spaceBelow;

    final double maxMenuHeight = (openAbove ? spaceAbove : spaceBelow).clamp(160.0, 420.0);
    final double? topOffset = openAbove ? null : (buttonOffset.dy + button.size.height + 8);
    final double? bottomOffset = openAbove ? (overlay.size.height - buttonOffset.dy + 8) : null;

    final double rawLeft = buttonOffset.dx;
    final double maxLeft = overlay.size.width - dialogWidth - 12.0;
    final double leftOffset = rawLeft.clamp(12.0, maxLeft > 12.0 ? maxLeft : 12.0);

    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Dismiss',
      barrierColor: Colors.transparent,
      transitionDuration: const Duration(milliseconds: 250),
      pageBuilder: (context, animation, secondaryAnimation) {
        return Stack(
          children: [
            Positioned(
              top: topOffset,
              bottom: bottomOffset,
              left: leftOffset,
              child: Material(
                color: Colors.transparent,
                child: TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0.0, end: 1.0),
                  duration: const Duration(milliseconds: 250),
                  curve: Curves.easeOut,
                  builder: (context, value, child) {
                    return Transform.translate(
                      offset: Offset(0, (openAbove ? 10 : -10) * (1 - value)),
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
                        width: dialogWidth,
                        constraints: BoxConstraints(maxHeight: maxMenuHeight),
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
                              _buildSizeDropdownItem('All Sizes', null),
                              const SizedBox(height: 4),
                              Container(
                                height: 1,
                                color: Colors.white.withValues(alpha: 0.1),
                              ),
                              const SizedBox(height: 4),
                              _buildSizeDropdownItem('< 1 GB', '<1gb'),
                              _buildSizeDropdownItem('1 GB – 5 GB', '1-5gb'),
                              _buildSizeDropdownItem('5 GB – 15 GB', '5-15gb'),
                              _buildSizeDropdownItem('15 GB – 30 GB', '15-30gb'),
                              _buildSizeDropdownItem('> 30 GB', '>30gb'),
                              const SizedBox(height: 4),
                              Container(
                                height: 1,
                                color: Colors.white.withValues(alpha: 0.1),
                              ),
                              const SizedBox(height: 4),
                              _buildSizeDropdownItem('Largest First', 'largest'),
                              _buildSizeDropdownItem('Smallest First', 'smallest'),
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

  Widget _buildSizeDropdownItem(String title, String? value) {
    final isSelected = _selectedSizeFilter == value;
    return InkWell(
      onTap: () {
        setState(() {
          _selectedSizeFilter = value;
        });
        Navigator.pop(context);
      },
      borderRadius: BorderRadius.circular(16),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 14),
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
                  fontSize: 14,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                ),
              ),
            ),
            if (isSelected)
              const Icon(Icons.check_circle, color: Colors.white, size: 18),
          ],
        ),
      ),
    );
  }

  Widget _buildAddonFilterDropdown() {
    final addons = _sources.map((e) => e.addonName).toSet().toList();
    if (addons.isEmpty) return const SizedBox.shrink();
    final currentText = _selectedAddonFilter ?? 'All Sources';

    return Builder(
      builder: (buttonContext) {
        return GestureDetector(
          onTap: () => _isDesktop()
              ? _showGlassDropdown(buttonContext, addons)
              : _showAddonBottomSheet(addons),
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

    const double dialogWidth = 230.0;
    final double spaceBelow = overlay.size.height - (buttonOffset.dy + button.size.height + 8) - 16;
    final double spaceAbove = buttonOffset.dy - 16;
    final bool openAbove = spaceBelow < 280 && spaceAbove > spaceBelow;

    final double maxMenuHeight = (openAbove ? spaceAbove : spaceBelow).clamp(160.0, 420.0);
    final double? topOffset = openAbove ? null : (buttonOffset.dy + button.size.height + 8);
    final double? bottomOffset = openAbove ? (overlay.size.height - buttonOffset.dy + 8) : null;

    final double rawLeft = buttonOffset.dx;
    final double maxLeft = overlay.size.width - dialogWidth - 12.0;
    final double leftOffset = rawLeft.clamp(12.0, maxLeft > 12.0 ? maxLeft : 12.0);

    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Dismiss',
      barrierColor: Colors.transparent,
      transitionDuration: const Duration(milliseconds: 250),
      pageBuilder: (context, animation, secondaryAnimation) {
        return Stack(
          children: [
            Positioned(
              top: topOffset,
              bottom: bottomOffset,
              left: leftOffset,
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
                        (openAbove ? 10 : -10) * (1 - value),
                      ),
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
                        width: dialogWidth,
                        constraints: BoxConstraints(maxHeight: maxMenuHeight),
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

  String _getAudioFilterLabel(String key) {
    switch (key) {
      case 'multi':
        return '🌐 Multi-Audio';
      case 'english':
        return '🇺🇸 English / Orig';
      case 'hindi':
        return '🇮🇳 Hindi / Indian';
      case 'german':
        return '🇩🇪 German';
      case 'french':
        return '🇫🇷 French';
      case 'spanish_castilian':
        return '🇪🇸 Spanish (Castilian)';
      case 'spanish_latino':
        return '🇲🇽 Spanish (Latin)';
      case 'spanish':
        return '🌎 All Spanish';
      case 'russian':
        return '🇷🇺 Russian';
      case 'japanese':
        return '🇯🇵 Japanese';
      case 'italian':
        return '🇮🇹 Italian';
      default:
        return 'All Audio';
    }
  }

  Widget _buildAudioFilterDropdown() {
    final currentText = _getAudioFilterLabel(_selectedAudioFilter);
    final isActive = _selectedAudioFilter != 'all';

    return Builder(
      builder: (buttonContext) {
        return GestureDetector(
          onTap: () => _isDesktop()
              ? _showAudioGlassDropdown(buttonContext)
              : _showAudioBottomSheet(),
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
                  border: Border.all(
                    color: isActive
                        ? const Color(0xFFB197FC).withValues(alpha: 0.6)
                        : const Color(0x26FFFFFF),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.audiotrack_rounded,
                      color: isActive ? const Color(0xFFB197FC) : Colors.white70,
                      size: 16,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      currentText,
                      style: TextStyle(
                        color: isActive ? const Color(0xFFB197FC) : Colors.white,
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

  void _showAudioGlassDropdown(BuildContext buttonContext) {
    final RenderBox button = buttonContext.findRenderObject() as RenderBox;
    final RenderBox overlay =
        Navigator.of(context).overlay!.context.findRenderObject() as RenderBox;
    final Offset buttonOffset = button.localToGlobal(
      Offset.zero,
      ancestor: overlay,
    );

    const double dialogWidth = 240.0;
    final double spaceBelow = overlay.size.height - (buttonOffset.dy + button.size.height + 8) - 16;
    final double spaceAbove = buttonOffset.dy - 16;
    final bool openAbove = spaceBelow < 280 && spaceAbove > spaceBelow;

    final double maxMenuHeight = (openAbove ? spaceAbove : spaceBelow).clamp(160.0, 420.0);
    final double? topOffset = openAbove ? null : (buttonOffset.dy + button.size.height + 8);
    final double? bottomOffset = openAbove ? (overlay.size.height - buttonOffset.dy + 8) : null;

    final double rawLeft = buttonOffset.dx;
    final double maxLeft = overlay.size.width - dialogWidth - 12.0;
    final double leftOffset = rawLeft.clamp(12.0, maxLeft > 12.0 ? maxLeft : 12.0);

    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Dismiss',
      barrierColor: Colors.transparent,
      transitionDuration: const Duration(milliseconds: 150),
      pageBuilder: (ctx, anim1, anim2) {
        return Stack(
          children: [
            Positioned(
              top: topOffset,
              bottom: bottomOffset,
              left: leftOffset,
              child: Material(
                color: Colors.transparent,
                child: DecoratedBox(
                  decoration: const BoxDecoration(
                    borderRadius: BorderRadius.all(Radius.circular(16)),
                    boxShadow: [
                      BoxShadow(
                        color: Color(0x66000000),
                        blurRadius: 20,
                        offset: Offset(0, 8),
                      ),
                    ],
                  ),
                  child: PerformanceLiquidLens(
                    style: PerformanceGlassStyles.menu,
                    child: Container(
                      width: dialogWidth,
                      constraints: BoxConstraints(maxHeight: maxMenuHeight),
                      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
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
                            _buildAudioDropdownItem('All Audio', 'all'),
                            const SizedBox(height: 4),
                            Container(
                              height: 1,
                              color: Colors.white.withValues(alpha: 0.1),
                            ),
                            const SizedBox(height: 4),
                            _buildAudioDropdownItem('🌐 Multi-Audio', 'multi'),
                            _buildAudioDropdownItem('🇺🇸 English / Orig', 'english'),
                            _buildAudioDropdownItem('🇮🇳 Hindi / Indian', 'hindi'),
                            _buildAudioDropdownItem('🇩🇪 German', 'german'),
                            _buildAudioDropdownItem('🇫🇷 French', 'french'),
                            _buildAudioDropdownItem('🇪🇸 Spanish (Castilian)', 'spanish_castilian'),
                            _buildAudioDropdownItem('🇲🇽 Spanish (Latin)', 'spanish_latino'),
                            _buildAudioDropdownItem('🌎 All Spanish', 'spanish'),
                            _buildAudioDropdownItem('🇷🇺 Russian', 'russian'),
                            _buildAudioDropdownItem('🇯🇵 Japanese', 'japanese'),
                            _buildAudioDropdownItem('🇮🇹 Italian', 'italian'),
                          ],
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

  Widget _buildAudioDropdownItem(String title, String value) {
    final isSelected = _selectedAudioFilter == value;
    return InkWell(
      onTap: () {
        setState(() {
          _selectedAudioFilter = value;
        });
        Navigator.pop(context);
      },
      borderRadius: BorderRadius.circular(16),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 14),
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
                  fontSize: 14,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                ),
              ),
            ),
            if (isSelected)
              const Icon(Icons.check_circle, color: Color(0xFFB197FC), size: 18),
          ],
        ),
      ),
    );
  }

  Widget _buildGlassBottomSheetContainer({
    required BuildContext context,
    required Widget header,
    required Widget content,
  }) {
    return SafeArea(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          color: const Color(0xFF16161E).withValues(alpha: 0.96),
          border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.5),
              blurRadius: 24,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      margin: const EdgeInsets.only(bottom: 12),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.3),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  header,
                  const SizedBox(height: 8),
                  const Divider(color: Colors.white10, height: 1),
                  const SizedBox(height: 8),
                  content,
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBottomSheetItem({
    required String title,
    required bool isSelected,
    required Color activeColor,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: () {
        HapticFeedback.lightImpact();
        onTap();
      },
      borderRadius: BorderRadius.circular(14),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
        margin: const EdgeInsets.only(bottom: 4),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          color: isSelected
              ? activeColor.withValues(alpha: 0.15)
              : Colors.transparent,
          border: isSelected
              ? Border.all(color: activeColor.withValues(alpha: 0.4))
              : Border.all(color: Colors.transparent),
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
              Icon(Icons.check_circle_rounded, color: activeColor, size: 20),
          ],
        ),
      ),
    );
  }

  void _showAudioBottomSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return _buildGlassBottomSheetContainer(
          context: context,
          header: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFFB197FC).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.audiotrack_rounded,
                  color: Color(0xFFB197FC),
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'Audio & Dub Language',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close, color: Colors.white54, size: 20),
                onPressed: () => Navigator.pop(ctx),
              ),
            ],
          ),
          content: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(context).height * 0.55,
            ),
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildBottomSheetItem(
                    title: 'All Audio',
                    isSelected: _selectedAudioFilter == 'all',
                    activeColor: const Color(0xFFB197FC),
                    onTap: () {
                      setState(() => _selectedAudioFilter = 'all');
                      Navigator.pop(ctx);
                    },
                  ),
                  _buildBottomSheetItem(
                    title: '🌐 Multi-Audio',
                    isSelected: _selectedAudioFilter == 'multi',
                    activeColor: const Color(0xFFB197FC),
                    onTap: () {
                      setState(() => _selectedAudioFilter = 'multi');
                      Navigator.pop(ctx);
                    },
                  ),
                  _buildBottomSheetItem(
                    title: '🇺🇸 English / Original',
                    isSelected: _selectedAudioFilter == 'english',
                    activeColor: const Color(0xFFB197FC),
                    onTap: () {
                      setState(() => _selectedAudioFilter = 'english');
                      Navigator.pop(ctx);
                    },
                  ),
                  _buildBottomSheetItem(
                    title: '🇮🇳 Hindi / Indian',
                    isSelected: _selectedAudioFilter == 'hindi',
                    activeColor: const Color(0xFFFF922B),
                    onTap: () {
                      setState(() => _selectedAudioFilter = 'hindi');
                      Navigator.pop(ctx);
                    },
                  ),
                  _buildBottomSheetItem(
                    title: '🇩🇪 German',
                    isSelected: _selectedAudioFilter == 'german',
                    activeColor: const Color(0xFFFFD43B),
                    onTap: () {
                      setState(() => _selectedAudioFilter = 'german');
                      Navigator.pop(ctx);
                    },
                  ),
                  _buildBottomSheetItem(
                    title: '🇫🇷 French',
                    isSelected: _selectedAudioFilter == 'french',
                    activeColor: const Color(0xFF4DABF7),
                    onTap: () {
                      setState(() => _selectedAudioFilter = 'french');
                      Navigator.pop(ctx);
                    },
                  ),
                  _buildBottomSheetItem(
                    title: '🇪🇸 Spanish (Castilian)',
                    isSelected: _selectedAudioFilter == 'spanish_castilian',
                    activeColor: const Color(0xFFFAB005),
                    onTap: () {
                      setState(() => _selectedAudioFilter = 'spanish_castilian');
                      Navigator.pop(ctx);
                    },
                  ),
                  _buildBottomSheetItem(
                    title: '🇲🇽 Spanish (Latin)',
                    isSelected: _selectedAudioFilter == 'spanish_latino',
                    activeColor: const Color(0xFF20C997),
                    onTap: () {
                      setState(() => _selectedAudioFilter = 'spanish_latino');
                      Navigator.pop(ctx);
                    },
                  ),
                  _buildBottomSheetItem(
                    title: '🌎 All Spanish',
                    isSelected: _selectedAudioFilter == 'spanish',
                    activeColor: const Color(0xFFFAB005),
                    onTap: () {
                      setState(() => _selectedAudioFilter = 'spanish');
                      Navigator.pop(ctx);
                    },
                  ),
                  _buildBottomSheetItem(
                    title: '🇷🇺 Russian',
                    isSelected: _selectedAudioFilter == 'russian',
                    activeColor: const Color(0xFF22B8CF),
                    onTap: () {
                      setState(() => _selectedAudioFilter = 'russian');
                      Navigator.pop(ctx);
                    },
                  ),
                  _buildBottomSheetItem(
                    title: '🇯🇵 Japanese',
                    isSelected: _selectedAudioFilter == 'japanese',
                    activeColor: const Color(0xFFFF8787),
                    onTap: () {
                      setState(() => _selectedAudioFilter = 'japanese');
                      Navigator.pop(ctx);
                    },
                  ),
                  _buildBottomSheetItem(
                    title: '🇮🇹 Italian',
                    isSelected: _selectedAudioFilter == 'italian',
                    activeColor: const Color(0xFF69DB7C),
                    onTap: () {
                      setState(() => _selectedAudioFilter = 'italian');
                      Navigator.pop(ctx);
                    },
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  void _showSeederBottomSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return _buildGlassBottomSheetContainer(
          context: context,
          header: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFF10B981).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.people_alt_rounded,
                  color: Color(0xFF10B981),
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'Seeders Filter',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close, color: Colors.white54, size: 20),
                onPressed: () => Navigator.pop(ctx),
              ),
            ],
          ),
          content: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(context).height * 0.55,
            ),
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildBottomSheetItem(
                    title: 'All Seeds',
                    isSelected: _selectedSeederFilter == 'all',
                    activeColor: const Color(0xFF10B981),
                    onTap: () {
                      setState(() => _selectedSeederFilter = 'all');
                      Navigator.pop(ctx);
                    },
                  ),
                  _buildBottomSheetItem(
                    title: 'Most Seeds (High to Low)',
                    isSelected: _selectedSeederFilter == 'most',
                    activeColor: const Color(0xFF10B981),
                    onTap: () {
                      setState(() => _selectedSeederFilter = 'most');
                      Navigator.pop(ctx);
                    },
                  ),
                  _buildBottomSheetItem(
                    title: '50+ Seeds',
                    isSelected: _selectedSeederFilter == '50+',
                    activeColor: const Color(0xFF10B981),
                    onTap: () {
                      setState(() => _selectedSeederFilter = '50+');
                      Navigator.pop(ctx);
                    },
                  ),
                  _buildBottomSheetItem(
                    title: '20+ Seeds',
                    isSelected: _selectedSeederFilter == '20+',
                    activeColor: const Color(0xFF10B981),
                    onTap: () {
                      setState(() => _selectedSeederFilter = '20+');
                      Navigator.pop(ctx);
                    },
                  ),
                  _buildBottomSheetItem(
                    title: '5+ Seeds',
                    isSelected: _selectedSeederFilter == '5+',
                    activeColor: const Color(0xFF10B981),
                    onTap: () {
                      setState(() => _selectedSeederFilter = '5+');
                      Navigator.pop(ctx);
                    },
                  ),
                  _buildBottomSheetItem(
                    title: 'Active Seeds (>0)',
                    isSelected: _selectedSeederFilter == '1+',
                    activeColor: const Color(0xFF10B981),
                    onTap: () {
                      setState(() => _selectedSeederFilter = '1+');
                      Navigator.pop(ctx);
                    },
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  void _showSizeBottomSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return _buildGlassBottomSheetContainer(
          context: context,
          header: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFF3B82F6).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.folder_open_rounded,
                  color: Color(0xFF3B82F6),
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'File Size Filter',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close, color: Colors.white54, size: 20),
                onPressed: () => Navigator.pop(ctx),
              ),
            ],
          ),
          content: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(context).height * 0.55,
            ),
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildBottomSheetItem(
                    title: 'All Sizes',
                    isSelected: _selectedSizeFilter == null,
                    activeColor: const Color(0xFF3B82F6),
                    onTap: () {
                      setState(() => _selectedSizeFilter = null);
                      Navigator.pop(ctx);
                    },
                  ),
                  _buildBottomSheetItem(
                    title: 'Largest First',
                    isSelected: _selectedSizeFilter == 'largest',
                    activeColor: const Color(0xFF3B82F6),
                    onTap: () {
                      setState(() => _selectedSizeFilter = 'largest');
                      Navigator.pop(ctx);
                    },
                  ),
                  _buildBottomSheetItem(
                    title: 'Smallest First',
                    isSelected: _selectedSizeFilter == 'smallest',
                    activeColor: const Color(0xFF3B82F6),
                    onTap: () {
                      setState(() => _selectedSizeFilter = 'smallest');
                      Navigator.pop(ctx);
                    },
                  ),
                  _buildBottomSheetItem(
                    title: '< 1 GB',
                    isSelected: _selectedSizeFilter == '<1gb',
                    activeColor: const Color(0xFF3B82F6),
                    onTap: () {
                      setState(() => _selectedSizeFilter = '<1gb');
                      Navigator.pop(ctx);
                    },
                  ),
                  _buildBottomSheetItem(
                    title: '1 - 5 GB',
                    isSelected: _selectedSizeFilter == '1-5gb',
                    activeColor: const Color(0xFF3B82F6),
                    onTap: () {
                      setState(() => _selectedSizeFilter = '1-5gb');
                      Navigator.pop(ctx);
                    },
                  ),
                  _buildBottomSheetItem(
                    title: '5 - 15 GB',
                    isSelected: _selectedSizeFilter == '5-15gb',
                    activeColor: const Color(0xFF3B82F6),
                    onTap: () {
                      setState(() => _selectedSizeFilter = '5-15gb');
                      Navigator.pop(ctx);
                    },
                  ),
                  _buildBottomSheetItem(
                    title: '15 - 30 GB',
                    isSelected: _selectedSizeFilter == '15-30gb',
                    activeColor: const Color(0xFF3B82F6),
                    onTap: () {
                      setState(() => _selectedSizeFilter = '15-30gb');
                      Navigator.pop(ctx);
                    },
                  ),
                  _buildBottomSheetItem(
                    title: '> 30 GB',
                    isSelected: _selectedSizeFilter == '>30gb',
                    activeColor: const Color(0xFF3B82F6),
                    onTap: () {
                      setState(() => _selectedSizeFilter = '>30gb');
                      Navigator.pop(ctx);
                    },
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  void _showAddonBottomSheet(List<String> addons) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return _buildGlassBottomSheetContainer(
          context: context,
          header: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.extension_rounded,
                  color: Colors.white,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'Source Provider',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close, color: Colors.white54, size: 20),
                onPressed: () => Navigator.pop(ctx),
              ),
            ],
          ),
          content: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(context).height * 0.55,
            ),
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildBottomSheetItem(
                    title: 'All Sources',
                    isSelected: _selectedAddonFilter == null,
                    activeColor: Colors.white,
                    onTap: () {
                      setState(() => _selectedAddonFilter = null);
                      Navigator.pop(ctx);
                    },
                  ),
                  for (final addon in addons)
                    _buildBottomSheetItem(
                      title: addon,
                      isSelected: _selectedAddonFilter == addon,
                      activeColor: Colors.white,
                      onTap: () {
                        setState(() => _selectedAddonFilter = addon);
                        Navigator.pop(ctx);
                      },
                    ),
                ],
              ),
            ),
          ),
        );
      },
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
    return const RepaintBoundary(child: _ShimmerCard());
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
  final Duration? initialPosition;

  const _SourceCard({
    required this.source,
    this.backdropUrl,
    this.logoUrl,
    required this.detail,
    this.episode,
    this.initialPosition,
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
    if (s.seeders != null) {
      final seederColor = s.seeders! >= 20
          ? const Color(0xFF10B981)
          : (s.seeders! >= 5 ? const Color(0xFFFFD43B) : const Color(0xFFFF922B));
      badges.add(_badge('👤 ${s.seeders} Seeds', seederColor));
    }

    // Audio Language / Dub badge
    final audioBadge = s.getAudioBadge(mediaTitle: widget.detail.name);
    if (audioBadge != null) {
      Color audioBadgeColor;
      if (audioBadge.contains('MULTI')) {
        audioBadgeColor = const Color(0xFFB197FC);
      } else if (audioBadge.contains('HINDI') ||
          audioBadge.contains('TELUGU') ||
          audioBadge.contains('TAMIL') ||
          audioBadge.contains('MALAYALAM') ||
          audioBadge.contains('KANNADA') ||
          audioBadge.contains('PUNJABI')) {
        audioBadgeColor = const Color(0xFFFF922B);
      } else if (audioBadge.contains('GER')) {
        audioBadgeColor = const Color(0xFFFFD43B);
      } else if (audioBadge.contains('FRE')) {
        audioBadgeColor = const Color(0xFF4DABF7);
      } else if (audioBadge.contains('CAST')) {
        audioBadgeColor = const Color(0xFFFAB005);
      } else if (audioBadge.contains('LAT')) {
        audioBadgeColor = const Color(0xFF20C997);
      } else if (audioBadge.contains('SPA')) {
        audioBadgeColor = const Color(0xFFFAB005);
      } else if (audioBadge.contains('RUS')) {
        audioBadgeColor = const Color(0xFF22B8CF);
      } else if (audioBadge.contains('JPN')) {
        audioBadgeColor = const Color(0xFFFF8787);
      } else if (audioBadge.contains('ITA')) {
        audioBadgeColor = const Color(0xFF69DB7C);
      } else {
        audioBadgeColor = _C.textTertiary;
      }
      badges.add(_badge(audioBadge, audioBadgeColor));
    }

    return RepaintBoundary(
      child: MouseRegion(
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

              final isColl = widget.detail.isCollection;
              final effectiveTitle = (isColl && widget.episode != null && widget.episode!.title.isNotEmpty)
                  ? widget.episode!.title
                  : s.displayTitle;

              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => PlayerScreen(
                    source: s,
                    title: effectiveTitle,
                    backdropUrl: widget.backdropUrl,
                    logoUrl: widget.logoUrl,
                    detail: widget.detail,
                    episode: widget.episode,
                    initialPosition: widget.initialPosition,
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
                  _AddonSourceIcon(addonName: s.addonName),
                  const SizedBox(width: _S.sm),
                  // Info
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          (s.addonName.toLowerCase() == 'playtorriohttp' &&
                                  s.providerName != null &&
                                  s.providerName!.isNotEmpty)
                              ? 'PlayTorrioHTTP · ${s.providerName}'
                              : (s.name != null && s.name!.isNotEmpty
                                  ? s.name!
                                  : s.addonName),
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
                  if (s.isMagnet && s.magnetUrl != null) ...[
                    _CopyMagnetButton(magnetUrl: s.magnetUrl!),
                    const SizedBox(width: 8),
                  ],
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
// Addon Source Icon / App Logo
// ─────────────────────────────────────────────────────────────────────────────
class _AddonSourceIcon extends StatelessWidget {
  final String addonName;

  const _AddonSourceIcon({required this.addonName});

  @override
  Widget build(BuildContext context) {
    final nameLower = addonName.trim().toLowerCase();
    final isBuiltIn = nameLower == 'playtorrio' ||
        nameLower == 'playtorriohttp' ||
        nameLower.startsWith('builtin');

    if (isBuiltIn) {
      return Container(
        width: 40,
        height: 40,
        padding: const EdgeInsets.all(5),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: const Color(0xFF7C5CFF).withValues(alpha: 0.25),
          ),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: Image.asset(
            'assets/icon.png',
            width: 30,
            height: 30,
            fit: BoxFit.contain,
          ),
        ),
      );
    }

    final logoUrl = AddonManager.instance.getAddonLogo(addonName);

    if (logoUrl != null && logoUrl.isNotEmpty) {
      if (logoUrl.startsWith('asset:')) {
        final assetPath = logoUrl.substring('asset:'.length);
        return Container(
          width: 40,
          height: 40,
          padding: const EdgeInsets.all(5),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: Image.asset(
              assetPath,
              width: 30,
              height: 30,
              fit: BoxFit.contain,
            ),
          ),
        );
      }

      return Container(
        width: 40,
        height: 40,
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: CachedNetworkImage(
            imageUrl: logoUrl,
            width: 32,
            height: 32,
            fit: BoxFit.contain,
            placeholder: (context, url) => Container(
              color: Colors.white.withValues(alpha: 0.04),
              child: const Center(
                child: SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: _C.accent,
                  ),
                ),
              ),
            ),
            errorWidget: (context, url, error) => _buildFallbackIcon(),
          ),
        ),
      );
    }

    return _buildFallbackIcon();
  }

  Widget _buildFallbackIcon() {
    final firstLetter = addonName.isNotEmpty ? addonName[0].toUpperCase() : 'A';
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: _C.accent.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _C.accent.withValues(alpha: 0.3)),
      ),
      child: Center(
        child: Text(
          firstLetter,
          style: const TextStyle(
            color: _C.accent,
            fontSize: 17,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Copy Magnet Button
// ─────────────────────────────────────────────────────────────────────────────
class _CopyMagnetButton extends StatefulWidget {
  final String magnetUrl;

  const _CopyMagnetButton({required this.magnetUrl});

  @override
  State<_CopyMagnetButton> createState() => _CopyMagnetButtonState();
}

class _CopyMagnetButtonState extends State<_CopyMagnetButton> {
  bool _copied = false;
  bool _hovered = false;
  Timer? _timer;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _copy() {
    Clipboard.setData(ClipboardData(text: widget.magnetUrl));
    HapticFeedback.lightImpact();

    setState(() => _copied = true);
    _timer?.cancel();
    _timer = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => _copied = false);
    });

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
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Tooltip(
        message: _copied ? 'Copied!' : 'Copy Magnet Link',
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: _copy,
            borderRadius: BorderRadius.circular(18),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: _copied
                    ? const Color(0xFF10B981).withValues(alpha: 0.2)
                    : (_hovered
                        ? const Color(0xFF00E5FF).withValues(alpha: 0.18)
                        : Colors.white.withValues(alpha: 0.06)),
                shape: BoxShape.circle,
                border: Border.all(
                  color: _copied
                      ? const Color(0xFF10B981).withValues(alpha: 0.5)
                      : (_hovered
                          ? const Color(0xFF00E5FF).withValues(alpha: 0.4)
                          : Colors.white.withValues(alpha: 0.08)),
                  width: 1,
                ),
              ),
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                child: Icon(
                  _copied ? Icons.check_rounded : Icons.link_rounded,
                  key: ValueKey(_copied),
                  color: _copied
                      ? const Color(0xFF10B981)
                      : (_hovered ? const Color(0xFF00E5FF) : _C.textSecondary),
                  size: 18,
                ),
              ),
            ),
          ),
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
