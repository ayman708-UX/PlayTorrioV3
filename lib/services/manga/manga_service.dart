import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:html/parser.dart' as html_parser;
import 'package:shared_preferences/shared_preferences.dart';

import '../../models/manga/manga.dart';
import '../../models/manga/manga_chapter.dart';

const String _baseUrl = 'https://weebcentral.com';
const String _coverCdn = 'https://temp.compsci88.com/cover';

class MangaService {
  static const String _likedKey = 'liked_manga';
  static const String _historyKey = 'manga_reading_history';
  static const int _pageSize = 32;
  static const String _userAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0.0.0 Safari/537.36';

  final http.Client _client = http.Client();

  /// Bumped whenever the reading history is saved or removed.
  static final ValueNotifier<int> readingHistoryRevision = ValueNotifier<int>(0);

  Map<String, String> get _headers => {
        'User-Agent': _userAgent,
        'Accept':
            'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
        'Accept-Language': 'en-US,en;q=0.9',
      };

  Future<String> _fetchHtml(String url) async {
    final response = await _client.get(Uri.parse(url), headers: _headers);
    if (response.statusCode != 200) {
      throw Exception('HTTP ${response.statusCode} for $url');
    }
    return response.body;
  }

  String? _extractSeriesId(String url) {
    final match = RegExp(r'/series/([A-Z0-9]{26})').firstMatch(url);
    return match?.group(1);
  }

  String? _extractChapterId(String url) {
    final match = RegExp(r'/chapters/([A-Z0-9]{26})').firstMatch(url);
    return match?.group(1);
  }

  // ── Browse / Search ─────────────────────────────────────────────────

  Future<List<Manga>> getManga({int page = 1, String? tag, bool allowAdult = false}) async {
    final offset = (page - 1) * _pageSize;
    final adult = allowAdult ? 'Any' : 'False';
    var url =
        '$_baseUrl/search/data?text=&display_mode=Full+Display&sort=Popularity&order=Descending&official=Any&adult=$adult&offset=$offset';
    if (tag != null) {
      url += '&included_tag=${Uri.encodeComponent(tag)}';
    }
    debugPrint('[MangaService] Fetching page $page: $url');
    final html = await _fetchHtml(url);
    return _parseSearchResults(html);
  }

  Future<List<Manga>> searchManga(String query, {int page = 1, bool allowAdult = false}) async {
    final offset = (page - 1) * _pageSize;
    final adult = allowAdult ? 'Any' : 'False';
    final encodedQuery = Uri.encodeComponent(query);
    final url =
        '$_baseUrl/search/data?text=$encodedQuery&display_mode=Full+Display&sort=Best+Match&order=Descending&official=Any&adult=$adult&offset=$offset';
    debugPrint('[MangaService] Searching page $page: $url');
    final html = await _fetchHtml(url);
    return _parseSearchResults(html);
  }

  List<Manga> _parseSearchResults(String html) {
    final doc = html_parser.parse(html);
    final articles = doc.querySelectorAll('article');
    final results = <Manga>[];

    for (final article in articles) {
      final seriesLink = article.querySelector('a[href*="/series/"]');
      if (seriesLink == null) continue;

      final href = seriesLink.attributes['href'] ?? '';
      final seriesId = _extractSeriesId(href);
      if (seriesId == null) continue;

      String title = '';

      // 1. Target line-clamp-1 link inside title tooltip
      final titleLink = article.querySelector('a.line-clamp-1, a.link-hover');
      if (titleLink != null && titleLink.text.trim().isNotEmpty) {
        title = titleLink.text.trim();
      }

      // 2. Target img alt attribute ("Title cover" -> "Title")
      if (title.isEmpty) {
        final img = article.querySelector('img');
        final alt = img?.attributes['alt'] ?? '';
        if (alt.toLowerCase().endsWith(' cover')) {
          title = alt.substring(0, alt.length - 6).trim();
        } else if (alt.isNotEmpty) {
          title = alt.trim();
        }
      }

      // 3. Fallback to series link text
      if (title.isEmpty) {
        title = seriesLink.text.trim().split('\n').first.trim();
      }

      // Strip unwanted badge prefixes like "Official" if attached
      title = title.replaceAll(RegExp(r'^Official\s+', caseSensitive: false), '').trim();

      // Type from tooltip data-tip matching known types
      String type = '';
      for (final el in article.querySelectorAll('[data-tip]')) {
        final tip = el.attributes['data-tip'] ?? '';
        if (['Manga', 'Manhwa', 'Manhua', 'OEL'].contains(tip)) {
          type = tip;
          break;
        }
      }

      results.add(Manga(
        id: seriesId,
        title: title,
        coverSmall: '$_coverCdn/small/$seriesId.webp',
        coverNormal: '$_coverCdn/normal/$seriesId.webp',
        type: type,
        url: href,
      ));
    }

    return results;
  }

  // ── Series Detail ───────────────────────────────────────────────────

