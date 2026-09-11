import 'dart:async';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../models/iptv/iptv_models.dart';
import '../../models/iptv/m3u_models.dart';
import '../../services/theme/app_theme_service.dart';
import '../../services/iptv/hardcoded_channels.dart';
import '../../services/iptv/iptv_network.dart';
import '../../services/iptv/iptv_settings.dart';
import '../../services/iptv/iptv_storage.dart';
import '../../services/discord/discord_rpc_service.dart';
import '../../utils/navigation/route_transitions.dart';
import 'iptv_player_page.dart';

class IptvPortalBrowserPage extends StatefulWidget {
  final VerifiedPortal? portal;
  final M3uPlaylist? m3uPlaylist;
  final bool returning;
  final void Function(String streamUrl, String channelName)? onStreamSelected;

  const IptvPortalBrowserPage({
    super.key,
    this.portal,
    this.m3uPlaylist,
    this.returning = false,
    this.onStreamSelected,
  });

  @override
  State<IptvPortalBrowserPage> createState() => _IptvPortalBrowserPageState();
}

class _IptvPortalBrowserPageState extends State<IptvPortalBrowserPage> {
  static const String favoritesCategoryId = '__favorites__';

  IptvSection _activeSection = IptvSection.live;
  bool _isLoading = true;
  String? _errorMessage;

  List<IptvCategory> _categories = [];
  String _selectedCategoryId = '';
  List<IptvStream> _allStreams = [];

  final TextEditingController _searchCtrl = TextEditingController();
  final TextEditingController _catSearchCtrl = TextEditingController();
  String _searchQuery = '';
  String _catSearchQuery = '';

  // Scroll Controllers with Desktop Arrow Navigation
  final ScrollController _categoryScrollController = ScrollController();
  final ScrollController _contentScrollController = ScrollController();

  bool _isHoveringCategories = false;
  bool _isHoveringContent = false;
  bool _canScrollCatUp = false;
  bool _canScrollCatDown = false;
  bool _canScrollContentUp = false;
  bool _canScrollContentDown = false;

  // Stream Health / Alive Checker State
  bool _isCheckingAlive = false;
  int _aliveChecked = 0;
  int _aliveTotal = 0;
  Set<String> _aliveStreamIds = {};
  bool _cancelAlive = false;

  // Favorited Streams in this Portal
  Set<String> _favoriteStreamIds = {};

  String get _storageKey {
    if (widget.portal != null) {
      return IptvPortalFavoritesStore.portalKey(widget.portal!.portal);
    } else if (widget.m3uPlaylist != null) {
      return 'm3u_${widget.m3uPlaylist!.id}';
    }
    return '';
  }

  // Static in-memory EPG cache shared across rows to avoid duplicate network fetches
  static final Map<String, List<EpgEntry>> _sharedEpgCache = {};

  @override
  void initState() {
    super.initState();
    final name = widget.portal?.name ?? widget.m3uPlaylist?.name ?? 'IPTV Portal';
    DiscordRpcService.instance.setWatchingLiveTv(channelName: 'Portal: $name');
    _categoryScrollController.addListener(_updateCategoryScrollState);
    _contentScrollController.addListener(_updateContentScrollState);
    IptvSettings.changeNotifier.addListener(_onSettingsChanged);
    AppThemeService.currentPalette.addListener(_onSettingsChanged);
    _loadFavorites();
    _loadSectionData();
  }

  void _onSettingsChanged() {
    if (!mounted) return;
    setState(() {});
  }

  Future<void> _loadFavorites() async {
    final key = _storageKey;
    if (key.isEmpty) return;
    final favs = await IptvPortalFavoritesStore.load(key);
    if (mounted) {
      setState(() => _favoriteStreamIds = favs);
    }
  }

  Future<void> _toggleFavoriteStream(String streamId) async {
    final key = _storageKey;
    if (key.isEmpty) return;
    setState(() {
      if (_favoriteStreamIds.contains(streamId)) {
        _favoriteStreamIds.remove(streamId);
      } else {
        _favoriteStreamIds.add(streamId);
      }
    });
    await IptvPortalFavoritesStore.save(key, _favoriteStreamIds);
  }

  @override
  void dispose() {
    _cancelAlive = true;
    IptvSettings.changeNotifier.removeListener(_onSettingsChanged);
    AppThemeService.currentPalette.removeListener(_onSettingsChanged);
    _categoryScrollController.removeListener(_updateCategoryScrollState);
    _contentScrollController.removeListener(_updateContentScrollState);
    _categoryScrollController.dispose();
    _contentScrollController.dispose();
    _searchCtrl.dispose();
    _catSearchCtrl.dispose();
    DiscordRpcService.instance.clearToIdle();
    super.dispose();
  }

