import 'package:flutter/material.dart';

import '../../widgets/common/section_top_bar.dart';
import '../../utils/hub_controller.dart';
import '../../utils/search_scope.dart';
import '../anime/anime_page.dart';
import '../collection/collection_page.dart';
import '../catalog/type_catalog_page.dart';
import '../catalog/genres_page.dart';

/// Media hub: Movies, Series, Anime, and the user's media collection.
///
/// Sections are switched via the [SectionTopBar] chip bar. The active section
/// is driven by the shared [HubController] so navigation stays in sync.
class MediaHub extends StatelessWidget {
  const MediaHub({super.key});

  static Widget _buildSection(String activeSection) {
    switch (activeSection) {
      case 'movies':
        SearchScope.set('movie', label: 'Movies');
        return const TypeCatalogPage(type: 'movie', title: 'Movies');
      case 'series':
        SearchScope.set('series', label: 'Series');
        return const TypeCatalogPage(type: 'series', title: 'Series');
      case 'anime':
        SearchScope.set('anime', label: 'Anime');
        return const AnimePage();
      case 'genres':
        SearchScope.set(null, label: 'Genres');
        return const GenresPage();
      case 'collection':
        SearchScope.set(null, label: 'Library');
        return const CollectionPage();
      default:
        SearchScope.set(null, label: 'Movies');
        return const TypeCatalogPage(type: 'movie', title: 'Movies');
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: HubController.instance,
      builder: (context, _) {
        final activeSection = HubController.instance.mediaSection;
        return Scaffold(
          backgroundColor: const Color(0xFF080A0F),
          body: Column(
            children: [
              const SectionTopBar(),
              Expanded(child: _buildSection(activeSection)),
            ],
          ),
        );
      },
    );
  }
}
