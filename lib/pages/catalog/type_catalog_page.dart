import 'package:flutter/material.dart';

import '../../models/movie/movie.dart';
import '../../services/addon/addon_manager.dart';
import '../../widgets/common/error_view.dart';
import '../../widgets/common/page_search_button.dart';
import '../../widgets/movie/movie_card.dart';

/// A simple catalog page that shows all content of a given type
/// (e.g. "movie" or "series") aggregated from the installed addons.
///
/// Used by the Media hub's "Movies" and "Series" sidebar sections.
class TypeCatalogPage extends StatefulWidget {
  final String type; // 'movie' | 'series'
  final String title;

  const TypeCatalogPage({
    super.key,
    required this.type,
    required this.title,
  });

  @override
  State<TypeCatalogPage> createState() => _TypeCatalogPageState();
}

class _TypeCatalogPageState extends State<TypeCatalogPage> {
  final _manager = AddonManager.instance;
  List<Movie> _items = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final sections = await _manager.fetchByType(widget.type);
      final seen = <String>{};
      final items = <Movie>[];
      for (final section in sections) {
        for (final movie in section.movies) {
          // Ensure the movie's type matches the section so series are treated
          // as series (some addons omit the type in the JSON).
          final typed = Movie(
            id: movie.id,
            name: movie.name,
            poster: movie.poster,
            year: movie.year,
            type: widget.type,
            addonBaseUrl: movie.addonBaseUrl,
          );
          final key = '${typed.type}:${typed.id}';
          if (seen.add(key)) items.add(typed);
        }
      }
      if (!mounted) return;
      setState(() {
        _items = items;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(color: Color(0xFF7C5CFF)),
      );
    }
    if (_error != null) {
      return ErrorView(error: _error, onRetry: _load);
    }

    final width = MediaQuery.sizeOf(context).width;
    final crossAxisCount = width < 600
        ? 3
        : width < 900
            ? 4
            : width < 1200
                ? 5
                : 6;

    return CustomScrollView(
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
          sliver: SliverToBoxAdapter(
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    widget.title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 28,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -0.5,
                    ),
                  ),
                ),
                const PageSearchButton(),
              ],
            ),
          ),
        ),
        if (_items.isEmpty)
          const SliverFillRemaining(
            hasScrollBody: false,
            child: Center(
              child: Text(
                'No content found. Install more addons in Settings.',
                style: TextStyle(color: Colors.white54, fontSize: 16),
              ),
            ),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 120),
            sliver: SliverGrid(
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: crossAxisCount,
                mainAxisSpacing: 20,
                crossAxisSpacing: 16,
                childAspectRatio: 0.62,
              ),
              delegate: SliverChildBuilderDelegate(
                (context, index) => MovieCard(movie: _items[index]),
                childCount: _items.length,
              ),
            ),
          ),
      ],
    );
  }
}
