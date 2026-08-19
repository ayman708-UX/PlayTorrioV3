import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../models/iptv/espn_models.dart';
import '../../models/iptv/iptv_models.dart';
import '../../models/iptv/sports_models.dart';
import '../../models/stream/stream_model.dart';
import '../../services/iptv/channel_scorer.dart';
import '../../services/iptv/espn_client.dart';
import '../../services/iptv/iptv_repository.dart';
import '../../services/iptv/multi_window_store.dart';
import '../../services/iptv/portal_nutz_scraper.dart';
import '../../services/iptv/quick_channel_list.dart';
import '../../services/iptv/stream_validation_store.dart';
import '../../utils/tab_navigation.dart';
import '../../widgets/multiwindow/multi_window_position_picker.dart';
import '../player/player_screen.dart';

const _bg = Color(0xFF080A0F);
const _surface = Color(0xFF151822);
const _surfaceLight = Color(0xFF1A1D27);
const _surfaceLowest = Color(0xFF0C0E13);
const _accent = Color(0xFF7C5CFF);
const _gold = Color(0xFFFFD700);
const _cyan = Color(0xFF00F0FF);
const _green = Color(0xFF4CAF50);
const _red = Color(0xFFFF4444);
const _textPrimary = Colors.white;
const _textSecondary = Color(0xB3FFFFFF);
const _textTertiary = Color(0x80FFFFFF);

/// The IPTVNutz tab (mirrors `IptvScreen.kt`). Adapts between a phone layout
/// and a TV layout (width >= 1024) with bento favorites, quick channels,
/// recommended grid, playlists, history, EPG and Live Sports.
class IptvPage extends StatefulWidget {
  const IptvPage({super.key});

  @override
  State<IptvPage> createState() => _IptvPageState();
}

class _IptvPageState extends State<IptvPage> {
  final IptvRepository _repo = IptvRepository.instance;
  bool _showSearch = false;
  IptvChannel? _epgChannel;
  List<EspnProcessedEvent> _sportsEvents = [];
  bool _sportsLoading = true;
  String? _sportsError;

  @override
  void initState() {
    super.initState();
    _repo.ensureLoaded();
    _loadSports();
  }

  Future<void> _loadSports() async {
    setState(() {
      _sportsLoading = true;
      _sportsError = null;
    });
    try {
      final all = await EspnClient.fetchAll();
      if (!mounted) return;
      // Prefer live events, then upcoming, capped for display.
      final sorted = [...all]
        ..sort((a, b) {
          if (a.isLive != b.isLive) return a.isLive ? -1 : 1;
          return 0;
        });
      setState(() {
        _sportsEvents = sorted.take(12).toList();
        _sportsLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _sportsError = e.toString();
        _sportsLoading = false;
      });
    }
  }

  void _playChannel(BuildContext context, IptvChannel channel) {
    _repo.addToHistory(channel.id);
    final source = StreamSource(
      url: channel.url,
      name: channel.name,
      title: channel.name,
      addonName: 'IPTVNutz',
    );
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PlayerScreen(source: source, title: channel.name),
      ),
    );
  }

  void _openPicker(IptvChannel channel) {
    MultiWindowPositionPicker.show(
      context,
      channelName: channel.name,
      channelLogo: channel.logo,
      selectionMode: true,
      onSlotSelected: (slot) {
        MultiWindowStore.instance.addToSlot(channel, slot);
      },
      onSlotSelectedAndOpenHub: (slot) {
        MultiWindowStore.instance.addToSlot(channel, slot);
        TabNav.switchTo(TabNav.multiWindow);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<IptvUiState>(
      valueListenable: _repo.uiState,
      builder: (context, state, _) {
        return LayoutBuilder(
          builder: (context, constraints) {
            final isTv = constraints.maxWidth >= 1024;
            final content = isTv
                ? _TvLayout(
                    state: state,
                    repo: _repo,
                    showSearch: _showSearch,
                    onToggleSearch: () =>
                        setState(() => _showSearch = !_showSearch),
                    onPlay: (ch) => _playChannel(context, ch),
                    onAddSource: () => _showAddSourceSheet(context),
                    onPicker: _openPicker,
                    onEpg: (ch) => setState(() => _epgChannel = ch),
                    sportsEvents: _sportsEvents,
                    sportsLoading: _sportsLoading,
                    sportsError: _sportsError,
                    onRetrySports: _loadSports,
                  )
                : _MobileLayout(
                    state: state,
                    repo: _repo,
                    showSearch: _showSearch,
                    onToggleSearch: () =>
                        setState(() => _showSearch = !_showSearch),
                    onPlay: (ch) => _playChannel(context, ch),
                    onAddSource: () => _showAddSourceSheet(context),
                    onPicker: _openPicker,
                    onEpg: (ch) => setState(() => _epgChannel = ch),
                    sportsEvents: _sportsEvents,
                    sportsLoading: _sportsLoading,
                    sportsError: _sportsError,
                    onRetrySports: _loadSports,
                  );
            return Stack(
              children: [
                Positioned.fill(child: content),
                if (_epgChannel != null)
                  Positioned.fill(
                    child: _EpgSheet(
                      channel: _epgChannel!,
                      repo: _repo,
                      onDismiss: () => setState(() => _epgChannel = null),
                    ),
                  ),
              ],
            );
          },
        );
      },
    );
  }

  void _showAddSourceSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black54,
      builder: (_) => _AddSourceSheet(repo: _repo),
    );
  }
}

// ── Top bar ───────────────────────────────────────────────────────────────

class _TopBar extends StatelessWidget {
  final bool showSearch;
  final String searchQuery;
  final ValueChanged<String> onSearchChanged;
  final VoidCallback onToggleSearch;
  final VoidCallback onAddSource;

  const _TopBar({
    required this.showSearch,
    required this.searchQuery,
    required this.onSearchChanged,
    required this.onToggleSearch,
    required this.onAddSource,
  });

  @override
  Widget build(BuildContext context) {
    final isTv = MediaQuery.sizeOf(context).width >= 1024;
    return Container(
      padding: EdgeInsets.fromLTRB(
        isTv ? 28 : 16,
        MediaQuery.of(context).padding.top + 8,
        isTv ? 28 : 16,
        8,
      ),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [_bg.withValues(alpha: 0.96), _bg.withValues(alpha: 0.0)],
        ),
        border: const Border(
          bottom: BorderSide(color: Color(0x1AFFFFFF), width: 0.5),
        ),
      ),
      child: Row(
        children: [
          Icon(Icons.live_tv_rounded, color: _accent, size: isTv ? 28 : 24),
          const SizedBox(width: 10),
          const Text(
            'IPTVNutz',
            style: TextStyle(
              color: _accent,
              fontWeight: FontWeight.w800,
              fontSize: 21,
              letterSpacing: -0.5,
            ),
          ),
          if (showSearch) ...[
            const SizedBox(width: 16),
            Expanded(
              child: Container(
                height: 42,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                decoration: BoxDecoration(
                  color: _surfaceLight,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: const Color(0x1AFFFFFF), width: 0.5),
                ),
                child: TextField(
                  autofocus: true,
                  onChanged: onSearchChanged,
                  style: const TextStyle(color: _textPrimary, fontSize: 13),
                  decoration: const InputDecoration(
                    hintText: 'Search channels, groups, or sources...',
                    hintStyle: TextStyle(
                      color: Color(0x80FFFFFF),
                      fontSize: 13,
                    ),
                    border: InputBorder.none,
                    isDense: true,
                    suffixIcon: Icon(
                      Icons.close_rounded,
                      size: 18,
                      color: _textTertiary,
                    ),
                  ),
                  onSubmitted: (_) {},
                ),
              ),
            ),
          ] else
            const Spacer(),
          if (!showSearch)
            IconButton(
              icon: Icon(Icons.search_rounded,
                  color: _textPrimary, size: isTv ? 26 : 22),
              onPressed: onToggleSearch,
            ),
          const SizedBox(width: 4),
          if (!showSearch)
            IconButton(
              icon: Icon(Icons.add_circle_outline_rounded,
                  color: _textPrimary, size: isTv ? 26 : 22),
              tooltip: 'Add source',
              onPressed: onAddSource,
            ),
          const SizedBox(width: 8),
          // Profile avatar (glass)
          _Glass(
            radius: 22,
            color: _surface,
            child: Container(
              width: isTv ? 44 : 40,
              height: isTv ? 44 : 40,
              alignment: Alignment.center,
              child: const Icon(Icons.person_rounded,
                  color: _textSecondary, size: 24),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Source chips ──────────────────────────────────────────────────────────

class _SourceChipsRow extends StatelessWidget {
  final IptvRepository repo;
  final IptvUiState state;

  const _SourceChipsRow({required this.repo, required this.state});

  @override
  Widget build(BuildContext context) {
    final names = repo.getAllSourceNames();
    final ids = repo.getAllSourceIds();

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          _Chip(
            label: 'All',
            count: state.channels.length,
            selected: state.selectedSourceIds.isEmpty,
            onTap: repo.clearSourceSelection,
          ),
          for (var i = 0; i < ids.length; i++) ...[
            const SizedBox(width: 8),
            _Chip(
              label: names[i],
              selected: state.selectedSourceIds.contains(ids[i]),
              onTap: () => repo.toggleSourceSelection(i),
            ),
          ],
        ],
      ),
    );
  }
}

class _CategoryChipsRow extends StatelessWidget {
  final IptvRepository repo;
  final IptvUiState state;

