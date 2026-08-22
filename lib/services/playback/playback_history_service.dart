import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../models/playback/playback_history_item.dart';

abstract final class PlaybackHistoryService {
  static const _storageKey = 'playback_history_v1';
  static const int maxItems = 100;

  static final ValueNotifier<List<PlaybackHistoryItem>> history =
      ValueNotifier<List<PlaybackHistoryItem>>([]);

  static Future<void> initialize() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(_storageKey);
    if (stored != null) {
      try {
        final list = (jsonDecode(stored) as List)
            .map((e) => PlaybackHistoryItem.fromJson(e as Map<String, dynamic>))
            .toList();
        history.value = list;
      } catch (_) {
        history.value = [];
      }
    }
  }

  static Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    final data = jsonEncode(history.value.map((e) => e.toJson()).toList());
    await prefs.setString(_storageKey, data);
  }

  static PlaybackHistoryItem? getProgress(String id) {
    try {
      return history.value.firstWhere((h) => h.id == id);
    } catch (_) {
      return null;
    }
  }

  static void saveProgress(PlaybackHistoryItem item) {
    final filtered = history.value.where((h) => h.id != item.id).toList();
    final updated = [item, ...filtered];
    if (updated.length > maxItems) {
      updated.removeRange(maxItems, updated.length);
    }
    history.value = updated;
    _persist();
  }

  static void removeProgress(String id) {
    history.value = history.value.where((h) => h.id != id).toList();
    _persist();
  }
}
