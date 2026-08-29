import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';

class SubtitleCatEntry {
  final String code;
  final String label;
  final String url;
  final bool isTranslated;
  final String origUrl;
  final String baseName;

  const SubtitleCatEntry({
    required this.code,
    required this.label,
    required this.url,
    this.isTranslated = false,
    this.origUrl = '',
    this.baseName = '',
  });
}

/// SubtitleCat scraper & On-the-Fly Google Translation Engine.
///
/// Scrapes subtitlecat.com:
///   - Search:   `https://www.subtitlecat.com/index.php?search=<query>`
///   - Detail:   `https://www.subtitlecat.com/subs/<id>/<name>.html`
///   - Direct download: `<a id="download_<lang>" href="/subs/<id>/<name>-<lang>.srt">`
///   - Missing languages: Translate the original `.srt` on the fly via Google Translate
///     (`translate.googleapis.com/translate_a/single?client=gtx&sl=auto&tl=<lang>&dt=t&q=<text>`)
///     with bounded concurrency and fallback.
class SubtitleCatService {
  SubtitleCatService._();
  static final SubtitleCatService instance = SubtitleCatService._();

  static const String _origin = 'https://www.subtitlecat.com';
  static const Map<String, String> _hdrs = {
    'User-Agent':
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
        '(KHTML, like Gecko) Chrome/127.0.0.0 Safari/537.36',
    'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
    'Accept-Language': 'en-US,en;q=0.9',
  };

  final HttpClient _httpClient = HttpClient()
    ..connectionTimeout = const Duration(seconds: 15);

  // ── In-memory caches ──────────────────────────────────────────────────────
  final Map<String, List<_SearchHit>> _searchCache = {};
  final Map<String, _DetailPage> _detailCache = {};
  final Map<String, String> _translationCache = {}; // key = origUrl|lang
  final Map<String, Future<String>> _translationInflight = {};

  // ── Public API ────────────────────────────────────────────────────────────

  /// Build search query:
  /// Movies: "Title Year" e.g. "Inception 2010"
  /// Shows:  "Title SxxEyy" e.g. "The Walking Dead S02E12"
  static String buildQuery({
    required String title,
    int? year,
    int? season,
    int? episode,
  }) {
    final cleanTitle = title.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (season != null && episode != null) {
      final s = season.toString().padLeft(2, '0');
      final e = episode.toString().padLeft(2, '0');
      return '$cleanTitle S${s}E$e';
    }
    if (year != null && year > 0) return '$cleanTitle $year';
    return cleanTitle;
  }

  /// Perform a search on SubtitleCat and extract all direct and translatable subtitles.
  Future<List<SubtitleCatEntry>> searchAndExtract({
    required String title,
    int? year,
    int? season,
    int? episode,
    int maxResults = 8,
  }) async {
    final query = buildQuery(
      title: title,
      year: year,
      season: season,
      episode: episode,
    );

    try {
      final hits = await _search(query);
      if (hits.isEmpty) return [];

      final picks = hits.take(maxResults).toList();
      final List<SubtitleCatEntry> out = [];
      final Set<String> seenDirect = {};
      final Set<String> translatedLangs = {};

      final details = await Future.wait(picks.map((h) async {
        try {
          return await _fetchDetail(h.detailUrl);
        } catch (e) {
          if (kDebugMode) debugPrint('[SubtitleCat] detail page failed (${h.detailUrl}): $e');
          return null;
        }
      }));

      for (var i = 0; i < details.length; i++) {
        final detail = details[i];
        if (detail == null) continue;

        // 1. Directly available subtitles
        for (final ln in detail.directLanguages) {
          if (!seenDirect.add(ln.url)) continue;
          out.add(SubtitleCatEntry(
            code: ln.code,
            label: ln.label,
            url: ln.url,
            isTranslated: false,
            baseName: detail.baseName,
          ));
        }

        // 2. On-the-fly translatable languages
        for (final ln in detail.translatableLanguages) {
          if (translatedLangs.contains(ln.code)) continue;
          if (detail.directLanguages.any((d) => d.code == ln.code)) continue;
          translatedLangs.add(ln.code);

          final origUrl = '$_origin${detail.folder}${detail.origFilename}';
          out.add(SubtitleCatEntry(
            code: ln.code,
            label: ln.label,
            url: origUrl,
            isTranslated: true,
            origUrl: origUrl,
            baseName: detail.baseName,
          ));
        }
      }

      return out;
    } catch (e) {
      if (kDebugMode) debugPrint('[SubtitleCat] searchAndExtract error: $e');
      return [];
    }
  }

