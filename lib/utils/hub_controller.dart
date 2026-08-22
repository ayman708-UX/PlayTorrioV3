import 'package:flutter/material.dart';

import 'app_hub.dart';

/// A single section within a hub (e.g. Media -> Movies, Books -> Manga).
class HubSection {
  final String id;
  final String label;
  final IconData icon;

  const HubSection({
    required this.id,
    required this.label,
    required this.icon,
  });
}

/// Global controller for the top-level navigation: which hub is active and
/// which section within that hub. The header and the hubs both read/write this
/// so navigation stays in sync.
class HubController extends ChangeNotifier {
  static final HubController instance = HubController._internal();
  HubController._internal();

  AppHub _currentHub = AppHub.media;
  String _mediaSection = 'movies';
  String _booksSection = 'manga';
  String _musicTab = 'Music';

  AppHub get currentHub => _currentHub;
  String get mediaSection => _mediaSection;
  String get booksSection => _booksSection;
  String get musicTab => _musicTab;

  void setHub(AppHub hub) {
    if (_currentHub == hub) return;
    _currentHub = hub;
    notifyListeners();
  }

  void setMediaSection(String id) {
    if (_mediaSection == id) return;
    _mediaSection = id;
    notifyListeners();
  }

  void setBooksSection(String id) {
    if (_booksSection == id) return;
    _booksSection = id;
    notifyListeners();
  }

  void setMusicTab(String tab) {
    if (_musicTab == tab) return;
    _musicTab = tab;
    notifyListeners();
  }

  /// The sections available for the current hub.
  List<HubSection> get currentSections {
    switch (_currentHub) {
      case AppHub.media:
        return const [
          HubSection(id: 'movies', label: 'Movies', icon: Icons.movie_rounded),
          HubSection(id: 'series', label: 'Series', icon: Icons.live_tv_rounded),
          HubSection(id: 'anime', label: 'Anime', icon: Icons.animation_rounded),
          HubSection(id: 'genres', label: 'Genres', icon: Icons.category_rounded),
          HubSection(id: 'collection', label: 'Library', icon: Icons.video_library_rounded),
        ];
      case AppHub.books:
        return const [
          HubSection(id: 'manga', label: 'Manga', icon: Icons.auto_stories_rounded),
          HubSection(id: 'comics', label: 'Comics', icon: Icons.menu_book_rounded),
          HubSection(id: 'collection', label: 'Library', icon: Icons.collections_bookmark_rounded),
        ];
      case AppHub.music:
        return const [
          HubSection(id: 'Music', label: 'Music', icon: Icons.music_note_rounded),
          HubSection(id: 'Search', label: 'Search', icon: Icons.search_rounded),
          HubSection(id: 'Genres', label: 'Genres', icon: Icons.category_rounded),
          HubSection(id: 'Radio', label: 'Radio', icon: Icons.radio_rounded),
          HubSection(id: 'Audiobooks', label: 'Audiobooks', icon: Icons.headphones_rounded),
          HubSection(id: 'Library', label: 'Library', icon: Icons.library_music_rounded),
        ];
    }
  }

  /// The id of the active section within the current hub.
  String get currentSectionId {
    switch (_currentHub) {
      case AppHub.media:
        return _mediaSection;
      case AppHub.books:
        return _booksSection;
      case AppHub.music:
        return _musicTab;
    }
  }

  void setCurrentSection(String id) {
    switch (_currentHub) {
      case AppHub.media:
        setMediaSection(id);
        break;
      case AppHub.books:
        setBooksSection(id);
        break;
      case AppHub.music:
        setMusicTab(id);
        break;
    }
  }
}
