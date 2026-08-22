import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../models/audiobook/audiobook_model.dart';

/// Persists the user's liked audiobooks so they can be shown in the Books
/// hub's Library section.
class AudiobookLibraryService extends ChangeNotifier {
  static final AudiobookLibraryService instance =
      AudiobookLibraryService._internal();
  AudiobookLibraryService._internal();

  static const String _likedKey = 'audiobook_liked_v1';

  List<Audiobook> _liked = [];
  bool _initialized = false;

  List<Audiobook> get liked => _liked;

  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final json = prefs.getString(_likedKey);
      if (json != null) {
        final list = jsonDecode(json) as List<dynamic>;
        _liked = list
            .whereType<Map<String, dynamic>>()
            .map((e) => Audiobook.fromJson(e))
            .toList();
      }
      notifyListeners();
    } catch (e) {
      debugPrint('AudiobookLibraryService init error: $e');
    }
  }

  bool isLiked(String id) => _liked.any((a) => a.uuid == id);

  Future<void> toggleLike(Audiobook audiobook) async {
    final idx = _liked.indexWhere((a) => a.uuid == audiobook.uuid);
    if (idx >= 0) {
      _liked.removeAt(idx);
    } else {
      _liked.insert(0, audiobook);
    }
    notifyListeners();
    await _save();
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    final json = jsonEncode(_liked.map((a) => a.toJson()).toList());
    await prefs.setString(_likedKey, json);
  }
}
