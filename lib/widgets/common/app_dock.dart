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
  final ValueChanged<AppHub> onSelectHub;
  final VoidCallback onSettingsTap;

  const AppDock({
    super.key,
    required this.currentHub,
    required this.onSelectHub,
    required this.onSettingsTap,
  });

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
              onTap: () => onSelectHub(AppHub.media),
            ),
            DockItem(
              icon: Icons.animation_rounded,
              label: 'Anime',
              onTap: () => onSelectHub(AppHub.anime),
            ),
            DockItem(
              icon: Icons.auto_stories_rounded,
              label: 'Manga',
              onTap: () => onSelectHub(AppHub.manga),
            ),
            DockItem(
              icon: Icons.headphones_rounded,
              label: 'Audiobooks',
              onTap: () => onSelectHub(AppHub.audiobooks),
            ),
            DockItem(
              icon: Icons.music_note_rounded,
              label: 'Music',
              onTap: () => onSelectHub(AppHub.music),
            ),
            DockItem(
              icon: Icons.video_library_rounded,
              label: 'Collection',
              onTap: () => onSelectHub(AppHub.collection),
            ),
            DockItem(
              icon: Icons.settings_rounded,
              label: 'Settings',
              onTap: onSettingsTap,
            ),
          ],
        ),
      ),
    );
  }
}
