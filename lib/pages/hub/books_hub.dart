import 'package:flutter/material.dart';

import '../../widgets/common/section_top_bar.dart';
import '../../utils/hub_controller.dart';
import '../../utils/search_scope.dart';
import '../manga/manga_page.dart';
import '../collection/books_library_page.dart';
import '../catalog/comics_page.dart';

/// Read hub: Manga, Comics, and the user's reading collection.
///
/// Sections are switched via the [SectionTopBar] chip bar. The active section
/// is driven by the shared [HubController] so navigation stays in sync.
class BooksHub extends StatelessWidget {
  const BooksHub({super.key});

  static Widget _buildSection(String activeSection) {
    switch (activeSection) {
      case 'manga':
        SearchScope.set('manga', label: 'Manga');
        return const MangaPage();
      case 'comics':
        SearchScope.set(null, label: 'Comics');
        return const ComicsPage();
      case 'collection':
        SearchScope.set(null, label: 'Library');
        return const BooksLibraryPage();
      default:
        SearchScope.set('manga', label: 'Manga');
        return const MangaPage();
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: HubController.instance,
      builder: (context, _) {
        final activeSection = HubController.instance.booksSection;
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