  const _CategoryChipsRow({required this.repo, required this.state});

  @override
  Widget build(BuildContext context) {
    final categories = repo.getAllCategories();
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          _Chip(
            label: 'All Categories',
            selected: state.selectedCategory == null,
            onTap: () => repo.selectCategory(null),
          ),
          for (final c in categories) ...[
            const SizedBox(width: 8),
            _Chip(
              label: c,
              selected: state.selectedCategory == c,
              onTap: () => repo.selectCategory(c),
            ),
          ],
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final String label;
  final int? count;
  final bool selected;
  final VoidCallback onTap;

  const _Chip({
    required this.label,
    this.count,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? _accent : _surfaceLight,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? Colors.transparent : _textTertiary,
            width: 0.5,
          ),
        ),
        child: Text(
          count != null ? '$label ($count)' : label,
          style: TextStyle(
            color: selected ? Colors.white : _textSecondary,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

// ── Shared channel card bits ──────────────────────────────────────────────

class _ChannelLogo extends StatelessWidget {
  final String? url;
  final double size;

  const _ChannelLogo({this.url, this.size = 40});

  @override
  Widget build(BuildContext context) {
    if (url == null || url!.isEmpty) {
      return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: _surfaceLight,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(Icons.live_tv_rounded,
            color: _textTertiary, size: size * 0.5),
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: CachedNetworkImage(
        imageUrl: url!,
        width: size,
        height: size,
        fit: BoxFit.contain,
        placeholder: (_, __) => Container(
          width: size,
          height: size,
          color: _surfaceLight,
        ),
        errorWidget: (_, __, ___) => Container(
          width: size,
          height: size,
          color: _surfaceLight,
          child: Icon(Icons.live_tv_rounded,
              color: _textTertiary, size: size * 0.5),
        ),
      ),
    );
  }
}

// ── Shared glass card (Liquid Cinematic) ─────────────────────────────────

/// Glassmorphism card: translucent fill with a 1px gradient hairline border
/// (white 20% → 5%, top-left to bottom-right) — mirrors `.glass-panel`.
class _Glass extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final double radius;
  final Color? color;

  const _Glass({
    required this.child,
    this.padding,
    this.radius = 16,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0x33FFFFFF), Color(0x0DFFFFFF)],
        ),
        borderRadius: BorderRadius.circular(radius),
      ),
      padding: const EdgeInsets.all(1),
      child: Container(
        padding: padding,
        decoration: BoxDecoration(
          color: color ?? _surfaceLight,
          borderRadius: BorderRadius.circular(radius - 1),
        ),
        child: child,
      ),
    );
  }
}

/// Section header with the Sora-like headline style used across the redesign.
class _SectionTitle extends StatelessWidget {
  final String text;
  final IconData? icon;

  const _SectionTitle(this.text, {this.icon});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        if (icon != null) ...[
          Icon(icon, color: _accent, size: 20),
          const SizedBox(width: 8),
        ],
        Text(
          text,
          style: const TextStyle(
            color: _textPrimary,
            fontWeight: FontWeight.w700,
            fontSize: 20,
            letterSpacing: -0.3,
          ),
        ),
      ],
    );
  }
}

// ── TV layout ─────────────────────────────────────────────────────────────

class _TvLayout extends StatefulWidget {
  final IptvUiState state;
  final IptvRepository repo;
  final bool showSearch;
  final VoidCallback onToggleSearch;
  final ValueChanged<IptvChannel> onPlay;
  final VoidCallback onAddSource;
  final ValueChanged<IptvChannel> onPicker;
  final ValueChanged<IptvChannel> onEpg;
  final List<EspnProcessedEvent> sportsEvents;
  final bool sportsLoading;
  final String? sportsError;
  final VoidCallback onRetrySports;

  const _TvLayout({
    required this.state,
    required this.repo,
    required this.showSearch,
    required this.onToggleSearch,
    required this.onPlay,
    required this.onAddSource,
    required this.onPicker,
    required this.onEpg,
    required this.sportsEvents,
    required this.sportsLoading,
    required this.sportsError,
    required this.onRetrySports,
  });

  @override
  State<_TvLayout> createState() => _TvLayoutState();
}

class _TvLayoutState extends State<_TvLayout> {
  final ScrollController _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final repo = widget.repo;
    final allChannels = repo.getAllChannels();
    final favorites = repo.getFavoriteChannels();
    final history = repo.getHistoryChannels();

    final displayChannels = state.searchQuery.isNotEmpty
        ? allChannels.where((c) {
            final q = state.searchQuery.toLowerCase();
            return c.name.toLowerCase().contains(q) ||
                (c.group?.toLowerCase().contains(q) ?? false);
          }).toList()
        : allChannels;

    final heroEvent = widget.sportsEvents.isEmpty
        ? null
        : widget.sportsEvents.first;

    return Container(
      color: _bg,
      child: Column(
        children: [
          _TopBar(
            showSearch: widget.showSearch,
            searchQuery: state.searchQuery,
            onSearchChanged: repo.setSearchQuery,
            onToggleSearch: widget.onToggleSearch,
            onAddSource: widget.onAddSource,
          ),
          Expanded(
            child: ListView(
              controller: _scroll,
              padding: const EdgeInsets.symmetric(horizontal: 28),
              children: [
                _LiveHero(
                  event: heroEvent,
                  loading: widget.sportsLoading,
                  onPlay: widget.onPlay,
                  onRetry: widget.onRetrySports,
                ),
                const SizedBox(height: 28),
                _QuickZapRow(
                  allChannels: allChannels,
                  onPlay: widget.onPlay,
                ),
                const SizedBox(height: 28),
                _BouquetsGrid(repo: repo, state: state),
                const SizedBox(height: 28),
                if (favorites.isNotEmpty) ...[
                  _FavoriteBentoSection(
                    favorites: favorites.take(3).toList(),
                    onPlay: widget.onPlay,
                    onEpg: widget.onEpg,
                  ),
                  const SizedBox(height: 28),
                ],
                if (state.error != null) ...[
                  _ErrorBanner(error: state.error!),
                  const SizedBox(height: 16),
                ],
                _SourceChipsRow(repo: repo, state: state),
                const SizedBox(height: 12),
                _CategoryChipsRow(repo: repo, state: state),
                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Recommended Channels',
                      style: TextStyle(
                        color: _accent,
                        fontWeight: FontWeight.w600,
                        fontSize: 20,
                      ),
                    ),
                    Text(
                      'VIEW ALL',
                      style: TextStyle(
                        color: _textTertiary,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        fontFamily: 'monospace',
                        letterSpacing: 1,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _ChannelGrid(
                  channels: displayChannels.take(10).toList(),
                  favorites: state.favoriteChannelIds.toSet(),
                  onPlay: widget.onPlay,
                  onPicker: widget.onPicker,
                  onEpg: widget.onEpg,
                  onToggleFavorite: repo.toggleFavorite,
                ),
                const SizedBox(height: 28),
                _LiveSportsPanel(
                  events: widget.sportsEvents,
                  loading: widget.sportsLoading,
                  error: widget.sportsError,
                  onRetry: widget.onRetrySports,
                  onPlay: widget.onPlay,
                ),
                const SizedBox(height: 28),
                _PlaylistsSection(
                  state: state,
                  repo: repo,
                  onAddClick: widget.onAddSource,
                ),
                const SizedBox(height: 28),
                if (history.isNotEmpty)
                  _HistorySection(
                    history: history.take(12).toList(),
                    onPlay: widget.onPlay,
                    onClear: repo.clearHistory,
                  ),
                const SizedBox(height: 120),
              ],
            ),
          ),
          _StatusBar(upNext: history.isEmpty ? '' : history.first.name),
        ],
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  final String error;

  const _ErrorBanner({required this.error});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0x33FFB4AB),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(error, style: const TextStyle(color: _red, fontSize: 13)),
    );
  }
}

class _StatusBar extends StatelessWidget {
  final String upNext;

  const _StatusBar({required this.upNext});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 8),
      decoration: const BoxDecoration(
        color: Color(0xE6151822),
        border: Border(top: BorderSide(color: Color(0x80414755), width: 0.5)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: _green,
                ),
              ),
              const SizedBox(width: 6),
              const Text(
                'SERVER STATUS: OPTIMAL',
                style: TextStyle(
                  color: _textTertiary,
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  fontFamily: 'monospace',
                ),
              ),
              const SizedBox(width: 16),
              const Text(
                'LATENCY: 42ms',
                style: TextStyle(
                  color: _textTertiary,
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  fontFamily: 'monospace',
                ),
              ),
            ],
          ),
          Row(
            children: [
              Text(
                'UPNEXT: ${upNext.toUpperCase()}',
                style: const TextStyle(
                  color: _accent,
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  fontFamily: 'monospace',
                ),
              ),
              const SizedBox(width: 16),
              _TvClock(),
            ],
          ),
        ],
      ),
    );
  }
}

