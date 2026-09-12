import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:liquid_glass_easy/liquid_glass_easy.dart';

import '../../services/theme/app_theme_service.dart';
import '../../services/theme/dock_settings.dart';
import '../../services/theme/glass_settings.dart';
import '../../services/iptv/hardcoded_channels.dart';
import '../../services/iptv/iptv_controller.dart';
import '../../services/iptv/iptv_settings.dart';
import '../../services/iptv/iptv_storage.dart';
import '../../models/iptv/iptv_models.dart';
import '../../services/discord/discord_rpc_service.dart';
import '../../utils/navigation/route_transitions.dart';
import '../../widgets/common/animated_ambient_background.dart';
import '../../widgets/common/app_liquid_dock.dart';
import '../../widgets/common/custom_scroll_track.dart';
import '../../widgets/iptv/iptv_hero_carousel.dart';
import '../../widgets/iptv/iptv_slider_section.dart';
import '../settings/settings_page.dart';
import 'iptv_channel_sheet.dart';
import 'iptv_player_page.dart';
import 'iptv_portals_modal.dart';
import 'iptv_search_page.dart';

class IptvPage extends StatefulWidget {
  const IptvPage({super.key});

  @override
  State<IptvPage> createState() => _IptvPageState();
}

class _IptvPageState extends State<IptvPage> {
  final IptvController _ctrl = IptvController.instance;
  final ScrollController _scrollController = ScrollController();

  List<HardcodedChannel> _featured = [];
  List<HardcodedChannel> _espnAndCollege = [];
  List<HardcodedChannel> _usSports = [];
  List<HardcodedChannel> _soccer = [];
  List<HardcodedChannel> _combat = [];
  List<HardcodedChannel> _racing = [];
  List<HardcodedChannel> _movies = [];
  List<HardcodedChannel> _news = [];
  List<HardcodedChannel> _arabic = [];
  List<HardcodedChannel> _discovery = [];
  List<HardcodedChannel> _kids = [];

  List<QuickChannel> _quickChannels = [];

  @override
  void initState() {
    super.initState();
    DiscordRpcService.instance.setWatchingLiveTv(channelName: 'Live TV');
    IptvSettings.changeNotifier.addListener(_onSettingsChanged);
    AppThemeService.currentPalette.addListener(_onSettingsChanged);
    _ctrl.init();
    _loadQuickChannels();
    _loadSections();
  }

  Future<void> _loadQuickChannels() async {
    final channels = await IptvQuickChannelStore.load();
    setState(() => _quickChannels = channels);
  }

  Future<void> _addQuickChannel(QuickChannel channel) async {
    await IptvQuickChannelStore.add(channel);
    setState(() => _quickChannels.add(channel));
  }

  Future<void> _removeQuickChannel(String id) async {
    await IptvQuickChannelStore.remove(id);
    setState(() => _quickChannels.removeWhere((c) => c.id == id));
  }

  void _showAddQuickChannelDialog() {
    showDialog(
      context: context,
      builder: (ctx) => _AddQuickChannelDialog(onAdd: _addQuickChannel),
    );
  }

  @override
  void dispose() {
    IptvSettings.changeNotifier.removeListener(_onSettingsChanged);
    AppThemeService.currentPalette.removeListener(_onSettingsChanged);
    _scrollController.dispose();
    DiscordRpcService.instance.clearToIdle();
    super.dispose();
  }

  void _onSettingsChanged() {
    if (!mounted) return;
    setState(() {});
  }

