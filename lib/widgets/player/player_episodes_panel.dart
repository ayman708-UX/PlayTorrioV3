import 'dart:ui';
import 'package:flutter/material.dart';
import '../../models/movie/video.dart';
import 'player_glass.dart';

/// Ultra-responsive, glassmorphic Episodes Side Panel with season tabs,
/// auto-scroll to current episode, animated card expansion, and high FPS rendering.
class PlayerEpisodesPanel extends StatefulWidget {
  final List<Video> videos;
  final Video? currentEpisode;
  final Function(Video selectedEpisode) onEpisodeSelected;
  final VoidCallback onClose;

  const PlayerEpisodesPanel({
    super.key,
    required this.videos,
    this.currentEpisode,
    required this.onEpisodeSelected,
    required this.onClose,
  });

  @override
  State<PlayerEpisodesPanel> createState() => _PlayerEpisodesPanelState();
}

class _PlayerEpisodesPanelState extends State<PlayerEpisodesPanel> {
  final ScrollController _scrollController = ScrollController();
  final ScrollController _seasonScrollController = ScrollController();
  late int _selectedSeason;
  String? _selectedEpisodeId;
  int? _hoveredIndex;

  List<int> _seasons = [];
  Map<int, List<Video>> _seasonEpisodes = {};
  Map<int, String> _seasonLabels = {};