  void _showBrowserCustomizer(BuildContext context) {
    final palette = AppThemeService.currentPalette.value;
    showDialog(
      context: context,
      builder: (ctx) {
        return Dialog(
          backgroundColor: const Color(0xFF10131C),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: BorderSide(color: Colors.white.withValues(alpha: 0.12)),
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 500),
            child: Padding(
              padding: const EdgeInsets.all(22),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.tune_rounded, color: palette.primaryColor, size: 20),
                      const SizedBox(width: 10),
                      const Text(
                        'Customize Portal Browser',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16.5,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const Spacer(),
                      IconButton(
                        icon: const Icon(Icons.close_rounded, color: Colors.white54, size: 20),
                        onPressed: () => Navigator.pop(ctx),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Divider(color: Colors.white.withValues(alpha: 0.08)),
                  const SizedBox(height: 12),

                  const Text(
                    'Channel Stream Layout Mode',
                    style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 8),
                  ValueListenableBuilder<PortalBrowserLayout>(
                    valueListenable: IptvSettings.browserLayout,
                    builder: (context, layout, _) {
                      return Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: PortalBrowserLayout.values.map((l) {
                          final isSelected = l == layout;
                          return ChoiceChip(
                            label: Text(l.label),
                            selected: isSelected,
                            selectedColor: palette.primaryColor.withValues(alpha: 0.25),
                            backgroundColor: const Color(0xFF0D1017),
                            labelStyle: TextStyle(
                              color: isSelected ? palette.primaryColor : Colors.white70,
                              fontWeight: isSelected ? FontWeight.w800 : FontWeight.w500,
                              fontSize: 12,
                            ),
                            side: BorderSide(
                              color: isSelected
                                  ? palette.primaryColor.withValues(alpha: 0.6)
                                  : Colors.white.withValues(alpha: 0.08),
                            ),
                            onSelected: (selected) {
                              if (selected) IptvSettings.setBrowserLayout(l);
                            },
                          );
                        }).toList(),
                      );
                    },
                  ),

                  const SizedBox(height: 14),

                  ValueListenableBuilder<PortalBrowserLayout>(
                    valueListenable: IptvSettings.browserLayout,
                    builder: (context, layout, _) {
                      if (layout != PortalBrowserLayout.grid) return const SizedBox.shrink();
                      return ValueListenableBuilder<int>(
                        valueListenable: IptvSettings.browserGridColumns,
                        builder: (context, cols, _) {
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  const Text('Grid Stream Columns', style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
                                  Text('$cols Cols', style: TextStyle(color: palette.primaryColor, fontSize: 12, fontWeight: FontWeight.bold)),
                                ],
                              ),
                              SliderTheme(
                                data: SliderTheme.of(context).copyWith(
                                  activeTrackColor: palette.primaryColor,
                                  inactiveTrackColor: Colors.white12,
                                  thumbColor: palette.primaryColor,
                                  trackHeight: 3,
                                ),
                                child: Slider(
                                  value: cols.toDouble(),
                                  min: 2,
                                  max: 6,
                                  divisions: 4,
                                  onChanged: (val) => IptvSettings.setBrowserGridColumns(val.round()),
                                ),
                              ),
                              const SizedBox(height: 8),
                            ],
                          );
                        },
                      );
                    },
                  ),

                  ValueListenableBuilder<bool>(
                    valueListenable: IptvSettings.showStreamLogos,
                    builder: (context, showLogos, _) {
                      return SwitchListTile.adaptive(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Show Channel Stream Logos', style: TextStyle(color: Colors.white, fontSize: 13.5)),
                        value: showLogos,
                        activeColor: palette.primaryColor,
                        onChanged: (val) => IptvSettings.setShowStreamLogos(val),
                      );
                    },
                  ),

                  ValueListenableBuilder<bool>(
                    valueListenable: IptvSettings.showEpgSnippet,
                    builder: (context, showEpg, _) {
                      return SwitchListTile.adaptive(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Show EPG "Now Playing" Snippet', style: TextStyle(color: Colors.white, fontSize: 13.5)),
                        value: showEpg,
                        activeColor: palette.primaryColor,
                        onChanged: (val) => IptvSettings.setShowEpgSnippet(val),
                      );
                    },
                  ),

                  ValueListenableBuilder<bool>(
                    valueListenable: IptvSettings.showCategoryCount,
                    builder: (context, showCount, _) {
                      return SwitchListTile.adaptive(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Show Category Stream Counts', style: TextStyle(color: Colors.white, fontSize: 13.5)),
                        value: showCount,
                        activeColor: palette.primaryColor,
                        onChanged: (val) => IptvSettings.setShowCategoryCount(val),
                      );
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

  void _updateCategoryScrollState() {
    if (!_categoryScrollController.hasClients) return;
    final canUp = _categoryScrollController.position.pixels > 10;
    final canDown = _categoryScrollController.position.pixels <
        _categoryScrollController.position.maxScrollExtent - 10;
    if (canUp != _canScrollCatUp || canDown != _canScrollCatDown) {
      setState(() {
        _canScrollCatUp = canUp;
        _canScrollCatDown = canDown;
      });
    }
  }

  void _updateContentScrollState() {
    if (!_contentScrollController.hasClients) return;
    final canUp = _contentScrollController.position.pixels > 10;
    final canDown = _contentScrollController.position.pixels <
        _contentScrollController.position.maxScrollExtent - 10;
    if (canUp != _canScrollContentUp || canDown != _canScrollContentDown) {
      setState(() {
        _canScrollContentUp = canUp;
        _canScrollContentDown = canDown;
      });
    }
  }

  void _scrollCategories(double delta) {
    if (!_categoryScrollController.hasClients) return;
    final target = (_categoryScrollController.position.pixels + delta)
        .clamp(0.0, _categoryScrollController.position.maxScrollExtent);
    _categoryScrollController.animateTo(
      target,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
    );
  }

  void _scrollContent(double delta) {
    if (!_contentScrollController.hasClients) return;
    final target = (_contentScrollController.position.pixels + delta)
        .clamp(0.0, _contentScrollController.position.maxScrollExtent);
    _contentScrollController.animateTo(
      target,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
    );
  }

  bool _isDesktop(BuildContext context) {
    return MediaQuery.sizeOf(context).width >= 750;
  }

  String _selectedCategoryName() {
    if (_selectedCategoryId == favoritesCategoryId) return '⭐ Favorites';
    if (_selectedCategoryId.isEmpty) return 'All Categories';
    final found = _categories.firstWhere(
      (c) => c.id == _selectedCategoryId,
      orElse: () => const IptvCategory(id: '', name: 'All Categories'),
    );
    return found.name;
  }

  Future<void> _loadSectionData() async {
    if (widget.portal == null && widget.m3uPlaylist == null) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _searchQuery = '';
      _searchCtrl.clear();
      _catSearchQuery = '';
      _catSearchCtrl.clear();
    });

    try {
      if (widget.portal != null) {
        final p = widget.portal!.portal;
        final cats = await IptvClient.categories(p, _activeSection);
        final streams = await IptvClient.streams(p, _activeSection, '');

        if (!mounted) return;
        setState(() {
          _categories = [
            const IptvCategory(id: '', name: 'All Categories'),
            const IptvCategory(id: favoritesCategoryId, name: 'Favorites'),
            ...cats,
          ];
          _selectedCategoryId = '';
          _allStreams = streams;
          _isLoading = false;
        });

        if (_activeSection == IptvSection.live) {
          _loadSavedAliveSnapshot();
        }
      } else if (widget.m3uPlaylist != null) {
        final pl = widget.m3uPlaylist!;
        final groupNames = pl.channels
            .map((c) => c.group.isNotEmpty ? c.group : 'General')
            .toSet()
            .toList();

        final cats = groupNames
            .map((g) => IptvCategory(id: g, name: g))
            .toList();

        final streams = pl.channels
            .map((c) => IptvStream(
                  streamId: c.url,
                  name: c.name,
                  icon: c.logo,
                  categoryId: c.group.isNotEmpty ? c.group : 'General',
                  containerExt: 'm3u8',
                  kind: 'live',
                ))
            .toList();

        if (!mounted) return;
        setState(() {
          _categories = [
            const IptvCategory(id: '', name: 'All Categories'),
            const IptvCategory(id: favoritesCategoryId, name: 'Favorites'),
            ...cats,
          ];
          _selectedCategoryId = '';
          _allStreams = streams;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = 'Failed to load content: $e';
      });
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _updateCategoryScrollState();
      _updateContentScrollState();
    });
  }

  Future<void> _loadSavedAliveSnapshot() async {
    if (widget.portal == null) return;
    final key = IptvAliveStore.portalKey(widget.portal!.portal);
    final snap = await IptvAliveStore.load(key);
    if (snap != null && mounted) {
      setState(() {
        _aliveStreamIds = snap.aliveIds;
      });
    }
  }

  Future<void> _startAliveCheck() async {
    if (widget.portal == null || _activeSection != IptvSection.live || _isCheckingAlive) return;

    final p = widget.portal!.portal;
    final filtered = _filteredStreams();
    if (filtered.isEmpty) return;

    setState(() {
      _isCheckingAlive = true;
      _aliveChecked = 0;
      _aliveTotal = filtered.length;
      _cancelAlive = false;
    });

    final entries = filtered
        .map((s) => MapEntry(s.streamId, IptvClient.streamUrl(p, s)))
        .toList();

    final aliveSet = Set<String>.from(_aliveStreamIds);

    await IptvAliveChecker.launchCheck(
      streams: entries,
      isCancelled: () => _cancelAlive,
      onResult: (id, alive) async {
        if (alive) {
          aliveSet.add(id);
          if (mounted) setState(() => _aliveStreamIds = aliveSet);
        }
      },
      onProgress: (prog) async {
        if (mounted) {
          setState(() {
            _aliveChecked = prog.checked;
            _aliveTotal = prog.total;
          });
        }
      },
      onDone: () async {
        if (mounted) {
          setState(() => _isCheckingAlive = false);
          final key = IptvAliveStore.portalKey(p);
          await IptvAliveStore.save(
            key,
            AliveSnapshot(
              checkedAt: DateTime.now().millisecondsSinceEpoch,
              aliveIds: aliveSet,
            ),
          );
        }
      },
    );
  }

  List<IptvCategory> _filteredCategories() {
    if (_catSearchQuery.trim().isEmpty) return _categories;
    final q = _catSearchQuery.toLowerCase();
    return _categories.where((c) => c.name.toLowerCase().contains(q)).toList();
  }

  List<IptvStream> _filteredStreams() {
    return _allStreams.where((s) {
      if (_selectedCategoryId == favoritesCategoryId) {
        if (!_favoriteStreamIds.contains(s.streamId)) return false;
      } else if (_selectedCategoryId.isNotEmpty) {
        if (s.categoryId != _selectedCategoryId) return false;
      }
      if (_searchQuery.trim().isEmpty) return true;
      return s.name.toLowerCase().contains(_searchQuery.toLowerCase());
    }).toList();
  }

  int _countForCategory(String catId) {
    if (catId == favoritesCategoryId) {
      return _allStreams.where((s) => _favoriteStreamIds.contains(s.streamId)).length;
    }
    if (catId.isEmpty) return _allStreams.length;
    return _allStreams.where((s) => s.categoryId == catId).length;
  }

  void _playStream(IptvStream stream) {
    if (widget.returning && widget.onStreamSelected != null) {
      final url = widget.portal != null
          ? IptvClient.streamUrl(widget.portal!.portal, stream)
          : stream.streamId;
      widget.onStreamSelected!(url, stream.name);
      Navigator.pop(context);
      return;
    }
    final isLive = _activeSection == IptvSection.live;
    final currentList = _filteredStreams();
    final clickedIndex = currentList.indexWhere((s) => s.streamId == stream.streamId);
    final initialIndex = clickedIndex >= 0 ? clickedIndex : 0;

    final currentCat = _categories.firstWhere(
      (c) => c.id == _selectedCategoryId,
      orElse: () => IptvCategory(id: '', name: isLive ? 'Live Channels' : (_activeSection == IptvSection.vod ? 'Movies' : 'Series')),
    );

    if (widget.portal != null) {
      final p = widget.portal!;
      final hits = currentList.map((s) => ChannelHit(
        portal: p,
        stream: s,
        streamUrl: IptvClient.streamUrl(p.portal, s),
      )).toList();

      final ch = HardcodedChannel(
        id: stream.streamId,
        name: stream.name,
        short: isLive ? 'LIVE' : (_activeSection == IptvSection.vod ? 'VOD' : 'SERIES'),
        category: currentCat.name,
        keywords: [stream.name],
        gradient: const [Color(0xFF7C5CFF), Color(0xFF00D2EF)],
      );

      Navigator.push(
        context,
        LiquidRevealRoute(
          page: IptvPlayerPage(
            channel: ch,
            hits: hits.isNotEmpty
                ? hits
                : [
                    ChannelHit(
                      portal: p,
                      stream: stream,
                      streamUrl: IptvClient.streamUrl(p.portal, stream),
                    ),
                  ],
            initialHitIndex: initialIndex,
            isLive: isLive,
            categoryTitle: currentCat.name,
          ),
        ),
      );
    } else if (widget.m3uPlaylist != null) {
      final hits = currentList.map((s) => ChannelHit(
        portal: VerifiedPortal(
          portal: IptvPortal(url: s.streamId, username: '', password: '', source: 'M3U'),
          name: widget.m3uPlaylist!.name,
          expiry: '',
          maxConnections: '1',
          activeConnections: '0',
        ),
        stream: s,
        streamUrl: s.streamId,
      )).toList();

      final ch = HardcodedChannel(
        id: stream.streamId,
        name: stream.name,
        short: isLive ? 'LIVE' : 'VOD',
        category: currentCat.name,
        keywords: [stream.name],
        gradient: const [Color(0xFF7C5CFF), Color(0xFF00D2EF)],
      );

      Navigator.push(
        context,
        LiquidRevealRoute(
          page: IptvPlayerPage(
            channel: ch,
            hits: hits.isNotEmpty
                ? hits
                : [
                    ChannelHit(
                      portal: VerifiedPortal(
                        portal: IptvPortal(url: stream.streamId, username: '', password: '', source: 'M3U'),
                        name: widget.m3uPlaylist!.name,
                        expiry: '',
                        maxConnections: '1',
                        activeConnections: '0',
                      ),
                      stream: stream,
                      streamUrl: stream.streamId,
                    ),
                  ],
            initialHitIndex: initialIndex,
            isLive: isLive,
            categoryTitle: currentCat.name,
          ),
        ),
      );
    }
  }

  Future<void> _openSeriesEpisodes(IptvStream series) async {
    if (widget.returning && widget.onStreamSelected != null) {
      final url = widget.portal != null
          ? IptvClient.streamUrl(widget.portal!.portal, series)
          : series.streamId;
      widget.onStreamSelected!(url, series.name);
      Navigator.pop(context);
      return;
    }
    if (widget.portal == null) return;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => _SeriesEpisodesSheet(
        portal: widget.portal!,
        series: series,
      ),
    );
  }  void _showMobileCategorySheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            final cats = _filteredCategories();
            return Container(
              height: MediaQuery.sizeOf(context).height * 0.75,
              decoration: const BoxDecoration(
                color: Color(0xFF0C0F17),
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                border: Border(top: BorderSide(color: Color(0xFF22283A), width: 1.2)),
              ),
              child: Column(
                children: [
                  Center(
                    child: Container(
                      margin: const EdgeInsets.only(top: 10, bottom: 12),
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.white24,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Row(
                      children: [
                        const Icon(Icons.folder_rounded, color: Color(0xFF7C5CFF), size: 20),
                        const SizedBox(width: 8),
                        const Text(
                          'Select Category',
                          style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                        const Spacer(),
                        Text(
                          '${_categories.length} total',
                          style: const TextStyle(color: Colors.white38, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Container(
                      height: 40,
                      decoration: BoxDecoration(
                        color: const Color(0xFF141824),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0xFF22283A)),
                      ),
                      child: TextField(
                        controller: _catSearchCtrl,
                        style: const TextStyle(color: Colors.white, fontSize: 13),
                        decoration: InputDecoration(
                          hintText: 'Filter categories…',
                          hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.35), fontSize: 12.5),
                          prefixIcon: const Icon(Icons.search_rounded, color: Colors.white54, size: 18),
                          suffixIcon: _catSearchQuery.isNotEmpty
                              ? IconButton(
                                  icon: const Icon(Icons.close_rounded, color: Colors.white54, size: 16),
                                  onPressed: () {
                                    _catSearchCtrl.clear();
                                    setState(() => _catSearchQuery = '');
                                    setSheetState(() {});
                                  },
                                )
                              : null,
                          border: InputBorder.none,
                          contentPadding: const EdgeInsets.symmetric(vertical: 10),
                        ),
                        onChanged: (v) {
                          setState(() => _catSearchQuery = v);
                          setSheetState(() {});
                        },
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  const Divider(color: Color(0xFF1B2030), height: 1),
                  Expanded(
                    child: ListView.builder(
                      itemCount: cats.length,
                      itemExtent: 50.0,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      itemBuilder: (ctx, i) {
                        final cat = cats[i];
                        final isSelected = _selectedCategoryId == cat.id;
                        final count = _countForCategory(cat.id);
                        return _CategoryListRow(
                          category: cat,
                          count: count,
                          isSelected: isSelected,
                          onTap: () {
                            setState(() => _selectedCategoryId = cat.id);
                            _contentScrollController.jumpTo(0);
                            Navigator.pop(ctx);
                          },
                        );
                      },
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppThemeService.currentPalette.value;
    final title = widget.portal?.name.isNotEmpty == true
        ? widget.portal!.name
        : (widget.m3uPlaylist?.name ?? 'IPTV Portal');

    final isDesktop = _isDesktop(context);

    return Scaffold(
      backgroundColor: const Color(0xFF07090E),
      body: SafeArea(
        child: Column(
          children: [
            // ── TOP APPLICATION HEADER ──
            if (isDesktop)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                decoration: const BoxDecoration(
                  color: Color(0xFF0C0F17),
                  border: Border(
                    bottom: BorderSide(color: Color(0xFF1B2030), width: 1.2),
                  ),
                ),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.arrow_back_rounded, color: Colors.white, size: 22),
                      tooltip: 'Back',
                      onPressed: () => Navigator.pop(context),
                    ),
                    const SizedBox(width: 8),

                    // Portal Emblem & Title
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: palette.primaryColor.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: palette.primaryColor.withValues(alpha: 0.4)),
                      ),
                      child: Icon(Icons.settings_input_antenna_rounded, color: palette.primaryColor, size: 20),
                    ),
                    const SizedBox(width: 12),

                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 0.2,
                            ),
                          ),
                          if (widget.portal != null) ...[
                            const SizedBox(height: 2),
                            Row(
                              children: [
                                Text(
                                  'Expiry: ${widget.portal!.expiry}',
                                  style: const TextStyle(color: Color(0xFF9D4EDD), fontSize: 11, fontWeight: FontWeight.w600),
                                ),
                                const SizedBox(width: 10),
                                Container(width: 3, height: 3, decoration: const BoxDecoration(color: Colors.white30, shape: BoxShape.circle)),
                                const SizedBox(width: 10),
                                Text(
                                  'Connections: ${widget.portal!.activeConnections}/${widget.portal!.maxConnections}',
                                  style: const TextStyle(color: Colors.greenAccent, fontSize: 11, fontWeight: FontWeight.w600),
                                ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),

                    const SizedBox(width: 16),

                    // ── SECTION SWITCHER TABS ──
                    if (widget.portal != null) ...[
                      Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: const Color(0xFF141824),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFF22283A)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _buildSectionTab('Live TV', Icons.live_tv_rounded, IptvSection.live),
                            const SizedBox(width: 4),
                            _buildSectionTab('Movies', Icons.movie_rounded, IptvSection.vod),
                            const SizedBox(width: 4),
                            _buildSectionTab('TV Series', Icons.tv_rounded, IptvSection.series),
                          ],
                        ),
                      ),
                      const SizedBox(width: 16),
                    ],

                    // Search Bar
                    SizedBox(
                      width: 240,
                      height: 40,
                      child: TextField(
                        controller: _searchCtrl,
                        style: const TextStyle(color: Colors.white, fontSize: 13),
                        decoration: InputDecoration(
                          hintText: 'Search channels…',
                          hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.4), fontSize: 12.5),
                          prefixIcon: Icon(Icons.search_rounded, color: palette.primaryColor, size: 18),
                          suffixIcon: _searchQuery.isNotEmpty
                              ? IconButton(
                                  icon: const Icon(Icons.close_rounded, color: Colors.white54, size: 16),
                                  onPressed: () {
                                    _searchCtrl.clear();
                                    setState(() => _searchQuery = '');
                                  },
                                )
                              : null,
                          filled: true,
                          fillColor: const Color(0xFF141824),
                          contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 12),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: const BorderSide(color: Color(0xFF22283A)),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: BorderSide(color: palette.primaryColor, width: 1.4),
                          ),
                        ),
                        onChanged: (v) => setState(() => _searchQuery = v),
                      ),
                    ),

                    // Alive Sniffer Action
                    if (_activeSection == IptvSection.live && widget.portal != null) ...[
                      const SizedBox(width: 12),
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _isCheckingAlive ? const Color(0xFFB91C1C) : palette.primaryColor,
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        icon: _isCheckingAlive
                            ? const SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                              )
                            : const Icon(Icons.speed_rounded, size: 16, color: Colors.white),
                        label: Text(
                          _isCheckingAlive ? 'Stop ($_aliveChecked/$_aliveTotal)' : 'Check Health',
                          style: const TextStyle(color: Colors.white, fontSize: 12.5, fontWeight: FontWeight.w700),
                        ),
                        onPressed: _isCheckingAlive ? () => setState(() => _cancelAlive = true) : _startAliveCheck,
                      ),
                    ],