  void _loadSections() {
    _featured = [
      HardcodedChannels.byId('espn_plus') ?? HardcodedChannels.byId('espn')!,
      HardcodedChannels.byId('ncaa_cbb') ?? HardcodedChannels.byId('espn')!,
      HardcodedChannels.byId('ufc')!,
      HardcodedChannels.byId('bein_sports')!,
      HardcodedChannels.byId('champions_league')!,
      HardcodedChannels.byId('f1')!,
      HardcodedChannels.byId('nba')!,
      HardcodedChannels.byId('hbo')!,
    ];
    _espnAndCollege = [
      HardcodedChannels.byId('espn_plus')!,
      HardcodedChannels.byId('espn')!,
      HardcodedChannels.byId('espn2')!,
      HardcodedChannels.byId('espnu')!,
      HardcodedChannels.byId('ncaa_cbb')!,
      HardcodedChannels.byId('ncaa_mens_cbb')!,
      HardcodedChannels.byId('ncaa_womens_cbb')!,
      HardcodedChannels.byId('sec_network')!,
      HardcodedChannels.byId('acc_network')!,
      HardcodedChannels.byId('big_ten_network')!,
      HardcodedChannels.byId('pac_12_network')!,
      HardcodedChannels.byId('espnews')!,
      HardcodedChannels.byId('espn_deportes')!,
      HardcodedChannels.byId('longhorn_network')!,
      HardcodedChannels.byId('bally_sports')!,
    ];
    _usSports = [
      HardcodedChannels.byId('nba')!,
      HardcodedChannels.byId('nfl')!,
      HardcodedChannels.byId('nfl_redzone')!,
      HardcodedChannels.byId('mlb')!,
      HardcodedChannels.byId('nhl')!,
      HardcodedChannels.byId('fox_sports')!,
      HardcodedChannels.byId('cbs_sports')!,
      HardcodedChannels.byId('nbc_sports')!,
      HardcodedChannels.byId('dazn')!,
      HardcodedChannels.byId('eurosport')!,
    ];
    _soccer = HardcodedChannels.byCategory('Soccer');
    _combat = HardcodedChannels.byCategory('Combat');
    _racing = HardcodedChannels.byCategory('Racing');
    _movies = HardcodedChannels.byCategory('Movies');
    _news = HardcodedChannels.byCategory('News');
    _arabic = HardcodedChannels.byCategory('Arabic');
    _discovery = HardcodedChannels.byCategory('Discovery');
    _kids = HardcodedChannels.byCategory('Kids');
  }

  void _openChannel(HardcodedChannel channel) {
    IptvChannelSheet.show(context, channel);
  }

