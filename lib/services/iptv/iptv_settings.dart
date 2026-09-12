import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../home/home_page_settings.dart';
import 'iptv_network.dart';

enum PortalCardStyle {
  rich('Rich Card with Badges'),
  compact('Compact Row');

  final String label;
  const PortalCardStyle(this.label);
}

enum PortalBrowserLayout {
  grid('Grid Cards'),
  list('Detailed List with EPG'),
  compactList('Compact Channel List');

  final String label;
  const PortalBrowserLayout(this.label);
}

abstract final class IptvSettings {
  // Live TV & Spotlight Keys
  static const _keyEnableSpotlight = 'iptv_enable_spotlight';
  static const _keyHeroStyle = 'iptv_hero_style';
  static const _keyHeroAutoRotate = 'iptv_hero_auto_rotate';
  static const _keyHeroRotateSeconds = 'iptv_hero_rotate_seconds';
  static const _keyCardDensity = 'iptv_card_density';
  static const _keyCardHoverZoom = 'iptv_card_hover_zoom';
  static const _keyShowHdBadge = 'iptv_show_hd_badge';
  static const _keyShowCategoryTag = 'iptv_show_category_tag';
  static const _keyEnableAmbientLights = 'iptv_enable_ambient_lights';
  static const _keyVisibleCategories = 'iptv_visible_categories';

  // Portals Modal Keys
  static const _keyPortalCardStyle = 'iptv_portal_card_style';
  static const _keyShowPortalExpiry = 'iptv_show_portal_expiry';
  static const _keyShowPortalConnections = 'iptv_show_portal_connections';
  static const _keyDefaultPortalTab = 'iptv_default_portal_tab';
  static const _keyDefaultScrapeSource = 'iptv_default_scrape_source';

  // Portal Browser Keys
  static const _keyBrowserLayout = 'iptv_browser_layout';
  static const _keyBrowserGridColumns = 'iptv_browser_grid_columns';
  static const _keyShowStreamLogos = 'iptv_show_stream_logos';
  static const _keyShowEpgSnippet = 'iptv_show_epg_snippet';
  static const _keyShowCategoryCount = 'iptv_show_category_count';
  static const _keySidebarWidth = 'iptv_sidebar_width';

  static const List<String> defaultCategories = [
    'Premier Live Broadcasts',
    'ESPN & College Basketball (NCAA)',
    'US Major Leagues & Sports',
    'Global Football & Soccer',
    'Combat & Martial Arts',
    'Motorsport & Racing',
    'Movies & Premium Networks',
    '24/7 Global News Networks',
    'Arabic & Regional Hub',
    'Discovery & Documentaries',
    'Kids & Family',
    'US Region',
    'UK Region',
    'Canada Region',
    'Bay Area',
    'International Sports',
  ];

  // Live TV Values
  static final ValueNotifier<bool> enableSpotlight = ValueNotifier<bool>(true);
  static final ValueNotifier<HeroStyle> heroStyle =
      ValueNotifier<HeroStyle>(HeroStyle.immersive);
  static final ValueNotifier<bool> heroAutoRotate = ValueNotifier<bool>(true);
  static final ValueNotifier<int> heroRotateSeconds = ValueNotifier<int>(7);
  static final ValueNotifier<CardDensity> cardDensity =
      ValueNotifier<CardDensity>(CardDensity.standard);
  static final ValueNotifier<double> cardHoverZoom = ValueNotifier<double>(1.06);
  static final ValueNotifier<bool> showHdBadge = ValueNotifier<bool>(true);
  static final ValueNotifier<bool> showCategoryTag = ValueNotifier<bool>(true);
  static final ValueNotifier<bool> enableAmbientLights = ValueNotifier<bool>(true);
  static final ValueNotifier<List<String>> visibleCategories =
      ValueNotifier<List<String>>(List.from(defaultCategories));

  // Portals Modal Values
  static final ValueNotifier<PortalCardStyle> portalCardStyle =
      ValueNotifier<PortalCardStyle>(PortalCardStyle.rich);
  static final ValueNotifier<bool> showPortalExpiry = ValueNotifier<bool>(true);
  static final ValueNotifier<bool> showPortalConnections = ValueNotifier<bool>(true);
  static final ValueNotifier<int> defaultPortalTab = ValueNotifier<int>(0);
  static final ValueNotifier<CatalogSource> defaultScrapeSource =
      ValueNotifier<CatalogSource>(CatalogSource.cloudVault);