  @override
  void initState() {
    super.initState();
    _organizeSeasons();

    _selectedEpisodeId = widget.currentEpisode?.id;

    // Find the season/batch containing the current episode
    int initialSeason = _seasons.isNotEmpty ? _seasons.first : 1;
    if (widget.currentEpisode != null) {
      for (final entry in _seasonEpisodes.entries) {
        final hasEp = entry.value.any((v) =>
            v.id == widget.currentEpisode?.id ||
            (v.episode != null && v.episode == widget.currentEpisode?.episode));
        if (hasEp) {
          initialSeason = entry.key;
          break;
        }
      }
    }
    _selectedSeason = initialSeason;

    // Auto-scroll to currently playing episode and active season tab on open
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollToCurrentEpisode(immediate: true);
      _scrollToActiveSeason(immediate: true);
    });
  }

  void _organizeSeasons() {
    final map = <int, List<Video>>{};
    final distinctSeasons = widget.videos.map((v) => v.season ?? 1).toSet();

    if (distinctSeasons.length > 1) {
      for (final video in widget.videos) {
        final s = video.season ?? 1;
        map.putIfAbsent(s, () => []).add(video);
      }
      final seasons = map.keys.toList()..sort();
      for (final s in seasons) {
        map[s]!.sort((a, b) => (a.episode ?? 0).compareTo(b.episode ?? 0));
      }
      _seasons = seasons;
      _seasonEpisodes = map;
      _seasonLabels = {for (final s in seasons) s: 'Season $s'};
    } else if (widget.videos.length > 50) {
      // Group single season with 50+ episodes into 50-episode tabs (e.g. 1-50, 51-100)
      const chunkSize = 50;
      final sortedVideos = List<Video>.from(widget.videos)
        ..sort((a, b) => (a.episode ?? 0).compareTo(b.episode ?? 0));

      final batchKeys = <int>[];
      final batchLabels = <int, String>{};

      for (int i = 0; i < sortedVideos.length; i += chunkSize) {
        final batchNum = (i ~/ chunkSize) + 1;
        final end = (i + chunkSize < sortedVideos.length) ? i + chunkSize : sortedVideos.length;
        final chunk = sortedVideos.sublist(i, end);
        final startEp = chunk.first.episode ?? (i + 1);
        final endEp = chunk.last.episode ?? end;

        map[batchNum] = chunk;
        batchKeys.add(batchNum);
        batchLabels[batchNum] = '$startEp - $endEp';
      }

      _seasons = batchKeys;
      _seasonEpisodes = map;
      _seasonLabels = batchLabels;
    } else {
      const s = 1;
      map[s] = List<Video>.from(widget.videos)
        ..sort((a, b) => (a.episode ?? 0).compareTo(b.episode ?? 0));
      _seasons = [s];
      _seasonEpisodes = map;
      _seasonLabels = {s: 'Season 1'};
    }
  }

  void _scrollToCurrentEpisode({bool immediate = false}) {
    if (!mounted || widget.currentEpisode == null) return;

    final currentList = _seasonEpisodes[_selectedSeason] ?? [];
    final idx = currentList.indexWhere((v) => v.id == widget.currentEpisode?.id);
    if (idx < 0) return;

    // Approximate card height: 110px compact, 180px expanded
    final targetOffset = (idx * 116.0).clamp(
      0.0,
      _scrollController.hasClients ? _scrollController.position.maxScrollExtent : 9999.0,
    );

    if (immediate) {
      if (_scrollController.hasClients) {
        _scrollController.jumpTo(targetOffset);
      } else {
        Future.delayed(const Duration(milliseconds: 60), () {
          if (mounted && _scrollController.hasClients) {
            _scrollController.jumpTo(targetOffset);
          }
        });
      }
    } else {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          targetOffset,
          duration: const Duration(milliseconds: 320),
          curve: Curves.easeOutCubic,
        );
      }
    }
  }

  void _scrollToActiveSeason({bool immediate = false}) {
    if (!mounted || _seasons.isEmpty) return;
    final idx = _seasons.indexOf(_selectedSeason);
    if (idx < 0) return;
    final targetOffset = (idx * 86.0).clamp(
      0.0,
      _seasonScrollController.hasClients ? _seasonScrollController.position.maxScrollExtent : 9999.0,
    );
    if (immediate) {
      if (_seasonScrollController.hasClients) {
        _seasonScrollController.jumpTo(targetOffset);
      } else {
        Future.delayed(const Duration(milliseconds: 60), () {
          if (mounted && _seasonScrollController.hasClients) {
            _seasonScrollController.jumpTo(targetOffset);
          }
        });
      }
    } else {
      if (_seasonScrollController.hasClients) {
        _seasonScrollController.animateTo(
          targetOffset,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
        );
      }
    }
  }

  void _selectSeason(int season) {
    if (_selectedSeason == season) return;
    setState(() {
      _selectedSeason = season;
      final episodesInSeason = _seasonEpisodes[season] ?? [];
      if (episodesInSeason.isNotEmpty) {
        _selectedEpisodeId = episodesInSeason.first.id;
      }
    });

    _scrollToActiveSeason();

    if (_scrollController.hasClients) {
      _scrollController.jumpTo(0.0);
    }
  }

  void _handleEpisodeTap(Video video) {
    if (_selectedEpisodeId == video.id) {
      // Second tap on the selected card -> open sources panel!
      widget.onEpisodeSelected(video);
    } else {
      // First tap -> select and smoothly expand card
      setState(() {
        _selectedEpisodeId = video.id;
      });
    }
  }

  void _scrollStep(bool down) {
    if (!_scrollController.hasClients) return;
    final current = _scrollController.offset;
    final target = (current + (down ? 240.0 : -240.0)).clamp(
      0.0,
      _scrollController.position.maxScrollExtent,
    );
    _scrollController.animateTo(
      target,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOutCubic,
    );
  }

  void _scrollSeason(bool right) {
    if (!_seasonScrollController.hasClients) return;
    final current = _seasonScrollController.offset;
    final target = (current + (right ? 140.0 : -140.0)).clamp(
      0.0,
      _seasonScrollController.position.maxScrollExtent,
    );
    _seasonScrollController.animateTo(
      target,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _seasonScrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.sizeOf(context).width;
    final isCompact = screenWidth < 680;
    final drawerWidth = isCompact ? screenWidth * 0.94 : 440.0;
    final episodes = _seasonEpisodes[_selectedSeason] ?? [];

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
                _buildHeader(episodes.length, isCompact),

                // ── Season Tabs Row (if multi-season) ──
                if (_seasons.length > 1) _buildSeasonTabs(isCompact),

                const Divider(height: 1, color: Color(0x1AFFFFFF)),

                // ── Scrollable Episodes List ──
                Expanded(
                  child: Stack(
                    children: [
                      ListView.separated(
                        controller: _scrollController,
                        physics: const BouncingScrollPhysics(),
                        padding: EdgeInsets.symmetric(
                          horizontal: isCompact ? 12 : 16,
                          vertical: 14,
                        ),
                        itemCount: episodes.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 10),
                        itemBuilder: (context, index) {
                          final video = episodes[index];
                          final isCurrentPlaying = widget.currentEpisode?.id == video.id ||
                              (widget.currentEpisode?.season == video.season &&
                                  widget.currentEpisode?.episode == video.episode);
                          final isSelected = _selectedEpisodeId == video.id;

                          return _buildEpisodeCard(
                            video: video,
                            index: index,
                            isCurrentPlaying: isCurrentPlaying,
                            isSelected: isSelected,
                            isCompact: isCompact,
                          );
                        },
                      ),

                      // Floating Quick Scroll Controls (Desktop / TV friendly)
                      if (!isCompact && episodes.length > 4) ...[
                        Positioned(
                          right: 12,
                          top: 12,
                          child: _buildScrollFloatingButton(
                            icon: Icons.keyboard_arrow_up_rounded,
                            tooltip: 'Scroll Up',
                            onTap: () => _scrollStep(false),
                          ),
                        ),
                        Positioned(
                          right: 12,
                          bottom: 12,
                          child: _buildScrollFloatingButton(
                            icon: Icons.keyboard_arrow_down_rounded,
                            tooltip: 'Scroll Down',
                            onTap: () => _scrollStep(true),
                          ),
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

  Widget _buildHeader(int episodeCount, bool isCompact) {
    return Container(
      padding: EdgeInsets.only(
        top: MediaQuery.paddingOf(context).top + 12,
        left: isCompact ? 14 : 20,
        right: isCompact ? 14 : 18,
        bottom: 12,
      ),
      color: const Color(0x66000000),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(
              color: PlayerTheme.accent.withValues(alpha: 0.20),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: PlayerTheme.accent.withValues(alpha: 0.40),
              ),
            ),
            child: const Icon(
              Icons.video_library_rounded,
              color: Color(0xFF9D84FF),
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Episodes',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.3,
                  ),
                ),
                Text(
                  '${_seasonLabels[_selectedSeason] ?? "Season $_selectedSeason"} • $episodeCount Episodes',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.55),
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
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

  Widget _buildSeasonTabs(bool isCompact) {
    final showArrows = !isCompact && _seasons.length > 2;

    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
      color: const Color(0x33000000),
      child: Row(
        children: [
          // Desktop Left Season Arrow
          if (showArrows)
            Padding(
              padding: const EdgeInsets.only(left: 4, right: 2),
              child: _buildSeasonArrowButton(
                icon: Icons.chevron_left_rounded,
                tooltip: 'Previous Seasons',
                onTap: () => _scrollSeason(false),
              ),
            ),

          // Scrollable Season Tabs
          Expanded(
            child: ListView.separated(
              controller: _seasonScrollController,
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              padding: EdgeInsets.symmetric(horizontal: isCompact ? 12 : 6),
              itemCount: _seasons.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                final season = _seasons[index];
                final isActive = season == _selectedSeason;
                final tabLabel = _seasonLabels[season] ?? 'Season $season';

                return Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: () => _selectSeason(season),
                    borderRadius: BorderRadius.circular(10),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                      decoration: BoxDecoration(
                        color: isActive
                            ? PlayerTheme.accent.withValues(alpha: 0.28)
                            : Colors.white.withValues(alpha: 0.06),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: isActive
                              ? PlayerTheme.accent.withValues(alpha: 0.80)
                              : Colors.white.withValues(alpha: 0.10),
                          width: 1.2,
                        ),
                        boxShadow: isActive
                            ? [
                                BoxShadow(
                                  color: PlayerTheme.accent.withValues(alpha: 0.35),
                                  blurRadius: 10,
                                  offset: const Offset(0, 2),
                                ),
                              ]
                            : null,
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        tabLabel,
                        style: TextStyle(
                          color: isActive ? Colors.white : Colors.white.withValues(alpha: 0.70),
                          fontSize: 12.5,
                          fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),

          // Desktop Right Season Arrow
          if (showArrows)
            Padding(
              padding: const EdgeInsets.only(left: 2, right: 4),
              child: _buildSeasonArrowButton(
                icon: Icons.chevron_right_rounded,
                tooltip: 'Next Seasons',
                onTap: () => _scrollSeason(true),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSeasonArrowButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback onTap,
  }) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.14),
                width: 1,
              ),
            ),
            alignment: Alignment.center,
            child: Icon(
              icon,
              size: 20,
              color: Colors.white.withValues(alpha: 0.85),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEpisodeCard({
    required Video video,
    required int index,
    required bool isCurrentPlaying,
    required bool isSelected,
    required bool isCompact,
  }) {
    final epNum = video.episode ?? (index + 1);
    final epTitle = video.title.isNotEmpty ? video.title : 'Episode $epNum';
    final hasOverview = video.overview != null && video.overview!.trim().isNotEmpty;
    final isHovered = _hoveredIndex == index;

    return MouseRegion(
      onEnter: (_) => setState(() => _hoveredIndex = index),
      onExit: (_) => setState(() => _hoveredIndex = null),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () => _handleEpisodeTap(video),
        child: AnimatedScale(
          scale: isSelected ? 1.0 : (isHovered ? 1.015 : 1.0),
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 240),
            curve: Curves.easeOutCubic,
            decoration: BoxDecoration(
              color: isSelected
                  ? const Color(0xFF141926)
                  : (isHovered
                      ? const Color(0x331E2435)
                      : const Color(0x1F121722)),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: isSelected
                    ? PlayerTheme.accent
                    : (isCurrentPlaying
                        ? const Color(0xFF10B981).withValues(alpha: 0.70)
                        : (isHovered
                            ? Colors.white.withValues(alpha: 0.28)
                            : Colors.white.withValues(alpha: 0.10))),
                width: isSelected ? 1.8 : 1.0,
              ),
              boxShadow: [
                if (isSelected)
                  BoxShadow(
                    color: PlayerTheme.accent.withValues(alpha: 0.30),
                    blurRadius: 18,
                    offset: const Offset(0, 4),
                  )
                else if (isHovered)
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.50),
                    blurRadius: 12,
                    offset: const Offset(0, 3),
                  ),
              ],
            ),
            padding: EdgeInsets.all(isCompact ? 10 : 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Top Row: Thumbnail + Episode Info
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Thumbnail Container
                    ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: Container(
                        width: isSelected ? 116 : (isCompact ? 92 : 104),
                        height: isSelected ? 68 : (isCompact ? 56 : 62),
                        color: const Color(0xFF1A1F2C),
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            if (video.thumbnail != null && video.thumbnail!.isNotEmpty)
                              Image.network(
                                video.thumbnail!,
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => _buildThumbPlaceholder(epNum),
                              )
                            else
                              _buildThumbPlaceholder(epNum),

                            // Subtle dark gradient overlay
                            Container(
                              decoration: const BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                  colors: [Colors.transparent, Color(0x99000000)],
                                ),
                              ),
                            ),

                            // Episode Badge on Thumbnail
                            Positioned(
                              left: 5,
                              bottom: 5,
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                                decoration: BoxDecoration(
                                  color: Colors.black.withValues(alpha: 0.75),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  'EP $epNum',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 10,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 0.4,
                                  ),
                                ),
                              ),
                            ),

                            // Center Play Icon Indicator
                            if (isSelected || isHovered)
                              Center(
                                child: Container(
                                  padding: const EdgeInsets.all(6),
                                  decoration: BoxDecoration(
                                    color: (isSelected ? PlayerTheme.accent : Colors.black)
                                        .withValues(alpha: 0.85),
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(
                                    Icons.play_arrow_rounded,
                                    color: Colors.white,
                                    size: 16,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(width: 12),

                    // Episode Title & Details
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              // "NOW PLAYING" Badge
                              if (isCurrentPlaying) ...[
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  margin: const EdgeInsets.only(right: 6),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF10B981).withValues(alpha: 0.20),
                                    borderRadius: BorderRadius.circular(5),
                                    border: Border.all(
                                      color: const Color(0xFF10B981).withValues(alpha: 0.60),
                                    ),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Container(
                                        width: 6,
                                        height: 6,
                                        decoration: const BoxDecoration(
                                          color: Color(0xFF10B981),
                                          shape: BoxShape.circle,
                                        ),
                                      ),
                                      const SizedBox(width: 4),
                                      const Text(
                                        'PLAYING',
                                        style: TextStyle(
                                          color: Color(0xFF34D399),
                                          fontSize: 9.5,
                                          fontWeight: FontWeight.w800,
                                          letterSpacing: 0.5,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],

                              if (video.released != null && video.released!.isNotEmpty) ...[
                                Text(
                                  video.released!,
                                  style: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.50),
                                    fontSize: 11,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ],
                          ),

                          const SizedBox(height: 3),

                          // Episode Title
                          Text(
                            epTitle,
                            style: TextStyle(
                              color: isSelected
                                  ? const Color(0xFF9D84FF)
                                  : (isCurrentPlaying ? const Color(0xFF34D399) : Colors.white),
                              fontSize: isSelected ? 14.5 : 13.5,
                              fontWeight: isSelected || isCurrentPlaying
                                  ? FontWeight.w700
                                  : FontWeight.w600,
                              letterSpacing: -0.2,
                            ),
                            maxLines: isSelected ? 2 : 1,
                            overflow: TextOverflow.ellipsis,
                          ),

                          if (!isSelected && hasOverview) ...[
                            const SizedBox(height: 3),
                            Text(
                              video.overview!,
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.55),
                                fontSize: 11.5,
                                height: 1.25,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),

                // Expanded Section for Selected Episode
                if (isSelected) ...[
                  const SizedBox(height: 10),
                  if (hasOverview) ...[
                    Text(
                      video.overview!,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.75),
                        fontSize: 12.0,
                        height: 1.35,
                      ),
                      maxLines: 4,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 12),
                  ],

                  // "SELECT SOURCE / PLAY" Action Button
                  Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: () => widget.onEpisodeSelected(video),
                      borderRadius: BorderRadius.circular(10),
                      child: Container(
                        height: 38,
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFF7C5CFF), Color(0xFF9D84FF)],
                          ),
                          borderRadius: BorderRadius.circular(10),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFF7C5CFF).withValues(alpha: 0.45),
                              blurRadius: 10,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.play_circle_filled_rounded, color: Colors.white, size: 18),
                            SizedBox(width: 8),
                            Text(
                              'Select Sources',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.1,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildThumbPlaceholder(int epNum) {
    return Container(
      color: const Color(0xFF141926),
      alignment: Alignment.center,
      child: Icon(
        Icons.tv_rounded,
        color: Colors.white.withValues(alpha: 0.20),
        size: 26,
      ),
    );
  }

  Widget _buildScrollFloatingButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback onTap,
  }) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(999),
          child: Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: const Color(0xD9080C14),
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white.withValues(alpha: 0.20)),
              boxShadow: const [
                BoxShadow(
                  color: Colors.black54,
                  blurRadius: 8,
                  offset: Offset(0, 2),
                ),
              ],
            ),
            child: Icon(icon, color: Colors.white, size: 20),
          ),
        ),
      ),
    );
  }
}
