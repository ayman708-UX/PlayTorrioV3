import 'package:flutter/material.dart';

import '../../services/addon/addon_manager.dart';
import '../../widgets/common/error_view.dart';
import '../../widgets/common/page_search_button.dart';
import '../discover/discover_page.dart';

/// A "Genres" browse section for the Media hub.
///
/// Aggregates the distinct genres advertised by all active addons (movies and
/// series catalogs) and lets the user pick one to browse. Tapping a genre
/// opens a [DiscoverPage] filtered by that genre.
class GenresPage extends StatefulWidget {
  const GenresPage({super.key});

  @override
  State<GenresPage> createState() => _GenresPageState();
}

class _GenresPageState extends State<GenresPage> {
  bool _isLoading = true;
  String? _error;
  List<String> _genres = [];

  @override
  void initState() {
    super.initState();
    _loadGenres();
  }

  Future<void> _loadGenres() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final genres = <String>{};
      for (final addon in AddonManager.instance.activeAddons) {
        for (final catalog in addon.manifest.catalogs) {
          if (catalog.type != 'movie' && catalog.type != 'series') continue;
          genres.addAll(catalog.genres);
        }
      }
      // Filter out year-like entries (e.g. "2024", "2025") that some addons
      // advertise as genres, and drop empty/whitespace strings.
      final filtered = genres.where((g) {
        final trimmed = g.trim();
        if (trimmed.isEmpty) return false;
        // Exclude pure 4-digit years.
        if (RegExp(r'^\d{4}$').hasMatch(trimmed)) return false;
        return true;
      }).toSet();
      // Sort alphabetically, case-insensitive.
      final sorted = filtered.toList()
        ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

      if (!mounted) return;
      setState(() {
        _genres = sorted;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  void _openGenre(String genre) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => DiscoverPage(query: genre, isGenre: true),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: Color(0xFF7C5CFF)),
      );
    }

    if (_error != null) {
      return ErrorView(
        error: _error!,
        onRetry: _loadGenres,
      );
    }

    if (_genres.isEmpty) {
      return const Center(
        child: Text(
          'No genres available from your addons.',
          style: TextStyle(color: Colors.white54),
        ),
      );
    }

    final width = MediaQuery.sizeOf(context).width;
    final crossAxisCount = width >= 1400
        ? 6
        : width >= 1100
            ? 5
            : width >= 800
                ? 4
                : width >= 500
                    ? 3
                    : 2;

    return CustomScrollView(
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 12),
          sliver: SliverToBoxAdapter(
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    'Genres',
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),
                const PageSearchButton(),
              ],
            ),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
          sliver: SliverGrid(
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: crossAxisCount,
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: 2.4,
            ),
            delegate: SliverChildBuilderDelegate(
              (context, index) {
                final genre = _genres[index];
                return _GenreTile(
                  genre: genre,
                  onTap: () => _openGenre(genre),
                );
              },
              childCount: _genres.length,
            ),
          ),
        ),
      ],
    );
  }
}

class _GenreTile extends StatelessWidget {
  final String genre;
  final VoidCallback onTap;

  const _GenreTile({required this.genre, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFF141824),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
          ),
          child: Text(
            genre,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}
