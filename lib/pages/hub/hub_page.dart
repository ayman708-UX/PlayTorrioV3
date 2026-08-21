import 'package:flutter/material.dart';

import '../../widgets/common/app_dock.dart';
import '../home/home_page.dart';
import '../anime/anime_page.dart';
import '../manga/manga_page.dart';
import '../audiobooks/audiobooks_page.dart';
import '../music/music_page.dart';
import '../collection/collection_page.dart';
import '../settings/settings_page.dart';

/// HubPage: a top-level container that will host all primary app hubs
/// (Movies & Series, Anime, Manga, Audiobooks, Music, Collection).
///
/// This is a lightweight skeleton for the staged refactor. It exposes an
/// IndexedStack and manages the current hub index. At this stage it does not
/// replace the dock navigation behavior — the existing AppDock remains in the
/// child pages so this change is low-risk and reversible.
class HubPage extends StatefulWidget {
  const HubPage({Key? key}) : super(key: key);

  @override
  State<HubPage> createState() => _HubPageState();
}

class _HubPageState extends State<HubPage> {
  AppHub _currentHub = AppHub.media;

  final List<Widget> _children = const [
    HomePage(),
    AnimePage(),
    MangaPage(),
    AudiobooksPage(),
    MusicPage(),
    CollectionPage(),
  ];

  void _setHub(AppHub hub) {
    setState(() {
      _currentHub = hub;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          IndexedStack(
            index: _currentHub.index,
            children: _children,
          ),
          AppDock(
            currentHub: _currentHub,
            onSelectHub: (hub) {
              // Update the displayed hub
              _setHub(hub);
            },
            onSettingsTap: () {
              Navigator.push(
                context,
                // Use the same LiquidReveal transition for settings
                // tapPosition left as null for center reveal
                // to match previous behavior
                LiquidRevealRoute(page: const SettingsPage(), tapPosition: null),
              );
            },
          ),
        ],
      ),
    );
  }
}
