import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum DockItemKey {
  home(
    key: 'home',
    label: 'Home',
    icon: Icons.home_rounded,
    isRemovable: false,
    description: 'Explore trending, continue watching, and catalog recommendations.',
  ),
  discover(
    key: 'discover',
    label: 'Discover',
    icon: Icons.explore_rounded,
    isRemovable: true,
    description: 'Explore and filter addon catalogs, genres, and special selectors.',
  ),
  manga(
    key: 'manga',
    label: 'Manga',
    icon: Icons.auto_stories_rounded,
    isRemovable: true,
    description: 'Browse, search, and read manga and webtoons.',
  ),
  books(
    key: 'books',
    label: 'Books',
    icon: Icons.menu_book_rounded,
    isRemovable: true,
    description: 'Read EPUB and PDF eBooks with custom themes.',
  ),
  audiobooks(
    key: 'audiobooks',
    label: 'Audiobooks',
    icon: Icons.headphones_rounded,
    isRemovable: true,
    description: 'Listen to narrated audiobooks with chapter bookmarks.',
  ),
  music(
    key: 'music',
    label: 'Music',
    icon: Icons.music_note_rounded,
    isRemovable: true,
    description: 'High-res lossless streaming, visualizer, and studio playback.',
  ),
  anime(
    key: 'anime',
    label: 'Anime',
    icon: Icons.animation_rounded,
    isRemovable: true,
    description: 'Discover trending seasonal anime, Arabic/Eng subs, and episodes.',
  ),
  liveTv(
    key: 'livetv',
    label: 'Live TV',
    icon: Icons.live_tv_rounded,
    isRemovable: true,
    description: 'Watch worldwide live television channels and sports streams.',
  ),
  multiNutz(
    key: 'multinutz',
    label: 'MultiNutz',
    icon: Icons.apps_rounded,
    isRemovable: true,
    description: 'Multi-window layout with Picture-in-Picture support.',
  ),
  addons(
    key: 'addons',
    label: 'Addons',
    icon: Icons.extension_rounded,
    isRemovable: true,
    description: 'Manage installed Stremio add-ons, catalogs, and scrapers.',
  ),
  downloads(
    key: 'downloads',
    label: 'Downloads',
    icon: Icons.download_rounded,
    isRemovable: true,
    description: 'View active torrent and direct media download tasks.',
  ),
  myList(
    key: 'mylist',
    label: 'My List',
    icon: Icons.favorite_rounded,
    isRemovable: true,
    description: 'Access your saved bookmarks, watchlist, and favorites.',
  ),
  settings(
    key: 'settings',
    label: 'Settings',
    icon: Icons.settings_rounded,
    isRemovable: false,
    description: 'App preferences, accounts, appearance, and player options.',
  ),
  search(
    key: 'search',
    label: 'Search',
    icon: Icons.search_rounded,
    isRemovable: true,
    description: 'Global search across all catalog metadata and addons.',
  );

  final String key;
  final String label;
  final IconData icon;
  final bool isRemovable;
  final String description;

  const DockItemKey({
    required this.key,
    required this.label,
    required this.icon,
    required this.isRemovable,
    required this.description,
  });
}

abstract final class DockSettings {
  static const String _prefPrefix = 'dock_item_enabled_';

  /// Reactive notifier containing the map of enabled dock item keys.
  static final ValueNotifier<Map<String, bool>> enabledNotifier =
      ValueNotifier<Map<String, bool>>({
    for (final item in DockItemKey.values) item.key: true,
  });

  /// Initialize and load saved state from SharedPreferences.
  static Future<void> initialize() async {
    final prefs = await SharedPreferences.getInstance();
    final map = <String, bool>{};

    for (final item in DockItemKey.values) {
      if (!item.isRemovable) {
        // Home and Settings are strictly non-removable
        map[item.key] = true;
      } else {
        map[item.key] = prefs.getBool('$_prefPrefix${item.key}') ?? true;
      }
    }

    enabledNotifier.value = map;
  }

  /// Check whether a specific item key is currently enabled.
  static bool isEnabled(String key) {
    if (key == 'home' || key == 'settings') return true;
    return enabledNotifier.value[key] ?? true;
  }

  /// Toggle or update the enabled status of an item.
  static Future<void> setItemEnabled(String key, bool enabled) async {
    // Prevent disabling non-removable essential items
    if (key == 'home' || key == 'settings') return;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('$_prefPrefix$key', enabled);

    final updated = Map<String, bool>.from(enabledNotifier.value);
    updated[key] = enabled;
    enabledNotifier.value = updated;
  }

  /// Reset all dock item toggles to enabled default.
  static Future<void> resetToDefaults() async {
    final prefs = await SharedPreferences.getInstance();
    for (final item in DockItemKey.values) {
      if (item.isRemovable) {
        await prefs.remove('$_prefPrefix${item.key}');
      }
    }

    enabledNotifier.value = {
      for (final item in DockItemKey.values) item.key: true,
    };
  }
}
