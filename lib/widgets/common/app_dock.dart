import 'package:flutter/material.dart';
import '../../pages/anime/anime_page.dart';
import '../../pages/audiobooks/audiobooks_page.dart';
import '../../pages/collection/collection_page.dart';
import '../../pages/home/home_page.dart';
import '../../pages/manga/manga_page.dart';
import '../../pages/music/music_page.dart';
import '../../utils/route_transitions.dart';
import 'liquid_dock.dart';

enum AppHub {
  media,
  manga,
  audiobooks,
  music,
  collection,
}

class AppDock extends StatelessWidget {
  final AppHub currentHub;

  const AppDock({
    super.key,
    required this.currentHub,
  });

  void _navigateTo(BuildContext context, AppHub targetHub) {
    if (targetHub == currentHub) return;

    Widget page;
    switch (targetHub) {
      case AppHub.media:
        page = const HomePage();
        break;
      case AppHub.manga:
        page = const MangaPage();
        break;
      case AppHub.audiobooks:
        page = const AudiobooksPage();
        break;
      case AppHub.music:
        page = const MusicPage();
        break;
      case AppHub.collection:
        page = const CollectionPage();
        break;
    }

    Navigator.pushReplacement(
      context,
      LiquidRevealRoute(
        page: page,
        tapPosition: null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      bottom: 24,
      left: 0,
      right: 0,
      child: Center(
        child: LiquidDock(
          items: [
            DockItem(
              icon: Icons.movie_filter_rounded,
              label: 'Media',
              onTap: () => _navigateTo(context, AppHub.media),
            ),
            DockItem(
              icon: Icons.auto_stories_rounded,
              label: 'Manga',
              onTap: () => _navigateTo(context, AppHub.manga),
            ),
            DockItem(
              icon: Icons.headphones_rounded,
              label: 'Audiobooks',
              onTap: () => _navigateTo(context, AppHub.audiobooks),
            ),
            DockItem(
              icon: Icons.music_note_rounded,
              label: 'Music',
              onTap: () => _navigateTo(context, AppHub.music),
            ),
            DockItem(
              icon: Icons.video_library_rounded,
              label: 'Collection',
              onTap: () => _navigateTo(context, AppHub.collection),
            ),
          ],
        ),
      ),
    );
  }
}