class _TvClock extends StatefulWidget {
  @override
  State<_TvClock> createState() => _TvClockState();
}

class _TvClockState extends State<_TvClock> {
  DateTime _now = DateTime.now();

  @override
  void initState() {
    super.initState();
    Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
  }

  @override
  Widget build(BuildContext context) {
    final h = _now.hour.toString().padLeft(2, '0');
    final m = _now.minute.toString().padLeft(2, '0');
    final s = _now.second.toString().padLeft(2, '0');
    return Text(
      '$h:$m:$s',
      style: const TextStyle(
        color: _textSecondary,
        fontSize: 11,
        fontWeight: FontWeight.w500,
        fontFamily: 'monospace',
      ),
    );
  }
}

// ── Favorite bento section ────────────────────────────────────────────────

class _FavoriteBentoSection extends StatelessWidget {
  final List<IptvChannel> favorites;
  final ValueChanged<IptvChannel> onPlay;
  final ValueChanged<IptvChannel> onEpg;

  const _FavoriteBentoSection({
    required this.favorites,
    required this.onPlay,
    required this.onEpg,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (final (i, ch) in favorites.indexed) ...[
          if (i > 0) const SizedBox(width: 20),
          Expanded(
            flex: i == 0 ? 2 : 1,
            child: _FavoriteBentoCard(
              channel: ch,
              hero: i == 0,
              onPlay: () => onPlay(ch),
              onEpg: () => onEpg(ch),
            ),
          ),
        ],
      ],
    );
  }
}

class _FavoriteBentoCard extends StatelessWidget {
  final IptvChannel channel;
  final bool hero;
  final VoidCallback onPlay;
  final VoidCallback onEpg;