  Future<Manga> getSeriesDetail(String seriesId) async {
    final html = await _fetchHtml('$_baseUrl/series/$seriesId');
    final doc = html_parser.parse(html);

    String title = doc.querySelector('h1')?.text.trim() ?? '';
    title = title.replaceAll(RegExp(r'^Official\s+', caseSensitive: false), '').trim();
    if (title.isEmpty) {
      final ogTitle = doc.querySelector('meta[property="og:title"]')?.attributes['content'] ?? '';
      title = ogTitle.replaceAll(RegExp(r'\s*-\s*Weeb\s*Central.*$', caseSensitive: false), '').trim();
    }

    // Scope metadata extraction strictly to the left sidebar section
    final sidebar = doc.querySelector('section.md\\:w-4\\/12') ?? doc.querySelector('section');
    final details = <String, List<String>>{};
    final items = sidebar != null
        ? sidebar.querySelectorAll('li, div.flex, div.grid')
        : doc.querySelectorAll('li');

    for (final element in items) {
      final strong = element.querySelector('strong, b, span.font-bold, span.font-semibold');
      if (strong == null) continue;
      final label = strong.text.trim().replaceAll(':', '').replaceAll('(s)', '').trim();
      if (label.isEmpty) continue;

      final links = element.querySelectorAll('a');
      List<String> values = [];
      if (links.isNotEmpty) {
        values = links
            .map((a) => a.text.trim())
            .where((t) => t.isNotEmpty && t != strong.text.trim() && !t.contains('RSS'))
            .toList();
      } else {
        String rawText = element.text.trim();
        if (rawText.startsWith(strong.text.trim())) {
          rawText = rawText.substring(strong.text.trim().length).trim();
        }
        rawText = rawText.replaceAll(RegExp(r'^\s*:\s*'), '').trim();
        if (rawText.isNotEmpty) {
          values = [rawText];
        }
      }

      if (values.isNotEmpty && !details.containsKey(label)) {
        details[label] = values;
      }
    }

    // Robust year resolution
    String year = '';
    final possibleYearKeys = ['Released', 'Release Year', 'Year', 'Published', 'Date', 'Release'];
    for (final key in possibleYearKeys) {
      if (details.containsKey(key) && details[key]!.isNotEmpty) {
        final rawVal = details[key]!.first;
        final yearMatch = RegExp(r'\b(19\d\d|20\d\d)\b').firstMatch(rawVal);
        if (yearMatch != null) {
          year = yearMatch.group(1)!;
          break;
        } else if (rawVal.isNotEmpty) {
          year = rawVal;
          break;
        }
      }
    }

    if (year.isEmpty) {
      final yearMatch = RegExp(r'\b(19\d\d|20\d\d)\b').firstMatch(html);
      if (yearMatch != null) {
        year = yearMatch.group(1)!;
      }
    }

    // Synopsis: target p.whitespace-pre-wrap directly, or clean fallback
    String synopsis = doc.querySelector('p.whitespace-pre-wrap, .whitespace-pre-wrap')?.text.trim() ?? '';
    if (synopsis.isEmpty) {
      for (final p in doc.querySelectorAll('p')) {
        final text = p.text.trim();
        if (text.length > 30 &&
            !text.contains('Copyright') &&
            !text.contains('verified') &&
            !text.contains('Last Read') &&
            !text.contains('Chapter') &&
            !text.contains('emoji')) {
          synopsis = text;
          break;
        }
      }
    }

    return Manga(
      id: seriesId,
      title: title,
      coverSmall: '$_coverCdn/small/$seriesId.webp',
      coverNormal: '$_coverCdn/normal/$seriesId.webp',
      type: (details['Type']?.isNotEmpty ?? false) ? details['Type']!.first : '',
      status: (details['Status']?.isNotEmpty ?? false) ? details['Status']!.first : '',
      year: year,
      author: (details['Author'] ?? details['Author(s)'] ?? []).join(', '),
      tags: details['Tag'] ?? details['Tags'] ?? details['Genres'] ?? [],
      synopsis: synopsis,
      url: '/series/$seriesId',
    );
  }

  // ── Chapters ────────────────────────────────────────────────────────

  Future<List<MangaChapter>> getChapters(String seriesId) async {
    try {
      final html =
          await _fetchHtml('$_baseUrl/series/$seriesId/full-chapter-list');
      final doc = html_parser.parse(html);

      final chapters = <MangaChapter>[];
      final links = doc.querySelectorAll('a[href*="/chapters/"]');

      for (final a in links) {
        final href = a.attributes['href'] ?? '';
        final chapterId = _extractChapterId(href);
        if (chapterId == null) continue;

        final titleSpan = a.querySelector('.grow > span:first-child') ??
            a.querySelector('span:not([class*="link-info"]):not([class*="me-2"])');

        String chapterName = titleSpan?.text.trim() ?? '';

        if (chapterName.isEmpty) {
          String fullText = a.text.trim();
          fullText = fullText.replaceAll(RegExp(r'Last Read', caseSensitive: false), '').trim();
          chapterName = fullText;
        }

        if (chapterName.isNotEmpty) {
          chapters.add(MangaChapter.fromRaw(chapterId, chapterName, href));
        }
      }

      debugPrint('[MangaService] Found ${chapters.length} chapters');
      return chapters;
    } catch (e) {
      debugPrint('[MangaService] Error fetching chapters: $e');
      return [];
    }
  }

