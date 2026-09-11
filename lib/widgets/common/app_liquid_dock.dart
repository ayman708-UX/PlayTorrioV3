import 'package:flutter/material.dart';
import '../../pages/anime/anime_page.dart';
import '../../pages/audiobooks/audiobooks_page.dart';
import '../../pages/books/books_page.dart';
import '../../pages/discover/discover_page.dart';
import '../../pages/downloads/downloads_page.dart';
import '../../pages/home/home_page.dart';
import '../../pages/iptv/iptv_page.dart';
import '../../pages/multinutz/multinutz_page.dart';
import '../../pages/manga/manga_page.dart';
import '../../pages/music/music_page.dart';
import '../../pages/my_list/my_list_page.dart';
import '../../pages/search/search_page.dart';
import '../../pages/settings/addons_settings_page.dart';
import '../../pages/settings/settings_page.dart';
import '../../services/theme/dock_settings.dart';
import '../../utils/navigation/route_transitions.dart';
import 'liquid_dock.dart';

/// Reusable global Liquid Glass Dock Navbar connected to [DockSettings].
class AppLiquidDock extends StatelessWidget {
  final DockItemKey? currentDestination;
  final VoidCallback? onSettingsTap;
  final VoidCallback? onSearchTap;
  final VoidCallback? onHomeTap;

  const AppLiquidDock({
    super.key,
    this.currentDestination,
    this.onSettingsTap,
    this.onSearchTap,
    this.onHomeTap,
  });

  void _navigateToPage(BuildContext context, Widget targetPage, {bool isOverlay = false}) {
    if (isOverlay) {
      Navigator.push(
        context,
        LiquidRevealRoute(
          page: targetPage,
          tapPosition: null,
        ),
      );
      return;
    }

    if (currentDestination == DockItemKey.home) {
      Navigator.push(
        context,
        LiquidRevealRoute(
          page: targetPage,
          tapPosition: null,
        ),
      );
    } else {
      Navigator.pushReplacement(
        context,
        LiquidRevealRoute(
          page: targetPage,
          tapPosition: null,
        ),
      );
    }
  }

  void _handleHomeTap(BuildContext context) {
    if (onHomeTap != null) {
      onHomeTap!();
      return;
    }

    if (currentDestination == DockItemKey.home) {
      return;
    }

    if (Navigator.canPop(context)) {
      Navigator.popUntil(context, (route) => route.isFirst);
    } else {
      Navigator.pushReplacement(
        context,
        LiquidRevealRoute(
          page: const HomePage(),
          tapPosition: null,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Map<String, bool>>(
      valueListenable: DockSettings.enabledNotifier,
      builder: (context, enabledMap, _) {
        final items = <DockItem>[];

        for (final itemKey in DockItemKey.values) {
          final isEnabled = enabledMap[itemKey.key] ?? true;
          if (!isEnabled && itemKey.isRemovable) continue;

          switch (itemKey) {
            case DockItemKey.home:
              items.add(
                DockItem(
                  icon: itemKey.icon,
                  label: itemKey.label,
                  onTap: () => _handleHomeTap(context),
                ),
              );
              break;

            case DockItemKey.discover:
              items.add(
                DockItem(
                  icon: itemKey.icon,
                  label: itemKey.label,
                  onTap: () {
                    if (currentDestination == DockItemKey.discover) return;
                    _navigateToPage(context, const DiscoverPage());
                  },
                ),
              );
              break;

            case DockItemKey.manga:
              items.add(
                DockItem(
                  icon: itemKey.icon,
                  label: itemKey.label,
                  onTap: () {
                    if (currentDestination == DockItemKey.manga) return;
                    _navigateToPage(context, const MangaPage());
                  },
                ),
              );
              break;

            case DockItemKey.books:
              items.add(
                DockItem(
                  icon: itemKey.icon,
                  label: itemKey.label,
                  onTap: () {
                    if (currentDestination == DockItemKey.books) return;
                    _navigateToPage(context, const BooksPage());
                  },
                ),
              );
              break;

            case DockItemKey.audiobooks:
              items.add(
                DockItem(
                  icon: itemKey.icon,
                  label: itemKey.label,
                  onTap: () {
                    if (currentDestination == DockItemKey.audiobooks) return;
                    _navigateToPage(context, const AudiobooksPage());
                  },
                ),
              );
              break;

            case DockItemKey.music:
              items.add(
                DockItem(
                  icon: itemKey.icon,
                  label: itemKey.label,
                  onTap: () {
                    if (currentDestination == DockItemKey.music) return;
                    _navigateToPage(context, const MusicPage());
                  },
                ),
              );
              break;

            case DockItemKey.anime:
              items.add(
                DockItem(
                  icon: itemKey.icon,
                  label: itemKey.label,
                  onTap: () {
                    if (currentDestination == DockItemKey.anime) return;
                    _navigateToPage(context, const AnimePage());
                  },
                ),
              );
              break;

            case DockItemKey.liveTv:
              items.add(
                DockItem(
                  icon: itemKey.icon,
                  label: itemKey.label,
                  onTap: () {
                    if (currentDestination == DockItemKey.liveTv) return;
                    _navigateToPage(context, const IptvPage());
                  },
                ),
              );
              break;

            case DockItemKey.multiNutz:
              items.add(
                DockItem(
                  icon: itemKey.icon,
                  label: itemKey.label,
                  onTap: () {
                    if (currentDestination == DockItemKey.multiNutz) return;
                    _navigateToPage(context, const MultiNutzPage());
                  },
                ),
              );
              break;

            case DockItemKey.addons:
              items.add(
                DockItem(
                  icon: itemKey.icon,
                  label: itemKey.label,
                  onTap: () => _navigateToPage(
                    context,
                    const AddonsSettingsPage(),
                    isOverlay: true,
                  ),
                ),
              );
              break;

            case DockItemKey.downloads:
              items.add(
                DockItem(
                  icon: itemKey.icon,
                  label: itemKey.label,
                  onTap: () => _navigateToPage(
                    context,
                    const DownloadsPage(),
                    isOverlay: true,
                  ),
                ),
              );
              break;

            case DockItemKey.myList:
              items.add(
                DockItem(
                  icon: itemKey.icon,
                  label: itemKey.label,
                  onTap: () {
                    if (currentDestination == DockItemKey.myList) return;
                    _navigateToPage(context, const MyListPage());
                  },
                ),
              );
              break;

            case DockItemKey.settings:
              items.add(
                DockItem(
                  icon: itemKey.icon,
                  label: itemKey.label,
                  onTap: () {
                    if (onSettingsTap != null) {
                      onSettingsTap!();
                    } else {
                      _navigateToPage(
                        context,
                        const SettingsPage(),
                        isOverlay: true,
                      );
                    }
                  },
                ),
              );
              break;

            case DockItemKey.search:
              items.add(
                DockItem(
                  icon: itemKey.icon,
                  label: itemKey.label,
                  onTap: () {
                    if (onSearchTap != null) {
                      onSearchTap!();
                    } else {
                      _navigateToPage(
                        context,
                        const SearchPage(),
                        isOverlay: true,
                      );
                    }
                  },
                ),
              );
              break;
          }
        }

        return LiquidDock(items: items);
      },
    );
  }
}