  void _watchChannelNow(HardcodedChannel channel) async {
    // If we have saved hits, launch immediately, otherwise open sheet to scan
    final results = _ctrl.channelResults;
    if (_ctrl.activeHardcoded?.id == channel.id && results.isNotEmpty) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => IptvPlayerPage(
            channel: channel,
            hits: results,
            initialHitIndex: 0,
          ),
        ),
      );
    } else {
      IptvChannelSheet.show(context, channel);
    }
  }

  void _navigateToSettings(Offset? tapPosition) {
    Navigator.push(
      context,
      LiquidRevealRoute(page: const SettingsPage(), tapPosition: tapPosition),
    );
  }

  void _navigateToSearch(Offset? tapPosition) {
    Navigator.push(
      context,
      LiquidRevealRoute(page: IptvSearchPage(quickChannels: _quickChannels), tapPosition: tapPosition),
    );
  }

  @override
  Widget build(BuildContext context) {
    final topPadding = MediaQuery.of(context).padding.top;
    final palette = AppThemeService.currentPalette.value;
    final spotlightEnabled = IptvSettings.enableSpotlight.value;
    final visibleCategories = IptvSettings.visibleCategories.value;

    final Map<String, (String, List<HardcodedChannel>)> categoryMap = {
      'Premier Live Broadcasts': (
        'Top worldwide sporting events and championship channels',
        _featured,
      ),
      'ESPN & College Basketball (NCAA)': (
        'ESPN+, ESPN, ESPN2, ESPNU, NCAA Men\'s & Women\'s CBB, SEC & ACC',
        _espnAndCollege,
      ),
      'US Major Leagues & Sports': (
        'NBA TV, NFL Network, RedZone, MLB, NHL, Fox Sports & CBS Sports',
        _usSports,
      ),
      'Global Football & Soccer': (
        'UEFA Champions League, Premier League, beIN Sports, La Liga & Serie A',
        _soccer,
      ),
      'Combat & Martial Arts': (
        'UFC Fight Pass, WWE, AEW, World Boxing & PPV',
        _combat,
      ),
      'Motorsport & Racing': (
        'Formula 1, MotoGP, NASCAR Cup, IndyCar & Rally WRC',
        _racing,
      ),
      'Movies & Premium Networks': (
        'HBO, Showtime, Starz, Cinemax, Paramount & AMC',
        _movies,
      ),
      '24/7 Global News Networks': (
        'CNN, BBC World, Fox News, Sky News, Al Jazeera & Bloomberg',
        _news,
      ),
      'Arabic & Regional Hub': (
        'MBC, Rotana, OSN, Abu Dhabi TV, Dubai TV & Al Arabiya',
        _arabic,
      ),
      'Discovery & Documentaries': (
        'National Geographic, Discovery Channel, History & Animal Planet',
        _discovery,
      ),
      'Kids & Family': (
        'Cartoon Network, Disney Channel, Nickelodeon & Spacetoon',
        _kids,
      ),
      'US Region': (
        'ABC News Live, CBS News 24/7, NBC News Now, Weather Channel & more',
        HardcodedChannels.byCategory('US'),
      ),
      'UK Region': (
        'BBC One UK, ITV News, Sky News UK, Channel 4 & more',
        HardcodedChannels.byCategory('UK'),
      ),
      'Canada Region': (
        'CBC News, CTV News, TSN Sportsnet, Crave & Global News',
        HardcodedChannels.byCategory('CA'),
      ),
      'Bay Area': (
        'KTVU Fox 2, KPIX 5 CBS, KGO 7 ABC, KRON 4 & NBC Bay Area',
        HardcodedChannels.byCategory('Bay Area'),
      ),
      'International Sports': (
        'Willow Cricket, Fox Soccer Plus, GolTV, TUDN, Viaplay & more',
        HardcodedChannels.byCategory('Int. Sports'),
      ),
    };

    final listContent = RefreshIndicator(
      color: palette.primaryColor,
      backgroundColor: palette.cardBackgroundColor,
      onRefresh: () async {
        _ctrl.scrape();
      },
      child: ListView(
        controller: _scrollController,
        clipBehavior: Clip.none,
        padding: EdgeInsets.zero,
        physics: const BouncingScrollPhysics(
          parent: AlwaysScrollableScrollPhysics(),
        ),
        children: [
          // 1. Full Bleed Spotlight Hero Carousel
          if (spotlightEnabled)
            IptvHeroCarousel(
              channels: _featured,
              onWatchNow: _watchChannelNow,
              onSourcesTap: _openChannel,
            )
          else
            SizedBox(height: topPadding + 76),

          const SizedBox(height: 20),

          // Quick Channels row (below hero, above categories)
          _QuickChannelsSlider(
            channels: _quickChannels,
            onChannelTap: _openChannel,
            onAddTap: _showAddQuickChannelDialog,
            onRemoveTap: _removeQuickChannel,
          ),
          const SizedBox(height: 8),

          // 2. Curated Slider Sections (driven by user-customized category visibility and order)
          for (final catName in visibleCategories)
            if (categoryMap.containsKey(catName) && categoryMap[catName]!.$2.isNotEmpty)
              IptvSliderSection(
                title: catName,
                subtitle: categoryMap[catName]!.$1,
                channels: categoryMap[catName]!.$2,
                onChannelTap: _openChannel,
              ),

          const SizedBox(height: 90),
        ],
      ),
    );

    final backgroundContent = IptvSettings.enableAmbientLights.value
        ? AnimatedAmbientBackground(child: listContent)
        : Container(
            color: palette.scaffoldBackgroundColor,
            child: listContent,
          );

    final overlayChildren = <Widget>[
      // Floating Glass App Bar (Home & Anime Page Style)
      Positioned(
        top: 0,
        left: 0,
        right: 0,
        child: _IptvGlassAppBar(
          topPadding: topPadding,
          onSearchTap: _navigateToSearch,
          onSettingsTap: _navigateToSettings,
          onSourcesTap: () => IptvPortalsModal.show(context),
        ),
      ),

      // Custom Scroll Track (Matching Home & Anime Page)
      if (MediaQuery.sizeOf(context).width > 800)
        Positioned(
          right: 24,
          bottom: 40,
          child: CustomScrollTrack(controller: _scrollController),
        ),

      // Liquid Dock Navbar (Home & Anime Page Style)
      Positioned(
        bottom: 24,
        left: 0,
        right: 0,
        child: Center(
          child: AppLiquidDock(
            currentDestination: DockItemKey.liveTv,
            onSettingsTap: () => _navigateToSettings(null),
            onSearchTap: () => _navigateToSearch(null),
          ),
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

class _IptvGlassAppBar extends StatelessWidget {
  final double topPadding;
  final Function(Offset? tapPosition) onSearchTap;
  final Function(Offset? tapPosition) onSettingsTap;
  final VoidCallback onSourcesTap;

  const _IptvGlassAppBar({
    required this.topPadding,
    required this.onSearchTap,
    required this.onSettingsTap,
    required this.onSourcesTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(28, topPadding + 14, 28, 14),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color(0xCC080A0F),
            Color(0x77080A0F),
            Colors.transparent,
          ],
          stops: [0.0, 0.6, 1.0],
        ),
      ),
      child: Row(
        children: [
          // Logo & Title
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF7C5CFF), Color(0xFF00D2EF)],
                  ),
                  borderRadius: BorderRadius.circular(10),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF7C5CFF).withValues(alpha: 0.4),
                      blurRadius: 10,
                    ),
                  ],
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.live_tv_rounded, color: Colors.white, size: 18),
                    SizedBox(width: 6),
                    Text(
                      'LIVE TV',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.8,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Text(
                  '60+ CHANNELS',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
            ],
          ),

          const Spacer(),

          // Sources / Xtream Panels button
          _GlassActionButton(
            icon: Icons.settings_input_antenna_rounded,
            tooltip: 'Manage Portals & Playlists',
            onTap: onSourcesTap,
          ),

          const SizedBox(width: 10),

          // Search button
          _GlassActionButton(
            icon: Icons.search_rounded,
            tooltip: 'Search Channels',
            onTapWithPosition: onSearchTap,
          ),

          const SizedBox(width: 10),

          // Settings button
          _GlassActionButton(
            icon: Icons.settings_rounded,
            tooltip: 'Settings',
            onTapWithPosition: onSettingsTap,
          ),
        ],
      ),
    );
  }
}