                    const SizedBox(width: 8),

                    IconButton(
                      icon: const Icon(Icons.tune_rounded, color: Colors.white70, size: 20),
                      tooltip: 'Customize Portal Browser Layout',
                      onPressed: () => _showBrowserCustomizer(context),
                    ),
                  ],
                ),
              )
            else
              // ── MOBILE RESPONSIVE HEADER ──
              Container(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                decoration: const BoxDecoration(
                  color: Color(0xFF0C0F17),
                  border: Border(
                    bottom: BorderSide(color: Color(0xFF1B2030), width: 1.2),
                  ),
                ),
                child: Column(
                  children: [
                    // Top Bar: Back, Portal Title, Health button
                    Row(
                      children: [
                        IconButton(
                          icon: const Icon(Icons.arrow_back_rounded, color: Colors.white, size: 22),
                          onPressed: () => Navigator.pop(context),
                        ),
                        const SizedBox(width: 4),
                        Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: palette.primaryColor.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: palette.primaryColor.withValues(alpha: 0.4)),
                          ),
                          child: Icon(Icons.settings_input_antenna_rounded, color: palette.primaryColor, size: 16),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 15,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              if (widget.portal != null)
                                Text(
                                  'Conn: ${widget.portal!.activeConnections}/${widget.portal!.maxConnections} • ${widget.portal!.expiry}',
                                  style: const TextStyle(color: Colors.white54, fontSize: 10.5),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                            ],
                          ),
                        ),
                        if (_activeSection == IptvSection.live && widget.portal != null)
                          IconButton(
                            tooltip: 'Check Health',
                            icon: _isCheckingAlive
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.redAccent),
                                  )
                                : const Icon(Icons.speed_rounded, color: Color(0xFF00D2EF), size: 20),
                            onPressed: _isCheckingAlive ? () => setState(() => _cancelAlive = true) : _startAliveCheck,
                          ),
                        IconButton(
                          icon: const Icon(Icons.tune_rounded, color: Colors.white70, size: 20),
                          tooltip: 'Customize',
                          onPressed: () => _showBrowserCustomizer(context),
                        ),
                      ],
                    ),

                    const SizedBox(height: 8),

                    // Controls Bar: Category Selector Chip + Section Tabs
                    Row(
                      children: [
                        // Mobile Category Chip
                        InkWell(
                          onTap: () => _showMobileCategorySheet(context),
                          borderRadius: BorderRadius.circular(10),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                            decoration: BoxDecoration(
                              color: const Color(0xFF141824),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: const Color(0xFF7C5CFF).withValues(alpha: 0.5)),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.folder_rounded, color: Color(0xFF7C5CFF), size: 15),
                                const SizedBox(width: 6),
                                ConstrainedBox(
                                  constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.32),
                                  child: Text(
                                    _selectedCategoryName(),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(color: Colors.white, fontSize: 11.5, fontWeight: FontWeight.bold),
                                  ),
                                ),
                                const SizedBox(width: 4),
                                const Icon(Icons.arrow_drop_down_rounded, color: Color(0xFF7C5CFF), size: 18),
                              ],
                            ),
                          ),
                        ),

                        const SizedBox(width: 8),

                        // Section Switchers
                        if (widget.portal != null)
                          Expanded(
                            child: SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              child: Container(
                                padding: const EdgeInsets.all(3),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF141824),
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(color: const Color(0xFF22283A)),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    _buildSectionTab('Live', Icons.live_tv_rounded, IptvSection.live),
                                    const SizedBox(width: 2),
                                    _buildSectionTab('Movies', Icons.movie_rounded, IptvSection.vod),
                                    const SizedBox(width: 2),
                                    _buildSectionTab('Series', Icons.tv_rounded, IptvSection.series),
                                  ],
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),

                    const SizedBox(height: 8),

                    // Search Input
                    Container(
                      height: 38,
                      decoration: BoxDecoration(
                        color: const Color(0xFF141824),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0xFF22283A)),
                      ),
                      child: TextField(
                        controller: _searchCtrl,
                        style: const TextStyle(color: Colors.white, fontSize: 12.5),
                        decoration: InputDecoration(
                          hintText: 'Search in this category…',
                          hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.35), fontSize: 12),
                          prefixIcon: const Icon(Icons.search_rounded, color: Color(0xFF7C5CFF), size: 18),
                          suffixIcon: _searchQuery.isNotEmpty
                              ? IconButton(
                                  icon: const Icon(Icons.close_rounded, color: Colors.white54, size: 16),
                                  onPressed: () {
                                    _searchCtrl.clear();
                                    setState(() => _searchQuery = '');
                                  },
                                )
                              : null,
                          border: InputBorder.none,
                          contentPadding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
                        ),
                        onChanged: (v) => setState(() => _searchQuery = v),
                      ),
                    ),
                  ],
                ),
              ),

            // ── MAIN CONTENT (SPLIT VIEW ON DESKTOP, FULL-WIDTH ON MOBILE) ──
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator(color: Color(0xFF7C5CFF)))
                  : _errorMessage != null
                      ? Center(child: Text(_errorMessage!, style: const TextStyle(color: Colors.redAccent, fontSize: 15)))
                      : isDesktop
                          ? Row(
                              children: [
                                // ── LEFT CATEGORIES PANEL ──
                                SizedBox(
                                  width: IptvSettings.sidebarWidth.value,
                                  child: Container(
                                    decoration: const BoxDecoration(
                                      color: Color(0xFF0A0D14),
                                      border: Border(
                                        right: BorderSide(color: Color(0xFF1B2030), width: 1.2),
                                      ),
                                    ),
                                    child: Column(
                                      children: [
                                        // Categories Search Filter
                                        Padding(
                                          padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
                                          child: Container(
                                            height: 38,
                                            decoration: BoxDecoration(
                                              color: const Color(0xFF141824),
                                              borderRadius: BorderRadius.circular(8),
                                              border: Border.all(color: const Color(0xFF22283A)),
                                            ),
                                            child: TextField(
                                              controller: _catSearchCtrl,
                                              style: const TextStyle(color: Colors.white, fontSize: 12.5),
                                              decoration: InputDecoration(
                                                hintText: 'Filter categories…',
                                                hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.35), fontSize: 12),
                                                prefixIcon: const Icon(Icons.filter_list_rounded, color: Colors.white54, size: 18),
                                                suffixIcon: _catSearchQuery.isNotEmpty
                                                    ? IconButton(
                                                        icon: const Icon(Icons.close_rounded, color: Colors.white54, size: 16),
                                                        onPressed: () {
                                                          _catSearchCtrl.clear();
                                                          setState(() => _catSearchQuery = '');
                                                        },
                                                      )
                                                    : null,
                                                border: InputBorder.none,
                                                contentPadding: const EdgeInsets.symmetric(vertical: 8),
                                              ),
                                              onChanged: (v) => setState(() => _catSearchQuery = v),
                                            ),
                                          ),
                                        ),

                                        // Category List with Desktop Vertical Scroll Arrows
                                        Expanded(
                                          child: MouseRegion(
                                            onEnter: (_) => setState(() => _isHoveringCategories = true),
                                            onExit: (_) => setState(() => _isHoveringCategories = false),
                                            child: Stack(
                                              children: [
                                                ListView.builder(
                                                  controller: _categoryScrollController,
                                                  itemExtent: 46.0,
                                                  cacheExtent: 300.0,
                                                  addAutomaticKeepAlives: false,
                                                  addRepaintBoundaries: true,
                                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                                  itemCount: _filteredCategories().length,
                                                  itemBuilder: (context, index) {
                                                    final cat = _filteredCategories()[index];
                                                    final isSelected = _selectedCategoryId == cat.id;
                                                    final count = _countForCategory(cat.id);

                                                    return _CategoryListRow(
                                                      category: cat,
                                                      count: count,
                                                      isSelected: isSelected,
                                                      onTap: () {
                                                        setState(() => _selectedCategoryId = cat.id);
                                                        _contentScrollController.jumpTo(0);
                                                      },
                                                    );
                                                  },
                                                ),

                                                // Desktop Category Scroll Up Arrow
                                                if (_isHoveringCategories && _canScrollCatUp)
                                                  Positioned(
                                                    top: 6,
                                                    left: 0,
                                                    right: 0,
                                                    child: Center(
                                                      child: _VerticalScrollButton(
                                                        icon: Icons.keyboard_arrow_up_rounded,
                                                        onTap: () => _scrollCategories(-240),
                                                      ),
                                                    ),
                                                  ),

                                                // Desktop Category Scroll Down Arrow
                                                if (_isHoveringCategories && _canScrollCatDown)
                                                  Positioned(
                                                    bottom: 6,
                                                    left: 0,
                                                    right: 0,
                                                    child: Center(
                                                      child: _VerticalScrollButton(
                                                        icon: Icons.keyboard_arrow_down_rounded,
                                                        onTap: () => _scrollCategories(240),
                                                      ),
                                                    ),
                                                  ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),

                                // ── RIGHT CONTENT PANEL ──
                                Expanded(
                                  child: MouseRegion(
                                    onEnter: (_) => setState(() => _isHoveringContent = true),
                                    onExit: (_) => setState(() => _isHoveringContent = false),
                                    child: Stack(
                                      children: [
                                        _buildMainContent(),

                                        // Desktop Content Scroll Up Arrow
                                        if (_isHoveringContent && _canScrollContentUp)
                                          Positioned(
                                            top: 14,
                                            right: 28,
                                            child: _VerticalScrollButton(
                                              icon: Icons.keyboard_arrow_up_rounded,
                                              onTap: () => _scrollContent(-450),
                                            ),
                                          ),

                                        // Desktop Content Scroll Down Arrow
                                        if (_isHoveringContent && _canScrollContentDown)
                                          Positioned(
                                            bottom: 14,
                                            right: 28,
                                            child: _VerticalScrollButton(
                                              icon: Icons.keyboard_arrow_down_rounded,
                                              onTap: () => _scrollContent(450),
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            )
                          : _buildMainContent(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionTab(String label, IconData icon, IptvSection section) {
    final palette = AppThemeService.currentPalette.value;
    final isSelected = _activeSection == section;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () {
          if (_activeSection != section) {
            setState(() => _activeSection = section);
            _loadSectionData();
          }
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          decoration: BoxDecoration(
            color: isSelected ? palette.primaryColor : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                color: isSelected ? Colors.white : Colors.white60,
                size: 16,
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  color: isSelected ? Colors.white : Colors.white70,
                  fontSize: 13,
                  fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMainContent() {
    final streams = _filteredStreams();
    if (streams.isEmpty) {
      if (_selectedCategoryId == favoritesCategoryId) {
        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFC107).withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.star_outline_rounded, color: Color(0xFFFFC107), size: 48),
              ),
              const SizedBox(height: 16),
              const Text(
                'No Favorited Channels',
                style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 6),
              const Text(
                'Tap the star icon on any channel to save it to your Favorites.',
                style: TextStyle(color: Colors.white54, fontSize: 13.5),
              ),
            ],
          ),
        );
      }
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.tv_off_rounded, color: Colors.white24, size: 48),
            const SizedBox(height: 12),
            Text(
              _searchQuery.isNotEmpty
                  ? 'No streams matching "$_searchQuery"'
                  : 'No streams available in this category.',
              style: const TextStyle(color: Colors.white54, fontSize: 15),
            ),
          ],
        ),
      );
    }

    final isDesktop = _isDesktop(context);

    if (_activeSection == IptvSection.live) {
      final layout = IptvSettings.browserLayout.value;

      if (layout == PortalBrowserLayout.grid) {
        final screenW = MediaQuery.sizeOf(context).width;
        int gridCols = IptvSettings.browserGridColumns.value;
        if (!isDesktop) {
          gridCols = screenW > 600 ? 3 : 2;
        }

        return GridView.builder(
          controller: _contentScrollController,
          cacheExtent: 400.0,
          addAutomaticKeepAlives: false,
          addRepaintBoundaries: true,
          padding: EdgeInsets.fromLTRB(isDesktop ? 20 : 10, 12, isDesktop ? 20 : 10, 30),
          physics: const BouncingScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: gridCols,
            childAspectRatio: 1.25,
            crossAxisSpacing: isDesktop ? 14 : 10,
            mainAxisSpacing: isDesktop ? 14 : 10,
          ),
          itemCount: streams.length,
          itemBuilder: (context, index) {
            final stream = streams[index];
            final isAlive = _aliveStreamIds.contains(stream.streamId);
            final isFav = _favoriteStreamIds.contains(stream.streamId);

            return _LiveChannelGridCard(
              key: ValueKey(stream.streamId),
              index: index + 1,
              stream: stream,
              portal: widget.portal,
              isAlive: isAlive,
              isFavorite: isFav,
              onToggleFavorite: () => _toggleFavoriteStream(stream.streamId),
              onTap: () => _playStream(stream),
            );
          },
        );
      } else if (layout == PortalBrowserLayout.compactList) {
        return ListView.builder(
          controller: _contentScrollController,
          itemExtent: 52.0,
          cacheExtent: 400.0,
          addAutomaticKeepAlives: false,
          addRepaintBoundaries: true,
          padding: EdgeInsets.fromLTRB(isDesktop ? 20 : 10, 12, isDesktop ? 20 : 10, 30),
          physics: const BouncingScrollPhysics(),
          itemCount: streams.length,
          itemBuilder: (context, index) {
            final stream = streams[index];
            final isAlive = _aliveStreamIds.contains(stream.streamId);
            final isFav = _favoriteStreamIds.contains(stream.streamId);

            return Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: _LiveChannelCompactListRow(
                key: ValueKey(stream.streamId),
                index: index + 1,
                stream: stream,
                portal: widget.portal,
                isAlive: isAlive,
                isFavorite: isFav,
                onToggleFavorite: () => _toggleFavoriteStream(stream.streamId),
                onTap: () => _playStream(stream),
              ),
            );
          },
        );
      } else {
        // Detailed List view
        return ListView.builder(
          controller: _contentScrollController,
          itemExtent: 78.0,
          cacheExtent: 400.0,
          addAutomaticKeepAlives: false,
          addRepaintBoundaries: true,
          padding: EdgeInsets.fromLTRB(isDesktop ? 20 : 10, 12, isDesktop ? 20 : 10, 30),
          physics: const BouncingScrollPhysics(),
          itemCount: streams.length,
          itemBuilder: (context, index) {
            final stream = streams[index];
            final isAlive = _aliveStreamIds.contains(stream.streamId);
            final isFav = _favoriteStreamIds.contains(stream.streamId);

            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _LiveChannelListRow(
                key: ValueKey(stream.streamId),
                index: index + 1,
                stream: stream,
                portal: widget.portal,
                isAlive: isAlive,
                isFavorite: isFav,
                onToggleFavorite: () => _toggleFavoriteStream(stream.streamId),
                onTap: () => _playStream(stream),
              ),
            );
          },
        );
      }
    } else {
      // ── MOVIES & SERIES GRID VIEW ──
      final screenW = MediaQuery.sizeOf(context).width;
      final sidebarW = isDesktop ? IptvSettings.sidebarWidth.value : 0.0;
      final width = isDesktop ? (screenW - sidebarW) : screenW;
      int crossAxisCount = 2;
      if (width > 1200) {
        crossAxisCount = 6;
      } else if (width > 900) {
        crossAxisCount = 5;
      } else if (width > 650) {
        crossAxisCount = 4;
      } else if (width > 420) {
        crossAxisCount = 3;
      } else {
        crossAxisCount = 2;
      }

      return GridView.builder(
        controller: _contentScrollController,
        cacheExtent: 400.0,
        addAutomaticKeepAlives: false,
        addRepaintBoundaries: true,
        padding: EdgeInsets.fromLTRB(isDesktop ? 20 : 10, 12, isDesktop ? 20 : 10, 30),
        physics: const BouncingScrollPhysics(),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: crossAxisCount,
          childAspectRatio: 0.68,
          crossAxisSpacing: isDesktop ? 14 : 10,
          mainAxisSpacing: isDesktop ? 14 : 10,
        ),
        itemCount: streams.length,
        itemBuilder: (context, index) {
          final stream = streams[index];
          final isFav = _favoriteStreamIds.contains(stream.streamId);

          if (_activeSection == IptvSection.series) {
            return _VodSeriesCard(
              key: ValueKey(stream.streamId),
              stream: stream,
              isSeries: true,
              isFavorite: isFav,
              onToggleFavorite: () => _toggleFavoriteStream(stream.streamId),
              onTap: () => _openSeriesEpisodes(stream),
            );
          } else {
            return _VodSeriesCard(
              key: ValueKey(stream.streamId),
              stream: stream,
              isSeries: false,
              isFavorite: isFav,
              onToggleFavorite: () => _toggleFavoriteStream(stream.streamId),
              onTap: () => _playStream(stream),
            );
          }
        },
      );
    }
  }
}

class _CategoryListRow extends StatefulWidget {
  final IptvCategory category;
  final int count;
  final bool isSelected;
  final VoidCallback onTap;

  const _CategoryListRow({
    required this.category,
    required this.count,
    required this.isSelected,
    required this.onTap,
  });

  @override
  State<_CategoryListRow> createState() => _CategoryListRowState();
}

class _CategoryListRowState extends State<_CategoryListRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final palette = AppThemeService.currentPalette.value;
    final isFavCategory = widget.category.id == _IptvPortalBrowserPageState.favoritesCategoryId;
    final showCount = IptvSettings.showCategoryCount.value;

    return RepaintBoundary(
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: widget.isSelected
                  ? (isFavCategory ? const Color(0xFFFFC107).withValues(alpha: 0.15) : palette.primaryColor.withValues(alpha: 0.15))
                  : (_hovered ? const Color(0xFF141724) : Colors.transparent),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: widget.isSelected
                    ? (isFavCategory ? const Color(0xFFFFC107).withValues(alpha: 0.6) : palette.primaryColor.withValues(alpha: 0.6))
                    : Colors.transparent,
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 3.5,
                  height: 16,
                  decoration: BoxDecoration(
                    color: widget.isSelected
                        ? (isFavCategory ? const Color(0xFFFFC107) : palette.primaryColor)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: 8),
                if (isFavCategory) ...[
                  const Icon(Icons.star_rounded, color: Color(0xFFFFC107), size: 16),
                  const SizedBox(width: 6),
                ],
                Expanded(
                  child: Text(
                    widget.category.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: widget.isSelected
                          ? (isFavCategory ? const Color(0xFFFFD54F) : Colors.white)
                          : (_hovered ? Colors.white : (isFavCategory ? const Color(0xFFFFC107) : Colors.white70)),
                      fontSize: 12.5,
                      fontWeight: widget.isSelected ? FontWeight.w800 : (isFavCategory ? FontWeight.w700 : FontWeight.w600),
                    ),
                  ),
                ),
                if (showCount) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                    decoration: BoxDecoration(
                      color: widget.isSelected
                          ? (isFavCategory ? const Color(0xFFFFC107).withValues(alpha: 0.3) : palette.primaryColor.withValues(alpha: 0.3))
                          : (isFavCategory ? const Color(0xFFFFC107).withValues(alpha: 0.12) : Colors.white.withValues(alpha: 0.06)),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '${widget.count}',
                      style: TextStyle(
                        color: isFavCategory
                            ? const Color(0xFFFFC107)
                            : (widget.isSelected ? palette.primaryColor : Colors.white38),
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
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
}

class _LiveChannelListRow extends StatefulWidget {
  final int index;
  final IptvStream stream;
  final VerifiedPortal? portal;
  final bool isAlive;
  final bool isFavorite;
  final VoidCallback onToggleFavorite;
  final VoidCallback onTap;

  const _LiveChannelListRow({
    super.key,
    required this.index,
    required this.stream,
    this.portal,
    required this.isAlive,
    required this.isFavorite,
    required this.onToggleFavorite,
    required this.onTap,
  });

  @override
  State<_LiveChannelListRow> createState() => _LiveChannelListRowState();
}

class _LiveChannelListRowState extends State<_LiveChannelListRow> {
  bool _hovered = false;
  List<EpgEntry>? _cachedEpg;

  @override
  void initState() {
    super.initState();
    _cachedEpg = _IptvPortalBrowserPageState._sharedEpgCache[widget.stream.streamId];
  }

  void _loadEpg() async {
    if (!IptvSettings.showEpgSnippet.value) return;
    if (_cachedEpg != null || widget.portal == null || widget.stream.streamId.isEmpty) return;
    try {
      final entries = await IptvClient.shortEpg(widget.portal!.portal, widget.stream.streamId, limit: 2);
      if (mounted && entries.isNotEmpty) {
        _IptvPortalBrowserPageState._sharedEpgCache[widget.stream.streamId] = entries;
        setState(() => _cachedEpg = entries);
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppThemeService.currentPalette.value;
    final s = widget.stream;
    final indexFormatted = widget.index.toString().padLeft(3, '0');
    final currentEpg = _cachedEpg?.isNotEmpty == true ? _cachedEpg!.first : null;
    final nextEpg = _cachedEpg != null && _cachedEpg!.length > 1 ? _cachedEpg![1] : null;
    final screenW = MediaQuery.sizeOf(context).width;
    final isVerySmall = screenW < 440;
    final showLogo = IptvSettings.showStreamLogos.value;
    final showEpg = IptvSettings.showEpgSnippet.value;

    return RepaintBoundary(
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) {
          setState(() => _hovered = true);
          _loadEpg();
        },
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            padding: EdgeInsets.symmetric(horizontal: isVerySmall ? 8 : 14, vertical: 8),
            decoration: BoxDecoration(
              color: _hovered ? const Color(0xFF161A28) : const Color(0xFF0E111A),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: _hovered ? palette.primaryColor.withValues(alpha: 0.7) : const Color(0xFF1B2030),
                width: _hovered ? 1.4 : 1.0,
              ),
              boxShadow: _hovered
                  ? [
                      BoxShadow(
                        color: palette.primaryColor.withValues(alpha: 0.2),
                        blurRadius: 10,
                        offset: const Offset(0, 2),
                      ),
                    ]
                  : null,
            ),
            child: Row(
              children: [
                // Index
                if (!isVerySmall) ...[
                  SizedBox(
                    width: 30,
                    child: Text(
                      indexFormatted,
                      style: const TextStyle(
                        color: Colors.white24,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                ],

                // ── CHANNEL LOGO BAY ──
                if (showLogo) ...[
                  Container(
                    width: isVerySmall ? 52 : 64,
                    height: isVerySmall ? 40 : 46,
                    padding: const EdgeInsets.all(3),
                    decoration: BoxDecoration(
                      color: const Color(0xFF080A10),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: const Color(0xFF1E2336)),
                    ),
                    child: s.icon.isNotEmpty
                        ? ClipRRect(
                            borderRadius: BorderRadius.circular(5),
                            child: CachedNetworkImage(
                              imageUrl: s.icon,
                              fit: BoxFit.contain,
                              memCacheWidth: 128,
                              errorWidget: (_, _, _) => const Icon(Icons.live_tv_rounded, color: Colors.white38, size: 20),
                            ),
                          )
                        : const Icon(Icons.live_tv_rounded, color: Colors.white38, size: 20),
                  ),
                  SizedBox(width: isVerySmall ? 8 : 12),
                ],

                // Channel Title & EPG Info
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              s.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 14,
                                fontWeight: FontWeight.w800,
                                letterSpacing: -0.2,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          if (widget.isAlive)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                              decoration: BoxDecoration(
                                color: Colors.greenAccent.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(color: Colors.greenAccent.withValues(alpha: 0.4)),
                              ),
                              child: const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.fiber_manual_record_rounded, color: Colors.greenAccent, size: 7),
                                  SizedBox(width: 3),
                                  Text(
                                    'LIVE',
                                    style: TextStyle(color: Colors.greenAccent, fontSize: 9, fontWeight: FontWeight.w900),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),

                      if (showEpg) ...[
                        const SizedBox(height: 2),
                        if (currentEpg != null) ...[
                          Text(
                            'NOW: ${currentEpg.title}${nextEpg != null ? "  |  NEXT: ${nextEpg.title}" : ""}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(color: Colors.white.withValues(alpha: 0.65), fontSize: 11),
                          ),
                        ] else ...[
                          Text(
                            'Live Stream Feed',
                            style: TextStyle(color: Colors.white.withValues(alpha: 0.3), fontSize: 11),
                          ),
                        ],
                      ],
                    ],
                  ),
                ),

                const SizedBox(width: 10),

                // Format Tag
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                  decoration: BoxDecoration(
                    color: const Color(0xFF141824),
                    borderRadius: BorderRadius.circular(5),
                    border: Border.all(color: const Color(0xFF22283A)),
                  ),
                  child: Text(
                    s.containerExt.toUpperCase(),
                    style: const TextStyle(color: Colors.white60, fontSize: 9.5, fontWeight: FontWeight.w800),
                  ),
                ),

                const SizedBox(width: 6),

                // Favorite Button
                IconButton(
                  icon: Icon(
                    widget.isFavorite ? Icons.star_rounded : Icons.star_outline_rounded,
                    color: widget.isFavorite ? const Color(0xFFFFC107) : Colors.white38,
                    size: 21,
                  ),
                  tooltip: widget.isFavorite ? 'Remove from Favorites' : 'Add to Favorites',
                  onPressed: widget.onToggleFavorite,
                ),

                const SizedBox(width: 4),

                // Play Icon Button
                AnimatedContainer(
                  duration: const Duration(milliseconds: 120),
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: _hovered ? palette.primaryColor : Colors.white.withValues(alpha: 0.06),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.play_arrow_rounded,
                    color: Colors.white,
                    size: 20,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _LiveChannelGridCard extends StatefulWidget {
  final int index;
  final IptvStream stream;
  final VerifiedPortal? portal;
  final bool isAlive;
  final bool isFavorite;
  final VoidCallback onToggleFavorite;
  final VoidCallback onTap;

  const _LiveChannelGridCard({
    super.key,
    required this.index,
    required this.stream,
    this.portal,
    required this.isAlive,
    required this.isFavorite,
    required this.onToggleFavorite,
    required this.onTap,
  });

  @override
  State<_LiveChannelGridCard> createState() => _LiveChannelGridCardState();
}

class _LiveChannelGridCardState extends State<_LiveChannelGridCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final palette = AppThemeService.currentPalette.value;
    final s = widget.stream;
    final showLogo = IptvSettings.showStreamLogos.value;

    return RepaintBoundary(
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 140),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: _hovered ? const Color(0xFF161A28) : const Color(0xFF0E111A),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: _hovered ? palette.primaryColor.withValues(alpha: 0.8) : const Color(0xFF1B2030),
                width: _hovered ? 1.5 : 1.0,
              ),
              boxShadow: _hovered
                  ? [
                      BoxShadow(
                        color: palette.primaryColor.withValues(alpha: 0.22),
                        blurRadius: 14,
                        offset: const Offset(0, 4),
                      ),
                    ]
                  : null,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Top row: logo/index + live badge + star
                Row(
                  children: [
                    if (showLogo && s.icon.isNotEmpty)
                      Container(
                        width: 44,
                        height: 32,
                        padding: const EdgeInsets.all(2),
                        decoration: BoxDecoration(
                          color: const Color(0xFF080A10),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: const Color(0xFF1E2336)),
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: CachedNetworkImage(
                            imageUrl: s.icon,
                            fit: BoxFit.contain,
                            memCacheWidth: 100,
                            errorWidget: (_, _, _) => const Icon(Icons.live_tv_rounded, color: Colors.white38, size: 16),
                          ),
                        ),
                      )
                    else
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.06),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          '#${widget.index}',
                          style: const TextStyle(color: Colors.white54, fontSize: 10, fontWeight: FontWeight.bold),
                        ),
                      ),

                    const Spacer(),

                    if (widget.isAlive)
                      Container(
                        margin: const EdgeInsets.only(right: 6),
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                        decoration: BoxDecoration(
                          color: Colors.greenAccent.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: Colors.greenAccent.withValues(alpha: 0.4)),
                        ),
                        child: const Text('LIVE', style: TextStyle(color: Colors.greenAccent, fontSize: 9, fontWeight: FontWeight.w900)),
                      ),

                    GestureDetector(
                      onTap: widget.onToggleFavorite,
                      child: Icon(
                        widget.isFavorite ? Icons.star_rounded : Icons.star_outline_rounded,
                        color: widget.isFavorite ? const Color(0xFFFFC107) : Colors.white30,
                        size: 19,
                      ),
                    ),
                  ],
                ),

                const Spacer(),

                // Channel Title
                Text(
                  s.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    height: 1.2,
                  ),
                ),

                const SizedBox(height: 6),

                // Bottom row: format tag + Play Icon
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                      decoration: BoxDecoration(
                        color: const Color(0xFF141824),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: const Color(0xFF22283A)),
                      ),
                      child: Text(
                        s.containerExt.toUpperCase(),
                        style: const TextStyle(color: Colors.white60, fontSize: 9, fontWeight: FontWeight.w800),
                      ),
                    ),
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 120),
                      width: 26,
                      height: 26,
                      decoration: BoxDecoration(
                        color: _hovered ? palette.primaryColor : Colors.white.withValues(alpha: 0.06),
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
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _LiveChannelCompactListRow extends StatefulWidget {
  final int index;
  final IptvStream stream;
  final VerifiedPortal? portal;
  final bool isAlive;
  final bool isFavorite;
  final VoidCallback onToggleFavorite;
  final VoidCallback onTap;

  const _LiveChannelCompactListRow({
    super.key,
    required this.index,
    required this.stream,
    this.portal,
    required this.isAlive,
    required this.isFavorite,
    required this.onToggleFavorite,
    required this.onTap,
  });

  @override
  State<_LiveChannelCompactListRow> createState() => _LiveChannelCompactListRowState();
}

class _LiveChannelCompactListRowState extends State<_LiveChannelCompactListRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final palette = AppThemeService.currentPalette.value;
    final s = widget.stream;
    final showLogo = IptvSettings.showStreamLogos.value;

    return RepaintBoundary(
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: _hovered ? const Color(0xFF161A28) : const Color(0xFF0E111A),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: _hovered ? palette.primaryColor.withValues(alpha: 0.7) : const Color(0xFF1B2030),
              ),
            ),
            child: Row(
              children: [
                SizedBox(
                  width: 28,
                  child: Text(
                    widget.index.toString().padLeft(3, '0'),
                    style: const TextStyle(color: Colors.white24, fontSize: 11, fontFamily: 'monospace', fontWeight: FontWeight.bold),
                  ),
                ),
                if (showLogo && s.icon.isNotEmpty) ...[
                  const SizedBox(width: 6),
                  SizedBox(
                    width: 32,
                    height: 24,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: CachedNetworkImage(
                        imageUrl: s.icon,
                        fit: BoxFit.contain,
                        memCacheWidth: 64,
                        errorWidget: (_, _, _) => const Icon(Icons.live_tv_rounded, color: Colors.white24, size: 14),
                      ),
                    ),
                  ),
                ],
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    s.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w700),
                  ),
                ),
                if (widget.isAlive) ...[
                  Container(
                    margin: const EdgeInsets.only(right: 8),
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                    decoration: BoxDecoration(
                      color: Colors.greenAccent.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Text('LIVE', style: TextStyle(color: Colors.greenAccent, fontSize: 9, fontWeight: FontWeight.w900)),
                  ),
                ],
                GestureDetector(
                  onTap: widget.onToggleFavorite,
                  child: Icon(
                    widget.isFavorite ? Icons.star_rounded : Icons.star_outline_rounded,
                    color: widget.isFavorite ? const Color(0xFFFFC107) : Colors.white30,
                    size: 18,
                  ),
                ),
                const SizedBox(width: 8),
                Icon(
                  Icons.play_arrow_rounded,
                  color: _hovered ? palette.primaryColor : Colors.white38,
                  size: 18,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _VodSeriesCard extends StatefulWidget {
  final IptvStream stream;
  final bool isSeries;
  final bool isFavorite;
  final VoidCallback onToggleFavorite;
  final VoidCallback onTap;

  const _VodSeriesCard({
    super.key,
    required this.stream,
    required this.isSeries,
    required this.isFavorite,
    required this.onToggleFavorite,
    required this.onTap,
  });

  @override
  State<_VodSeriesCard> createState() => _VodSeriesCardState();
}

class _VodSeriesCardState extends State<_VodSeriesCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final s = widget.stream;

    return RepaintBoundary(
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          onTap: widget.onTap,
          child: AnimatedScale(
            duration: const Duration(milliseconds: 140),
            scale: _hovered ? 1.035 : 1.0,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFF141824),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: _hovered ? const Color(0xFF7C5CFF) : const Color(0xFF22283A),
                        width: _hovered ? 1.4 : 1.0,
                      ),
                      boxShadow: _hovered
                          ? [
                              BoxShadow(
                                color: const Color(0xFF7C5CFF).withValues(alpha: 0.3),
                                blurRadius: 12,
                                offset: const Offset(0, 3),
                              ),
                            ]
                          : null,
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(11),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          s.icon.isNotEmpty
                              ? CachedNetworkImage(
                                  imageUrl: s.icon,
                                  fit: BoxFit.cover,
                                  memCacheWidth: 256,
                                  errorWidget: (_, _, _) => const Center(
                                    child: Icon(Icons.movie_rounded, color: Colors.white38, size: 32),
                                  ),
                                )
                              : const Center(
                                  child: Icon(Icons.movie_rounded, color: Colors.white38, size: 32),
                                ),
                          if (_hovered)
                            Positioned.fill(
                              child: Container(
                                color: Colors.black45,
                                child: const Center(
                                  child: Icon(Icons.play_circle_fill_rounded, color: Color(0xFF7C5CFF), size: 40),
                                ),
                              ),
                            ),
                          // Floating Favorite Star Button
                          Positioned(
                            top: 8,
                            right: 8,
                            child: Material(
                              color: Colors.transparent,
                              child: InkWell(
                                onTap: widget.onToggleFavorite,
                                borderRadius: BorderRadius.circular(16),
                                child: Container(
                                  padding: const EdgeInsets.all(5),
                                  decoration: BoxDecoration(
                                    color: Colors.black.withValues(alpha: 0.75),
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: widget.isFavorite ? const Color(0xFFFFC107) : Colors.white24,
                                      width: 1.2,
                                    ),
                                  ),
                                  child: Icon(
                                    widget.isFavorite ? Icons.star_rounded : Icons.star_outline_rounded,
                                    color: widget.isFavorite ? const Color(0xFFFFC107) : Colors.white70,
                                    size: 16,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  s.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SeriesEpisodesSheet extends StatefulWidget {
  final VerifiedPortal portal;
  final IptvStream series;

  const _SeriesEpisodesSheet({required this.portal, required this.series});

  @override
  State<_SeriesEpisodesSheet> createState() => _SeriesEpisodesSheetState();
}

class _SeriesEpisodesSheetState extends State<_SeriesEpisodesSheet> {
  bool _isLoading = true;
  List<IptvEpisode> _episodes = [];
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadEpisodes();
  }

  Future<void> _loadEpisodes() async {
    try {
      final eps = await IptvClient.seriesEpisodes(widget.portal.portal, widget.series.streamId);
      if (mounted) {
        setState(() {
          _episodes = eps;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = '$e';
          _isLoading = false;
        });
      }
    }
  }

  void _playEpisode(IptvEpisode ep) {
    final epIndex = _episodes.indexWhere((e) => e.id == ep.id);
    final initialIndex = epIndex >= 0 ? epIndex : 0;

    final hits = _episodes.map((e) {
      final s = IptvStream(
        streamId: e.id,
        name: '${widget.series.name} - S${e.season}E${e.episode} ${e.title}',
        icon: e.image.isNotEmpty ? e.image : widget.series.icon,
        categoryId: widget.series.categoryId,
        containerExt: e.containerExt,
        kind: 'series',
      );
      return ChannelHit(
        portal: widget.portal,
        stream: s,
        streamUrl: IptvClient.streamUrl(widget.portal.portal, s),
      );
    }).toList();

    final currentStream = (hits.isNotEmpty && initialIndex < hits.length)
        ? hits[initialIndex].stream
        : IptvStream(
            streamId: ep.id,
            name: '${widget.series.name} - S${ep.season}E${ep.episode} ${ep.title}',
            icon: ep.image.isNotEmpty ? ep.image : widget.series.icon,
            categoryId: widget.series.categoryId,
            containerExt: ep.containerExt,
            kind: 'series',
          );

    final ch = HardcodedChannel(
      id: ep.id,
      name: currentStream.name,
      short: 'TV',
      category: widget.series.name,
      keywords: [widget.series.name],
      gradient: const [Color(0xFF7C5CFF), Color(0xFF00D2EF)],
    );

    Navigator.pop(context);
    Navigator.push(
      context,
      LiquidRevealRoute(
        page: IptvPlayerPage(
          channel: ch,
          hits: hits.isNotEmpty
              ? hits
              : [
                  ChannelHit(
                    portal: widget.portal,
                    stream: currentStream,
                    streamUrl: IptvClient.streamUrl(widget.portal.portal, currentStream),
                  ),
                ],
          initialHitIndex: initialIndex,
          isLive: false,
          categoryTitle: '${widget.series.name} Episodes',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.8,
      ),
      decoration: const BoxDecoration(
        color: Color(0xFF0C0E15),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          // Handle
          Center(
            child: Container(
              margin: const EdgeInsets.only(top: 12, bottom: 8),
              width: 44,
              height: 4.5,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(3),
              ),
            ),
          ),

          Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    widget.series.name,
                    style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w900),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded, color: Colors.white54),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),

          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator(color: Color(0xFF7C5CFF)))
                : _error != null
                    ? Center(child: Text(_error!, style: const TextStyle(color: Colors.redAccent)))
                    : ListView.separated(
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                        itemCount: _episodes.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 8),
                        itemBuilder: (context, index) {
                          final ep = _episodes[index];
                          return ListTile(
                            tileColor: const Color(0xFF141824),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            leading: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: const Color(0xFF7C5CFF).withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                'S${ep.season}E${ep.episode}',
                                style: const TextStyle(color: Color(0xFF9D4EDD), fontWeight: FontWeight.w800),
                              ),
                            ),
                            title: Text(
                              ep.title.isNotEmpty ? ep.title : 'Episode ${ep.episode}',
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
                            ),
                            trailing: const Icon(Icons.play_circle_fill_rounded, color: Color(0xFF7C5CFF)),
                            onTap: () => _playEpisode(ep),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}

class _VerticalScrollButton extends StatefulWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _VerticalScrollButton({required this.icon, required this.onTap});

  @override
  State<_VerticalScrollButton> createState() => _VerticalScrollButtonState();
}

class _VerticalScrollButtonState extends State<_VerticalScrollButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: _hovered ? const Color(0xFF7C5CFF) : Colors.black87,
            shape: BoxShape.circle,
            border: Border.all(
              color: _hovered ? const Color(0xFF7C5CFF) : Colors.white.withValues(alpha: 0.3),
              width: 1.2,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.5),
                blurRadius: 8,
              ),
            ],
          ),
          child: Icon(
            widget.icon,
            color: Colors.white,
            size: 22,
          ),
        ),
      ),
    );
  }
}
