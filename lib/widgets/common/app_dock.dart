import 'package:flutter/material.dart';
import '../../pages/anime/anime_page.dart';
import '../../pages/audiobooks/audiobooks_page.dart';
import '../../pages/collection/collection_page.dart';
import '../../pages/home/home_page.dart';
import '../../pages/manga/manga_page.dart';
import '../../pages/music/music_page.dart';
import '../../pages/settings/settings_page.dart';
import '../../utils/route_transitions.dart';
import 'liquid_dock.dart';

enum AppHub {
  media,
  anime,
  manga,
  audiobooks,
  music,
  collection,
  settings,
}

class AppDock extends StatelessWidget {
  final AppHub currentHub;

  const AppDock({
    super.key,
    required this.currentHub,
  });

  void _navigateTo(BuildContext context, AppHub targetHub) {
    if (targetHub == currentHub) return;

    if (targetHub == AppHub.settings) {
      Navigator.push(
        context,
        LiquidRevealRoute(
          page: const SettingsPage(),
          tapPosition: null,
        ),
      );
      return;
    }

    Widget page;
    switch (targetHub) {
      case AppHub.media:
        page = const HomePage();
        break;
      case AppHub.anime:
        page = const AnimePage();
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
      case AppHub.settings:
        page = const SettingsPage();
        break;
    }

    // Use pushAndRemoveUntil keeping the first route (app root) so the
    // system/back/pop behavior correctly returns to the Home root instead
    // of leaving an empty stack (which caused the black screen). Settings
    // still use a normal push so they behave like a modal overlay.
    Navigator.pushAndRemoveUntil(
      context,
      LiquidRevealRoute(
        page: page,
        tapPosition: null,
      ),
      (route) => route.isFirst,
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
              label: 'Movies & Series',
              onTap: () => _navigateTo(context, AppHub.media),
            ),
            DockItem(
              icon: Icons.animation_rounded,
              label: 'Anime',
              onTap: () => _navigateTo(context, AppHub.anime),
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
            DockItem(
              icon: Icons.settings_rounded,
              label: 'Settings',
              onTap: () => _navigateTo(context, AppHub.settings),
            ),
          ],
        ),
      ),
    );
  }
}