  // ── Chapter Images ──────────────────────────────────────────────────

  Future<List<String>> getChapterImages(String chapterId) async {
    try {
      final url =
          '$_baseUrl/chapters/$chapterId/images?is_prev=False&current_page=1&reading_style=long_strip';
      final html = await _fetchHtml(url);
      final doc = html_parser.parse(html);

      final images = <String>[];
      for (final img in doc.querySelectorAll('img')) {
        final src = img.attributes['src'] ?? '';
        if (src.isNotEmpty &&
            !src.contains('/static/') &&
            !src.contains('brand')) {
          images.add(src);
        }
      }

      debugPrint('[MangaService] Found ${images.length} chapter images');
      return images;
    } catch (e) {
      debugPrint('[MangaService] Error fetching chapter images: $e');
      return [];
    }
  }

  // ── History & Tracking ──────────────────────────────────────────────

  Future<void> saveProgress(Manga manga, int chapterIndex, int pageIndex, List<MangaChapter> chapters) async {
    final prefs = await SharedPreferences.getInstance();
    
    final progress = {
      'manga': manga.toJson(),
      'chapterIndex': chapterIndex,
      'pageIndex': pageIndex,
      'chapters': chapters.map((c) => c.toJson()).toList(),
      'timestamp': DateTime.now().toIso8601String(),
    };

    final historyJson = prefs.getStringList(_historyKey) ?? [];
    final history = historyJson.map((e) => jsonDecode(e) as Map<String, dynamic>).toList();
    
    // Remove existing entry for this manga
    history.removeWhere((h) => h['manga']['id'] == manga.id);
    
    // Add new entry at the beginning
    history.insert(0, progress);
    
    // Keep only last 10 items
    if (history.length > 10) {
      history.removeRange(10, history.length);
    }
    
    await prefs.setStringList(_historyKey, history.map((e) => jsonEncode(e)).toList());
    readingHistoryRevision.value++;
  }

  Future<List<Map<String, dynamic>>> getReadingHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final historyJson = prefs.getStringList(_historyKey) ?? [];
    return historyJson.map((e) => jsonDecode(e) as Map<String, dynamic>).toList();
  }

  Future<void> removeHistory(String mangaId) async {
    final prefs = await SharedPreferences.getInstance();
    final historyJson = prefs.getStringList(_historyKey) ?? [];
    final history = historyJson.map((e) => jsonDecode(e) as Map<String, dynamic>).toList();
    
    history.removeWhere((h) => h['manga']['id'] == mangaId);
    await prefs.setStringList(_historyKey, history.map((e) => jsonEncode(e)).toList());
    readingHistoryRevision.value++;
  }

  // ── Like Functionality ──────────────────────────────────────────────

  Future<void> toggleLike(Manga manga) async {
    final prefs = await SharedPreferences.getInstance();
    final likedJson = prefs.getStringList(_likedKey) ?? [];

    final index = likedJson.indexWhere((j) {
      final m = jsonDecode(j) as Map<String, dynamic>;
      return m['id'] == manga.id;
    });

    if (index != -1) {
      likedJson.removeAt(index);
    } else {
      likedJson.add(jsonEncode(manga.toJson()));
    }

    await prefs.setStringList(_likedKey, likedJson);
  }

  Future<bool> isLiked(String id) async {
    final prefs = await SharedPreferences.getInstance();
    final likedJson = prefs.getStringList(_likedKey) ?? [];
    return likedJson.any((j) {
      final m = jsonDecode(j) as Map<String, dynamic>;
      return m['id'] == id;
    });
  }

  Future<List<Manga>> getLikedManga() async {
    final prefs = await SharedPreferences.getInstance();
    final likedJson = prefs.getStringList(_likedKey) ?? [];
    return likedJson.map((j) => Manga.fromJson(jsonDecode(j))).toList();
  }

  // ── Available Tags ──────────────────────────────────────────────────

  static const List<String> availableTags = [
    'Action', 'Adventure', 'Comedy', 'Cooking', 'Doujinshi', 'Drama',
    'Ecchi', 'Fantasy', 'Gender Bender', 'Harem', 'Historical',
    'Horror', 'Isekai', 'Josei', 'Lolicon', 'Martial Arts', 'Mature',
    'Mecha', 'Medical', 'Music', 'Mystery', 'One Shot', 'Psychological',
    'Romance', 'School Life', 'Sci-Fi', 'Seinen', 'Shotacon', 'Shoujo',
    'Shoujo Ai', 'Shounen', 'Shounen Ai', 'Slice of Life', 'Smut',
    'Sports', 'Supernatural', 'Tragedy', 'Yaoi', 'Yuri',
  ];
}
