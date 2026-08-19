// Port of `MultiWindowBookmarks.kt` + `MultiWindowStorage.android.kt`.
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../models/iptv/iptv_models.dart';
import '../../models/multiwindow/multi_window_models.dart';
import 'iptv_repository.dart';
import 'multi_window_store.dart';

/// Persisted layout + slot-channel set. Mirrors `MultiWindowBookmarks.kt`.
class MultiWindowBookmarkStore {
  MultiWindowBookmarkStore._();

  static final MultiWindowBookmarkStore instance =
      MultiWindowBookmarkStore._();

  static const String _prefsKey = 'multinutz_bookmarks';

  final ValueNotifier<List<MultiWindowBookmark>> bookmarks =
      ValueNotifier(const []);
  bool _loaded = false;
  int _idCounter = 0;

  Future<void> ensureLoaded() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefsKey);
      if (raw != null) {
        bookmarks.value = MultiWindowBookmark.decodeList(raw);
        for (final bm in bookmarks.value) {
          final n = int.tryParse(bm.id.replaceFirst('bm_', '')) ?? 0;
          if (n > _idCounter) _idCounter = n;
        }
      }
    } catch (_) {}
  }

  Future<void> _persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _prefsKey,
        MultiWindowBookmark.encodeList(bookmarks.value),
      );
    } catch (_) {}
  }

  /// Saves the current grid as a named bookmark (layout + occupied slots).
  Future<MultiWindowBookmark> save(String name) async {
    await ensureLoaded();
    final layout = MultiWindowStore.instance.currentLayout.value;
    final slotChannels = <int, IptvChannel>{};
    for (final stream in MultiWindowStore.instance.streams.value) {
      if (stream.channel != null) {
        slotChannels[stream.slotIndex] = stream.channel!;
      }
    }
    final bm = MultiWindowBookmark(
      id: 'bm_${++_idCounter}',
      name: name,
      layoutName: layout?.name,
      slotChannels: slotChannels,
    );
    final updated = List.of(bookmarks.value)..add(bm);
    bookmarks.value = updated;
    await _persist();
    return bm;
  }

  /// Clears the grid and re-adds every stored slot's channel.
  Future<void> load(MultiWindowBookmark bm) async {
    final store = MultiWindowStore.instance;
    store.clear();
    final allChannels = IptvRepository.instance.getAllChannels();
    for (final entry in bm.slotChannels.entries) {
      final ch = allChannels.firstWhereOrNull(
        (c) => c.id == entry.value.id && c.sourceId == entry.value.sourceId,
      );
      if (ch != null) {
        store.addToSlot(ch, entry.key);
      }
    }
  }

  Future<void> delete(String id) async {
    bookmarks.value = List.of(bookmarks.value)
      ..removeWhere((bm) => bm.id == id);
    await _persist();
  }
}

extension _FirstWhereOrNull<T> on Iterable<T> {
  T? firstWhereOrNull(bool Function(T element) test) {
    for (final element in this) {
      if (test(element)) return element;
    }
    return null;
  }
}