  const _FavoriteBentoCard({
    required this.channel,
    required this.hero,
    required this.onPlay,
    required this.onEpg,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onPlay,
      onLongPress: onEpg,
      child: Container(
        height: hero ? 180 : 160,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [_surfaceLight, _surface],
          ),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: _textTertiary, width: 0.5),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _ChannelLogo(url: channel.logo, size: hero ? 56 : 44),
            const Spacer(),
Text(
                channel.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: _textPrimary,
                  fontWeight: FontWeight.bold,
                  fontSize: hero ? 18 : 15,
                ),
              ),
            if (channel.group != null) ...[
              const SizedBox(height: 2),
              Text(
                channel.group!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: _textTertiary, fontSize: 12),
              ),
            ],
            const SizedBox(height: 10),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: _accent,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Text(
                    '▶ PLAY',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  onPressed: onEpg,
                  icon: const Icon(Icons.more_horiz_rounded,
                      color: _textSecondary, size: 20),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ── Quick channels section ────────────────────────────────────────────────

// ── Quick Zap (circular quick-play row) ───────────────────────────────────

class _QuickZapRow extends StatelessWidget {
  final List<IptvChannel> allChannels;
  final ValueChanged<IptvChannel> onPlay;

  const _QuickZapRow({required this.allChannels, required this.onPlay});

  @override
  Widget build(BuildContext context) {
    final zaps = QuickChannelList.all.take(10).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionTitle('Quick Zap', icon: Icons.bolt_rounded),
        const SizedBox(height: 14),
        SizedBox(
          height: 96,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: zaps.length,
            separatorBuilder: (_, __) => const SizedBox(width: 18),
            itemBuilder: (context, index) {
              final qc = zaps[index];
              return _ZapCircle(
                quickChannel: qc,
                onTap: () => _resolveZap(context, qc, allChannels, onPlay),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _ZapCircle extends StatelessWidget {
  final QuickChannel quickChannel;
  final VoidCallback onTap;

  const _ZapCircle({required this.quickChannel, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final icon = _quickIcon(quickChannel);
    final color = quickChannel.tags.contains('premium') ? _gold : _accent;
    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: 72,
        child: Column(
          children: [
            _Glass(
              radius: 34,
              color: _surface,
              child: Container(
                width: 64,
                height: 64,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      color.withValues(alpha: 0.22),
                      color.withValues(alpha: 0.06),
                    ],
                  ),
                ),
                child: Icon(icon, color: color, size: 26),
              ),
            ),
            const SizedBox(height: 7),
            Text(
              quickChannel.displayName.toUpperCase(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: _textTertiary,
                fontSize: 9,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.6,
                fontFamily: 'monospace',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

IconData _quickIcon(QuickChannel qc) {
  if (qc.tags.contains('sports')) return Icons.sports_soccer_rounded;
  if (qc.tags.contains('news')) return Icons.public_rounded;
  if (qc.tags.contains('music')) return Icons.music_note_rounded;
  if (qc.tags.contains('kids')) return Icons.child_care_rounded;
  if (qc.tags.contains('movies')) return Icons.movie_rounded;
  if (qc.tags.contains('documentary')) return Icons.menu_book_rounded;
  if (qc.tags.contains('premium')) return Icons.workspace_premium_rounded;
  return Icons.live_tv_rounded;
}

Future<void> _resolveZap(
  BuildContext context,
  QuickChannel qc,
  List<IptvChannel> allChannels,
  ValueChanged<IptvChannel> onPlay,
) async {
  final matches = allChannels
      .where((ch) => QuickChannelList.matches(qc, ch))
      .toList();
  if (matches.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('No sources found for "${qc.displayName}"'),
        backgroundColor: _surfaceLight,
      ),
    );
    return;
  }
  // Prefer the first channel that the validation store believes is alive.
  final store = StreamValidationStore.instance;
  IptvChannel? best;
  for (final ch in matches) {
    if (store.isKnownAlive(ch.url)) {
      best = ch;
      break;
    }
  }
  onPlay(best ?? matches.first);
}

// ── Browse Bouquets (category bento) ──────────────────────────────────────

class _BouquetsGrid extends StatelessWidget {
  final IptvRepository repo;
  final IptvUiState state;

  const _BouquetsGrid({required this.repo, required this.state});

  @override
  Widget build(BuildContext context) {
    final categories = repo.getAllCategories();
    if (categories.isEmpty) return const SizedBox.shrink();
    final channels = repo.getAllChannels();

    final tiles = <_BouquetTileData>[
      for (final c in categories)
        _BouquetTileData(
          name: c,
          count: channels.where((ch) => ch.group == c).length,
          icon: _bouquetIcon(c),
          accent: _bouquetAccent(c),
        ),
    ];

    var featured = tiles.indexWhere((t) => _isSport(t.name));
    if (featured < 0) featured = 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionTitle('Browse Bouquets', icon: Icons.grid_view_rounded),
        const SizedBox(height: 14),
        LayoutBuilder(
          builder: (context, constraints) {
            final columns = constraints.maxWidth >= 1024 ? 4 : 2;
            const gap = 16.0;
            final baseW = (constraints.maxWidth - (columns - 1) * gap) / columns;
            final items = <Widget>[];
            for (var i = 0; i < tiles.length; i++) {
              final t = tiles[i];
              final isFeatured = i == featured && columns >= 4;
              items.add(
                SizedBox(
                  width: isFeatured ? baseW * 2 + gap : baseW,
                  height: 148,
                  child: _BouquetTile(
                    data: t,
                    selected: state.selectedCategory == t.name,
                    onTap: () => repo.selectCategory(
                      state.selectedCategory == t.name ? null : t.name,
                    ),
                  ),
                ),
              );
            }
            return Wrap(spacing: gap, runSpacing: gap, children: items);
          },
        ),
      ],
    );
  }
}

class _BouquetTileData {
  final String name;
  final int count;
  final IconData icon;
  final Color accent;

  const _BouquetTileData({
    required this.name,
    required this.count,
    required this.icon,
    required this.accent,
  });
}

class _BouquetTile extends StatelessWidget {
  final _BouquetTileData data;
  final bool selected;
  final VoidCallback onTap;

  const _BouquetTile({
    required this.data,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: _Glass(
        radius: 16,
        color: selected ? data.accent.withValues(alpha: 0.12) : _surfaceLight,
        child: Stack(
          children: [
            Positioned(
              top: -26,
              right: -26,
              child: Container(
                width: 130,
                height: 130,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      data.accent.withValues(alpha: 0.22),
                      data.accent.withValues(alpha: 0.0),
                    ],
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 34,
                        height: 34,
                        decoration: BoxDecoration(
                          color: data.accent.withValues(alpha: 0.16),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        alignment: Alignment.center,
                        child: Icon(data.icon, color: data.accent, size: 18),
                      ),
                      const Spacer(),
                      if (selected)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: _cyan.withValues(alpha: 0.16),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: _cyan.withValues(alpha: 0.5),
                              width: 0.6,
                            ),
                          ),
                          child: const Text(
                            'ACTIVE',
                            style: TextStyle(
                              color: _cyan,
                              fontSize: 9,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 1,
                              fontFamily: 'monospace',
                            ),
                          ),
                        )
                      else
                        Text(
                          '${data.count}',
                          style: const TextStyle(
                            color: _textTertiary,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            fontFamily: 'monospace',
                          ),
                        ),
                    ],
                  ),
                  const Spacer(),
                  Text(
                    data.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: _textPrimary,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.2,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '${data.count} CHANNELS',
                    style: const TextStyle(
                      color: _textTertiary,
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1,
                      fontFamily: 'monospace',
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

bool _isSport(String name) {
  final n = name.toLowerCase();
  return n.contains('sport') ||
      n.contains('espn') ||
      n.contains('nba') ||
      n.contains('nfl') ||
      n.contains('mlb') ||
      n.contains('nhl') ||
      n.contains('soccer') ||
      n.contains('box');
}

IconData _bouquetIcon(String name) {
  final n = name.toLowerCase();
  if (_isSport(n)) return Icons.sports_soccer_rounded;
  if (n.contains('news')) return Icons.public_rounded;
  if (n.contains('movie') || n.contains('cinema') || n.contains('film'))
    return Icons.movie_rounded;
  if (n.contains('kid') || n.contains('cartoon')) return Icons.child_care_rounded;
  if (n.contains('music')) return Icons.music_note_rounded;
  if (n.contains('doc')) return Icons.menu_book_rounded;
  if (n.contains('entertain')) return Icons.stars_rounded;
  if (n.contains('premium')) return Icons.workspace_premium_rounded;
  if (n.contains('shop')) return Icons.shopping_bag_rounded;
  if (n.contains('local') || n.contains('region')) return Icons.location_city_rounded;
  if (n.contains('religion') || n.contains('faith')) return Icons.church_rounded;
  return Icons.live_tv_rounded;
}

Color _bouquetAccent(String name) {
  final n = name.toLowerCase();
  if (n.contains('kid') || n.contains('music') || n.contains('cartoon'))
    return _gold;
  if (n.contains('sport') || n.contains('news')) return _cyan;
  return _accent;
}

// ── Channel grid (recommended) ────────────────────────────────────────────

class _ChannelGrid extends StatelessWidget {
  final List<IptvChannel> channels;
  final Set<String> favorites;
  final ValueChanged<IptvChannel> onPlay;
  final ValueChanged<IptvChannel> onPicker;
  final ValueChanged<IptvChannel> onEpg;
  final ValueChanged<String> onToggleFavorite;

  const _ChannelGrid({
    required this.channels,
    required this.favorites,
    required this.onPlay,
    required this.onPicker,
    required this.onEpg,
    required this.onToggleFavorite,
  });

  @override
  Widget build(BuildContext context) {
    if (channels.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(
          child: Text(
            'No channels match. Add a playlist or clear filters.',
            style: TextStyle(color: _textTertiary, fontSize: 14),
          ),
        ),
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns =
            (constraints.maxWidth / 260).floor().clamp(2, 6);
        final rows = (channels.length / columns).ceil();
        return SizedBox(
          height: rows * 150.0,
          child: GridView.builder(
            physics: const NeverScrollableScrollPhysics(),
            padding: EdgeInsets.zero,
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: columns,
              crossAxisSpacing: 16,
              mainAxisSpacing: 16,
              childAspectRatio: 1.9,
            ),
            itemCount: channels.length,
            itemBuilder: (context, index) {
              final ch = channels[index];
              return _ChannelCard(
                channel: ch,
                isFavorite: favorites.contains(ch.id),
                onPlay: () => onPlay(ch),
                onPicker: () => onPicker(ch),
                onEpg: () => onEpg(ch),
                onToggleFavorite: () => onToggleFavorite(ch.id),
              );
            },
          ),
        );
      },
    );
  }
}

class _ChannelCard extends StatelessWidget {
  final IptvChannel channel;
  final bool isFavorite;
  final VoidCallback onPlay;
  final VoidCallback onPicker;
  final VoidCallback onEpg;
  final VoidCallback onToggleFavorite;

  const _ChannelCard({
    required this.channel,
    required this.isFavorite,
    required this.onPlay,
    required this.onPicker,
    required this.onEpg,
    required this.onToggleFavorite,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _surfaceLight,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _textTertiary, width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _ChannelLogo(url: channel.logo, size: 36),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  channel.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: _textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              GestureDetector(
                onTap: onToggleFavorite,
                child: Icon(
                  isFavorite
                      ? Icons.favorite_rounded
                      : Icons.favorite_border_rounded,
                  color: isFavorite ? _gold : _textTertiary,
                  size: 20,
                ),
              ),
            ],
          ),
          const Spacer(),
          Row(
            children: [
              GestureDetector(
                onTap: onPlay,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: _accent,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Text(
                    '▶ Play',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              IconButton(
                onPressed: onEpg,
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.info_outline_rounded,
                    color: _textSecondary, size: 18),
              ),
              IconButton(
                onPressed: onPicker,
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.grid_view_rounded,
                    color: _textSecondary, size: 18),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── History section ───────────────────────────────────────────────────────

class _HistorySection extends StatelessWidget {
  final List<IptvChannel> history;
  final ValueChanged<IptvChannel> onPlay;
  final VoidCallback onClear;

  const _HistorySection({
    required this.history,
    required this.onPlay,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Recently Watched',
              style: TextStyle(
                color: _accent,
                fontWeight: FontWeight.w600,
                fontSize: 20,
              ),
            ),
            GestureDetector(
              onTap: onClear,
              child: const Text(
                '✕ Clear',
                style: TextStyle(color: _textTertiary, fontSize: 13),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 120,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: history.length,
            separatorBuilder: (_, __) => const SizedBox(width: 12),
            itemBuilder: (context, index) {
              final ch = history[index];
              return GestureDetector(
                onTap: () => onPlay(ch),
                child: Container(
                  width: 200,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: _surfaceLight,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: _textTertiary,
                      width: 0.5,
                    ),
                  ),
                  child: Row(
                    children: [
                      _ChannelLogo(url: ch.logo, size: 40),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              ch.name,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: _textPrimary,
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 4),
                            const Icon(Icons.play_circle_fill_rounded,
                                color: _accent, size: 18),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

// ── Live Now hero ─────────────────────────────────────────────────────────

/// Cinematic "Live Now" banner pinned at the top of the feed. Shows the top
/// live/upcoming ESPN event with a full-screen-ready Watch pill, or a branded
/// fallback when there's nothing airing.
class _LiveHero extends StatelessWidget {
  final EspnProcessedEvent? event;
  final bool loading;
  final ValueChanged<IptvChannel> onPlay;
  final VoidCallback onRetry;

  const _LiveHero({
    required this.event,
    required this.loading,
    required this.onPlay,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final isTv = MediaQuery.sizeOf(context).width >= 1024;
    final aspect = isTv ? 21.0 / 9.0 : 16.0 / 9.0;

    if (loading) {
      return AspectRatio(
        aspectRatio: aspect,
        child: _Glass(
          color: _surfaceLowest,
          child: const Center(
            child: CircularProgressIndicator(color: _accent, strokeWidth: 2),
          ),
        ),
      );
    }

    final ev = event;
    if (ev == null) {
      return AspectRatio(
        aspectRatio: aspect,
        child: _fallbackBanner(isTv),
      );
    }

    return AspectRatio(
      aspectRatio: aspect,
      child: GestureDetector(
        onTap: () => _openSportMatches(context, ev, onPlay),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (ev.eventImage != null)
                CachedNetworkImage(
                  imageUrl: ev.eventImage!,
                  fit: BoxFit.cover,
                  errorWidget: (_, __, ___) => const ColoredBox(color: _surfaceLowest),
                )
              else
                const ColoredBox(color: _surfaceLowest),
              // Cinematic scrims for legibility.
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.black54, Colors.transparent, Colors.black87],
                    stops: [0.0, 0.4, 1.0],
                  ),
                ),
              ),
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                    colors: [Colors.black54, Colors.transparent, Colors.black38],
                  ),
                ),
              ),
              // Top row: badges.
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _HeroBadge(
                      label: ev.isLive ? 'LIVE' : 'UPCOMING',
                      color: ev.isLive ? _red : _cyan,
                      dot: ev.isLive,
                    ),
                    const SizedBox(width: 8),
                    if (ev.isPpv)
                      const _HeroBadge(label: 'VIP', color: _gold),
                    const Spacer(),
                    if (isTv)
                      _Glass(
                        radius: 20,
                        color: _surface,
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        child: Text(
                          ev.league.toUpperCase(),
                          style: const TextStyle(
                            color: _textSecondary,
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1.4,
                            fontFamily: 'monospace',
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              // Bottom row: matchup + score + watch.
              Positioned(
                left: 16,
                right: 16,
                bottom: 14,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            ev.homeTeam,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: _textPrimary,
                              fontSize: 22,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.5,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'vs ${ev.awayTeam}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: _textSecondary,
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            ev.isLive
                                ? ev.detail.isEmpty ? ev.league : ev.detail
                                : (ev.timeStr ?? ev.status),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: _textTertiary,
                              fontSize: 12,
                              fontFamily: 'monospace',
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (ev.homeScore != null && ev.awayScore != null) ...[
                      const SizedBox(width: 12),
                      _HeroScorePanel(
                        home: ev.homeTeam,
                        away: ev.awayTeam,
                        homeScore: ev.homeScore!,
                        awayScore: ev.awayScore!,
                        homeLogo: ev.homeLogo,
                        awayLogo: ev.awayLogo,
                      ),
                    ],
                    const SizedBox(width: 12),
                    _HeroWatchButton(
                      onTap: () => _openSportMatches(context, ev, onPlay),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _fallbackBanner(bool isTv) {
    return _Glass(
      color: _surfaceLowest,
      child: Stack(
        fit: StackFit.expand,
        children: [
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0x337C5CFF), Colors.transparent],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Row(
              children: [
                const Icon(Icons.sports_rounded, color: _accent, size: 40),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'IPTVNutz Live',
                        style: TextStyle(
                          color: _textPrimary,
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.5,
                        ),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'Catch every game live. Browse channels to start watching.',
                        style: TextStyle(color: _textSecondary, fontSize: 13),
                      ),
                      const SizedBox(height: 10),
                      _HeroBadge(
                        label: 'REFRESH',
                        color: _cyan,
                        onTap: onRetry,
                      ),
                    ],
                  ),
                ),
                if (isTv)
                  _HeroWatchButton(
                    label: 'BROWSE',
                    onTap: () {},
                    emphasized: false,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _HeroBadge extends StatelessWidget {
  final String label;
  final Color color;
  final bool dot;
  final VoidCallback? onTap;

  const _HeroBadge({
    required this.label,
    required this.color,
    this.dot = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final pill = Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.6), width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (dot) ...[
            _PulseDot(color: color),
            const SizedBox(width: 6),
          ],
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 10,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.2,
              fontFamily: 'monospace',
            ),
          ),
        ],
      ),
    );
    if (onTap == null) return pill;
    return GestureDetector(onTap: onTap, child: pill);
  }
}

class _PulseDot extends StatefulWidget {
  final Color color;

  const _PulseDot({required this.color});

  @override
  State<_PulseDot> createState() => _PulseDotState();
}

class _PulseDotState extends State<_PulseDot> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: Tween(begin: 1.0, end: 0.25).animate(_controller),
      child: Container(
        width: 7,
        height: 7,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: widget.color,
          boxShadow: [
            BoxShadow(
              color: widget.color.withValues(alpha: 0.8),
              blurRadius: 6,
            ),
          ],
        ),
      ),
    );
  }
}

class _HeroScorePanel extends StatelessWidget {
  final String home;
  final String away;
  final String homeScore;
  final String awayScore;
  final String? homeLogo;
  final String? awayLogo;

  const _HeroScorePanel({
    required this.home,
    required this.away,
    required this.homeScore,
    required this.awayScore,
    this.homeLogo,
    this.awayLogo,
  });

  @override
  Widget build(BuildContext context) {
    return _Glass(
      radius: 14,
      color: _surface,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _team(home, homeScore, homeLogo),
          Container(width: 1, height: 26, color: const Color(0x33FFFFFF)),
          const SizedBox(width: 8),
          _team(away, awayScore, awayLogo),
        ],
      ),
    );
  }

  Widget _team(String name, String score, String? logo) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 26,
          height: 26,
          child: _ChannelLogo(url: logo, size: 26),
        ),
        const SizedBox(width: 6),
        Text(
          score,
          style: const TextStyle(
            color: _textPrimary,
            fontSize: 18,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }
}

class _HeroWatchButton extends StatelessWidget {
  final VoidCallback onTap;
  final String label;
  final bool emphasized;

  const _HeroWatchButton({
    required this.onTap,
    this.label = 'WATCH',
    this.emphasized = true,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        decoration: BoxDecoration(
          gradient: emphasized
              ? const LinearGradient(
                  colors: [_accent, Color(0xFF9A7BFF)],
                )
              : null,
          color: emphasized ? null : _surface,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: emphasized
                ? Colors.white.withValues(alpha: 0.25)
                : const Color(0x33FFFFFF),
            width: 0.6,
          ),
          boxShadow: emphasized
              ? [
                  BoxShadow(
                    color: _accent.withValues(alpha: 0.45),
                    blurRadius: 20,
                    offset: const Offset(0, 6),
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.play_arrow_rounded,
                color: emphasized ? Colors.white : _cyan, size: 20),
            const SizedBox(width: 6),
            Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w800,
                letterSpacing: 1,
                fontFamily: 'monospace',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Live Sports panel (ESPN extra) ────────────────────────────────────────

class _LiveSportsPanel extends StatelessWidget {
  final List<EspnProcessedEvent> events;
  final bool loading;
  final String? error;
  final VoidCallback onRetry;
  final ValueChanged<IptvChannel> onPlay;

  const _LiveSportsPanel({
    required this.events,
    required this.loading,
    required this.error,
    required this.onRetry,
    required this.onPlay,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const _SectionTitle('Live Sports', icon: Icons.sports_rounded),
            const SizedBox(width: 8),
            IconButton(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded,
                  color: _textTertiary, size: 18),
            ),
          ],
        ),
        const SizedBox(height: 10),
        if (loading)
          const Center(
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: CircularProgressIndicator(
                color: _accent,
                strokeWidth: 2,
              ),
            ),
          )
        else if (error != null && events.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Column(
              children: [
                Text(error!, style: const TextStyle(color: _textTertiary, fontSize: 13)),
                const SizedBox(height: 12),
                _Chip(label: 'Retry', selected: false, onTap: onRetry),
              ],
            ),
          )
        else if (events.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(
              child: Text(
                'No live sports right now. Check back soon!',
                style: TextStyle(color: _textTertiary, fontSize: 14),
              ),
            ),
          )
        else
          SizedBox(
            height: 200,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: events.length,
              separatorBuilder: (_, __) => const SizedBox(width: 12),
              itemBuilder: (context, index) {
                final event = events[index];
                return _SportEventCard(
                  event: event,
                  onFind: () => _openSportMatches(context, event, onPlay),
                );
              },
            ),
          ),
      ],
    );
  }
}

/// Shared "find channels airing this game" flow used by the live hero and the
/// sports panel: match against the channel catalogue (EPG-aware), then either
/// play the single match, or present the matches sheet.
Future<void> _openSportMatches(
  BuildContext context,
  EspnProcessedEvent event,
  ValueChanged<IptvChannel> onPlay,
) async {
  final channels = IptvRepository.instance.getAllChannels();
  if (channels.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Add an IPTV source first to match channels'),
        backgroundColor: _surfaceLight,
      ),
    );
    return;
  }
  // Optimistic fast pass, then lazily enrich with EPG.
  final epgTitles = IptvRepository.instance.buildCurrentEpgTitleMap();
  final matches = await EspnClient.findScoredMatchingChannelsWithLazyEpg(
    SportEvent(
      idEvent: event.id,
      strEvent: event.title,
      strSport: event.sport,
      strLeague: event.league,
      strHomeTeam: event.homeTeam,
      strAwayTeam: event.awayTeam,
      strDate: event.rawDate ?? event.date,
      strTime: event.timeStr ?? '',
      strThumb: event.eventImage,
      strChannel: event.channel,
      intHomeScore: event.homeScore,
      intAwayScore: event.awayScore,
      strStatus: event.status,
    ),
    channels,
    currentEpgTitleFor: (name) => epgTitles[name] ?? '',
    cap: 6,
  );
  if (!context.mounted) return;
  if (matches.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('No channel match found for ${event.title}'),
        backgroundColor: _surfaceLight,
      ),
    );
    return;
  }
  if (matches.length == 1) {
    onPlay(matches.first.channel);
    return;
  }
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black54,
    builder: (_) => _SportMatchesSheet(
      event: event,
      matches: matches,
      onPlay: onPlay,
    ),
  );
}

class _SportEventCard extends StatelessWidget {
  final EspnProcessedEvent event;
  final VoidCallback onFind;

  const _SportEventCard({required this.event, required this.onFind});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 260,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _surfaceLight,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _textTertiary, width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: event.isLive ? _red : _gold,
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  event.league.toUpperCase(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: event.isLive ? _red : _textSecondary,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            '${event.homeTeam} vs ${event.awayTeam}',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: _textPrimary,
              fontWeight: FontWeight.bold,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 4),
          if (event.homeScore != null && event.awayScore != null)
            Text(
              '${event.homeScore} - ${event.awayScore}',
              style: const TextStyle(color: _gold, fontSize: 13),
            ),
          const SizedBox(height: 8),
          Text(
            event.isLive ? 'LIVE' : (event.timeStr ?? event.status),
            style: TextStyle(
              color: event.isLive ? _red : _textTertiary,
              fontSize: 11,
            ),
          ),
          const Spacer(),
          GestureDetector(
            onTap: onFind,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 8),
              decoration: BoxDecoration(
                color: _accent,
                borderRadius: BorderRadius.circular(10),
              ),
              alignment: Alignment.center,
              child: const Text(
                'Match Channels',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SportMatchesSheet extends StatelessWidget {
  final EspnProcessedEvent event;
  final List<ChannelScore> matches;
  final ValueChanged<IptvChannel> onPlay;

  const _SportMatchesSheet({
    required this.event,
    required this.matches,
    required this.onPlay,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        decoration: const BoxDecoration(
          color: _bg,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          border: Border(top: BorderSide(color: Colors.white12, width: 0.6)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${event.homeTeam} vs ${event.awayTeam}',
              style: const TextStyle(
                color: _textPrimary,
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
            Text(
              '${event.league} · ${matches.length} matches',
              style: const TextStyle(color: _textTertiary, fontSize: 12),
            ),
            const SizedBox(height: 12),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 360),
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: matches.length,
                separatorBuilder: (_, __) => const SizedBox(height: 6),
                itemBuilder: (context, index) {
                  final m = matches[index];
                  final ch = m.channel;
                  return GestureDetector(
                    onTap: () {
                      Navigator.of(context).pop();
                      onPlay(ch);
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: _surfaceLight,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        children: [
                          _ChannelLogo(url: ch.logo, size: 32),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  ch.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: _textPrimary,
                                    fontSize: 14,
                                  ),
                                ),
                                if (ch.group != null)
                                  Text(
                                    ch.group!,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: _textTertiary,
                                      fontSize: 10,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0x337C5CFF),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              '${m.score}%',
                              style: const TextStyle(
                                color: _accent,
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          const Icon(Icons.play_circle_fill_rounded,
                              color: _accent, size: 22),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Playlists section ─────────────────────────────────────────────────────

class _PlaylistsSection extends StatelessWidget {
  final IptvUiState state;
  final IptvRepository repo;
  final VoidCallback onAddClick;

  const _PlaylistsSection({
    required this.state,
    required this.repo,
    required this.onAddClick,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text(
              'Playlists & Sources',
              style: TextStyle(
                color: _accent,
                fontWeight: FontWeight.w600,
                fontSize: 20,
              ),
            ),
            const Spacer(),
            _Chip(label: '+ Add', selected: true, onTap: onAddClick),
          ],
        ),
        const SizedBox(height: 12),
        if (state.epgLoading)
          const Padding(
            padding: EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    color: _accent,
                    strokeWidth: 2,
                  ),
                ),
                SizedBox(width: 8),
                Text('Updating EPG...',
                    style: TextStyle(color: _textTertiary, fontSize: 12)),
              ],
            ),
          ),
        if (state.epgError != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(state.epgError!,
                style: const TextStyle(color: _red, fontSize: 12)),
          ),
        if (state.m3uPlaylists.isEmpty &&
            state.xtreamAccounts.isEmpty &&
            state.stalkerAccounts.isEmpty)
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: _surfaceLight,
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Center(
              child: Text(
                'No sources yet. Add an M3U playlist, Xtream code, or Stalker portal.',
                style: TextStyle(color: _textTertiary, fontSize: 13),
              ),
            ),
          )
        else
          Column(
            children: [
              for (final p in state.m3uPlaylists)
                _PlaylistCard(
                  name: p.name,
                  count: p.channels.length,
                  refreshing: state.refreshingSourceIds.contains(p.id),
                  onRefresh: () => repo.refreshM3uChannels(p.id),
                  onDelete: () => repo.removeM3uPlaylist(p.id),
                  onValidate: () => StreamValidationController.scanSource(
                    p.channels,
                  ),
                ),
              for (final a in state.xtreamAccounts)
                _PlaylistCard(
                  name: a.name,
                  subtitle: '${a.categories.length} categories',
                  count: a.channels.length,
                  refreshing: state.refreshingSourceIds.contains(a.id),
                  onRefresh: () => repo.refreshXtreamChannels(a.id),
                  onDelete: () => repo.removeXtreamAccount(a.id),
                  onValidate: () => StreamValidationController.scanSource(
                    a.channels,
                  ),
                ),
              for (final s in state.stalkerAccounts)
                _PlaylistCard(
                  name: s.name,
                  subtitle: s.server,
                  count: s.channels.length,
                  refreshing: state.refreshingSourceIds.contains(s.id),
                  onRefresh: () => repo.refreshStalkerChannels(s.id),
                  onDelete: () => repo.removeStalkerAccount(s.id),
                  onValidate: () => StreamValidationController.scanSource(
                    s.channels,
                  ),
                ),
              if (state.epgSources.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Row(
                    children: [
                      const Icon(Icons.calendar_month_rounded,
                          color: _textTertiary, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '${state.epgSources.length} EPG source(s) · '
                          '${state.epgMatchCount} channels matched',
                          style: const TextStyle(
                            color: _textTertiary,
                            fontSize: 12,
                          ),
                        ),
                      ),
                      _Chip(
                        label: 'Refresh EPG',
                        selected: false,
                        onTap: () => repo.refreshEpg(),
                      ),
                    ],
                  ),
                ),
            ],
          ),
      ],
    );
  }
}

class _PlaylistCard extends StatelessWidget {
  final String name;
  final String? subtitle;
  final int count;
  final bool refreshing;
  final VoidCallback onRefresh;
  final VoidCallback onDelete;
  final VoidCallback onValidate;

  const _PlaylistCard({
    required this.name,
    this.subtitle,
    required this.count,
    required this.refreshing,
    required this.onRefresh,
    required this.onDelete,
    required this.onValidate,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: _surfaceLight,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _textTertiary, width: 0.5),
      ),
      child: Row(
        children: [
          const Icon(Icons.playlist_play_rounded, color: _accent, size: 26),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: _textPrimary,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
                if (subtitle != null)
                  Text(
                    subtitle!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: _textTertiary,
                      fontSize: 11,
                    ),
                  ),
                Text(
                  '$count channels',
                  style: const TextStyle(
                    color: _textSecondary,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          if (refreshing)
            const Padding(
              padding: EdgeInsets.all(6),
              child: SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(
                  color: _accent,
                  strokeWidth: 2,
                ),
              ),
            )
          else ...[
            IconButton(
              onPressed: onValidate,
              icon: const Icon(Icons.fact_check_rounded,
                  color: _textSecondary, size: 20),
              tooltip: 'Validate streams',
            ),
            IconButton(
              onPressed: onRefresh,
              icon: const Icon(Icons.refresh_rounded,
                  color: _textSecondary, size: 20),
              tooltip: 'Refresh',
            ),
            IconButton(
              onPressed: onDelete,
              icon: const Icon(Icons.delete_outline_rounded,
                  color: _red, size: 20),
              tooltip: 'Delete',
            ),
          ],
        ],
      ),
    );
  }
}

// ── Mobile layout ─────────────────────────────────────────────────────────

class _MobileLayout extends StatefulWidget {
  final IptvUiState state;
  final IptvRepository repo;
  final bool showSearch;
  final VoidCallback onToggleSearch;
  final ValueChanged<IptvChannel> onPlay;
  final VoidCallback onAddSource;
  final ValueChanged<IptvChannel> onPicker;
  final ValueChanged<IptvChannel> onEpg;
  final List<EspnProcessedEvent> sportsEvents;
  final bool sportsLoading;
  final String? sportsError;
  final VoidCallback onRetrySports;

  const _MobileLayout({
    required this.state,
    required this.repo,
    required this.showSearch,
    required this.onToggleSearch,
    required this.onPlay,
    required this.onAddSource,
    required this.onPicker,
    required this.onEpg,
    required this.sportsEvents,
    required this.sportsLoading,
    required this.sportsError,
    required this.onRetrySports,
  });

  @override
  State<_MobileLayout> createState() => _MobileLayoutState();
}

class _MobileLayoutState extends State<_MobileLayout> {
  final ScrollController _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final repo = widget.repo;
    final favorites = repo.getFavoriteChannels();
    final history = repo.getHistoryChannels();
    final filtered = repo.getLastFilteredChannels();
    final heroEvent =
        widget.sportsEvents.isEmpty ? null : widget.sportsEvents.first;

    return Container(
      color: _bg,
      child: Column(
        children: [
          _TopBar(
            showSearch: widget.showSearch,
            searchQuery: state.searchQuery,
            onSearchChanged: repo.setSearchQuery,
            onToggleSearch: widget.onToggleSearch,
            onAddSource: widget.onAddSource,
          ),
          Expanded(
            child: ListView(
              controller: _scroll,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              children: [
                _LiveHero(
                  event: heroEvent,
                  loading: widget.sportsLoading,
                  onPlay: widget.onPlay,
                  onRetry: widget.onRetrySports,
                ),
                const SizedBox(height: 20),
                _QuickZapRow(
                  allChannels: repo.getAllChannels(),
                  onPlay: widget.onPlay,
                ),
                const SizedBox(height: 20),
                _BouquetsGrid(repo: repo, state: state),
                const SizedBox(height: 20),
                if (state.error != null) ...[
                  _ErrorBanner(error: state.error!),
                  const SizedBox(height: 12),
                ],
                if (state.isLoading)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 20),
                    child: Center(
                      child: CircularProgressIndicator(
                        color: _accent,
                        strokeWidth: 2,
                      ),
                    ),
                  ),
                _SourceChipsRow(repo: repo, state: state),
                const SizedBox(height: 10),
                _CategoryChipsRow(repo: repo, state: state),
                const SizedBox(height: 16),
                if (favorites.isNotEmpty) ...[
                  _MobileFavoritesRow(
                    favorites: favorites.take(6).toList(),
                    onPlay: widget.onPlay,
                  ),
                  const SizedBox(height: 16),
                ],
                if (history.isNotEmpty) ...[
                  _HistorySection(
                    history: history.take(8).toList(),
                    onPlay: widget.onPlay,
                    onClear: repo.clearHistory,
                  ),
                  const SizedBox(height: 16),
                ],
                _LiveSportsPanel(
                  events: widget.sportsEvents,
                  loading: widget.sportsLoading,
                  error: widget.sportsError,
                  onRetry: widget.onRetrySports,
                  onPlay: widget.onPlay,
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    const Text(
                      'Channels',
                      style: TextStyle(
                        color: _accent,
                        fontWeight: FontWeight.w600,
                        fontSize: 18,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      '${filtered.length}',
                      style: const TextStyle(
                        color: _textTertiary,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                _ChannelList(
                  channels: filtered,
                  favorites: state.favoriteChannelIds.toSet(),
                  onPlay: widget.onPlay,
                  onPicker: widget.onPicker,
                  onEpg: widget.onEpg,
                  onToggleFavorite: repo.toggleFavorite,
                ),
                const SizedBox(height: 20),
                _PlaylistsSection(
                  state: state,
                  repo: repo,
                  onAddClick: widget.onAddSource,
                ),
                const SizedBox(height: 90),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MobileFavoritesRow extends StatelessWidget {
  final List<IptvChannel> favorites;
  final ValueChanged<IptvChannel> onPlay;

  const _MobileFavoritesRow({
    required this.favorites,
    required this.onPlay,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Favorites',
          style: TextStyle(
            color: _gold,
            fontWeight: FontWeight.w700,
            fontSize: 18,
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 120,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: favorites.length,
            separatorBuilder: (_, __) => const SizedBox(width: 10),
            itemBuilder: (context, index) {
              final ch = favorites[index];
              return GestureDetector(
                onTap: () => onPlay(ch),
                child: Container(
                  width: 160,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: _surfaceLight,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: _textTertiary,
                      width: 0.5,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _ChannelLogo(url: ch.logo, size: 36),
                      const Spacer(),
                      Text(
                        ch.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: _textPrimary,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _ChannelList extends StatelessWidget {
  final List<IptvChannel> channels;
  final Set<String> favorites;
  final ValueChanged<IptvChannel> onPlay;
  final ValueChanged<IptvChannel> onPicker;
  final ValueChanged<IptvChannel> onEpg;
  final ValueChanged<String> onToggleFavorite;

  const _ChannelList({
    required this.channels,
    required this.favorites,
    required this.onPlay,
    required this.onPicker,
    required this.onEpg,
    required this.onToggleFavorite,
  });

  @override
  Widget build(BuildContext context) {
    if (channels.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 20),
        child: Center(
          child: Text(
            'No channels match. Add a source or clear filters.',
            style: TextStyle(color: _textTertiary, fontSize: 13),
          ),
        ),
      );
    }
    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: channels.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final ch = channels[index];
        return _MobileChannelRow(
          channel: ch,
          isFavorite: favorites.contains(ch.id),
          onPlay: () => onPlay(ch),
          onPicker: () => onPicker(ch),
          onEpg: () => onEpg(ch),
          onToggleFavorite: () => onToggleFavorite(ch.id),
        );
      },
    );
  }
}

class _MobileChannelRow extends StatelessWidget {
  final IptvChannel channel;
  final bool isFavorite;
  final VoidCallback onPlay;
  final VoidCallback onPicker;
  final VoidCallback onEpg;
  final VoidCallback onToggleFavorite;

  const _MobileChannelRow({
    required this.channel,
    required this.isFavorite,
    required this.onPlay,
    required this.onPicker,
    required this.onEpg,
    required this.onToggleFavorite,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: _surfaceLight,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _textTertiary, width: 0.5),
      ),
      child: Row(
        children: [
          _ChannelLogo(url: channel.logo, size: 38),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  channel.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: _textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (channel.group != null)
                  Text(
                    channel.group!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: _textTertiary,
                      fontSize: 11,
                    ),
                  ),
              ],
            ),
          ),
          IconButton(
            onPressed: onToggleFavorite,
            visualDensity: VisualDensity.compact,
            icon: Icon(
              isFavorite
                  ? Icons.favorite_rounded
                  : Icons.favorite_border_rounded,
              color: isFavorite ? _gold : _textTertiary,
              size: 20,
            ),
          ),
          IconButton(
            onPressed: onEpg,
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.info_outline_rounded,
                color: _textSecondary, size: 20),
          ),
          IconButton(
            onPressed: onPicker,
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.grid_view_rounded,
                color: _textSecondary, size: 20),
          ),
          GestureDetector(
            onTap: onPlay,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: _accent,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Text(
                '▶',
                style: TextStyle(color: Colors.white, fontSize: 13),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── EPG sheet ─────────────────────────────────────────────────────────────

class _EpgSheet extends StatefulWidget {
  final IptvChannel channel;
  final IptvRepository repo;
  final VoidCallback onDismiss;

  const _EpgSheet({
    required this.channel,
    required this.repo,
    required this.onDismiss,
  });

  @override
  State<_EpgSheet> createState() => _EpgSheetState();
}

class _EpgSheetState extends State<_EpgSheet> {
  List<EpgProgram>? _programs;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final programs = await widget.repo.getEpgProgramsForChannel(
        widget.channel,
      );
      if (!mounted) return;
      setState(() => _programs = programs);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onDismiss,
      child: Container(
        color: Colors.black54,
        child: Align(
          alignment: Alignment.bottomCenter,
          child: GestureDetector(
            onTap: () {},
            child: Container(
              width: double.infinity,
              constraints: const BoxConstraints(maxHeight: 400),
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
              decoration: const BoxDecoration(
                color: _bg,
                borderRadius: BorderRadius.vertical(
                  top: Radius.circular(24),
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      _ChannelLogo(url: widget.channel.logo, size: 36),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          widget.channel.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: _textPrimary,
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                      ),
                      GestureDetector(
                        onTap: widget.onDismiss,
                        child: const Icon(Icons.close_rounded,
                            color: _textTertiary, size: 22),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (_error != null)
                    Text(_error!,
                        style: const TextStyle(color: _red, fontSize: 13))
                  else if (_programs == null)
                    const Center(
                      child: Padding(
                        padding: EdgeInsets.all(24),
                        child: CircularProgressIndicator(
                          color: _accent,
                          strokeWidth: 2,
                        ),
                      ),
                    )
                  else if (_programs!.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(24),
                      child: Center(
                        child: Text(
                          'No EPG data for this channel',
                          style: TextStyle(
                            color: _textTertiary,
                            fontSize: 14,
                          ),
                        ),
                      ),
                    )
                  else
                    Flexible(
                      child: ListView.separated(
                        shrinkWrap: true,
                        itemCount: _programs!.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 6),
                        itemBuilder: (context, index) {
                          final p = _programs![index];
                          final isNow = p.isNow;
                          return Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 10,
                            ),
                            decoration: BoxDecoration(
                              color: isNow
                                  ? const Color(0x337C5CFF)
                                  : _surfaceLight,
                              borderRadius: BorderRadius.circular(10),
                              border: isNow
                                  ? Border.all(
                                      color: _accent,
                                      width: 1,
                                    )
                                  : null,
                            ),
                            child: Row(
                              children: [
                                Text(
                                  _fmtTime(p.startTime),
                                  style: TextStyle(
                                    color: isNow ? _accent : _textTertiary,
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    fontFamily: 'monospace',
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        p.title,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          color: _textPrimary,
                                          fontSize: 13,
                                          fontWeight: isNow
                                              ? FontWeight.bold
                                              : FontWeight.w500,
                                        ),
                                      ),
                                      if (p.description != null &&
                                          p.description!.isNotEmpty)
                                        Text(
                                          p.description!,
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            color: _textTertiary,
                                            fontSize: 11,
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                                if (isNow)
                                  const Text(
                                    'NOW',
                                    style: TextStyle(
                                      color: _accent,
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                              ],
                            ),
                          );
                        },
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

  String _fmtTime(DateTime t) {
    final h = t.hour.toString().padLeft(2, '0');
    final m = t.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }
}

// ── Add source sheet ──────────────────────────────────────────────────────

class _AddSourceSheet extends StatefulWidget {
  final IptvRepository repo;

  const _AddSourceSheet({required this.repo});

  @override
  State<_AddSourceSheet> createState() => _AddSourceSheetState();
}

class _AddSourceSheetState extends State<_AddSourceSheet> {
  int _tab = 0;
  bool _busy = false;
  String? _error;

  final _nameCtrl = TextEditingController();
  final _urlCtrl = TextEditingController();
  final _serverCtrl = TextEditingController();
  final _userCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  final _macCtrl = TextEditingController();

  bool _englishOnly = true;
  bool _noAdult = true;
  bool _sportsOnly = false;
  bool _scraping = false;
  String _scrapeStatus = '';
  String? _scrapeError;
  List<PortalNutzEntry> _results = [];

  @override
  void dispose() {
    _nameCtrl.dispose();
    _urlCtrl.dispose();
    _serverCtrl.dispose();
    _userCtrl.dispose();
    _passCtrl.dispose();
    _macCtrl.dispose();
    PortalNutzScraper.cancel();
    super.dispose();
  }

  Future<void> _submit() async {
    final navigator = Navigator.of(context);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      switch (_tab) {
        case 0:
          final name = _nameCtrl.text.trim();
          final url = _urlCtrl.text.trim();
          if (name.isEmpty || url.isEmpty) {
            throw Exception('Name and URL are required');
          }
          await widget.repo.addM3uPlaylist(name, url);
        case 1:
          final name = _nameCtrl.text.trim();
          final server = _serverCtrl.text.trim();
          final user = _userCtrl.text.trim();
          final pass = _passCtrl.text.trim();
          if (name.isEmpty ||
              server.isEmpty ||
              user.isEmpty ||
              pass.isEmpty) {
            throw Exception('All Xtream fields are required');
          }
          await widget.repo.addXtreamAccount(name, server, user, pass);
        case 2:
          final name = _nameCtrl.text.trim();
          final server = _serverCtrl.text.trim();
          final mac = _macCtrl.text.trim();
          if (name.isEmpty || server.isEmpty || mac.isEmpty) {
            throw Exception('Name, server, and MAC are required');
          }
          await widget.repo.addStalkerAccount(name, server, mac);
        case 3:
          final name = _nameCtrl.text.trim();
          final url = _urlCtrl.text.trim();
          if (name.isEmpty || url.isEmpty) {
            throw Exception('Name and URL are required');
          }
          await widget.repo.addEpgSource(name, url);
      }
      if (mounted) navigator.pop();
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = e.toString();
        });
      }
    }
  }

  Future<void> _findPortals() async {
    setState(() {
      _scraping = true;
      _scrapeError = null;
      _scrapeStatus = 'Starting the portal hunt...';
      _results = [];
    });
    PortalNutzScraper.scrape(
      englishOnly: _englishOnly,
      noAdult: _noAdult,
      sportsOnly: _sportsOnly,
      onEvent: (event) {
        switch (event) {
          case PortalNutzProgress(:final message):
            if (mounted) setState(() => _scrapeStatus = message);
          case PortalNutzResult(:final portals):
            if (mounted) {
              setState(() {
                _results = portals;
                _scraping = false;
              });
            }
          case PortalNutzError(:final message):
            if (mounted) {
              setState(() {
                _scrapeError = message;
                _scraping = false;
              });
            }
        }
      },
    );
  }

  Future<void> _addPortal(PortalNutzEntry portal) async {
    final navigator = Navigator.of(context);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.repo.addXtreamAccount(
        portal.domain,
        portal.url,
        portal.username,
        portal.password,
        info: PortalAccountInfo(
          expDate: portal.expDate,
          maxConnections: portal.maxConnections,
          activeConnections: portal.activeConnections,
          status: portal.status,
          isTrial: portal.isTrial,
        ),
      );
      if (mounted) navigator.pop();
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = e.toString();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final tabs = ['M3U', 'Xtream', 'Stalker', 'EPG', 'Portal'];
    final isPortal = _tab == 4;
    return SafeArea(
      top: false,
      child: Container(
        decoration: const BoxDecoration(
          color: _bg,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          border: Border(top: BorderSide(color: Colors.white12, width: 0.6)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Text(
                    'Add Source',
                    style: TextStyle(
                      color: _textPrimary,
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                    ),
                  ),
                  const Spacer(),
                  GestureDetector(
                    onTap: () => Navigator.of(context).pop(),
                    child: const Icon(Icons.close_rounded,
                        color: _textTertiary, size: 22),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  for (final (i, t) in tabs.indexed) ...[
                    Expanded(
                      child: _Chip(
                        label: t,
                        selected: _tab == i,
                        onTap: () => setState(() => _tab = i),
                      ),
                    ),
                    if (i < tabs.length - 1) const SizedBox(width: 8),
                  ],
                ],
              ),
              const SizedBox(height: 16),
              if (isPortal) _buildPortalContent() else _buildManualContent(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildManualContent() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        _field(_nameCtrl, 'Name', hint: 'My Playlist'),
        const SizedBox(height: 10),
        if (_tab == 0 || _tab == 3)
          _field(_urlCtrl, _tab == 3 ? 'EPG URL' : 'M3U URL', hint: 'https://...')
        else if (_tab == 1)
          _field(_serverCtrl, 'Server URL', hint: 'http://server:8080')
        else if (_tab == 2)
          _field(_serverCtrl, 'Portal Server', hint: 'http://portal'),
        if (_tab == 1) ...[
          const SizedBox(height: 10),
          _field(_userCtrl, 'Username'),
          const SizedBox(height: 10),
          _field(_passCtrl, 'Password', obscure: true),
        ],
        if (_tab == 2) ...[
          const SizedBox(height: 10),
          _field(_macCtrl, 'MAC Address', hint: '00:1A:79:...'),
        ],
        if (_error != null) ...[
          const SizedBox(height: 10),
          Text(_error!, style: const TextStyle(color: _red, fontSize: 12)),
        ],
        const SizedBox(height: 16),
        GestureDetector(
          onTap: _busy ? null : _submit,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 14),
            decoration: BoxDecoration(
              color: _busy ? _accent.withValues(alpha: 0.5) : _accent,
              borderRadius: BorderRadius.circular(12),
            ),
            alignment: Alignment.center,
            child: _busy
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 2,
                    ),
                  )
                : const Text(
                    'Add',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
          ),
        ),
      ],
    );
  }

  Widget _buildPortalContent() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text(
          'Find working Xtream portals scraped from public lists — no '
          'credentials needed.',
          style: TextStyle(color: _textSecondary, fontSize: 12.5, height: 1.4),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            _Chip(
              label: 'English',
              selected: _englishOnly,
              onTap: () => setState(() => _englishOnly = !_englishOnly),
            ),
            const SizedBox(width: 8),
            _Chip(
              label: 'No Adult',
              selected: _noAdult,
              onTap: () => setState(() => _noAdult = !_noAdult),
            ),
            const SizedBox(width: 8),
            _Chip(
              label: 'Sports',
              selected: _sportsOnly,
              onTap: () => setState(() => _sportsOnly = !_sportsOnly),
            ),
          ],
        ),
        const SizedBox(height: 14),
        GestureDetector(
          onTap: _busy || _scraping ? null : _findPortals,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 14),
            decoration: BoxDecoration(
              color: _busy || _scraping
                  ? _accent.withValues(alpha: 0.5)
                  : _accent,
              borderRadius: BorderRadius.circular(12),
            ),
            alignment: Alignment.center,
            child: _scraping
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 2,
                    ),
                  )
                : const Text(
                    'Find Portals',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
          ),
        ),
        if (_scrapeStatus.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text(
            _scrapeStatus,
            style: const TextStyle(
              color: _textTertiary,
              fontSize: 12,
              fontFamily: 'monospace',
            ),
          ),
        ],
        if (_scrapeError != null) ...[
          const SizedBox(height: 12),
          Text(_scrapeError!,
              style: const TextStyle(color: _red, fontSize: 12)),
        ],
        if (_error != null) ...[
          const SizedBox(height: 12),
          Text(_error!, style: const TextStyle(color: _red, fontSize: 12)),
        ],
        if (_results.isNotEmpty) ...[
          const SizedBox(height: 14),
          const Text(
            'Working portals',
            style: TextStyle(
              color: _accent,
              fontWeight: FontWeight.bold,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 8),
          for (final portal in _results) ...[
            _PortalResultTile(
              portal: portal,
              busy: _busy,
              onAdd: () => _addPortal(portal),
            ),
            const SizedBox(height: 8),
          ],
        ],
      ],
    );
  }

  Widget _field(
    TextEditingController controller,
    String label, {
    String? hint,
    bool obscure = false,
  }) {
    return TextField(
      controller: controller,
      obscureText: obscure,
      style: const TextStyle(color: _textPrimary, fontSize: 14),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        labelStyle: const TextStyle(color: _textTertiary, fontSize: 13),
        hintStyle: const TextStyle(color: Color(0x80FFFFFF), fontSize: 13),
        filled: true,
        fillColor: _surfaceLight,
        isDense: true,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }
}

/// One verified portal result from the PortalNutz scraper.
class _PortalResultTile extends StatelessWidget {
  final PortalNutzEntry portal;
  final bool busy;
  final VoidCallback onAdd;

  const _PortalResultTile({
    required this.portal,
    required this.busy,
    required this.onAdd,
  });

  @override
  Widget build(BuildContext context) {
    final accountInfo = PortalNutzScraper.formatAccountInfoLine(
      expDate: portal.expDate,
      maxConnections: portal.maxConnections,
      activeConnections: portal.activeConnections,
      status: portal.status,
      isTrial: portal.isTrial,
    );
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
      decoration: BoxDecoration(
        color: _surfaceLight,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _textTertiary, width: 0.5),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  portal.domain,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: _textPrimary,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${portal.username} · ${portal.channelCount} channels'
                  '${accountInfo == null ? '' : ' · $accountInfo'}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: _textTertiary, fontSize: 11),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          if (busy)
            const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(color: _accent, strokeWidth: 2),
            )
          else
            GestureDetector(
              onTap: onAdd,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: _accent,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Text(
                  'Add',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}