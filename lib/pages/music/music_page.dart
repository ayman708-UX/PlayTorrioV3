import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/music/music_track.dart';
import '../../services/music/music_service.dart';
import '../../services/music/music_player_controller.dart';
import '../../services/music/music_library_service.dart';
import '../../widgets/common/library_tabs.dart';
import '../../widgets/common/performance_liquid_lens.dart';
import '../../widgets/common/slider_arrow.dart';
import '../../widgets/common/section_top_bar.dart';
import '../../utils/fullscreen_navigator.dart';
import '../../utils/hub_controller.dart';
import '../../utils/search_scope.dart';
import '../../main.dart' show navigatorKey;
import '../audiobooks/audiobooks_page.dart';

class MusicPage extends StatefulWidget {
  const MusicPage({super.key});

  @override
  State<MusicPage> createState() => _MusicPageState();
}

class _MusicPageState extends State<MusicPage> {
  final MusicService _musicService = MusicService.instance;
  final MusicPlayerController _playerController = MusicPlayerController.instance;
  final MusicLibraryService _libraryService = MusicLibraryService.instance;

  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _searchFocusNode = FocusNode();
  final FocusNode _keyboardFocusNode = FocusNode();

  String _activeTab = 'Music'; // 'Music', 'Search', 'Genres', 'Radio', 'Audiobooks', 'Library'

  Map<String, List<MusicTrack>> _sections = {};
  List<MusicArtist> _trendingArtists = [];
  List<MusicAlbum> _newReleases = [];
  List<MusicPlaylist> _curatedPlaylists = [];
  MusicTrack? _heroTrack;

  MusicSearchData _searchData = MusicSearchData.empty;
  MusicArtistDetails? _activeArtistModal;
  MusicAlbumDetails? _activeAlbumModal;
  MusicPlaylistDetails? _activeCuratedPlaylistModal;
  UserPlaylist? _activeUserPlaylistModal;

  bool _isLoading = true;
  bool _isSearching = false;
  bool _hasSearched = false;
  String _activeQuery = '';
  String _selectedFilter = 'All';
  Timer? _debounceTimer;

  bool _showQueueDrawer = false;
  bool _showLyricsDrawer = false;
  bool _showShortcutsModal = false;
  String? _toastMessage;
  Timer? _toastTimer;

  @override
  void initState() {
    super.initState();
    _playerController.addListener(_onStateChanged);
    _libraryService.addListener(_onStateChanged);
    HubController.instance.addListener(_onHubChanged);
    _libraryService.init();
    // Sync the initial tab from the controller (in case a chip is already active).
    _activeTab = HubController.instance.musicTab;
    // Let the universal play bar open the full player when tapped.
    _playerController.setExpandCallback(_openFullscreenPlayer);
    // Let tapping the artist in the play bar open the artist's view.
    _playerController.setOpenArtistCallback(() {
      final artistId = _playerController.currentTrack?.artistId ?? '';
      if (artistId.isNotEmpty) _openArtistModal(artistId);
    });
    _loadMusicData();
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _toastTimer?.cancel();
    _playerController.removeListener(_onStateChanged);
    _libraryService.removeListener(_onStateChanged);
    HubController.instance.removeListener(_onHubChanged);
    _searchController.dispose();
    _scrollController.dispose();
    _searchFocusNode.dispose();
    _keyboardFocusNode.dispose();
    super.dispose();
  }

  /// Syncs the active tab from the shared [HubController] when a section chip
  /// is tapped (the left sidebar was removed, so the SectionTopBar drives it).
  void _onHubChanged() {
    if (!mounted) return;
    final tab = HubController.instance.musicTab;
    if (tab == _activeTab) return;
    setState(() {
      _activeTab = tab;
      _hasSearched = false;
      _isSearching = false;
      _searchData = MusicSearchData.empty;
      _activeQuery = '';
      _searchController.clear();
    });
  }

  void _onStateChanged() {
    if (mounted) setState(() {});
  }

