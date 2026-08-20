import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../models/download/download_item.dart';

abstract final class DownloadService {
  static const _storageKey = 'downloads_v1';
  static final ValueNotifier<List<DownloadItem>> downloads = ValueNotifier<List<DownloadItem>>([]);

  static Future<void> initialize() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(_storageKey);
    if (stored != null) {
      try {
        final list = (jsonDecode(stored) as List)
            .map((e) => DownloadItem.fromJson(e as Map<String, dynamic>))
            .toList();
        downloads.value = list;
      } catch (_) {
        downloads.value = [];
      }
    }
  }

  static Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    final data = jsonEncode(downloads.value.map((e) => e.toJson()).toList());
    await prefs.setString(_storageKey, data);
  }

  static void addDownload(DownloadItem item) {
    if (downloads.value.any((d) => d.id == item.id)) return;
    downloads.value = [item, ...downloads.value];
    _persist();
  }

  static void updateProgress(String id, double progress, int receivedBytes, int totalBytes, DownloadStatus status) {
    final index = downloads.value.indexWhere((d) => d.id == id);
    if (index != -1) {
      final updated = downloads.value[index].copyWith(
        progress: progress,
        receivedBytes: receivedBytes,
        totalBytes: totalBytes,
        status: status,
      );
      final list = List<DownloadItem>.from(downloads.value);
      list[index] = updated;
      downloads.value = list;
      _persist();
    }
  }

  static void removeDownload(String id) {
    downloads.value = downloads.value.where((d) => d.id != id).toList();
    _persist();
  }

  static void pauseDownload(String id) {
    final index = downloads.value.indexWhere((d) => d.id == id);
    if (index != -1) {
      final updated = downloads.value[index].copyWith(status: DownloadStatus.paused);
      final list = List<DownloadItem>.from(downloads.value);
      list[index] = updated;
      downloads.value = list;
      _persist();
    }
  }

  static void resumeDownload(String id) {
    final index = downloads.value.indexWhere((d) => d.id == id);
    if (index != -1) {
      final updated = downloads.value[index].copyWith(status: DownloadStatus.downloading);
      final list = List<DownloadItem>.from(downloads.value);
      list[index] = updated;
      downloads.value = list;
      _persist();
    }
  }
}