  /// Translate the original SRT at [origUrl] into [targetLang] and return the
  /// full assembled SRT string.
  Future<String> translateSrt({
    required String origUrl,
    required String targetLang,
  }) async {
    final key = '$origUrl|$targetLang';
    final cached = _translationCache[key];
    if (cached != null) return cached;

    final inflight = _translationInflight[key];
    if (inflight != null) return inflight;

    final fut = _translateSrtInternal(origUrl: origUrl, targetLang: targetLang);
    _translationInflight[key] = fut;
    try {
      final res = await fut;
      _translationCache[key] = res;
      return res;
    } finally {
      _translationInflight.remove(key);
    }
  }

  // ── Internal: Search ──────────────────────────────────────────────────────

  Future<List<_SearchHit>> _search(String query) async {
    final cached = _searchCache[query];
    if (cached != null) return cached;

    final url = Uri.parse('$_origin/index.php')
        .replace(queryParameters: {'search': query});

    final req = await _httpClient.getUrl(url);
    _hdrs.forEach((k, v) => req.headers.set(k, v));
    final res = await req.close();
    if (res.statusCode != 200) {
      throw HttpException('SubtitleCat search failed with status ${res.statusCode}');
    }
    final html = await res.transform(utf8.decoder).join();
    final hits = _parseSearchResults(html);
    _searchCache[query] = hits;
    return hits;
  }

  static List<_SearchHit> _parseSearchResults(String html) {
    final re = RegExp(
      r'<a\s+href="(subs/(\d+)/([^"]+\.html))"[^>]*>([^<]*)</a>',
      caseSensitive: false,
    );
    final out = <_SearchHit>[];
    final seen = <String>{};
    for (final m in re.allMatches(html)) {
      final relPath = m.group(1)!;
      if (!seen.add(relPath)) continue;
      out.add(_SearchHit(
        detailUrl: '$_origin/$relPath',
        title: _stripHtml(m.group(4) ?? ''),
      ));
    }
    return out;
  }

  // ── Internal: Detail Page ─────────────────────────────────────────────────

  Future<_DetailPage> _fetchDetail(String detailUrl) async {
    final cached = _detailCache[detailUrl];
    if (cached != null) return cached;

    final req = await _httpClient.getUrl(Uri.parse(detailUrl));
    _hdrs.forEach((k, v) => req.headers.set(k, v));
    final res = await req.close();
    if (res.statusCode != 200) {
      throw HttpException('SubtitleCat detail failed with status ${res.statusCode}');
    }
    final html = await res.transform(utf8.decoder).join();
    final parsed = _parseDetailPage(html);
    _detailCache[detailUrl] = parsed;
    return parsed;
  }