  // Portal Browser Values
  static final ValueNotifier<PortalBrowserLayout> browserLayout =
      ValueNotifier<PortalBrowserLayout>(PortalBrowserLayout.grid);
  static final ValueNotifier<int> browserGridColumns = ValueNotifier<int>(4);
  static final ValueNotifier<bool> showStreamLogos = ValueNotifier<bool>(true);
  static final ValueNotifier<bool> showEpgSnippet = ValueNotifier<bool>(true);
  static final ValueNotifier<bool> showCategoryCount = ValueNotifier<bool>(true);
  static final ValueNotifier<double> sidebarWidth = ValueNotifier<double>(260.0);

  static final ValueNotifier<int> changeNotifier = ValueNotifier<int>(0);

  static Future<void> initialize() async {
    final prefs = await SharedPreferences.getInstance();
    enableSpotlight.value = prefs.getBool(_keyEnableSpotlight) ?? true;

    final heroStr = prefs.getString(_keyHeroStyle);
    heroStyle.value = HeroStyle.values.firstWhere(
      (h) => h.name == heroStr,
      orElse: () => HeroStyle.immersive,
    );

    heroAutoRotate.value = prefs.getBool(_keyHeroAutoRotate) ?? true;
    heroRotateSeconds.value = prefs.getInt(_keyHeroRotateSeconds) ?? 7;

    final densityStr = prefs.getString(_keyCardDensity);
    cardDensity.value = CardDensity.values.firstWhere(
      (d) => d.name == densityStr,
      orElse: () => CardDensity.standard,
    );

    cardHoverZoom.value = prefs.getDouble(_keyCardHoverZoom) ?? 1.06;
    showHdBadge.value = prefs.getBool(_keyShowHdBadge) ?? true;
    showCategoryTag.value = prefs.getBool(_keyShowCategoryTag) ?? true;
    enableAmbientLights.value = prefs.getBool(_keyEnableAmbientLights) ?? true;

    final savedCats = prefs.getStringList(_keyVisibleCategories);
    if (savedCats != null && savedCats.isNotEmpty) {
      final merged = List<String>.from(savedCats);
      for (final d in defaultCategories) {
        if (!merged.contains(d)) merged.add(d);
      }
      visibleCategories.value = merged;
    } else {
      visibleCategories.value = List.from(defaultCategories);
    }

    // Modal settings
    final pStyleStr = prefs.getString(_keyPortalCardStyle);
    portalCardStyle.value = PortalCardStyle.values.firstWhere(
      (s) => s.name == pStyleStr,
      orElse: () => PortalCardStyle.rich,
    );
    showPortalExpiry.value = prefs.getBool(_keyShowPortalExpiry) ?? true;
    showPortalConnections.value = prefs.getBool(_keyShowPortalConnections) ?? true;
    defaultPortalTab.value = prefs.getInt(_keyDefaultPortalTab) ?? 0;

    final scrapeSrcStr = prefs.getString(_keyDefaultScrapeSource);
    defaultScrapeSource.value = CatalogSource.values.firstWhere(
      (s) => s.name == scrapeSrcStr,
      orElse: () => CatalogSource.cloudVault,
    );

    // Browser settings
    final bLayoutStr = prefs.getString(_keyBrowserLayout);
    browserLayout.value = PortalBrowserLayout.values.firstWhere(
      (l) => l.name == bLayoutStr,
      orElse: () => PortalBrowserLayout.grid,
    );
    browserGridColumns.value = prefs.getInt(_keyBrowserGridColumns) ?? 4;
    showStreamLogos.value = prefs.getBool(_keyShowStreamLogos) ?? true;
    showEpgSnippet.value = prefs.getBool(_keyShowEpgSnippet) ?? true;
    showCategoryCount.value = prefs.getBool(_keyShowCategoryCount) ?? true;
    sidebarWidth.value = prefs.getDouble(_keySidebarWidth) ?? 260.0;
  }