class _GlassActionButton extends StatefulWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;
  final Function(Offset? position)? onTapWithPosition;

  const _GlassActionButton({
    required this.icon,
    required this.tooltip,
    this.onTap,
    this.onTapWithPosition,
  });

  @override
  State<_GlassActionButton> createState() => _GlassActionButtonState();
}

class _GlassActionButtonState extends State<_GlassActionButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Tooltip(
        message: widget.tooltip,
        child: GestureDetector(
          onTapDown: (details) {
            if (widget.onTapWithPosition != null) {
              widget.onTapWithPosition!(details.globalPosition);
            } else if (widget.onTap != null) {
              widget.onTap!();
            }
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: _hovered
                  ? Colors.white.withValues(alpha: 0.16)
                  : Colors.white.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: _hovered
                    ? const Color(0xFF7C5CFF).withValues(alpha: 0.6)
                    : Colors.white.withValues(alpha: 0.12),
              ),
              boxShadow: _hovered
                  ? [
                      BoxShadow(
                        color: const Color(0xFF7C5CFF).withValues(alpha: 0.25),
                        blurRadius: 10,
                      )
                    ]
                  : null,
            ),
            child: Icon(
              widget.icon,
              color: _hovered ? Colors.white : Colors.white70,
              size: 20,
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Quick Channels Slider (user-added channels)
// ─────────────────────────────────────────────────────────────────────────────
class _QuickChannelsSlider extends StatefulWidget {
  final List<QuickChannel> channels;
  final Function(HardcodedChannel) onChannelTap;
  final VoidCallback onAddTap;
  final Function(String) onRemoveTap;

  const _QuickChannelsSlider({
    required this.channels,
    required this.onChannelTap,
    required this.onAddTap,
    required this.onRemoveTap,
  });

  @override
  State<_QuickChannelsSlider> createState() => _QuickChannelsSliderState();
}

class _QuickChannelsSliderState extends State<_QuickChannelsSlider> {
  late final ScrollController _scrollController;
  bool _canScrollLeft = false;
  bool _canScrollRight = true;
  final bool _isHovering = false;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    _scrollController.addListener(_updateButtons);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_updateButtons);
    _scrollController.dispose();
    super.dispose();
  }

  void _updateButtons() {
    if (!_scrollController.hasClients) return;
    final canLeft = _scrollController.position.pixels > 10;
    final canRight = _scrollController.position.pixels <
        _scrollController.position.maxScrollExtent - 10;
    if (canLeft != _canScrollLeft || canRight != _canScrollRight) {
      setState(() {
        _canScrollLeft = canLeft;
        _canScrollRight = canRight;
      });
    }
  }

  void _scroll(double dir) {
    if (!_scrollController.hasClients) return;
    final viewport = _scrollController.position.viewportDimension;
    final amount = viewport * 0.75 * dir;
    final target = (_scrollController.position.pixels + amount)
        .clamp(0.0, _scrollController.position.maxScrollExtent);
    _scrollController.animateTo(
      target,
      duration: const Duration(milliseconds: 500),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final cardWidth = width < 600 ? 140.0 : width < 1000 ? 160.0 : 180.0;
    final posterH = cardWidth * 1.35;
    final totalH = posterH + 60;
    final isDesktop =
        !kIsWeb && (Theme.of(context).platform == TargetPlatform.windows ||
            Theme.of(context).platform == TargetPlatform.macOS ||
            Theme.of(context).platform == TargetPlatform.linux);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                'Quick Channels',
                style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800, letterSpacing: 0.5),
              ),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.add_circle_outline_rounded, size: 24),
                color: const Color(0xFF7C5CFF),
                tooltip: 'Add Quick Channel',
                onPressed: widget.onAddTap,
              ),
            ],
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: totalH,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                ListView.separated(
                  controller: _scrollController,
                  scrollDirection: Axis.horizontal,
                  clipBehavior: Clip.none,
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  physics: const BouncingScrollPhysics(),
                  itemCount: widget.channels.length + 1,
                  separatorBuilder: (_, __) => const SizedBox(width: 12),
                  itemBuilder: (context, index) {
                    if (index == widget.channels.length) {
                      return SizedBox(
                        width: cardWidth,
                        child: _QuickAddCard(onTap: widget.onAddTap),
                      );
                    }
                    final ch = widget.channels[index];
                    return SizedBox(
                      width: cardWidth,
                      child: _QuickChannelCard(
                        channel: ch,
                        onTap: () {
                          final hc = HardcodedChannel(
                            id: 'qc_${ch.id}',
                            name: ch.name,
                            short: ch.short,
                            category: ch.category,
                            keywords: ch.keywords,
                            gradient: ch.gradient,
                            iconUrl: ch.iconUrl,
                          );
                          widget.onChannelTap(hc);
                        },
                        onRemove: () => widget.onRemoveTap(ch.id),
                      ),
                    );
                  },
                ),
                // Desktop scroll arrows
                if (isDesktop) ...[
                  AnimatedPositioned(
                    duration: const Duration(milliseconds: 250),
                    curve: Curves.easeOutCubic,
                    left: _canScrollLeft && _isHovering ? 2 : -50,
                    top: 0,
                    bottom: 0,
                    child: Center(
                      child: IconButton(
                        icon: const Icon(Icons.chevron_left_rounded, color: Colors.white70),
                        onPressed: _canScrollLeft ? () => _scroll(-1) : null,
                      ),
                    ),
                  ),
                  AnimatedPositioned(
                    duration: const Duration(milliseconds: 250),
                    curve: Curves.easeOutCubic,
                    right: _canScrollRight && _isHovering ? 2 : -50,
                    top: 0,
                    bottom: 0,
                    child: Center(
                      child: IconButton(
                        icon: const Icon(Icons.chevron_right_rounded, color: Colors.white70),
                        onPressed: _canScrollRight ? () => _scroll(1) : null,
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
}

class _QuickChannelCard extends StatefulWidget {
  final QuickChannel channel;
  final VoidCallback onTap;
  final VoidCallback onRemove;

  const _QuickChannelCard({
    required this.channel,
    required this.onTap,
    required this.onRemove,
  });

  @override
  State<_QuickChannelCard> createState() => _QuickChannelCardState();
}

class _QuickChannelCardState extends State<_QuickChannelCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        onLongPress: widget.onRemove,
        child: Stack(
          children: [
            Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: widget.channel.gradient,
                ),
                boxShadow: _hovered
                    ? [BoxShadow(color: widget.channel.gradient.first.withValues(alpha: 0.5), blurRadius: 16.0, spreadRadius: 2.0)]
                    : null,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Center(
                      child: widget.channel.iconUrl != null
                          ? Image.network(
                              widget.channel.iconUrl!,
                              fit: BoxFit.contain,
                              errorBuilder: (_, __, ___) => _QuickChannelIcon(widget.channel.short),
                            )
                          : _QuickChannelIcon(widget.channel.short),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.channel.name,
                          style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w700),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          widget.channel.category,
                          style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            // Remove button — always visible (works on touch + desktop)
            Positioned(
              top: 4,
              right: 4,
              child: GestureDetector(
                onTap: widget.onRemove,
                child: Container(
                  padding: const EdgeInsets.all(3),
                  decoration: const BoxDecoration(color: Color(0xFFCC0000), shape: BoxShape.circle),
                  child: const Icon(Icons.close_rounded, color: Colors.white, size: 14),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _QuickAddCard extends StatelessWidget {
  final VoidCallback onTap;
  const _QuickAddCard({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFF7C5CFF).withValues(alpha: 0.5), width: 2),
          color: const Color(0xFF0C0F17),
        ),
        child: const Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.add_rounded, color: Color(0xFF7C5CFF), size: 36),
            SizedBox(height: 8),
            Text('Add Channel', style: TextStyle(color: Color(0xFF7C5CFF), fontSize: 12, fontWeight: FontWeight.w700)),
          ],
        ),
      ),
    );
  }
}