  static _DetailPage _parseDetailPage(String html) {
    // 1. Direct downloads
    final dlRe = RegExp(
      r'<a\s+id="download_([A-Za-z0-9-]+)"[^>]*href="(/subs/\d+/[^"]+\.srt)"',
      caseSensitive: false,
    );
    final directs = <_LangEntry>[];
    final directCodes = <String>{};
    for (final m in dlRe.allMatches(html)) {
      final code = m.group(1)!;
      final href = m.group(2)!;
      final norm = _normalizeLang(code);
      directs.add(_LangEntry(
        code: norm,
        label: _languageLabel(code),
        url: '$_origin$href',
      ));
      directCodes.add(norm);
    }

    // 2. Translatable languages
    final trRe = RegExp(
      r"translate_from_server_folder\(\s*'([^']+)'\s*,\s*'([^']+)'\s*,\s*'([^']+)'\s*\)",
      caseSensitive: false,
    );
    final translatables = <_LangEntry>[];
    String folder = '';
    String origFilename = '';
    for (final m in trRe.allMatches(html)) {
      final code = m.group(1)!;
      origFilename = m.group(2)!;
      folder = m.group(3)!;
      final norm = _normalizeLang(code);
      if (directCodes.contains(norm)) continue;
      translatables.add(_LangEntry(
        code: norm,
        label: _languageLabel(code),
      ));
    }

    // Fallback derive folder / filename if not matched in JS
    if (folder.isEmpty && directs.isNotEmpty) {
      final href = Uri.parse(directs.first.url).path;
      final lastSlash = href.lastIndexOf('/');
      folder = '${href.substring(0, lastSlash)}/';
      final fname = href.substring(lastSlash + 1);
      final dashLang = RegExp(r'-([A-Za-z0-9-]+)\.srt$');
      final base = fname.replaceFirst(dashLang, '');
      origFilename = '$base-orig.srt';
    }

    final baseName = origFilename.replaceFirst(RegExp(r'-orig\.srt$'), '');
    return _DetailPage(
      directLanguages: directs,
      translatableLanguages: translatables,
      folder: folder,
      origFilename: origFilename,
      baseName: baseName,
    );
  }

  // ── Internal: Translation Engine ──────────────────────────────────────────

  Future<String> _translateSrtInternal({
    required String origUrl,
    required String targetLang,
  }) async {
    final req = await _httpClient.getUrl(Uri.parse(origUrl));
    _hdrs.forEach((k, v) => req.headers.set(k, v));
    final res = await req.close();
    if (res.statusCode != 200) {
      throw HttpException('SubtitleCat orig file failed with status ${res.statusCode}');
    }

    final oBytes = await res.fold<List<int>>([], (p, e) => p..addAll(e));
    final body = utf8.decode(oBytes, allowMalformed: true);

    final srcLines = const LineSplitter().convert(body);
    final translated = List<String>.filled(srcLines.length, '');

    const int charsPerBatch = 500;
    final List<String> batches = [];
    final List<List<int>> linesInBatch = [];

    final numRe = RegExp(r'^[0-9 \r]*$');
    final tsRe = RegExp(r'^[0-9,: ]*-->[0-9,: \r]*$');

    String curBatch = '';
    int curChars = 0;
    List<int> curIndices = [];

    void flush() {
      if (curIndices.isEmpty && curBatch.isEmpty) return;
      batches.add(curBatch);
      linesInBatch.add(curIndices);
      curBatch = '';
      curChars = 0;
      curIndices = [];
    }

    for (var i = 0; i < srcLines.length; i++) {
      final line = srcLines[i];
      if (numRe.hasMatch(line) || tsRe.hasMatch(line)) {
        translated[i] = line;
        continue;
      }
      final cleaned = line
          .replaceAll(RegExp(r'<font[^>]*>', caseSensitive: false), '')
          .replaceAll(RegExp(r'</font>', caseSensitive: false), '')
          .replaceAll('&', 'and');
      if (curChars + cleaned.length + 1 < charsPerBatch) {
        if (curBatch.isEmpty) {
          curBatch = cleaned;
        } else {
          curBatch = '$curBatch\n$cleaned';
        }
        curChars += cleaned.length + 1;
        curIndices.add(i);
      } else {
        flush();
        curBatch = cleaned;
        curChars = cleaned.length + 1;
        curIndices.add(i);
      }
    }
    flush();

    if (kDebugMode) {
      debugPrint(
        '[SubtitleCat] Translating SRT (${srcLines.length} lines, '
        '${batches.length} chunks) → $targetLang',
      );
    }

    // Process batches with bounded concurrency (8 workers)
    const int parallel = 8;
    int nextIndex = 0;

    Future<void> worker() async {
      while (true) {
        final b = nextIndex;
        if (b >= batches.length) return;
        nextIndex++;
        final batch = batches[b];
        final indices = linesInBatch[b];
        if (indices.isEmpty) continue;
        try {
          final translatedLines = await _translateBatch(batch, targetLang);
          if (translatedLines.length == indices.length) {
            for (var k = 0; k < indices.length; k++) {
              translated[indices[k]] = translatedLines[k];
            }
          } else {
            // Mismatch fallback: translate line-by-line
            final origPieces = batch.split('\n');
            for (var k = 0; k < indices.length; k++) {
              final src = k < origPieces.length ? origPieces[k] : '';
              if (src.trim().isEmpty) {
                translated[indices[k]] = src;
                continue;
              }
              try {
                final one = await _translateBatch(src, targetLang);
                translated[indices[k]] = one.isNotEmpty ? one.join('\n') : src;
              } catch (_) {
                translated[indices[k]] = src;
              }
            }
          }
        } catch (e) {
          if (kDebugMode) debugPrint('[SubtitleCat] Batch $b failed: $e');
          final origPieces = batch.split('\n');
          for (var k = 0; k < indices.length; k++) {
            translated[indices[k]] = k < origPieces.length ? origPieces[k] : '';
          }
        }
      }
    }

    await Future.wait(List.generate(parallel, (_) => worker()));
    return '${translated.join('\n')}\n';
  }