  void _showToast(String message) {
    _toastTimer?.cancel();
    setState(() => _toastMessage = message);
    _toastTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _toastMessage = null);
    });
  }

  Future<void> _loadMusicData() async {
    setState(() => _isLoading = true);

    try {
      final sectionsFuture = _musicService.fetchFeaturedSections();
      final artistsFuture = _musicService.fetchTrendingArtists();
      final releasesFuture = _musicService.fetchNewReleases();
      final playlistsFuture = _musicService.fetchCuratedPlaylists();

      final results = await Future.wait([
        sectionsFuture,
        artistsFuture,
        releasesFuture,
        playlistsFuture,
      ]);

      final sections = results[0] as Map<String, List<MusicTrack>>;
      final artists = results[1] as List<MusicArtist>;
      final releases = results[2] as List<MusicAlbum>;
      final playlists = results[3] as List<MusicPlaylist>;

      MusicTrack? hero;
      if (sections.isNotEmpty && sections.values.first.isNotEmpty) {
        hero = sections.values.first.first;
      }

      if (mounted) {
        setState(() {
          _sections = sections;
          _trendingArtists = artists;
          _newReleases = releases;
          _curatedPlaylists = playlists;
          _heroTrack = hero;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading music data: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _onSearchChanged(String query) {
    _debounceTimer?.cancel();
    final trimmed = query.trim();
    if (trimmed.isEmpty) {
      setState(() {
        _isSearching = false;
        _hasSearched = false;
        _searchData = MusicSearchData.empty;
        _activeQuery = '';
      });
      return;
    }

    _debounceTimer = Timer(const Duration(milliseconds: 350), () async {
      if (!mounted) return;
      setState(() {
        _isSearching = true;
        _activeQuery = trimmed;
        if (_activeTab != 'Search') _activeTab = 'Search';
      });

      final results = await _musicService.searchFull(trimmed);

      if (mounted) {
        setState(() {
          _searchData = results;
          _isSearching = false;
          _hasSearched = true;
        });
      }
    });
  }

  void _onGenreTap(String query) {
    _searchController.text = query;
    _onSearchChanged(query);
  }

  Future<void> _openArtistModal(String artistId) async {
    _showToast('Loading artist details...');
    final details = await _musicService.fetchArtistDetails(artistId);
    if (details != null && mounted) {
      setState(() {
        _activeArtistModal = details;
      });
    }
  }

  Future<void> _openAlbumModal(String albumId) async {
    _showToast('Loading album...');
    final details = await _musicService.fetchAlbumDetails(albumId);
    if (details != null && mounted) {
      setState(() {
        _activeAlbumModal = details;
      });
    }
  }

  Future<void> _openCuratedPlaylistModal(String playlistId) async {
    _showToast('Loading playlist...');
    final details = await _musicService.fetchPlaylistDetails(playlistId);
    if (details != null && mounted) {
      setState(() {
        _activeCuratedPlaylistModal = details;
      });
    }
  }

  void _handleKeyEvent(KeyEvent event) {
    if (event is! KeyDownEvent) return;
    if (_searchFocusNode.hasFocus) return;

    final key = event.logicalKey;
    // Music transport shortcuts (Space/K, J, L, M) are handled globally by
    // GlobalShortcuts so they work app-wide. Only page-specific UI toggles
    // remain here.
    if (key == LogicalKeyboardKey.keyQ) {
      setState(() => _showQueueDrawer = !_showQueueDrawer);
    } else if (key == LogicalKeyboardKey.keyF) {
      _openFullscreenPlayer();
    } else if (key == LogicalKeyboardKey.slash ||
        (HardwareKeyboard.instance.isShiftPressed &&
            key == LogicalKeyboardKey.slash)) {
      setState(() => _showShortcutsModal = !_showShortcutsModal);
    }
  }

  void _showCreatePlaylistDialog({MusicTrack? initialTrack}) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF13151C),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: BorderSide(
            color: const Color(0xFF7C5CFF).withValues(alpha: 0.3),
          ),
        ),
        title: const Row(
          children: [
            Icon(
              Icons.playlist_add_rounded,
              color: Color(0xFF7C5CFF),
              size: 26,
            ),
            SizedBox(width: 10),
            Text(
              'New Playlist',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (initialTrack != null) ...[
              Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: CachedNetworkImage(
                      imageUrl: initialTrack.coverUrl,
                      width: 40,
                      height: 40,
                      fit: BoxFit.cover,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          initialTrack.title,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          initialTrack.artist,
                          style: const TextStyle(
                            color: Colors.white54,
                            fontSize: 11,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
            ],
            TextField(
              controller: controller,
              autofocus: true,
              style: const TextStyle(color: Colors.white, fontSize: 14),
              decoration: InputDecoration(
                hintText: 'Enter playlist title...',
                hintStyle: const TextStyle(color: Colors.white38),
                filled: true,
                fillColor: const Color(0xFF1B1E2B),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Color(0xFF7C5CFF)),
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text(
              'Cancel',
              style: TextStyle(color: Colors.white54),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF7C5CFF),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            onPressed: () async {
              final name = controller.text.trim();
              if (name.isNotEmpty) {
                final pl = await _libraryService.createPlaylist(name);
                if (initialTrack != null) {
                  await _libraryService.addTrackToPlaylist(pl.id, initialTrack);
                  _showToast('Added "${initialTrack.title}" to "$name"');
                } else {
                  _showToast('Created playlist "$name"');
                }
              }
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: const Text(
              'Create',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Opens the now-playing player as a **fullscreen** route on the root
  /// navigator (escaping the header/sidebar), matching how video, audiobook,
  /// and manga playback open fullscreen.
  void _openFullscreenPlayer() {
    if (!_playerController.hasTrack) return;
    pushFullscreen(
      MaterialPageRoute(
        builder: (_) => _MusicExpandedPlayer(
          playerController: _playerController,
          isSaved: _libraryService.isTrackLiked(
            _playerController.currentTrack?.id ?? '',
          ),
          onToggleSave: () {
            if (_playerController.currentTrack != null) {
              _libraryService.toggleLikeTrack(_playerController.currentTrack!);
            }
          },
          onCollapse: () => navigatorKey.currentState?.pop(),
          onQueueTap: () {},
          onAddToPlaylist: () {
            if (_playerController.currentTrack != null) {
              _showAddToPlaylistMenu(_playerController.currentTrack!);
            }
          },
        ),
      ),
    );
  }

  void _showAddToPlaylistMenu(MusicTrack track) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) {
        final playlists = _libraryService.userPlaylists;
        return PerformanceLiquidLens(
          style: PerformanceGlassStyles.sheet,
          child: Container(
            margin: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF0F121C).withValues(alpha: 0.95),
              borderRadius: BorderRadius.circular(28),
              border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.6),
                  blurRadius: 36,
                  offset: const Offset(0, 12),
                ),
              ],
            ),
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: CachedNetworkImage(
                        imageUrl: track.coverUrl,
                        width: 52,
                        height: 52,
                        fit: BoxFit.cover,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            track.title,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w900,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            track.artist,
                            style: const TextStyle(
                              color: Color(0xFF9E9EA8),
                              fontSize: 13,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(
                        Icons.close_rounded,
                        color: Colors.white70,
                      ),
                      onPressed: () => Navigator.pop(ctx),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                const Divider(color: Colors.white10),
                const SizedBox(height: 12),
                Row(
                  children: [
                    const Text(
                      'Save to Playlist',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const Spacer(),
                    TextButton.icon(
                      onPressed: () {
                        Navigator.pop(ctx);
                        _showCreatePlaylistDialog(initialTrack: track);
                      },
                      icon: const Icon(
                        Icons.add_rounded,
                        color: Color(0xFF7C5CFF),
                        size: 18,
                      ),
                      label: const Text(
                        'New Playlist',
                        style: TextStyle(
                          color: Color(0xFF7C5CFF),
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                if (playlists.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 24.0),
                    child: Center(
                      child: Column(
                        children: [
                          const Icon(
                            Icons.playlist_add_rounded,
                            color: Colors.white38,
                            size: 40,
                          ),
                          const SizedBox(height: 10),
                          const Text(
                            'No custom playlists yet',
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 12),
                          ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF7C5CFF),
                            ),
                            onPressed: () {
                              Navigator.pop(ctx);
                              _showCreatePlaylistDialog(initialTrack: track);
                            },
                            child: const Text(
                              'Create First Playlist',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                else
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 280),
                    child: ListView.separated(
                      shrinkWrap: true,
                      itemCount: playlists.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (context, index) {
                        final pl = playlists[index];
                        final inPlaylist = pl.tracks.any((t) => t.id == track.id);
                        return ListTile(
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 4,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                          tileColor: const Color(0xFF1B1E2B),
                          leading: Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              color: const Color(0xFF7C5CFF).withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(
                              Icons.music_note_rounded,
                              color: Color(0xFF7C5CFF),
                            ),
                          ),
                          title: Text(
                            pl.title,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                          ),
                          subtitle: Text(
                            '${pl.tracks.length} tracks',
                            style: const TextStyle(
                              color: Colors.white54,
                              fontSize: 12,
                            ),
                          ),
                          trailing: Icon(
                            inPlaylist
                                ? Icons.check_circle_rounded
                                : Icons.add_circle_outline_rounded,
                            color: inPlaylist
                                ? const Color(0xFF00D294)
                                : Colors.white60,
                          ),
                          onTap: () async {
                            if (inPlaylist) {
                              await _libraryService.removeTrackFromPlaylist(
                                pl.id,
                                track.id,
                              );
                              _showToast('Removed from "${pl.title}"');
                            } else {
                              await _libraryService.addTrackToPlaylist(
                                pl.id,
                                track,
                              );
                              _showToast('Added to "${pl.title}"');
                            }
                            if (ctx.mounted) Navigator.pop(ctx);
                          },
                        );
                      },
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  bool _isDesktop(BuildContext context) {
    return MediaQuery.sizeOf(context).width >= 900;
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop = _isDesktop(context);

    return KeyboardListener(
      focusNode: _keyboardFocusNode,
      autofocus: true,
      onKeyEvent: _handleKeyEvent,
      child: Scaffold(
        backgroundColor: const Color(0xFF080A0F),
        body: Stack(
          children: [
            // Ambient Background Glow
            Positioned(
              top: -120,
              right: -100,
              child: Container(
                width: 450,
                height: 450,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFF7C5CFF).withValues(alpha: 0.08),
                ),
              ),
            ),
            Positioned(
              bottom: 80,
              left: -120,
              child: Container(
                width: 400,
                height: 400,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFF00D2EF).withValues(alpha: 0.05),
                ),
              ),
            ),

            // Main App Shell Layout
            Column(
              children: [
                // Main Page Content Area
                Expanded(
                  child: Column(
                    children: [
                      const SectionTopBar(),
                      Expanded(
                        child: Stack(
                          children: [
                            Positioned.fill(
                              child: _buildTabContent(isDesktop),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),

            // Queue Drawer
            if (_showQueueDrawer)
              Positioned(
                top: 0,
                bottom: 0,
                right: 0,
                child: _MusicQueueDrawer(
                  onClose: () => setState(() => _showQueueDrawer = false),
                ),
              ),

            // Synced Lyrics Drawer
            if (_showLyricsDrawer && _playerController.hasTrack)
              Positioned(
                top: 0,
                bottom: 0,
                right: 0,
                child: _MusicLyricsDrawer(
                  track: _playerController.currentTrack!,
                  playerController: _playerController,
                  onClose: () => setState(() => _showLyricsDrawer = false),
                ),
              ),

            // Modals: Artist Detail
            if (_activeArtistModal != null)
              Positioned.fill(
                child: _MusicArtistDetailModal(
                  details: _activeArtistModal!,
                  playerController: _playerController,
                  onClose: () => setState(() => _activeArtistModal = null),
                  onPlayTrack: (t, queue) => _playerController.playTrack(t, playlistQueue: queue),
                  onAddToPlaylist: _showAddToPlaylistMenu,
                  onOpenAlbum: _openAlbumModal,
                ),
              ),

            // Modals: Album Detail
            if (_activeAlbumModal != null)
              Positioned.fill(
                child: _MusicAlbumDetailModal(
                  details: _activeAlbumModal!,
                  playerController: _playerController,
                  onClose: () => setState(() => _activeAlbumModal = null),
                  onPlayTrack: (t, queue) => _playerController.playTrack(t, playlistQueue: queue),
                  onAddToPlaylist: _showAddToPlaylistMenu,
                ),
              ),

            // Modals: Curated Playlist Detail
            if (_activeCuratedPlaylistModal != null)
              Positioned.fill(
                child: _MusicCuratedPlaylistDetailModal(
                  details: _activeCuratedPlaylistModal!,
                  playerController: _playerController,
                  onClose: () => setState(() => _activeCuratedPlaylistModal = null),
                  onPlayTrack: (t, queue) => _playerController.playTrack(t, playlistQueue: queue),
                  onAddToPlaylist: _showAddToPlaylistMenu,
                ),
              ),

            // Modals: User Playlist Detail
            if (_activeUserPlaylistModal != null)
              Positioned.fill(
                child: _MusicUserPlaylistDetailModal(
                  playlist: _activeUserPlaylistModal!,
                  playerController: _playerController,
                  onClose: () => setState(() => _activeUserPlaylistModal = null),
                  onPlayTrack: (t, queue) => _playerController.playTrack(t, playlistQueue: queue),
                  onRemoveTrack: (trackId) async {
                    await _libraryService.removeTrackFromPlaylist(_activeUserPlaylistModal!.id, trackId);
                    setState(() {
                      final updated = _libraryService.userPlaylists.firstWhere(
                        (p) => p.id == _activeUserPlaylistModal!.id,
                        orElse: () => _activeUserPlaylistModal!,
                      );
                      _activeUserPlaylistModal = updated;
                    });
                  },
                ),
              ),

            // Modals: Shortcuts
            if (_showShortcutsModal)
              Positioned.fill(
                child: _MusicShortcutsModal(
                  onClose: () => setState(() => _showShortcutsModal = false),
                ),
              ),

            // Temporary Notification Toast
            if (_toastMessage != null)
              Positioned(
                top: 80,
                left: 0,
                right: 0,
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                    decoration: BoxDecoration(
                      color: const Color(0xFF7C5CFF),
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF7C5CFF).withValues(alpha: 0.4),
                          blurRadius: 16,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Text(
                      _toastMessage!,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ),
              ),

            // Persistent Hub Navigation Dock
          ],
        ),
      ),
    );
  }

  Widget _buildTabContent(bool isDesktop) {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: Color(0xFF7C5CFF)),
      );
    }

    if (_activeTab == 'Search' || _hasSearched || _searchController.text.isNotEmpty) {
      SearchScope.set('music', label: 'Music');
      return _buildSearchView();
    }

    if (_activeTab == 'Genres') return _buildBrowseView();
    if (_activeTab == 'Radio') return _buildRadioView();
    if (_activeTab == 'Audiobooks') {
      SearchScope.set('audiobook', label: 'Audiobooks');
      return const AudiobooksPage();
    }
    if (_activeTab == 'Library') {
      SearchScope.set(null, label: 'Library');
      return _buildLibraryView();
    }

    final bottomPad = isDesktop ? 120.0 : 110.0;

    return RefreshIndicator(
      color: const Color(0xFF7C5CFF),
      backgroundColor: const Color(0xFF151822),
      onRefresh: _loadMusicData,
      child: ListView(
        controller: _scrollController,
        padding: EdgeInsets.only(top: 75, bottom: bottomPad),
        physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
        children: [
          if (_heroTrack != null)
            _MusicHeroBillboard(
              track: _heroTrack!,
              onPlayTap: () => _playerController.playTrack(
                _heroTrack!,
                playlistQueue: _sections.values.isNotEmpty ? _sections.values.first : null,
              ),
              onSaveTap: () {
                _libraryService.toggleLikeTrack(_heroTrack!);
                _showToast(
                  _libraryService.isTrackLiked(_heroTrack!.id)
                      ? 'Saved to Library'
                      : 'Removed from Library',
                );
              },
              onAddToPlaylistTap: () => _showAddToPlaylistMenu(_heroTrack!),
              isSaved: _libraryService.isTrackLiked(_heroTrack!.id),
            ),
          const SizedBox(height: 24),
          if (_trendingArtists.isNotEmpty)
            _MusicTrendingArtists(
              artists: _trendingArtists,
              onArtistTap: (artist) {
                if (artist.id.isNotEmpty) {
                  _openArtistModal(artist.id);
                } else {
                  _onGenreTap(artist.name);
                }
              },
            ),
          if (_newReleases.isNotEmpty)
            _MusicAlbumsRow(
              title: '💿 New Album Releases',
              albums: _newReleases,
              onAlbumTap: (album) => _openAlbumModal(album.id),
            ),
          if (_curatedPlaylists.isNotEmpty)
            _MusicPlaylistsRow(
              title: '🎧 Curated Charts & Mixes',
              playlists: _curatedPlaylists,
              onPlaylistTap: (pl) => _openCuratedPlaylistModal(pl.id),
            ),
          for (final entry in _sections.entries)
            _MusicCategorySlider(
              title: entry.key,
              tracks: entry.value,
              onAddToPlaylist: _showAddToPlaylistMenu,
            ),
        ],
      ),
    );
  }

  Widget _buildSearchView() {
    final sizing = _MusicCardSizing.fromWidth(MediaQuery.sizeOf(context).width);

    return ListView(
      controller: _scrollController,
      padding: const EdgeInsets.only(top: 80, left: 24, right: 24, bottom: 150),
      children: [
        TextField(
          controller: _searchController,
          autofocus: true,
          style: const TextStyle(color: Colors.white),
          onChanged: _onSearchChanged,
          decoration: InputDecoration(
            hintText: 'Search music...',
            hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.35)),
            prefixIcon: const Icon(Icons.search_rounded, color: Colors.white54),
            filled: true,
            fillColor: const Color(0xFF12151E),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
          ),
        ),
        const SizedBox(height: 20),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          physics: const BouncingScrollPhysics(),
          child: Row(
            children: [
              _filterTab('All'),
              const SizedBox(width: 8),
              _filterTab('Tracks (${_searchData.tracks.length})'),
              const SizedBox(width: 8),
              _filterTab('Artists (${_searchData.artists.length})'),
              const SizedBox(width: 8),
              _filterTab('Albums (${_searchData.albums.length})'),
              const SizedBox(width: 8),
              _filterTab('Playlists (${_searchData.playlists.length})'),
            ],
          ),
        ),
        const SizedBox(height: 24),
        if (_isSearching)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 48.0),
            child: Center(
              child: CircularProgressIndicator(color: Color(0xFF7C5CFF)),
            ),
          )
        else if (_searchData.tracks.isEmpty &&
            _searchData.artists.isEmpty &&
            _searchData.albums.isEmpty &&
            _searchData.playlists.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 48.0),
            child: Center(
              child: Column(
                children: [
                  const Icon(
                    Icons.search_off_rounded,
                    color: Colors.white38,
                    size: 48,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'No results for "$_activeQuery"',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          )
        else ...[
          if ((_selectedFilter == 'All' || _selectedFilter.startsWith('Tracks')) &&
              _searchData.tracks.isNotEmpty) ...[
            const Text(
              'Songs',
              style: TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 14),
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _searchData.tracks.length.clamp(0, 15),
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final track = _searchData.tracks[index];
                return _MusicTrackRow(
                  track: track,
                  isPlaying: _playerController.currentTrack?.id == track.id &&
                      _playerController.isPlaying,
                  isCurrent: _playerController.currentTrack?.id == track.id,
                  onTap: () => _playerController.playTrack(
                    track,
                    playlistQueue: _searchData.tracks,
                  ),
                  onMoreTap: () => _showAddToPlaylistMenu(track),
                );
              },
            ),
            const SizedBox(height: 32),
          ],
          if ((_selectedFilter == 'All' || _selectedFilter.startsWith('Artists')) &&
              _searchData.artists.isNotEmpty) ...[
            const Text(
              'Artists',
              style: TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 14),
            SizedBox(
              height: 130,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                physics: const BouncingScrollPhysics(),
                itemCount: _searchData.artists.length,
                separatorBuilder: (_, __) => const SizedBox(width: 16),
                itemBuilder: (context, index) {
                  final artist = _searchData.artists[index];
                  return _MusicHoverable(
                    scaleFactor: 1.06,
                    child: GestureDetector(
                      onTap: () => _openArtistModal(artist.id),
                      child: Column(
                        children: [
                          ClipOval(
                            child: CachedNetworkImage(
                              imageUrl: artist.pictureUrl,
                              width: 80,
                              height: 80,
                              fit: BoxFit.cover,
                            ),
                          ),
                          const SizedBox(height: 8),
                          SizedBox(
                            width: 90,
                            child: Text(
                              artist.name,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 32),
          ],
          if ((_selectedFilter == 'All' || _selectedFilter.startsWith('Albums')) &&
              _searchData.albums.isNotEmpty) ...[
            const Text(
              'Albums',
              style: TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 14),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: (MediaQuery.sizeOf(context).width / sizing.cardWidth)
                    .floor()
                    .clamp(2, 6),
                mainAxisSpacing: 20,
                crossAxisSpacing: 16,
                childAspectRatio: sizing.cardWidth / sizing.totalHeight,
              ),
              itemCount: _searchData.albums.length.clamp(0, 12),
              itemBuilder: (context, index) {
                final album = _searchData.albums[index];
                return _MusicAlbumCard(
                  album: album,
                  onTap: () => _openAlbumModal(album.id),
                );
              },
            ),
            const SizedBox(height: 32),
          ],
          if ((_selectedFilter == 'All' || _selectedFilter.startsWith('Playlists')) &&
              _searchData.playlists.isNotEmpty) ...[
            const Text(
              'Playlists',
              style: TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 14),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: (MediaQuery.sizeOf(context).width / sizing.cardWidth)
                    .floor()
                    .clamp(2, 6),
                mainAxisSpacing: 20,
                crossAxisSpacing: 16,
                childAspectRatio: sizing.cardWidth / sizing.totalHeight,
              ),
              itemCount: _searchData.playlists.length.clamp(0, 12),
              itemBuilder: (context, index) {
                final pl = _searchData.playlists[index];
                return _MusicPlaylistCard(
                  playlist: pl,
                  onTap: () => _openCuratedPlaylistModal(pl.id),
                );
              },
            ),
          ],
        ],
      ],
    );
  }

  Widget _filterTab(String label) {
    final isSelected = _selectedFilter == label ||
        (_selectedFilter == 'All' && label == 'All') ||
        (label.startsWith(_selectedFilter) && _selectedFilter != 'All');

    return _MusicHoverable(
      scaleFactor: 1.05,
      child: GestureDetector(
        onTap: () {
          setState(() {
            if (label.startsWith('Tracks')) {
              _selectedFilter = 'Tracks';
            } else if (label.startsWith('Artists')) {
              _selectedFilter = 'Artists';
            } else if (label.startsWith('Albums')) {
              _selectedFilter = 'Albums';
            } else if (label.startsWith('Playlists')) {
              _selectedFilter = 'Playlists';
            } else {
              _selectedFilter = 'All';
            }
          });
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: isSelected
                ? const Color(0xFF7C5CFF)
                : Colors.white.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: isSelected
                  ? const Color(0xFF7C5CFF)
                  : Colors.white.withValues(alpha: 0.12),
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: isSelected ? Colors.white : Colors.white70,
              fontSize: 13,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBrowseView() {
    final genres = [
      {'title': 'Pop Hits', 'color': const Color(0xFF7C5CFF), 'query': 'Pop Hits'},
      {'title': 'Hip-Hop & Rap', 'color': const Color(0xFF7850FF), 'query': 'Hip-Hop'},
      {'title': 'Electronic & EDM', 'color': const Color(0xFF00D294), 'query': 'EDM Dance'},
      {'title': 'Chill Lofi Beats', 'color': const Color(0xFF00D2EF), 'query': 'Chill Lofi'},
      {'title': 'Rock Classics', 'color': const Color(0xFFF99C00), 'query': 'Rock Classics'},
      {'title': 'R&B & Soul', 'color': const Color(0xFFE12AFB), 'query': 'R&B Soul'},
      {'title': 'Soundtracks & Gaming', 'color': const Color(0xFFFF6568), 'query': 'Soundtracks'},
      {'title': 'Heavy Metal', 'color': const Color(0xFFFB2C36), 'query': 'Heavy Metal'},
      {'title': 'Jazz & Blues', 'color': const Color(0xFF625FFF), 'query': 'Jazz Blues'},
      {'title': 'Classical Piano', 'color': const Color(0xFFFAC800), 'query': 'Classical Piano'},
    ];

    return ListView(
      controller: _scrollController,
      padding: const EdgeInsets.only(top: 80, left: 24, right: 24, bottom: 150),
      children: [
        const Text(
          'Browse Moods & Genres',
          style: TextStyle(
            color: Colors.white,
            fontSize: 26,
            fontWeight: FontWeight.w900,
            letterSpacing: -0.6,
          ),
        ),
        const SizedBox(height: 16),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: 220,
            mainAxisSpacing: 16,
            crossAxisSpacing: 16,
            childAspectRatio: 1.6,
          ),
          itemCount: genres.length,
          itemBuilder: (context, index) {
            final g = genres[index];
            final color = g['color'] as Color;
            return _MusicHoverable(
              scaleFactor: 1.04,
              child: GestureDetector(
                onTap: () => _onGenreTap(g['query'] as String),
                child: PerformanceLiquidLens(
                  style: PerformanceGlassStyles.menu,
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(18),
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          color.withValues(alpha: 0.85),
                          color.withValues(alpha: 0.40),
                        ],
                      ),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.15),
                      ),
                    ),
                    padding: const EdgeInsets.all(16),
                    child: Align(
                      alignment: Alignment.bottomLeft,
                      child: Text(
                        g['title'] as String,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                          letterSpacing: -0.3,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _buildRadioView() {
    final radioGenres = [
      {'name': 'Pop Radio', 'color': const Color(0xFF7C5CFF), 'query': 'Pop Radio Hits'},
      {'name': 'Rap & Hip-Hop', 'color': const Color(0xFF7850FF), 'query': 'Hip Hop Radio'},
      {'name': 'Rock Mix', 'color': const Color(0xFFF99C00), 'query': 'Rock Radio'},
      {'name': 'Dance & Electro', 'color': const Color(0xFF00D294), 'query': 'Electro Radio'},
      {'name': 'R&B Station', 'color': const Color(0xFFE12AFB), 'query': 'R&B Radio'},
      {'name': 'Lofi & Ambient', 'color': const Color(0xFF00D2EF), 'query': 'Lofi Radio'},
      {'name': 'Heavy Metal Station', 'color': const Color(0xFFFB2C36), 'query': 'Metal Radio'},
      {'name': 'Jazz Club', 'color': const Color(0xFF625FFF), 'query': 'Jazz Radio'},
    ];

    return ListView(
      controller: _scrollController,
      padding: const EdgeInsets.only(top: 80, left: 24, right: 24, bottom: 150),
      children: [
        const Text(
          'Radio Stations & Live Streams',
          style: TextStyle(
            color: Colors.white,
            fontSize: 26,
            fontWeight: FontWeight.w900,
            letterSpacing: -0.6,
          ),
        ),
        const SizedBox(height: 6),
        const Text(
          'Continuous music channels tuned to your mood.',
          style: TextStyle(color: Color(0xFF9E9EA8), fontSize: 14),
        ),
        const SizedBox(height: 20),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: 220,
            mainAxisSpacing: 16,
            crossAxisSpacing: 16,
            childAspectRatio: 1.5,
          ),
          itemCount: radioGenres.length,
          itemBuilder: (context, index) {
            final station = radioGenres[index];
            final color = station['color'] as Color;
            return _MusicHoverable(
              scaleFactor: 1.04,
              child: GestureDetector(
                onTap: () => _onGenreTap(station['query'] as String),
                child: PerformanceLiquidLens(
                  style: PerformanceGlassStyles.menu,
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(18),
                      color: color.withValues(alpha: 0.20),
                      border: Border.all(color: color.withValues(alpha: 0.5)),
                    ),
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Icon(Icons.radio_rounded, color: color, size: 28),
                        Text(
                          station['name'] as String,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _buildLibraryView() {
    final liked = _libraryService.likedTracks;
    final playlists = _libraryService.userPlaylists;
    final recent = _libraryService.recentTracks;

    return LibraryTabs(
      title: 'Library',
      titleIcon: Icons.library_music_rounded,
      trailing: _MusicHoverable(
        scaleFactor: 1.05,
        child: ElevatedButton.icon(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF7C5CFF),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
          ),
          onPressed: () => _showCreatePlaylistDialog(),
          icon: const Icon(Icons.add_rounded, color: Colors.white, size: 18),
          label: const Text(
            'New Playlist',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          ),
        ),
      ),
      tabs: [
        LibraryTab(
          label: 'Liked Songs',
          icon: Icons.favorite_rounded,
          builder: (_) => _buildLikedSongsTab(liked),
        ),
        LibraryTab(
          label: 'Playlists',
          icon: Icons.queue_music_rounded,
          builder: (_) => _buildPlaylistsTab(playlists),
        ),
        LibraryTab(
          label: 'Recent',
          icon: Icons.history_rounded,
          builder: (_) => _buildRecentTab(recent),
        ),
      ],
    );
  }

  Widget _buildLikedSongsTab(List<MusicTrack> liked) {
    if (liked.isEmpty) {
      return const LibraryEmptyState(
        icon: Icons.favorite_rounded,
        title: 'No liked songs',
        subtitle: 'Tap the heart on a song to save it here.',
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
      itemCount: liked.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final track = liked[index];
        return _MusicTrackRow(
          track: track,
          isPlaying: _playerController.currentTrack?.id == track.id &&
              _playerController.isPlaying,
          isCurrent: _playerController.currentTrack?.id == track.id,
          onTap: () => _playerController.playTrack(track, playlistQueue: liked),
          onMoreTap: () => _showAddToPlaylistMenu(track),
        );
      },
    );
  }

  Widget _buildPlaylistsTab(List<UserPlaylist> playlists) {
    if (playlists.isEmpty) {
      return const LibraryEmptyState(
        icon: Icons.queue_music_rounded,
        title: 'No playlists yet',
        subtitle: 'Create a playlist to organize your music.',
      );
    }
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 220,
        mainAxisSpacing: 16,
        crossAxisSpacing: 16,
        childAspectRatio: 1.1,
      ),
      itemCount: playlists.length,
      itemBuilder: (context, index) {
        final pl = playlists[index];
        return _MusicHoverable(
          scaleFactor: 1.04,
          child: GestureDetector(
            onTap: () => setState(() => _activeUserPlaylistModal = pl),
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0xFF13151F),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
              ),
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    height: 70,
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: const Color(0xFF7C5CFF).withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.queue_music_rounded,
                      color: Color(0xFF7C5CFF),
                      size: 36,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    pl.title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    '${pl.tracks.length} tracks',
                    style: const TextStyle(
                      color: Colors.white54,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildRecentTab(List<MusicTrack> recent) {
    if (recent.isEmpty) {
      return const LibraryEmptyState(
        icon: Icons.history_rounded,
        title: 'No recently played',
        subtitle: 'Songs you play will appear here.',
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
      itemCount: recent.length.clamp(0, 50),
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final track = recent[index];
        return _MusicTrackRow(
          track: track,
          isPlaying: _playerController.currentTrack?.id == track.id &&
              _playerController.isPlaying,
          isCurrent: _playerController.currentTrack?.id == track.id,
          onTap: () => _playerController.playTrack(track, playlistQueue: recent),
          onMoreTap: () => _showAddToPlaylistMenu(track),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// FPS-Friendly Hover Container
// ─────────────────────────────────────────────────────────────────────────────

class _MusicHoverable extends StatefulWidget {
  final Widget child;
  final double scaleFactor;

  const _MusicHoverable({
    required this.child,
    this.scaleFactor = 1.04,
  });

  @override
  State<_MusicHoverable> createState() => _MusicHoverableState();
}

class _MusicHoverableState extends State<_MusicHoverable> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: AnimatedScale(
        scale: _isHovered ? widget.scaleFactor : 1.0,
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOutCubic,
        child: widget.child,
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Reusable Horizontal Slider with Desktop Navigation Arrows
// ─────────────────────────────────────────────────────────────────────────────

class _MusicHorizontalScrollSection extends StatefulWidget {
  final String? title;
  final double height;
  final int itemCount;
  final Widget Function(BuildContext, int) itemBuilder;

  const _MusicHorizontalScrollSection({
    this.title,
    required this.height,
    required this.itemCount,
    required this.itemBuilder,
  });

  @override
  State<_MusicHorizontalScrollSection> createState() => _MusicHorizontalScrollSectionState();
}

class _MusicHorizontalScrollSectionState extends State<_MusicHorizontalScrollSection> {
  late final ScrollController _controller;
  bool _canScrollLeft = false;
  bool _canScrollRight = true;
  bool _isHovered = false;

  @override
  void initState() {
    super.initState();
    _controller = ScrollController();
    _controller.addListener(_updateScrollButtons);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _updateScrollButtons();
    });
  }

  @override
  void dispose() {
    _controller.removeListener(_updateScrollButtons);
    _controller.dispose();
    super.dispose();
  }

  void _updateScrollButtons() {
    if (!_controller.hasClients) return;
    final canLeft = _controller.position.pixels > 5;
    final canRight = _controller.position.pixels < _controller.position.maxScrollExtent - 5;
    if (canLeft != _canScrollLeft || canRight != _canScrollRight) {
      setState(() {
        _canScrollLeft = canLeft;
        _canScrollRight = canRight;
      });
    }
  }

  void _scroll(double multiplier) {
    if (!_controller.hasClients) return;
    final viewportWidth = _controller.position.viewportDimension;
    final scrollAmount = viewportWidth * 0.75 * multiplier;
    final target = (_controller.position.pixels + scrollAmount)
        .clamp(0.0, _controller.position.maxScrollExtent);

    _controller.animateTo(
      target,
      duration: const Duration(milliseconds: 450),
      curve: Curves.easeOutCubic,
    );
  }

  bool _isDesktop(BuildContext context) {
    if (kIsWeb) return true;
    return defaultTargetPlatform == TargetPlatform.windows ||
        defaultTargetPlatform == TargetPlatform.macOS ||
        defaultTargetPlatform == TargetPlatform.linux;
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop = _isDesktop(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.title != null) ...[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24.0),
            child: Text(
              widget.title!,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          const SizedBox(height: 14),
        ],
        MouseRegion(
          onEnter: (_) => setState(() => _isHovered = true),
          onExit: (_) => setState(() => _isHovered = false),
          child: SizedBox(
            height: widget.height,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                ListView.separated(
                  controller: _controller,
                  scrollDirection: Axis.horizontal,
                  physics: const BouncingScrollPhysics(),
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  itemCount: widget.itemCount,
                  separatorBuilder: (_, __) => const SizedBox(width: 16),
                  itemBuilder: widget.itemBuilder,
                ),

                // Desktop Left & Right Floating Arrows
                if (isDesktop) ...[
                  AnimatedPositioned(
                    duration: const Duration(milliseconds: 250),
                    curve: Curves.easeOutCubic,
                    left: _canScrollLeft && _isHovered ? 8 : -60,
                    top: 0,
                    bottom: 0,
                    child: Center(
                      child: SliderArrow(
                        icon: Icons.arrow_back_ios_new_rounded,
                        onTap: () => _scroll(-1),
                      ),
                    ),
                  ),
                  AnimatedPositioned(
                    duration: const Duration(milliseconds: 250),
                    curve: Curves.easeOutCubic,
                    right: _canScrollRight && _isHovered ? 8 : -60,
                    top: 0,
                    bottom: 0,
                    child: Center(
                      child: SliderArrow(
                        icon: Icons.arrow_forward_ios_rounded,
                        onTap: () => _scroll(1),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _MusicHeroBillboard extends StatelessWidget {
  final MusicTrack track;
  final VoidCallback onPlayTap;
  final VoidCallback onSaveTap;
  final VoidCallback onAddToPlaylistTap;
  final bool isSaved;

  const _MusicHeroBillboard({
    required this.track,
    required this.onPlayTap,
    required this.onSaveTap,
    required this.onAddToPlaylistTap,
    required this.isSaved,
  });

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.sizeOf(context).width;
    final isMobile = screenWidth < 600;

    return Container(
      margin: EdgeInsets.symmetric(horizontal: isMobile ? 16 : 24),
      height: isMobile ? 190 : 240,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF7C5CFF).withValues(alpha: 0.25),
            blurRadius: 32,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(28),
        child: Stack(
          children: [
            Positioned.fill(
              child: CachedNetworkImage(
                imageUrl: track.coverUrl,
                fit: BoxFit.cover,
              ),
            ),
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                    colors: [
                      Colors.black.withValues(alpha: 0.94),
                      Colors.black.withValues(alpha: 0.65),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),
            Padding(
              padding: EdgeInsets.all(isMobile ? 18.0 : 28.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFF7C5CFF),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Text(
                      'TOP CHART HIT',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                        fontSize: 10,
                        letterSpacing: 1.0,
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    track.title,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: isMobile ? 20 : 26,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -0.5,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    track.artist,
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: isMobile ? 13 : 15,
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  SizedBox(height: isMobile ? 14 : 20),
                  Row(
                    children: [
                      _MusicHoverable(
                        scaleFactor: 1.06,
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF7C5CFF),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(20),
                            ),
                            padding: EdgeInsets.symmetric(
                              horizontal: isMobile ? 16 : 20,
                              vertical: isMobile ? 10 : 12,
                            ),
                          ),
                          onPressed: onPlayTap,
                          icon: const Icon(Icons.play_arrow_rounded, color: Colors.white),
                          label: const Text(
                            'Play Now',
                            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      _MusicHoverable(
                        scaleFactor: 1.1,
                        child: IconButton(
                          style: IconButton.styleFrom(
                            backgroundColor: Colors.white.withValues(alpha: 0.15),
                          ),
                          icon: Icon(
                            isSaved ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                            color: isSaved ? const Color(0xFFFF4B72) : Colors.white,
                          ),
                          onPressed: onSaveTap,
                        ),
                      ),
                      const SizedBox(width: 8),
                      _MusicHoverable(
                        scaleFactor: 1.1,
                        child: IconButton(
                          style: IconButton.styleFrom(
                            backgroundColor: Colors.white.withValues(alpha: 0.15),
                          ),
                          icon: const Icon(Icons.playlist_add_rounded, color: Colors.white),
                          onPressed: onAddToPlaylistTap,
                        ),
                      ),
                    ],
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

class _MusicTrendingArtists extends StatelessWidget {
  final List<MusicArtist> artists;
  final Function(MusicArtist) onArtistTap;

  const _MusicTrendingArtists({
    required this.artists,
    required this.onArtistTap,
  });

  @override
  Widget build(BuildContext context) {
    return _MusicHorizontalScrollSection(
      title: '🌟 Trending Artists',
      height: 130,
      itemCount: artists.length,
      itemBuilder: (context, index) {
        final artist = artists[index];
        return _MusicHoverable(
          scaleFactor: 1.06,
          child: GestureDetector(
            onTap: () => onArtistTap(artist),
            child: Column(
              children: [
                Container(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: const Color(0xFF7C5CFF).withValues(alpha: 0.5),
                      width: 2,
                    ),
                  ),
                  child: ClipOval(
                    child: CachedNetworkImage(
                      imageUrl: artist.pictureUrl,
                      width: 78,
                      height: 78,
                      fit: BoxFit.cover,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: 85,
                  child: Text(
                    artist.name,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _MusicAlbumsRow extends StatelessWidget {
  final String title;
  final List<MusicAlbum> albums;
  final Function(MusicAlbum) onAlbumTap;

  const _MusicAlbumsRow({
    required this.title,
    required this.albums,
    required this.onAlbumTap,
  });

  @override
  Widget build(BuildContext context) {
    return _MusicHorizontalScrollSection(
      title: title,
      height: 200,
      itemCount: albums.length,
      itemBuilder: (context, index) {
        final album = albums[index];
        return _MusicAlbumCard(album: album, onTap: () => onAlbumTap(album));
      },
    );
  }
}

class _MusicPlaylistsRow extends StatelessWidget {
  final String title;
  final List<MusicPlaylist> playlists;
  final Function(MusicPlaylist) onPlaylistTap;

  const _MusicPlaylistsRow({
    required this.title,
    required this.playlists,
    required this.onPlaylistTap,
  });

  @override
  Widget build(BuildContext context) {
    return _MusicHorizontalScrollSection(
      title: title,
      height: 200,
      itemCount: playlists.length,
      itemBuilder: (context, index) {
        final pl = playlists[index];
        return _MusicPlaylistCard(playlist: pl, onTap: () => onPlaylistTap(pl));
      },
    );
  }
}

class _MusicCategorySlider extends StatelessWidget {
  final String title;
  final List<MusicTrack> tracks;
  final Function(MusicTrack) onAddToPlaylist;

  const _MusicCategorySlider({
    required this.title,
    required this.tracks,
    required this.onAddToPlaylist,
  });

  @override
  Widget build(BuildContext context) {
    return _MusicHorizontalScrollSection(
      title: title,
      height: 215,
      itemCount: tracks.length,
      itemBuilder: (context, index) {
        final track = tracks[index];
        return _MusicTrackCard(
          track: track,
          onTap: () => MusicPlayerController.instance.playTrack(
            track,
            playlistQueue: tracks,
          ),
          onMoreTap: () => onAddToPlaylist(track),
        );
      },
    );
  }
}

class _MusicTrackCard extends StatelessWidget {
  final MusicTrack track;
  final VoidCallback onTap;
  final VoidCallback onMoreTap;

  const _MusicTrackCard({
    required this.track,
    required this.onTap,
    required this.onMoreTap,
  });

  @override
  Widget build(BuildContext context) {
    return _MusicHoverable(
      scaleFactor: 1.05,
      child: GestureDetector(
        onTap: onTap,
        child: SizedBox(
          width: 145,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Stack(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: CachedNetworkImage(
                      imageUrl: track.coverUrl,
                      width: 145,
                      height: 145,
                      fit: BoxFit.cover,
                    ),
                  ),
                  Positioned(
                    bottom: 8,
                    right: 8,
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: const BoxDecoration(
                        color: Color(0xFF7C5CFF),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.play_arrow_rounded,
                        color: Colors.white,
                        size: 20,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                track.title,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 2),
              Text(
                track.artist,
                style: const TextStyle(
                  color: Colors.white54,
                  fontSize: 11,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MusicAlbumCard extends StatelessWidget {
  final MusicAlbum album;
  final VoidCallback onTap;

  const _MusicAlbumCard({
    required this.album,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return _MusicHoverable(
      scaleFactor: 1.05,
      child: GestureDetector(
        onTap: onTap,
        child: SizedBox(
          width: 145,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: CachedNetworkImage(
                  imageUrl: album.coverUrl,
                  width: 145,
                  height: 145,
                  fit: BoxFit.cover,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                album.title,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 2),
              Text(
                album.artistName,
                style: const TextStyle(
                  color: Colors.white54,
                  fontSize: 11,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MusicPlaylistCard extends StatelessWidget {
  final MusicPlaylist playlist;
  final VoidCallback onTap;

  const _MusicPlaylistCard({
    required this.playlist,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return _MusicHoverable(
      scaleFactor: 1.05,
      child: GestureDetector(
        onTap: onTap,
        child: SizedBox(
          width: 145,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: CachedNetworkImage(
                  imageUrl: playlist.coverUrl,
                  width: 145,
                  height: 145,
                  fit: BoxFit.cover,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                playlist.title,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 2),
              Text(
                '${playlist.trackCount} tracks',
                style: const TextStyle(
                  color: Colors.white54,
                  fontSize: 11,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MusicTrackRow extends StatelessWidget {
  final MusicTrack track;
  final bool isPlaying;
  final bool isCurrent;
  final VoidCallback onTap;
  final VoidCallback onMoreTap;

  const _MusicTrackRow({
    required this.track,
    required this.isPlaying,
    required this.isCurrent,
    required this.onTap,
    required this.onMoreTap,
  });

  @override
  Widget build(BuildContext context) {
    return _MusicHoverable(
      scaleFactor: 1.01,
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        tileColor: isCurrent
            ? const Color(0xFF7C5CFF).withValues(alpha: 0.15)
            : const Color(0xFF13151F),
        leading: Stack(
          alignment: Alignment.center,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: CachedNetworkImage(
                imageUrl: track.coverUrl,
                width: 48,
                height: 48,
                fit: BoxFit.cover,
              ),
            ),
            if (isCurrent)
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.45),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                  color: const Color(0xFF7C5CFF),
                  size: 28,
                ),
              ),
          ],
        ),
        title: Text(
          track.title,
          style: TextStyle(
            color: isCurrent ? const Color(0xFF7C5CFF) : Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 14,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          track.artist,
          style: const TextStyle(color: Colors.white54, fontSize: 12),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              track.formattedDuration,
              style: const TextStyle(color: Colors.white38, fontSize: 12),
            ),
            const SizedBox(width: 8),
            IconButton(
              icon: const Icon(Icons.more_vert_rounded, color: Colors.white54, size: 20),
              onPressed: onMoreTap,
            ),
          ],
        ),
        onTap: onTap,
      ),
    );
  }
}

class _MusicCardSizing {
  final double cardWidth;
  final double totalHeight;

  const _MusicCardSizing(this.cardWidth, this.totalHeight);

  factory _MusicCardSizing.fromWidth(double width) {
    if (width >= 1200) return const _MusicCardSizing(170, 240);
    if (width >= 800) return const _MusicCardSizing(150, 215);
    return const _MusicCardSizing(140, 200);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Drawers & Modals
// ─────────────────────────────────────────────────────────────────────────────

class _MusicLyricsDrawer extends StatelessWidget {
  final MusicTrack track;
  final MusicPlayerController playerController;
  final VoidCallback onClose;

  const _MusicLyricsDrawer({
    required this.track,
    required this.playerController,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final lyrics = playerController.currentLyrics;
    final activeIndex = playerController.activeLyricIndex;
    final isMobile = MediaQuery.sizeOf(context).width < 600;

    return PerformanceLiquidLens(
      style: PerformanceGlassStyles.sheet,
      child: Container(
        width: isMobile ? MediaQuery.sizeOf(context).width : 360,
        decoration: BoxDecoration(
          color: const Color(0xFF0F121C).withValues(alpha: 0.96),
          borderRadius: isMobile
              ? const BorderRadius.vertical(top: Radius.circular(24))
              : const BorderRadius.only(
                  topLeft: Radius.circular(24),
                  bottomLeft: Radius.circular(24),
                ),
          border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
        ),
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.format_quote_rounded,
                  color: Color(0xFF7C5CFF),
                  size: 22,
                ),
                const SizedBox(width: 10),
                const Text(
                  'Synced Lyrics',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close_rounded, color: Colors.white70, size: 20),
                  onPressed: onClose,
                ),
              ],
            ),
            const SizedBox(height: 14),
            if (playerController.isLoadingLyrics)
              const Expanded(
                child: Center(
                  child: CircularProgressIndicator(color: Color(0xFF7C5CFF)),
                ),
              )
            else if (!lyrics.isSynced && lyrics.plainLyrics.isEmpty)
              const Expanded(
                child: Center(
                  child: Text(
                    'No lyrics found for this track.',
                    style: TextStyle(color: Colors.white38, fontSize: 13),
                  ),
                ),
              )
            else if (lyrics.isSynced)
              Expanded(
                child: ListView.builder(
                  itemCount: lyrics.syncedLines.length,
                  itemBuilder: (context, index) {
                    final line = lyrics.syncedLines[index];
                    final isActive = index == activeIndex;
                    return GestureDetector(
                      onTap: () => playerController.seekTo(line.timestamp),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8.0),
                        child: Text(
                          line.text,
                          style: TextStyle(
                            color: isActive
                                ? const Color(0xFF7C5CFF)
                                : Colors.white.withValues(alpha: 0.45),
                            fontSize: isActive ? 18 : 15,
                            fontWeight: isActive ? FontWeight.w900 : FontWeight.w600,
                          ),
                        ),
                      ),
                    );
                  },
                ),
              )
            else
              Expanded(
                child: SingleChildScrollView(
                  child: Text(
                    lyrics.plainLyrics,
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 14,
                      height: 1.6,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _MusicQueueDrawer extends StatelessWidget {
  final VoidCallback onClose;

  const _MusicQueueDrawer({required this.onClose});

  @override
  Widget build(BuildContext context) {
    final controller = MusicPlayerController.instance;
    final queue = controller.playlist;
    final currentIndex = controller.currentIndex;
    final isMobile = MediaQuery.sizeOf(context).width < 600;

    return PerformanceLiquidLens(
      style: PerformanceGlassStyles.sheet,
      child: Container(
        width: isMobile ? MediaQuery.sizeOf(context).width : 360,
        decoration: BoxDecoration(
          color: const Color(0xFF0F121C).withValues(alpha: 0.96),
          borderRadius: isMobile
              ? const BorderRadius.vertical(top: Radius.circular(24))
              : const BorderRadius.only(
                  topLeft: Radius.circular(24),
                  bottomLeft: Radius.circular(24),
                ),
          border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
        ),
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.queue_music_rounded,
                  color: Color(0xFF7C5CFF),
                  size: 22,
                ),
                const SizedBox(width: 10),
                Text(
                  'Queue (${queue.length})',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const Spacer(),
                if (queue.isNotEmpty)
                  TextButton(
                    onPressed: controller.clearQueue,
                    child: const Text(
                      'Clear',
                      style: TextStyle(color: Colors.white54, fontSize: 12),
                    ),
                  ),
                IconButton(
                  icon: const Icon(Icons.close_rounded, color: Colors.white70, size: 20),
                  onPressed: onClose,
                ),
              ],
            ),
            const SizedBox(height: 14),
            if (queue.isEmpty)
              const Expanded(
                child: Center(
                  child: Text(
                    'Queue is empty',
                    style: TextStyle(color: Colors.white38, fontSize: 13),
                  ),
                ),
              )
            else
              Expanded(
                child: ListView.separated(
                  itemCount: queue.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final track = queue[index];
                    final isCurrent = index == currentIndex;
                    return ListTile(
                      dense: true,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      tileColor: isCurrent
                          ? const Color(0xFF7C5CFF).withValues(alpha: 0.2)
                          : const Color(0xFF13151F),
                      leading: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: CachedNetworkImage(
                          imageUrl: track.coverUrl,
                          width: 36,
                          height: 36,
                          fit: BoxFit.cover,
                        ),
                      ),
                      title: Text(
                        track.title,
                        style: TextStyle(
                          color: isCurrent ? const Color(0xFF7C5CFF) : Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        track.artist,
                        style: const TextStyle(color: Colors.white54, fontSize: 11),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: IconButton(
                        icon: const Icon(Icons.close_rounded, color: Colors.white38, size: 16),
                        onPressed: () => controller.removeFromQueue(index),
                      ),
                      onTap: () => controller.playTrack(track, playlistQueue: queue),
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

class _MusicArtistDetailModal extends StatelessWidget {
  final MusicArtistDetails details;
  final MusicPlayerController playerController;
  final VoidCallback onClose;
  final Function(MusicTrack, List<MusicTrack>) onPlayTrack;
  final Function(MusicTrack) onAddToPlaylist;
  final Function(String) onOpenAlbum;

  const _MusicArtistDetailModal({
    required this.details,
    required this.playerController,
    required this.onClose,
    required this.onPlayTrack,
    required this.onAddToPlaylist,
    required this.onOpenAlbum,
  });

  @override
  Widget build(BuildContext context) {
    final artist = details.artist;
    final size = MediaQuery.sizeOf(context);
    final isMobile = size.width < 700;

    return Container(
      color: Colors.black.withValues(alpha: 0.85),
      child: Center(
        child: PerformanceLiquidLens(
          style: PerformanceGlassStyles.sheet,
          child: Container(
            width: isMobile ? size.width - 24 : 720,
            height: isMobile ? size.height * 0.85 : 640,
            decoration: BoxDecoration(
              color: const Color(0xFF0F121C),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
            ),
            child: Column(
              children: [
                Stack(
                  children: [
                    SizedBox(
                      height: 200,
                      width: double.infinity,
                      child: CachedNetworkImage(
                        imageUrl: artist.pictureUrl,
                        fit: BoxFit.cover,
                      ),
                    ),
                    Positioned.fill(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.transparent,
                              const Color(0xFF0F121C),
                            ],
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      top: 12,
                      right: 12,
                      child: IconButton(
                        icon: const Icon(Icons.close_rounded, color: Colors.white, size: 24),
                        onPressed: onClose,
                      ),
                    ),
                    Positioned(
                      left: 24,
                      bottom: 16,
                      child: Row(
                        children: [
                          Text(
                            artist.name,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 28,
                              fontWeight: FontWeight.w900,
                              letterSpacing: -0.6,
                            ),
                          ),
                          const SizedBox(width: 16),
                          if (details.topTracks.isNotEmpty)
                            ListenableBuilder(
                              listenable: playerController,
                              builder: (context, _) {
                                final isPlayingAll =
                                    playerController.isPlaying &&
                                        details.topTracks.any((t) =>
                                            t.id == playerController.currentTrack?.id);
                                return ElevatedButton.icon(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFF7C5CFF),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(20),
                                    ),
                                  ),
                                  onPressed: () => onPlayTrack(details.topTracks.first, details.topTracks),
                                  icon: Icon(
                                    isPlayingAll
                                        ? Icons.pause_rounded
                                        : Icons.play_arrow_rounded,
                                    color: Colors.white,
                                  ),
                                  label: Text(
                                    isPlayingAll ? 'Pause All' : 'Play All',
                                    style: const TextStyle(color: Colors.white),
                                  ),
                                );
                              },
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                    children: [
                      if (details.topTracks.isNotEmpty) ...[
                        const Text(
                          'Top Songs',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 12),
                        ListenableBuilder(
                          listenable: playerController,
                          builder: (context, _) {
                            return ListView.separated(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              itemCount: details.topTracks.length.clamp(0, 10),
                              separatorBuilder: (_, __) => const SizedBox(height: 8),
                              itemBuilder: (context, index) {
                                final track = details.topTracks[index];
                                final isCurrent =
                                    playerController.currentTrack?.id == track.id;
                                return _MusicTrackRow(
                                  track: track,
                                  isPlaying: isCurrent && playerController.isPlaying,
                                  isCurrent: isCurrent,
                                  onTap: () => onPlayTrack(track, details.topTracks),
                                  onMoreTap: () => onAddToPlaylist(track),
                                );
                              },
                            );
                          },
                        ),
                        const SizedBox(height: 24),
                      ],
                      if (details.albums.isNotEmpty) ...[
                        const Text(
                          'Albums & Discography',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 12),
                        SizedBox(
                          height: 180,
                          child: ListView.separated(
                            scrollDirection: Axis.horizontal,
                            itemCount: details.albums.length,
                            separatorBuilder: (_, __) => const SizedBox(width: 14),
                            itemBuilder: (context, index) {
                              final album = details.albums[index];
                              return _MusicAlbumCard(album: album, onTap: () => onOpenAlbum(album.id));
                            },
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
    );
  }
}

class _MusicAlbumDetailModal extends StatelessWidget {
  final MusicAlbumDetails details;
  final MusicPlayerController playerController;
  final VoidCallback onClose;
  final Function(MusicTrack, List<MusicTrack>) onPlayTrack;
  final Function(MusicTrack) onAddToPlaylist;

  const _MusicAlbumDetailModal({
    required this.details,
    required this.playerController,
    required this.onClose,
    required this.onPlayTrack,
    required this.onAddToPlaylist,
  });

  @override
  Widget build(BuildContext context) {
    final album = details.album;
    final tracks = details.tracks;
    final size = MediaQuery.sizeOf(context);
    final isMobile = size.width < 700;

    return Container(
      color: Colors.black.withValues(alpha: 0.85),
      child: Center(
        child: PerformanceLiquidLens(
          style: PerformanceGlassStyles.sheet,
          child: Container(
            width: isMobile ? size.width - 24 : 720,
            height: isMobile ? size.height * 0.85 : 640,
            decoration: BoxDecoration(
              color: const Color(0xFF0F121C),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
            ),
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: CachedNetworkImage(
                        imageUrl: album.coverUrl,
                        width: isMobile ? 80 : 120,
                        height: isMobile ? 80 : 120,
                        fit: BoxFit.cover,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            album.title,
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: isMobile ? 18 : 22,
                              fontWeight: FontWeight.w900,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            album.artistName,
                            style: const TextStyle(
                              color: Color(0xFF7C5CFF),
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${tracks.length} tracks • ${album.releaseDate}',
                            style: const TextStyle(color: Colors.white54, fontSize: 12),
                          ),
                          const SizedBox(height: 12),
                          if (tracks.isNotEmpty)
                            ListenableBuilder(
                              listenable: playerController,
                              builder: (context, _) {
                                final isAlbumPlaying =
                                    playerController.isPlaying &&
                                        tracks.any((t) =>
                                            t.id == playerController.currentTrack?.id);
                                return ElevatedButton.icon(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFF7C5CFF),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(16),
                                    ),
                                  ),
                                  onPressed: () => onPlayTrack(tracks.first, tracks),
                                  icon: Icon(
                                    isAlbumPlaying
                                        ? Icons.pause_rounded
                                        : Icons.play_arrow_rounded,
                                    color: Colors.white,
                                  ),
                                  label: Text(
                                    isAlbumPlaying ? 'Pause Album' : 'Play Album',
                                    style: const TextStyle(color: Colors.white),
                                  ),
                                );
                              },
                            ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded, color: Colors.white70),
                      onPressed: onClose,
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                const Divider(color: Colors.white10),
                const SizedBox(height: 8),
                Expanded(
                  child: ListenableBuilder(
                    listenable: playerController,
                    builder: (context, _) {
                      return ListView.separated(
                        itemCount: tracks.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (context, index) {
                          final track = tracks[index];
                          final isCurrent =
                              playerController.currentTrack?.id == track.id;
                          return _MusicTrackRow(
                            track: track,
                            isPlaying: isCurrent && playerController.isPlaying,
                            isCurrent: isCurrent,
                            onTap: () => onPlayTrack(track, tracks),
                            onMoreTap: () => onAddToPlaylist(track),
                          );
                        },
                      );
                    },
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

class _MusicCuratedPlaylistDetailModal extends StatelessWidget {
  final MusicPlaylistDetails details;
  final MusicPlayerController playerController;
  final VoidCallback onClose;
  final Function(MusicTrack, List<MusicTrack>) onPlayTrack;
  final Function(MusicTrack) onAddToPlaylist;

  const _MusicCuratedPlaylistDetailModal({
    required this.details,
    required this.playerController,
    required this.onClose,
    required this.onPlayTrack,
    required this.onAddToPlaylist,
  });

  @override
  Widget build(BuildContext context) {
    final playlist = details.playlist;
    final tracks = details.tracks;
    final size = MediaQuery.sizeOf(context);
    final isMobile = size.width < 700;

    return Container(
      color: Colors.black.withValues(alpha: 0.85),
      child: Center(
        child: PerformanceLiquidLens(
          style: PerformanceGlassStyles.sheet,
          child: Container(
            width: isMobile ? size.width - 24 : 720,
            height: isMobile ? size.height * 0.85 : 640,
            decoration: BoxDecoration(
              color: const Color(0xFF0F121C),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
            ),
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: CachedNetworkImage(
                        imageUrl: playlist.coverUrl,
                        width: isMobile ? 80 : 120,
                        height: isMobile ? 80 : 120,
                        fit: BoxFit.cover,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            playlist.title,
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: isMobile ? 18 : 22,
                              fontWeight: FontWeight.w900,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Curated by ${playlist.creatorName} • ${tracks.length} tracks',
                            style: const TextStyle(color: Colors.white54, fontSize: 13),
                          ),
                          const SizedBox(height: 12),
                          if (tracks.isNotEmpty)
                            ListenableBuilder(
                              listenable: playerController,
                              builder: (context, _) {
                                final isPlaylistPlaying =
                                    playerController.isPlaying &&
                                        tracks.any((t) =>
                                            t.id == playerController.currentTrack?.id);
                                return ElevatedButton.icon(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFF7C5CFF),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(16),
                                    ),
                                  ),
                                  onPressed: () => onPlayTrack(tracks.first, tracks),
                                  icon: Icon(
                                    isPlaylistPlaying
                                        ? Icons.pause_rounded
                                        : Icons.play_arrow_rounded,
                                    color: Colors.white,
                                  ),
                                  label: Text(
                                    isPlaylistPlaying
                                        ? 'Pause Playlist'
                                        : 'Play Playlist',
                                    style: const TextStyle(color: Colors.white),
                                  ),
                                );
                              },
                            ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded, color: Colors.white70),
                      onPressed: onClose,
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                const Divider(color: Colors.white10),
                const SizedBox(height: 8),
                Expanded(
                  child: ListenableBuilder(
                    listenable: playerController,
                    builder: (context, _) {
                      return ListView.separated(
                        itemCount: tracks.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (context, index) {
                          final track = tracks[index];
                          final isCurrent =
                              playerController.currentTrack?.id == track.id;
                          return _MusicTrackRow(
                            track: track,
                            isPlaying: isCurrent && playerController.isPlaying,
                            isCurrent: isCurrent,
                            onTap: () => onPlayTrack(track, tracks),
                            onMoreTap: () => onAddToPlaylist(track),
                          );
                        },
                      );
                    },
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

class _MusicUserPlaylistDetailModal extends StatelessWidget {
  final UserPlaylist playlist;
  final MusicPlayerController playerController;
  final VoidCallback onClose;
  final Function(MusicTrack, List<MusicTrack>) onPlayTrack;
  final Function(String) onRemoveTrack;

  const _MusicUserPlaylistDetailModal({
    required this.playlist,
    required this.playerController,
    required this.onClose,
    required this.onPlayTrack,
    required this.onRemoveTrack,
  });

  @override
  Widget build(BuildContext context) {
    final tracks = playlist.tracks;
    final size = MediaQuery.sizeOf(context);
    final isMobile = size.width < 700;

    return Container(
      color: Colors.black.withValues(alpha: 0.85),
      child: Center(
        child: PerformanceLiquidLens(
          style: PerformanceGlassStyles.sheet,
          child: Container(
            width: isMobile ? size.width - 24 : 720,
            height: isMobile ? size.height * 0.85 : 640,
            decoration: BoxDecoration(
              color: const Color(0xFF0F121C),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
            ),
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: isMobile ? 70 : 100,
                      height: isMobile ? 70 : 100,
                      decoration: BoxDecoration(
                        color: const Color(0xFF7C5CFF).withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Icon(
                        Icons.queue_music_rounded,
                        color: const Color(0xFF7C5CFF),
                        size: isMobile ? 36 : 48,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            playlist.title,
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: isMobile ? 20 : 24,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Custom Playlist • ${tracks.length} tracks',
                            style: const TextStyle(color: Colors.white54, fontSize: 13),
                          ),
                          const SizedBox(height: 12),
                          if (tracks.isNotEmpty)
                            ListenableBuilder(
                              listenable: playerController,
                              builder: (context, _) {
                                final isPlaylistPlaying =
                                    playerController.isPlaying &&
                                        tracks.any((t) =>
                                            t.id == playerController.currentTrack?.id);
                                return ElevatedButton.icon(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFF7C5CFF),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(16),
                                    ),
                                  ),
                                  onPressed: () => onPlayTrack(tracks.first, tracks),
                                  icon: Icon(
                                    isPlaylistPlaying
                                        ? Icons.pause_rounded
                                        : Icons.play_arrow_rounded,
                                    color: Colors.white,
                                  ),
                                  label: Text(
                                    isPlaylistPlaying
                                        ? 'Pause Playlist'
                                        : 'Play Playlist',
                                    style: const TextStyle(color: Colors.white),
                                  ),
                                );
                              },
                            ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded, color: Colors.white70),
                      onPressed: onClose,
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                const Divider(color: Colors.white10),
                const SizedBox(height: 8),
                Expanded(
                  child: tracks.isEmpty
                      ? const Center(
                          child: Text(
                            'No tracks in this playlist yet',
                            style: TextStyle(color: Colors.white38),
                          ),
                        )
                      : ListenableBuilder(
                          listenable: playerController,
                          builder: (context, _) {
                            return ListView.separated(
                          itemCount: tracks.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 8),
                          itemBuilder: (context, index) {
                            final track = tracks[index];
                            final isCurrent =
                                playerController.currentTrack?.id == track.id;
                            return ListTile(
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              tileColor: isCurrent
                                  ? const Color(0xFF7C5CFF).withValues(alpha: 0.15)
                                  : const Color(0xFF13151F),
                              leading: ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: CachedNetworkImage(
                                  imageUrl: track.coverUrl,
                                  width: 44,
                                  height: 44,
                                  fit: BoxFit.cover,
                                ),
                              ),
                              title: Text(
                                track.title,
                                style: TextStyle(
                                  color: isCurrent
                                      ? const Color(0xFF7C5CFF)
                                      : Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                ),
                              ),
                              subtitle: Text(
                                track.artist,
                                style: const TextStyle(color: Colors.white54, fontSize: 12),
                              ),
                              trailing: IconButton(
                                icon: const Icon(Icons.delete_outline_rounded, color: Colors.white38),
                                onPressed: () => onRemoveTrack(track.id),
                              ),
                              onTap: () => onPlayTrack(track, tracks),
                            );
                          },
                        );
                          },
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

class _MusicExpandedPlayer extends StatelessWidget {
  final MusicPlayerController playerController;
  final bool isSaved;
  final VoidCallback onToggleSave;
  final VoidCallback onCollapse;
  final VoidCallback onQueueTap;
  final VoidCallback onAddToPlaylist;

  const _MusicExpandedPlayer({
    required this.playerController,
    required this.isSaved,
    required this.onToggleSave,
    required this.onCollapse,
    required this.onQueueTap,
    required this.onAddToPlaylist,
  });

  @override
  Widget build(BuildContext context) {
    final track = playerController.currentTrack;
    if (track == null) return const SizedBox.shrink();

    // Rebuild on playback/position changes so the progress slider and times
    // stay live inside the expanded player.
    return AnimatedBuilder(
      animation: playerController,
      builder: (context, _) {
        final duration = playerController.duration;
        final position = playerController.position;
        final progress = duration.inMilliseconds > 0
            ? (position.inMilliseconds / duration.inMilliseconds).clamp(0.0, 1.0)
        : 0.0;

    final screenSize = MediaQuery.sizeOf(context);
    final artSize = math.min(screenSize.width * 0.72, screenSize.height * 0.36);

    return Container(
      color: const Color(0xFF0A0C14).withValues(alpha: 0.98),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 14.0),
          child: Column(
            children: [
              Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.keyboard_arrow_down_rounded, color: Colors.white, size: 32),
                    onPressed: onCollapse,
                  ),
                  const Spacer(),
                  const Text(
                    'PLAYING FROM DEEZER & YOUTUBE',
                    style: TextStyle(
                      color: Colors.white54,
                      fontSize: 10,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.0,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.more_horiz_rounded, color: Colors.white),
                    onPressed: onAddToPlaylist,
                  ),
                ],
              ),
              const Spacer(),
              ClipRRect(
                borderRadius: BorderRadius.circular(24),
                child: CachedNetworkImage(
                  imageUrl: track.coverUrl,
                  width: artSize,
                  height: artSize,
                  fit: BoxFit.cover,
                ),
              ),
              const Spacer(),
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          track.title,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.w900,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          track.artist,
                          style: const TextStyle(color: Colors.white60, fontSize: 15),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: Icon(
                      isSaved ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                      color: isSaved ? const Color(0xFFFF4B72) : Colors.white70,
                      size: 28,
                    ),
                    onPressed: onToggleSave,
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Progress Scrub Slider
              SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  thumbColor: const Color(0xFF7C5CFF),
                  activeTrackColor: const Color(0xFF7C5CFF),
                  inactiveTrackColor: Colors.white12,
                  trackHeight: 4,
                  thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                ),
                child: Slider(
                  value: progress,
                  onChanged: (val) {
                    final targetMs = (val * duration.inMilliseconds).toInt();
                    playerController.seekTo(Duration(milliseconds: targetMs));
                  },
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      _formatDuration(position),
                      style: const TextStyle(color: Colors.white38, fontSize: 12),
                    ),
                    Text(
                      _formatDuration(duration),
                      style: const TextStyle(color: Colors.white38, fontSize: 12),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // Playback Controls Row
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  IconButton(
                    icon: Icon(
                      Icons.shuffle_rounded,
                      color: playerController.isShuffle
                          ? const Color(0xFF7C5CFF)
                          : Colors.white38,
                    ),
                    onPressed: playerController.toggleShuffle,
                  ),
                  IconButton(
                    icon: const Icon(Icons.skip_previous_rounded, color: Colors.white, size: 36),
                    onPressed: playerController.playPrevious,
                  ),
                  IconButton(
                    icon: playerController.isLoading
                        ? const SizedBox(
                            width: 32,
                            height: 32,
                            child: CircularProgressIndicator(color: Color(0xFF7C5CFF), strokeWidth: 3),
                          )
                        : Icon(
                            playerController.isPlaying
                                ? Icons.pause_circle_filled_rounded
                                : Icons.play_circle_fill_rounded,
                            color: const Color(0xFF7C5CFF),
                            size: 64,
                          ),
                    onPressed: playerController.togglePlayPause,
                  ),
                  IconButton(
                    icon: const Icon(Icons.skip_next_rounded, color: Colors.white, size: 36),
                    onPressed: playerController.playNext,
                  ),
                  IconButton(
                    icon: Icon(
                      playerController.repeatMode == MusicRepeatMode.one
                          ? Icons.repeat_one_rounded
                          : Icons.repeat_rounded,
                      color: playerController.repeatMode != MusicRepeatMode.off
                          ? const Color(0xFF7C5CFF)
                          : Colors.white38,
                    ),
                    onPressed: playerController.toggleRepeat,
                  ),
                ],
              ),
              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );
      },
    );
  }

  String _formatDuration(Duration d) {
    final mins = d.inMinutes.toString().padLeft(2, '0');
    final secs = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$mins:$secs';
  }
}

class _MusicShortcutsModal extends StatelessWidget {
  final VoidCallback onClose;

  const _MusicShortcutsModal({required this.onClose});

  @override
  Widget build(BuildContext context) {
    final shortcuts = [
      {'key': 'Space / K', 'desc': 'Toggle Play / Pause'},
      {'key': 'J', 'desc': 'Seek -5 seconds backward'},
      {'key': 'L', 'desc': 'Seek +5 seconds forward'},
      {'key': 'M', 'desc': 'Toggle Mute / Unmute'},
      {'key': 'Q', 'desc': 'Toggle Queue Drawer'},
      {'key': 'F', 'desc': 'Toggle Fullscreen Now Playing'},
      {'key': '? / Shift + /', 'desc': 'Show Shortcuts'},
    ];

    return Container(
      color: Colors.black.withValues(alpha: 0.8),
      child: Center(
        child: PerformanceLiquidLens(
          style: PerformanceGlassStyles.sheet,
          child: Container(
            width: 420,
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: const Color(0xFF0F121C),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.keyboard_rounded, color: Color(0xFF7C5CFF), size: 24),
                    const SizedBox(width: 10),
                    const Text(
                      'Keyboard Shortcuts',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.close_rounded, color: Colors.white70),
                      onPressed: onClose,
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                for (final s in shortcuts)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6.0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: const Color(0xFF1B1E2B),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: Colors.white12),
                          ),
                          child: Text(
                            s['key']!,
                            style: const TextStyle(
                              color: Color(0xFF7C5CFF),
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                          ),
                        ),
                        Text(
                          s['desc']!,
                          style: const TextStyle(color: Colors.white70, fontSize: 13),
                        ),
                      ],
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
