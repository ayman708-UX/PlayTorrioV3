import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';

import '../../models/anime/anime_media.dart';
import '../../services/anime/anilist_service.dart';
import '../../utils/route_transitions.dart';
import '../../widgets/anime/anime_slider_section.dart';
import 'anime_details_page.dart';

class AnimeSearchPage extends StatefulWidget {
  const AnimeSearchPage({super.key});

  @override
  State<AnimeSearchPage> createState() => _AnimeSearchPageState();
}

class _AnimeSearchPageState extends State<AnimeSearchPage> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _focusNode = FocusNode();

  Timer? _debounce;
  bool _isLoading = false;
  bool _allowAdult = false;
  List<AnimeMedia> _allResults = [];
  String _lastQuery = '';

  // Filter selections
  String? _genre;
  int? _year;
  String? _season;
  String? _format;
  String? _status;
  String _sort = 'TRENDING_DESC';

  // Discovery sliders when search is empty and no filters
  List<AnimeMedia> _trendingList = [];
  List<AnimeMedia> _popularSeasonList = [];
  List<AnimeMedia> _topRatedList = [];
  bool _loadingInitial = true;

  static const _genres = [
    'Action', 'Adventure', 'Comedy', 'Drama', 'Ecchi', 'Fantasy',
    'Hentai', 'Horror', 'Mahou Shoujo', 'Mecha', 'Music', 'Mystery',
    'Psychological', 'Romance', 'Sci-Fi', 'Slice of Life',
    'Sports', 'Supernatural', 'Thriller',
  ];

  static const _seasons = ['WINTER', 'SPRING', 'SUMMER', 'FALL'];
  static const _formats = ['TV', 'TV_SHORT', 'MOVIE', 'OVA', 'ONA', 'SPECIAL', 'MUSIC'];
  static const _statuses = ['RELEASING', 'FINISHED', 'NOT_YET_RELEASED', 'CANCELLED', 'HIATUS'];
  static const _sorts = <String, String>{
    'TRENDING_DESC': 'Trending',
    'POPULARITY_DESC': 'Most Popular',
    'SCORE_DESC': 'Top Rated',
    'FAVOURITES_DESC': 'Most Favorited',
    'START_DATE_DESC': 'Newest',
    'START_DATE': 'Oldest',
    'TITLE_ROMAJI': 'Title (A-Z)',
  };

  @override
  void initState() {
    super.initState();
    _loadInitialSliders();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _focusNode.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  bool get _hasActiveFilters =>
      _genre != null ||
      _year != null ||
      _season != null ||
      _format != null ||
      _status != null ||
      _sort != 'TRENDING_DESC';

  void _loadInitialSliders() async {
    try {
      final results = await Future.wait([
        AnilistService.instance.fetchTrendingAnime(page: 1, perPage: 20),
        AnilistService.instance.fetchPopularThisSeason(page: 1, perPage: 20),
        AnilistService.instance.fetchTopRated(page: 1, perPage: 20),
      ]);

      if (mounted) {
        setState(() {
          _trendingList = results[0];
          _popularSeasonList = results[1];
          _topRatedList = results[2];
          _loadingInitial = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _loadingInitial = false;
        });
      }
    }
  }

  void _onSearchChanged(String query) {
    if (_debounce?.isActive ?? false) _debounce!.cancel();

    final trimmed = query.trim();
    if (trimmed.isEmpty && !_hasActiveFilters) {
      setState(() {
        _allResults.clear();
        _isLoading = false;
        _lastQuery = '';
      });
      return;
    }

    _debounce = Timer(const Duration(milliseconds: 450), () {
      _performSearch(trimmed);
    });
  }

  void _performSearch([String? query]) async {
    final q = (query ?? _searchController.text).trim();
    setState(() {
      _isLoading = true;
      _lastQuery = q;
    });

    try {
      final results = await AnilistService.instance.searchAnime(
        q,
        genre: _genre,
        year: _year,
        season: _season,
        format: _format,
        status: _status,
        sort: _sort,
        isAdult: _allowAdult,
        perPage: 35,
      );
      if (!mounted) return;

      setState(() {
        _allResults = results;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _allResults = [];
      });
    }
  }

  void _toggleAdult(bool val) {
    setState(() {
      _allowAdult = val;
    });
    _performSearch();
  }

  void _resetFilters() {
    setState(() {
      _genre = null;
      _year = null;
      _season = null;
      _format = null;
      _status = null;
      _sort = 'TRENDING_DESC';
    });
    if (_searchController.text.trim().isNotEmpty) {
      _performSearch();
    } else {
      setState(() {
        _allResults.clear();
      });
    }
  }

  Future<void> _pickFromList<T>({
    required String title,
    required List<T> items,
    required String Function(T) label,
    required T? current,
    required void Function(T?) onSelected,
  }) async {
    final picked = await showModalBottomSheet<_PickResult<T>>(
      context: context,
      backgroundColor: const Color(0xFF10131E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      isScrollControlled: true,
      builder: (ctx) {
        return DraggableScrollableSheet(
          initialChildSize: 0.55,
          maxChildSize: 0.85,
          minChildSize: 0.35,
          expand: false,
          builder: (_, controller) => Column(
            children: [
              // Top drag indicator
              Container(
                margin: const EdgeInsets.only(top: 12, bottom: 8),
                width: 44,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.25),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),

              // Header
              Padding(
                padding: const EdgeInsets.fromLTRB(22, 6, 16, 12),
                child: Row(
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const Spacer(),
                    if (current != null)
                      TextButton(
                        onPressed: () => Navigator.of(ctx).pop(_PickResult<T>(null, true)),
                        child: const Text(
                          'Clear',
                          style: TextStyle(
                            color: Color(0xFF7C5CFF),
                            fontWeight: FontWeight.w700,
                            fontSize: 14,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const Divider(color: Colors.white10, height: 1),

              // Options list
              Expanded(
                child: ListView.builder(
                  controller: controller,
                  itemCount: items.length,
                  itemBuilder: (_, i) {
                    final v = items[i];
                    final selected = v == current;
                    return Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: () => Navigator.of(ctx).pop(_PickResult<T>(v, false)),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
                          decoration: BoxDecoration(
                            color: selected
                                ? const Color(0xFF7C5CFF).withValues(alpha: 0.12)
                                : Colors.transparent,
                            border: Border(
                              bottom: BorderSide(
                                color: Colors.white.withValues(alpha: 0.04),
                              ),
                            ),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  label(v),
                                  style: TextStyle(
                                    color: selected ? const Color(0xFF7C5CFF) : Colors.white,
                                    fontSize: 15,
                                    fontWeight: selected ? FontWeight.w800 : FontWeight.w500,
                                  ),
                                ),
                              ),
                              if (selected)
                                const Icon(
                                  Icons.check_rounded,
                                  color: Color(0xFF7C5CFF),
                                  size: 20,
                                ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );

    if (picked == null) return;
    onSelected(picked.cleared ? null : picked.value);
    _performSearch();
  }

  Future<void> _pickYear() async {
    final currentYear = DateTime.now().year;
    final years = List.generate(60, (i) => currentYear - i);
    return _pickFromList<int>(
      title: 'Release Year',
      items: years,
      label: (y) => '$y',
      current: _year,
      onSelected: (v) => _year = v,
    );
  }

  String _capitalize(String s) =>
      s.isEmpty ? s : s[0] + s.substring(1).toLowerCase();

  Widget _buildFilterDropdownButton({
    required String label,
    required bool active,
    required VoidCallback onTap,
    IconData? icon,
  }) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Material(
        color: active
            ? const Color(0xFF7C5CFF).withValues(alpha: 0.22)
            : Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: active
                    ? const Color(0xFF7C5CFF).withValues(alpha: 0.65)
                    : Colors.white.withValues(alpha: 0.10),
                width: 1.1,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 14, color: Colors.white70),
                  const SizedBox(width: 6),
                ],
                Text(
                  label,
                  style: TextStyle(
                    color: active ? Colors.white : Colors.white70,
                    fontSize: 12.5,
                    fontWeight: active ? FontWeight.w800 : FontWeight.w600,
                  ),
                ),
                const SizedBox(width: 4),
                Icon(
                  Icons.expand_more_rounded,
                  size: 15,
                  color: active ? const Color(0xFF7C5CFF) : Colors.white38,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _openDetails(AnimeMedia anime) {
    Navigator.push(
      context,
      CinematicSlideRoute(
        page: AnimeDetailsPage(anime: anime),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final topPadding = MediaQuery.of(context).padding.top;
    final isSearching = _searchController.text.trim().isNotEmpty || _hasActiveFilters;

    // Split search results into format sliders
    final tvSeries = _allResults
        .where((a) => a.format.toUpperCase() == 'TV' || a.format.toUpperCase() == 'TV_SHORT')
        .toList();
    final movies = _allResults
        .where((a) => a.format.toUpperCase() == 'MOVIE')
        .toList();
    final ovasAndOthers = _allResults
        .where((a) =>
            a.format.toUpperCase() != 'TV' &&
            a.format.toUpperCase() != 'TV_SHORT' &&
            a.format.toUpperCase() != 'MOVIE')
        .toList();

    return Scaffold(
      backgroundColor: const Color(0xFF080A0F),
      extendBodyBehindAppBar: true,
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(kToolbarHeight + 62),
        child: ClipRRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 28, sigmaY: 28),
            child: Container(
              padding: EdgeInsets.only(top: topPadding + 4, bottom: 8),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    const Color(0xFF080A0F).withValues(alpha: 0.94),
                    const Color(0xFF080A0F).withValues(alpha: 0.70),
                  ],
                ),
                border: Border(
                  bottom: BorderSide(
                    color: Colors.white.withValues(alpha: 0.06),
                  ),
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Row 1: Back Button + Search Bar + 18+ Toggle
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Row(
                      children: [
                        IconButton(
                          icon: const Icon(Icons.arrow_back_ios_rounded, size: 20),
                          color: Colors.white,
                          onPressed: () => Navigator.pop(context),
                        ),
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: Container(
                              height: 42,
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.06),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: Colors.white.withValues(alpha: 0.1),
                                ),
                              ),
                              child: TextField(
                                controller: _searchController,
                                focusNode: _focusNode,
                                autofocus: true,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 15,
                                  fontWeight: FontWeight.w500,
                                ),
                                textInputAction: TextInputAction.search,
                                onChanged: _onSearchChanged,
                                onSubmitted: _performSearch,
                                decoration: InputDecoration(
                                  hintText: 'Search anime, movies, OVAs...',
                                  hintStyle: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.35),
                                    fontSize: 14,
                                  ),
                                  border: InputBorder.none,
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 12,
                                  ),
                                  suffixIcon: _searchController.text.isNotEmpty
                                      ? IconButton(
                                          icon: const Icon(Icons.close_rounded, size: 18),
                                          color: Colors.white60,
                                          onPressed: () {
                                            _searchController.clear();
                                            _onSearchChanged('');
                                          },
                                        )
                                      : const Icon(
                                          Icons.search_rounded,
                                          size: 20,
                                          color: Colors.white54,
                                        ),
                                ),
                              ),
                            ),
                          ),
                        ),

                        // 18+ Adult Toggle Pill
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: GestureDetector(
                            onTap: () => _toggleAdult(!_allowAdult),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                              decoration: BoxDecoration(
                                color: _allowAdult
                                    ? const Color(0xFFEF4444).withValues(alpha: 0.20)
                                    : Colors.white.withValues(alpha: 0.06),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: _allowAdult
                                      ? const Color(0xFFEF4444)
                                      : Colors.white.withValues(alpha: 0.12),
                                  width: 1.2,
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    _allowAdult
                                        ? Icons.check_box_rounded
                                        : Icons.check_box_outline_blank_rounded,
                                    size: 16,
                                    color: _allowAdult ? const Color(0xFFEF4444) : Colors.white54,
                                  ),
                                  const SizedBox(width: 5),
                                  Text(
                                    '18+',
                                    style: TextStyle(
                                      color: _allowAdult ? const Color(0xFFEF4444) : Colors.white70,
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 8),

                  // Row 2: Custom Dropdown Menu Buttons
                  SizedBox(
                    height: 38,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      physics: const BouncingScrollPhysics(),
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      children: [
                        // Sort Dropdown
                        _buildFilterDropdownButton(
                          label: 'Sort: ${_sorts[_sort] ?? "Trending"}',
                          active: _sort != 'TRENDING_DESC',
                          onTap: () => _pickFromList<String>(
                            title: 'Sort By',
                            items: _sorts.keys.toList(),
                            label: (k) => _sorts[k]!,
                            current: _sort,
                            onSelected: (v) => _sort = v ?? 'TRENDING_DESC',
                          ),
                        ),

                        // Genre Dropdown
                        _buildFilterDropdownButton(
                          label: _genre ?? 'Genre',
                          active: _genre != null,
                          onTap: () => _pickFromList<String>(
                            title: 'Genre',
                            items: _genres,
                            label: (g) => g,
                            current: _genre,
                            onSelected: (v) => _genre = v,
                          ),
                        ),

                        // Year Dropdown
                        _buildFilterDropdownButton(
                          label: _year != null ? '$_year' : 'Year',
                          active: _year != null,
                          onTap: _pickYear,
                        ),

                        // Season Dropdown
                        _buildFilterDropdownButton(
                          label: _season != null ? _capitalize(_season!) : 'Season',
                          active: _season != null,
                          onTap: () => _pickFromList<String>(
                            title: 'Season',
                            items: _seasons,
                            label: (s) => _capitalize(s),
                            current: _season,
                            onSelected: (v) => _season = v,
                          ),
                        ),

                        // Format Dropdown
                        _buildFilterDropdownButton(
                          label: _format ?? 'Format',
                          active: _format != null,
                          onTap: () => _pickFromList<String>(
                            title: 'Format',
                            items: _formats,
                            label: (f) => f,
                            current: _format,
                            onSelected: (v) => _format = v,
                          ),
                        ),

                        // Status Dropdown
                        _buildFilterDropdownButton(
                          label: _status != null ? _capitalize(_status!.replaceAll('_', ' ')) : 'Status',
                          active: _status != null,
                          onTap: () => _pickFromList<String>(
                            title: 'Status',
                            items: _statuses,
                            label: (s) => _capitalize(s.replaceAll('_', ' ')),
                            current: _status,
                            onSelected: (v) => _status = v,
                          ),
                        ),

                        // Reset Button
                        if (_hasActiveFilters)
                          Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: Material(
                              color: Colors.white.withValues(alpha: 0.05),
                              borderRadius: BorderRadius.circular(20),
                              child: InkWell(
                                borderRadius: BorderRadius.circular(20),
                                onTap: _resetFilters,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(20),
                                    border: Border.all(color: Colors.white24),
                                  ),
                                  child: const Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.close_rounded, size: 14, color: Colors.white70),
                                      SizedBox(width: 4),
                                      Text(
                                        'Reset',
                                        style: TextStyle(
                                          color: Colors.white70,
                                          fontSize: 12,
                                          fontWeight: FontWeight.bold,
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
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
      body: Stack(
        children: [
          // Content Area
          if (_isLoading || (_loadingInitial && _allResults.isEmpty && _trendingList.isEmpty))
            const Center(
              child: CircularProgressIndicator(color: Color(0xFF7C5CFF)),
            )
          else if (isSearching && _allResults.isEmpty)
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.search_off_rounded,
                    size: 64,
                    color: Colors.white.withValues(alpha: 0.2),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    _lastQuery.isNotEmpty
                        ? 'No anime results for "$_lastQuery"'
                        : 'No anime found with selected filters',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.6),
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            )
          else if (_allResults.isNotEmpty)
            ListView(
              clipBehavior: Clip.none,
              padding: EdgeInsets.only(
                top: topPadding + kToolbarHeight + 80,
                bottom: 40,
              ),
              physics: const BouncingScrollPhysics(),
              children: [
                if (tvSeries.isNotEmpty)
                  AnimeSliderSection(
                    title: 'Anime TV Series',
                    subtitle: '${tvSeries.length} Results',
                    animeList: tvSeries,
                    onAnimeTap: _openDetails,
                  ),
                if (movies.isNotEmpty)
                  AnimeSliderSection(
                    title: 'Anime Movies',
                    subtitle: '${movies.length} Results',
                    animeList: movies,
                    onAnimeTap: _openDetails,
                  ),
                if (ovasAndOthers.isNotEmpty)
                  AnimeSliderSection(
                    title: 'OVAs, ONAs & Specials',
                    subtitle: '${ovasAndOthers.length} Results',
                    animeList: ovasAndOthers,
                    onAnimeTap: _openDetails,
                  ),
              ],
            )
          else
            // Discovery Sliders when not searching
            ListView(
              clipBehavior: Clip.none,
              padding: EdgeInsets.only(
                top: topPadding + kToolbarHeight + 80,
                bottom: 40,
              ),
              physics: const BouncingScrollPhysics(),
              children: [
                if (_trendingList.isNotEmpty)
                  AnimeSliderSection(
                    title: 'Trending Anime',
                    animeList: _trendingList,
                    onAnimeTap: _openDetails,
                  ),
                if (_popularSeasonList.isNotEmpty)
                  AnimeSliderSection(
                    title: 'Popular This Season',
                    animeList: _popularSeasonList,
                    onAnimeTap: _openDetails,
                  ),
                if (_topRatedList.isNotEmpty)
                  AnimeSliderSection(
                    title: 'All-Time Top Rated',
                    animeList: _topRatedList,
                    onAnimeTap: _openDetails,
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

class _PickResult<T> {
  final T? value;
  final bool cleared;
  _PickResult(this.value, this.cleared);
}
