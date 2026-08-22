import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../models/my_list/my_list_item.dart';
import '../../services/my_list/my_list_service.dart';
import 'trakt_api_service.dart';
import 'trakt_auth_service.dart';

class TraktSyncService {
  static final ValueNotifier<bool> isSyncing = ValueNotifier<bool>(false);
  static final ValueNotifier<DateTime?> lastSync = ValueNotifier<DateTime?>(null);

  static Future<void> initialize() async {
    final prefs = await SharedPreferences.getInstance();
    final lastSyncStr = prefs.getString('last_trakt_sync');
    if (lastSyncStr != null) {
      lastSync.value = DateTime.tryParse(lastSyncStr);
    }
  }

  /// Perform a safe, non-destructive sync with Trakt.
  /// Merges remote watchlist into local items without removing any local entries.
  static Future<void> manualSync() async {
    final auth = TraktAuthService();
    if (!auth.isLoggedIn.value || isSyncing.value) return;

    isSyncing.value = true;
    try {
      // 1. Pull movie watchlist from Trakt
      final movies = await TraktApiService.getWatchlistMovies();
      for (final raw in movies) {
        final item = MyListItem.fromTraktJson(raw);
        if (!MyListService.isInList(item)) {
          MyListService.add(item);
        }
      }

      // 2. Pull show watchlist from Trakt
      final shows = await TraktApiService.getWatchlistShows();
      for (final raw in shows) {
        final item = MyListItem.fromTraktJson(raw);
        if (!MyListService.isInList(item)) {
          MyListService.add(item);
        }
      }

      // 3. Sync up any local-only items that haven't been pushed to Trakt
      final localOnly = MyListService.items.value
          .where((i) => i.source == MyListSource.local)
          .toList();

      for (final item in localOnly) {
        await syncUp(item);
      }

      final now = DateTime.now();
      lastSync.value = now;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('last_trakt_sync', now.toIso8601String());
    } catch (e) {
      debugPrint('[TraktSyncService] Manual sync error: $e');
    } finally {
      isSyncing.value = false;
    }
  }

  static Future<void> syncDown() async {
    await manualSync();
  }

  static Future<void> syncUp(MyListItem item) async {
    final auth = TraktAuthService();
    if (!auth.isLoggedIn.value) return;

    try {
      final ids = <String, dynamic>{};
      if (item.traktId != null) ids['trakt'] = item.traktId;
      if (item.imdbId != null) ids['imdb'] = item.imdbId;
      if (item.tmdbId != null) ids['tmdb'] = item.tmdbId;

      final Map<String, dynamic> entry = {'ids': ids};
      if (item.title.isNotEmpty) entry['title'] = item.title;
      if (item.year != null) entry['year'] = item.year;

      if (item.type == 'series') {
        await TraktApiService.addToWatchlist(movies: [], shows: [entry]);
      } else {
        await TraktApiService.addToWatchlist(movies: [entry], shows: []);
      }

      // Safely update local item state to mark as synced with Trakt
      final updated = item.copyWith(source: MyListSource.trakt);
      MyListService.markSynced(item, updated);
    } catch (e) {
      debugPrint('[TraktSyncService] syncUp error: $e');
    }
  }

  static Future<bool> syncRemove(MyListItem item, BuildContext context) async {
    final auth = TraktAuthService();
    if (!auth.isLoggedIn.value || item.traktId == null) {
      MyListService.remove(item);
      return true;
    }

    // Ask user if they want to remove from Trakt too
    final removeFromTrakt = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF151822),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Remove from Trakt?',
            style: TextStyle(fontWeight: FontWeight.w800, color: Colors.white)),
        content: Text(
          'Also remove "${item.title}" from your Trakt.tv watchlist?',
          style: TextStyle(color: Colors.white.withValues(alpha: 0.7)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Keep on Trakt',
                style: TextStyle(color: Colors.white.withValues(alpha: 0.6))),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFE50914),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text('Remove from Trakt',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (removeFromTrakt == true) {
      try {
        final ids = <String, dynamic>{'trakt': item.traktId};
        final Map<String, dynamic> entry = {'ids': ids};
        if (item.type == 'series') {
          await TraktApiService.removeFromWatchlist(movies: [], shows: [entry]);
        } else {
          await TraktApiService.removeFromWatchlist(movies: [entry], shows: []);
        }
      } catch (e) {
        debugPrint('[TraktSyncService] syncRemove error: $e');
      }
    }

    MyListService.remove(item);
    return true;
  }

  /// Automatically scrobbles playback progress to Trakt
  static Future<void> scrobblePlayback({
    required String action,
    required double progressPercent,
    required String title,
    String? imdbId,
    int? tmdbId,
    int? season,
    int? episode,
    String type = 'movie',
  }) async {
    final auth = TraktAuthService();
    if (!auth.isLoggedIn.value) return;

    final ids = <String, dynamic>{
      if (imdbId != null && imdbId.isNotEmpty) 'imdb': imdbId,
      if (tmdbId != null) 'tmdb': tmdbId,
    };

    if (type == 'series' || type == 'anime') {
      final showMap = <String, dynamic>{
        'title': title,
        if (ids.isNotEmpty) 'ids': ids,
      };
      final episodeMap = <String, dynamic>{
        if (season != null) 'season': season,
        if (episode != null) 'number': episode,
      };
      await TraktApiService.scrobble(
        action: action,
        progress: progressPercent,
        show: showMap,
        episode: episodeMap,
      );
    } else {
      final movieMap = <String, dynamic>{
        'title': title,
        if (ids.isNotEmpty) 'ids': ids,
      };
      await TraktApiService.scrobble(
        action: action,
        progress: progressPercent,
        movie: movieMap,
      );
    }
  }
}