  static Future<void> setEnableSpotlight(bool val) async {
    enableSpotlight.value = val;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyEnableSpotlight, val);
    changeNotifier.value++;
  }

  static Future<void> setHeroStyle(HeroStyle style) async {
    heroStyle.value = style;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyHeroStyle, style.name);
    changeNotifier.value++;
  }

  static Future<void> setHeroAutoRotate(bool val) async {
    heroAutoRotate.value = val;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyHeroAutoRotate, val);
    changeNotifier.value++;
  }

  static Future<void> setHeroRotateSeconds(int seconds) async {
    heroRotateSeconds.value = seconds;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keyHeroRotateSeconds, seconds);
    changeNotifier.value++;
  }

  static Future<void> setCardDensity(CardDensity density) async {
    cardDensity.value = density;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyCardDensity, density.name);
    changeNotifier.value++;
  }

  static Future<void> setCardHoverZoom(double zoom) async {
    cardHoverZoom.value = zoom;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_keyCardHoverZoom, zoom);
    changeNotifier.value++;
  }

  static Future<void> setShowHdBadge(bool val) async {
    showHdBadge.value = val;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyShowHdBadge, val);
    changeNotifier.value++;
  }

  static Future<void> setShowCategoryTag(bool val) async {
    showCategoryTag.value = val;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyShowCategoryTag, val);
    changeNotifier.value++;
  }

  static Future<void> setEnableAmbientLights(bool val) async {
    enableAmbientLights.value = val;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyEnableAmbientLights, val);
    changeNotifier.value++;
  }

  static Future<void> toggleCategoryVisibility(String category) async {
    final list = List<String>.from(visibleCategories.value);
    if (list.contains(category)) {
      if (list.length > 1) {
        list.remove(category);
      }
    } else {
      list.add(category);
    }
    visibleCategories.value = list;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_keyVisibleCategories, list);
    changeNotifier.value++;
  }

  static Future<void> reorderCategories(int oldIndex, int newIndex) async {
    final list = List<String>.from(visibleCategories.value);
    if (oldIndex < newIndex) {
      newIndex -= 1;
    }
    final item = list.removeAt(oldIndex);
    list.insert(newIndex, item);
    visibleCategories.value = list;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_keyVisibleCategories, list);
    changeNotifier.value++;
  }

  static Future<void> resetCategories() async {
    visibleCategories.value = List.from(defaultCategories);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_keyVisibleCategories, defaultCategories);
    changeNotifier.value++;
  }

  // ── Portals Modal Setters ──

  static Future<void> setPortalCardStyle(PortalCardStyle style) async {
    portalCardStyle.value = style;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyPortalCardStyle, style.name);
    changeNotifier.value++;
  }

  static Future<void> setShowPortalExpiry(bool val) async {
    showPortalExpiry.value = val;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyShowPortalExpiry, val);
    changeNotifier.value++;
  }

  static Future<void> setShowPortalConnections(bool val) async {
    showPortalConnections.value = val;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyShowPortalConnections, val);
    changeNotifier.value++;
  }

  static Future<void> setDefaultPortalTab(int tabIndex) async {
    defaultPortalTab.value = tabIndex;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keyDefaultPortalTab, tabIndex);
    changeNotifier.value++;
  }

  static Future<void> setDefaultScrapeSource(CatalogSource source) async {
    defaultScrapeSource.value = source;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyDefaultScrapeSource, source.name);
    changeNotifier.value++;
  }

  // ── Portal Browser Setters ──

  static Future<void> setBrowserLayout(PortalBrowserLayout layout) async {
    browserLayout.value = layout;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyBrowserLayout, layout.name);
    changeNotifier.value++;
  }

  static Future<void> setBrowserGridColumns(int cols) async {
    browserGridColumns.value = cols;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keyBrowserGridColumns, cols);
    changeNotifier.value++;
  }

  static Future<void> setShowStreamLogos(bool val) async {
    showStreamLogos.value = val;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyShowStreamLogos, val);
    changeNotifier.value++;
  }

  static Future<void> setShowEpgSnippet(bool val) async {
    showEpgSnippet.value = val;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyShowEpgSnippet, val);
    changeNotifier.value++;
  }

  static Future<void> setShowCategoryCount(bool val) async {
    showCategoryCount.value = val;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyShowCategoryCount, val);
    changeNotifier.value++;
  }

  static Future<void> setSidebarWidth(double width) async {
    sidebarWidth.value = width;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_keySidebarWidth, width);
    changeNotifier.value++;
  }
}