class _QuickChannelIcon extends StatelessWidget {
  final String short;
  const _QuickChannelIcon(this.short);

  @override
  Widget build(BuildContext context) {
    return Text(
      short,
      style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w900, letterSpacing: 1),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Add Quick Channel Dialog
// ─────────────────────────────────────────────────────────────────────────────
class _AddQuickChannelDialog extends StatefulWidget {
  final void Function(QuickChannel) onAdd;

  const _AddQuickChannelDialog({required this.onAdd});

  @override
  State<_AddQuickChannelDialog> createState() => _AddQuickChannelDialogState();
}

class _AddQuickChannelDialogState extends State<_AddQuickChannelDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _shortCtrl = TextEditingController();
  final _keywordsCtrl = TextEditingController();

  List<Color> _gradient = [const Color(0xFF7C5CFF), const Color(0xFF1A1A1A)];
  final List<List<Color>> _presetGradients = [
    [const Color(0xFF7C5CFF), const Color(0xFF1A1A1A)],
    [const Color(0xFFCC0000), const Color(0xFF1A1A1A)],
    [const Color(0xFF003366), const Color(0xFF0066CC)],
    [const Color(0xFFD4AF37), const Color(0xFF1A1A1A)],
    [const Color(0xFF00AA00), const Color(0xFF1A1A1A)],
    [const Color(0xFFFF6D00), const Color(0xFF1A1A1A)],
    [const Color(0xFF0066CC), const Color(0xFF003366)],
    [const Color(0xFFCC0000), const Color(0xFF001965)],
  ];

  String _selectedCategory = 'Quick';
  final List<String> _categories = ['Quick', 'US', 'UK', 'CA', 'Bay Area', 'Sports', 'News', 'Movies', 'Int. Sports'];

  @override
  void dispose() {
    _nameCtrl.dispose();
    _shortCtrl.dispose();
    _keywordsCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF0C0F17),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Text('Add Quick Channel', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
      content: SizedBox(
        width: 360,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: _nameCtrl,
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(
                    labelText: 'Channel Name',
                    labelStyle: TextStyle(color: Colors.white70),
                    border: UnderlineInputBorder(),
                    focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFF7C5CFF))),
                  ),
                  validator: (v) => v == null || v.trim().isEmpty ? 'Required' : null,
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _shortCtrl,
                        style: const TextStyle(color: Colors.white),
                        decoration: const InputDecoration(
                          labelText: 'Short Code (optional)',
                          labelStyle: TextStyle(color: Colors.white70),
                          border: UnderlineInputBorder(),
                          focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFF7C5CFF))),
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        value: _selectedCategory,
                        dropdownColor: const Color(0xFF0C0F17),
                        style: const TextStyle(color: Colors.white),
                        decoration: const InputDecoration(
                          labelText: 'Category',
                          labelStyle: TextStyle(color: Colors.white70),
                          border: UnderlineInputBorder(),
                          focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFF7C5CFF))),
                        ),
                        items: _categories.map((c) => DropdownMenuItem(value: c, child: Text(c, style: const TextStyle(color: Colors.white)))).toList(),
                        onChanged: (v) => setState(() => _selectedCategory = v!),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _keywordsCtrl,
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(
                    labelText: 'Keywords (comma-separated)',
                    labelStyle: TextStyle(color: Colors.white70),
                    hintText: 'e.g. cnn, news, international',
                    hintStyle: TextStyle(color: Colors.white38),
                    border: UnderlineInputBorder(),
                    focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFF7C5CFF))),
                  ),
                  validator: (v) => v == null || v.trim().isEmpty ? 'Required' : null,
                ),
                const SizedBox(height: 16),
                const Align(alignment: Alignment.centerLeft, child: Text('Gradient', style: TextStyle(color: Colors.white70, fontSize: 12))),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: _presetGradients.map((g) {
                    final isSelected = _gradient == g;
return GestureDetector(
                      onTap: () => setState(() => _gradient = g),
                      child: Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(8),
                          gradient: LinearGradient(colors: g),
                          border: Border.all(color: isSelected ? const Color(0xFF7C5CFF) : Colors.transparent, width: 2),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel', style: TextStyle(color: Colors.white70))),
        ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF7C5CFF), foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
          onPressed: () {
            if (_formKey.currentState!.validate()) {
              final id = 'user_${DateTime.now().millisecondsSinceEpoch}';
              final shortVal = _shortCtrl.text.trim().isEmpty
                  ? _nameCtrl.text.trim().substring(0, _nameCtrl.text.trim().length > 3 ? 3 : _nameCtrl.text.trim().length).toUpperCase()
                  : _shortCtrl.text.trim().toUpperCase();
              final channel = QuickChannel(
                id: id,
                name: _nameCtrl.text.trim(),
                short: shortVal,
                category: _selectedCategory,
                keywords: _keywordsCtrl.text.trim().split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList(),
                gradient: _gradient,
              );
              widget.onAdd(channel);
              Navigator.pop(context);
            }
          },
          child: const Text('Add'),
        ),
      ],
    );
  }
}