  Future<List<String>> _translateBatch(String text, String tl) async {
    final uri = Uri.parse('https://translate.googleapis.com/translate_a/single')
        .replace(queryParameters: {
      'client': 'gtx',
      'sl': 'auto',
      'tl': tl,
      'dt': 't',
      'q': text,
    });

    final req = await _httpClient.getUrl(uri);
    req.headers.set('User-Agent',
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/127.0.0.0 Safari/537.36');
    req.headers.set('Accept', '*/*');
    final res = await req.close();
    if (res.statusCode != 200) {
      throw HttpException('Google Translate GTX failed with status ${res.statusCode}');
    }

    final body = await res.transform(utf8.decoder).join();
    final dynamic root = json.decode(body);
    if (root is! List || root.isEmpty || root[0] is! List) return const [];
    final segments = root[0] as List;
    final buf = StringBuffer();
    for (final seg in segments) {
      if (seg is List && seg.isNotEmpty && seg[0] is String) {
        buf.write(seg[0] as String);
      }
    }
    return buf.toString().split('\n');
  }

  // ── Helpers & Language Codes ──────────────────────────────────────────────

  static String _stripHtml(String s) =>
      s.replaceAll(RegExp(r'<[^>]+>'), '').trim();

  static String _normalizeLang(String code) {
    final c = code.toLowerCase();
    const remap = {'iw': 'he', 'jw': 'jv', 'in': 'id'};
    return remap[c] ?? c;
  }

  static String _languageLabel(String code) {
    const map = {
      'af': 'Afrikaans', 'ak': 'Akan', 'sq': 'Albanian', 'am': 'Amharic',
      'ar': 'Arabic', 'hy': 'Armenian', 'az': 'Azerbaijani', 'eu': 'Basque',
      'be': 'Belarusian', 'bem': 'Bemba', 'bn': 'Bengali', 'bh': 'Bihari',
      'bs': 'Bosnian', 'br': 'Breton', 'bg': 'Bulgarian', 'km': 'Cambodian',
      'ca': 'Catalan', 'ceb': 'Cebuano', 'chr': 'Cherokee', 'ny': 'Chichewa',
      'zh-cn': 'Chinese (S)', 'zh-tw': 'Chinese (T)', 'co': 'Corsican',
      'hr': 'Croatian', 'cs': 'Czech', 'da': 'Danish', 'nl': 'Dutch',
      'en': 'English', 'eo': 'Esperanto', 'et': 'Estonian', 'ee': 'Ewe',
      'fo': 'Faroese', 'tl': 'Filipino', 'fi': 'Finnish', 'fr': 'French',
      'fy': 'Frisian', 'gaa': 'Ga', 'gl': 'Galician', 'ka': 'Georgian',
      'de': 'German', 'el': 'Greek', 'gn': 'Guarani', 'gu': 'Gujarati',
      'ht': 'Haitian', 'ha': 'Hausa', 'haw': 'Hawaiian', 'iw': 'Hebrew',
      'he': 'Hebrew', 'hi': 'Hindi', 'hmn': 'Hmong', 'hu': 'Hungarian',
      'is': 'Icelandic', 'ig': 'Igbo', 'id': 'Indonesian', 'in': 'Indonesian',
      'ia': 'Interlingua', 'ga': 'Irish', 'it': 'Italian', 'ja': 'Japanese',
      'jw': 'Javanese', 'jv': 'Javanese', 'kn': 'Kannada', 'kk': 'Kazakh',
      'rw': 'Kinyarwanda', 'rn': 'Kirundi', 'kg': 'Kongo', 'ko': 'Korean',
      'kri': 'Krio', 'ku': 'Kurdish', 'ckb': 'Kurdish (Sorani)', 'ky': 'Kyrgyz',
      'lo': 'Laothian', 'la': 'Latin', 'lv': 'Latvian', 'ln': 'Lingala',
      'lt': 'Lithuanian', 'loz': 'Lozi', 'lg': 'Luganda', 'ach': 'Luo',
      'lb': 'Luxembourgish', 'mk': 'Macedonian', 'mg': 'Malagasy',
      'ms': 'Malay', 'ml': 'Malayalam', 'mt': 'Maltese', 'mi': 'Maori',
      'mr': 'Marathi', 'mfe': 'Mauritian Creole', 'mo': 'Moldavian',
      'mn': 'Mongolian', 'sr-me': 'Montenegrin', 'my': 'Burmese',
      'ne': 'Nepali', 'pcm': 'Nigerian Pidgin', 'nso': 'Northern Sotho',
      'no': 'Norwegian', 'nn': 'Norwegian Nynorsk', 'oc': 'Occitan',
      'or': 'Oriya', 'om': 'Oromo', 'ps': 'Pashto', 'fa': 'Persian',
      'pl': 'Polish', 'pt': 'Portuguese', 'pt-br': 'Portuguese (BR)',
      'pt-pt': 'Portuguese (PT)', 'pa': 'Punjabi', 'qu': 'Quechua',
      'ro': 'Romanian', 'rm': 'Romansh', 'nyn': 'Runyakitara', 'ru': 'Russian',
      'gd': 'Scots Gaelic', 'sr': 'Serbian', 'sh': 'Serbo-Croatian',
      'st': 'Sesotho', 'tn': 'Setswana', 'crs': 'Seychellois Creole',
      'sn': 'Shona', 'sd': 'Sindhi', 'si': 'Sinhalese', 'sk': 'Slovak',
      'sl': 'Slovenian', 'so': 'Somali', 'es': 'Spanish',
      'es-419': 'Spanish (LatAm)', 'su': 'Sundanese', 'sw': 'Swahili',
      'sv': 'Swedish', 'tg': 'Tajik', 'ta': 'Tamil', 'tt': 'Tatar',
      'te': 'Telugu', 'th': 'Thai', 'ti': 'Tigrinya', 'to': 'Tonga',
      'lua': 'Tshiluba', 'tum': 'Tumbuka', 'tr': 'Turkish', 'tk': 'Turkmen',
      'tw': 'Twi', 'ug': 'Uighur', 'uk': 'Ukrainian', 'ur': 'Urdu',
      'uz': 'Uzbek', 'vi': 'Vietnamese', 'cy': 'Welsh', 'wo': 'Wolof',
      'xh': 'Xhosa', 'yi': 'Yiddish', 'yo': 'Yoruba', 'zu': 'Zulu',
    };
    final c = code.toLowerCase();
    return map[c] ?? code.toUpperCase();
  }
}

class _SearchHit {
  final String detailUrl;
  final String title;
  _SearchHit({required this.detailUrl, required this.title});
}

class _LangEntry {
  final String code;
  final String label;
  final String url;
  _LangEntry({required this.code, required this.label, this.url = ''});
}

class _DetailPage {
  final List<_LangEntry> directLanguages;
  final List<_LangEntry> translatableLanguages;
  final String folder;
  final String origFilename;
  final String baseName;
  _DetailPage({
    required this.directLanguages,
    required this.translatableLanguages,
    required this.folder,
    required this.origFilename,
    required this.baseName,
  });
}
